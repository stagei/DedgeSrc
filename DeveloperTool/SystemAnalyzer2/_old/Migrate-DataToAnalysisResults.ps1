#!/usr/bin/env pwsh
#Requires -Version 7
<#
.SYNOPSIS
  One-time migration: moves existing analysis data into AnalysisResults/{alias}/_History structure.

.DESCRIPTION
  Moves:
    {DataRoot}/analyses.json            -> {DataRoot}/AnalysisResults/analyses.json
    {DataRoot}/{alias}/                 -> {DataRoot}/AnalysisResults/{alias}/
    {DataRoot}/{alias}_{timestamp}/     -> {DataRoot}/AnalysisResults/{alias}/_History/{alias}_{timestamp}/

  Leaves _uploads, log files, and other non-analysis items at DataRoot level.
#>
[CmdletBinding(SupportsShouldProcess)]
param(
    [Parameter(Mandatory)]
    [string]$DataRoot
)

$ErrorActionPreference = 'Stop'

if (-not (Test-Path -LiteralPath $DataRoot)) {
    Write-Error "DataRoot not found: $($DataRoot)"
    exit 1
}

$resultsRoot = Join-Path $DataRoot 'AnalysisResults'
New-Item -ItemType Directory -Path $resultsRoot -Force | Out-Null
Write-Host "AnalysisResults root: $($resultsRoot)"

$analysesJson = Join-Path $DataRoot 'analyses.json'
if (Test-Path -LiteralPath $analysesJson) {
    $dest = Join-Path $resultsRoot 'analyses.json'
    Write-Host "Moving analyses.json -> AnalysisResults/"
    Copy-Item -LiteralPath $analysesJson -Destination $dest -Force
    Remove-Item -LiteralPath $analysesJson -Force
}

$index = $null
$indexPath = Join-Path $resultsRoot 'analyses.json'
if (Test-Path -LiteralPath $indexPath) {
    $index = Get-Content -LiteralPath $indexPath -Raw -Encoding UTF8 | ConvertFrom-Json
}

$aliases = @()
if ($index -and $index.analyses) {
    $aliases = @($index.analyses | ForEach-Object { $_.alias } | Where-Object { $_ })
}

$allDirs = @(Get-ChildItem -LiteralPath $DataRoot -Directory -ErrorAction SilentlyContinue |
    Where-Object { $_.Name -ne 'AnalysisResults' -and $_.Name -ne '_uploads' })

foreach ($alias in $aliases) {
    $aliasDir = Join-Path $DataRoot $alias
    if (Test-Path -LiteralPath $aliasDir) {
        $destAlias = Join-Path $resultsRoot $alias
        Write-Host "Moving alias folder: $($alias) -> AnalysisResults/$($alias)"
        if (Test-Path -LiteralPath $destAlias) {
            Remove-Item -LiteralPath $destAlias -Recurse -Force
        }
        Move-Item -LiteralPath $aliasDir -Destination $destAlias -Force
    }

    $historyDir = Join-Path $resultsRoot $alias '_History'
    $runDirs = @($allDirs | Where-Object { $_.Name -match "^$([regex]::Escape($alias))_\d{8}_\d{6}$" })
    if ($runDirs.Count -gt 0) {
        New-Item -ItemType Directory -Path $historyDir -Force | Out-Null
        foreach ($rd in $runDirs) {
            $destRun = Join-Path $historyDir $rd.Name
            Write-Host "Moving run folder: $($rd.Name) -> AnalysisResults/$($alias)/_History/$($rd.Name)"
            if (Test-Path -LiteralPath $destRun) {
                Remove-Item -LiteralPath $destRun -Recurse -Force
            }
            Move-Item -LiteralPath $rd.FullName -Destination $destRun -Force
        }
    }
}

$remaining = @(Get-ChildItem -LiteralPath $DataRoot -Directory -ErrorAction SilentlyContinue |
    Where-Object { $_.Name -ne 'AnalysisResults' -and $_.Name -ne '_uploads' -and $_.Name -notmatch '^\.' })

if ($remaining.Count -gt 0) {
    Write-Host ""
    Write-Host "Remaining unmigrated directories (not in aliases list):"
    foreach ($r in $remaining) {
        Write-Host "  $($r.Name)"
    }
}

Write-Host ""
Write-Host "Migration complete. New structure:"
Get-ChildItem -LiteralPath $resultsRoot -ErrorAction SilentlyContinue | ForEach-Object {
    $prefix = if ($_.PSIsContainer) { 'DIR ' } else { 'FILE' }
    Write-Host "  [$prefix] $($_.Name)"
    if ($_.PSIsContainer) {
        Get-ChildItem -LiteralPath $_.FullName -ErrorAction SilentlyContinue | ForEach-Object {
            $p2 = if ($_.PSIsContainer) { 'DIR ' } else { 'FILE' }
            Write-Host "    [$p2] $($_.Name)"
        }
    }
}
