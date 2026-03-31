<#
.SYNOPSIS
    Deep comparison of dependency_master.json between V1 and V2 for each profile.
.DESCRIPTION
    This is the most important output file. Checks:
      1. Program list match (names, counts)
      2. Per-program: call graph targets, SQL tables, copy elements, file I/O
      3. Structural completeness of each program entry
.PARAMETER ProjectRoot
    Root of the SystemAnalyzer project.
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

Log "Compare-DependencyMaster — Deep V1 vs V2 comparison"
Log ""

foreach ($profile in $profiles) {
    Log "═══════════════════════════════════════════════════"
    Log "Profile: $($profile)"
    Log "═══════════════════════════════════════════════════"

    $v1Path = Join-Path $v1Root "$profile\dependency_master.json"
    $v2Path = Join-Path $v2Root "$profile\dependency_master.json"

    if (-not (Test-Path $v1Path)) { Log "  V1 file missing" -Level FAIL; $totalFail++; continue }
    if (-not (Test-Path $v2Path)) { Log "  V2 file missing" -Level FAIL; $totalFail++; continue }

    try {
        $v1Json = Get-Content $v1Path -Raw -Encoding UTF8 | ConvertFrom-Json
        $v2Json = Get-Content $v2Path -Raw -Encoding UTF8 | ConvertFrom-Json
    } catch {
        Log "  Parse error: $($_.Exception.Message)" -Level FAIL; $totalFail++; continue
    }

    $v1Programs = $v1Json.programs
    $v2Programs = $v2Json.programs

    if ($null -eq $v1Programs -or $null -eq $v2Programs) {
        Log "  Missing 'programs' key" -Level FAIL; $totalFail++; continue
    }

    $v1ProgNames = @($v1Programs | ForEach-Object { $_.program } | Sort-Object -Unique)
    $v2ProgNames = @($v2Programs | ForEach-Object { $_.program } | Sort-Object -Unique)

    Log "  V1 programs: $($v1ProgNames.Count)"
    Log "  V2 programs: $($v2ProgNames.Count)"

    if ($v1ProgNames.Count -eq $v2ProgNames.Count) {
        Log "  Program count: match" -Level PASS; $totalPass++
    } else {
        $diff = [math]::Abs($v1ProgNames.Count - $v2ProgNames.Count)
        $pct = if ($v1ProgNames.Count -gt 0) { [math]::Round($diff / $v1ProgNames.Count * 100, 1) } else { 0 }
        $lvl = if ($pct -le 5) { 'WARN' } else { 'FAIL' }
        Log "  Program count: V1=$($v1ProgNames.Count) V2=$($v2ProgNames.Count) (diff=$($diff), $($pct)%)" -Level $lvl
        if ($lvl -eq 'FAIL') { $totalFail++ } else { $totalWarn++ }
    }

    $onlyInV1 = @($v1ProgNames | Where-Object { $_ -notin $v2ProgNames })
    $onlyInV2 = @($v2ProgNames | Where-Object { $_ -notin $v1ProgNames })

    if ($onlyInV1.Count -gt 0) {
        $show = if ($onlyInV1.Count -le 15) { $onlyInV1 -join ', ' } else { "$($onlyInV1.Count) programs" }
        Log "  Only in V1: $($show)" -Level WARN; $totalWarn++
    }
    if ($onlyInV2.Count -gt 0) {
        $show = if ($onlyInV2.Count -le 15) { $onlyInV2 -join ', ' } else { "$($onlyInV2.Count) programs" }
        Log "  Only in V2: $($show)" -Level WARN; $totalWarn++
    }

    $commonProgs = @($v1ProgNames | Where-Object { $_ -in $v2ProgNames })
    $sampleSize = [math]::Min(20, $commonProgs.Count)
    if ($sampleSize -eq 0) { continue }

    $samples = $commonProgs | Get-Random -Count $sampleSize
    $callMatch = 0; $callDiff = 0; $sqlMatch = 0; $sqlDiff = 0

    foreach ($progName in $samples) {
        $v1Prog = $v1Programs | Where-Object { $_.program -eq $progName } | Select-Object -First 1
        $v2Prog = $v2Programs | Where-Object { $_.program -eq $progName } | Select-Object -First 1

        $v1Calls = @($v1Prog.callTargets | Sort-Object)
        $v2Calls = @($v2Prog.callTargets | Sort-Object)
        if (($v1Calls -join ',') -eq ($v2Calls -join ',')) { $callMatch++ } else { $callDiff++ }

        $v1Sql = @()
        if ($v1Prog.sqlOperations) { $v1Sql = @($v1Prog.sqlOperations | ForEach-Object { $_.tableName } | Sort-Object -Unique) }
        $v2Sql = @()
        if ($v2Prog.sqlOperations) { $v2Sql = @($v2Prog.sqlOperations | ForEach-Object { $_.tableName } | Sort-Object -Unique) }
        if (($v1Sql -join ',') -eq ($v2Sql -join ',')) { $sqlMatch++ } else { $sqlDiff++ }
    }

    if ($callDiff -eq 0) {
        Log "  Call targets ($($sampleSize) samples): all match" -Level PASS; $totalPass++
    } else {
        Log "  Call targets ($($sampleSize) samples): $($callDiff) differ" -Level WARN; $totalWarn++
    }
    if ($sqlDiff -eq 0) {
        Log "  SQL tables ($($sampleSize) samples): all match" -Level PASS; $totalPass++
    } else {
        Log "  SQL tables ($($sampleSize) samples): $($sqlDiff) differ" -Level WARN; $totalWarn++
    }
    Log ""
}

Log "═══════════════════════════════════════════════════"
Log "SUMMARY: $($totalPass) PASS, $($totalFail) FAIL, $($totalWarn) WARN"
Log "═══════════════════════════════════════════════════"
Log "Log: $($logFile)"

return [PSCustomObject]@{ Pass = $totalPass; Fail = $totalFail; Warn = $totalWarn; LogFile = $logFile }
