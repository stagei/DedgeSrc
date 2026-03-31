#!/usr/bin/env pwsh
#Requires -Version 7
<#
.SYNOPSIS
  C# version of Regenerate-All-Analyses.ps1 — runs the converted .NET 10
  analysis pipeline instead of the PowerShell scripts.

.DESCRIPTION
  Mirrors the parameter interface of Regenerate-All-Analyses.ps1 so both
  can be run side-by-side for output comparison. Delegates to the compiled
  SystemAnalyzer.Batch.CSharp.exe (or dotnet run) instead of Run-Analysis.ps1.

  Use this to validate that the C# conversion produces identical results
  to the PowerShell version.

.PARAMETER SettingsFile
  Path to appsettings.json containing SystemAnalyzer.DataRoot.

.PARAMETER DataRoot
  Override DataRoot (base folder for output).

.PARAMETER SkipKill
  Do not terminate other analysis processes.

.PARAMETER SkipClassification
  Passed through to the C# pipeline for every analysis.

.PARAMETER SkipPhases
  Passed through to the C# pipeline (e.g. "5,6").

.PARAMETER ResetResults
  When true (default), deletes all files under AnalysisResults/ before
  regeneration so output is clean.

.PARAMETER NoResetResults
  Shortcut to skip AnalysisResults/ cleanup.

.PARAMETER ResetCache
  When true (default), deletes all JSON files under AnalysisCommon/.

.PARAMETER NoResetCache
  Shortcut to disable cache reset.

.PARAMETER UseDotnetRun
  Use 'dotnet run' instead of the compiled .exe. Slower but does not
  require a prior 'dotnet publish'.

.EXAMPLE
  pwsh.exe -NoProfile -File .\Regenerate-All-Analyses-CSharp.ps1

.EXAMPLE
  pwsh.exe -NoProfile -File .\Regenerate-All-Analyses-CSharp.ps1 -NoResetCache -UseDotnetRun
#>
[CmdletBinding()]
param(
    [string]$SettingsFile,
    [string]$DataRoot,
    [switch]$SkipKill,
    [switch]$SkipClassification,
    [string]$SkipPhases = '',
    [bool]$ResetResults = $true,
    [switch]$NoResetResults,
    [bool]$ResetCache = $true,
    [switch]$NoResetCache,
    [switch]$UseDotnetRun
)

$ErrorActionPreference = 'Stop'

Import-Module GlobalFunctions -Force

# ── Locate the C# project ──
$csharpProjectDir = Join-Path $PSScriptRoot 'src\SystemAnalyzer.Batch.CSharp'
$csharpProjectFile = Join-Path $csharpProjectDir 'SystemAnalyzer.Batch.CSharp.csproj'

if (-not (Test-Path -LiteralPath $csharpProjectFile)) {
    Write-LogMessage "C# project not found: $($csharpProjectFile)" -Level ERROR
    Write-LogMessage "Run the Pwsh2CSharp conversion pipeline first." -Level ERROR
    exit 1
}

# ── Resolve settings (same logic as Regenerate-All-Analyses.ps1) ──
if (-not $SettingsFile) {
    $SettingsFile = Join-Path $PSScriptRoot 'src\SystemAnalyzer.Web\appsettings.json'
}
if (-not (Test-Path -LiteralPath $SettingsFile)) {
    Write-LogMessage "Settings file not found: $($SettingsFile)" -Level ERROR
    exit 1
}

$settings = Get-Content -LiteralPath $SettingsFile -Raw | ConvertFrom-Json
$cfg = $settings.SystemAnalyzer

if (-not $DataRoot) { $DataRoot = $cfg.DataRoot }
if ([string]::IsNullOrWhiteSpace($DataRoot)) {
    Write-LogMessage "DataRoot is empty (appsettings or -DataRoot)." -Level ERROR
    exit 1
}

# ── Process resets (identical to original) ──
if ($NoResetResults) { $ResetResults = $false }
if ($NoResetCache)   { $ResetCache = $false }

if ($ResetResults) {
    $analysisResultsPath = Join-Path $PSScriptRoot 'AnalysisResults'
    if (Test-Path -LiteralPath $analysisResultsPath) {
        Write-LogMessage "Clearing AnalysisResults at $($analysisResultsPath)..." -Level INFO
        $removedFiles = 0
        Get-ChildItem -LiteralPath $analysisResultsPath -Recurse -File | ForEach-Object {
            Remove-Item -LiteralPath $_.FullName -Force -ErrorAction SilentlyContinue
            $removedFiles++
        }
        Get-ChildItem -LiteralPath $analysisResultsPath -Recurse -Directory |
            Sort-Object { $_.FullName.Length } -Descending |
            ForEach-Object { Remove-Item -LiteralPath $_.FullName -Force -ErrorAction SilentlyContinue }
        Write-LogMessage "  Removed $($removedFiles) result files." -Level INFO
    }
}

if ($ResetCache) {
    $analysisCommonPath = if ($cfg.AnalysisCommonPath) { $cfg.AnalysisCommonPath } else { Join-Path $PSScriptRoot 'AnalysisCommon' }
    if (Test-Path -LiteralPath $analysisCommonPath) {
        Write-LogMessage "Resetting AnalysisCommon cache at $($analysisCommonPath)..." -Level INFO
        $removedFiles = 0
        Get-ChildItem -LiteralPath $analysisCommonPath -Recurse -File |
            Where-Object { $_.Extension -ne '.md' } |
            ForEach-Object {
                Remove-Item -LiteralPath $_.FullName -Force -ErrorAction SilentlyContinue
                $removedFiles++
            }
        Write-LogMessage "  Removed $($removedFiles) cached files." -Level INFO
    }
}

# ── Discover profiles (identical to original) ──
$profilesDir = Join-Path $PSScriptRoot 'AnalysisProfiles'
if (-not (Test-Path -LiteralPath $profilesDir)) {
    Write-LogMessage "AnalysisProfiles folder not found: $($profilesDir)" -Level ERROR
    exit 1
}

$toRun = [System.Collections.ArrayList]::new()
foreach ($dir in (Get-ChildItem -LiteralPath $profilesDir -Directory | Sort-Object Name)) {
    $allJsonPath = Join-Path $dir.FullName 'all.json'
    if (-not (Test-Path -LiteralPath $allJsonPath)) { continue }
    [void]$toRun.Add([PSCustomObject]@{ Alias = $dir.Name; AllJsonPath = $allJsonPath })
}

if ($toRun.Count -eq 0) {
    Write-LogMessage "No profiles with all.json found in $($profilesDir)" -Level WARN
    exit 0
}

Write-LogMessage "Regenerating $($toRun.Count) analyses via C# pipeline" -Level INFO

# ── Run each profile through the C# exe ──
$failures = 0
$idx = 0
foreach ($item in $toRun) {
    $idx++
    Write-LogMessage "[$idx/$($toRun.Count)] Starting (C#): $($item.Alias)" -Level INFO

    $csharpArgs = @(
        '--AllJsonPath', $item.AllJsonPath
        '--AnalysisAlias', $item.Alias
        '--SettingsFile', $SettingsFile
    )
    if ($SkipClassification) { $csharpArgs += '--SkipClassification' }
    if ($SkipPhases)         { $csharpArgs += @('--SkipPhases', $SkipPhases) }

    try {
        if ($UseDotnetRun) {
            & dotnet run --project $csharpProjectFile -- @csharpArgs
        } else {
            $exePath = Join-Path $csharpProjectDir 'bin\Release\net10.0\SystemAnalyzer.Batch.CSharp.exe'
            if (-not (Test-Path -LiteralPath $exePath)) {
                $exePath = Join-Path $csharpProjectDir 'bin\Debug\net10.0\SystemAnalyzer.Batch.CSharp.exe'
            }
            if (-not (Test-Path -LiteralPath $exePath)) {
                Write-LogMessage "  Exe not found, falling back to dotnet run" -Level WARN
                & dotnet run --project $csharpProjectFile -- @csharpArgs
            } else {
                & $exePath @csharpArgs
            }
        }

        if ($LASTEXITCODE -ne 0) {
            $failures++
            Write-LogMessage "[$idx/$($toRun.Count)] FAILED (exit $($LASTEXITCODE)): $($item.Alias)" -Level ERROR
        } else {
            Write-LogMessage "[$idx/$($toRun.Count)] OK: $($item.Alias)" -Level INFO
        }
    } catch {
        $failures++
        Write-LogMessage "[$idx/$($toRun.Count)] EXCEPTION for $($item.Alias): $($_.Exception.Message)" -Level ERROR
    }
}

if ($failures -gt 0) {
    Write-LogMessage "Completed with $($failures) failure(s) out of $($toRun.Count)." -Level ERROR
    exit 1
}

Write-LogMessage "All $($toRun.Count) analyses regenerated successfully via C# pipeline." -Level INFO
exit 0
