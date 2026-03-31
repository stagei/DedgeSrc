# ServerMonitor Alert Analysis Methodology

**Purpose:** Standardized procedure for analyzing alert patterns across the ServerMonitor agent fleet and recommending configuration tuning.

**Trigger:** Run `--analysis` in Cursor to execute this automatically.

**Rule file:** `c:\opt\src\ServerMonitor\.cursor\rules\command-analysis.mdc`

---

## Overview

The ServerMonitor agent runs on all servers in the fleet (DB and app servers). Each agent monitors:
- DB2 databases (diag logs, instance health, sessions, queries)
- Windows Event Log (system, application, security events)
- Scheduled Tasks (completion status, failures)
- IIS Web Server (sites, app pools, worker processes)
- System resources (CPU, memory, virtual memory, disk)

Alerts are generated when thresholds are exceeded or patterns are matched. All alerts are written to local log files on each server and polled by the Dashboard for centralized display.

Over time, alert configurations need tuning because:
- New workloads create new baselines that weren't anticipated
- Batch jobs produce predictable bursts that should be grouped
- Broad regex patterns match benign conditions alongside real errors
- Thresholds set during initial deployment may be too sensitive or too loose

---

## Data Sources

### 1. Dashboard API

The ServerMonitorDashboard on `dedge-server` provides REST APIs:

| Endpoint | Use |
|----------|-----|
| `GET /ServerMonitorDashboard/api/servers` | Discover all monitored servers |
| `GET /ServerMonitorDashboard/api/alerts/active` | Current active alerts by server |
| `GET /ServerMonitorDashboard/api/alerts/config` | Alert polling settings |
| `GET /ServerMonitorDashboard/api/snapshot/{server}` | Full agent snapshot (proxied) |

All endpoints require Windows authentication (`-UseDefaultCredentials`).

### 2. Alert Log Files (per server)

Each server writes alert logs to `\\{serverName}\opt\data\ServerMonitor\`:

| File Pattern | Content |
|-------------|---------|
| `FkLog_{yyyyMMdd}.log` | General agent log (text, timestamped lines) |
| `AlertLog_{yyyyMMdd}.json` | Structured alerts (one JSON object per line) |

### 3. Centralized Logs

Some logs are also copied to a central share:

```
C:\opt\src\DedgeSrc\DedgeSystemTools\Folders\Commonlogging\Server\ServerMonitor\
```

Including SQL error logs: `{server}_{date}_{database}_sqlerrors.log`

### 4. Agent Configuration (source of truth)

```
C:\opt\src\DedgeSrc\DedgeSystemTools\Folders\DedgeCommon\Software\Config\ServerMonitor\appsettings.ServerMonitorAgent.json
```

This is the single config file used by ALL agents in the fleet.

---

## Server Fleet

| Server | Role | Type |
|--------|------|------|
| t-no1inltst-db | Test DB (INLTST) | DB |
| p-no1fkmprd-db | Prod DB (FKMPRD/XFKMPRD/FKMHST) | DB |
| p-no1inlprd-db | Prod DB (INLPRD/XINLPRD) | DB |
| dedge-server | Test app server | App/IIS |
| p-no1fkmprd-app | Prod app server | App/IIS |
| p-no1fkxprd-app | Prod app server | App/IIS |
| t-no1inltst-app | Test app server | App/IIS |
| p-no1inlprd-app | Prod app server | App/IIS |

---

## Analysis Procedure

### Phase 1: Data Collection

1. **Query Dashboard API** for server list and active alerts
2. **Read alert log files** from each accessible server (today + yesterday minimum)
3. **Read the production config** to understand current thresholds

### Phase 2: Volume Analysis

For each server, calculate:

| Metric | How |
|--------|-----|
| Total alerts per day | Count lines in `AlertLog_{date}.json` |
| Alerts by severity | Group by `Severity` field (CRITICAL, WARNING, Informational) |
| Alerts by category | Group by `Category` field (Database, EventLog, ScheduledTask, IIS, etc.) |
| Alerts by source | Group by `Source` or `AlertKey` field |
| File size trend | Compare today vs. yesterday log file sizes |

### Phase 3: Pattern Detection

Look for these common patterns:

| Pattern | Indicator | Action |
|---------|-----------|--------|
| **Burst flooding** | 100+ identical alerts within 5 minutes | Increase MaxOccurrences or add specific Skip/Remap pattern |
| **Constant baseline** | Same count every hour, 24/7 | Threshold is below the operational floor — raise it |
| **Time-clustered** | Alerts only at specific hours (e.g., 05:30) | Likely batch job — add time-aware suppression or group pattern |
| **Double-alert** | Same event generates 2 alerts (specific + generic) | Fix code path or add Skip for the generic fallback |
| **Cross-server** | Same alert on all servers | Systemic — may need fleet-wide threshold adjustment |
| **Per-entity fragmentation** | Separate alert per user/database/task | Alert key is too granular — aggregate before alerting |

### Phase 4: Recommendation Generation

For each finding, document:

1. **What is happening** — describe the alert pattern with data
2. **Root cause analysis** — why does this alert at this volume?
3. **Config change** — specific JSON path, old value, new value
4. **Expected impact** — estimated reduction in alert count
5. **Risk assessment** — what genuine alerts might be missed?

### Phase 5: Report Generation

Save as `docs/Alert-Tuning-Analysis-{yyyy-MM-dd}.md` with sections:

1. Server Fleet Overview (table)
2. Volume Summary (table with per-server, per-day, per-severity counts)
3. Numbered Findings (each with what/why/recommendation)
4. Complete Config Change Log (table with all proposed changes)
5. Pattern Priority Table (if DB2 patterns were modified)
6. Remaining Investigation Items (things that need human follow-up)

### Phase 6: Apply Changes (with user confirmation)

After presenting the report:

1. Ask user to confirm which changes to apply
2. Follow the **mandatory UNC config workflow**:
   - Pull UNC → local
   - Edit local
   - Push local → UNC
   - Push local → published agent folder
3. Verify changes with `Select-String` on UNC file
4. Agent reloads config every 15 minutes (`ConfigReloadIntervalMinutes: 15`)

---

## Alert Tuning Categories

### DB2 Diag Monitoring (`Db2DiagMonitoring`)

Key config fields:
- `PatternsToMonitor[]` — regex patterns with Priority, Action (Skip/Remap/Escalate/LogOnly), MaxOccurrences
- `MaxEntriesPerCycle` — limits entries scanned per polling cycle
- `DuplicateSuppressionMinutes` — cooldown between duplicate alerts
- `MaxLogFileSizeBytes` — skip scan if diag log exceeds this size

### DB2 Instance Monitoring (`Db2InstanceMonitoring`)

Key thresholds:
- `LongRunningQueryWarningSeconds` / `CriticalSeconds`
- `SessionCountWarningThreshold` / `CriticalThreshold`
- `LockWaitWarningSeconds` / `CriticalSeconds`
- `DiagErrorsTodayWarningThreshold`

### Event Log Monitoring (`EventMonitoring`)

Per-event configuration:
- `EventId`, `Source`, `LogName`
- `MaxOccurrences` / `TimeWindowMinutes` — how many before alerting
- `SuppressedChannels[]` — skip SMS, Email, WkMonitor, etc.

### IIS Monitoring (`IisMonitoring`)

Key settings:
- `AlertOnStoppedAppPools` / `AlertOnStoppedSites`
- `WorkerProcessMemoryThresholdMB`
- `Alerts.StoppedAppPoolSeverity` / `StoppedSiteSeverity`

### System Resource Monitoring

- `ProcessorMonitoring` — WarningPercent, CriticalPercent, SustainedDurationSeconds
- `VirtualMemoryMonitoring` — WarningPercent, CriticalPercent, ExcessivePagingRate
- `PhysicalMemoryMonitoring` — WarningPercent, CriticalPercent

---

## Comparison with Previous Analyses

Always reference the most recent analysis when generating a new one. Compare:

- Are previously identified noise sources still producing alerts?
- Did applied changes have the expected impact?
- Are there new alert sources that weren't present before?
- Has any server's alert volume changed significantly?

Previous analyses:
- `docs/Alert-Tuning-Analysis-2026-02-20.md` — Initial multi-server analysis (2 rounds)

---

## PowerShell Quick Reference

```powershell
# Get server list from Dashboard
$baseUrl = "http://dedge-server/ServerMonitorDashboard"
$servers = Invoke-RestMethod -Uri "$($baseUrl)/api/servers" -UseDefaultCredentials

# Get active alerts
$alerts = Invoke-RestMethod -Uri "$($baseUrl)/api/alerts/active" -UseDefaultCredentials

# Read today's alert log from a server
$server = "p-no1fkmprd-db"
$today = Get-Date -Format "yyyyMMdd"
$logPath = "\\$($server)\opt\data\ServerMonitor\AlertLog_$($today).json"
$alertLines = Get-Content $logPath | ForEach-Object { $_ | ConvertFrom-Json }

# Count by severity
$alertLines | Group-Object Severity | Select-Object Name, Count

# Count by category
$alertLines | Group-Object Category | Sort-Object Count -Descending | Select-Object Name, Count

# Read production config
$config = Get-Content "C:\opt\src\DedgeSrc\DedgeSystemTools\Folders\DedgeCommon\Software\Config\ServerMonitor\appsettings.ServerMonitorAgent.json" | ConvertFrom-Json
```

---

*This document describes the methodology used by the `--analysis` command defined in `.cursor/rules/command-analysis.mdc`.*
