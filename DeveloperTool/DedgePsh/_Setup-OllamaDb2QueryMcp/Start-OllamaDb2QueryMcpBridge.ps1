<#
.SYNOPSIS
    Ensures the local ollama-mcp-bridge process is running for DB2 MCP access.

.DESCRIPTION
    Starts the local bridge only if it is not already running. Intended for
    manual use and scheduled-task execution after reboot/logon.

.PARAMETER BridgePort
    Local bridge port. Default: 8000

.EXAMPLE
    pwsh.exe -NoProfile -File Start-OllamaDb2QueryMcpBridge.ps1
#>
[CmdletBinding()]
param(
    [int]$BridgePort = 8000
)

Import-Module GlobalFunctions -Force
$ErrorActionPreference = 'Stop'

$bridgeRoot = Join-Path $env:USERPROFILE '.ollama-db2-bridge'
$venvPath = Join-Path $bridgeRoot 'venv'
$bridgeExe = Join-Path $venvPath 'Scripts\ollama-mcp-bridge.exe'
$bridgeConfigPath = Join-Path $bridgeRoot 'mcp-config.json'
$bridgeLogPath = Join-Path $bridgeRoot 'bridge.log'
$bridgeErrPath = Join-Path $bridgeRoot 'bridge.err.log'

if (-not (Test-Path -LiteralPath $bridgeExe)) {
    Write-LogMessage "Bridge executable not found: $($bridgeExe). Run Setup-OllamaDb2QueryMcp.ps1 first." -Level ERROR
    throw "Bridge executable missing"
}

if (-not (Test-Path -LiteralPath $bridgeConfigPath)) {
    Write-LogMessage "Bridge config not found: $($bridgeConfigPath). Run Setup-OllamaDb2QueryMcp.ps1 first." -Level ERROR
    throw "Bridge config missing"
}

$alreadyRunning = Get-CimInstance Win32_Process |
    Where-Object { $_.Name -like 'ollama-mcp-bridge*' -and $_.CommandLine -like "*$($bridgeConfigPath)*" } |
    Select-Object -First 1

if ($alreadyRunning) {
    Write-LogMessage "DB2 bridge already running (PID: $($alreadyRunning.ProcessId))." -Level INFO
    return
}

try {
    Start-Process -FilePath $bridgeExe `
        -ArgumentList @('--config', $bridgeConfigPath, '--port', $BridgePort.ToString()) `
        -WindowStyle Hidden `
        -RedirectStandardOutput $bridgeLogPath `
        -RedirectStandardError $bridgeErrPath | Out-Null

    Write-LogMessage "Started DB2 bridge on http://127.0.0.1:$($BridgePort)" -Level INFO
}
catch {
    Write-LogMessage "Failed to start DB2 bridge process." -Level ERROR -Exception $_
    throw
}
