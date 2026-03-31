$startTime = Get-Date
Write-Host "⏱️  START: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')" -ForegroundColor Yellow
Write-Host "Action: Test External Event Submission to ServerMonitor REST API`n" -ForegroundColor Cyan

Write-Host "══════════════════════════════════════════════════════" -ForegroundColor Green
Write-Host "  🔔 EXTERNAL EVENT SUBMISSION TEST" -ForegroundColor Green
Write-Host "══════════════════════════════════════════════════════`n" -ForegroundColor Green

$port = 8999
$baseUrl = "http://localhost:$port/api"

# Test 1: Db2 Event (x00d) - Test throttling (maxOccurrences=3, need 3 triggers to alert)
Write-Host "1️⃣ Submitting Db2 Event (x00d) - Testing Throttling..." -ForegroundColor Yellow
Write-Host "   Expected: Alert only after 3rd submission (maxOccurrences=3)" -ForegroundColor Gray

$db2Event = @{
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

# Submit 3 times (should only alert on 3rd)
for ($i = 1; $i -le 3; $i++) {
    Write-Host "`n   Submission #${i}:" -ForegroundColor Cyan
    try {
        $response = Invoke-RestMethod -Uri "$baseUrl/Alerts" -Method Post `
            -Body $db2Event -ContentType "application/json" -TimeoutSec 5
        
        Write-Host "      ✅ Event received" -ForegroundColor Green
        Write-Host "      Event ID: $($response.EventId)" -ForegroundColor Gray
        Write-Host "      Event Code: $($response.ExternalEventCode)" -ForegroundColor Gray
        Write-Host "      Severity: $($response.Severity)" -ForegroundColor Gray
        
        # Check if alert was generated (by checking alerts endpoint)
        Start-Sleep -Milliseconds 500
        $alerts = Invoke-RestMethod -Uri "$baseUrl/Snapshot/alerts" -Method Get -TimeoutSec 5
        $db2Alerts = $alerts | Where-Object { $_.Category -eq "Database" -and $_.Message -like "*Db2 event*" }
        
        if ($db2Alerts.Count -gt 0) {
            Write-Host "      ⚠️  ALERT GENERATED (this should only happen on 3rd submission)" -ForegroundColor Yellow
            if ($i -lt 3) {
                Write-Host "      ❌ TEST FAILED: Alert generated too early (on submission #${i})" -ForegroundColor Red
            } else {
                Write-Host "      ✅ Alert generated correctly on 3rd submission" -ForegroundColor Green
            }
        } else {
            Write-Host "      ✓ No alert yet (expected for submissions 1-2)" -ForegroundColor Gray
        }
    } catch {
        Write-Host "      ❌ Failed: $($_.Exception.Message)" -ForegroundColor Red
    }
    
    if ($i -lt 3) {
        Start-Sleep -Seconds 2
    }
}

Start-Sleep -Seconds 2

# Test 2: Different event code (should alert immediately if maxOccurrences=0 or 1)
Write-Host "`n2️⃣ Submitting Different Event Code (x001)..." -ForegroundColor Yellow

$db2Event2 = @{
    severity = "Warning"
    externalEventCode = "x001"
    category = "Database"
    message = "A different Db2 event was detected."
    timestamp = (Get-Date).ToUniversalTime().ToString("yyyy-MM-ddTHH:mm:ss.fffZ")
    serverName = "Prod-SQL-01"
    source = "Db2DiagLog"
    metadata = @{
        errorId = "x001"
        extraDetail = "Different event code"
    }
    surveillance = @{
        maxOccurrences = 1
        timeWindowMinutes = 60
        suppressedChannels = @()
    }
} | ConvertTo-Json -Depth 10

try {
    $response2 = Invoke-RestMethod -Uri "$baseUrl/Alerts" -Method Post `
        -Body $db2Event2 -ContentType "application/json" -TimeoutSec 5
    
    Write-Host "   ✅ Event received" -ForegroundColor Green
    Write-Host "   Event ID: $($response2.EventId)" -ForegroundColor Cyan
    Write-Host "   Event Code: $($response2.ExternalEventCode)" -ForegroundColor Cyan
    
    # Check for alert
    Start-Sleep -Milliseconds 500
    $alerts = Invoke-RestMethod -Uri "$baseUrl/Snapshot/alerts" -Method Get -TimeoutSec 5
    $x001Alerts = $alerts | Where-Object { $_.Category -eq "Database" -and $_.Message -like "*different Db2 event*" }
    
    if ($x001Alerts.Count -gt 0) {
        Write-Host "   ✅ Alert generated (expected for maxOccurrences=1)" -ForegroundColor Green
    } else {
        Write-Host "   ⚠️  No alert generated (may need to wait or check logic)" -ForegroundColor Yellow
    }
} catch {
    Write-Host "   ❌ Failed: $($_.Exception.Message)" -ForegroundColor Red
}

Start-Sleep -Seconds 2

# Test 3: Retrieve all external events
Write-Host "`n3️⃣ Retrieving External Events..." -ForegroundColor Yellow
try {
    $externalEvents = Invoke-RestMethod -Uri "$baseUrl/Snapshot/external-events" -Method Get -TimeoutSec 5
    Write-Host "   ✅ Retrieved $($externalEvents.Count) external events" -ForegroundColor Green
    
    $x00dEvents = $externalEvents | Where-Object { $_.ExternalEventCode -eq "x00d" }
    Write-Host "   x00d events: $($x00dEvents.Count)" -ForegroundColor Cyan
    
    if ($x00dEvents.Count -ge 3) {
        Write-Host "   ✅ Found all 3 x00d events" -ForegroundColor Green
    }
} catch {
    Write-Host "   ❌ Failed: $($_.Exception.Message)" -ForegroundColor Red
}

# Test 4: Check full snapshot includes external events
Write-Host "`n4️⃣ Checking Full Snapshot..." -ForegroundColor Yellow
try {
    $snapshot = Invoke-RestMethod -Uri "$baseUrl/Snapshot" -Method Get -TimeoutSec 5
    if ($snapshot.ExternalEvents) {
        Write-Host "   ✅ Snapshot includes $($snapshot.ExternalEvents.Count) external events" -ForegroundColor Green
    } else {
        Write-Host "   ⚠️  Snapshot does not include ExternalEvents property" -ForegroundColor Yellow
    }
} catch {
    Write-Host "   ❌ Failed: $($_.Exception.Message)" -ForegroundColor Red
}

Write-Host "`n══════════════════════════════════════════════════════" -ForegroundColor Green
Write-Host "  ✅ EXTERNAL EVENT TEST COMPLETE!" -ForegroundColor Green
Write-Host "══════════════════════════════════════════════════════`n" -ForegroundColor Green

$elapsed = (Get-Date) - $startTime
Write-Host "⏱️  Elapsed: $([math]::Round($elapsed.TotalSeconds, 1))s" -ForegroundColor Yellow

Write-Host "`n📌 API Endpoints:" -ForegroundColor Cyan
Write-Host "   Submit Event: POST http://localhost:$port/api/Alerts" -ForegroundColor White
Write-Host "   Get Event:    GET  http://localhost:$port/api/Alerts/events/{id}" -ForegroundColor White
Write-Host "   All Events:   GET  http://localhost:$port/api/Snapshot/external-events" -ForegroundColor White
Write-Host "   Full Snapshot: GET http://localhost:$port/api/Snapshot" -ForegroundColor White
Write-Host "   Swagger UI:   http://localhost:$port/swagger`n" -ForegroundColor White
