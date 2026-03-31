# DB2 State Information Panel - Visual Design Specification

## Overview

One **panel per active database**, showing real-time state information that impacts performance NOW.

## Panel Title Format
```
🗄️ Db2 State Information: XFKMPRD (DB2FED)
```
Where:
- `XFKMPRD` = Database name  
- `DB2FED` = Instance name (in parentheses)

---

## Visual Layout Specification

### Panel Structure (Per Database)

```
┌─────────────────────────────────────────────────────────────────────────────────────────┐
│ 🗄️ Db2 State Information: XFKMPRD (DB2FED)                                    ● ACTIVE │
├─────────────────────────────────────────────────────────────────────────────────────────┤
│                                                                                         │
│  ┌─── GAUGES ──────────────────────────────────────────────────────────────────────┐   │
│  │                                                                                  │   │
│  │   ┌────────────────┐    ┌────────────────┐    ┌────────────────┐                 │   │
│  │   │    ╭──────╮    │    │    ╭──────╮    │    │    ╭──────╮    │                 │   │
│  │   │   ╱   42   ╲   │    │   ╱   3    ╲   │    │   ╱  98.5% ╲   │                 │   │
│  │   │  ╱──────────╲  │    │  ╱──────────╲  │    │  ╱──────────╲  │                 │   │
│  │   │  SESSIONS      │    │   USERS        │    │  BP HIT RATIO  │                 │   │
│  │   └────────────────┘    └────────────────┘    └────────────────┘                 │   │
│  │                                                                                  │   │
│  └──────────────────────────────────────────────────────────────────────────────────┘   │
│                                                                                         │
│  ┌─── COUNTERS ────────────────────────────────────────────────────────────────────┐   │
│  │                                                                                  │   │
│  │   ┌──────────┐  ┌──────────┐  ┌──────────┐  ┌──────────┐  ┌──────────┐          │   │
│  │   │    🔒    │  │    ⏱️    │  │    📊    │  │    💾    │  │    ⚠️    │          │   │
│  │   │     0    │  │     2    │  │    15    │  │  125 GB  │  │     5    │          │   │
│  │   │ Blocking │  │ Long Ops │  │ Lock Wait│  │ DB Size  │  │ Errors   │          │   │
│  │   └──────────┘  └──────────┘  └──────────┘  └──────────┘  └──────────┘          │   │
│  │                                                                                  │   │
│  └──────────────────────────────────────────────────────────────────────────────────┘   │
│                                                                                         │
│  ┌─── LONG OPERATIONS (> 5 sec) ───────────────────────────────────────────────────┐   │
│  │                                                                                  │   │
│  │  ┌──────────┬──────────┬──────────────────────────────────────────────────────┐  │   │
│  │  │ User     │ Duration │ SQL                                                  │  │   │
│  │  ├──────────┼──────────┼──────────────────────────────────────────────────────┤  │   │
│  │  │ APP_SVC  │  5m 23s  │ SELECT * FROM FK.TRANSACTIONS WHERE DATO > '2026... │  │   │
│  │  │ BATCH    │  2m 11s  │ UPDATE FK.INVENTORY SET QUANTITY = QUANTITY - 1 W... │  │   │
│  │  └──────────┴──────────┴──────────────────────────────────────────────────────┘  │   │
│  │                                                                                  │   │
│  └──────────────────────────────────────────────────────────────────────────────────┘   │
│                                                                                         │
│  ┌─── LOCK WAITS ──────────────────────────────────────────────────────────────────┐   │
│  │                                                                                  │   │
│  │  ┌──────────┬──────────┬──────────┬───────────────────────────────────────────┐  │   │
│  │  │ Blocked  │ Blocker  │ Wait     │ Object                                    │  │   │
│  │  ├──────────┼──────────┼──────────┼───────────────────────────────────────────┤  │   │
│  │  │ APP_USER │ ADMIN    │   45s    │ FK.ORDERS (Row Lock - X)                  │  │   │
│  │  │ BATCH_01 │ APP_USER │   12s    │ FK.INVENTORY (Table Lock - S)             │  │   │
│  │  └──────────┴──────────┴──────────┴───────────────────────────────────────────┘  │   │
│  │                                                                                  │   │
│  └──────────────────────────────────────────────────────────────────────────────────┘   │
│                                                                                         │
│  ┌─── TODAY'S DIAG LOG ────────────────────────────────────────────────────────────┐   │
│  │                                                                                  │   │
│  │   ┌──────────┐  ┌──────────┐  ┌──────────┐  ┌──────────┐                        │   │
│  │   │ 🔴  0    │  │ 🟠  5    │  │ 🟡  12   │  │ 🔵  45   │                        │   │
│  │   │ Critical │  │ Errors   │  │ Warnings │  │ Events   │                        │   │
│  │   └──────────┘  └──────────┘  └──────────┘  └──────────┘                        │   │
│  │                                                                                  │   │
│  └──────────────────────────────────────────────────────────────────────────────────┘   │
│                                                                                         │
└─────────────────────────────────────────────────────────────────────────────────────────┘
```

---

## Metrics Specification

### 1. GAUGES (Circular Semi-Arc Meters)

| Metric | Source | Description | Thresholds |
|--------|--------|-------------|------------|
| **Sessions** | `MON_GET_CONNECTION` | Total active connections | 🟢 <50, 🟡 50-80, 🔴 >80 |
| **Users** | `MON_GET_CONNECTION` (DISTINCT) | Unique `SESSION_AUTH_ID` | Display only |
| **BP Hit Ratio** | `MON_GET_BUFFERPOOL` | Buffer pool hit ratio % | 🟢 >95%, 🟡 90-95%, 🔴 <90% |

### 2. COUNTERS (Box Tiles with Icon)

| Metric | Source | Description | Visual |
|--------|--------|-------------|--------|
| **🔒 Blocking** | `MON_GET_APPL_LOCKWAIT` | Sessions blocked by locks | 🟢 = 0, 🔴 ≥ 1 |
| **⏱️ Long Ops** | `MON_GET_ACTIVITY` | Queries > threshold seconds | 🟢 = 0, 🟡 1-5, 🔴 >5 |
| **📊 Lock Waits** | `MON_GET_APPL_LOCKWAIT` | Total lock wait events today | Count value |
| **💾 DB Size** | `SYSIBMADM.SNAPDB` / `MON_GET_TABLESPACE` | Database size in GB | Display only |
| **⚠️ Errors** | Db2 Diag Monitor (today) | Error count from db2diag.log | 🟢 = 0, 🟡 1-10, 🔴 >10 |

### 3. LONG OPERATIONS TABLE

Shows queries running longer than configured threshold (`appsettings.json: Thresholds.LongRunningQueryThresholdSeconds`).

| Column | Source | Description |
|--------|--------|-------------|
| User | `SESSION_AUTH_ID` | User running the query |
| Duration | `TIMESTAMPDIFF()` | How long it's been running |
| SQL | `STMT_TEXT` | First 60 chars of SQL (hover for full) |

**Row Colors:**
- 🟡 Warning: > `LongRunningQueryWarningSeconds` (default: 300s / 5 min)
- 🔴 Critical: > `LongRunningQueryCriticalSeconds` (default: 1800s / 30 min)

### 4. LOCK WAITS TABLE

Shows sessions currently waiting for locks.

| Column | Source | Description |
|--------|--------|-------------|
| Blocked | `REQ_APPLICATION_HANDLE` → `SESSION_AUTH_ID` | User being blocked |
| Blocker | `HLD_APPLICATION_HANDLE` → `SESSION_AUTH_ID` | User holding the lock |
| Wait | `LOCK_WAIT_START_TIME` | How long blocked |
| Object | `TABSCHEMA.TABNAME` + Lock Mode | Table and lock type |

**Row Colors:**
- 🟡 Warning: > `LockWaitWarningSeconds` (default: 30s)
- 🔴 Critical: > `LockWaitCriticalSeconds` (default: 300s / 5 min)

### 5. TODAY'S DIAG LOG (Counters)

| Counter | Source | Color |
|---------|--------|-------|
| Critical | Db2DiagMonitor summary | 🔴 Red |
| Errors | Db2DiagMonitor summary | 🟠 Orange |
| Warnings | Db2DiagMonitor summary | 🟡 Yellow |
| Events | Db2DiagMonitor summary | 🔵 Blue |

---

## Additional Performance Metrics (Future)

These are "NOW" metrics - they impact real-time performance:

| Metric | SQL Query | Why It Matters |
|--------|-----------|----------------|
| **Sort Overflows** | `MON_GET_DATABASE().SORT_OVERFLOWS` | Memory pressure indicator |
| **Log Space Used %** | `MON_GET_TRANSACTION_LOG()` | Transaction log pressure |
| **Package Cache Hit %** | `MON_GET_PKG_CACHE_STMT()` | SQL plan efficiency |
| **Rows Read/Returned Ratio** | `MON_GET_ACTIVITY()` | Query efficiency |
| **Deadlocks Today** | `MON_GET_DATABASE().DEADLOCKS` | Concurrency issues |
| **Lock Escalations** | `MON_GET_DATABASE().LOCK_ESCALS` | Lock granularity issues |

---

## Configuration Requirements (appsettings.json)

```json
{
  "Surveillance": {
    "Db2InstanceMonitoring": {
      "Enabled": true,
      "RefreshIntervalSeconds": 1200,
      "ServerNamePattern": "-db$",
      
      "CollectSessionCounts": true,
      "CollectLongRunningQueries": true,
      "CollectBlockingSessions": true,
      "CollectBufferPoolStats": true,
      "CollectDiagSummary": true,
      
      "Thresholds": {
        "LongRunningQueryThresholdSeconds": 5,
        "LongRunningQueryWarningSeconds": 300,
        "LongRunningQueryCriticalSeconds": 1800,
        "LockWaitWarningSeconds": 30,
        "LockWaitCriticalSeconds": 300,
        "SessionCountWarningThreshold": 50,
        "BufferPoolHitRatioWarning": 95,
        "BufferPoolHitRatioCritical": 90,
        "MaxLongRunningQueriesToShow": 20,
        "MaxBlockingSessionsToShow": 20
      }
    }
  }
}
```

---

## SQL Queries for New Metrics

### Buffer Pool Hit Ratio
```sql
SELECT 
    BP_NAME,
    CASE WHEN (POOL_DATA_L_READS + POOL_INDEX_L_READS) > 0
         THEN DECIMAL(
              ((POOL_DATA_L_READS + POOL_INDEX_L_READS 
                - POOL_DATA_P_READS - POOL_INDEX_P_READS) * 100.0) 
              / (POOL_DATA_L_READS + POOL_INDEX_L_READS), 5, 2)
         ELSE 100.00
    END AS HIT_RATIO
FROM TABLE(MON_GET_BUFFERPOOL('', -2)) AS BP
WHERE BP_NAME NOT LIKE 'IBMSYS%'
```

### Database Size (GB)
```sql
SELECT 
    DECIMAL(SUM(TBSP_USED_SIZE_KB) / 1024.0 / 1024.0, 10, 2) AS SIZE_GB
FROM TABLE(MON_GET_TABLESPACE('', -2)) AS TS
```

### Lock Escalations Today
```sql
SELECT LOCK_ESCALS 
FROM TABLE(MON_GET_DATABASE(-2)) AS DB
```

---

## Example: Multiple Databases on p-no1fkmprd-db

```
┌──────────────────────────────────────────────────────────────────────┐
│ 🗄️ Db2 State Information: XFKMPRD (DB2FED)                 ● ACTIVE │
│ Sessions: 42 │ Users: 3 │ BP: 98.5% │ Blocking: 0 │ Long Ops: 2      │
│ [Expand for details]                                                 │
└──────────────────────────────────────────────────────────────────────┘

┌──────────────────────────────────────────────────────────────────────┐
│ 🗄️ Db2 State Information: FKMPRD (DB2)                     ● ACTIVE │
│ Sessions: 18 │ Users: 5 │ BP: 99.1% │ Blocking: 1 │ Long Ops: 0      │
│ ⚠️ 1 blocking session                                                │
│ [Expand for details]                                                 │
└──────────────────────────────────────────────────────────────────────┘

┌──────────────────────────────────────────────────────────────────────┐
│ 🗄️ Db2 State Information: XHSTPRD (DB2HFED)                ● ACTIVE │
│ Sessions: 8 │ Users: 2 │ BP: 97.2% │ Blocking: 0 │ Long Ops: 0       │
│ [Expand for details]                                                 │
└──────────────────────────────────────────────────────────────────────┘

┌──────────────────────────────────────────────────────────────────────┐
│ 🗄️ Db2 State Information: HSTPRD (DB2HST)                  ● ACTIVE │
│ Sessions: 12 │ Users: 1 │ BP: 99.8% │ Blocking: 0 │ Long Ops: 0      │
│ [Expand for details]                                                 │
└──────────────────────────────────────────────────────────────────────┘
```

---

## Panel States

### All Clear
```
🗄️ Db2 State Information: XFKMPRD (DB2FED)                    🟢 OK
```
- Green indicator
- No blocking, no long ops
- All gauges in green zone

### Warning State
```
🗄️ Db2 State Information: XFKMPRD (DB2FED)                    🟡 WARN
```
- Yellow indicator
- Has long-running queries > 5 min
- Or lock waits > 30s
- Or BP hit ratio < 95%

### Critical State
```
🗄️ Db2 State Information: XFKMPRD (DB2FED)                    🔴 CRIT
```
- Red indicator
- Blocking sessions present
- Or long-running queries > 30 min
- Or lock waits > 5 min
- Or BP hit ratio < 90%

---

## Implementation Checklist

1. **Agent (Db2InstanceDataCollector.cs)**
   - [ ] Add `CollectBufferPoolStats` method
   - [ ] Add `BufferPoolHitRatio` to `Db2DatabaseInstanceData`
   - [ ] Add `DatabaseSizeGb` to model
   - [ ] Add configuration for new thresholds

2. **Dashboard (dashboard.js)**
   - [ ] Create per-database panel rendering
   - [ ] Implement gauge SVG components
   - [ ] Implement counter tile components
   - [ ] Add expand/collapse for tables
   - [ ] Color coding based on thresholds

3. **CSS (dashboard.css)**
   - [ ] Gauge arc styling
   - [ ] Counter tile grid
   - [ ] Threshold color classes
   - [ ] Panel state indicators

---

## Approval Required

- [ ] Gauge design (semi-arc vs full circle vs bar)
- [ ] Counter tiles layout (5 across vs 2 rows)
- [ ] Collapsible tables (default expanded or collapsed?)
- [ ] Sort order of databases (by issues? alphabetical? sessions?)
