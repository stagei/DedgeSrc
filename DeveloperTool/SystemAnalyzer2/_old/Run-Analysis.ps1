#!/usr/bin/env pwsh
#Requires -Version 7
<#
.SYNOPSIS
  Run the SystemAnalyzer analysis pipeline locally, reading all settings from
  appsettings.json so output lands on the correct server DataRoot.

.DESCRIPTION
  Reads SystemAnalyzer configuration from src\SystemAnalyzer.Web\appsettings.json,
  locates Invoke-FullAnalysis.ps1 in src\SystemAnalyzer.Batch\Scripts\, and
  runs the full analysis pipeline.

  Output is written to {DataRoot}\AnalysisResults\{alias}\ with run history
  in {alias}\_History\{alias}_{timestamp}\.

  By default, output is written directly to the server DataRoot\AnalysisResults
  via UNC path.

  With -LocalExecution, the pipeline writes to a local temp folder first
  (fast disk I/O, local Ollama at localhost:11434), then syncs the results to
  the server AnalysisResults after completion. This is ideal when the local PC
  has a more powerful GPU for the Ollama AI classification.

.PARAMETER AllJsonPath
  Path to the input all.json file. Can be a local path or UNC path.

.PARAMETER Alias
  Analysis alias name. If omitted, auto-derived from areas in the JSON file.

.PARAMETER SkipPhases
  Comma-separated phase numbers to skip. Use "5,6" to skip RAG-dependent
  phases when the RAG server is unavailable.
  Accepts: "5,6" or "5 6" or "5, 6" (string, parsed internally to avoid
  pwsh.exe -File mode array-conversion bugs).

.PARAMETER SkipClassification
  Skip the classification phase.

.PARAMETER LocalExecution
  Run the analysis with output to a local temp folder, then copy results
  to the server. Faster I/O and uses the local Ollama instance.

.PARAMETER SettingsFile
  Path to appsettings.json. Defaults to src\SystemAnalyzer.Web\appsettings.json.

.EXAMPLE
  pwsh.exe -NoProfile -File Run-Analysis.ps1 -AllJsonPath "C:\opt\src\AgriProd\run_20260313_173751\all.json"

.EXAMPLE
  pwsh.exe -NoProfile -File Run-Analysis.ps1 -AllJsonPath .\my_programs.json -Alias KD_Korn -SkipPhases "5,6"

.EXAMPLE
  pwsh.exe -NoProfile -File Run-Analysis.ps1 -AllJsonPath .\all.json -LocalExecution
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory)]
    [string]$AllJsonPath,

    [string]$Alias,

    [string]$SkipPhases = '',

    [switch]$SkipClassification,

    [switch]$LocalExecution,

    [string]$SettingsFile
)

$ErrorActionPreference = 'Stop'

$skipPhasesArray = @()
if ($SkipPhases) {
    $skipPhasesArray = @($SkipPhases -split '[,\s]+' | Where-Object { $_ -match '^\d+$' } | ForEach-Object { [int]$_ })
}

if (-not $SettingsFile) {
    $SettingsFile = Join-Path $PSScriptRoot 'src\SystemAnalyzer.Web\appsettings.json'
}

if (-not (Test-Path -LiteralPath $SettingsFile)) {
    Write-Error "Settings file not found: $($SettingsFile)"
    exit 1
}

$allJsonFull = (Resolve-Path -LiteralPath $AllJsonPath -ErrorAction Stop).Path
if (-not (Test-Path -LiteralPath $allJsonFull)) {
    Write-Error "all.json not found: $($allJsonFull)"
    exit 1
}

$settings = Get-Content -LiteralPath $SettingsFile -Raw | ConvertFrom-Json
$cfg = $settings.SystemAnalyzer

Write-Host "Configuration from: $($SettingsFile)"
Write-Host "  DataRoot:       $($cfg.DataRoot)"
Write-Host "  SourceRoot:     $($cfg.SourceRoot)"
Write-Host "  RagUrl:         $($cfg.RagUrl)"
Write-Host "  Db2Dsn:         $($cfg.Db2Dsn)"
Write-Host "  OllamaUrl:      $($cfg.OllamaUrl)"
Write-Host "  OllamaModel:    $($cfg.OllamaModel)"

$scriptCandidates = @(
    (Join-Path $PSScriptRoot 'src\SystemAnalyzer.Batch\Scripts\Invoke-FullAnalysis.ps1')
)
$invokeScript = $scriptCandidates | Where-Object { Test-Path -LiteralPath $_ } | Select-Object -First 1

if (-not $invokeScript) {
    Write-Error "Invoke-FullAnalysis.ps1 not found. Searched:`n  $($scriptCandidates -join "`n  ")"
    exit 1
}

Write-Host "  Pipeline:       $($invokeScript)"

if (-not $Alias) {
    $suggested = 'Analysis'
    try {
        $doc = Get-Content -LiteralPath $allJsonFull -Raw | ConvertFrom-Json
        $areas = @($doc.entries | ForEach-Object { $_.area } | Where-Object { $_ } | Sort-Object -Unique)
        if ($areas.Count -gt 0) { $suggested = $areas -join '_' }
    } catch { }

    $userInput = Read-Host "Analysis alias [$($suggested)]"
    $Alias = if ([string]::IsNullOrWhiteSpace($userInput)) { $suggested } else { $userInput.Trim() }
}

$serverDataRoot = $cfg.DataRoot
$serverResultsRoot = Join-Path $serverDataRoot 'AnalysisResults'
$outputDir = $serverResultsRoot
$localTempDir = $null

if ($LocalExecution) {
    $timestamp = Get-Date -Format 'yyyyMMdd_HHmmss'
    $localTempDir = Join-Path 'C:\temp\SystemAnalyzer\AnalysisResults' "$($Alias)_$($timestamp)"
    New-Item -ItemType Directory -Path $localTempDir -Force | Out-Null
    $outputDir = $localTempDir
    Write-Host ""
    Write-Host "LOCAL EXECUTION MODE"
    Write-Host "  Local output:   $($localTempDir)"
    Write-Host "  Server target:  $($serverResultsRoot)"
}

Write-Host ""
Write-Host "Starting analysis:"
Write-Host "  Alias:          $($Alias)"
Write-Host "  Input:          $($allJsonFull)"
Write-Host "  Output:         $($outputDir)\$($Alias)"
if ($skipPhasesArray.Count -gt 0) {
    Write-Host "  Skip phases:    $($skipPhasesArray -join ', ')"
}
Write-Host ""

$scriptArgs = @(
    '-NoProfile'
    '-File', $invokeScript
    '-AllJsonPath', $allJsonFull
    '-AnalysisAlias', $Alias
    '-AnalysisDataRoot', $outputDir
    '-OutputDir', $outputDir
    '-SourceRoot', $cfg.SourceRoot
    '-RagUrl', $cfg.RagUrl
    '-VisualCobolRagUrl', $cfg.VisualCobolRagUrl
    '-Db2Dsn', $cfg.Db2Dsn
    '-DefaultFilePath', $cfg.DefaultFilePath
    '-OllamaUrl', $cfg.OllamaUrl
    '-OllamaModel', $cfg.OllamaModel
    '-MaxCallIterations', $cfg.MaxCallIterations.ToString()
    '-RagResults', $cfg.RagResults.ToString()
    '-RagTableResults', $cfg.RagTableResults.ToString()
)

$analysisCommonPath = if ($cfg.AnalysisCommonPath) { $cfg.AnalysisCommonPath } else { Join-Path $PSScriptRoot 'AnalysisCommon' }
if (Test-Path -LiteralPath $analysisCommonPath) {
    $scriptArgs += '-AnalysisCommonPath'
    $scriptArgs += $analysisCommonPath
}

if ($SkipClassification) {
    $scriptArgs += '-SkipClassification'
}
if ($skipPhasesArray.Count -gt 0) {
    $scriptArgs += '-SkipPhases'
    foreach ($phase in $skipPhasesArray) {
        $scriptArgs += $phase.ToString()
    }
}

$sw = [System.Diagnostics.Stopwatch]::StartNew()
& pwsh.exe @scriptArgs
$exitCode = $LASTEXITCODE
$sw.Stop()

$elapsed = $sw.Elapsed.ToString('hh\:mm\:ss')

if ($exitCode -eq 0) {
    Write-Host ""
    Write-Host "Analysis completed in $($elapsed)."

    if ($LocalExecution -and $localTempDir) {
        Write-Host ""
        Write-Host "Syncing results to server..."

        $localAliasFolder = Join-Path $localTempDir $Alias
        $serverAliasFolder = Join-Path $serverResultsRoot $Alias

        $localHistoryDir = Join-Path $localAliasFolder '_History'
        if (Test-Path -LiteralPath $localHistoryDir) {
            $serverHistoryDir = Join-Path $serverAliasFolder '_History'
            New-Item -ItemType Directory -Path $serverHistoryDir -Force | Out-Null
            $runFolders = @(Get-ChildItem -LiteralPath $localHistoryDir -Directory -ErrorAction SilentlyContinue)
            foreach ($runFolder in $runFolders) {
                $serverRunFolder = Join-Path $serverHistoryDir $runFolder.Name
                Write-Host "  Copying run folder: _History/$($runFolder.Name)"
                if (Test-Path -LiteralPath $serverRunFolder) {
                    Remove-Item -LiteralPath $serverRunFolder -Recurse -Force
                }
                Copy-Item -LiteralPath $runFolder.FullName -Destination $serverRunFolder -Recurse -Force
            }
        }

        if (Test-Path -LiteralPath $localAliasFolder) {
            Write-Host "  Copying alias snapshot: $($Alias)"
            New-Item -ItemType Directory -Path $serverAliasFolder -Force | Out-Null
            Get-ChildItem -LiteralPath $localAliasFolder -Force -ErrorAction SilentlyContinue |
                Where-Object { $_.Name -ne '_History' } |
                ForEach-Object {
                    $destPath = Join-Path $serverAliasFolder $_.Name
                    if (Test-Path -LiteralPath $destPath) { Remove-Item -LiteralPath $destPath -Recurse -Force }
                    Copy-Item -LiteralPath $_.FullName -Destination $destPath -Recurse -Force
                }
        }

        $localAnalysesJson = Join-Path $localTempDir 'analyses.json'
        if (Test-Path -LiteralPath $localAnalysesJson) {
            $serverAnalysesJson = Join-Path $serverResultsRoot 'analyses.json'
            New-Item -ItemType Directory -Path $serverResultsRoot -Force | Out-Null
            Write-Host "  Copying analyses.json to server"
            Copy-Item -LiteralPath $localAnalysesJson -Destination $serverAnalysesJson -Force
        }

        $serverFiles = @(Get-ChildItem -LiteralPath $serverAliasFolder -File -ErrorAction SilentlyContinue)
        $totalSize = ($serverFiles | Measure-Object -Property Length -Sum).Sum
        Write-Host "  Synced $($serverFiles.Count) files ($([math]::Round($totalSize / 1KB, 1)) KB) to server."
        Write-Host "  Server path: $($serverAliasFolder)"
    }

    $aliasFolder = if ($LocalExecution) { Join-Path $serverResultsRoot $Alias } else { Join-Path $outputDir $Alias }
    if (Test-Path -LiteralPath $aliasFolder) {
        $files = Get-ChildItem -LiteralPath $aliasFolder -File -ErrorAction SilentlyContinue
        Write-Host ""
        Write-Host "Output folder: $($aliasFolder)"
        Write-Host "  Files: $($files.Count)"
        foreach ($f in $files | Sort-Object Name) {
            Write-Host "    $($f.Name)  ($([math]::Round($f.Length / 1KB, 1)) KB)"
        }
    }
} else {
    Write-Host ""
    Write-Host "Analysis failed with exit code $($exitCode) after $($elapsed)." -ForegroundColor Red
}

exit $exitCode
