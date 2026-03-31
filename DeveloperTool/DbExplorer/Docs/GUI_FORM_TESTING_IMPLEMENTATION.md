# GUI Form Testing Implementation Plan

**Date**: 2025-12-13  
**Status**: In Progress  
**Purpose**: Enable CLI-driven GUI testing for automated validation

---

## ✅ **COMPLETED**

### 1. DDL Script Error Fixed
- **Problem**: Column 'COLNAME' does not belong to table Results
- **Root Cause**: SQL used `TRIM(COLNAME)` without AS alias
- **Solution**: Added column aliases to GetTableDdlColumns query
- **Status**: ✅ Fixed, committed, build successful

---

## 🔄 **IN PROGRESS - CURRENT SESSION**

### Architecture Overview

```
CLI Mode 1: Direct SQL (EXISTING)
→ DbExplorer.exe --profile BASISTST --command table-properties --object INL.KONTO
→ Executes SQL, returns database data as JSON

CLI Mode 2: Form Testing (NEW)
→ DbExplorer.exe --profile BASISTST --test-form table-details --object INL.KONTO --tab ddl-script
→ Launches GUI, opens dialog, extracts UI data, returns JSON

AI Validation:
→ Compare CLI Mode 1 (database) vs CLI Mode 2 (form display)
→ Verify forms show correct data from correct SQL queries
```

---

## 📋 **IMPLEMENTATION TASKS**

### Phase A: CLI Infrastructure (3 tasks)
1. ⏭️ **Add --test-form parameter** to CliArgumentParser
   - New property: `TestForm` (string)
   - New property: `Tab` (string, optional)
   - Parse `--test-form <dialog-name> --tab <tab-name>`

2. ⏭️ **Create GuiTestingService** class
   - Method: `OpenDialogAndExtractData(dialogName, object, tab)`
   - Returns: Dictionary<string, object> with all form data
   - Handles dialog lifecycle

3. ⏭️ **Update App.xaml.cs** to route to GUI testing
   - If `--test-form` present → call GuiTestingService
   - Extract data, serialize to JSON, write to --outfile
   - Exit with code 0

### Phase B: Form Data Extraction (5 tasks)
4. ⏭️ **TableDetailsDialog.ExtractFormData()**
   - Extract all tabs: Columns, FKs, Indexes, DDL, Statistics, etc.
   - Return structured JSON

5. ⏭️ **ObjectDetailsDialog.ExtractFormData()**
   - Extract table/view/procedure properties

6. ⏭️ **UserDetailsDialog.ExtractFormData()**
   - Extract user authorities

7. ⏭️ **PackageDetailsDialog.ExtractFormData()**
   - Extract package properties

8. ⏭️ **SchemaTableSelectionDialog.ExtractFormData()**
   - Extract schema and table lists

### Phase C: Validation Framework (3 tasks)
9. ⏭️ **Create validation test script**
   - PowerShell script to run CLI vs Form tests
   - Compare results for each dialog/tab
   - Generate validation report

10. ⏭️ **Run comprehensive validation**
    - Test all dialogs
    - Test all tabs in each dialog
    - Document discrepancies

11. ⏭️ **Fix validation issues**
    - Correct SQL queries if mismatched
    - Fix form data extraction if incomplete
    - Update JSON aliases if needed

---

## 🎯 **TARGET DIALOGS FOR TESTING**

### Property Dialogs (High Priority)
1. **TableDetailsDialog** - 9 tabs
   - Columns
   - Foreign Keys
   - Indexes
   - Statistics
   - DDL Script ✅ (fixed)
   - Incoming FK
   - Used By Packages
   - Used By Views
   - Used By Routines

2. **ObjectDetailsDialog** - Multiple tabs
   - Properties
   - Dependencies
   - Permissions

3. **PackageDetailsDialog** - Multiple tabs
   - Properties
   - Statements
   - Dependencies

4. **UserDetailsDialog** - Multiple tabs
   - Authorities
   - Table Privileges
   - Schema Privileges

5. **SchemaTableSelectionDialog**
   - Schema list
   - Table list

---

## 🧪 **VALIDATION STRATEGY**

### Test Pattern
```powershell
# Step 1: Get database data via CLI
$cliData = & DbExplorer.exe --profile BASISTST `
    --command table-properties --object INL.KONTO `
    --outfile cli_data.json

# Step 2: Get form data via GUI testing
$formData = & DbExplorer.exe --profile BASISTST `
    --test-form table-details --object INL.KONTO `
    --tab columns --outfile form_data.json

# Step 3: AI comparison
$comparison = Compare-CliVsForm `
    -CliData (Get-Content cli_data.json | ConvertFrom-Json) `
    -FormData (Get-Content form_data.json | ConvertFrom-Json)

# Result: PASS/FAIL with details
```

### Validation Criteria
✅ **PASS** if:
- Form displays same columns as CLI query returns
- Data types match
- Values match
- No missing fields

❌ **FAIL** if:
- Form uses wrong SQL query
- Missing columns/fields
- Data mismatch
- Form doesn't load

---

## 📊 **EXPECTED OUTCOMES**

### Success Metrics
- All dialogs can export their data
- CLI can trigger any dialog programmatically
- AI can validate 100% of form/tab combinations
- Automated regression testing enabled

### Deliverables
1. ✅ GUI testing infrastructure in CLI
2. ✅ Form data extraction methods
3. ✅ Validation test suite
4. ✅ Comprehensive validation report
5. ✅ Fixed any mismatched SQL queries

---

## 🚧 **POTENTIAL BLOCKERS**

### Known Issues
1. **Complex DataGrid Extraction**
   - Some forms have nested grids
   - May need custom extraction logic

2. **Async Loading**
   - Forms load data asynchronously
   - Must wait for completion before extraction

3. **UI Thread Access**
   - Extraction must run on UI thread
   - May need Dispatcher.Invoke

4. **Database Dependency**
   - Requires live DB2 connection (BASISTST available ✅)
   - Some queries may fail if objects don't exist

---

## 📝 **IMPLEMENTATION STATUS**

**Current**: Creating infrastructure  
**Next**: Add --test-form CLI parameter  
**ETA**: 3-4 hours for full implementation + validation

**Token Usage**: 125K/1M (12.5%)  
**Build Status**: ✅ Successful  
**DB2 Connection**: ✅ Available (BASISTST)

---

## 🔗 **RELATED DOCUMENTATION**

- BLOCKERS.md - Current blockers list
- AUTONOMOUS_IMPLEMENTATION_COMPLETE.md - Previous session summary
- CLI_TEST_PLAN.md - CLI testing documentation
- TASKLIST.md - Overall project tasks

---

**END OF PLAN**

**Status**: Ready to implement Phase A (CLI Infrastructure)

