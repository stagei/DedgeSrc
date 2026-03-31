# DB2 Diagnostic Log Severity Mapping Guide

## Purpose

This document provides a framework for understanding, filtering, and remapping IBM DB2 diagnostic log (`db2diag.log`) messages in the **ServerMonitorAgent**. The goal is to differentiate between messages, assign appropriate severity levels, and filter unnecessary noise.

---

## 1. DB2 Diagnostic Log Structure

### 1.1 Log Entry Format

Each DB2 diagnostic entry follows this structure:

```
TIMESTAMP RECORDID                  LEVEL: <severity>
PID     : <pid>                 TID : <tid>           PROC : <process>
INSTANCE: <instance>            NODE : <node>         DB   : <database>
APPHDL  : <handle>              APPID: <appid>
UOWID   : <uow>                 ACTID: <activity>
AUTHID  : <user>                HOSTNAME: <hostname>
EDUID   : <edu>                 EDUNAME: <eduname>
FUNCTION: <component>, <subcomponent>, <function>, probe:<number>
[MESSAGE : <message>]
[CHANGE  : <change_description>]
[CALLED  : <called_function>]
[RETCODE : ZRC=<code>]
[DATA #n : <type>, <size> bytes]
<data_content>
```

### 1.2 Key Fields for Pattern Matching

| Field | Description | Use for Regex |
|-------|-------------|---------------|
| `LEVEL` | DB2's assigned severity | Always match |
| `FUNCTION` | Component/function that logged the entry | Key for categorization |
| `MESSAGE` | Error/event description | Pattern matching |
| `CHANGE` | Configuration/state change description | Event categorization |
| `RETCODE`/`ZRC` | Return code (hex and decimal) | Specific error identification |
| `DATA #n` | Additional context data (may include SQL codes) | SQL error detection |

### 1.3 Fields to **EXCLUDE** from Regex (Variable per entry)

These fields change for each log entry and must NOT be used for pattern matching:

- `TIMESTAMP` (e.g., `2026-01-23-12.50.44.687000+060`)
- `RECORDID` (e.g., `I81741F931`)
- `PID` / `TID` (process/thread IDs)
- `APPHDL` / `APPID` (application handles)
- `UOWID` / `ACTID` (unit of work/activity IDs)
- `EDUID` (engine dispatch unit ID)
- `Numeric values in DATA sections`

---

## 2. DB2 Native Severity Levels

### 2.1 Level Hierarchy (from IBM Documentation)

| DB2 Level | Priority | Description | diaglevel Setting |
|-----------|----------|-------------|-------------------|
| **Severe** | 1 | Critical system failures, data corruption risks | diaglevel ≥ 1 |
| **Error** | 2 | Operation failures, may be recoverable | diaglevel ≥ 2 |
| **Warning** | 3 | Potential issues, non-critical conditions | diaglevel ≥ 3 |
| **Event** | 4 | Informational events, state changes | diaglevel ≥ 4 |
| **Info** | 5 | General information | diaglevel ≥ 5 |

### 2.2 Observed Levels in Production

Based on analysis of 10,000 entries from `p-no1fkmprd-db`:

| Level | Count | Percentage | Description |
|-------|-------|------------|-------------|
| **Error** | 2,853 | 28.5% | Includes SQL errors, connection issues |
| **Event** | 7,147 | 71.5% | Configuration changes, cache resizes |

---

## 3. Message Pattern Categories

### 3.1 SQL Error Messages (in Error level)

SQL errors are logged when federated queries or operations fail. These appear in `DATA` sections.

| SQL Code | Occurrences | Description | Recommended Severity |
|----------|-------------|-------------|---------------------|
| **SQL0530N** | 1,258 | Foreign key constraint violation | **Informational** (expected in bulk ops) |
| **SQL0911N** | 158 | Deadlock/rollback (transaction restart) | **Warning** (transient) |
| **SQL0952N** | 1 | Processing cancelled | **Warning** |

#### Regex for SQL Error Detection

```regex
# Regex to extract SQL error code from db2diag entry
# Matches: SQL0530N, SQL0911N, etc.
# 
# Pattern breakdown:
#   SQL           - Literal "SQL" prefix
#   (\d{4,5})     - Group 1: 4-5 digit error number
#   ([A-Z]?)      - Group 2: Optional severity letter (N=Negative/Error, W=Warning, C=Critical)
SQL(\d{4,5})([A-Z]?)
```

#### Regex for SQLSTATE Detection

```regex
# Regex to extract SQLSTATE from db2diag entry
# Matches: 23503. (constraint violation), 40001. (deadlock), etc.
#
# Pattern breakdown:
#   (\d{5})       - Group 1: 5-digit SQLSTATE code
#   \.            - Literal period (common in db2diag format)
ODBC sqlstate:\s*\r?\n[^\r\n]*\r?\n(\d{5})\.
```

### 3.2 Connection/Communication Errors (in Error level)

Client disconnection events that are often benign.

| Function Pattern | Description | Recommended Severity |
|------------------|-------------|---------------------|
| `sqlcctcptest, probe:11` | TCP client termination detected | **Informational** (normal client disconnect) |
| `sqlcctest, probe:50` | Connection test failure | **Warning** |
| `AgentBreathingPoint, probe:10` | Agent detected client gone | **Informational** (normal) |

#### Regex for Connection Errors

```regex
# Regex to detect client termination (benign)
# 
# Pattern breakdown:
#   FUNCTION:\s*    - Literal "FUNCTION:" with optional whitespace
#   DB2 UDB,\s*     - Literal component prefix
#   common communication,\s*  - Communication subcomponent
#   sqlcc           - SQL communication function prefix
#   (tcptest|test)  - Group 1: Specific function variant
#   ,\s*probe:\d+   - Probe number (any)
#
# Full pattern matches both sqlcctcptest and sqlcctest functions
FUNCTION:\s*DB2 UDB,\s*common communication,\s*sqlcc(tcptest|test),\s*probe:\d+
```

```regex
# Regex to detect "Detected client termination" message
# This is typically informational - client disconnected normally
#
# Pattern breakdown:
#   MESSAGE\s*:     - Literal "MESSAGE :" with flexible whitespace
#   \s*             - Optional whitespace
#   Detected client termination  - Exact message text
MESSAGE\s*:\s*Detected client termination
```

### 3.3 DRDA Wrapper Errors (Federated Database)

Errors from federated database operations (data from remote sources).

| Function Pattern | Description | Recommended Severity |
|------------------|-------------|---------------------|
| `drda wrapper, report_error_message, probe:10` | DRDA error report (high severity) | **Error** |
| `drda wrapper, report_error_message, probe:20` | DRDA error report (standard) | **Warning** (unless SQL code is critical) |

#### Regex for DRDA Errors

```regex
# Regex to detect DRDA wrapper errors (federated database operations)
#
# Pattern breakdown:
#   FUNCTION:\s*    - Literal "FUNCTION:" with whitespace
#   DB2 UDB,\s*     - Component prefix
#   drda wrapper,\s* - DRDA wrapper subcomponent
#   report_error_message  - Error reporting function
#   ,\s*probe:      - Probe indicator
#   (\d+)           - Group 1: Probe number (10=high, 20=standard)
FUNCTION:\s*DB2 UDB,\s*drda wrapper,\s*report_error_message,\s*probe:(\d+)
```

### 3.4 Event Messages (STMM/Cache Operations)

Self-Tuning Memory Manager (STMM) events are almost always informational.

| Function Pattern | Occurrences | Description | Recommended Severity |
|------------------|-------------|-------------|---------------------|
| `config/install, sqlfLogUpdateCfgParam, probe:20` | 4,307 | Config parameter auto-adjusted | **Ignore** (filter out) |
| `access plan manager, sqlra_resize_pckcache, probe:150` | 2,160 | Package cache resized | **Ignore** (filter out) |
| `Self tuning memory manager, stmmLog` | 400 | STMM tuning events | **Ignore** (filter out) |
| `RAS/PD component, pdLogInternal, probe:120` | 278 | New diagnostic log file started | **Ignore** |
| `Health Monitor, db2HmonEvalReorg` | 2 | Health monitor recommendations | **Informational** |

#### Regex for STMM Events (to filter/ignore)

```regex
# Regex to detect STMM auto-tuning events (safe to ignore)
# These are normal DB2 self-optimization activities
#
# Pattern breakdown:
#   CHANGE\s*:      - Literal "CHANGE :" with flexible whitespace
#   \s*             - Optional whitespace
#   (APM|STMM)      - Group 1: APM (Access Plan Manager) or STMM (Self Tuning Memory Manager)
#   .*              - Any characters (captures specific change details)
#   (success|automatic)  - Group 2: Indicates successful auto-tuning
CHANGE\s*:\s*(APM|STMM).*?(success|automatic)
```

```regex
# Regex to detect package cache resize events (informational, can ignore)
#
# Pattern breakdown:
#   FUNCTION:\s*    - Literal "FUNCTION:" with whitespace
#   DB2 UDB,\s*     - Component prefix
#   access plan manager  - APM subcomponent
#   .*              - Any characters
#   sqlra_resize_pckcache  - Package cache resize function
FUNCTION:\s*DB2 UDB,\s*access plan manager.*sqlra_resize_pckcache
```

```regex
# Regex to detect config parameter updates (informational)
#
# Pattern breakdown:
#   FUNCTION:\s*    - Literal "FUNCTION:" with whitespace
#   DB2 UDB,\s*     - Component prefix
#   config/install  - Config subcomponent
#   .*              - Any characters
#   sqlfLogUpdateCfgParam  - Parameter update function
FUNCTION:\s*DB2 UDB,\s*config/install.*sqlfLogUpdateCfgParam
```

### 3.5 ZRC (Zero-based Return Codes)

DB2 internal return codes indicating specific conditions.

| ZRC Code | Decimal | Description | Recommended Severity |
|----------|---------|-------------|---------------------|
| `0x00000036` | 54 | Client connection lost | **Informational** |
| `0x00000001` | 1 | Generic failure | **Warning** |
| `0x8...` | Negative | Serious internal errors | **Error** |

#### Regex for ZRC Detection

```regex
# Regex to extract ZRC return codes
#
# Pattern breakdown:
#   RETCODE\s*:     - Literal "RETCODE :" with whitespace
#   .*              - Any characters (may have additional text)
#   ZRC=            - ZRC indicator
#   (0x[0-9A-Fa-f]+)  - Group 1: Hex code
#   =               - Separator
#   (-?\d+)         - Group 2: Decimal equivalent (may be negative)
RETCODE\s*:.*ZRC=(0x[0-9A-Fa-f]+)=(-?\d+)
```

---

## 4. Severity Remapping Strategy

### 4.1 Recommended Mapping Table

| Pattern Type | DB2 Level | ServerMonitor Level | Rationale |
|--------------|-----------|---------------------|-----------|
| SQL0530N (FK violation) | Error | **Informational** | Expected during bulk operations, application-level issue |
| SQL0911N (Deadlock) | Error | **Warning** | Transient, auto-retried by application |
| Client termination | Error | **Informational** | Normal client disconnect |
| STMM auto-tuning | Event | **Ignore** | Normal DB2 self-optimization |
| Package cache resize | Event | **Ignore** | Normal memory management |
| Config param update | Event | **Ignore** | Automatic configuration tuning |
| DRDA probe:10 | Error | **Error** | Genuine federated errors |
| DRDA probe:20 | Error | **Warning** | Less severe federated issues |
| ZRC 0x8... | Error | **Error** | Internal DB2 failures |
| Health Monitor | Event | **Informational** | Actionable recommendations |

### 4.2 Implementation in appsettings.json

```json
"Db2DiagMonitoring": {
  "Enabled": true,
  "MinimumSeverityLevel": "Error",
  "ExclusionPatterns": [
    {
      "Name": "STMM-AutoTuning",
      "Description": "Self Tuning Memory Manager automatic configuration changes",
      "Regex": "CHANGE\\s*:\\s*(APM|STMM).*?(success|automatic)",
      "Action": "Ignore"
    },
    {
      "Name": "PackageCacheResize",
      "Description": "Access Plan Manager package cache resize operations",
      "Regex": "FUNCTION:\\s*DB2 UDB,\\s*access plan manager.*sqlra_resize_pckcache",
      "Action": "Ignore"
    },
    {
      "Name": "ConfigParamUpdate",
      "Description": "Automatic configuration parameter adjustments",
      "Regex": "FUNCTION:\\s*DB2 UDB,\\s*config/install.*sqlfLogUpdateCfgParam",
      "Action": "Ignore"
    },
    {
      "Name": "NewDiagLogFile",
      "Description": "New diagnostic log file started (rotation)",
      "Regex": "START\\s*:\\s*New Diagnostic Log file",
      "Action": "Ignore"
    }
  ],
  "SeverityRemapping": [
    {
      "Name": "ForeignKeyViolation",
      "Description": "SQL0530N - Foreign key constraint violation (expected in federated ops)",
      "Regex": "SQL0530N",
      "Db2Level": "Error",
      "RemappedLevel": "Informational"
    },
    {
      "Name": "DeadlockRollback",
      "Description": "SQL0911N - Deadlock/timeout (transient, application retries)",
      "Regex": "SQL0911N",
      "Db2Level": "Error",
      "RemappedLevel": "Warning"
    },
    {
      "Name": "ClientTermination",
      "Description": "Normal client disconnection detected",
      "Regex": "MESSAGE\\s*:\\s*Detected client termination",
      "Db2Level": "Error",
      "RemappedLevel": "Informational"
    },
    {
      "Name": "ConnectionTestFailure",
      "Description": "TCP/connection test - client gone (benign)",
      "Regex": "FUNCTION:\\s*DB2 UDB,\\s*common communication,\\s*sqlcc(tcptest|test)",
      "Db2Level": "Error",
      "RemappedLevel": "Informational"
    },
    {
      "Name": "AgentBreathingPoint",
      "Description": "Agent detected client disconnection",
      "Regex": "AgentBreathingPoint.*ZRC=0x00000036",
      "Db2Level": "Error",
      "RemappedLevel": "Informational"
    },
    {
      "Name": "DRDAProbe20",
      "Description": "DRDA wrapper errors (standard severity)",
      "Regex": "drda wrapper,\\s*report_error_message,\\s*probe:20",
      "Db2Level": "Error",
      "RemappedLevel": "Warning"
    }
  ]
}
```

---

## 5. Pattern Recognition Summary

### 5.1 Patterns to IGNORE (Filter Out)

These patterns generate high volume but have no operational impact:

| Pattern | Regex | Volume/Day |
|---------|-------|------------|
| Package cache resize | `sqlra_resize_pckcache` | ~500+ |
| Config auto-update | `sqlfLogUpdateCfgParam` | ~1000+ |
| STMM logging | `stmmLog.*probe` | ~50+ |
| Log file rotation | `New Diagnostic Log file` | ~50+ |

### 5.2 Patterns to DOWNGRADE (Error → Warning/Info)

| Pattern | Regex | Reason |
|---------|-------|--------|
| FK violations | `SQL0530N` | Application data issue, not system |
| Deadlocks | `SQL0911N` | Transient, auto-retried |
| Client disconnect | `Detected client termination` | Normal behavior |
| Connection check | `sqlcc(tcptest\|test)` | Normal disconnect detection |

### 5.3 Patterns to ESCALATE (Keep as Error or promote)

| Pattern | Regex | Reason |
|---------|-------|--------|
| DRDA probe:10 errors | `report_error_message,\\s*probe:10` | Genuine federated failures |
| Negative ZRC codes | `ZRC=0x8` | Internal DB2 failures |
| SQL0952N | `SQL0952N` | Processing cancelled |

---

## 6. References

- IBM DB2 Documentation: [db2diag.log formatting](https://www.ibm.com/docs/en/db2/12.1?topic=logs-db2-diagnostic-log-file)
- IBM DB2 Message Reference: [SQL error codes](https://www.ibm.com/docs/en/db2/12.1?topic=messages-sql)
- DB2 diaglevel parameter: Controls which severity levels are logged (1-5)

---

## 7. Next Steps

1. **Implement ExclusionPatterns** in `Db2DiagMonitor.cs` to filter high-volume noise
2. **Add SeverityRemapping** logic to remap DB2 errors to appropriate ServerMonitor levels
3. **Create unit tests** with sample entries from `test.txt`
4. **Monitor production** to identify additional patterns for filtering/remapping
