# Invoke-TaskWithLogging.ps1

**Author:** Geir Helge Starholm, www.dEdge.no

## Description

Task wrapper script that adds comprehensive logging to scheduled task execution. This script wraps the execution of PowerShell scripts or script blocks with detailed start, completion, failure, and execution time logging using the existing Write-LogMessage infrastructure.

## Features

- **Comprehensive Logging**: Logs task start, completion, failure, and execution time
- **Script File Support**: Execute PowerShell script files with logging
- **Script Block Support**: Execute PowerShell script blocks directly
- **Parameter Passing**: Pass parameters to scripts or script blocks
- **Working Directory**: Set custom working directory for task execution
- **Duration Tracking**: Automatically calculates and logs execution time
- **Error Handling**: Detailed error logging with exception information
- **Result Passing**: Option to return results from executed scripts

## Parameters

| Parameter | Type | Description | Required | Default |
|-----------|------|-------------|----------|---------|
| TaskName | String | Name of the task for logging purposes | Yes | - |
| ScriptPath | String | Path to PowerShell script file to execute | No* | - |
| ScriptBlock | ScriptBlock | PowerShell script block to execute | No* | - |
| Parameters | Hashtable | Parameters to pass to script/scriptblock | No | @{} |
| WorkingDirectory | String | Working directory for script execution | No | Current location |
| PassThru | Switch | Return result from executed script/scriptblock | No | False |
| ShowHelp | Switch | Show help message and exit | No | False |

*Either ScriptPath or ScriptBlock must be provided

## Usage Examples

### Script File Execution
```powershell
# Execute a simple script with logging
.\Invoke-TaskWithLogging.ps1 -TaskName "DataBackup" -ScriptPath "C:\Scripts\Backup.ps1"

# Execute script with parameters
.\Invoke-TaskWithLogging.ps1 -TaskName "DataBackup" -ScriptPath "C:\Scripts\Backup.ps1" -Parameters @{
    Database = "MyDB"
    BackupPath = "C:\Backups"
    RetentionDays = 30
}

# Execute script in specific working directory
.\Invoke-TaskWithLogging.ps1 -TaskName "ProcessLogs" -ScriptPath ".\ProcessLogs.ps1" -WorkingDirectory "C:\LogProcessing"

# Execute script and capture results
$result = .\Invoke-TaskWithLogging.ps1 -TaskName "DataExport" -ScriptPath "C:\Scripts\Export.ps1" -PassThru
```

### Script Block Execution
```powershell
# Execute a simple script block
.\Invoke-TaskWithLogging.ps1 -TaskName "SystemCheck" -ScriptBlock { 
    Get-Process | Where-Object CPU -gt 100 
}

# Execute script block with parameters
.\Invoke-TaskWithLogging.ps1 -TaskName "ServiceRestart" -ScriptBlock {
    param($ServiceName, $WaitSeconds)
    Restart-Service -Name $ServiceName
    Start-Sleep -Seconds $WaitSeconds
    Get-Service -Name $ServiceName
} -Parameters @{ServiceName = "Spooler"; WaitSeconds = 5}

# Complex script block with multiple operations
.\Invoke-TaskWithLogging.ps1 -TaskName "MaintenanceTask" -ScriptBlock {
    param($LogPath, $DaysToKeep)
    
    # Clean old logs
    Get-ChildItem $LogPath -File | Where-Object LastWriteTime -lt (Get-Date).AddDays(-$DaysToKeep) | Remove-Item
    
    # Generate report
    $reportData = @{
        CleanupDate = Get-Date
        FilesRemoved = (Get-ChildItem $LogPath -File).Count
    }
    
    return $reportData
} -Parameters @{LogPath = "C:\Logs"; DaysToKeep = 7} -PassThru
```

### Integration with Scheduled Tasks

#### Method 1: Modify Existing Task Action
**Before:**
```
Action: powershell.exe
Arguments: -File "C:\Scripts\MyScript.ps1" -Parameter1 "Value1"
```

**After:**
```
Action: powershell.exe  
Arguments: -File "C:\opt\DedgePshApps\ScheduledTaskMonitor\Invoke-TaskWithLogging.ps1" -TaskName "MyTask" -ScriptPath "C:\Scripts\MyScript.ps1" -Parameters @{Parameter1="Value1"}
```

#### Method 2: Create New Task with Wrapper
```powershell
# Create scheduled task using the wrapper
$action = New-ScheduledTaskAction -Execute "powershell.exe" -Argument '-File "C:\opt\DedgePshApps\ScheduledTaskMonitor\Invoke-TaskWithLogging.ps1" -TaskName "DataBackup" -ScriptPath "C:\Scripts\Backup.ps1"'

$trigger = New-ScheduledTaskTrigger -Daily -At "02:00"
$principal = New-ScheduledTaskPrincipal -UserId "$env:USERDOMAIN\$env:USERNAME" -LogonType Interactive
$settings = New-ScheduledTaskSettingsSet -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries

Register-ScheduledTask -TaskName "DataBackup-WithLogging" -Action $action -Trigger $trigger -Principal $principal -Settings $settings
```

#### Method 3: Using New-ScheduledTaskWithLogging Function
```powershell
# Use the built-in helper function (included in the script)
New-ScheduledTaskWithLogging -TaskName "DataBackup" -ScriptPath "C:\Scripts\Backup.ps1" -Description "Daily data backup with logging" -Daily -StartTime "02:00"

# Create task with parameters
New-ScheduledTaskWithLogging -TaskName "LogCleanup" -ScriptPath "C:\Scripts\CleanLogs.ps1" -Parameters @{RetentionDays=30} -Daily -StartTime "01:00" -DryRun
```

## Log Output Examples

### Successful Task Execution
```
[2024-01-15 14:30:15] [JOB_STARTED] TASK_STARTED: DataBackup
[2024-01-15 14:30:15] [INFO] Executing script: C:\Scripts\Backup.ps1
[2024-01-15 14:30:15] [INFO] Script parameters: Database, BackupPath
[2024-01-15 14:32:45] [JOB_COMPLETED] TASK_COMPLETED: DataBackup - Duration: 2.50 minutes
```

### Failed Task Execution
```
[2024-01-15 14:30:15] [JOB_STARTED] TASK_STARTED: DataBackup
[2024-01-15 14:30:15] [INFO] Executing script: C:\Scripts\Backup.ps1
[2024-01-15 14:30:45] [JOB_FAILED] TASK_FAILED: DataBackup - Duration: 30.5 seconds
[2024-01-15 14:30:45] [JOB_FAILED] Exception: Access to the path 'C:\Backups' is denied.
```

### Script Block Execution
```
[2024-01-15 14:30:15] [JOB_STARTED] TASK_STARTED: SystemCheck
[2024-01-15 14:30:15] [INFO] Executing script block for task: SystemCheck
[2024-01-15 14:30:16] [JOB_COMPLETED] TASK_COMPLETED: SystemCheck - Duration: 1.2 seconds
```

### Working Directory Change
```
[2024-01-15 14:30:15] [JOB_STARTED] TASK_STARTED: ProcessLogs
[2024-01-15 14:30:15] [INFO] Changed working directory to: C:\LogProcessing
[2024-01-15 14:30:15] [INFO] Executing script: .\ProcessLogs.ps1
[2024-01-15 14:31:20] [JOB_COMPLETED] TASK_COMPLETED: ProcessLogs - Duration: 1.08 minutes
```

## Advanced Usage

### Complex Parameter Passing
```powershell
# Complex parameter example
$complexParams = @{
    DatabaseConfig = @{
        Server = "DatabaseServer"
        Database = "ProductionDB"
        Timeout = 300
    }
    EmailSettings = @{
        SmtpServer = "mail.company.com"
        Recipients = @("admin@company.com", "backup@company.com")
    }
    Options = @{
        Verbose = $true
        SkipValidation = $false
        RetryCount = 3
    }
}

.\Invoke-TaskWithLogging.ps1 -TaskName "ComplexBackup" -ScriptPath "C:\Scripts\AdvancedBackup.ps1" -Parameters $complexParams
```

### Error Handling Integration
```powershell
# Script that handles errors gracefully
.\Invoke-TaskWithLogging.ps1 -TaskName "RobustTask" -ScriptBlock {
    param($Path, $Pattern)
    
    try {
        if (-not (Test-Path $Path)) {
            throw "Path does not exist: $Path"
        }
        
        $files = Get-ChildItem $Path -Filter $Pattern
        Write-Host "Found $($files.Count) files matching pattern: $Pattern"
        
        return $files
    }
    catch {
        Write-Error "Error in RobustTask: $($_.Exception.Message)"
        throw
    }
} -Parameters @{Path = "C:\Data"; Pattern = "*.log"}
```

### Performance Monitoring
```powershell
# Task that monitors its own performance
.\Invoke-TaskWithLogging.ps1 -TaskName "PerformanceTask" -ScriptBlock {
    $startMemory = [System.GC]::GetTotalMemory($false)
    
    # Perform work
    1..1000000 | ForEach-Object { $_ * 2 } | Out-Null
    
    $endMemory = [System.GC]::GetTotalMemory($false)
    $memoryUsed = $endMemory - $startMemory
    
    Write-Host "Memory used: $($memoryUsed / 1MB) MB"
}
```

## Helper Functions

### New-ScheduledTaskWithLogging
Creates a new scheduled task that uses the logging wrapper:

```powershell
New-ScheduledTaskWithLogging -TaskName "DataSync" -ScriptPath "C:\Scripts\Sync.ps1" -Description "Data synchronization with logging" -Daily -StartTime "03:00" -User "DOMAIN\ServiceAccount"
```

Parameters:
- **TaskName**: Name of the scheduled task
- **ScriptPath**: Path to script to execute
- **Parameters**: Hashtable of script parameters
- **Description**: Task description
- **StartTime**: Start time in HH:MM format
- **User**: User account to run the task as
- **Daily**: Create daily trigger
- **DryRun**: Show what would be created without actually creating it

## Best Practices

### Task Naming
Use descriptive, consistent task names:
```powershell
# Good examples
-TaskName "DataBackup-Production"
-TaskName "LogCleanup-WebServer"
-TaskName "SecurityScan-Daily"

# Avoid generic names
-TaskName "Task1"
-TaskName "Script"
```

### Parameter Organization
Organize complex parameters clearly:
```powershell
$params = @{
    # Database settings
    DatabaseServer = "prod-db-01"
    DatabaseName   = "ProductionDB"
    
    # File settings
    BackupPath     = "\\backup-server\backups"
    RetentionDays  = 30
    
    # Notification settings
    EmailEnabled   = $true
    Recipients     = @("admin@company.com")
}
```

### Working Directory Usage
Set appropriate working directories:
```powershell
# For scripts that work with relative paths
-WorkingDirectory "C:\Scripts\ProjectRoot"

# For scripts that process specific directories
-WorkingDirectory "C:\Data\Processing"
```

### Error Handling
Implement proper error handling in wrapped scripts:
```powershell
# In your script that will be wrapped
try {
    # Main script logic
    $result = Invoke-SomeOperation
    
    if (-not $result) {
        throw "Operation returned null result"
    }
    
    return $result
}
catch {
    # Log additional context before re-throwing
    Write-Error "Additional context: Operation failed at step 3"
    throw
}
```

## Troubleshooting

### Common Issues

1. **Script Not Found**:
   ```powershell
   # Verify script path
   Test-Path "C:\Scripts\MyScript.ps1"
   
   # Use absolute paths
   -ScriptPath "C:\Full\Path\To\Script.ps1"
   ```

2. **Parameter Passing Errors**:
   ```powershell
   # Test parameters separately
   $params = @{Key = "Value"}
   & "C:\Scripts\MyScript.ps1" @params
   ```

3. **Working Directory Issues**:
   ```powershell
   # Verify working directory exists
   Test-Path "C:\WorkingDirectory"
   
   # Check current location in script
   Get-Location
   ```

4. **Permission Errors**:
   ```powershell
   # Verify script execution policy
   Get-ExecutionPolicy
   
   # Set if needed
   Set-ExecutionPolicy -ExecutionPolicy RemoteSigned -Scope CurrentUser
   ```

### Debugging

Enable detailed logging:
```powershell
Set-LogLevel -LogLevel "DEBUG"
.\Invoke-TaskWithLogging.ps1 -TaskName "DebugTest" -ScriptPath "C:\Scripts\Test.ps1"
```

Test script execution directly:
```powershell
# Test without wrapper first
& "C:\Scripts\MyScript.ps1" -Parameter1 "Value1"

# Then test with wrapper
.\Invoke-TaskWithLogging.ps1 -TaskName "Test" -ScriptPath "C:\Scripts\MyScript.ps1" -Parameters @{Parameter1="Value1"}
```

## Prerequisites

- **PowerShell 5.1** or later
- **GlobalFunctions module** must be available in PSModulePath
- **Script execution permissions** for the user running the wrapper
- **File system access** to script paths and working directories

## Related Files

- **Start-ScheduledTaskEventMonitor.ps1**: Event monitoring script
- **_deploy.ps1**: Automated deployment script  
- **README.md**: Overall toolkit documentation
