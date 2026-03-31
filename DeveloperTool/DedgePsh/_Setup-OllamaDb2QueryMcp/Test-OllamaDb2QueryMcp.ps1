<#
.SYNOPSIS
    Verify local Ollama DB2 Query MCP bridge availability after restart.

.DESCRIPTION
    Validates that Setup-OllamaDb2QueryMcp configured everything correctly:
      - Profile marker exists
      - Bridge files/config exist
      - Bridge process is running (or can be auto-started)
      - Bridge health endpoint responds
      - Remote DB2 MCP endpoint responds

.PARAMETER RemoteHost
    Hostname for the remote DB2 MCP server.

.PARAMETER BridgePort
    Local bridge port.

.PARAMETER AutoStartBridge
    Start bridge automatically if not already running.

.EXAMPLE
    pwsh.exe -NoProfile -File Test-OllamaDb2QueryMcp.ps1
#>
[CmdletBinding()]
param(
    [string]$RemoteHost = 'dedge-server',
    [int]$BridgePort = 8000,
    [switch]$AutoStartBridge
)

Import-Module GlobalFunctions -Force
$ErrorActionPreference = 'Stop'

$bridgeRoot = Join-Path $env:USERPROFILE '.ollama-db2-bridge'
$venvPath = Join-Path $bridgeRoot 'venv'
$bridgeExe = Join-Path $venvPath 'Scripts\ollama-mcp-bridge.exe'
$bridgeConfigPath = Join-Path $bridgeRoot 'mcp-config.json'
$bridgeLogPath = Join-Path $bridgeRoot 'bridge.log'
$bridgeErrPath = Join-Path $bridgeRoot 'bridge.err.log'
$profilePath = $PROFILE.CurrentUserAllHosts
$markerBegin = '# >>> Setup-OllamaDb2QueryMcp >>>'
$remoteMcpUrl = "http://$($RemoteHost)/CursorDb2McpServer/"
$healthUrl = "http://127.0.0.1:$($BridgePort)/health"

Write-LogMessage "Starting Setup-OllamaDb2QueryMcp verification" -Level INFO

if (-not (Test-Path -LiteralPath $profilePath)) {
    Write-LogMessage "PowerShell profile not found: $($profilePath)" -Level ERROR
    throw "Profile missing"
}

$profileContent = Get-Content -LiteralPath $profilePath -Raw
if ($profileContent -notmatch [regex]::Escape($markerBegin)) {
    Write-LogMessage "Setup marker not found in profile. Run Setup-OllamaDb2QueryMcp.ps1 first." -Level ERROR
    throw "Profile marker missing"
}
Write-LogMessage "Profile marker found" -Level INFO

foreach ($requiredPath in @($bridgeRoot, $bridgeExe, $bridgeConfigPath)) {
    if (-not (Test-Path -LiteralPath $requiredPath)) {
        Write-LogMessage "Required path is missing: $($requiredPath)" -Level ERROR
        throw "Missing required path"
    }
}
Write-LogMessage "Bridge files found" -Level INFO

$config = Get-Content -LiteralPath $bridgeConfigPath -Raw | ConvertFrom-Json
$configuredUrl = $config.mcpServers.'db2-query'.url
if ([string]::IsNullOrWhiteSpace($configuredUrl)) {
    Write-LogMessage "db2-query URL missing in bridge config: $($bridgeConfigPath)" -Level ERROR
    throw "Bridge config invalid"
}
Write-LogMessage "Bridge config db2-query URL: $($configuredUrl)" -Level INFO

$bridgeProc = Get-CimInstance Win32_Process |
    Where-Object { $_.Name -like 'ollama-mcp-bridge*' -and $_.CommandLine -like "*$($bridgeConfigPath)*" } |
    Select-Object -First 1

if (-not $bridgeProc -and $AutoStartBridge) {
    Write-LogMessage "Bridge is not running; starting it automatically" -Level WARN
    Start-Process -FilePath $bridgeExe `
        -ArgumentList @('--config', $bridgeConfigPath, '--port', $BridgePort.ToString()) `
        -WindowStyle Hidden `
        -RedirectStandardOutput $bridgeLogPath `
        -RedirectStandardError $bridgeErrPath | Out-Null

    Start-Sleep -Seconds 2
    $bridgeProc = Get-CimInstance Win32_Process |
        Where-Object { $_.Name -like 'ollama-mcp-bridge*' -and $_.CommandLine -like "*$($bridgeConfigPath)*" } |
        Select-Object -First 1
}

if ($bridgeProc) {
    Write-LogMessage "Bridge process is running (PID: $($bridgeProc.ProcessId))" -Level INFO
} else {
    Write-LogMessage "Bridge process is not running. Start it with Start-Db2Bridge." -Level WARN
}

try {
    $health = Invoke-RestMethod -Uri $healthUrl -TimeoutSec 10
    Write-LogMessage "Bridge health endpoint responded: $($health | ConvertTo-Json -Compress)" -Level INFO
} catch {
    Write-LogMessage "Bridge health check failed at $($healthUrl)" -Level ERROR -Exception $_
    throw
}

# Direct MCP check ensures the remote service is available from this machine.
$headers = @{ Accept = 'application/json, text/event-stream' }
$initBody = @{
    jsonrpc = '2.0'
    id = 1
    method = 'initialize'
    params = @{
        protocolVersion = '2024-11-05'
        capabilities = @{}
        clientInfo = @{ name = 'ollama-db2-test'; version = '1.0' }
    }
} | ConvertTo-Json -Depth 10

try {
    $initResp = Invoke-WebRequest -Uri $remoteMcpUrl -Method Post -Body $initBody -ContentType 'application/json' -Headers $headers -TimeoutSec 30
    if ($initResp.StatusCode -ge 200 -and $initResp.StatusCode -lt 300) {
        Write-LogMessage "Remote MCP initialize succeeded at $($remoteMcpUrl)" -Level INFO
    } else {
        Write-LogMessage "Remote MCP initialize returned status $($initResp.StatusCode)" -Level ERROR
        throw "Remote MCP unavailable"
    }
} catch {
    Write-LogMessage "Remote MCP check failed: $($remoteMcpUrl)" -Level ERROR -Exception $_
    throw
}

Write-LogMessage "Verification complete. Setup-OllamaDb2QueryMcp is available after restart." -Level INFO
