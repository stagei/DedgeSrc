# TestSuite

This directory contains all test projects and scripts for SqlMermaidErdTools.

## Structure

```
TestSuite/
├── ComprehensiveTest/          # Full circle conversion test (SQL→MMD→SQL)
├── TestMmdDiff/                # Mermaid diff to SQL ALTER statements test
├── Scripts/                    # Test automation scripts
│   ├── Run-RegressionTests.ps1 # Main regression test runner
│   └── Test-SqlConversion.ps1  # SQL conversion test script
└── RegressionTest/             # Regression test data
    ├── Baseline/               # Baseline output files for comparison
    ├── BaselineInput/          # Baseline input files (test.sql, testBeforeChange.mmd, testAfterChange.mmd)
    ├── Audit/                  # Timestamped audit folders with all test artifacts
    │   └── YYYYMMDD_HHMMSS/    # Each test run creates a new folder
    │       ├── FullCircle_Export/      # All SQL→MMD→SQL intermediate files
    │       ├── MmdDiffTest_Export/     # All MMD diff intermediate files
    │       ├── DIFF_*.txt              # Detailed diffs for failed comparisons
    │       └── REGRESSION_TEST_REPORT.md  # Complete test report
    └── Reports/                # Legacy report location (also stores copy of reports)
```

## Test Projects

### ComprehensiveTest
**Purpose**: Tests the full circle conversion: SQL → Mermaid ERD → SQL

**What it does**:
1. Reads `TestFiles/test.sql` (ANSI SQL DDL)
2. Converts to Mermaid ERD
3. Converts back to SQL in multiple dialects (ANSI, SQL Server, PostgreSQL, MySQL)
4. Exports all intermediate files for inspection

**Output**: `FullCircle_Export_<timestamp>/` folder with all conversion artifacts

### TestMmdDiff
**Purpose**: Tests bidirectional Mermaid ERD diff to SQL ALTER statements

**What it does**:
1. Reads two Mermaid ERD diagrams: `testBeforeChange.mmd` and `testAfterChange.mmd`
2. Generates forward ALTER statements (Before → After)
3. Generates reverse ALTER statements (After → Before)
4. Tests all SQL dialects (ANSI, SQL Server, PostgreSQL, MySQL)
5. Exports all intermediate files for inspection

**Output**: `MmdDiffTest_Export_<timestamp>/` folder with forward and reverse migrations

## Running Tests

### Regression Tests (Recommended)
```powershell
# From project root
pwsh -ExecutionPolicy Bypass -File "TestSuite\Scripts\Run-RegressionTests.ps1"

# Reset baseline (when you want to accept current output as new baseline)
pwsh -ExecutionPolicy Bypass -File "TestSuite\Scripts\Run-RegressionTests.ps1" -ResetBaseline
```

**Features**:
- ✅ Builds all projects before running tests
- ✅ Verifies input files haven't changed (SHA256 hash comparison)
- ✅ Compares outputs against baseline files
- ✅ Creates timestamped audit folders with ALL intermediate files
- ✅ Generates detailed diff files for failures
- ✅ Produces comprehensive markdown reports
- ✅ Automatically opens report in Cursor

**Audit Folders**: Each test run creates a timestamped folder in `RegressionTest/Audit/` containing:
- Complete export folders from both test projects
- All intermediate `.mmd`, `.sql`, and `.ast` files
- SQLGlot input/output traces
- Diff files showing exact differences for failures
- Complete test report in markdown format

This comprehensive artifact collection enables rapid diagnosis of test failures.

### Individual Test Projects
```powershell
# Run ComprehensiveTest
dotnet run --project TestSuite\ComprehensiveTest\ComprehensiveTest.csproj -c Release

# Run TestMmdDiff
dotnet run --project TestSuite\TestMmdDiff\TestMmdDiff.csproj -c Release
```

### Unit Tests
```powershell
# From project root
dotnet test tests\SqlMermaidErdTools.Tests\SqlMermaidErdTools.Tests.csproj -c Release
```

## Test Input Files

All test input files are located in `TestFiles/` (project root):

- **`test.sql`**: Comprehensive ANSI SQL DDL with ~1300 lines covering:
  - CREATE TABLE statements with various data types
  - PRIMARY KEY and FOREIGN KEY constraints
  - UNIQUE, NOT NULL, DEFAULT constraints
  - Complex relationships and indexes

- **`testBeforeChange.mmd`**: Mermaid ERD diagram representing the "before" schema state (~963 lines)

- **`testAfterChange.mmd`**: Mermaid ERD diagram representing the "after" schema state (~1177 lines)
  - Used to test diff generation and ALTER statement creation

## Baseline Management

### What are Baselines?
Baselines are "golden" output files that represent the expected correct output. Regression tests compare current output against these baselines.

### Baseline Files Location
`TestSuite/RegressionTest/Baseline/`

### When to Reset Baseline
Reset the baseline when:
- You've fixed a bug and want to accept new output as correct
- You've added new features and output format has intentionally changed
- Initial setup (first time running regression tests)

**⚠️ Important**: Always review diff files before resetting baseline to ensure changes are intentional!

### Baseline Input Files
`TestSuite/RegressionTest/BaselineInput/` contains SHA256-hashed copies of input files:
- `test.sql`
- `testBeforeChange.mmd`
- `testAfterChange.mmd`

If input files change, regression tests will warn you that comparisons may be invalid.

## Interpreting Test Results

### Successful Test Run
```
Total Tests:  13
Passed:       13
Failed:       0
Pass Rate:    100%
```

### Failed Tests
When tests fail:
1. Check the audit folder: `TestSuite/RegressionTest/Audit/<timestamp>/`
2. Review `REGRESSION_TEST_REPORT.md` for summary
3. Examine `DIFF_*.txt` files to see exact differences
4. Inspect export folders to see all intermediate files
5. Compare `*-In.mmd` and `*-Out.sql` files to understand transformations

## Troubleshooting

### Non-Deterministic Output
If tests fail randomly with different output each run:
- Clear Python cache: Remove `__pycache__` directories
- Check for set/dict iteration without explicit sorting
- Review `*-OutFromSqlGlot*.sql` files in audit folder to see SQLGlot's output

### Build Failures
```powershell
# Clean and rebuild
dotnet clean
dotnet build -c Release
```

### Missing Dependencies
The test projects depend on:
- **SqlMermaidErdTools** (main project) - must be built first
- **Bundled Python runtime** with SQLGlot
- **Bundled Node.js runtime** with little-mermaid-2-the-sql

The regression test script automatically builds all dependencies in correct order.

## CI/CD Integration

To integrate regression tests into CI/CD:

```yaml
# Example GitHub Actions / Azure DevOps
steps:
  - name: Run Regression Tests
    run: pwsh -ExecutionPolicy Bypass -File "TestSuite/Scripts/Run-RegressionTests.ps1"
    
  - name: Upload Audit Artifacts on Failure
    if: failure()
    uses: actions/upload-artifact@v3
    with:
      name: regression-test-audit
      path: TestSuite/RegressionTest/Audit/
      retention-days: 30
```

## Contributing

When adding new test cases:
1. Add test data to `TestFiles/`
2. Update test projects to include new scenarios
3. Run regression tests with `-ResetBaseline` to create new baseline
4. Commit both test code and baseline files
5. Document new test scenarios in this README

## Notes

- All test scripts use PowerShell 7+ (`pwsh`)
- Tests can be run from any directory (paths are auto-resolved)
- Regression tests automatically clean up old export folders
- Audit folders are kept indefinitely for historical analysis
- Test reports include clickable file paths for easy navigation in Cursor
