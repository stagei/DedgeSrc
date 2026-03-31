#!/usr/bin/env pwsh
<#
.SYNOPSIS
    Compares V1 and V2 analysis results across profiles with deep JSON normalization.
.DESCRIPTION
    For each profile, locates the latest _History snapshot (or profile root as fallback),
    normalizes JSON by stripping timestamps and sorting all arrays by their primary keys,
    then performs a deep comparison. Outputs per-profile JSON/Markdown reports and a summary.
.PARAMETER ProfileNames
    Profiles to compare. Default: CobDok, FkKonto, KD_Korn, Vareregister.
.PARAMETER V1DataRoot
    Root directory for V1 results. Default: AnalysisResults (relative to script root).
.PARAMETER V2DataRoot
    Root directory for V2 results. Default: AnalysisResultsV2 (relative to script root).
.PARAMETER OutputDir
    Directory where comparison reports are written. Default: C:\temp\V1vsV2_comparison.
.EXAMPLE
    .\Compare-AllProfiles-V1vsV2.ps1
.EXAMPLE
    .\Compare-AllProfiles-V1vsV2.ps1 -ProfileNames CobDok -OutputDir C:\temp\compare_cobdok
#>

[CmdletBinding()]
param(
    [string[]]$ProfileNames = @('CobDok', 'FkKonto', 'KD_Korn', 'Vareregister'),

    [string]$V1DataRoot = 'AnalysisResults',

    [string]$V2DataRoot = 'AnalysisResultsV2',

    [string]$OutputDir = 'C:\temp\V1vsV2_comparison'
)

$ErrorActionPreference = 'Stop'
Import-Module GlobalFunctions -Force

$scriptRoot = $PSScriptRoot

if (-not [System.IO.Path]::IsPathRooted($V1DataRoot)) {
    $V1DataRoot = Join-Path $scriptRoot $V1DataRoot
}
if (-not [System.IO.Path]::IsPathRooted($V2DataRoot)) {
    $V2DataRoot = Join-Path $scriptRoot $V2DataRoot
}

$ComparisonFiles = @(
    'dependency_master.json'
    'all_total_programs.json'
    'all_sql_tables.json'
    'all_copy_elements.json'
    'all_call_graph.json'
    'all_file_io.json'
    'source_verification.json'
    'db2_table_validation.json'
    'applied_exclusions.json'
    'standard_cobol_filtered.json'
    'classified_programs.json'
    'business_areas.json'
)

$TimestampFields = @(
    'generated'
    'timestamp'
    'lastRun'
    'analysisTimestamp'
    'runTimestamp'
    'analyzedAt'
)

#region ── Helper Functions ──

function Get-LatestHistoryDir {
    <#
    .SYNOPSIS
        Returns the path containing the latest analysis JSON files for a profile.
        Checks _History subdirectories first, falls back to the profile root.
    #>
    param(
        [string]$DataRoot,
        [string]$ProfileName
    )

    $profileDir = Join-Path $DataRoot $ProfileName
    if (-not (Test-Path $profileDir)) { return $null }

    $historyDir = Join-Path $profileDir '_History'
    if (Test-Path $historyDir) {
        $subDirs = Get-ChildItem -Path $historyDir -Directory | Sort-Object Name -Descending
        foreach ($dir in $subDirs) {
            $jsonFiles = Get-ChildItem -Path $dir.FullName -Filter '*.json' -File -ErrorAction SilentlyContinue
            if ($jsonFiles.Count -gt 0) {
                return $dir.FullName
            }
        }
    }

    $rootJsonFiles = Get-ChildItem -Path $profileDir -Filter '*.json' -File -ErrorAction SilentlyContinue
    if ($rootJsonFiles.Count -gt 0) {
        return $profileDir
    }

    return $null
}

function Get-SortKey {
    <#
    .SYNOPSIS
        Computes a deterministic sort key for an object based on known schema patterns.
    #>
    param($Item)

    if ($Item -is [string]) { return $Item }
    if ($Item -is [ValueType]) { return "$($Item)" }
    if ($Item -is [System.Collections.IDictionary] -or $Item.PSObject) {
        $obj = $Item

        # Known composite keys (most specific first)
        if ($null -ne (Get-Member -InputObject $obj -Name 'caller' -ErrorAction SilentlyContinue) -and
            $null -ne (Get-Member -InputObject $obj -Name 'callee' -ErrorAction SilentlyContinue)) {
            return "$($obj.caller)|$($obj.callee)"
        }
        if ($null -ne (Get-Member -InputObject $obj -Name 'program' -ErrorAction SilentlyContinue) -and
            $null -ne (Get-Member -InputObject $obj -Name 'tableName' -ErrorAction SilentlyContinue) -and
            $null -ne (Get-Member -InputObject $obj -Name 'operation' -ErrorAction SilentlyContinue)) {
            $schemaVal = if ($null -ne (Get-Member -InputObject $obj -Name 'schema' -ErrorAction SilentlyContinue)) { $obj.schema } else { '' }
            return "$($obj.program)|$($schemaVal)|$($obj.tableName)|$($obj.operation)"
        }
        if ($null -ne (Get-Member -InputObject $obj -Name 'program' -ErrorAction SilentlyContinue) -and
            $null -ne (Get-Member -InputObject $obj -Name 'logicalName' -ErrorAction SilentlyContinue)) {
            return "$($obj.program)|$($obj.logicalName)"
        }
        if ($null -ne (Get-Member -InputObject $obj -Name 'schema' -ErrorAction SilentlyContinue) -and
            $null -ne (Get-Member -InputObject $obj -Name 'tableName' -ErrorAction SilentlyContinue) -and
            $null -ne (Get-Member -InputObject $obj -Name 'operation' -ErrorAction SilentlyContinue)) {
            return "$($obj.schema)|$($obj.tableName)|$($obj.operation)"
        }
        if ($null -ne (Get-Member -InputObject $obj -Name 'qualifiedName' -ErrorAction SilentlyContinue)) {
            return "$($obj.qualifiedName)"
        }

        # Single primary keys
        foreach ($keyName in @('program', 'name', 'logicalName', 'qualifiedName', 'area', 'id')) {
            if ($null -ne (Get-Member -InputObject $obj -Name $keyName -ErrorAction SilentlyContinue)) {
                return "$($obj.$keyName)"
            }
        }

        # Fallback: first string property value
        foreach ($prop in $obj.PSObject.Properties) {
            if ($prop.Value -is [string]) { return $prop.Value }
        }

        return ($obj | ConvertTo-Json -Compress -Depth 1)
    }

    return "$($Item)"
}

function Get-SortedArrayItems {
    <#
    .SYNOPSIS
        Sorts an array of items using schema-aware sort keys.
    #>
    param([array]$Items)

    if ($null -eq $Items -or $Items.Count -le 1) { return $Items }

    return @($Items | Sort-Object { Get-SortKey $_ })
}

function ConvertTo-NormalizedJson {
    <#
    .SYNOPSIS
        Recursively normalizes a parsed JSON object: strips timestamp fields,
        sorts all arrays deterministically, and recurses into nested structures.
    #>
    param($Obj)

    if ($null -eq $Obj) { return $null }

    if ($Obj -is [System.Collections.IList]) {
        $normalized = @()
        foreach ($item in $Obj) {
            $normalized += , (ConvertTo-NormalizedJson $item)
        }
        return , (Get-SortedArrayItems $normalized)
    }

    if ($Obj -is [PSCustomObject]) {
        $result = [ordered]@{}
        foreach ($prop in ($Obj.PSObject.Properties | Sort-Object Name)) {
            if ($prop.Name -in $TimestampFields) { continue }

            $val = $prop.Value
            if ($val -is [System.Collections.IList]) {
                $normalizedArray = @()
                foreach ($item in $val) {
                    $normalizedArray += , (ConvertTo-NormalizedJson $item)
                }
                $result[$prop.Name] = @(Get-SortedArrayItems $normalizedArray)
            }
            elseif ($val -is [PSCustomObject]) {
                $result[$prop.Name] = ConvertTo-NormalizedJson $val
            }
            else {
                $result[$prop.Name] = $val
            }
        }
        return [PSCustomObject]$result
    }

    return $Obj
}

function Compare-DeepJson {
    <#
    .SYNOPSIS
        Deeply compares two normalized objects. Returns a list of difference descriptors.
    #>
    param(
        $V1,
        $V2,
        [string]$Path = '$'
    )

    $diffs = [System.Collections.Generic.List[object]]::new()

    if ($null -eq $V1 -and $null -eq $V2) { return $diffs }
    if ($null -eq $V1 -and $null -ne $V2) {
        $diffs.Add(@{ path = $Path; type = 'added_in_v2'; v1 = $null; v2 = $V2 })
        return $diffs
    }
    if ($null -ne $V1 -and $null -eq $V2) {
        $diffs.Add(@{ path = $Path; type = 'removed_in_v2'; v1 = $V1; v2 = $null })
        return $diffs
    }

    if ($V1 -is [PSCustomObject] -and $V2 -is [PSCustomObject]) {
        $props1 = @{}; $V1.PSObject.Properties | ForEach-Object { $props1[$_.Name] = $_.Value }
        $props2 = @{}; $V2.PSObject.Properties | ForEach-Object { $props2[$_.Name] = $_.Value }

        $allKeys = @($props1.Keys) + @($props2.Keys) | Sort-Object -Unique

        foreach ($key in $allKeys) {
            $childPath = "$($Path).$($key)"
            $has1 = $props1.ContainsKey($key)
            $has2 = $props2.ContainsKey($key)

            if ($has1 -and -not $has2) {
                $diffs.Add(@{ path = $childPath; type = 'removed_in_v2'; v1 = $props1[$key]; v2 = $null })
            }
            elseif (-not $has1 -and $has2) {
                $diffs.Add(@{ path = $childPath; type = 'added_in_v2'; v1 = $null; v2 = $props2[$key] })
            }
            else {
                $childDiffs = @(Compare-DeepJson -V1 $props1[$key] -V2 $props2[$key] -Path $childPath)
                if ($childDiffs.Count -gt 0) { $diffs.AddRange($childDiffs) }
            }
        }
        return $diffs
    }

    if ($V1 -is [System.Collections.IList] -and $V2 -is [System.Collections.IList]) {
        $max = [Math]::Max($V1.Count, $V2.Count)
        for ($i = 0; $i -lt $max; $i++) {
            $childPath = "$($Path)[$($i)]"
            if ($i -ge $V1.Count) {
                $diffs.Add(@{ path = $childPath; type = 'added_in_v2'; v1 = $null; v2 = $V2[$i] })
            }
            elseif ($i -ge $V2.Count) {
                $diffs.Add(@{ path = $childPath; type = 'removed_in_v2'; v1 = $V1[$i]; v2 = $null })
            }
            else {
                $childDiffs = @(Compare-DeepJson -V1 $V1[$i] -V2 $V2[$i] -Path $childPath)
                if ($childDiffs.Count -gt 0) { $diffs.AddRange($childDiffs) }
            }
        }
        return $diffs
    }

    # Scalar comparison
    $s1 = if ($null -eq $V1) { '' } else { "$($V1)" }
    $s2 = if ($null -eq $V2) { '' } else { "$($V2)" }

    if ($s1 -cne $s2) {
        $diffs.Add(@{ path = $Path; type = 'value_changed'; v1 = $V1; v2 = $V2 })
    }

    return $diffs
}

function Format-DiffValue {
    param($Value, [int]$MaxLen = 120)
    if ($null -eq $Value) { return '(null)' }
    if ($Value -is [string]) {
        if ($Value.Length -gt $MaxLen) { return $Value.Substring(0, $MaxLen) + '...' }
        return $Value
    }
    if ($Value -is [ValueType]) { return "$($Value)" }
    $json = $Value | ConvertTo-Json -Compress -Depth 3
    if ($json.Length -gt $MaxLen) { return $json.Substring(0, $MaxLen) + '...' }
    return $json
}

#endregion

#region ── Main Execution ──

Write-LogMessage '═══════════════════════════════════════════════════════════════════════' -Level INFO
Write-LogMessage '  V1 vs V2 Analysis Results Comparison' -Level INFO
Write-LogMessage "  V1 Root: $($V1DataRoot)" -Level INFO
Write-LogMessage "  V2 Root: $($V2DataRoot)" -Level INFO
Write-LogMessage "  Profiles: $($ProfileNames -join ', ')" -Level INFO
Write-LogMessage "  Output: $($OutputDir)" -Level INFO
Write-LogMessage '═══════════════════════════════════════════════════════════════════════' -Level INFO

if (-not (Test-Path $OutputDir)) {
    New-Item -Path $OutputDir -ItemType Directory -Force | Out-Null
    Write-LogMessage "Created output directory: $($OutputDir)" -Level INFO
}

$summaryRows = [System.Collections.Generic.List[object]]::new()

foreach ($profileName in $ProfileNames) {
    Write-LogMessage '' -Level INFO
    Write-LogMessage "───────────────────────────────────────────────────────────────────────" -Level INFO
    Write-LogMessage "  Profile: $($profileName)" -Level INFO
    Write-LogMessage "───────────────────────────────────────────────────────────────────────" -Level INFO

    $v1Dir = Get-LatestHistoryDir -DataRoot $V1DataRoot -ProfileName $profileName
    $v2Dir = Get-LatestHistoryDir -DataRoot $V2DataRoot -ProfileName $profileName

    Write-LogMessage "V1 source: $(if ($v1Dir) { $v1Dir } else { '(not found)' })" -Level INFO
    Write-LogMessage "V2 source: $(if ($v2Dir) { $v2Dir } else { '(not found)' })" -Level INFO

    if (-not $v1Dir -and -not $v2Dir) {
        Write-LogMessage "Both V1 and V2 missing for profile $($profileName) — skipping" -Level WARN
        $summaryRows.Add([PSCustomObject]@{
            Profile     = $profileName
            Compared    = 0
            Matches     = 0
            Differences = 0
            Status      = 'SKIP'
            Note        = 'Both V1 and V2 not found'
        })
        continue
    }

    $profileOutDir = Join-Path $OutputDir $profileName
    if (-not (Test-Path $profileOutDir)) {
        New-Item -Path $profileOutDir -ItemType Directory -Force | Out-Null
    }

    $profileResults = [System.Collections.Generic.List[object]]::new()
    $totalCompared = 0
    $totalMatch = 0
    $totalDiff = 0

    foreach ($fileName in $ComparisonFiles) {
        $v1File = if ($v1Dir) { Join-Path $v1Dir $fileName } else { $null }
        $v2File = if ($v2Dir) { Join-Path $v2Dir $fileName } else { $null }

        $v1Exists = $v1File -and (Test-Path $v1File)
        $v2Exists = $v2File -and (Test-Path $v2File)

        $totalCompared++

        # Both missing = match
        if (-not $v1Exists -and -not $v2Exists) {
            Write-LogMessage "  $($fileName): both missing — counted as MATCH" -Level DEBUG
            $totalMatch++
            $profileResults.Add([PSCustomObject]@{
                file    = $fileName
                status  = 'MATCH'
                reason  = 'Both files absent'
                diffCount = 0
                diffs   = @()
            })
            continue
        }

        # One side missing
        if (-not $v1Exists) {
            Write-LogMessage "  $($fileName): V1 missing, V2 exists — DIFF" -Level WARN
            $totalDiff++
            $profileResults.Add([PSCustomObject]@{
                file    = $fileName
                status  = 'DIFF'
                reason  = 'V1 file missing; V2 exists'
                diffCount = 1
                diffs   = @(@{ path = '$'; type = 'v1_missing'; v1 = $null; v2 = '(file exists)' })
            })
            continue
        }
        if (-not $v2Exists) {
            Write-LogMessage "  $($fileName): V1 exists, V2 missing — DIFF" -Level WARN
            $totalDiff++
            $profileResults.Add([PSCustomObject]@{
                file    = $fileName
                status  = 'DIFF'
                reason  = 'V2 file missing; V1 exists'
                diffCount = 1
                diffs   = @(@{ path = '$'; type = 'v2_missing'; v1 = '(file exists)'; v2 = $null })
            })
            continue
        }

        # Both exist — parse, normalize, compare
        try {
            $v1Json = Get-Content -Path $v1File -Raw -Encoding utf8 | ConvertFrom-Json
            $v2Json = Get-Content -Path $v2File -Raw -Encoding utf8 | ConvertFrom-Json
        }
        catch {
            Write-LogMessage "  $($fileName): JSON parse error — $($_.Exception.Message)" -Level ERROR
            $totalDiff++
            $profileResults.Add([PSCustomObject]@{
                file    = $fileName
                status  = 'ERROR'
                reason  = "JSON parse error: $($_.Exception.Message)"
                diffCount = 1
                diffs   = @()
            })
            continue
        }

        $v1Norm = ConvertTo-NormalizedJson $v1Json
        $v2Norm = ConvertTo-NormalizedJson $v2Json

        $diffs = @(Compare-DeepJson -V1 $v1Norm -V2 $v2Norm)

        if ($diffs.Count -eq 0) {
            Write-LogMessage "  $($fileName): MATCH" -Level INFO
            $totalMatch++
            $profileResults.Add([PSCustomObject]@{
                file    = $fileName
                status  = 'MATCH'
                reason  = 'Identical after normalization'
                diffCount = 0
                diffs   = @()
            })
        }
        else {
            Write-LogMessage "  $($fileName): DIFF — $($diffs.Count) difference(s)" -Level WARN
            $totalDiff++
            $profileResults.Add([PSCustomObject]@{
                file      = $fileName
                status    = 'DIFF'
                reason    = "$($diffs.Count) difference(s) found"
                diffCount = $diffs.Count
                diffs     = @($diffs)
            })
        }
    }

    # Write per-profile JSON report
    $profileReport = [PSCustomObject]@{
        profile        = $profileName
        v1Source       = $v1Dir
        v2Source       = $v2Dir
        comparedAt     = (Get-Date).ToString('yyyy-MM-dd HH:mm:ss')
        totalCompared  = $totalCompared
        totalMatches   = $totalMatch
        totalDiffs     = $totalDiff
        overallStatus  = if ($totalDiff -eq 0) { 'PASS' } else { 'FAIL' }
        files          = @($profileResults)
    }

    $jsonOutPath = Join-Path $profileOutDir 'comparison_report.json'
    $profileReport | ConvertTo-Json -Depth 10 | Set-Content -Path $jsonOutPath -Encoding utf8
    Write-LogMessage "JSON report: $($jsonOutPath)" -Level INFO

    # Write per-profile Markdown report
    $md = [System.Text.StringBuilder]::new()
    [void]$md.AppendLine("# V1 vs V2 Comparison — $($profileName)")
    [void]$md.AppendLine('')
    [void]$md.AppendLine("| Item | Value |")
    [void]$md.AppendLine("|------|-------|")
    [void]$md.AppendLine("| V1 Source | ``$($v1Dir)`` |")
    [void]$md.AppendLine("| V2 Source | ``$($v2Dir)`` |")
    [void]$md.AppendLine("| Compared At | $($profileReport.comparedAt) |")
    [void]$md.AppendLine("| Files Compared | $($totalCompared) |")
    [void]$md.AppendLine("| Matches | $($totalMatch) |")
    [void]$md.AppendLine("| Differences | $($totalDiff) |")
    [void]$md.AppendLine("| **Status** | **$($profileReport.overallStatus)** |")
    [void]$md.AppendLine('')
    [void]$md.AppendLine("## File Results")
    [void]$md.AppendLine('')
    [void]$md.AppendLine("| File | Status | Diff Count | Reason |")
    [void]$md.AppendLine("|------|--------|------------|--------|")

    foreach ($fr in $profileResults) {
        $statusIcon = switch ($fr.status) {
            'MATCH' { 'MATCH' }
            'DIFF'  { 'DIFF' }
            'ERROR' { 'ERROR' }
            default { $fr.status }
        }
        [void]$md.AppendLine("| $($fr.file) | $($statusIcon) | $($fr.diffCount) | $($fr.reason) |")
    }

    $diffFiles = @($profileResults | Where-Object { $_.status -eq 'DIFF' -and $_.diffs.Count -gt 0 })
    if ($diffFiles.Count -gt 0) {
        [void]$md.AppendLine('')
        [void]$md.AppendLine("## Difference Details")

        foreach ($df in $diffFiles) {
            [void]$md.AppendLine('')
            [void]$md.AppendLine("### $($df.file)")
            [void]$md.AppendLine('')
            [void]$md.AppendLine("| # | Path | Type | V1 | V2 |")
            [void]$md.AppendLine("|---|------|------|----|----|")

            $idx = 0
            foreach ($d in $df.diffs) {
                $idx++
                if ($idx -gt 50) {
                    [void]$md.AppendLine("| ... | _$($df.diffs.Count - 50) more differences truncated_ | | | |")
                    break
                }
                $v1Val = Format-DiffValue $d.v1 80
                $v2Val = Format-DiffValue $d.v2 80
                # Escape pipes in values for markdown table safety
                $v1Val = $v1Val -replace '\|', '\|'
                $v2Val = $v2Val -replace '\|', '\|'
                [void]$md.AppendLine("| $($idx) | ``$($d.path)`` | $($d.type) | $($v1Val) | $($v2Val) |")
            }
        }
    }

    $mdOutPath = Join-Path $profileOutDir 'comparison_report.md'
    $md.ToString() | Set-Content -Path $mdOutPath -Encoding utf8
    Write-LogMessage "Markdown report: $($mdOutPath)" -Level INFO

    $overallStatus = if ($totalDiff -eq 0) { 'PASS' } else { 'FAIL' }
    Write-LogMessage "Profile $($profileName): $($totalMatch)/$($totalCompared) match — $($overallStatus)" -Level $(if ($overallStatus -eq 'PASS') { 'INFO' } else { 'WARN' })

    $summaryRows.Add([PSCustomObject]@{
        Profile     = $profileName
        Compared    = $totalCompared
        Matches     = $totalMatch
        Differences = $totalDiff
        Status      = $overallStatus
        Note        = ''
    })
}

#endregion

#region ── Summary Report ──

Write-LogMessage '' -Level INFO
Write-LogMessage '═══════════════════════════════════════════════════════════════════════' -Level INFO
Write-LogMessage '  SUMMARY' -Level INFO
Write-LogMessage '═══════════════════════════════════════════════════════════════════════' -Level INFO

$grandTotal   = ($summaryRows | Measure-Object -Property Compared -Sum).Sum
$grandMatch   = ($summaryRows | Measure-Object -Property Matches -Sum).Sum
$grandDiff    = ($summaryRows | Measure-Object -Property Differences -Sum).Sum
$grandStatus  = if ($grandDiff -eq 0 -and ($summaryRows | Where-Object Status -eq 'SKIP').Count -eq 0) { 'PASS' } else { 'FAIL' }

foreach ($row in $summaryRows) {
    Write-LogMessage "  $($row.Profile): $($row.Matches)/$($row.Compared) match — $($row.Status) $($row.Note)" -Level $(if ($row.Status -eq 'PASS') { 'INFO' } else { 'WARN' })
}
Write-LogMessage '' -Level INFO
Write-LogMessage "Grand total: $($grandMatch)/$($grandTotal) match, $($grandDiff) differences — $($grandStatus)" -Level $(if ($grandStatus -eq 'PASS') { 'INFO' } else { 'WARN' })

# Write summary JSON
$summaryJson = [PSCustomObject]@{
    comparedAt     = (Get-Date).ToString('yyyy-MM-dd HH:mm:ss')
    v1DataRoot     = $V1DataRoot
    v2DataRoot     = $V2DataRoot
    profiles       = @($summaryRows)
    grandTotal     = $grandTotal
    grandMatches   = $grandMatch
    grandDiffs     = $grandDiff
    overallStatus  = $grandStatus
}

$summaryJsonPath = Join-Path $OutputDir 'summary.json'
$summaryJson | ConvertTo-Json -Depth 5 | Set-Content -Path $summaryJsonPath -Encoding utf8
Write-LogMessage "Summary JSON: $($summaryJsonPath)" -Level INFO

# Write summary Markdown
$smd = [System.Text.StringBuilder]::new()
[void]$smd.AppendLine('# V1 vs V2 Comparison Summary')
[void]$smd.AppendLine('')
[void]$smd.AppendLine("**Date:** $($summaryJson.comparedAt)")
[void]$smd.AppendLine("**V1 Root:** ``$($V1DataRoot)``")
[void]$smd.AppendLine("**V2 Root:** ``$($V2DataRoot)``")
[void]$smd.AppendLine("**Overall Status:** **$($grandStatus)**")
[void]$smd.AppendLine('')
[void]$smd.AppendLine('## Per-Profile Results')
[void]$smd.AppendLine('')
[void]$smd.AppendLine('| Profile | Compared | Matches | Differences | Status | Note |')
[void]$smd.AppendLine('|---------|----------|---------|-------------|--------|------|')

foreach ($row in $summaryRows) {
    [void]$smd.AppendLine("| $($row.Profile) | $($row.Compared) | $($row.Matches) | $($row.Differences) | **$($row.Status)** | $($row.Note) |")
}

[void]$smd.AppendLine('')
[void]$smd.AppendLine("## Totals")
[void]$smd.AppendLine('')
[void]$smd.AppendLine("| Metric | Value |")
[void]$smd.AppendLine("|--------|-------|")
[void]$smd.AppendLine("| Files Compared | $($grandTotal) |")
[void]$smd.AppendLine("| Matches | $($grandMatch) |")
[void]$smd.AppendLine("| Differences | $($grandDiff) |")
[void]$smd.AppendLine("| **Overall** | **$($grandStatus)** |")

$summaryMdPath = Join-Path $OutputDir 'summary.md'
$smd.ToString() | Set-Content -Path $summaryMdPath -Encoding utf8
Write-LogMessage "Summary Markdown: $($summaryMdPath)" -Level INFO
Write-LogMessage '' -Level INFO
Write-LogMessage "All reports written to: $($OutputDir)" -Level INFO

#endregion
