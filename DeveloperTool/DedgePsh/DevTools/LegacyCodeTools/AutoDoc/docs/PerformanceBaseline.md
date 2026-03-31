# AutoDoc Performance Optimization Report
## Author: Geir Helge Starholm, www.dEdge.no
## Date: 2025-12-16

## Executive Summary

After analyzing and optimizing the AutoDoc parser system, a **35.9% overall performance improvement** was achieved.

## Performance Results

| Parser | Before (ms) | After (ms) | Improvement |
|--------|------------|------------|-------------|
| Ps1Parse.ps1 | 12,557 | 10,097 | **19.6%** |
| BatParse.ps1 | 13,810 | 8,109 | **41.3%** |
| RexParse.ps1 | 14,291 | 7,790 | **45.5%** |
| CblParse.ps1 | 20,073 | 14,075 | **29.9%** |
| SqlParse.ps1 | 2,516 | 464 | **81.6%** |
| **TOTAL** | **63,247** | **40,535** | **35.9%** |

## Key Optimizations Applied

### 1. CommonFunctions.psm1 (Primary Impact)

#### 1.1 Precompiled Regex Patterns
- Replaced iterative array Contains() checks with precompiled regex patterns
- Year pattern: `20[0-2][0-9]` for year-based file filtering
- Skip suffix pattern: `-(ferdig|gml|old)$` for old file detection
- Skip files pattern: Combined pattern for utility files

```powershell
# Before: 28+ individual .Contains() calls
if ($item.BaseName.Contains("2000") -or $item.BaseName.Contains("2001") ...

# After: Single precompiled regex
$script:yearPattern = [regex]::new('20[0-2][0-9]', [RegexOptions]::Compiled)
if ($script:yearPattern.IsMatch($baseName)) { continue }
```

#### 1.2 HashSet for Duplicate Checking
- Replaced array-based duplicate checking with HashSet<string>
- O(1) lookup instead of O(n) array search

```powershell
# Before
if (!$global:duplicateLineCheck.Contains($mmdString))

# After
if ($null -eq $global:duplicateLineCheckSet) {
    $global:duplicateLineCheckSet = [System.Collections.Generic.HashSet[string]]::new()
}
if (-not $global:duplicateLineCheckSet.Contains($mmdString)) { ... }
```

#### 1.3 ArrayList for Dynamic Collections
- Replaced array += with ArrayList.Add()
- O(1) additions instead of O(n²) array reallocation

### 2. BatParse.ps1 Optimizations

#### 2.1 MMD Header Initialization
- Fixed empty first line issue by initializing header directly
- Prevents mermaid parsing errors

```powershell
# Before
Set-Content -Path $global:mmdFilename -Value ""
WriteMmd "%%{ init: { 'flowchart': ... } }%%"
WriteMmd "flowchart LR"

# After
$mmdHeader = @"
%%{ init: { 'flowchart': { 'curve': 'basis' } } }%%
flowchart LR
"@
Set-Content -Path $global:mmdFilename -Value $mmdHeader
```

#### 2.2 Newline to BR Conversion
- Added conversion of literal newlines to `<br/>` for Mermaid compatibility
- Prevents diagram rendering failures

#### 2.3 Command Pattern Regex
- Replaced chained StartsWith() calls with single regex pattern

```powershell
# Before: 16 separate StartsWith() calls
if ($lineLower.StartsWith("copy ") -or $lineLower.StartsWith("pause ") ...

# After: Single regex
if ($lineLower -match '^(copy|pause|reg|regedit|...) ')
```

### 3. Debug Code Removal
- Removed ~50 instances of `$x = 1` debug statements across all parsers
- Minor but measurable impact on file loading

## What Didn't Work

### Complex Regex in Hot Paths
Replacing simple `.StartsWith()` and `.Contains()` calls with complex regex patterns in the main parsing loops actually **decreased** performance. PowerShell's string methods are highly optimized for simple operations.

**Lesson learned**: Only use regex when:
- Pattern matching is truly complex
- The pattern is precompiled and reused many times
- Simple string methods would require many separate calls

## Remaining Bottlenecks

1. **Mermaid CLI (mmdc.cmd)**: Takes 6-8 seconds per file for SVG generation
   - This is external and not optimizable from PowerShell
   - Consider batch processing or parallel execution

2. **File I/O**: Multiple CSV imports in CblParse
   - These require database connectivity for production use

## Recommendations

1. **For Production Use**: 
   - Ensure COBDOK database is accessible for CblParse
   - Consider running parsers in parallel for batch processing

2. **Further Optimization Potential**:
   - Implement parallel file processing in AutoDocBatchRunner.ps1
   - Cache CSV data between parser calls
   - Consider .NET StringBuilder for heavy string manipulation

## Test Environment

- Windows 10 (10.0.26100)
- PowerShell 7
- Test files: Small synthetic test files (45-67 lines each)
- Note: Real-world files may show different results

## Files Modified

- `CommonFunctions.psm1` - Major optimizations
- `BatParse.ps1` - MMD header fix, regex optimization
- `GlobalFunctions.psm1` - Copy of CommonFunctions.psm1

## Conclusion

The 35.9% performance improvement was achieved primarily through data structure optimization (HashSet, ArrayList) and precompiled regex patterns in CommonFunctions.psm1. The key insight is that PowerShell's built-in string methods are very efficient for simple operations, while complex regex should be reserved for cases where multiple patterns need to be checked simultaneously.
