# AutoDoc Parallel Processing Design

**Author:** Geir Helge Starholm, www.dEdge.no  
**Date:** 2026-01-19  
**Status:** Feasibility Analysis

---

## Executive Summary

Parallelizing `AutoDocBatchRunner.ps1` is **highly feasible** and could provide **3-6x speedup** on typical multi-core systems. The current architecture processes files independently, making it an ideal candidate for parallel execution.

### Quick Stats

| Metric | Current | With Parallelization |
|--------|---------|---------------------|
| Processing model | Sequential (1 thread) | Parallel (75% of cores) |
| Est. time for 3500 CBL files | ~3.5 hours | ~35-70 minutes |
| CPU utilization | ~12% (1 of 8 cores) | ~75% |

---

## Current Architecture Analysis

### Processing Flow

```
┌──────────────────────────────────────────────────────────────┐
│ Phase 1: SETUP (Sequential - Must remain sequential)         │
├──────────────────────────────────────────────────────────────┤
│ • Copy scheduled task files                                  │
│ • Clone/update Git repositories                              │
│ • Export COBDOK database tables                              │
│ • Create folders, load CSV metadata                          │
└──────────────────────────────────────────────────────────────┘
                              ▼
┌──────────────────────────────────────────────────────────────┐
│ Phase 2: FILE PARSING (Parallelizable!)                      │
├──────────────────────────────────────────────────────────────┤
│ HandleCblFiles()    → 3,583 files × ~3 sec = ~3 hours        │
│ HandleScriptFiles() → ~2,246 files (REX + BAT + PS1)         │
│ HandleSqlTables()   → 2,915 tables × ~1 sec = ~48 min        │
└──────────────────────────────────────────────────────────────┘
                              ▼
┌──────────────────────────────────────────────────────────────┐
│ Phase 3: AGGREGATION (Sequential - Must remain sequential)   │
├──────────────────────────────────────────────────────────────┤
│ • Generate JSON index files                                  │
│ • Copy to web folder                                         │
│ • Create ZIP archive                                         │
│ • Send completion SMS                                        │
└──────────────────────────────────────────────────────────────┘
```

### Why Parallelization Works Here

| Factor | Analysis |
|--------|----------|
| **File Independence** | ✅ Each file is parsed independently - no dependencies between files |
| **Output Isolation** | ✅ Each parser writes to unique output file (e.g., `AAADATO.CBL.html`) |
| **Read-Only Inputs** | ✅ Source files and COBDOK CSVs are read-only during parsing |
| **Stateless Parsers** | ✅ Parser functions don't share state between invocations |

---

## Implementation Approach

### Option 1: ForEach-Object -Parallel (PowerShell 7+) ⭐ Recommended

```powershell
# Calculate thread count (75% of logical processors)
$totalCores = [Environment]::ProcessorCount
$parallelThreads = [Math]::Max(2, [Math]::Floor($totalCores * 0.75))

Write-LogMessage "Using $parallelThreads parallel threads (75% of $totalCores cores)" -Level INFO

# Parallel processing example
$filesToProcess | ForEach-Object -Parallel {
    # Import modules in each runspace
    Import-Module AutodocFunctions -Force
    Import-Module GlobalFunctions -Force
    
    $params = @{
        sourceFile    = $_.FullName
        show          = $false
        outputFolder  = $using:outputFolder
        cleanUp       = $true
        tmpRootFolder = $using:tmpFolder
        srcRootFolder = $using:srcRootFolder
        ClientSideRender = $using:ClientSideRender
    }
    
    Start-CblParse @params
} -ThrottleLimit $parallelThreads
```

**Pros:**
- Native PowerShell 7 feature
- Simple syntax
- Automatic thread management
- Built-in throttling

**Cons:**
- Each runspace needs to import modules (small overhead)
- Variables need `$using:` prefix
- Error handling requires special attention

### Option 2: Runspace Pools (More Control)

```powershell
$runspacePool = [runspacefactory]::CreateRunspacePool(1, $parallelThreads)
$runspacePool.Open()

$jobs = foreach ($file in $filesToProcess) {
    $powershell = [powershell]::Create()
    $powershell.RunspacePool = $runspacePool
    
    [void]$powershell.AddScript({
        param($sourceFile, $outputFolder, $tmpFolder, $srcRootFolder, $ClientSideRender)
        Import-Module AutodocFunctions -Force
        Start-CblParse -SourceFile $sourceFile -OutputFolder $outputFolder ...
    }).AddParameters(@{
        sourceFile = $file.FullName
        outputFolder = $outputFolder
        # ... other params
    })
    
    @{
        Powershell = $powershell
        Handle = $powershell.BeginInvoke()
        File = $file.Name
    }
}

# Wait and collect results
$jobs | ForEach-Object {
    $_.Powershell.EndInvoke($_.Handle)
    $_.Powershell.Dispose()
}
$runspacePool.Close()
```

**Pros:**
- Maximum control over execution
- Better for complex scenarios
- Reusable runspaces

**Cons:**
- More complex code
- Manual resource management

---

## Challenges and Solutions

### Challenge 1: Temp Folder Collisions

**Problem:** Multiple parsers may create files in `$tmpRootFolder` with conflicting names.

**Solution:** Create unique temp folders per file:
```powershell
$uniqueTmpFolder = Join-Path $tmpFolder ([Guid]::NewGuid().ToString("N"))
New-Item -ItemType Directory -Path $uniqueTmpFolder -Force | Out-Null
# ... parse ...
Remove-Item $uniqueTmpFolder -Recurse -Force
```

### Challenge 2: Logging Thread Safety

**Problem:** `Write-LogMessage` may have concurrent write issues.

**Solution:** Use thread-safe logging:
```powershell
# Option A: Queue-based logging
$logQueue = [System.Collections.Concurrent.ConcurrentQueue[string]]::new()

# In parallel block:
$logQueue.Enqueue("[INFO] Processing $fileName")

# After parallel block:
while ($logQueue.TryDequeue([ref]$msg)) {
    Write-LogMessage $msg -Level INFO
}
```

```powershell
# Option B: File-based with mutex
$mutex = [System.Threading.Mutex]::new($false, "AutoDocLogMutex")
try {
    $mutex.WaitOne() | Out-Null
    Write-LogMessage $message -Level INFO
} finally {
    $mutex.ReleaseMutex()
}
```

### Challenge 3: Progress Reporting

**Problem:** Can't easily track progress across parallel jobs.

**Solution:** Use thread-safe counter:
```powershell
$counter = [System.Threading.Interlocked]
$processedCount = [ref]0
$totalCount = $filesToProcess.Count

$filesToProcess | ForEach-Object -Parallel {
    # ... process file ...
    
    $current = [System.Threading.Interlocked]::Increment($using:processedCount)
    if ($current % 100 -eq 0) {
        Write-Host "Progress: $current / $($using:totalCount)"
    }
} -ThrottleLimit $parallelThreads
```

### Challenge 4: Error Isolation

**Problem:** One file's error shouldn't crash the entire batch.

**Solution:** Wrap each file in try/catch:
```powershell
$filesToProcess | ForEach-Object -Parallel {
    try {
        Start-CblParse @params
    }
    catch {
        # Create .err file for this specific file
        $errFile = Join-Path $using:outputFolder "$($_.Name).err"
        $_.Exception.Message | Set-Content $errFile
    }
} -ThrottleLimit $parallelThreads
```

---

## Pre-Export Common Data

Before parallel processing, export shared data once:

```powershell
function Export-CommonParseData {
    param(
        [string]$CobdokFolder,
        [string]$ExportPath
    )
    
    # Export once, use everywhere
    $commonData = @{
        ModulCsv = Import-Csv "$CobdokFolder\modul.csv" -Header system,delsystem,modul,tekst,modultype,benytter_sql,benytter_ds,fra_dato,fra_kl,antall_linjer,lengde,filenavn -Delimiter ';'
        TablesCsv = Import-Csv "$CobdokFolder\tables.csv" -Header schemaName,tableName,comment,type,alter_time -Delimiter ';'
        ColumnsCsv = Import-Csv "$CobdokFolder\columns.csv" -Header tabschema,tabname,colname,colno,typeschema,typename,length,scale,remarks -Delimiter ';'
        CallCsv = Import-Csv "$CobdokFolder\call.csv" -ErrorAction SilentlyContinue
        CopyCsv = Import-Csv "$CobdokFolder\copy.csv" -ErrorAction SilentlyContinue
    }
    
    # Serialize to file for parallel workers
    $commonData | Export-Clixml -Path $ExportPath
    
    return $commonData
}

# In parallel block, each worker loads:
$commonData = Import-Clixml -Path $using:commonDataPath
```

---

## Proposed New Architecture

```
┌─────────────────────────────────────────────────────────────────┐
│ PHASE 1: SEQUENTIAL SETUP                                       │
│ • Detect cores: $cores = [Environment]::ProcessorCount          │
│ • Calculate threads: $threads = [Math]::Floor($cores * 0.75)    │
│ • Export common data: Export-CommonParseData                    │
│ • Clone repos, export COBDOK                                    │
└─────────────────────────────────────────────────────────────────┘
                               ▼
┌─────────────────────────────────────────────────────────────────┐
│ PHASE 2: COLLECT FILES TO PROCESS                               │
│ • Build list of all files needing regeneration                  │
│ • Filter using RegenerateAutoDoc check                          │
│ • Create unified work queue with file type tags                 │
└─────────────────────────────────────────────────────────────────┘
                               ▼
┌─────────────────────────────────────────────────────────────────┐
│ PHASE 3: PARALLEL PROCESSING                                    │
│ ┌─────────┐ ┌─────────┐ ┌─────────┐ ┌─────────┐ ┌─────────┐    │
│ │Thread 1 │ │Thread 2 │ │Thread 3 │ │Thread 4 │ │Thread 5 │    │
│ │ CBL     │ │ CBL     │ │ REX     │ │ PS1     │ │ SQL     │    │
│ └─────────┘ └─────────┘ └─────────┘ └─────────┘ └─────────┘    │
│           ▼           ▼           ▼           ▼           ▼     │
│                     Shared Output Folder                        │
└─────────────────────────────────────────────────────────────────┘
                               ▼
┌─────────────────────────────────────────────────────────────────┐
│ PHASE 4: SEQUENTIAL AGGREGATION                                 │
│ • Wait for all threads to complete                              │
│ • Generate JSON index files                                     │
│ • Copy to web folder, create ZIP                                │
│ • Report errors, send SMS                                       │
└─────────────────────────────────────────────────────────────────┘
```

---

## Implementation Roadmap

### Phase 1: Foundation (2-3 hours)
- [ ] Add `-Parallel` switch parameter to `AutoDocBatchRunner.ps1`
- [ ] Add core detection and thread calculation
- [ ] Create `Export-CommonParseData` function
- [ ] Modify temp folder handling for isolation

### Phase 2: Parallel Processing (3-4 hours)
- [ ] Refactor `HandleCblFiles` to use `ForEach-Object -Parallel`
- [ ] Refactor `HandleScriptFiles` to use `ForEach-Object -Parallel`
- [ ] Refactor `HandleSqlTables` to use `ForEach-Object -Parallel`
- [ ] Implement thread-safe logging

### Phase 3: Testing & Tuning (2-3 hours)
- [ ] Test with small batch (10 files each type)
- [ ] Test with full dataset
- [ ] Tune thread count for optimal performance
- [ ] Add error recovery and reporting

### Phase 4: Monitoring (1-2 hours)
- [ ] Add progress reporting
- [ ] Add performance metrics logging
- [ ] Add memory usage monitoring

---

## Expected Performance Gains

| System | Cores | Threads (75%) | Est. Speedup |
|--------|-------|---------------|--------------|
| Dev laptop | 8 | 6 | 4-5x |
| Build server | 16 | 12 | 8-10x |
| Production VM | 4 | 3 | 2-3x |

### Estimated Run Times

| Dataset | Current (1 thread) | Parallel (6 threads) |
|---------|-------------------|---------------------|
| 3,583 CBL files | ~3 hours | ~30-45 min |
| 2,246 Script files | ~1 hour | ~10-15 min |
| 2,915 SQL tables | ~48 min | ~8-12 min |
| **Total** | **~5 hours** | **~50-75 min** |

---

## Risks and Mitigations

| Risk | Probability | Impact | Mitigation |
|------|-------------|--------|------------|
| Memory exhaustion | Medium | High | Add memory check, reduce threads if needed |
| File locking conflicts | Low | Medium | Use unique temp folders |
| DB connection limits | Low | Medium | Pool ODBC connections |
| Logging corruption | Medium | Low | Use thread-safe logging |
| Incomplete runs | Low | High | Add checkpoint/resume capability |

---

## Recommendation

**Proceed with implementation** using `ForEach-Object -Parallel` approach:

1. It's the simplest and most maintainable solution
2. PowerShell 7 is already in use
3. The workload is perfectly suited for parallel processing
4. Expected 3-6x speedup with minimal code changes
5. Risk is low due to file processing independence

Start with a new `-Parallel` switch that can be toggled, allowing easy rollback to sequential processing if issues arise.

---

## Next Steps

1. Review this document and approve approach
2. Implement Phase 1 (Foundation)
3. Test with `-maxFilesPerType 10 -Parallel`
4. If successful, proceed with full implementation

