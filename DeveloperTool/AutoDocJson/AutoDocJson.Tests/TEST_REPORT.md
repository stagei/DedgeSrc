# AutoDoc C# vs PowerShell Test Report

**Generated:** 2026-02-05 14:06:37  
**Test Duration:** 00:01:24

## Executive Summary

| Metric | Value |
|--------|-------|
| Total Files Tested | 60 |
| Perfect Matches (≥98% similarity) | 0 |
| Show Stoppers | 0 |
| Overall Similarity | **0.00%** |
| **Status** | **✗ FAILED** - Similarity below 98% threshold |

## Detailed Breakdown by File Type

### CBL (COBOL Files)
- **Files Tested:** 10
- **Perfect Matches:** 0
- **Average Similarity:** 0.00%
- **Show Stoppers:** 0
- **PowerShell Avg Duration:** 00:00:02
- **C# Avg Duration:** 00:00:00

### REX (Rexx Files)
- **Files Tested:** 10
- **Perfect Matches:** 0
- **Average Similarity:** 0.00%
- **Show Stoppers:** 0
- **PowerShell Avg Duration:** 00:00:02
- **C# Avg Duration:** 00:00:00

### BAT (Batch Files)
- **Files Tested:** 10
- **Perfect Matches:** 0
- **Average Similarity:** 0.00%
- **Show Stoppers:** 0
- **PowerShell Avg Duration:** 00:00:01
- **C# Avg Duration:** 00:00:00

### PS1 (PowerShell Files)
- **Files Tested:** 10
- **Perfect Matches:** 0
- **Average Similarity:** 0.00%
- **Show Stoppers:** 0
- **PowerShell Avg Duration:** 00:00:00
- **C# Avg Duration:** 00:00:00

### SQL (SQL Tables)
- **Files Tested:** 10
- **Perfect Matches:** 0
- **Average Similarity:** 0.00%
- **Show Stoppers:** 0
- **PowerShell Avg Duration:** 00:00:02
- **C# Avg Duration:** 00:00:00

### CSharp (C# Solutions)
- **Files Tested:** 10
- **Perfect Matches:** 0
- **Average Similarity:** 0.00%
- **Show Stoppers:** 0
- **PowerShell Avg Duration:** 00:00:00
- **C# Avg Duration:** 00:00:00

## Issues Identified

### 1. PowerShell Parser Execution
- **Problem:** PowerShell parsers return `ExitCode=1` due to warnings about missing config files (`C:\opt\src\DedgeSrc\DedgeSystemTools\Folders\DedgeCommon\Configfiles\DatabasesV2.json`)
- **Impact:** Current error handling treats any non-zero exit code as failure, preventing HTML file path extraction
- **Observation:** HTML files may still be generated despite warnings, but paths are not captured

### 2. Comparison Execution
- **Problem:** 0% similarity indicates comparisons are not being performed
- **Root Cause:** `psHtmlPath` or `csHtmlPath` are likely null due to error handling
- **Evidence:** Status fields in report are empty, suggesting comparison logic never executed

### 3. Error Handling Logic
- **Current Behavior:** Code returns `null` immediately when `process.ExitCode != 0`
- **Required Behavior:** Should distinguish between:
  - **Warnings** (config file missing) - HTML may still be generated
  - **Actual Failures** (syntax errors, file not found) - HTML not generated
- **Solution Needed:** Extract HTML path from output even when ExitCode != 0, then verify file exists

## Test Infrastructure Status

### ✅ Working Components
- C# parsers successfully generate HTML files
- Test suite executes all file types sequentially
- Comparison report generation works
- Logging infrastructure functional

### ❌ Issues to Fix
- PowerShell parser error handling too strict
- HTML path extraction fails on warnings
- Comparison logic not executed due to null paths
- Need to handle warnings vs failures differently

## Recommendations

1. **Immediate Fix:** Modify `RunPowerShellParser` to:
   - Extract HTML path from output regardless of ExitCode
   - Check if HTML file exists as fallback
   - Only treat as failure if HTML file doesn't exist AND ExitCode != 0

2. **Error Classification:** Distinguish between:
   - Non-critical warnings (config files missing) - continue processing
   - Critical errors (file not found, syntax errors) - fail immediately

3. **Path Extraction:** Improve robustness:
   - Parse output for HTML paths even with warnings
   - Use fallback path construction if extraction fails
   - Verify file existence before returning path

## Next Steps

1. Fix PowerShell parser error handling in `ComparativeTester.cs`
2. Re-run full test suite
3. Verify HTML files are being compared
4. Achieve ≥98% similarity target
5. Send SMS notification upon success

---

**Report Location:** `C:\opt\src\DedgePsh\AutoDocNew\AutoDocNew.Tests\bin\Debug\net8.0\ComparisonReport.json`  
**Text Report:** `C:\opt\src\DedgePsh\AutoDocNew\AutoDocNew.Tests\bin\Debug\net8.0\ComparisonReport.txt`
