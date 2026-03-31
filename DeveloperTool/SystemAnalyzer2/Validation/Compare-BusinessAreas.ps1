<#
.SYNOPSIS
    Compares BusinessAreas JSON files between V1 and V2 AnalysisCommon.
.DESCRIPTION
    Checks:
      1. Same business area files exist per profile
      2. Same area names / keys in each file
      3. Program assignment counts match
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

$v1Dir = Join-Path $ProjectRoot '_old\AnalysisCommon\BusinessAreas'
$v2Dir = Join-Path $ProjectRoot 'AnalysisCommon\BusinessAreas'
$profiles = @('CobDok', 'FkKonto', 'KD_Korn', 'Vareregister')
$totalPass = 0; $totalFail = 0; $totalWarn = 0

Log "Compare-BusinessAreas — V1 vs V2 AnalysisCommon/BusinessAreas"
Log "V1: $($v1Dir)"
Log "V2: $($v2Dir)"
Log ""

if (-not (Test-Path $v1Dir)) { Log "V1 folder missing" -Level FAIL; $totalFail++; return }
if (-not (Test-Path $v2Dir)) { Log "V2 folder missing" -Level FAIL; $totalFail++; return }

foreach ($profile in $profiles) {
    $fname = "$($profile)_business_areas.json"
    Log "═══════════════════════════════════════════════════"
    Log "File: $($fname)"
    Log "═══════════════════════════════════════════════════"

    $v1Path = Join-Path $v1Dir $fname
    $v2Path = Join-Path $v2Dir $fname

    if (-not (Test-Path $v1Path)) { Log "  V1 file missing" -Level WARN; $totalWarn++; continue }
    if (-not (Test-Path $v2Path)) { Log "  V2 file missing — not yet generated" -Level WARN; $totalWarn++; continue }

    try {
        $v1Data = Get-Content $v1Path -Raw -Encoding UTF8 | ConvertFrom-Json
        $v2Data = Get-Content $v2Path -Raw -Encoding UTF8 | ConvertFrom-Json

        $v1Keys = @($v1Data.PSObject.Properties.Name | Sort-Object)
        $v2Keys = @($v2Data.PSObject.Properties.Name | Sort-Object)

        if (($v1Keys -join ',') -eq ($v2Keys -join ',')) {
            Log "  Area keys match ($($v1Keys.Count) areas)" -Level PASS; $totalPass++
        } else {
            $missing = @($v1Keys | Where-Object { $_ -notin $v2Keys })
            $extra = @($v2Keys | Where-Object { $_ -notin $v1Keys })
            if ($missing.Count -gt 0) { Log "  Missing areas: $($missing -join ', ')" -Level WARN; $totalWarn++ }
            if ($extra.Count -gt 0) { Log "  Extra areas: $($extra -join ', ')" -Level WARN; $totalWarn++ }
        }

        foreach ($key in $v1Keys) {
            if ($key -notin $v2Keys) { continue }
            $v1Progs = @($v1Data.$key).Count
            $v2Progs = @($v2Data.$key).Count
            if ($v1Progs -eq $v2Progs) {
                Log "  $($key): $($v1Progs) programs (match)" -Level PASS; $totalPass++
            } else {
                $diff = [math]::Abs($v1Progs - $v2Progs)
                $lvl = if ($diff -le 2) { 'WARN' } else { 'FAIL' }
                Log "  $($key): V1=$($v1Progs) V2=$($v2Progs) (diff=$($diff))" -Level $lvl
                if ($lvl -eq 'FAIL') { $totalFail++ } else { $totalWarn++ }
            }
        }
    } catch {
        Log "  Parse error: $($_.Exception.Message)" -Level FAIL; $totalFail++
    }
    Log ""
}

Log "═══════════════════════════════════════════════════"
Log "SUMMARY: $($totalPass) PASS, $($totalFail) FAIL, $($totalWarn) WARN"
Log "═══════════════════════════════════════════════════"
Log "Log: $($logFile)"

return [PSCustomObject]@{ Pass = $totalPass; Fail = $totalFail; Warn = $totalWarn; LogFile = $logFile }
