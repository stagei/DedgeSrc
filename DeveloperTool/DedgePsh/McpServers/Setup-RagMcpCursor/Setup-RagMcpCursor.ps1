<#
.SYNOPSIS
    Configure Cursor to use remote RAG doc servers (via AiDocNew API).
.PARAMETER ApiBaseUrl
    AiDocNew API base URL. Default: http://dedge-server/AiDocNew
.PARAMETER Revert
    Restore previous mcp.json backup.
.EXAMPLE
    pwsh.exe -File Setup-RagMcpCursor.ps1
#>
[CmdletBinding()]
param(
    [string]$ApiBaseUrl = 'http://dedge-server/AiDocNew',
    [switch]$Revert
)

$ErrorActionPreference = 'Stop'

Import-Module GlobalFunctions -Force

$proxyDir  = Join-Path $env:USERPROFILE '.cursor\rag-proxy'
$venvDir   = Join-Path $proxyDir '.venv'
$proxyPy   = Join-Path $proxyDir 'server_mcp_proxy.py'
$mcpJson   = Join-Path $env:USERPROFILE '.cursor\mcp.json'
$mcpBackup = Join-Path $env:USERPROFILE '.cursor\mcp.json.pre-rag-backup'

if ($Revert) {
    if (Test-Path -LiteralPath $mcpBackup) {
        Copy-Item -LiteralPath $mcpBackup -Destination $mcpJson -Force
        Write-LogMessage '[OK] Reverted mcp.json from backup. Restart Cursor.' -Level INFO
        $result = [PSCustomObject]@{
            Script  = $MyInvocation.MyCommand.Name
            Status  = "OK"
            Message = "Reverted mcp.json from backup"
        }
        Write-LogMessage "RESULT: $($result.Status) - $($result.Message)" -Level INFO
        Write-Output $result
    } else {
        Write-LogMessage "[WARN] No backup at $($mcpBackup)" -Level WARN
        $result = [PSCustomObject]@{
            Script  = $MyInvocation.MyCommand.Name
            Status  = "WARN"
            Message = "No backup at $($mcpBackup)"
        }
        Write-LogMessage "RESULT: $($result.Status) - $($result.Message)" -Level WARN
        Write-Output $result
    }
    return
}

Write-LogMessage "[1/5] Fetching RAG config from $($ApiBaseUrl)..." -Level INFO
$mcpConfig = Invoke-RestMethod -Uri "$($ApiBaseUrl)/api/Rags/setup/cursor-mcp" -TimeoutSec 10

if (-not $mcpConfig.mcpServers -or ($mcpConfig.mcpServers.PSObject.Properties | Measure-Object).Count -eq 0) {
    Write-LogMessage '[ERROR] No RAGs returned from API.' -Level ERROR
    exit 1
}

$ragNames = @($mcpConfig.mcpServers.PSObject.Properties.Name)
Write-LogMessage "       Found $($ragNames.Count) RAG(s): $($ragNames -join ', ')" -Level DEBUG

Write-LogMessage '[2/5] Finding Python...' -Level INFO
$pythonExe = $null
foreach ($ver in @('3.14', '3.13', '3.12', '3.11')) {
    try { $pythonExe = (py "-$ver" -c "import sys; print(sys.executable)" 2>$null) } catch {}
    if ($pythonExe -and (Test-Path -LiteralPath $pythonExe)) { break }
    $pythonExe = $null
}
if (-not $pythonExe) {
    $p = Get-Command python -ErrorAction SilentlyContinue
    if ($p -and $p.Source -notmatch 'WindowsApps') { $pythonExe = $p.Source }
}
if (-not $pythonExe) {
    Write-LogMessage '[ERROR] Python 3.11+ not found.' -Level ERROR
    exit 1
}
Write-LogMessage "       $($pythonExe)" -Level DEBUG

Write-LogMessage '[3/5] Checking venv...' -Level INFO
if (-not (Test-Path -LiteralPath $proxyDir)) { New-Item -ItemType Directory -Path $proxyDir -Force | Out-Null }
$venvPython = Join-Path $venvDir 'Scripts\python.exe'
$venvCfg    = Join-Path $venvDir 'pyvenv.cfg'

$needsRebuild = $false
if (-not (Test-Path -LiteralPath $venvPython)) {
    $needsRebuild = $true
    Write-LogMessage '       Venv python.exe missing — will create.' -Level DEBUG
} elseif (-not (Test-Path -LiteralPath $venvCfg)) {
    $needsRebuild = $true
    Write-LogMessage '       Venv broken (pyvenv.cfg missing) — will recreate.' -Level WARN
} else {
    $venvCheck = & $venvPython -c "import sys; print(sys.version)" 2>&1
    if ($LASTEXITCODE -ne 0) {
        $needsRebuild = $true
        Write-LogMessage "       Venv broken (python fails: $($venvCheck)) — will recreate." -Level WARN
    }
}

if ($needsRebuild) {
    if (Test-Path -LiteralPath $venvDir) {
        Write-LogMessage '       Removing broken venv...' -Level DEBUG
        Remove-Item -LiteralPath $venvDir -Recurse -Force
    }
    Write-LogMessage '       Creating venv...' -Level DEBUG
    & $pythonExe -m venv $venvDir
    if ($LASTEXITCODE -ne 0) { Write-LogMessage '[ERROR] venv creation failed.' -Level ERROR; exit 1 }
    & $venvPython -m pip install --upgrade pip --quiet 2>$null
    & $venvPython -m pip install --quiet 'mcp>=1.0.0'
    if ($LASTEXITCODE -ne 0) { Write-LogMessage '[ERROR] pip install mcp failed.' -Level ERROR; exit 1 }
    Write-LogMessage '       Venv created and mcp installed.' -Level INFO
} else {
    Write-LogMessage '       Venv OK, upgrading mcp...' -Level DEBUG
    & $venvPython -m pip install --upgrade --quiet 'mcp>=1.0.0' 2>$null
    Write-LogMessage '       Done.' -Level DEBUG
}

Write-LogMessage '[4/5] Writing proxy script...' -Level INFO
$proxyScript = Invoke-RestMethod -Uri "$($ApiBaseUrl)/api/Rags/setup/proxy-script" -TimeoutSec 10
$proxyScript.content | Set-Content -LiteralPath $proxyPy -Encoding utf8

Write-LogMessage '[5/5] Updating Cursor mcp.json...' -Level INFO
# Legacy RAG server names (from old AiDoc / Register-CursorRagMcp / Register-AllCursorRagMcp)
$legacyRagNames = @('db2-docs', 'visual-cobol-docs', 'Dedge-code')
$namesToRemove = @($ragNames) + @($legacyRagNames) | Select-Object -Unique
Write-LogMessage "       Removing old RAG config: $($namesToRemove -join ', ')" -Level DEBUG

$existingServers = [ordered]@{}
if (Test-Path -LiteralPath $mcpJson) {
    Copy-Item -LiteralPath $mcpJson -Destination $mcpBackup -Force
    try {
        $existing = Get-Content -LiteralPath $mcpJson -Raw | ConvertFrom-Json
        if ($existing.mcpServers) {
            foreach ($prop in $existing.mcpServers.PSObject.Properties) {
                if ($prop.Name -notin $namesToRemove) {
                    $existingServers[$prop.Name] = $prop.Value
                }
            }
        }
    } catch {}
}

$mcpServers = [ordered]@{}
foreach ($prop in $mcpConfig.mcpServers.PSObject.Properties) {
    $rag = $prop.Value
    $mcpServers[$prop.Name] = [ordered]@{
        command = $venvPython
        args    = @($proxyPy, '--rag', $prop.Name, '--remote-url', ($rag.args | Where-Object { $_ -match '^http' }))
        cwd     = $proxyDir
    }
}
foreach ($key in $existingServers.Keys) { $mcpServers[$key] = $existingServers[$key] }

$config = [ordered]@{ mcpServers = $mcpServers }
$config | ConvertTo-Json -Depth 10 | Set-Content -LiteralPath $mcpJson -Encoding utf8

Write-LogMessage "Done. Restart Cursor." -Level INFO

$result = [PSCustomObject]@{
    Script  = $MyInvocation.MyCommand.Name
    Status  = "OK"
    Message = "Registered RAG MCP servers in mcp.json"
}
Write-LogMessage "RESULT: $($result.Status) - $($result.Message)" -Level INFO
Write-Output $result
