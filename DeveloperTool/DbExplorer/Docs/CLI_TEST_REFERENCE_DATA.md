# CLI Test Reference Data - Golden Standard for Automated Testing

**Date**: December 13, 2025  
**Purpose**: Reference metadata for validating CLI command outputs  
**Database**: ILOGTST @ t-no1fkxtst-db:3700  
**Test Schema**: INL or DBM

---

## 🎯 PURPOSE

This document serves as the "golden standard" for CLI automated testing. It contains comprehensive metadata about a specific test table that has:
- ✅ Primary Keys
- ✅ Foreign Keys  
- ✅ Indexes
- ✅ Triggers
- ✅ Multiple columns with various data types

All CLI commands will be tested against this reference data to ensure correctness.

---

## 📋 TEST TABLE SELECTION CRITERIA

### SQL Query to Find Suitable Test Tables:

```sql
-- Find tables with PKs, FKs, and triggers in INL or DBM schema
SELECT DISTINCT t.TABSCHEMA, t.TABNAME, t.CARD AS ROW_COUNT,
    (SELECT COUNT(*) FROM SYSCAT.KEYCOLUSE k 
     WHERE k.TABSCHEMA = t.TABSCHEMA AND k.TABNAME = t.TABNAME) AS PK_COUNT,
    (SELECT COUNT(*) FROM SYSCAT.REFERENCES r 
     WHERE r.TABSCHEMA = t.TABSCHEMA AND r.TABNAME = t.TABNAME) AS FK_COUNT,
    (SELECT COUNT(*) FROM SYSCAT.TRIGGERS trg 
     WHERE trg.TABSCHEMA = t.TABSCHEMA AND trg.TABNAME = t.TABNAME) AS TRIGGER_COUNT
FROM SYSCAT.TABLES t
WHERE t.TABSCHEMA IN ('INL', 'DBM')
  AND t.TYPE = 'T'
  AND EXISTS (SELECT 1 FROM SYSCAT.KEYCOLUSE k 
              WHERE k.TABSCHEMA = t.TABSCHEMA AND k.TABNAME = t.TABNAME)
  AND EXISTS (SELECT 1 FROM SYSCAT.REFERENCES r 
              WHERE r.TABSCHEMA = t.TABSCHEMA AND r.TABNAME = t.TABNAME)
ORDER BY TRIGGER_COUNT DESC, FK_COUNT DESC, PK_COUNT DESC
FETCH FIRST 5 ROWS ONLY;
```

---

## 📊 REFERENCE TABLE METADATA

### Table: **[SCHEMA.TABLENAME]** (TO BE POPULATED)

**Basic Information:**
```json
{
  "schema": "INL",
  "tableName": "EXAMPLE_TABLE",
  "type": "T",
  "status": "N",
  "tableId": 12345,
  "rowCount": 50000,
  "dataPages": 2048,
  "indexPages": 512,
  "overflowPages": 0,
  "created": "2024-01-15",
  "lastStatsTime": "2025-12-01 10:30:00",
  "remarks": "Example table comment"
}
```

### CLI Command to Retrieve:
```bash
DbExplorer.exe -Profile "ILOGTST" -Command table-props -Object "INL.EXAMPLE_TABLE" -IncludeDependencies -Outfile reference_table.json
```

---

## 📝 COLUMN DEFINITIONS

### Expected JSON Output:

```json
{
  "columns": [
    {
      "columnName": "ID",
      "ordinalPosition": 1,
      "dataType": "INTEGER",
      "length": 4,
      "scale": 0,
      "isNullable": false,
      "defaultValue": null,
      "isIdentity": true,
      "identityStart": 1,
      "identityIncrement": 1,
      "comment": "Primary key - auto-increment",
      "isPrimaryKey": true,
      "isForeignKey": false,
      "isUnique": false
    },
    {
      "columnName": "NAME",
      "ordinalPosition": 2,
      "dataType": "VARCHAR",
      "length": 100,
      "scale": 0,
      "isNullable": false,
      "defaultValue": null,
      "isIdentity": false,
      "comment": "Entity name",
      "isPrimaryKey": false,
      "isForeignKey": false,
      "isUnique": true
    },
    {
      "columnName": "PARENT_ID",
      "ordinalPosition": 3,
      "dataType": "INTEGER",
      "length": 4,
      "scale": 0,
      "isNullable": true,
      "defaultValue": null,
      "isIdentity": false,
      "comment": "Foreign key to parent table",
      "isPrimaryKey": false,
      "isForeignKey": true,
      "isUnique": false
    },
    {
      "columnName": "AMOUNT",
      "ordinalPosition": 4,
      "dataType": "DECIMAL",
      "length": 15,
      "scale": 2,
      "isNullable": true,
      "defaultValue": "0.00",
      "isIdentity": false,
      "comment": "Monetary amount",
      "isPrimaryKey": false,
      "isForeignKey": false,
      "isUnique": false
    },
    {
      "columnName": "CREATED_DATE",
      "ordinalPosition": 5,
      "dataType": "TIMESTAMP",
      "length": 10,
      "scale": 6,
      "isNullable": false,
      "defaultValue": "CURRENT_TIMESTAMP",
      "isIdentity": false,
      "comment": "Record creation timestamp",
      "isPrimaryKey": false,
      "isForeignKey": false,
      "isUnique": false
    },
    {
      "columnName": "STATUS",
      "ordinalPosition": 6,
      "dataType": "CHAR",
      "length": 1,
      "scale": 0,
      "isNullable": false,
      "defaultValue": "'A'",
      "isIdentity": false,
      "comment": "Status code: A=Active, I=Inactive",
      "isPrimaryKey": false,
      "isForeignKey": false,
      "isUnique": false
    }
  ]
}
```

### SQL Query to Retrieve Columns:
```sql
SELECT 
    c.COLNAME, 
    c.COLNO,
    c.TYPENAME, 
    c.LENGTH, 
    c.SCALE, 
    c.NULLS,
    c.DEFAULT,
    c.IDENTITY,
    c.REMARKS,
    CASE WHEN k.COLNAME IS NOT NULL THEN 1 ELSE 0 END AS IS_PK,
    CASE WHEN r.FK_COLNAMES LIKE '%' || c.COLNAME || '%' THEN 1 ELSE 0 END AS IS_FK
FROM SYSCAT.COLUMNS c
LEFT JOIN SYSCAT.KEYCOLUSE k 
    ON c.TABSCHEMA = k.TABSCHEMA 
    AND c.TABNAME = k.TABNAME 
    AND c.COLNAME = k.COLNAME
LEFT JOIN SYSCAT.REFERENCES r 
    ON c.TABSCHEMA = r.TABSCHEMA 
    AND c.TABNAME = r.TABNAME
WHERE c.TABSCHEMA = 'INL' 
  AND c.TABNAME = 'EXAMPLE_TABLE'
ORDER BY c.COLNO;
```

---

## 🔑 PRIMARY KEY CONSTRAINTS

### Expected JSON Output:

```json
{
  "primaryKeys": {
    "constraintName": "PK_EXAMPLE_TABLE",
    "columns": ["ID"],
    "columnSequence": [
      {
        "columnName": "ID",
        "keySequence": 1
      }
    ],
    "indexName": "SQL251213103000010",
    "isEnforced": true,
    "createTime": "2024-01-15 10:30:00"
  }
}
```

### SQL Query:
```sql
SELECT 
    k.CONSTNAME,
    k.COLNAME,
    k.KEYSEQ,
    tc.ENFORCED,
    tc.CREATE_TIME
FROM SYSCAT.KEYCOLUSE k
JOIN SYSCAT.TABCONST tc 
    ON k.TABSCHEMA = tc.TABSCHEMA 
    AND k.TABNAME = tc.TABNAME 
    AND k.CONSTNAME = tc.CONSTNAME
WHERE k.TABSCHEMA = 'INL' 
  AND k.TABNAME = 'EXAMPLE_TABLE'
ORDER BY k.KEYSEQ;
```

---

## 🔗 FOREIGN KEY CONSTRAINTS

### Expected JSON Output:

```json
{
  "foreignKeys": [
    {
      "constraintName": "FK_EXAMPLE_PARENT",
      "columns": "PARENT_ID",
      "referencedSchema": "INL",
      "referencedTable": "PARENT_TABLE",
      "referencedColumns": "ID",
      "deleteRule": "CASCADE",
      "updateRule": "RESTRICT",
      "isEnforced": true,
      "createTime": "2024-01-15 10:32:00"
    }
  ]
}
```

### SQL Query:
```sql
SELECT 
    r.CONSTNAME,
    r.FK_COLNAMES,
    r.REFTABSCHEMA,
    r.REFTABNAME,
    r.PK_COLNAMES,
    r.DELETERULE,
    r.UPDATERULE,
    r.ENFORCED,
    r.CREATE_TIME
FROM SYSCAT.REFERENCES r
WHERE r.TABSCHEMA = 'INL' 
  AND r.TABNAME = 'EXAMPLE_TABLE'
ORDER BY r.CONSTNAME;
```

---

## 📇 INDEX DEFINITIONS

### Expected JSON Output:

```json
{
  "indexes": [
    {
      "indexName": "PK_EXAMPLE_TABLE",
      "indexSchema": "INL",
      "uniqueRule": "P",
      "isUnique": true,
      "isPrimaryKey": true,
      "columns": [
        {
          "columnName": "ID",
          "columnSequence": 1,
          "ordering": "A"
        }
      ],
      "indexType": "REG",
      "colCount": 1,
      "firstKeyCard": 50000,
      "fullKeyCard": 50000,
      "createTime": "2024-01-15 10:30:00",
      "remarks": null
    },
    {
      "indexName": "IDX_EXAMPLE_NAME",
      "indexSchema": "INL",
      "uniqueRule": "U",
      "isUnique": true,
      "isPrimaryKey": false,
      "columns": [
        {
          "columnName": "NAME",
          "columnSequence": 1,
          "ordering": "A"
        }
      ],
      "indexType": "REG",
      "colCount": 1,
      "firstKeyCard": 50000,
      "fullKeyCard": 50000,
      "createTime": "2024-01-15 10:31:00",
      "remarks": "Unique index on name column"
    },
    {
      "indexName": "IDX_EXAMPLE_PARENT",
      "indexSchema": "INL",
      "uniqueRule": "D",
      "isUnique": false,
      "isPrimaryKey": false,
      "columns": [
        {
          "columnName": "PARENT_ID",
          "columnSequence": 1,
          "ordering": "A"
        }
      ],
      "indexType": "REG",
      "colCount": 1,
      "firstKeyCard": 500,
      "fullKeyCard": 50000,
      "createTime": "2024-01-15 10:32:00",
      "remarks": "Index for foreign key lookups"
    }
  ]
}
```

### SQL Query:
```sql
SELECT 
    i.INDNAME,
    i.INDSCHEMA,
    i.UNIQUERULE,
    i.COLNAMES,
    i.INDEXTYPE,
    i.COLCOUNT,
    i.FIRST_KEYCARD,
    i.FULLKEYCARD,
    i.CREATE_TIME,
    i.REMARKS
FROM SYSCAT.INDEXES i
WHERE i.TABSCHEMA = 'INL' 
  AND i.TABNAME = 'EXAMPLE_TABLE'
ORDER BY i.INDNAME;
```

---

## 🔔 TRIGGER DEFINITIONS

### Expected JSON Output:

```json
{
  "triggers": [
    {
      "triggerName": "TRG_EXAMPLE_AUDIT",
      "triggerSchema": "INL",
      "targetSchema": "INL",
      "targetTable": "EXAMPLE_TABLE",
      "triggerTime": "AFTER",
      "triggerEvent": "UPDATE",
      "granularity": "R",
      "isEnabled": "Y",
      "valid": "Y",
      "createTime": "2024-01-15 10:33:00",
      "remarks": "Audit trail trigger",
      "text": "CREATE TRIGGER INL.TRG_EXAMPLE_AUDIT\nAFTER UPDATE ON INL.EXAMPLE_TABLE\nREFERENCING NEW AS N OLD AS O\nFOR EACH ROW\nMODE DB2SQL\nBEGIN ATOMIC\n  INSERT INTO INL.AUDIT_LOG (TABLE_NAME, OPERATION, OLD_VALUE, NEW_VALUE, CHANGE_DATE)\n  VALUES ('EXAMPLE_TABLE', 'UPDATE', O.NAME, N.NAME, CURRENT_TIMESTAMP);\nEND"
    },
    {
      "triggerName": "TRG_EXAMPLE_VALIDATE",
      "triggerSchema": "INL",
      "targetSchema": "INL",
      "targetTable": "EXAMPLE_TABLE",
      "triggerTime": "BEFORE",
      "triggerEvent": "INSERT",
      "granularity": "R",
      "isEnabled": "Y",
      "valid": "Y",
      "createTime": "2024-01-15 10:34:00",
      "remarks": "Validation trigger",
      "text": "CREATE TRIGGER INL.TRG_EXAMPLE_VALIDATE\nBEFORE INSERT ON INL.EXAMPLE_TABLE\nREFERENCING NEW AS N\nFOR EACH ROW\nMODE DB2SQL\nWHEN (N.AMOUNT < 0)\nBEGIN ATOMIC\n  SIGNAL SQLSTATE '75001' SET MESSAGE_TEXT = 'Amount cannot be negative';\nEND"
    }
  ]
}
```

### SQL Query:
```sql
SELECT 
    t.TRIGNAME,
    t.TRIGSCHEMA,
    t.TABSCHEMA,
    t.TABNAME,
    t.TRIGTIME,
    t.TRIGEVENT,
    t.GRANULARITY,
    t.ENABLED,
    t.VALID,
    t.CREATE_TIME,
    t.REMARKS,
    t.TEXT
FROM SYSCAT.TRIGGERS t
WHERE t.TABSCHEMA = 'INL' 
  AND t.TABNAME = 'EXAMPLE_TABLE'
ORDER BY t.TRIGNAME;
```

---

## 📊 TABLE STATISTICS

### Expected JSON Output:

```json
{
  "statistics": {
    "rowCount": 50000,
    "dataPages": 2048,
    "indexPages": 512,
    "overflowPages": 0,
    "avgRowSize": 150,
    "compressionRatio": 100,
    "tableSpaceId": 2,
    "tableSpaceName": "USERSPACE1",
    "lastStatsTime": "2025-12-01 10:30:00",
    "lastReorgTime": "2025-11-15 08:00:00",
    "reorgPending": "N"
  }
}
```

### SQL Query:
```sql
SELECT 
    t.CARD,
    t.NPAGES,
    t.FPAGES,
    t.OVERFLOW,
    t.AVGROWSIZE,
    t.PCTPAGESSAVED,
    t.TBSPACEID,
    ts.TBSPACE AS TBSPACENAME,
    t.STATS_TIME,
    t.LAST_REGEN_TIME,
    t.STATUS
FROM SYSCAT.TABLES t
LEFT JOIN SYSCAT.TABLESPACES ts 
    ON t.TBSPACEID = ts.TBSPACEID
WHERE t.TABSCHEMA = 'INL' 
  AND t.TABNAME = 'EXAMPLE_TABLE';
```

---

## 🔍 DEPENDENCY ANALYSIS

### Tables Referenced BY this table (Dependencies):

```json
{
  "dependsOn": [
    {
      "schema": "INL",
      "object": "PARENT_TABLE",
      "type": "TABLE",
      "relationship": "FOREIGN_KEY",
      "constraintName": "FK_EXAMPLE_PARENT"
    }
  ]
}
```

### Tables that Reference this table (Dependents):

```json
{
  "usedBy": [
    {
      "schema": "INL",
      "object": "CHILD_TABLE",
      "type": "TABLE",
      "relationship": "FOREIGN_KEY",
      "constraintName": "FK_CHILD_EXAMPLE"
    },
    {
      "schema": "INL",
      "object": "V_EXAMPLE_VIEW",
      "type": "VIEW",
      "relationship": "VIEW_DEPENDENCY"
    },
    {
      "schema": "INL",
      "object": "SP_GET_EXAMPLE_DATA",
      "type": "PROCEDURE",
      "relationship": "PROCEDURE_DEPENDENCY"
    }
  ]
}
```

### SQL Query for Dependencies:
```sql
-- Tables this table depends on (foreign keys pointing out)
SELECT 
    r.REFTABSCHEMA AS REF_SCHEMA,
    r.REFTABNAME AS REF_TABLE,
    'TABLE' AS OBJECT_TYPE,
    'FOREIGN_KEY' AS RELATIONSHIP,
    r.CONSTNAME
FROM SYSCAT.REFERENCES r
WHERE r.TABSCHEMA = 'INL' 
  AND r.TABNAME = 'EXAMPLE_TABLE';

-- Tables/views/procedures that depend on this table
SELECT 
    d.BSCHEMA AS DEP_SCHEMA,
    d.BNAME AS DEP_OBJECT,
    d.BTYPE AS OBJECT_TYPE,
    'DEPENDENCY' AS RELATIONSHIP
FROM SYSCAT.TABDEP d
WHERE d.TABSCHEMA = 'INL' 
  AND d.TABNAME = 'EXAMPLE_TABLE';
```

---

## 🧪 CLI TEST COMMANDS

### Command 1: Get Table Properties
```bash
DbExplorer.exe -Profile "ILOGTST" \
  -Command table-props \
  -Object "INL.EXAMPLE_TABLE" \
  -IncludeDependencies \
  -Outfile "test_output/table_props.json"
```

**Expected Output**: JSON matching the structure above

**Validation**:
```powershell
$result = Get-Content "test_output/table_props.json" | ConvertFrom-Json

# Assert column count
if ($result.columns.Count -ne 6) {
    throw "Expected 6 columns, got $($result.columns.Count)"
}

# Assert primary key
if ($result.primaryKeys -notcontains "ID") {
    throw "Expected ID as primary key"
}

# Assert foreign keys
if ($result.foreignKeys.Count -ne 1) {
    throw "Expected 1 foreign key"
}

# Assert indexes
if ($result.indexes.Count -ne 3) {
    throw "Expected 3 indexes"
}
```

---

### Command 2: Get Trigger Information
```bash
DbExplorer.exe -Profile "ILOGTST" \
  -Command trigger-info \
  -Object "INL.TRG_EXAMPLE_AUDIT" \
  -IncludeSourceCode \
  -Outfile "test_output/trigger_info.json"
```

**Expected Output**:
```json
{
  "schema": "INL",
  "triggerName": "TRG_EXAMPLE_AUDIT",
  "targetSchema": "INL",
  "targetTable": "EXAMPLE_TABLE",
  "triggerTime": "AFTER",
  "triggerEvent": "UPDATE",
  "granularity": "ROW",
  "comment": "Audit trail trigger",
  "sourceCode": "CREATE TRIGGER INL.TRG_EXAMPLE_AUDIT...",
  "retrievedAt": "2025-12-13T10:30:00Z"
}
```

---

### Command 3: List All Triggers in Schema
```bash
DbExplorer.exe -Profile "ILOGTST" \
  -Command trigger-usage \
  -Schema "INL" \
  -Outfile "test_output/triggers.json"
```

**Expected Output**:
```json
{
  "schema": "INL",
  "triggerCount": 25,
  "triggers": [
    {
      "triggerSchema": "INL",
      "triggerName": "TRG_EXAMPLE_AUDIT",
      "targetSchema": "INL",
      "targetTable": "EXAMPLE_TABLE",
      "triggerTime": "AFTER",
      "triggerEvent": "UPDATE",
      "isEnabled": true
    },
    ...
  ],
  "retrievedAt": "2025-12-13T10:30:00Z"
}
```

---

### Command 4: Analyze Dependencies
```bash
DbExplorer.exe -Profile "ILOGTST" \
  -Command dependencies \
  -Object "INL.EXAMPLE_TABLE" \
  -ObjectType TABLE \
  -Outfile "test_output/dependencies.json"
```

**Expected Output**:
```json
{
  "schema": "INL",
  "objectName": "EXAMPLE_TABLE",
  "objectType": "TABLE",
  "dependencyCount": 5,
  "dependencies": [
    {
      "dependencyType": "DEPENDS_ON",
      "targetSchema": "INL",
      "targetObject": "PARENT_TABLE",
      "targetType": "TABLE",
      "relationship": "FOREIGN_KEY"
    },
    {
      "dependencyType": "USED_BY",
      "targetSchema": "INL",
      "targetObject": "CHILD_TABLE",
      "targetType": "TABLE",
      "relationship": "FOREIGN_KEY"
    }
  ],
  "retrievedAt": "2025-12-13T10:30:00Z"
}
```

---

## 📝 COMPLETE TEST SUITE

### PowerShell Test Script:
```powershell
# test_cli_complete.ps1
param(
    [string]$Profile = "ILOGTST",
    [string]$Schema = "INL",
    [string]$Table = "EXAMPLE_TABLE"
)

$ErrorActionPreference = "Stop"
$testsPassed = 0
$testsFailed = 0

Write-Host "`n🧪 CLI Automated Test Suite" -ForegroundColor Cyan
Write-Host "===========================" -ForegroundColor Cyan
Write-Host "Profile: $Profile" -ForegroundColor Yellow
Write-Host "Schema: $Schema" -ForegroundColor Yellow
Write-Host "Table: $Table`n" -ForegroundColor Yellow

# Create output directory
New-Item -ItemType Directory -Force -Path "test_output" | Out-Null

# Test 1: Table Properties
Write-Host "Test 1: Table Properties..." -NoNewline
try {
    .\DbExplorer.exe -Profile $Profile -Command table-props `
        -Object "$Schema.$Table" -IncludeDependencies `
        -Outfile "test_output/table_props.json" | Out-Null
    
    $result = Get-Content "test_output/table_props.json" | ConvertFrom-Json
    
    if ($result.schema -ne $Schema) { throw "Schema mismatch" }
    if ($result.tableName -ne $Table) { throw "Table name mismatch" }
    if ($result.columns.Count -eq 0) { throw "No columns found" }
    if ($null -eq $result.primaryKeys) { throw "No primary keys" }
    
    Write-Host " ✅ PASS" -ForegroundColor Green
    $testsPassed++
} catch {
    Write-Host " ❌ FAIL: $_" -ForegroundColor Red
    $testsFailed++
}

# Test 2: Trigger Information
Write-Host "Test 2: Trigger Information..." -NoNewline
try {
    .\DbExplorer.exe -Profile $Profile -Command trigger-usage `
        -Schema $Schema -Outfile "test_output/triggers.json" | Out-Null
    
    $result = Get-Content "test_output/triggers.json" | ConvertFrom-Json
    
    if ($result.schema -ne $Schema) { throw "Schema mismatch" }
    if ($result.triggerCount -lt 0) { throw "Invalid trigger count" }
    
    Write-Host " ✅ PASS" -ForegroundColor Green
    $testsPassed++
} catch {
    Write-Host " ❌ FAIL: $_" -ForegroundColor Red
    $testsFailed++
}

# Test 3: Dependencies
Write-Host "Test 3: Dependencies..." -NoNewline
try {
    .\DbExplorer.exe -Profile $Profile -Command dependencies `
        -Object "$Schema.$Table" -ObjectType TABLE `
        -Outfile "test_output/dependencies.json" | Out-Null
    
    $result = Get-Content "test_output/dependencies.json" | ConvertFrom-Json
    
    if ($result.objectName -ne $Table) { throw "Object name mismatch" }
    if ($result.objectType -ne "TABLE") { throw "Object type mismatch" }
    
    Write-Host " ✅ PASS" -ForegroundColor Green
    $testsPassed++
} catch {
    Write-Host " ❌ FAIL: $_" -ForegroundColor Red
    $testsFailed++
}

# Summary
Write-Host "`n===========================" -ForegroundColor Cyan
Write-Host "Tests Passed: $testsPassed" -ForegroundColor Green
Write-Host "Tests Failed: $testsFailed" -ForegroundColor $(if ($testsFailed -eq 0) { "Green" } else { "Red" })
Write-Host "===========================" -ForegroundColor Cyan

if ($testsFailed -gt 0) {
    exit 1
}

Write-Host "`n✅ All tests passed!" -ForegroundColor Green
exit 0
```

---

## 🔄 NEXT STEPS

### 1. Once Database is Accessible:

```bash
# Step 1: Find suitable test table
DbExplorer.exe -Profile "ILOGTST" -Sql "SELECT ... (query above)" -Outfile "candidate_tables.json"

# Step 2: Populate this reference document with actual data
# Run all SQL queries in this document against chosen table

# Step 3: Validate CLI output matches reference
# Run test suite and compare results
```

### 2. Create Golden Standard Files:

- `golden_table_props.json` - Expected table properties output
- `golden_triggers.json` - Expected triggers output  
- `golden_dependencies.json` - Expected dependencies output
- `golden_indexes.json` - Expected indexes output

### 3. Automate Validation:

```powershell
# compare_outputs.ps1
$golden = Get-Content "golden_table_props.json" | ConvertFrom-Json
$actual = Get-Content "test_output/table_props.json" | ConvertFrom-Json

# Deep comparison logic
Compare-Object $golden $actual -Property columns, primaryKeys, foreignKeys
```

---

## 📊 SUCCESS CRITERIA

✅ **CLI produces consistent JSON output**  
✅ **All expected fields are present**  
✅ **Data types match reference**  
✅ **Counts match (columns, PKs, FKs, triggers)**  
✅ **Relationships are correctly identified**  
✅ **Source code is retrieved accurately**  
✅ **No data corruption (trimmed strings, correct types)**

---

**This document will be populated with actual data once database connection is available.**

---

**Status**: ⏳ AWAITING DATABASE ACCESS  
**Last Updated**: December 13, 2025  
**Database Error**: SQL30081N (Communication error)  
**Next Action**: Populate with real data from accessible DB2 instance

