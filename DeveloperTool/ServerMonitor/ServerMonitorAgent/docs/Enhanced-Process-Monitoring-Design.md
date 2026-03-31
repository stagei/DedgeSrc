# Enhanced Process Monitoring Design

## Overview

This document describes how to implement comprehensive process monitoring that tracks the top 10 most resource-intensive processes with detailed metadata including CPU time, disk I/O, memory usage, and service associations.

---

## Windows Capabilities

### ✅ What's Available in .NET

Windows provides extensive process information through:

1. **`System.Diagnostics.Process`** - Basic process information
2. **`System.Management.ManagementObject`** (WMI)** - Advanced metrics
3. **`System.Diagnostics.PerformanceCounter`** - Real-time performance data
4. **`System.ServiceProcess.ServiceController`** - Service information

### Available Process Metadata

#### From `Process` Class:
- ✅ Process ID (PID)
- ✅ Process Name
- ✅ Executable Path (`MainModule.FileName`)
- ✅ Working Set (Memory)
- ✅ Private Memory
- ✅ Virtual Memory
- ✅ Start Time
- ✅ CPU Time (`TotalProcessorTime`)
- ✅ Thread Count
- ✅ Handle Count
- ✅ User Name (running as)

#### From WMI (`Win32_Process`):
- ✅ Command Line
- ✅ Executable Path
- ✅ Parent Process ID
- ✅ Creation Date
- ✅ Kernel Mode Time
- ✅ User Mode Time
- ✅ Page File Usage
- ✅ Working Set Size
- ✅ Peak Working Set Size
- ✅ Page Faults
- ✅ I/O Read Bytes
- ✅ I/O Write Bytes
- ✅ I/O Read Operations
- ✅ I/O Write Operations

#### From Performance Counters:
- ✅ Real-time CPU % per process
- ✅ Real-time Disk I/O per process
- ✅ Real-time Network I/O per process

#### Service Association:
- ✅ `ServiceController.GetServices()` - Get all services
- ✅ `Win32_Service` WMI class - Service executable path
- ✅ Match service executable to process by PID or path

---

## Implementation Design

### 1. Enhanced TopProcess Model

**Current Model:**
```csharp
public class TopProcess
{
    public string Name { get; init; } = string.Empty;
    public int Pid { get; init; }
    public double CpuPercent { get; init; }
    public long MemoryMB { get; init; }
}
```

**Enhanced Model:**
```csharp
public class TopProcess
{
    public string Name { get; init; } = string.Empty;
    public int Pid { get; init; }
    public string ExecutablePath { get; init; } = string.Empty;
    public string CommandLine { get; init; } = string.Empty;
    public string UserName { get; init; } = string.Empty;
    public DateTime StartTime { get; init; }
    
    // CPU Metrics
    public double CpuPercent { get; init; }
    public TimeSpan TotalCpuTime { get; init; }
    public TimeSpan UserCpuTime { get; init; }
    public TimeSpan KernelCpuTime { get; init; }
    
    // Memory Metrics
    public long MemoryMB { get; init; }
    public long PrivateMemoryMB { get; init; }
    public long VirtualMemoryMB { get; init; }
    public long PeakMemoryMB { get; init; }
    
    // Disk I/O Metrics
    public long DiskReadBytes { get; init; }
    public long DiskWriteBytes { get; init; }
    public long DiskReadOperations { get; init; }
    public long DiskWriteOperations { get; init; }
    
    // Process Info
    public int ThreadCount { get; init; }
    public int HandleCount { get; init; }
    public long PageFaults { get; init; }
    
    // Service Association
    public string? ServiceName { get; init; }
    public string? ServiceDisplayName { get; init; }
    public string? ServiceStatus { get; init; }
}
```

### 2. Process History Tracking

**New Model for History:**
```csharp
public class ProcessHistoryEntry
{
    public DateTime Timestamp { get; init; }
    public int Pid { get; init; }
    public string ProcessName { get; init; } = string.Empty;
    public double CpuPercent { get; init; }
    public long MemoryMB { get; init; }
    public long DiskReadBytes { get; init; }
    public long DiskWriteBytes { get; init; }
    public string? ServiceName { get; init; }
}

public class ProcessHistory
{
    public List<ProcessHistoryEntry> TopProcessesByCpu { get; set; } = new();
    public List<ProcessHistoryEntry> TopProcessesByMemory { get; set; } = new();
    public List<ProcessHistoryEntry> TopProcessesByDiskIO { get; set; } = new();
    public DateTime LastUpdated { get; set; }
}
```

### 3. Global Snapshot Integration

**Add to SystemSnapshot:**
```csharp
public class SystemSnapshot
{
    // ... existing properties ...
    
    /// <summary>
    /// History of top processes over time (for export only)
    /// </summary>
    public ProcessHistory? ProcessHistory { get; set; }
}
```

**Add to GlobalSnapshotService:**
```csharp
public class GlobalSnapshotService
{
    // Internal tracking (not in snapshot until export)
    private readonly List<ProcessHistoryEntry> _processHistory = new();
    private readonly object _processHistoryLock = new();
    
    /// <summary>
    /// Updates process history (called periodically, not on every monitor cycle)
    /// </summary>
    public void UpdateProcessHistory(List<TopProcess> topProcesses)
    {
        lock (_processHistoryLock)
        {
            var entry = new ProcessHistoryEntry
            {
                Timestamp = DateTime.UtcNow,
                // ... populate from topProcesses ...
            };
            
            _processHistory.Add(entry);
            
            // Keep only last N entries (e.g., last 100 snapshots)
            if (_processHistory.Count > 100)
            {
                _processHistory.RemoveAt(0);
            }
        }
    }
    
    /// <summary>
    /// Gets process history for export (creates copy)
    /// </summary>
    public ProcessHistory GetProcessHistory()
    {
        lock (_processHistoryLock)
        {
            return new ProcessHistory
            {
                TopProcessesByCpu = _processHistory
                    .OrderByDescending(e => e.CpuPercent)
                    .Take(10)
                    .ToList(),
                TopProcessesByMemory = _processHistory
                    .OrderByDescending(e => e.MemoryMB)
                    .Take(10)
                    .ToList(),
                TopProcessesByDiskIO = _processHistory
                    .OrderByDescending(e => e.DiskReadBytes + e.DiskWriteBytes)
                    .Take(10)
                    .ToList(),
                LastUpdated = DateTime.UtcNow
            };
        }
    }
}
```

---

## Performance Implications

### ⚠️ CRITICAL: Process Enumeration is Expensive

**Current Impact:**
- `Process.GetProcesses()` is called **every 30 seconds** (CPU monitor)
- `Process.GetProcesses()` is called **every 60 seconds** (Memory monitor)
- **Total: ~120 process enumerations per hour**

**With Enhanced Monitoring:**

#### Option 1: Full Metadata Every Poll (NOT RECOMMENDED)
- **Impact**: 30-50% CPU increase
- **Why**: Accessing `MainModule.FileName`, WMI queries, PerformanceCounters for each process
- **Cost**: ~500-1000ms per enumeration on systems with 100+ processes

#### Option 2: Cached Process List with Periodic Refresh (RECOMMENDED)
- **Impact**: 5-10% CPU increase
- **Approach**: 
  - Cache process list for 60-120 seconds
  - Only refresh when needed
  - Use cached data for metadata extraction
- **Cost**: ~200-400ms per enumeration, but only every 60-120 seconds

#### Option 3: Incremental Updates (BEST PERFORMANCE)
- **Impact**: 2-5% CPU increase
- **Approach**:
  - Track PIDs of top processes
  - Only query metadata for tracked PIDs
  - Refresh full list every 5-10 minutes
- **Cost**: ~50-100ms per poll (only querying 10-20 processes)

### Performance Breakdown

#### Process.GetProcesses() Cost:
- **Time**: 100-300ms for 100 processes
- **CPU**: 5-15% spike during enumeration
- **Memory**: Temporary allocation of ~10-50 MB

#### WMI Query Cost (Win32_Process):
- **Time**: 200-500ms for 100 processes
- **CPU**: 10-20% spike
- **Memory**: ~20-100 MB temporary allocation
- **Network**: If WMI over network (not applicable for local)

#### PerformanceCounter Per Process:
- **Time**: 5-10ms per process
- **CPU**: 1-2% per counter
- **Memory**: Minimal

#### Service Association Lookup:
- **Time**: 50-200ms (one-time cache)
- **CPU**: 2-5% during initial lookup
- **Memory**: ~5-20 MB for service cache

### Recommended Approach

**Hybrid Caching Strategy:**

1. **Full Process List**: Refresh every **120 seconds** (2 minutes)
2. **Top 10 Processes**: Update every **30 seconds** (current CPU polling interval)
3. **Metadata Extraction**: Only for top 10 processes, using cached full list
4. **Service Mapping**: Cache service-to-process mapping, refresh every **10 minutes**

**Expected Performance:**
- **CPU Increase**: 3-7% (vs current 30%)
- **Memory Increase**: +10-30 MB (for caches)
- **Collection Time**: +100-200ms per CPU monitor cycle

---

## Implementation Details

### 1. Process Metadata Extraction

```csharp
private TopProcess GetProcessMetadata(Process process, Dictionary<int, ServiceInfo> serviceMap)
{
    try
    {
        // Basic info (fast)
        var pid = process.Id;
        var name = process.ProcessName;
        
        // Executable path (slow - ~5-10ms)
        string executablePath = string.Empty;
        try
        {
            executablePath = process.MainModule?.FileName ?? string.Empty;
        }
        catch { } // Access denied for some processes
        
        // CPU time (fast)
        var cpuTime = process.TotalProcessorTime;
        var userTime = process.UserProcessorTime;
        var kernelTime = process.PrivilegedProcessorTime;
        
        // Memory (fast)
        var memoryMB = process.WorkingSet64 / 1024 / 1024;
        var privateMemoryMB = process.PrivateMemorySize64 / 1024 / 1024;
        var virtualMemoryMB = process.VirtualMemorySize64 / 1024 / 1024;
        
        // Process info (fast)
        var threadCount = process.Threads.Count;
        var handleCount = process.HandleCount;
        var startTime = process.StartTime;
        
        // User name (slow - ~10-20ms)
        string userName = string.Empty;
        try
        {
            userName = process.StartInfo.UserName ?? 
                      GetProcessOwner(pid); // WMI fallback
        }
        catch { }
        
        // WMI for advanced metrics (slow - ~50-100ms per process)
        long diskReadBytes = 0;
        long diskWriteBytes = 0;
        long pageFaults = 0;
        string commandLine = string.Empty;
        
        try
        {
            using (var searcher = new ManagementObjectSearcher(
                $"SELECT * FROM Win32_Process WHERE ProcessId = {pid}"))
            {
                foreach (ManagementObject obj in searcher.Get())
                {
                    diskReadBytes = Convert.ToInt64(obj["ReadTransferCount"] ?? 0);
                    diskWriteBytes = Convert.ToInt64(obj["WriteTransferCount"] ?? 0);
                    pageFaults = Convert.ToInt64(obj["PageFaults"] ?? 0);
                    commandLine = obj["CommandLine"]?.ToString() ?? string.Empty;
                }
            }
        }
        catch { }
        
        // Service association (fast - from cache)
        ServiceInfo? serviceInfo = null;
        if (serviceMap.TryGetValue(pid, out var service))
        {
            serviceInfo = service;
        }
        else
        {
            // Try to match by executable path
            serviceInfo = serviceMap.Values
                .FirstOrDefault(s => s.ExecutablePath.Equals(executablePath, StringComparison.OrdinalIgnoreCase));
        }
        
        return new TopProcess
        {
            Name = name,
            Pid = pid,
            ExecutablePath = executablePath,
            CommandLine = commandLine,
            UserName = userName,
            StartTime = startTime,
            CpuPercent = CalculateCpuPercent(process), // Requires history
            TotalCpuTime = cpuTime,
            UserCpuTime = userTime,
            KernelCpuTime = kernelTime,
            MemoryMB = memoryMB,
            PrivateMemoryMB = privateMemoryMB,
            VirtualMemoryMB = virtualMemoryMB,
            DiskReadBytes = diskReadBytes,
            DiskWriteBytes = diskWriteBytes,
            ThreadCount = threadCount,
            HandleCount = handleCount,
            PageFaults = pageFaults,
            ServiceName = serviceInfo?.ServiceName,
            ServiceDisplayName = serviceInfo?.DisplayName,
            ServiceStatus = serviceInfo?.Status
        };
    }
    catch (Exception ex)
    {
        _logger.LogWarning(ex, "Failed to get metadata for process {Pid}", process.Id);
        return null;
    }
}
```

### 2. CPU Percent Calculation

**Requires Historical Tracking:**

```csharp
private class ProcessCpuTracker
{
    private readonly Dictionary<int, (DateTime timestamp, TimeSpan cpuTime)> _lastMeasurements = new();
    
    public double CalculateCpuPercent(Process process, TimeSpan interval)
    {
        var pid = process.Id;
        var currentCpuTime = process.TotalProcessorTime;
        var currentTime = DateTime.UtcNow;
        
        if (_lastMeasurements.TryGetValue(pid, out var last))
        {
            var cpuDelta = (currentCpuTime - last.cpuTime).TotalMilliseconds;
            var timeDelta = (currentTime - last.timestamp).TotalMilliseconds;
            
            if (timeDelta > 0)
            {
                var cpuPercent = (cpuDelta / timeDelta) * 100.0 / Environment.ProcessorCount;
                _lastMeasurements[pid] = (currentTime, currentCpuTime);
                return cpuPercent;
            }
        }
        
        _lastMeasurements[pid] = (currentTime, currentCpuTime);
        return 0;
    }
}
```

### 3. Service Mapping Cache

```csharp
private class ServiceInfo
{
    public string ServiceName { get; init; } = string.Empty;
    public string DisplayName { get; init; } = string.Empty;
    public string ExecutablePath { get; init; } = string.Empty;
    public string Status { get; init; } = string.Empty;
    public int? ProcessId { get; init; }
}

private Dictionary<int, ServiceInfo> BuildServiceMap()
{
    var serviceMap = new Dictionary<int, ServiceInfo>();
    
    try
    {
        // Get services via WMI (includes executable path)
        using (var searcher = new ManagementObjectSearcher("SELECT * FROM Win32_Service"))
        {
            foreach (ManagementObject service in searcher.Get())
            {
                var serviceName = service["Name"]?.ToString() ?? string.Empty;
                var pathName = service["PathName"]?.ToString() ?? string.Empty;
                var processId = service["ProcessId"] != null ? 
                    Convert.ToInt32(service["ProcessId"]) : (int?)null;
                
                if (processId.HasValue)
                {
                    serviceMap[processId.Value] = new ServiceInfo
                    {
                        ServiceName = serviceName,
                        DisplayName = service["DisplayName"]?.ToString() ?? string.Empty,
                        ExecutablePath = ExtractExecutablePath(pathName),
                        Status = service["State"]?.ToString() ?? string.Empty,
                        ProcessId = processId
                    };
                }
            }
        }
    }
    catch (Exception ex)
    {
        _logger.LogWarning(ex, "Failed to build service map");
    }
    
    return serviceMap;
}
```

### 4. Optimized Top Process Collection

```csharp
private class ProcessCache
{
    private DateTime _lastRefresh = DateTime.MinValue;
    private List<Process> _cachedProcesses = new();
    private readonly TimeSpan _refreshInterval = TimeSpan.FromSeconds(120);
    private readonly object _lock = new();
    
    public List<Process> GetProcesses(bool forceRefresh = false)
    {
        lock (_lock)
        {
            if (forceRefresh || DateTime.UtcNow - _lastRefresh > _refreshInterval)
            {
                _cachedProcesses = Process.GetProcesses().ToList();
                _lastRefresh = DateTime.UtcNow;
            }
            return _cachedProcesses;
        }
    }
}

private List<TopProcess> GetTopProcessesWithMetadata(int count)
{
    var processCache = GetProcessCache(); // Singleton
    var serviceMap = GetServiceMap(); // Cached, refreshed every 10 minutes
    
    var processes = processCache.GetProcesses();
    
    // First pass: Get basic metrics (fast)
    var processMetrics = processes
        .AsParallel()
        .Select(p =>
        {
            try
            {
                return new
                {
                    Process = p,
                    MemoryMB = p.WorkingSet64 / 1024 / 1024,
                    CpuTime = p.TotalProcessorTime
                };
            }
            catch { return null; }
        })
        .Where(p => p != null)
        .OrderByDescending(p => p!.MemoryMB) // Or CPU, or combined metric
        .Take(count * 2) // Get more candidates for metadata extraction
        .ToList();
    
    // Second pass: Get detailed metadata only for top candidates (slower)
    var topProcesses = processMetrics
        .AsParallel()
        .Select(p => GetProcessMetadata(p!.Process, serviceMap))
        .Where(p => p != null)
        .OrderByDescending(p => p!.MemoryMB + p!.CpuPercent * 10) // Combined metric
        .Take(count)
        .ToList();
    
    return topProcesses!;
}
```

---

## Integration with GlobalSnapshotService

### Storage Strategy

**Key Principle**: Process history is **NOT stored in the main snapshot object** - it's only added during export.

**Implementation:**

```csharp
public class GlobalSnapshotService
{
    // Main snapshot (lightweight, always available)
    private SystemSnapshot _currentSnapshot;
    
    // Process history (separate, only for export)
    private readonly ProcessHistoryManager _processHistory = new();
    
    public SystemSnapshot GetCurrentSnapshot()
    {
        lock (_lock)
        {
            // Return lightweight snapshot (no process history)
            _currentSnapshot.Metadata.Timestamp = DateTime.UtcNow;
            return _currentSnapshot;
        }
    }
    
    public SystemSnapshot GetSnapshotForExport()
    {
        lock (_lock)
        {
            // Create copy with process history for export
            var snapshot = CloneSnapshot(_currentSnapshot);
            snapshot.ProcessHistory = _processHistory.GetHistory();
            return snapshot;
        }
    }
}
```

### Update Frequency

**Recommendation:**
- Update process history **every 60-120 seconds** (not every CPU poll)
- Store last 50-100 snapshots
- Only include in export (JSON, HTML, REST API)

**Why:**
- Reduces CPU overhead (process enumeration is expensive)
- History is only needed for export/analysis
- Main snapshot stays lightweight for real-time API access

---

## Performance Summary

### Current State (After CPU Optimization)
- **CPU Usage**: ~5-10% (down from 30%)
- **Process Enumeration**: Every 30s (CPU) + Every 60s (Memory) = ~120/hour
- **Cost per Enumeration**: ~100-300ms, 5-15% CPU spike

### With Enhanced Process Monitoring (Recommended Approach)

#### Option A: Cached + Periodic (RECOMMENDED)
- **CPU Usage**: ~8-15% (3-5% increase)
- **Process Enumeration**: Every 120s (full list) + Every 30s (top 10 metadata)
- **Cost**: 
  - Full enumeration: ~200-400ms every 2 minutes
  - Top 10 metadata: ~100-200ms every 30 seconds
- **Memory**: +20-50 MB (caches)

#### Option B: Incremental Updates (BEST PERFORMANCE)
- **CPU Usage**: ~6-12% (1-2% increase)
- **Process Enumeration**: Every 600s (10 minutes) for full refresh
- **Top 10 Updates**: Every 30s, only query tracked PIDs
- **Cost**:
  - Full enumeration: ~200-400ms every 10 minutes
  - Top 10 updates: ~50-100ms every 30 seconds
- **Memory**: +10-30 MB

### Performance Comparison

| Approach | CPU Increase | Memory Increase | Collection Time | Refresh Frequency |
|----------|-------------|-----------------|-----------------|------------------|
| **Current** | Baseline | Baseline | ~100ms | Every 30-60s |
| **Option A (Cached)** | +3-5% | +20-50 MB | +100-200ms | Full: 120s, Top: 30s |
| **Option B (Incremental)** | +1-2% | +10-30 MB | +50-100ms | Full: 600s, Top: 30s |
| **Option C (Full Every Poll)** | +20-30% | +50-100 MB | +500-1000ms | Every 30s ❌ |

---

## Recommended Implementation Plan

### Phase 1: Enhanced TopProcess Model
1. ✅ Extend `TopProcess` class with new properties
2. ✅ Add service association fields
3. ✅ Update JSON serialization (camelCase)

### Phase 2: Process Metadata Extraction
1. ✅ Implement `GetProcessMetadata()` with caching
2. ✅ Add WMI queries for disk I/O (with error handling)
3. ✅ Implement service mapping cache
4. ✅ Add CPU percent calculation with history tracking

### Phase 3: Process History Manager
1. ✅ Create `ProcessHistoryManager` class
2. ✅ Store history separately from main snapshot
3. ✅ Implement retention (last 50-100 entries)
4. ✅ Add to export methods only

### Phase 4: Integration
1. ✅ Update `ProcessorMonitor` to use enhanced collection
2. ✅ Update `GlobalSnapshotService` to manage history
3. ✅ Update export methods to include history
4. ✅ Update REST API to optionally include history

### Phase 5: Performance Optimization
1. ✅ Implement process caching (120s refresh)
2. ✅ Implement service mapping cache (10min refresh)
3. ✅ Use incremental updates for top 10
4. ✅ Add performance logging

---

## Configuration

**Add to appsettings.json:**
```json
{
  "ProcessorMonitoring": {
    "TrackTopProcesses": 10,
    "ProcessHistoryEnabled": true,
    "ProcessHistoryRetention": 100,
    "ProcessCacheRefreshSeconds": 120,
    "ServiceMapRefreshMinutes": 10,
    "IncludeProcessHistoryInApi": false  // Only in exports
  }
}
```

---

## Export Behavior

### REST API (`/api/Snapshot`)
- **Default**: No process history (lightweight)
- **With Query Parameter**: `?includeHistory=true` - includes process history

### JSON Export (File)
- **Always includes**: Process history (for analysis)

### HTML Export
- **Always includes**: Process history with charts/visualizations

---

## Conclusion

**Yes, this is fully possible in Windows**, but requires careful performance management:

1. ✅ **Use caching** - Don't enumerate processes every poll
2. ✅ **Separate storage** - Keep history separate from main snapshot
3. ✅ **Incremental updates** - Only query metadata for top processes
4. ✅ **Optional in API** - History only when requested
5. ✅ **Service mapping** - Cache service-to-process associations

**Expected Impact:**
- **CPU**: +1-5% (with proper caching)
- **Memory**: +10-50 MB (for caches and history)
- **Value**: Comprehensive process monitoring with service associations

