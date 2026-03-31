# Regression Test Flow - Changes Summary

## Date: 2025-12-01

## Overview
Updated the regression test system to properly separate baseline creation from regression testing, with all test artifacts stored in timestamped audit folders.

---

## Changes Made

### 1. C# Test Applications - Accept Export Directory Parameter

#### **File: `TestSuite/ComprehensiveTest/Program.cs`**
- **Change**: Added command-line argument support for export directory
- **Details**: 
  - Accepts optional export folder path as `args[0]`
  - Falls back to timestamped folder in current directory if not provided
  - Allows PowerShell script to control where test outputs are generated

#### **File: `TestSuite/TestMmdDiff/Program.cs`**
- **Change**: Added command-line argument support for export directory
- **Details**: Same as ComprehensiveTest above

---

### 2. PowerShell Regression Test Script - Two-Mode Operation

#### **File: `TestSuite/Scripts/Run-RegressionTests.ps1`**

### Mode 1: **With `-ResetBaseline` Switch** (Baseline Creation)

**Purpose**: Establish the "golden" reference files that define correct output

**Flow**:
1. ✅ Read input files from `@BaselineInput` folder:
   - `test.sql`
   - `testBeforeChange.mmd`
   - `testAfterChange.mmd`

2. ✅ Run C# test executables **without** export directory parameter
   - Creates timestamped export folders in project root
   - Examples: `FullCircle_Export_20251201_123456`, `MmdDiffTest_Export_20251201_123456`

3. ✅ Extract key output files and **copy to `@Baseline` folder**:
   - `FullCircle_roundtrip.mmd`
   - `FullCircle_AnsiSql_roundtrip_AnsiSql.sql`
   - `FullCircle_SqlServer_roundtrip_SqlServer.sql`
   - `FullCircle_PostgreSql_roundtrip_PostgreSql.sql`
   - `FullCircle_MySql_roundtrip_MySql.sql`
   - `MermaidDiff_Direction1_AnsiSql.sql` (and other dialects)
   - `MermaidDiff_Direction2_AnsiSql.sql` (and other dialects)

4. ✅ Copy input files to `@BaselineInput` folder (for hash verification)

5. ✅ **Clean up** temporary timestamped export folders

6. ✅ Generate report showing baseline files created

---

### Mode 2: **Without `-ResetBaseline`** (Regression Testing)

**Purpose**: Verify that current code produces the same outputs as the baseline

**Flow**:
1. ✅ Read input files from `@BaselineInput` folder (same files used for baseline)

2. ✅ Verify input file hashes match baseline (ensures inputs haven't changed)

3. ✅ Create timestamped audit folder: `@Audit\<YYYYMMDD_HHMMSS>`

4. ✅ Run ComprehensiveTest **with export directory parameter**:
   - Pass `@Audit\<timestamp>\FullCircle_Export` as argument
   - Test outputs are created **directly in audit folder**

5. ✅ Compare outputs in audit folder with baseline files:
   - Read: `@Audit\<timestamp>\FullCircle_Export\roundtrip.mmd`
   - Compare with: `@Baseline\FullCircle_roundtrip.mmd`
   - If match → ✅ PASS
   - If differ → ❌ FAIL, save diff to `@Audit\<timestamp>\DIFF_FullCircle_roundtrip.mmd.txt`

6. ✅ Run TestMmdDiff **with export directory parameter**:
   - Pass `@Audit\<timestamp>\MmdDiffTest_Export` as argument
   - Test outputs are created **directly in audit folder**

7. ✅ Compare outputs in audit folder with baseline files (same logic as step 5)

8. ✅ **Keep all files** in audit folder (no cleanup)
   - Audit folder contains:
     - All generated outputs
     - All intermediate files (AST, SQLGlot I/O)
     - DIFF files for failed comparisons
     - Test report

9. ✅ Generate comprehensive report in audit folder

10. ✅ Copy report to `@Reports` folder for easy access

---

## Key Benefits

### ✅ **Clear Separation**
- Baseline files (`@Baseline`) define the "truth"
- Test outputs (`@Audit\<timestamp>`) are isolated per run
- No mixing of reference and test data

### ✅ **Full Traceability**
- Every test run creates a timestamped audit folder
- All intermediate files preserved for debugging
- Easy to compare "what changed" between runs

### ✅ **Reproducibility**
- Input files stored in `@BaselineInput` with hash verification
- Ensures tests use same inputs as when baseline was created
- Warns if input files have been modified

### ✅ **Developer-Friendly**
- Audit folders kept indefinitely (added to `.gitignore`)
- Easy to open and inspect all intermediate files
- Diffs saved for quick identification of regressions

---

## Folder Structure

```
TestSuite/
├── RegressionTest/
│   ├── Baseline/                           # ← Golden reference files
│   │   ├── FullCircle_roundtrip.mmd
│   │   ├── FullCircle_AnsiSql_roundtrip_AnsiSql.sql
│   │   ├── MermaidDiff_Direction1_AnsiSql.sql
│   │   └── ... (13 baseline files total)
│   │
│   ├── BaselineInput/                      # ← Input files used for tests
│   │   ├── test.sql
│   │   ├── testBeforeChange.mmd
│   │   └── testAfterChange.mmd
│   │
│   ├── Audit/                              # ← Test run artifacts (gitignored)
│   │   ├── 20251201_143022/                # ← Timestamped folder per run
│   │   │   ├── FullCircle_Export/          # ← All ComprehensiveTest outputs
│   │   │   │   ├── roundtrip.mmd
│   │   │   │   ├── AnsiSql/
│   │   │   │   │   ├── roundtrip_AnsiSql.sql
│   │   │   │   │   └── ... (AST files, etc.)
│   │   │   │   └── ...
│   │   │   ├── MmdDiffTest_Export/         # ← All TestMmdDiff outputs
│   │   │   │   ├── Forward_Before-To-After/
│   │   │   │   └── Reverse_After-To-Before/
│   │   │   ├── DIFF_*.txt                  # ← Diff files for failures
│   │   │   └── REGRESSION_TEST_REPORT.md   # ← Main report
│   │   └── 20251201_150033/                # ← Next run
│   │       └── ...
│   │
│   └── Reports/                            # ← Copy of reports for easy access
│       ├── REGRESSION_TEST_20251201_143022.md
│       └── REGRESSION_TEST_20251201_150033.md
```

---

## Usage

### First Time Setup (Create Baseline):
```powershell
pwsh -ExecutionPolicy Bypass -File "TestSuite\Scripts\Run-RegressionTests.ps1" -ResetBaseline
```

**Result**: Creates baseline files in `@Baseline` folder

---

### Normal Regression Testing:
```powershell
pwsh -ExecutionPolicy Bypass -File "TestSuite\Scripts\Run-RegressionTests.ps1"
```

**Result**: 
- Outputs generated in `@Audit\<timestamp>` folder
- Compared with baseline files
- Report shows pass/fail for each test
- All artifacts preserved for inspection

---

## Verification Checklist

Before running the test, verify:

- [ ] Input files exist in `TestSuite/RegressionTest/BaselineInput/`
  - [ ] `test.sql`
  - [ ] `testBeforeChange.mmd`
  - [ ] `testAfterChange.mmd`

- [ ] Baseline files exist in `TestSuite/RegressionTest/Baseline/`
  - [ ] 13 baseline files (5 FullCircle + 8 MermaidDiff)
  - [ ] `baseline-mapping.json`

- [ ] `.gitignore` includes `TestSuite/RegressionTest/Audit/`

- [ ] C# test applications build successfully
  - [ ] `ComprehensiveTest.exe`
  - [ ] `TestMmdDiff.exe`

- [ ] Main project builds successfully
  - [ ] `SqlMermaidErdTools.dll` with RuntimeManager

---

## Expected Behavior

### ✅ With `-ResetBaseline`:
- Exit code: `1` (baseline created, not a true test)
- Report shows "⚠️ Baseline Files Created"
- Temporary export folders cleaned up
- Baseline files updated in `@Baseline` folder

### ✅ Without `-ResetBaseline` (All Tests Pass):
- Exit code: `0`
- Report shows "✅ All Tests Passed!"
- Audit folder preserved with all artifacts
- No diff files generated

### ❌ Without `-ResetBaseline` (Test Failures):
- Exit code: `1`
- Report shows "⚠️ Regressions Detected!"
- Audit folder preserved with all artifacts
- `DIFF_*.txt` files created for each failure
- Detailed diffs show baseline vs current output

---

## Testing the Changes

1. **Verify baseline mode works**:
   ```powershell
   pwsh -ExecutionPolicy Bypass -File "TestSuite\Scripts\Run-RegressionTests.ps1" -ResetBaseline
   ```
   - Check that baseline files are created/updated
   - Check that temporary folders are cleaned up
   - Check that audit folder contains report

2. **Verify regression mode works**:
   ```powershell
   pwsh -ExecutionPolicy Bypass -File "TestSuite\Scripts\Run-RegressionTests.ps1"
   ```
   - Check that audit folder is created with timestamp
   - Check that outputs are generated in audit folder (not project root)
   - Check that comparison with baseline works
   - Check that all files are preserved in audit folder

3. **Introduce intentional failure**:
   - Modify a baseline file slightly
   - Run regression test
   - Verify that failure is detected
   - Verify that diff file is created
   - Restore baseline file

---

## Conclusion

The regression test system now properly separates:
- **Baseline creation** (with `-ResetBaseline`)
- **Regression testing** (without `-ResetBaseline`)

All test artifacts are preserved in timestamped audit folders for full traceability and debugging.

