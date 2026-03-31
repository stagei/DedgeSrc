# Why Is a 5.86 GB db2diag.log Loaded Into Memory?

**Date:** 2026-03-17
**Server:** Local workstation (30237-FK)
**File:** `C:\ProgramData\IBM\DB2\DB2COPY1\DB2\DIAG0000\db2diag.log`
**File size:** 5.86 GB (6,294,191,961 bytes)
**Created:** 2025-09-15 | **Modified:** 2026-03-17

## Short Answer

**It WAS loaded into memory** because the deployed agent version on `t-no1fkmper-db` was **old (pre-v1.0.134)** and did not contain the `MaxLogFileSizeBytes` check — even though the setting existed in the source code since January 25, 2026.

The `MaxLogFileSizeBytes` setting (300 MB limit) was added to both the config and code in the source repository in late January 2026, but the **compiled agent binary on the server was never updated**. The auto-update mechanism (`ReinstallTriggerService`) was also added late (Jan 27) and was not installed on the production database server.

Server logs from `t-no1fkmper-db` (February 11, 2026) prove the old version was running.

## Why MaxLogFileSizeBytes Didn't Protect the Server

### The Deployment Gap

The `MaxLogFileSizeBytes` check was implemented in three separate commits:

| Date | Commit | Version | What was added |
|------|--------|---------|----------------|
| Jan 19 | `de9e11a` | v1.0.96 | `MaxLogFileSizeBytes` property added to `Db2DiagMonitoringSettings` class (default: 300 MB) |
| Jan 23 | `ef9d6f2` | v1.0.132 | `"MaxLogFileSizeBytes": 314572800` added to `appsettings.json` |
| Jan 25 | `633e068` | v1.0.134 | Size check code added to `Db2DiagMonitor.cs` — files > limit are skipped before `ProcessLogFileWithStatsAsync` |
| Jan 27 | `649089e` | — | `ReinstallTriggerService` added to auto-update agents on headless servers |

**The incident occurred on February 11** — 17 days after the fix was committed. But the agent binary on `t-no1fkmper-db` was never updated.

### Proof: The Old Version Was Running

The Feb 11 log output is the conclusive proof:

```
Phase 4 - Process [DB2]: 2853209ms | Lines: 0 | Blocks: 0 | Entries: 0 | Skipped: 0
```

In v1.0.134+, the size check occurs **before** `ProcessLogFileWithStatsAsync` is called:

```csharp
if (settings.MaxLogFileSizeBytes > 0 && diagFile.Length > settings.MaxLogFileSizeBytes)
{
    _logger.LogWarning("SKIPPING large db2diag.log file: ...");
    continue; // Phase 4 log line is NEVER emitted
}

var (entries, stats) = await ProcessLogFileWithStatsAsync(...);
_logger.LogDebug("Phase 4 - Process [{Instance}]: ..."); // only reached if NOT skipped
```

If v1.0.134+ had been running, we would see `"SKIPPING large db2diag.log file"` in the log and the Phase 4 line would never appear. Instead, Phase 4 ran for **47.5 minutes**, proving the deployed version had no size check.

### Why the Server Wasn't Updated

`t-no1fkmper-db` is a **production database server** with no interactive user sessions. The auto-update mechanisms relied on either:

1. **ServerMonitorTrayIcon** — requires a logged-in user (not available on headless servers)
2. **ReinstallTriggerService** — a Windows service that watches the staging share for trigger files

The `ReinstallTriggerService` was only added on Jan 27 (`649089e`). Even after that commit, the service would need to be **manually installed on each server** the first time. On `t-no1fkmper-db`, this hadn't been done yet.

**Result:** The agent was stuck on an old version (somewhere between v1.0.80 and v1.0.133) that had `File.ReadAllLinesAsync()` with no file size protection.

## Evidence From Server Logs

### t-no1fkmper-db — February 11, 2026

The agent discovered two db2diag.log files:

| File | Size |
|------|------|
| `DB2COPY1\DB2FED\db2diag.log` | 5.3 MB |
| `DB2COPY1\DB2\DIAG0000\db2diag.log` | **6.29 GB** (6,283,789,766 bytes) |

The agent loaded the 6.29 GB file using `File.ReadAllLinesAsync()`:

```
2026-02-11 00:23:43|Phase 4 - Process [DB2]: 2853209ms | Lines: 0 | Blocks: 0 | Entries: 0 | Skipped: 0
2026-02-11 00:23:43|Phase 4 - Process [DB2]: 2914144ms | Lines: 0 | Blocks: 0 | Entries: 0 | Skipped: 0
```

**2,853,209 ms = 47.5 minutes** to read one file. It found 0 new entries (state pointer was already at end of file) — so it burned 14 GB of RAM for nothing.

During this time, the server's free memory dropped to critical levels:

```
Available memory critically low: 137 MB
Available memory critically low: 111 MB
Available memory critically low: 108 MB
```

The 16 GB server was left with ~100 MB free while the agent held ~14 GB.

### Why 6.29 GB on disk becomes ~14 GB in RAM

| Layer | Size | Explanation |
|-------|------|-------------|
| File on disk | 6.29 GB | Windows-1252 encoded (1 byte per char) |
| .NET string array | ~12.6 GB | .NET strings are UTF-16 (2 bytes per char) |
| String object headers | ~1.5 GB | 24-byte overhead per string object × millions of lines |
| Array + GC overhead | ~0.5 GB | Large Object Heap fragmentation |
| **Total in RAM** | **~14.6 GB** | |

`File.ReadAllLinesAsync()` reads the entire file, splits by newline, and returns a `string[]`. Each line becomes a separate .NET `string` object on the Large Object Heap, with 2x character expansion and per-object overhead.

## The Three Problems

### 1. Instance Name Extraction Bug (Fixed)

The `GetInstanceFromPath` method extracted the wrong DB2 instance name from the file path.

**Path structure:**

```
C:\ProgramData\IBM\DB2\DB2COPY1\DB2\DIAG0000\db2diag.log
                      ^^^^^^^^  ^^^  ^^^^^^^^
                      DB2 copy  Instance  Diag folder
                      (software) (actual)
```

| Component | Meaning |
|-----------|---------|
| `DB2COPY1` | DB2 software installation copy — NOT an instance |
| `DB2` | The actual DB2 instance name |
| `DIAG0000` | Diagnostic output directory |

**What went wrong:** The original code looked for the first `DB2` folder in the path and returned the *next* segment. This found `DB2` at index 3 (under `IBM`), then returned `DB2COPY1` — which is the software copy, not the instance.

**Result:** The file size was stored in `_diagLogFileSizes["DB2COPY1"]`, but `Db2InstanceMonitor` queried `GetDiagLogFileSizeBytes("DB2")`. Key mismatch → dashboard tile showed nothing.

**Fix:** Changed `GetInstanceFromPath` to use the `DIAG0000` folder as a landmark — the folder directly above `DIAG*` is always the instance name. This works for all known DB2 path structures:

```
..\DB2COPY1\DB2\DIAG0000\       → "DB2"
..\DB2COPY1\DB2FED\DIAG0000\    → "DB2FED"
..\DB2COPY1\DB2HFED\DIAG0000\   → "DB2HFED"
```

### 2. File Is Skipped But Dashboard Shows Nothing

Because of Bug #1, the file size was recorded under the wrong key. Even though the agent correctly:
- Recorded the file size (line 186)
- Skipped processing (line 221, file > 500 MB limit)
- Generated a warning alert about the skip

...the dashboard tile never showed the size because it looked up `db2DiagLogSizeMb` using the instance name from `Db2InstanceMonitor` (e.g., `"DB2"`), which didn't match the stored key (`"DB2COPY1"`).

### 3. Why Is the File 5.86 GB?

The `db2diag.log` file has been growing since **September 15, 2025** — over 6 months without rotation. This happens when:

| Cause | Explanation |
|-------|-------------|
| **No log rotation configured** | DB2's `DIAGSIZE` parameter is 0 (unlimited) or not set |
| **Local dev workstation** | Production servers typically have rotation configured; dev machines often don't |
| **High diagnostic verbosity** | `DIAGLEVEL` may be set to 3 or 4 (verbose), generating excessive output |

## Configuration That Protects Against This

The agent's `appsettings.json` has safeguards:

```json
{
  "Db2DiagMonitoring": {
    "MaxLogFileSizeBytes": 524288000,
    "MaxLogFileSizeBytesNotes": "500 MB limit. Files larger than this are skipped with a warning alert."
  }
}
```

**What happens when a file exceeds 500 MB:**

1. File size is recorded for the dashboard tile (works correctly now with the instance name fix)
2. A `Warning` alert is generated: *"DB2 diag log file skipped - too large (5,861 MB)"*
3. The file is **not opened, not read, not loaded into memory**
4. Processing continues to the next `db2diag.log` file (if any)

Additionally, the agent has inline memory guards:
- At 2 GB working set → forced `GC.Collect`
- At 3 GB working set → abort all file processing
- At 3 GB configured threshold → Critical alert + graceful shutdown
- At 6 GB (2x threshold) → immediate `Environment.Exit(99)`

## Memory Impact Summary

| Version | Scenario | Memory Used |
|---------|----------|-------------|
| **Pre-v1.0.134** | Any file | `File.ReadAllLinesAsync`, no size check — entire file loaded (~2.3x disk size) |
| **v1.0.134–v1.0.298** | File > limit | Skipped (size check added) |
| **v1.0.134–v1.0.298** | File < limit | `File.ReadAllLinesAsync` — entire file loaded |
| **v1.0.299+** | File < limit | Streaming `StreamReader`, ~2-10 MB peak (line-by-line) |
| **v1.0.299+** | File > limit | **0 bytes** — file is skipped entirely |
| **v1.0.302+** | File size recording | ~100 bytes (just the `long` value in a dictionary) + correct instance name |

## Lessons Learned

1. **A config setting is useless if the compiled binary doesn't check it.** The `MaxLogFileSizeBytes` was in `appsettings.json` on the staging share, but the DLL on the server was from before the check existed.
2. **Auto-update mechanisms must be bootstrapped manually.** The `ReinstallTriggerService` can keep agents current, but it must be installed on each server first. A chicken-and-egg problem.
3. **Headless servers need special attention.** Tray-icon-based auto-updates only work when a user is logged in. Production database servers need the `ReinstallTriggerService` or another push-based mechanism.
4. **Defense in depth matters.** The current version has four layers of protection: file size skip → streaming reads → inline memory guards → self-monitoring kill. Any single layer failing won't cause a catastrophic memory event.

## Recommendations

### For this workstation

```bash
# Check current DB2 DIAGSIZE setting
db2 get dbm cfg | findstr DIAGSIZE

# Set rotation to 500 MB (creates db2diag.0.log, db2diag.1.log, etc.)
db2 update dbm cfg using DIAGSIZE 500

# Reduce verbosity if set too high
db2 get dbm cfg | findstr DIAGLEVEL
db2 update dbm cfg using DIAGLEVEL 2
```

After setting `DIAGSIZE`, the current 5.86 GB file can be safely deleted (DB2 creates a new one automatically).

### For production servers

All production DB2 servers should have `DIAGSIZE` configured to prevent unbounded growth. The agent's `MaxLogFileSizeBytes` is a safety net, not a substitute for proper log rotation.
