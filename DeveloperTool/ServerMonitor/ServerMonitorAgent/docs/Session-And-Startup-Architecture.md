# ServerMonitor Session and Startup Architecture

## Overview

This document describes how ServerMonitor applications start, stop, and interact across Windows Session 0 (services) and Session 1+ (user sessions).

## Windows Session Architecture

### Session 0 (Service Session)
- **No desktop access** - Cannot display UI elements, tray icons, or interact with users
- **Always running** - Services start at boot, before any user logs in
- **Isolated** - Cannot directly interact with user session applications
- **Used by**: ServerMonitor (Agent) and ServerMonitorDashboard (Web API) Windows Services

### Session 1+ (User Sessions)
- **Desktop access** - Can display windows, tray icons, notifications
- **Requires user logon** - Only starts when a user logs in
- **Interactive** - Can receive user input
- **Used by**: ServerMonitorTrayIcon and ServerMonitorDashboard.Tray applications

## Application Components

| Component | Type | Session | Purpose |
|-----------|------|---------|---------|
| **ServerMonitor** | Windows Service | 0 | Agent service that monitors server health, runs 24/7 |
| **ServerMonitorDashboard** | Windows Service | 0 | Web API/UI on port 8998, runs 24/7 |
| **ServerMonitorTrayIcon** | Desktop App | 1+ | System tray icon for Agent, launches on user logon |
| **ServerMonitorDashboard.Tray** | Desktop App | 1+ | System tray icon for Dashboard, launches on user logon |

## Startup Sequence

### On Boot (Session 0 - No User Logged In)

```
System Boot
    │
    ├─► Windows Service Control Manager
    │       │
    │       ├─► ServerMonitor service starts (delayed auto-start)
    │       │       └─► ReinstallTriggerService monitors for updates
    │       │
    │       └─► ServerMonitorDashboard service starts (delayed auto-start)
    │               └─► ReinstallTriggerService monitors for updates
    │
    └─► Services run in Session 0 (no desktop)
```

### On User Logon (Session 1+)

```
User Logon
    │
    ├─► Task Scheduler detects ONLOGON trigger
    │       │
    │       ├─► ServerMonitorTrayIcon scheduled task
    │       │       └─► /IT flag = Interactive (runs in user session)
    │       │       └─► /RL HIGHEST = Elevated without UAC prompt
    │       │       └─► /DELAY 0000:10 = 10 second delay for desktop
    │       │
    │       └─► ServerMonitorDashboard.Tray scheduled task
    │               └─► Same flags as above
    │
    └─► Tray icons appear in user's system tray
```

## Auto-Update Mechanism

### Trigger Files
Located at: `C:\opt\src\DedgeSrc\DedgeSystemTools\Folders\DedgeCommon\Software\Config\ServerMonitor\`

| File | Affects |
|------|---------|
| `ReinstallServerMonitor.txt` | Agent service + TrayIcon |
| `ReinstallServerMonitor_{MachineName}.txt` | Agent on specific machine |
| `ReinstallServerMonitorDashboard.txt` | Dashboard service + Tray |
| `ReinstallServerMonitorDashboard_{MachineName}.txt` | Dashboard on specific machine |

### Version Comparison
- Trigger file contains: `Version=1.0.193`
- Applications compare this with their assembly version
- **CRITICAL**: Assembly version format is `1.0.193.0` (4 parts) vs trigger `1.0.193` (3 parts)
- Comparison must normalize versions to match

### Update Flow

```
ReinstallTriggerService (in Service, Session 0)
    │
    ├─► Checks trigger file every 10 seconds
    │
    ├─► Reads Version= from trigger file
    │
    ├─► Compares with current assembly version
    │       └─► If match: skip (already up to date)
    │       └─► If mismatch: proceed with update
    │
    ├─► Launches PowerShell install script as detached process
    │       ├─► Install-OurPshApp -AppName 'ServerMonitorAgent'
    │       └─► Start-OurPshApp -AppName 'ServerMonitorAgent'
    │
    └─► Install script runs:
            ├─► Stops service
            ├─► Kills related processes
            ├─► Removes old files
            ├─► Copies new files from DedgeCommon
            ├─► Recreates service
            ├─► Starts service
            └─► Starts tray app (if in user session)
```

### Tray App Update Detection
The tray apps also monitor trigger files using FileSystemWatcher:
- They detect changes faster than the service (using file system events)
- They can launch updates while user is logged in
- They show balloon notifications for update status

## Known Issues and Solutions

### Issue 1: Version Comparison Mismatch
**Problem**: Assembly version `1.0.193.0` ≠ Trigger version `1.0.193`
**Solution**: Normalize version comparison - compare only first 3 parts

### Issue 2: Endless Reinstall Loop
**Problem**: Version never matches, so reinstall triggers every 5 minutes
**Solution**: Fix version comparison; add cooldown; track last installed version

### Issue 3: Tray Apps Running Without Desktop Interaction
**Problem**: Scheduled tasks not using /IT flag or running in wrong session
**Solution**: Ensure `/IT` flag is present in schtasks.exe command

### Issue 4: Services Fail to Start
**Problem**: Service cannot start due to credential or path issues
**Solution**: 
- Verify service account has "Log on as a service" right
- Verify executable path exists and is accessible
- Check Windows Event Viewer for detailed error

### Issue 5: Process Conflicts
**Problem**: Install script kills processes but they restart immediately
**Solution**: 
- Services: Stop service before killing process
- Tray apps: Only start after install complete

## Scheduled Task Configuration

### Required schtasks.exe Flags

```powershell
schtasks.exe /Create `
    /TN "TaskName" `           # Task name
    /TR "ExePath" `            # Executable path
    /SC ONLOGON `              # Trigger on any user logon
    /RL HIGHEST `              # Run with highest privileges (admin)
    /IT `                      # Interactive - runs in user session with desktop
    /DELAY 0000:10 `           # 10 second delay after logon
    /F                         # Force overwrite if exists
```

### Critical: The /IT Flag
- **Without /IT**: Task runs in Session 0 (no desktop access)
- **With /IT**: Task runs in user's session (Session 1+) with desktop access

## Windows Service Configuration

### Required Settings
```powershell
New-Service -Name "ServiceName" `
    -BinaryPathName "ExePath" `
    -DisplayName "Display Name" `
    -StartupType Automatic `
    -Credential $domainCredential

# Configure auto-restart on failure
sc.exe failure ServiceName reset=86400 actions=restart/60000

# Set delayed auto-start
Set-ItemProperty -Path "HKLM:\SYSTEM\CurrentControlSet\Services\ServiceName" `
    -Name "DelayedAutoStart" -Value 1 -Type DWord
```

### Service Account Requirements
- Must have "Log on as a service" right
- Must have read access to executable and config files
- Must have write access to log directories
- Must have network access to DedgeCommon share

## Debugging Commands

### Check Service Status
```powershell
Get-Service *ServerMonitor*
```

### Check Scheduled Tasks
```powershell
schtasks /query /tn "ServerMonitorTrayIcon" /v
schtasks /query /tn "ServerMonitorDashboard.Tray" /v
```

### Check Running Processes
```powershell
Get-Process *ServerMonitor* | Select Name, Id, SessionId
```

### Check Event Logs
```powershell
# Application log
Get-WinEvent -FilterHashtable @{LogName='Application'; StartTime=(Get-Date).AddHours(-2)} | 
    Where-Object { $_.Message -match 'ServerMonitor' }

# System log (service events)
Get-WinEvent -FilterHashtable @{LogName='System'; StartTime=(Get-Date).AddHours(-2)} | 
    Where-Object { $_.Message -match 'ServerMonitor' }
```

### Manually Start Components
```powershell
# Services
Start-Service ServerMonitor
Start-Service ServerMonitorDashboard

# Tray apps (as current user)
Start-Process "C:\opt\DedgeWinApps\ServerMonitorTrayIcon\ServerMonitorTrayIcon.exe"
Start-Process "C:\opt\DedgeWinApps\ServerMonitorDashboard.Tray\ServerMonitorDashboard.Tray.exe"
```
