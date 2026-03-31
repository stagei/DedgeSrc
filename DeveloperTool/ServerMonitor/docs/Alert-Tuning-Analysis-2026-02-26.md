# ServerMonitor Alert Tuning Analysis

**Date:** 2026-02-26  
**Analyst:** Auto-generated from live alert logs and agent configuration  
**Previous analysis:** `docs/Alert-Tuning-Analysis-2026-02-20.md`  
**Data sources:**
- `\\t-no1inltst-db\opt\data\ServerMonitor\` — 2-day alert logs (Feb 25–26)
- `\\p-no1fkmprd-db\opt\data\ServerMonitor\` — latest alert log (Feb 24, agent offline since)
- `\\p-no1inlprd-db\opt\data\ServerMonitor\` — 2-day alert logs (Feb 25–26)
- `C:\opt\src\DedgeSrc\DedgeSystemTools\Folders\Opt\data\ServerMonitor\` — 2-day alert logs (Feb 24–25)
- `\\p-no1fkmprd-app\opt\data\ServerMonitor\` — 2-day alert logs (Feb 25–26)
- `\\p-no1fkxprd-app\opt\data\ServerMonitor\` — quiet (last alert Feb 22)
- `\\t-no1inltst-app\opt\data\ServerMonitor\` — 2-day alert logs (Feb 24–25)
- `\\p-no1inlprd-app\opt\data\ServerMonitor\` — empty directory (agent not writing)
- `C:\opt\src\DedgeSrc\DedgeSystemTools\Folders\DedgeCommon\Software\Config\ServerMonitor\appsettings.ServerMonitorAgent.json`

---

## Server Fleet Overview

| Server | Role | Agent Status | Alert Log Size (today) | Alert Log Size (yesterday) |
|---|---|---|---|---|
| t-no1inltst-db | Test DB (INLTST) | ✅ Active | 109 KB | 269 KB |
| p-no1fkmprd-db | Prod DB (FKMPRD/XFKMPRD/FKMHST) | ⚠️ Last log Feb 24 | 0 KB | 0 KB |
| p-no1inlprd-db | Prod DB (INLPRD/XINLPRD) | ✅ Active | 103 KB | 269 KB |
| dedge-server | Test app server | ✅ Active | — | 7 KB |
| p-no1fkmprd-app | Prod app server | ✅ Active | 0.8 KB | 0.8 KB |
| p-no1fkxprd-app | Prod app server | ✅ Quiet | 0 KB | 0 KB |
| t-no1inltst-app | Test app server | ✅ Active | — | 0.7 KB |
| p-no1inlprd-app | Prod app server | ❌ No data | 0 KB | 0 KB |

---

## Volume Summary

| Server | Date | CRITICAL | WARNING | Informational | Total |
|---|---|---|---|---|---|
| t-no1inltst-db | Feb 26 (partial) | 334 | 150 | 0 | **484** |
| t-no1inltst-db | Feb 25 (full) | 887 | 313 | 0 | **1,200** |
| p-no1inlprd-db | Feb 26 (partial) | 302 | 62 | 102 | **466** |
| p-no1inlprd-db | Feb 25 (full) | 891 | 169 | 133 | **1,193** |
| p-no1fkmprd-db | Feb 24 (latest) | 0 | 81 | 0 | **81** |
| dedge-server | Feb 25 | 0 | 18 | 0 | **18** |
| dedge-server | Feb 24 | 0 | 10 | 0 | **10** |
| p-no1fkmprd-app | Feb 26 (partial) | 0 | 3 | 0 | **3** |
| p-no1fkmprd-app | Feb 25 | 0 | 3 | 0 | **3** |
| t-no1inltst-app | Feb 25 | 0 | 2 | 0 | **2** |
| **Fleet total** | | **2,414** | **811** | **235** | **3,460** |

---

## Finding 1 — CRITICAL: Triple-Alert Problem (Pattern Matching is Additive, Not Exclusive)

### What is happening

The SQLCA-AlreadyBuilt pattern (Priority 9) was added in the Feb 20 analysis to intercept `probe:480` events **before** CriticalZRC (Priority 10). However, **all three fire for the same event**:

| Alert | Type | Count (t-no1inltst-db Feb 25) |
|---|---|---|
| `DB2 CRITICAL: DB2 UDB, relation data serv, sqlrr_appl_init, probe:480` | CriticalZRC match | 446 |
| `[DB2] [INLTST] DB2 Error detected` | Generic fallback | 441 |
| `DB2 transient SQLCA conflict in [DB2] [INLTST] (auto-recovered)` | SQLCA-AlreadyBuilt remap | 313 |
| **Total for same events** | | **1,200** |

Adding the SQLCA-AlreadyBuilt pattern did not suppress the other two — it **added a third alert line** per event.

### Burst severity

| Server | Date | Worst single-second burst |
|---|---|---|
| p-no1inlprd-db | Feb 25 | **110 alerts at 05:37:21** |
| t-no1inltst-db | Feb 25 | **51 alerts at 05:37:40** |

### Root cause

Pattern matching in `Db2DiagMonitor` is **additive**: lower-priority patterns are not suppressed when a higher-priority pattern matches. This is a code-level issue, not a configuration issue.

### Recommendations

#### 1a. Code fix (priority): Make pattern matching exclusive

When a higher-priority pattern (e.g., SQLCA-AlreadyBuilt at Priority 9) matches, skip all lower-priority patterns (CriticalZRC at Priority 10) for that log entry.

#### 1b. Immediate config workaround: Change SQLCA-AlreadyBuilt to Skip

Until the code is fixed, change `Action: "Remap"` → `Action: "Skip"` on the SQLCA-AlreadyBuilt pattern. This won't fix the CriticalZRC match but will eliminate the third alert line.

#### 1c. Modify CriticalZRC regex to exclude 0x8012006D

Add a negative lookahead to the CriticalZRC regex:

```
Current:  "ZRC=0x8"
Proposed: "ZRC=0x8(?!012006D)"
```

This prevents the broad CriticalZRC from matching the known-benign SQLR_CA_BUILT code.

#### 1d. Fix generic "DB2 Error detected" fallback

The generic fallback should only fire for entries NOT matched by any specific pattern. This is likely a second code path that fires independently of pattern matching.

**Expected impact:** Reducing from ~1,200 → ~10 alerts/day on t-no1inltst-db (99% reduction).

---

## Finding 2 — p-no1fkmprd-db Agent Offline Since Feb 24

### What is happening

The agent on `p-no1fkmprd-db` last wrote to its log at 2026-02-24 02:50:12. No alert files exist for Feb 25 or 26. The last alert was a self-monitoring shutdown: `ServerMonitor.exe memory usage exceeded threshold (3085 MB > 3072 MB)`.

### Root cause

The agent consumed 3,085 MB of memory (above the 3,072 MB threshold), triggered a self-monitoring shutdown, and has not restarted since.

### Recommendations

| # | Action | Value |
|---|---|---|
| 2a | **Restart the agent** on p-no1fkmprd-db | Manual intervention required |
| 2b | Raise `SelfMonitoring.MemoryThresholdMB` | Current: 3072 → Proposed: **4096** |
| 2c | Investigate root cause | Memory leak likely from processing large db2diag files (~128 MB/day general log) |

---

## Finding 3 — ServerMonitorDashboard Crash Loop on dedge-server (RESOLVED)

### What happened

Between Feb 24 13:57 and Feb 25 13:31, the ServerMonitorDashboard service crashed ~65 times/hour (~1,500 total crashes). Event 1000 confirmed `ServerMonitorDashboard.exe v1.0.277.0` faulting in `KERNELBASE.dll`.

This generated **20 Event 7031 alerts** over the period (one per hour, each reporting 44–67 occurrences).

### Current status

The dashboard was redeployed at v1.0.278+ and is currently running healthy (health check passes). No Event 7031 alerts after Feb 25 13:31.

### Recommendation

No action needed on the crash itself. However, Event 7031 and 7034 currently have `MaxOccurrences: 0` (alert on every occurrence), generating unnecessary noise during known service restart cycles:

| Setting | Current | Proposed |
|---|---|---|
| Event 7031 MaxOccurrences | 0 | **3** |
| Event 7031 TimeWindowMinutes | 60 | 60 |
| Event 7034 MaxOccurrences | 0 | **3** |
| Event 7034 TimeWindowMinutes | 60 | 60 |

---

## Finding 4 — Event 201 Threshold Exceeded Again on p-no1fkmprd-app

### What is happening

Task `\Generate on-call dashboard` runs via `pwsh.exe` on p-no1fkmprd-app and fires **601 times/hour** (up from 548/hour in the Feb 20 analysis). The task returns code 0 (success). The current threshold of 600 is now being exceeded, generating 1 alert/day at exactly 06:00.

### Recommendation

| Setting | Current | Proposed |
|---|---|---|
| Event 201 MaxOccurrences | 600 | **700** |

Or better: investigate why this task runs ~10 times/minute. A task running successfully 601 times/hour should not alert.

---

## Finding 5 — VirtualMemory Paging Alerts Across Multiple Servers

### What is happening

Excessive paging alerts fire on 3 of 5 app servers, typically at overnight (23:xx) and morning (08:xx) windows:

| Server | Date | Pages/sec | Time |
|---|---|---|---|
| p-no1fkmprd-app | Feb 26 | 2548, 3927 | 23:13, 08:01 |
| p-no1fkmprd-app | Feb 25 | 2835, 3904 | 23:13, 08:01 |
| dedge-server | Feb 25 | 3981 | overnight |
| dedge-server | Feb 24 | 3736, 3195 | overnight |
| p-no1fkxprd-app | Feb 22 | 2151 | sporadic |

Current threshold: 2000 pages/sec. Most readings are 2000–4000, which is borderline for servers running backups and batch jobs.

### Recommendation

| Setting | Current | Proposed |
|---|---|---|
| ExcessivePagingRate | 2000 | **4000** |

This retains alerting for genuine spikes (e.g., the 10,462 pages/sec spike seen on Feb 20) while eliminating routine batch-window noise.

---

## Finding 6 — AutoAssessPatchesService / RdAgent Terminations (Azure Noise)

### What is happening

Azure guest agents (`AutoAssessPatchesService`, `RdAgent`) regularly terminate and restart on test servers (dedge-server, t-no1inltst-app). This fires Event 7034 alerts daily at ~22:00.

### Recommendation

Add `AutoAssessPatchesService` and `RdAgent` to the Event 7034 suppression list, or increase MaxOccurrences as recommended in Finding 3.

---

## Finding 7 — p-no1inlprd-app Has No Agent Data

The directory `\\p-no1inlprd-app\opt\data\ServerMonitor\` exists but contains zero files. The agent is either not installed, not running, or writing to a different location.

### Recommendation

Verify the ServerMonitor agent is installed and running on p-no1inlprd-app.

---

## Comparison with Feb 20 Analysis

### Changes That Worked

| Change | Feb 20 Impact | Current Impact | Status |
|---|---|---|---|
| DRDAProbe10 → Skip | ~490 alerts/day on p-no1fkmprd-db | **0** | ✅ RESOLVED |
| DRDAProbe20 MaxOcc 5→20, Window 30→60 | ~485/day | 72/day (Feb 24) | ✅ 85% reduction |
| SQLD-UserInterrupt Remap | Was CRITICAL | Now WARNING (10-26/day) | ✅ Downgraded |
| QPLEX-UserError MaxOcc 6→20 | Many per-user | 3 (Feb 24) | ✅ Grouped |
| Event 201 MaxOcc 100→600 | 24 alerts/day | 1 alert/day | ✅ 96% reduction |
| MaxLogFileSizeBytes 300→500 MB | Log scan skipped | No more skip alerts | ✅ RESOLVED |

### Changes That Didn't Work as Expected

| Change | Expected | Actual | Root Cause |
|---|---|---|---|
| SQLCA-AlreadyBuilt Remap (Priority 9) | Intercept before CriticalZRC, ~600 CRITICAL → 2 WARNING | **Added 313 WARNINGs on top of existing CRITICALs** | Pattern matching is additive, not exclusive |
| CriticalZRC MaxOcc 0→3 | Burst cap | Partially working but base events still fire | Triple-alert negates throttling |

### New Issues Since Feb 20

| Issue | Server | Impact |
|---|---|---|
| Agent memory leak → offline | p-no1fkmprd-db | Production DB server unmonitored since Feb 24 |
| Dashboard crash loop → Event 7031 flood | dedge-server | 20 extra alerts over 14 hours (resolved) |
| Event 201 count increased 548→601 | p-no1fkmprd-app | Now exceeds threshold again |

---

## Recommended Config Changes

| # | Setting | Current | Proposed | Expected Impact |
|---|---|---|---|---|
| 1 | SQLCA-AlreadyBuilt Action | Remap | **Skip** | Eliminates 313 WARNING/day on t-no1inltst-db, 143/day on p-no1inlprd-db |
| 2 | CriticalZRC Regex | `ZRC=0x8` | `ZRC=0x8(?!012006D)` | Prevents CriticalZRC from matching benign SQLR_CA_BUILT |
| 3 | Event 7031 MaxOccurrences | 0 | **3** | Limits service crash alerts during restart cycles |
| 4 | Event 7034 MaxOccurrences | 0 | **3** | Limits service termination alerts |
| 5 | Event 201 MaxOccurrences | 600 | **700** | Prevents threshold breach from 601/hour task |
| 6 | ExcessivePagingRate | 2000 | **4000** | Eliminates routine batch-window paging alerts |
| 7 | SelfMonitoring.MemoryThresholdMB | 3072 | **4096** | Prevents premature agent shutdown on busy servers |

### Code-Level Fixes Needed

| # | Issue | Impact |
|---|---|---|
| C1 | Pattern matching should be **exclusive** (highest-priority match stops further matching) | Would eliminate triple-alert, reducing ~2,400 CRITICAL/day to ~10 |
| C2 | Generic "DB2 Error detected" should only fire for unmatched entries | Would eliminate 441/day on t-no1inltst-db, 420/day on p-no1inlprd-db |

---

## Signal-to-Noise Ratio

| Server | Daily Alert Rate | Est. Actionable | Ratio |
|---|---|---|---|
| t-no1inltst-db | ~1,200 | ~2 (Db2Instance) | **0.2%** |
| p-no1inlprd-db | ~1,193 | ~30 (SQLD_INTRP, ADM4500W, XINLPRD) | **2.5%** |
| p-no1fkmprd-db | ~81 | ~9 (QPLEX, paging, sessions) | **11%** |
| dedge-server | ~14 | ~5 (paging, OpenSSH) | **36%** |
| p-no1fkmprd-app | ~3 | ~1 (paging spikes only) | **33%** |
| **Fleet total** | **~2,491/day** | **~47** | **1.9%** |

Fixing the triple-alert issue (code changes C1 + C2) would improve the fleet signal-to-noise ratio from 1.9% to an estimated **25-30%**.

---

## Remaining Investigation Items

| Item | Server | Description |
|---|---|---|
| Agent restart | p-no1fkmprd-db | Agent offline since Feb 24 — needs manual restart |
| Agent installation | p-no1inlprd-app | No alert data — verify agent is installed |
| Triple-alert code fix | All DB servers | Pattern matching exclusivity in Db2DiagMonitor |
| Generic DB2 Error fallback | All DB servers | Suppress for entries already matched by patterns |
| Task 201 baseline | p-no1fkmprd-app | `\Generate on-call dashboard` runs 601x/hour — investigate |
| Memory leak | p-no1fkmprd-db | Agent consumed 3,085 MB — investigate allocation patterns |

---

*Analysis covers data from 2026-02-24 to 2026-02-26. Compared against previous analysis from 2026-02-20.*  
*Config source of truth: `C:\opt\src\DedgeSrc\DedgeSystemTools\Folders\DedgeCommon\Software\Config\ServerMonitor\appsettings.ServerMonitorAgent.json`*
