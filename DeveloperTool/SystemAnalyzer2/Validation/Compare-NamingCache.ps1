<#
.SYNOPSIS
    Compares the Naming cache (TableNames, ColumnNames, ProgramNames) between V1 and V2.
.DESCRIPTION
    Checks:
      1. File counts in each naming subfolder
      2. Coverage percentage (V2 files / V1 files)
      3. Spot-checks JSON structure of naming entries
      4. Reports missing and extra entries
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

$v1Naming = Join-Path $ProjectRoot '_old\AnalysisCommon\Naming'
$v2Naming = Join-Path $ProjectRoot 'AnalysisCommon\Naming'
$categories = @('TableNames', 'ColumnNames', 'ProgramNames')
$totalPass = 0; $totalFail = 0; $totalWarn = 0

Log "Compare-NamingCache — V1 vs V2 AnalysisCommon/Naming"
Log "V1: $($v1Naming)"
Log "V2: $($v2Naming)"
Log ""

foreach ($cat in $categories) {
    Log "═══════════════════════════════════════════════════"
    Log "Category: $($cat)"
    Log "═══════════════════════════════════════════════════"

    $v1Dir = Join-Path $v1Naming $cat
    $v2Dir = Join-Path $v2Naming $cat

    if (-not (Test-Path $v1Dir)) { Log "V1 folder missing: $($v1Dir)" -Level FAIL; $totalFail++; continue }
    if (-not (Test-Path $v2Dir)) { Log "V2 folder missing: $($v2Dir)" -Level FAIL; $totalFail++; continue }

    $v1Files = @(Get-ChildItem $v1Dir -Filter '*.json' -File)
    $v2Files = @(Get-ChildItem $v2Dir -Filter '*.json' -File)

    Log "  V1 count: $($v1Files.Count)"
    Log "  V2 count: $($v2Files.Count)"

    $coverage = if ($v1Files.Count -gt 0) { [math]::Round($v2Files.Count / $v1Files.Count * 100, 1) } else { 100 }
    if ($coverage -ge 80) {
        Log "  Coverage: $($coverage)% ($($v2Files.Count)/$($v1Files.Count))" -Level PASS; $totalPass++
    } elseif ($coverage -ge 50) {
        Log "  Coverage: $($coverage)% ($($v2Files.Count)/$($v1Files.Count))" -Level WARN; $totalWarn++
    } else {
        Log "  Coverage: $($coverage)% ($($v2Files.Count)/$($v1Files.Count)) — significantly less than V1" -Level FAIL; $totalFail++
    }

    $v1Names = $v1Files | ForEach-Object { $_.BaseName } | Sort-Object
    $v2Names = $v2Files | ForEach-Object { $_.BaseName } | Sort-Object

    $onlyInV1 = @($v1Names | Where-Object { $_ -notin $v2Names })
    $onlyInV2 = @($v2Names | Where-Object { $_ -notin $v1Names })
    $common = @($v1Names | Where-Object { $_ -in $v2Names })

    Log "  Common: $($common.Count), Only in V1: $($onlyInV1.Count), Only in V2: $($onlyInV2.Count)"

    if ($onlyInV1.Count -gt 0 -and $onlyInV1.Count -le 20) {
        Log "  Missing in V2: $($onlyInV1 -join ', ')" -Level WARN; $totalWarn++
    } elseif ($onlyInV1.Count -gt 20) {
        Log "  Missing in V2: $($onlyInV1.Count) entries (first 20: $($onlyInV1[0..19] -join ', '))" -Level WARN; $totalWarn++
    }

    $sampleCount = [math]::Min(5, $common.Count)
    if ($sampleCount -gt 0) {
        $samples = $common | Get-Random -Count $sampleCount
        $structureOk = 0; $structureBad = 0
        foreach ($name in $samples) {
            try {
                $v1Data = Get-Content (Join-Path $v1Dir "$($name).json") -Raw -Encoding UTF8 | ConvertFrom-Json
                $v2Data = Get-Content (Join-Path $v2Dir "$($name).json") -Raw -Encoding UTF8 | ConvertFrom-Json
                $v1Keys = @($v1Data.PSObject.Properties.Name | Sort-Object)
                $v2Keys = @($v2Data.PSObject.Properties.Name | Sort-Object)

                $expectedKey = switch ($cat) {
                    'TableNames' { 'futureName' }
                    'ColumnNames' { 'futureName' }
                    'ProgramNames' { 'futureProjectName' }
                }

                $v1Has = $v1Keys -contains $expectedKey
                $v2Has = $v2Keys -contains $expectedKey
                if ($v2Has) { $structureOk++ } else { $structureBad++ }
            } catch {
                $structureBad++
            }
        }
        if ($structureBad -eq 0) {
            Log "  Structure check ($($sampleCount) samples): all have expected keys" -Level PASS; $totalPass++
        } else {
            Log "  Structure check ($($sampleCount) samples): $($structureBad) missing expected key" -Level WARN; $totalWarn++
        }
    }
    Log ""
}

Log "═══════════════════════════════════════════════════"
Log "SUMMARY: $($totalPass) PASS, $($totalFail) FAIL, $($totalWarn) WARN"
Log "═══════════════════════════════════════════════════"
Log "Log: $($logFile)"

return [PSCustomObject]@{ Pass = $totalPass; Fail = $totalFail; Warn = $totalWarn; LogFile = $logFile }
