$startTime = Get-Date
Write-Host "⏱️  START: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')" -ForegroundColor Yellow
Write-Host "Action: Test External Event Throttling`n" -ForegroundColor Cyan

Write-Host "══════════════════════════════════════════════════════" -ForegroundColor Green
Write-Host "  🔔 EXTERNAL EVENT THROTTLING TEST" -ForegroundColor Green
Write-Host "══════════════════════════════════════════════════════`n" -ForegroundColor Green

# Kill existing processes
Get-Process -Name "ServerMonitor" -ErrorAction SilentlyContinue | Stop-Process -Force
Start-Sleep -Seconds 2

# Start ServerMonitor
$exePath = "src\ServerMonitor\ServerMonitorAgent\bin\Release\net10.0-windows\win-x64\ServerMonitor.exe"
$configPath = "src\ServerMonitor\ServerMonitorAgent\appsettings.LowLimitsTest.json"
Copy-Item -Path $configPath -Destination "src\ServerMonitor\ServerMonitorAgent\bin\Release\net10.0-windows\win-x64\appsettings.json" -Force
$env:DOTNET_ENVIRONMENT = "LowLimitsTest"

Write-Host "Starting ServerMonitor..." -ForegroundColor Cyan
$process = Start-Process -FilePath $exePath -PassThru -WindowStyle Minimized
Write-Host "✅ ServerMonitor started (PID: $($process.Id))" -ForegroundColor Green

Write-Host "Waiting 20 seconds for REST API to initialize..." -ForegroundColor Yellow
Start-Sleep -Seconds 20

$port = 8999
$baseUrl = "http://localhost:$port/api"
$logDir = "$env:OptPath\data\ServerMonitor"
if (-not $logDir -or $logDir -eq "") { $logDir = "C:\opt\data\ServerMonitor" }

# Test: Submit event 3 times with maxOccurrences=3
# Expected: Alert only on 3rd submission, SMS should NOT be sent before 3rd
Write-Host "`n📊 Testing Throttling (maxOccurrences=3)..." -ForegroundColor Cyan
Write-Host "Expected: Alert only after 3rd submission`n" -ForegroundColor Gray

$event = @{
    severity = "Information"
    externalEventCode = "x00d"
    category = "Database"
    message = "A Db2 event was detected in the diagnostic log."
    timestamp = (Get-Date).ToUniversalTime().ToString("yyyy-MM-ddTHH:mm:ss.fffZ")
    serverName = "Prod-SQL-01"
    source = "Db2DiagLog"
    metadata = @{
        errorId = "x00d"
        extraDetail = "Auto-generated event from external integration"
    }
    surveillance = @{
        maxOccurrences = 3
        timeWindowMinutes = 60
        suppressedChannels = @("Email")
    }
} | ConvertTo-Json -Depth 10

$testPassed = $true
$alertGeneratedOn = 0

for ($i = 1; $i -le 3; $i++) {
    Write-Host "Submission #${i}:" -ForegroundColor Cyan
    
    # Get log count before submission
    $logFiles = Get-ChildItem -Path $logDir -Filter "ServerMonitor_*.log" -ErrorAction SilentlyContinue | Sort-Object LastWriteTime -Descending | Select-Object -First 1
    $smsCountBefore = 0
    if ($logFiles) {
        $smsCountBefore = (Select-String -Path $logFiles.FullName -Pattern "SMS.*sent|SMS.*distributed" -ErrorAction SilentlyContinue | Measure-Object).Count
    }
    
    try {
        $response = Invoke-RestMethod -Uri "$baseUrl/Alerts" -Method Post `
            -Body $event -ContentType "application/json" -TimeoutSec 5
        
        Write-Host "  ✅ Event received (ID: $($response.EventId))" -ForegroundColor Green
        
        Start-Sleep -Milliseconds 1000
        
        # Check for alerts
        $alerts = Invoke-RestMethod -Uri "$baseUrl/Snapshot/alerts" -Method Get -TimeoutSec 5
        $db2Alerts = $alerts | Where-Object { $_.Category -eq "Database" -and $_.Message -like "*Db2 event*" }
        
        # Check for SMS in logs
        if ($logFiles) {
            $smsCountAfter = (Select-String -Path $logFiles.FullName -Pattern "SMS.*sent|SMS.*distributed" -ErrorAction SilentlyContinue | Measure-Object).Count
            $smsSent = $smsCountAfter -gt $smsCountBefore
        } else {
            $smsSent = $false
        }
        
        if ($db2Alerts.Count -gt 0) {
            Write-Host "  ⚠️  ALERT GENERATED" -ForegroundColor Yellow
            $alertGeneratedOn = $i
            
            if ($i -lt 3) {
                Write-Host "  ❌ TEST FAILED: Alert generated too early (on submission #${i})" -ForegroundColor Red
                $testPassed = $false
            } else {
                Write-Host "  ✅ Alert generated correctly on 3rd submission" -ForegroundColor Green
            }
            
            if ($smsSent) {
                if ($i -lt 3) {
                    Write-Host "  ❌ TEST FAILED: SMS sent before 3rd submission!" -ForegroundColor Red
                    $testPassed = $false
                } else {
                    Write-Host "  ✅ SMS sent correctly on 3rd submission" -ForegroundColor Green
                }
            } else {
                if ($i -ge 3) {
                    Write-Host "  ⚠️  No SMS found in logs (may be suppressed or not sent)" -ForegroundColor Yellow
                }
            }
        } else {
            Write-Host "  ✓ No alert yet (expected for submissions 1-2)" -ForegroundColor Gray
            
            if ($smsSent) {
                Write-Host "  ❌ TEST FAILED: SMS sent before alert was generated!" -ForegroundColor Red
                $testPassed = $false
            }
        }
    } catch {
        Write-Host "  ❌ Failed: $($_.Exception.Message)" -ForegroundColor Red
        $testPassed = $false
    }
    
    if ($i -lt 3) {
        Start-Sleep -Seconds 2
    }
}

# Final verification
Write-Host "`n📋 Final Verification:" -ForegroundColor Cyan
try {
    $externalEvents = Invoke-RestMethod -Uri "$baseUrl/Snapshot/external-events" -Method Get -TimeoutSec 5
    $x00dEvents = $externalEvents | Where-Object { $_.ExternalEventCode -eq "x00d" }
    Write-Host "  External events (x00d): $($x00dEvents.Count)" -ForegroundColor White
    
    if ($x00dEvents.Count -ge 3) {
        Write-Host "  ✅ All 3 events recorded" -ForegroundColor Green
    } else {
        Write-Host "  ⚠️  Expected 3 events, found $($x00dEvents.Count)" -ForegroundColor Yellow
    }
} catch {
    Write-Host "  ❌ Failed to retrieve external events: $($_.Exception.Message)" -ForegroundColor Red
}

# Check logs for SMS
Write-Host "`n📋 Checking Logs for SMS Distribution:" -ForegroundColor Cyan
$logFiles = Get-ChildItem -Path $logDir -Filter "ServerMonitor_*.log" -ErrorAction SilentlyContinue | Sort-Object LastWriteTime -Descending | Select-Object -First 1
if ($logFiles) {
    $smsLines = Select-String -Path $logFiles.FullName -Pattern "SMS.*sent|SMS.*distributed|Alert.*SMS" -ErrorAction SilentlyContinue | Select-Object -Last 5
    if ($smsLines) {
        Write-Host "  Recent SMS-related log entries:" -ForegroundColor Yellow
        $smsLines | ForEach-Object { Write-Host "    $($_.Line)" -ForegroundColor Gray }
    } else {
        Write-Host "  ✓ No SMS distribution found in logs (may be suppressed)" -ForegroundColor Gray
    }
} else {
    Write-Host "  ⚠️  Log files not found in $logDir" -ForegroundColor Yellow
}

Write-Host "`n══════════════════════════════════════════════════════" -ForegroundColor Green
if ($testPassed -and $alertGeneratedOn -eq 3) {
    Write-Host "  ✅ TEST PASSED!" -ForegroundColor Green
    Write-Host "  Alert generated correctly on 3rd submission" -ForegroundColor Green
} else {
    Write-Host "  ❌ TEST FAILED!" -ForegroundColor Red
    if ($alertGeneratedOn -ne 3) {
        Write-Host "  Alert generated on submission #${alertGeneratedOn} (expected: 3)" -ForegroundColor Red
    }
}
Write-Host "══════════════════════════════════════════════════════`n" -ForegroundColor Green

$elapsed = (Get-Date) - $startTime
Write-Host "⏱️  Elapsed: $([math]::Round($elapsed.TotalSeconds, 1))s" -ForegroundColor Yellow

# Return test result
if (-not $testPassed -or $alertGeneratedOn -ne 3) {
    Write-Host "`n⚠️  Test failed - keeping ServerMonitor running for inspection" -ForegroundColor Yellow
    Write-Host "PID: $($process.Id)" -ForegroundColor Cyan
    exit 1
} else {
    Write-Host "`n✅ Test passed - stopping ServerMonitor" -ForegroundColor Green
    Stop-Process -Id $process.Id -Force -ErrorAction SilentlyContinue
    exit 0
}

