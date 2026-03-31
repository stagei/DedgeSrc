# Event Monitoring in ServerMonitor Agent

## Overview

The ServerMonitor agent monitors Windows Event Logs using two methods:
1. **Polling** - Periodically queries event logs for matching events
2. **Real-Time Hooks** - Uses system hooks for critical events like shutdown (Event ID 1074)

## Architecture

```
┌─────────────────────────────────────────────────────────────────┐
│                    SurveillanceWorker                           │
│                    (Main orchestrator)                          │
└─────────────────────────────┬───────────────────────────────────┘
                              │
                              ▼
┌─────────────────────────────────────────────────────────────────┐
│                    EventLogMonitor                              │
│                    (IMonitor implementation)                    │
│                                                                 │
│   ┌─────────────────────────────────────────────────────────┐   │
│   │  CollectAsync()                                         │   │
│   │  - Called every PollingIntervalSeconds                  │   │
│   │  - Iterates through EventsToMonitor[]                   │   │
│   │  - Filters by Enabled property                          │   │
│   │  - Calls CheckEventAsync() for each event               │   │
│   └─────────────────────────────────────────────────────────┘   │
└─────────────────────────────┬───────────────────────────────────┘
                              │
                              ▼
┌─────────────────────────────────────────────────────────────────┐
│                    CheckEventAsync()                            │
│   - Queries Windows Event Log using EventLogReader             │
│   - Filters by: EventId, Source, LogName                       │
│   - Counts occurrences in TimeWindowMinutes                    │
│   - If Count > MaxOccurrences → Generate Alert                 │
└─────────────────────────────────────────────────────────────────┘
```

## Polling Flow (Primary Method)

### 1. Configuration Loading

```json
{
  "EventMonitoring": {
    "Enabled": true,                    // Master switch for all event monitoring
    "PollingIntervalSeconds": 120,      // How often to check (2 minutes)
    "EventsToMonitor": [
      {
        "Enabled": true,                // Per-event enable/disable
        "EventId": 4625,
        "Description": "Security - Failed login attempt",
        "Source": "Microsoft-Windows-Security-Auditing",
        "LogName": "Security",
        "Level": "Warning",
        "MaxOccurrences": 10,           // Alert if > 10 occurrences
        "TimeWindowMinutes": 5          // in the last 5 minutes
      }
    ]
  }
}
```

### 2. Collection Cycle

```
Every PollingIntervalSeconds:
┌──────────────────────────────────────────────────────────────────┐
│ 1. SurveillanceWorker calls EventLogMonitor.CollectAsync()      │
│                                                                  │
│ 2. EventLogMonitor filters to enabled events:                   │
│    var enabledEvents = EventsToMonitor.Where(e => e.Enabled)    │
│                                                                  │
│ 3. For each enabled event config:                               │
│    ┌──────────────────────────────────────────────────────────┐ │
│    │ a. Open EventLogReader for LogName                       │ │
│    │ b. Build XPath query:                                    │ │
│    │    "*[System[EventID={EventId}] and                      │ │
│    │     System[TimeCreated >= {TimeWindowStart}]]"           │ │
│    │ c. Count matching events                                 │ │
│    │ d. If Count > MaxOccurrences → Create Alert              │ │
│    └──────────────────────────────────────────────────────────┘ │
│                                                                  │
│ 4. Return MonitorResult with:                                   │
│    - Data: Event counts and details                             │
│    - Alerts: Any generated alerts                               │
└──────────────────────────────────────────────────────────────────┘
```

### 3. XPath Query Construction

The monitor uses Windows Event Log's XPath query capability:

```csharp
// Example query for Event ID 4625 in last 5 minutes
var query = $@"*[System[
    EventID={eventConfig.EventId} and 
    TimeCreated[timediff(@SystemTime) <= {timeWindowMs}]
]]";

var eventLogQuery = new EventLogQuery(eventConfig.LogName, PathType.LogName, query);
using var reader = new EventLogReader(eventLogQuery);
```

### 4. Event Counting Logic

```csharp
// Count all matching events
int count = 0;
while (reader.ReadEvent() != null)
{
    count++;
}

// Check against threshold
if (count > eventConfig.MaxOccurrences)
{
    // MaxOccurrences = 0 means "alert on ANY occurrence"
    // MaxOccurrences = 5 means "alert only if MORE than 5"
    GenerateAlert(eventConfig, count);
}
```

## Real-Time Hooks (For Critical Events)

For events like system shutdown (Event ID 1074), polling is unreliable because:
- The service may be stopped before the poll occurs
- The event happens AT shutdown, not before

### Current Implementation: ShutdownInterceptorService

⚠️ **IMPORTANT**: Currently, `UseRealTimeHooks` is **ONLY implemented for Event ID 1074**.

```csharp
// In ShutdownInterceptorService.cs line 45:
var eventsWithHooks = eventMonitoring.EventsToMonitor
    .Where(e => e.UseRealTimeHooks && e.EventId == 1074) // Only Event ID 1074!
    .ToList();
```

If you set `UseRealTimeHooks: true` on other events (e.g., Event ID 411), **it will be ignored** and the event will still be processed via polling.

```
┌─────────────────────────────────────────────────────────────────┐
│                 ShutdownInterceptorService                      │
│                 (BackgroundService)                             │
│                                                                 │
│   Uses: Microsoft.Win32.SystemEvents                            │
│   Only handles: Event ID 1074 (shutdown)                        │
│                                                                 │
│   ┌─────────────────────────────────────────────────────────┐   │
│   │  SystemEvents.SessionEnding += OnSessionEnding          │   │
│   │  SystemEvents.SessionEnded += OnSessionEnded            │   │
│   └─────────────────────────────────────────────────────────┘   │
│                                                                 │
│   When shutdown detected:                                       │
│   1. Immediately log the event                                  │
│   2. Generate alert (if configured)                             │
│   3. Allow graceful shutdown                                    │
└─────────────────────────────────────────────────────────────────┘
```

### UseRealTimeHooks Configuration

```json
{
  "EventId": 1074,
  "Description": "System - System shutdown/restart initiated",
  "UseRealTimeHooks": true,    // ← Uses real-time hooks instead of polling
  "SuppressedChannels": []
}
```

## Current: Real-Time Monitoring with EventLogWatcher ✅

**IMPLEMENTED**: The `EventLogWatcherService` now uses `EventLogWatcher` for ALL events.

### How EventLogWatcherService Works

```
┌─────────────────────────────────────────────────────────────────┐
│                 EventLogWatcherService                          │
│                 (IHostedService - runs at startup)              │
│                                                                 │
│   Groups events by LogName for efficiency:                      │
│   ┌─────────────────────────────────────────────────────────┐   │
│   │  // For all events in System log:                       │   │
│   │  var query = new EventLogQuery("System", PathType.LogName, │
│   │      "*[System[(EventID=1074) or (EventID=6008) ...]]");│   │
│   │                                                         │   │
│   │  var watcher = new EventLogWatcher(query);              │   │
│   │  watcher.EventRecordWritten += OnEventRecordWritten;    │   │
│   │  watcher.Enabled = true;                                │   │
│   └─────────────────────────────────────────────────────────┘   │
│                                                                 │
│   OS pushes events to callback → Zero polling overhead!         │
│                                                                 │
│   Event tracking per type:                                      │
│   - Maintains occurrence count within TimeWindowMinutes         │
│   - Cleans up old occurrences automatically                     │
│   - Triggers alert when count > MaxOccurrences                  │
└─────────────────────────────────────────────────────────────────┘
```

### Key Features

- **Grouped watchers**: Events are grouped by LogName (e.g., System, Security, Application) to minimize resource usage
- **XPath queries**: Uses efficient XPath to match multiple event IDs in a single query
- **Time window tracking**: Each event type tracks occurrences within its configured `TimeWindowMinutes`
- **Immediate alerts**: Alerts fire as soon as threshold is crossed, not at polling interval

### Comparison: Old Polling vs New EventLogWatcher

| Aspect | Old Polling | New EventLogWatcher |
|--------|-------------|---------------------|
| **CPU Usage** | Every 600s, scans all event logs | Zero until event occurs |
| **Latency** | Up to 10 minutes | Immediate (milliseconds) |
| **Reliability** | Could miss events between polls | Catches all events |
| **Resource usage** | One query per poll cycle | One watcher per log type |
| **Configuration** | `PollingIntervalSeconds` | Not needed (always real-time) |

### Files Changed

| File | Change |
|------|--------|
| `EventLogWatcherService.cs` | **NEW** - Real-time event monitoring |
| `EventLogMonitor.cs` | Polling code commented out, `IsEnabled = false` |
| `Program.cs` | Registers `EventLogWatcherService` as hosted service |

### Event Occurrence Tracking

```csharp
private class EventOccurrenceTracker
{
    public EventToMonitor EventConfig { get; set; }
    public List<DateTime> Occurrences { get; set; }  // Within time window
    public DateTime? LastOccurrence { get; set; }
    public string? LastMessage { get; set; }
}
```

When an event is received:
1. Record the occurrence timestamp
2. Remove occurrences older than `TimeWindowMinutes`
3. Check if count > `MaxOccurrences`
4. If threshold exceeded → Create and send alert

## Alert Generation

When an event threshold is exceeded:

```
┌──────────────────────────────────────────────────────────────────┐
│ Alert Generated:                                                 │
│                                                                  │
│ {                                                                │
│   "Category": "Event",                                           │
│   "Severity": "{Level from config}",  // Warning, Error, etc.   │
│   "Message": "Event 4625 occurred 15 times in 5 minutes",       │
│   "Timestamp": "2026-01-14T10:30:00Z",                          │
│   "Details": {                                                   │
│     "EventId": 4625,                                            │
│     "Description": "Security - Failed login attempt",           │
│     "OccurrenceCount": 15,                                      │
│     "TimeWindowMinutes": 5,                                     │
│     "Threshold": 10                                             │
│   }                                                              │
│ }                                                                │
└──────────────────────────────────────────────────────────────────┘
```

## Code Files Involved

| File | Purpose |
|------|---------|
| `Monitors/EventLogMonitor.cs` | Main polling logic |
| `Services/ShutdownInterceptorService.cs` | Real-time shutdown hooks |
| `Configuration/SurveillanceConfiguration.cs` | `EventToMonitor` class with `Enabled` property |
| `Models/SystemSnapshot.cs` | Event data in snapshot |

## Per-Event Enable/Disable

The `Enabled` property on each event allows granular control:

```csharp
// In EventLogMonitor.CollectAsync()
var enabledEvents = settings.EventsToMonitor.Where(e => e.Enabled).ToList();

_logger.LogDebug("Event monitoring: {EnabledCount} of {TotalCount} events enabled",
    enabledEvents.Count, settings.EventsToMonitor.Count);

foreach (var eventConfig in enabledEvents)
{
    // Only process enabled events
    var eventResult = await CheckEventAsync(eventConfig, cancellationToken);
    // ...
}
```

## Example: Disabling a Specific Event

To disable monitoring of "DCOM - Server did not register" (Event ID 10010):

```json
{
  "Enabled": false,           // ← Set to false to disable this specific event
  "EventId": 10010,
  "Description": "DCOM - Server did not register with DCOM",
  "Source": "Microsoft-Windows-DistributedCOM",
  "LogName": "System",
  "Level": "Error",
  "MaxOccurrences": 10,
  "TimeWindowMinutes": 60
}
```

The event will be skipped during collection, but remains in the config for easy re-enabling.
