# DB2 Utility Monitoring and History Guide

**Version:** DB2 11.5 / 12.1 for Linux, UNIX and Windows  
**Source:** IBM Documentation

This document covers DB2 commands for monitoring currently running utilities and viewing historical utility job logs.

---

## Table of Contents

1. [LIST UTILITIES Command](#list-utilities-command)
2. [LIST HISTORY Command](#list-history-command)
3. [db2pd Monitoring Tool](#db2pd-monitoring-tool)
4. [db2diag Log Analysis Tool](#db2diag-log-analysis-tool)
5. [SYSIBMADM.DB_HISTORY View](#sysibmadmdb_history-view)
6. [Quick Reference](#quick-reference)

---

## LIST UTILITIES Command

Monitors **currently running** utility operations. Once a utility completes, it will no longer appear.

### Command Syntax

```
>>-LIST UTILITIES--+-------------+----------------------------><
                   '-SHOW DETAIL-'
```

### Command Parameters

| Parameter | Description |
|-----------|-------------|
| `SHOW DETAIL` | Shows detailed progress information including phase, percentage complete, and estimated time remaining |

### Usage Examples

```bash
# List all running utilities (summary)
db2 LIST UTILITIES

# List all running utilities with detailed progress
db2 LIST UTILITIES SHOW DETAIL
```

### Example Output

```
ID                               = 1
Type                             = BACKUP
Database Name                    = SAMPLE
Member Number                    = 0
Description                      = offline db
Start Time                       = 01/30/2026 14:22:35.482910
State                            = Executing
Invocation Type                  = User
Throttling:
   Priority                      = Unthrottled
Progress Monitoring:
   Estimated Percentage Complete = 45
   Total Work                    = 892741632 bytes
   Completed Work                = 401233784 bytes
   Start Time                    = 01/30/2026 14:22:35.527462
```

### Supported Utility Types

- **BACKUP** - Database and tablespace backups
- **RESTORE** - Database and tablespace restores
- **ROLLFORWARD** - Rollforward recovery operations
- **REORG** - Table and index reorganization
- **REBALANCE** - Tablespace rebalancing
- **RUNSTATS** - Statistics collection
- **LOAD** - Data load operations
- **REDISTRIBUTE** - Data redistribution
- **CRASH RECOVERY** - Automatic crash recovery

### Alternative: db2pd -util

```bash
db2pd -util
```

---

## LIST HISTORY Command

Lists entries from the **database history records** containing recovery and administrative events.

### Command Syntax

```
>>-LIST HISTORY--+---------+--+-----+--+-----------------------------+-->
                 +-BACKUP--+  +-ALL-+  +-SINCE timestamp-------------+
                 +-ROLLFORWARD-+      +-CONTAINING schema.object_name-+
                 +-DROPPED TABLE-+    '-CONTAINING object_name--------'
                 +-LOAD----+
                 +-CREATE TABLESPACE-+
                 +-ALTER TABLESPACE-+
                 +-RENAME TABLESPACE-+
                 +-REORG--+
                 '-ARCHIVE LOG-'

>--FOR--+-DATABASE-+--database-alias---------------------------><
        '-DB-------'
```

### Command Parameters

| Parameter | Description |
|-----------|-------------|
| `HISTORY` | Lists all recovery and administration events currently logged |
| `BACKUP` | Lists backup and restore operations |
| `ROLLFORWARD` | Lists rollforward operations |
| `DROPPED TABLE` | Lists dropped table records (requires DROPPED TABLE RECOVERY enabled) |
| `LOAD` | Lists load operations |
| `CREATE TABLESPACE` | Lists tablespace create and drop operations |
| `ALTER TABLESPACE` | Lists alter tablespace operations |
| `RENAME TABLESPACE` | Lists tablespace renaming operations |
| `REORG` | Lists reorganization operations |
| `ARCHIVE LOG` | Lists archive log operations |
| `ALL` | Lists all entries of the specified type |
| `SINCE timestamp` | Format `yyyymmddhhmmss` (minimum prefix: `yyyy`). Lists entries with timestamps >= provided |
| `CONTAINING schema.object_name` | Qualified name identifying a specific table |
| `CONTAINING object_name` | Unqualified name identifying a tablespace |
| `FOR DATABASE database-alias` | Identifies the database whose history to list |

### Authorization

None required.

### Required Connection

Instance attachment (explicit attachment required for remote databases).

### Usage Examples

```bash
# List all history entries
db2 LIST HISTORY ALL FOR DATABASE sample

# List backup operations only
db2 LIST HISTORY BACKUP ALL FOR DATABASE sample

# List entries since a specific date (format: yyyymmdd)
db2 LIST HISTORY SINCE 20260101 FOR sample

# List entries since specific timestamp (format: yyyymmddhhmmss)
db2 LIST HISTORY ALL SINCE 20260130143000 FOR DATABASE sample

# List backup operations containing specific tablespace
db2 LIST HISTORY BACKUP CONTAINING userspace1 FOR sample

# List dropped tables
db2 LIST HISTORY DROPPED TABLE ALL FOR DB sample

# List reorg operations
db2 LIST HISTORY REORG ALL FOR DATABASE sample

# List archive log operations
db2 LIST HISTORY ARCHIVE LOG ALL FOR DATABASE sample

# Run on all database partitions
db2_all "db2 LIST HISTORY SINCE 20260101 FOR sample"
```

### Example Output

```
                         List History File for sample

Number of matching file entries = 2

 Op Obj Timestamp+Sequence Type Dev Earliest Log Current Log  Backup ID
 -- --- ------------------ ---- --- ------------ ------------ --------------
  L  T  20260130133005001    R    S  S0000000.LOG S0000000.LOG
 ----------------------------------------------------------------------------
 "USERNAME"."T1" resides in 1 tablespace(s):
 00001 USERSPACE1
 ----------------------------------------------------------------------------
 Comment: DB2 LOAD
 Start Time: 20260130133005
 End Time: 20260130133006
 Status: A
 ----------------------------------------------------------------------------
 EID: 3 Location: /home/db2inst1/mydatafile.del

 Op Obj Timestamp+Sequence Type Dev Earliest Log Current Log  Backup ID
 -- --- ------------------ ---- --- ------------ ------------ --------------
  B  D  20260130135509001    F    D  S0000000.LOG S0000000.LOG
 ----------------------------------------------------------------------------
 Contains 2 tablespace(s):
 00001 SYSCATSPACE
 00002 USERSPACE1
 ----------------------------------------------------------------------------
 Comment: DB2 BACKUP SAMPLE OFFLINE
 Start Time: 20260130135509
 End Time: 20260130135512
 Status: A
 ----------------------------------------------------------------------------
 EID: 4 Location: /home/db2inst1/backups
```

### Output Symbol Reference

#### Operation Codes (Op)

| Code | Operation |
|------|-----------|
| A | Create tablespace |
| B | Backup |
| C | Load copy |
| D | Drop table |
| F | Rollforward |
| G | Reorganize |
| L | Load |
| N | Rename tablespace |
| O | Drop tablespace |
| Q | Quiesce |
| R | Restore |
| T | Alter tablespace |
| U | Unload |
| X | Archive log |

#### Object Codes (Obj)

| Code | Object |
|------|--------|
| D | Database |
| I | Index |
| P | Tablespace |
| T | Table |
| R | Partitioned table |

#### Type Codes

**Backup/Restore Types:**

| Code | Type |
|------|------|
| D | Delta offline |
| E | Delta online |
| F | Offline |
| I | Incremental offline |
| M | Merged |
| N | Online |
| O | Incremental online |
| R | Rebuild |

**Load Types:**

| Code | Type |
|------|------|
| I | Insert |
| R | Replace |

**Rollforward Types:**

| Code | Type |
|------|------|
| E | End of logs |
| P | Point-in-time |

**Archive Log Types:**

| Code | Type |
|------|------|
| F | Failover archive path |
| M | Secondary (mirror) log path |
| N | Archive log command |
| P | Primary log path |
| 1 | Primary log archive method |
| 2 | Secondary log archive method |

**Alter Tablespace Types:**

| Code | Type |
|------|------|
| C | Add container |
| R | Rebalance |

**Quiesce Types:**

| Code | Type |
|------|------|
| S | Quiesce share |
| U | Quiesce update |
| X | Quiesce exclusive |
| Z | Quiesce reset |

#### Device Codes (Dev)

| Code | Device |
|------|--------|
| A | ADSM (TSM) |
| D | Disk |
| K | Diskette |
| O | Other |
| T | Tape |
| U | User Exit |

#### Status Codes

| Code | Status |
|------|--------|
| A | Active |
| D | Deleted |
| E | Expired |
| I | Inactive |
| N | Not yet committed |
| P | Pending delete |
| X | Do not delete |
| a | Incomplete active |
| i | Incomplete inactive |

---

## db2pd Monitoring Tool

The `db2pd` tool provides non-intrusive monitoring without using significant engine resources.

### General Syntax

```
db2pd [options]
```

### Utility Monitoring Options

| Command | Description |
|---------|-------------|
| `db2pd -util` | Monitor all running utilities |
| `db2pd -db <dbname> -util` | Monitor utilities for specific database |
| `db2pd -db <dbname> -reorg` | Monitor table reorganization |
| `db2pd -db <dbname> -reorg index` | Monitor index reorganization |
| `db2pd -db <dbname> -runstats` | Monitor runstats operations |
| `db2pd -db <dbname> -rec` | Monitor crash recovery / rollforward |
| `db2pd -load -alldbs` | Monitor load operations across all databases |

### Usage Examples

```bash
# Monitor all utilities
db2pd -util

# Monitor reorg for specific database
db2pd -db SAMPLE -reorg

# Monitor crash recovery
db2pd -db SAMPLE -rec

# Monitor runstats
db2pd -db SAMPLE -runstats

# Monitor load operations
db2pd -load -alldbs
```

### Monitoring Commands by Operation

| Operation | Primary Command | Alternative |
|-----------|-----------------|-------------|
| Crash Recovery | `db2pd -rec -db <dbname>` | `db2pd -util` |
| Rollforward | `db2pd -rec -db <dbname>` | `db2 LIST UTILITIES SHOW DETAIL` |
| Backup/Restore | `db2 LIST UTILITIES SHOW DETAIL` | `db2pd -util` |
| Reorg | `db2pd -db <dbname> -reorg` | `db2pd -db <dbname> -reorg index` |
| Rebalance | `db2 LIST UTILITIES SHOW DETAIL` | `db2pd -util` |
| Load | `db2pd -util` | `db2pd -load -alldbs` |
| Runstats | `db2pd -db <dbname> -runstats` | `db2pd -util` |
| Partition Detach | `db2 LIST UTILITIES SHOW DETAIL` | `db2pd -util` |

---

## db2diag Log Analysis Tool

The `db2diag` tool filters and analyzes DB2 diagnostic log files (`db2diag.log`).

### Command Syntax

```
db2diag [options] [filename...]
```

### Main Options

| Option | Description |
|--------|-------------|
| `-g "key=value"` | Filter by field (case-sensitive). Use `:=` for contains match |
| `-gi "key=value"` | Filter by field (case-insensitive) |
| `-gv "key=value"` | Filter by field, invert results |
| `-gvi "key=value"` | Filter by field, case-insensitive, invert results |
| `-level <level>` | Filter by severity: `Severe`, `Error`, `Warning`, `Event` |
| `-time <timestamp>` | Filter from timestamp onwards (format: `yyyy-mm-dd-hh.mm.ss`) |
| `-time <start>:<end>` | Filter within time range |
| `-n <nodes>` | Filter by partition/node numbers (comma-separated) |
| `-pid <pid>` | Filter by process ID |
| `-fmt "<format>"` | Custom output format using template variables |
| `-a <directory>` | Archive log file to specified directory |
| `-readfile <file>` | Read specific log file |

### Filter Field Names (for -g option)

| Field | Description |
|-------|-------------|
| `db` | Database name |
| `level` | Severity level |
| `pid` | Process ID |
| `tid` | Thread ID |
| `eduid` | EDU ID |
| `node` | Partition number |
| `instance` | Instance name |
| `function` | Function name |
| `message` or `msg` | Message text |
| `rc` | Return code (ZRC or ECF) |
| `apphdl` | Application handle |

### Format Template Variables (for -fmt option)

| Variable | Description |
|----------|-------------|
| `%{ts}` | Timestamp |
| `%{LEVEL}` | Severity level |
| `%{pid}` | Process ID |
| `%{TID}` | Thread ID |
| `%{Node}` | Partition number |
| `%{instance}` | Instance name |
| `%{msg}` | Message text |
| `%{db}` | Database name |

### Help Commands

```bash
db2diag -help        # Short description of all options
db2diag -h brief     # Descriptions without examples
db2diag -h notes     # Usage notes and restrictions
db2diag -h examples  # Example commands
db2diag -h tutorial  # Tutorial with all options
db2diag -h all       # Complete option list
```

### Usage Examples

```bash
# Filter by database name
db2diag -g "db=SAMPLE"

# Filter by severity level (case-sensitive!)
db2diag -level Severe
db2diag -g "level=Severe"

# Filter by process ID and severity
db2diag -g "level=Severe,pid=2200"

# Filter by time (entries from date onwards)
db2diag -time 2026-01-30

# Filter by time range
db2diag -time 2026-01-30-00.00.00:2026-01-31-00.00.00

# Filter by partitions
db2diag -n 0,1,2,3

# Filter messages containing keyword (use := for contains)
db2diag -g "msg:=BACKUP"
db2diag -gi "message:=reorg"

# Filter by return code (ZRC)
db2diag -g "rc=0x83000001"

# Custom formatted output
db2diag -fmt "Time: %{ts} Level: %{LEVEL} PID: %{pid} Message: %{msg}"

# Combine multiple filters
db2diag -time 2026-01-30 -level Severe -g "db=SAMPLE"

# Filter by application handle
db2diag -gi "apphdl=0-10"

# Find instance startup events
db2diag -gi "PROC=db2syscs.exe,LEVEL=Event,MESSAGE:=ADM7513W"

# Merge and sort multiple log files by timestamp
db2diag -merge db2diag.0.log db2diag.1.log

# Archive log file
db2diag -a /backup/db2logs
```

### Severity Levels

The `DIAGLEVEL` database manager configuration parameter controls logging:

| Level | Description |
|-------|-------------|
| 0 | No diagnostic data captured |
| 1 | Severe errors only |
| 2 | All errors |
| 3 | All errors and warnings (default) |
| 4 | All errors, warnings, and informational messages |

Check current setting:
```bash
db2 GET DBM CFG | find "DIAGLEVEL"
```

---

## SYSIBMADM.DB_HISTORY View

SQL-accessible view for querying database history with flexible filtering.

### Query Examples

```sql
-- All backup operations
SELECT * FROM SYSIBMADM.DB_HISTORY
WHERE OPERATION = 'B'
ORDER BY START_TIME DESC;

-- Backups since specific date
SELECT * FROM SYSIBMADM.DB_HISTORY
WHERE OPERATION = 'B'
  AND START_TIME > '2026-01-01-00.00.00'
ORDER BY START_TIME DESC;

-- Recent reorg operations
SELECT * FROM SYSIBMADM.DB_HISTORY
WHERE OPERATION = 'G'
ORDER BY START_TIME DESC
FETCH FIRST 10 ROWS ONLY;

-- All operations for specific tablespace
SELECT * FROM SYSIBMADM.DB_HISTORY
WHERE TBSPNAMES LIKE '%USERSPACE1%'
ORDER BY START_TIME DESC;

-- Failed operations
SELECT * FROM SYSIBMADM.DB_HISTORY
WHERE SQLCODE < 0
ORDER BY START_TIME DESC;

-- Backups since specific date (formatted query)
SELECT *
FROM SYSIBMADM.DB_HISTORY
WHERE OPERATION = 'B'  -- B=Backup
    AND START_TIME > '2026-01-01-00.00.00'
ORDER BY START_TIME DESC;

-- Latest operation of each type (most recent backup, reorg, load, etc.)
SELECT *
FROM SYSIBMADM.DB_HISTORY y 
JOIN (
    SELECT OPERATION, MAX(START_TIME) AS START_TIME
    FROM SYSIBMADM.DB_HISTORY
    WHERE START_TIME > '2026-01-01-00.00.00'
    GROUP BY OPERATION
) x ON y.START_TIME = x.START_TIME 
   AND y.OPERATION = x.OPERATION;
```

### Key Columns

| Column | Description |
|--------|-------------|
| `OPERATION` | Operation code (B, R, G, L, etc.) |
| `OPERATIONTYPE` | Type code (F, N, I, etc.) |
| `START_TIME` | Operation start timestamp |
| `END_TIME` | Operation end timestamp |
| `OBJECTTYPE` | Object type (D, T, P) |
| `SEQNUM` | Sequence number |
| `DEVICETYPE` | Device type code |
| `LOCATION` | Backup/archive location |
| `COMMENT` | Operation comment |
| `SQLCODE` | Return code |
| `TBSPNAMES` | Tablespace names involved |

---

## Quick Reference

| Need | Command |
|------|---------|
| Currently running utilities | `db2 LIST UTILITIES SHOW DETAIL` |
| Alternative: running utilities | `db2pd -util` |
| Historical backup operations | `db2 LIST HISTORY BACKUP ALL FOR DB <name>` |
| Historical reorg operations | `db2 LIST HISTORY REORG ALL FOR DB <name>` |
| Historical load operations | `db2 LIST HISTORY LOAD ALL FOR DB <name>` |
| All history since date | `db2 LIST HISTORY ALL SINCE yyyymmdd FOR DB <name>` |
| Monitor reorg progress | `db2pd -db <name> -reorg` |
| Monitor runstats progress | `db2pd -db <name> -runstats` |
| Monitor crash recovery | `db2pd -db <name> -rec` |
| SQL-based history query | `SELECT * FROM SYSIBMADM.DB_HISTORY` |
| Diagnostic log - severe errors | `db2diag -level Severe` |
| Diagnostic log - by database | `db2diag -g "db=SAMPLE"` |
| Diagnostic log - by time range | `db2diag -time start:end` |
| Diagnostic log help | `db2diag -h all` |

---

## Sample View: DB_HISTORY with Explanatory Comments

A sample view that translates all shortcodes into readable descriptions and calculates days since each operation.

### Actual SYSIBMADM.DB_HISTORY Columns

The view has these columns (for reference):

```sql
-- Actual column list from SYSIBMADM.DB_HISTORY:
-- dbpartitionnum, EID, start_time, seqnum, end_time, num_log_elems,
-- firstlog, lastlog, backup_id, tabschema, tabname,
-- comment, cmd_text, num_tbsps, tbspnames, operation,
-- operationtype, objecttype, location, devicetype, entry_status,
-- tenantname, total_size, seq_size, compression_library,
-- encrypted, include_logs,
-- sqlcaid, sqlcabc, sqlcode, sqlerrml, sqlerrmc, sqlerrp,
-- sqlerrd1, sqlerrd2, sqlerrd3, sqlerrd4, sqlerrd5, sqlerrd6,
-- sqlwarn, sqlstate
```

### Readable View Definition

**Code Reference:**

| Code Type | Code | Description |
|-----------|------|-------------|
| OPERATION | A | Create Tablespace - New tablespace created |
| | B | Backup - Database or tablespace backup |
| | C | Load Copy - Copy image from load operation |
| | D | Drop Table - Table was dropped |
| | F | Rollforward - Point-in-time recovery |
| | G | Reorganize - Table/index reorganization |
| | L | Load - Data load into table |
| | N | Rename Tablespace |
| | O | Drop Tablespace |
| | Q | Quiesce - Lock database/tablespace |
| | R | Restore - Database/tablespace restore |
| | T | Alter Tablespace - Configuration change |
| | U | Unload - Data export from table |
| | X | Archive Log - Transaction log archived |
| OBJECTTYPE | D | Database - Entire database |
| | I | Index - Database index |
| | P | Tablespace - Storage container |
| | T | Table - Database table |
| | R | Partitioned Table - Range-partitioned |
| DEVICETYPE | A | Tivoli Storage Manager (TSM/ADSM) |
| | D | Disk - Local or network storage |
| | K | Diskette - Floppy disk (legacy) |
| | O | Other - Vendor-specific device |
| | T | Tape - Magnetic tape storage |
| | U | User Exit - Custom backup program |
| ENTRY_STATUS | A | Active - Valid for recovery |
| | D | Deleted - Marked for removal |
| | E | Expired - Exceeded retention |
| | I | Inactive - No longer needed |
| | N | Not yet committed - In progress |
| | P | Pending delete - Scheduled removal |
| | X | Do not delete - Protected |
| | a | Incomplete active |
| | i | Incomplete inactive |

```sql
SELECT * from TV.V_DBQA_HISTORY_READABLE x order by DAYS_AGO;

DROP view TV.V_DBQA_HISTORY_READABLE;

CREATE OR REPLACE VIEW TV.V_DBQA_HISTORY_READABLE AS
SELECT
    START_TIME,
    END_TIME,
    DAYS(CURRENT DATE) - DAYS(DATE(START_TIME)) AS DAYS_AGO,
    EID,
    DBPARTITIONNUM,
    SEQNUM,
    OPERATION,
    CASE OPERATION
        WHEN 'A' THEN 'Create Tablespace'
        WHEN 'B' THEN 'Backup'
        WHEN 'C' THEN 'Load Copy'
        WHEN 'D' THEN 'Drop Table'
        WHEN 'F' THEN 'Rollforward'
        WHEN 'G' THEN 'Reorganize'
        WHEN 'L' THEN 'Load'
        WHEN 'N' THEN 'Rename Tablespace'
        WHEN 'O' THEN 'Drop Tablespace'
        WHEN 'Q' THEN 'Quiesce'
        WHEN 'R' THEN 'Restore'
        WHEN 'T' THEN 'Alter Tablespace'
        WHEN 'U' THEN 'Unload'
        WHEN 'X' THEN 'Archive Log'
        ELSE 'Unknown (' || OPERATION || ')'
    END AS OPERATION_SHORT_DESC,
    CASE OPERATION
        WHEN 'A' THEN 'Create Tablespace - New tablespace created'
        WHEN 'B' THEN 'Backup - Database or tablespace backup operation'
        WHEN 'C' THEN 'Load Copy - Copy image created during load operation'
        WHEN 'D' THEN 'Drop Table - Table was dropped from database'
        WHEN 'F' THEN 'Rollforward - Point-in-time recovery operation'
        WHEN 'G' THEN 'Reorganize - Table or index reorganization'
        WHEN 'L' THEN 'Load - Data load operation into table'
        WHEN 'N' THEN 'Rename Tablespace - Tablespace was renamed'
        WHEN 'O' THEN 'Drop Tablespace - Tablespace was dropped'
        WHEN 'Q' THEN 'Quiesce - Database or tablespace quiesce operation'
        WHEN 'R' THEN 'Restore - Database or tablespace restore operation'
        WHEN 'T' THEN 'Alter Tablespace - Tablespace configuration changed'
        WHEN 'U' THEN 'Unload - Data unload operation from table'
        WHEN 'X' THEN 'Archive Log - Transaction log archival'
        ELSE 'Unknown (' || OPERATION || ')'
    END AS OPERATION_DESC,
    OBJECTTYPE,
    CASE OBJECTTYPE
        WHEN 'D' THEN 'Database'
        WHEN 'I' THEN 'Index'
        WHEN 'P' THEN 'Tablespace'
        WHEN 'T' THEN 'Table'
        WHEN 'R' THEN 'Partitioned Table'
        ELSE 'Unknown (' || COALESCE(OBJECTTYPE, 'NULL') || ')'
    END AS OBJECTTYPE_SHORT_DESC,
    CASE OBJECTTYPE
        WHEN 'D' THEN 'Database - Entire database object'
        WHEN 'I' THEN 'Index - Database index object'
        WHEN 'P' THEN 'Tablespace - Storage container for tables'
        WHEN 'T' THEN 'Table - Database table object'
        WHEN 'R' THEN 'Partitioned Table - Range-partitioned table'
        ELSE 'Unknown (' || COALESCE(OBJECTTYPE, 'NULL') || ')'
    END AS OBJECTTYPE_DESC,
    OPERATIONTYPE,
    CASE 
        WHEN OPERATION IN ('B', 'R') AND OPERATIONTYPE = 'D' THEN 'Delta Offline'
        WHEN OPERATION IN ('B', 'R') AND OPERATIONTYPE = 'E' THEN 'Delta Online'
        WHEN OPERATION IN ('B', 'R') AND OPERATIONTYPE = 'F' THEN 'Full Offline'
        WHEN OPERATION IN ('B', 'R') AND OPERATIONTYPE = 'I' THEN 'Incremental Offline'
        WHEN OPERATION IN ('B', 'R') AND OPERATIONTYPE = 'M' THEN 'Merged'
        WHEN OPERATION IN ('B', 'R') AND OPERATIONTYPE = 'N' THEN 'Full Online'
        WHEN OPERATION IN ('B', 'R') AND OPERATIONTYPE = 'O' THEN 'Incremental Online'
        WHEN OPERATION IN ('B', 'R') AND OPERATIONTYPE = 'R' THEN 'Rebuild'
        WHEN OPERATION = 'L' AND OPERATIONTYPE = 'I' THEN 'Insert'
        WHEN OPERATION = 'L' AND OPERATIONTYPE = 'R' THEN 'Replace'
        WHEN OPERATION = 'F' AND OPERATIONTYPE = 'E' THEN 'End of Logs'
        WHEN OPERATION = 'F' AND OPERATIONTYPE = 'P' THEN 'Point-in-Time'
        WHEN OPERATION = 'X' AND OPERATIONTYPE = 'F' THEN 'Failover Archive'
        WHEN OPERATION = 'X' AND OPERATIONTYPE = 'M' THEN 'Mirror Log'
        WHEN OPERATION = 'X' AND OPERATIONTYPE = 'N' THEN 'Archive Command'
        WHEN OPERATION = 'X' AND OPERATIONTYPE = 'P' THEN 'Primary Log'
        WHEN OPERATION = 'X' AND OPERATIONTYPE = '1' THEN 'Primary Archive'
        WHEN OPERATION = 'X' AND OPERATIONTYPE = '2' THEN 'Secondary Archive'
        WHEN OPERATION = 'T' AND OPERATIONTYPE = 'C' THEN 'Add Container'
        WHEN OPERATION = 'T' AND OPERATIONTYPE = 'R' THEN 'Rebalance'
        WHEN OPERATION = 'Q' AND OPERATIONTYPE = 'S' THEN 'Quiesce Share'
        WHEN OPERATION = 'Q' AND OPERATIONTYPE = 'U' THEN 'Quiesce Update'
        WHEN OPERATION = 'Q' AND OPERATIONTYPE = 'X' THEN 'Quiesce Exclusive'
        WHEN OPERATION = 'Q' AND OPERATIONTYPE = 'Z' THEN 'Quiesce Reset'
        ELSE OPERATIONTYPE
    END AS OPERATIONTYPE_SHORT_DESC,
    CASE 
        WHEN OPERATION IN ('B', 'R') AND OPERATIONTYPE = 'D' THEN 'Delta Offline - Changes since last backup, database offline'
        WHEN OPERATION IN ('B', 'R') AND OPERATIONTYPE = 'E' THEN 'Delta Online - Changes since last backup, database online'
        WHEN OPERATION IN ('B', 'R') AND OPERATIONTYPE = 'F' THEN 'Full Offline - Complete backup, database offline'
        WHEN OPERATION IN ('B', 'R') AND OPERATIONTYPE = 'I' THEN 'Incremental Offline - Cumulative changes, database offline'
        WHEN OPERATION IN ('B', 'R') AND OPERATIONTYPE = 'M' THEN 'Merged - Consolidated incremental backup image'
        WHEN OPERATION IN ('B', 'R') AND OPERATIONTYPE = 'N' THEN 'Full Online - Complete backup, database online'
        WHEN OPERATION IN ('B', 'R') AND OPERATIONTYPE = 'O' THEN 'Incremental Online - Cumulative changes, database online'
        WHEN OPERATION IN ('B', 'R') AND OPERATIONTYPE = 'R' THEN 'Rebuild - Database rebuilt from backup images'
        WHEN OPERATION = 'L' AND OPERATIONTYPE = 'I' THEN 'Insert - Load data appended to existing table data'
        WHEN OPERATION = 'L' AND OPERATIONTYPE = 'R' THEN 'Replace - Load data replaced existing table data'
        WHEN OPERATION = 'F' AND OPERATIONTYPE = 'E' THEN 'End of Logs - Rollforward to end of available logs'
        WHEN OPERATION = 'F' AND OPERATIONTYPE = 'P' THEN 'Point-in-Time - Rollforward to specific timestamp'
        WHEN OPERATION = 'X' AND OPERATIONTYPE = 'F' THEN 'Failover Archive Path - Log archived to failover location'
        WHEN OPERATION = 'X' AND OPERATIONTYPE = 'M' THEN 'Mirror Log Path - Log archived to mirror/secondary path'
        WHEN OPERATION = 'X' AND OPERATIONTYPE = 'N' THEN 'Archive Log Command - Manual archive log command executed'
        WHEN OPERATION = 'X' AND OPERATIONTYPE = 'P' THEN 'Primary Log Path - Log archived to primary location'
        WHEN OPERATION = 'X' AND OPERATIONTYPE = '1' THEN 'Primary Archive Method - First archive destination'
        WHEN OPERATION = 'X' AND OPERATIONTYPE = '2' THEN 'Secondary Archive Method - Second archive destination'
        WHEN OPERATION = 'T' AND OPERATIONTYPE = 'C' THEN 'Add Container - New storage container added to tablespace'
        WHEN OPERATION = 'T' AND OPERATIONTYPE = 'R' THEN 'Rebalance - Data redistributed across containers'
        WHEN OPERATION = 'Q' AND OPERATIONTYPE = 'S' THEN 'Quiesce Share - Shared read access, no writes allowed'
        WHEN OPERATION = 'Q' AND OPERATIONTYPE = 'U' THEN 'Quiesce Update - Single updater allowed'
        WHEN OPERATION = 'Q' AND OPERATIONTYPE = 'X' THEN 'Quiesce Exclusive - No access allowed'
        WHEN OPERATION = 'Q' AND OPERATIONTYPE = 'Z' THEN 'Quiesce Reset - Quiesce state removed'
        ELSE OPERATIONTYPE
    END AS OPERATIONTYPE_DESC,
    DEVICETYPE,
    CASE DEVICETYPE
        WHEN 'A' THEN 'TSM/ADSM'
        WHEN 'D' THEN 'Disk'
        WHEN 'K' THEN 'Diskette'
        WHEN 'O' THEN 'Other'
        WHEN 'T' THEN 'Tape'
        WHEN 'U' THEN 'User Exit'
        ELSE 'Unknown (' || COALESCE(DEVICETYPE, 'NULL') || ')'
    END AS DEVICETYPE_SHORT_DESC,
    CASE DEVICETYPE
        WHEN 'A' THEN 'Tivoli Storage Manager (TSM/ADSM) - IBM backup server'
        WHEN 'D' THEN 'Disk - Local or network disk storage'
        WHEN 'K' THEN 'Diskette - Floppy disk (legacy)'
        WHEN 'O' THEN 'Other - Vendor-specific or custom device'
        WHEN 'T' THEN 'Tape - Magnetic tape storage'
        WHEN 'U' THEN 'User Exit - Custom user-defined backup program'
        ELSE 'Unknown (' || COALESCE(DEVICETYPE, 'NULL') || ')'
    END AS DEVICETYPE_DESC,
    ENTRY_STATUS,
    CASE ENTRY_STATUS
        WHEN 'A' THEN 'Active'
        WHEN 'D' THEN 'Deleted'
        WHEN 'E' THEN 'Expired'
        WHEN 'I' THEN 'Inactive'
        WHEN 'N' THEN 'Not committed'
        WHEN 'P' THEN 'Pending delete'
        WHEN 'X' THEN 'Do not delete'
        WHEN 'a' THEN 'Incomplete active'
        WHEN 'i' THEN 'Incomplete inactive'
        ELSE 'Unknown (' || COALESCE(ENTRY_STATUS, 'NULL') || ')'
    END AS ENTRY_STATUS_SHORT_DESC,
    CASE ENTRY_STATUS
        WHEN 'A' THEN 'Active - Entry is valid and usable for recovery'
        WHEN 'D' THEN 'Deleted - Entry marked for removal from history'
        WHEN 'E' THEN 'Expired - Entry exceeded retention period'
        WHEN 'I' THEN 'Inactive - Entry no longer needed for recovery'
        WHEN 'N' THEN 'Not yet committed - Operation still in progress'
        WHEN 'P' THEN 'Pending delete - Scheduled for automatic removal'
        WHEN 'X' THEN 'Do not delete - Entry protected from pruning'
        WHEN 'a' THEN 'Incomplete active - Active but operation did not complete'
        WHEN 'i' THEN 'Incomplete inactive - Inactive and operation did not complete'
        ELSE 'Unknown (' || COALESCE(ENTRY_STATUS, 'NULL') || ')'
    END AS ENTRY_STATUS_DESC,
    FIRSTLOG,
    LASTLOG,
    NUM_LOG_ELEMS,
    BACKUP_ID,
    TABSCHEMA,
    TABNAME,
    LOCATION,
    TOTAL_SIZE,
    SEQ_SIZE,
    CMD_TEXT,
    COMMENT,
    ENCRYPTED,
    INCLUDE_LOGS,
    COMPRESSION_LIBRARY,
    SQLCODE,
    CASE 
        WHEN SQLCODE IS NULL THEN SYSPROC.SQLERRM(0) 
        ELSE SYSPROC.SQLERRM(SQLCODE) 
    END AS STATUS_SHORT_DESC,
    SQLERRMC,
    SQLSTATE,
    NUM_TBSPS,
    TBSPNAMES
FROM SYSIBMADM.DB_HISTORY;
```

### Example Queries Using the View

```sql
-- Get all operations from the last 7 days
SELECT * FROM V_DB_HISTORY_READABLE
WHERE DAYS_AGO <= 7
ORDER BY START_TIME DESC;

-- Get latest backups with readable descriptions
SELECT OPERATION_DESC, OBJECTTYPE_DESC, OPERATIONTYPE_DESC, 
       DEVICETYPE_DESC, START_TIME, DAYS_AGO, LOCATION, STATUS_DESC
FROM V_DB_HISTORY_READABLE
WHERE OPERATION = 'B'
ORDER BY START_TIME DESC
FETCH FIRST 5 ROWS ONLY;

-- Summary of operations in the last 30 days
SELECT OPERATION_DESC, COUNT(*) AS COUNT, 
       MIN(DAYS_AGO) AS MOST_RECENT_DAYS_AGO,
       MAX(DAYS_AGO) AS OLDEST_DAYS_AGO
FROM V_DB_HISTORY_READABLE
WHERE DAYS_AGO <= 30
GROUP BY OPERATION, OPERATION_DESC
ORDER BY COUNT DESC;

-- Find any failed operations
SELECT OPERATION_DESC, OPERATIONTYPE_DESC, START_TIME, 
       DAYS_AGO, STATUS_DESC, SQLCODE, SQLERRMC
FROM V_DB_HISTORY_READABLE
WHERE SQLCODE < 0
ORDER BY START_TIME DESC;

-- Latest operation of each type
SELECT *
FROM V_DB_HISTORY_READABLE y 
JOIN (
    SELECT OPERATION, MAX(START_TIME) AS START_TIME
    FROM SYSIBMADM.DB_HISTORY
    GROUP BY OPERATION
) x ON y.START_TIME = x.START_TIME 
   AND y.OPERATION = x.OPERATION
ORDER BY y.START_TIME DESC;
```

---

## SQLCODE Error Message Lookup

DB2 provides built-in functions and commands to retrieve human-readable error messages for SQLCODE values.

### SYSPROC.SQLERRM Function

The `SYSPROC.SQLERRM` scalar function retrieves error message text for a given SQLCODE.

**Simple syntax (SQLCODE only):**

```sql
VALUES (SYSPROC.SQLERRM(-551))
```

Returns: `SQL0551N "" does not have the privilege to perform operation "" on object "".`

**Full syntax with tokens and language:**

```sql
SYSPROC.SQLERRM(msgid, tokens, token_delimiter, locale, shortmsg)
```

| Parameter | Type | Description |
|-----------|------|-------------|
| `msgid` | VARCHAR(9) | Message ID: 'SQL551', 'CLI0001', or SQLSTATE like '42829' |
| `tokens` | VARCHAR(70) | Token values separated by delimiter (or NULL) |
| `token_delimiter` | VARCHAR(1) | Delimiter character (default ';') |
| `locale` | VARCHAR(33) | Language locale, e.g., 'en_US' |
| `shortmsg` | INTEGER | 1 = short message, 0 = long message with explanation |

**Examples:**

```sql
-- Short message with tokens filled in
VALUES (SYSPROC.SQLERRM('SQL551', 'DBUSER;UPDATE;SYSCAT.TABLES', ';', 'en_US', 1))
-- Returns: SQL0551N "DBUSER" does not have the privilege to perform operation "UPDATE" on object "SYSCAT.TABLES"

-- Get error message for SQLSTATE
VALUES (SYSPROC.SQLERRM('42501', '', '', 'en_US', 1))
-- Returns: SQLSTATE 42501: The authorization ID does not have the privilege...

-- Long message with full explanation and recovery steps
VALUES (SYSPROC.SQLERRM('SQL1001', '', '', 'en_US', 0))
-- Returns full explanation, cause, and user response
```

### Using SQLERRM with DB_HISTORY

Join with SQLERRM to get error descriptions for failed operations:

```sql
SELECT 
    h.START_TIME,
    h.OPERATION,
    h.SQLCODE,
    h.SQLSTATE,
    SYSPROC.SQLERRM(h.SQLCODE) AS ERROR_MESSAGE
FROM SYSIBMADM.DB_HISTORY h
WHERE h.SQLCODE < 0
ORDER BY h.START_TIME DESC;
```

### Command Line: db2 ? 

From the command line, use `db2 ?` to look up error codes:

```bash
# Look up SQLCODE by message ID
db2 ? SQL0551N

# Look up by SQLSTATE
db2 ? 42501
```

### SQLCODE Format Reference

| SQLCODE Range | Message ID Format | Example |
|---------------|-------------------|---------|
| -9999 to 9999 | SQL + absolute value | SQLCODE -551 → SQL0551N |
| 10000+ | SQ + value | SQLCODE -30082 → SQ30082N |

**Suffix meaning:** N = Negative (error), W = Warning

### Generate SQLCODE Reference Table (Dynamic)

DB2 doesn't have a system table with all SQLCODE definitions (they're in file-based message catalogs). 
However, you can generate a reference table dynamically using a recursive CTE with `SYSPROC.SQLERRM`:

```sql
CREATE TABLE SQLCODE_REFERENCE AS (
    WITH SQLCODE_RANGE(CODE) AS (
        SELECT -1 FROM SYSIBM.SYSDUMMY1
        UNION ALL
        SELECT CODE - 1 FROM SQLCODE_RANGE WHERE CODE > -2000
    )
    SELECT 
        CODE AS SQLCODE,
        SYSPROC.SQLERRM(CODE) AS ERROR_MESSAGE
    FROM SQLCODE_RANGE
    WHERE SYSPROC.SQLERRM(CODE) IS NOT NULL
      AND SYSPROC.SQLERRM(CODE) NOT LIKE '%is not valid%'
) WITH DATA;
```

Or create a view for on-demand lookup of common error ranges:

```sql
CREATE OR REPLACE VIEW V_SQLCODE_LOOKUP AS
WITH CODES(CODE) AS (
    SELECT -1 FROM SYSIBM.SYSDUMMY1
    UNION ALL
    SELECT CODE - 1 FROM CODES WHERE CODE > -1000
)
SELECT 
    CODE AS SQLCODE,
    'SQL' || RIGHT('0000' || CHAR(ABS(CODE)), 4) || 'N' AS MESSAGE_ID,
    SYSPROC.SQLERRM(CODE) AS ERROR_MESSAGE
FROM CODES;
```

**Usage:**

```sql
SELECT * FROM V_SQLCODE_LOOKUP WHERE SQLCODE = -551;

SELECT * FROM V_SQLCODE_LOOKUP 
WHERE ERROR_MESSAGE LIKE '%privilege%';
```

**Note:** SQLCODE ranges in DB2:
- `-1 to -999`: Common SQL errors
- `-1001 to -1650`: Database engine errors  
- `-30000 to -30100`: Distributed/DRDA communication errors

---

## Related Documentation

- [IBM DB2 12.1 Documentation](https://www.ibm.com/docs/en/db2/12.1)
- [IBM DB2 LIST UTILITIES Command](https://www.ibm.com/docs/en/db2/11.5?topic=commands-list-utilities)
- [IBM DB2 LIST HISTORY Command](https://www.ibm.com/docs/en/db2/11.5?topic=commands-list-history)
- [IBM DB2 db2pd Tool](https://www.ibm.com/docs/en/db2/11.5?topic=tools-db2pd)
- [IBM DB2 db2diag Tool](https://www.ibm.com/docs/en/db2/11.5?topic=commands-db2diag-db2diag-logs-analysis-tool)
- [Monitor Progress of DB2 Commands](https://www.ibm.com/support/pages/monitor-progress-db2-commands)
