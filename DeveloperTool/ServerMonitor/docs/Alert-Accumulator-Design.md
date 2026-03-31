# Alert Accumulator Design Specification

## Overview

This document describes the design for a unified alert accumulation system that prevents alert flooding while providing configurable thresholds for all alert types in ServerMonitor.

## Problem Statement

### Current Behavior
- Monitors check conditions every poll cycle (1-5 minutes)
- If a condition exceeds threshold, an alert is created **every poll cycle**
- This causes alert flooding (e.g., 996 Event 201 alerts in a single snapshot)
- No deduplication or cooldown mechanism exists

### Example: Event 201 Flooding
```
09:00 - Poll: 350 events found (> 100 threshold) → Alert created
09:01 - Poll: 351 events found (> 100 threshold) → Alert created (duplicate!)
09:02 - Poll: 352 events found (> 100 threshold) → Alert created (duplicate!)
... (continues every minute)
```

## Solution Design

### Core Concept

Implement an **AlertAccumulator** service that:
1. Tracks occurrences of each alert condition over time
2. Only triggers an alert when occurrences exceed `MaxOccurrences` within `TimeWindowMinutes`
3. Clears the accumulator after an alert is distributed (preventing re-alerting on same events)
4. Maintains `LastProcessedTimestamp` to only count genuinely new occurrences

### Data Structures

```csharp
public class AlertAccumulator
{
    // Key format: "MonitorName:AlertType:Context" 
    // Examples: "EventLog:201", "Processor:HighCpu", "Disk:C:LowSpace"
    
    private readonly ConcurrentDictionary<string, List<DateTime>> _occurrences;
    private readonly ConcurrentDictionary<string, DateTime> _lastProcessedTimestamp;
}
```

### Flow Diagram

```
┌─────────────────────────────────────────────────────────────────────┐
│ Monitor detects condition (e.g., Event 201 found, CPU > 90%)        │
└─────────────────────────────────────────────────────────────────────┘
                                │
                                ▼
┌─────────────────────────────────────────────────────────────────────┐
│ Step 1: SANITIZE                                                    │
│ Remove entries from accumulator older than TimeWindowMinutes        │
│                                                                     │
│ _occurrences[key].RemoveAll(t => t < (now - TimeWindowMinutes))     │
└─────────────────────────────────────────────────────────────────────┘
                                │
                                ▼
┌─────────────────────────────────────────────────────────────────────┐
│ Step 2: ADD                                                         │
│ Add new occurrence timestamp(s) to accumulator                      │
│ Only add events newer than _lastProcessedTimestamp[key]             │
│                                                                     │
│ _occurrences[key].Add(timestamp)                                    │
│ Update _lastProcessedTimestamp[key]                                 │
└─────────────────────────────────────────────────────────────────────┘
                                │
                                ▼
┌─────────────────────────────────────────────────────────────────────┐
│ Step 3: CHECK                                                       │
│ Compare count against MaxOccurrences                                │
│                                                                     │
│ if (_occurrences[key].Count > MaxOccurrences)                       │
└─────────────────────────────────────────────────────────────────────┘
                                │
                ┌───────────────┴───────────────┐
                │ YES                           │ NO
                ▼                               ▼
┌───────────────────────────────┐    ┌─────────────────────────────┐
│ Step 4: CREATE & DISTRIBUTE   │    │ No alert                    │
│ Create alert with message:    │    │ Continue accumulating       │
│ "Event X occurred N times     │    │                             │
│  in last Y minutes"           │    │                             │
│                               │    │                             │
│ Step 5: CLEAR ACCUMULATOR     │    │                             │
│ _occurrences[key] = []        │    │                             │
│ (Keep _lastProcessedTimestamp)│    │                             │
└───────────────────────────────┘    └─────────────────────────────┘
```

### Configuration Behavior

| MaxOccurrences | TimeWindowMinutes | Behavior |
|----------------|-------------------|----------|
| 0 | 0 | **Legacy mode**: Alert on every occurrence, no dedup |
| 0 | N | **Immediate + cooldown**: Alert on first occurrence, N-minute cooldown |
| M | N | **Accumulate**: Need M+ occurrences in N minutes before alert |

### Special Cases

#### MaxOccurrences = 0 (Immediate Alert)
- Alert triggers on the **first** occurrence
- `TimeWindowMinutes` acts as a **cooldown period**
- After cooldown expires, next occurrence triggers alert again

#### TimeWindowMinutes = 0 (No Accumulation)
- Every occurrence generates an alert (legacy behavior)
- Useful for critical one-time events that must always be reported
- **Warning**: Can cause flooding if condition persists

### After Alert Distribution

| State | Action | Reason |
|-------|--------|--------|
| Accumulator array | **CLEAR** | Reset count to zero |
| LastProcessedTimestamp | **KEEP** | Only count genuinely new events |

This ensures:
- No re-alerting on the same events that triggered the previous alert
- Fresh accumulation starts from truly new occurrences

---

## Implementation Status: COMPLETED ✅

Implementation was completed on 2026-01-22.

### Phase 1: Core AlertAccumulator Service ✅

- [x] **1.1** Created `AlertAccumulator.cs` in `ServerMonitor.Core/Services/`
  - [x] Defined `ConcurrentDictionary<string, List<DateTime>> _occurrences`
  - [x] Defined `ConcurrentDictionary<string, DateTime> _lastProcessedTimestamp`
  - [x] Implemented `RecordOccurrence(string key, DateTime timestamp, int timeWindowMinutes)`
  - [x] Implemented `RecordOccurrences(string key, IEnumerable<DateTime> timestamps, int timeWindowMinutes)`
  - [x] Implemented `ShouldAlert(string key, int maxOccurrences, int timeWindowMinutes)`
  - [x] Implemented `ClearAfterAlert(string key, int timeWindowMinutes)`
  - [x] Implemented `GetOccurrenceCount(string key, int timeWindowMinutes)`
  - [x] Implemented `GetAccumulatorState(string key)` for diagnostics

- [x] **1.2** Registered AlertAccumulator as singleton in DI container
  - [x] Added `IAlertAccumulator` interface
  - [x] Registered in `Program.cs` service collection

### Phase 2: Configuration Schema Updates ✅

- [x] **2.1** Added `MaxOccurrences` and `TimeWindowMinutes` to all alert configurations
  - [x] EventMonitoring (already had these)
  - [x] ProcessorMonitoring.Alerts
  - [x] MemoryMonitoring.Alerts
  - [x] VirtualMemoryMonitoring.Alerts
  - [x] DiskSpaceMonitoring.Alerts
  - [x] DiskUsageMonitoring.Alerts
  - [x] NetworkMonitoring.Alerts
  - [x] ScheduledTaskMonitoring.Alerts
  - [x] WindowsUpdateMonitoring.Alerts
  - [x] UptimeMonitoring.Alerts

- [x] **2.2** Updated configuration model classes
  - [x] Added properties to alert settings classes in `SurveillanceConfiguration.cs`
  - [x] Added properties to `ScheduledTaskMonitoringSettings.cs`
  - [x] Set sensible defaults for backward compatibility

- [x] **2.3** Updated appsettings.json with new fields

### Phase 3: Monitor Refactoring ✅

- [x] **3.1** Refactored EventLogWatcherService (real-time event monitoring)
  - [x] Injected AlertAccumulator
  - [x] Replaced direct alert creation with accumulator pattern
  - [x] Generates unique key per EventId

- [x] **3.2** Refactored ProcessorMonitor
  - [x] Injected AlertAccumulator
  - [x] Uses accumulator for CPU threshold alerts

- [x] **3.3** Refactored MemoryMonitor
  - [x] Injected AlertAccumulator
  - [x] Uses accumulator for memory threshold alerts

- [x] **3.4** Refactored VirtualMemoryMonitor
  - [x] Injected AlertAccumulator
  - [x] Uses accumulator for virtual memory alerts

- [x] **3.5** Refactored DiskMonitor
  - [x] Injected AlertAccumulator
  - [x] Uses accumulator for disk space and I/O alerts
  - [x] Generates unique key per drive letter

- [x] **3.6** Refactored NetworkMonitor
  - [x] Injected AlertAccumulator
  - [x] Integrated with existing ConsecutiveFailures logic

- [x] **3.7** Refactored ScheduledTaskMonitor
  - [x] Injected AlertAccumulator
  - [x] Uses accumulator for task failure alerts

- [x] **3.8** Refactored WindowsUpdateMonitor
  - [x] Injected AlertAccumulator
  - [x] Uses accumulator for update alerts

- [x] **3.9** Refactored UptimeMonitor
  - [x] Injected AlertAccumulator
  - [x] Uses accumulator for uptime/reboot alerts

### Phase 4: Alert Message Enhancement ✅

- [x] **4.1** Updated alert message format where applicable
  - [x] Includes occurrence count: "Occurred N times in the last Y minutes"

### Phase 5: Testing & Validation ✅

- [x] **5.1** Build verification
  - [x] All monitors compile successfully with no errors

### Phase 6: Documentation ✅

- [x] **6.1** Created Alert Configuration User Manual (`docs/Alert-Configuration-Guide.md`)
- [x] **6.2** Updated design specification (`docs/Alert-Accumulator-Design.md`)

---

## Files to Create/Modify

### New Files
| File | Description |
|------|-------------|
| `ServerMonitor.Core/Services/AlertAccumulator.cs` | Core accumulator service |
| `ServerMonitor.Core/Services/IAlertAccumulator.cs` | Interface for DI |
| `docs/Alert-Configuration-Guide.md` | User manual |

### Modified Files
| File | Changes |
|------|---------|
| `ServerMonitor/Program.cs` | Register AlertAccumulator in DI |
| `ServerMonitor.Core/Configuration/*.cs` | Add MaxOccurrences/TimeWindowMinutes to alert configs |
| `ServerMonitor/appsettings.json` | Add new alert config fields |
| `ServerMonitor.Core/Monitors/EventLogMonitor.cs` | Use accumulator |
| `ServerMonitor.Core/Monitors/ProcessorMonitor.cs` | Use accumulator |
| `ServerMonitor.Core/Monitors/MemoryMonitor.cs` | Use accumulator |
| `ServerMonitor.Core/Monitors/VirtualMemoryMonitor.cs` | Use accumulator |
| `ServerMonitor.Core/Monitors/DiskMonitor.cs` | Use accumulator |
| `ServerMonitor.Core/Monitors/NetworkMonitor.cs` | Use accumulator |
| `ServerMonitor.Core/Monitors/ScheduledTaskMonitor.cs` | Use accumulator |
| `ServerMonitor.Core/Monitors/WindowsUpdateMonitor.cs` | Use accumulator |
| `ServerMonitor.Core/Monitors/UptimeMonitor.cs` | Use accumulator |
| `ServerMonitor.Core/Monitors/Db2DiagMonitor.cs` | *Future* - uses own pattern-based throttling via `PatternsToMonitor` |

---

## Risk Assessment

| Risk | Mitigation |
|------|------------|
| Breaking existing alert behavior | Default values match current behavior |
| Memory growth from accumulator | Sanitize old entries; bounded by TimeWindowMinutes |
| Thread safety issues | Use ConcurrentDictionary |
| Lost state on restart | Acceptable - fresh accumulation starts |
| Complex configuration | Provide clear documentation and examples |

---

## Version History

| Version | Date | Changes |
|---------|------|---------|
| 1.0 | 2026-01-22 | Initial design specification |
