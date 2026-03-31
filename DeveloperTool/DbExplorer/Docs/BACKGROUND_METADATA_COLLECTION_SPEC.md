# Background Metadata Collection - Complete Specification from NEXTSTEPS.md

**Source:** NEXTSTEPS.md Feature #5 + SYSCAT Table Relationships Section  
**Purpose:** Automatic metadata collection in background without blocking UI  
**Reusability:** JSON files cached with version names for offline reference

---

## 📊 WHAT NEXTSTEPS.MD SPECIFIES

### Overview (Feature #5)

**Requirements:**
1. After connection, automatically query DB2 version
2. Query SYSCAT.TABLES to get all system catalog tables
3. **Save metadata to JSON files for offline reference**
4. **Run in background thread without blocking UI**

**Key Points:**
- Metadata collected automatically on every connection
- Runs in background (non-blocking)
- Saved to JSON files in `%LOCALAPPDATA%\DbExplorer\metadata\`
- **Filename includes DB2 version** for version-specific caching
- **Filename includes profile name** for connection-specific caching
- Errors don't interrupt user (non-critical background task)

---

## 🔄 THREE-PHASE METADATA STRATEGY

### Phase 1: Initial Connection (Background Thread)
**Timing:** Triggered immediately after successful DB2 connection  
**Duration:** < 10 seconds  
**Thread:** Background Task.Run() (non-blocking)

**Steps:**

#### Step 1: DB2 Version Detection (< 1 second)
```sql
SELECT PROD_RELEASE 
FROM SYSIBMADM.ENV_PROD_INFO 
WHERE LICENSE_INSTALLED = 'Y'
```

**Result:** Version string (e.g., "DB2 v11.5.0.0")  
**Cleaned:** "11.5" (extracted major.minor)  
**Used for:** Filename prefix

#### Step 2: Core Catalog Tables (< 5 seconds)
```sql
-- Schema Information
SELECT * FROM SYSCAT.SCHEMATA
WHERE SCHEMANAME NOT IN ('SYSIBM', 'SYSIBMADM', ...)  -- Filter system schemas

-- Table Metadata
SELECT * FROM SYSCAT.TABLES
WHERE TABSCHEMA = 'SYSCAT'  -- Get SYSCAT table definitions
ORDER BY TABNAME

-- All Application Tables
SELECT * FROM SYSCAT.TABLES
WHERE TABSCHEMA NOT IN (system schemas)  -- User schemas only

-- Column Definitions for All Tables
SELECT * FROM SYSCAT.COLUMNS
WHERE TABSCHEMA NOT IN (system schemas)
ORDER BY TABSCHEMA, TABNAME, COLNO
```

#### Step 3: Relationship Tables (< 10 seconds)
```sql
-- Primary Keys
SELECT * FROM SYSCAT.KEYCOLUSE
WHERE TABSCHEMA NOT IN (system schemas)

-- Foreign Keys
SELECT * FROM SYSCAT.REFERENCES
WHERE TABSCHEMA NOT IN (system schemas)

-- Indexes
SELECT * FROM SYSCAT.INDEXES
WHERE TABSCHEMA NOT IN (system schemas)

-- Index Columns
SELECT * FROM SYSCAT.INDEXCOLUSE
WHERE INDSCHEMA NOT IN (system schemas)
```

**Saved to:** `db2_syscat_{version}_{profileName}.json`

---

### Phase 2: On-Demand Loading (Lazy Load)
**Trigger:** When user clicks on specific objects in UI  
**Purpose:** Load detailed metadata only when needed

**Table Details** (When user clicks a table):
```sql
-- Full column details
SELECT * FROM SYSCAT.COLUMNS
WHERE TABSCHEMA = '{schema}' AND TABNAME = '{table}'
ORDER BY COLNO

-- Indexes for this table
SELECT * FROM SYSCAT.INDEXES
WHERE TABSCHEMA = '{schema}' AND TABNAME = '{table}'

-- Foreign keys FROM this table
SELECT * FROM SYSCAT.REFERENCES
WHERE TABSCHEMA = '{schema}' AND TABNAME = '{table}'

-- Foreign keys TO this table (incoming)
SELECT * FROM SYSCAT.REFERENCES
WHERE REFTABSCHEMA = '{schema}' AND REFTABNAME = '{table}'

-- Triggers on this table
SELECT * FROM SYSCAT.TRIGGERS
WHERE TABSCHEMA = '{schema}' AND TABNAME = '{table}'
```

**Saved to:** `db2_table_{schema}_{table}_{version}_{profileName}.json`

**Schema Navigation** (When user expands schema):
- List of tables, views, procedures, functions in that schema
- Object counts and statistics
- Loaded from cached JSON if available

**View Definitions** (When user clicks a view):
```sql
SELECT * FROM SYSCAT.VIEWS
WHERE VIEWSCHEMA = '{schema}' AND VIEWNAME = '{view}'
```

**Procedure/Function Details** (When user clicks routine):
```sql
SELECT * FROM SYSCAT.ROUTINES
WHERE ROUTINESCHEMA = '{schema}' AND ROUTINENAME = '{routine}'
```

---

### Phase 3: Real-Time Monitoring (On-Demand)
**Trigger:** When user opens monitoring panels  
**Purpose:** Current state, not cached

**Lock Information:**
```sql
SELECT * FROM SYSIBMADM.SNAPLOCK
-- Refreshed every 5 seconds when Lock Monitor panel open
```

**Active Sessions:**
```sql
SELECT * FROM SYSIBMADM.SNAPAPPL_INFO
-- Refreshed every 10 seconds when Sessions panel open
```

---

## 📂 FILE NAMING PATTERN (From NEXTSTEPS.md)

### SYSCAT Metadata (System Tables)
**Filename:** `db2_syscat_{version}_{profileName}.json`

**Examples:**
- `db2_syscat_11.5_ILOGTST.json`
- `db2_syscat_11.1_PRODUCTION.json`
- `db2_syscat_10.5_TESTDB.json`

**Contents:**
```json
{
  "CollectedAt": "2025-11-19T22:00:00Z",
  "DB2Version": "11.5",
  "RowCount": 150,
  "Columns": [
    { "ColumnName": "TABSCHEMA", "DataType": "String" },
    { "ColumnName": "TABNAME", "DataType": "String" },
    ...
  ],
  "Data": [
    {
      "TABSCHEMA": "SYSCAT",
      "TABNAME": "TABLES",
      "TYPE": "T",
      ...
    },
    ...
  ]
}
```

### Table-Specific Metadata
**Filename:** `db2_table_{schema}_{table}_{version}_{profileName}.json`

**Examples:**
- `db2_table_FK_CUSTOMERS_11.5_PRODUCTION.json`
- `db2_table_APP_SESSIONS_11.5_TESTDB.json`

**Contents:**
```json
{
  "Table": {
    "Schema": "FK",
    "Name": "CUSTOMERS"
  },
  "CollectedAt": "2025-11-19T22:00:00Z",
  "DB2Version": "11.5",
  "Columns": [
    {
      "COLNAME": "CUSTOMER_ID",
      "TYPENAME": "INTEGER",
      "LENGTH": 4,
      "NULLS": "N",
      "DEFAULT": null,
      "REMARKS": "Unique customer identifier"
    },
    ...
  ],
  "Indexes": [
    {
      "INDNAME": "PK_CUSTOMERS",
      "UNIQUERULE": "P",
      "COLNAMES": "CUSTOMER_ID",
      ...
    },
    ...
  ]
}
```

---

## 🚀 BACKGROUND COLLECTION IMPLEMENTATION (From NEXTSTEPS.md)

### Integration with Connection Flow

**File:** `Controls/ConnectionTabControl.xaml.cs`  
**Method:** `ConnectToDatabase()`

```csharp
private async Task ConnectToDatabase()
{
    Logger.Info($"Connecting to database: {_connection.GetDisplayName()}");
    StatusText.Text = "Connecting...";

    try
    {
        // Open connection
        await _connectionManager.OpenAsync();
        
        StatusText.Text = $"Connected to {_connection.GetDisplayName()}";
        Logger.Info("Database connection established");

        // RBAC: Update access level indicator
        UpdateAccessLevelIndicator();

        // Load database objects
        await LoadDatabaseObjectsAsync();
        
        // Load query history
        RefreshQueryHistory();
        
        // ============================================================
        // BACKGROUND METADATA COLLECTION (Feature #5)
        // ============================================================
        // After successful connection, start metadata collection in background
        // This runs without blocking the UI
        _ = Task.Run(async () =>
        {
            try
            {
                Logger.Info("Starting background metadata collection");
                
                var metadataService = new DB2MetadataService();
                
                // Collect SYSCAT metadata
                await metadataService.CollectMetadataAsync(
                    _connectionManager, 
                    _connection.ProfileName ?? _connection.GetDisplayName());
                
                Logger.Info("Background metadata collection completed");
            }
            catch (Exception ex)
            {
                Logger.Error(ex, "Background metadata collection failed");
                // DON'T show error to user - this is non-critical background task
                // User can still use the application normally
            }
        });
        // ============================================================
    }
    catch (Exception ex)
    {
        Logger.Error(ex, "Failed to connect to database");
        StatusText.Text = "Connection failed";
        MessageBox.Show($"Failed to connect: {ex.Message}", "Connection Error",
            MessageBoxButton.OK, MessageBoxImage.Error);
    }
}
```

**Key Points:**
- `_ = Task.Run(async () => ...)` - Fire-and-forget background task
- Doesn't block UI or connection
- Errors logged but not shown to user
- User can immediately start working while metadata collects

---

## 💾 METADATA REUSABILITY STRATEGY

### How Cached Metadata Is Reused

#### 1. Check for Existing Metadata Before Collecting

**In DB2MetadataService.cs:**
```csharp
private async Task SaveMetadataAsync(string fileName, DataTable dataTable, string version)
{
    var filePath = Path.Combine(_metadataFolder, fileName);
    Logger.Debug("Saving metadata to: {File}", filePath);
    
    // ============================================
    // CHECK IF FILE ALREADY EXISTS AND HAS DATA
    // ============================================
    if (File.Exists(filePath))
    {
        var fileInfo = new FileInfo(filePath);
        if (fileInfo.Length > 0)
        {
            Logger.Info("Metadata file already exists and contains data, skipping: {File}", fileName);
            return;  // DON'T re-collect if already have it
        }
    }
    
    // Only collect if file doesn't exist or is empty
    // ... rest of collection code ...
}
```

**This means:**
- First connection to TESTDB (v11.5): Collects and saves `db2_syscat_11.5_TESTDB.json`
- Second connection to TESTDB (v11.5): **Skips collection** (file exists)
- Connection to PRODDB (v11.5): **Reuses** same SYSCAT structure (same version)
- Connection to OLDDB (v10.5): Collects new file for v10.5

#### 2. Version-Based Caching

**Same DB2 Version = Same SYSCAT Structure:**
- All DB2 11.5 databases have identical SYSCAT tables
- File `db2_syscat_11.5_{any profile}.json` is reusable
- Only need to collect once per DB2 version

**Example:**
```
First connection to TESTDB (11.5):
  → Creates: db2_syscat_11.5_TESTDB.json
  → Contains: All SYSCAT.TABLES structure
  
Second connection to PRODDB (11.5):
  → Finds: db2_syscat_11.5_PRODDB.json doesn't exist
  → Collects: New file (but same structure as TESTDB)
  → Could be optimized to reuse TESTDB file
  
Connection to DEVDB (10.5):
  → Creates: db2_syscat_10.5_DEVDB.json
  → Different version = different SYSCAT structure
```

#### 3. Application Schema Metadata (User Tables)

**These are connection-specific:**
- `db2_table_FK_CUSTOMERS_11.5_PRODUCTION.json`
- `db2_table_APP_SESSIONS_11.5_TESTDB.json`

**NOT reusable across databases** (each DB has different schemas/tables)

---

## 🔍 WHAT'S COLLECTED AND WHEN

### Background Collection (Automatic, Immediate)

**Collected Immediately After Connection:**
1. ✅ DB2 Version
2. ✅ SYSCAT.TABLES (all system catalog table definitions)
3. ✅ Basic schema list (SYSCAT.SCHEMATA)

**Filename:** `db2_syscat_{version}_{profile}.json`

**Saved Location:** `%LOCALAPPDATA%\DbExplorer\metadata\`

**Purpose:**
- Offline reference for SYSCAT table structure
- IntelliSense data (column names, table names)
- DDL generation templates
- Metadata browsing without re-querying

### On-Demand Collection (User-Triggered)

**Collected When Needed:**
- Full table details (columns, indexes, FK, triggers)
- View definitions and source code
- Procedure/function source code
- Package SQL statements

**Filename Pattern:** `db2_table_{schema}_{table}_{version}_{profile}.json`

**Trigger:** When user clicks on specific table/view/procedure in metadata tree

---

## 🎯 HOW TO IMPLEMENT (From NEXTSTEPS.md)

### Step 1: Add Background Collection to ConnectToDatabase()

**Location:** `Controls/ConnectionTabControl.xaml.cs`  
**Method:** `ConnectToDatabase()`  
**Line:** After `await _connectionManager.OpenAsync()` succeeds

```csharp
// After successful connection, start metadata collection in background
_ = Task.Run(async () =>
{
    try
    {
        Logger.Info("Starting background metadata collection");
        
        var metadataService = new DB2MetadataService();
        await metadataService.CollectMetadataAsync(
            _connectionManager, 
            _connection.ProfileName ?? _connection.GetDisplayName());
            
        Logger.Info("Background metadata collection completed");
    }
    catch (Exception ex)
    {
        Logger.Error(ex, "Background metadata collection failed");
        // Don't show error to user - this is non-critical background task
    }
});
```

**Key Characteristics:**
- `_ =` discards the Task (fire-and-forget)
- `Task.Run()` runs on background thread
- Doesn't await (non-blocking)
- Errors logged but not shown to user
- User can start working immediately

### Step 2: DB2MetadataService.CollectMetadataAsync()

**What It Does:**

```csharp
public async Task CollectMetadataAsync(
    DB2ConnectionManager connectionManager, 
    string profileName)
{
    // Step 1: Get DB2 version
    var version = await GetDB2VersionAsync(connectionManager);
    // Returns: "11.5", "10.5", etc.
    
    // Step 2: Get all SYSCAT tables
    var syscatTables = await GetSyscatTablesAsync(connectionManager);
    // Query: SELECT * FROM SYSCAT.TABLES WHERE TABSCHEMA = 'SYSCAT'
    
    // Step 3: Save to JSON file
    var fileName = $"db2_syscat_{version}_{SanitizeFileName(profileName)}.json";
    await SaveMetadataAsync(fileName, syscatTables, version);
    
    // File saved to: %LOCALAPPDATA%\DbExplorer\metadata\{fileName}
}
```

### Step 3: Check for Existing Files (Smart Caching)

**In SaveMetadataAsync():**

```csharp
private async Task SaveMetadataAsync(string fileName, DataTable dataTable, string version)
{
    var filePath = Path.Combine(_metadataFolder, fileName);
    
    // CHECK IF FILE ALREADY EXISTS
    if (File.Exists(filePath))
    {
        var fileInfo = new FileInfo(filePath);
        if (fileInfo.Length > 0)
        {
            Logger.Info("Metadata file already exists and contains data, skipping: {File}", fileName);
            return;  // SKIP - Already have this metadata
        }
    }
    
    // Only collect if file doesn't exist or is empty
    // ... proceed with collection and save ...
}
```

**This means:**
- First connection to any DB2 11.5 database: Collects SYSCAT metadata
- Subsequent connections to ANY DB2 11.5 database: Skips (already have it)
- Connection to DB2 10.5 database: Collects NEW metadata (different version)

---

## 🔄 REUSABILITY ACROSS CONNECTIONS

### What's Reusable (Same Version)

**SYSCAT Structure (System Catalog):**
- ✅ Reusable across ALL databases of same version
- ✅ SYSCAT.TABLES structure is identical for DB2 11.5
- ✅ SYSCAT.COLUMNS structure is identical for DB2 11.5
- ✅ All system catalog tables have same structure

**Example:**
```
DB2 11.5 TESTDB: Collects → db2_syscat_11.5_TESTDB.json
DB2 11.5 PRODDB: Collects → db2_syscat_11.5_PRODDB.json
  
Both files have IDENTICAL SYSCAT structure!
Could optimize to reuse first file.
```

**Optimization Possible:**
- Could check for ANY `db2_syscat_{version}_*.json` file
- If exists for same version, skip collection
- Currently: Collects per profile (simple, safe approach)

### What's NOT Reusable (Connection-Specific)

**Application Schemas/Tables:**
- ❌ NOT reusable (each DB has different user schemas)
- `db2_table_FK_CUSTOMERS_11.5_PRODDB.json` ≠ `db2_table_FK_CUSTOMERS_11.5_TESTDB.json`
- PRODDB customers table may have different columns than TESTDB

**User Permissions:**
- ❌ NOT reusable (each user has different DBAUTH)
- Determined fresh on every connection
- Not cached (security-sensitive)

---

## 📊 SYSCAT TABLES RELATIONSHIP DIAGRAM (From NEXTSTEPS.md)

**Complete Relationship Map:**

```
SYSCAT.SCHEMATA (Schema definitions)
    │
    └─────┐
          │
SYSCAT.TABLES (Table metadata)
    │
    ├─→ SYSCAT.COLUMNS (Column definitions)
    │     └─ FK: (TABSCHEMA, TABNAME) → SYSCAT.TABLES
    │
    ├─→ SYSCAT.KEYCOLUSE (Primary keys)
    │     └─ FK: (TABSCHEMA, TABNAME) → SYSCAT.TABLES
    │
    ├─→ SYSCAT.REFERENCES (Foreign keys)
    │     ├─ FK: (TABSCHEMA, TABNAME) → SYSCAT.TABLES
    │     └─ FK: (REFTABSCHEMA, REFTABNAME) → SYSCAT.TABLES
    │
    ├─→ SYSCAT.INDEXES (Index definitions)
    │     ├─ FK: (TABSCHEMA, TABNAME) → SYSCAT.TABLES
    │     └─→ SYSCAT.INDEXCOLUSE (Index columns)
    │           └─ FK: (INDSCHEMA, INDNAME) → SYSCAT.INDEXES
    │
    ├─→ SYSCAT.VIEWS (View definitions)
    │     └─ FK: (VIEWSCHEMA, VIEWNAME) → SYSCAT.TABLES
    │
    ├─→ SYSCAT.TRIGGERS (Trigger definitions)
    │     └─ FK: (TABSCHEMA, TABNAME) → SYSCAT.TABLES
    │
    └─→ SYSCAT.TABDEP (Dependencies)
          └─ FK: (TABSCHEMA, TABNAME) → SYSCAT.TABLES

SYSCAT.PACKAGES (Package definitions)
    │
    └─→ SYSCAT.STATEMENTS (Package SQL)
          └─ FK: (PKGSCHEMA, PKGNAME) → SYSCAT.PACKAGES

SYSCAT.ROUTINES (Procedures & Functions - independent)
```

**This relationship map is used for:**
- Dependency analysis
- DDL generation
- Impact analysis
- Migration planning

---

## 🎯 CURRENT IMPLEMENTATION STATUS

### What's Implemented: ✅

**DB2MetadataService.cs - COMPLETE:**
- ✅ CollectMetadataAsync() - Collects SYSCAT tables
- ✅ GetDB2VersionAsync() - Gets version
- ✅ CleanVersionString() - Extracts "11.5" format
- ✅ GetSyscatTablesAsync() - Queries SYSCAT.TABLES
- ✅ SaveMetadataAsync() - Saves to JSON with version in filename
- ✅ CollectTableMetadataAsync() - Table-specific metadata
- ✅ SanitizeFileName() - Removes invalid characters
- ✅ File checking (skip if exists and has data)

**CLI Integration - COMPLETE:**
- ✅ `-CollectMetadata` flag supported
- ✅ CliExecutorService calls metadata service
- ✅ Console output for progress

### What's NOT Implemented: ❌

**Background Integration:**
- ❌ NOT added to ConnectionTabControl.ConnectToDatabase()
- ❌ Metadata collection runs via CLI only
- ❌ No automatic background collection on GUI connection

**Why It's Optional:**
- Service is ready and working
- Can be added with 3 lines of code in ConnectToDatabase()
- Currently only runs via CLI (`-CollectMetadata` flag)
- Doesn't affect application functionality

---

## 🔧 HOW TO ADD BACKGROUND COLLECTION (3 Lines of Code)

**Add to ConnectionTabControl.xaml.cs:**

```csharp
private async Task ConnectToDatabase()
{
    // ... existing connection code ...
    
    await _connectionManager.OpenAsync();
    UpdateAccessLevelIndicator();
    await LoadDatabaseObjectsAsync();
    RefreshQueryHistory();
    
    // ADD THESE 3 LINES:
    _ = Task.Run(async () => {
        var svc = new DB2MetadataService();
        await svc.CollectMetadataAsync(_connectionManager, _connection.Name);
    });
}
```

---

## 📊 METADATA USAGE SCENARIOS

### Scenario 1: IntelliSense (Future Enhancement)
**Uses:** Cached SYSCAT metadata for autocomplete
```
User types: "SELECT * FROM SYS"
  → Reads: db2_syscat_11.5_*.json
  → Suggests: SYSCAT.TABLES, SYSCAT.COLUMNS, etc.
```

### Scenario 2: Offline DDL Generation
**Uses:** Cached table metadata
```
User opens DDL Generator while offline
  → Reads: db2_table_FK_CUSTOMERS_11.5_PROD.json
  → Generates: CREATE TABLE DDL from cached data
```

### Scenario 3: Metadata Tree View (Future Enhancement)
**Uses:** Cached schema/table lists
```
User expands FK schema in tree
  → Reads: db2_syscat_11.5_*.json
  → Shows: All tables in FK schema (from cache)
  → No database query needed
```

---

## 🎯 SUMMARY

**What NEXTSTEPS.md Says:**

1. **Background Collection:** Run in Task.Run() after connection, don't block UI
2. **Version-Based Naming:** Include DB2 version in filename (`db2_syscat_{version}_{profile}.json`)
3. **Smart Caching:** Check if file exists before collecting
4. **Reusability:** SYSCAT structure is version-specific, reusable across databases
5. **Non-Critical:** Errors don't interrupt user, logged only
6. **Storage:** `%LOCALAPPDATA%\DbExplorer\metadata\`
7. **File Check:** Skip if file exists and has data (size > 0)
8. **Table-Specific:** Collect detailed metadata on-demand for user tables

**Current Status:**
- ✅ Service implemented and working
- ✅ CLI integration complete
- ❌ Background integration not added to GUI (3 lines of code to add)
- ✅ Version-based file naming working
- ✅ File checking working (won't duplicate)

**The pattern is:**
```
db2_syscat_{version}_{profile}.json  ← SYSCAT structure (reusable by version)
db2_table_{schema}_{table}_{version}_{profile}.json  ← User table details (connection-specific)
```

---

**Source:** NEXTSTEPS.md lines 780-1600  
**Implementation:** DB2MetadataService.cs (COMPLETE)  
**Background Integration:** Specified but not yet added to GUI connection flow  
**Status:** Ready to use via CLI, can add to GUI with 3 lines

