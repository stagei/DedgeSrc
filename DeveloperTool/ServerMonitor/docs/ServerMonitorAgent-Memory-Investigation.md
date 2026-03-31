# ServerMonitorAgent Memory Investigation

**Date:** 2026-02-20  
**Issue:** Agent reported using 12+ GB RAM on a 16 GB server  
**Threshold configured:** 3 GB (should auto-shutdown at 3,072 MB)

---

## 1. Existing Memory Safeguard — Self-Monitoring

The agent has a built-in memory watchdog in `SurveillanceOrchestrator.CheckProcessMemory()`:

| Setting | Default | Location |
|---------|---------|----------|
| `SelfMonitoring.Enabled` | `true` | `SurveillanceConfiguration.cs:669` |
| `SelfMonitoring.MemoryThresholdMB` | `3072` (3 GB) | `SurveillanceConfiguration.cs:676` |
| `SelfMonitoring.CheckIntervalSeconds` | `30` | `SurveillanceConfiguration.cs:689` |
| `SelfMonitoring.ShutdownDelaySeconds` | `10` | `SurveillanceConfiguration.cs:683` |

**How it works:**

1. A `System.Threading.Timer` fires every 30 seconds
2. Reads `Process.GetCurrentProcess().WorkingSet64`
3. If `WorkingSet64 > MemoryThresholdMB`, it:
   - Logs a warning
   - Sends an alert via `AlertManager.ProcessAlertsSync()`
   - Waits `ShutdownDelaySeconds` (10s)
   - Calls `IHostApplicationLifetime.StopApplication()` for graceful shutdown
   - Falls back to `Environment.Exit(1)` if callback is null

**Why it may have failed to prevent 12 GB usage:**

- The timer fires every 30 seconds. Between checks, a single collection cycle (especially DB2 diag processing) can allocate multiple GB in a burst that is never checked.
- `WorkingSet64` measures committed physical memory, but large managed allocations may not immediately reflect in working set if the GC has not compacted yet.
- If the self-monitoring timer callback itself throws or deadlocks, the check silently stops.
- The interval is further *increased* (less frequent) on low-capacity servers via `ScalingService`.

---

## 2. Root Cause Analysis — Where Memory Goes

### 2.1. DB2 Diag Log Full-File Read (Primary Suspect)

**File:** `Db2DiagMonitor.cs:657`

```csharp
var lines = await File.ReadAllLinesAsync(diagFile.FullName, encoding, cancellationToken);
```

The entire `db2diag.log` file is read into a `string[]` array in one shot.

| Config | Default | appsettings Override |
|--------|---------|----------------------|
| `MaxLogFileSizeBytes` | 314,572,800 (300 MB) | 524,288,000 (500 MB) |

A 500 MB text file loaded via `ReadAllLinesAsync` produces:

- ~500 MB for the raw byte buffer during read
- ~1,000 MB for the `string[]` array (UTF-16 strings in .NET are 2× the byte size)
- **Total: ~1.5 GB per file, per read cycle**

With **multiple DB2 instances** (DB2, DB2FED, DB2HST, DB2HFED, DB2DOC, DB2DBQA), each having its own `db2diag.log`, a single collection cycle can read **multiple large files sequentially**, with GC not guaranteed to reclaim the previous array before the next one is allocated.

**Worst case:** 4 instances × 500 MB files = **6 GB** just for file reads in one cycle.

### 2.2. In-Memory Diag Entry Storage (Secondary Suspect)

**File:** `Db2DiagMonitor.cs:41-44` and `Db2DiagMonitor.cs:318-329`

```csharp
private readonly List<Db2DiagEntry> _allEntries = new();    // Persistent storage
...
db2Data.AllEntries = _allEntries.ToList();                   // Full copy each cycle
```

| Config | Default | appsettings Override |
|--------|---------|----------------------|
| `KeepAllEntriesInMemory` | `true` | `true` |
| `MaxEntriesInMemory` | 10,000 | 10,000 |

**Two copies exist simultaneously:**

1. `Db2DiagMonitor._allEntries` — persistent list, trimmed to 10,000
2. `GlobalSnapshotService._currentSnapshot.Db2Diagnostics.AllEntries` — full `.ToList()` copy

Each `Db2DiagEntry` object contains:

- `RawBlock` (string) — the complete raw log block text (can be **1–50 KB** per entry)
- `CallStack` (List<string>) — optional, can have dozens of frames
- `DataSections` (List<Db2DataSection>) — optional, can contain large data values
- `Description` (Db2DiagDescription) — ZRC, probe, message, level info objects
- 20+ string properties (Timestamp, RecordId, Level, ProcessId, ThreadId, etc.)

**Conservative estimate per entry:** 5–10 KB average, but entries with large call stacks or data sections can be 50+ KB.

At 10,000 entries × 10 KB average × 2 copies = **~200 MB**.  
At 10,000 entries × 50 KB (worst case) × 2 copies = **~1 GB**.

### 2.3. Alert Metadata with RawBlock (Contributing Factor)

**File:** `Db2DiagMonitor.cs:1354`

```csharp
["Db2RawBlock"] = entry.RawBlock ?? ""
```

Every DB2 diag alert copies the full `RawBlock` into its metadata dictionary.

| Config | Default |
|--------|---------|
| `MaxAlertsInMemory` | 1,000 |
| `CleanupAgeHours` | 24 |

With 1,000 alerts and large `RawBlock` values, this adds **10–50 MB** of duplicate string data.

### 2.4. Snapshot Size Estimation is Inaccurate

**File:** `GlobalSnapshotService.cs:342-349`

```csharp
private double EstimateSnapshotSizeMB()
{
    var alertSize = (_currentSnapshot.Alerts?.Count ?? 0) * 2.0;      // ~2KB per alert
    var eventSize = (_currentSnapshot.ExternalEvents?.Count ?? 0) * 0.5;
    var db2Size = (_currentSnapshot.Db2Diagnostics?.AllEntries?.Count ?? 0) * 5.0; // ~5KB per entry

    return (alertSize + eventSize + db2Size) / 1024.0;
}
```

The estimate uses 5 KB per DB2 entry and 2 KB per alert. Real sizes are likely **2–10× higher** due to `RawBlock`, call stacks, and metadata. The snapshot size reported in the dashboard understates actual memory consumption.

### 2.5. MaxEntriesInMemory = 0 Disables Trimming

**File:** `Db2DiagMonitor.cs:321-327`

```csharp
if (settings.MaxEntriesInMemory > 0 && _allEntries.Count > settings.MaxEntriesInMemory)
{
    var excess = _allEntries.Count - settings.MaxEntriesInMemory;
    _allEntries.RemoveRange(0, excess);
}
```

If `MaxEntriesInMemory` is set to `0` (in appsettings), the trimming logic is bypassed entirely, allowing **unbounded growth**. The comment in the config says "0 = unlimited", which is dangerous in production.

### 2.6. GC Pressure and LOH Fragmentation

.NET's Large Object Heap (LOH) is used for objects > 85 KB. The `string[]` from `ReadAllLinesAsync` for a large file easily lands on the LOH, as do large `RawBlock` strings. LOH is only compacted during a full Gen 2 GC collection, which may not run frequently enough during sustained allocation bursts.

---

## 3. Memory Accumulation Timeline

```
Cycle N:
  ├── Read db2diag.log (Instance DB2):       ~1.5 GB allocated (string[])
  ├── Parse entries:                          ~50 MB (10,000 Db2DiagEntry objects)
  ├── GC may not have reclaimed cycle N-1 arrays yet
  ├── Read db2diag.log (Instance DB2FED):     ~1.5 GB allocated (string[])
  ├── Read db2diag.log (Instance DB2HST):     ~1.0 GB allocated (string[])
  ├── Copy _allEntries to snapshot:           ~50 MB (duplicate list)
  ├── Generate alerts with RawBlock:          ~20 MB
  └── Total peak: potentially 4–5 GB before GC catches up

If GC is slow or LOH is fragmented:
  Peak can exceed self-monitoring threshold before the 30s timer fires.
```

---

## 4. Why Self-Monitoring Did Not Prevent 12 GB

Several factors can explain why the 3 GB threshold was not enforced:

1. **Memory spike between checks:** The 30-second timer only checks periodically. A single `ReadAllLinesAsync` call on a 500 MB file takes seconds and allocates 1.5 GB instantly — no check runs during that allocation.

2. **ScalingService increases interval:** On low-capacity servers, `ScaleIntervalSeconds()` may increase the 30s interval to 60s or more, creating a larger blind window.

3. **Possible config override:** If `SelfMonitoring.Enabled` is set to `false` or `MemoryThresholdMB` is set higher in a server-specific appsettings, the safeguard is weakened or disabled.

4. **Timer callback exception:** If `CheckProcessMemory()` throws before reaching the comparison, the timer silently continues without triggering shutdown.

5. **WorkingSet vs Committed memory:** `WorkingSet64` may not reflect all committed memory if pages are in the standby list. The process can have 12 GB committed but a lower WorkingSet.

---

## 5. Recommended Fixes

### 5.1. Immediate — Reduce Memory Footprint

| Change | Impact | Effort |
|--------|--------|--------|
| Switch `ReadAllLinesAsync` to streaming line-by-line read | Eliminates 1.5 GB+ per-file allocation | Medium |
| Reduce `MaxEntriesInMemory` from 10,000 to 2,000 | Reduces entry storage by 80% | Config change |
| Stop copying `RawBlock` into alert metadata | Eliminates duplicate string storage in alerts | Small |
| Remove the `.ToList()` copy in `db2Data.AllEntries = _allEntries.ToList()` — use shared reference or summary | Eliminates second copy of 10,000 entries | Small |
| Truncate `RawBlock` to first 2,000 chars in `Db2DiagEntry` | Caps per-entry size | Small |
| Reduce `MaxLogFileSizeBytes` from 500 MB to 100 MB | Prevents processing oversized logs | Config change |

### 5.2. Defensive — Improve Self-Monitoring

| Change | Impact | Effort |
|--------|--------|--------|
| Check memory **before** each `ReadAllLinesAsync` call | Prevents allocation if already near threshold | Small |
| Use `GC.GetTotalMemory(false)` in addition to `WorkingSet64` | Catches managed heap growth that WorkingSet misses | Small |
| Add a hard ceiling using `MemoryFailPoint` before large reads | Throws `InsufficientMemoryException` proactively | Medium |
| Reduce check interval to 10 seconds (or make it configurable per phase) | Narrows the blind window | Config change |
| Force `GC.Collect()` after processing each log file | Reclaims LOH memory between files | Small |

### 5.3. Architectural — Long-Term

| Change | Impact | Effort |
|--------|--------|--------|
| Stream-process `db2diag.log` using `StreamReader.ReadLineAsync()` | Constant memory regardless of file size | Medium |
| Move diag entry storage to SQLite or file-backed store | Removes large in-memory collections entirely | Large |
| Implement memory budget per monitor (abort collection if budget exceeded) | Prevents any single monitor from causing OOM | Medium |
| Use `ArrayPool<string>` or `MemoryPool` for line buffers | Reduces GC pressure from repeated large allocations | Medium |

---

## 6. Configuration Reference

### Current appsettings.json values (relevant sections)

```json
"SelfMonitoring": {
    "Enabled": true,
    "MemoryThresholdMB": 3072,
    "ShutdownDelaySeconds": 10,
    "CheckIntervalSeconds": 30
}
```

```json
"Db2DiagMonitoring": {
    "MaxLogFileSizeBytes": 524288000,
    "MaxEntriesPerCycle": 50,
    "KeepAllEntriesInMemory": true,
    "MaxEntriesInMemory": 10000
}
```

```json
"MemoryManagement": {
    "CleanupAgeHours": 24,
    "MaxAlertsInMemory": 1000,
    "CleanupIntervalMinutes": 60
}
```

---

## 7. Key Source Files

| File | Relevance |
|------|-----------|
| `ServerMonitor.Core/Services/SurveillanceOrchestrator.cs` (lines 843–953) | Self-monitoring timer and memory check |
| `ServerMonitor.Core/Monitors/Db2DiagMonitor.cs` (line 657) | `ReadAllLinesAsync` — full file load |
| `ServerMonitor.Core/Monitors/Db2DiagMonitor.cs` (lines 318–329) | `.ToList()` copy of all entries |
| `ServerMonitor.Core/Monitors/Db2DiagMonitor.cs` (line 1354) | `RawBlock` copied into alert metadata |
| `ServerMonitor.Core/Models/Db2DiagModels.cs` (line 153) | `RawBlock` field definition |
| `ServerMonitor.Core/Services/GlobalSnapshotService.cs` (lines 342–349) | Inaccurate size estimation |
| `ServerMonitor.Core/Configuration/SurveillanceConfiguration.cs` (lines 663–696) | `SelfMonitoringSettings` |
| `ServerMonitor.Core/Configuration/Db2DiagMonitoringSettings.cs` (lines 176–205) | DB2 memory-related config |
| `ServerMonitor/SurveillanceWorker.cs` (lines 47–48, 219–223) | Shutdown callback wiring |
