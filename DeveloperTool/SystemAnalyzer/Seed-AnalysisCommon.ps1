#!/usr/bin/env pwsh
#Requires -Version 7
<#
.SYNOPSIS
  Seeds AnalysisCommon/Objects/ from existing analysis results.

.DESCRIPTION
  Parses standard_cobol_filtered.json, all_file_io.json, and
  dependency_master.json from each profile in AnalysisResults/ and
  populates AnalysisCommon/Objects/{NAME}.{type}.json with cached facts.

  Files use a type suffix to disambiguate elements with the same base name:
    PROGRAM.cbl.json    — COBOL program
    COPYBOOK.cpb.json   — Copybook (.CPY, .CPB, bare)
    TABLE.dcl.json      — SQL declare include
    TABLE.sqltable.json — SQL table
    FILE.file.json      — File I/O target

  Existing JSON files are merged (not overwritten) — new facts are added
  alongside any previously cached facts.

  The seed also populates an 'extraction' fact from dependency_master.json
  (without sourceHash) so that the first pipeline run can verify and stamp
  the hash instead of re-extracting from scratch.

.PARAMETER AnalysisResultsPath
  Path to the AnalysisResults folder.

.PARAMETER AnalysisCommonPath
  Path to the AnalysisCommon folder.

.EXAMPLE
  pwsh.exe -NoProfile -File .\Seed-AnalysisCommon.ps1
#>
[CmdletBinding()]
param(
    [string]$AnalysisResultsPath = (Join-Path $PSScriptRoot 'AnalysisResults'),
    [string]$AnalysisCommonPath  = (Join-Path $PSScriptRoot 'AnalysisCommon')
)

$ErrorActionPreference = 'Stop'

$objectsDir = Join-Path $AnalysisCommonPath 'Objects'
New-Item -ItemType Directory -Path $objectsDir -Force | Out-Null

function Get-ProgramJson {
    param([string]$ProgramName, [string]$ElementType = 'cbl')
    $path = Join-Path $objectsDir "$($ProgramName).$($ElementType).json"
    if (Test-Path -LiteralPath $path) {
        return (Get-Content -LiteralPath $path -Raw -Encoding UTF8 | ConvertFrom-Json)
    }
    return [PSCustomObject]@{
        program     = $ProgramName
        elementType = $ElementType
        lastUpdated = $null
    }
}

function Save-ProgramJson {
    param([string]$ProgramName, [string]$ElementType = 'cbl', [object]$Data)
    $Data.lastUpdated = (Get-Date).ToString('yyyy-MM-ddTHH:mm:ss')
    if (-not ($Data.PSObject.Properties.Name -contains 'elementType')) {
        $Data | Add-Member -NotePropertyName 'elementType' -NotePropertyValue $ElementType -Force
    }
    $path = Join-Path $objectsDir "$($ProgramName).$($ElementType).json"
    $Data | ConvertTo-Json -Depth 10 | Set-Content -LiteralPath $path -Encoding UTF8
}

$profiles = @(Get-ChildItem -LiteralPath $AnalysisResultsPath -Directory -ErrorAction SilentlyContinue |
    Where-Object { $_.Name -ne '_uploads' })

if ($profiles.Count -eq 0) {
    Write-Host "No profiles found in $($AnalysisResultsPath)"
    exit 0
}

Write-Host "Seeding AnalysisCommon from $($profiles.Count) profile(s): $($profiles.Name -join ', ')"
Write-Host ""

$totalStdCobol = 0
$totalFileIO = 0
$totalClassification = 0
$totalExtraction = 0
$programsSeen = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)

foreach ($profile in $profiles) {
    Write-Host "=== $($profile.Name) ==="

    # --- standard_cobol_filtered.json -> isStandardCobol ---
    $stdCobolFile = Join-Path $profile.FullName 'standard_cobol_filtered.json'
    if (Test-Path -LiteralPath $stdCobolFile) {
        $stdCobol = Get-Content -LiteralPath $stdCobolFile -Raw -Encoding UTF8 | ConvertFrom-Json
        $generated = $stdCobol.generated

        foreach ($entry in @($stdCobol.removed) + @($stdCobol.retained)) {
            if (-not $entry.program) { continue }
            $name = $entry.program.ToUpperInvariant()
            $null = $programsSeen.Add($name)

            $pj = Get-ProgramJson -ProgramName $name -ElementType 'cbl'

            if (-not ($pj.PSObject.Properties.Name -contains 'isStandardCobol')) {
                $pj | Add-Member -NotePropertyName 'isStandardCobol' -NotePropertyValue ([PSCustomObject]@{
                    answer     = $entry.ollamaVerdict
                    ragEvidence = if ($entry.ragEvidence.Length -gt 500) { $entry.ragEvidence.Substring(0, 500) } else { $entry.ragEvidence }
                    model      = 'qwen2.5:7b'
                    protocol   = 'Cbl-StandardProgramFilter'
                    analyzedAt = $generated
                }) -Force
                $totalStdCobol++
            }

            Save-ProgramJson -ProgramName $name -ElementType 'cbl' -Data $pj
        }
        Write-Host "  standard_cobol_filtered: $(@($stdCobol.removed).Count + @($stdCobol.retained).Count) entries"
    } else {
        Write-Host "  standard_cobol_filtered.json not found — skipping"
    }

    # --- all_file_io.json -> variableFilenames ---
    $fileIOFile = Join-Path $profile.FullName 'all_file_io.json'
    if (Test-Path -LiteralPath $fileIOFile) {
        $fileIO = Get-Content -LiteralPath $fileIOFile -Raw -Encoding UTF8 | ConvertFrom-Json
        $generated = $fileIO.generated

        $resolvedEntries = @($fileIO.fileReferences | Where-Object {
            $_.resolvedPath -or $_.filenamePattern -or $_.filenameDescription
        })

        foreach ($entry in $resolvedEntries) {
            if (-not $entry.program) { continue }
            $name = $entry.program.ToUpperInvariant()
            $null = $programsSeen.Add($name)

            $pj = Get-ProgramJson -ProgramName $name -ElementType 'cbl'

            if (-not ($pj.PSObject.Properties.Name -contains 'variableFilenames')) {
                $pj | Add-Member -NotePropertyName 'variableFilenames' -NotePropertyValue ([PSCustomObject]@{}) -Force
            }

            $logicalKey = $entry.logicalName
            if (-not $logicalKey) { $logicalKey = $entry.physicalName }
            if (-not $logicalKey) { continue }

            $existingVf = $pj.variableFilenames
            if (-not ($existingVf.PSObject.Properties.Name -contains $logicalKey)) {
                $existingVf | Add-Member -NotePropertyName $logicalKey -NotePropertyValue ([PSCustomObject]@{
                    logicalName      = $entry.logicalName
                    physicalVariable = $entry.physicalName
                    basePath         = $entry.path
                    filenamePattern  = $entry.filenamePattern
                    resolvedPath     = $entry.resolvedPath
                    description      = $entry.filenameDescription
                    model            = 'qwen2.5:7b'
                    protocol         = 'Cbl-VariableFilenames'
                    analyzedAt       = $generated
                }) -Force
                $totalFileIO++
            }

            Save-ProgramJson -ProgramName $name -ElementType 'cbl' -Data $pj
        }
        Write-Host "  all_file_io: $($resolvedEntries.Count) resolved entries"
    } else {
        Write-Host "  all_file_io.json not found — skipping"
    }

    # --- dependency_master.json -> classification + extraction ---
    $masterFile = Join-Path $profile.FullName 'dependency_master.json'
    if (Test-Path -LiteralPath $masterFile) {
        $master = Get-Content -LiteralPath $masterFile -Raw -Encoding UTF8 | ConvertFrom-Json
        $generated = $master.generated

        foreach ($entry in @($master.programs)) {
            if (-not $entry.program) { continue }
            $name = $entry.program.ToUpperInvariant()
            $null = $programsSeen.Add($name)

            $pj = Get-ProgramJson -ProgramName $name -ElementType 'cbl'

            # Classification fact
            if ($entry.classification -and -not ($pj.PSObject.Properties.Name -contains 'classification')) {
                $pj | Add-Member -NotePropertyName 'classification' -NotePropertyValue ([PSCustomObject]@{
                    value      = $entry.classification
                    confidence = $entry.classificationConfidence
                    evidence   = $entry.classificationEvidence
                    model      = 'rule-based'
                    protocol   = 'Cbl-ProgramClassification'
                    analyzedAt = $generated
                }) -Force
                $totalClassification++
            }

            # Extraction fact (without sourceHash — first pipeline run will stamp it)
            if (-not ($pj.PSObject.Properties.Name -contains 'extraction')) {
                $pj | Add-Member -NotePropertyName 'extraction' -NotePropertyValue ([PSCustomObject]@{
                    sourceHash    = $null
                    sourceType    = $entry.sourceType
                    sourcePath    = $entry.sourcePath
                    actualName    = $entry.actualName
                    program       = $name
                    copyElements  = @($entry.copyElements)
                    sqlOperations = @($entry.sqlOperations)
                    callTargets   = @($entry.callTargets)
                    fileIO        = @($entry.fileIO)
                    extractedAt   = $generated
                }) -Force
                $totalExtraction++
            }

            Save-ProgramJson -ProgramName $name -ElementType 'cbl' -Data $pj
        }
        $classifiedCount = @($master.programs | Where-Object { $_.classification }).Count
        Write-Host "  dependency_master: $($master.programs.Count) programs ($classifiedCount classified)"
    } else {
        Write-Host "  dependency_master.json not found — skipping"
    }

    Write-Host ""
}

Write-Host "═══════════════════════════════════════════════════════════════════════════════"
Write-Host "  Seeding Complete"
Write-Host "═══════════════════════════════════════════════════════════════════════════════"
Write-Host "  Unique programs:       $($programsSeen.Count)"
Write-Host "  isStandardCobol facts: $($totalStdCobol)"
Write-Host "  variableFilenames:     $($totalFileIO)"
Write-Host "  classification:        $($totalClassification)"
Write-Host "  extraction:            $($totalExtraction)"
Write-Host "  Output: $($objectsDir)"
Write-Host ""
