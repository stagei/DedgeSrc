#!/usr/bin/env pwsh
<#
.SYNOPSIS
    Runs SystemAnalyzer.Batch for one or all analysis profiles.
.DESCRIPTION
    Builds and runs the C# batch analysis pipeline against the specified profile(s).
    Profiles are discovered automatically from the AnalysisProfiles folder.
    By default, generated output folders (AnalysisResults, AnalysisCommon, AnalysisStats)
    are cleaned before running so each run starts fresh.
.PARAMETER Profile
    Name of a single profile to run (e.g. CobDok, FkKonto, KD_Korn, Vareregister).
    Use 'All' to run every profile sequentially. Default: All.
.PARAMETER CleanBefore
    Clear generated folders (AnalysisResults, AnalysisCommon, AnalysisStats) before
    running. Preserves AnalysisStatic and AnalysisProfiles. Default: $true.
    Use -CleanBefore:$false to keep previous results and let the pipeline append/reuse.
.PARAMETER NoBuild
    Skip the dotnet build step (use previous build output).
.PARAMETER SkipPhases
    Comma-separated phase numbers to skip (passed through to the batch pipeline).
.PARAMETER SkipClassification
    Skip the classification phase.
.PARAMETER SkipNaming
    Skip Ollama-powered naming phases (useful for quick re-analysis).
.PARAMETER SkipCatalog
    Skip DB2 catalog export even if files are missing.
.PARAMETER RefreshCatalogs
    Force re-export DB2 catalogs even if files are recent.
.PARAMETER CopyToServer
    Copy AnalysisResults and AnalysisCommon to dedge-server after successful
    analysis so results are publicly available. Default: $true.
.EXAMPLE
    .\Run-Analysis.ps1
    # Cleans output folders, then runs all four profiles from scratch
.EXAMPLE
    .\Run-Analysis.ps1 -CleanBefore:$false
    # Keeps existing results and runs all profiles (incremental / cache-reuse)
.EXAMPLE
    .\Run-Analysis.ps1 -Profile CobDok
    # Cleans and runs CobDok only
.EXAMPLE
    .\Run-Analysis.ps1 -Profile KD_Korn -NoBuild -CleanBefore:$false
    # Runs KD_Korn without rebuilding or cleaning
.EXAMPLE
    .\Run-Analysis.ps1 -RefreshCatalogs
    # Cleans, runs all profiles, and forces DB2 catalog re-export
#>

[CmdletBinding()]
param(
    [ValidateSet('All', 'CobDok', 'FkKonto', 'KD_Korn', 'Vareregister')]
    [string]$Profile = 'All',

    [bool]$CleanBefore = $true,

    [switch]$NoBuild,

    [string]$SkipPhases,

    [switch]$SkipClassification,

    [switch]$SkipNaming,

    [switch]$SkipCatalog,

    [switch]$RefreshCatalogs,

    [bool]$CopyToServer = $true
)

$ErrorActionPreference = 'Stop'
$projectRoot = $PSScriptRoot
$batchProject = Join-Path $projectRoot 'src\SystemAnalyzer.Batch\SystemAnalyzer.Batch.csproj'
$profilesDir = Join-Path $projectRoot 'AnalysisProfiles'

if (-not (Test-Path $batchProject)) {
    Write-Host "Batch project not found: $($batchProject)" -ForegroundColor Red
    exit 1
}

$profiles = if ($Profile -eq 'All') {
    Get-ChildItem $profilesDir -Directory | ForEach-Object { $_.Name }
} else {
    @($Profile)
}

foreach ($p in $profiles) {
    $allJson = Join-Path $profilesDir "$($p)\all.json"
    if (-not (Test-Path $allJson)) {
        Write-Host "Profile all.json not found: $($allJson)" -ForegroundColor Red
        exit 1
    }
}

Write-Host ''
Write-Host '════════════════════════════════════════════════════════════════════════════════' -ForegroundColor Cyan
Write-Host '  SystemAnalyzer — Batch Analysis' -ForegroundColor Cyan
Write-Host "  Profiles: $($profiles -join ', ')" -ForegroundColor Cyan
Write-Host "  CleanBefore: $($CleanBefore)" -ForegroundColor Cyan
Write-Host '════════════════════════════════════════════════════════════════════════════════' -ForegroundColor Cyan
Write-Host ''

if ($CleanBefore) {
    Write-Host 'Cleaning generated folders...' -ForegroundColor Yellow
    # Note: AnalysisOverride is intentionally NOT cleaned — user edits persist
    $foldersToClean = @(
        (Join-Path $projectRoot 'AnalysisResults'),
        (Join-Path $projectRoot 'AnalysisCommon'),
        (Join-Path $projectRoot 'AnalysisStats')
    )
    foreach ($folder in $foldersToClean) {
        if (Test-Path $folder) {
            Remove-Item $folder -Recurse -Force
            Write-Host "  Cleared: $($folder)" -ForegroundColor DarkYellow
        }
    }
    Write-Host 'Clean complete.' -ForegroundColor Green
    Write-Host ''
}

if (-not $NoBuild) {
    Write-Host 'Building SystemAnalyzer.Batch...' -ForegroundColor Yellow
    dotnet build $batchProject -c Release --verbosity quiet
    if ($LASTEXITCODE -ne 0) {
        Write-Host 'Build failed.' -ForegroundColor Red
        exit 1
    }
    Write-Host 'Build succeeded.' -ForegroundColor Green
    Write-Host ''
}

# Pre-step: Export DB2 catalogs via ODBC (PowerShell) so C# pipeline can use them
if (-not $SkipCatalog) {
    $catalogScript = Join-Path $projectRoot 'Export-DatabaseCatalogs.ps1'
    if (Test-Path $catalogScript) {
        Write-Host 'Exporting DB2 catalogs via ODBC...' -ForegroundColor Yellow
        try {
            & $catalogScript
            Write-Host 'DB2 catalog export complete.' -ForegroundColor Green
        } catch {
            Write-Host "DB2 catalog export failed: $($_.Exception.Message)" -ForegroundColor DarkYellow
            Write-Host 'Continuing — C# pipeline will retry via MCP fallback.' -ForegroundColor DarkYellow
        }
        Write-Host ''
    }
}

$totalSw = [System.Diagnostics.Stopwatch]::StartNew()
$results = @()

foreach ($p in $profiles) {
    $allJson = Join-Path $profilesDir "$($p)\all.json"

    Write-Host "────────────────────────────────────────────────────────────────────────────────" -ForegroundColor DarkGray
    Write-Host "  Running profile: $($p)" -ForegroundColor White
    Write-Host "────────────────────────────────────────────────────────────────────────────────" -ForegroundColor DarkGray

    $isLastProfile = ($p -eq $profiles[-1]) -and ($Profile -eq 'All')
    $runArgs = @('run', '--project', $batchProject, '-c', 'Release', '--no-build', '--', '--all-json', $allJson, '--alias', $p)

    if ($SkipPhases) {
        $runArgs += '--skip-phases'
        $runArgs += $SkipPhases
    }
    if ($SkipClassification) {
        $runArgs += '--skip-classification'
    }
    if ($SkipNaming) {
        $runArgs += '--skip-naming'
    }
    if ($SkipCatalog) {
        $runArgs += '--skip-catalog'
    }
    if ($RefreshCatalogs) {
        $runArgs += '--refresh-catalogs'
    }
    if ($isLastProfile) {
        $runArgs += '--generate-stats'
    }

    $sw = [System.Diagnostics.Stopwatch]::StartNew()
    & dotnet @runArgs
    $exitCode = $LASTEXITCODE
    $sw.Stop()

    $status = if ($exitCode -eq 0) { 'OK' } else { 'FAILED' }
    $results += [PSCustomObject]@{
        Profile  = $p
        Status   = $status
        Duration = $sw.Elapsed.ToString('mm\:ss\.f')
        ExitCode = $exitCode
    }

    if ($exitCode -ne 0) {
        Write-Host "  Profile $($p) FAILED (exit code $($exitCode))" -ForegroundColor Red
    } else {
        Write-Host "  Profile $($p) completed in $($sw.Elapsed.ToString('mm\:ss\.f'))" -ForegroundColor Green
    }
    Write-Host ''
}

$totalSw.Stop()

Write-Host '════════════════════════════════════════════════════════════════════════════════' -ForegroundColor Cyan
Write-Host '  Summary' -ForegroundColor Cyan
Write-Host '════════════════════════════════════════════════════════════════════════════════' -ForegroundColor Cyan
$results | Format-Table -AutoSize
Write-Host "Total time: $($totalSw.Elapsed.ToString('mm\:ss\.f'))" -ForegroundColor Cyan

$failed = $results | Where-Object { $_.ExitCode -ne 0 }
if ($failed) {
    Write-Host "$($failed.Count) profile(s) failed." -ForegroundColor Red
    exit 1
} else {
    Write-Host 'All profiles completed successfully.' -ForegroundColor Green
}

# ── Copy results to dedge-server ──
if ($CopyToServer -and -not $failed) {
    $serverBase = 'C:\opt\src\DedgeSrc\DedgeSystemTools\Folders\Opt\src\SystemAnalyzer'

    Write-Host ''
    Write-Host '════════════════════════════════════════════════════════════════════════════════' -ForegroundColor Magenta
    Write-Host '  Copying results to dedge-server' -ForegroundColor Magenta
    Write-Host '════════════════════════════════════════════════════════════════════════════════' -ForegroundColor Magenta

    $copySw = [System.Diagnostics.Stopwatch]::StartNew()
    $copyPairs = @(
        @{ Name = 'AnalysisResults';  Src = Join-Path $projectRoot 'AnalysisResults';  Dst = Join-Path $serverBase 'AnalysisResults' }
        @{ Name = 'AnalysisCommon';   Src = Join-Path $projectRoot 'AnalysisCommon';   Dst = Join-Path $serverBase 'AnalysisCommon' }
        @{ Name = 'AnalysisStats';    Src = Join-Path $projectRoot 'AnalysisStats';    Dst = Join-Path $serverBase 'AnalysisStats' }
        @{ Name = 'AnalysisOverride'; Src = Join-Path $projectRoot 'AnalysisOverride'; Dst = Join-Path $serverBase 'AnalysisOverride' }
    )

    foreach ($pair in $copyPairs) {
        if (-not (Test-Path $pair.Src)) { continue }
        Write-Host "  Syncing $($pair.Name)..." -ForegroundColor Gray
        $roboArgs = @($pair.Src, $pair.Dst, '/MIR', '/NJH', '/NJS', '/NDL', '/NC', '/NS', '/NP', '/R:2', '/W:2', '/MT:8')
        $roboOut = & robocopy @roboArgs 2>&1
        $roboExit = $LASTEXITCODE
        if ($roboExit -ge 8) {
            Write-Host "  WARNING: robocopy returned $($roboExit) for $($pair.Name)" -ForegroundColor Yellow
        } else {
            Write-Host "  $($pair.Name) synced." -ForegroundColor Green
        }
    }

    $copySw.Stop()
    Write-Host "  Server copy completed in $($copySw.Elapsed.ToString('mm\:ss\.f'))" -ForegroundColor Magenta
    Write-Host ''
}
