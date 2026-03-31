# AutoDoc Performance Analysis: In-Memory Optimization Strategy

**Author:** Geir Helge Starholm, www.dEdge.no  
**Created:** 2025-01-22  
**Technology:** PowerShell, Performance Optimization

---

## Executive Summary

Analysis of `AutoDocBatchRunner.ps1` and `AutoDocFunctions.psm1` reveals significant performance gains are achievable by loading all source files into memory (7GB available). The current implementation repeatedly reads files from disk and performs file system searches. An abstraction layer with a memory/file switch can enable in-memory operations with minimal code rewrites.

**Estimated Performance Gain:** 5-10x faster execution for large codebases

---

## Current Performance Bottlenecks

### 1. Repeated File I/O Operations

**Problem:** Files are read from disk multiple times during processing.

**Evidence:**
- `Get-Content` called 34+ times in `AutoDocFunctions.psm1`
- Same files read repeatedly for different search operations
- No caching mechanism between function calls

**Example Locations:**
```powershell
# AutoDocFunctions.psm1:2008
$fileContentOriginal = Get-Content $SourceFile -Encoding ([System.Text.Encoding]::GetEncoding(1252))

# AutoDocFunctions.psm1:3145-3146
$fileContentOriginalWithComments = Get-Content -Path $SourceFile
$fileContentOriginal = Get-Content -Path $SourceFile | Select-String "^*"

# AutoDocFunctions.psm1:4446
$fileContentOriginal = Get-Content $SourceFile -Encoding ([System.Text.Encoding]::GetEncoding(1252))
```

**Impact:** Each file read is ~1-5ms, multiplied by thousands of files and multiple reads = significant overhead.

---

### 2. File System Searches with Select-String

**Problem:** `Get-ChildItem` with `-Recurse` + `Select-String` scans the file system repeatedly.

**Evidence:**
```powershell
# AutoDocFunctions.psm1:263-265
$resultFiles = Get-ChildItem -Path $FindPath -Include $IncludeFilter -Recurse -ErrorAction SilentlyContinue | 
    Select-String $Pattern -ErrorAction SilentlyContinue | 
    Select-Object Path, Line, Filename, Extension, BaseName
```

**Impact:** 
- File system enumeration: ~10-50ms per directory
- Pattern matching on disk: ~5-20ms per file
- Repeated searches for same patterns across different functions

---

### 3. No Cross-Function Caching

**Problem:** Each function independently reads and searches files.

**Evidence:**
- `Find-AutodocUsages` reads files independently
- `Get-AutodocExecutionPath` reads files independently  
- `Start-CblParse`, `Start-Ps1Parse`, etc. all read source files independently
- No shared cache between parallel processing threads

**Impact:** Same files read 3-5 times during a single document generation.

---

### 4. Inefficient Array Searches

**Problem:** PowerShell array operations (`Where-Object`, `Select-String`) are slower than hashtable lookups.

**Evidence:**
```powershell
# AutoDocBatchRunner.ps1:341
$descArray = $csvModulArray | Where-Object { $_.modul.Contains($baseFileName) }

# AutoDocFunctions.psm1:1793
$descArray = $csvModulArray | Where-Object { $_.modul.Contains($item.Replace(".cbl", "").ToUpper()) }
```

**Impact:** O(n) linear searches instead of O(1) hashtable lookups.

---

## In-Memory Optimization Strategy

### Architecture Overview

```
┌─────────────────────────────────────────────────────────┐
│              AutoDocBatchRunner.ps1                      │
│  ┌──────────────────────────────────────────────────┐   │
│  │  Initialize-InMemoryCache (if enabled)           │   │
│  │  - Load all source files into hashtables        │   │
│  │  - Index by file path, content, and patterns     │   │
│  └──────────────────────────────────────────────────┘   │
└─────────────────────────────────────────────────────────┘
                        │
                        ▼
┌─────────────────────────────────────────────────────────┐
│         AutoDocFunctions.psm1                           │
│  ┌──────────────────────────────────────────────────┐   │
│  │  Abstracted File Access Layer                     │   │
│  │  - Get-FileContent (switch: memory vs disk)      │   │
│  │  - Search-FileContent (switch: array vs Select)  │   │
│  │  - Get-FileList (switch: cache vs Get-ChildItem)│   │
│  └──────────────────────────────────────────────────┘   │
└─────────────────────────────────────────────────────────┘
```

---

### Implementation Approach

#### Phase 1: Abstract File Access Layer

Create wrapper functions that can switch between memory and file access:

```powershell
# In AutoDocFunctions.psm1

# Module-level cache
$script:InMemoryFileCache = $null
$script:UseInMemoryCache = $false

function Initialize-InMemoryFileCache {
    <#
    .SYNOPSIS
        Loads all source files into memory for fast access.
    #>
    param(
        [string]$SrcRootFolder,
        [string[]]$IncludeFilters = @("*.cbl", "*.ps1", "*.rex", "*.bat", "*.cs", "*.sql")
    )
    
    Write-LogMessage "Loading source files into memory cache..." -Level INFO
    
    $script:InMemoryFileCache = @{
        FilesByPath = @{}           # [hashtable] FullPath -> FileContent (string[])
        FilesByPattern = @{}        # [hashtable] Pattern -> FileContent[]
        FileMetadata = @{}          # [hashtable] FullPath -> {LastWriteTime, Size, Encoding}
        SearchIndex = @{}           # [hashtable] LowercaseContent -> FilePath[]
    }
    
    $fileCount = 0
    $totalSize = 0
    
    foreach ($filter in $IncludeFilters) {
        $files = Get-ChildItem -Path $SrcRootFolder -Filter $filter -Recurse -File -ErrorAction SilentlyContinue |
            Where-Object { $_.DirectoryName -notmatch '\\(bin|obj|node_modules|\.git|_old)\\' }
        
        foreach ($file in $files) {
            try {
                # Read file content
                $encoding = [System.Text.Encoding]::UTF8
                if ($filter -eq "*.cbl" -or $filter -eq "*.bat") {
                    $encoding = [System.Text.Encoding]::GetEncoding(1252)
                }
                
                $content = [System.IO.File]::ReadAllLines($file.FullName, $encoding)
                
                # Store in cache
                $script:InMemoryFileCache.FilesByPath[$file.FullName] = $content
                $script:InMemoryFileCache.FileMetadata[$file.FullName] = @{
                    LastWriteTime = $file.LastWriteTime
                    Size = $file.Length
                    Encoding = $encoding
                }
                
                # Build search index (lowercase for case-insensitive searches)
                $contentLower = $content | ForEach-Object { $_.ToLower() }
                foreach ($line in $contentLower) {
                    if (-not $script:InMemoryFileCache.SearchIndex.ContainsKey($line)) {
                        $script:InMemoryFileCache.SearchIndex[$line] = @()
                    }
                    if ($script:InMemoryFileCache.SearchIndex[$line] -notcontains $file.FullName) {
                        $script:InMemoryFileCache.SearchIndex[$line] += $file.FullName
                    }
                }
                
                $fileCount++
                $totalSize += $file.Length
            }
            catch {
                Write-LogMessage "Error loading file into cache: $($file.FullName) - $_" -Level WARN
            }
        }
    }
    
    $script:UseInMemoryCache = $true
    Write-LogMessage "Loaded $fileCount files ($([math]::Round($totalSize/1MB, 2)) MB) into memory cache" -Level INFO
}

function Get-FileContent {
    <#
    .SYNOPSIS
        Gets file content from memory cache or disk.
    #>
    param(
        [Parameter(Mandatory = $true)]
        [string]$FilePath,
        [System.Text.Encoding]$Encoding = $null
    )
    
    if ($script:UseInMemoryCache -and $script:InMemoryFileCache.FilesByPath.ContainsKey($FilePath)) {
        # Return from cache
        return $script:InMemoryFileCache.FilesByPath[$FilePath]
    }
    else {
        # Fallback to disk read
        if ($null -eq $Encoding) {
            $Encoding = [System.Text.Encoding]::UTF8
        }
        return [System.IO.File]::ReadAllLines($FilePath, $Encoding)
    }
}

function Search-FileContent {
    <#
    .SYNOPSIS
        Searches file content in memory or on disk.
    #>
    param(
        [Parameter(Mandatory = $true)]
        [string]$Pattern,
        [string]$FindPath,
        [string[]]$IncludeFilters,
        [switch]$CaseSensitive
    )
    
    if ($script:UseInMemoryCache) {
        # In-memory search using hashtable index
        $results = @()
        $patternLower = if (-not $CaseSensitive) { $Pattern.ToLower() } else { $Pattern }
        
        # Search through indexed content
        foreach ($filePath in $script:InMemoryFileCache.FilesByPath.Keys) {
            # Filter by path and include filters
            if ($filePath -notlike "*$FindPath*") { continue }
            
            $matched = $false
            foreach ($filter in $IncludeFilters) {
                if ($filePath -like "*$filter") {
                    $matched = $true
                    break
                }
            }
            if (-not $matched) { continue }
            
            # Search content
            $content = $script:InMemoryFileCache.FilesByPath[$filePath]
            for ($i = 0; $i -lt $content.Length; $i++) {
                $line = if ($CaseSensitive) { $content[$i] } else { $content[$i].ToLower() }
                if ($line -match [regex]::Escape($patternLower)) {
                    $results += [PSCustomObject]@{
                        Path = $filePath
                        LineNumber = $i + 1
                        Line = $content[$i]
                        Filename = [System.IO.Path]::GetFileName($filePath)
                        Extension = [System.IO.Path]::GetExtension($filePath)
                        BaseName = [System.IO.Path]::GetFileNameWithoutExtension($filePath)
                    }
                }
            }
        }
        
        return $results
    }
    else {
        # Fallback to disk-based search
        $resultFiles = Get-ChildItem -Path $FindPath -Include $IncludeFilters -Recurse -ErrorAction SilentlyContinue | 
            Select-String $Pattern -ErrorAction SilentlyContinue | 
            Select-Object Path, Line, Filename, Extension, BaseName
        
        return $resultFiles
    }
}
```

---

#### Phase 2: Update Existing Functions

Replace direct `Get-Content` calls with abstracted functions:

**Before:**
```powershell
$fileContentOriginal = Get-Content $SourceFile -Encoding ([System.Text.Encoding]::GetEncoding(1252))
```

**After:**
```powershell
$encoding = [System.Text.Encoding]::GetEncoding(1252)
$fileContentOriginal = Get-FileContent -FilePath $SourceFile -Encoding $encoding
```

**Before:**
```powershell
$resultFiles = Get-ChildItem -Path $FindPath -Include $IncludeFilter -Recurse -ErrorAction SilentlyContinue | 
    Select-String $Pattern -ErrorAction SilentlyContinue
```

**After:**
```powershell
$resultFiles = Search-FileContent -Pattern $Pattern -FindPath $FindPath -IncludeFilters @($IncludeFilter)
```

---

#### Phase 3: Memory Estimation and Validation

**Memory Requirements Calculation:**

```powershell
function Estimate-MemoryRequirements {
    param([string]$SrcRootFolder)
    
    $fileTypes = @("*.cbl", "*.ps1", "*.rex", "*.bat", "*.cs", "*.sql")
    $totalSize = 0
    $fileCount = 0
    
    foreach ($filter in $fileTypes) {
        $files = Get-ChildItem -Path $SrcRootFolder -Filter $filter -Recurse -File -ErrorAction SilentlyContinue |
            Where-Object { $_.DirectoryName -notmatch '\\(bin|obj|node_modules|\.git|_old)\\' }
        
        foreach ($file in $files) {
            $totalSize += $file.Length
            $fileCount++
        }
    }
    
    # Estimate: file content + overhead (PowerShell arrays ~2x, hashtables ~1.5x)
    $estimatedMemory = $totalSize * 3.5
    
    Write-LogMessage "Estimated memory usage: $([math]::Round($estimatedMemory/1MB, 2)) MB for $fileCount files" -Level INFO
    
    return @{
        FileCount = $fileCount
        TotalSize = $totalSize
        EstimatedMemoryMB = [math]::Round($estimatedMemory/1MB, 2)
    }
}
```

**Validation:**
- Check available memory before loading
- Warn if estimated memory > 6GB (leave 1GB buffer)
- Provide fallback to disk mode if insufficient memory

---

### Code Changes Required

#### Minimal Changes (Abstraction Layer Only)

**Files to Modify:**
1. `AutoDocFunctions.psm1` - Add abstraction functions (3 new functions, ~200 lines)
2. `AutoDocBatchRunner.ps1` - Initialize cache at startup (1 function call, ~5 lines)

**Functions Requiring Updates:**
- `Find-AutodocUsages` - Replace `Get-ChildItem` + `Select-String` with `Search-FileContent`
- `Start-CblParse` - Replace `Get-Content` with `Get-FileContent`
- `Start-Ps1Parse` - Replace `Get-Content` with `Get-FileContent`
- `Start-RexParse` - Replace `Get-Content` with `Get-FileContent`
- `Start-BatParse` - Replace `Get-Content` with `Get-FileContent`
- `Find-ExternalApiCallers` - Replace `Get-Content` with `Get-FileContent`

**Estimated Lines Changed:** ~50-100 lines (mostly find/replace operations)

---

#### Switch Mechanism

Add parameter to `AutoDocBatchRunner.ps1`:

```powershell
param(
    # ... existing parameters ...
    
    # Enable in-memory file cache for faster processing (requires 5-7GB RAM)
    [bool]$UseInMemoryCache = $false
)
```

In main execution:

```powershell
if ($UseInMemoryCache) {
    $memEstimate = Estimate-MemoryRequirements -SrcRootFolder $workFolder
    if ($memEstimate.EstimatedMemoryMB -lt 6000) {
        Initialize-InMemoryFileCache -SrcRootFolder $workFolder
    }
    else {
        Write-LogMessage "Estimated memory ($($memEstimate.EstimatedMemoryMB) MB) exceeds safe limit. Using disk mode." -Level WARN
        $UseInMemoryCache = $false
    }
}
```

---

### Performance Gains Expected

#### File I/O Elimination

**Current:**
- 10,000 files × 3 reads each = 30,000 disk operations
- Average: 2ms per read = 60 seconds total

**With In-Memory:**
- 10,000 files × 1 load = 10,000 disk operations (one-time)
- Average: 2ms per read = 20 seconds initial load
- Subsequent reads: 0ms (memory access) = **~40 seconds saved**

---

#### Search Performance

**Current:**
- `Get-ChildItem -Recurse`: ~50ms per directory
- `Select-String` on disk: ~10ms per file
- 100 searches × 1000 files = 100,000 operations = **~1000 seconds**

**With In-Memory:**
- Array iteration: ~0.1ms per file
- Hashtable lookup: ~0.001ms per search
- 100 searches × 1000 files = 100,000 operations = **~10 seconds**

**Gain: ~100x faster searches**

---

#### Overall Expected Improvement

For a typical run processing 5,000 files:

| Operation | Current Time | In-Memory Time | Improvement |
|-----------|--------------|----------------|-------------|
| File Loading | 60s | 20s (one-time) | 3x faster |
| File Searches | 1000s | 10s | 100x faster |
| Content Access | 40s | <1s | 40x faster |
| **Total** | **~1100s** | **~31s** | **~35x faster** |

**Realistic expectation: 5-10x overall improvement** (accounting for other bottlenecks)

---

### Implementation Risks and Mitigations

#### Risk 1: Memory Exhaustion

**Mitigation:**
- Pre-flight memory check
- Graceful fallback to disk mode
- Progress monitoring during cache load
- Option to clear cache mid-run if needed

#### Risk 2: Stale Data

**Mitigation:**
- Cache includes `LastWriteTime` metadata
- Compare cache timestamps with file system on access
- Option to force cache refresh
- Cache invalidation on file changes

#### Risk 3: Parallel Processing Conflicts

**Mitigation:**
- Cache is read-only after initialization
- Thread-safe hashtable access (PowerShell handles this)
- Each parallel thread uses same cache (shared memory)
- No write operations to cache during processing

#### Risk 4: Encoding Issues

**Mitigation:**
- Preserve original encoding per file
- Store encoding metadata in cache
- Fallback to UTF8 if encoding detection fails

---

### Testing Strategy

#### Phase 1: Unit Tests
- Test `Get-FileContent` with memory and disk modes
- Test `Search-FileContent` with various patterns
- Verify cache initialization and memory usage

#### Phase 2: Integration Tests
- Run on small subset (100 files) with both modes
- Compare output HTML files (should be identical)
- Measure performance difference

#### Phase 3: Production Test
- Run on full codebase with memory mode enabled
- Monitor memory usage (should stay < 7GB)
- Verify no functional regressions

---

### Rollout Plan

1. **Week 1:** Implement abstraction layer (backward compatible)
2. **Week 2:** Update 5-10 key functions to use abstraction
3. **Week 3:** Test with small codebase subset
4. **Week 4:** Full rollout with `-UseInMemoryCache:$false` by default
5. **Week 5:** Enable by default after validation

---

### Code Abstraction Example

**Minimal rewrite required - just wrapper functions:**

```powershell
# OLD CODE (still works if abstraction not used)
$content = Get-Content $file -Raw

# NEW CODE (with abstraction - same interface)
$content = Get-FileContent -FilePath $file -AsString

# The abstraction function handles the switch internally:
function Get-FileContent {
    param([string]$FilePath, [switch]$AsString)
    
    if ($script:UseInMemoryCache) {
        $lines = $script:InMemoryFileCache.FilesByPath[$FilePath]
        return if ($AsString) { $lines -join "`n" } else { $lines }
    }
    else {
        return if ($AsString) { Get-Content $FilePath -Raw } else { Get-Content $FilePath }
    }
}
```

**No changes needed to calling code** - just replace `Get-Content` with `Get-FileContent`.

---

## Conclusion

Loading all source files into memory (7GB available) can provide **5-10x performance improvement** with **minimal code changes** through an abstraction layer. The implementation is low-risk with graceful fallbacks and can be enabled via a simple switch parameter.

**Recommendation:** Proceed with implementation using the abstraction layer approach to minimize code rewrites while maximizing performance gains.

---

## Appendix: Quick Wins (No Memory Mode Required)

These optimizations can be implemented immediately without the in-memory cache:

1. **Cache CSV module array in hashtable:**
   ```powershell
   # Instead of: $csvModulArray | Where-Object { $_.modul.Contains($baseFileName) }
   # Use: $moduleIndex[$baseFileName] (O(1) vs O(n))
   ```

2. **Pre-compile regex patterns:**
   ```powershell
   # Already done for some patterns, but can be extended
   $script:skipFilesPattern = [regex]::new($pattern, [System.Text.RegularExpressions.RegexOptions]::Compiled)
   ```

3. **Use HashSet for duplicate checking:**
   ```powershell
   # Already implemented in some places, but can be extended
   $searchSet = [System.Collections.Generic.HashSet[string]]::new()
   ```

4. **Batch file reads:**
   ```powershell
   # Read file once, reuse content instead of multiple Get-Content calls
   ```

These quick wins alone could provide 2-3x improvement without the memory mode.
