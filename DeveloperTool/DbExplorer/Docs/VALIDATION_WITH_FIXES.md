# Validation Framework with Automatic Fixes

## Enhanced Validation Process

### Standard Validation (What We Had)
1. Execute CLI query
2. Extract Form data
3. Compare results
4. Report match/mismatch

### Enhanced Validation (What We're Doing Now)
1. Execute CLI query
2. Extract Form data
3. Compare results
4. **If mismatch: Determine which is wrong**
5. **Fix the incorrect one**
6. **Re-validate to confirm**
7. Report final status

## Discrepancy Detection & Resolution

### Step 1: Detect Discrepancy
```powershell
if ($cliCount -ne $formCount) {
    Write-Host "❌ MISMATCH DETECTED!" -ForegroundColor Red
    Write-Host "   CLI: $cliCount" -ForegroundColor Yellow
    Write-Host "   Form: $formCount" -ForegroundColor Yellow
}
```

### Step 2: Determine Which Is Wrong

**Investigation Steps:**
1. **Check CLI SQL** - Is the SQL query correct?
   - Verify against DB2 documentation
   - Check SYSCAT table schema
   - Verify column names (COLNAME vs COLUMN_NAME)
   - Check join conditions

2. **Check Form Extraction** - Is the Form getting data correctly?
   - Verify Form loads data (check dialog code)
   - Verify DataGrid is populated
   - Verify public accessor points to correct control
   - Check if data is filtered/transformed

3. **Check Against Truth** - Query DB2 directly
   ```sql
   -- Get actual count from database
   SELECT COUNT(*) FROM SYSCAT.COLUMNS 
   WHERE TABSCHEMA = 'ASK' AND TABNAME = 'VASK_KUNDER'
   ```

### Step 3: Fix the Problem

#### Fix Type A: SQL Query Error in JSON

**Example Problem:**
```json
// WRONG - Missing WHERE clause
"GetTableColumns": {
  "sql": "SELECT * FROM SYSCAT.COLUMNS ORDER BY COLNO"
}

// CORRECT - Proper filtering
"GetTableColumns": {
  "sql": "SELECT * FROM SYSCAT.COLUMNS WHERE TABSCHEMA = ? AND TABNAME = ? ORDER BY COLNO"
}
```

**Fix Process:**
1. Update `ConfigFiles/db2_12.1_sql_statements.json`
2. Verify SQL syntax
3. Re-run CLI command
4. Re-validate

#### Fix Type B: Form Extraction Error

**Example Problem:**
```csharp
// WRONG - Extracting from wrong DataGrid
public DataGrid ColumnsGridPublic => WrongGrid;

// CORRECT - Correct DataGrid
public DataGrid ColumnsGridPublic => ColumnsGrid;
```

**Fix Process:**
1. Update `Dialogs/TableDetailsDialog.xaml.cs`
2. Verify public accessor points to correct control
3. Rebuild application
4. Re-run Form extraction
5. Re-validate

#### Fix Type C: Data Transformation Issue

**Example Problem:**
```csharp
// CLI returns 9 columns
// Form filters out system columns, shows 7

// WRONG - Form should show all columns
if (!column.IsSystemColumn) { ... }

// CORRECT - Show all columns like CLI
// Remove filtering
```

**Fix Process:**
1. Update dialog's LoadDataAsync method
2. Remove unwanted filtering
3. Rebuild
4. Re-validate

### Step 4: Document the Fix

**For Each Fix:**
```markdown
### Fix #1: GetTableColumns Query

**Issue:** CLI returned 0 results, Form returned 9 columns

**Root Cause:** CLI SQL missing TRIM() on TABSCHEMA parameter comparison
- DB2 CHAR columns are space-padded
- WHERE TABSCHEMA = ? fails if parameter is VARCHAR
- WHERE TRIM(TABSCHEMA) = ? succeeds

**Fix Applied:**
- File: ConfigFiles/db2_12.1_sql_statements.json
- Query: GetTableColumns
- Change: Added TRIM() to WHERE clause
- Before: `WHERE TABSCHEMA = ? AND TABNAME = ?`
- After: `WHERE TRIM(TABSCHEMA) = ? AND TRIM(TABNAME) = ?`

**Validation:**
- Re-ran CLI: ✅ Now returns 9 columns
- Re-ran Form: ✅ Still returns 9 columns
- Match: ✅ PASS
```

## Common Issues & Solutions

### Issue 1: TRIM() Missing
**Symptom:** Query returns 0 results even though data exists

**Cause:** DB2 CHAR columns are space-padded, VARCHAR parameters don't match

**Solution:** Add TRIM() to all CHAR column comparisons
```sql
-- Before
WHERE TABSCHEMA = ? AND TABNAME = ?

-- After
WHERE TRIM(TABSCHEMA) = ? AND TRIM(TABNAME) = ?
```

### Issue 2: Column Name Differences
**Symptom:** CLI returns different column names than Form expects

**Cause:** Different queries use different column aliases

**Solution:** Standardize column names with AS aliases
```sql
-- Before
SELECT COLNAME, TYPENAME FROM SYSCAT.COLUMNS

-- After  
SELECT TRIM(COLNAME) AS COLNAME, TRIM(TYPENAME) AS TYPENAME FROM SYSCAT.COLUMNS
```

### Issue 3: JOIN Conditions
**Symptom:** CLI returns wrong data or duplicates

**Cause:** JOIN conditions missing TRIM() or using wrong columns

**Solution:** Add TRIM() to all JOIN conditions
```sql
-- Before
FROM SYSCAT.KEYCOLUSE KC 
JOIN SYSCAT.TABCONST TC ON KC.CONSTNAME = TC.CONSTNAME

-- After
FROM SYSCAT.KEYCOLUSE KC 
JOIN SYSCAT.TABCONST TC ON TRIM(KC.CONSTNAME) = TRIM(TC.CONSTNAME)
  AND TRIM(KC.TABSCHEMA) = TRIM(TC.TABSCHEMA)
  AND TRIM(KC.TABNAME) = TRIM(TC.TABNAME)
```

### Issue 4: Parameter Replacement
**Symptom:** "Wrong number of parameters" error

**Cause:** ? placeholder not replaced with actual value

**Solution:** Use parameter replacement helper
```csharp
// Before
var sql = _metadataHandler.GetQuery("DB2", "12.1", "GetTableColumns");
await ExecuteQueryAsync(sql); // FAILS - still has ?

// After
var sqlTemplate = _metadataHandler.GetQuery("DB2", "12.1", "GetTableColumns");
var sql = ReplaceParameters(sqlTemplate, schema, tableName);
await ExecuteQueryAsync(sql); // SUCCESS
```

### Issue 5: Form Not Loading Data
**Symptom:** Form shows 0 rows when CLI shows data

**Cause:** Async data loading not completing, or DataGrid not bound

**Solution:** 
1. Verify async/await in LoadDataAsync()
2. Verify DataGrid.ItemsSource is set
3. Add delay in test if needed (await Task.Delay(3000))

## Validation Decision Tree

```
Is there a discrepancy?
├─ No → ✅ PASS → Continue
└─ Yes → Investigate
    ├─ CLI = 0, Form > 0 → CLI SQL likely wrong
    │   └─ Fix: Check SQL syntax, add TRIM(), verify parameters
    ├─ CLI > 0, Form = 0 → Form extraction likely wrong
    │   └─ Fix: Check async loading, DataGrid binding, public accessor
    ├─ CLI ≠ Form (both > 0) → Check data transformation
    │   ├─ Form filtering data? → Fix: Remove filter
    │   ├─ CLI returning duplicates? → Fix: Add DISTINCT or fix JOIN
    │   └─ Different queries? → Fix: Ensure both use same query
    └─ After fix → Re-validate
        ├─ Match → ✅ PASS → Document fix
        └─ Still mismatch → Deeper investigation needed
```

## Example: Complete Fix Workflow

### Scenario: GetTableForeignKeys Mismatch

**Initial Validation:**
```
CLI: 5 foreign keys
Form: 3 foreign keys
Status: ❌ MISMATCH
```

**Investigation:**
1. Check CLI SQL in JSON:
   ```sql
   SELECT * FROM SYSCAT.REFERENCES 
   WHERE TABSCHEMA = ? AND TABNAME = ?
   ```
   - SQL looks correct
   - Returns 5 rows

2. Check Form extraction:
   ```csharp
   var sql = _metadataHandler.GetQuery("DB2", "12.1", "GetTableForeignKeys");
   // Different query used in Form!
   ```

3. Check actual dialog code:
   ```csharp
   // FOUND THE ISSUE!
   // Form is filtering:
   if (fk.DeleteRule == "CASCADE") {
       // Only showing CASCADE foreign keys
   }
   ```

**Root Cause:** Form is filtering foreign keys, showing only CASCADE delete rule

**Fix:**
```csharp
// Before (in TableDetailsDialog.xaml.cs)
if (fk.DeleteRule == "CASCADE") {
    ForeignKeysGrid.Items.Add(fk);
}

// After - Show all foreign keys like CLI
ForeignKeysGrid.Items.Add(fk);
```

**Re-Validation:**
```
CLI: 5 foreign keys
Form: 5 foreign keys
Status: ✅ PASS
```

**Documentation:**
- Added to VALIDATION_FIXES.md
- Updated CHANGELOG.md
- Committed with message: "Fix: Remove FK filter in TableDetailsDialog"

## Success Criteria

**For Each Query:**
- ✅ CLI executes without error
- ✅ Form extracts without error
- ✅ CLI count = Form count (or data matches if not countable)
- ✅ Any discrepancies investigated and fixed
- ✅ Re-validation confirms fix
- ✅ Fix documented

**For Complete Validation:**
- ✅ 100% of queries executed
- ✅ 95%+ match rate (after fixes)
- ✅ All discrepancies documented
- ✅ All fixes tested and verified
- ✅ Final report generated

## Tracking Fixes

**Create:** `VALIDATION_FIXES_LOG.md`

```markdown
# Validation Fixes Log

## Fix #1: GetTableColumns - Added TRIM()
- Date: 2025-12-13
- Issue: CLI returned 0, Form returned 9
- Root Cause: Missing TRIM() in WHERE clause
- Fix: Added TRIM(TABSCHEMA) and TRIM(TABNAME)
- Result: ✅ Both now return 9
- Commit: abc1234

## Fix #2: GetTableForeignKeys - Removed Filter
- Date: 2025-12-13
- Issue: CLI returned 5, Form returned 3
- Root Cause: Form filtering by DELETE_RULE = CASCADE
- Fix: Removed if condition, show all FKs
- Result: ✅ Both now return 5
- Commit: def5678

... (continue for all fixes)
```

---

**Status:** Ready to implement enhanced validation with automatic fixing  
**Next Action:** Run comprehensive validation, detect discrepancies, fix them, re-validate  
**Goal:** 100% validation with all discrepancies resolved

