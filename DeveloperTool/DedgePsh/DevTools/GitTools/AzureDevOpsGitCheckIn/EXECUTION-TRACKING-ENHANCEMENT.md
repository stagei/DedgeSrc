# Azure DevOps Git Check-In - Execution Tracking Enhancement

## Overview

Enhanced the `AzureDevOpsGitCheckIn.ps1` script to build a comprehensive WorkObject similar to DB2 scripts, providing detailed execution tracking, phase monitoring, and comprehensive HTML reporting.

## Changes Made

### 1. Enhanced WorkObject Initialization

**Location**: Lines 12-63

**Before**:
```powershell
$script:WorkObject = [PSCustomObject]@{
    Name = "AzureDevOpsGitCheckIn"
    Description = "Azure DevOps Git Check-In"
}
```

**After**: Comprehensive WorkObject with 30+ properties tracking:

```powershell
$script:WorkObject = [PSCustomObject]@{
    # Job Information
    Name                      = "AzureDevOpsGitCheckIn"
    Description               = "Azure DevOps Git Check-In Automation"
    ScriptPath                = $PSCommandPath
    ExecutionTimestamp        = Get-Date -Format 'yyyy-MM-dd HH:mm:ss'
    ExecutionUser             = "$env:USERDOMAIN\$env:USERNAME"
    ComputerName              = $env:COMPUTERNAME
    
    # Execution Status
    Status                    = "Running"
    OverallSuccess            = $false
    ErrorMessage              = $null
    
    # Configuration
    Organization              = $null
    Project                   = $null
    Repository                = $null
    GitFolders                = $null
    
    # Execution Phases (tracked as boolean flags)
    NetworkPathsValidated     = $false
    FoldersInitialized        = $false
    CobdokModulesRetrieved    = $false
    GitRepoInitialized        = $false
    SourceFilesCopied         = $false
    FilesProcessed            = $false
    ChangesCommitted          = $false
    ChangesPushed             = $false
    
    # Statistics
    TotalFilesCopied          = 0
    TotalFilesExcluded        = 0
    TotalFilesInRepo          = 0
    ExcludedFilesDetails      = @()
    
    # Timing
    StartTime                 = Get-Date
    EndTime                   = $null
    Duration                  = $null
    LastSuccessfulRun         = $null
    
    # Script and Output Tracking
    ScriptArray               = @()
    
    # Results
    CommitMessage             = $null
    CommitHash                = $null
    PushResult                = $null
}
```

---

### 2. Function-Level Tracking

Each critical function now uses `Add-ScriptAndOutputToWorkObject` to record execution details:

#### A. Test-NetworkPaths

**Enhancement**: Tracks which paths were validated and their status

```powershell
$validationResults = @()
foreach ($folder in $config.GitFolders.GetEnumerator()) {
    foreach ($source in $folder.Value.Sources) {
        $isValid = Test-Path $source.Path
        $validationResults += "Path: $($source.Path) - $(if($isValid){'✓ Accessible'}else{'✗ NOT Accessible'})"
    }
}

$script:WorkObject.NetworkPathsValidated = $allValid
$script:WorkObject = Add-ScriptAndOutputToWorkObject -WorkObject $script:WorkObject -Name "Test-NetworkPaths" -Script "Network path validation" -Output ($validationResults -join "`n")
```

#### B. Initialize-Folders

**Enhancement**: Tracks which folders were created vs already existed

```powershell
$folderResults = @()
foreach ($path in $paths) {
    if (-not (Test-Path $path -PathType Container)) {
        Add-Folder -Path $path -AdditionalAdmins @(...)
        $folderResults += "Created: $path"
    }
    else {
        $folderResults += "Exists: $path"
    }
}

$script:WorkObject.FoldersInitialized = $true
$script:WorkObject = Add-ScriptAndOutputToWorkObject -WorkObject $script:WorkObject -Name "Initialize-Folders" -Script "Folder initialization" -Output ($folderResults -join "`n")
```

#### C. Get-CobdokModules

**Enhancement**: Tracks query executed and results

```powershell
$outputDetails = @(
    "Query: $query",
    "Total modules retrieved: $($modules.Count)",
    "Modules marked as UTGATT: $($excludedFiles.Count)"
)

$script:WorkObject.CobdokModulesRetrieved = $true
$script:WorkObject = Add-ScriptAndOutputToWorkObject -WorkObject $script:WorkObject -Name "Get-CobdokModules" -Script $query -Output ($outputDetails -join "`n")
```

#### D. Copy-SourceFiles

**Enhancement**: Tracks every robocopy operation and file count

```powershell
$copyResults = @()
$totalFilesCopied = 0

# ... robocopy operations ...

if ($result.ExitCode -gt 7) {
    $copyResults += "ERROR: Robocopy failed for $filter with exit code $($result.ExitCode)"
}
else {
    $copyResults += "Copied $filter from $($source.Path) to $targetFolder (Exit code: $($result.ExitCode))"
    if ($result.ExitCode -gt 0) {
        $totalFilesCopied++
    }
}

$script:WorkObject.SourceFilesCopied = $true
$script:WorkObject.TotalFilesCopied = $totalFilesCopied
$script:WorkObject = Add-ScriptAndOutputToWorkObject -WorkObject $script:WorkObject -Name "Copy-SourceFiles" -Script "Robocopy operations" -Output ($copyResults -join "`n")
```

#### E. Initialize-GitRepo

**Enhancement**: Tracks git operations and clone status

```powershell
$gitInitResults = @()
$gitInitResults += "Repository path: $repoPath"
$gitInitResults += "Repository URL: $repoUrl"
$gitInitResults += "Full clone performed: $fullClonePerformed"
$gitInitResults += "Repository initialized successfully"

$script:WorkObject.GitRepoInitialized = $true
$script:WorkObject = Add-ScriptAndOutputToWorkObject -WorkObject $script:WorkObject -Name "Initialize-GitRepo" -Script "Git repository initialization" -Output ($gitInitResults -join "`n")
```

#### F. Update-GitRepo

**Enhancement**: Tracks file exclusions, git add, commit, and push operations

```powershell
# Track excluded files
$script:WorkObject.TotalFilesExcluded = $finalExcludedFiles.Count
$script:WorkObject.ExcludedFilesDetails = $finalExcludedFiles
$script:WorkObject.TotalFilesInRepo = $files.Count - $finalExcludedFiles.Count

# Track git operations
$gitOperationResults = @()
$gitOperationResults += "Commit message: $commitMessage"
$gitOperationResults += "Commit output: $commitOutput"
$gitOperationResults += "Commit hash: $commitHash"
$gitOperationResults += "Push output: $pushOutput"

if ($LASTEXITCODE -eq 0) {
    $script:WorkObject.ChangesCommitted = $true
    $script:WorkObject.CommitMessage = $commitMessage
    $script:WorkObject.CommitHash = $commitHash
}

$script:WorkObject = Add-ScriptAndOutputToWorkObject -WorkObject $script:WorkObject -Name "Update-GitRepo" -Script "Git add, commit, and push operations" -Output ($gitOperationResults -join "`n")
```

---

### 3. Main Execution Enhancement

**Enhancement**: Comprehensive success/failure tracking and reporting

#### Success Path

```powershell
try {
    Start-GitCheckIn -isRetry:$isRetry -allFiltersFromConfig $allFiltersFromConfig
    
    # Mark as successful
    $script:WorkObject.Status = "Completed"
    $script:WorkObject.OverallSuccess = $true
}
catch {
    # Retry logic with tracking
    if ($_.Exception.Message -like "*Git operation failed*") {
        $script:WorkObject = Add-ScriptAndOutputToWorkObject -WorkObject $script:WorkObject -Name "Retry-Attempt" -Script "Retry with full copy after git error" -Output "First attempt failed: $($_.Exception.Message)"
        
        try {
            Start-GitCheckIn -isRetry:$true -allFiltersFromConfig $allFiltersFromConfig
            $script:WorkObject.Status = "Completed (after retry)"
            $script:WorkObject.OverallSuccess = $true
        }
        catch {
            $script:WorkObject.Status = "Failed"
            $script:WorkObject.OverallSuccess = $false
            $script:WorkObject.ErrorMessage = $_.Exception.Message
            throw
        }
    }
}

# Calculate duration
$script:WorkObject.EndTime = Get-Date
$script:WorkObject.Duration = $script:WorkObject.EndTime - $script:WorkObject.StartTime

# Add complete execution log
$logContent = Get-Content -Path $global:CurrentLogFilePath
$script:WorkObject = Add-ScriptAndOutputToWorkObject -WorkObject $script:WorkObject -Name "ExecutionLog" -Script "Complete execution log" -Output ($logContent -join "`n")

# Export comprehensive HTML report
$reportPath = Join-Path $(Get-ApplicationDataPath) "AzureDevOpsGitCheckIn_$(Get-Date -Format 'yyyyMMdd_HHmmss').html"
Export-WorkObjectToHtmlFile -WorkObject $script:WorkObject -FileName $reportPath -Title "Azure DevOps Git Check-In - Execution Report" -AutoOpen $false -AddToDevToolsWebPath $true -DevToolsWebDirectory "Git/AzureDevOpsGitCheckIn"
```

#### Failure Path

```powershell
catch {
    # Update work object with failure information
    $script:WorkObject.Status = "Failed"
    $script:WorkObject.OverallSuccess = $false
    $script:WorkObject.ErrorMessage = $_.Exception.Message
    $script:WorkObject.EndTime = Get-Date
    $script:WorkObject.Duration = $script:WorkObject.EndTime - $script:WorkObject.StartTime
    
    # Add failure details
    $failureDetails = @(
        "Error occurred at line: $($_.InvocationInfo.ScriptLineNumber)",
        "Error message: $($_.Exception.Message)",
        "Stack trace: $($_.ScriptStackTrace)"
    )
    $script:WorkObject = Add-ScriptAndOutputToWorkObject -WorkObject $script:WorkObject -Name "ExecutionError" -Script "Failure details" -Output ($failureDetails -join "`n")
    
    # Add log content even on failure
    try {
        $logContent = Get-Content -Path $global:CurrentLogFilePath -ErrorAction SilentlyContinue
        if ($logContent) {
            $script:WorkObject = Add-ScriptAndOutputToWorkObject -WorkObject $script:WorkObject -Name "ExecutionLog" -Script "Complete execution log (with errors)" -Output ($logContent -join "`n")
        }
    }
    catch { }
    
    # Export failure report
    $reportPath = Join-Path $(Get-ApplicationDataPath) "AzureDevOpsGitCheckIn_FAILED_$(Get-Date -Format 'yyyyMMdd_HHmmss').html"
    Export-WorkObjectToHtmlFile -WorkObject $script:WorkObject -FileName $reportPath -Title "Azure DevOps Git Check-In - FAILURE Report" -AutoOpen $false -AddToDevToolsWebPath $true -DevToolsWebDirectory "Git/AzureDevOpsGitCheckIn"
}
```

---

## Execution Phases Tracked

The WorkObject now tracks these execution phases as boolean flags:

1. ✅ **NetworkPathsValidated** - All source paths are accessible
2. ✅ **FoldersInitialized** - Required folders created
3. ✅ **CobdokModulesRetrieved** - Excluded files list retrieved from COBDOK
4. ✅ **GitRepoInitialized** - Git repository cloned/reset
5. ✅ **SourceFilesCopied** - Files copied from network shares
6. ✅ **FilesProcessed** - Files filtered and processed
7. ✅ **ChangesCommitted** - Changes committed to git
8. ✅ **ChangesPushed** - Changes pushed to remote

---

## Statistics Captured

### File Statistics
- **TotalFilesCopied**: Number of file copy operations
- **TotalFilesExcluded**: Files filtered out (UTGATT, old files, etc.)
- **TotalFilesInRepo**: Net files in repository
- **ExcludedFilesDetails**: Array of excluded files with reasons

### Timing Statistics
- **StartTime**: Job start timestamp
- **EndTime**: Job completion timestamp
- **Duration**: Total execution time
- **LastSuccessfulRun**: Previous successful execution

### Git Statistics
- **CommitMessage**: Generated commit message
- **CommitHash**: Git commit SHA
- **PushResult**: Push operation result

---

## HTML Report Structure

The exported HTML report now contains:

### Main Properties Table
Shows all WorkObject properties including:
- Job information (name, path, user, computer)
- Execution status (success/failure)
- Configuration details
- Phase completion flags
- Statistics
- Timing information

### Execution Tabs
Each tracked phase appears as a separate tab:
- **Test-NetworkPaths**: Network path validation results
- **Initialize-Folders**: Folder creation results
- **Get-CobdokModules**: COBDOK query and exclusion list
- **Copy-SourceFiles**: Robocopy operations and results
- **Initialize-GitRepo**: Git repository initialization
- **Update-GitRepo**: Git add, commit, and push operations
- **ExecutionLog**: Complete PowerShell log
- **ExecutionError** (on failure): Error details and stack trace
- **Retry-Attempt** (if applicable): Retry operation details

---

## Usage Examples

### Reviewing a Successful Run

1. Navigate to DevTools web path: `Git/AzureDevOpsGitCheckIn`
2. Open latest HTML report: `AzureDevOpsGitCheckIn_YYYYMMDD_HHMMSS.html`
3. Check main table for statistics:
   - Files copied
   - Files excluded
   - Commit hash
   - Duration
4. Click tabs to see detailed execution of each phase

### Troubleshooting a Failure

1. Open failure report: `AzureDevOpsGitCheckIn_FAILED_YYYYMMDD_HHMMSS.html`
2. Check **Status** property: Shows "Failed"
3. Check **ErrorMessage** property: Brief error description
4. Click **ExecutionError** tab: Full error details and stack trace
5. Check phase flags to see where failure occurred:
   - If `GitRepoInitialized = false`: Failed during git clone
   - If `ChangesPushed = false` but `ChangesCommitted = true`: Push failed
6. Click **ExecutionLog** tab: Complete PowerShell log up to failure point

---

## Alert Enhancements

### Success Alert
```
Azure DevOps Git Check-In completed successfully
Files copied: 25
Files excluded: 8
Files in repo: 1247
Duration: 00:03:45
```

### Failure Alert
```
Azure DevOps Git Check-In FAILED
Line: 425
Error: Robocopy failed with exit code 16
Duration: 00:01:23
```

---

## Benefits

1. **Complete Visibility**: Every phase of execution is tracked and recorded
2. **Easy Troubleshooting**: Failure reports show exactly where and why failure occurred
3. **Historical Analysis**: Compare execution times, file counts across runs
4. **Audit Trail**: Complete log of what was done, when, and by whom
5. **Pattern Analysis**: Identify trends in excluded files, copy times, etc.

---

## Future Enhancements

Potential additions:
- Git diff statistics (files added/modified/deleted)
- Network path latency measurements
- Robocopy performance metrics per folder
- Excluded file categorization (by reason)
- Comparison with previous run
- Automatic anomaly detection (unusual file counts, long duration)

---

**Implementation Date**: 2025-12-16  
**Pattern Source**: DB2-CreateInitialDatabases.ps1 and DB2-Handler module  
**Status**: ✅ Complete  
**Linter**: ✅ No errors
