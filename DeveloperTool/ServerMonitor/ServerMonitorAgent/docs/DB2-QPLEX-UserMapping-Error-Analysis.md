# DB2 QPLEX Query Gateway User Mapping Error Analysis

## Error Summary

| Attribute | Value |
|-----------|-------|
| **Server** | p-no1fkmprd-db |
| **Instance** | DB2 |
| **Database** | FKMPRD |
| **Function** | `DB2 UDB, Query Gateway, sqlqgGetUserOptions, probe:721` |
| **DB2 Severity** | Error |
| **Remapped Severity** | Warning (by QPLEX-UserError pattern) |
| **Affected User** | BUTEIK03 |
| **Remote Server** | FKMHST |

## What is QPLEX?

**QPLEX** (Query Parallel Execution) is a DB2 component that manages:

1. **Federated query execution** - Distributing queries across multiple data sources
2. **User mapping** - Authenticating users when accessing remote federated servers
3. **Connection pooling** - Managing connections to remote databases

The **Query Gateway** component (`sqlqgGetUserOptions`) is responsible for:
- Resolving local user credentials to remote server credentials
- Managing user mappings defined in `SYSCAT.USEROPTIONS`
- Handling authentication between federated database servers

## Error Message Breakdown

```
MESSAGE : It can't get valid connected user name or disabled the platform user 
          for QPLEX connection
```

### Data Sections Analysis

| Data | Value | Meaning |
|------|-------|---------|
| **Data#1** | `BUTEIK03` | The local user attempting the federated query |
| **Data#2** | `PUBLIC` | Default authorization group (no specific mapping) |
| **Data#3** | `FKMHST` | The remote server nickname/alias being accessed |
| **Data#4** | `DB2NT` | The remote authentication ID being attempted |
| **Data#5** | `false` | Platform user validation result (failed) |

## Why Does This Happen?

### Root Cause

The user **BUTEIK03** is executing a query that involves federated access to server **FKMHST**, but there is **no valid user mapping** configured for this user.

### Common Causes

1. **Missing User Mapping**
   - User `BUTEIK03` doesn't have an entry in `SYSCAT.USEROPTIONS` for server `FKMHST`
   - The user is relying on `PUBLIC` authorization which may not have federated access

2. **Disabled or Expired Mapping**
   - The user mapping exists but has been disabled
   - Password/credentials in the mapping are stale

3. **Application Using Wrong User**
   - Application connecting with a service account that lacks federation privileges
   - User switched context but mapping wasn't updated

4. **Server Configuration Issue**
   - Remote server `FKMHST` has restricted authentication
   - `DB2NT` (the target auth ID) is not valid on the remote server

## Severity Assessment

### Is This Critical?

**Usually NO** - This error indicates a user configuration issue, not a system failure:

| Factor | Assessment |
|--------|------------|
| **User-Specific** | Only affects users without proper mapping |
| **No Data Loss** | Query fails but no corruption occurs |
| **Application Handles** | Well-designed apps retry or fail gracefully |
| **Transient Possible** | May resolve if user mapping is fixed |

### When IS It Critical?

- **Many users affected** - If a system account used by many apps fails
- **Critical business process** - If the affected query is part of a critical workflow
- **Sustained failures** - If the same user fails repeatedly without resolution
- **Production batch jobs** - If batch processing depends on federated queries

## Current Alert Configuration

The `QPLEX-UserError` pattern is configured in `appsettings.json`:

```json
{
  "PatternId": "QPLEX-UserError",
  "Description": "Query Gateway QPLEX connection user mapping error",
  "Regex": "Query Gateway.*sqlqgGetUserOptions|can't get valid connected user name.*QPLEX",
  "Enabled": true,
  "Action": "Remap",
  "Level": "Warning",
  "MessageTemplate": "[{Instance}] [{Database}] QPLEX user mapping error for user {AuthId}",
  "Priority": 30,
  "MaxOccurrences": 6,
  "TimeWindowMinutes": 60,
  "AlsoLogToFile": true,
  "SuppressedChannels": []
}
```

### What This Does:

1. **Remap** - Changes severity from Error to Warning
2. **MaxOccurrences: 6** - Only alert if more than 6 errors per user in 60 minutes
3. **AlsoLogToFile: true** - Logs to SQL error log for later analysis
4. **MessageTemplate** - Creates readable message with user info

## Resolution Steps

### 1. Check Existing User Mappings

```sql
-- List all user mappings for the remote server
SELECT AUTHID, SERVERNAME, OPTION, SETTING
FROM SYSCAT.USEROPTIONS
WHERE SERVERNAME = 'FKMHST'
ORDER BY AUTHID;
```

### 2. Create User Mapping (If Missing)

```sql
-- Create user mapping for the affected user
CREATE USER MAPPING FOR BUTEIK03
  SERVER FKMHST
  OPTIONS (
    REMOTE_AUTHID 'REMOTE_USERNAME',
    REMOTE_PASSWORD 'REMOTE_PASSWORD'
  );
```

### 3. Verify Server Wrapper Configuration

```sql
-- Check server configuration
SELECT SERVERNAME, SERVERTYPE, WRAPNAME, SERVERVERSION
FROM SYSCAT.SERVERS
WHERE SERVERNAME = 'FKMHST';

-- Check wrapper status
SELECT * FROM SYSCAT.WRAPPERS;
```

### 4. Test Connection

```sql
-- Test federated connection
SELECT * FROM FKMHST.SCHEMA.TABLENAME
FETCH FIRST 1 ROW ONLY;
```

### 5. Check Remote Server Connectivity

```powershell
# Test network connectivity to remote DB2 server
Test-NetConnection -ComputerName <remote-server-ip> -Port 50000
```

## Monitoring Recommendations

### Current Thresholds

| Setting | Value | Rationale |
|---------|-------|-----------|
| MaxOccurrences | 6 | Allow some transient failures |
| TimeWindowMinutes | 60 | 1-hour window |
| Action | Remap | Downgrade from Error to Warning |

### Suggested Adjustments

For production environments with many users:

```json
{
  "MaxOccurrences": 10,
  "TimeWindowMinutes": 60,
  "SuppressedChannels": ["SMS"]
}
```

This allows:
- 10 user mapping errors per hour before alerting
- Suppresses SMS for these errors (file logging only)
- Still visible in dashboard for investigation

## Related Errors

| Pattern | Description | Severity |
|---------|-------------|----------|
| `QPLEX-UserError` | User mapping issues | Warning |
| `DRDAProbe10` | Federated SQL execution errors | Warning |
| `DRDAProbe20` | Federated connection errors | Warning |
| `SQL0530N` | Foreign key violations (federated) | Informational |

## Conclusion

The **QPLEX user mapping error** is a **LOW severity** operational issue that indicates:

- A specific user lacks proper federation configuration
- The query attempted by that user requires access to remote server `FKMHST`
- The current mapping (or lack thereof) doesn't allow authentication

**Action Required:**
1. If user `BUTEIK03` should have federated access → Create/fix user mapping
2. If user shouldn't use federated queries → Fix the application query
3. If sporadic and self-resolving → Monitor but no immediate action needed

The current alert configuration appropriately:
- ✅ Remaps Error to Warning
- ✅ Logs to file for audit trail
- ✅ Alerts only on sustained issues (>6/hour)
- ✅ Shows affected user in alert message

---

*Document created: 2026-01-27*
*Related to: ServerMonitor DB2 Diagnostic Monitoring*
*Pattern: QPLEX-UserError*
