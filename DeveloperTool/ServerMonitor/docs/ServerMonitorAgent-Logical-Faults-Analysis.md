# ServerMonitorAgent Logical Faults Analysis

**Analysis Date:** 2026-01-25  
**Version Analyzed:** 1.0.144

This document identifies logical faults, inconsistencies, and potential issues in the ServerMonitorAgent implementation and configuration.

---

## 🔴 Critical Issues

### 1. Db2InstanceDataCollector Uses Static Configuration

**Location:** `Db2InstanceDataCollector.cs` line 21

**Problem:** The collector injects `IOptions<Db2InstanceMonitoringSettings>` instead of `IOptionsMonitor<>`:
```csharp
IOptions<Db2InstanceMonitoringSettings> settings
```

**Impact:** Configuration changes to `Db2InstanceMonitoring` settings (thresholds, intervals, etc.) will NOT be reflected until the agent is restarted. Other monitors use `IOptionsMonitor<>` and support hot-reload.

**Fix:** Change to `IOptionsMonitor<Db2InstanceMonitoringSettings>` and read `.CurrentValue` when needed.

---

### 2. Db2MinimumLogLevel Always Includes "Event" Level

**Location:** `Db2DiagMonitor.cs` line 763

**Problem:** The `GetTargetLevels()` function hardcodes "Event" in the initial HashSet:
```csharp
var levels = new HashSet<string>(StringComparer.OrdinalIgnoreCase) { "Event" };
```

**Impact:** Even when `Db2MinimumLogLevel` is set to "Error", "Event" level entries are ALWAYS processed and stored in memory. This is inconsistent with the documented behavior.

**Intended Behavior:** If `Db2MinimumLogLevel` is "Error", only Critical, Severe, and Error entries should be read from the log.

**Fix:** Remove hardcoded "Event" or make it configurable. Add "Event" to the priority map with priority 5.

---

### 3. DB2 Instance Monitor RefreshIntervalSeconds Ignores Performance Scaling

**Location:** `Db2InstanceMonitor.cs` lines 66-71

**Problem:** The `Db2InstanceMonitor` has its own internal caching based on `RefreshIntervalSeconds`:
```csharp
if (_lastSnapshot != null && timeSinceLastCollection.TotalSeconds < settings.RefreshIntervalSeconds)
{
    // Return cached result
}
```

**Impact:** On low-capacity servers (matching `LowCapacityServerPattern`), other monitors have their intervals multiplied by 4x, but DB2 Instance Monitor's 1200s interval stays at 1200s. This creates inconsistent behavior.

**Fix:** Apply `PerformanceScalingService.ScaleIntervalSeconds()` to `RefreshIntervalSeconds`.

---

## 🟠 Medium Issues

### 4. Duplicate ServerNamePattern Configuration

**Location:** `appsettings.json` lines 686 and 878

**Problem:** Both `Db2DiagMonitoring` and `Db2InstanceMonitoring` have separate `ServerNamePattern` settings:
```json
"Db2DiagMonitoring": {
  "ServerNamePattern": "-db$"
},
"Db2InstanceMonitoring": {
  "ServerNamePattern": "-db$"
}
```

**Impact:** These can get out of sync. A user might enable DB2 instance monitoring on different servers than diag monitoring, causing confusion.

**Fix:** Consider a shared `Db2Monitoring` parent section with a single `ServerNamePattern`, or document that they must match.

---

### 5. CPU SustainedDurationSeconds Effectively Disables Alerts

**Location:** `appsettings.json` line 213

**Problem:**
```json
"ProcessorMonitoring": {
  "Thresholds": {
    "WarningPercent": 99,
    "CriticalPercent": 100,
    "SustainedDurationSeconds": 86400  // 24 hours!
  }
}
```

**Impact:** CPU must be at 99%+ for 24 continuous hours before generating an alert. This effectively disables CPU alerting - no realistic workload maintains 99% CPU for 24 hours straight.

**Recommendation:** Set to a more reasonable value like 300-600 seconds (5-10 minutes).

---

### 6. Empty InstanceNames Array May Cause Silent Failures

**Location:** `appsettings.json` line 882

**Problem:**
```json
"Db2InstanceMonitoring": {
  "InstanceNames": []
}
```

The code attempts auto-detection:
```csharp
var instanceNames = settings.InstanceNames.Count > 0 
    ? settings.InstanceNames 
    : await DetectInstanceNamesAsync(cancellationToken);
```

**Impact:** `DetectInstanceNamesAsync()` relies on the `DB2INSTANCE` environment variable. If not set (e.g., when running as a different user or service account), no instances will be found and monitoring silently does nothing.

**Fix:** Either require explicit instance names in config, or improve detection with registry lookup/db2ls command.

---

### 7. Db2InstanceAlerts Uses String Severity Instead of Enum

**Location:** `Db2InstanceMonitoringSettings.cs` lines 143-168

**Problem:** Alert severities are defined as strings:
```csharp
public string LongRunningQueryWarningSeverity { get; init; } = "Warning";
public string LongRunningQueryCriticalSeverity { get; init; } = "Critical";
```

But code needs to parse them:
```csharp
Severity = ParseSeverity(alertSettings.LongRunningQueryCriticalSeverity)
```

**Impact:** 
- Typos in config (e.g., "Warninng") will fail silently or use default
- No compile-time validation
- Inconsistent with other monitors that use `AlertSeverity` enum

**Fix:** Change to use `AlertSeverity` enum type, or add robust validation with clear error messages.

---

### 8. MaxOccurrences = 0 Semantics Inconsistent

**Location:** Various places in `appsettings.json`

**Problem:** `MaxOccurrences: 0` means different things in different contexts:
- In pattern throttling: "alert on every occurrence" (no throttling)
- But global throttling (`MaxAlertsPerHour: 50`) still applies

**Example:** A pattern with `MaxOccurrences: 0` suggests "always alert", but if you hit the global limit of 50/hour, alerts are dropped.

**Fix:** Document this clearly. Consider using `-1` or `null` for "unlimited" to distinguish from "0 occurrences = threshold of 0".

---

## 🟡 Minor Issues

### 9. DiskUsageMonitoring is Disabled but DiskSpaceMonitoring is Enabled

**Location:** `appsettings.json` lines 267-282 and 284-300

**Problem:** Two similar-sounding monitors:
- `DiskUsageMonitoring` (I/O performance) - **Disabled**
- `DiskSpaceMonitoring` (free space) - **Enabled**

**Impact:** The naming is confusing. "Usage" typically means "how full" not "I/O activity".

**Recommendation:** Rename to `DiskIOMonitoring` and `DiskSpaceMonitoring` for clarity.

---

### 10. Event Level "Information" vs "Informational" Inconsistency

**Location:** `appsettings.json` lines 474-488

**Problem:** Windows events use "Information":
```json
{
  "EventId": 1074,
  "Level": "Information"  // <-- Windows uses this
}
```

But agent severities use "Informational":
```json
"MinimumAlertSeverity": "Warning"  // Valid values: Critical, Warning, Informational
```

**Impact:** Configuration seems inconsistent, though code handles both.

**Fix:** Standardize on one naming convention throughout.

---

### 11. Missing Validation for Regex Patterns

**Location:** `Db2DiagMonitoringSettings.cs`, `PerformanceScalingSettings.cs`

**Problem:** Regex patterns in config are not validated at startup:
```json
"ServerNamePattern": "-db$",
"Regex": "Query Gateway.*sqlqgGetUserOptions|can't get valid connected user name.*QPLEX"
```

**Impact:** Invalid regex patterns will cause runtime exceptions on first match attempt.

**Fix:** Add startup validation that compiles all regex patterns and logs/fails on invalid patterns.

---

### 12. Throttling Suppression Times Don't Match Alert Importance

**Location:** `appsettings.json` lines 159-161

**Problem:**
```json
"Throttling": {
  "WarningSuppressionMinutes": 60,
  "ErrorSuppressionMinutes": 15,       // Errors suppressed for LESS time
  "InformationalSuppressionMinutes": 1440  // Informational = 24 hours
}
```

**Observation:** Errors are suppressed for less time (15 min) than Warnings (60 min). This is intentional (errors are more important so you want to see them more often), but the inverse naming is counterintuitive.

**Recommendation:** Add a "Notes" field explaining the rationale.

---

### 13. WKMonitor Channel Enabled=false but Referenced in SuppressedChannels

**Location:** `appsettings.json` lines 143-152 and 700

**Problem:**
```json
{
  "Type": "WKMonitor",
  "Enabled": false  // Disabled globally
}
...
"Db2DiagMonitoring": {
  "SuppressedChannels": ["WkMonitor"]  // But also suppressed here (case mismatch too!)
}
```

**Impact:** 
1. Suppressing a disabled channel is redundant
2. Case mismatch: "WKMonitor" vs "WkMonitor" may cause issues if channel matching is case-sensitive

**Fix:** Remove from `SuppressedChannels` if globally disabled. Fix case consistency.

---

### 14. MaxLogFileSizeBytes Description Mismatch

**Location:** `appsettings.json` lines 697-698

**Problem:**
```json
"MaxLogFileSizeBytes": 314572800,
"MaxLogFileSizeBytesNotes": "Maximum log file size in bytes (314572800 = 300 MB)"
```

**Calculation:** 314572800 bytes = 300 × 1024 × 1024 = **300 MiB** (not MB)

**Impact:** Minor, but technically 300 MB = 300,000,000 bytes. This uses binary units (MiB).

**Fix:** Clarify in notes or use 300000000 for exactly 300 MB.

---

## 📋 Configuration Recommendations

### Recommended Fixes for Production

1. **Change CPU SustainedDurationSeconds from 86400 to 300-600**
2. **Add explicit DB2 instance names** if auto-detection is unreliable
3. **Align ServerNamePattern** between Db2DiagMonitoring and Db2InstanceMonitoring
4. **Enable Db2InstanceMonitoring** if DB2 instance metrics are needed
5. **Fix WkMonitor case** to match exactly

### Code Fixes Required

| Priority | File | Issue | Fix |
|----------|------|-------|-----|
| High | `Db2InstanceDataCollector.cs` | Static config | Use `IOptionsMonitor<>` |
| High | `Db2DiagMonitor.cs` | Hardcoded "Event" | Make configurable |
| Medium | `Db2InstanceMonitor.cs` | No perf scaling | Apply `PerformanceScalingService` |
| Medium | `Db2InstanceMonitoringSettings.cs` | String severities | Use `AlertSeverity` enum |
| Low | Multiple | Regex validation | Add startup validation |

---

## Summary

| Severity | Count | Description |
|----------|-------|-------------|
| 🔴 Critical | 3 | Config not hot-reloadable, hardcoded levels, missing scaling |
| 🟠 Medium | 5 | Duplicate config, ineffective thresholds, silent failures |
| 🟡 Minor | 6 | Naming, validation, documentation |

**Total Issues:** 14

Most issues relate to **configuration inconsistency** and **incomplete integration** between the newer DB2 instance monitoring features and the established patterns used by other monitors.
