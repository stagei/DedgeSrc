# Alert Push Notifications: Agent to Tray App

**Status**: ✅ **IMPLEMENTED** (Option A - API Polling with Alert Tracking)

## Overview

This document describes how to implement real-time alert notifications from the ServerMonitor agent to the tray application, including balloon notifications that open the related HTML/JSON report when clicked.

---

## Current Architecture

```
┌─────────────────────┐         ┌─────────────────────┐
│   ServerMonitor     │         │  ServerMonitorTray  │
│   (Windows Service) │         │   (Desktop App)     │
│                     │         │                     │
│  ┌───────────────┐  │  HTTP   │  ┌───────────────┐  │
│  │  REST API     │◄─┼─────────┼──│  API Client   │  │
│  │  :8999        │  │  Poll   │  │  (3s timer)   │  │
│  └───────────────┘  │         │  └───────────────┘  │
│                     │         │                     │
│  ┌───────────────┐  │         │  ┌───────────────┐  │
│  │  Snapshot     │  │  Files  │  │  NotifyIcon   │  │
│  │  Exporter     │──┼────────►│  │  Balloon Tips │  │
│  └───────────────┘  │         │  └───────────────┘  │
└─────────────────────┘         └─────────────────────┘
        JSON/HTML files written to shared folders
```

**Current Capabilities:**
- Agent exposes REST API on port 8999 with alert endpoints
- Tray app polls service status every 3 seconds
- Agent exports JSON/HTML snapshots to configured directories
- Tray app can already open last HTML/JSON via menu items

---

## Proposed Solution Options

### Option A: API Polling with Alert Tracking (Recommended)

**Approach:** Tray app polls the agent's `/api/snapshot/alerts/recent` endpoint and tracks seen alert IDs. When new alerts appear, show balloon notifications.

**Pros:**
- Uses existing infrastructure (REST API, timer)
- Simple implementation
- Works across network (agent and tray can be on different machines)
- No new dependencies

**Cons:**
- Not truly real-time (up to 3-second delay)
- Additional API calls (small overhead)

---

### Option B: FileSystemWatcher on Snapshot Directory

**Approach:** Watch the snapshot export directory for new files. When a new snapshot appears, read it and check for new alerts.

**Pros:**
- Near real-time detection
- Already using FileSystemWatcher for trigger files
- Works even if API is down

**Cons:**
- Requires access to export directory
- More complex file parsing
- May miss alerts if export is disabled

---

### Option C: SignalR/WebSocket (Future Enhancement)

**Approach:** Add SignalR hub to the agent for real-time push notifications.

**Pros:**
- True real-time push
- Efficient (no polling)
- Bidirectional communication

**Cons:**
- Significant development effort
- New dependency (SignalR)
- More complex infrastructure

---

## Implemented Solution: Option A ✅

### Phase 1: Add Alert Polling to Tray App

#### 1.1 Extend API Client

Add method to fetch recent alerts:

```csharp
// ServerMonitorApiClient.cs

/// <summary>
/// Gets recent alerts from the agent
/// </summary>
public async Task<List<AlertInfo>?> GetRecentAlertsAsync(int count = 10)
{
    try
    {
        var response = await _httpClient.GetAsync($"{_baseUrl}/api/snapshot/alerts/recent?count={count}");
        
        if (!response.IsSuccessStatusCode)
            return null;
        
        var content = await response.Content.ReadAsStringAsync();
        return JsonSerializer.Deserialize<List<AlertInfo>>(content, _jsonOptions);
    }
    catch (Exception ex)
    {
        Debug.WriteLine($"Error getting alerts: {ex.Message}");
        return null;
    }
}

/// <summary>
/// Gets the current snapshot with file paths
/// </summary>
public async Task<SnapshotWithPaths?> GetSnapshotWithPathsAsync()
{
    // Returns snapshot info including the paths to latest HTML/JSON files
    // Used when alert balloon is clicked
}
```

#### 1.2 Add Alert Info Model

```csharp
// Models/AlertInfo.cs

public class AlertInfo
{
    public Guid Id { get; set; }
    public string Severity { get; set; } = string.Empty;
    public string Category { get; set; } = string.Empty;
    public string Message { get; set; } = string.Empty;
    public string? Details { get; set; }
    public DateTime Timestamp { get; set; }
    public string ServerName { get; set; } = string.Empty;
}
```

#### 1.3 Add Alert Tracking to TrayIconApplicationContext

```csharp
// TrayIconApplicationContext.cs

// Track seen alerts to avoid duplicate notifications
private readonly HashSet<Guid> _seenAlertIds = new();
private string? _lastSnapshotHtmlPath;
private string? _lastSnapshotJsonPath;

// Add to constructor
private void InitializeAlertTracking()
{
    // Load initial alerts as "seen" to avoid balloon storm on startup
    _ = LoadInitialAlertsAsync();
}

private async Task LoadInitialAlertsAsync()
{
    try
    {
        var alerts = await _apiClient.GetRecentAlertsAsync(50);
        if (alerts != null)
        {
            foreach (var alert in alerts)
            {
                _seenAlertIds.Add(alert.Id);
            }
            Debug.WriteLine($"Loaded {_seenAlertIds.Count} existing alerts (suppressing startup notifications)");
        }
    }
    catch (Exception ex)
    {
        Debug.WriteLine($"Error loading initial alerts: {ex.Message}");
    }
}
```

#### 1.4 Check for New Alerts on Timer Tick

```csharp
// TrayIconApplicationContext.cs

private async void CheckForNewAlertsAsync()
{
    try
    {
        var alerts = await _apiClient.GetRecentAlertsAsync(10);
        if (alerts == null) return;
        
        // Find alerts we haven't seen yet
        var newAlerts = alerts.Where(a => !_seenAlertIds.Contains(a.Id)).ToList();
        
        if (newAlerts.Count > 0)
        {
            // Mark as seen
            foreach (var alert in newAlerts)
            {
                _seenAlertIds.Add(alert.Id);
            }
            
            // Limit seen alerts to prevent memory growth (keep last 1000)
            if (_seenAlertIds.Count > 1000)
            {
                var oldest = _seenAlertIds.Take(_seenAlertIds.Count - 1000).ToList();
                foreach (var id in oldest)
                {
                    _seenAlertIds.Remove(id);
                }
            }
            
            // Get latest snapshot paths for when user clicks balloon
            await UpdateSnapshotPathsAsync();
            
            // Show notification for the most severe alert
            var mostSevere = newAlerts
                .OrderByDescending(a => GetSeverityRank(a.Severity))
                .ThenByDescending(a => a.Timestamp)
                .First();
            
            ShowAlertBalloon(mostSevere, newAlerts.Count);
        }
    }
    catch (Exception ex)
    {
        Debug.WriteLine($"Error checking alerts: {ex.Message}");
    }
}

private int GetSeverityRank(string severity) => severity switch
{
    "Critical" => 3,
    "Warning" => 2,
    "Informational" => 1,
    _ => 0
};
```

#### 1.5 Show Alert Balloon with Click Handler

```csharp
// TrayIconApplicationContext.cs

private void ShowAlertBalloon(AlertInfo alert, int totalNewAlerts)
{
    // Set balloon icon based on severity
    var icon = alert.Severity switch
    {
        "Critical" => ToolTipIcon.Error,
        "Warning" => ToolTipIcon.Warning,
        _ => ToolTipIcon.Info
    };
    
    // Build title
    var title = totalNewAlerts > 1
        ? $"ServerMonitor: {totalNewAlerts} New Alerts"
        : $"ServerMonitor: {alert.Severity}";
    
    // Build message
    var message = $"[{alert.Category}] {alert.Message}";
    if (message.Length > 200)
        message = message.Substring(0, 197) + "...";
    
    // Show balloon
    _notifyIcon.BalloonTipIcon = icon;
    _notifyIcon.BalloonTipTitle = title;
    _notifyIcon.BalloonTipText = message;
    _notifyIcon.ShowBalloonTip(5000);
}

private async Task UpdateSnapshotPathsAsync()
{
    try
    {
        _lastSnapshotHtmlPath = await _apiClient.GetLastExportedHtmlPathAsync();
        _lastSnapshotJsonPath = await _apiClient.GetLastExportedJsonPathAsync();
    }
    catch (Exception ex)
    {
        Debug.WriteLine($"Error updating snapshot paths: {ex.Message}");
    }
}
```

#### 1.6 Handle Balloon Click to Open HTML

```csharp
// TrayIconApplicationContext.cs - in constructor

// Register balloon click handler
_notifyIcon.BalloonTipClicked += OnBalloonTipClicked;

private void OnBalloonTipClicked(object? sender, EventArgs e)
{
    // Prefer HTML, fall back to JSON
    var pathToOpen = _lastSnapshotHtmlPath ?? _lastSnapshotJsonPath;
    
    if (!string.IsNullOrEmpty(pathToOpen) && File.Exists(pathToOpen))
    {
        try
        {
            Process.Start(new ProcessStartInfo
            {
                FileName = pathToOpen,
                UseShellExecute = true
            });
        }
        catch (Exception ex)
        {
            Debug.WriteLine($"Error opening file: {ex.Message}");
            // Fallback: open Swagger
            OpenSwagger();
        }
    }
    else
    {
        // No file available, open Swagger
        OpenSwagger();
    }
}
```

---

### Phase 2: Agent-Side Enhancements

#### 2.1 Add Alert File Export (Optional)

For per-alert file tracking, the agent could export each alert as a separate file:

```csharp
// AlertManager.cs - after alert is distributed

private void ExportAlertFile(Alert alert, string htmlPath)
{
    var alertDir = Path.GetDirectoryName(htmlPath);
    var alertFileName = $"Alert_{alert.Id}_{alert.Timestamp:yyyyMMdd_HHmmss}.json";
    var alertPath = Path.Combine(alertDir, "alerts", alertFileName);
    
    Directory.CreateDirectory(Path.GetDirectoryName(alertPath)!);
    
    var json = JsonSerializer.Serialize(alert, new JsonSerializerOptions { WriteIndented = true });
    File.WriteAllText(alertPath, json);
}
```

#### 2.2 Add API Endpoint for Latest Snapshot Paths

```csharp
// SnapshotController.cs

/// <summary>
/// Gets paths to the latest exported snapshot files
/// </summary>
[HttpGet("latest-paths")]
[ProducesResponseType(typeof(SnapshotPathsResponse), 200)]
public IActionResult GetLatestSnapshotPaths()
{
    var settings = _config.CurrentValue.ExportSettings;
    var dirs = GetOutputDirectories(settings);
    
    string? latestHtml = null;
    string? latestJson = null;
    
    foreach (var dir in dirs)
    {
        if (Directory.Exists(dir))
        {
            latestHtml ??= Directory.GetFiles(dir, "*.html")
                .OrderByDescending(f => File.GetLastWriteTime(f))
                .FirstOrDefault();
            
            latestJson ??= Directory.GetFiles(dir, "*.json")
                .Where(f => !f.EndsWith(".gz"))
                .OrderByDescending(f => File.GetLastWriteTime(f))
                .FirstOrDefault();
        }
        
        if (latestHtml != null && latestJson != null)
            break;
    }
    
    return Ok(new SnapshotPathsResponse
    {
        LatestHtmlPath = latestHtml,
        LatestJsonPath = latestJson,
        Timestamp = DateTime.UtcNow
    });
}

public class SnapshotPathsResponse
{
    public string? LatestHtmlPath { get; set; }
    public string? LatestJsonPath { get; set; }
    public DateTime Timestamp { get; set; }
}
```

---

### Phase 3: Configuration

#### 3.1 Add Settings to appsettings.json

```json
{
  "TrayAppSettings": {
    "ApiBaseUrl": "http://localhost:8999",
    "StatusCheckIntervalMs": 3000,
    
    // Alert notification settings
    "EnableAlertNotifications": true,
    "AlertPollIntervalMs": 5000,
    "SuppressStartupAlerts": true,
    "MaxSeenAlertIds": 1000,
    
    // Balloon notification settings
    "BalloonDisplayTimeMs": 5000,
    "OpenHtmlOnBalloonClick": true,
    "FallbackToSwaggerOnClick": true
  }
}
```

#### 3.2 Extend TrayAppSettings

```csharp
// TrayAppSettings.cs

/// <summary>
/// Enable balloon notifications for new alerts
/// </summary>
public bool EnableAlertNotifications { get; set; } = true;

/// <summary>
/// How often to poll for new alerts (milliseconds)
/// </summary>
public int AlertPollIntervalMs { get; set; } = 5000;

/// <summary>
/// Suppress notifications for alerts that exist at startup
/// </summary>
public bool SuppressStartupAlerts { get; set; } = true;

/// <summary>
/// Maximum number of alert IDs to track (memory management)
/// </summary>
public int MaxSeenAlertIds { get; set; } = 1000;

/// <summary>
/// How long to display balloon notification (milliseconds)
/// </summary>
public int BalloonDisplayTimeMs { get; set; } = 5000;

/// <summary>
/// Open HTML report when balloon is clicked
/// </summary>
public bool OpenHtmlOnBalloonClick { get; set; } = true;

/// <summary>
/// If HTML not available, open Swagger instead
/// </summary>
public bool FallbackToSwaggerOnClick { get; set; } = true;
```

---

## Complete Timer Tick Flow

```csharp
private void StatusTimer_Tick(object? sender, EventArgs e)
{
    if (_isStatusCheckInProgress)
        return;
    
    _isStatusCheckInProgress = true;
    try
    {
        // 1. Update service status (existing)
        UpdateStatus();
        
        // 2. Check for trigger files (existing)
        if (_triggerFileWatcher == null || !_triggerFileWatcher.EnableRaisingEvents)
            ProcessTriggerFilesAsync();
        
        // 3. Check for new alerts (NEW)
        if (_settings.EnableAlertNotifications && _serviceManager.IsRunning())
            CheckForNewAlertsAsync();
    }
    finally
    {
        _isStatusCheckInProgress = false;
    }
}
```

---

## User Experience Flow

```
1. ServerMonitor agent detects high CPU usage
   ↓
2. Alert generated and added to snapshot
   ↓
3. Snapshot exported to HTML/JSON files
   ↓
4. Tray app polls /api/snapshot/alerts/recent (every 5s)
   ↓
5. Tray app detects new alert ID not in _seenAlertIds
   ↓
6. Balloon notification appears:
   ┌─────────────────────────────────────────┐
   │ 🔴 ServerMonitor: Critical              │
   │ [Processor] CPU usage at 95%            │
   │ ─────────────────────────────────────── │
   │ Click to view details                   │
   └─────────────────────────────────────────┘
   ↓
7. User clicks balloon
   ↓
8. Browser opens latest ServerMonitor HTML report
   - Alerts tab shows full alert details
   - User can see all system metrics
```

---

## Alternative: Per-Alert HTML Files

For opening the specific alert rather than the full snapshot, implement alert-specific exports:

```csharp
// Agent: Export individual alert HTML
public string ExportAlertHtml(Alert alert, string baseDir)
{
    var alertDir = Path.Combine(baseDir, "alerts");
    Directory.CreateDirectory(alertDir);
    
    var fileName = $"Alert_{alert.Id}_{alert.Timestamp:yyyyMMdd_HHmmss}.html";
    var path = Path.Combine(alertDir, fileName);
    
    var html = GenerateAlertHtml(alert);
    File.WriteAllText(path, html);
    
    return path;
}

// Tray: Track alert-to-file mapping
private readonly Dictionary<Guid, string> _alertFilePaths = new();

private void OnAlertGenerated(Alert alert, string htmlPath)
{
    _alertFilePaths[alert.Id] = htmlPath;
    ShowAlertBalloon(alert);
}

private void OnBalloonTipClicked(object? sender, EventArgs e)
{
    if (_lastClickedAlertId.HasValue && 
        _alertFilePaths.TryGetValue(_lastClickedAlertId.Value, out var path))
    {
        Process.Start(new ProcessStartInfo { FileName = path, UseShellExecute = true });
    }
}
```

---

## Implementation Checklist

### Tray App Changes
- [ ] Add `AlertInfo` model class
- [ ] Extend `ServerMonitorApiClient` with `GetRecentAlertsAsync()`
- [ ] Add `_seenAlertIds` HashSet for tracking
- [ ] Add `LoadInitialAlertsAsync()` for startup suppression
- [ ] Add `CheckForNewAlertsAsync()` method
- [ ] Add `ShowAlertBalloon()` method
- [ ] Register `BalloonTipClicked` event handler
- [ ] Add `OnBalloonTipClicked()` to open HTML
- [ ] Extend `TrayAppSettings` with alert notification options
- [ ] Update `appsettings.json` with new settings
- [ ] Update timer tick to call alert check

### Agent Changes (Optional)
- [ ] Add `/api/snapshot/latest-paths` endpoint
- [ ] Consider per-alert file export for direct linking

### Testing
- [ ] Verify balloon appears for new alerts
- [ ] Verify startup alerts are suppressed
- [ ] Verify clicking balloon opens HTML
- [ ] Verify memory doesn't grow (seenAlertIds cleanup)
- [ ] Test with service not running
- [ ] Test with network issues

---

## Summary

The recommended approach uses the existing REST API polling mechanism to detect new alerts. When a new alert is found:

1. A balloon notification is shown with alert details
2. The notification icon reflects severity (error/warning/info)
3. Clicking the balloon opens the latest HTML report in the browser
4. Startup alerts are suppressed to avoid notification storms

This approach requires minimal changes and leverages existing infrastructure while providing a good user experience.
