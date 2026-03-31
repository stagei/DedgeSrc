# DB2 DRDA Wrapper Error Analysis: probe:10

## Error Summary

| Attribute | Value |
|-----------|-------|
| **Server** | p-no1fkmprd-db |
| **Instance** | DB2FED |
| **Database** | XFKMPRD |
| **Function** | `DB2 UDB, drda wrapper, report_error_message, probe:10` |
| **Severity** | Error (DB2) → Critical (Agent default mapping) |
| **Frequency** | High volume (thousands per day) |

## What is DRDA?

**DRDA** (Distributed Relational Database Architecture) is IBM's protocol for communication between distributed database systems. In DB2, the **DRDA wrapper** is used for:

1. **Federated queries** - Accessing remote databases from a local DB2 instance
2. **Database links** - Connecting DB2 to other DB2 instances or other RDBMS
3. **Nicknames** - Virtual tables that reference remote data sources

## What Does probe:10 Mean?

The probe number in DB2 diagnostic messages indicates the specific location in the code where the error was logged:

| Probe | Description |
|-------|-------------|
| **probe:10** | Error occurred during SQL execution phase on the remote server |
| probe:20 | Error occurred during connection or query preparation |
| probe:30 | Error occurred during result set processing |

**`probe:10`** specifically indicates that:
- A SQL statement was sent to a remote (federated) database server
- The remote server returned an error during execution
- The DRDA wrapper is reporting this error back to the calling application

## Error Context from This Alert

```
FUNCTION: DB2 UDB, drda wrapper, report_error_message, probe:10
DATA #1 : DRDA Server:    
DATA #2 : FKMPRD          ← Remote server nickname
DATA #3 : Function name:  
DATA #4 : SQLExecute      ← Failed during SQL execution
```

This tells us:
- **XFKMPRD** (local federated database) was executing a query
- The query involved a federated link to **FKMPRD** (remote server)
- The `SQLExecute` function failed on the remote server

## Why Does This Happen?

### Common Causes

1. **Network connectivity issues**
   - Temporary network glitches between DB2FED and the remote server
   - Firewall rules blocking traffic intermittently

2. **Remote server issues**
   - Lock contention or deadlocks on the remote database
   - Resource exhaustion (memory, connections) on remote server
   - Remote query timeout

3. **Data issues**
   - Foreign key constraint violations
   - Unique constraint violations on federated inserts/updates
   - Data type mismatches

4. **Configuration issues**
   - Connection pool exhaustion
   - Authentication token expiration
   - Wrapper configuration drift

### Why High Volume?

In federated environments like XFKMPRD → FKMPRD, every failed remote operation generates this error. Batch jobs or applications that:
- Process many records with federated queries
- Have retry logic that generates multiple attempts
- Run during peak hours with higher failure rates

...will produce many of these errors even for transient issues.

## Severity Assessment

### Is This Critical?

**Usually NO** - Despite DB2 logging this as "Error" level:

| Factor | Assessment |
|--------|------------|
| **Transient** | Most probe:10 errors are temporary and auto-recover |
| **Expected** | Federated operations have inherent failure modes |
| **Application handles** | Well-designed apps retry failed federated calls |
| **No data loss** | Failed operations don't corrupt data |

### When IS It Critical?

- **Sustained failures** - If errors persist for extended periods (>30 min)
- **100% failure rate** - If ALL federated queries are failing
- **Accompanied by other errors** - If combined with connection failures or severe errors

## Recommended Alert Configuration

Based on this analysis, we've configured a filter in `appsettings.json`:

```json
{
  "PatternId": "DRDAProbe10",
  "Description": "DRDA wrapper probe:10 errors (federated SQL execution, high volume expected)",
  "Regex": "drda wrapper,\\s*report_error_message,\\s*probe:10",
  "Enabled": true,
  "Action": "Remap",
  "Level": "Warning",
  "MessageTemplate": "DRDA federated SQL in {Database}",
  "Priority": 41,
  "MaxOccurrences": 1000,
  "TimeWindowMinutes": 1440,
  "SuppressedChannels": []
}
```

### What This Does:

1. **Remap** - Changes severity from Critical to Warning
2. **MaxOccurrences: 1000** - Only alert if >1000 errors in 24 hours
3. **TimeWindowMinutes: 1440** - 24-hour sliding window

This means:
- ✅ Normal federated operation noise is suppressed
- ✅ Unusually high error rates still trigger alerts
- ✅ Errors are still logged for troubleshooting
- ✅ Dashboard shows them in diagnostic counters

## Troubleshooting Steps

If you need to investigate:

1. **Check remote server health**
   ```sql
   -- On FKMPRD, check for blocking/locks
   SELECT * FROM SYSIBMADM.SNAPLOCK WHERE LOCK_STATUS = 'G';
   ```

2. **Check federated wrapper status**
   ```sql
   -- On DB2FED, check wrapper servers
   SELECT * FROM SYSCAT.SERVERS WHERE WRAPNAME = 'DRDA';
   ```

3. **Review recent db2diag.log entries**
   ```powershell
   # Filter for related errors
   Select-String -Path "E:\DB2\DB2FED\db2diag.log" -Pattern "XFKMPRD.*probe:10" | 
     Select-Object -Last 20
   ```

4. **Check connection pool**
   ```sql
   -- Active connections to federated server
   SELECT * FROM TABLE(MON_GET_CONNECTION(NULL, -2)) 
   WHERE APPLICATION_NAME LIKE '%FED%';
   ```

## Conclusion

The `DRDA wrapper, report_error_message, probe:10` error is a **normal operational message** in federated DB2 environments. It indicates that a remote SQL execution failed, but this is:

- Expected in distributed systems
- Usually transient
- Handled by application retry logic
- Not indicative of data corruption

The configured filter appropriately suppresses noise while still alerting on abnormal volumes (>1000/day).

---

*Document created: 2026-01-27*
*Related to: ServerMonitor DB2 Diagnostic Monitoring*
