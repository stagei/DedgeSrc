# CLI Automated Testing Guide

## Overview

The `Test-CLI.ps1` script provides automated regression testing for the SqlMermaidErdTools CLI tool. It reuses the same test files and baseline comparisons as the main C# regression tests.

## Quick Start

### Run All Tests

```powershell
cd D:\opt\src\SqlMermaidErdTools\srcCLI
.\Test-CLI.ps1
```

This will:
1. ✅ Build the CLI project
2. ✅ Pack as .NET Global Tool
3. ✅ Install globally (replacing existing)
4. ✅ Run all tests
5. ✅ Generate report

---

### First-Time Setup (Create Baselines)

```powershell
.\Test-CLI.ps1 -ResetBaseline
```

This creates baseline files in `TestSuite/RegressionTest/Baseline/`:
- `CLI_test_output.mmd` - Baseline Mermaid output
- `CLI_test_AnsiSql.sql` - Baseline AnsiSql output
- `CLI_test_SqlServer.sql` - Baseline SQL Server output
- `CLI_test_PostgreSql.sql` - Baseline PostgreSQL output
- `CLI_test_MySql.sql` - Baseline MySQL output
- `CLI_migration_AnsiSql.sql` - Baseline migration (AnsiSql)
- `CLI_migration_SqlServer.sql` - Baseline migration (SQL Server)
- `CLI_migration_PostgreSql.sql` - Baseline migration (PostgreSQL)
- `CLI_migration_MySql.sql` - Baseline migration (MySQL)

---

### Skip Reinstall (Faster Testing)

If the CLI is already installed and you haven't changed the code:

```powershell
.\Test-CLI.ps1 -SkipInstall
```

This skips the build/pack/install steps and runs tests directly.

---

## What Gets Tested

### Test 1: SQL → Mermaid Conversion
- **Input**: `TestFiles/test.sql`
- **Command**: `sqlmermaid sql-to-mmd test.sql -o test_output.mmd`
- **Baseline**: `Baseline/CLI_test_output.mmd`
- **Validates**: SQL parsing, Mermaid generation, index callouts

### Test 2: Mermaid → SQL (All 4 Dialects)
- **Input**: Generated Mermaid from Test 1
- **Commands**:
  - `sqlmermaid mmd-to-sql test.mmd -d AnsiSql -o test_AnsiSql.sql`
  - `sqlmermaid mmd-to-sql test.mmd -d SqlServer -o test_SqlServer.sql`
  - `sqlmermaid mmd-to-sql test.mmd -d PostgreSql -o test_PostgreSql.sql`
  - `sqlmermaid mmd-to-sql test.mmd -d MySql -o test_MySql.sql`
- **Baselines**: `CLI_test_{dialect}.sql`
- **Validates**: Mermaid parsing, SQL generation, dialect-specific syntax

### Test 3: Schema Diff (All 4 Dialects)
- **Input**: 
  - Before: `TestFiles/testBeforeChange.mmd`
  - After: `TestFiles/testAfterChange.mmd`
- **Commands**:
  - `sqlmermaid diff before.mmd after.mmd -d AnsiSql -o migration_AnsiSql.sql`
  - (Same for SqlServer, PostgreSql, MySql)
- **Baselines**: `CLI_migration_{dialect}.sql`
- **Validates**: Diff detection, ALTER statement generation

---

## Test Results

### Location

All test outputs are saved to:
```
srcCLI/TestResults/{timestamp}/
```

Example:
```
srcCLI/TestResults/20251201_143022/
├── CLI_TEST_REPORT.md           # Full test report
├── test_output.mmd               # Generated Mermaid
├── test_AnsiSql.sql              # Generated SQL (AnsiSql)
├── test_SqlServer.sql            # Generated SQL (SQL Server)
├── test_PostgreSql.sql           # Generated SQL (PostgreSQL)
├── test_MySql.sql                # Generated SQL (MySQL)
├── migration_AnsiSql.sql         # Generated migration (AnsiSql)
├── migration_SqlServer.sql       # Generated migration (SQL Server)
├── migration_PostgreSql.sql      # Generated migration (PostgreSQL)
├── migration_MySql.sql           # Generated migration (MySQL)
├── DIFF_test_output.mmd.txt      # Diff file (if test failed)
├── DIFF_test_AnsiSql.sql.txt     # Diff file (if test failed)
└── ... (more diff files if tests failed)
```

### Report Format

The report (`CLI_TEST_REPORT.md`) includes:
- ✅ CLI installation verification
- ✅ License status
- ✅ Test results for each command
- ✅ Pass/fail summary
- ✅ Detailed diffs for failures

---

## Exit Codes

| Code | Meaning |
|------|---------|
| `0` | All tests passed |
| `1` | One or more tests failed |

Use in CI/CD:
```powershell
.\Test-CLI.ps1
if ($LASTEXITCODE -ne 0) {
    Write-Error "CLI tests failed!"
    exit 1
}
```

---

## Comparison: CLI Tests vs. Main Regression Tests

| Aspect | Main Regression Tests | CLI Tests |
|--------|----------------------|-----------|
| **What's Tested** | C# library directly | CLI tool commands |
| **Test Files** | Same (`TestFiles/`) | Same (`TestFiles/`) |
| **Baselines** | `Baseline/FullCircle_*` | `Baseline/CLI_*` |
| **Execution** | C# executables | CLI commands |
| **Purpose** | Validate core library | Validate CLI wrapper |

Both test suites use the same input files but validate different execution paths!

---

## Troubleshooting

### "CLI tool not found or not working"

**Cause**: CLI not installed or not in PATH

**Solution**:
```powershell
# Run without -SkipInstall
.\Test-CLI.ps1

# Or manually install
dotnet build SqlMermaidErdTools.CLI.csproj -c Release
dotnet pack SqlMermaidErdTools.CLI.csproj -c Release
dotnet tool install -g SqlMermaidErdTools.CLI --add-source ./bin/Release
```

---

### "Baseline not found"

**Cause**: Baseline files not created yet

**Solution**:
```powershell
# Create baselines first
.\Test-CLI.ps1 -ResetBaseline

# Then run tests
.\Test-CLI.ps1
```

---

### "All tests fail after code changes"

**Expected behavior!** This means your changes affected the output.

**Options**:
1. **If changes are intentional**: Reset baseline with `-ResetBaseline`
2. **If changes are bugs**: Fix the code and retest

---

## Integration with Main Regression Tests

You can run both test suites together:

```powershell
# Run main regression tests
.\TestSuite\Scripts\Run-RegressionTests.ps1

# Run CLI tests
.\srcCLI\Test-CLI.ps1

# Both should pass!
```

---

## CI/CD Integration

### Example: GitHub Actions

```yaml
name: Test CLI

on: [push, pull_request]

jobs:
  test-cli:
    runs-on: windows-latest
    
    steps:
    - uses: actions/checkout@v3
    
    - name: Setup .NET
      uses: actions/setup-dotnet@v3
      with:
        dotnet-version: '10.0.x'
    
    - name: Run CLI Tests
      run: .\srcCLI\Test-CLI.ps1
      shell: pwsh
    
    - name: Upload Test Results
      if: always()
      uses: actions/upload-artifact@v3
      with:
        name: cli-test-results
        path: srcCLI/TestResults/**/*
```

---

## Advanced Usage

### Test Only Specific Functionality

Edit the script to comment out tests you don't want to run:

```powershell
# Step 4: Test SQL → Mermaid Conversion
# ... keep this ...

# Step 5: Test Mermaid → SQL Conversion (All Dialects)
# ... comment this out if you only want to test SQL → Mermaid ...

# Step 6: Test Diff Command
# ... comment this out if you don't want to test diff ...
```

---

### Custom Test Files

To test with different files, modify these variables:

```powershell
$testSqlFile = Join-Path $testFilesRoot "your_custom.sql"
$testBeforeMmdFile = Join-Path $testFilesRoot "your_before.mmd"
$testAfterMmdFile = Join-Path $testFilesRoot "your_after.mmd"
```

---

## Baseline Management

### View Baselines

```powershell
cd ..\TestSuite\RegressionTest\Baseline
ls CLI_*
```

### Compare Baselines

```powershell
# Compare CLI vs. Main test baselines
Compare-Object `
    (Get-Content Baseline/CLI_test_output.mmd) `
    (Get-Content Baseline/FullCircle_roundtrip.mmd)
```

### Reset Single Baseline

Instead of resetting all baselines, you can manually update one:

```powershell
# Run test to get new output
.\Test-CLI.ps1 -SkipInstall

# Copy specific output to baseline
$timestamp = "20251201_143022"  # Use actual timestamp
Copy-Item "TestResults/$timestamp/test_PostgreSql.sql" `
          "../TestSuite/RegressionTest/Baseline/CLI_test_PostgreSql.sql" -Force

# Run test again to verify
.\Test-CLI.ps1 -SkipInstall
```

---

## Best Practices

1. ✅ **Reset baseline** when you intentionally change output format
2. ✅ **Run tests** before committing code changes
3. ✅ **Review diffs** carefully when tests fail
4. ✅ **Keep baselines in git** so team members can test
5. ✅ **Use `-SkipInstall`** for faster iteration during development
6. ✅ **Run both test suites** (main + CLI) for complete validation

---

## Summary

**Quick Commands:**

```powershell
# First time: Create baselines
.\Test-CLI.ps1 -ResetBaseline

# Regular testing
.\Test-CLI.ps1

# Fast iteration (skip rebuild)
.\Test-CLI.ps1 -SkipInstall
```

**Total Tests**: 9 tests
- 1 SQL → Mermaid test
- 4 Mermaid → SQL tests (one per dialect)
- 4 Diff tests (one per dialect)

**Test Duration**: ~30 seconds (with install), ~5 seconds (skip install)

---

Made with ❤️ for the SqlMermaidErdTools CLI

