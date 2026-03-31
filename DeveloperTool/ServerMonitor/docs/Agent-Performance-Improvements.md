# ServerMonitor Agent - Performance Improvements

## Critical Issue: CPU Spike at Startup

### Problem
When the agent starts on a server, it consumes almost all CPU for several seconds during baseline/initial data collection. This affects production systems significantly.

### Root Cause
In `SurveillanceOrchestrator.StartMonitoringCycles()`, all monitors start simultaneously with `TimeSpan.Zero` delay:

```csharp
var timer = new Timer(
    async _ => await RunMonitorCycleAsync(monitor),
    null,
    TimeSpan.Zero,  // ALL monitors fire immediately!
    TimeSpan.FromSeconds(interval));
```

This causes 10+ monitors (Processor, Memory, VirtualMemory, Disk, Network, Uptime, WindowsUpdate, EventLog, ScheduledTask, Db2Diag) to all collect data simultaneously at startup.

### Solution: Staggered Monitor Startup
Implement staggered startup where each monitor starts with an incremental delay:

```csharp
private void StartMonitoringCycles()
{
    var startupDelaySeconds = 0;
    var staggerIntervalSeconds = 3; // 3 seconds between each monitor start
    
    foreach (var monitor in _monitors.Where(m => m.IsEnabled))
    {
        var interval = GetMonitorInterval(monitor);
        if (interval > 0)
        {
            var initialDelay = TimeSpan.FromSeconds(startupDelaySeconds);
            
            var timer = new Timer(
                async _ => await RunMonitorCycleAsync(monitor),
                null,
                initialDelay,  // Staggered start
                TimeSpan.FromSeconds(interval));

            _monitorTimers[monitor.Category] = timer;

            _logger.LogInformation("Started monitoring cycle for {Category} (initial delay: {Delay}s, interval: {Interval}s)",
                monitor.Category, startupDelaySeconds, interval);
            
            startupDelaySeconds += staggerIntervalSeconds;
        }
    }
}
```

### Priority Order for Staggered Startup
Consider starting lightweight monitors first:
1. **Uptime** (fast, simple WMI query)
2. **Memory** (single WMI query)
3. **VirtualMemory** (performance counter)
4. **Processor** (performance counter with sampling)
5. **Disk** (multiple drives)
6. **Network** (ping tests - can take time)
7. **ScheduledTask** (Task Scheduler enumeration)
8. **EventLog** (log parsing - can be heavy)
9. **WindowsUpdate** (WMI query - can be slow)
10. **Db2Diag** (file parsing - conditional)

---

## Additional Performance Improvements

### 1. Reduce Process Enumeration Frequency
**Current**: Top processes collected every CPU/Memory cycle
**Improvement**: Cache process list for 30 seconds, only refresh on interval

```csharp
private List<ProcessInfo>? _cachedProcesses;
private DateTime _lastProcessRefresh;
private readonly TimeSpan _processCacheTimeout = TimeSpan.FromSeconds(30);

private List<ProcessInfo> GetTopProcesses()
{
    if (_cachedProcesses != null && 
        (DateTime.Now - _lastProcessRefresh) < _processCacheTimeout)
    {
        return _cachedProcesses;
    }
    
    _cachedProcesses = CollectProcesses();
    _lastProcessRefresh = DateTime.Now;
    return _cachedProcesses;
}
```

### 2. Lazy Initialization for Heavy Monitors
Some monitors (EventLog, WindowsUpdate, Db2Diag) should skip their first intensive scan:

```csharp
private bool _initialScanComplete = false;

public async Task<MonitorResult> CollectAsync()
{
    if (!_initialScanComplete)
    {
        // First run: just mark current state as baseline
        _lastProcessedTime = DateTime.UtcNow;
        _initialScanComplete = true;
        return new MonitorResult { Success = true, Data = null };
    }
    
    // Subsequent runs: normal processing
    return await CollectChangesAsync();
}
```

### 3. Performance Counter Pooling
Create shared performance counter instances to avoid repeated creation:

```csharp
public class PerformanceCounterPool : IDisposable
{
    private readonly Dictionary<string, PerformanceCounter> _counters = new();
    private readonly SemaphoreSlim _lock = new(1, 1);
    
    public PerformanceCounter GetOrCreate(string category, string counter, string instance = "")
    {
        var key = $"{category}|{counter}|{instance}";
        if (!_counters.TryGetValue(key, out var pc))
        {
            pc = new PerformanceCounter(category, counter, instance);
            _counters[key] = pc;
        }
        return pc;
    }
}
```

### 4. Async WMI Queries
Replace synchronous WMI calls with async patterns:

```csharp
private async Task<double> GetCpuUsageAsync()
{
    return await Task.Run(() =>
    {
        using var searcher = new ManagementObjectSearcher(
            "SELECT PercentProcessorTime FROM Win32_PerfFormattedData_PerfOS_Processor WHERE Name='_Total'");
        // ...
    });
}
```

### 5. Configurable Startup Mode
Add configuration option for production-friendly startup:

```json
{
  "Surveillance": {
    "StartupMode": {
      "StaggeredStartup": true,
      "StaggerIntervalSeconds": 5,
      "SkipInitialBaseline": false,
      "DelayFirstCollectionSeconds": 10
    }
  }
}
```

### 6. Memory Management Improvements
- Use `ArrayPool<T>` for temporary buffers
- Implement object pooling for frequently created objects
- Add memory pressure detection to reduce collection frequency

### 7. Reduce Logging Overhead
- Use structured logging with conditional compilation
- Batch log writes
- Reduce debug logging in release builds

---

## Implementation Priority

| Priority | Improvement | Impact | Effort |
|----------|-------------|--------|--------|
| 🔴 High | Staggered monitor startup | High | Low |
| 🔴 High | Skip initial baseline for EventLog | High | Low |
| 🟡 Medium | Process enumeration caching | Medium | Low |
| 🟡 Medium | Performance counter pooling | Medium | Medium |
| 🟢 Low | Async WMI queries | Low | Medium |
| 🟢 Low | Configurable startup mode | Low | Low |

---

## Monitoring & Metrics

Add startup performance logging:

```csharp
_logger.LogInformation("=== STARTUP METRICS ===");
_logger.LogInformation("Total monitors: {Count}", _monitors.Count());
_logger.LogInformation("Enabled monitors: {Count}", _monitors.Count(m => m.IsEnabled));
_logger.LogInformation("Stagger interval: {Interval}s", staggerInterval);
_logger.LogInformation("Estimated full startup time: {Time}s", 
    _monitors.Count(m => m.IsEnabled) * staggerInterval);
```
