# PowerShell Parallel Processing: ForEach-Object -Parallel vs Start-Job

**Author:** Geir Helge Starholm, www.dEdge.no  
**Created:** 2026-01-27  
**PowerShell Version:** 7.x+

---

## Overview

PowerShell offers two primary approaches for parallel execution:

1. **`ForEach-Object -Parallel`** - Runspace-based threading (PowerShell 7+)
2. **`Start-Job`** - Process-based parallelism (PowerShell 5.1+)

This document explains the differences, when to use each, and provides practical examples.

---

## ForEach-Object -Parallel

### How It Works

`ForEach-Object -Parallel` uses **runspaces** - lightweight threads that run within the same PowerShell process. All parallel operations share the same process ID (PID).

### Syntax

```powershell
$items | ForEach-Object -Parallel {
    # Code runs in separate runspace (thread)
    $item = $_
    $parentValue = $using:someVariable  # Access parent scope variables
    
    # Process the item
    Write-Output "Processing: $item"
} -ThrottleLimit 10
```

### Characteristics

| Aspect | Description |
|--------|-------------|
| **Mechanism** | Runspaces (threads within same process) |
| **Process ID** | Same PID for all threads |
| **Memory** | Shared process memory, efficient |
| **Startup Time** | Fast (~milliseconds per thread) |
| **Module Import** | Must `Import-Module` in each runspace |
| **Variable Sharing** | Use `$using:variableName` to pass values |
| **Output** | Returns directly to pipeline |
| **PowerShell Version** | 7.0+ only |

### Example: Parallel File Processing

```powershell
$files = Get-ChildItem -Path "C:\Source" -Filter "*.txt"

$files | ForEach-Object -Parallel {
    $file = $_
    $outputFolder = $using:outputFolder
    
    # Process file
    $content = Get-Content $file.FullName
    $processed = $content -replace "old", "new"
    
    # Save result
    $outPath = Join-Path $outputFolder $file.Name
    Set-Content -Path $outPath -Value $processed
    
    Write-Output "Processed: $($file.Name)"
} -ThrottleLimit 8
```

### Global Variables in Parallel Runspaces

**Important:** Global variables from the parent scope do NOT propagate to parallel runspaces automatically. Even when importing modules, module-level globals may not initialize correctly.

**Problem:**
```powershell
# In parent scope
$global:ConfigPath = "C:\Config"

$items | ForEach-Object -Parallel {
    Import-Module MyModule
    # $global:ConfigPath is NULL here!
}
```

**Solution:**
```powershell
$items | ForEach-Object -Parallel {
    # Explicitly set globals BEFORE importing modules
    $global:ConfigPath = "C:\Config"
    
    Import-Module MyModule
    # Now it works
}
```

Or better, create an initialization function in your module:

```powershell
# In your module
function Initialize-ModuleForParallel {
    if (-not $global:ConfigPath) {
        $global:ConfigPath = "C:\Config"
    }
}

# In parallel block
$items | ForEach-Object -Parallel {
    Import-Module MyModule -Force
    Initialize-ModuleForParallel
}
```

---

## Start-Job

### How It Works

`Start-Job` creates **separate child processes** for each job. Each job runs in complete isolation with its own PID and memory space.

### Syntax

```powershell
# Start jobs
$jobs = foreach ($item in $items) {
    Start-Job -ScriptBlock {
        param($filePath, $outputFolder)
        
        # Process the file
        $content = Get-Content $filePath
        # ... processing ...
        
        return "Processed: $filePath"
    } -ArgumentList $item.FullName, $outputFolder
}

# Wait and collect results
$results = $jobs | Wait-Job | Receive-Job

# Clean up
$jobs | Remove-Job
```

### Characteristics

| Aspect | Description |
|--------|-------------|
| **Mechanism** | Separate child processes |
| **Process ID** | Different PID for each job |
| **Memory** | Independent (~50-100MB per job) |
| **Startup Time** | Slow (~1-2 seconds per job) |
| **Module Import** | Must import in each job |
| **Variable Sharing** | Pass via `-ArgumentList` parameter |
| **Output** | Retrieve with `Receive-Job` |
| **PowerShell Version** | 5.1+ |

### Example: Long-Running Tasks

```powershell
$servers = @("Server1", "Server2", "Server3")

# Start jobs for each server
$jobs = foreach ($server in $servers) {
    Start-Job -Name "Backup-$server" -ScriptBlock {
        param($serverName)
        
        # Long-running backup operation
        Invoke-Command -ComputerName $serverName -ScriptBlock {
            # Backup logic here
            Start-Sleep -Seconds 300  # Simulating long operation
        }
        
        return "Backup completed for $serverName"
    } -ArgumentList $server
}

# Monitor progress
while ($jobs | Where-Object { $_.State -eq 'Running' }) {
    $running = ($jobs | Where-Object { $_.State -eq 'Running' }).Count
    Write-Host "Jobs still running: $running"
    Start-Sleep -Seconds 10
}

# Collect results
$results = $jobs | Receive-Job
$jobs | Remove-Job
```

---

## Comparison Table

| Feature | ForEach-Object -Parallel | Start-Job |
|---------|--------------------------|-----------|
| **Speed** | ⚡ Much faster startup | 🐢 Slower (process creation) |
| **Memory** | 💾 Efficient (shared process) | 💾 Heavy (separate processes) |
| **Isolation** | Threads share process space | Complete process isolation |
| **Crash Impact** | One crash may affect others | Isolated - one crash doesn't affect others |
| **Debugging** | Harder (interleaved output) | Easier (separate processes) |
| **Best For** | Many small-medium tasks | Few long-running tasks |
| **PowerShell Version** | 7.0+ only | 5.1+ |
| **Credentials** | Same as parent | Can use `-Credential` |
| **Remote Sessions** | Complex to pass | Works naturally |

---

## When to Use Each

### Use `ForEach-Object -Parallel` When:

✅ Processing **many items** (100+)  
✅ Each task is **short to medium duration** (seconds to minutes)  
✅ You need **fast startup**  
✅ Memory efficiency matters  
✅ Running on **PowerShell 7+**  
✅ All tasks use the **same credentials**

**Example Use Cases:**
- Parsing hundreds of log files
- Generating documentation for many source files
- Processing data transformations on multiple datasets
- Batch image/file operations

### Use `Start-Job` When:

✅ Running **few long-running tasks** (hours)  
✅ Need **complete isolation** between tasks  
✅ Running on **PowerShell 5.1**  
✅ Need to run with **different credentials**  
✅ Tasks might **crash** and you need protection  
✅ Using **remote sessions** that need to persist

**Example Use Cases:**
- Long-running backup operations
- Tasks that might fail and need isolation
- Running operations as different users
- Legacy PowerShell 5.1 environments

---

## Thread-Safe Logging

When using parallel processing, console output gets interleaved. Use thread-safe approaches:

### Option 1: Concurrent Queue

```powershell
$logQueue = [System.Collections.Concurrent.ConcurrentQueue[string]]::new()

$items | ForEach-Object -Parallel {
    $queue = $using:logQueue
    $queue.Enqueue("$(Get-Date -Format 'HH:mm:ss') - Processing: $_")
    # ... work ...
}

# Drain queue after processing
$message = $null
while ($logQueue.TryDequeue([ref]$message)) {
    Write-Host $message
}
```

### Option 2: Interlocked Counter

```powershell
$processedCount = [ref]0

$items | ForEach-Object -Parallel {
    # ... work ...
    $count = [System.Threading.Interlocked]::Increment($using:processedCount)
    if ($count % 100 -eq 0) {
        Write-Host "Processed: $count items"
    }
}
```

---

## Performance Tips

### 1. Optimal ThrottleLimit

```powershell
# Use 75% of available cores
$cores = [Environment]::ProcessorCount
$throttle = [Math]::Max(2, [Math]::Floor($cores * 0.75))

$items | ForEach-Object -Parallel {
    # ...
} -ThrottleLimit $throttle
```

### 2. Minimize Module Imports

```powershell
# Bad: Import multiple modules every iteration
$items | ForEach-Object -Parallel {
    Import-Module Module1, Module2, Module3  # Slow!
}

# Better: Import only what's needed
$items | ForEach-Object -Parallel {
    Import-Module MinimalModule -Force
}
```

### 3. Pre-calculate Common Data

```powershell
# Export common data to file before parallel loop
$commonData | Export-Clixml -Path "$tmpFolder\CommonData.xml"

$items | ForEach-Object -Parallel {
    $data = Import-Clixml -Path "$using:tmpFolder\CommonData.xml"
    # Use $data...
}
```

---

## Error Handling

### ForEach-Object -Parallel

```powershell
$items | ForEach-Object -Parallel {
    $item = $_
    $outFolder = $using:outputFolder
    
    try {
        # Processing that might fail
        Process-Item $item
    }
    catch {
        # Create error file for this specific item
        $errPath = Join-Path $outFolder "$item.err"
        "Error: $($_.Exception.Message)`n$($_.ScriptStackTrace)" | 
            Set-Content -Path $errPath -Force
    }
}
```

### Start-Job

```powershell
$jobs = foreach ($item in $items) {
    Start-Job -ScriptBlock {
        param($item)
        try {
            Process-Item $item
        }
        catch {
            throw "Failed processing $item: $_"
        }
    } -ArgumentList $item
}

# Check for failures
$jobs | Wait-Job
$failed = $jobs | Where-Object { $_.State -eq 'Failed' }
foreach ($job in $failed) {
    Write-Error "Job failed: $($job.Name)"
    Receive-Job $job -ErrorAction Continue
}
```

---

## Real-World Example: AutoDoc Batch Runner

The AutoDoc batch runner uses `ForEach-Object -Parallel` to process hundreds of source files:

```powershell
# Build unified work queue
$unifiedQueue = @()
$unifiedQueue += $nonCblFiles  # Faster files first
$unifiedQueue += $cblFiles      # Slower files last

# Process all items with unified parallel queue
$unifiedQueue | ForEach-Object -Parallel {
    # Initialize globals for parallel runspace
    Import-Module GlobalFunctions -Force -ErrorAction Stop
    Initialize-GlobalFunctionsForParallel
    Import-Module AutodocFunctions -Force -ErrorAction Stop
    
    $item = $_
    $outFolder = $using:outputFolder
    
    try {
        switch ($item.ParserType) {
            "CBL" { Start-CblParse -SourceFile $item.FilePath -OutputFolder $outFolder }
            "REX" { Start-RexParse -SourceFile $item.FilePath -OutputFolder $outFolder }
            "PS1" { Start-Ps1Parse -SourceFile $item.FilePath -OutputFolder $outFolder }
            "SQL" { Start-SqlParse -SqlTable $item.TableName -OutputFolder $outFolder }
        }
    }
    catch {
        # Log error to file
        "$($_.Exception.Message)" | Set-Content "$outFolder\$($item.FileName).err"
    }
} -ThrottleLimit 20
```

**Why this approach:**
- Processing 500+ files → runspaces are much faster
- Each file takes 10-60 seconds → medium duration tasks
- All files go to same output folder → simple coordination
- Memory efficiency matters → shared process space

---

## Summary

| Scenario | Recommendation |
|----------|----------------|
| 100+ small files, PS7+ | `ForEach-Object -Parallel` |
| 5 long-running backups | `Start-Job` |
| PowerShell 5.1 only | `Start-Job` |
| Need different credentials | `Start-Job` |
| Memory-constrained environment | `ForEach-Object -Parallel` |
| Tasks that might crash | `Start-Job` (isolation) |
| Fast batch processing | `ForEach-Object -Parallel` |

---

## References

- [Microsoft Docs: ForEach-Object -Parallel](https://docs.microsoft.com/en-us/powershell/module/microsoft.powershell.core/foreach-object)
- [Microsoft Docs: Start-Job](https://docs.microsoft.com/en-us/powershell/module/microsoft.powershell.core/start-job)
- [PowerShell 7 Parallel Processing](https://devblogs.microsoft.com/powershell/powershell-foreach-object-parallel-feature/)
