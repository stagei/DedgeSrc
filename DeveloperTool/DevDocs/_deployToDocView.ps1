#Requires -Version 7.0
[CmdletBinding()]
param(
    [string]$TargetServer = 'dedge-server',
    [string]$ContentSubfolder = 'DevDocs'
)

Import-Module GlobalFunctions -Force

$ErrorActionPreference = 'Stop'
$scriptName = Split-Path $PSCommandPath -Leaf

$sourceDir = $PSScriptRoot
$targetBase = "\\$($TargetServer)\opt\Webs\DocViewWeb\Content"
$targetDir = Join-Path $targetBase $ContentSubfolder
$docViewRefreshUrl = "http://$($TargetServer)/DocView/api/document/refresh"

Write-LogMessage "[$($scriptName)] Starting DevDocs deploy to $($targetDir)" -Level INFO

if (-not (Test-Path $targetBase)) {
    Write-LogMessage "[$($scriptName)] Target base path not found: $($targetBase) - creating it" -Level WARN
    New-Item -Path $targetBase -ItemType Directory -Force | Out-Null
}

if (-not (Test-Path $targetDir)) {
    New-Item -Path $targetDir -ItemType Directory -Force | Out-Null
    Write-LogMessage "[$($scriptName)] Created target folder: $($targetDir)" -Level INFO
}

$excludeDirs = @('.git', '.cursor', 'node_modules', 'bin', 'obj')
$excludeArgs = $excludeDirs | ForEach-Object { "/XD"; $_ }

$robocopyArgs = @(
    $sourceDir
    $targetDir
    '/MIR'
    '/R:2'
    '/W:3'
    '/NP'
    '/NDL'
    '/NFL'
) + $excludeArgs

Write-LogMessage "[$($scriptName)] Running Robocopy: $($sourceDir) -> $($targetDir)" -Level INFO
$robocopyOutput = & robocopy @robocopyArgs 2>&1
$robocopyExit = $LASTEXITCODE

if ($robocopyExit -ge 8) {
    Write-LogMessage "[$($scriptName)] Robocopy failed with exit code $($robocopyExit): $($robocopyOutput -join "`n")" -Level ERROR
    throw "Robocopy failed with exit code $($robocopyExit)"
}

$summary = $robocopyOutput | Select-String -Pattern '^\s*(Dirs|Files|Bytes)\s*:' | ForEach-Object { $_.Line.Trim() }
foreach ($line in $summary) {
    Write-LogMessage "[$($scriptName)] $($line)" -Level INFO
}

Write-LogMessage "[$($scriptName)] Robocopy completed (exit code $($robocopyExit))" -Level INFO

Write-LogMessage "[$($scriptName)] Refreshing DocView cache: POST $($docViewRefreshUrl)" -Level INFO
try {
    $response = Invoke-RestMethod -Uri $docViewRefreshUrl -Method Post -TimeoutSec 30 -ErrorAction Stop
    Write-LogMessage "[$($scriptName)] DocView cache refreshed successfully" -Level INFO
}
catch {
    Write-LogMessage "[$($scriptName)] DocView cache refresh failed (non-fatal): $($_.Exception.Message)" -Level WARN
}

Write-LogMessage "[$($scriptName)] DevDocs deploy completed successfully" -Level INFO
