<#
.SYNOPSIS
    Uninstall all MCP servers for detected clients (Cursor and/or Ollama).
.DESCRIPTION
    Detects whether Cursor and/or Ollama is installed, then runs all relevant
    Uninstall scripts from the source tree. Reports a summary table at the end.
.PARAMETER CursorOnly
    Only uninstall Cursor MCP servers.
.PARAMETER OllamaOnly
    Only uninstall Ollama MCP servers.
.EXAMPLE
    pwsh.exe -NoProfile -File Uninstall-AllMcpServers.ps1
.EXAMPLE
    pwsh.exe -NoProfile -File Uninstall-AllMcpServers.ps1 -CursorOnly
#>
[CmdletBinding()]
param(
    [switch]$CursorOnly,
    [switch]$OllamaOnly
)

$ErrorActionPreference = 'Stop'

Import-Module GlobalFunctions -Force

$mcpServersRoot = Split-Path -Parent $PSScriptRoot

$hasCursor = Test-Path (Join-Path $env:USERPROFILE '.cursor')
$hasOllama = $null -ne (Get-Command ollama -ErrorAction SilentlyContinue)

Write-LogMessage "=== Uninstall-AllMcpServers ===" -Level INFO
Write-LogMessage "Source root: $($mcpServersRoot)" -Level INFO
Write-LogMessage "Cursor detected: $($hasCursor)" -Level INFO
Write-LogMessage "Ollama detected: $($hasOllama)" -Level INFO

if (-not $hasCursor -and -not $hasOllama) {
    Write-LogMessage "Neither Cursor nor Ollama detected. Nothing to uninstall." -Level WARN
    exit 0
}

if ($CursorOnly) { $hasOllama = $false }
if ($OllamaOnly) { $hasCursor = $false }

$cursorUninstalls = @(
    @{ Folder = 'Setup-AutoDocMcpCursor';    Script = 'Uninstall-AutoDocMcpCursor' }
    @{ Folder = 'Setup-Db2QueryMcpCursor';   Script = 'Uninstall-Db2QueryMcpCursor' }
    @{ Folder = 'Setup-PostgreSqlMcpCursor';  Script = 'Uninstall-PostgreSqlMcpCursor' }
    @{ Folder = 'Setup-RagMcpCursor';         Script = 'Uninstall-RagMcpCursor' }
)

$ollamaUninstalls = @(
    @{ Folder = 'Setup-Db2QueryMcpOllama'; Script = 'Uninstall-Db2QueryMcpOllama' }
    @{ Folder = 'Setup-RagMcpOllama';      Script = 'Uninstall-RagMcpOllama' }
)

$results = [System.Collections.ArrayList]::new()

function Invoke-McpUninstall {
    param(
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
        Write-LogMessage "[Uninstall] $($Client): $($Script)..." -Level INFO
        & pwsh.exe -NoProfile -File $scriptPath
        if ($LASTEXITCODE -ne 0) { throw "Script exited with code $($LASTEXITCODE)" }
        $sw.Stop()
        $null = $results.Add([PSCustomObject]@{
            Client   = $Client
            Script   = $Script
            Status   = 'OK'
            Duration = "$([math]::Round($sw.Elapsed.TotalSeconds, 1))s"
            Error    = ''
        })
    }
    catch {
        $sw.Stop()
        Write-LogMessage "[Uninstall] $($Client): $($Script) FAILED: $($_.Exception.Message)" -Level ERROR
        $null = $results.Add([PSCustomObject]@{
            Client   = $Client
            Script   = $Script
            Status   = 'FAIL'
            Duration = "$([math]::Round($sw.Elapsed.TotalSeconds, 1))s"
            Error    = $_.Exception.Message
        })
    }
}

if ($hasCursor) {
    Write-LogMessage "" -Level INFO
    Write-LogMessage "=== CURSOR UNINSTALL ===" -Level INFO
    foreach ($entry in $cursorUninstalls) {
        Invoke-McpUninstall -Client 'Cursor' -Folder $entry.Folder -Script $entry.Script
    }
}

if ($hasOllama) {
    Write-LogMessage "" -Level INFO
    Write-LogMessage "=== OLLAMA UNINSTALL ===" -Level INFO
    foreach ($entry in $ollamaUninstalls) {
        Invoke-McpUninstall -Client 'Ollama' -Folder $entry.Folder -Script $entry.Script
    }
}

Write-LogMessage "" -Level INFO
Write-LogMessage "=== SUMMARY ===" -Level INFO

$passCount = ($results | Where-Object { $_.Status -eq 'OK' }).Count
$failCount = ($results | Where-Object { $_.Status -eq 'FAIL' }).Count

$results | Format-Table Client, Script, Status, Duration, Error -AutoSize | Out-String | ForEach-Object { Write-LogMessage $_ -Level INFO }

Write-LogMessage "Total: $($results.Count) scripts, $($passCount) OK, $($failCount) FAIL" -Level INFO

if ($failCount -gt 0) {
    Write-LogMessage "Some uninstalls failed. Check output above for details." -Level WARN
    exit 1
}
