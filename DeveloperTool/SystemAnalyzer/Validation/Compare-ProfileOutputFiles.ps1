<#
.SYNOPSIS
    Compares per-profile output files between V1 (_old) and V2 (current) AnalysisResults.
.DESCRIPTION
    For each profile (CobDok, FkKonto, KD_Korn, Vareregister), checks that:
      1. All expected files exist in V2
      2. JSON files have the same top-level keys
      3. Program counts and table counts match within tolerance
      4. No files are missing compared to V1
.PARAMETER ProjectRoot
    Root of the SystemAnalyzer project. Default: script parent directory's parent.
#>
[CmdletBinding()]
param(
    [string]$ProjectRoot = (Split-Path $PSScriptRoot)
)

$ErrorActionPreference = 'Stop'
$scriptName = [System.IO.Path]::GetFileNameWithoutExtension($PSCommandPath)
$resultDir = Join-Path $PSScriptRoot $scriptName
New-Item -ItemType Directory -Path $resultDir -Force | Out-Null
$logFile = Join-Path $resultDir "$($scriptName)_$(Get-Date -Format 'yyyyMMdd_HHmmss').log"

function Log {
    param([string]$Message, [string]$Level = 'INFO')
    $line = "$(Get-Date -Format 'HH:mm:ss') [$($Level)] $($Message)"
    Write-Host $line -ForegroundColor $(switch ($Level) { 'PASS' { 'Green' } 'FAIL' { 'Red' } 'WARN' { 'Yellow' } default { 'Gray' } })
    $line | Out-File -Append -FilePath $logFile -Encoding utf8
}

$v1Root = Join-Path $ProjectRoot '_old\AnalysisResults'
$v2Root = Join-Path $ProjectRoot 'AnalysisResults'
$profiles = @('CobDok', 'FkKonto', 'KD_Korn', 'Vareregister')
$totalPass = 0; $totalFail = 0; $totalWarn = 0

Log "Compare-ProfileOutputFiles — V1 vs V2 AnalysisResults"
Log "V1: $($v1Root)"
Log "V2: $($v2Root)"
Log ""

foreach ($profile in $profiles) {
    Log "═══════════════════════════════════════════════════"
    Log "Profile: $($profile)"
    Log "═══════════════════════════════════════════════════"

    $v1Dir = Join-Path $v1Root $profile
    $v2Dir = Join-Path $v2Root $profile

    if (-not (Test-Path $v1Dir)) { Log "V1 folder missing: $($v1Dir)" -Level FAIL; $totalFail++; continue }
    if (-not (Test-Path $v2Dir)) { Log "V2 folder missing: $($v2Dir)" -Level FAIL; $totalFail++; continue }

    $v1Files = @(Get-ChildItem $v1Dir -File | Where-Object { $_.Name -ne 'analysis_stats.json' })
    $v2Files = @(Get-ChildItem $v2Dir -File | Where-Object { $_.Name -ne 'analysis_stats.json' })

    $v1Names = $v1Files | ForEach-Object { $_.Name } | Sort-Object
    $v2Names = $v2Files | ForEach-Object { $_.Name } | Sort-Object

    $missingInV2 = $v1Names | Where-Object { $_ -notin $v2Names }
    $extraInV2 = $v2Names | Where-Object { $_ -notin $v1Names }

    if ($missingInV2.Count -eq 0) {
        Log "  File presence: all $($v1Names.Count) V1 files present in V2" -Level PASS; $totalPass++
    } else {
        Log "  Missing in V2: $($missingInV2 -join ', ')" -Level FAIL; $totalFail++
    }
    if ($extraInV2.Count -gt 0) {
        Log "  Extra in V2 (OK): $($extraInV2 -join ', ')" -Level WARN; $totalWarn++
    }

    $commonFiles = $v1Names | Where-Object { $_ -in $v2Names }
    foreach ($fname in $commonFiles) {
        if ($fname -match '\.md$') { continue }
        $v1Path = Join-Path $v1Dir $fname
        $v2Path = Join-Path $v2Dir $fname

        try {
            $v1Json = Get-Content $v1Path -Raw -Encoding UTF8 | ConvertFrom-Json
            $v2Json = Get-Content $v2Path -Raw -Encoding UTF8 | ConvertFrom-Json

            $v1Keys = @($v1Json.PSObject.Properties.Name | Sort-Object)
            $v2Keys = @($v2Json.PSObject.Properties.Name | Sort-Object)
            $keyDiff = Compare-Object $v1Keys $v2Keys
            if ($keyDiff.Count -eq 0) {
                Log "  $($fname): top-level keys match ($($v1Keys.Count) keys)" -Level PASS; $totalPass++
            } else {
                $missing = ($keyDiff | Where-Object { $_.SideIndicator -eq '<=' }).InputObject -join ', '
                $extra = ($keyDiff | Where-Object { $_.SideIndicator -eq '=>' }).InputObject -join ', '
                $msg = "  $($fname): key diff —"
                if ($missing) { $msg += " missing=[$($missing)]" }
                if ($extra) { $msg += " extra=[$($extra)]" }
                Log $msg -Level WARN; $totalWarn++
            }

            if ($fname -eq 'dependency_master.json') {
                $v1Progs = if ($v1Json.programs) { @($v1Json.programs).Count } else { 0 }
                $v2Progs = if ($v2Json.programs) { @($v2Json.programs).Count } else { 0 }
                if ($v1Progs -eq $v2Progs) {
                    Log "  $($fname): program count matches ($($v1Progs))" -Level PASS; $totalPass++
                } else {
                    $diff = [math]::Abs($v1Progs - $v2Progs)
                    $pct = if ($v1Progs -gt 0) { [math]::Round($diff / $v1Progs * 100, 1) } else { 0 }
                    $lvl = if ($pct -le 10) { 'WARN' } else { 'FAIL' }
                    Log "  $($fname): program count V1=$($v1Progs) V2=$($v2Progs) (diff=$($diff), $($pct)%)" -Level $lvl
                    if ($lvl -eq 'FAIL') { $totalFail++ } else { $totalWarn++ }
                }
            }

            if ($fname -eq 'all_sql_tables.json') {
                $v1Tables = $v1Json.uniqueTables
                $v2Tables = $v2Json.uniqueTables
                if ($v1Tables -eq $v2Tables) {
                    Log "  $($fname): uniqueTables match ($($v1Tables))" -Level PASS; $totalPass++
                } else {
                    Log "  $($fname): uniqueTables V1=$($v1Tables) V2=$($v2Tables)" -Level WARN; $totalWarn++
                }
            }
        } catch {
            Log "  $($fname): parse error — $($_.Exception.Message)" -Level WARN; $totalWarn++
        }
    }
    Log ""
}

Log "═══════════════════════════════════════════════════"
Log "SUMMARY: $($totalPass) PASS, $($totalFail) FAIL, $($totalWarn) WARN"
Log "═══════════════════════════════════════════════════"
Log "Log: $($logFile)"

return [PSCustomObject]@{ Pass = $totalPass; Fail = $totalFail; Warn = $totalWarn; LogFile = $logFile }
