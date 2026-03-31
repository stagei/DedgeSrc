# DB2 SQL Statements - Duplicate Analysis Report

**Generated:** 2025-12-18  
**Status:** ✅ ALL FIXES APPLIED  
**Purpose:** Identify duplicate statement names and recommend corrections

---

## Summary of Duplicates Found

| Statement Name | Line (1st) | Line (2nd) | Line (3rd) | Recommendation |
|----------------|------------|------------|------------|----------------|
| GetTablesForSchema | 20 | 853 | - | Rename 2nd → `GetTablesForSchema_MetadataLoader` |
| GetTablesCount | 27 | 664 | - | Keep both different (different TYPE filters) → Rename 2nd to `GetTablesCount_BaseOnly` |
| GetForeignKeysForTable | 153 | 475 | - | Keep both → Rename 2nd to `GetForeignKeysForTable_Full` |
| GetIndexesForTable | 160 | 482 | - | Keep both → Rename 2nd to `GetIndexesForTable_WithColumns` |
| GetPackageStatements | 90 | 874 | 1322 | Keep 1st, rename 2nd to `GetPackageStatements_Simple`, **FIX 3rd (STMTTEXT→TEXT)** → `GetPackageStatements_AI` |
| GetViewDefinition | 258 | 1245 | - | Keep 1st, rename 2nd to `GetViewDefinition_AI` + add TRIM() |
| GetViewDependencies | 293 | 1259 | - | Keep both → Rename 2nd to `GetViewDependencies_TablesOnly` |
| GetSequencesForSchema | 125 | 573 | - | Keep both → Rename 2nd to `GetSequencesForSchema_Full` + add SEQTYPE filter |
| GetTableDependencies | 503 | 1091 | - | Keep both → Rename 2nd to `GetTableDependencies_Outgoing` + add TRIM() |
| GetUserAccessLevel | 1210 | 1427 | - | Keep both → Rename 2nd to `GetCurrentUserAccessLevel` |
| GetProceduresCount | 69 | 615 | - | Identical → Remove duplicate |
| GetFunctionsCount | 55 | 622 | - | Identical → Remove duplicate |
| GetIndexesCount | 104 | 629 | - | Identical → Remove duplicate |
| GetTriggersCount | 118 | 636 | - | Identical → Remove duplicate |
| GetSequencesCount | 132 | 643 | - | Identical → Remove duplicate |
| GetPackagesCount | 83 | 650 | - | Identical → Remove duplicate |
| GetViewsCount | 41 | 657 | - | Identical → Remove duplicate |

---

## Critical Fixes Required

### 1. Line 21: `CREATED` → `CREATE_TIME`
```sql
-- WRONG:
SELECT ... CREATED, ...
-- CORRECT:
SELECT ... CREATE_TIME, ...
```
**Schema Reference:** SYSCAT.TABLES has `CREATE_TIME` column, not `CREATED`

### 2. Line 1323: `STMTTEXT` → `TEXT`
```sql
-- WRONG:
SELECT STMTTEXT FROM SYSCAT.STATEMENTS
-- CORRECT:
SELECT TEXT FROM SYSCAT.STATEMENTS
```
**Schema Reference:** SYSCAT.STATEMENTS has `TEXT` column, not `STMTTEXT`

### 3. Line 573: Missing `SEQTYPE = 'S'` filter
The second `GetSequencesForSchema` should filter for user sequences only:
```sql
-- Current (missing filter):
WHERE TRIM(SEQSCHEMA) = ?
-- Correct:
WHERE TRIM(SEQSCHEMA) = ? AND SEQTYPE = 'S'
```

### 4. Multiple statements missing TRIM() in WHERE clause
Lines affected: 853, 860-862, 867-868, 874-876, 1091-1093, 1218, 1245-1247, 1259-1261

---

## Detailed Duplicate Analysis

### 1. GetTablesForSchema (Lines 20 vs 853)

**Line 20 (KEEP - with fix):**
```sql
SELECT TRIM(TABNAME) AS TABNAME, TRIM(OWNER) AS OWNER, CREATE_TIME, CARD AS ROW_COUNT, TRIM(REMARKS) AS REMARKS 
FROM SYSCAT.TABLES WHERE TRIM(TABSCHEMA) = ? AND TYPE IN ('T', 'S', 'G', 'H', 'L', 'N', 'U', 'W') ORDER BY TABNAME
```
- ✅ Uses TRIM()
- ❌ Uses `CREATED` instead of `CREATE_TIME` - **FIX REQUIRED**
- ✅ Filters for multiple table types

**Line 853 (RENAME to GetTablesForSchema_MetadataLoader):**
```sql
SELECT TABSCHEMA, TABNAME, TYPE FROM SYSCAT.TABLES WHERE TABSCHEMA = ? AND TYPE = 'T' ORDER BY TABNAME
```
- ❌ Missing TRIM() - **FIX REQUIRED**
- ✅ Simple metadata-only query

---

### 2. GetForeignKeysForTable (Lines 153 vs 475)

**Line 153 (KEEP - PropertyDialogs):**
- Simpler columns: FK_NAME, REF_SCHEMA, REF_TABLE, FK_COLUMNS, PK_COLUMNS, DELETE_RULE, UPDATE_RULE
- Has ORDER BY

**Line 475 (RENAME to GetForeignKeysForTable_Full):**
- More columns: CONSTNAME, TABSCHEMA, TABNAME, REFTABSCHEMA, REFTABNAME, etc.
- Missing ORDER BY - **ADD ORDER BY**

---

### 3. GetIndexesForTable (Lines 160 vs 482)

**Line 160 (KEEP - Simple):**
- Basic query from SYSCAT.INDEXES only
- Columns: INDNAME, UNIQUERULE, INDEXTYPE, COLNAMES, CREATE_TIME

**Line 482 (RENAME to GetIndexesForTable_WithColumns):**
- Complex query with LISTAGG join to SYSCAT.INDEXCOLUSE
- Returns individual column details with ASC/DESC

---

### 4. GetPackageStatements (Lines 90 vs 874 vs 1322)

**Line 90 (KEEP - Best):**
- Uses TRIM() on all CHAR columns
- Joins STATEMENTS to PACKAGES
- Returns STMTNO, SECTNO, SEQNO, STATEMENT_TEXT
- Proper ORDER BY

**Line 874 (RENAME to GetPackageStatements_Simple):**
- Simpler query, just TEXT
- Missing TRIM() - **FIX REQUIRED**

**Line 1322 (RENAME to GetPackageStatements_AI + FIX):**
- Uses `STMTTEXT` which does not exist - **CRITICAL FIX: Change to TEXT**
- Missing TRIM()

---

### 5. GetUserAccessLevel (Lines 1210 vs 1427)

**Line 1210 (KEEP - Parameter-based):**
- Takes USERNAME parameter
- Uses TRIM()
- Returns: DBADMAUTH, SECURITYADMAUTH (aliased as SECADMAUTH)

**Line 1427 (RENAME to GetCurrentUserAccessLevel):**
- Uses `CURRENT USER` instead of parameter
- Returns more columns: DBADMAUTH, SECURITYADMAUTH, DATAACCESSAUTH, CREATETABAUTH, BINDADDAUTH
- No parameter needed

---

## Schema Verification

Based on `db2_12.1_system_tables.json`:

| Column Name | Correct | Notes |
|-------------|---------|-------|
| SECURITYADMAUTH | ✅ Yes | Line 535 of schema file confirms this |
| CREATE_TIME | ✅ Yes | SYSCAT.TABLES has CREATE_TIME, not CREATED |
| TEXT | ✅ Yes | SYSCAT.STATEMENTS has TEXT, not STMTTEXT |
| SEQTYPE | ✅ Yes | SYSCAT.SEQUENCES has SEQTYPE (S=User sequence, I=Identity) |

---

## Recommended Actions

1. **Fix CREATED → CREATE_TIME** in line 21
2. **Fix STMTTEXT → TEXT** in line 1323
3. **Add SEQTYPE = 'S'** filter to line 573
4. **Rename duplicates** with unique suffixes:
   - `_Simple` for simpler versions
   - `_Full` for more complete versions
   - `_AI` for AI/context builder versions
   - `_CLI` for CLI command versions
   - `_MetadataLoader` for metadata loading
   - `_WithColumns` for queries with column details
5. **Remove identical duplicates** (count queries)
6. **Add TRIM()** to all WHERE clauses using CHAR columns
