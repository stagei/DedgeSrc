#!/usr/bin/env pwsh
<#
.SYNOPSIS
    Analyzes ServerMonitor alerts log for discrepancies and functional issues
#>

param(
    [string]$LogFile = "C:\opt\data\ServerMonitor\ServerMonitor_Alerts_20251202.log",
    [string]$StartTime = "15:00:00"
)

$startTime = Get-Date
Write-Host "⏱️  START: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')" -ForegroundColor Yellow
Write-Host "Action: Analyzing alerts log for discrepancies`n" -ForegroundColor Cyan

if (-not (Test-Path $LogFile)) {
    Write-Host "❌ Log file not found: $LogFile" -ForegroundColor Red
    exit 1
}

$logDate = if ($LogFile -match '(\d{4}\d{2}\d{2})') { 
    $matches[1].Insert(4, '-').Insert(7, '-') 
} else { 
    (Get-Date).ToString('yyyy-MM-dd') 
}

$targetTime = [DateTime]::Parse("$logDate $StartTime")
Write-Host "📋 Analyzing: $LogFile" -ForegroundColor Cyan
Write-Host "   From: $targetTime onwards`n" -ForegroundColor Gray

$lines = Get-Content $LogFile
$relevantLines = $lines | Where-Object { 
    if ($_ -match '\[(\d{4}-\d{2}-\d{2} \d{2}:\d{2}:\d{2})\]') { 
        $lineTime = [DateTime]::Parse($matches[1])
        $lineTime -ge $targetTime 
    } else { 
        $false 
    } 
}

Write-Host "=" * 80 -ForegroundColor Gray
Write-Host "ANALYSIS REPORT" -ForegroundColor Cyan
Write-Host "=" * 80 -ForegroundColor Gray
Write-Host ""

# Statistics
$errors = $relevantLines | Where-Object { $_ -match "\[CRITICAL\]|\[ERROR\]" }
$warnings = $relevantLines | Where-Object { $_ -match "\[WARNING\]" }
$scheduledTask = $relevantLines | Where-Object { $_ -match "ScheduledTask" }
$windowsUpdate = $relevantLines | Where-Object { $_ -match "WindowsUpdate" }

Write-Host "📈 STATISTICS" -ForegroundColor Cyan
Write-Host "   Total alerts: $($relevantLines.Count)" -ForegroundColor White
Write-Host "   Critical/Error: $($errors.Count)" -ForegroundColor $(if ($errors.Count -gt 0) { "Red" } else { "Green" })
Write-Host "   Warnings: $($warnings.Count)" -ForegroundColor $(if ($warnings.Count -gt 0) { "Yellow" } else { "Green" })
Write-Host "   Scheduled Task alerts: $($scheduledTask.Count)" -ForegroundColor White
Write-Host "   Windows Update alerts: $($windowsUpdate.Count)" -ForegroundColor White
Write-Host ""

# Analyze exit code descriptions
Write-Host "🔍 EXIT CODE DESCRIPTION ANALYSIS" -ForegroundColor Cyan
$exitCodeLines = $relevantLines | Where-Object { $_ -match "exit code" }
$withDescription = $exitCodeLines | Where-Object { $_ -match "exit code \d+.*- " }
$withoutDescription = $exitCodeLines | Where-Object { $_ -notmatch "exit code \d+.*- " }

Write-Host "   Total exit code alerts: $($exitCodeLines.Count)" -ForegroundColor White
Write-Host "   With description: $($withDescription.Count)" -ForegroundColor Green
Write-Host "   Without description: $($withoutDescription.Count)" -ForegroundColor $(if ($withoutDescription.Count -gt 0) { "Red" } else { "Green" })

if ($withoutDescription.Count -gt 0) {
    Write-Host "`n   ⚠️  Alerts missing exit code descriptions:" -ForegroundColor Yellow
    $withoutDescription | ForEach-Object {
        if ($_ -match 'exit code (\d+)') {
            $code = $matches[1]
            Write-Host "      Exit code $code - No description found" -ForegroundColor Gray
        }
    }
}

# Analyze exit code format changes
Write-Host "`n📋 EXIT CODE FORMAT ANALYSIS" -ForegroundColor Cyan
$oldFormat = $exitCodeLines | Where-Object { $_ -match "exit code \d+$" -or $_ -match "exit code \d+ \|" }
$newFormat = $exitCodeLines | Where-Object { $_ -match "exit code \d+ \(0x" }
Write-Host "   Old format (no hex): $($oldFormat.Count)" -ForegroundColor Gray
Write-Host "   New format (with hex): $($newFormat.Count)" -ForegroundColor Gray

if ($oldFormat.Count -gt 0 -and $newFormat.Count -gt 0) {
    Write-Host "   ⚠️  Format inconsistency detected!" -ForegroundColor Yellow
    Write-Host "      Some alerts show hex, others don't" -ForegroundColor Gray
}

# Analyze specific exit codes
Write-Host "`n🔢 EXIT CODE BREAKDOWN" -ForegroundColor Cyan
$code267011 = $exitCodeLines | Where-Object { $_ -match "exit code 267011|exit code 41303" }
$code64 = $exitCodeLines | Where-Object { $_ -match "exit code 64|exit code 40[^0-9]" }
$code40 = $exitCodeLines | Where-Object { $_ -match "exit code 40[^0-9]" -and $_ -notmatch "exit code 64" }

Write-Host "   Exit code 267011/41303 (DB2): $($code267011.Count) occurrences" -ForegroundColor White
$code267011WithDesc = $code267011 | Where-Object { $_ -match "- DB2" }
Write-Host "      With description: $($code267011WithDesc.Count)" -ForegroundColor $(if ($code267011WithDesc.Count -eq $code267011.Count) { "Green" } else { "Yellow" })

Write-Host "   Exit code 64/40 (Custom): $($code64.Count + $code40.Count) occurrences" -ForegroundColor White
$code64WithDesc = ($code64 + $code40) | Where-Object { $_ -match "- Custom" }
Write-Host "      With description: $($code64WithDesc.Count)" -ForegroundColor $(if ($code64WithDesc.Count -eq ($code64.Count + $code40.Count)) { "Green" } else { "Yellow" })

# Analyze alert frequency
Write-Host "`n⏰ ALERT FREQUENCY ANALYSIS" -ForegroundColor Cyan
$taskFailures = $relevantLines | Where-Object { $_ -match "Scheduled task failed" }
$timePatterns = @{}
foreach ($line in $taskFailures) {
    if ($line -match '\[(\d{4}-\d{2}-\d{2} \d{2}:\d{2}:\d{2})\]') {
        $time = [DateTime]::Parse($matches[1])
        $timeKey = $time.ToString("HH:mm")
        if (-not $timePatterns.ContainsKey($timeKey)) {
            $timePatterns[$timeKey] = 0
        }
        $timePatterns[$timeKey]++
    }
}

Write-Host "   Alert frequency pattern:" -ForegroundColor White
$timePatterns.GetEnumerator() | Sort-Object Key | ForEach-Object {
    Write-Host "      $($_.Key): $($_.Value) alerts" -ForegroundColor Gray
}

# Check for missing information
Write-Host "`n⚠️  DISCREPANCIES FOUND" -ForegroundColor Cyan
$discrepancies = @()

# Check 1: Missing exit code descriptions
if ($withoutDescription.Count -gt 0) {
    $discrepancies += "Missing exit code descriptions: $($withoutDescription.Count) alerts"
}

# Check 2: DB2 exit code missing description
$db2WithoutDesc = $code267011 | Where-Object { $_ -notmatch "- DB2" }
if ($db2WithoutDesc.Count -gt 0) {
    $discrepancies += "DB2 exit code (267011/41303) missing description: $($db2WithoutDesc.Count) alerts"
}

# Check 3: Format inconsistency
if ($oldFormat.Count -gt 0 -and $newFormat.Count -gt 0) {
    $discrepancies += "Exit code format inconsistency: Some show hex, others don't"
}

# Check 4: Alert throttling - same alerts repeating
$uniqueAlerts = $taskFailures | Select-Object -Unique
if ($taskFailures.Count -gt $uniqueAlerts.Count * 2) {
    $discrepancies += "Possible alert throttling issue: $($taskFailures.Count) alerts for $($uniqueAlerts.Count) unique failures"
}

if ($discrepancies.Count -eq 0) {
    Write-Host "   ✅ No discrepancies found!" -ForegroundColor Green
} else {
    foreach ($disc in $discrepancies) {
        Write-Host "   ❌ $disc" -ForegroundColor Red
    }
}

# Timeline analysis
Write-Host "`n📅 TIMELINE ANALYSIS" -ForegroundColor Cyan
$firstAlert = $relevantLines | Select-Object -First 1
$lastAlert = $relevantLines | Select-Object -Last 1

if ($firstAlert -match '\[(\d{4}-\d{2}-\d{2} \d{2}:\d{2}:\d{2})\]') {
    $firstTime = [DateTime]::Parse($matches[1])
    Write-Host "   First alert: $($firstTime.ToString('HH:mm:ss'))" -ForegroundColor White
}

if ($lastAlert -match '\[(\d{4}-\d{2}-\d{2} \d{2}:\d{2}:\d{2})\]') {
    $lastTime = [DateTime]::Parse($matches[1])
    Write-Host "   Last alert: $($lastTime.ToString('HH:mm:ss'))" -ForegroundColor White
    if ($firstAlert) {
        $duration = $lastTime - $firstTime
        Write-Host "   Duration: $([math]::Round($duration.TotalHours, 1)) hours" -ForegroundColor White
    }
}

Write-Host ""
Write-Host "=" * 80 -ForegroundColor Gray
Write-Host "END OF ANALYSIS" -ForegroundColor Cyan
Write-Host "=" * 80 -ForegroundColor Gray
Write-Host ""

$totalElapsed = ((Get-Date) - $script:startTime).TotalSeconds
Write-Host "⏱️  END: $(Get-Date -Format 'HH:mm:ss') | Duration: $([math]::Round($totalElapsed, 1))s" -ForegroundColor Yellow

