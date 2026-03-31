# ServerMonitor TrayIcon - Improvements

## Current Functionality
- System tray icon showing agent status (running/stopped)
- Context menu for start/stop/restart/reinstall
- REST API for remote control
- Trigger file monitoring for automated actions

---

## Feature Improvements

### 1. Enhanced Status Display
Show more information in tooltip:

```csharp
_notifyIcon.Text = $"ServerMonitor v{version}\n" +
    $"Status: {status}\n" +
    $"CPU: {cpuPercent:F0}%\n" +
    $"Memory: {memPercent:F0}%\n" +
    $"Alerts: {alertCount}";
```

### 2. Quick Metrics Popup
Double-click to show quick metrics popup window:
- Current CPU/Memory usage
- Recent alerts summary
- Disk space overview
- Link to full dashboard

### 3. Alert Notifications
Show balloon notifications for agent alerts:

```csharp
private async Task PollForAlertsAsync()
{
    var alerts = await _agentApi.GetRecentAlertsAsync();
    foreach (var alert in alerts.Where(a => a.Severity >= AlertSeverity.Warning))
    {
        _notifyIcon.ShowBalloonTip(5000, 
            $"Alert: {alert.Category}", 
            alert.Message, 
            ToolTipIcon.Warning);
    }
}
```

### 4. Log Viewer
Quick access to recent log entries:
- Tail the log file
- Filter by level
- Search functionality

### 5. Configuration Editor
Simple UI for editing common settings:
- Polling intervals
- Alert thresholds
- Export settings

---

## Performance Improvements

### 1. Reduce API Polling
Use longer intervals when agent is stable:

```csharp
private int _consecutiveSuccesses = 0;
private int _pollIntervalMs = 5000;

private void AdjustPollingInterval(bool success)
{
    if (success)
    {
        _consecutiveSuccesses++;
        if (_consecutiveSuccesses > 10)
        {
            _pollIntervalMs = Math.Min(30000, _pollIntervalMs * 2);
        }
    }
    else
    {
        _consecutiveSuccesses = 0;
        _pollIntervalMs = 5000; // Reset to fast polling
    }
}
```

### 2. Cached Status
Don't poll API if we know status hasn't changed:

```csharp
private DateTime _lastServiceStateChange;

private bool ShouldPollApi()
{
    // Only poll if service state recently changed
    return (DateTime.Now - _lastServiceStateChange).TotalSeconds < 60;
}
```

### 3. Efficient Icon Updates
Only update icon when status actually changes:

```csharp
private Icon _currentIcon;

private void UpdateIcon(Icon newIcon)
{
    if (_currentIcon != newIcon)
    {
        _notifyIcon.Icon = newIcon;
        _currentIcon = newIcon;
    }
}
```

---

## Reliability Improvements

### 1. Service Recovery Detection
Detect when service restarts automatically:

```csharp
private void MonitorServiceRecovery()
{
    var lastPid = GetServicePid();
    
    _timer.Tick += (s, e) =>
    {
        var currentPid = GetServicePid();
        if (currentPid != lastPid && currentPid > 0)
        {
            _logger.LogInformation("Service recovered with new PID: {Pid}", currentPid);
            lastPid = currentPid;
            ShowRecoveryNotification();
        }
    };
}
```

### 2. Graceful Degradation
Continue functioning even if agent API is unavailable:

```csharp
private async Task<AgentStatus> GetStatusWithFallbackAsync()
{
    try
    {
        return await _agentApi.GetStatusAsync();
    }
    catch
    {
        // Fallback to WMI service status check
        return GetServiceStatusViaWmi();
    }
}
```

### 3. Auto-Recovery
Automatically restart crashed agent:

```csharp
if (_config.AutoRestartOnCrash && 
    !_serviceManager.IsRunning() && 
    _wasRunningBeforeCrash)
{
    _logger.LogWarning("Agent crashed - attempting auto-restart");
    await _serviceManager.StartServiceAsync();
}
```

---

## UI Improvements

### 1. Modern Context Menu
Use WPF for better-looking menus:
- Icons for menu items
- Submenus for advanced options
- Keyboard shortcuts

### 2. Status Colors
Different icon colors for different states:
- 🟢 Green: Running, healthy
- 🟡 Yellow: Running, warnings
- 🔴 Red: Stopped or critical alerts
- ⚪ Gray: Unknown/disconnected

### 3. Progress Indicators
Show progress during reinstall:

```csharp
private void ShowReinstallProgress(int percent, string status)
{
    _notifyIcon.Text = $"Installing... {percent}%\n{status}";
    _notifyIcon.Icon = _installingIcon;
}
```

---

## Configuration Improvements

### 1. Settings Persistence
Save user preferences:

```json
{
  "TraySettings": {
    "StartMinimized": true,
    "ShowNotifications": true,
    "NotificationSeverity": "Warning",
    "AutoRestartOnCrash": false,
    "PollIntervalMs": 5000
  }
}
```

### 2. Remote Configuration
Sync settings from central config:

```csharp
private async Task SyncSettingsAsync()
{
    var centralConfig = await LoadCentralConfigAsync();
    if (centralConfig.Version > _localConfig.Version)
    {
        ApplySettings(centralConfig);
    }
}
```

---

## Implementation Priority

| Priority | Improvement | Impact | Effort |
|----------|-------------|--------|--------|
| 🔴 High | Alert notifications | High | Medium |
| 🔴 High | Status colors | High | Low |
| 🟡 Medium | Quick metrics popup | Medium | Medium |
| 🟡 Medium | Auto-recovery | Medium | Low |
| 🟡 Medium | Progress indicators | Medium | Low |
| 🟢 Low | Configuration editor | Low | High |
| 🟢 Low | Log viewer | Low | Medium |
