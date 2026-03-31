#!/usr/bin/env pwsh
<#
.SYNOPSIS
    Enables the Task Scheduler Operational log for event monitoring

.DESCRIPTION
    Enables the Microsoft-Windows-TaskScheduler/Operational event log
    which is required for monitoring Task Scheduler events (103, 201, 411).
    This log is often disabled by default on some Windows systems.

.EXAMPLE
    .\Enable-TaskSchedulerLog.ps1
    Enables the Task Scheduler operational log
#>

$startTime = Get-Date
Write-Host "⏱️  START: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')" -ForegroundColor Yellow
Write-Host "Action: Enabling Task Scheduler Operational log`n" -ForegroundColor Cyan

$logName = "Microsoft-Windows-TaskScheduler/Operational"

Write-Host "📋 Task Scheduler Operational Log Configuration`n" -ForegroundColor Cyan

# Check if running as administrator
$isAdmin = ([Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
if (-not $isAdmin) {
    Write-Host "❌ This script requires Administrator privileges!" -ForegroundColor Red
    Write-Host "💡 Please run PowerShell as Administrator and try again." -ForegroundColor Yellow
    exit 1
}

Write-Host "✅ Running with Administrator privileges`n" -ForegroundColor Green

# Check if log exists
Write-Host "🔍 Checking if log exists..." -ForegroundColor Cyan
try {
    $log = Get-WinEvent -ListLog $logName -ErrorAction Stop
    Write-Host "✅ Log exists: $logName" -ForegroundColor Green
    Write-Host "   Current status: $($log.IsEnabled)" -ForegroundColor Gray
    Write-Host "   Maximum size: $([math]::Round($log.MaximumSizeInBytes / 1MB, 2)) MB" -ForegroundColor Gray
} catch {
    Write-Host "❌ Log does not exist: $logName" -ForegroundColor Red
    Write-Host "   This log may not be available on this Windows version." -ForegroundColor Yellow
    exit 1
}

# Enable the log
Write-Host "`n🔧 Enabling the log..." -ForegroundColor Cyan
try {
    # Use wevtutil to enable the log
    $result = wevtutil sl $logName /e:true 2>&1
    
    if ($LASTEXITCODE -eq 0) {
        Write-Host "✅ Log enabled successfully!" -ForegroundColor Green
    } else {
        Write-Host "⚠️  wevtutil returned exit code: $LASTEXITCODE" -ForegroundColor Yellow
        Write-Host "   Output: $result" -ForegroundColor Gray
    }
    
    # Verify it's enabled
    Start-Sleep -Milliseconds 500
    $log = Get-WinEvent -ListLog $logName -ErrorAction Stop
    if ($log.IsEnabled) {
        Write-Host "✅ Verification: Log is now enabled" -ForegroundColor Green
    } else {
        Write-Host "⚠️  Verification: Log status is still: $($log.IsEnabled)" -ForegroundColor Yellow
    }
    
} catch {
    Write-Host "❌ Failed to enable log: $_" -ForegroundColor Red
    exit 1
}

# Show log configuration
Write-Host "`n📋 Current log configuration:" -ForegroundColor Cyan
try {
    $log = Get-WinEvent -ListLog $logName -ErrorAction Stop
    Write-Host "   Log Name: $($log.LogName)" -ForegroundColor White
    Write-Host "   Enabled: $($log.IsEnabled)" -ForegroundColor $(if ($log.IsEnabled) { "Green" } else { "Red" })
    Write-Host "   Maximum Size: $([math]::Round($log.MaximumSizeInBytes / 1MB, 2)) MB" -ForegroundColor White
    Write-Host "   Record Count: $($log.RecordCount)" -ForegroundColor White
    Write-Host "   Log Path: $($log.LogFilePath)" -ForegroundColor White
} catch {
    Write-Host "   ⚠️  Could not retrieve log details" -ForegroundColor Yellow
}

Write-Host "`n💡 Next steps:" -ForegroundColor Yellow
Write-Host "   1. The log is now enabled" -ForegroundColor Gray
Write-Host "   2. Restart ServerMonitor to begin monitoring Task Scheduler events" -ForegroundColor Gray
Write-Host "   3. Events 103, 201, and 411 will now be monitored" -ForegroundColor Gray

$totalElapsed = ((Get-Date) - $startTime).TotalSeconds
Write-Host "`n⏱️  END: $(Get-Date -Format 'HH:mm:ss') | Duration: $([math]::Round($totalElapsed, 1))s" -ForegroundColor Yellow

