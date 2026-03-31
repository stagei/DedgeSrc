$startTime = Get-Date
Write-Host "⏱️  START: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')" -ForegroundColor Yellow
Write-Host "Action: Test External Event Throttling with SMS Verification`n" -ForegroundColor Cyan

Write-Host "══════════════════════════════════════════════════════" -ForegroundColor Green
Write-Host "  🔔 EXTERNAL EVENT THROTTLING TEST" -ForegroundColor Green
Write-Host "══════════════════════════════════════════════════════`n" -ForegroundColor Green

# Kill existing ServerMonitor
Get-Process -Name "ServerMonitor" -ErrorAction SilentlyContinue | Stop-Process -Force
Start-Sleep -Seconds 3

# Start ServerMonitor with test config
$exePath = "src\ServerMonitor\ServerMonitorAgent\bin\Release\net10.0-windows\win-x64\ServerMonitor.exe"
if (-not (Test-Path $exePath)) {
    $exePath = "C:\opt\src\ServerMonitor\ServerMonitorAgent\src\ServerMonitor\ServerMonitorAgent\bin\Release\net10.0-windows\win-x64\ServerMonitor.exe"
}

$configPath = "src\ServerMonitor\ServerMonitorAgent\appsettings.LowLimitsTest.json"
$outputDir = "src\ServerMonitor\ServerMonitorAgent\bin\Release\net10.0-windows\win-x64"

# Copy test config to output directory
if (Test-Path $configPath) {
    Copy-Item -Path $configPath -Destination "$outputDir\appsettings.json" -Force
    Write-Host "✅ Copied test config to output directory" -ForegroundColor Green
}

Write-Host "Starting ServerMonitor..." -ForegroundColor Cyan
$process = Start-Process -FilePath $exePath -WorkingDirectory $outputDir -PassThru -WindowStyle Minimized

Write-Host "✅ ServerMonitor started (PID: $($process.Id))" -ForegroundColor Green
Write-Host "Waiting 20 seconds for REST API to initialize..." -ForegroundColor Yellow
Start-Sleep -Seconds 20

$port = 8999
$baseUrl = "http://localhost:$port/api"

# Get log file path
$logDir = "C:\opt\data\ServerMonitor"
$logFile = Get-ChildItem -Path $logDir -Filter "ServerMonitor_*.log" -ErrorAction SilentlyContinue | 
    Sort-Object LastWriteTime -Descending | Select-Object -First 1

if (-not $logFile) {
    Write-Host "⚠️  Warning: Could not find log file in $logDir" -ForegroundColor Yellow
    $logFile = $null
} else {
    Write-Host "📋 Using log file: $($logFile.FullName)" -ForegroundColor Cyan
}

# Function to get SMS count from logs
function Get-SmsCount {
    param([string]$LogPath, [DateTime]$Since)
    
    if (-not $LogPath -or -not (Test-Path $LogPath)) {
        return 0
    }
    
    $logContent = Get-Content $LogPath -Tail 200 -ErrorAction SilentlyContinue
    $smsLines = $logContent | Where-Object { 
        $_ -match "SMS sent successfully|Sending SMS|Alert sent to SMS" -and 
        $_ -match "x00d"
    }
    
    return $smsLines.Count
}

# Test event with maxOccurrences=3
$testEvent = @{
    severity = "Warning"
    externalEventCode = "x00d"
    category = "Database"
    message = "A Db2 event was detected in the diagnostic log."
    timestamp = (Get-Date).ToUniversalTime().ToString("yyyy-MM-ddTHH:mm:ss.fffZ")
    serverName = "Test-Server"
    source = "TestScript"
    metadata = @{
        errorId = "x00d"
        testRun = "throttling-verification"
    }
    surveillance = @{
        maxOccurrences = 3
        timeWindowMinutes = 60
        suppressedChannels = @()  # Don't suppress SMS - we want to verify it
    }
} | ConvertTo-Json -Depth 10

Write-Host "`n📊 Testing Throttling (maxOccurrences=3)..." -ForegroundColor Yellow
Write-Host "Expected: Alert only after 3rd submission" -ForegroundColor Gray
Write-Host "Expected: SMS sent only on 3rd submission`n" -ForegroundColor Gray

$testStartTime = Get-Date
$smsCountBefore = 0
if ($logFile) {
    $smsCountBefore = Get-SmsCount -LogPath $logFile.FullName -Since $testStartTime.AddMinutes(-5)
}

$testPassed = $true

# Submit 3 times
for ($i = 1; $i -le 3; $i++) {
    Write-Host "`n📤 Submission #${i}:" -ForegroundColor Cyan
    
    $submissionTime = Get-Date
    
    try {
        $response = Invoke-RestMethod -Uri "$baseUrl/Alerts" -Method Post `
            -Body $testEvent -ContentType "application/json" -TimeoutSec 5
        
        Write-Host "   ✅ Event received (ID: $($response.EventId))" -ForegroundColor Green
        
        # Wait a bit for processing
        Start-Sleep -Seconds 2
        
        # Check for SMS in logs
        if ($logFile) {
            $smsCountAfter = Get-SmsCount -LogPath $logFile.FullName -Since $testStartTime.AddMinutes(-5)
            $smsSentForThisSubmission = ($smsCountAfter - $smsCountBefore) > 0
            
            if ($smsSentForThisSubmission) {
                if ($i -lt 3) {
                    Write-Host "   ❌ FAILED: SMS was sent on submission #${i} (should only send on 3rd)" -ForegroundColor Red
                    $testPassed = $false
                } else {
                    Write-Host "   ✅ SMS sent correctly on 3rd submission" -ForegroundColor Green
                }
            } else {
                if ($i -lt 3) {
                    Write-Host "   ✅ No SMS sent (correct for submission #${i})" -ForegroundColor Green
                } else {
                    Write-Host "   ❌ FAILED: SMS was NOT sent on 3rd submission (should have been sent)" -ForegroundColor Red
                    $testPassed = $false
                }
            }
            
            $smsCountBefore = $smsCountAfter
        } else {
            Write-Host "   ⚠️  Cannot verify SMS (log file not found)" -ForegroundColor Yellow
        }
        
        # Check if alert was generated
        Start-Sleep -Milliseconds 500
        try {
            $alerts = Invoke-RestMethod -Uri "$baseUrl/Snapshot/alerts" -Method Get -TimeoutSec 5
            $testAlerts = $alerts | Where-Object { 
                $_.Category -eq "Database" -and 
                $_.Message -like "*Db2 event*" -and
                $_.Metadata.testRun -eq "throttling-verification"
            }
            
            if ($testAlerts.Count -gt 0) {
                if ($i -lt 3) {
                    Write-Host "   ⚠️  Alert generated on submission #${i} (should only generate on 3rd)" -ForegroundColor Yellow
                } else {
                    Write-Host "   ✅ Alert generated correctly on 3rd submission" -ForegroundColor Green
                }
            } else {
                if ($i -lt 3) {
                    Write-Host "   ✅ No alert yet (correct for submission #${i})" -ForegroundColor Green
                } else {
                    Write-Host "   ⚠️  No alert found (may need to wait or check logic)" -ForegroundColor Yellow
                }
            }
        } catch {
            Write-Host "   ⚠️  Could not check alerts: $($_.Exception.Message)" -ForegroundColor Yellow
        }
        
    } catch {
        Write-Host "   ❌ Failed: $($_.Exception.Message)" -ForegroundColor Red
        $testPassed = $false
    }
    
    if ($i -lt 3) {
        Start-Sleep -Seconds 1
    }
}

# Final verification
Write-Host "`n📋 Final Verification:" -ForegroundColor Yellow
try {
    $externalEvents = Invoke-RestMethod -Uri "$baseUrl/Snapshot/external-events" -Method Get -TimeoutSec 5
    $x00dEvents = $externalEvents | Where-Object { 
        $_.ExternalEventCode -eq "x00d" -and 
        $_.Metadata.testRun -eq "throttling-verification"
    }
    
    Write-Host "   Found $($x00dEvents.Count) x00d events with testRun metadata" -ForegroundColor Cyan
    
    if ($x00dEvents.Count -ge 3) {
        Write-Host "   ✅ All 3 events stored correctly" -ForegroundColor Green
    } else {
        Write-Host "   ⚠️  Expected 3 events, found $($x00dEvents.Count)" -ForegroundColor Yellow
    }
} catch {
    Write-Host "   ⚠️  Could not retrieve external events: $($_.Exception.Message)" -ForegroundColor Yellow
}

# Check logs for SMS distribution
Write-Host "`n📋 Checking Logs for SMS Distribution:" -ForegroundColor Yellow
if ($logFile) {
    $recentLogs = Get-Content $logFile.FullName -Tail 50 -ErrorAction SilentlyContinue
    $smsLogs = $recentLogs | Where-Object { $_ -match "SMS|SmsAlertChannel" -and $_ -match "x00d" }
    
    if ($smsLogs.Count -gt 0) {
        Write-Host "   Recent SMS-related log entries:" -ForegroundColor Cyan
        $smsLogs | Select-Object -Last 5 | ForEach-Object {
            Write-Host "   $_" -ForegroundColor Gray
        }
    } else {
        Write-Host "   No SMS-related logs found for x00d events" -ForegroundColor Gray
    }
} else {
    Write-Host "   ⚠️  Log file not available" -ForegroundColor Yellow
}

Write-Host "`n══════════════════════════════════════════════════════" -ForegroundColor Green
if ($testPassed) {
    Write-Host "  ✅ TEST PASSED!" -ForegroundColor Green
    Write-Host "  SMS was correctly sent only on 3rd submission" -ForegroundColor Green
} else {
    Write-Host "  ❌ TEST FAILED!" -ForegroundColor Red
    Write-Host "  SMS was sent incorrectly (check logs above)" -ForegroundColor Red
}
Write-Host "══════════════════════════════════════════════════════`n" -ForegroundColor Green

$elapsed = (Get-Date) - $startTime
Write-Host "⏱️  Elapsed: $([math]::Round($elapsed.TotalSeconds, 1))s" -ForegroundColor Yellow

Write-Host "`n📌 Keeping ServerMonitor running for inspection" -ForegroundColor Cyan
Write-Host "PID: $($process.Id)`n" -ForegroundColor Cyan

