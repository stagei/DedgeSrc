# ScheduledTask-Handler Module

Comprehensive management of Windows Scheduled Tasks.

## Exported Functions

### New-ScheduledTask
Creates a new scheduled task with specified settings.

```powershell
New-ScheduledTask [-TaskName <string>] [-Executable <string>] [-Arguments <string>] [-StartHour <int>] [-TaskFolder <string>] [-RunWhenLoggedOf <bool>] [-RunLevel <string>] [-RunFrequency <string>]
```

### Stop-ScheduledTask
Stops a running scheduled task.

```powershell
Stop-ScheduledTask -TaskName <string> [-IgnoreError <bool>]
```

### Disable-ScheduledTask
Disables a scheduled task.

```powershell
Disable-ScheduledTask -TaskName <string> [-IgnoreError <bool>]
```

### Enable-ScheduledTask
Enables a disabled scheduled task.

```powershell
Enable-ScheduledTask -TaskName <string> [-IgnoreError <bool>]
```

### Start-ScheduledTask
Starts a scheduled task immediately.

```powershell
Start-ScheduledTask -TaskName <string> [-IgnoreError <bool>]
```

### Remove-ScheduledTask
Removes a scheduled task.

```powershell
Remove-ScheduledTask [-TaskName <string>] [-TaskFolder <string>] [-IgnoreError <bool>]
```

### Save-ScheduledTaskFiles
Saves scheduled task configuration files.

```powershell
Save-ScheduledTaskFiles
```

### New-ScheduledTaskOverviewReport
Creates a report of all scheduled tasks.

```powershell
New-ScheduledTaskOverviewReport
```

### Get-ScriptPath
Gets the script path for a scheduled task.

```powershell
Get-ScriptPath -Executable <string> -TaskName <string> [-TaskFolder <string>]
```

### Get-ScheduledTaskCredentials
Gets credentials for scheduled tasks.

```powershell
Get-ScheduledTaskCredentials
```

## Overview
The ScheduledTask-Handler module provides comprehensive functionality for managing Windows scheduled tasks across local and remote computers. It enables creating, modifying, enabling, disabling, starting, stopping, and removing scheduled tasks, as well as generating reports on task status.

## Dependencies
- Export-Array module
- GlobalFunctions module
- Infrastructure module
- PowerShell 7 or later

## Usage Notes
- This module requires PowerShell 7 or later
- Many functions require administrator privileges
- Remote task management requires appropriate permissions on the remote computer
- The module uses the Windows Task Scheduler command-line interface (schtasks.exe) for compatibility 