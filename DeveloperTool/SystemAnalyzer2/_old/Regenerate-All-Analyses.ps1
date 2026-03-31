#!/usr/bin/env pwsh
#Requires -Version 7
<#
.SYNOPSIS
  Stops in-flight SystemAnalyzer regeneration processes, then re-runs analysis for
  every profile in AnalysisProfiles/.

.DESCRIPTION
  1) Stops SystemAnalyzer.Batch.exe and pwsh/dotnet processes running
     Invoke-FullAnalysis.ps1 or SystemAnalyzer.Batch (excluding this script's session).
  2) Reads DataRoot from SystemAnalyzer.Web appsettings.json (or -DataRoot).
  3) Scans AnalysisProfiles/ for all.json files (canonical source of truth).
  4) Optionally clears AnalysisResults/ and AnalysisCommon/ before regeneration.
  5) For each profile, calls Run-Analysis.ps1 with -Alias and -AllJsonPath.

.PARAMETER SettingsFile
  Path to appsettings.json containing SystemAnalyzer.DataRoot.

.PARAMETER DataRoot
  Override DataRoot (base folder for output).

.PARAMETER SkipKill
  Do not terminate other analysis processes.

.PARAMETER SkipClassification
  Passed through to Run-Analysis.ps1 for every analysis.

.PARAMETER SkipPhases
  Passed through to Run-Analysis.ps1 (e.g. "5,6").

.PARAMETER ResetResults
  When true (default), deletes all files under AnalysisResults/ before
  regeneration so output is clean. AnalysisProfiles/ and AnalysisStatic/ are never touched.

.PARAMETER NoResetResults
  Shortcut to skip AnalysisResults/ cleanup.

.PARAMETER ResetCache
  When true (default), deletes all JSON files under AnalysisCommon/ before
  regeneration — effectively forcing a cold-cache run. Preserves .md files
  and folder structure so READMEs and documentation survive.

.PARAMETER NoResetCache
  Shortcut to disable cache reset (equivalent to -ResetCache:$false).

.EXAMPLE
  pwsh.exe -NoProfile -File .\Regenerate-All-Analyses.ps1
  # Deletes AnalysisResults/ and AnalysisCommon/ cache, then regenerates all.

.EXAMPLE
  pwsh.exe -NoProfile -File .\Regenerate-All-Analyses.ps1 -NoResetCache
  # Deletes AnalysisResults/ but keeps AnalysisCommon/ (warm-cache run).

.EXAMPLE
  pwsh.exe -NoProfile -File .\Regenerate-All-Analyses.ps1 -NoResetResults -NoResetCache
  # Keeps all existing output and cache. Re-runs pipelines over existing data.

.EXAMPLE
  pwsh.exe -NoProfile -File .\Regenerate-All-Analyses.ps1 -SkipPhases "5,6"
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

    [switch]$NoResetCache
)

$ErrorActionPreference = 'Stop'

Import-Module GlobalFunctions -Force

function Stop-SystemAnalyzerRegenProcesses {
    param([int]$ExcludeProcessId)

    $stopped = [System.Collections.Generic.List[string]]::new()

    foreach ($p in Get-Process -Name 'SystemAnalyzer.Batch' -ErrorAction SilentlyContinue) {
        try {
            Stop-Process -Id $p.Id -Force -ErrorAction Stop
            $null = $stopped.Add("SystemAnalyzer.Batch pid=$($p.Id)")
        } catch {
            Write-LogMessage "Could not stop SystemAnalyzer.Batch pid=$($p.Id): $($_.Exception.Message)" -Level WARN
        }
    }

    $patterns = @(
        @{ Name = 'pwsh.exe'; Pattern = 'Invoke-FullAnalysis\.ps1' },
        @{ Name = 'powershell.exe'; Pattern = 'Invoke-FullAnalysis\.ps1' },
        @{ Name = 'dotnet.exe'; Pattern = 'SystemAnalyzer\.Batch' }
    )
    foreach ($rule in $patterns) {
        $procs = Get-CimInstance -ClassName Win32_Process -Filter "Name = '$($rule.Name)'" -ErrorAction SilentlyContinue
        foreach ($proc in $procs) {
            if ($proc.ProcessId -eq $ExcludeProcessId) { continue }
            $cmd = $proc.CommandLine
            if ([string]::IsNullOrEmpty($cmd)) { continue }
            if ($cmd -notmatch $rule.Pattern) { continue }
            try {
                Stop-Process -Id $proc.ProcessId -Force -ErrorAction Stop
                $null = $stopped.Add("$($rule.Name) pid=$($proc.ProcessId)")
            } catch {
                Write-LogMessage "Could not stop $($rule.Name) pid=$($proc.ProcessId): $($_.Exception.Message)" -Level WARN
            }
        }
    }

    return $stopped
}

if (-not $SettingsFile) {
    $SettingsFile = Join-Path $PSScriptRoot 'src\SystemAnalyzer.Web\appsettings.json'
}
if (-not (Test-Path -LiteralPath $SettingsFile)) {
    Write-LogMessage "Settings file not found: $($SettingsFile)" -Level ERROR
    exit 1
}

$settings = Get-Content -LiteralPath $SettingsFile -Raw | ConvertFrom-Json
$cfg = $settings.SystemAnalyzer

if (-not $DataRoot) {
    $DataRoot = $cfg.DataRoot
}
if ([string]::IsNullOrWhiteSpace($DataRoot)) {
    Write-LogMessage "DataRoot is empty (appsettings or -DataRoot)." -Level ERROR
    exit 1
}

$profilesDir = Join-Path $PSScriptRoot 'AnalysisProfiles'
if (-not (Test-Path -LiteralPath $profilesDir)) {
    Write-LogMessage "AnalysisProfiles folder not found: $($profilesDir)" -Level ERROR
    exit 1
}

if (-not $SkipKill) {
    Write-LogMessage "Stopping in-flight SystemAnalyzer regen processes (excluding current pid=$PID)..." -Level INFO
    $killed = Stop-SystemAnalyzerRegenProcesses -ExcludeProcessId $PID
    if ($killed.Count -eq 0) {
        Write-LogMessage "No matching regen processes were running." -Level INFO
    } else {
        foreach ($k in $killed) {
            Write-LogMessage "Stopped: $($k)" -Level INFO
        }
    }
    Start-Sleep -Seconds 2
}

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
        Write-LogMessage "  Removed $removedFiles result files." -Level INFO
    }
}

if ($ResetCache) {
    $analysisCommonPath = if ($cfg.AnalysisCommonPath) { $cfg.AnalysisCommonPath } else { Join-Path $PSScriptRoot 'AnalysisCommon' }
    if (Test-Path -LiteralPath $analysisCommonPath) {
        Write-LogMessage "Resetting AnalysisCommon cache at $($analysisCommonPath) (preserving .md files and folders)..." -Level INFO

        $removedFiles = 0
        Get-ChildItem -LiteralPath $analysisCommonPath -Recurse -File |
            Where-Object { $_.Extension -ne '.md' } |
            ForEach-Object {
                Remove-Item -LiteralPath $_.FullName -Force -ErrorAction SilentlyContinue
                $removedFiles++
            }

        Write-LogMessage "  Removed $removedFiles cached files. Folder structure and .md files preserved." -Level INFO
    } else {
        Write-LogMessage "AnalysisCommon path not found: $($analysisCommonPath) — skipping reset" -Level WARN
    }
}

$runAnalysis = Join-Path $PSScriptRoot 'Run-Analysis.ps1'
if (-not (Test-Path -LiteralPath $runAnalysis)) {
    Write-LogMessage "Run-Analysis.ps1 not found: $($runAnalysis)" -Level ERROR
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

Write-LogMessage "Regenerating $($toRun.Count) analysis/archives from $($profilesDir)" -Level INFO

$failures = 0
$idx = 0
foreach ($item in $toRun) {
    $idx++
    Write-LogMessage "[$idx/$($toRun.Count)] Starting: $($item.Alias) <= $($item.AllJsonPath)" -Level INFO

    $raArgs = @{
        AllJsonPath        = $item.AllJsonPath
        Alias              = $item.Alias
        SettingsFile       = $SettingsFile
    }
    if ($SkipClassification) {
        $raArgs.SkipClassification = $true
    }
    if ($SkipPhases) {
        $raArgs.SkipPhases = $SkipPhases
    }

    try {
        & $runAnalysis @raArgs
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

Write-LogMessage "All $($toRun.Count) analyses regenerated successfully." -Level INFO
exit 0
