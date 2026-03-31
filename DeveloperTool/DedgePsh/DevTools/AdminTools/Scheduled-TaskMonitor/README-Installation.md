# Installation Guide - Scheduled Task Monitor

**Author:** Geir Helge Starholm, www.dEdge.no

## Overview

This guide provides detailed instructions for installing and configuring the Scheduled Task Monitor toolkit on Windows servers. The toolkit consists of monitoring scripts that integrate with the existing Dedge PowerShell infrastructure.

## Prerequisites

### System Requirements
- **Operating System**: Windows Server 2016 or later, Windows 10/11
- **PowerShell**: Version 5.1 or later
- **User Permissions**: 
  - Local administrator rights (for service installation)
  - "Log on as a service" right (for service accounts)
  - Read access to Windows Event Log
- **Network Access**: For remote deployment scenarios

### Module Dependencies
- **GlobalFunctions**: Must be available in PSModulePath
- **ScheduledTask-Handler**: Required for deployment script
- **Infrastructure**: Required for deployment script

### Directory Structure
The toolkit will be installed to:
```
C:\opt\DedgePshApps\ScheduledTaskMonitor\
├── Start-ScheduledTaskEventMonitor.ps1
├── Invoke-TaskWithLogging.ps1
└── README files (optional)
```

## Installation Methods

### Method 1: Automated Deployment (Recommended)

#### Single Server Installation
```powershell
# Navigate to the source directory
cd "C:\opt\src\DedgePsh\DevTools\AdminTools\Scheduled-TaskMonitor"

# Install on current server with monitoring service
.\_deploy.ps1 -InstallAsService -EnableCurrentUserOnly

# Install without service (manual execution)
.\_deploy.ps1
```

#### Multiple Server Deployment
```powershell
# Deploy to multiple servers
$servers = @("server1.domain.com", "server2.domain.com", "server3.domain.com")
.\_deploy.ps1 -TargetServers $servers -InstallAsService -EnableCurrentUserOnly

# Deploy with custom service user
.\_deploy.ps1 -TargetServers $servers -InstallAsService -ServiceUser "DOMAIN\MonitoringUser" -MonitoringInterval 60
```

#### Test Deployment (Dry Run)
```powershell
# Test what would be deployed without making changes
.\_deploy.ps1 -DryRun -InstallAsService -EnableCurrentUserOnly

# Test multi-server deployment
.\_deploy.ps1 -TargetServers @("server1", "server2") -DryRun -InstallAsService
```

### Method 2: Manual Installation

#### Step 1: Create Directory Structure
```powershell
# Create target directory
$targetPath = "C:\opt\DedgePshApps\ScheduledTaskMonitor"
New-Item -ItemType Directory -Path $targetPath -Force

# Verify directory creation
Test-Path $targetPath
```

#### Step 2: Copy Files
```powershell
# Define source and target paths
$sourcePath = "C:\opt\src\DedgePsh\DevTools\AdminTools\Scheduled-TaskMonitor"
$targetPath = "C:\opt\DedgePshApps\ScheduledTaskMonitor"

# Copy main scripts
Copy-Item -Path "$sourcePath\Start-ScheduledTaskEventMonitor.ps1" -Destination $targetPath -Force
Copy-Item -Path "$sourcePath\Invoke-TaskWithLogging.ps1" -Destination $targetPath -Force

# Verify files copied
Get-ChildItem $targetPath
```

#### Step 3: Test Installation
```powershell
# Test event monitor
cd $targetPath
.\Start-ScheduledTaskEventMonitor.ps1 -RunOnce -MonitorCurrentUser

# Test task wrapper
.\Invoke-TaskWithLogging.ps1 -TaskName "InstallTest" -ScriptBlock { Get-Date }
```

### Method 3: Remote Installation

#### Using PowerShell Remoting
```powershell
# Install on remote server
$serverName = "remote-server.domain.com"
$session = New-PSSession -ComputerName $serverName

# Copy files to remote server
$sourcePath = "C:\opt\src\DedgePsh\DevTools\AdminTools\Scheduled-TaskMonitor"
Copy-Item -Path "$sourcePath\*.ps1" -Destination "\\$serverName\C$\opt\DedgePshApps\ScheduledTaskMonitor\" -Force

# Configure on remote server
Invoke-Command -Session $session -ScriptBlock {
    # Test installation
    cd "C:\opt\DedgePshApps\ScheduledTaskMonitor"
    .\Start-ScheduledTaskEventMonitor.ps1 -RunOnce
}

Remove-PSSession $session
```

## Service Configuration

### Install Monitoring Service

#### Basic Service Installation
```powershell
# Install service to monitor all tasks
$taskName = "FK-TaskMonitoringService"
$scriptPath = "C:\opt\DedgePshApps\ScheduledTaskMonitor\Start-ScheduledTaskEventMonitor.ps1"
$arguments = "-File `"$scriptPath`" -PollingIntervalSeconds 30"

$action = New-ScheduledTaskAction -Execute "powershell.exe" -Argument $arguments
$trigger = New-ScheduledTaskTrigger -AtStartup
$principal = New-ScheduledTaskPrincipal -UserId "$env:USERDOMAIN\$env:USERNAME" -LogonType ServiceAccount
$settings = New-ScheduledTaskSettingsSet -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries -StartWhenAvailable

Register-ScheduledTask -TaskName $taskName -Action $action -Trigger $trigger -Principal $principal -Settings $settings -Description "FK Scheduled Task Monitoring Service"
```

#### Service with Current User Monitoring
```powershell
# Monitor only current user's tasks
$arguments = "-File `"$scriptPath`" -MonitorCurrentUser -PollingIntervalSeconds 30"
# ... rest same as above
```

#### Service with Specific Task Monitoring
```powershell
# Monitor specific tasks only
$taskNames = @("DataBackup", "LogCleanup", "SecurityScan")
$taskNamesString = ($taskNames | ForEach-Object { "`"$_`"" }) -join ","
$arguments = "-File `"$scriptPath`" -TaskNames @($taskNamesString) -PollingIntervalSeconds 30"
# ... rest same as above
```

### Service Management

#### Start/Stop Service
```powershell
# Start monitoring service
Start-ScheduledTask -TaskName "FK-TaskMonitoringService"

# Stop monitoring service
Stop-ScheduledTask -TaskName "FK-TaskMonitoringService"

# Check service status
Get-ScheduledTask -TaskName "FK-TaskMonitoringService" | Get-ScheduledTaskInfo
```

#### Update Service Configuration
```powershell
# Get current task
$task = Get-ScheduledTask -TaskName "FK-TaskMonitoringService"

# Update arguments (example: change polling interval)
$newArguments = "-File `"C:\opt\DedgePshApps\ScheduledTaskMonitor\Start-ScheduledTaskEventMonitor.ps1`" -PollingIntervalSeconds 60 -MonitorCurrentUser"
$task.Actions[0].Arguments = $newArguments

# Update the task
Set-ScheduledTask -InputObject $task
```

#### Remove Service
```powershell
# Stop and remove the monitoring service
Stop-ScheduledTask -TaskName "FK-TaskMonitoringService" -ErrorAction SilentlyContinue
Unregister-ScheduledTask -TaskName "FK-TaskMonitoringService" -Confirm:$false
```

## Configuration Options

### Deployment Script Parameters

| Parameter | Description | Default | Example |
|-----------|-------------|---------|---------|
| TargetServers | Array of server names | Current computer | @("srv1", "srv2") |
| InstallAsService | Create monitoring service | False | -InstallAsService |
| ServiceUser | User for service | Current user | "DOMAIN\svc_monitor" |
| MonitoringInterval | Polling interval (seconds) | 30 | 60 |
| EnableCurrentUserOnly | Monitor current user only | False | -EnableCurrentUserOnly |
| DryRun | Test without changes | False | -DryRun |

### Event Monitor Configuration

| Parameter | Description | Default | Example |
|-----------|-------------|---------|---------|
| MonitorCurrentUser | Monitor current user tasks only | False | -MonitorCurrentUser |
| TaskNames | Specific tasks to monitor | All tasks | @("Backup*", "Sync*") |
| PollingIntervalSeconds | Event check interval | 30 | 60 |
| RunOnce | Check once and exit | False | -RunOnce |
| MaxEvents | Max events per check | 100 | 50 |

## Post-Installation Verification

### Verify File Installation
```powershell
# Check files are in place
$targetPath = "C:\opt\DedgePshApps\ScheduledTaskMonitor"
Get-ChildItem $targetPath

# Verify file integrity (optional)
Get-FileHash "$targetPath\Start-ScheduledTaskEventMonitor.ps1"
```

### Test Event Monitoring
```powershell
# Test event monitor manually
cd "C:\opt\DedgePshApps\ScheduledTaskMonitor"
.\Start-ScheduledTaskEventMonitor.ps1 -RunOnce -MonitorCurrentUser

# Should output recent task events or "No new task scheduler events found"
```

### Test Task Wrapper
```powershell
# Test task wrapper with simple script block
.\Invoke-TaskWithLogging.ps1 -TaskName "VerificationTest" -ScriptBlock { 
    Write-Host "Test successful: $(Get-Date)"
    return "Success"
}

# Check logs for proper output
Get-Content "C:\opt\data\AllPwshLog\30237-FK_$(Get-Date -Format 'yyyyMMdd').log" | Select-String "VerificationTest"
```

### Verify Service Installation (if applicable)
```powershell
# Check service exists and is running
Get-ScheduledTask -TaskName "FK-TaskMonitoringService" | Get-ScheduledTaskInfo

# Verify service is generating logs
Start-Sleep 60  # Wait for one polling cycle
Get-Content "C:\opt\data\AllPwshLog\30237-FK_$(Get-Date -Format 'yyyyMMdd').log" | Select-String "TASK_EVENT" | Select-Object -Last 5
```

## Security Configuration

### Service Account Setup
```powershell
# Create dedicated service account (run as domain admin)
$password = ConvertTo-SecureString "ComplexPassword123!" -AsPlainText -Force
New-ADUser -Name "svc_taskmonitor" -GivenName "Task" -Surname "Monitor" -SamAccountName "svc_taskmonitor" -UserPrincipalName "svc_taskmonitor@domain.com" -AccountPassword $password -Enabled $true -PasswordNeverExpires $true

# Grant "Log on as a service" right
# Use Local Security Policy (secpol.msc) or:
secedit /export /cfg c:\temp\security.cfg
# Edit security.cfg to add user to SeServiceLogonRight
secedit /configure /db c:\temp\security.sdb /cfg c:\temp\security.cfg
```

### Permissions Setup
```powershell
# Grant read access to event logs (if needed)
wevtutil sl Microsoft-Windows-ScheduledTask/Operational /ca:O:BAG:SYD:(A;;0x1;;;BA)(A;;0x1;;;SY)(A;;0x1;;;S-1-5-32-573)

# Set folder permissions
$acl = Get-Acl "C:\opt\DedgePshApps\ScheduledTaskMonitor"
$accessRule = New-Object System.Security.AccessControl.FileSystemAccessRule("DOMAIN\svc_taskmonitor", "ReadAndExecute", "ContainerInherit,ObjectInherit", "None", "Allow")
$acl.SetAccessRule($accessRule)
Set-Acl "C:\opt\DedgePshApps\ScheduledTaskMonitor" $acl
```

## Troubleshooting Installation

### Common Installation Issues

1. **Access Denied Errors**:
   ```powershell
   # Run as administrator
   Start-Process powershell -Verb RunAs
   
   # Check current user permissions
   whoami /priv
   ```

2. **Module Not Found**:
   ```powershell
   # Check module availability
   Get-Module -ListAvailable GlobalFunctions
   
   # Add module path if needed
   $env:PSModulePath += ";C:\opt\src\DedgePsh\_Modules"
   ```

3. **Network Path Issues**:
   ```powershell
   # Test network connectivity
   Test-Path "\\target-server\C$"
   
   # Use credentials if needed
   $cred = Get-Credential
   New-PSDrive -Name "TempDrive" -PSProvider FileSystem -Root "\\target-server\C$" -Credential $cred
   ```

4. **Scheduled Task Creation Fails**:
   ```powershell
   # Check task scheduler service
   Get-Service Schedule
   
   # Test with simple task first
   $action = New-ScheduledTaskAction -Execute "cmd.exe" -Argument "/c echo test"
   Register-ScheduledTask -TaskName "TestTask" -Action $action
   ```

### Diagnostic Commands

```powershell
# System information
Get-ComputerInfo | Select-Object WindowsProductName, WindowsVersion, PowerShellVersion

# Check execution policy
Get-ExecutionPolicy -List

# Verify log directory exists
Test-Path "C:\opt\data\AllPwshLog"

# Check event log accessibility
Get-WinEvent -ListLog Microsoft-Windows-ScheduledTask/Operational

# Test basic functionality
Import-Module GlobalFunctions -Force
Write-LogMessage "Installation test" -Level INFO
```

## Uninstallation

### Remove Service
```powershell
# Stop and remove monitoring service
Stop-ScheduledTask -TaskName "FK-TaskMonitoringService" -ErrorAction SilentlyContinue
Unregister-ScheduledTask -TaskName "FK-TaskMonitoringService" -Confirm:$false
```

### Remove Files
```powershell
# Remove installation directory
Remove-Item "C:\opt\DedgePshApps\ScheduledTaskMonitor" -Recurse -Force
```

### Clean Registry (if needed)
```powershell
# Remove any service-related registry entries (usually not needed for scheduled tasks)
# Check for any custom registry entries you may have created
```

## Maintenance

### Regular Maintenance Tasks

1. **Check Service Health**:
   ```powershell
   # Weekly check
   Get-ScheduledTask -TaskName "FK-TaskMonitoringService" | Get-ScheduledTaskInfo
   ```

2. **Monitor Log File Growth**:
   ```powershell
   # Check log file sizes
   Get-ChildItem "C:\opt\data\AllPwshLog\*.log" | Sort-Object Length -Descending | Select-Object Name, @{N="SizeMB";E={[math]::Round($_.Length/1MB,2)}}
   ```

3. **Update Scripts**:
   ```powershell
   # Re-run deployment to update scripts
   .\_deploy.ps1 -InstallAsService -EnableCurrentUserOnly
   ```

### Performance Monitoring

```powershell
# Monitor service performance
Get-Process | Where-Object ProcessName -eq "powershell" | Where-Object {$_.CommandLine -like "*ScheduledTaskEventMonitor*"}

# Check event processing efficiency
Get-Content "C:\opt\data\AllPwshLog\30237-FK_$(Get-Date -Format 'yyyyMMdd').log" | Select-String "Processing.*task scheduler events"
```

## Support

For issues with installation or configuration:

1. Check the main README.md for troubleshooting guidance
2. Review log files in `C:\opt\data\AllPwshLog\`
3. Verify prerequisites are met
4. Test with minimal configuration first
5. Contact: Geir Helge Starholm, www.dEdge.no
