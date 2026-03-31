<#
.SYNOPSIS
    Setup and test all MCP servers for detected clients (Cursor and/or Ollama).
.DESCRIPTION
    Detects whether Cursor and/or Ollama is installed, then runs all relevant
    Setup and Test scripts from the source tree. Reports a summary table at
    the end.
.PARAMETER SkipSetup
    Skip the Setup phase and only run Tests.
.PARAMETER SkipTest
    Skip the Test phase and only run Setup.
.EXAMPLE
    pwsh.exe -NoProfile -File Setup-AllMcpServers.ps1
.EXAMPLE
    pwsh.exe -NoProfile -File Setup-AllMcpServers.ps1 -SkipTest
#>
[CmdletBinding()]
param(
    [switch]$SkipSetup,
    [switch]$SkipTest
)

$ErrorActionPreference = 'Stop'

Import-Module GlobalFunctions -Force

$mcpServersRoot = Split-Path -Parent $PSScriptRoot

$hasCursor = Test-Path (Join-Path $env:USERPROFILE '.cursor')
$hasOllama = $null -ne (Get-Command ollama -ErrorAction SilentlyContinue)

Write-LogMessage "=== Setup-AllMcpServers ===" -Level INFO
Write-LogMessage "Source root: $($mcpServersRoot)" -Level INFO
Write-LogMessage "Cursor detected: $($hasCursor)" -Level INFO
Write-LogMessage "Ollama detected: $($hasOllama)" -Level INFO

if (-not $hasCursor -and -not $hasOllama) {
    Write-LogMessage "Neither Cursor nor Ollama detected. Nothing to set up." -Level WARN
    exit 0
}

$cursorSetups = @(
    @{ Folder = 'Setup-AutoDocMcpCursor';    Script = 'Setup-AutoDocMcpCursor' }
    @{ Folder = 'Setup-Db2QueryMcpCursor';   Script = 'Setup-Db2QueryMcpCursor' }
    @{ Folder = 'Setup-PostgreSqlMcpCursor';  Script = 'Setup-PostgreSqlMcpCursor' }
    @{ Folder = 'Setup-RagMcpCursor';         Script = 'Setup-RagMcpCursor' }
)

$cursorTests = @(
    @{ Folder = 'Setup-AutoDocMcpCursor';    Script = 'Test-AutoDocMcpCursor' }
    @{ Folder = 'Setup-Db2QueryMcpCursor';   Script = 'Test-Db2QueryMcpCursor' }
    @{ Folder = 'Setup-PostgreSqlMcpCursor';  Script = 'Test-PostgreSqlMcpCursor' }
    @{ Folder = 'Setup-RagMcpCursor';         Script = 'Test-RagMcpCursor' }
)

$ollamaSetups = @(
    @{ Folder = 'Setup-AutoDocMcpOllama';  Script = 'Setup-AutoDocMcpOllama' }
    @{ Folder = 'Setup-Db2QueryMcpOllama'; Script = 'Setup-Db2QueryMcpOllama' }
    @{ Folder = 'Setup-RagMcpOllama';      Script = 'Setup-RagMcpOllama' }
)

$ollamaTests = @(
    @{ Folder = 'Setup-AutoDocMcpOllama';  Script = 'Test-AutoDocMcpOllama' }
    @{ Folder = 'Setup-Db2QueryMcpOllama'; Script = 'Test-Db2QueryMcpOllama' }
    @{ Folder = 'Setup-RagMcpOllama';      Script = 'Test-RagMcpOllama' }
)

$results = [System.Collections.ArrayList]::new()

function Invoke-McpScript {
    param(
        [string]$Phase,
        [string]$Client,
        [string]$Folder,
        [string]$Script
    )

    $scriptPath = Join-Path $mcpServersRoot "$($Folder)\$($Script).ps1"
    $sw = [System.Diagnostics.Stopwatch]::StartNew()

    try {
        if (-not (Test-Path $scriptPath)) {
            throw "Script not found: $($scriptPath)"
        }
        Write-LogMessage "[$($Phase)] $($Client): $($Script)..." -Level INFO
        & pwsh.exe -NoProfile -File $scriptPath
        if ($LASTEXITCODE -ne 0) { throw "Script exited with code $($LASTEXITCODE)" }
        $sw.Stop()
        $null = $results.Add([PSCustomObject]@{
            Phase    = $Phase
            Client   = $Client
            Script   = $Script
            Status   = 'OK'
            Duration = "$([math]::Round($sw.Elapsed.TotalSeconds, 1))s"
            Error    = ''
        })
    }
    catch {
        $sw.Stop()
        Write-LogMessage "[$($Phase)] $($Client): $($Script) FAILED: $($_.Exception.Message)" -Level ERROR
        $null = $results.Add([PSCustomObject]@{
            Phase    = $Phase
            Client   = $Client
            Script   = $Script
            Status   = 'FAIL'
            Duration = "$([math]::Round($sw.Elapsed.TotalSeconds, 1))s"
            Error    = $_.Exception.Message
        })
    }
}

if (-not $SkipSetup) {
    Write-LogMessage "" -Level INFO
    Write-LogMessage "=== SETUP PHASE ===" -Level INFO

    if ($hasCursor) {
        foreach ($entry in $cursorSetups) {
            Invoke-McpScript -Phase 'Setup' -Client 'Cursor' -Folder $entry.Folder -Script $entry.Script
        }
    }

    if ($hasOllama) {
        foreach ($entry in $ollamaSetups) {
            Invoke-McpScript -Phase 'Setup' -Client 'Ollama' -Folder $entry.Folder -Script $entry.Script
        }
    }
}

if (-not $SkipTest) {
    Write-LogMessage "" -Level INFO
    Write-LogMessage "=== TEST PHASE ===" -Level INFO

    if ($hasCursor) {
        foreach ($entry in $cursorTests) {
            Invoke-McpScript -Phase 'Test' -Client 'Cursor' -Folder $entry.Folder -Script $entry.Script
        }
    }

    if ($hasOllama) {
        foreach ($entry in $ollamaTests) {
            Invoke-McpScript -Phase 'Test' -Client 'Ollama' -Folder $entry.Folder -Script $entry.Script
        }
    }
}

Write-LogMessage "" -Level INFO
Write-LogMessage "=== SUMMARY ===" -Level INFO

$passCount = ($results | Where-Object { $_.Status -eq 'OK' }).Count
$failCount = ($results | Where-Object { $_.Status -eq 'FAIL' }).Count

$results | Format-Table Phase, Client, Script, Status, Duration, Error -AutoSize | Out-String | ForEach-Object { Write-LogMessage $_ -Level INFO }

Write-LogMessage "Total: $($results.Count) scripts, $($passCount) OK, $($failCount) FAIL" -Level INFO

if ($failCount -gt 0) {
    Write-LogMessage "Some scripts failed. Check output above for details." -Level WARN
    exit 1
}
