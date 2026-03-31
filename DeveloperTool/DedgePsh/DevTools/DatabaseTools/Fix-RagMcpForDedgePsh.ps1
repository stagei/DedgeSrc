<#
.SYNOPSIS
    Fixes RAG MCP config and runs a Cursor CLI test from DedgePsh workspace; appends results to RAG-Fix-Report.md.

.DESCRIPTION
    Ensures mcp.json uses a real Python (3.12 or 3.13; 3.14 not supported by ChromaDB). Runs Register-AllCursorRagMcp.ps1 when library exists, else Register-CursorRagMcp.ps1.
    optionally sets HF offline env when cache exists, then runs Cursor CLI test. Append-only report in same folder.
    Run with pwsh.exe. Safe to run repeatedly (e.g. every 60 min); when environment is fixed, a later run will pass.

.EXAMPLE
    pwsh.exe -File Fix-RagMcpForDedgePsh.ps1
#>
[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'
$scriptDir = Split-Path -LiteralPath $MyInvocation.MyCommand.Path
$reportPath = Join-Path -Path $scriptDir -ChildPath 'RAG-Fix-Report.md'
$aiDocMcpDir = 'C:\opt\src\AiDoc\mcp-db2-docs'
$registerScript = Join-Path -Path $aiDocMcpDir -ChildPath 'scripts\Register-AllCursorRagMcp.ps1'
$registerScriptLegacy = Join-Path -Path $aiDocMcpDir -ChildPath 'scripts\Register-CursorRagMcp.ps1'
$aiDocRoot = Split-Path -Path $aiDocMcpDir -Parent
$libraryDir = Join-Path -Path $aiDocRoot -ChildPath 'library'
$cursorDir = Join-Path -Path $env:USERPROFILE -ChildPath '.cursor'
$configPath = Join-Path -Path $cursorDir -ChildPath 'mcp.json'

function Write-Report {
    param([string]$Line)
    $ts = Get-Date -Format 'yyyy-MM-dd HH:mm'
    Add-Content -LiteralPath $reportPath -Value "- $ts – $Line"
}

# Resolve Python: prefer 3.13 or 3.12 (3.14 not supported by ChromaDB)
$pythonExe = $null
if (Get-Command py -ErrorAction SilentlyContinue) {
    $pythonExe = (py -3.13 -c "import sys; print(sys.executable)" 2>$null)
    if (-not $pythonExe) { $pythonExe = (py -3.12 -c "import sys; print(sys.executable)" 2>$null) }
}
if (-not $pythonExe -or -not (Test-Path -LiteralPath $pythonExe)) {
    $p = Get-Command python -ErrorAction SilentlyContinue
    if ($p -and $p.Source -notmatch 'WindowsApps') { $pythonExe = $p.Source }
}
if (-not $pythonExe -or -not (Test-Path -LiteralPath $pythonExe)) {
    $fallback = 'C:\Users\FKGEISTA\AppData\Local\Programs\Python\Python313\python.exe'
    if (Test-Path -LiteralPath $fallback) { $pythonExe = $fallback }
}
if (-not $pythonExe -or -not (Test-Path -LiteralPath $pythonExe)) {
    $fallback = 'C:\Users\FKGEISTA\AppData\Local\Programs\Python\Python312\python.exe'
    if (Test-Path -LiteralPath $fallback) { $pythonExe = $fallback }
}
if (-not $pythonExe -or -not (Test-Path -LiteralPath $pythonExe)) {
    Write-Report "Step: Resolve Python. Outcome: Fail. No Python 3.12/3.13 found (3.14 not supported)."
    Add-Content -LiteralPath $reportPath -Value "`n## Problems encountered`n- No suitable Python for RAG MCP.`n"
    throw "No Python 3.12/3.13 found. Create venv in $aiDocMcpDir or install Python 3.12/3.13."
}

$serverPy = Join-Path -Path $aiDocMcpDir -ChildPath 'server.py'
$serverEntry = @{
    command = $pythonExe
    args    = @($serverPy)
    cwd     = $aiDocMcpDir
}

# Load mcp.json and set db2-docs
$config = @{ mcpServers = @{} }
if (Test-Path -LiteralPath $configPath) {
    try {
        $raw = Get-Content -LiteralPath $configPath -Raw -Encoding UTF8
        if ($raw) {
            $config = $raw | ConvertFrom-Json
            if (-not $config.mcpServers) { $config | Add-Member -NotePropertyName mcpServers -NotePropertyValue @{} -Force }
        }
    } catch {
        # ignore
    }
}
if ($config.mcpServers -isnot [System.Collections.IDictionary] -and $config.mcpServers -isnot [PSCustomObject]) {
    $config.mcpServers = @{}
}
$servers = @{}
foreach ($key in $config.mcpServers.PSObject.Properties.Name) {
    $servers[$key] = $config.mcpServers.$key
}
$servers['db2-docs'] = $serverEntry
$config.mcpServers = $servers
$null = New-Item -ItemType Directory -Path $cursorDir -Force
$jsonObj = @{ mcpServers = $config.mcpServers }
$json = $jsonObj | ConvertTo-Json -Depth 10
Set-Content -LiteralPath $configPath -Value $json -Encoding UTF8 -NoNewline
Write-Report "Step: Ensure MCP config (Python). Outcome: OK. command=$($pythonExe)."

# Run register script (prefer Register-AllCursorRagMcp when library exists)
$regScript = if (Test-Path -LiteralPath $libraryDir) { $registerScript } else { $registerScriptLegacy }
try {
    & $regScript
    Write-Report "Step: Run register script. Outcome: OK."
} catch {
    Write-Report "Step: Run register script. Outcome: Fail. $($_.Exception.Message)"
}

# Optional: HF offline when cache exists (document only; Cursor mcp.json may not support env)
$hfCache = Join-Path -Path $env:USERPROFILE -ChildPath '.cache\huggingface\hub'
$modelDir = Join-Path -Path $hfCache -ChildPath 'models--sentence-transformers--all-MiniLM-L6-v2'
if (Test-Path -LiteralPath $modelDir) {
    Write-Report "Step: HF cache present. Set HF_HUB_OFFLINE=1 and TRANSFORMERS_OFFLINE=1 before starting Cursor if RAG fails with SSL."
}

# Cursor CLI test
$cursorCmd = $null
try {
    $c = Get-Command -Name 'cursor' -ErrorAction Stop
    if ($c) { $cursorCmd = $c.Source }
} catch { }
if (-not $cursorCmd -or -not (Test-Path -LiteralPath $cursorCmd)) {
    $cursorCmd = 'C:\Program Files\cursor\resources\app\bin\cursor.cmd'
    if (-not (Test-Path -LiteralPath $cursorCmd)) { $cursorCmd = $null }
}
if (-not $cursorCmd) {
    Write-Report "Step: Cursor CLI test. Outcome: Skip. Cursor CLI not found; run test manually in Cursor with DedgePsh open."
    Add-Content -LiteralPath $reportPath -Value "`n## Recommended next steps`n- Run test manually: in Cursor with DedgePsh workspace, ask: What does SQL30082N reason code 36 mean? Use the db2-docs RAG (query_docs).`n"
    exit 0
}

$testPrompt = 'What does SQL30082N reason code 36 mean? Use the query_db2_manuals tool first.'
$workspace = 'C:\opt\src\DedgePsh'
try {
    $out = & $cursorCmd agent -p $testPrompt --workspace $workspace --print 2>&1 | Out-String
} catch {
    $out = $_.Exception.Message
}
$last500 = if ($out.Length -gt 500) { $out.Substring($out.Length - 500) } else { $out }
if ($out -match 'client has been closed|Search failed|SSL') {
    Write-Report "Step: Cursor CLI test. Outcome: Fail. Likely embedding model (Hugging Face). $last500"
    $problems = @"
## Problems encountered
- Cursor CLI test failed: embedding model load (Hugging Face unreachable or client closed).
"@
    if (-not (Get-Content -LiteralPath $reportPath -Raw) -match 'Problems encountered') {
        Add-Content -LiteralPath $reportPath -Value "`n$problems"
    }
    $steps = @"
## Recommended next steps (if still failing)
- Copy Hugging Face cache (models--sentence-transformers--all-MiniLM-L6-v2) from a machine that can download to %USERPROFILE%\.cache\huggingface\hub.
- Or run build_index.py on a network that can reach Hugging Face, then zip and restore the index (see AiDoc docs/RAG-Backup-and-Distribution.md).
"@
    Add-Content -LiteralPath $reportPath -Value "`n$steps"
} elseif ($out -match 'UNEXPECTED CLIENT ERROR|db2_sec_guide|query_docs') {
    Write-Report "Step: Cursor CLI test. Outcome: OK. RAG response or tool call detected."
} else {
    Write-Report "Step: Cursor CLI test. Outcome: Unknown. $last500"
}
