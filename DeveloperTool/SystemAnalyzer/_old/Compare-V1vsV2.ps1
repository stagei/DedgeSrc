#!/usr/bin/env pwsh
#Requires -Version 7
<#
.SYNOPSIS
    Compares JSON output files from V1 (PowerShell) and V2 (C#) analysis runs.

.PARAMETER V1RunDir
    Path to the V1 run output folder (e.g., AnalysisResults\V1_Baseline\_History\V1_Baseline_20260328_...)

.PARAMETER V2RunDir
    Path to the V2 run output folder (e.g., AnalysisResultsV2\V2_Test\_History\V2_Test_20260328_...)

.PARAMETER OutputDir
    Directory for comparison report. Defaults to C:\temp\V1vsV2_comparison.

.EXAMPLE
    pwsh.exe -NoProfile -File Compare-V1vsV2.ps1 -V1RunDir ".\AnalysisResults\X\_History\X_20260328_120000" -V2RunDir ".\AnalysisResultsV2\X\_History\X_20260328_120100"
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory)]
    [string]$V1RunDir,

    [Parameter(Mandatory)]
    [string]$V2RunDir,

    [string]$OutputDir = 'C:\temp\V1vsV2_comparison'
)

$ErrorActionPreference = 'Stop'

Import-Module GlobalFunctions -Force

New-Item -ItemType Directory -Path $OutputDir -Force | Out-Null

$filesToCompare = @(
    'dependency_master.json',
    'all_total_programs.json',
    'all_sql_tables.json',
    'all_copy_elements.json',
    'all_call_graph.json',
    'all_file_io.json',
    'source_verification.json',
    'db2_table_validation.json',
    'applied_exclusions.json',
    'standard_cobol_filtered.json',
    'classified_programs.json',
    'business_areas.json'
)

$timestampFields = @('generated', 'timestamp', 'lastRun', 'analysisTimestamp', 'runTimestamp')

function Normalize-JsonObject {
    param([object]$Obj, [int]$Depth = 0)
    if ($Depth -gt 20) { return $Obj }
    if ($null -eq $Obj) { return $null }

    if ($Obj -is [System.Collections.IList]) {
        $normalized = @()
        foreach ($item in $Obj) {
            $normalized += Normalize-JsonObject -Obj $item -Depth ($Depth + 1)
        }
        return $normalized
    }

    if ($Obj -is [PSCustomObject]) {
        $ordered = [ordered]@{}
        $props = @($Obj.PSObject.Properties | Sort-Object Name)
        foreach ($p in $props) {
            if ($p.Name -in $timestampFields) { continue }
            $ordered[$p.Name] = Normalize-JsonObject -Obj $p.Value -Depth ($Depth + 1)
        }
        return [PSCustomObject]$ordered
    }

    return $Obj
}

function Compare-JsonDeep {
    param(
        [object]$Left,
        [object]$Right,
        [string]$Path = '$'
    )

    $diffs = [System.Collections.ArrayList]::new()

    if ($null -eq $Left -and $null -eq $Right) { return $diffs }
    if ($null -eq $Left) {
        [void]$diffs.Add([PSCustomObject]@{ Path = $Path; Type = 'missing_in_v1'; V1 = $null; V2 = "$Right" })
        return $diffs
    }
    if ($null -eq $Right) {
        [void]$diffs.Add([PSCustomObject]@{ Path = $Path; Type = 'missing_in_v2'; V1 = "$Left"; V2 = $null })
        return $diffs
    }

    if ($Left -is [PSCustomObject] -and $Right -is [PSCustomObject]) {
        $leftProps = @{}
        $Left.PSObject.Properties | ForEach-Object { $leftProps[$_.Name] = $_.Value }
        $rightProps = @{}
        $Right.PSObject.Properties | ForEach-Object { $rightProps[$_.Name] = $_.Value }

        foreach ($key in $leftProps.Keys) {
            if (-not $rightProps.ContainsKey($key)) {
                [void]$diffs.Add([PSCustomObject]@{ Path = "$($Path).$($key)"; Type = 'missing_in_v2'; V1 = "$($leftProps[$key])"; V2 = $null })
            } else {
                $childDiffs = Compare-JsonDeep -Left $leftProps[$key] -Right $rightProps[$key] -Path "$($Path).$($key)"
                foreach ($d in $childDiffs) { [void]$diffs.Add($d) }
            }
        }
        foreach ($key in $rightProps.Keys) {
            if (-not $leftProps.ContainsKey($key)) {
                [void]$diffs.Add([PSCustomObject]@{ Path = "$($Path).$($key)"; Type = 'missing_in_v1'; V1 = $null; V2 = "$($rightProps[$key])" })
            }
        }
        return $diffs
    }

    if ($Left -is [System.Collections.IList] -and $Right -is [System.Collections.IList]) {
        $leftArr = @($Left)
        $rightArr = @($Right)
        if ($leftArr.Count -ne $rightArr.Count) {
            [void]$diffs.Add([PSCustomObject]@{
                Path = "$($Path).length"
                Type = 'array_length_mismatch'
                V1 = $leftArr.Count
                V2 = $rightArr.Count
            })
        }
        $minLen = [math]::Min($leftArr.Count, $rightArr.Count)
        for ($i = 0; $i -lt $minLen; $i++) {
            $childDiffs = Compare-JsonDeep -Left $leftArr[$i] -Right $rightArr[$i] -Path "$($Path)[$($i)]"
            foreach ($d in $childDiffs) { [void]$diffs.Add($d) }
        }
        return $diffs
    }

    if ("$Left" -ne "$Right") {
        [void]$diffs.Add([PSCustomObject]@{ Path = $Path; Type = 'value_mismatch'; V1 = "$Left"; V2 = "$Right" })
    }

    return $diffs
}

$fileResults = [System.Collections.ArrayList]::new()

foreach ($fileName in $filesToCompare) {
    $v1Path = Join-Path $V1RunDir $fileName
    $v2Path = Join-Path $V2RunDir $fileName

    $v1Exists = Test-Path -LiteralPath $v1Path
    $v2Exists = Test-Path -LiteralPath $v2Path

    $result = [ordered]@{
        file         = $fileName
        v1Exists     = $v1Exists
        v2Exists     = $v2Exists
        status       = 'unknown'
        totalDiffs   = 0
        diffsByType  = @{}
        sampleDiffs  = @()
    }

    if (-not $v1Exists -and -not $v2Exists) {
        $result.status = 'both_missing'
        [void]$fileResults.Add([PSCustomObject]$result)
        continue
    }
    if (-not $v1Exists) {
        $result.status = 'v1_missing'
        [void]$fileResults.Add([PSCustomObject]$result)
        continue
    }
    if (-not $v2Exists) {
        $result.status = 'v2_missing'
        [void]$fileResults.Add([PSCustomObject]$result)
        continue
    }

    try {
        $v1Raw = Get-Content -LiteralPath $v1Path -Raw -Encoding UTF8 | ConvertFrom-Json
        $v2Raw = Get-Content -LiteralPath $v2Path -Raw -Encoding UTF8 | ConvertFrom-Json

        $v1Norm = Normalize-JsonObject -Obj $v1Raw
        $v2Norm = Normalize-JsonObject -Obj $v2Raw

        $diffs = @(Compare-JsonDeep -Left $v1Norm -Right $v2Norm)

        $result.totalDiffs = $diffs.Count
        $result.diffsByType = @{}
        $diffs | Group-Object Type | ForEach-Object {
            $result.diffsByType[$_.Name] = $_.Count
        }
        $result.sampleDiffs = @($diffs | Select-Object -First 10)

        if ($diffs.Count -eq 0) {
            $result.status = 'match'
        } else {
            $result.status = 'differences'
        }
    } catch {
        $result.status = 'parse_error'
        $result.error = $_.Exception.Message
    }

    [void]$fileResults.Add([PSCustomObject]$result)
}

$totalFiles = $fileResults.Count
$matchCount = @($fileResults | Where-Object { $_.status -eq 'match' }).Count
$diffCount  = @($fileResults | Where-Object { $_.status -eq 'differences' }).Count
$missingCount = @($fileResults | Where-Object { $_.status -like '*missing*' }).Count

$report = [ordered]@{
    generated    = (Get-Date).ToString('yyyy-MM-dd HH:mm:ss')
    v1RunDir     = $V1RunDir
    v2RunDir     = $V2RunDir
    summary      = [ordered]@{
        totalFiles    = $totalFiles
        matches       = $matchCount
        differences   = $diffCount
        missing       = $missingCount
        matchPercent  = if ($totalFiles -gt 0) { [math]::Round(($matchCount / $totalFiles) * 100, 1) } else { 0 }
    }
    files        = @($fileResults)
}

$reportJsonPath = Join-Path $OutputDir 'comparison_report.json'
$report | ConvertTo-Json -Depth 10 | Set-Content -LiteralPath $reportJsonPath -Encoding UTF8

$mdLines = [System.Collections.Generic.List[string]]::new()
$mdLines.Add('# V1 vs V2 Comparison Report')
$mdLines.Add('')
$mdLines.Add("Generated: $($report.generated)")
$mdLines.Add("V1 run: ``$V1RunDir``")
$mdLines.Add("V2 run: ``$V2RunDir``")
$mdLines.Add('')
$mdLines.Add('## Summary')
$mdLines.Add('')
$mdLines.Add("| Metric | Value |")
$mdLines.Add("|---|---:|")
$mdLines.Add("| Total files compared | $($totalFiles) |")
$mdLines.Add("| Exact matches | $($matchCount) |")
$mdLines.Add("| With differences | $($diffCount) |")
$mdLines.Add("| Missing files | $($missingCount) |")
$mdLines.Add("| Match rate | $($report.summary.matchPercent)% |")
$mdLines.Add('')

$mdLines.Add('## Per-File Results')
$mdLines.Add('')
$mdLines.Add('| File | Status | Diffs | Details |')
$mdLines.Add('|---|---|---:|---|')

foreach ($fr in $fileResults) {
    $details = ''
    if ($fr.diffsByType -and $fr.diffsByType.Count -gt 0) {
        $parts = @()
        foreach ($k in $fr.diffsByType.Keys) { $parts += "$($k): $($fr.diffsByType[$k])" }
        $details = $parts -join ', '
    }
    $statusIcon = switch ($fr.status) {
        'match'       { 'PASS' }
        'differences' { 'DIFF' }
        'v2_missing'  { 'V2 MISSING' }
        'v1_missing'  { 'V1 MISSING' }
        default       { $fr.status.ToUpper() }
    }
    $mdLines.Add("| $($fr.file) | $($statusIcon) | $($fr.totalDiffs) | $($details) |")
}

$mdLines.Add('')

foreach ($fr in $fileResults) {
    if ($fr.status -eq 'differences' -and $fr.sampleDiffs.Count -gt 0) {
        $mdLines.Add("### $($fr.file) — Sample Differences")
        $mdLines.Add('')
        $mdLines.Add('| Path | Type | V1 | V2 |')
        $mdLines.Add('|---|---|---|---|')
        foreach ($d in $fr.sampleDiffs) {
            $v1Val = if ($d.V1) { "$($d.V1)".Substring(0, [math]::Min("$($d.V1)".Length, 80)) } else { '(null)' }
            $v2Val = if ($d.V2) { "$($d.V2)".Substring(0, [math]::Min("$($d.V2)".Length, 80)) } else { '(null)' }
            $mdLines.Add("| ``$($d.Path)`` | $($d.Type) | $($v1Val) | $($v2Val) |")
        }
        $mdLines.Add('')
    }
}

$reportMdPath = Join-Path $OutputDir 'comparison_report.md'
Set-Content -LiteralPath $reportMdPath -Value ($mdLines -join "`r`n") -Encoding UTF8

Write-LogMessage "Comparison complete:" -Level INFO
Write-LogMessage "  Match rate: $($report.summary.matchPercent)% ($($matchCount)/$($totalFiles))" -Level INFO
Write-LogMessage "  JSON report: $($reportJsonPath)" -Level INFO
Write-LogMessage "  Markdown report: $($reportMdPath)" -Level INFO
