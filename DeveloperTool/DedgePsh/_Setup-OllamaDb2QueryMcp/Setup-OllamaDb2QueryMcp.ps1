<#
.SYNOPSIS
    Configure local Ollama to use the remote db2-query MCP server.

.DESCRIPTION
    Installs and configures ollama-mcp-bridge in a local Python virtual environment,
    writes a bridge MCP config that points to dedge-server, and adds helper
    functions to the PowerShell profile:

      - Start-Db2Bridge
      - Ask-Db2

.PARAMETER RemoteHost
    Hostname that serves CursorDb2McpServer over HTTP.

.PARAMETER BridgePort
    Local port used by ollama-mcp-bridge.

.PARAMETER Model
    Default Ollama model used by Ask-Db2.

.PARAMETER Remove
    Remove profile functions and local bridge folder.

.EXAMPLE
    pwsh.exe -NoProfile -File Setup-OllamaDb2QueryMcp.ps1

.EXAMPLE
    pwsh.exe -NoProfile -File Setup-OllamaDb2QueryMcp.ps1 -Model llama3.2

.EXAMPLE
    pwsh.exe -NoProfile -File Setup-OllamaDb2QueryMcp.ps1 -Remove
#>
[CmdletBinding()]
param(
    [string]$RemoteHost = 'dedge-server',
    [int]$BridgePort = 8000,
    [string]$Model = 'qwen2.5',
    [switch]$Remove
)

Import-Module GlobalFunctions -Force
$ErrorActionPreference = 'Stop'

$bridgeRoot = Join-Path $env:USERPROFILE '.ollama-db2-bridge'
$venvPath = Join-Path $bridgeRoot 'venv'
$venvPython = Join-Path $venvPath 'Scripts\python.exe'
$bridgeExe = Join-Path $venvPath 'Scripts\ollama-mcp-bridge.exe'
$bridgeConfigPath = Join-Path $bridgeRoot 'mcp-config.json'
$bridgeLogPath = Join-Path $bridgeRoot 'bridge.log'
$bridgeErrPath = Join-Path $bridgeRoot 'bridge.err.log'
$profilePath = $PROFILE.CurrentUserAllHosts
$markerBegin = '# >>> Setup-OllamaDb2QueryMcp >>>'
$markerEnd = '# <<< Setup-OllamaDb2QueryMcp <<<'
$db2McpUrl = "http://$($RemoteHost)/CursorDb2McpServer/"

function Get-ProfileContent {
    if (Test-Path -LiteralPath $profilePath) {
        return Get-Content -LiteralPath $profilePath -Raw
    }
    return ''
}

function Set-ProfileContent {
    param([string]$Content)

    $profileDir = Split-Path -Parent $profilePath
    if (-not (Test-Path -LiteralPath $profileDir)) {
        New-Item -ItemType Directory -Path $profileDir -Force | Out-Null
    }
    Set-Content -LiteralPath $profilePath -Value $Content -Encoding utf8
}

function Remove-ProfileBlock {
    $content = Get-ProfileContent
    $startIdx = $content.IndexOf($markerBegin)
    if ($startIdx -lt 0) { return $content }

    $endIdx = $content.IndexOf($markerEnd, $startIdx)
    if ($endIdx -lt 0) { return $content }

    $endIdx = $endIdx + $markerEnd.Length
    while ($endIdx -lt $content.Length -and ($content[$endIdx] -eq "`r" -or $content[$endIdx] -eq "`n")) {
        $endIdx++
    }

    return ($content.Substring(0, $startIdx) + $content.Substring($endIdx)).TrimEnd()
}

if ($Remove) {
    Write-LogMessage "Removing Setup-OllamaDb2QueryMcp profile functions and local bridge files" -Level INFO

    $cleaned = Remove-ProfileBlock
    Set-ProfileContent -Content $cleaned

    if (Test-Path -LiteralPath $bridgeRoot) {
        Remove-Item -LiteralPath $bridgeRoot -Recurse -Force
    }

    Write-LogMessage "Removed. Restart PowerShell to unload functions." -Level INFO
    return
}

Write-LogMessage "Preparing local Ollama + DB2 Query MCP bridge setup" -Level INFO

if (-not (Get-Command ollama -ErrorAction SilentlyContinue)) {
    Write-LogMessage "Ollama was not found in PATH. Install Ollama and rerun." -Level ERROR
    throw "Ollama not found"
}

$pythonCmd = Get-Command python -ErrorAction SilentlyContinue
if (-not $pythonCmd) {
    Write-LogMessage "Python was not found in PATH. Install Python 3.10+ and rerun." -Level ERROR
    throw "Python not found"
}

try {
    $pythonVersionOutput = & $pythonCmd.Source --version 2>&1
    Write-LogMessage "Detected Python: $($pythonVersionOutput)" -Level INFO
} catch {
    Write-LogMessage "Could not read Python version." -Level ERROR -Exception $_
    throw
}

if (-not (Test-Path -LiteralPath $bridgeRoot)) {
    New-Item -ItemType Directory -Path $bridgeRoot -Force | Out-Null
}

Write-LogMessage "Checking Ollama model availability for $($Model)" -Level INFO
try {
    $modelListRaw = ollama list 2>$null
    $modelExists = ($modelListRaw -match ("^" + [regex]::Escape($Model) + "\s"))
    if (-not $modelExists) {
        Write-LogMessage "Model $($Model) not found locally. Pulling model..." -Level WARN
        ollama pull $Model | Out-Null
    }
} catch {
    Write-LogMessage "Failed while checking or pulling Ollama model." -Level ERROR -Exception $_
    throw
}

if (-not (Test-Path -LiteralPath $venvPython)) {
    Write-LogMessage "Creating Python virtual environment at $($venvPath)" -Level INFO
    & $pythonCmd.Source -m venv $venvPath
}

Write-LogMessage "Installing ollama-mcp-bridge in the virtual environment" -Level INFO
& $venvPython -m pip install --upgrade pip | Out-Null
& $venvPython -m pip install --upgrade ollama-mcp-bridge | Out-Null

if (-not (Test-Path -LiteralPath $bridgeExe)) {
    Write-LogMessage "Bridge executable not found after install: $($bridgeExe)" -Level ERROR
    throw "ollama-mcp-bridge install failed"
}

$bridgeConfig = @{
    mcpServers = @{
        'db2-query' = @{
            url = $db2McpUrl
        }
    }
}
$bridgeConfig | ConvertTo-Json -Depth 10 | Set-Content -LiteralPath $bridgeConfigPath -Encoding utf8
Write-LogMessage "Wrote bridge config: $($bridgeConfigPath)" -Level INFO

$profileFunction = @"
$markerBegin
function Start-Db2Bridge {
    [CmdletBinding()]
    param(
        [int]`$Port = $BridgePort
    )

    Import-Module GlobalFunctions -Force

    `$bridgeRoot = Join-Path `$env:USERPROFILE '.ollama-db2-bridge'
    `$venvPath = Join-Path `$bridgeRoot 'venv'
    `$bridgeExe = Join-Path `$venvPath 'Scripts\ollama-mcp-bridge.exe'
    `$bridgeConfigPath = Join-Path `$bridgeRoot 'mcp-config.json'
    `$bridgeLogPath = Join-Path `$bridgeRoot 'bridge.log'
    `$bridgeErrPath = Join-Path `$bridgeRoot 'bridge.err.log'

    if (-not (Test-Path -LiteralPath `$bridgeExe)) {
        Write-LogMessage "Bridge executable not found: `$($bridgeExe)" -Level ERROR
        return
    }

    `$alreadyRunning = Get-CimInstance Win32_Process |
        Where-Object { `$_.Name -like 'ollama-mcp-bridge*' -and `$_.CommandLine -like "*`$bridgeConfigPath*" } |
        Select-Object -First 1

    if (`$alreadyRunning) {
        Write-LogMessage "DB2 bridge is already running (PID: `$(`$alreadyRunning.ProcessId))." -Level INFO
        return
    }

    Start-Process -FilePath `$bridgeExe `
        -ArgumentList @('--config', `$bridgeConfigPath, '--port', `$Port.ToString()) `
        -WindowStyle Hidden `
        -RedirectStandardOutput `$bridgeLogPath `
        -RedirectStandardError `$bridgeErrPath | Out-Null

    Write-LogMessage "Started DB2 bridge on http://127.0.0.1:`$(`$Port)" -Level INFO
}

function Ask-Db2 {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]`$Question,
        [string]`$Model = '$Model',
        [int]`$Port = $BridgePort
    )

    Import-Module GlobalFunctions -Force

    `$uri = "http://127.0.0.1:`$(`$Port)/api/chat"
    `$payload = @{
        model = `$Model
        stream = `$false
        messages = @(
            @{
                role = 'system'
                content = 'You are a DB2 assistant. For DB2 questions, call query_db2. Always prefer alias names (for example BASISTST). Ask for database alias if missing.'
            },
            @{
                role = 'user'
                content = `$Question
            }
        )
    }

    try {
        `$response = Invoke-RestMethod -Uri `$uri -Method Post -Body (`$payload | ConvertTo-Json -Depth 10) -ContentType 'application/json' -TimeoutSec 120
        if (`$response.message.content) {
            `$response.message.content
        } else {
            Write-LogMessage 'No response content from bridge.' -Level WARN
        }
    } catch {
        Write-LogMessage "Ask-Db2 failed. Is Start-Db2Bridge running?" -Level ERROR -Exception `$_
    }
}
$markerEnd
"@

$existingProfile = Get-ProfileContent
$cleanProfile = Remove-ProfileBlock
if ([string]::IsNullOrWhiteSpace($cleanProfile)) {
    Set-ProfileContent -Content $profileFunction.Trim()
} else {
    Set-ProfileContent -Content ($cleanProfile.TrimEnd() + "`r`n`r`n" + $profileFunction.Trim())
}

Write-LogMessage "Setup complete. Restart PowerShell, then run Start-Db2Bridge and Ask-Db2." -Level INFO
Write-LogMessage "DB2 MCP URL: $($db2McpUrl)" -Level INFO
