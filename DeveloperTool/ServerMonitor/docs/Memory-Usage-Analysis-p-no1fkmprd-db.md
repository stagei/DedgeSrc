# ServerMonitor Memory Usage Analysis: p-no1fkmprd-db

**Date:** 2026-02-02  
**Reported Issue:** Agent using ~1037-1460 MB of memory while snapshot is only 0.21-1.07 MB

---

## Executive Summary

The ServerMonitor agent on **p-no1fkmprd-db** is consuming significantly more memory than other servers. Analysis reveals that the high memory usage is primarily in **native/unmanaged memory** (~724 MB), not in managed .NET data structures.

| Metric | p-no1fkmprd-db | t-no1fkmtst-db (Reference) |
|--------|----------------|----------------------------|
| Working Set | **1,436 MB** | 198 MB |
| Private Memory | 1,416 MB | 109 MB |
| GC Managed Memory | 692 MB | 29 MB |
| Native Memory (est.) | ~724 MB | ~80 MB |
| Alerts in Memory | 187-217 | 12 |
| DB2 Entries | 0 | 0 |
| Snapshot Size | 1.07 MB | 0.02 MB |

---

## Memory Breakdown Comparison

| Server | Working Set | Private | GC Managed | Native Est. | Alerts | Version |
|--------|-------------|---------|------------|-------------|--------|---------|
| **p-no1fkmprd-db** | **1,436 MB** | 1,416 MB | 692 MB | 724 MB | 187 | 1.0.226 |
| p-no1inlprd-db | 767 MB | 688 MB | 239 MB | 449 MB | 1,000 | 1.0.132 |
| p-no1fkxprd-db | 285 MB | 193 MB | 43 MB | 150 MB | 2 | 1.0.132 |
| t-no1fkmtst-db | 198 MB | 109 MB | 29 MB | 80 MB | 12 | 1.0.226 |
| t-no1fkmdev-db | 183 MB | 96 MB | 32 MB | 64 MB | 0 | 1.0.226 |
| p-no1fkmprd-app | 182 MB | 99 MB | 18 MB | 81 MB | 2 | 1.0.226 |
| t-no1fkmtst-app | 168 MB | 99 MB | 18 MB | 81 MB | 1 | 1.0.226 |

**Lowest memory usage:** `t-no1fkmtst-app` at **168 MB** (with 1 alert)

---

## Analysis of p-no1fkmprd-db Memory

### Alert Data Analysis

The server has 187-217 alerts in memory, categorized as:

| Category | Count |
|----------|-------|
| Database/XFKMPRD | 180 |
| Database/FKMPRD | 3 |
| Db2Instance | 3 |
| WindowsUpdate | 1 |

**Alert metadata size analysis:**
- Total alerts JSON (compressed): **0.5 MB**
- DB2 raw blocks in metadata: **0.16 MB**
- Distribution history records: 37

**Conclusion:** The alert data itself accounts for only ~0.5 MB - this does NOT explain 1,400+ MB usage.

### Memory Type Breakdown

| Memory Type | Size | Description |
|-------------|------|-------------|
| **GC Managed** | 692 MB | .NET managed heap objects |
| **Native/Unmanaged** | ~724 MB | Native allocations, runtime overhead, fragmentation |
| **Total Working Set** | 1,436 MB | All memory pages in physical RAM |

---

## Likely Causes

### 1. .NET Runtime Overhead & Fragmentation
The Large Object Heap (LOH) in .NET can become fragmented over time, especially with:
- Large string allocations (DB2 raw log entries)
- Repeated JSON serialization/deserialization
- Long-running process without restart

### 2. Native Memory Usage
~724 MB of native memory suggests:
- **DB2 drivers/libraries** - IBM DB2 client libraries use native memory
- **Windows COM/WMI components** - Used for monitoring Windows Updates, Event Log, etc.
- **Kestrel HTTP server** - ASP.NET Core web server buffers

### 3. Accumulation Over Time
- Server has been running continuously since last reboot
- Memory may accumulate due to:
  - String interning
  - GC not aggressively collecting Gen2 objects
  - Native handle leaks

---

## Configuration Check

Current memory management settings in `appsettings.json`:

```json
"MemoryManagement": {
  "CleanupAgeHours": 24,
  "MaxAlertsInMemory": 1000,
  "CleanupIntervalMinutes": 60
}
```

```json
"Db2DiagMonitoring": {
  "KeepAllEntriesInMemory": true,
  "MaxEntriesInMemory": 10000
}
```

**Note:** The agent has `SelfMonitoring.MemoryThresholdMB: 3072` which would trigger shutdown at 3 GB - we haven't hit that yet.

---

## Recommendations

### Immediate Actions

1. **Restart the ServerMonitor agent on p-no1fkmprd-db**
   - This will reset memory to baseline (~180-200 MB)
   - Can be done via: `Stop-Process -Name ServerMonitor` on the server

2. **Monitor memory growth pattern**
   - Check if memory grows linearly over time
   - Identify if specific operations cause spikes

### Configuration Adjustments

1. **Reduce MaxEntriesInMemory** for DB2 diagnostics:
   ```json
   "MaxEntriesInMemory": 1000  // Reduce from 10000
   ```

2. **Consider disabling KeepAllEntriesInMemory** on high-volume servers:
   ```json
   "KeepAllEntriesInMemory": false
   ```

3. **Lower MemoryThresholdMB** for more aggressive auto-restart:
   ```json
   "MemoryThresholdMB": 1024  // Currently 3072
   ```

### Code Improvements (Future)

1. Add periodic GC.Collect() for long-running instances
2. Implement native memory tracking via NativeMemory APIs
3. Add memory usage metrics to snapshot with detailed breakdown
4. Consider using `ArrayPool<T>` for large allocations
5. Investigate DB2 driver memory usage patterns

---

## Comparison: Healthy vs High Memory

### Healthy Server (t-no1fkmtst-db)
- Memory: 198 MB
- Alerts: 12
- Version: 1.0.226 (latest)
- Snapshot: 0.02 MB

### High Memory Server (p-no1fkmprd-db)
- Memory: 1,436 MB (**7.2x higher**)
- Alerts: 187 (**15.6x more alerts**)
- Version: 1.0.226 (latest)
- Snapshot: 1.07 MB

### Correlation
While p-no1fkmprd-db has ~15x more alerts, it has ~24x more managed memory and ~9x more native memory. This disproportionate growth suggests **memory fragmentation** or **accumulation** rather than just data volume.

---

## Root Cause: MASSIVE FILE READ EVERY MINUTE

### The Primary Cause

**The db2diag.log file is 210 MB and is read entirely into memory every minute!**

Log evidence:
```
[DB2] File read: 4292ms | Total lines: 4,782,445 | File size: 211,245,119 bytes
```

The code in `Db2DiagMonitor.cs` line 649:
```csharp
var lines = await File.ReadAllLinesAsync(diagFile.FullName, encoding, cancellationToken)
```

### Memory Math

| Component | Size |
|-----------|------|
| File size (UTF-8) | 210 MB |
| × 2 for UTF-16 in .NET | 420 MB |
| + 4.7M string object headers (~24 bytes each) | 113 MB |
| + string[] array overhead | ~10 MB |
| **Total per read cycle** | **~550 MB** |

### Why Memory Fluctuates

The logs show memory fluctuating between 942 MB and 1,426 MB:

```
16:01:55 - Self-monitoring: 1,426 MB used
16:02:25 - Self-monitoring: 1,333 MB used
16:03:25 - Self-monitoring: 1,130 MB used
16:04:25 - Self-monitoring: 987 MB used
16:05:55 - Self-monitoring: 942 MB used  (GC completed)
16:06:25 - Self-monitoring: 1,028 MB used (new file read)
16:08:25 - Self-monitoring: 1,072 MB used
```

**Pattern:**
1. Minute N: Read 210 MB file → allocate ~550 MB → memory peaks at 1,400 MB
2. GC runs → memory drops to ~950 MB
3. Minute N+1: Read file again before GC completes → peaks higher

### Secondary Issue: Alert Accumulation

Alerts are also growing (679 → 891 in 6 minutes) because duplicates are added to the snapshot before being suppressed. However, this is a minor contributor (~2 MB) compared to the file read issue.

---

## Conclusion

The memory usage on p-no1fkmprd-db (1,000-1,400 MB) is caused by **reading a 210 MB log file into memory every minute**:

1. **Db2DiagMonitor** reads the entire db2diag.log file using `File.ReadAllLinesAsync()`
2. The file is **210 MB** with **4.7 million lines**
3. In .NET, this creates **~550 MB of temporary allocations** per read
4. Reading happens every 60 seconds (monitoring interval)
5. GC cannot keep up → memory stays high with sawtooth pattern

### Immediate Actions

1. **Restart the agent** to reset memory baseline
2. Consider **rotating/truncating** the db2diag.log file (it's 210 MB!)

### Code Improvements (Future)

1. **Streaming read** - Use `StreamReader` instead of `ReadAllLinesAsync()`
2. **Incremental reading** - Only read new content since last check (track file position)
3. **File size limit** - Skip files larger than a threshold or read only tail
4. **Memory pooling** - Reuse buffers for string operations

### Secondary Issue

The alert duplication bug (duplicates added before suppression check) is also present but contributes only ~2 MB - not the main cause.

---

*Generated by ServerMonitor Log Analysis - 2026-02-02*
