<#
.SYNOPSIS
    Orchestrator: runs all validation scripts in sequence and produces a final summary.
.DESCRIPTION
    Executes each Compare-*.ps1 script, collects PASS/FAIL/WARN totals, 
    and outputs a consolidated report.
.PARAMETER ProjectRoot
    Root of the SystemAnalyzer project.
#>
[CmdletBinding()]
param(
    [string]$ProjectRoot = (Split-Path $PSScriptRoot)
)

$ErrorActionPreference = 'Stop'
$startTime = Get-Date
$logDir = Join-Path $PSScriptRoot 'Orchestrator'
New-Item -ItemType Directory -Path $logDir -Force | Out-Null
$masterLog = Join-Path $logDir "Run-AllValidations_$(Get-Date -Format 'yyyyMMdd_HHmmss').log"

function MasterLog {
    param([string]$Message, [string]$Level = 'INFO')
    $line = "$(Get-Date -Format 'HH:mm:ss') [$($Level)] $($Message)"
    $color = switch ($Level) { 'PASS' { 'Green' } 'FAIL' { 'Red' } 'WARN' { 'Yellow' } 'HEADER' { 'Cyan' } default { 'White' } }
    Write-Host $line -ForegroundColor $color
    $line | Out-File -Append -FilePath $masterLog -Encoding utf8
}

$scripts = @(
    'Compare-ProfileOutputFiles.ps1',
    'Compare-DependencyMaster.ps1',
    'Compare-NamingCache.ps1',
    'Compare-Objects.ps1',
    'Compare-BusinessAreas.ps1'
)

$grandPass = 0; $grandFail = 0; $grandWarn = 0
$results = @()

MasterLog "╔═══════════════════════════════════════════════════════════════════╗" -Level HEADER
MasterLog "║     SystemAnalyzer V1 vs V2 — Full Validation Suite             ║" -Level HEADER
MasterLog "╚═══════════════════════════════════════════════════════════════════╝" -Level HEADER
MasterLog "Project root: $($ProjectRoot)"
MasterLog "Started: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')"
MasterLog ""

foreach ($script in $scripts) {
    $scriptPath = Join-Path $PSScriptRoot $script
    if (-not (Test-Path $scriptPath)) {
        MasterLog "SKIPPED: $($script) (file not found)" -Level WARN
        $grandWarn++
        continue
    }

    MasterLog ""
    MasterLog "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━" -Level HEADER
    MasterLog "Running: $($script)" -Level HEADER
    MasterLog "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━" -Level HEADER

    try {
        $result = & $scriptPath -ProjectRoot $ProjectRoot
        $p = $result.Pass; $f = $result.Fail; $w = $result.Warn
        $grandPass += $p; $grandFail += $f; $grandWarn += $w

        $status = if ($f -gt 0) { 'FAIL' } elseif ($w -gt 0) { 'WARN' } else { 'PASS' }
        MasterLog "  => $($script): $($p) PASS, $($f) FAIL, $($w) WARN" -Level $status

        $results += [PSCustomObject]@{
            Script  = $script
            Pass    = $p
            Fail    = $f
            Warn    = $w
            Status  = $status
            LogFile = $result.LogFile
        }
    } catch {
        MasterLog "  => $($script): EXCEPTION — $($_.Exception.Message)" -Level FAIL
        $grandFail++
        $results += [PSCustomObject]@{
            Script  = $script
            Pass    = 0
            Fail    = 1
            Warn    = 0
            Status  = 'ERROR'
            LogFile = ''
        }
    }
}

$elapsed = (Get-Date) - $startTime
MasterLog ""
MasterLog "╔═══════════════════════════════════════════════════════════════════╗" -Level HEADER
MasterLog "║                     GRAND SUMMARY                               ║" -Level HEADER
MasterLog "╚═══════════════════════════════════════════════════════════════════╝" -Level HEADER

$overallStatus = if ($grandFail -gt 0) { 'FAIL' } elseif ($grandWarn -gt 0) { 'WARN' } else { 'PASS' }

foreach ($r in $results) {
    $icon = switch ($r.Status) { 'PASS' { '[OK]  ' } 'WARN' { '[WARN]' } 'FAIL' { '[FAIL]' } default { '[ERR] ' } }
    MasterLog "  $($icon) $($r.Script): $($r.Pass)P / $($r.Fail)F / $($r.Warn)W" -Level $r.Status
}

MasterLog ""
MasterLog "Grand total: $($grandPass) PASS, $($grandFail) FAIL, $($grandWarn) WARN"
MasterLog "Overall: $($overallStatus)"
MasterLog "Elapsed: $($elapsed.ToString('mm\:ss'))"
MasterLog "Master log: $($masterLog)"

$results | Format-Table -AutoSize | Out-String | ForEach-Object { MasterLog $_ }

return [PSCustomObject]@{
    OverallStatus = $overallStatus
    Pass          = $grandPass
    Fail          = $grandFail
    Warn          = $grandWarn
    Elapsed       = $elapsed
    MasterLog     = $masterLog
    Results       = $results
}
