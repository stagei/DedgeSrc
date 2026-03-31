# Enhanced Validation with Web Verification

## Validation Process with IBM Documentation Check

### When CLI Query Returns Unexpected Results:

**Step 1: Detect Issue**
```powershell
if ($cliCount -eq 0 -or $cliCount -ne $formCount) {
    # Issue detected - verify SQL against IBM docs
}
```

**Step 2: Web Search for IBM DB2 12.1 Documentation**

Search patterns:
- `"IBM DB2 12.1 SYSCAT.TABLES columns"`
- `"IBM DB2 12.1 SYSCAT.COLUMNS schema"`
- `"DB2 12.1 SYSCAT.REFERENCES documentation"`

**Step 3: Verify Against Official Schema**

Example for SYSCAT.COLUMNS:
```
Search: "IBM DB2 12.1 SYSCAT.COLUMNS"
Official columns: TABSCHEMA, TABNAME, COLNAME, COLNO, TYPENAME, LENGTH, 
                  SCALE, NULLS, DEFAULT, etc.

Our query uses: COLNAME ✅, TYPENAME ✅, NULLS ✅
Missing: SCALE ❌ (should we include?)
Wrong: COLUMN_NAME ❌ (should be COLNAME)
```

**Step 4: Fix Based on Documentation**

Update SQL in `db2_12.1_sql_statements.json` to match IBM specs exactly.

## Common SYSCAT Tables to Verify

### Priority 1: Core Tables
1. **SYSCAT.TABLES** - Table metadata
2. **SYSCAT.COLUMNS** - Column definitions
3. **SYSCAT.INDEXES** - Index information
4. **SYSCAT.REFERENCES** - Foreign key relationships
5. **SYSCAT.KEYCOLUSE** - Primary key columns
6. **SYSCAT.VIEWS** - View definitions
7. **SYSCAT.ROUTINES** - Procedures/Functions

### Priority 2: Relationships
8. **SYSCAT.TABDEP** - Table dependencies
9. **SYSCAT.ROUTINEDEP** - Routine dependencies
10. **SYSCAT.TABCONST** - Table constraints

### Priority 3: Security
11. **SYSCAT.DBAUTH** - Database authorities
12. **SYSCAT.TABAUTH** - Table privileges

### Priority 4: Objects
13. **SYSCAT.TRIGGERS** - Trigger definitions
14. **SYSCAT.SEQUENCES** - Sequence objects
15. **SYSCAT.PACKAGES** - Package metadata
16. **SYSCAT.STATEMENTS** - Package statements

## Web Search Strategy

### For Each SYSCAT Table:

**Search Query:**
```
"IBM DB2 12.1 SYSCAT.{TABLE_NAME}"
"DB2 12.1 catalog views SYSCAT.{TABLE_NAME}"
"IBM Knowledge Center DB2 12.1 SYSCAT.{TABLE_NAME}"
```

**Look For:**
- Official column list
- Data types for each column
- Join relationships
- Example queries
- Version differences (11.5 vs 12.1)

**Verify:**
- Column names (exact spelling, case)
- Required columns (can't SELECT * if column doesn't exist)
- WHERE clause compatibility
- JOIN conditions

## Example: Verifying SYSCAT.COLUMNS

### Issue Detected
```
Query: SELECT COLNAME, TYPENAME, LENGTH, SCALE, NULLS 
       FROM SYSCAT.COLUMNS 
       WHERE TABSCHEMA = ? AND TABNAME = ?

Result: 0 rows (expected 5)
```

### Web Search
**Query:** `"IBM DB2 12.1 SYSCAT.COLUMNS"`

**Official IBM Documentation:**
```
SYSCAT.COLUMNS contains one row for each column in a table or view.

Columns:
- TABSCHEMA (VARCHAR(128)) - Schema name
- TABNAME (VARCHAR(128)) - Table name  
- COLNAME (VARCHAR(128)) - Column name
- COLNO (SMALLINT) - Column position
- TYPENAME (VARCHAR(18)) - Data type name
- LENGTH (INTEGER) - Maximum length
- SCALE (SMALLINT) - Scale for decimal
- NULLS (CHAR(1)) - Y=nullable, N=not null
- DEFAULT (CLOB) - Default value
...

Note: TABSCHEMA and TABNAME are CHAR type, space-padded!
```

### Root Cause Identified
**Problem:** CHAR columns are space-padded, VARCHAR parameter doesn't match

**IBM Best Practice:** Always use TRIM() when comparing CHAR columns to VARCHAR

### Fix Applied
```sql
-- BEFORE (Wrong)
SELECT COLNAME, TYPENAME, LENGTH, SCALE, NULLS 
FROM SYSCAT.COLUMNS 
WHERE TABSCHEMA = ? AND TABNAME = ?

-- AFTER (Correct per IBM docs)
SELECT TRIM(COLNAME) AS COLNAME, 
       TRIM(TYPENAME) AS TYPENAME, 
       LENGTH, 
       SCALE, 
       TRIM(NULLS) AS NULLS,
       TRIM(DEFAULT) AS DEFAULT
FROM SYSCAT.COLUMNS 
WHERE TRIM(TABSCHEMA) = ? AND TRIM(TABNAME) = ?
ORDER BY COLNO
```

### Re-Validation
```
Result: 5 rows ✅
Form: 5 rows ✅
Status: PASS ✅
```

## Documentation Sources

### Primary Sources:
1. **IBM Knowledge Center** (official)
   - https://www.ibm.com/docs/en/db2/12.1
   - Most authoritative source

2. **IBM Db2 12.1 SQL Reference**
   - System catalog views
   - Column definitions
   - Data types

3. **IBM Redbooks**
   - Best practices
   - Example queries
   - Performance tips

### Search Strategy:
```
Priority 1: IBM Knowledge Center (ibm.com/docs)
Priority 2: IBM Developer (developer.ibm.com)
Priority 3: Stack Overflow (for known issues)
```

## Common DB2 12.1 Gotchas

### 1. CHAR vs VARCHAR
**Issue:** CHAR columns are space-padded
**Solution:** Always TRIM()
```sql
WHERE TRIM(TABSCHEMA) = ?  -- NOT: WHERE TABSCHEMA = ?
```

### 2. Column Name Changes Between Versions
**Issue:** Column names differ in DB2 11.5 vs 12.1
**Solution:** Check version-specific docs
```
DB2 11.5: FIRST_KEYCARD
DB2 12.1: FIRSTKEYCARD (no underscore!)
```

### 3. CLOB vs VARCHAR
**Issue:** Some columns are CLOB (e.g., DEFAULT, TEXT)
**Solution:** Cast to VARCHAR if needed
```sql
SELECT TRIM(CAST(DEFAULT AS VARCHAR(254))) AS DEFAULT_VALUE
```

### 4. Join Requirements
**Issue:** Some catalogs require multi-column joins
**Solution:** Verify join conditions in IBM docs
```sql
-- WRONG (incomplete join)
JOIN SYSCAT.TABCONST TC ON KC.CONSTNAME = TC.CONSTNAME

-- CORRECT (per IBM docs)
JOIN SYSCAT.TABCONST TC 
  ON TRIM(KC.CONSTNAME) = TRIM(TC.CONSTNAME)
  AND TRIM(KC.TABSCHEMA) = TRIM(TC.TABSCHEMA)
  AND TRIM(KC.TABNAME) = TRIM(TC.TABNAME)
```

### 5. System vs User Objects
**Issue:** Queries return system objects
**Solution:** Filter by TYPE or schema
```sql
-- Filter out system tables
WHERE TYPE IN ('T', 'U')  -- T=Table, U=User table, exclude S=System

-- Or filter by schema
WHERE TABSCHEMA NOT LIKE 'SYS%'
```

## Validation Workflow with Web Search

```
1. Execute CLI query
   ↓
2. Returns unexpected result (0 rows, wrong count)
   ↓
3. 🔍 WEB SEARCH: "IBM DB2 12.1 SYSCAT.{TABLE}"
   ↓
4. Compare our SQL with IBM documentation
   ↓
5. Identify discrepancy:
   - Missing TRIM()?
   - Wrong column name?
   - Missing JOIN condition?
   - Wrong filter?
   ↓
6. Fix SQL in db2_12.1_sql_statements.json
   ↓
7. Re-execute CLI query
   ↓
8. Verify against Form data
   ↓
9. Document fix in VALIDATION_FIXES_LOG.md
   ↓
10. Commit with reference to IBM docs
```

## Fix Documentation Template

```markdown
### Fix #X: {QueryName} - Verified Against IBM Docs

**Issue:** CLI returned {X}, Form returned {Y}

**Web Search:** "IBM DB2 12.1 SYSCAT.{TABLE}"
**IBM Documentation:** 
- URL: https://www.ibm.com/docs/...
- Column Schema: [list columns]
- Key Finding: {what we learned}

**Root Cause:** 
- Our SQL: {what was wrong}
- IBM Spec: {what it should be}

**Fix Applied:**
```sql
-- Before
{old SQL}

-- After (per IBM docs)
{new SQL}
```

**Validation:**
- CLI: {before} → {after} ✅
- Form: {count} ✅
- Match: PASS ✅

**IBM Doc Reference:** [URL]
**Commit:** {hash}
```

## Success Criteria with Web Verification

For each failing query:
- ✅ Web search performed for SYSCAT table
- ✅ IBM documentation reviewed
- ✅ SQL verified against official schema
- ✅ Fix applied based on IBM specs
- ✅ Re-validation confirms fix
- ✅ IBM doc URL documented
- ✅ Fix committed with reference

---

**This ensures our SQL queries are 100% accurate per IBM DB2 12.1 official specifications!**

