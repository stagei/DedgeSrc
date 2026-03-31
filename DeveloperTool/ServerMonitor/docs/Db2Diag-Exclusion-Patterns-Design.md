# DB2 Diag Log Exclusion Patterns Design

## Overview

This document outlines a plan to add regex-based exclusion patterns to the DB2 Diagnostic Log Monitor. This allows administrators to filter out known, non-actionable log entries (like startup events, expected errors, or informational messages) without disabling the entire monitor.

## Current State

### Live Data Analysis (p-no1fkmprd-db)

From the production database server, we observed:

| Level | Count | Description |
|-------|-------|-------------|
| Error | 60 | Critical alerts from DRDA wrapper |
| Event | 2 | Informational (startup messages) |

#### Unique FUNCTION Patterns Found

```
DB2 UDB, RAS/PD component, pdLogInternal, probe:120
DB2 UDB, drda wrapper, report_error_message, probe:10
DB2 UDB, drda wrapper, report_error_message, probe:20
```

#### Sample Messages

1. **Event - New Diagnostic Log file** (probe:120)
   - Occurs at DB2 startup
   - Contains build level and system info
   - Typically non-actionable

2. **Error - DRDA Server** (probe:10)
   - Federation wrapper errors
   - May indicate connection issues to remote servers

3. **Error - ODBC native err** (probe:20)
   - ODBC driver errors from federation
   - Often duplicates of probe:10 errors

### Current Configuration

```json
"Db2DiagMonitoring": {
  "Enabled": true,
  "ServerNamePattern": "-db$",
  "MinimumSeverityLevel": "Error",
  "MaxEntriesPerCycle": 200,
  "Throttling": {
    "MaxAlertsPerInstancePerHour": 100,
    "DuplicateSuppressionMinutes": 15
  }
}
```

## Proposed Solution

### New Configuration Properties

Add an `ExclusionPatterns` section to `Db2DiagMonitoring`:

```json
"Db2DiagMonitoring": {
  "Enabled": true,
  "ServerNamePattern": "-db$",
  "MinimumSeverityLevel": "Error",
  
  "ExclusionPatterns": {
    "Notes": "Regex patterns to exclude DB2 diag entries. Entries matching ANY pattern will not generate alerts. Patterns are case-insensitive.",
    "Enabled": true,
    
    "ByFunction": [
      {
        "Pattern": "pdLogInternal.*probe:120",
        "Description": "Exclude startup 'New Diagnostic Log file' events",
        "Enabled": true
      },
      {
        "Pattern": "report_error_message.*probe:10",
        "Description": "Exclude DRDA federation errors (if expected)",
        "Enabled": false
      }
    ],
    
    "ByMessage": [
      {
        "Pattern": "user.*not.*authorized",
        "Description": "Exclude authorization failures (handled by SIEM)",
        "Enabled": false
      }
    ],
    
    "ByRawBlock": [
      {
        "Pattern": "DRDA Server:.*FKMHST",
        "Description": "Exclude federation errors to FKMHST",
        "Enabled": false
      }
    ],
    
    "ByDatabase": [
      {
        "Pattern": "^TESTDB$",
        "Description": "Exclude all entries for TESTDB database",
        "Enabled": false
      }
    ],
    
    "ByLevel": [
      {
        "Pattern": "^Event$",
        "Description": "Exclude all Event-level entries",
        "Enabled": false
      }
    ]
  }
}
```

### Pattern Types

| Type | Matches Against | Use Case |
|------|-----------------|----------|
| `ByFunction` | `FUNCTION` field (e.g., "DB2 UDB, drda wrapper, report_error_message, probe:10") | Exclude specific DB2 components/probes |
| `ByMessage` | `MESSAGE` field | Exclude messages containing specific text |
| `ByRawBlock` | Full raw log block | Match complex patterns across multiple fields |
| `ByDatabase` | `DB` field | Exclude specific databases |
| `ByLevel` | `LEVEL` field (Critical, Severe, Error, Warning, Event) | Exclude entire severity levels |

### Example Exclusion Patterns

#### 1. Exclude Startup Events
```json
{
  "Pattern": "pdLogInternal.*probe:120",
  "Description": "DB2 startup/shutdown events",
  "Enabled": true
}
```

**Matches:** 
```
FUNCTION: DB2 UDB, RAS/PD component, pdLogInternal, probe:120
START   : New Diagnostic Log file
```

#### 2. Exclude Federation Errors to Specific Server
```json
{
  "Pattern": "DRDA Server:.*FKMHST",
  "Description": "Federation errors to FKMHST (known maintenance window)",
  "Enabled": true
}
```

**Matches raw block containing:**
```
DATA #1 : String, 16 bytes
DRDA Server:
DATA #2 : String with size, 6 bytes
FKMHST
```

#### 3. Exclude All Events from Test Database
```json
{
  "Pattern": "^TESTDB$",
  "Description": "Test database - no alerts needed",
  "Enabled": true
}
```

#### 4. Exclude Specific Error Codes
```json
{
  "Pattern": "ZRC=0x[89]",
  "Description": "Exclude warning-level ZRC codes (0x8xxx, 0x9xxx)",
  "Enabled": true
}
```

#### 5. Exclude User Authorization Failures
```json
{
  "Pattern": "user.*disabled|not.*authorized|authentication.*failed",
  "Description": "Auth failures handled by SIEM",
  "Enabled": true
}
```

## Implementation Plan

### Phase 1: Configuration Classes

Add new classes to `Db2DiagMonitoringSettings.cs`:

```csharp
public class Db2ExclusionPatterns
{
    public bool Enabled { get; init; } = false;
    public List<ExclusionPattern> ByFunction { get; init; } = new();
    public List<ExclusionPattern> ByMessage { get; init; } = new();
    public List<ExclusionPattern> ByRawBlock { get; init; } = new();
    public List<ExclusionPattern> ByDatabase { get; init; } = new();
    public List<ExclusionPattern> ByLevel { get; init; } = new();
}

public class ExclusionPattern
{
    public string Pattern { get; init; } = "";
    public string? Description { get; init; }
    public bool Enabled { get; init; } = true;
    
    private Regex? _compiledPattern;
    public bool IsMatch(string? value)
    {
        if (string.IsNullOrEmpty(value) || !Enabled) return false;
        _compiledPattern ??= new Regex(Pattern, RegexOptions.IgnoreCase | RegexOptions.Compiled);
        return _compiledPattern.IsMatch(value);
    }
}
```

### Phase 2: Monitor Integration

Modify `Db2DiagMonitor.CreateAlertFromEntry()` to check exclusions:

```csharp
private Alert? CreateAlertFromEntry(Db2DiagEntry entry, string instanceName, Db2DiagMonitoringSettings settings)
{
    // Check exclusion patterns before creating alert
    if (settings.ExclusionPatterns?.Enabled == true)
    {
        if (IsExcluded(entry, settings.ExclusionPatterns))
        {
            _logger.LogDebug("DB2 entry excluded by pattern: {Function}", entry.Function);
            return null;
        }
    }
    
    // ... existing alert creation code ...
}

private bool IsExcluded(Db2DiagEntry entry, Db2ExclusionPatterns patterns)
{
    // Check each pattern type
    if (patterns.ByFunction.Any(p => p.IsMatch(entry.Function))) return true;
    if (patterns.ByMessage.Any(p => p.IsMatch(entry.Message))) return true;
    if (patterns.ByRawBlock.Any(p => p.IsMatch(entry.RawBlock))) return true;
    if (patterns.ByDatabase.Any(p => p.IsMatch(entry.DatabaseName))) return true;
    if (patterns.ByLevel.Any(p => p.IsMatch(entry.Level))) return true;
    
    return false;
}
```

### Phase 3: Logging and Metrics

Add metrics for excluded entries:

```csharp
db2Data.ExcludedByPatternCount = excludedCount;
db2Data.ExclusionPatternsActive = activePatternCount;
```

Log summary at end of cycle:
```
📊 DB2 Diag Monitor COMPLETE: 150ms | Entries: 62 | Excluded: 15 | Alerts: 47
```

### Phase 4: Dashboard Integration (Optional)

Add UI to:
- View active exclusion patterns
- See exclusion hit counts
- Test patterns against recent entries
- Enable/disable patterns dynamically

## Recommended Initial Configuration

Based on production data analysis, these patterns should be enabled initially:

```json
"ExclusionPatterns": {
  "Enabled": true,
  
  "ByFunction": [
    {
      "Pattern": "pdLogInternal.*probe:120",
      "Description": "DB2 startup/shutdown diagnostic events - informational only",
      "Enabled": true
    }
  ],
  
  "ByRawBlock": [],
  "ByMessage": [],
  "ByDatabase": [],
  "ByLevel": []
}
```

This excludes only the "New Diagnostic Log file" startup events, which are purely informational and generated every time DB2 starts or rotates log files.

## Testing Strategy

1. **Unit Tests**: Test regex matching against sample log blocks
2. **Integration Tests**: Verify exclusion works end-to-end
3. **Shadow Mode**: Log what would be excluded without actually excluding (for validation)
4. **Gradual Rollout**: Enable one pattern at a time, monitor for missed alerts

## Rollback Plan

If exclusion patterns cause issues:
1. Set `"ExclusionPatterns": { "Enabled": false }` to disable all patterns
2. Or set individual pattern `"Enabled": false` 
3. No code changes needed - configuration only

## Future Enhancements

1. **Time-based exclusions**: Exclude patterns only during certain hours (maintenance windows)
2. **Instance-specific patterns**: Different patterns per DB2 instance
3. **Auto-learning**: Suggest patterns based on frequently occurring non-actionable entries
4. **Pattern validation API**: Test patterns before applying

## References

- [Db2DiagMonitor.cs](../ServerMonitorAgent/src/ServerMonitor.Core/Monitors/Db2DiagMonitor.cs)
- [Db2DiagMonitoringSettings.cs](../ServerMonitorAgent/src/ServerMonitor.Core/Configuration/Db2DiagMonitoringSettings.cs)
- [appsettings.json](../ServerMonitorAgent/src/ServerMonitor/appsettings.json)
