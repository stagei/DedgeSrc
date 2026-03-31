# Start-ScheduledTaskEventMonitor.ps1

**Author:** Geir Helge Starholm, www.dEdge.no

## Description

Real-time monitoring script that watches Windows Event Log for scheduled task events and logs them using the existing Write-LogMessage infrastructure. This script provides comprehensive monitoring of task lifecycle events including start, completion, and failure events.

## Features

- **Real-time Event Monitoring**: Monitors Task Scheduler operational log for events
- **User Filtering**: Option to monitor only tasks running as specific users  
- **Task Name Filtering**: Monitor specific tasks by name patterns (supports wildcards)
- **Configurable Polling**: Adjustable polling interval for event checks
- **One-time Execution**: Option to check recent events once and exit
- **Comprehensive Logging**: Uses existing Write-LogMessage with appropriate log levels

## Parameters

| Parameter | Type | Description | Default |
|-----------|------|-------------|---------|
| MonitorCurrentUser | Switch | Only monitor tasks running as current user | False |
| TaskNames | String[] | Array of task names to monitor (supports wildcards) | @() (all tasks) |
| PollingIntervalSeconds | Int | Seconds between event checks | 30 |
| RunOnce | Switch | Check events once and exit (don't loop) | False |
| MaxEvents | Int | Maximum events to process per check | 100 |
| ShowHelp | Switch | Show help message and exit | False |

## Event Types Monitored

| Event ID | Event Type | Description | Log Level |
|----------|------------|-------------|-----------|
| 100 | STARTED | Task execution started | JOB_STARTED |
| 101 | COMPLETED_SUCCESS | Task completed successfully | JOB_COMPLETED |
| 102 | COMPLETED_WITH_ERRORS | Task completed with errors | JOB_FAILED |
| 103 | FAILED_TO_START | Task failed to start | JOB_FAILED |
| 110 | TRIGGERED | Task was triggered | INFO |
| 200 | ACTION_STARTED | Task action started | INFO |
| 201 | ACTION_COMPLETED | Task action completed | INFO |

## Usage Examples

### Basic Monitoring
```powershell
# Monitor all scheduled tasks continuously
.\Start-ScheduledTaskEventMonitor.ps1

# Show help
.\Start-ScheduledTaskEventMonitor.ps1 -ShowHelp
```

### User-Specific Monitoring
```powershell
# Monitor only current user's tasks
.\Start-ScheduledTaskEventMonitor.ps1 -MonitorCurrentUser

# Monitor current user's tasks with faster polling
.\Start-ScheduledTaskEventMonitor.ps1 -MonitorCurrentUser -PollingIntervalSeconds 10
```

### Task-Specific Monitoring
```powershell
# Monitor specific tasks by name
.\Start-ScheduledTaskEventMonitor.ps1 -TaskNames @("DataBackup", "LogCleanup")

# Monitor tasks with wildcard patterns
.\Start-ScheduledTaskEventMonitor.ps1 -TaskNames @("*Backup*", "*Sync*")

# Monitor specific tasks for current user only
.\Start-ScheduledTaskEventMonitor.ps1 -MonitorCurrentUser -TaskNames @("MyPersonalTask")
```

### One-Time Execution
```powershell
# Check recent events once and exit
.\Start-ScheduledTaskEventMonitor.ps1 -RunOnce

# Check recent events for current user only
.\Start-ScheduledTaskEventMonitor.ps1 -RunOnce -MonitorCurrentUser

# Check only 10 most recent events
.\Start-ScheduledTaskEventMonitor.ps1 -RunOnce -MaxEvents 10
```

### Custom Polling
```powershell
# Monitor with 1-minute polling interval
.\Start-ScheduledTaskEventMonitor.ps1 -PollingIntervalSeconds 60

# Monitor with very fast polling (5 seconds) for debugging
.\Start-ScheduledTaskEventMonitor.ps1 -PollingIntervalSeconds 5 -MonitorCurrentUser
```

## Installation as Service

### Method 1: Using Deployment Script
```powershell
# Install monitoring service for current user
.\_deploy.ps1 -InstallAsService -EnableCurrentUserOnly

# Install monitoring service for all tasks
.\_deploy.ps1 -InstallAsService -MonitoringInterval 60
```

### Method 2: Manual Service Installation
```powershell
# Create scheduled task for continuous monitoring
$taskName = "FK-TaskMonitoringService"
$scriptPath = "C:\opt\DedgePshApps\ScheduledTaskMonitor\Start-ScheduledTaskEventMonitor.ps1"
$arguments = "-File `"$scriptPath`" -MonitorCurrentUser -PollingIntervalSeconds 30"

$action = New-ScheduledTaskAction -Execute "powershell.exe" -Argument $arguments
$trigger = New-ScheduledTaskTrigger -AtStartup
$principal = New-ScheduledTaskPrincipal -UserId "$env:USERDOMAIN\$env:USERNAME" -LogonType ServiceAccount -RunLevel Highest
$settings = New-ScheduledTaskSettingsSet -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries -StartWhenAvailable -RestartCount 3

Register-ScheduledTask -TaskName $taskName -Action $action -Trigger $trigger -Principal $principal -Settings $settings -Description "FK Scheduled Task Monitoring Service"

# Start the monitoring service
Start-ScheduledTask -TaskName $taskName
```

## Log Output Examples

### Task Started
```
[2024-01-15 14:30:15] [JOB_STARTED] TASK_EVENT: STARTED - Task: DataBackup - Path: \DevTools\DataBackup - Time: 2024-01-15 14:30:15
```

### Task Completed Successfully
```
[2024-01-15 14:32:45] [JOB_COMPLETED] TASK_EVENT: COMPLETED_SUCCESS - Task: DataBackup - Result: 0 - Time: 2024-01-15 14:32:45
```

### Task Failed
```
[2024-01-15 14:35:12] [JOB_FAILED] TASK_EVENT: FAILED_TO_START - Task: LogCleanup - Result: 2147942402 - Time: 2024-01-15 14:35:12
```

### Task Triggered
```
[2024-01-15 14:30:00] [INFO] TASK_EVENT: TRIGGERED - Task: DataBackup - Time: 2024-01-15 14:30:00
```

## Performance Considerations

### Polling Interval Guidelines
- **High-frequency servers**: 60+ seconds to reduce CPU usage
- **Normal servers**: 30 seconds (default) for balanced monitoring
- **Critical monitoring**: 10-15 seconds for near real-time alerts
- **Debugging**: 5 seconds for immediate feedback

### Memory Usage
- **Baseline**: ~10-15 MB for basic monitoring
- **High event volume**: May increase to 20-30 MB
- **MaxEvents parameter**: Limits memory growth by capping event processing

### CPU Usage
- **Typical**: <1% CPU usage with 30-second polling
- **High event volume**: May spike to 2-3% during event processing
- **Continuous monitoring**: Negligible impact with proper polling intervals

## Troubleshooting

### Common Issues

1. **Access Denied to Event Log**:
   ```powershell
   # Verify user has access to event logs
   Get-WinEvent -ListLog Microsoft-Windows-ScheduledTask/Operational
   
   # Run with elevated privileges if needed
   ```

2. **No Events Found**:
   ```powershell
   # Check if Task Scheduler operational log is enabled
   wevtutil sl Microsoft-Windows-ScheduledTask/Operational /e:true
   
   # Verify recent task activity
   Get-WinEvent -FilterHashtable @{LogName='Microsoft-Windows-ScheduledTask/Operational'} -MaxEvents 5
   ```

3. **High CPU Usage**:
   ```powershell
   # Increase polling interval
   .\Start-ScheduledTaskEventMonitor.ps1 -PollingIntervalSeconds 60
   
   # Reduce max events processed
   .\Start-ScheduledTaskEventMonitor.ps1 -MaxEvents 50
   ```

4. **Script Stops Unexpectedly**:
   ```powershell
   # Check for errors in the log
   Get-Content "C:\opt\data\AllPwshLog\30237-FK_$(Get-Date -Format 'yyyyMMdd').log" | Select-String "ERROR"
   
   # Run with debug logging
   Set-LogLevel -LogLevel "DEBUG"
   .\Start-ScheduledTaskEventMonitor.ps1 -RunOnce
   ```

### Debugging Commands

```powershell
# Test event log access
Get-WinEvent -FilterHashtable @{LogName='Microsoft-Windows-ScheduledTask/Operational'; ID=100,101,102,103} -MaxEvents 1

# Check current task activity
Get-ScheduledTask | Where-Object State -eq "Running"

# Monitor with detailed logging
Set-LogLevel -LogLevel "TRACE"
.\Start-ScheduledTaskEventMonitor.ps1 -RunOnce -MonitorCurrentUser

# Check service health (if installed as service)
Get-ScheduledTask -TaskName "FK-TaskMonitoringService" | Get-ScheduledTaskInfo
```

## Advanced Configuration

### Custom Event Filtering
Modify the script to add additional event filtering:
```powershell
# Add custom event IDs
$eventIds = @(100, 101, 102, 103, 110, 200, 201, 411, 412)  # Added 411, 412 for detailed action events

# Add custom task path filtering
if ($taskPath -like "*/MyCompany/*" -or $taskPath -like "*/Custom/*") {
    $shouldLog = $true
}
```

### Integration with Alerting Systems
```powershell
# Add email alerts for critical failures
if ($logLevel -eq "JOB_FAILED" -and $taskName -like "*Critical*") {
    # Send alert email
    Send-MailMessage -To "admin@company.com" -Subject "Critical Task Failed: $taskName" -Body $message
}
```

### Custom Log Destinations
```powershell
# Add additional logging destinations
if ($eventType -eq "FAILED_TO_START") {
    # Log to Windows Event Log
    Write-EventLog -LogName Application -Source "FK-TaskMonitor" -EventId 1001 -EntryType Error -Message $message
}
```

## Prerequisites

- **PowerShell 5.1** or later
- **GlobalFunctions module** must be available in PSModulePath
- **Event log access**: User must have read access to Task Scheduler operational log
- **Elevated privileges**: Required for some event log operations

## Related Files

- **Invoke-TaskWithLogging.ps1**: Task wrapper for enhanced logging
- **_deploy.ps1**: Automated deployment script
- **README.md**: Overall toolkit documentation
