<#
.SYNOPSIS
    Test all configured MCP servers for Cursor and/or Ollama.

.DESCRIPTION
    Runs each MCP server's individual test script and collects results.
    Before running tests, validates the mcp.json configuration and checks
    connectivity to backend services (IIS endpoints, RAG ports, PostgreSQL).

    Phase 1: Pre-flight — validate mcp.json, check endpoints
    Phase 2: Individual tests — run each Test-*.ps1 script
    Phase 3: Summary — pass/fail table with timings

.PARAMETER CursorOnly
    Only test Cursor MCP servers.

.PARAMETER OllamaOnly
    Only test Ollama MCP servers.

.PARAMETER SkipPreflight
    Skip the pre-flight connectivity checks and go straight to tests.

.PARAMETER StopOnFirstFailure
    Stop testing after the first failure instead of running all tests.

.EXAMPLE
    pwsh.exe -NoProfile -File Test-AllMcpServers.ps1

.EXAMPLE
    pwsh.exe -NoProfile -File Test-AllMcpServers.ps1 -CursorOnly

.EXAMPLE
    pwsh.exe -NoProfile -File Test-AllMcpServers.ps1 -SkipPreflight
#>
[CmdletBinding()]
param(
    [switch]$CursorOnly,
    [switch]$OllamaOnly,
    [switch]$SkipPreflight,
    [switch]$StopOnFirstFailure
)

$ErrorActionPreference = 'Stop'

Import-Module GlobalFunctions -Force

$mcpServersRoot = Split-Path -Parent $PSScriptRoot

$hasCursor = Test-Path (Join-Path $env:USERPROFILE '.cursor')
$hasOllama = $null -ne (Get-Command ollama -ErrorAction SilentlyContinue)

if ($CursorOnly) { $hasOllama = $false }
if ($OllamaOnly) { $hasCursor = $false }

Write-LogMessage "============================================" -Level INFO
Write-LogMessage " Test-AllMcpServers" -Level INFO
Write-LogMessage "============================================" -Level INFO
Write-LogMessage "Source root : $($mcpServersRoot)" -Level INFO
Write-LogMessage "Cursor      : $(if ($hasCursor) { 'detected' } else { 'not found' })" -Level INFO
Write-LogMessage "Ollama      : $(if ($hasOllama) { 'detected' } else { 'not found' })" -Level INFO
Write-LogMessage "" -Level INFO

if (-not $hasCursor -and -not $hasOllama) {
    Write-LogMessage "Neither Cursor nor Ollama detected. Nothing to test." -Level WARN
    exit 0
}

$results = [System.Collections.ArrayList]::new()
$stopped = $false

$cursorTests = @(
    @{ Folder = 'Setup-AutoDocMcpCursor';    Script = 'Test-AutoDocMcpCursor';    Description = 'AutoDoc JSON document search' }
    @{ Folder = 'Setup-Db2QueryMcpCursor';   Script = 'Test-Db2QueryMcpCursor';   Description = 'DB2 read-only SQL queries' }
    @{ Folder = 'Setup-PostgreSqlMcpCursor';  Script = 'Test-PostgreSqlMcpCursor';  Description = 'PostgreSQL read-only queries' }
    @{ Folder = 'Setup-RagMcpCursor';         Script = 'Test-RagMcpCursor';         Description = 'RAG documentation search' }
)

$ollamaTests = @(
    @{ Folder = 'Setup-Db2QueryMcpOllama'; Script = 'Test-Db2QueryMcpOllama'; Description = 'DB2 queries via Ollama' }
    @{ Folder = 'Setup-RagMcpOllama';      Script = 'Test-RagMcpOllama';      Description = 'RAG search via Ollama' }
)

# ════════════════════════════════════════════════════════════════════════════════
# Phase 1: Pre-flight checks
# ════════════════════════════════════════════════════════════════════════════════

function Test-Endpoint {
    param([string]$Name, [string]$Url, [int]$TimeoutSec = 5)
    try {
        $null = Invoke-WebRequest -Uri $Url -UseBasicParsing -TimeoutSec $TimeoutSec -ErrorAction Stop
        Write-LogMessage "  [OK]   $($Name) — $($Url)" -Level INFO
        return 'OK'
    }
    catch {
        $code = $_.Exception.Response.StatusCode.value__
        if ($code) {
            Write-LogMessage "  [OK]   $($Name) — $($Url) (HTTP $($code))" -Level INFO
            return 'OK'
        }
        Write-LogMessage "  [FAIL] $($Name) — $($Url) — $($_.Exception.Message)" -Level ERROR
        return 'FAIL'
    }
}

if (-not $SkipPreflight) {
    Write-LogMessage "=== PHASE 1: PRE-FLIGHT CHECKS ===" -Level INFO
    Write-LogMessage "" -Level INFO

    $preflightFailed = $false

    # Check mcp.json exists and is valid
    Write-LogMessage "[Config] Checking mcp.json..." -Level INFO
    $mcpJsonPath = Join-Path $env:USERPROFILE '.cursor\mcp.json'
    if ($hasCursor) {
        if (Test-Path $mcpJsonPath) {
            try {
                $mcpConfig = Get-Content $mcpJsonPath -Raw | ConvertFrom-Json
                $serverCount = ($mcpConfig.mcpServers.PSObject.Properties | Measure-Object).Count
                Write-LogMessage "  [OK]   mcp.json valid — $($serverCount) server(s) configured" -Level INFO

                foreach ($prop in $mcpConfig.mcpServers.PSObject.Properties) {
                    $name = $prop.Name
                    $def = $prop.Value
                    $transport = if ($def.PSObject.Properties['url']) { "HTTP: $($def.url)" }
                                 elseif ($def.PSObject.Properties['command']) { "stdio: $($def.command)" }
                                 else { 'unknown' }
                    Write-LogMessage "         $($name) ($($transport))" -Level INFO
                }
            }
            catch {
                Write-LogMessage "  [FAIL] mcp.json is invalid JSON: $($_.Exception.Message)" -Level ERROR
                $preflightFailed = $true
            }
        }
        else {
            Write-LogMessage "  [FAIL] mcp.json not found at $($mcpJsonPath)" -Level ERROR
            $preflightFailed = $true
        }
    }

    # Check backend endpoints
    Write-LogMessage "" -Level INFO
    Write-LogMessage "[Endpoints] Checking backend services..." -Level INFO

    $endpointChecks = @(
        @{ Name = 'DB2 MCP (IIS)';     Url = 'http://dedge-server/CursorDb2McpServer/' }
        @{ Name = 'AutoDoc health';     Url = 'http://dedge-server/AutoDocJson/health' }
        @{ Name = 'AutoDoc MCP';        Url = 'http://dedge-server/AutoDocJson/mcp' }
        @{ Name = 'RAG registry';       Url = 'http://dedge-server:8484/' }
        @{ Name = 'RAG db2-docs';       Url = 'http://dedge-server:8484/' }
        @{ Name = 'RAG visual-cobol';   Url = 'http://dedge-server:8485/' }
        @{ Name = 'RAG Dedge-code';    Url = 'http://dedge-server:8486/' }
    )

    foreach ($ep in $endpointChecks) {
        $epResult = Test-Endpoint -Name $ep.Name -Url $ep.Url
        if ($epResult -eq 'FAIL') { $preflightFailed = $true }
    }

    # Check PostgreSQL Node.js server script exists
    Write-LogMessage "" -Level INFO
    Write-LogMessage "[Files] Checking local MCP server files..." -Level INFO
    $pgScript = Join-Path $mcpServersRoot 'Setup-PostgreSqlMcpCursor\postgresql-mcp-server.mjs'
    if (Test-Path $pgScript) {
        Write-LogMessage "  [OK]   PostgreSQL MCP server script" -Level INFO
    }
    else {
        Write-LogMessage "  [FAIL] PostgreSQL MCP server script missing: $($pgScript)" -Level ERROR
        $preflightFailed = $true
    }

    # Check RAG proxy
    $ragProxy = Join-Path $env:USERPROFILE '.cursor\rag-proxy\server_mcp_proxy.py'
    if (Test-Path -LiteralPath $ragProxy) {
        Write-LogMessage "  [OK]   RAG proxy script" -Level INFO
    }
    else {
        Write-LogMessage "  [WARN] RAG proxy script missing: $($ragProxy)" -Level WARN
    }

    # Check RAG venv
    $ragVenv = Join-Path $env:USERPROFILE '.cursor\rag-proxy\.venv\Scripts\python.exe'
    if (Test-Path -LiteralPath $ragVenv) {
        Write-LogMessage "  [OK]   RAG proxy venv" -Level INFO
    }
    else {
        Write-LogMessage "  [WARN] RAG proxy venv missing — RAG tests may fail" -Level WARN
    }

    Write-LogMessage "" -Level INFO
    if ($preflightFailed) {
        Write-LogMessage "Pre-flight: Some checks failed. Tests will still run but may fail." -Level WARN
    }
    else {
        Write-LogMessage "Pre-flight: All checks passed." -Level INFO
    }

    $null = $results.Add([PSCustomObject]@{
        Phase       = 'Preflight'
        Client      = '-'
        Script      = 'Config & Endpoints'
        Description = 'mcp.json validation and endpoint connectivity'
        Status      = if ($preflightFailed) { 'WARN' } else { 'OK' }
        Duration    = '-'
        Error       = if ($preflightFailed) { 'Some pre-flight checks failed' } else { '' }
    })
}

# ════════════════════════════════════════════════════════════════════════════════
# Phase 2: Run individual test scripts
# ════════════════════════════════════════════════════════════════════════════════

Write-LogMessage "" -Level INFO
Write-LogMessage "=== PHASE 2: MCP SERVER TESTS ===" -Level INFO
Write-LogMessage "" -Level INFO

function Invoke-McpTest {
    param(
        [string]$Client,
        [string]$Folder,
        [string]$Script,
        [string]$Description
    )

    if ($stopped) { return }

    $scriptPath = Join-Path $mcpServersRoot "$($Folder)\$($Script).ps1"
    $sw = [System.Diagnostics.Stopwatch]::StartNew()

    try {
        if (-not (Test-Path $scriptPath)) {
            throw "Script not found: $($scriptPath)"
        }
        Write-LogMessage "[$($Client)] $($Script) — $($Description)" -Level INFO
        $output = & pwsh.exe -NoProfile -File $scriptPath 2>&1
        $exitCode = $LASTEXITCODE

        $outputStr = ($output | Out-String).Trim()
        if ($outputStr) {
            $outputStr -split "`n" | ForEach-Object {
                $line = $_.Trim()
                if ($line) { Write-LogMessage "  | $($line)" -Level INFO }
            }
        }

        if ($exitCode -ne 0) { throw "Script exited with code $($exitCode)" }

        # Detect FAIL reported by child script even when exit code is 0
        $childFailed = $outputStr -match 'RESULT:\s*FAIL'
        if ($childFailed) { throw "Script reported FAIL in output" }

        $sw.Stop()
        $null = $results.Add([PSCustomObject]@{
            Phase       = 'Test'
            Client      = $Client
            Script      = $Script
            Description = $Description
            Status      = 'OK'
            Duration    = "$([math]::Round($sw.Elapsed.TotalSeconds, 1))s"
            Error       = ''
        })
        Write-LogMessage "  => PASS ($([math]::Round($sw.Elapsed.TotalSeconds, 1))s)" -Level INFO
    }
    catch {
        $sw.Stop()
        $errMsg = $_.Exception.Message
        if ($errMsg.Length -gt 200) { $errMsg = $errMsg.Substring(0, 200) + '...' }
        Write-LogMessage "  => FAIL ($([math]::Round($sw.Elapsed.TotalSeconds, 1))s): $($errMsg)" -Level ERROR
        $null = $results.Add([PSCustomObject]@{
            Phase       = 'Test'
            Client      = $Client
            Script      = $Script
            Description = $Description
            Status      = 'FAIL'
            Duration    = "$([math]::Round($sw.Elapsed.TotalSeconds, 1))s"
            Error       = $errMsg
        })

        if ($StopOnFirstFailure) {
            Write-LogMessage "StopOnFirstFailure is set — aborting remaining tests." -Level WARN
            $script:stopped = $true
        }
    }
    Write-LogMessage "" -Level INFO
}

if ($hasCursor) {
    Write-LogMessage "--- Cursor MCP Servers ---" -Level INFO
    Write-LogMessage "" -Level INFO
    foreach ($entry in $cursorTests) {
        Invoke-McpTest -Client 'Cursor' -Folder $entry.Folder -Script $entry.Script -Description $entry.Description
    }
}

if ($hasOllama) {
    Write-LogMessage "--- Ollama MCP Servers ---" -Level INFO
    Write-LogMessage "" -Level INFO
    foreach ($entry in $ollamaTests) {
        Invoke-McpTest -Client 'Ollama' -Folder $entry.Folder -Script $entry.Script -Description $entry.Description
    }
}

# ════════════════════════════════════════════════════════════════════════════════
# Phase 3: Summary
# ════════════════════════════════════════════════════════════════════════════════

Write-LogMessage "============================================" -Level INFO
Write-LogMessage " SUMMARY" -Level INFO
Write-LogMessage "============================================" -Level INFO

$testResults = $results | Where-Object { $_.Phase -eq 'Test' }
$passCount = ($testResults | Where-Object { $_.Status -eq 'OK' }).Count
$failCount = ($testResults | Where-Object { $_.Status -eq 'FAIL' }).Count
$totalCount = $testResults.Count

$results | Format-Table Phase, Client, Script, Status, Duration, Error -AutoSize | Out-String -Width 160 | ForEach-Object {
    $_.Trim() -split "`n" | Where-Object { $_.Trim() } | ForEach-Object { Write-LogMessage $_ -Level INFO }
}

Write-LogMessage "" -Level INFO
$summaryLevel = if ($failCount -eq 0) { 'INFO' } else { 'ERROR' }
Write-LogMessage "Tests: $($totalCount) total, $($passCount) passed, $($failCount) failed" -Level $summaryLevel

if ($stopped) {
    Write-LogMessage "Note: Testing was stopped early due to -StopOnFirstFailure" -Level WARN
}

if ($failCount -gt 0) {
    Write-LogMessage "" -Level INFO
    Write-LogMessage "Failed tests:" -Level ERROR
    $testResults | Where-Object { $_.Status -eq 'FAIL' } | ForEach-Object {
        Write-LogMessage "  $($_.Client)/$($_.Script): $($_.Error)" -Level ERROR
    }
    exit 1
}

Write-LogMessage "" -Level INFO
Write-LogMessage "All MCP server tests passed." -Level INFO
exit 0
