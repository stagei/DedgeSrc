# DB2 Diagnostics Dashboard - Design Document

## Overview

This document outlines a design for extending the ServerMonitor Dashboard with comprehensive DB2 database monitoring capabilities. The goal is to provide real-time visibility into DB2 database health, performance, and configuration on monitored servers.

## Current State

The existing `Db2DiagMonitor` provides:
- **db2diag.log parsing** - Reads diagnostic log entries with pattern matching
- **Severity filtering** - Skip, remap, escalate based on configured patterns
- **SQL error logging** - Logs specific SQL errors to separate files
- **Alert generation** - Creates alerts from Error/Warning/Severe/Critical entries

The Dashboard currently shows:
- Severity distribution bar chart (Critical/Error/Warning/Event counts)
- Recent diagnostic log entries
- SQL Error Log file viewer (Monaco editor)

## Proposed Enhancements

### Phase 1: Database Instance Overview

Add real-time database instance status by executing DB2 commands from C#.

#### Data to Collect

| Metric | DB2 Command | Description |
|--------|-------------|-------------|
| Active Databases | `db2 list active databases` | Currently active databases |
| Database Directory | `db2 list db directory` | All cataloged databases |
| Instance Status | `db2 get instance` | Instance name and state |
| Instance Config | `db2 get dbm cfg` | Database Manager configuration |
| Database Config | `db2 get db cfg for <DBNAME>` | Per-database configuration |
| Node Directory | `db2 list node directory` | Remote node connections |

#### Key Configuration Parameters to Display

From `db2 get dbm cfg`:
```
DIAGLEVEL          - Diagnostic error capture level (0-4)
DIAGPATH           - Diagnostic data directory path
SVCENAME           - TCP/IP service name/port
NUMDB              - Maximum concurrent active databases
FEDERATED          - Federated database support
AUTHENTICATION     - Authentication method (KERBEROS, SERVER, etc.)
SYSADM_GROUP       - System admin group
INSTANCE_MEMORY    - Instance memory allocation
```

From `db2 get db cfg for <DBNAME>`:
```
LOGARCHMETH1       - Log archive method (OFF = not recoverable)
LOGPATH            - Active log file path
LOGBUFSZ           - Log buffer size
DATABASE_MEMORY    - Database memory pool
LOCKLIST           - Lock list memory
CATALOGCACHE_SZ    - Catalog cache size
SELF_TUNING_MEM    - Self-tuning memory enabled
BACKUP_PENDING     - Backup required
RECOVERY_PENDING   - Recovery required
ROLLFORWARD_PENDING - Roll forward required
```

### Phase 2: Database Health Metrics

#### Tablespace Monitoring

Query tablespace status using:
```sql
SELECT TBSP_NAME, TBSP_TYPE, TBSP_STATE, TBSP_TOTAL_SIZE_KB, 
       TBSP_USED_SIZE_KB, TBSP_FREE_SIZE_KB, TBSP_UTILIZATION_PERCENT
FROM TABLE(MON_GET_TABLESPACE('', -2)) AS T
```

#### Buffer Pool Statistics

```sql
SELECT BP_NAME, POOL_DATA_L_READS, POOL_DATA_P_READS,
       CASE WHEN POOL_DATA_L_READS > 0 
            THEN (POOL_DATA_L_READS - POOL_DATA_P_READS) * 100.0 / POOL_DATA_L_READS 
            ELSE 0 END AS HIT_RATIO
FROM TABLE(MON_GET_BUFFERPOOL('', -2)) AS T
```

#### Connection Information

```sql
SELECT APPLICATION_HANDLE, APPLICATION_NAME, CLIENT_HOSTNAME,
       SESSION_AUTH_ID, CONNECTION_START_TIME, UOW_START_TIME
FROM TABLE(MON_GET_CONNECTION(NULL, -2)) AS T
```

#### Lock Waits and Blocking Sessions

Use `MON_GET_APPL_LOCKWAIT` to find sessions waiting for locks (DB2 11.5/12.1 LUW):

```sql
-- Basic lock wait detection
SELECT * FROM TABLE(MON_GET_APPL_LOCKWAIT(NULL, -2)) AS T
WHERE LOCK_WAIT_START_TIME IS NOT NULL
```

**Detailed Blocking Session Query:**
```sql
-- Find blocking and blocked sessions with details (DB2 11.5/12.1)
SELECT 
    L.REQ_APPLICATION_HANDLE AS BLOCKED_HANDLE,
    L.HLD_APPLICATION_HANDLE AS BLOCKER_HANDLE,
    L.LOCK_MODE AS REQUESTED_MODE,
    L.LOCK_OBJECT_TYPE,
    L.TABSCHEMA,
    L.TABNAME,
    L.LOCK_WAIT_START_TIME,
    TIMESTAMPDIFF(2, CURRENT_TIMESTAMP - L.LOCK_WAIT_START_TIME) AS WAIT_TIME_SECONDS,
    -- Blocked session details
    REQ.SESSION_AUTH_ID AS BLOCKED_USER,
    REQ.CLIENT_HOSTNAME AS BLOCKED_HOST,
    REQ.APPLICATION_NAME AS BLOCKED_APP,
    -- Blocker session details
    HLD.SESSION_AUTH_ID AS BLOCKER_USER,
    HLD.CLIENT_HOSTNAME AS BLOCKER_HOST,
    HLD.APPLICATION_NAME AS BLOCKER_APP,
    HLD.UOW_START_TIME AS BLOCKER_UOW_START
FROM TABLE(MON_GET_APPL_LOCKWAIT(NULL, -2)) AS L
INNER JOIN TABLE(MON_GET_CONNECTION(NULL, -2)) AS REQ
    ON L.REQ_APPLICATION_HANDLE = REQ.APPLICATION_HANDLE
INNER JOIN TABLE(MON_GET_CONNECTION(NULL, -2)) AS HLD
    ON L.HLD_APPLICATION_HANDLE = HLD.APPLICATION_HANDLE
ORDER BY WAIT_TIME_SECONDS DESC
```

**Lock Wait Summary (count by blocker):**
```sql
-- Summary: Who is blocking the most?
SELECT 
    HLD.SESSION_AUTH_ID AS BLOCKER_USER,
    HLD.APPLICATION_NAME AS BLOCKER_APP,
    HLD.CLIENT_HOSTNAME AS BLOCKER_HOST,
    COUNT(*) AS BLOCKED_COUNT,
    MAX(TIMESTAMPDIFF(2, CURRENT_TIMESTAMP - L.LOCK_WAIT_START_TIME)) AS MAX_WAIT_SECONDS
FROM TABLE(MON_GET_APPL_LOCKWAIT(NULL, -2)) AS L
INNER JOIN TABLE(MON_GET_CONNECTION(NULL, -2)) AS HLD
    ON L.HLD_APPLICATION_HANDLE = HLD.APPLICATION_HANDLE
GROUP BY HLD.SESSION_AUTH_ID, HLD.APPLICATION_NAME, HLD.CLIENT_HOSTNAME
ORDER BY BLOCKED_COUNT DESC
```

### Phase 2.5: Session and Activity Monitoring (DB2 11.5/12.1 LUW)

> **Note:** These queries use the `MON_GET_*` table functions available in DB2 11.5 and 12.1 LUW.
> The API is stable across these versions. Always connect to a database first to run these queries.

#### Long-Running SQL Statements

Use `MON_GET_ACTIVITY` to find currently executing SQL statements with their elapsed time:

```sql
-- Get currently running SQL statements ordered by elapsed time (DB2 11.5/12.1)
SELECT 
    A.APPLICATION_HANDLE,
    A.UOW_ID,
    A.ACTIVITY_ID,
    A.ACTIVITY_TYPE,
    A.ACTIVITY_STATE,
    A.LOCAL_START_TIME,
    TIMESTAMPDIFF(2, CURRENT_TIMESTAMP - A.LOCAL_START_TIME) AS ELAPSED_SECONDS,
    A.SESSION_AUTH_ID AS USER_ID,
    SUBSTR(A.STMT_TEXT, 1, 500) AS SQL_TEXT,
    A.ROWS_READ,
    A.ROWS_RETURNED,
    A.TOTAL_CPU_TIME / 1000 AS CPU_TIME_MS,
    C.CLIENT_HOSTNAME,
    C.APPLICATION_NAME
FROM TABLE(MON_GET_ACTIVITY(NULL, -2)) AS A
LEFT JOIN TABLE(MON_GET_CONNECTION(NULL, -2)) AS C
    ON A.APPLICATION_HANDLE = C.APPLICATION_HANDLE
WHERE A.ACTIVITY_STATE = 'EXECUTING'
  AND TIMESTAMPDIFF(2, CURRENT_TIMESTAMP - A.LOCAL_START_TIME) > 5  -- > 5 seconds
ORDER BY ELAPSED_SECONDS DESC
FETCH FIRST 20 ROWS ONLY
```

Alternative using `MON_GET_PKG_CACHE_STMT` for historical expensive queries:
```sql
-- Most expensive SQL statements by execution time (cached in package cache)
SELECT 
    SUBSTR(STMT_TEXT, 1, 500) AS SQL_TEXT,
    NUM_EXECUTIONS,
    TOTAL_ACT_TIME / 1000 AS TOTAL_TIME_MS,
    CASE WHEN NUM_EXECUTIONS > 0 
         THEN (TOTAL_ACT_TIME / NUM_EXECUTIONS) / 1000 
         ELSE 0 END AS AVG_TIME_MS,
    ROWS_READ,
    ROWS_RETURNED
FROM TABLE(MON_GET_PKG_CACHE_STMT(NULL, NULL, NULL, -2)) AS S
WHERE NUM_EXECUTIONS > 0
ORDER BY TOTAL_ACT_TIME DESC
FETCH FIRST 10 ROWS ONLY
```

#### Active Sessions Count (Total Connections)

```sql
-- Total active sessions/connections
SELECT COUNT(*) AS TOTAL_SESSIONS
FROM TABLE(MON_GET_CONNECTION(NULL, -2)) AS C
```

With breakdown by state:
```sql
-- Sessions by connection state
SELECT 
    CONNECTION_STATE,
    COUNT(*) AS SESSION_COUNT
FROM TABLE(MON_GET_CONNECTION(NULL, -2)) AS C
GROUP BY CONNECTION_STATE
```

#### Unique Logged-In Users Count

```sql
-- Count of unique authenticated users
SELECT COUNT(DISTINCT SESSION_AUTH_ID) AS UNIQUE_USERS
FROM TABLE(MON_GET_CONNECTION(NULL, -2)) AS C
```

With user list:
```sql
-- List of connected users with session count
SELECT 
    SESSION_AUTH_ID AS USER_ID,
    COUNT(*) AS SESSION_COUNT,
    MIN(CONNECTION_START_TIME) AS FIRST_CONNECTION,
    MAX(CONNECTION_START_TIME) AS LAST_CONNECTION
FROM TABLE(MON_GET_CONNECTION(NULL, -2)) AS C
GROUP BY SESSION_AUTH_ID
ORDER BY SESSION_COUNT DESC
```

#### Combined Session Summary Query

```sql
-- Single query for dashboard counters
SELECT 
    COUNT(*) AS TOTAL_SESSIONS,
    COUNT(DISTINCT SESSION_AUTH_ID) AS UNIQUE_USERS,
    SUM(CASE WHEN CONNECTION_STATE = 'CONNECTED' THEN 1 ELSE 0 END) AS CONNECTED,
    SUM(CASE WHEN CONNECTION_STATE = 'EXECUTING' THEN 1 ELSE 0 END) AS EXECUTING,
    SUM(CASE WHEN CONNECTION_STATE = 'WAITING' THEN 1 ELSE 0 END) AS WAITING
FROM TABLE(MON_GET_CONNECTION(NULL, -2)) AS C
```

### Phase 2.6: Today's Diagnostic Log Summary

Use the existing `Db2DiagMonitor` data to aggregate today's entries by severity.

#### From Existing Db2DiagData

The `Db2DiagMonitor` already parses `db2diag.log` files and stores entries. We can add summary counters:

```csharp
public class Db2DiagSummary
{
    public DateTime Date { get; set; }
    public int TotalEvents { get; set; }
    public int CriticalCount { get; set; }
    public int SevereCount { get; set; }
    public int ErrorCount { get; set; }
    public int WarningCount { get; set; }
    public int EventCount { get; set; }
    public int InfoCount { get; set; }
}

// In Db2DiagMonitor, add method to get today's summary:
public Db2DiagSummary GetTodaysSummary()
{
    var today = DateTime.Today;
    var todayEntries = _allEntries
        .Where(e => e.TimestampParsed?.Date == today)
        .ToList();
    
    return new Db2DiagSummary
    {
        Date = today,
        TotalEvents = todayEntries.Count,
        CriticalCount = todayEntries.Count(e => e.Level == "Critical"),
        SevereCount = todayEntries.Count(e => e.Level == "Severe"),
        ErrorCount = todayEntries.Count(e => e.Level == "Error"),
        WarningCount = todayEntries.Count(e => e.Level == "Warning"),
        EventCount = todayEntries.Count(e => e.Level == "Event"),
        InfoCount = todayEntries.Count(e => e.Level == "Info")
    };
}
```

#### Dashboard Display for Diag Summary

```
┌─────────────────────────────────────────────────────────────────────────────┐
│ 📊 Today's Diagnostics (2026-01-25)                                        │
├─────────────────────────────────────────────────────────────────────────────┤
│                                                                             │
│  🔴 Critical: 0    🟠 Severe: 0    ❌ Errors: 5    ⚠️ Warnings: 12         │
│                                                                             │
│  ℹ️ Events: 45     📝 Total: 62                                            │
│                                                                             │
└─────────────────────────────────────────────────────────────────────────────┘
```

### Phase 3: Federation Status (If Applicable)

Query federation wrappers and server links:
```sql
SELECT * FROM SYSCAT.WRAPPERS
SELECT SERVERNAME FROM SYSCAT.SERVERS
SELECT * FROM SYSCAT.USEROPTIONS
```

## C# Implementation Approach

### Executing DB2 Commands from C#

Based on the Db2-Handler.psm1 patterns, there are two main approaches:

#### Approach 1: db2cmd Process Execution

```csharp
public class Db2CommandExecutor
{
    private readonly ILogger<Db2CommandExecutor> _logger;
    private readonly string _db2CmdPath;
    
    public Db2CommandExecutor(ILogger<Db2CommandExecutor> logger)
    {
        _logger = logger;
        _db2CmdPath = FindDb2CmdPath();
    }
    
    public async Task<Db2CommandResult> ExecuteCommandAsync(
        string instanceName,
        string command,
        CancellationToken cancellationToken = default)
    {
        // Create temp batch file with commands
        var tempBatFile = Path.GetTempFileName() + ".bat";
        var tempOutFile = Path.ChangeExtension(tempBatFile, ".out");
        var tempErrFile = Path.ChangeExtension(tempBatFile, ".err");
        
        try
        {
            // Build batch content
            var batContent = $@"@echo off
set DB2INSTANCE={instanceName}
{command} >> ""{tempOutFile}"" 2>> ""{tempErrFile}""
";
            await File.WriteAllTextAsync(tempBatFile, batContent, cancellationToken);
            
            // Execute via db2cmd
            var process = new Process
            {
                StartInfo = new ProcessStartInfo
                {
                    FileName = _db2CmdPath,
                    Arguments = $"/c /w /i \"{tempBatFile}\"",
                    UseShellExecute = false,
                    CreateNoWindow = true,
                    RedirectStandardOutput = true,
                    RedirectStandardError = true
                }
            };
            
            process.Start();
            await process.WaitForExitAsync(cancellationToken);
            
            // Read output (DB2 uses IBM-1252 encoding)
            var outputBytes = await File.ReadAllBytesAsync(tempOutFile, cancellationToken);
            var output = Encoding.GetEncoding(1252).GetString(outputBytes);
            
            var errorOutput = File.Exists(tempErrFile) 
                ? await File.ReadAllTextAsync(tempErrFile, cancellationToken) 
                : "";
            
            return new Db2CommandResult
            {
                Success = process.ExitCode == 0 && !HasSqlError(output),
                Output = output,
                ErrorOutput = errorOutput,
                ExitCode = process.ExitCode
            };
        }
        finally
        {
            // Cleanup temp files
            TryDeleteFile(tempBatFile);
            TryDeleteFile(tempOutFile);
            TryDeleteFile(tempErrFile);
        }
    }
    
    private string FindDb2CmdPath()
    {
        var candidates = new[]
        {
            @"C:\DbInst\BIN\db2cmd.exe",
            @"C:\Program Files\IBM\SQLLIB\BIN\db2cmd.exe",
            Environment.ExpandEnvironmentVariables(@"%DB2PATH%\BIN\db2cmd.exe")
        };
        
        return candidates.FirstOrDefault(File.Exists) 
            ?? throw new FileNotFoundException("db2cmd.exe not found");
    }
    
    private bool HasSqlError(string output)
    {
        // Check for SQL error codes: SQLxxxx, DB2xxxx
        return Regex.IsMatch(output, @"SQL\d{4,5}[A-Z]") &&
               !output.Contains("SQL0000W"); // Success code
    }
}
```

#### Approach 2: IBM.Data.DB2 ADO.NET Provider

For SQL queries, use the IBM Data Server Provider:

```csharp
using IBM.Data.DB2;

public class Db2QueryExecutor
{
    public async Task<DataTable> ExecuteQueryAsync(
        string connectionString,
        string sql,
        CancellationToken cancellationToken = default)
    {
        using var connection = new DB2Connection(connectionString);
        await connection.OpenAsync(cancellationToken);
        
        using var command = new DB2Command(sql, connection);
        using var adapter = new DB2DataAdapter(command);
        
        var dataTable = new DataTable();
        adapter.Fill(dataTable);
        
        return dataTable;
    }
}
```

**Connection String Examples:**
```
# Local database
Database=FKMPRD;

# With credentials
Database=FKMPRD;User ID=db2admin;Password=xxx;

# Remote
Server=hostname:50000;Database=FKMPRD;
```

### Data Model

```csharp
public class Db2InstanceStatus
{
    public string InstanceName { get; set; }
    public bool IsRunning { get; set; }
    public string DiagPath { get; set; }
    public int DiagLevel { get; set; }
    public string ServicePort { get; set; }
    public string Authentication { get; set; }
    public List<Db2DatabaseStatus> Databases { get; set; }
}

public class Db2DatabaseStatus
{
    public string DatabaseName { get; set; }
    public string Alias { get; set; }
    public bool IsActive { get; set; }
    public bool IsRecoverable { get; set; }
    public bool BackupPending { get; set; }
    public bool RollforwardPending { get; set; }
    public long DatabaseMemoryKB { get; set; }
    public DateTime? LastBackupTime { get; set; }
    public List<Db2TablespaceStatus> Tablespaces { get; set; }
    public Db2BufferPoolStats BufferPoolStats { get; set; }
    
    // Session/Activity Metrics
    public int TotalSessions { get; set; }
    public int UniqueUsers { get; set; }
    public int ExecutingSessions { get; set; }
    public int WaitingSessions { get; set; }
    public List<Db2LongRunningQuery> LongRunningQueries { get; set; }
    public List<Db2BlockingSession> BlockingSessions { get; set; }
}

public class Db2LongRunningQuery
{
    public long ApplicationHandle { get; set; }
    public string UserId { get; set; }
    public string ClientHostname { get; set; }
    public string ApplicationName { get; set; }
    public DateTime StartTime { get; set; }
    public int ElapsedSeconds { get; set; }
    public string SqlText { get; set; }  // Truncated to 500 chars
    public long RowsRead { get; set; }
    public long RowsReturned { get; set; }
    public long CpuTimeMs { get; set; }
}

public class Db2DiagSummary
{
    public DateTime Date { get; set; }
    public int TotalEvents { get; set; }
    public int CriticalCount { get; set; }
    public int SevereCount { get; set; }
    public int ErrorCount { get; set; }
    public int WarningCount { get; set; }
    public int EventCount { get; set; }
    public int InfoCount { get; set; }
}

public class Db2BlockingSession
{
    // Blocked session info
    public long BlockedHandle { get; set; }
    public string BlockedUser { get; set; }
    public string BlockedHost { get; set; }
    public string BlockedApp { get; set; }
    
    // Blocker session info
    public long BlockerHandle { get; set; }
    public string BlockerUser { get; set; }
    public string BlockerHost { get; set; }
    public string BlockerApp { get; set; }
    public DateTime? BlockerUowStart { get; set; }
    
    // Lock details
    public string LockMode { get; set; }
    public string LockObjectType { get; set; }
    public string TableSchema { get; set; }
    public string TableName { get; set; }
    public DateTime LockWaitStartTime { get; set; }
    public int WaitTimeSeconds { get; set; }
}

public class Db2TablespaceStatus
{
    public string Name { get; set; }
    public string Type { get; set; } // SMS, DMS, AUTOMATIC
    public string State { get; set; }
    public long TotalSizeKB { get; set; }
    public long UsedSizeKB { get; set; }
    public long FreeSizeKB { get; set; }
    public double UtilizationPercent { get; set; }
}

public class Db2BufferPoolStats
{
    public string PoolName { get; set; }
    public long LogicalReads { get; set; }
    public long PhysicalReads { get; set; }
    public double HitRatio { get; set; }
}
```

### Configuration

Add to `appsettings.json`:

```json
{
  "Db2DiagMonitoring": {
    "InstanceMonitoring": {
      "Enabled": true,
      "CollectionIntervalSeconds": 300,
      "InstanceNames": ["db2inst1"],
      "CollectDatabaseConfig": true,
      "CollectTablespaceInfo": true,
      "CollectBufferPoolStats": true,
      "CollectConnectionInfo": true,
      "CollectLongRunningQueries": true,
      "TablespaceUtilizationWarningPercent": 80,
      "TablespaceUtilizationCriticalPercent": 95,
      "BufferPoolHitRatioWarningPercent": 90,
      "LongRunningQueryThresholdSeconds": 5,
      "LongRunningQueryWarningSeconds": 300,
      "LongRunningQueryCriticalSeconds": 1800,
      "MaxLongRunningQueriesToShow": 20,
      "SessionCountWarningThreshold": 50,
      "DiagErrorsTodayWarningThreshold": 10,
      "CollectBlockingSessions": true,
      "LockWaitWarningSeconds": 30,
      "LockWaitCriticalSeconds": 300,
      "MaxBlockingSessionsToShow": 20
    }
  }
}
```

## Dashboard UI Design

### Enhanced DB2 Panel Layout

```
┌────────────────────────────────────────────────────────────────────────────┐
│ 🗄️ DB2 Diagnostics                                                        │
├────────────────────────────────────────────────────────────────────────────┤
│                                                                            │
│  ┌──────────────┐  ┌──────────────┐  ┌──────────────┐  ┌──────────────┐   │
│  │ 🗄️ DB2INST1 │  │ 📊 2        │  │ 👥 8 Users  │  │ 🔌 12        │   │
│  │   Instance   │  │  Databases   │  │   Connected  │  │  Sessions    │   │
│  └──────────────┘  └──────────────┘  └──────────────┘  └──────────────┘   │
│                                                                            │
│  ┌─────────────────────────────────────────────────────────────────────┐  │
│  │ 📊 Today's Diagnostics (2026-01-25)                                  │  │
│  │                                                                       │  │
│  │  🔴 Critical: 0   🟠 Severe: 0   ❌ Errors: 5   ⚠️ Warnings: 12     │  │
│  │  ℹ️ Events: 45    📝 Total: 62                                       │  │
│  └─────────────────────────────────────────────────────────────────────┘  │
│                                                                            │
│  ┌─────────────────────────────────────────────────────────────────────┐  │
│  │ 📁 Databases                                                         │  │
│  ├───────────┬──────────┬─────────┬─────────┬───────────────────────────┤  │
│  │ Name      │ Status   │ Users   │Sessions │ Tablespace Usage          │  │
│  ├───────────┼──────────┼─────────┼─────────┼───────────────────────────┤  │
│  │ XFKMPRD   │ 🟢 Active│ 6       │ 9       │ ████████░░ 78%            │  │
│  │ XFKMNPD   │ 🟢 Active│ 2       │ 3       │ ██████░░░░ 62%            │  │
│  └───────────┴──────────┴─────────┴─────────┴───────────────────────────┘  │
│                                                                            │
│  ┌─────────────────────────────────────────────────────────────────────┐  │
│  │ ⏱️ Long-Running Queries (> 5 sec)                                    │  │
│  ├───────────┬──────────┬───────────┬───────────────────────────────────┤  │
│  │ User      │ Duration │ Rows Read │ SQL                               │  │
│  ├───────────┼──────────┼───────────┼───────────────────────────────────┤  │
│  │ DBUSER1   │ 45s      │ 1.2M      │ SELECT * FROM LARGE_TABLE WHE... │  │
│  │ APPUSER   │ 12s      │ 250K      │ UPDATE INVENTORY SET QUAN...     │  │
│  └───────────┴──────────┴───────────┴───────────────────────────────────┘  │
│                                                                            │
│  ┌─────────────────────────────────────────────────────────────────────┐  │
│  │ 🔒 Blocking Sessions (Lock Waits)                                    │  │
│  ├──────────────────────────┬───────────────────────────────────────────┤  │
│  │ Blocker                  │ Blocked                                   │  │
│  ├───────────┬──────────────┼───────────┬───────────┬───────────────────┤  │
│  │ User      │ App          │ User      │ Wait Time │ Table             │  │
│  ├───────────┼──────────────┼───────────┼───────────┼───────────────────┤  │
│  │ BATCHUSER │ db2bp.exe    │ APPUSER   │ 32s       │ ORDERS            │  │
│  │ DBADMIN   │ Data Studio  │ DBUSER1   │ 8s        │ INVENTORY         │  │
│  └───────────┴──────────────┴───────────┴───────────┴───────────────────┘  │
│                                                                            │
│  ┌─────────────────────────────────────────────────────────────────────┐  │
│  │ 💾 Buffer Pool Hit Ratio                                             │  │
│  │                                                                       │  │
│  │  IBMDEFAULTBP    ████████████████████████████░░░ 96.3%              │  │
│  │  BP32K           ████████████████████████████░░░ 94.8%              │  │
│  └─────────────────────────────────────────────────────────────────────┘  │
│                                                                            │
│  ┌───────────────────────────────────┬─────────────────────────────────┐  │
│  │ 🔔 Recent Diagnostic Entries      │ 📄 SQL Error Logs              │  │
│  ├───────────┬───────────┬───────────┼─────────────────────────────────┤  │
│  │ Level     │ Time      │ Message   │ p-no1fkmprd-db_20260125_...     │  │
│  ├───────────┼───────────┼───────────┤ p-no1fkmprd-db_20260124_...     │  │
│  │ ⚠️ Warning│ 14:23:45  │ QPLEX... │ p-no1fkmprd-db_20260123_...     │  │
│  │ ℹ️ Event  │ 14:20:12  │ Auto...  │                                 │  │
│  └───────────┴───────────┴───────────┴─────────────────────────────────┘  │
│                                                                            │
└────────────────────────────────────────────────────────────────────────────┘
```

### Expandable Database Details

Clicking a database row expands to show:
- Tablespace breakdown with usage bars
- Buffer pool statistics
- Recent connections
- Configuration highlights

## Alerts to Generate

| Condition | Severity | Message |
|-----------|----------|---------|
| Tablespace > 95% full | Critical | Tablespace {name} is {pct}% full |
| Tablespace > 80% full | Warning | Tablespace {name} is {pct}% full |
| Buffer pool hit ratio < 90% | Warning | Buffer pool {name} hit ratio is {pct}% |
| Database backup pending | Warning | Database {name} has backup pending |
| Recovery pending | Critical | Database {name} requires recovery |
| Rollforward pending | Critical | Database {name} requires rollforward |
| Instance not running | Critical | DB2 instance {name} is not running |
| Log archive failure | Critical | Log archive failed for {database} |
| Query running > 5 min | Warning | Long-running query by {user}: {elapsed} min |
| Query running > 30 min | Critical | Query blocked by {user} for {elapsed} min |
| High session count (> threshold) | Warning | {count} active sessions on {database} |
| Diag errors today > threshold | Warning | {count} errors in db2diag.log today |
| Lock wait > 30 sec | Warning | {blocked_user} waiting {elapsed}s for lock held by {blocker_user} on {table} |
| Lock wait > 5 min | Critical | Blocking session: {blocker_user} blocking {count} sessions for {elapsed} min |

## Implementation Phases

### Phase 1 (MVP)
- [ ] Create `Db2InstanceMonitor` class
- [ ] Implement `Db2CommandExecutor` for running db2cmd
- [ ] Collect instance status and active databases
- [ ] Add to dashboard API endpoint
- [ ] Display basic instance/database info in dashboard
- [ ] Add today's diag log summary (events/errors/warnings count)

### Phase 2 (Enhanced Monitoring)
- [ ] Add tablespace monitoring via SQL
- [ ] Add buffer pool statistics
- [ ] Add session count and unique user count
- [ ] Add long-running SQL statements list
- [ ] Add blocking sessions / lock wait detection
- [ ] Create alerts for thresholds
- [ ] Add expandable database details in UI

### Phase 3 (Advanced)
- [ ] Federation server status
- [ ] Lock wait monitoring
- [ ] Transaction log monitoring
- [ ] Historical trend storage
- [ ] Performance recommendations
- [ ] Query execution history (from package cache)

## Security Considerations

1. **Credentials**: Use Windows authentication where possible (instance runs under service account)
2. **Process Execution**: Sanitize all parameters to prevent command injection
3. **Connection Strings**: Store credentials securely if needed
4. **Permissions**: Ensure service account has SYSMON authority minimum

## References

- [DB2 Command Reference](https://www.ibm.com/docs/en/db2)
- [MON_GET functions](https://www.ibm.com/docs/en/db2/11.5?topic=functions-mon-get-tablespace)
- [SYSCAT views](https://www.ibm.com/docs/en/db2/11.5?topic=views-catalog)
- Db2-Handler.psm1 - `C:\opt\src\DedgePsh\_Modules\Db2-Handler\Db2-Handler.psm1`

## Appendix: Useful DB2 Commands from Db2-Handler

```powershell
# Set instance
set DB2INSTANCE=db2inst1

# Start/Stop instance
db2start
db2stop force

# List databases
db2 list active databases
db2 list db directory

# Database configuration
db2 get db cfg for DBNAME
db2 get dbm cfg

# Instance registry
db2set -i INSTANCENAME -all

# Activate/Deactivate
db2 activate database DBNAME
db2 deactivate database DBNAME

# Node directory (federation)
db2 list node directory

# Check recoverability
db2 get database configuration for DBNAME | findstr "LOGARCHMETH1"
```
