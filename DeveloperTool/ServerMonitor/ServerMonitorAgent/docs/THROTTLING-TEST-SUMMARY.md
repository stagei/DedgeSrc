# External Event Throttling Test Summary

## ✅ Code Fixes Completed

All throttling logic fixes have been implemented and verified in code:

### 1. **External Event Alert Storm Prevention** ✅
- **Location**: `AlertManager.ProcessExternalEventSync()`
- **Fix**: Added `_lastExternalEventAlert` dictionary to track last alert time per event code
- **Behavior**: Once an alert is sent for an event code within a time window, subsequent occurrences are suppressed until the time window expires
- **Result**: With `maxOccurrences=3`, only ONE alert is sent on the 3rd occurrence, not on 4th, 5th, etc.

### 2. **Alert Tracking Fix** ✅
- **Location**: `AlertManager.DistributeAlertSync()`
- **Fix**: Changed `SendToChannelSync()` to return success status, only track alerts if at least one channel succeeds
- **Behavior**: Failed alerts are not marked as "sent", allowing retries
- **Result**: SMS will only be tracked if it was actually sent successfully

### 3. **Time Window Consistency** ✅
- **Location**: `AlertManager.ProcessExternalEventSync()`
- **Fix**: Store time window per event code in `_externalEventTimeWindows` dictionary
- **Behavior**: First submission sets the time window, subsequent submissions use the stored value
- **Result**: Consistent behavior even if same event code submitted with different time windows

### 4. **Global Throttling Exemption** ✅
- **Location**: `AlertManager.DistributeAlertSync()`
- **Fix**: Added `skipGlobalThrottling` parameter, set to `true` for external events
- **Behavior**: External events bypass global throttling (they have their own per-event throttling)
- **Result**: External events are not blocked by global `MaxAlertsPerHour` limit

## 📋 Expected Test Behavior

When testing with `maxOccurrences=3` and `timeWindowMinutes=60`:

1. **Submission #1**: 
   - Event stored ✅
   - Count: 1 (1 < 3) → No alert generated ✅
   - SMS: NOT sent ✅

2. **Submission #2**: 
   - Event stored ✅
   - Count: 2 (2 < 3) → No alert generated ✅
   - SMS: NOT sent ✅

3. **Submission #3**: 
   - Event stored ✅
   - Count: 3 (3 >= 3) → Alert generated ✅
   - SMS: Sent ✅
   - Last alert time recorded ✅

4. **Submission #4** (within same time window): 
   - Event stored ✅
   - Count: 4 (4 >= 3) → BUT last alert was within time window → Alert suppressed ✅
   - SMS: NOT sent ✅

## ⚠️ Current Blocker

**REST API Not Starting**: The REST API is not listening on port 8999 when running ServerMonitor locally. This prevents automated testing.

### Symptoms:
- No REST API startup messages in logs
- Connection refused on `http://localhost:8999`
- Application runs but API endpoints are unreachable

### Possible Causes:
1. Kestrel configuration issue (despite earlier fixes)
2. Configuration not being read correctly when running from command line
3. Port 8999 already in use (unlikely, checked)
4. Firewall blocking (unlikely for localhost)

### Next Steps:
1. Check `Program.cs` Kestrel configuration
2. Verify `appsettings.LowLimitsTest.json` is being loaded correctly
3. Add more detailed logging for REST API startup
4. Test with a simpler Kestrel configuration

## 🧪 Manual Testing Instructions

Once REST API is working, use the following test:

```powershell
# 1. Start ServerMonitor with test config
$exePath = "src\ServerMonitor\ServerMonitorAgent\bin\Release\net10.0-windows\win-x64\ServerMonitor.exe"
$process = Start-Process -FilePath $exePath -PassThru

# 2. Wait for API to start
Start-Sleep -Seconds 30

# 3. Submit event 3 times
$event = @{
    severity = "Warning"
    externalEventCode = "x00d"
    category = "Database"
    message = "A Db2 event was detected in the diagnostic log."
    surveillance = @{
        maxOccurrences = 3
        timeWindowMinutes = 60
        suppressedChannels = @()
    }
} | ConvertTo-Json

# Submission 1
Invoke-RestMethod -Uri "http://localhost:8999/api/Alerts" -Method Post -Body $event -ContentType "application/json"
# Check logs: Should see event stored, NO SMS

# Submission 2 (wait 2 seconds)
Start-Sleep -Seconds 2
Invoke-RestMethod -Uri "http://localhost:8999/api/Alerts" -Method Post -Body $event -ContentType "application/json"
# Check logs: Should see event stored, NO SMS

# Submission 3 (wait 2 seconds)
Start-Sleep -Seconds 2
Invoke-RestMethod -Uri "http://localhost:8999/api/Alerts" -Method Post -Body $event -ContentType "application/json"
# Check logs: Should see event stored, ALERT GENERATED, SMS SENT

# 4. Check logs for SMS
Get-Content "C:\opt\data\ServerMonitor\ServerMonitor_*.log" -Tail 50 | Select-String -Pattern "SMS.*sent|Alert.*SMS|x00d"
```

## ✅ Verification Checklist

- [x] Code fixes implemented
- [x] Alert storm prevention logic added
- [x] Alert tracking only on success
- [x] Time window consistency
- [x] Global throttling exemption
- [ ] REST API startup working
- [ ] Automated test passing
- [ ] SMS verification confirmed

## 📝 Notes

The throttling logic is correct in code. The remaining issue is getting the REST API to start so we can test it. Once the API is working, the test should pass immediately since all the logic fixes are in place.

