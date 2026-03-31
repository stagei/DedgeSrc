<#
.SYNOPSIS
    Verify Cursor RAG setup (via AiDocNew API).
#>
[CmdletBinding()]
param(
    [string]$ApiBaseUrl = 'http://dedge-server/AiDocNew'
)

Import-Module GlobalFunctions -Force

$ErrorActionPreference = 'Stop'
$mcpJson = Join-Path $env:USERPROFILE '.cursor\mcp.json'
$proxyPy = Join-Path $env:USERPROFILE '.cursor\rag-proxy\server_mcp_proxy.py'

Write-LogMessage "[1/6] API health..." -Level INFO
try {
    $null = Invoke-RestMethod -Uri "$($ApiBaseUrl)/health" -TimeoutSec 5
    Write-LogMessage "       OK" -Level INFO
} catch { Write-LogMessage "       FAILED: $($_.Exception.Message)" -Level ERROR }

Write-LogMessage "[2/6] Proxy script..." -Level INFO
if (Test-Path -LiteralPath $proxyPy) { Write-LogMessage "       OK" -Level INFO }
else { Write-LogMessage "       MISSING" -Level ERROR }

Write-LogMessage "[3/6] Venv health..." -Level INFO
$venvPython = Join-Path $env:USERPROFILE '.cursor\rag-proxy\.venv\Scripts\python.exe'
$venvCfg    = Join-Path $env:USERPROFILE '.cursor\rag-proxy\.venv\pyvenv.cfg'
if (-not (Test-Path -LiteralPath $venvPython)) {
    Write-LogMessage "       FAIL — venv python.exe missing" -Level ERROR
} elseif (-not (Test-Path -LiteralPath $venvCfg)) {
    Write-LogMessage "       FAIL — pyvenv.cfg missing (broken venv). Re-run Setup-RagMcpCursor.ps1" -Level ERROR
} else {
    $importCheck = & $venvPython -c "from mcp.server.fastmcp import FastMCP; print('OK')" 2>&1
    if ($importCheck -match 'OK') {
        Write-LogMessage "       OK — venv works, mcp importable" -Level INFO
    } else {
        Write-LogMessage "       FAIL — mcp import error: $($importCheck)" -Level ERROR
    }
}

Write-LogMessage "[4/6] Remote RAG ports (direct HTTP)..." -Level INFO
foreach ($port in @(8484, 8485, 8486)) {
    $portUrl = "http://dedge-server:$($port)/"
    try {
        $null = Invoke-WebRequest -Uri $portUrl -UseBasicParsing -TimeoutSec 5 -ErrorAction Stop
        Write-LogMessage "       Port $($port): OK" -Level INFO
    } catch {
        $code = $_.Exception.Response.StatusCode.value__
        if ($code) {
            Write-LogMessage "       Port $($port): Reachable (HTTP $($code))" -Level INFO
        } else {
            Write-LogMessage "       Port $($port): UNREACHABLE" -Level ERROR
        }
    }
}

Write-LogMessage "[5/6] mcp.json RAG entries..." -Level INFO
if (Test-Path -LiteralPath $mcpJson) {
    $config = Get-Content -LiteralPath $mcpJson -Raw | ConvertFrom-Json
    $ragEntries = $config.mcpServers.PSObject.Properties | Where-Object { $_.Value.args -and ($_.Value.args -match 'server_mcp_proxy') }
    Write-LogMessage "       Found $($ragEntries.Count) RAG MCP entries" -Level INFO
} else { Write-LogMessage "       mcp.json not found" -Level ERROR }

Write-LogMessage "[6/6] Remote RAG services..." -Level INFO
try {
    $services = Invoke-RestMethod -Uri "$($ApiBaseUrl)/api/Rags/setup/services" -TimeoutSec 10
    foreach ($svc in $services) {
        $level = if ($svc.status -eq 'running') { 'INFO' } else { 'WARN' }
        Write-LogMessage "       $($svc.name): $($svc.status) (port $($svc.port))" -Level $level
    }
} catch { Write-LogMessage "       Could not check services: $($_.Exception.Message)" -Level ERROR }

$result = [PSCustomObject]@{
    Script  = $MyInvocation.MyCommand.Name
    Status  = "OK"
    Message = "RAG MCP checks completed"
}
Write-LogMessage "RESULT: $($result.Status) - $($result.Message)" -Level INFO
Write-Output $result

