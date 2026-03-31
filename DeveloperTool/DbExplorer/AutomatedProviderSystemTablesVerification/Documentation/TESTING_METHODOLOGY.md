# Testing Methodology

**Version**: 1.0  
**Purpose**: Explain how the automated testing framework works internally

---

## 🎯 Overview

The testing framework uses a three-tier approach:
1. **Object Type Validation** - Can all object types be opened?
2. **Tab Selection Validation** - Can all dialog tabs be activated?
3. **CLI vs Form Validation** - Does CLI data match form data?

---

## 🔬 Test Architecture

### Test Flow

```
Provider Config JSON
       ↓
Test Script (PowerShell)
       ↓
DbExplorer.exe CLI
       ↓
Application Opens
       ↓
Dialog/Tab Activated
       ↓
Process Monitoring (timeout protection)
       ↓
Result Captured (JSON)
       ↓
Report Generated
```

### Timeout Protection

All tests include 20-second timeout protection:

```powershell
$elapsed = 0
while ($elapsed < 20) {
    $proc = Get-Process -Name "DbExplorer"
    if ($proc -and $proc.Responding) {
        # Success!
        break
    }
    Start-Sleep -Milliseconds 500
    $elapsed++
}
```

**Why 20 seconds?**
- Database connections: ~2-3 seconds
- Query execution: ~1-5 seconds
- UI rendering: ~1-2 seconds
- Total buffer: 20 seconds is safe

---

## 📊 Test 1: Object Types

### Purpose
Validates that all 13 object types can be opened via CLI `--open` parameter.

### Method

1. Load provider config JSON
2. For each object type:
   - Launch: `DbExplorer.exe --profile X --open Y --type Z`
   - Wait for process to become responsive
   - If responsive within timeout → PASS
   - If timeout or crash → FAIL
3. Kill process and move to next test

### Pass Criteria
- Process starts successfully
- Process responds within timeout
- No unhandled exceptions

### Does NOT Validate
- Data accuracy
- UI rendering correctness
- Full dialog functionality

### Test Duration
- ~15 seconds per object type
- Total: ~3-5 minutes for all 13 types

---

## 🎯 Test 2: Tab Selection

### Purpose
Validates that all tabs in all dialogs can be activated via CLI `--tab` parameter.

### Method

1. Load provider config JSON
2. For each tab:
   - Launch: `DbExplorer.exe --profile X --open Y --type Z --tab TAB`
   - Wait for process to become responsive
   - Check logs for "Activated tab: TAB" message (optional)
   - If responsive within timeout → PASS
   - If timeout or crash → FAIL
3. Kill process and move to next test

### Pass Criteria
- Process starts successfully
- Process responds within timeout
- Tab activation logged (if log checking enabled)
- No unhandled exceptions

### Tab Names Tested

**TableDetailsDialog (9 tabs)**:
- columns, foreign-keys, indexes, ddl-script, statistics
- incoming-fk, packages, views, routines

**ObjectDetailsDialog (5 tabs)**:
- properties, source-code, create-ddl, drop-ddl, dependencies

**PackageDetailsDialog (2 tabs)**:
- properties, statements

**UserDetailsDialog (6 tabs)**:
- authorities, table-privileges, schema-privileges
- routine-privileges, roles, members

### Test Duration
- ~10 seconds per tab
- Total: ~4-5 minutes for all 22 tabs

---

## 🔬 Test 3: CLI vs Form

### Purpose
Compares data retrieved via CLI queries with data displayed in GUI forms.

### Method

1. **CLI Phase**:
   - Execute: `DbExplorer.exe --profile X --command Y`
   - Capture JSON output
   - Parse row counts and data

2. **Form Phase**:
   - Launch: `DbExplorer.exe --profile X --open Y --tab Z`
   - Wait for form to open
   - (Future: Extract form data via GuiTestingService)
   - Currently: Just verify form opens

3. **Comparison Phase**:
   - Compare row counts
   - (Future: Compare actual data values)
   - Report discrepancies

### Current Limitations

**Phase 1 Implementation**:
- ✅ CLI data extraction working
- ✅ Form opening validation working
- ❌ Form data extraction NOT YET implemented
- ❌ Data value comparison NOT YET implemented

**Why?**
Form data extraction requires extending `GuiTestingService` to:
- Access form's internal controls
- Extract DataGrid ItemsSource
- Serialize to JSON
- Return to test script

### Pass Criteria (Current)
- CLI query returns data
- Form opens without crashing
- (Future: Data matches within 95%)

### Test Duration
- ~30 seconds per validation
- Total: ~5-10 minutes for all validations

---

## 📈 Test Results Format

### JSON Output

Each test generates a JSON file:

```json
{
  "provider": "PostgreSQL",
  "version": "15.0",
  "testDate": "2025-12-14T10:30:00Z",
  "testType": "ObjectTypes|TabSelection|CliVsForm",
  "results": {
    "total": 13,
    "passed": 12,
    "failed": 1,
    "skipped": 0,
    "passRate": 92.31
  },
  "details": [
    {
      "Type": "Table",
      "ObjectName": "public.customers",
      "Status": "PASS",
      "Reason": ""
    },
    {
      "Type": "Package",
      "ObjectName": "N/A",
      "Status": "SKIP",
      "Reason": "Not configured"
    },
    {
      "Type": "View",
      "ObjectName": "public.invalid_view",
      "Status": "FAIL",
      "Reason": "Timeout after 20 seconds"
    }
  ]
}
```

### Report Format

`Generate-ProviderReport.ps1` aggregates JSON files into Markdown/HTML:

- Executive summary (pass rates)
- Results by category
- Detailed failure list
- Recommendations

---

## 🐛 Failure Analysis

### Failure Types

| Failure Type | Cause | Fix |
|--------------|-------|-----|
| Timeout | App slow/hanging | Increase timeout or optimize queries |
| Crash | Unhandled exception | Check logs, fix code |
| Not Found | Object doesn't exist | Update config with valid object |
| Permission | No DB access | Grant privileges |
| SQL Error | Invalid query syntax | Fix SQL in JSON config |

### Debugging Process

1. **Check Logs**:
   ```powershell
   Get-Content bin\Debug\net10.0-windows\logs\*.log | Select-String -Pattern "ERROR"
   ```

2. **Manual Test**:
   ```powershell
   # Try manually
   DbExplorer.exe --profile X --open Y --type Z
   ```

3. **Check SQL**:
   - Verify query in `ConfigFiles/[provider]_sql_statements.json`
   - Test query directly in database client

4. **Check Code**:
   - Search for object type handler in `Dialogs/`
   - Verify `ActivateTab()` method exists

---

## 🎓 Test Design Principles

### 1. Isolation
Each test runs independently. No shared state between tests.

### 2. Idempotence
Tests can be run multiple times with same results.

### 3. Timeout Protection
No test hangs indefinitely. All have timeouts.

### 4. Clean Slate
Each test kills previous process before starting.

### 5. Detailed Logging
All results saved to JSON for analysis.

### 6. Progressive Enhancement
Tests start simple (object opening) and get complex (data validation).

---

## 🔮 Future Enhancements

### Phase 2: Full Data Extraction

**Goal**: Extract actual form data, not just verify it opens.

**Approach**:
1. Extend `GuiTestingService.cs`
2. Add method: `ExtractDialogData(dialogType, objectName, tabName)`
3. Return JSON with all field values
4. Compare with CLI data field-by-field

**Benefits**:
- Detect data discrepancies
- Validate data transformations
- Ensure UI accuracy

### Phase 3: Visual Regression

**Goal**: Capture screenshots of each tab for visual comparison.

**Approach**:
1. Use Windows API to capture window screenshots
2. Store baseline screenshots
3. Compare pixel-by-pixel on future runs
4. Report visual differences

**Benefits**:
- Detect UI layout changes
- Catch rendering bugs
- Validate theming

### Phase 4: Performance Profiling

**Goal**: Measure and track performance metrics.

**Approach**:
1. Time each operation
2. Track query execution times
3. Monitor memory usage
4. Generate performance trend reports

**Benefits**:
- Detect performance regressions
- Optimize slow queries
- Validate scalability

---

## 📊 Success Metrics

### Test Quality Metrics

| Metric | Good | Excellent |
|--------|------|-----------|
| Test Coverage | 80%+ | 95%+ |
| Pass Rate | 90%+ | 99%+ |
| Test Duration | <10 min | <5 min |
| False Positives | <5% | <1% |

### Provider Implementation Metrics

| Metric | Target |
|--------|--------|
| Object Types Working | 90%+ |
| Tabs Activating | 95%+ |
| CLI Queries Valid | 100% |
| Forms Displaying Data | 95%+ |

---

## 🛠️ Extending the Framework

### Adding New Test Types

1. Create new PowerShell script in `Scripts/`
2. Follow naming convention: `Test-[Category].ps1`
3. Load config, iterate tests, save JSON results
4. Update `Generate-ProviderReport.ps1` to include new category

### Adding New Assertions

```powershell
# Example: Check for specific log message
$logFile = Get-Content "..\..\bin\Debug\logs\*.log"
$hasError = $logFile | Select-String "ERROR"

if ($hasError) {
    # Report failure
}
```

### Custom Validators

```powershell
# Example: Validate row count matches expected
if ($cliData.Count -ne $expectedCount) {
    Write-Host "❌ FAIL - Expected $expectedCount, got $($cliData.Count)"
}
```

---

## 📝 Documentation Standards

### Test Script Documentation

Each test script should include:
- Synopsis (what it tests)
- Description (how it works)
- Parameters (what's configurable)
- Examples (usage patterns)
- Notes (version, author, caveats)

### Config File Documentation

Each provider config should include:
- Provider name and version
- Test object mappings
- System catalog mappings
- Notes array with provider-specific quirks

### Test Report Documentation

Each report should include:
- Pass/fail summary
- Detailed failure list
- Recommendations
- Timestamp and version info

---

**Next**: See `DB2_EXAMPLE.md` for real-world example  
**Reference**: See `IMPLEMENTATION_GUIDE.md` for step-by-step instructions

