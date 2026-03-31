# ServerMonitor Dashboard Tray - Improvements

## Current Functionality
- System tray icon for dashboard access
- Alert polling from all servers
- Balloon notifications for new alerts
- Environment and severity filtering
- Notification toggle

---

## Feature Improvements

### 1. Alert History Window
Show recent alerts in a popup window:

```csharp
private void ShowAlertHistory()
{
    var form = new AlertHistoryForm(_recentAlerts);
    form.Show();
}
```

Features:
- List of last 50 alerts
- Filter by server/severity
- Click to open in dashboard
- Mark as read/acknowledged

### 2. Server Status Overview
Quick popup showing all server statuses:

```
┌─────────────────────────────────┐
│ Server Status Overview          │
├─────────────────────────────────┤
│ 🟢 p-no1fkmprd-db    OK        │
│ 🟢 p-no1inlprd-db    OK        │
│ 🟡 t-no1fkmtst-app   2 Warns   │
│ 🔴 t-no1inltst-db    OFFLINE   │
└─────────────────────────────────┘
```

### 3. Quick Actions
Right-click menu for common actions:
- Open specific server in dashboard
- Trigger all agents update
- View alert summary
- Clear seen alerts

### 4. Sound Alerts
Play sound for critical alerts:

```csharp
private void PlayAlertSound(AlertSeverity severity)
{
    if (!_settings.SoundEnabled) return;
    
    var soundFile = severity switch
    {
        AlertSeverity.Critical => "critical.wav",
        AlertSeverity.Warning => "warning.wav",
        _ => null
    };
    
    if (soundFile != null)
    {
        new SoundPlayer(soundFile).Play();
    }
}
```

### 5. Alert Aggregation
Group similar alerts to prevent notification spam:

```csharp
private Dictionary<string, int> _alertCounts = new();

private void ProcessAlert(AlertInfo alert)
{
    var key = $"{alert.ServerName}_{alert.Category}";
    
    if (!_alertCounts.TryGetValue(key, out var count))
    {
        count = 0;
    }
    
    _alertCounts[key] = count + 1;
    
    // Only show notification for first occurrence in 5 minutes
    if (count == 0)
    {
        ShowNotification(alert);
    }
}
```

### 6. Dashboard Health Check
Monitor dashboard service availability:

```csharp
private async Task CheckDashboardHealthAsync()
{
    try
    {
        var response = await _httpClient.GetAsync($"{_settings.DashboardUrl}/health");
        _dashboardHealthy = response.IsSuccessStatusCode;
    }
    catch
    {
        _dashboardHealthy = false;
    }
    
    UpdateIconForHealth();
}
```

---

## Performance Improvements

### 1. Parallel Server Polling
Poll multiple servers concurrently with throttling:

```csharp
private async Task PollAllServersAsync()
{
    var semaphore = new SemaphoreSlim(5); // Max 5 concurrent
    
    var tasks = _servers.Select(async server =>
    {
        await semaphore.WaitAsync();
        try
        {
            return await PollServerAsync(server);
        }
        finally
        {
            semaphore.Release();
        }
    });
    
    await Task.WhenAll(tasks);
}
```

### 2. Adaptive Polling
Increase interval for quiet servers:

```csharp
private TimeSpan GetPollingInterval(ServerInfo server)
{
    if (server.LastAlertTime.HasValue && 
        (DateTime.UtcNow - server.LastAlertTime.Value).TotalHours > 1)
    {
        return TimeSpan.FromMinutes(2); // Quiet server
    }
    
    return TimeSpan.FromSeconds(30); // Active server
}
```

### 3. Connection Reuse
Use persistent HTTP connections:

```csharp
_httpClient = new HttpClient(new SocketsHttpHandler
{
    PooledConnectionLifetime = TimeSpan.FromMinutes(10),
    MaxConnectionsPerServer = 2
});
```

### 4. Efficient JSON Parsing
Use System.Text.Json source generators:

```csharp
[JsonSerializable(typeof(List<AlertInfo>))]
[JsonSerializable(typeof(ServerStatus))]
internal partial class JsonContext : JsonSerializerContext
{
}
```

---

## Reliability Improvements

### 1. Offline Resilience
Handle network failures gracefully:

```csharp
private int _consecutiveFailures = 0;

private void HandlePollResult(bool success)
{
    if (!success)
    {
        _consecutiveFailures++;
        
        if (_consecutiveFailures >= 3)
        {
            _notifyIcon.Icon = _offlineIcon;
            _notifyIcon.Text = "Dashboard Tray - Connection Issues";
        }
    }
    else
    {
        _consecutiveFailures = 0;
        _notifyIcon.Icon = _normalIcon;
    }
}
```

### 2. Auto-Recovery
Reconnect after network restoration:

```csharp
NetworkChange.NetworkAvailabilityChanged += (s, e) =>
{
    if (e.IsAvailable)
    {
        _logger.LogInformation("Network restored - resuming polling");
        ResumePolling();
    }
};
```

### 3. Persistent Alert State
Save seen alerts to survive restarts:

```csharp
private void SaveSeenAlerts()
{
    var json = JsonSerializer.Serialize(_seenAlertIds);
    File.WriteAllText(_seenAlertsPath, json);
}

private void LoadSeenAlerts()
{
    if (File.Exists(_seenAlertsPath))
    {
        var json = File.ReadAllText(_seenAlertsPath);
        _seenAlertIds = JsonSerializer.Deserialize<HashSet<string>>(json) ?? new();
    }
}
```

---

## UI Improvements

### 1. Rich Notifications
Use Windows 10/11 toast notifications:

```csharp
private void ShowToastNotification(AlertInfo alert)
{
    var builder = new ToastContentBuilder()
        .AddText($"Alert: {alert.ServerName}")
        .AddText(alert.Message)
        .AddButton("Open Dashboard", "action", "open")
        .AddButton("Dismiss", "action", "dismiss");
    
    builder.Show();
}
```

### 2. Badge Count
Show alert count on taskbar icon:

```csharp
private void UpdateBadge(int count)
{
    if (count > 0)
    {
        // Use Windows overlay icon or badge API
        TaskbarManager.Instance.SetOverlayIcon(
            CreateBadgeIcon(count), 
            $"{count} alerts");
    }
}
```

### 3. Dark/Light Mode
Match Windows theme:

```csharp
private Icon GetIconForTheme()
{
    var isDarkMode = Registry.GetValue(
        @"HKEY_CURRENT_USER\SOFTWARE\Microsoft\Windows\CurrentVersion\Themes\Personalize",
        "AppsUseLightTheme", 1) is int value && value == 0;
    
    return isDarkMode ? _lightIcon : _darkIcon;
}
```

---

## Configuration Improvements

### 1. Server Groups
Configure server groups for filtering:

```json
{
  "ServerGroups": {
    "Production": ["p-*"],
    "Test": ["t-*"],
    "Database": ["*-db"],
    "Application": ["*-app"]
  }
}
```

### 2. Custom Alert Rules
Define notification rules:

```json
{
  "NotificationRules": [
    {
      "ServerPattern": "p-*",
      "MinSeverity": "Warning",
      "Sound": true,
      "Toast": true
    },
    {
      "ServerPattern": "t-*",
      "MinSeverity": "Critical",
      "Sound": false,
      "Toast": true
    }
  ]
}
```

---

## Implementation Priority

| Priority | Improvement | Impact | Effort |
|----------|-------------|--------|--------|
| 🔴 High | Server status overview | High | Medium |
| 🔴 High | Alert aggregation | High | Low |
| 🔴 High | Parallel server polling | High | Low |
| 🟡 Medium | Toast notifications | Medium | Medium |
| 🟡 Medium | Sound alerts | Medium | Low |
| 🟡 Medium | Persistent alert state | Medium | Low |
| 🟢 Low | Badge count | Low | Medium |
| 🟢 Low | Custom alert rules | Low | Medium |
