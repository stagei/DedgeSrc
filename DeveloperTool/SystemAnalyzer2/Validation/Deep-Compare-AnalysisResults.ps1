<#
.SYNOPSIS
    Deep value-level comparison of every field in AnalysisResults per profile.
    Reports ALL differences, not just structural ones.
#>
[CmdletBinding()]
param(
    [string]$ProjectRoot = (Split-Path $PSScriptRoot)
)

$ErrorActionPreference = 'Stop'
$resultDir = Join-Path $PSScriptRoot 'Deep-Compare-AnalysisResults'
New-Item -ItemType Directory -Path $resultDir -Force | Out-Null
$logFile = Join-Path $resultDir "deep_compare_$(Get-Date -Format 'yyyyMMdd_HHmmss').log"

function Log {
    param([string]$Message, [string]$Level = 'INFO')
    $line = "$(Get-Date -Format 'HH:mm:ss') [$($Level)] $($Message)"
    $color = switch ($Level) { 'PASS' { 'Green' } 'FAIL' { 'Red' } 'WARN' { 'Yellow' } 'DIFF' { 'Magenta' } default { 'Gray' } }
    Write-Host $line -ForegroundColor $color
    $line | Out-File -Append -FilePath $logFile -Encoding utf8
}

$ignoredKeys = @('generated', 'runDuration', 'runFolder', 'startTime', 'endTime', 'cachedAt', 'lastUpdated')

function Compare-JsonDeep {
    param($V1, $V2, [string]$Path = '')
    $diffs = @()

    if ($null -eq $V1 -and $null -eq $V2) { return $diffs }
    if ($null -eq $V1 -or $null -eq $V2) {
        $diffs += "$($Path): V1=$(if($null -eq $V1){'null'}else{'present'}) V2=$(if($null -eq $V2){'null'}else{'present'})"
        return $diffs
    }

    if ($V1 -is [PSCustomObject] -and $V2 -is [PSCustomObject]) {
        $allKeys = @(($V1.PSObject.Properties.Name + $V2.PSObject.Properties.Name) | Sort-Object -Unique)
        foreach ($key in $allKeys) {
            if ($key -in $ignoredKeys) { continue }
            $v1Has = $null -ne $V1.PSObject.Properties[$key]
            $v2Has = $null -ne $V2.PSObject.Properties[$key]
            if ($v1Has -and -not $v2Has) { $diffs += "$($Path).$($key): missing in V2"; continue }
            if (-not $v1Has -and $v2Has) { $diffs += "$($Path).$($key): extra in V2"; continue }
            $diffs += Compare-JsonDeep -V1 $V1.$key -V2 $V2.$key -Path "$($Path).$($key)"
        }
    } elseif ($V1 -is [System.Collections.IEnumerable] -and $V1 -isnot [string] -and $V2 -is [System.Collections.IEnumerable] -and $V2 -isnot [string]) {
        $a1 = @($V1); $a2 = @($V2)
        if ($a1.Count -ne $a2.Count) {
            $diffs += "$($Path)[]: length V1=$($a1.Count) V2=$($a2.Count)"
        }
        $minLen = [math]::Min($a1.Count, $a2.Count)
        $maxCheck = [math]::Min($minLen, 5)
        for ($i = 0; $i -lt $maxCheck; $i++) {
            $diffs += Compare-JsonDeep -V1 $a1[$i] -V2 $a2[$i] -Path "$($Path)[$($i)]"
        }
    } else {
        $s1 = "$V1"; $s2 = "$V2"
        if ($s1 -ne $s2) {
            $show1 = if ($s1.Length -gt 80) { $s1.Substring(0,80) + '...' } else { $s1 }
            $show2 = if ($s2.Length -gt 80) { $s2.Substring(0,80) + '...' } else { $s2 }
            $diffs += "$($Path): '$($show1)' vs '$($show2)'"
        }
    }
    return $diffs
}

$profiles = @('CobDok', 'FkKonto', 'KD_Korn', 'Vareregister')
$totalDiffs = 0

foreach ($profile in $profiles) {
    Log "═══ Profile: $($profile) ═══"
    $v1Dir = Join-Path $ProjectRoot "_old\AnalysisResults\$profile"
    $v2Dir = Join-Path $ProjectRoot "AnalysisResults\$profile"

    $v1Files = Get-ChildItem $v1Dir -Filter '*.json' -File | Where-Object { $_.Name -ne 'analysis_stats.json' }

    foreach ($f in $v1Files) {
        $v2Path = Join-Path $v2Dir $f.Name
        if (-not (Test-Path $v2Path)) { Log "  $($f.Name): MISSING in V2" -Level FAIL; $totalDiffs++; continue }

        $v1Data = Get-Content $f.FullName -Raw -Encoding UTF8 | ConvertFrom-Json
        $v2Data = Get-Content $v2Path -Raw -Encoding UTF8 | ConvertFrom-Json

        # all_sql_tables: V1 used PowerShell's unstable Sort-Object which non-deterministically
        # orders entries with the same tableName+program. V2 uses C# LINQ stable sort.
        # Canonicalize both sides by sorting tableReferences by all key fields.
        if ($f.Name -eq 'all_sql_tables.json' -and $v1Data.tableReferences -and $v2Data.tableReferences) {
            $sortProps = @(
                @{Expression={$_.tableName}},
                @{Expression={$_.program}},
                @{Expression={$_.schema}},
                @{Expression={$_.operation}}
            )
            $v1Data.tableReferences = @($v1Data.tableReferences | Sort-Object -Stable -Property $sortProps)
            $v2Data.tableReferences = @($v2Data.tableReferences | Sort-Object -Stable -Property $sortProps)
        }

        $diffs = Compare-JsonDeep -V1 $v1Data -V2 $v2Data -Path $f.BaseName
        if ($diffs.Count -eq 0) {
            Log "  $($f.Name): IDENTICAL" -Level PASS
        } else {
            Log "  $($f.Name): $($diffs.Count) difference(s)" -Level DIFF
            $showMax = [math]::Min($diffs.Count, 10)
            for ($i = 0; $i -lt $showMax; $i++) { Log "    $($diffs[$i])" -Level DIFF }
            if ($diffs.Count -gt $showMax) { Log "    ... and $($diffs.Count - $showMax) more" -Level DIFF }
            $totalDiffs += $diffs.Count
        }
    }

    $v2Only = Get-ChildItem $v2Dir -Filter '*.json' -File | Where-Object { $_.Name -ne 'analysis_stats.json' -and -not (Test-Path (Join-Path $v1Dir $_.Name)) }
    foreach ($f in $v2Only) { Log "  $($f.Name): EXTRA in V2 (not in V1)" -Level WARN }
    Log ""
}

Log "═══ TOTAL DIFFERENCES: $($totalDiffs) ═══"
Log "Log: $($logFile)"

return [PSCustomObject]@{ TotalDiffs = $totalDiffs; LogFile = $logFile }
