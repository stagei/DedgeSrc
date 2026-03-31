# DB2 State Info Panel Enhancement Proposal

## Overview

This document outlines suggestions for enhancing the ServerMonitorAgent DB2 monitoring capabilities and the Dashboard UI, based on analysis of the WindowsDb2Editor SQL statements, DB2 system metadata, and current implementation.

---

## 1. Current Issues and Fixes

### 1.1 Session Counter Issue

**Problem**: Sessions and Users stats may be incorrect during batch job execution, as the current query counts all connections including internal DB2 processes.

**Current SQL** (in `Db2InstanceDataCollector.cs`):
```sql
SELECT 
    COUNT(*) AS TOTAL_SESSIONS,
    COUNT(DISTINCT SESSION_AUTH_ID) AS UNIQUE_USERS,
    SUM(CASE WHEN CONNECTION_STATE = 'CONNECTED' THEN 1 ELSE 0 END) AS CONNECTED,
    SUM(CASE WHEN CONNECTION_STATE = 'EXECUTING' THEN 1 ELSE 0 END) AS EXECUTING,
    SUM(CASE WHEN CONNECTION_STATE = 'WAITING' THEN 1 ELSE 0 END) AS WAITING
FROM TABLE(MON_GET_CONNECTION(NULL, -2)) AS C
```

**Suggested Fix**: Filter out internal DB2 connections and provide breakdown by connection type:
```sql
SELECT 
    COUNT(*) AS TOTAL_SESSIONS,
    COUNT(DISTINCT SESSION_AUTH_ID) AS UNIQUE_USERS,
    SUM(CASE WHEN SESSION_AUTH_ID NOT LIKE 'DB2%' AND SESSION_AUTH_ID NOT LIKE 'SYSIBM%' THEN 1 ELSE 0 END) AS USER_SESSIONS,
    SUM(CASE WHEN SESSION_AUTH_ID LIKE 'DB2%' OR SESSION_AUTH_ID LIKE 'SYSIBM%' THEN 1 ELSE 0 END) AS SYSTEM_SESSIONS,
    SUM(CASE WHEN CONNECTION_STATE = 'EXECUTING' THEN 1 ELSE 0 END) AS EXECUTING,
    SUM(CASE WHEN CONNECTION_STATE = 'IDLE' THEN 1 ELSE 0 END) AS IDLE,
    SUM(CASE WHEN CONNECTION_STATE = 'WAITING' THEN 1 ELSE 0 END) AS WAITING
FROM TABLE(MON_GET_CONNECTION(NULL, -2)) AS C
WHERE MEMBER = CURRENT MEMBER
```

**Dashboard Update**: Show separate counters for "User Sessions" vs "System Sessions" to clarify batch job impact.

---

## 2. New API Endpoints for Pop-Out Window

### 2.1 Database-Specific Refresh Endpoint

Add a new API endpoint that fetches data for a **single database** on demand:

**Endpoint**: `GET /api/db2/{instanceName}/{databaseName}/state`

**Response Model**:
```csharp
public record Db2DatabaseDetailedState
{
    public string InstanceName { get; init; }
    public string DatabaseName { get; init; }
    public DateTime CollectedAt { get; init; }
    public bool IsInstanceRunning { get; init; }
    
    // Sessions
    public Db2SessionMetrics Sessions { get; init; }
    
    // Active queries with details
    public List<Db2ActiveQuery> ActiveQueries { get; init; }
    
    // Blocking chains
    public List<Db2BlockingChain> BlockingChains { get; init; }
    
    // Performance metrics
    public Db2PerformanceMetrics Performance { get; init; }
    
    // Lock information
    public List<Db2ActiveLock> ActiveLocks { get; init; }
    
    // Table activity (top 10)
    public List<Db2TableActivity> TopActiveTablesByOps { get; init; }
    
    // Diagnostic summary
    public Db2DiagSummary DiagSummary { get; init; }
    
    // Filtered alerts for this database (last 24h)
    public List<Alert> RecentAlerts { get; init; }
}
```

### 2.2 Suggested New Endpoints

| Endpoint | Description | Refresh Interval |
|----------|-------------|------------------|
| `GET /api/db2/{instance}/{db}/sessions` | Active sessions with details | 10s |
| `GET /api/db2/{instance}/{db}/locks` | Current lock waits and holders | 10s |
| `GET /api/db2/{instance}/{db}/activity` | Current statement activity | 5s |
| `GET /api/db2/{instance}/{db}/top-tables` | Top 10 active tables | 30s |
| `GET /api/db2/{instance}/{db}/bufferpools` | Buffer pool stats per pool | 30s |
| `GET /api/db2/{instance}/{db}/tablespaces` | Tablespace usage | 60s |
| `GET /api/db2/{instance}/{db}/alerts` | Filtered alerts for this database (24h) | 30s |

---

## 3. Enhanced SQL Queries (from WindowsDb2Editor)

### 3.1 Active Sessions with Details

Based on `GetActiveSessions_Full` from WindowsDb2Editor:
```sql
SELECT 
    C.APPLICATION_HANDLE,
    C.APPLICATION_NAME,
    C.SESSION_AUTH_ID AS USER_ID,
    C.CLIENT_HOSTNAME,
    C.CLIENT_IPADDR,
    C.CONNECTION_STATE,
    TIMESTAMPDIFF(2, CURRENT_TIMESTAMP - C.CONNECTION_START_TIME) AS CONNECTED_SECONDS,
    C.TOTAL_CPU_TIME / 1000 AS CPU_TIME_MS,
    C.TOTAL_WAIT_TIME / 1000 AS WAIT_TIME_MS,
    C.ROWS_READ,
    C.ROWS_RETURNED,
    C.ROWS_MODIFIED
FROM TABLE(MON_GET_CONNECTION(NULL, -2)) AS C
WHERE C.MEMBER = CURRENT MEMBER
ORDER BY C.TOTAL_CPU_TIME DESC
FETCH FIRST 50 ROWS ONLY
```

### 3.2 Lock Chains (Deadlock Analysis)

Based on `GetLockChains` from WindowsDb2Editor:
```sql
SELECT 
    L.REQ_APPLICATION_HANDLE AS BLOCKED_HANDLE,
    L.HLD_APPLICATION_HANDLE AS BLOCKER_HANDLE,
    L.LOCK_MODE,
    L.LOCK_OBJECT_TYPE,
    L.TABSCHEMA,
    L.TABNAME,
    TIMESTAMPDIFF(2, CURRENT_TIMESTAMP - L.LOCK_WAIT_START_TIME) AS WAIT_SECONDS,
    REQ.SESSION_AUTH_ID AS BLOCKED_USER,
    REQ.APPLICATION_NAME AS BLOCKED_APP,
    REQ.CLIENT_HOSTNAME AS BLOCKED_HOST,
    HLD.SESSION_AUTH_ID AS BLOCKER_USER,
    HLD.APPLICATION_NAME AS BLOCKER_APP,
    -- Try to get blocker's current statement
    SUBSTR(COALESCE(ACT.STMT_TEXT, ''), 1, 200) AS BLOCKER_SQL
FROM TABLE(MON_GET_APPL_LOCKWAIT(NULL, -2)) AS L
INNER JOIN TABLE(MON_GET_CONNECTION(NULL, -2)) AS REQ ON L.REQ_APPLICATION_HANDLE = REQ.APPLICATION_HANDLE
INNER JOIN TABLE(MON_GET_CONNECTION(NULL, -2)) AS HLD ON L.HLD_APPLICATION_HANDLE = HLD.APPLICATION_HANDLE
LEFT JOIN TABLE(MON_GET_ACTIVITY(NULL, -2)) AS ACT ON L.HLD_APPLICATION_HANDLE = ACT.APPLICATION_HANDLE
ORDER BY WAIT_SECONDS DESC
```

### 3.3 Table Activity (Top Tables)

Based on `GetTableActivity` from WindowsDb2Editor:
```sql
SELECT 
    TABLE_SCHEMA,
    TABLE_NAME,
    ROWS_READ,
    ROWS_INSERTED,
    ROWS_UPDATED,
    ROWS_DELETED,
    (ROWS_READ + ROWS_INSERTED + ROWS_UPDATED + ROWS_DELETED) AS TOTAL_OPS,
    TABLE_SCANS,
    OBJECT_DATA_L_READS AS LOGICAL_READS,
    OBJECT_DATA_P_READS AS PHYSICAL_READS,
    CASE WHEN OBJECT_DATA_L_READS > 0 
         THEN DECIMAL((OBJECT_DATA_L_READS - OBJECT_DATA_P_READS) * 100.0 / OBJECT_DATA_L_READS, 5, 2)
         ELSE 100.00 
    END AS HIT_RATIO_PCT
FROM TABLE(MON_GET_TABLE('', '', -2)) AS T
WHERE TABLE_SCHEMA NOT IN ('SYSIBM', 'SYSCAT', 'SYSPROC', 'SYSFUN')
ORDER BY TOTAL_OPS DESC
FETCH FIRST 10 ROWS ONLY
```

### 3.4 Buffer Pool Details Per Pool

```sql
SELECT 
    BP_NAME,
    POOL_DATA_L_READS + POOL_INDEX_L_READS AS LOGICAL_READS,
    POOL_DATA_P_READS + POOL_INDEX_P_READS AS PHYSICAL_READS,
    CASE WHEN (POOL_DATA_L_READS + POOL_INDEX_L_READS) > 0
         THEN DECIMAL(
              ((POOL_DATA_L_READS + POOL_INDEX_L_READS - POOL_DATA_P_READS - POOL_INDEX_P_READS) * 100.0) 
              / (POOL_DATA_L_READS + POOL_INDEX_L_READS), 5, 2)
         ELSE 100.00
    END AS HIT_RATIO,
    POOL_ASYNC_DATA_READS + POOL_ASYNC_INDEX_READS AS ASYNC_READS,
    POOL_ASYNC_DATA_WRITES + POOL_ASYNC_INDEX_WRITES AS ASYNC_WRITES,
    POOL_DATA_WRITES + POOL_INDEX_WRITES AS WRITES
FROM TABLE(MON_GET_BUFFERPOOL('', -2)) AS BP
WHERE BP_NAME NOT LIKE 'IBMSYS%'
ORDER BY BP_NAME
```

### 3.5 Tablespace Usage

```sql
SELECT 
    TBSP_NAME,
    TBSP_TYPE,
    TBSP_STATE,
    TBSP_TOTAL_SIZE_KB / 1024 AS TOTAL_MB,
    TBSP_USED_SIZE_KB / 1024 AS USED_MB,
    TBSP_FREE_SIZE_KB / 1024 AS FREE_MB,
    CASE WHEN TBSP_TOTAL_SIZE_KB > 0
         THEN DECIMAL(TBSP_USED_SIZE_KB * 100.0 / TBSP_TOTAL_SIZE_KB, 5, 2)
         ELSE 0.00
    END AS USED_PCT,
    TBSP_PAGE_SIZE / 1024 AS PAGE_SIZE_KB,
    TBSP_EXTENT_SIZE AS EXTENT_SIZE,
    TBSP_PREFETCH_SIZE AS PREFETCH_SIZE
FROM TABLE(MON_GET_TABLESPACE('', -2)) AS TS
ORDER BY TBSP_NAME
```

### 3.6 Current Statements (Active Queries)

```sql
SELECT 
    A.APPLICATION_HANDLE,
    A.UOW_ID,
    A.ACTIVITY_ID,
    A.ACTIVITY_STATE,
    A.ACTIVITY_TYPE,
    A.SESSION_AUTH_ID AS USER_ID,
    TIMESTAMPDIFF(2, CURRENT_TIMESTAMP - A.LOCAL_START_TIME) AS ELAPSED_SECONDS,
    A.ROWS_READ,
    A.ROWS_RETURNED,
    A.ROWS_MODIFIED,
    A.TOTAL_CPU_TIME / 1000 AS CPU_TIME_MS,
    SUBSTR(COALESCE(A.STMT_TEXT, ''), 1, 1000) AS SQL_TEXT,
    C.APPLICATION_NAME,
    C.CLIENT_HOSTNAME
FROM TABLE(MON_GET_ACTIVITY(NULL, -2)) AS A
LEFT JOIN TABLE(MON_GET_CONNECTION(NULL, -2)) AS C ON A.APPLICATION_HANDLE = C.APPLICATION_HANDLE
WHERE A.ACTIVITY_STATE IN ('EXECUTING', 'IDLE')
ORDER BY A.TOTAL_CPU_TIME DESC
FETCH FIRST 50 ROWS ONLY
```

---

## 4. Pop-Out Window Design

### 4.1 UI Layout

The pop-out window for a single database should include:

```
┌────────────────────────────────────────────────────────────────┐
│ 🗄️ FKMPRD (DB2)                              ⟳ Refresh  ✕ Close │
│ Instance: DB2 | Status: 🟢 Running | Updated: 13:45:02          │
├────────────────────────────────────────────────────────────────┤
│ ┌──────────────┐ ┌──────────────┐ ┌──────────────┐ ┌──────────┐ │
│ │  Sessions    │ │    Users     │ │   BP Ratio   │ │ DB Size  │ │
│ │     12       │ │      4       │ │    98.7%     │ │  24.5 GB │ │
│ │   ⚙️ 2 exec   │ │   👤 users   │ │   🎯 hit%    │ │   💾     │ │
│ └──────────────┘ └──────────────┘ └──────────────┘ └──────────┘ │
├────────────────────────────────────────────────────────────────┤
│ 📊 Active Statements                                            │
│ ┌────────┬────────┬────────┬───────────┬──────────────────────┐ │
│ │ Handle │ User   │ State  │ Elapsed   │ SQL                  │ │
│ ├────────┼────────┼────────┼───────────┼──────────────────────┤ │
│ │ 12345  │ BATCH1 │ EXEC   │ 45s       │ SELECT * FROM...     │ │
│ │ 12346  │ APPUSER│ IDLE   │ 2s        │ UPDATE ORDERS SET... │ │
│ └────────┴────────┴────────┴───────────┴──────────────────────┘ │
├────────────────────────────────────────────────────────────────┤
│ 🔒 Blocking Sessions                                            │
│ (None detected)                                                 │
├────────────────────────────────────────────────────────────────┤
│ 📈 Top Active Tables (by operations)                            │
│ ┌────────────────────┬─────────┬─────────┬─────────┬──────────┐ │
│ │ Table              │ Reads   │ Inserts │ Updates │ Deletes  │ │
│ ├────────────────────┼─────────┼─────────┼─────────┼──────────┤ │
│ │ FKMPRD.ORDERS      │ 12,456  │ 234     │ 567     │ 12       │ │
│ │ FKMPRD.ORDERLINES  │ 8,234   │ 456     │ 123     │ 8        │ │
│ └────────────────────┴─────────┴─────────┴─────────┴──────────┘ │
├────────────────────────────────────────────────────────────────┤
│ 💿 Buffer Pool Stats                                            │
│ ┌──────────────┬───────────────┬───────────────┬──────────────┐ │
│ │ Pool Name    │ Logical Reads │ Physical Reads│ Hit Ratio    │ │
│ ├──────────────┼───────────────┼───────────────┼──────────────┤ │
│ │ IBMDEFAULTBP │ 1,234,567     │ 12,345        │ 99.00%       │ │
│ │ BP32K        │ 234,567       │ 2,345         │ 99.00%       │ │
│ └──────────────┴───────────────┴───────────────┴──────────────┘ │
├────────────────────────────────────────────────────────────────┤
│ 📁 Tablespace Usage                                             │
│ ┌──────────────┬──────────┬──────────┬──────────┬─────────────┐ │
│ │ Tablespace   │ Total    │ Used     │ Free     │ Used %      │ │
│ ├──────────────┼──────────┼──────────┼──────────┼─────────────┤ │
│ │ USERSPACE1   │ 50.0 GB  │ 24.5 GB  │ 25.5 GB  │ 49.0%       │ │
│ │ TEMPSPACE1   │ 10.0 GB  │ 0.5 GB   │ 9.5 GB   │ 5.0%        │ │
│ └──────────────┴──────────┴──────────┴──────────┴─────────────┘ │
├────────────────────────────────────────────────────────────────┤
│ 🚨 Alerts for FKMPRD (Last 24h)                                 │
│ ┌──────────┬────────────┬──────────────────────────────────────┐ │
│ │ Severity │ Time       │ Message                              │ │
│ ├──────────┼────────────┼──────────────────────────────────────┤ │
│ │ 🔴 ERROR │ 13:45:22   │ SQL0530N: FK constraint violation    │ │
│ │ 🟡 WARN  │ 13:30:15   │ Long query (>60s): SELECT * FROM...  │ │
│ │ 🟡 WARN  │ 12:15:08   │ Buffer pool hit ratio below 95%      │ │
│ │ 🔵 INFO  │ 11:00:00   │ Database backup completed            │ │
│ └──────────┴────────────┴──────────────────────────────────────┘ │
│ Showing 4 of 12 alerts                                          │
├────────────────────────────────────────────────────────────────┤
│ 📜 Recent Diagnostic Entries (Today)                            │
│ ┌────────┬──────────────┬──────────────────────────────────────┐ │
│ │ Level  │ Time         │ Message                              │ │
│ ├────────┼──────────────┼──────────────────────────────────────┤ │
│ │ ERROR  │ 12:34:56     │ SQL0530N: FK constraint violation... │ │
│ │ WARN   │ 12:30:22     │ Log file nearly full...              │ │
│ └────────┴──────────────┴──────────────────────────────────────┘ │
└────────────────────────────────────────────────────────────────┘
```

### 4.2 Filtered Alerts for Database

The pop-out window should include alerts filtered specifically for the current database:

**New Endpoint**: `GET /api/db2/{instanceName}/{databaseName}/alerts`

**Filter Logic**:
```csharp
// In AlertAccumulator or a new Db2AlertService
public List<Alert> GetAlertsForDatabase(string instanceName, string databaseName)
{
    var cutoff = DateTime.UtcNow.AddHours(-24);
    
    return _alerts
        .Where(a => a.Timestamp >= cutoff)
        .Where(a => 
            // Match by database context
            (a.Context != null && a.Context.Contains(databaseName, StringComparison.OrdinalIgnoreCase)) ||
            // Match by instance + database in source
            (a.Source != null && a.Source.Contains($"{instanceName}/{databaseName}", StringComparison.OrdinalIgnoreCase)) ||
            // Match Db2Diag alerts by database field
            (a.MonitorName == "Db2DiagMonitor" && a.Metadata?.GetValueOrDefault("Database") == databaseName) ||
            // Match Db2Instance alerts
            (a.MonitorName == "Db2InstanceMonitor" && 
             a.Metadata?.GetValueOrDefault("Instance") == instanceName &&
             a.Metadata?.GetValueOrDefault("Database") == databaseName)
        )
        .OrderByDescending(a => a.Timestamp)
        .Take(100)
        .ToList();
}
```

**Alert Categories to Include**:
| Alert Type | Source | Filter Key |
|------------|--------|------------|
| Blocking Sessions | Db2InstanceMonitor | `Database` metadata |
| Long Running Queries | Db2InstanceMonitor | `Database` metadata |
| Buffer Pool Critical | Db2InstanceMonitor | `Database` metadata |
| SQL Errors | Db2DiagMonitor | `DatabaseName` field in entry |
| DB2 Warnings | Db2DiagMonitor | `DatabaseName` field in entry |
| DB2 Critical | Db2DiagMonitor | `DatabaseName` field in entry |

**UI Section in Pop-Out Window**:
```
├────────────────────────────────────────────────────────────────┤
│ 🚨 Alerts for FKMPRD (Last 24h)                    [View All →]│
│ ┌──────────┬────────────┬──────────────────────────────────────┐ │
│ │ Severity │ Time       │ Message                              │ │
│ ├──────────┼────────────┼──────────────────────────────────────┤ │
│ │ 🔴 ERROR │ 13:45:22   │ SQL0530N: FK constraint violation    │ │
│ │ 🟡 WARN  │ 13:30:15   │ Long query (>60s): SELECT * FROM...  │ │
│ │ 🟡 WARN  │ 12:15:08   │ Buffer pool hit ratio below 95%      │ │
│ │ 🔵 INFO  │ 11:00:00   │ Database backup completed            │ │
│ └──────────┴────────────┴──────────────────────────────────────┘ │
│ Showing 4 of 12 alerts                          [Show More ↓]  │
├────────────────────────────────────────────────────────────────┤
```

**JavaScript for Fetching Filtered Alerts**:
```javascript
async fetchDatabaseAlerts(instanceName, databaseName) {
    const response = await fetch(
        `/api/db2/${instanceName}/${databaseName}/alerts`
    );
    if (!response.ok) return [];
    return await response.json();
}

renderDatabaseAlerts(alerts) {
    if (!alerts || alerts.length === 0) {
        return `<div class="no-alerts">✅ No alerts in the last 24 hours</div>`;
    }
    
    const severityIcons = {
        'Critical': '🔴',
        'Error': '🔴', 
        'Warning': '🟡',
        'Info': '🔵'
    };
    
    let html = `
        <div class="alerts-section">
            <h3>🚨 Alerts (Last 24h)</h3>
            <table class="alerts-table">
                <thead>
                    <tr>
                        <th>Severity</th>
                        <th>Time</th>
                        <th>Message</th>
                    </tr>
                </thead>
                <tbody>
    `;
    
    for (const alert of alerts.slice(0, 10)) {
        const icon = severityIcons[alert.severity] || '⚪';
        const time = new Date(alert.timestamp).toLocaleTimeString();
        html += `
            <tr class="alert-row alert-${alert.severity.toLowerCase()}">
                <td>${icon} ${alert.severity}</td>
                <td>${time}</td>
                <td class="alert-message" title="${this.escapeHtml(alert.message)}">
                    ${this.escapeHtml(alert.message.substring(0, 80))}${alert.message.length > 80 ? '...' : ''}
                </td>
            </tr>
        `;
    }
    
    html += `
                </tbody>
            </table>
            ${alerts.length > 10 ? `<div class="show-more">Showing 10 of ${alerts.length} alerts</div>` : ''}
        </div>
    `;
    
    return html;
}
```

### 4.4 Dashboard JavaScript Implementation

```javascript
// Add to dashboard.js

async openDb2PopOutWindow(instanceName, databaseName) {
    const windowName = `db2_${instanceName}_${databaseName}`;
    const width = 900;
    const height = 800;
    const left = (screen.width - width) / 2;
    const top = (screen.height - height) / 2;
    
    // Open pop-out window
    const popOut = window.open(
        `/db2-detail.html?instance=${instanceName}&database=${databaseName}`,
        windowName,
        `width=${width},height=${height},left=${left},top=${top},resizable=yes,scrollbars=yes`
    );
    
    if (popOut) {
        popOut.focus();
    }
}

// Button in database panel
renderDb2DatabasePopOutButton(instanceName, databaseName) {
    return `
        <button class="btn-popout" 
                onclick="dashboard.openDb2PopOutWindow('${instanceName}', '${databaseName}')"
                title="Open in new window">
            🔲 Pop Out
        </button>
    `;
}
```

### 4.5 Code Reuse Strategy - Shared Alert Components

**Recommendation**: Extract the existing `renderAlerts` logic from `dashboard.js` into a reusable module that both the main dashboard and pop-out window can consume.

**Current Dashboard Alerts Features** (in `dashboard.js`):
- Severity normalization (`critical`, `warning`, `informational`)
- Sorting by severity then timestamp
- Expandable detail rows with metadata
- Context extraction from metadata
- Copy to Markdown/JSON buttons
- Modal popup for full details

**Approach 1: Extract Shared Module** ✅ Recommended

Create `wwwroot/js/components/alerts-renderer.js`:

```javascript
// alerts-renderer.js - Shared alert rendering component

class AlertsRenderer {
    constructor(options = {}) {
        this.maxAlerts = options.maxAlerts || 50;
        this.showCopyButtons = options.showCopyButtons !== false;
        this.showExpandable = options.showExpandable !== false;
        this.showModal = options.showModal !== false;
    }
    
    /**
     * Normalizes severity from string or number to consistent string
     */
    normalizeSeverity(sev) {
        if (typeof sev === 'string') return sev.toLowerCase();
        const names = ['informational', 'warning', 'critical'];
        return names[sev] || 'unknown';
    }
    
    getSeverityClass(sev) {
        const name = this.normalizeSeverity(sev);
        if (name === 'critical') return 'critical';
        if (name === 'warning') return 'warning';
        return 'info';
    }
    
    getSeverityIcon(sev) {
        const name = this.normalizeSeverity(sev);
        if (name === 'critical') return '🔴';
        if (name === 'warning') return '🟡';
        return '🔵';
    }
    
    /**
     * Sorts alerts by severity (critical first), then timestamp (newest first)
     */
    sortAlerts(alerts) {
        const severityOrder = { critical: 0, warning: 1, informational: 2 };
        return [...alerts].sort((a, b) => {
            const aSev = severityOrder[this.normalizeSeverity(a.severity)] ?? 3;
            const bSev = severityOrder[this.normalizeSeverity(b.severity)] ?? 3;
            if (aSev !== bSev) return aSev - bSev;
            return new Date(b.timestamp) - new Date(a.timestamp);
        });
    }
    
    /**
     * Extracts display context from alert metadata
     */
    extractContext(alert) {
        if (!alert.metadata) return '';
        const parts = [];
        if (alert.metadata.Database) parts.push(`DB: ${alert.metadata.Database}`);
        if (alert.metadata.Instance) parts.push(`Instance: ${alert.metadata.Instance}`);
        if (alert.metadata.Source) parts.push(alert.metadata.Source);
        return parts.join(' | ');
    }
    
    /**
     * Renders alerts to a table body element
     * @param {HTMLElement} container - The container element (usually tbody)
     * @param {Array} alerts - Array of alert objects
     * @param {Object} options - Render options
     */
    render(container, alerts, options = {}) {
        if (!container || !alerts) return;
        
        const sorted = this.sortAlerts(alerts).slice(0, this.maxAlerts);
        
        container.innerHTML = sorted.map((alert, idx) => {
            const sevName = this.normalizeSeverity(alert.severity);
            const sevClass = this.getSeverityClass(alert.severity);
            const sevIcon = this.getSeverityIcon(alert.severity);
            const displayName = sevName.charAt(0).toUpperCase() + sevName.slice(1);
            const hasMetadata = alert.metadata && Object.keys(alert.metadata).length > 0;
            const hasDetails = (alert.details || hasMetadata) && this.showExpandable;
            const context = this.extractContext(alert);
            const time = this.formatTime(alert.timestamp);
            
            return `
                <tr class="alert-row ${hasDetails ? 'expandable' : ''}" data-alert-idx="${idx}">
                    <td><span class="severity-badge ${sevClass}">${sevIcon} ${displayName}</span></td>
                    <td class="alert-source-cell">${alert.monitorName?.replace('Monitor', '') || '-'}</td>
                    <td class="alert-message-cell">
                        ${this.escapeHtml(alert.message || '-')}
                        ${hasDetails ? '<span class="expand-indicator">▶</span>' : ''}
                    </td>
                    <td class="alert-context-cell">${context}</td>
                    <td class="alert-time-cell">${time}</td>
                </tr>
                ${hasDetails ? `
                <tr class="alert-details-row hidden" data-alert-details-idx="${idx}">
                    <td colspan="5">
                        <div class="alert-details-content">
                            ${this.formatDetails(alert)}
                        </div>
                    </td>
                </tr>
                ` : ''}
            `;
        }).join('');
        
        // Store for event handlers
        container._renderedAlerts = sorted;
        
        // Bind expandable row handlers
        if (this.showExpandable) {
            this.bindExpandHandlers(container);
        }
    }
    
    formatTime(timestamp) {
        if (!timestamp) return '-';
        const date = new Date(timestamp);
        return date.toLocaleTimeString();
    }
    
    formatDetails(alert) {
        let html = '';
        if (alert.details) {
            html += `<div class="alert-detail-text">${this.escapeHtml(alert.details)}</div>`;
        }
        if (alert.metadata) {
            html += '<div class="alert-metadata"><table>';
            for (const [key, value] of Object.entries(alert.metadata)) {
                html += `<tr><td class="meta-key">${this.escapeHtml(key)}:</td><td class="meta-value">${this.escapeHtml(String(value))}</td></tr>`;
            }
            html += '</table></div>';
        }
        return html;
    }
    
    escapeHtml(text) {
        const div = document.createElement('div');
        div.textContent = text;
        return div.innerHTML;
    }
    
    bindExpandHandlers(container) {
        container.querySelectorAll('.alert-row.expandable').forEach(row => {
            row.addEventListener('click', (e) => {
                if (e.target.closest('.btn-icon')) return;
                const idx = row.dataset.alertIdx;
                const detailsRow = container.querySelector(`[data-alert-details-idx="${idx}"]`);
                if (detailsRow) {
                    detailsRow.classList.toggle('hidden');
                    const indicator = row.querySelector('.expand-indicator');
                    if (indicator) {
                        indicator.textContent = detailsRow.classList.contains('hidden') ? '▶' : '▼';
                    }
                }
            });
        });
    }
}

// Export for both module and global use
if (typeof module !== 'undefined' && module.exports) {
    module.exports = AlertsRenderer;
} else {
    window.AlertsRenderer = AlertsRenderer;
}
```

**Usage in Main Dashboard** (`dashboard.js`):
```javascript
// Initialize once
this.alertsRenderer = new AlertsRenderer({ maxAlerts: 100, showModal: true });

// In renderAlerts()
renderAlerts() {
    const alerts = this.currentSnapshot?.alerts || [];
    const tbody = document.querySelector('#alertsPanel tbody');
    this.alertsRenderer.render(tbody, alerts);
}
```

**Usage in Pop-Out Window** (`db2-detail.js`):
```javascript
// Initialize with different options
this.alertsRenderer = new AlertsRenderer({ maxAlerts: 20, showModal: false });

// Render filtered alerts
async refreshAlerts() {
    const alerts = await this.fetchAlerts();
    const tbody = document.querySelector('#alerts-panel tbody');
    this.alertsRenderer.render(tbody, alerts);
}
```

**Benefits**:
- ✅ Single source of truth for alert rendering
- ✅ Consistent look and feel across main dashboard and pop-out
- ✅ Easy to add new features (affects both views)
- ✅ Smaller file sizes (no duplication)
- ✅ CSS shared via `dashboard.css`

---

### 4.6 New HTML Page: `db2-detail.html`

Create a dedicated page for the pop-out window with its own refresh logic:
- Auto-refresh every 10 seconds (configurable)
- Independent of main dashboard
- "Refresh Now" button for manual refresh
- Connection to same API endpoints
- **Includes filtered alerts for the specific database**
- **Reuses `AlertsRenderer` component from shared module**

```javascript
// db2-detail.js - Pop-out window initialization
// Uses shared AlertsRenderer component

class Db2DetailWindow {
    constructor() {
        this.instanceName = new URLSearchParams(window.location.search).get('instance');
        this.databaseName = new URLSearchParams(window.location.search).get('database');
        this.refreshInterval = 10000; // 10 seconds default
        this.autoRefresh = true;
        this.refreshTimer = null;
        
        // Use shared AlertsRenderer component
        this.alertsRenderer = new AlertsRenderer({ 
            maxAlerts: 25, 
            showCopyButtons: true,
            showExpandable: true,
            showModal: false  // No modal in pop-out (already a separate window)
        });
    }
    
    async initialize() {
        document.title = `DB2: ${this.databaseName} (${this.instanceName})`;
        
        // Initial data load
        await this.refreshAllData();
        
        // Start auto-refresh
        this.startAutoRefresh();
        
        // Bind UI events
        this.bindEvents();
    }
    
    async refreshAllData() {
        this.setLoadingState(true);
        
        try {
            // Fetch all data in parallel
            const [stateData, sessionsData, alertsData] = await Promise.all([
                this.fetchDatabaseState(),
                this.fetchSessions(),
                this.fetchAlerts()
            ]);
            
            // Render all sections
            this.renderHeader(stateData);
            this.renderSessionsPanel(stateData, sessionsData);
            this.renderPerformancePanel(stateData);
            this.renderActivityPanel(stateData);
            this.renderAlertsPanel(alertsData);
            this.renderDiagPanel(stateData);
            
            this.updateLastRefreshTime();
        } catch (error) {
            console.error('Failed to refresh data:', error);
            this.showError(`Failed to load data: ${error.message}`);
        } finally {
            this.setLoadingState(false);
        }
    }
    
    async fetchDatabaseState() {
        const response = await fetch(
            `/api/db2/${this.instanceName}/${this.databaseName}/state`
        );
        if (!response.ok) throw new Error(`State API returned ${response.status}`);
        return await response.json();
    }
    
    async fetchSessions() {
        const response = await fetch(
            `/api/db2/${this.instanceName}/${this.databaseName}/sessions`
        );
        if (!response.ok) return [];
        return await response.json();
    }
    
    async fetchAlerts() {
        const response = await fetch(
            `/api/db2/${this.instanceName}/${this.databaseName}/alerts`
        );
        if (!response.ok) return [];
        return await response.json();
    }
    
    /**
     * Renders alerts using the shared AlertsRenderer component
     * Same look & feel as main dashboard alerts
     */
    renderAlertsPanel(alerts) {
        const container = document.getElementById('alerts-panel');
        if (!container) return;
        
        // Render header
        let headerHtml = `
            <div class="panel-header">
                <h3>🚨 Alerts for ${this.databaseName} (Last 24h)</h3>
                <span class="badge ${alerts.length > 0 ? 'has-alerts' : ''}">${alerts.length}</span>
            </div>
        `;
        
        if (alerts.length === 0) {
            container.innerHTML = headerHtml + '<div class="no-data">✅ No alerts in the last 24 hours</div>';
            return;
        }
        
        // Create table structure
        container.innerHTML = headerHtml + `
            <table class="data-table alerts-table">
                <thead>
                    <tr>
                        <th>Severity</th>
                        <th>Source</th>
                        <th>Message</th>
                        <th>Context</th>
                        <th>Time</th>
                    </tr>
                </thead>
                <tbody id="alerts-tbody"></tbody>
            </table>
            ${alerts.length > 25 ? `<div class="show-more">Showing 25 of ${alerts.length} alerts</div>` : ''}
        `;
        
        // Use shared renderer for consistent display
        const tbody = document.getElementById('alerts-tbody');
        this.alertsRenderer.render(tbody, alerts);
    }
    
    startAutoRefresh() {
        if (this.refreshTimer) {
            clearInterval(this.refreshTimer);
        }
        if (this.autoRefresh) {
            this.refreshTimer = setInterval(() => this.refreshAllData(), this.refreshInterval);
        }
    }
    
    stopAutoRefresh() {
        if (this.refreshTimer) {
            clearInterval(this.refreshTimer);
            this.refreshTimer = null;
        }
    }
    
    bindEvents() {
        // Refresh button
        document.getElementById('btn-refresh')?.addEventListener('click', () => {
            this.refreshAllData();
        });
        
        // Auto-refresh toggle
        document.getElementById('auto-refresh-toggle')?.addEventListener('change', (e) => {
            this.autoRefresh = e.target.checked;
            if (this.autoRefresh) {
                this.startAutoRefresh();
            } else {
                this.stopAutoRefresh();
            }
        });
    }
    
    // ... other render methods (renderHeader, renderSessionsPanel, etc.)
}

// Initialize when DOM is ready
document.addEventListener('DOMContentLoaded', () => {
    const detailWindow = new Db2DetailWindow();
    detailWindow.initialize();
});
```

**HTML Script Includes** (`db2-detail.html`):
```html
<!DOCTYPE html>
<html lang="en">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>DB2 Database Details</title>
    <link rel="stylesheet" href="/css/dashboard.css">
</head>
<body>
    <div class="popout-container">
        <header class="popout-header">
            <h1 id="db-title">Loading...</h1>
            <div class="controls">
                <button id="btn-refresh" class="btn btn-primary">🔄 Refresh</button>
                <label class="toggle-label">
                    <input type="checkbox" id="auto-refresh-toggle" checked>
                    Auto-refresh (10s)
                </label>
                <span id="last-refresh">Last updated: --:--:--</span>
            </div>
        </header>
        
        <!-- Sessions Panel -->
        <section id="sessions-panel" class="panel"></section>
        
        <!-- Performance Panel -->
        <section id="performance-panel" class="panel"></section>
        
        <!-- Alerts Panel - Uses shared AlertsRenderer -->
        <section id="alerts-panel" class="panel"></section>
        
        <!-- Diagnostics Panel -->
        <section id="diag-panel" class="panel"></section>
    </div>
    
    <!-- Shared components first -->
    <script src="/js/components/alerts-renderer.js"></script>
    <!-- Then page-specific JS -->
    <script src="/js/db2-detail.js"></script>
</body>
</html>
```

---

## 5. Additional Suggestions

### 5.1 New Metrics to Add

| Metric | Query Source | Dashboard Display |
|--------|--------------|-------------------|
| **Sort Heap Usage** | `MON_GET_DATABASE()` | Gauge (% of available) |
| **Log Usage** | `MON_GET_TRANSACTION_LOG()` | Gauge with alert threshold |
| **Package Cache Hit Ratio** | `MON_GET_PKG_CACHE_STMT()` | Percentage with trend |
| **Deadlock Count** | `MON_GET_DATABASE()` | Counter (since last restart) |
| **Lock Escalations** | `MON_GET_DATABASE()` | Counter with alert |
| **Table Reorg Required** | `ADMIN_GET_TAB_COMPRESS_INFO()` | List of tables |

### 5.2 Query for Sort Heap and Log Usage

```sql
SELECT 
    SORT_HEAP_TOP / 1024 AS SORT_HEAP_MB,
    SORT_SHARE_HEAP_TOP / 1024 AS SHARED_SORT_MB,
    TOTAL_LOG_USED_KB / 1024 AS LOG_USED_MB,
    TOTAL_LOG_AVAILABLE_KB / 1024 AS LOG_AVAILABLE_MB,
    CASE WHEN TOTAL_LOG_AVAILABLE_KB > 0
         THEN DECIMAL(TOTAL_LOG_USED_KB * 100.0 / TOTAL_LOG_AVAILABLE_KB, 5, 2)
         ELSE 0.00
    END AS LOG_USED_PCT,
    DEADLOCKS,
    LOCK_ESCALS,
    LOCK_TIMEOUTS,
    LOCK_WAIT_TIME / 1000 AS LOCK_WAIT_MS
FROM TABLE(MON_GET_DATABASE(-2)) AS DB
```

### 5.3 Connection Timeout Detection

Add monitoring for connections that have been idle too long:
```sql
SELECT 
    APPLICATION_HANDLE,
    APPLICATION_NAME,
    SESSION_AUTH_ID,
    CLIENT_HOSTNAME,
    CONNECTION_STATE,
    TIMESTAMPDIFF(4, CURRENT_TIMESTAMP - CONNECTION_START_TIME) AS IDLE_MINUTES
FROM TABLE(MON_GET_CONNECTION(NULL, -2)) AS C
WHERE CONNECTION_STATE = 'IDLE'
  AND TIMESTAMPDIFF(4, CURRENT_TIMESTAMP - CONNECTION_START_TIME) > 30
ORDER BY IDLE_MINUTES DESC
```

### 5.4 Historical Trend Data

Consider adding a lightweight time-series storage for:
- Session count over time (hourly averages)
- Buffer pool hit ratio trend
- Lock wait events timeline
- Query throughput (queries/minute)

This would enable:
- 24-hour trend graphs in pop-out window
- Anomaly detection (sudden spike in sessions)
- Capacity planning insights

---

## 6. Implementation Priority

### Phase 1 (Quick Wins)
1. ✅ Fix session counter to exclude system sessions
2. ✅ Add "Pop Out" button to each database panel
3. ✅ Create `/api/db2/{instance}/{db}/state` endpoint
4. ✅ Create `/api/db2/{instance}/{db}/alerts` endpoint for filtered alerts
5. ⬜ Extract `AlertsRenderer` to shared component (`wwwroot/js/components/alerts-renderer.js`)

### Phase 2 (Enhanced Monitoring)
4. Add active statements view with SQL text
5. Add blocking chain visualization
6. Add top tables by activity

### Phase 3 (Advanced Features)
7. Add buffer pool per-pool breakdown
8. Add tablespace usage monitoring
9. Add historical trend storage
10. Add log usage monitoring

---

## 7. API Controller Implementation

```csharp
// Db2DetailController.cs
[ApiController]
[Route("api/db2")]
public class Db2DetailController : ControllerBase
{
    private readonly Db2InstanceDataCollector _collector;
    private readonly Db2DiagMonitor _diagMonitor;
    private readonly IAlertAccumulator _alertAccumulator;
    
    public Db2DetailController(
        Db2InstanceDataCollector collector,
        Db2DiagMonitor diagMonitor,
        IAlertAccumulator alertAccumulator)
    {
        _collector = collector;
        _diagMonitor = diagMonitor;
        _alertAccumulator = alertAccumulator;
    }
    
    [HttpGet("{instanceName}/{databaseName}/state")]
    public async Task<ActionResult<Db2DatabaseDetailedState>> GetDatabaseState(
        string instanceName, 
        string databaseName,
        CancellationToken cancellationToken)
    {
        var state = await _collector.CollectDatabaseDetailedStateAsync(
            instanceName, databaseName, cancellationToken);
        
        // Add diag summary for this specific database
        state = state with 
        { 
            DiagSummary = _diagMonitor.GetTodaysDiagSummary(databaseName),
            RecentAlerts = GetAlertsForDatabase(instanceName, databaseName)
        };
        
        return Ok(state);
    }
    
    [HttpGet("{instanceName}/{databaseName}/sessions")]
    public async Task<ActionResult<List<Db2SessionDetail>>> GetSessions(
        string instanceName, 
        string databaseName,
        CancellationToken cancellationToken)
    {
        return Ok(await _collector.CollectSessionDetailsAsync(
            instanceName, databaseName, cancellationToken));
    }
    
    [HttpGet("{instanceName}/{databaseName}/activity")]
    public async Task<ActionResult<List<Db2ActivityDetail>>> GetActivity(
        string instanceName, 
        string databaseName,
        CancellationToken cancellationToken)
    {
        return Ok(await _collector.CollectActivityAsync(
            instanceName, databaseName, cancellationToken));
    }
    
    [HttpGet("{instanceName}/{databaseName}/top-tables")]
    public async Task<ActionResult<List<Db2TableActivity>>> GetTopTables(
        string instanceName, 
        string databaseName,
        CancellationToken cancellationToken)
    {
        return Ok(await _collector.CollectTopTablesAsync(
            instanceName, databaseName, cancellationToken));
    }
    
    [HttpGet("{instanceName}/{databaseName}/alerts")]
    public ActionResult<List<Alert>> GetDatabaseAlerts(
        string instanceName, 
        string databaseName)
    {
        return Ok(GetAlertsForDatabase(instanceName, databaseName));
    }
    
    /// <summary>
    /// Gets alerts filtered for a specific database instance.
    /// Matches alerts by:
    /// - Db2DiagMonitor entries with DatabaseName_DB matching the database
    /// - Db2InstanceMonitor alerts with matching instance/database metadata
    /// - Alert context or source containing the database name
    /// </summary>
    private List<Alert> GetAlertsForDatabase(string instanceName, string databaseName)
    {
        var cutoff = DateTime.UtcNow.AddHours(-24);
        var allAlerts = _alertAccumulator.GetAlerts();
        
        return allAlerts
            .Where(a => a.Timestamp >= cutoff)
            .Where(a => MatchesDatabaseContext(a, instanceName, databaseName))
            .OrderByDescending(a => a.Timestamp)
            .Take(100)
            .ToList();
    }
    
    private bool MatchesDatabaseContext(Alert alert, string instanceName, string databaseName)
    {
        // Check Db2DiagMonitor alerts - match by DatabaseName_DB property
        if (alert.MonitorName == "Db2DiagMonitor")
        {
            if (alert.Metadata != null)
            {
                // Check DatabaseName_DB property (format: "XFKMPRD" or similar)
                if (alert.Metadata.TryGetValue("DatabaseName_DB", out var dbNameDb))
                {
                    return dbNameDb?.Equals(databaseName, StringComparison.OrdinalIgnoreCase) == true;
                }
                // Fallback: check Database property
                if (alert.Metadata.TryGetValue("Database", out var db))
                {
                    return db?.Equals(databaseName, StringComparison.OrdinalIgnoreCase) == true;
                }
            }
        }
        
        // Check Db2InstanceMonitor alerts - match by instance + database metadata
        if (alert.MonitorName == "Db2InstanceMonitor")
        {
            if (alert.Metadata != null)
            {
                var matchesInstance = alert.Metadata.TryGetValue("Instance", out var inst) &&
                    inst?.Equals(instanceName, StringComparison.OrdinalIgnoreCase) == true;
                var matchesDb = alert.Metadata.TryGetValue("Database", out var dbName) &&
                    dbName?.Equals(databaseName, StringComparison.OrdinalIgnoreCase) == true;
                return matchesInstance && matchesDb;
            }
        }
        
        // Fallback: check Context or Source for database name
        if (!string.IsNullOrEmpty(alert.Context) && 
            alert.Context.Contains(databaseName, StringComparison.OrdinalIgnoreCase))
        {
            return true;
        }
        
        if (!string.IsNullOrEmpty(alert.Source) && 
            alert.Source.Contains($"{instanceName}/{databaseName}", StringComparison.OrdinalIgnoreCase))
        {
            return true;
        }
        
        return false;
    }
}
```

---

## 8. Configuration Updates

Add to `appsettings.json`:
```json
{
  "Db2InstanceMonitoring": {
    "Enabled": true,
    "CollectionIntervalSeconds": 60,
    "CollectSessionCounts": true,
    "CollectLongRunningQueries": true,
    "CollectBlockingSessions": true,
    "CollectBufferPoolStats": true,
    "CollectTableActivity": true,
    "CollectTablespaceUsage": true,
    "PopOutWindow": {
      "RefreshIntervalSeconds": 10,
      "MaxActiveStatements": 50,
      "MaxTopTables": 10
    },
    "Thresholds": {
      "LongRunningQueryThresholdSeconds": 60,
      "IdleConnectionThresholdMinutes": 30,
      "BufferPoolHitRatioCritical": 90.0,
      "BufferPoolHitRatioWarning": 95.0,
      "LogUsageWarningPercent": 70,
      "LogUsageCriticalPercent": 85,
      "TablespaceUsageWarningPercent": 80,
      "TablespaceUsageCriticalPercent": 90
    }
  }
}
```

---

## Configuration Options

### Enable/Disable Pop-Out Functionality

The pop-out button can be disabled via the agent's `appsettings.json`:

```json
{
  "Surveillance": {
    "Db2InstanceMonitoring": {
      "EnableDashboardPopout": false
    }
  }
}
```

| Setting | Type | Default | Description |
|---------|------|---------|-------------|
| `EnableDashboardPopout` | boolean | `true` | When `false`, hides the "Pop Out" button in the dashboard UI |

**API Endpoint**: `GET /api/db2/config`

Returns the dashboard configuration from the agent:
```json
{
  "enablePopout": true
}
```

The dashboard fetches this configuration when loading a server and conditionally renders the pop-out button.

---

## Summary

This enhancement proposal provides:
1. **Fixed session counting** - distinguishing user vs system sessions
2. **Pop-out window** - independent per-database monitoring window
3. **New API endpoints** - granular, database-specific data retrieval
4. **Enhanced SQL queries** - leveraging DB2 MON_GET_* functions
5. **Additional metrics** - tablespace, buffer pools, table activity
6. **Phased implementation** - prioritized delivery plan
7. **Configurable pop-out** - can be disabled via appsettings.json

The implementation draws heavily from proven SQL patterns in WindowsDb2Editor and aligns with IBM DB2 best practices for monitoring.
