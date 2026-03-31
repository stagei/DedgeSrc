#!/usr/bin/env pwsh
<#
.SYNOPSIS
    Tests ServerMonitor with automatic 30-second timeout and kill
.DESCRIPTION
    Runs ServerMonitor with low-limit test configuration and automatically kills it after 30 seconds
#>

$startTime = Get-Date
Write-Host "══════════════════════════════════════════════════════" -ForegroundColor Cyan
Write-Host "  ⏱️  TEST START: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')" -ForegroundColor Yellow
Write-Host "══════════════════════════════════════════════════════`n" -ForegroundColor Cyan

# Kill any existing processes
Write-Host "🔪 Killing existing ServerMonitor processes..." -ForegroundColor Red
Get-Process -Name "ServerMonitor" -ErrorAction SilentlyContinue | Stop-Process -Force
Start-Sleep -Seconds 2

# Path to executable
$exePath = "C:\opt\src\ServerMonitor\ServerMonitorAgent\src\ServerMonitor\ServerMonitorAgent\bin\Release\net10.0-windows\win-x64\ServerMonitor.exe"

if (-not (Test-Path $exePath)) {
    Write-Host "❌ Executable not found: $exePath" -ForegroundColor Red
    exit 1
}

Write-Host "✅ Executable found" -ForegroundColor Green
Write-Host "🚀 Starting ServerMonitor..." -ForegroundColor Cyan
Write-Host "⏱️  Will auto-kill after 30 seconds`n" -ForegroundColor Yellow

# Start the process
$process = Start-Process -FilePath $exePath -PassThru -WindowStyle Minimized

Write-Host "Process started (PID: $($process.Id))`n" -ForegroundColor Green

# Wait for 30 seconds, checking status every 5 seconds
for ($i = 1; $i -le 6; $i++) {
    Start-Sleep -Seconds 5
    $elapsed = ((Get-Date) - $startTime).TotalSeconds
    Write-Host "⏱️  $([math]::Round($elapsed, 1))s elapsed..." -ForegroundColor Gray
    
    # Check if process is still running
    $runningProcess = Get-Process -Id $process.Id -ErrorAction SilentlyContinue
    if (-not $runningProcess) {
        Write-Host "⚠️  Process exited early!" -ForegroundColor Yellow
        break
    }
}

# Kill the process after 30 seconds
$runningProcess = Get-Process -Id $process.Id -ErrorAction SilentlyContinue
if ($runningProcess) {
    Write-Host "`n🔪 30 seconds reached - killing process..." -ForegroundColor Red
    Stop-Process -Id $process.Id -Force
    Write-Host "✅ Process killed" -ForegroundColor Green
} else {
    Write-Host "`n⚠️  Process already exited" -ForegroundColor Yellow
}

# Check for log file
Write-Host "`n📄 Checking for log files..." -ForegroundColor Cyan
$logFile = "C:\opt\data\ServerMonitor\ServerMonitor_$(Get-Date -Format 'yyyy-MM-dd').log"

if (Test-Path $logFile) {
    Write-Host "✅ Log file found: $logFile" -ForegroundColor Green
    $fileInfo = Get-Item $logFile
    Write-Host "   Size: $($fileInfo.Length) bytes" -ForegroundColor Gray
    Write-Host "   Modified: $($fileInfo.LastWriteTime)`n" -ForegroundColor Gray
    
    Write-Host "Last 60 lines of log:`n" -ForegroundColor Cyan
    Get-Content $logFile -Tail 60 | ForEach-Object {
        if ($_ -match "ERROR|FATAL|Exception") {
            Write-Host $_ -ForegroundColor Red
        } elseif ($_ -match "WARN") {
            Write-Host $_ -ForegroundColor Yellow
        } elseif ($_ -match "Alert|SMS|Email|WkMonitor|monitor path|sent to") {
            Write-Host $_ -ForegroundColor Green
        } elseif ($_ -match "REST API|Swagger|Starting") {
            Write-Host $_ -ForegroundColor Cyan
        } else {
            Write-Host $_ -ForegroundColor White
        }
    }
} else {
    Write-Host "❌ Log file NOT found at: $logFile" -ForegroundColor Red
    
    # Check other locations
    Write-Host "`nSearching other locations..." -ForegroundColor Yellow
    $altPaths = @(
        "C:\opt\data\ServerMonitor\ServerMonitor*.log",
        "C:\opt\src\ServerMonitor\ServerMonitorAgent\src\ServerMonitor\ServerMonitorAgent\bin\Release\net10.0-windows\win-x64\ServerMonitor*.log"
    )
    
    foreach ($pattern in $altPaths) {
        $logs = Get-ChildItem -Path (Split-Path $pattern) -Filter (Split-Path $pattern -Leaf) -ErrorAction SilentlyContinue |
                Where-Object { $_.LastWriteTime -gt (Get-Date).AddMinutes(-5) } |
                Sort-Object LastWriteTime -Descending | Select-Object -First 1
        
        if ($logs) {
            Write-Host "✅ Found: $($logs.FullName)" -ForegroundColor Green
            Get-Content $logs.FullName -Tail 30
            break
        }
    }
}

$totalElapsed = ((Get-Date) - $startTime).TotalSeconds
Write-Host "`n══════════════════════════════════════════════════════" -ForegroundColor Cyan
Write-Host "  ⏱️  TEST END: $(Get-Date -Format 'HH:mm:ss')" -ForegroundColor Yellow
Write-Host "  Total Duration: $([math]::Round($totalElapsed, 1))s" -ForegroundColor Yellow
Write-Host "══════════════════════════════════════════════════════" -ForegroundColor Cyan

