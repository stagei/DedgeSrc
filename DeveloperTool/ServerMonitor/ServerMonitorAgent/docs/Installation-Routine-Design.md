# ServerMonitor Silent Installation Routine Design

## Overview

This document describes how to create a fully automated, non-interactive installation routine for ServerMonitor components that:

1. ✅ Installs programs to correct folders
2. ✅ Creates desktop and Start Menu shortcuts with icons
3. ✅ Runs the agent/tray app with elevated privileges
4. ✅ Requires no console interaction (no "Press Y to continue")

---

## Current Architecture

### Components

| Component | Type | Install Location | Port |
|-----------|------|------------------|------|
| **ServerMonitor** | Windows Service | `%OptPath%\DedgeWinApps\ServerMonitor\` | 8999 |
| **ServerMonitorTrayIcon** | User Application | `%OptPath%\DedgeWinApps\ServerMonitorTrayIcon\` | 8997 |
| **ServerMonitorDashboard** | Web Application | `%OptPath%\DedgeWinApps\ServerMonitorDashboard\` | 8998 |

### Current Install Scripts

```
ServerMonitorAgent/
├── src/ServerMonitor/ServerMonitorAgent   # Main install script
├── Install/
│   ├── Install-Service.ps1                               # Simple service installer
│   └── Uninstall-Service.ps1                             # Service uninstaller
```

---

## Non-Interactive Installation Techniques

### 1. PowerShell Flags for Silent Execution

```powershell
# Always use these flags for non-interactive mode
$ErrorActionPreference = "Stop"           # Fail fast on errors
$ProgressPreference = "SilentlyContinue"  # Suppress progress bars
$ConfirmPreference = "None"               # Skip confirmation prompts

# For cmdlets that prompt:
Remove-Item -Force                         # Skip "Are you sure?"
Stop-Service -Force                        # Force stop without prompt
Copy-Item -Force                          # Overwrite without asking
New-Item -Force                           # Create/overwrite without prompt
```

### 2. Running as Administrator Without Prompt

#### Option A: Self-Elevating Script

```powershell
# Add to top of script - auto-elevates if not already admin
if (-not ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    $arguments = "-NoProfile -ExecutionPolicy Bypass -File `"$PSCommandPath`""
    Start-Process PowerShell -Verb RunAs -ArgumentList $arguments -Wait
    exit
}
```

#### Option B: Scheduled Task with Highest Privileges

```powershell
# Create a scheduled task that runs with highest privileges
$action = New-ScheduledTaskAction -Execute "PowerShell.exe" -Argument "-NoProfile -ExecutionPolicy Bypass -File `"$scriptPath`""
$trigger = New-ScheduledTaskTrigger -Once -At (Get-Date)
$principal = New-ScheduledTaskPrincipal -UserId "SYSTEM" -LogonType ServiceAccount -RunLevel Highest
$settings = New-ScheduledTaskSettingsSet -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries

Register-ScheduledTask -TaskName "ServerMonitor_Install" -Action $action -Trigger $trigger -Principal $principal -Settings $settings
Start-ScheduledTask -TaskName "ServerMonitor_Install"
```

#### Option C: psexec (For Remote Deployment)

```powershell
# Run as SYSTEM on remote machine (no UAC prompts)
psexec \\$serverName -s -h PowerShell.exe -NoProfile -ExecutionPolicy Bypass -File "\\share\Install-ServerMonitor.ps1"
```

### 3. Silent .NET Runtime Installation

The current script already does this correctly:

```powershell
# Download and install .NET runtime silently
$installArgs = "/install /quiet /norestart"
$process = Start-Process -FilePath $dotnetInstallerPath -ArgumentList $installArgs -Wait -PassThru

# Handle exit codes without prompting
switch ($process.ExitCode) {
    0     { Write-Host "✅ Installed successfully" }
    3010  { Write-Host "✅ Installed (reboot required)" }
    1641  { Write-Host "⚠️ Reboot was initiated" }
    default { throw "Installation failed with code: $($process.ExitCode)" }
}
```

---

## Creating Shortcuts with Icons

### Desktop Shortcut

```powershell
function New-DesktopShortcut {
    param(
        [string]$Name,
        [string]$TargetPath,
        [string]$IconPath,
        [string]$Arguments = "",
        [string]$WorkingDirectory = "",
        [bool]$RunAsAdmin = $false
    )
    
    $desktopPath = [Environment]::GetFolderPath('Desktop')
    $shortcutPath = Join-Path $desktopPath "$Name.lnk"
    
    $shell = New-Object -ComObject WScript.Shell
    $shortcut = $shell.CreateShortcut($shortcutPath)
    $shortcut.TargetPath = $TargetPath
    $shortcut.Arguments = $Arguments
    $shortcut.WorkingDirectory = if ($WorkingDirectory) { $WorkingDirectory } else { Split-Path $TargetPath }
    $shortcut.IconLocation = if ($IconPath) { $IconPath } else { "$TargetPath,0" }
    $shortcut.Description = $Name
    $shortcut.Save()
    
    # Set "Run as Administrator" flag if needed
    if ($RunAsAdmin) {
        $bytes = [System.IO.File]::ReadAllBytes($shortcutPath)
        $bytes[0x15] = $bytes[0x15] -bor 0x20  # Set byte 21 bit 5
        [System.IO.File]::WriteAllBytes($shortcutPath, $bytes)
    }
    
    Write-Host "✅ Created desktop shortcut: $shortcutPath"
}
```

### Start Menu Shortcut

```powershell
function New-StartMenuShortcut {
    param(
        [string]$Name,
        [string]$TargetPath,
        [string]$IconPath,
        [string]$FolderName = "ServerMonitor",
        [bool]$RunAsAdmin = $false
    )
    
    # Use All Users start menu for server-wide installation
    $startMenuPath = [Environment]::GetFolderPath('CommonStartMenu')
    $programsPath = Join-Path $startMenuPath "Programs"
    $folderPath = Join-Path $programsPath $FolderName
    
    # Create folder if it doesn't exist
    if (-not (Test-Path $folderPath)) {
        New-Item -Path $folderPath -ItemType Directory -Force | Out-Null
    }
    
    $shortcutPath = Join-Path $folderPath "$Name.lnk"
    
    $shell = New-Object -ComObject WScript.Shell
    $shortcut = $shell.CreateShortcut($shortcutPath)
    $shortcut.TargetPath = $TargetPath
    $shortcut.WorkingDirectory = Split-Path $TargetPath
    $shortcut.IconLocation = if ($IconPath) { $IconPath } else { "$TargetPath,0" }
    $shortcut.Description = $Name
    $shortcut.Save()
    
    # Set "Run as Administrator" flag if needed
    if ($RunAsAdmin) {
        $bytes = [System.IO.File]::ReadAllBytes($shortcutPath)
        $bytes[0x15] = $bytes[0x15] -bor 0x20
        [System.IO.File]::WriteAllBytes($shortcutPath, $bytes)
    }
    
    Write-Host "✅ Created Start Menu shortcut: $shortcutPath"
}
```

### Usage Example

```powershell
# Create shortcuts for ServerMonitorTrayIcon
$trayIconPath = "$env:OptPath\DedgeWinApps\ServerMonitorTrayIcon\ServerMonitorTrayIcon.exe"
$iconPath = "$env:OptPath\DedgeWinApps\ServerMonitorTrayIcon\dedge.ico"

New-DesktopShortcut -Name "Server Monitor" -TargetPath $trayIconPath -IconPath $iconPath
New-StartMenuShortcut -Name "Server Monitor" -TargetPath $trayIconPath -IconPath $iconPath -FolderName "ServerMonitor"
```

---

## Running Tray App at Startup

### Option 1: Registry Run Key (Current User)

```powershell
# Add to HKCU\Run for current user auto-start
$regPath = "HKCU:\Software\Microsoft\Windows\CurrentVersion\Run"
$appName = "ServerMonitorTrayIcon"
$appPath = "$env:OptPath\DedgeWinApps\ServerMonitorTrayIcon\ServerMonitorTrayIcon.exe"

Set-ItemProperty -Path $regPath -Name $appName -Value "`"$appPath`"" -Force
Write-Host "✅ Added to startup (current user)"
```

### Option 2: Registry Run Key (All Users - Requires Admin)

```powershell
# Add to HKLM\Run for all users auto-start
$regPath = "HKLM:\Software\Microsoft\Windows\CurrentVersion\Run"
$appName = "ServerMonitorTrayIcon"
$appPath = "$env:OptPath\DedgeWinApps\ServerMonitorTrayIcon\ServerMonitorTrayIcon.exe"

Set-ItemProperty -Path $regPath -Name $appName -Value "`"$appPath`"" -Force
Write-Host "✅ Added to startup (all users)"
```

### Option 3: Startup Folder Shortcut

```powershell
function Add-ToStartupFolder {
    param(
        [string]$Name,
        [string]$TargetPath,
        [bool]$AllUsers = $false
    )
    
    $startupFolder = if ($AllUsers) {
        [Environment]::GetFolderPath('CommonStartup')
    } else {
        [Environment]::GetFolderPath('Startup')
    }
    
    $shortcutPath = Join-Path $startupFolder "$Name.lnk"
    
    $shell = New-Object -ComObject WScript.Shell
    $shortcut = $shell.CreateShortcut($shortcutPath)
    $shortcut.TargetPath = $TargetPath
    $shortcut.WorkingDirectory = Split-Path $TargetPath
    $shortcut.Save()
    
    Write-Host "✅ Added to startup folder: $shortcutPath"
}
```

### Option 4: Scheduled Task at Logon (Recommended for Admin Apps)

```powershell
function Register-StartupTask {
    param(
        [string]$TaskName,
        [string]$ExecutablePath,
        [string]$RunAsUser = $env:USERNAME,
        [bool]$RunWithHighestPrivileges = $true
    )
    
    # Remove existing task if present
    Unregister-ScheduledTask -TaskName $TaskName -Confirm:$false -ErrorAction SilentlyContinue
    
    # Create the action
    $action = New-ScheduledTaskAction -Execute $ExecutablePath -WorkingDirectory (Split-Path $ExecutablePath)
    
    # Create the trigger (at logon)
    $trigger = New-ScheduledTaskTrigger -AtLogOn -User $RunAsUser
    
    # Create the principal (run level)
    $runLevel = if ($RunWithHighestPrivileges) { "Highest" } else { "Limited" }
    $principal = New-ScheduledTaskPrincipal -UserId $RunAsUser -LogonType Interactive -RunLevel $runLevel
    
    # Create settings
    $settings = New-ScheduledTaskSettingsSet `
        -AllowStartIfOnBatteries `
        -DontStopIfGoingOnBatteries `
        -StartWhenAvailable `
        -ExecutionTimeLimit (New-TimeSpan -Hours 0)  # No time limit
    
    # Register the task
    Register-ScheduledTask -TaskName $TaskName -Action $action -Trigger $trigger -Principal $principal -Settings $settings -Force
    
    Write-Host "✅ Registered scheduled task: $TaskName (runs at logon for $RunAsUser)"
}

# Usage
Register-StartupTask -TaskName "ServerMonitorTrayIcon" -ExecutablePath "$env:OptPath\DedgeWinApps\ServerMonitorTrayIcon\ServerMonitorTrayIcon.exe"
```

---

## Complete Silent Installation Script Template

```powershell
#Requires -RunAsAdministrator
#Requires -Version 7.0

<#
.SYNOPSIS
    Silent installation of ServerMonitor suite
.DESCRIPTION
    Installs ServerMonitor Agent, TrayIcon, and Dashboard without any user interaction.
    Creates shortcuts, configures auto-start, and starts services.
.PARAMETER SourcePath
    Network path to the installation files
.EXAMPLE
    .\Install-ServerMonitor-Silent.ps1
#>

param(
    [string]$SourcePath = "C:\opt\src\DedgeSrc\DedgeSystemTools\Folders\DedgeCommon\Software\DedgeWinApps"
)

# ═══════════════════════════════════════════════════════════════════════════════
# SILENT MODE CONFIGURATION
# ═══════════════════════════════════════════════════════════════════════════════
$ErrorActionPreference = "Stop"
$ProgressPreference = "SilentlyContinue"
$ConfirmPreference = "None"

# Redirect all streams to log file for unattended execution
$logFile = "C:\opt\data\ServerMonitor\Install_$(Get-Date -Format 'yyyyMMdd_HHmmss').log"
Start-Transcript -Path $logFile -Force

try {
    Write-Host "═══════════════════════════════════════════════════════" -ForegroundColor Cyan
    Write-Host "  ServerMonitor Silent Installation" -ForegroundColor Cyan
    Write-Host "  Started: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')" -ForegroundColor Gray
    Write-Host "═══════════════════════════════════════════════════════" -ForegroundColor Cyan

    # ─────────────────────────────────────────────────────────────────────────────
    # 1. VERIFY PREREQUISITES
    # ─────────────────────────────────────────────────────────────────────────────
    Write-Host "`n📋 Checking prerequisites..." -ForegroundColor Yellow
    
    # Check admin rights
    $isAdmin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
    if (-not $isAdmin) {
        throw "This script requires Administrator privileges"
    }
    Write-Host "   ✅ Running as Administrator" -ForegroundColor Green
    
    # Check source path
    if (-not (Test-Path $SourcePath)) {
        throw "Source path not accessible: $SourcePath"
    }
    Write-Host "   ✅ Source path accessible: $SourcePath" -ForegroundColor Green

    # ─────────────────────────────────────────────────────────────────────────────
    # 2. INSTALL .NET RUNTIME SILENTLY
    # ─────────────────────────────────────────────────────────────────────────────
    Write-Host "`n📦 Installing .NET Runtime (if needed)..." -ForegroundColor Yellow
    
    $dotnetInstalled = $false
    try {
        $runtimes = & dotnet --list-runtimes 2>$null
        if ($runtimes -match "Microsoft\.WindowsDesktop\.App 10\.") {
            $dotnetInstalled = $true
        }
    } catch { }
    
    if (-not $dotnetInstalled) {
        $dotnetUrl = "https://builds.dotnet.microsoft.com/dotnet/WindowsDesktop/10.0.1/windowsdesktop-runtime-10.0.1-win-x64.exe"
        $dotnetInstaller = Join-Path $env:TEMP "windowsdesktop-runtime.exe"
        
        Write-Host "   Downloading .NET 10 Runtime..." -ForegroundColor Gray
        Invoke-WebRequest -Uri $dotnetUrl -OutFile $dotnetInstaller -UseBasicParsing
        
        Write-Host "   Installing silently..." -ForegroundColor Gray
        $result = Start-Process -FilePath $dotnetInstaller -ArgumentList "/install /quiet /norestart" -Wait -PassThru
        
        if ($result.ExitCode -eq 0 -or $result.ExitCode -eq 3010) {
            Write-Host "   ✅ .NET 10 Runtime installed" -ForegroundColor Green
        } else {
            Write-Host "   ⚠️ .NET installer exit code: $($result.ExitCode)" -ForegroundColor Yellow
        }
        
        Remove-Item $dotnetInstaller -Force -ErrorAction SilentlyContinue
    } else {
        Write-Host "   ✅ .NET 10 Runtime already installed" -ForegroundColor Green
    }

    # ─────────────────────────────────────────────────────────────────────────────
    # 3. STOP EXISTING PROCESSES AND SERVICES
    # ─────────────────────────────────────────────────────────────────────────────
    Write-Host "`n🛑 Stopping existing components..." -ForegroundColor Yellow
    
    @("ServerMonitor", "ServerMonitorTrayIcon", "ServerMonitorDashboard") | ForEach-Object {
        Get-Process -Name $_ -ErrorAction SilentlyContinue | ForEach-Object {
            Write-Host "   Killing $($_.Name)..." -ForegroundColor Gray
            $_.Kill()
            $_.WaitForExit(5000)
        }
    }
    
    Get-Service -Name "ServerMonitor" -ErrorAction SilentlyContinue | ForEach-Object {
        if ($_.Status -eq 'Running') {
            Write-Host "   Stopping service..." -ForegroundColor Gray
            Stop-Service -Name $_.Name -Force -NoWait
            Start-Sleep -Seconds 2
        }
    }
    Write-Host "   ✅ Existing components stopped" -ForegroundColor Green

    # ─────────────────────────────────────────────────────────────────────────────
    # 4. COPY FILES TO INSTALLATION FOLDERS
    # ─────────────────────────────────────────────────────────────────────────────
    Write-Host "`n📂 Installing components..." -ForegroundColor Yellow
    
    $components = @(
        @{ Name = "ServerMonitor"; Source = "$SourcePath\ServerMonitor"; Dest = "$env:OptPath\DedgeWinApps\ServerMonitor" }
        @{ Name = "ServerMonitorTrayIcon"; Source = "$SourcePath\ServerMonitorTrayIcon"; Dest = "$env:OptPath\DedgeWinApps\ServerMonitorTrayIcon" }
        @{ Name = "ServerMonitorDashboard"; Source = "$SourcePath\ServerMonitorDashboard"; Dest = "$env:OptPath\DedgeWinApps\ServerMonitorDashboard" }
    )
    
    foreach ($component in $components) {
        if (Test-Path $component.Source) {
            Write-Host "   Installing $($component.Name)..." -ForegroundColor Gray
            
            # Remove old installation
            if (Test-Path $component.Dest) {
                Remove-Item -Path $component.Dest -Recurse -Force -ErrorAction SilentlyContinue
            }
            
            # Create destination folder
            New-Item -Path $component.Dest -ItemType Directory -Force | Out-Null
            
            # Copy files
            Copy-Item -Path "$($component.Source)\*" -Destination $component.Dest -Recurse -Force
            
            Write-Host "   ✅ $($component.Name) installed" -ForegroundColor Green
        }
    }

    # ─────────────────────────────────────────────────────────────────────────────
    # 5. CREATE SHORTCUTS
    # ─────────────────────────────────────────────────────────────────────────────
    Write-Host "`n🔗 Creating shortcuts..." -ForegroundColor Yellow
    
    $shell = New-Object -ComObject WScript.Shell
    
    # Desktop shortcut
    $desktopPath = [Environment]::GetFolderPath('CommonDesktopDirectory')
    $shortcutPath = Join-Path $desktopPath "Server Monitor.lnk"
    $targetPath = "$env:OptPath\DedgeWinApps\ServerMonitorTrayIcon\ServerMonitorTrayIcon.exe"
    
    $shortcut = $shell.CreateShortcut($shortcutPath)
    $shortcut.TargetPath = $targetPath
    $shortcut.WorkingDirectory = Split-Path $targetPath
    $shortcut.IconLocation = "$env:OptPath\DedgeWinApps\ServerMonitorTrayIcon\dedge.ico"
    $shortcut.Description = "Server Monitor Tray Application"
    $shortcut.Save()
    Write-Host "   ✅ Desktop shortcut created" -ForegroundColor Green
    
    # Start Menu shortcuts
    $startMenuPath = [Environment]::GetFolderPath('CommonStartMenu')
    $programsPath = Join-Path $startMenuPath "Programs\ServerMonitor"
    New-Item -Path $programsPath -ItemType Directory -Force | Out-Null
    
    $shortcut = $shell.CreateShortcut((Join-Path $programsPath "Server Monitor.lnk"))
    $shortcut.TargetPath = $targetPath
    $shortcut.IconLocation = "$env:OptPath\DedgeWinApps\ServerMonitorTrayIcon\dedge.ico"
    $shortcut.Save()
    Write-Host "   ✅ Start Menu shortcut created" -ForegroundColor Green

    # ─────────────────────────────────────────────────────────────────────────────
    # 6. CONFIGURE WINDOWS SERVICE
    # ─────────────────────────────────────────────────────────────────────────────
    Write-Host "`n⚙️ Configuring Windows Service..." -ForegroundColor Yellow
    
    $serviceName = "ServerMonitor"
    $exePath = "$env:OptPath\DedgeWinApps\ServerMonitor\ServerMonitor.exe"
    
    # Remove existing service if present
    $existingService = Get-Service -Name $serviceName -ErrorAction SilentlyContinue
    if ($existingService) {
        sc.exe delete $serviceName | Out-Null
        Start-Sleep -Seconds 2
    }
    
    # Create new service
    sc.exe create $serviceName binPath= "`"$exePath`"" start= delayed-auto DisplayName= "ServerMonitor" | Out-Null
    sc.exe description $serviceName "Monitors server health and generates alerts" | Out-Null
    sc.exe failure $serviceName reset= 86400 actions= restart/60000/restart/60000/restart/60000 | Out-Null
    
    Write-Host "   ✅ Windows Service configured" -ForegroundColor Green

    # ─────────────────────────────────────────────────────────────────────────────
    # 7. CONFIGURE TRAY APP AUTO-START (SCHEDULED TASK)
    # ─────────────────────────────────────────────────────────────────────────────
    Write-Host "`n🔧 Configuring Tray App auto-start..." -ForegroundColor Yellow
    
    $taskName = "ServerMonitorTrayIcon"
    $trayPath = "$env:OptPath\DedgeWinApps\ServerMonitorTrayIcon\ServerMonitorTrayIcon.exe"
    
    # Remove existing task
    Unregister-ScheduledTask -TaskName $taskName -Confirm:$false -ErrorAction SilentlyContinue
    
    # Create task that runs at logon for all users with highest privileges
    $action = New-ScheduledTaskAction -Execute $trayPath -WorkingDirectory (Split-Path $trayPath)
    $trigger = New-ScheduledTaskTrigger -AtLogOn
    $principal = New-ScheduledTaskPrincipal -GroupId "BUILTIN\Users" -RunLevel Highest
    $settings = New-ScheduledTaskSettingsSet -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries -ExecutionTimeLimit (New-TimeSpan -Hours 0)
    
    Register-ScheduledTask -TaskName $taskName -Action $action -Trigger $trigger -Principal $principal -Settings $settings -Force | Out-Null
    
    Write-Host "   ✅ Scheduled task created (runs at logon with admin privileges)" -ForegroundColor Green

    # ─────────────────────────────────────────────────────────────────────────────
    # 8. CONFIGURE FIREWALL RULES
    # ─────────────────────────────────────────────────────────────────────────────
    Write-Host "`n🔥 Configuring firewall rules..." -ForegroundColor Yellow
    
    @(
        @{ Name = "ServerMonitor_RestApi"; Port = 8999; Description = "ServerMonitor Agent API" }
        @{ Name = "ServerMonitorTrayIcon_Api"; Port = 8997; Description = "ServerMonitor Tray API" }
        @{ Name = "ServerMonitorDashboard"; Port = 8998; Description = "ServerMonitor Dashboard" }
    ) | ForEach-Object {
        Remove-NetFirewallRule -DisplayName "$($_.Name)_Inbound" -ErrorAction SilentlyContinue
        New-NetFirewallRule -DisplayName "$($_.Name)_Inbound" -Direction Inbound -Protocol TCP -LocalPort $_.Port -Action Allow -Profile Domain,Private -Description $_.Description | Out-Null
        Write-Host "   ✅ Port $($_.Port) opened ($($_.Description))" -ForegroundColor Green
    }

    # ─────────────────────────────────────────────────────────────────────────────
    # 9. START SERVICES AND APPLICATIONS
    # ─────────────────────────────────────────────────────────────────────────────
    Write-Host "`n🚀 Starting components..." -ForegroundColor Yellow
    
    # Start the Windows service
    Start-Service -Name "ServerMonitor"
    Write-Host "   ✅ ServerMonitor service started" -ForegroundColor Green
    
    # Start the tray icon application
    Start-Process -FilePath $trayPath
    Write-Host "   ✅ ServerMonitorTrayIcon started" -ForegroundColor Green

    # ─────────────────────────────────────────────────────────────────────────────
    # 10. VERIFY INSTALLATION
    # ─────────────────────────────────────────────────────────────────────────────
    Write-Host "`n✅ Installation Complete!" -ForegroundColor Green
    Write-Host "═══════════════════════════════════════════════════════" -ForegroundColor Cyan
    
    # Verify service
    $service = Get-Service -Name "ServerMonitor"
    Write-Host "   Service Status: $($service.Status)" -ForegroundColor $(if ($service.Status -eq 'Running') { 'Green' } else { 'Yellow' })
    
    # Verify tray app
    $trayProc = Get-Process -Name "ServerMonitorTrayIcon" -ErrorAction SilentlyContinue
    Write-Host "   Tray App: $(if ($trayProc) { 'Running' } else { 'Not Running' })" -ForegroundColor $(if ($trayProc) { 'Green' } else { 'Yellow' })
    
    Write-Host "`n   Log file: $logFile" -ForegroundColor Gray
    Write-Host "═══════════════════════════════════════════════════════" -ForegroundColor Cyan

} catch {
    Write-Host "`n❌ Installation failed: $($_.Exception.Message)" -ForegroundColor Red
    throw
} finally {
    Stop-Transcript
}
```

---

## Deployment Options

> **Note**: Remote PowerShell (WinRM/Invoke-Command) is disabled by administrator policy.
> The following options work without remote execution capabilities.

### Option 1: Network Share + Manual Execution (Recommended)

Place the install script on a network share and run locally on each server:

```powershell
# On each target server, run from elevated PowerShell:
& "C:\opt\src\DedgeSrc\DedgeSystemTools\Folders\DedgeCommon\Software\Scripts\Install-ServerMonitor-Silent.ps1"
```

**Batch deployment helper** (run from your workstation):

```powershell
# Generate commands for each server (copy/paste to each server's RDP session)
$servers = @("p-no1fkmprd-db", "p-no1inlprd-db", "dedge-server")
$scriptPath = "C:\opt\src\DedgeSrc\DedgeSystemTools\Folders\DedgeCommon\Software\Scripts\Install-ServerMonitor-Silent.ps1"

foreach ($server in $servers) {
    Write-Host "═══════════════════════════════════════════════════════" -ForegroundColor Cyan
    Write-Host "Server: $server" -ForegroundColor Yellow
    Write-Host "Run this command in elevated PowerShell on $($server):" -ForegroundColor Gray
    Write-Host ""
    Write-Host "  & `"$scriptPath`"" -ForegroundColor Green
    Write-Host ""
}
```

### Option 2: Auto-Update via Trigger File (Works When User is Logged In)

ServerMonitorTrayIcon already supports auto-update via a trigger file:

```powershell
# From any location with network access, create trigger file:
$servers = @("p-no1fkmprd-db", "p-no1inlprd-db")

foreach ($server in $servers) {
    $triggerPath = "\\$server\opt\DedgeWinApps\ServerMonitorTrayIcon\ReinstallServerMonitor.txt"
    "Trigger reinstall at $(Get-Date)" | Out-File -FilePath $triggerPath -Force
    Write-Host "✅ Triggered reinstall on $server" -ForegroundColor Green
}
```

The TrayIcon application watches for this file and automatically:
1. Stops the ServerMonitor service
2. Copies new files from the network share
3. Restarts the service
4. Deletes the trigger file

> ⚠️ **LIMITATION**: The TrayIcon uses Registry Run key (HKCU) which only runs when a user logs in.
> If the server reboots and no one logs in, the TrayIcon won't be running to detect trigger files.

---

## 🔧 Fix: TrayIcon Not Starting After Reboot

### Problem

The current setup adds TrayIcon to `HKCU:\Software\Microsoft\Windows\CurrentVersion\Run`:
- ✅ Works when the installing user logs in
- ❌ Does NOT work if server reboots and no one logs in
- ❌ Does NOT work for other users logging in

### Solution 1: Scheduled Task (Recommended) ⭐

Replace the Registry Run key with a Scheduled Task that runs at logon for ALL users:

```powershell
# Run this once on each server (as Administrator)
$taskName = "ServerMonitorTrayIcon"
$trayPath = "$env:OptPath\DedgeWinApps\ServerMonitorTrayIcon\ServerMonitorTrayIcon.exe"

# Remove registry run key (old method)
Remove-ItemProperty -Path "HKCU:\Software\Microsoft\Windows\CurrentVersion\Run" -Name $taskName -ErrorAction SilentlyContinue

# Remove existing task if present
Unregister-ScheduledTask -TaskName $taskName -Confirm:$false -ErrorAction SilentlyContinue

# Create task that runs at logon for ANY user with interactive session
$action = New-ScheduledTaskAction -Execute $trayPath -WorkingDirectory (Split-Path $trayPath)

# Trigger: At logon of any user
$trigger = New-ScheduledTaskTrigger -AtLogOn

# Principal: Run for logged-on users with highest privileges
$principal = New-ScheduledTaskPrincipal -GroupId "BUILTIN\Users" -RunLevel Highest

# Settings: Allow start, no time limit, restart on failure
$settings = New-ScheduledTaskSettingsSet `
    -AllowStartIfOnBatteries `
    -DontStopIfGoingOnBatteries `
    -ExecutionTimeLimit (New-TimeSpan -Hours 0) `
    -RestartCount 3 `
    -RestartInterval (New-TimeSpan -Minutes 1)

# Register the task
Register-ScheduledTask -TaskName $taskName -Action $action -Trigger $trigger -Principal $principal -Settings $settings -Force

Write-Host "✅ Scheduled task created: TrayIcon will start when ANY user logs on" -ForegroundColor Green
```

### Solution 2: Move Trigger File Monitoring to ServerMonitor Service

Add trigger file monitoring to the **ServerMonitor Windows Service** itself (runs even without login):

```csharp
// In ServerMonitor.Core - Add a new StopFileMonitorService or extend existing one
// to also watch for ReinstallServerMonitor.txt and trigger self-update
```

This is more complex but ensures updates work even when no user is logged in.

### Solution 3: All Users Startup Folder

Add a shortcut to the All Users startup folder (runs for any user who logs in):

```powershell
# Add to All Users Startup folder
$allUsersStartup = [Environment]::GetFolderPath('CommonStartup')
$shortcutPath = Join-Path $allUsersStartup "ServerMonitorTrayIcon.lnk"
$trayPath = "$env:OptPath\DedgeWinApps\ServerMonitorTrayIcon\ServerMonitorTrayIcon.exe"

$shell = New-Object -ComObject WScript.Shell
$shortcut = $shell.CreateShortcut($shortcutPath)
$shortcut.TargetPath = $trayPath
$shortcut.WorkingDirectory = Split-Path $trayPath
$shortcut.Save()

# Set "Run as Administrator" flag
$bytes = [System.IO.File]::ReadAllBytes($shortcutPath)
$bytes[0x15] = $bytes[0x15] -bor 0x20
[System.IO.File]::WriteAllBytes($shortcutPath, $bytes)

Write-Host "✅ Added to All Users Startup folder" -ForegroundColor Green
```

### Recommended: Update Both Install Scripts

#### ServerMonitorAgent.ps1 - Replace Registry Run with Scheduled Task

**Location**: `C:\opt\src\DedgePsh\DevTools\InfrastructureTools\ServerMonitorAgent\ServerMonitorAgent.ps1`

**REPLACE** lines 487-496 (the Registry Run section):

```powershell
# OLD CODE (DELETE THIS):
# Add ServerMonitorTrayIcon to Run at startup (Current User)
$startupRegPath = "HKCU:\Software\Microsoft\Windows\CurrentVersion\Run"
$startupName = "ServerMonitorTrayIcon"
try {
    Set-ItemProperty -Path $startupRegPath -Name $startupName -Value "`"$trayIconPath`""
    Write-LogMessage "✅ Added ServerMonitorTrayIcon to 'Run at startup' for current user." -Level INFO
}
catch {
    Write-LogMessage "❌ ERROR: Failed to add ServerMonitorTrayIcon to startup! $($_.Exception.Message)" -Level ERROR
}
```

**WITH** this new code:

```powershell
# ─────────────────────────────────────────────────────────────────────────────
# Configure ServerMonitorTrayIcon Startup via Scheduled Task (All Users)
# ─────────────────────────────────────────────────────────────────────────────
Write-LogMessage "📋 Configuring Scheduled Task for ServerMonitorTrayIcon..." -Level INFO

$taskName = "ServerMonitorTrayIcon"
$trayIconIconPath = "$env:OptPath\DedgeWinApps\ServerMonitorTrayIcon\dedge.ico"

try {
    # Remove old Registry Run key if present
    $regPath = "HKCU:\Software\Microsoft\Windows\CurrentVersion\Run"
    Remove-ItemProperty -Path $regPath -Name $taskName -ErrorAction SilentlyContinue
    
    # Remove existing scheduled task
    Unregister-ScheduledTask -TaskName $taskName -Confirm:$false -ErrorAction SilentlyContinue
    
    # Create Scheduled Task for startup at user logon (works for ALL users)
    # Use schtasks.exe for better compatibility across PowerShell versions
    # /SC ONLOGON - Trigger when any user logs on
    # /RL HIGHEST - Run with elevated (admin) privileges without UAC prompt
    # /IT - Interactive mode (runs in user session, tray icon visible)
    # /DELAY 0000:10 - 10 second delay to allow desktop to fully load
    $schtasksArgs = @(
        '/Create'
        '/TN', $taskName
        '/TR', "`"$trayIconPath`""
        '/SC', 'ONLOGON'
        '/RL', 'HIGHEST'
        '/IT'
        '/DELAY', '0000:10'
        '/F'
    )
    $result = & schtasks.exe @schtasksArgs 2>&1
    if ($LASTEXITCODE -eq 0) {
        Write-LogMessage "   ✅ Scheduled Task created (runs at logon with admin privileges)" -Level INFO
    }
    else {
        Write-LogMessage "   ⚠️ schtasks.exe returned: $result" -Level WARN
    }
}
catch {
    Write-LogMessage "   ❌ Failed to create Scheduled Task: $($_.Exception.Message)" -Level ERROR
}

# ─────────────────────────────────────────────────────────────────────────────
# Create Desktop and Start Menu Shortcuts with Icon
# ─────────────────────────────────────────────────────────────────────────────
Write-LogMessage "🔗 Creating shortcuts for Server Monitor Tray..." -Level INFO

try {
    $shell = New-Object -ComObject WScript.Shell
    
    # Desktop shortcut (All Users)
    $desktopPath = [Environment]::GetFolderPath('CommonDesktopDirectory')
    $desktopShortcut = Join-Path $desktopPath "Server Monitor Tray.lnk"
    $shortcut = $shell.CreateShortcut($desktopShortcut)
    $shortcut.TargetPath = $trayIconPath
    $shortcut.WorkingDirectory = Split-Path $trayIconPath
    $shortcut.Description = "Server Monitor Tray Application"
    if (Test-Path $trayIconIconPath) { $shortcut.IconLocation = "$trayIconIconPath,0" }
    $shortcut.Save()
    # Set "Run as Administrator"
    $bytes = [System.IO.File]::ReadAllBytes($desktopShortcut)
    $bytes[0x15] = $bytes[0x15] -bor 0x20
    [System.IO.File]::WriteAllBytes($desktopShortcut, $bytes)
    Write-LogMessage "   ✅ Desktop shortcut created" -Level INFO
    
    # Start Menu shortcut (All Users - in ServerMonitor folder)
    $startMenuPath = [Environment]::GetFolderPath('CommonStartMenu')
    $programsPath = Join-Path $startMenuPath "Programs\ServerMonitor"
    if (-not (Test-Path $programsPath)) { New-Item -Path $programsPath -ItemType Directory -Force | Out-Null }
    $startMenuShortcut = Join-Path $programsPath "Server Monitor Tray.lnk"
    $shortcut = $shell.CreateShortcut($startMenuShortcut)
    $shortcut.TargetPath = $trayIconPath
    $shortcut.WorkingDirectory = Split-Path $trayIconPath
    $shortcut.Description = "Server Monitor Tray Application"
    if (Test-Path $trayIconIconPath) { $shortcut.IconLocation = "$trayIconIconPath,0" }
    $shortcut.Save()
    # Set "Run as Administrator"
    $bytes = [System.IO.File]::ReadAllBytes($startMenuShortcut)
    $bytes[0x15] = $bytes[0x15] -bor 0x20
    [System.IO.File]::WriteAllBytes($startMenuShortcut, $bytes)
    Write-LogMessage "   ✅ Start Menu shortcut created" -Level INFO
    
    [System.Runtime.InteropServices.Marshal]::ReleaseComObject($shell) | Out-Null
}
catch {
    Write-LogMessage "   ⚠️ Could not create shortcuts: $($_.Exception.Message)" -Level WARN
}
```

#### ServerMonitorDashboard.ps1 - Add Scheduled Task for Dashboard.Tray

**Location**: `C:\opt\src\DedgePsh\DevTools\InfrastructureTools\ServerMonitorDashboard\ServerMonitorDashboard.ps1`

**ADD** after line 218 (after `Start-OurWinApp -AppName "ServerMonitorDashboard.Tray" -NoInstall`):

```powershell
# ─────────────────────────────────────────────────────────────────────────────
# Configure ServerMonitorDashboard.Tray Startup via Scheduled Task (All Users)
# ─────────────────────────────────────────────────────────────────────────────
Write-LogMessage "📋 Configuring Scheduled Task for ServerMonitorDashboard.Tray..." -Level INFO

$dashboardTrayTaskName = "ServerMonitorDashboard.Tray"
$dashboardTrayPath = "$env:OptPath\DedgeWinApps\ServerMonitorDashboard.Tray\ServerMonitorDashboard.Tray.exe"
$dashboardTrayIconPath = "$env:OptPath\DedgeWinApps\ServerMonitorDashboard.Tray\dedge.ico"

try {
    # Remove old Registry Run key if present (from Install-OurWinApp -AddToStartup)
    $regPath = "HKCU:\Software\Microsoft\Windows\CurrentVersion\Run"
    Remove-ItemProperty -Path $regPath -Name $dashboardTrayTaskName -ErrorAction SilentlyContinue
    Remove-ItemProperty -Path $regPath -Name "ServerMonitorDashboard.Tray" -ErrorAction SilentlyContinue
    
    # Remove existing scheduled task
    Unregister-ScheduledTask -TaskName $dashboardTrayTaskName -Confirm:$false -ErrorAction SilentlyContinue
    
    # Create Scheduled Task for startup at user logon (works for ALL users)
    $action = New-ScheduledTaskAction -Execute $dashboardTrayPath -WorkingDirectory (Split-Path $dashboardTrayPath)
    $trigger = New-ScheduledTaskTrigger -AtLogOn
    $principal = New-ScheduledTaskPrincipal -GroupId "BUILTIN\Users" -RunLevel Highest
    $settings = New-ScheduledTaskSettingsSet `
        -AllowStartIfOnBatteries `
        -DontStopIfGoingOnBatteries `
        -ExecutionTimeLimit (New-TimeSpan -Hours 0) `
        -RestartCount 3 `
        -RestartInterval (New-TimeSpan -Minutes 1)
    
    Register-ScheduledTask -TaskName $dashboardTrayTaskName -Action $action -Trigger $trigger -Principal $principal -Settings $settings -Force | Out-Null
    Write-LogMessage "   ✅ Scheduled Task created (runs at logon for all users)" -Level INFO
}
catch {
    Write-LogMessage "   ❌ Failed to create Scheduled Task: $($_.Exception.Message)" -Level ERROR
}

# ─────────────────────────────────────────────────────────────────────────────
# Create Desktop and Start Menu Shortcuts with Icon
# ─────────────────────────────────────────────────────────────────────────────
Write-LogMessage "🔗 Creating shortcuts for Server Monitor Dashboard..." -Level INFO

try {
    $shell = New-Object -ComObject WScript.Shell
    
    # Desktop shortcut (All Users)
    $desktopPath = [Environment]::GetFolderPath('CommonDesktopDirectory')
    $desktopShortcut = Join-Path $desktopPath "Server Monitor Dashboard.lnk"
    $shortcut = $shell.CreateShortcut($desktopShortcut)
    $shortcut.TargetPath = $dashboardTrayPath
    $shortcut.WorkingDirectory = Split-Path $dashboardTrayPath
    $shortcut.Description = "Server Monitor Dashboard Tray"
    if (Test-Path $dashboardTrayIconPath) { $shortcut.IconLocation = "$dashboardTrayIconPath,0" }
    $shortcut.Save()
    # Set "Run as Administrator"
    $bytes = [System.IO.File]::ReadAllBytes($desktopShortcut)
    $bytes[0x15] = $bytes[0x15] -bor 0x20
    [System.IO.File]::WriteAllBytes($desktopShortcut, $bytes)
    Write-LogMessage "   ✅ Desktop shortcut created" -Level INFO
    
    # Start Menu shortcut (All Users - in ServerMonitor folder)
    $startMenuPath = [Environment]::GetFolderPath('CommonStartMenu')
    $programsPath = Join-Path $startMenuPath "Programs\ServerMonitor"
    if (-not (Test-Path $programsPath)) { New-Item -Path $programsPath -ItemType Directory -Force | Out-Null }
    $startMenuShortcut = Join-Path $programsPath "Server Monitor Dashboard.lnk"
    $shortcut = $shell.CreateShortcut($startMenuShortcut)
    $shortcut.TargetPath = $dashboardTrayPath
    $shortcut.WorkingDirectory = Split-Path $dashboardTrayPath
    $shortcut.Description = "Server Monitor Dashboard Tray"
    if (Test-Path $dashboardTrayIconPath) { $shortcut.IconLocation = "$dashboardTrayIconPath,0" }
    $shortcut.Save()
    # Set "Run as Administrator"
    $bytes = [System.IO.File]::ReadAllBytes($startMenuShortcut)
    $bytes[0x15] = $bytes[0x15] -bor 0x20
    [System.IO.File]::WriteAllBytes($startMenuShortcut, $bytes)
    Write-LogMessage "   ✅ Start Menu shortcut created" -Level INFO
    
    [System.Runtime.InteropServices.Marshal]::ReleaseComObject($shell) | Out-Null
}
catch {
    Write-LogMessage "   ⚠️ Could not create shortcuts: $($_.Exception.Message)" -Level WARN
}
```

#### Also: Remove -AddToStartup from Install-OurWinApp calls

In `ServerMonitorDashboard.ps1`, **REMOVE** the `-AddToStartup` parameter since we're now using Scheduled Tasks:

```powershell
# CHANGE THIS:
Install-OurWinApp -AppName "ServerMonitorDashboard" -DisplayName "Server Monitor Dashboard" -AddToStartup
Install-OurWinApp -AppName "ServerMonitorDashboard.Tray" -DisplayName "Server Monitor Dashboard Tray" -AddToStartup

# TO THIS:
Install-OurWinApp -AppName "ServerMonitorDashboard" -DisplayName "Server Monitor Dashboard"
Install-OurWinApp -AppName "ServerMonitorDashboard.Tray" -DisplayName "Server Monitor Dashboard Tray"
```

---

### schtasks.exe Parameters Explained

The scheduled task is created using `schtasks.exe` instead of PowerShell cmdlets for better compatibility:

| Parameter | Value | Description |
|-----------|-------|-------------|
| `/Create` | - | Create a new scheduled task |
| `/TN` | `ServerMonitorTrayIcon` | Task Name |
| `/TR` | `"path\to\exe"` | Task Run - the executable path (quoted) |
| `/SC` | `ONLOGON` | Schedule type - runs when ANY user logs on |
| `/RL` | `HIGHEST` | Run Level - runs with administrator privileges (no UAC prompt) |
| `/IT` | - | Interactive - runs in user's session (tray icon visible) |
| `/DELAY` | `0000:10` | 10 second delay after logon to allow desktop to fully load |
| `/F` | - | Force - overwrite existing task if present |

**Key benefits of this configuration:**
- ✅ Starts when **any** user logs in (not just the installing user)
- ✅ Runs with **administrator** privileges (no UAC prompt)
- ✅ Runs **interactively** (tray icon appears in notification area)
- ✅ 10-second delay ensures desktop is ready before app starts

---

### Important: GUI Apps Cannot Run Without a User Session

The TrayIcon is a GUI application that displays in the system tray. It **requires an interactive user session** to run.

| Scenario | TrayIcon Starts? | Trigger Files Work? |
|----------|------------------|---------------------|
| User logs in (Registry Run) | ✅ Yes (that user only) | ✅ Yes |
| User logs in (Scheduled Task) | ✅ Yes (any user) | ✅ Yes |
| Server boots, no login | ❌ No | ❌ No |
| RDP session disconnected | ✅ Keeps running | ✅ Yes |

**For truly unattended operation**, move the trigger file monitoring into the ServerMonitor Windows Service.

### Option 3: Group Policy Logon Script

1. Create GPO: `Computer Configuration > Policies > Windows Settings > Scripts > Startup`
2. Add PowerShell script from network share
3. Link GPO to target server OUs

**Script location**: `\\domain\NETLOGON\ServerMonitor\Install-ServerMonitor-Silent.ps1`

### Option 4: Scheduled Task Pulling from Network Share

Create a scheduled task on each server that checks for updates:

```powershell
# Run once on each server to set up auto-update check
$taskName = "ServerMonitor_AutoUpdate"
$scriptContent = @'
$networkVersion = "C:\opt\src\DedgeSrc\DedgeSystemTools\Folders\DedgeCommon\Software\DedgeWinApps\ServerMonitor\ServerMonitor.exe"
$localVersion = "$env:OptPath\DedgeWinApps\ServerMonitor\ServerMonitor.exe"

if (Test-Path $networkVersion) {
    $networkVer = [System.Diagnostics.FileVersionInfo]::GetVersionInfo($networkVersion).FileVersion
    $localVer = if (Test-Path $localVersion) { 
        [System.Diagnostics.FileVersionInfo]::GetVersionInfo($localVersion).FileVersion 
    } else { "0.0.0" }
    
    if ([version]$networkVer -gt [version]$localVer) {
        & "C:\opt\src\DedgeSrc\DedgeSystemTools\Folders\DedgeCommon\Software\Scripts\Install-ServerMonitor-Silent.ps1"
    }
}
'@

$scriptPath = "$env:OptPath\DedgeWinApps\ServerMonitor\Check-Updates.ps1"
$scriptContent | Out-File -FilePath $scriptPath -Force

$action = New-ScheduledTaskAction -Execute "PowerShell.exe" -Argument "-NoProfile -ExecutionPolicy Bypass -File `"$scriptPath`""
$trigger = New-ScheduledTaskTrigger -Daily -At "03:00"
$principal = New-ScheduledTaskPrincipal -UserId "SYSTEM" -LogonType ServiceAccount -RunLevel Highest
$settings = New-ScheduledTaskSettingsSet -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries

Register-ScheduledTask -TaskName $taskName -Action $action -Trigger $trigger -Principal $principal -Settings $settings -Force
```

### Option 5: RDP + Clipboard Script Paste

For quick deployment to a few servers:

1. Copy the install command to clipboard
2. RDP to each server
3. Open elevated PowerShell
4. Paste and run

```powershell
# One-liner to copy to clipboard and paste in each RDP session:
Set-ExecutionPolicy Bypass -Scope Process -Force; & "C:\opt\src\DedgeSrc\DedgeSystemTools\Folders\DedgeCommon\Software\Scripts\Install-ServerMonitor-Silent.ps1"
```

### Option 6: PsExec (If Available)

If PsExec is allowed but WinRM is not:

```batch
:: Run from your workstation (requires admin share access)
psexec \\server1 -s -h powershell.exe -NoProfile -ExecutionPolicy Bypass -File "\\share\Install-ServerMonitor-Silent.ps1"
```

> **Note**: PsExec uses SMB admin shares ($ADMIN), not WinRM.

---

## Deployment Comparison

| Method | Requires | Best For |
|--------|----------|----------|
| Network Share + Manual | RDP access | Few servers, one-time setup |
| Trigger File | File share access | Regular updates to existing installs |
| GPO Logon Script | AD GPO access | Large-scale, policy-managed |
| Scheduled Task | Initial setup once | Automated daily updates |
| RDP + Paste | RDP access | Quick ad-hoc deployment |
| PsExec | PsExec + admin shares | Batch deployment without WinRM |

---

## Automatic Update Architecture

### Overview

The ServerMonitor system uses a **dual-layer auto-update mechanism** to ensure updates work both when users are logged in and when servers are running unattended:

| Layer | Component | When Active | How It Works |
|-------|-----------|-------------|--------------|
| **Service Layer** | `ReinstallTriggerService` | Always (service is running) | Polls for trigger files, launches install script |
| **Tray Layer** | `FileSystemWatcher` in tray apps | When user is logged in | Real-time detection of trigger files |

### Trigger Files

| Trigger File | Purpose | Components That Watch |
|--------------|---------|----------------------|
| `ReinstallServerMonitor.txt` | Agent update | ServerMonitor service + ServerMonitorTrayIcon |
| `ReinstallServerMonitorDashboard.txt` | Dashboard update | ServerMonitorDashboard service + Dashboard.Tray |
| `ReinstallServerMonitor_HOSTNAME.txt` | Machine-specific agent update | Same as above (higher priority) |
| `ReinstallServerMonitorDashboard_HOSTNAME.txt` | Machine-specific dashboard update | Same as above (higher priority) |

### How It Works

```
┌─────────────────────────────────────────────────────────────────────────────┐
│ Build-And-Publish.ps1                                                        │
│  1. Builds all projects                                                      │
│  2. Increments version                                                       │
│  3. Publishes to network share                                              │
│  4. Creates trigger files:                                                   │
│     - ReinstallServerMonitor.txt (Version=1.2.345)                          │
│     - ReinstallServerMonitorDashboard.txt (Version=1.2.345)                 │
└─────────────────────────────────────────────────────────────────────────────┘
                                    │
                                    ▼
┌─────────────────────────────────────────────────────────────────────────────┐
│ On Each Server                                                               │
│                                                                              │
│  ┌──────────────────────────────────────────────────────────────────────┐  │
│  │ Windows Service (ServerMonitor / ServerMonitorDashboard)              │  │
│  │  - ReinstallTriggerService (BackgroundService)                        │  │
│  │  - Polls trigger file every 10 seconds                                │  │
│  │  - Compares version in trigger file vs current version                │  │
│  │  - If newer: launches PowerShell install script (detached)            │  │
│  │  - Install script stops service, updates, restarts                    │  │
│  │  ✅ Works even when NO user is logged in                              │  │
│  └──────────────────────────────────────────────────────────────────────┘  │
│                                                                              │
│  ┌──────────────────────────────────────────────────────────────────────┐  │
│  │ Tray Application (when user is logged in)                             │  │
│  │  - FileSystemWatcher for real-time detection                          │  │
│  │  - Shows balloon notification "Update available"                      │  │
│  │  - Launches PowerShell install script (detached)                      │  │
│  │  - Exits so it can be updated                                         │  │
│  │  - Install script restarts tray app when done                         │  │
│  │  ✅ Provides visual feedback to logged-in users                       │  │
│  └──────────────────────────────────────────────────────────────────────┘  │
└─────────────────────────────────────────────────────────────────────────────┘
```

### Key Design Decisions

1. **Detached Process Launch**
   - Install script MUST run as a completely independent process
   - Uses `UseShellExecute = true` and `CreateNoWindow = true`
   - Service/tray app does NOT wait for script to complete
   - Prevents deadlock (script tries to stop calling process)

2. **Version Comparison**
   - Both service and tray read `Version=x.y.z` from trigger file
   - Compare against current assembly version
   - Skip update if already on same version

3. **Cooldown Period**
   - 5-minute cooldown after processing a trigger
   - Prevents rapid re-triggering

4. **Machine-Specific Triggers**
   - `ReinstallServerMonitor_HOSTNAME.txt` takes priority over global trigger
   - Allows targeting specific servers for testing

### Code Locations

| Component | File |
|-----------|------|
| Agent ReinstallTriggerService | `ServerMonitorAgent/src/ServerMonitor/Services/ReinstallTriggerService.cs` |
| Dashboard ReinstallTriggerService | `ServerMonitorDashboard/src/ServerMonitorDashboard/Services/ReinstallTriggerService.cs` |
| Agent Tray FileSystemWatcher | `ServerMonitorTrayIcon/src/ServerMonitorTrayIcon/TrayIconApplicationContext.cs` |
| Dashboard Tray FileSystemWatcher | `ServerMonitorDashboard/src/ServerMonitorDashboard.Tray/DashboardTrayContext.cs` |
| Trigger File Creation | `Build-And-Publish.ps1` |

---

## Summary

| Requirement | Solution |
|-------------|----------|
| No console prompts | Use `-Force`, `-Confirm:$false`, `-ErrorAction SilentlyContinue` |
| Run as admin | Self-elevating script or Scheduled Task with `RunLevel Highest` |
| Desktop icons | `WScript.Shell` COM object to create `.lnk` files |
| Start Menu icons | Same as desktop, but to `CommonStartMenu\Programs\` folder |
| Auto-start tray app | `schtasks /SC ONLOGON /RL HIGHEST /IT /DELAY 0000:10` |
| Silent .NET install | `/install /quiet /norestart` flags |
| Auto-update without login | Service-based `ReinstallTriggerService` monitors trigger files |
| Auto-update with login | Tray app `FileSystemWatcher` + balloon notifications |

---

*Document created: 2026-01-27*
*Last updated: 2026-01-27 - Added auto-update architecture section*
*Related to: ServerMonitor Installation*
