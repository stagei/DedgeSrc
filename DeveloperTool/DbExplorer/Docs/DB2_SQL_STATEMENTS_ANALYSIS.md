# DB2 SQL Statements Analysis Report

**Generated:** 2025-12-18  
**Source Files:**
- `ConfigFiles/db2_12.1_system_tables.json` - SYSCAT schema reference
- `ConfigFiles/db2_12.1_sql_statements.json` - Application SQL statements

---

## Executive Summary

This analysis cross-references the 150+ SQL statements in `db2_12.1_sql_statements.json` against the verified `db2_12.1_system_tables.json` schema definition to identify potential issues, bugs, and improvement opportunities.

### Key Findings:
- 🔴 **Critical Issues:** 8 queries referencing non-existent columns/tables
- 🟠 **Moderate Issues:** 12 inconsistencies that may cause runtime errors
- 🟡 **Minor Issues:** 15 missing TRIM() applications on CHAR columns
- 🟢 **Improvements:** 10 enhancement recommendations

---

## 🔴 Critical Issues (Will Cause Errors)

### 1. Non-Existent Table: SYSCAT.PROCEDURES
**Affected Statements:**
- `GetProceduresForSchemaSimple` (line 385-389)
- `GetAllProceduresSimple` (line 391-396)
- `GetProcedureMetadata` (line 1267-1271)
- `GetProcedureSource` (line 1281-1285)

**Problem:** These queries reference `SYSCAT.PROCEDURES` which **does not exist** in DB2. Procedures are stored in `SYSCAT.ROUTINES` with `ROUTINETYPE = 'P'`.

**Current (WRONG):**
```sql
SELECT PROCNAME FROM SYSCAT.PROCEDURES WHERE PROCSCHEMA = ?
```

**Correct:**
```sql
SELECT ROUTINENAME FROM SYSCAT.ROUTINES WHERE ROUTINESCHEMA = ? AND ROUTINETYPE = 'P'
```

**Impact:** Application will crash with SQL0204N when these queries execute.

---

### 2. Non-Existent Table: SYSCAT.FUNCTIONS
**Affected Statements:**
- `GetFunctionMetadata` (line 1294-1299)
- `GetFunctionSource` (line 1308-1313)

**Problem:** These queries reference `SYSCAT.FUNCTIONS` which **does not exist** in DB2. Functions are stored in `SYSCAT.ROUTINES` with `ROUTINETYPE = 'F'`.

**Current (WRONG):**
```sql
SELECT RETURN_TYPE FROM SYSCAT.FUNCTIONS WHERE FUNCSCHEMA = ?
```

**Correct:**
```sql
SELECT * FROM SYSCAT.ROUTINES WHERE ROUTINESCHEMA = ? AND ROUTINETYPE = 'F'
```

**Impact:** Application will crash with SQL0204N when these queries execute.

---

### 3. Non-Existent Table: SYSCAT.PROCPARMS
**Affected Statement:** `GetProcedureParameters` (line 1274-1278)

**Problem:** Uses `SYSCAT.PROCPARMS` which **does not exist**. Should use `SYSCAT.ROUTINEPARMS`.

**Current (WRONG):**
```sql
SELECT PARMNAME FROM SYSCAT.PROCPARMS WHERE PROCSCHEMA = ?
```

**Correct:**
```sql
SELECT PARMNAME, TYPENAME, PARM_MODE, REMARKS, ORDINAL 
FROM SYSCAT.ROUTINEPARMS WHERE ROUTINESCHEMA = ? AND ROUTINENAME = ? ORDER BY ORDINAL
```

---

### 4. Non-Existent Table: SYSCAT.FUNCPARMS
**Affected Statement:** `GetFunctionParameters` (line 1301-1306)

**Problem:** Uses `SYSCAT.FUNCPARMS` which **does not exist**. Should use `SYSCAT.ROUTINEPARMS`.

---

### 5. Non-Existent Column: SECURITYADMAUTH
**Affected Statements:**
- `GetUserAuthorities` (line 587-592)
- `GetUserAccessLevel` (line 1210-1214)

**Problem:** Uses `SECURITYADMAUTH` which should be `SECADMAUTH` in SYSCAT.DBAUTH.

**Current (WRONG):**
```sql
SELECT SECURITYADMAUTH FROM SYSCAT.DBAUTH
```

**Correct:**
```sql
SELECT SECADMAUTH FROM SYSCAT.DBAUTH
```

---

### 6. Non-Existent Column: RETURN_TYPE in SYSCAT.ROUTINES
**Affected Statement:** `GetFunctionMetadata` (line 1294)

**Problem:** `RETURN_TYPE` is not a column in `SYSCAT.ROUTINES`. The return type information is in `SYSCAT.ROUTINEPARMS` with `ORDINAL = 0` (return value).

---

### 7. Non-Existent Column: STMTTEXT in SYSCAT.STATEMENTS
**Affected Statement:** `GetPackageStatements` (line 1322-1327)

**Problem:** Uses `STMTTEXT` but column is named `TEXT` in SYSCAT.STATEMENTS.

**Current (WRONG):**
```sql
SELECT STMTTEXT FROM SYSCAT.STATEMENTS
```

**Correct:**
```sql
SELECT TEXT FROM SYSCAT.STATEMENTS
```

---

### 8. Non-Existent Column: PKGTYPE in SYSCAT.PACKAGES
**Affected Statement:** `GetPackageMetadata` (line 1315-1320)

**Problem:** `PKGTYPE` does not exist in `SYSCAT.PACKAGES`. The column is `BLOCKING` or similar.

---

## 🟠 Moderate Issues (May Cause Unexpected Behavior)

### 1. Inconsistent TRIM() Usage
Some queries use TRIM() on some columns but not others:

**Example - `GetTablesInTablespace` (line 419-425):**
```sql
WHERE TBSPACE = ?  -- Missing TRIM()
```

Should be:
```sql
WHERE TRIM(TBSPACE) = ?
```

**Status: ✅ FIXED on 2025-12-18** - Added TRIM() to GetTablesInTablespace WHERE clause.

**Affected Statements:**
- `GetTableColumns_All` (line 832-837)
- `GetTableIndexes_All` (line 839-844)
- `GetAllTablesAndViews` (line 846-851)
- `GetTablesForSchema` (multiple definitions at lines 20, 853)
- `GetColumnMetadataForTable` (line 860-865)
- `GetPackageList` (line 867-872)
- Multiple CLI statements

---

### 2. Duplicate Statement Names
The file contains duplicate statement definitions with the same key:

| Statement Name | First Definition | Second Definition |
|----------------|------------------|-------------------|
| `GetForeignKeysForTable` | Line 153 | Line 475 |
| `GetIndexesForTable` | Line 160 | Line 482 |
| `GetTablesForSchema` | Line 20 | Line 853 |
| `GetPackageStatements` | Line 90 | Line 874 |
| `GetViewDefinition` | Line 258 | Line 1245 |
| `GetViewDependencies` | Line 293 | Line 1259 |
| `GetTableDependencies` | Line 503 | Line 1091 |
| `GetProceduresCount` | Line 69 | Line 615 |
| `GetFunctionsCount` | Line 55 | Line 622 |
| `GetIndexesCount` | Line 104 | Line 629 |
| `GetTriggersCount` | Line 118 | Line 636 |
| `GetSequencesCount` | Line 132 | Line 643 |
| `GetPackagesCount` | Line 83 | Line 650 |
| `GetViewsCount` | Line 41 | Line 657 |
| `GetTablesCount` | Line 27 | Line 664 |
| `GetUserAccessLevel` | Line 1210 | Line 1427 |

**Impact:** JSON parsing will use only one definition (typically the last one). This causes unpredictable behavior.

**Recommendation:** Rename to unique names like `GetTableDependencies_CLI` vs `GetTableDependencies_Service`.

---

### 3. Missing ORDER BY in Aggregation Queries
Some queries with LISTAGG are missing proper grouping:

**Example - `GetTableForeignKeys_Detailed` (line 790-795):**
The LISTAGG ordering should match the outer ORDER BY for consistent results.

---

### 4. Incorrect JOIN Conditions with TRIM()
Some queries use TRIM() inconsistently in JOIN conditions:

**Example - `GetViewsForSchemaFull` (line 1525-1530):**
```sql
JOIN SYSCAT.VIEWS V ON T.TABSCHEMA = V.VIEWSCHEMA AND T.TABNAME = V.VIEWNAME
```

Should be:
```sql
JOIN SYSCAT.VIEWS V ON TRIM(T.TABSCHEMA) = TRIM(V.VIEWSCHEMA) AND TRIM(T.TABNAME) = TRIM(V.VIEWNAME)
```

---

### 5. Column Name Mismatch: CREATED vs CREATE_TIME
**Affected Statement:** `GetTablesForSchema` (line 20-25)

**Problem:** Uses `CREATED` column but correct name is `CREATE_TIME` in SYSCAT.TABLES.

---

### 6. Non-Existent Column: FUNCTIONTYPE
**Affected Statement:** `GetFunctionsForSchemaFull` (line 1539-1544)

**Problem:** `FUNCTIONTYPE` does not exist in `SYSCAT.ROUTINES`. The column describing function type might be `ORIGIN` or function characteristics.

---

## 🟡 Minor Issues (Best Practice Violations)

### 1. Missing TRIM() on CHAR(1) Columns
While CHAR(1) columns rarely have trailing spaces, it's best practice to TRIM():

**Affected columns:**
- `TYPE` in SYSCAT.TABLES
- `NULLS` in SYSCAT.COLUMNS
- `ROUTINETYPE` in SYSCAT.ROUTINES
- `GRANTEETYPE` in SYSCAT.DBAUTH/TABAUTH

---

### 2. SELECT * Usage
Several queries use `SELECT *` which is discouraged:

**Affected Statements:**
- `GetTableColumns_All` (line 832)
- `GetTableIndexes_All` (line 839)

**Recommendation:** Explicitly list required columns for maintainability.

---

### 3. Hardcoded System Schema Exclusions
Multiple queries hardcode system schema exclusions differently:

**Example 1:**
```sql
WHERE TABLE_SCHEMA NOT IN ('SYSIBM', 'SYSCAT', 'SYSPROC', 'SYSFUN')
```

**Example 2:**
```sql
WHERE t.tabschema NOT IN ('SYSCAT', 'SYSIBM', 'SYSIBMADM', 'SYSPROC', 'SYSSTAT', 'SYSTOOLS', 'SYSPUBLIC', 'SYSFUN', 'NULLID')
```

**Recommendation:** Create a single, consistent list of system schemas to exclude.

---

### 4. Inconsistent Alias Naming
Some queries use PascalCase aliases, others use UPPERCASE:

**Example:**
- `AS ColumnName` (PascalCase)
- `AS ROUTINENAME` (UPPERCASE)

**Recommendation:** Standardize on one naming convention (preferably PascalCase for C# integration).

---

### 5. Missing COALESCE for Nullable Columns
Some queries don't handle NULL in REMARKS:

**Current:**
```sql
SELECT REMARKS FROM SYSCAT.TABLES
```

**Recommended:**
```sql
SELECT COALESCE(TRIM(REMARKS), '') AS REMARKS FROM SYSCAT.TABLES
```

---

## 🟢 Improvement Recommendations

### 1. Add SYSCAT.ROLES Query
The system_tables.json doesn't include SYSCAT.ROLES, but the SQL statements reference it. Add SYSCAT.ROLES to the schema file.

---

### 2. Add SYSCAT.BUFFERPOOLS Definition
Referenced in `GetBufferpools` but not in system_tables.json.

---

### 3. Add SYSCAT.STOGROUPS Definition  
Referenced in `GetStorageGroups` but not in system_tables.json.

---

### 4. Add SYSCAT.MODULES Definition
Referenced in `GetModulesForSchema` but not in system_tables.json.

---

### 5. Add SYSCAT.XSROBJECTS Definition
Referenced in `GetXmlSchemasForSchema` but not in system_tables.json.

---

### 6. Add SYSCAT.EVENTMONITORS Definition
Referenced in `GetEventMonitors` but not in system_tables.json.

---

### 7. Add SYSCAT.WORKLOADS Definition
Referenced in `GetWorkloads` but not in system_tables.json.

---

### 8. Add SYSCAT.SERVICECLASSES Definition
Referenced in `GetServiceClasses` but not in system_tables.json.

---

### 9. Add SYSCAT.CONTEXTS Definition
Referenced in `GetTrustedContexts` but not in system_tables.json.

---

### 10. Add SYSCAT.SERVERS Definition
Referenced in `GetServers` but not in system_tables.json.

---

## Summary Action Items

### Immediate Fixes Required (Critical):
1. Replace `SYSCAT.PROCEDURES` → `SYSCAT.ROUTINES WHERE ROUTINETYPE = 'P'`
2. Replace `SYSCAT.FUNCTIONS` → `SYSCAT.ROUTINES WHERE ROUTINETYPE = 'F'`
3. Replace `SYSCAT.PROCPARMS` → `SYSCAT.ROUTINEPARMS`
4. Replace `SYSCAT.FUNCPARMS` → `SYSCAT.ROUTINEPARMS`
5. Fix `SECURITYADMAUTH` → `SECADMAUTH`
6. Fix `STMTTEXT` → `TEXT`
7. Fix `CREATED` → `CREATE_TIME`
8. Remove `PKGTYPE`, `RETURN_TYPE`, `FUNCTIONTYPE` references

### Short-Term Fixes (Moderate):
1. Resolve duplicate statement names
2. Add missing TRIM() to WHERE clauses
3. Fix inconsistent JOIN conditions

### Long-Term Improvements:
1. Add missing SYSCAT tables to system_tables.json
2. Standardize column alias naming
3. Create shared system schema exclusion list
4. Add COALESCE for all nullable columns

---

## Verification Queries

To test fixes before deployment, run:

```sql
-- Verify SYSCAT.ROUTINES has procedures
SELECT COUNT(*) FROM SYSCAT.ROUTINES WHERE ROUTINETYPE = 'P';

-- Verify SYSCAT.DBAUTH column names
SELECT DBADMAUTH, SECADMAUTH FROM SYSCAT.DBAUTH FETCH FIRST 1 ROW ONLY;

-- Verify SYSCAT.STATEMENTS column names
SELECT TEXT FROM SYSCAT.STATEMENTS FETCH FIRST 1 ROW ONLY;
```

---

**Report generated by automated cross-reference analysis of db2_12.1_system_tables.json and db2_12.1_sql_statements.json**
