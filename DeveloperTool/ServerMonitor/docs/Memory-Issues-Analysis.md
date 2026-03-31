# ServerMonitor Memory Issues Analysis

## Executive Summary

This document identifies all potential memory issues in the ServerMonitor agent and provides solutions for each. The analysis covers collections that grow unbounded, resources that lack proper cleanup, and caching strategies that may consume excessive memory.

**Status**: ✅ **ALL ISSUES FIXED** - See implementation details below.

---

## Configuration

All memory cleanup is now configurable via `appsettings.json`:

```json
{
  "General": {
    "MemoryManagement": {
      "CleanupAgeHours": 24,
      "MaxAlertsInMemory": 1000,
      "CleanupIntervalMinutes": 60
    }
  }
}
```

| Setting | Default | Description |
|---------|---------|-------------|
| `CleanupAgeHours` | 24 | Maximum age for in-memory items before cleanup |
| `MaxAlertsInMemory` | 1000 | Maximum alerts to keep (oldest removed first) |
| `CleanupIntervalMinutes` | 60 | How often the cleanup timer runs |

---

## 🔴 Critical Issues (FIXED)

### 1. **Alerts Collection - Unbounded Growth** ✅ FIXED

**Location**: `GlobalSnapshotService.AddAlert()`

**Problem**: Alerts were added to `_currentSnapshot.Alerts` but **never removed**.

**Solution Implemented**:
- Added `CleanupOldAlerts()` method called on every `AddAlert()`
- Added `RunPeriodicCleanup()` method called by cleanup timer
- Uses configurable `CleanupAgeHours` and `MaxAlertsInMemory`

```csharp
private void CleanupOldAlerts()
{
    var memSettings = _config.CurrentValue.General.MemoryManagement;
    var cleanupAgeHours = memSettings.CleanupAgeHours;
    var maxAlerts = memSettings.MaxAlertsInMemory;
    
    // Remove alerts older than cleanup age
    var cutoffTime = DateTime.UtcNow.AddHours(-cleanupAgeHours);
    _currentSnapshot.Alerts.RemoveAll(a => a.Timestamp < cutoffTime);
    
    // Enforce max count (remove oldest first)
    if (maxAlerts > 0 && _currentSnapshot.Alerts.Count > maxAlerts)
    {
        var sorted = _currentSnapshot.Alerts.OrderBy(a => a.Timestamp).ToList();
        var excess = sorted.Count - maxAlerts;
        var toRemove = sorted.Take(excess).Select(a => a.Id).ToHashSet();
        _currentSnapshot.Alerts.RemoveAll(a => toRemove.Contains(a.Id));
    }
}
```

**Impact**: Memory bounded by age AND count limits.

---

**Original Problem**:
```csharp
public void AddAlert(Alert alert)
{
    lock (_lock)
    {
        _currentSnapshot.Alerts.Add(alert);
        
        // Clean up old alerts (keep only last 24 hours)
        var maxRetentionWindow = TimeSpan.FromHours(24);
        var cutoffTime = DateTime.UtcNow - maxRetentionWindow;
        
        var removedCount = _currentSnapshot.Alerts.RemoveAll(a => a.Timestamp < cutoffTime);
        
        if (removedCount > 0)
        {
            _logger.LogDebug("Cleaned up {Count} old alerts (older than {Hours} hours)", 
                removedCount, maxRetentionWindow.TotalHours);
        }
        
        TouchTimestamp();
    }
}
```

**Alternative Solution** - Configuration-based max count:
```csharp
// In appsettings.json
"Alerting": {
    "MaxAlertsInMemory": 1000,
    "AlertRetentionHours": 24
}

// In AddAlert()
if (_currentSnapshot.Alerts.Count > settings.MaxAlertsInMemory)
{
    var excess = _currentSnapshot.Alerts.Count - settings.MaxAlertsInMemory;
    _currentSnapshot.Alerts.RemoveRange(0, excess); // Remove oldest
}
```

---

### 2. **External Event Tracking Dictionaries - No Cleanup** ✅ FIXED

**Location**: `AlertManager`

**Problem**: Two dictionaries tracked external event metadata but were never cleaned up.

**Solution Implemented**:
- Added `CleanupExternalEventTracking()` method called during `TrackAlert()`
- Added `RunPeriodicCleanup()` method called by cleanup timer
- Uses configurable `CleanupAgeHours`

```csharp
private void CleanupExternalEventTracking(DateTime cutoffTime)
{
    var staleCodes = _lastExternalEventAlert
        .Where(kvp => kvp.Value < cutoffTime)
        .Select(kvp => kvp.Key)
        .ToList();
    
    foreach (var code in staleCodes)
    {
        _lastExternalEventAlert.Remove(code);
        _externalEventTimeWindows.Remove(code);
    }
}
```

**Impact**: Memory bounded by cleanup age.

---

**Original Problem**:
```csharp
private void CleanupExternalEventTracking()
{
    lock (_lock)
    {
        var yesterday = DateTime.UtcNow.AddHours(-24);
        
        // Clean up old alert times
        var staleCodes = _lastExternalEventAlert
            .Where(kvp => kvp.Value < yesterday)
            .Select(kvp => kvp.Key)
            .ToList();
        
        foreach (var code in staleCodes)
        {
            _lastExternalEventAlert.Remove(code);
            _externalEventTimeWindows.Remove(code);
        }
        
        if (staleCodes.Count > 0)
        {
            _logger.LogDebug("Cleaned up {Count} stale external event tracking entries", staleCodes.Count);
        }
    }
}

// Call from TrackAlert() or on a periodic timer
```

---

## ⚠️ Medium Priority Issues

### 3. **PerformanceCounter Resources - No IDisposable** ✅ FIXED

**Location**: `ProcessorMonitor`, `MemoryMonitor`, `VirtualMemoryMonitor`

**Problem**: Monitors created `PerformanceCounter` instances but didn't implement `IDisposable`.

**Solution Implemented**:
- Added `IDisposable` interface to all three monitors
- PerformanceCounters are disposed on service shutdown (not during normal operation)
- DI container automatically calls `Dispose()` when service stops

```csharp
public class ProcessorMonitor : IMonitor, IDisposable
{
    private bool _disposed;
    
    public void Dispose()
    {
        Dispose(true);
        GC.SuppressFinalize(this);
    }
    
    protected virtual void Dispose(bool disposing)
    {
        if (_disposed) return;
        if (disposing)
        {
            _cpuCounter?.Dispose();
            foreach (var counter in _perCoreCounters)
                counter?.Dispose();
            _perCoreCounters.Clear();
        }
        _disposed = true;
    }
}
```

**Note**: DiskMonitor already uses `using var` for its temporary counters - no changes needed.

---

### 4. **ProcessCpuTracker._lastMeasurements - Unbounded PID Tracking** ✅ FIXED

**Location**: `ProcessCpuTracker.cs`

**Problem**: Tracked CPU measurements per process ID with no age-based cleanup.

**Solution Implemented**:
- Added `CleanupOldMeasurements(int maxAgeHours)` method
- Added `RunPeriodicCleanupIfNeeded()` for automatic cleanup
- Uses configurable `CleanupAgeHours` from General.MemoryManagement

```csharp
public void CleanupOldMeasurements(int maxAgeHours)
{
    lock (_lock)
    {
        var cutoffTime = DateTime.UtcNow.AddHours(-maxAgeHours);
        var staleEntries = _lastMeasurements
            .Where(kvp => kvp.Value.timestamp < cutoffTime)
            .Select(kvp => kvp.Key)
            .ToList();
        
        foreach (var pid in staleEntries)
            _lastMeasurements.Remove(pid);
    }
}
```

**Impact**: Memory bounded by cleanup age.

---

**Original Problem**:
```csharp
public double CalculateCpuPercent(Process process, TimeSpan? interval = null)
{
    // ... existing code ...
    
    // Periodic cleanup (every 100 measurements)
    if (_lastMeasurements.Count > 0 && _lastMeasurements.Count % 100 == 0)
    {
        CleanupStaleEntries();
    }
}

private void CleanupStaleEntries()
{
    var cutoff = DateTime.UtcNow.AddMinutes(-10);
    var stale = _lastMeasurements.Where(kvp => kvp.Value.timestamp < cutoff).ToList();
    foreach (var entry in stale)
    {
        _lastMeasurements.Remove(entry.Key);
    }
}
```

---

### 5. **ProcessCache._cachedProcesses - Process Object References**

**Location**: `ProcessCache.cs` (lines 40-44)

**Status**: ✅ **PROPERLY HANDLED**

The cache correctly disposes old process objects before refreshing:
```csharp
// Dispose old processes
foreach (var process in _cachedProcesses)
{
    try { process.Dispose(); } catch { }
}
```

**Note**: This is correct behavior. No action needed.

---

### 6. **Rolling Window Collections - Properly Bounded**

**Location**: Multiple monitors

**Status**: ✅ **PROPERLY HANDLED**

These collections are properly cleaned up based on `SustainedDurationSeconds`:
- `MemoryMonitor._memoryMeasurements`
- `ProcessorMonitor._cpuMeasurements`
- `VirtualMemoryMonitor._virtualMemoryMeasurements`
- `DiskMonitor._diskMeasurements`

Example cleanup pattern (correct):
```csharp
var cutoffTime = now.AddSeconds(-settings.Thresholds.SustainedDurationSeconds);
_memoryMeasurements.RemoveAll(m => m.timestamp < cutoffTime);
```

**Note**: No action needed.

---

### 7. **DB2 Diagnostic Entries - Configurable Limit**

**Location**: `Db2DiagMonitor.cs` (lines 159-175)

**Status**: ✅ **PROPERLY HANDLED** (with configuration)

The in-memory storage has a configurable maximum:
```csharp
if (settings.MaxEntriesInMemory > 0 && _allEntries.Count > settings.MaxEntriesInMemory)
{
    var excess = _allEntries.Count - settings.MaxEntriesInMemory;
    _allEntries.RemoveRange(0, excess);
}
```

**Default Configuration**:
- `KeepAllEntriesInMemory`: `true`
- `MaxEntriesInMemory`: `10000`

**Recommendation**: Ensure configuration is appropriate for your environment. Each `Db2DiagEntry` can be ~1-5 KB, so 10,000 entries = 10-50 MB.

---

## 💡 Low Priority / Enhancement Opportunities

### 8. **ExternalEvents Collection - Already Fixed**

**Location**: `GlobalSnapshotService.AddExternalEvent()` (lines 457-482)

**Status**: ✅ **ALREADY FIXED**

24-hour cleanup is properly implemented:
```csharp
var maxRetentionWindow = TimeSpan.FromHours(24);
var registeredCutoff = DateTime.UtcNow - maxRetentionWindow;
var removedCount = _currentSnapshot.ExternalEvents.RemoveAll(e => e.RegisteredTimestamp < registeredCutoff);
```

---

### 9. **AlertManager._recentAlerts - Already Has Cleanup**

**Location**: `AlertManager.TrackAlert()` (lines 579-589)

**Status**: ✅ **ALREADY HANDLED**

24-hour cleanup is properly implemented:
```csharp
var yesterday = DateTime.UtcNow.AddHours(-24);
var keysToRemove = _recentAlerts
    .Where(kvp => kvp.Value < yesterday)
    .Select(kvp => kvp.Key)
    .ToList();

foreach (var keyToRemove in keysToRemove)
{
    _recentAlerts.Remove(keyToRemove);
}
```

---

### 10. **AlertManager._alertTimestamps Queue - Already Has Cleanup**

**Location**: `AlertManager.IsThrottled()` (lines 478-481)

**Status**: ✅ **ALREADY HANDLED**

Old timestamps are dequeued:
```csharp
while (_alertTimestamps.Count > 0 && _alertTimestamps.Peek() < oneHourAgo)
{
    _alertTimestamps.Dequeue();
}
```

---

## 📊 Summary Table

| Issue | Location | Status | Priority | Memory Impact |
|-------|----------|--------|----------|---------------|
| Alerts unbounded growth | `GlobalSnapshotService` | ✅ **FIXED** | 🔴 Critical | High (KB per alert) |
| External event tracking | `AlertManager` | ✅ **FIXED** | 🔴 Critical | Low (100 bytes/code) |
| PerformanceCounter disposal | Monitors | ✅ **FIXED** | ⚠️ Medium | Low (native handles) |
| ProcessCpuTracker cleanup | `ProcessCpuTracker` | ✅ **FIXED** | ⚠️ Medium | Low (32 bytes/PID) |
| ProcessCache disposal | `ProcessCache` | ✅ **OK** | - | - |
| Rolling window collections | Monitors | ✅ **OK** | - | - |
| DB2 entries | `Db2DiagMonitor` | ✅ **OK** | - | Configurable |
| ExternalEvents cleanup | `GlobalSnapshotService` | ✅ **OK** | - | - |
| Recent alerts cleanup | `AlertManager` | ✅ **OK** | - | - |
| Alert timestamps queue | `AlertManager` | ✅ **OK** | - | - |

---

## 🎯 Action Items Completed

### Priority 1 (Critical) ✅
1. ✅ **Added cleanup to `GlobalSnapshotService.AddAlert()`** - Implements configurable age AND count-based retention
2. ✅ **Added cleanup to `AlertManager` external event dictionaries** - Cleans up old event code entries

### Priority 2 (Medium) ✅
3. ✅ **Implemented `IDisposable` on monitors** - ProcessorMonitor, MemoryMonitor, VirtualMemoryMonitor properly clean up PerformanceCounter instances on shutdown
4. ✅ **Added automatic cleanup to `ProcessCpuTracker`** - New `CleanupOldMeasurements()` and `RunPeriodicCleanupIfNeeded()` methods

### Priority 3 (Recommendation)
5. **Review DB2 `MaxEntriesInMemory` setting** - Default 10,000 should be appropriate for most environments

---

## Cleanup Timer Implementation

All cleanup is orchestrated by `SurveillanceOrchestrator`:

```csharp
private async Task RunAllCleanupTasksAsync()
{
    try
    {
        _logger.LogDebug("Running periodic cleanup tasks...");
        
        // 1. Memory cleanup: Alerts, ExternalEvents, tracking dictionaries
        _globalSnapshot.RunPeriodicCleanup();
        _alertManager.RunPeriodicCleanup();
        
        // 2. File cleanup: Old snapshot files
        await _snapshotExporter.CleanupOldSnapshotsAsync();
        
        _logger.LogDebug("Periodic cleanup tasks completed");
    }
    catch (Exception ex)
    {
        _logger.LogWarning(ex, "Error during periodic cleanup - will retry on next cycle");
    }
}
```

Timer runs at the configured `CleanupIntervalMinutes` (default: 60 minutes).

---

## Testing Recommendations

1. **Memory Growth Test**: Run service for 7+ days, generate alerts every hour, monitor memory with `Get-Process ServerMonitor | Select WorkingSet64`

2. **Stress Test**: Submit 1000+ unique `externalEventCode` values, verify memory doesn't grow linearly

3. **Long-running Baseline**: After fixes, establish baseline memory usage over 30-day period

4. **Verify Cleanup Logging**: Check logs for "Periodic memory cleanup" messages to confirm cleanup is running

---

## Configuration (Already Implemented)

Memory management is now configurable in `appsettings.json`:

```json
{
  "General": {
    "MemoryManagement": {
      "CleanupAgeHours": 24,
      "MaxAlertsInMemory": 1000,
      "CleanupIntervalMinutes": 60
    }
  }
}
```

---

## Conclusion

✅ **ALL MEMORY ISSUES HAVE BEEN FIXED**

The ServerMonitor agent now has comprehensive memory management:
1. **Alerts** - Cleaned by age (CleanupAgeHours) and count (MaxAlertsInMemory)
2. **External event tracking** - Cleaned by age on each TrackAlert() and periodically
3. **PerformanceCounters** - Properly disposed on service shutdown via IDisposable
4. **ProcessCpuTracker** - New age-based cleanup methods

The cleanup timer runs at the configured interval (default: hourly) and cleans all in-memory collections.
