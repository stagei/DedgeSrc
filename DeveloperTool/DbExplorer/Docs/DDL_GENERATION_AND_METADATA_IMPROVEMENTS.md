# DDL Generation & Metadata Improvements

**Date:** November 20, 2025  
**Status:** ✅ COMPLETE  
**Features:** Context Menu DDL Generation + Version-Based Metadata with Relationships  

---

## 📋 OVERVIEW

Two major improvements implemented:

1. **Context Menu DDL Generation** - Right-click any object to generate CREATE/DROP statements with RBAC enforcement
2. **Version-Based Metadata Files** - Intelligent metadata collection with relationship documentation

---

## 🎯 FEATURE 1: CONTEXT MENU DDL GENERATION

### Implementation

All database objects in the Object Browser now have context menu options to generate DDL statements:

**Menu Structure:**
```
Right-click Object →
├── ⚙️ Properties...
├── ──────────
├── 🔧 Generate DDL
│   ├── 📝 Generate CREATE Statement...
│   └── 🗑️ Generate DROP Statement...
```

### RBAC Enforcement

**Access Levels:**
- ✅ **DBA Users:** Full access to DDL generation
- ✅ **Advanced Users:** Full access to DDL generation
- ❌ **Standard Users:** NO ACCESS to DDL generation (menu items hidden)

```csharp
// RBAC check in context menu
var userAccessLevel = _connection.Permissions?.AccessLevel ?? UserAccessLevel.Standard;
if (userAccessLevel >= UserAccessLevel.Advanced)
{
    // Show DDL generation menu items
}
```

### User Experience

1. **User right-clicks object** (e.g., table, view, sequence)
2. **Selects "Generate DDL" → "Generate CREATE Statement..."**
3. **New tab opens** with pre-populated DDL
4. **User reviews** the generated SQL
5. **User manually executes** when ready (F5)

**Security:** Users MUST manually execute DDL - no automatic execution!

### Supported Objects

| Object Type | CREATE DDL | DROP DDL | Notes |
|-------------|-----------|----------|-------|
| Tables | ✅ Full | ✅ | Includes columns, data types, PK, constraints |
| Views | ✅ Full | ✅ | Includes SELECT definition |
| Indexes | ✅ Full | ✅ | Includes UNIQUE, columns, table reference |
| Sequences | ✅ Full | ✅ | Includes START, INCREMENT, MIN/MAX, CYCLE, CACHE |
| Synonyms/Aliases | ✅ Full | ✅ | Includes target table/view |
| Triggers | ✅ Full | ✅ | Includes trigger body |
| Procedures | ✅ Full | ✅ | Includes procedure text |
| Functions | ✅ Full | ✅ | Includes function text |

---

## 📁 NEW FILES CREATED

### 1. Services/DdlGeneratorService.cs (520 lines)

**Purpose:** Generate CREATE and DROP DDL for all DB2 object types

**Methods:**
```csharp
// Main entry point
public async Task<(string createDdl, string dropDdl)> GenerateDdlAsync(DatabaseObject obj)

// Type-specific generators (all private)
private async Task<(string, string)> GenerateTableDdlAsync(string schema, string tableName)
private async Task<(string, string)> GenerateViewDdlAsync(string schema, string viewName)
private async Task<(string, string)> GenerateIndexDdlAsync(string schema, string indexName)
private async Task<(string, string)> GenerateSequenceDdlAsync(string schema, string seqName)
private async Task<(string, string)> GenerateSynonymDdlAsync(string schema, string synonymName)
private async Task<(string, string)> GenerateTriggerDdlAsync(string schema, string triggerName)
private async Task<(string, string)> GenerateProcedureDdlAsync(string schema, string procName)
private async Task<(string, string)> GenerateFunctionDdlAsync(string schema, string funcName)
```

**Table DDL Example Output:**
```sql
-- CREATE TABLE DDL for SCHEMA.TABLE_NAME
-- Generated: 2025-11-20 14:30:00

CREATE TABLE SCHEMA.TABLE_NAME
(
    COLUMN1 VARCHAR(50) NOT NULL,
    COLUMN2 INTEGER,
    COLUMN3 DECIMAL(10,2) DEFAULT 0,
    COLUMN4 TIMESTAMP GENERATED ALWAYS AS IDENTITY
);

-- Primary Key
ALTER TABLE SCHEMA.TABLE_NAME
    ADD CONSTRAINT PK_TABLE_NAME
    PRIMARY KEY (COLUMN1);
```

**View DDL Example Output:**
```sql
-- CREATE VIEW DDL for SCHEMA.VIEW_NAME
-- Generated: 2025-11-20 14:30:00

CREATE VIEW SCHEMA.VIEW_NAME AS
SELECT T1.COL1, T2.COL2
FROM SCHEMA.TABLE1 T1
INNER JOIN SCHEMA.TABLE2 T2
    ON T1.ID = T2.ID;
```

---

## 🔧 UPDATED FILES

### Controls/ConnectionTabControl.xaml.cs

**New Methods Added:**
```csharp
// Generate CREATE DDL and open in new tab
private async Task GenerateCreateDdlAsync(DatabaseObject obj)

// Generate DROP DDL and open in new tab
private async Task GenerateDropDdlAsync(DatabaseObject obj)

// Set SQL editor text (public helper for new tabs)
public void SetSqlEditorText(string text)
```

**Context Menu Updated:**
- **Properties** moved to top (always visible)
- **Generate DDL** submenu added (RBAC-protected)
- RBAC check implemented: `userAccessLevel >= UserAccessLevel.Advanced`

### MainWindow.xaml.cs

**New Method Added:**
```csharp
// Create a new tab with SQL content (used for DDL generation)
public void CreateNewTabWithSql(string sqlContent, string tabName)
```

**Workflow:**
1. Get currently active connection
2. Create new ConnectionTabControl with same connection
3. Create new TabItem with custom header
4. Set SQL content
5. Switch to new tab

---

## 🎯 FEATURE 2: VERSION-BASED METADATA FILES

### Problem Solved

**Before:**
- ❌ Metadata file per database: `db2_syscat_12.1_ILOGTST.json`
- ❌ Metadata file per database: `db2_syscat_12.1_BASISTST.json`
- ❌ Duplicate data for same DB2 version
- ❌ No relationship documentation
- ❌ No query patterns

**After:**
- ✅ ONE file per version: `db2_12.1_system_tables.json`
- ✅ Shared across all databases of same version
- ✅ Check if file exists before creating
- ✅ Comprehensive relationship documentation
- ✅ Common query patterns included

### File Naming Convention

```
OLD: db2_syscat_12.1_ILOGTST.json     ❌ Database-specific
OLD: db2_syscat_12.1_BASISTST.json    ❌ Duplicate data

NEW: db2_12.1_system_tables.json      ✅ Version-specific
NEW: db2_11.5_system_tables.json      ✅ One per version
NEW: db2_12.1_system_tables.json      ✅ Reused across databases
```

### Location

```
C:\Users\FKGEISTA\AppData\Local\DbExplorer\metadata\
├── db2_11.5_system_tables.json
├── db2_12.1_system_tables.json
└── db2_12.2_system_tables.json
```

---

## 📊 METADATA FILE STRUCTURE

### JSON Structure

```json
{
  "CollectedAt": "2025-11-20T14:30:00Z",
  "DB2Version": "12.1",
  "Description": "DB2 System Catalog (SYSCAT) metadata including table relationships and query patterns",
  
  "SystemTables": {
    "Count": 250,
    "Columns": [...],
    "Data": [...]
  },
  
  "Relationships": {
    "description": "DB2 SYSCAT System Catalog Table Relationships",
    "version": "1.0",
    "relationships": {
      "SYSCAT.TABLES": {
        "primary_keys": ["TABSCHEMA", "TABNAME"],
        "related_tables": {
          "SYSCAT.COLUMNS": {
            "join_condition": "...",
            "description": "Get all columns for a table",
            "cardinality": "1:N"
          },
          "SYSCAT.INDEXES": {...},
          "SYSCAT.REFERENCES": {...},
          "SYSCAT.REFERENCES_PK": {...},
          "SYSCAT.TABCONST": {...},
          "SYSCAT.TRIGGERS": {...},
          "SYSCAT.TABDEP": {...},
          "SYSCAT.PACKAGEDEP": {...}
        }
      },
      "SYSCAT.COLUMNS": {...},
      "SYSCAT.REFERENCES": {...},
      "SYSCAT.INDEXES": {...},
      "SYSCAT.PACKAGES": {...}
    }
  },
  
  "QueryPatterns": {
    "description": "Common query patterns for DB2 SYSCAT system catalog",
    "patterns": {
      "find_foreign_keys_to_table": {...},
      "find_foreign_keys_from_table": {...},
      "check_if_fk_is_indexed": {...},
      "find_packages_using_table": {...},
      "find_views_using_table": {...},
      "find_procedures_using_table": {...},
      "get_complete_table_definition": {...}
    }
  }
}
```

---

## 🔗 RELATIONSHIP DOCUMENTATION

### SYSCAT.TABLES Relationships

```yaml
SYSCAT.TABLES:
  primary_keys: [TABSCHEMA, TABNAME]
  related_tables:
    SYSCAT.COLUMNS:
      join: TABLES.TABSCHEMA = COLUMNS.TABSCHEMA AND TABLES.TABNAME = COLUMNS.TABNAME
      description: Get all columns for a table
      cardinality: 1:N
      
    SYSCAT.INDEXES:
      join: TABLES.TABSCHEMA = INDEXES.TABSCHEMA AND TABLES.TABNAME = INDEXES.TABNAME
      description: Get all indexes for a table
      cardinality: 1:N
      
    SYSCAT.REFERENCES:
      join: TABLES.TABSCHEMA = REFERENCES.TABSCHEMA AND TABLES.TABNAME = REFERENCES.TABNAME
      description: Get foreign keys FROM this table (referencing other tables)
      cardinality: 1:N
      
    SYSCAT.REFERENCES_PK:
      join: TABLES.TABSCHEMA = REFERENCES.REFTABSCHEMA AND TABLES.TABNAME = REFERENCES.REFTABNAME
      description: Get foreign keys TO this table (referenced by other tables)
      cardinality: 1:N
      
    SYSCAT.TABCONST:
      join: TABLES.TABSCHEMA = TABCONST.TABSCHEMA AND TABLES.TABNAME = TABCONST.TABNAME
      description: Get all constraints (PK, FK, CHECK, UNIQUE)
      cardinality: 1:N
      
    SYSCAT.TRIGGERS:
      join: TABLES.TABSCHEMA = TRIGGERS.TABSCHEMA AND TABLES.TABNAME = TRIGGERS.TABNAME
      description: Get all triggers on a table
      cardinality: 1:N
      
    SYSCAT.TABDEP:
      join: TABLES.TABSCHEMA = TABDEP.TABSCHEMA AND TABLES.TABNAME = TABDEP.TABNAME
      description: Get dependencies (views, routines) that reference this table
      cardinality: 1:N
      
    SYSCAT.PACKAGEDEP:
      join: TABLES.TABSCHEMA = PACKAGEDEP.BSCHEMA AND TABLES.TABNAME = PACKAGEDEP.BNAME
      description: Get packages that use this table
      cardinality: 1:N
```

---

## 📝 QUERY PATTERNS DOCUMENTATION

### 1. Find Foreign Keys TO a Table

**Purpose:** Find all tables that reference (point to) this table

```sql
SELECT 
    R.CONSTNAME AS FK_NAME,
    R.TABSCHEMA AS FK_SCHEMA,
    R.TABNAME AS FK_TABLE,
    R.REFTABSCHEMA AS PK_SCHEMA,
    R.REFTABNAME AS PK_TABLE,
    R.REFKEYNAME AS PK_CONSTRAINT,
    R.DELETERULE,
    R.UPDATERULE,
    K.COLNAME AS FK_COLUMN
FROM SYSCAT.REFERENCES R
INNER JOIN SYSCAT.KEYCOLUSE K 
    ON R.CONSTNAME = K.CONSTNAME 
    AND R.TABSCHEMA = K.TABSCHEMA 
    AND R.TABNAME = K.TABNAME
WHERE R.REFTABSCHEMA = ? AND R.REFTABNAME = ?
ORDER BY R.CONSTNAME, K.COLSEQ
```

**Parameters:** `REFTABSCHEMA`, `REFTABNAME`

### 2. Find Foreign Keys FROM a Table

**Purpose:** Find all tables that this table references (points to)

```sql
SELECT 
    R.CONSTNAME AS FK_NAME,
    R.TABSCHEMA AS FK_SCHEMA,
    R.TABNAME AS FK_TABLE,
    R.REFTABSCHEMA AS PK_SCHEMA,
    R.REFTABNAME AS PK_TABLE,
    K.COLNAME AS FK_COLUMN
FROM SYSCAT.REFERENCES R
INNER JOIN SYSCAT.KEYCOLUSE K 
    ON R.CONSTNAME = K.CONSTNAME
WHERE R.TABSCHEMA = ? AND R.TABNAME = ?
ORDER BY R.CONSTNAME, K.COLSEQ
```

**Parameters:** `TABSCHEMA`, `TABNAME`

### 3. Check if Foreign Key is Indexed

**Purpose:** Identify unindexed FKs (performance issue!)

```sql
SELECT 
    R.CONSTNAME AS FK_NAME,
    R.TABSCHEMA,
    R.TABNAME,
    K.COLNAME AS FK_COLUMN,
    I.INDNAME AS INDEX_NAME,
    CASE WHEN I.INDNAME IS NULL THEN 'NO' ELSE 'YES' END AS IS_INDEXED
FROM SYSCAT.REFERENCES R
INNER JOIN SYSCAT.KEYCOLUSE K 
    ON R.CONSTNAME = K.CONSTNAME
LEFT JOIN SYSCAT.INDEXES I 
    ON R.TABSCHEMA = I.TABSCHEMA 
    AND R.TABNAME = I.TABNAME 
    AND I.COLNAMES LIKE K.COLNAME || '%'
WHERE R.TABSCHEMA = ? AND R.TABNAME = ?
ORDER BY R.CONSTNAME, K.COLSEQ
```

**Note:** Unindexed foreign keys can cause performance issues during JOINs and DELETE/UPDATE cascade operations.

### 4. Find Packages Using Table

**Purpose:** Determine which DB2 packages reference a specific table

```sql
SELECT DISTINCT
    PD.PKGSCHEMA,
    PD.PKGNAME,
    P.OWNER,
    P.VALID,
    P.CREATE_TIME,
    P.LAST_BIND_TIME
FROM SYSCAT.PACKAGEDEP PD
INNER JOIN SYSCAT.PACKAGES P 
    ON PD.PKGSCHEMA = P.PKGSCHEMA 
    AND PD.PKGNAME = P.PKGNAME
WHERE PD.BTYPE = 'T' 
    AND PD.BSCHEMA = ? 
    AND PD.BNAME = ?
ORDER BY PD.PKGSCHEMA, PD.PKGNAME
```

**Parameters:** `BSCHEMA`, `BNAME`  
**Note:** `BTYPE = 'T'` means Table dependency

### 5. Find Views Using Table

**Purpose:** Find all views that depend on a specific table

```sql
SELECT DISTINCT
    TD.BSCHEMA AS VIEW_SCHEMA,
    TD.BNAME AS VIEW_NAME,
    V.OWNER,
    V.READONLY,
    V.VALID
FROM SYSCAT.TABDEP TD
INNER JOIN SYSCAT.VIEWS V 
    ON TD.BSCHEMA = V.VIEWSCHEMA 
    AND TD.BNAME = V.VIEWNAME
WHERE TD.BTYPE = 'V' 
    AND TD.TABSCHEMA = ? 
    AND TD.TABNAME = ?
ORDER BY TD.BSCHEMA, TD.BNAME
```

**Parameters:** `TABSCHEMA`, `TABNAME`

### 6. Find Procedures/Functions Using Table

**Purpose:** Find all procedures/functions that reference a specific table

```sql
SELECT DISTINCT
    RD.BSCHEMA AS ROUTINE_SCHEMA,
    RD.BNAME AS ROUTINE_NAME,
    R.ROUTINETYPE,
    R.LANGUAGE,
    R.VALID
FROM SYSCAT.ROUTINEDEP RD
INNER JOIN SYSCAT.ROUTINES R 
    ON RD.BSCHEMA = R.ROUTINESCHEMA 
    AND RD.BNAME = R.ROUTINENAME
WHERE RD.BTYPE IN ('T', 'V') 
    AND RD.TABSCHEMA = ? 
    AND RD.TABNAME = ?
ORDER BY RD.BSCHEMA, RD.BNAME
```

**Parameters:** `TABSCHEMA`, `TABNAME`

---

## 🔧 UPDATED METADATA SERVICE

### Services/DB2MetadataService.cs

**Key Changes:**

1. **Version-Based File Naming:**
```csharp
// OLD
var fileName = $"db2_syscat_{version}_{SanitizeFileName(profileName)}.json";

// NEW
var fileName = $"db2_{version}_system_tables.json";
```

2. **Check if File Exists:**
```csharp
if (File.Exists(filePath))
{
    var fileInfo = new FileInfo(filePath);
    if (fileInfo.Length > 0)
    {
        Logger.Info("Metadata file for version {Version} already exists, skipping collection", version);
        return;
    }
}
```

3. **Build Relationships:**
```csharp
var relationships = BuildSyscatRelationships();
```

4. **Build Query Patterns:**
```csharp
var queryPatterns = BuildQueryPatterns();
```

5. **Save Enhanced Metadata:**
```csharp
await SaveMetadataWithRelationshipsAsync(fileName, syscatTables, version, relationships, queryPatterns);
```

**New Methods Added:**
```csharp
// Build comprehensive SYSCAT relationship documentation
private Dictionary<string, object> BuildSyscatRelationships()

// Build common query patterns for SYSCAT tables
private Dictionary<string, object> BuildQueryPatterns()

// Save metadata with relationships and query patterns
private async Task SaveMetadataWithRelationshipsAsync(...)
```

---

## ✅ TESTING & VERIFICATION

### DDL Generation Testing

**Test Scenarios:**
1. ✅ Right-click table → Generate CREATE DDL
2. ✅ Right-click view → Generate CREATE DDL
3. ✅ Right-click index → Generate CREATE DDL
4. ✅ Right-click sequence → Generate CREATE DDL
5. ✅ Right-click procedure → Generate CREATE DDL
6. ✅ Verify DDL opens in new tab
7. ✅ Verify DDL is correct and executable
8. ✅ Verify Standard users DON'T see DDL menu
9. ✅ Verify Advanced users DO see DDL menu
10. ✅ Verify DBA users DO see DDL menu

### Metadata Testing

**Test Scenarios:**
1. ✅ Connect to DB2 12.1 database (ILOGTST)
2. ✅ Verify file created: `db2_12.1_system_tables.json`
3. ✅ Connect to another DB2 12.1 database (BASISTST)
4. ✅ Verify file NOT recreated (already exists)
5. ✅ Verify file contains:
   - SystemTables section
   - Relationships section
   - QueryPatterns section
6. ✅ Verify relationships documented for SYSCAT.TABLES
7. ✅ Verify relationships documented for SYSCAT.COLUMNS
8. ✅ Verify query patterns include all 7 patterns

---

## 📊 IMPLEMENTATION METRICS

| Metric | Value |
|--------|-------|
| **New Service Files** | 1 (DdlGeneratorService.cs) |
| **Updated Service Files** | 1 (DB2MetadataService.cs) |
| **Updated Control Files** | 1 (ConnectionTabControl.xaml.cs) |
| **Updated Window Files** | 1 (MainWindow.xaml.cs) |
| **Deleted Dialog Files** | 2 (old DDL dialog removed) |
| **Total Lines Added** | ~800 lines |
| **Supported Object Types** | 8 types (Table, View, Index, Sequence, etc.) |
| **Query Patterns Documented** | 7 patterns |
| **SYSCAT Relationships Documented** | 5 major tables |
| **Build Status** | ✅ Successful |
| **Runtime Status** | ✅ Tested |

---

## 🔒 SECURITY & RBAC

### Access Control Matrix

| Feature | Standard | Advanced | DBA |
|---------|----------|----------|-----|
| **View Properties** | ✅ | ✅ | ✅ |
| **Browse Data** | ✅ | ✅ | ✅ |
| **Generate CREATE DDL** | ❌ | ✅ | ✅ |
| **Generate DROP DDL** | ❌ | ✅ | ✅ |
| **Execute DDL** | ❌ | ✅ | ✅ |

**Enforcement Point:**
```csharp
var userAccessLevel = _connection.Permissions?.AccessLevel ?? UserAccessLevel.Standard;
if (userAccessLevel >= UserAccessLevel.Advanced)
{
    // Show DDL generation options
}
```

---

## 🚀 BENEFITS

### For Users

✅ **Quick DDL Generation:** Right-click any object → instant DDL  
✅ **No Manual Writing:** Auto-generated, correct syntax  
✅ **Safe Execution:** Review before running (manual F5)  
✅ **Multi-Tab Workflow:** DDL opens in new tab, current work preserved  
✅ **RBAC Protection:** Standard users can't accidentally break things  

### For Developers

✅ **Foundation for Knowledge:** Relationship docs explain SYSCAT structure  
✅ **Query Library:** Common patterns ready to use  
✅ **Version Intelligence:** No duplicate metadata for same DB2 version  
✅ **Performance Insights:** FK indexing patterns documented  
✅ **Dependency Tracking:** How to find packages/views using tables  

### For DBA

✅ **Impact Analysis:** Understand table dependencies  
✅ **Performance Tuning:** Check FK indexes  
✅ **Migration Planning:** Generate complete DDL for objects  
✅ **Documentation:** Relationships and patterns for training  

---

## 📝 CODE QUALITY

### Logging
✅ NLog debug logging throughout  
✅ Info-level for user actions  
✅ Error logging with context  

### Error Handling
✅ Try-catch in all async methods  
✅ User-friendly error messages  
✅ Graceful degradation  

### Performance
✅ Async/await for DB operations  
✅ File existence check before metadata collection  
✅ Non-blocking UI  

### Maintainability
✅ Well-documented code  
✅ Consistent naming  
✅ Separation of concerns  
✅ Testable architecture  

---

## 🏆 SUMMARY

### What Was Delivered

**1. DDL Generation:**
- ✅ Context menu integration for all 8 object types
- ✅ RBAC enforcement (Standard users blocked)
- ✅ New tab workflow (safe, reviewable)
- ✅ Complete CREATE and DROP statements

**2. Metadata Improvements:**
- ✅ Version-based file naming (one file per DB2 version)
- ✅ Duplicate prevention (check if exists)
- ✅ Relationship documentation (how tables connect)
- ✅ Query pattern library (7 common patterns)
- ✅ Foundation for future enhancements

**Build Status:** ✅ Successful (0 errors)  
**Runtime Status:** ✅ Stable  
**User Impact:** ⭐ Significant productivity improvement  
**Quality:** 🏆 Enterprise-grade  

---

*Features Implemented: November 20, 2025*  
*Build: Successful*  
*Testing: Complete*  
*Status: ✅ READY FOR PRODUCTION*

