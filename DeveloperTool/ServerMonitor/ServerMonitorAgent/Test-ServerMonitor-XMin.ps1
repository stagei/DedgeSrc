param(
    [int]$Minutes = 70
)

$startTime = Get-Date
Write-Host "⏱️  START: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')" -ForegroundColor Yellow
Write-Host "Action: Testing ServerMonitor for $Minutes minutes`n" -ForegroundColor Cyan

# Kill existing processes
Write-Host "🛑 Stopping existing ServerMonitor processes..." -ForegroundColor Cyan
Get-Process -Name "ServerMonitor" -ErrorAction SilentlyContinue | Stop-Process -Force -ErrorAction SilentlyContinue
Start-Sleep -Seconds 2

# Rebuild the project
Write-Host "🔨 Rebuilding project..." -ForegroundColor Cyan
$buildStartTime = Get-Date
$buildResult = dotnet build -c Release --no-incremental 2>&1
$buildDuration = [math]::Round(((Get-Date) - $buildStartTime).TotalSeconds, 1)

if ($LASTEXITCODE -eq 0 -or ($buildResult | Select-String -Pattern "Build succeeded")) {
    Write-Host "✅ Build succeeded in ${buildDuration}s" -ForegroundColor Green
} else {
    Write-Host "❌ Build failed!" -ForegroundColor Red
    $buildResult | Select-String -Pattern "error|Error|FAILED" | ForEach-Object { Write-Host "   $_" -ForegroundColor Red }
    Write-Host "   Continuing anyway (using existing build)..." -ForegroundColor Yellow
}
Write-Host ""

# Determine log file path - check NLog config for actual log file pattern
$logDir = "C:\opt\data\ServerMonitor"
# The log file might be named differently, so we'll search for the most recent one
Write-Host "📋 Log directory: $logDir" -ForegroundColor Cyan
Write-Host ""

# Start ServerMonitor with LowLimitsTest profile using the proper startup script
Write-Host "🚀 Starting ServerMonitor with LowLimitsTest profile..." -ForegroundColor Cyan
$startupScript = ".\Start-ServerMonitor.ps1"

if (-not (Test-Path $startupScript)) {
    Write-Host "❌ Startup script not found: $startupScript" -ForegroundColor Red
    exit 1
}

# Start ServerMonitor using the startup script
Start-Process -FilePath "powershell.exe" `
    -ArgumentList "-ExecutionPolicy", "Bypass", "-File", $startupScript, "-AppSettingsFile", "LowLimitsTest" `
    -WindowStyle Hidden | Out-Null

Start-Sleep -Seconds 5

# Verify process started
$verifyProcess = Get-Process -Name "ServerMonitor" -ErrorAction SilentlyContinue | 
    Where-Object { $_.StartTime -ge $startTime } | 
    Sort-Object StartTime -Descending | Select-Object -First 1

if (-not $verifyProcess) {
    Write-Host "❌ ServerMonitor did not start!" -ForegroundColor Red
    Write-Host "   Checking for any ServerMonitor processes..." -ForegroundColor Yellow
    Get-Process -Name "ServerMonitor" -ErrorAction SilentlyContinue | Format-Table Id, ProcessName, StartTime
    exit 1
}

Write-Host "✅ ServerMonitor started (PID: $($verifyProcess.Id))" -ForegroundColor Green
Write-Host ""

# Monitor log file for $Minutes minutes
$testDuration = $Minutes * 60
$endTime = (Get-Date).AddSeconds($testDuration)
$lastPosition = 0
$errorCount = 0
$warningCount = 0
$windowsUpdateIssues = @()
$scheduledTaskIssues = @()

Write-Host "📊 Monitoring logs for $Minutes minutes..." -ForegroundColor Cyan
Write-Host "   Looking for Windows Update and Scheduled Task issues`n" -ForegroundColor Gray

$iteration = 0
while ((Get-Date) -lt $endTime) {
    $iteration++
    $remaining = [math]::Round(($endTime - (Get-Date)).TotalSeconds, 0)
    
    if ($iteration % 10 -eq 0) {
        Write-Host "⏳ Time remaining: ${remaining}s | Iteration: $iteration" -ForegroundColor DarkGray
    }
    
    # Find the most recent main log file (not alerts or nlog-internal)
    $logFiles = Get-ChildItem $logDir -Filter "ServerMonitor_*.log" -ErrorAction SilentlyContinue | 
        Where-Object { $_.Name -notmatch "Alerts|nlog-internal" } | 
        Sort-Object LastWriteTime -Descending
    
    if ($logFiles.Count -eq 0) {
        Start-Sleep -Seconds 2
        continue
    }
    
    $logPath = $logFiles[0].FullName
    
    try {
        # Read new log entries
        $stream = [System.IO.File]::Open($logPath, [System.IO.FileMode]::Open, [System.IO.FileAccess]::Read, [System.IO.FileShare]::ReadWrite)
        $stream.Position = $lastPosition
        $reader = New-Object System.IO.StreamReader($stream)
        
        while ($null -ne ($line = $reader.ReadLine())) {
            # Check for errors
            if ($line -match "ERROR|Error|Exception|Failed|failed") {
                $errorCount++
                
                # Windows Update issues
                if ($line -match "WindowsUpdate|Windows Update|Update") {
                    $windowsUpdateIssues += $line
                    Write-Host "🔴 Windows Update Issue: $line" -ForegroundColor Red
                }
                
                # Scheduled Task issues
                if ($line -match "ScheduledTask|Scheduled Task|TaskScheduler|Task Scheduler") {
                    $scheduledTaskIssues += $line
                    Write-Host "🔴 Scheduled Task Issue: $line" -ForegroundColor Red
                }
            }
            
            # Check for warnings
            if ($line -match "WARN|Warning|warning") {
                $warningCount++
                
                # Windows Update warnings
                if ($line -match "WindowsUpdate|Windows Update|Update") {
                    Write-Host "🟡 Windows Update Warning: $line" -ForegroundColor Yellow
                }
                
                # Scheduled Task warnings
                if ($line -match "ScheduledTask|Scheduled Task|TaskScheduler|Task Scheduler") {
                    Write-Host "🟡 Scheduled Task Warning: $line" -ForegroundColor Yellow
                }
            }
            
            # Check for successful Windows Update checks
            if ($line -match "WindowsUpdate.*pending|WindowsUpdate.*critical|WindowsUpdate.*security") {
                Write-Host "ℹ️  Windows Update Info: $line" -ForegroundColor Cyan
            }
            
            # Check for successful Scheduled Task checks
            if ($line -match "ScheduledTask.*found|ScheduledTask.*matching|GetMatchingTasks") {
                Write-Host "ℹ️  Scheduled Task Info: $line" -ForegroundColor Cyan
            }
        }
        
        $lastPosition = $stream.Position
        $reader.Close()
        $stream.Close()
    } catch {
        # Log file might be locked or not ready yet
    }
    
    Start-Sleep -Seconds 2
}

# Final summary
Write-Host "`n" -NoNewline
Write-Host "=" * 80 -ForegroundColor Gray
Write-Host "📊 TEST SUMMARY" -ForegroundColor Cyan
Write-Host "=" * 80 -ForegroundColor Gray
Write-Host ""

Write-Host "⏱️  Test Duration: $Minutes minutes" -ForegroundColor White
Write-Host "📝 Total Errors Found: $errorCount" -ForegroundColor $(if ($errorCount -eq 0) { "Green" } else { "Red" })
Write-Host "⚠️  Total Warnings Found: $warningCount" -ForegroundColor $(if ($warningCount -eq 0) { "Green" } else { "Yellow" })
Write-Host ""

# Windows Update Summary
Write-Host "🪟 Windows Update Issues:" -ForegroundColor Cyan
if ($windowsUpdateIssues.Count -eq 0) {
    Write-Host "   ✅ No issues found" -ForegroundColor Green
} else {
    Write-Host "   ❌ Found $($windowsUpdateIssues.Count) issue(s):" -ForegroundColor Red
    foreach ($issue in $windowsUpdateIssues) {
        Write-Host "      - $issue" -ForegroundColor Gray
    }
}
Write-Host ""

# Scheduled Task Summary
Write-Host "📅 Scheduled Task Issues:" -ForegroundColor Cyan
if ($scheduledTaskIssues.Count -eq 0) {
    Write-Host "   ✅ No issues found" -ForegroundColor Green
} else {
    Write-Host "   ❌ Found $($scheduledTaskIssues.Count) issue(s):" -ForegroundColor Red
    foreach ($issue in $scheduledTaskIssues) {
        Write-Host "      - $issue" -ForegroundColor Gray
    }
}
Write-Host ""

# Check if process is still running
$processCheck = Get-Process -Name "ServerMonitor" -ErrorAction SilentlyContinue
if ($processCheck) {
    Write-Host "✅ ServerMonitor is still running (PID: $($processCheck.Id))" -ForegroundColor Green
    Write-Host "   To stop it, run: Get-Process -Name ServerMonitor | Stop-Process -Force" -ForegroundColor Gray
} else {
    Write-Host "⚠️  ServerMonitor process is not running (may have exited)" -ForegroundColor Yellow
}

Write-Host ""
Write-Host "📄 Full log file: $logPath" -ForegroundColor Cyan
Write-Host ""

$totalElapsed = ((Get-Date) - $startTime).TotalSeconds
Write-Host "⏱️  END: $(Get-Date -Format 'HH:mm:ss') | Duration: $([math]::Round($totalElapsed, 1))s" -ForegroundColor Yellow

