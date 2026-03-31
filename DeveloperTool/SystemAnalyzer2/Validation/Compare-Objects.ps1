<#
.SYNOPSIS
    Compares AnalysisCommon/Objects (cbl.json and sqltable.json files) between V1 and V2.
.DESCRIPTION
    Checks:
      1. File counts for cbl.json and sqltable.json
      2. Coverage and missing entries
      3. JSON structure spot-checks (key presence and basic values)
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

$v1Dir = Join-Path $ProjectRoot '_old\AnalysisCommon\Objects'
$v2Dir = Join-Path $ProjectRoot 'AnalysisCommon\Objects'
$totalPass = 0; $totalFail = 0; $totalWarn = 0

Log "Compare-Objects — V1 vs V2 AnalysisCommon/Objects"
Log "V1: $($v1Dir)"
Log "V2: $($v2Dir)"
Log ""

foreach ($ext in @('cbl.json', 'sqltable.json')) {
    Log "═══════════════════════════════════════════════════"
    Log "Object type: *.$($ext)"
    Log "═══════════════════════════════════════════════════"

    $v1Files = @(Get-ChildItem $v1Dir -Filter "*.$ext" -File -ErrorAction SilentlyContinue)
    $v2Files = @(Get-ChildItem $v2Dir -Filter "*.$ext" -File -ErrorAction SilentlyContinue)

    Log "  V1 count: $($v1Files.Count)"
    Log "  V2 count: $($v2Files.Count)"

    $coverage = if ($v1Files.Count -gt 0) { [math]::Round($v2Files.Count / $v1Files.Count * 100, 1) } else { 100 }
    if ($coverage -ge 80) {
        Log "  Coverage: $($coverage)%" -Level PASS; $totalPass++
    } elseif ($coverage -ge 50) {
        Log "  Coverage: $($coverage)%" -Level WARN; $totalWarn++
    } else {
        Log "  Coverage: $($coverage)%" -Level FAIL; $totalFail++
    }

    $v1Names = $v1Files | ForEach-Object { $_.Name } | Sort-Object
    $v2Names = $v2Files | ForEach-Object { $_.Name } | Sort-Object
    $onlyInV1 = @($v1Names | Where-Object { $_ -notin $v2Names })
    $onlyInV2 = @($v2Names | Where-Object { $_ -notin $v1Names })
    $common = @($v1Names | Where-Object { $_ -in $v2Names })

    Log "  Common: $($common.Count), Only in V1: $($onlyInV1.Count), Only in V2: $($onlyInV2.Count)"

    if ($onlyInV1.Count -gt 0) {
        $show = if ($onlyInV1.Count -le 20) { $onlyInV1 -join ', ' } else { "$($onlyInV1.Count) files (first 20: $($onlyInV1[0..19] -join ', '))" }
        Log "  Missing in V2: $($show)" -Level WARN; $totalWarn++
    }

    $sampleCount = [math]::Min(10, $common.Count)
    if ($sampleCount -gt 0) {
        $samples = $common | Get-Random -Count $sampleCount
        $matchCount = 0; $diffCount = 0
        foreach ($fname in $samples) {
            try {
                $v1Data = Get-Content (Join-Path $v1Dir $fname) -Raw -Encoding UTF8 | ConvertFrom-Json
                $v2Data = Get-Content (Join-Path $v2Dir $fname) -Raw -Encoding UTF8 | ConvertFrom-Json

                if ($ext -eq 'cbl.json') {
                    $v1Prog = $v1Data.programName
                    $v2Prog = $v2Data.programName
                    if ($v1Prog -eq $v2Prog) { $matchCount++ }
                    else {
                        $diffCount++
                        Log "    $($fname): programName V1='$($v1Prog)' V2='$($v2Prog)'" -Level WARN
                    }
                } elseif ($ext -eq 'sqltable.json') {
                    $v1Tbl = $v1Data.tableName
                    $v2Tbl = $v2Data.tableName
                    if ($v1Tbl -eq $v2Tbl) { $matchCount++ }
                    else {
                        $diffCount++
                        Log "    $($fname): tableName V1='$($v1Tbl)' V2='$($v2Tbl)'" -Level WARN
                    }
                }
            } catch {
                $diffCount++
                Log "    $($fname): parse error — $($_.Exception.Message)" -Level WARN
            }
        }
        if ($diffCount -eq 0) {
            Log "  Spot-check ($($sampleCount) samples): all match" -Level PASS; $totalPass++
        } else {
            Log "  Spot-check ($($sampleCount) samples): $($diffCount) diffs" -Level WARN; $totalWarn++
        }
    }
    Log ""
}

Log "═══════════════════════════════════════════════════"
Log "SUMMARY: $($totalPass) PASS, $($totalFail) FAIL, $($totalWarn) WARN"
Log "═══════════════════════════════════════════════════"
Log "Log: $($logFile)"

return [PSCustomObject]@{ Pass = $totalPass; Fail = $totalFail; Warn = $totalWarn; LogFile = $logFile }
