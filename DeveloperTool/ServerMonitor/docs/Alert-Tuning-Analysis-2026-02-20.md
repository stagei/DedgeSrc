# ServerMonitor Alert Tuning Analysis

**Date:** 2026-02-20 (updated with multi-server analysis)  
**Analyst:** Auto-generated from live alert logs and agent configuration  
**Data sources:**
- `\\t-no1inltst-db\opt\data\ServerMonitor\` — 3-day alert logs
- `\\p-no1fkmprd-db\opt\data\ServerMonitor\` — 2-day alert logs (112 KB today, 239 KB yesterday)
- `\\p-no1inlprd-db\opt\data\ServerMonitor\` — 2-day alert logs (162 KB today, 304 KB yesterday)
- `C:\opt\src\DedgeSrc\DedgeSystemTools\Folders\Opt\data\ServerMonitor\` — 2-day alert logs
- `\\p-no1fkmprd-app\opt\data\ServerMonitor\` — 2-day alert logs
- `C:\opt\src\DedgeSrc\DedgeSystemTools\Folders\DedgeCommon\Software\Config\ServerMonitor\appsettings.ServerMonitorAgent.json`

---

## Server Fleet Overview

| Server | Role | Agent accessible | Alert log size (today) |
|---|---|---|---|
| t-no1inltst-db | Test DB (INLTST) | ✅ | 165 KB |
| p-no1fkmprd-db | Prod DB (FKMPRD/XFKMPRD/FKMHST) | ✅ | 112 KB |
| p-no1inlprd-db | Prod DB (INLPRD/XINLPRD) | ✅ | 162 KB |
| dedge-server | Test app server | ✅ | 7 KB |
| p-no1fkmprd-app | Prod app server | ✅ | 6 KB |
| p-no1fkxprd-app | Prod app server | ✅ | ~0 KB (no recent alerts) |
| t-no1inltst-app | Test app server | ✅ | ~0 KB |
| p-no1inlprd-app | Prod app server | ✅ | last log from Jan 2026 |

## Volume Summary

| Server | Day | CRITICAL | WARNING | Other | Total |
|---|---|---|---|---|---|
| t-no1inltst-db | 2026-02-18 | 1483 | 0 | 1 | **1484** |
| t-no1inltst-db | 2026-02-19 | 1300 | 0 | 0 | **1300** |
| t-no1inltst-db | 2026-02-20 (partial) | 650 | 0 | 0 | **650** |
| p-no1fkmprd-db | 2026-02-19 | 0 | 1121 | 0 | **1121** |
| p-no1fkmprd-db | 2026-02-20 (partial) | 0 | 525 | 0 | **525** |
| p-no1inlprd-db | 2026-02-20 (partial) | 557 | 0 | 85 | **642** |
| dedge-server | 2026-02-20 (partial) | 0 | 37 | 0 | **37** |
| p-no1fkmprd-app | 2026-02-20 (partial) | 0 | 28 | 0 | **28** |

> ⚠️ These are **file-channel** alert counts. The file channel logs every alert regardless of throttling. SMS and Email are throttled separately.

---

## Finding 1 — Massive DB2 CriticalZRC flooding on t-no1inltst-db (HIGHEST PRIORITY)

### What is happening

Every day at approximately **05:34** and **06:36** (likely nightly batch jobs), DB2 instance `INLTST` generates a high-volume burst of the same two error conditions:

| Error | Function | ZRC Code | Meaning |
|---|---|---|---|
| `sqlrr_appl_init, probe:480` | Relation data service | `ZRC=0x8012006D` | SQLR_CA_BUILT — "SQLCA has already been built" |
| `sqeApplication::AppStartUsing, probe:143` | Base system utilities | `ZRC=0x8012006D` | Same — duplicate SQLCA initialization |

**Volume per 3-hour window:**

| Date | 05:xx hour | 06:xx hour |
|---|---|---|
| 2026-02-20 | 101 alerts | 168 alerts |
| 2026-02-19 | 114 alerts | 52 alerts |

Each db2diag log entry triggers **two alerts**:
1. `[CRITICAL] CriticalZRC pattern` — matched by the `CriticalZRC` regex (`ZRC=0x8`)
2. `[CRITICAL] DB2 Error detected` — fired separately as an unmatched/generic fallback

This doubles the alert count artificially. **Two-thirds of all daily alerts on this server are CriticalZRC; one-third are the duplicate generic entries.**

### Root cause analysis

- `ZRC=0x8012006D` = `SQLR_CA_BUILT` is a transient DB2 internal error that occurs when a **connection is being reused or restarted** and the internal SQLCA structure is already initialized.
- This is a well-known benign condition in DB2 environments running federated or batch workloads. It is typically auto-recovered by DB2 without application impact.
- The `CriticalZRC` pattern in config uses `Regex: "ZRC=0x8"` — which matches **all** negative ZRC codes indiscriminately, including benign ones like `0x8012006D`.
- `MaxOccurrences: 0` means every single occurrence fires an alert with no batch threshold.
- `MaxEntriesPerCycle: 200` allows 200 db2diag entries per polling cycle (every 600s), meaning a batch burst generates up to 200 alerts in one cycle.

### Recommendations

#### 1a. Add a specific Skip or Remap pattern for `SQLR_CA_BUILT` (Priority: **immediate**)

Add this pattern **before** `CriticalZRC` in the `PatternsToMonitor` array with a lower `Priority` number (higher precedence):

```json
{
  "PatternId": "SQLCA-AlreadyBuilt",
  "Description": "SQLCA already initialized (ZRC=0x8012006D) - transient, auto-recovered by DB2",
  "Regex": "ZRC=0x8012006D.*SQLR_CA_BUILT|SQLR_CA_BUILT.*ZRC=0x8012006D",
  "Enabled": true,
  "Action": "Remap",
  "Level": "Warning",
  "MessageTemplate": "DB2 transient SQLCA conflict in {Instance} (auto-recovered)",
  "Priority": 9,
  "MaxOccurrences": 10,
  "TimeWindowMinutes": 60,
  "SuppressedChannels": ["SMS"]
}
```

**Effect:** Reduces from hundreds of CRITICAL per burst → maximum 1 WARNING alert per hour, SMS suppressed.

Alternatively, if confirmed truly benign: use `Action: "Skip"` to eliminate alerting entirely.

#### 1b. Tighten the general `CriticalZRC` pattern threshold

Current: `MaxOccurrences: 0` (every occurrence).  
Proposed: `MaxOccurrences: 3, TimeWindowMinutes: 60`

This ensures true unexpected critical failures still alert quickly, but a burst of the same code does not generate hundreds of alerts.

#### 1c. Reduce `MaxEntriesPerCycle` for test environment

Current: `MaxEntriesPerCycle: 200`  
Proposed: `MaxEntriesPerCycle: 50` (test) / `100` (production)

This limits the per-cycle blast radius. Combined with `DuplicateSuppressionMinutes: 15`, a single burst generates at most one alert.

#### 1d. Fix the double-alert (generic "DB2 Error detected")

The generic `[DB2] [INLTST] DB2 Error detected` alert fires for entries that match the `CriticalZRC` pattern AND for unmatched entries. This suggests a code path that fires the generic alert before pattern matching completes, or the `MaxEntriesPerCycle` cap causes some entries to be processed unmatched.

**Investigate:** Does `Db2DiagMonitoring` fire a generic alert for all entries at `Db2MinimumLogLevel: Error` regardless of pattern match outcome? If so, the minimum log level should be paired with patterns that capture everything — or the generic path should only fire for truly unmatched entries.

---

## Finding 2 — p-no1fkmprd-db: Database/XFKMPRD WARNING volume

### What is happening

Today's 518 WARNING alerts break down as:

| Category | Count | Source |
|---|---|---|
| Database/XFKMPRD | 458 (88%) | Db2DiagMonitor — database XFKMPRD |
| Database/FKMPRD | 34 (7%) | Db2DiagMonitor — database FKMPRD |
| Db2Instance | 21 (4%) | Long-running queries or blocking sessions |
| VirtualMemory | 3 (0.6%) | Page file pressure |
| Database/DB2 | 2 (0.4%) | DB2 instance-level |

The XFKMPRD database is the dominant source. This is likely DRDA federated queries or application-level SQL errors being promoted to WARNING. Cross-reference with `SqlErrorLogPath` output to confirm which SQL codes are firing.

### Recommendations

#### 2a. Identify top SQL error codes hitting XFKMPRD

Check the SQL error log file at:
```
C:\opt\src\DedgeSrc\DedgeSystemTools\Folders\Commonlogging\Server\ServerMonitor\p-no1fkmprd-db_*_XFKMPRD_sqlerrors.log
```

If most are `SQL0911N` (deadlock), `SQL0952N` (timeout), or `SQL0530N` (FK constraint) — these already have `LogOnly` patterns. Confirm the XFKMPRD entries are being captured by those patterns and not falling through to an unmatched alert.

#### 2b. Review DRDA `DRDAProbe10` threshold

Current: `MaxOccurrences: 1000, TimeWindowMinutes: 1440` — allows up to 1000 DRDA probe:10 events per day before alerting. If XFKMPRD is a federated database, this may still be generating many events. Consider if probe:10 should be `Action: "Skip"` entirely for XFKMPRD.

#### 2c. Db2Instance alerts — session/query thresholds

21 Db2Instance alerts today. Current thresholds:
- `LongRunningQueryWarningSeconds: 300` (5 min) — may fire too frequently for ETL/batch workloads
- `SessionCountWarningThreshold: 50` — verify if production routinely has >50 sessions

Proposed adjustments for production:
```json
"LongRunningQueryWarningSeconds": 600,
"LongRunningQueryCriticalSeconds": 3600,
"SessionCountWarningThreshold": 80,
"DiagErrorsTodayWarningThreshold": 25
```

---

## Finding 3 — VirtualMemory warnings on p-no1fkmprd-db

3 VirtualMemory alerts today on the production DB server. Current threshold: `WarningPercent: 70`.

### Recommendation

For DB servers with large buffer pools, page file usage above 70% may be normal during peak hours. Consider:
- Raise `WarningPercent` to **80%** on DB servers
- Raise `CriticalPercent` to **92%** (from 90%)
- Keep `SustainedDurationSeconds: 3600` (1 hour) to avoid false alarms from short spikes

---

## Finding 4 — Event Log monitors that may generate excessive noise

Based on the configuration, these event monitors warrant review:

### 4a. Event 1074 / 1076 — System shutdown/restart events

```json
"EventId": 1074, "MaxOccurrences": 1, "TimeWindowMinutes": 1
"EventId": 1076, "MaxOccurrences": 1, "TimeWindowMinutes": 1
```

These are informational events fired during every planned shutdown. Currently at `Level: "Information"` which is correct, but `SuppressedChannels: []` means they would still go to SMS if SMS `MinSeverity` were lowered.

**Recommendation:** Pre-emptively add `"SuppressedChannels": ["SMS", "Email"]` to ensure they never accidentally go through notification channels.

### 4b. Event 10010 — DCOM registration failure

```json
"MaxOccurrences": 10, "TimeWindowMinutes": 60
```

DCOM 10010 is extremely common on Windows Server and is almost always benign (many COM servers register late). Consider raising to `MaxOccurrences: 50` or disabling (`"Enabled": false`) unless you are specifically tracking DCOM issues.

### 4c. Event 5858 — WMI operation failure

```json
"MaxOccurrences": 300, "TimeWindowMinutes": 120, "SuppressedChannels": ["WkMonitor"]
```

The threshold of 300 occurrences per 2 hours is very permissive. WMI errors are common on busy servers. Unless there is a specific WMI dependency, consider disabling or raising further to `MaxOccurrences: 500` or `Action: "Skip"`.

### 4d. Task Scheduler events 201 / 411

```json
"EventId": 201, "MaxOccurrences": 100, "TimeWindowMinutes": 60
"EventId": 411, "MaxOccurrences": 0, "TimeWindowMinutes": 60
```

Event 201 allows 100 task failures per hour before alerting — which is very high. If the `ScheduledTaskMonitoring` filter (`FilterByUser: "{CurrentUser}"`) is already limiting task scope, this should not be a noise source, but confirm the filter is working correctly.

---

## Finding 5 — Processor monitoring threshold is effectively disabled

```json
"WarningPercent": 99,
"CriticalPercent": 100,
"SustainedDurationSeconds": 86400
```

CPU must be at 99%+ for **24 consecutive hours** before triggering a WARNING. This will never fire in practice.

### Recommendation

For DB servers, a more realistic threshold:

```json
"WarningPercent": 85,
"CriticalPercent": 95,
"SustainedDurationSeconds": 600
```

For the general fleet, 10 minutes sustained at 85% is a reasonable early warning.

---

## Summary of Recommended Config Changes

| # | Setting | Current | Proposed | Expected Impact |
|---|---|---|---|---|
| 1 | New `SQLCA-AlreadyBuilt` pattern (Priority 9) | Missing | Remap→Warning, MaxOcc=10/60min, SMS suppressed | ~600 CRITICAL/day → max 2/day on t-no1inltst-db |
| 2 | `CriticalZRC.MaxOccurrences` | `0` | `3` | First true critical fires fast; burst capped |
| 3 | `MaxEntriesPerCycle` | `200` | `50` | Limits per-cycle blast radius |
| 4 | `DuplicateSuppressionMinutes` | `15` | `30` | Reduces duplicate CRITICAL alerts in burst |
| 5 | `LongRunningQueryWarningSeconds` | `300` | `600` | Fewer alerts for normal batch queries |
| 6 | `SessionCountWarningThreshold` | `50` | `80` | Appropriate for production DB2 |
| 7 | `VirtualMemory.WarningPercent` | `70` | `80` | Reduces noise on large DB servers |
| 8 | Event 10010 `MaxOccurrences` | `10` | `50` | DCOM noise reduction |
| 9 | Event 1074/1076 `SuppressedChannels` | `[]` | `["SMS","Email"]` | Prevents accidental SMS on shutdowns |
| 10 | `ProcessorMonitoring.WarningPercent` | `99` | `85` | Re-enables meaningful CPU alerting |
| 11 | `ProcessorMonitoring.SustainedDurationSeconds` | `86400` | `600` | Re-enables meaningful CPU alerting |

---

## Actionable Next Steps

1. **Investigate `ZRC=0x8012006D` on t-no1inltst-db** — confirm with DB2 team whether this is expected behavior from a batch job at 05:34/06:36. If confirmed benign, use `Action: "Skip"` instead of Remap.

2. **Check XFKMPRD SQL error logs** — review `C:\opt\src\DedgeSrc\DedgeSystemTools\Folders\Commonlogging\Server\ServerMonitor\p-no1fkmprd-db_*_XFKMPRD_sqlerrors.log` to identify which SQL codes dominate the 458 DATABASE/XFKMPRD warnings.

3. **Apply config changes to the network share** at:  
   `C:\opt\src\DedgeSrc\DedgeSystemTools\Folders\DedgeCommon\Software\Config\ServerMonitor\appsettings.ServerMonitorAgent.json`  
   The agent reloads config every 15 minutes (`ConfigReloadIntervalMinutes: 15`) — no restart needed.

4. **Monitor for 48 hours** after changes to confirm volume is reduced without masking genuine issues.

---

## Multi-Server Analysis — Round 2 Findings

### Finding 6 — DRDA probe:10 is a constant baseline (p-no1fkmprd-db: 490 alerts/day)

**p-no1fkmprd-db** generates two dominant alert streams from database `XFKMPRD` (federated):

| Pattern | Yesterday | Today (partial) | Message |
|---|---|---|---|
| DRDAProbe10 | 490 | 232 | "DRDA federated SQL in XFKMPRD" |
| DRDAProbe20 | 485 | 232 | "DRDA Error in XFKMPRD: federated query issue" |

**Analysis:** DRDAProbe10 fires on `probe:10` events from the DRDA wrapper — these represent normal federated SQL execution overhead. The config description even states *"high volume expected"*. With ~490 alerts/day at identical intervals, this is clearly a constant operational baseline, not an exceptional condition.

**DRDAProbe20** at probe:20 is slightly more serious (actual federated errors, not just execution overhead) but still very high volume for what appear to be routine federated query issues on XFKMPRD.

**Actions applied:**
- `DRDAProbe10`: Changed `Action: "Remap"` → `Action: "Skip"` — eliminates ~490 daily alerts per DB server
- `DRDAProbe20`: `MaxOccurrences` 5 → 20, `TimeWindowMinutes` 30 → 60 — groups errors into fewer, more meaningful alerts

---

### Finding 7 — QPLEX user mapping errors fragmented per-user (p-no1fkmprd-db)

Each individual user account that fails QPLEX authentication generates a **separate alert**. Yesterday: 30+ individual user alerts (FKGEISTA, BUTBAR04, JOHLIN, MMA, VRKKLO01, etc.), each counted separately. This drowns useful signal in repetitive per-user noise.

**Root cause:** `QPLEX-UserError.MaxOccurrences: 6/60min` — fires after 6 *total* errors, but since each user gets a unique alert key, each user triggers independently at count=1.

**Action applied:** `MaxOccurrences: 6 → 20` — delays firing until 20 unique user mapping errors have accumulated, naturally grouping them into fewer reports.

> **Investigation suggested:** Determine why so many users have QPLEX mapping issues. Could indicate a configuration problem in the Query Gateway user table.

---

### Finding 8 — Event 201 fires hourly on all app servers (constant baseline)

Task Scheduler event 201 ("task completed with errors") fires at a **constant, predictable rate** on both app servers:

| Server | Events per hour | Alert fires? |
|---|---|---|
| dedge-server | ~135/hour (every hour, 24/7) | Yes, every hour (threshold was 100) |
| p-no1fkmprd-app | ~548/hour (every hour, 24/7) | Yes, every hour (threshold was 100) |

The count is essentially **flat** — p-no1fkmprd-app consistently generates 539–593 event 201s per hour around the clock. This is a structural baseline, not an exception. The EventLogWatcher fires once per 60-minute window when threshold is crossed, meaning **24 alerts/day per server purely from task scheduler churn**.

**Action applied:**
- `MaxOccurrences: 100 → 600` — eliminates routine hourly alerting on p-no1fkmprd-app (~548/h stays below 600)
- `SuppressedChannels: [] → ["SMS"]` — if threshold is crossed, it goes to file/dashboard only, not SMS

> **Investigation suggested:** Identify which scheduled tasks on p-no1fkmprd-app generate ~548 completion-with-errors events per hour. This may be a misconfigured task, a task that exits with non-zero code (harmlessly), or a legitimate but unknown failure baseline.

---

### Finding 9 — SQLD_INTRP bursts on p-no1inlprd-db (production, daily at 05:31)

17 CRITICAL alerts matching `SQLD_INTRP "USER INTERRUPT DETECTED"` on p-no1inlprd-db, all from `sqlrlCatalogScan::deleteRows, probe:50` at exactly **05:31** (same time window as SQLR_CA_BUILT on the test server). This is a batch job interrupting catalog scan operations.

`SQLD_INTRP` (ZRC=`0x80040003`) means a DB2 session received an interrupt signal — typically triggered when a long-running query or catalog operation is killed by a timeout, admin, or application. In small numbers during batch hours this is acceptable. In a burst of 17 within seconds at the same time daily, it indicates a batch process is being forcibly interrupted.

**This WAS being classified as CRITICAL** (matched by broad `CriticalZRC` regex `ZRC=0x8`). With our Round 1 change to `CriticalZRC.MaxOccurrences: 3`, burst impact was reduced. A dedicated pattern provides better signal:

**Action applied:** Added `SQLD-UserInterrupt` pattern (Priority 8, before SQLCA-AlreadyBuilt):
```json
{ "PatternId": "SQLD-UserInterrupt", "Regex": "SQLD_INTRP",
  "Action": "Remap", "Level": "Warning", 
  "MaxOccurrences": 5, "TimeWindowMinutes": 60, "SuppressedChannels": ["SMS"] }
```

> **Investigation suggested:** Identify the 05:31 batch job on p-no1inlprd-db that triggers catalog scan interrupts. If it runs cleanly with no user impact, consider changing to Skip.

---

### Finding 10 — "No saved session env to restore" (p-no1inlprd-db, secondary to SQLD_INTRP)

16 CRITICAL alerts with message `"No saved session env to restore"` appearing at exactly **05:31:18** — the same second as the SQLD_INTRP burst above. This is a **side-effect**: when sessions are interrupted, DB2 agents try to restore the session environment and find none saved. It adds noise without independent signal.

**Action applied:** Added `NoSavedSessionEnv` pattern (Priority 91, Skip) — eliminates ~16 daily CRITICAL entries that carry no actionable information.

---

### Finding 11 — DB2 diag log too large to scan (p-no1fkmprd-db)

One alert today: `"DB2 diag log file skipped - too large (366.2 MB)"`. The diag log on p-no1fkmprd-db exceeds the configured `MaxLogFileSizeBytes: 300 MB` limit, causing the **entire Db2DiagMonitor scan to be skipped** for that cycle. This means all DB2 error pattern matching is bypassed when the log grows large.

**Action applied:** `MaxLogFileSizeBytes: 314572800 (300 MB) → 524288000 (500 MB)`

> **Investigation suggested:** DB2 diag logs should be rotated. A 366 MB single file suggests DB2 archiving/rotation may be misconfigured on p-no1fkmprd-db. Run `db2diag -A` or configure `DIAGSIZE` in DB2 instance parameters.

---

### Finding 12 — VirtualMemory paging rates: threshold calibration

Actual paging rates seen on p-no1fkmprd-db:

| Timestamp | Pages/sec | Would alert at 1000? | Would alert at 2000? |
|---|---|---|---|
| 05:48 | 1919 | Yes | No (benign range) |
| 06:58 | 2068 | Yes | Yes (borderline) |
| 07:59 | 1567 | Yes | No (benign range) |
| 10:04 | 10462 | Yes | Yes (genuine spike) |
| 12:28 | 2319 | Yes | Yes (slightly elevated) |

The 10462 pages/sec spike is clearly genuine. Most others (1500–2000) are routine DB2 buffer activity on a busy production server.

**Action applied:** `ExcessivePagingRate: 1000 → 2000 pages/sec` — retains alerting for true spikes while eliminating routine buffer activity noise.

---

## Complete Config Change Log (Both Rounds)

| # | Setting | Round | Before | After | Expected Impact |
|---|---|---|---|---|---|
| 1 | New `SQLD-UserInterrupt` pattern (Priority 8) | R2 | Missing | Remap→Warning, MaxOcc=5/60min, SMS suppressed | ~17 CRITICAL/day → max 1 Warning |
| 2 | New `SQLCA-AlreadyBuilt` pattern (Priority 9) | R1 | Missing | Remap→Warning, MaxOcc=10/60min, SMS suppressed | ~600 CRITICAL/day → max 2/day on t-no1inltst-db |
| 3 | `CriticalZRC.MaxOccurrences` | R1 | 0 | 3 | Burst cap for remaining ZRC codes |
| 4 | `DRDAProbe10.Action` | R2 | Remap | Skip | ~490 alerts/day eliminated on p-no1fkmprd-db |
| 5 | `DRDAProbe20.MaxOccurrences` / `TimeWindowMinutes` | R2 | 5/30 | 20/60 | Groups federated errors into fewer alerts |
| 6 | `QPLEX-UserError.MaxOccurrences` | R2 | 6 | 20 | Groups per-user mapping errors |
| 7 | New `NoSavedSessionEnv` pattern (Priority 91, Skip) | R2 | Missing | Skip | ~16 CRITICAL/day eliminated |
| 8 | `MaxEntriesPerCycle` | R1 | 200 | 50 | Limits per-cycle blast radius |
| 9 | `DuplicateSuppressionMinutes` | R1 | 15 | 30 | Doubles cooldown between duplicate alerts |
| 10 | `MaxLogFileSizeBytes` | R2 | 300 MB | 500 MB | Prevents log scan skip on large diag files |
| 11 | `LongRunningQueryWarningSeconds` | R1 | 300 | 600 | Reduces false positives for batch/ETL |
| 12 | `SessionCountWarningThreshold` | R1 | 50 | 80 | Appropriate for production DB2 |
| 13 | `DiagErrorsTodayWarningThreshold` | R1 | 10 | 25 | Avoids daily noise on busy DB servers |
| 14 | `VirtualMemory.WarningPercent` | R1 | 70% | 80% | Appropriate for large DB buffer pools |
| 15 | `VirtualMemory.ExcessivePagingRate` | R2 | 1000 | 2000 pages/sec | Retains spike detection, drops routine IO |
| 16 | Event 201 `MaxOccurrences` | R2 | 100 | 600 | Stops hourly alerting on app servers |
| 17 | Event 201 `SuppressedChannels` | R2 | [] | ["SMS"] | Task scheduler churn stays in dashboard only |
| 18 | Event 1074/1076 `SuppressedChannels` | R1 | [] | ["SMS","Email"] | Shutdown events never sent via notification |
| 19 | Event 10010 DCOM `MaxOccurrences` | R1 | 10 | 50 | Reduces DCOM registration noise |
| 20 | `ProcessorMonitoring.WarningPercent` | R1 | 99% | 85% | Re-enables meaningful CPU alerting |
| 21 | `ProcessorMonitoring.SustainedDurationSeconds` | R1 | 86400 | 600 | Re-enables meaningful CPU alerting |

---

## Final Pattern Priority Table (after both rounds)

| Priority | PatternId | Action | MaxOcc / Window | SMS |
|---|---|---|---|---|
| 8 | SQLD-UserInterrupt | Remap → Warning | 5 / 60 min | Suppressed |
| 9 | SQLCA-AlreadyBuilt | Remap → Warning | 10 / 60 min | Suppressed |
| 10 | CriticalZRC | Escalate → Critical | 3 / 60 min | Active |
| 30 | QPLEX-UserError | Remap → Warning | 20 / 60 min | Active |
| 40 | DRDAProbe20 | Remap → Warning | 20 / 60 min | Active |
| 41 | DRDAProbe10 | **Skip** | — | — |
| 50 | SQL0530N / SQL0911N / SQL0952N | LogOnly | — | — |
| 90 | ClientTermination / ConnectionTest / AgentBreathingPoint | Skip | — | — |
| 91 | NoSavedSessionEnv | **Skip** | — | — |
| 100 | STMM-AutoTuning / PackageCacheResize / ConfigParamUpdate / NewDiagLogFile | Skip | — | — |

---

## Remaining Investigation Items

| Item | Server | Description | Suggested action |
|---|---|---|---|
| Task 201 baseline | p-no1fkmprd-app | 548 task scheduler errors/hour, every hour. What tasks? | Review Windows Task Scheduler event log for task names |
| SQLD_INTRP batch | p-no1inlprd-db | Daily 05:31 interrupt of catalog scan. What batch? | Identify via DB2 audit log or job scheduler |
| XFKMPRD DRDA volume | p-no1fkmprd-db | Skipped 490 DRDAProbe10 alerts/day. What federated queries drive this? | Query `DB2FED.XFKMPRD` access patterns |
| FKMHST session count | p-no1fkmprd-db | 90–187 sessions with only 2 unique users, repeatedly | Expected for a host/gateway DB? Confirm connection pooling behavior |
| DB2 diag log rotation | p-no1fkmprd-db | 366 MB single diag log file | Set DB2 `DIAGSIZE` parameter, or run `db2diag -A` |

---

*Analysis covers data from 2026-02-18 to 2026-02-20. Config changes applied in two rounds on 2026-02-20.*
*Config source of truth: `C:\opt\src\DedgeSrc\DedgeSystemTools\Folders\DedgeCommon\Software\Config\ServerMonitor\appsettings.ServerMonitorAgent.json`*
