# Regression Test Audit Folder Guide

## Overview

Every regression test run creates a timestamped audit folder containing **all** test artifacts. This comprehensive collection enables rapid diagnosis of test failures and provides a complete historical record of test executions.

## Folder Structure

```
TestSuite/RegressionTest/Audit/
└── YYYYMMDD_HHMMSS/                          # Timestamp: 20251201_183422
    ├── REGRESSION_TEST_REPORT.md             # Complete test report
    ├── DIFF_*.txt                            # Detailed diffs for failed tests
    ├── FullCircle_Export/                    # SQL→MMD→SQL conversion artifacts
    │   ├── roundtrip.mmd                     # Final Mermaid diagram
    │   ├── SqlToMmd-In_Original.sql          # Original input SQL
    │   ├── SqlToMmd-In_Cleaned.sql           # Cleaned SQL (comments removed)
    │   ├── SqlToMmd-In.sql                   # Normalized SQL
    │   ├── SqlToMmd-InToSqlGlot*.sql         # SQLGlot processed input
    │   ├── SqlToMmd-Out.ast                  # SQLGlot AST representation
    │   ├── SqlToMmd-Out.mmd                  # Generated Mermaid diagram
    │   ├── SqlToMmd-OutFromSqlGlot*.mmd      # Mermaid from SQLGlot
    │   ├── AnsiSql/
    │   │   ├── MmdToSql_AnsiSql-In.mmd       # Input Mermaid
    │   │   ├── MmdToSql_AnsiSql-InToSqlGlot*.mmd
    │   │   ├── MmdToSql_AnsiSql-Out.sql      # Generated SQL
    │   │   ├── MmdToSql_AnsiSql-OutFromSqlGlot*.sql
    │   │   └── roundtrip_AnsiSql.sql         # Final roundtrip SQL
    │   ├── SqlServer/...                     # Same structure for SQL Server
    │   ├── PostgreSql/...                    # Same structure for PostgreSQL
    │   ├── MySql/...                         # Same structure for MySQL
    │   └── Translated_*/                     # Dialect translations
    │       └── SqlDialectTranslate_*.sql     # Translation artifacts
    └── MmdDiffTest_Export/                   # MMD diff to SQL ALTER artifacts
        ├── Forward_Before-To-After/          # Before → After migrations
        │   ├── AnsiSql/
        │   │   ├── MmdDiff_AnsiSql-In_Before.mmd
        │   │   ├── MmdDiff_AnsiSql-In_After.mmd
        │   │   ├── MmdDiff_AnsiSql-Out.sql
        │   │   ├── MmdDiff_AnsiSql-OutFromSqlGlot*.sql
        │   │   └── forward_alter_AnsiSql.sql # Final ALTER statements
        │   ├── SqlServer/...
        │   ├── PostgreSql/...
        │   └── MySql/...
        └── Reverse_After-To-Before/          # After → Before (rollback)
            ├── AnsiSql/...
            ├── SqlServer/...
            ├── PostgreSql/...
            └── MySql/...
```

## File Types and Purpose

### Test Report
- **`REGRESSION_TEST_REPORT.md`**: Complete markdown report with test summary, pass/fail status, file sizes, and execution times.

### Diff Files
- **`DIFF_MermaidDiff_Direction1_AnsiSql.sql.txt`**: Shows exact differences between baseline and current output
- **`DIFF_MermaidDiff_Direction2_PostgreSql.sql.txt`**: Example of direction 2 diff for PostgreSQL
- Format:
  ```
  === BASELINE ===
  [baseline content]
  
  === CURRENT ===
  [current output]
  ```

### Conversion Artifacts

#### Input Files
- **`*-In_Original.sql`**: Original input SQL with all comments and formatting
- **`*-In_Cleaned.sql`**: SQL with comments stripped
- **`*-In.sql`**: Normalized SQL ready for conversion
- **`*-In.mmd`**: Input Mermaid diagram

#### SQLGlot Processing
- **`*-InToSqlGlot*.sql`**: SQL after SQLGlot parsing and pretty-printing
- **`*-InToSqlGlot*.mmd`**: Mermaid after SQLGlot processing
- Timestamp in filename indicates when SQLGlot processed the file

#### Output Files
- **`*-Out.sql`**: Final generated SQL
- **`*-Out.mmd`**: Final generated Mermaid diagram
- **`*-Out.ast`**: SQLGlot Abstract Syntax Tree (JSON format)
- **`*-OutFromSqlGlot*.sql`**: SQL from SQLGlot before any post-processing

#### Final Results
- **`roundtrip.mmd`**: Complete Mermaid diagram after full circle conversion
- **`roundtrip_AnsiSql.sql`**: SQL after MMD→SQL conversion (ANSI dialect)
- **`forward_alter_AnsiSql.sql`**: ALTER statements for forward migration
- **`reverse_alter_MySql.sql`**: ALTER statements for reverse migration

## Using Audit Folders for Debugging

### Scenario 1: Non-Deterministic Output

**Problem**: Tests fail randomly with different output each run.

**Solution**:
1. Compare multiple audit folders from consecutive runs
2. Check `*-OutFromSqlGlot*.sql` files - if they differ, the issue is in SQLGlot
3. If SQLGlot output is consistent but final output differs, the issue is in post-processing
4. Look for:
   - Dictionary/set iteration without sorting
   - Random number generation
   - Timestamp-based ordering
   - Hash-based ordering

### Scenario 2: Conversion Failure

**Problem**: Conversion produces incorrect or incomplete output.

**Solution**:
1. Check `*-In_Original.sql` → `*-In_Cleaned.sql` → `*-In.sql` pipeline
2. Review `*.ast` file to see SQLGlot's interpretation
3. Compare `*-InToSqlGlot*.sql` with `*-In.sql` to identify parsing issues
4. Check `*-OutFromSqlGlot*` files to see what SQLGlot generated
5. Compare with `*-Out.*` files to identify post-processing issues

### Scenario 3: Baseline Mismatch

**Problem**: Output differs from baseline but you don't know why.

**Solution**:
1. Read `DIFF_*.txt` files to see exact differences
2. Trace the conversion pipeline:
   ```
   Input → Cleaned → Normalized → SQLGlot → AST → Output → Final
   ```
3. Compare baseline files with current audit folder files
4. Use audit folder files to understand the complete transformation

### Scenario 4: Dialect-Specific Issues

**Problem**: One SQL dialect works, others fail.

**Solution**:
1. Compare audit folders between dialects:
   ```
   MmdDiffTest_Export/Forward_Before-To-After/
   ├── AnsiSql/     ← Works
   ├── SqlServer/   ← Fails
   ├── PostgreSql/  ← Works
   └── MySql/       ← Fails
   ```
2. Check `*-OutFromSqlGlot*.sql` to see if SQLGlot generates different output per dialect
3. Review dialect-specific type mappings and syntax

## Historical Analysis

### Comparing Test Runs
```powershell
# List all audit folders chronologically
Get-ChildItem "TestSuite\RegressionTest\Audit" | Sort-Object Name

# Compare two specific runs
diff (Get-Content "TestSuite\RegressionTest\Audit\20251201_183422\REGRESSION_TEST_REPORT.md") `
     (Get-Content "TestSuite\RegressionTest\Audit\20251201_183437\REGRESSION_TEST_REPORT.md")
```

### Tracking Changes Over Time
- Each audit folder is a snapshot of a specific test run
- Compare baseline files with audit outputs to see evolution
- Track when specific tests started failing
- Identify patterns in failures (always same file? same dialect?)

## Best Practices

### Before Resetting Baseline
1. ✅ Review latest audit folder
2. ✅ Check all DIFF files
3. ✅ Verify changes are intentional
4. ✅ Document why baseline is being reset

### When Debugging
1. ✅ Always check the most recent audit folder first
2. ✅ Compare with previous runs to identify when failure started
3. ✅ Use SQLGlot intermediate files to isolate issues
4. ✅ Keep audit folders for failed tests until issue is resolved

### Cleaning Up
- Audit folders can grow large over time
- Keep recent audit folders (last 30 days)
- Archive folders with important baseline resets
- Delete folders for successful runs after verification

```powershell
# Remove audit folders older than 30 days
$thirtyDaysAgo = (Get-Date).AddDays(-30)
Get-ChildItem "TestSuite\RegressionTest\Audit" | 
    Where-Object { $_.LastWriteTime -lt $thirtyDaysAgo } | 
    Remove-Item -Recurse -Force
```

## Integration with CI/CD

### Artifact Upload on Failure
```yaml
- name: Run Regression Tests
  run: pwsh -File "TestSuite/Scripts/Run-RegressionTests.ps1"
  
- name: Upload Audit Artifacts
  if: failure()
  uses: actions/upload-artifact@v3
  with:
    name: regression-test-audit-${{ github.run_number }}
    path: TestSuite/RegressionTest/Audit/
    retention-days: 30
```

### Artifact Download
```powershell
# Download artifact from CI
gh run download <run-id> -n regression-test-audit-<run-number>

# Extract and analyze
cd regression-test-audit-<run-number>
code REGRESSION_TEST_REPORT.md
```

## Troubleshooting Common Issues

### Issue: Audit folder is empty
**Cause**: Test executable failed before creating export folder  
**Solution**: Check test project build output and error logs

### Issue: Missing export files
**Cause**: Export path not configured or test failed early  
**Solution**: Check test project `ExportFolderPath` property

### Issue: SQLGlot files have wrong extension
**Cause**: SQLGlot didn't recognize file format  
**Solution**: Check input file encoding and format

### Issue: Timestamp files accumulating
**Cause**: Normal operation - each SQLGlot call creates timestamped file  
**Solution**: This is intentional for debugging; safe to ignore

## Summary

Audit folders provide:
- ✅ **Complete Test History**: Every run is preserved
- ✅ **Failure Diagnosis**: All intermediate files available
- ✅ **Regression Tracking**: Compare runs over time
- ✅ **Pipeline Visibility**: See every transformation step
- ✅ **CI/CD Integration**: Easy artifact upload/download

**Key Takeaway**: When a test fails, the audit folder contains everything you need to diagnose the issue without re-running the test.

