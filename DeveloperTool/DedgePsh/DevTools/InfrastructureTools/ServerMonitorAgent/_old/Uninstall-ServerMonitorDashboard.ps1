#!/usr/bin/env pwsh
#Requires -RunAsAdministrator

<#
.SYNOPSIS
    Uninstalls Server Monitor Dashboard applications
.DESCRIPTION
    Removes the ServerMonitor Dashboard by:
    - Stopping and killing any running processes
    - Removing from Windows startup
    - Removing firewall rules for port 8998
    - Deleting the application folders from DedgeWinApps
    
    Applications removed:
    - ServerMonitorDashboard (Web API/UI)
    - ServerMonitorDashboard.Tray (System tray icon)
.PARAMETER Force
    Force removal without confirmation prompts
.EXAMPLE
    .\Uninstall-ServerMonitorDashboard.ps1
.EXAMPLE
    .\Uninstall-ServerMonitorDashboard.ps1 -Force
#>

param(
    [switch]$Force
)

Import-Module -Name GlobalFunctions -Force -ErrorAction Stop

try {
    $ErrorActionPreference = "Stop"
    Write-LogMessage "Server Monitor Dashboard - Uninstallation" -Level INFO

    # Verify running as administrator
    $isAdmin = ([Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
    if (-not $isAdmin) {
        Write-LogMessage "❌ ERROR: This script must be run as Administrator!" -Level ERROR
        throw "This script must be run as Administrator!"
    }

    # Define applications to remove
    $appsToRemove = @(
        @{ 
            Name = "ServerMonitorDashboard"
            DisplayName = "Server Monitor Dashboard"
            Folder = "$env:OptPath\DedgeWinApps\ServerMonitorDashboard"
        }
        @{ 
            Name = "ServerMonitorDashboard.Tray"
            DisplayName = "Server Monitor Dashboard Tray"
            Folder = "$env:OptPath\DedgeWinApps\ServerMonitorDashboard.Tray"
        }
    )

    # Confirm removal unless -Force is specified
    if (-not $Force) {
        Write-LogMessage "" -Level INFO
        Write-LogMessage "⚠️  WARNING: This will remove the Dashboard applications and delete all files!" -Level WARN
        Write-LogMessage "" -Level INFO
        foreach ($app in $appsToRemove) {
            Write-LogMessage "   • $($app.DisplayName)" -Level INFO
            Write-LogMessage "     Folder: $($app.Folder)" -Level INFO
        }
        Write-LogMessage "" -Level INFO
        $confirmation = Read-Host "Continue with uninstallation? (y/n)"
        if ($confirmation -ne 'y') {
            Write-LogMessage "❌ Uninstallation cancelled by user" -Level WARN
            exit 0
        }
    }

    Write-LogMessage "" -Level INFO

    # ─────────────────────────────────────────────────────────────────────────────
    # Step 1: Kill running processes
    # ─────────────────────────────────────────────────────────────────────────────
    Write-LogMessage "🛑 Step 1: Stopping running processes..." -Level INFO
    
    $processNames = @("ServerMonitorDashboard.Tray", "ServerMonitorDashboard")
    foreach ($processName in $processNames) {
        $processes = Get-Process -Name $processName -ErrorAction SilentlyContinue
        
        if ($processes) {
            foreach ($process in $processes) {
                try {
                    Write-LogMessage "   Killing process: $($process.Id) - $processName" -Level INFO
                    $process.Kill()
                    $process.WaitForExit(5000)
                    Write-LogMessage "   ✅ Process $($process.Id) killed" -Level INFO
                }
                catch {
                    Write-LogMessage "   ⚠️  Could not kill process $($process.Id): $($_.Exception.Message)" -Level WARN
                }
            }
        }
        else {
            Write-LogMessage "   Process $processName is not running" -Level INFO
        }
    }
    
    Start-Sleep -Seconds 2
    
    # Verify all processes are gone
    foreach ($processName in $processNames) {
        $remainingProcesses = Get-Process -Name $processName -ErrorAction SilentlyContinue
        if ($remainingProcesses) {
            Write-LogMessage "   ⚠️  Some $processName processes still running, forcing kill..." -Level WARN
            Stop-Process -Name $processName -Force -ErrorAction SilentlyContinue
        }
    }
    
    Write-LogMessage "✅ All Dashboard processes stopped`n" -Level INFO

    # ─────────────────────────────────────────────────────────────────────────────
    # Step 2: Remove from Windows startup
    # ─────────────────────────────────────────────────────────────────────────────
    Write-LogMessage "🔧 Step 2: Removing from Windows startup..." -Level INFO
    
    $startupRegPath = "HKCU:\Software\Microsoft\Windows\CurrentVersion\Run"
    $startupNamesToRemove = @("Server Monitor Dashboard", "Server Monitor Dashboard Tray", "ServerMonitorDashboard", "ServerMonitorDashboard.Tray")
    
    foreach ($startupName in $startupNamesToRemove) {
        try {
            $existingValue = Get-ItemProperty -Path $startupRegPath -Name $startupName -ErrorAction SilentlyContinue
            if ($existingValue) {
                Remove-ItemProperty -Path $startupRegPath -Name $startupName -ErrorAction Stop
                Write-LogMessage "   ✅ Removed from startup: $startupName" -Level INFO
            }
        }
        catch {
            # Ignore if doesn't exist
        }
    }
    
    Write-LogMessage "✅ Startup entries removed`n" -Level INFO

    # ─────────────────────────────────────────────────────────────────────────────
    # Step 3: Remove firewall rules
    # ─────────────────────────────────────────────────────────────────────────────
    Write-LogMessage "🔥 Step 3: Removing firewall rules for port 8998..." -Level INFO
    
    $firewallRuleNames = @(
        "ServerMonitorDashboard_Api_Inbound",
        "ServerMonitorDashboard_Api_Outbound"
    )
    
    foreach ($ruleName in $firewallRuleNames) {
        try {
            $existingRule = Get-NetFirewallRule -DisplayName $ruleName -ErrorAction SilentlyContinue
            if ($existingRule) {
                Remove-NetFirewallRule -DisplayName $ruleName -ErrorAction Stop
                Write-LogMessage "   ✅ Removed firewall rule: $ruleName" -Level INFO
            }
            else {
                Write-LogMessage "   Firewall rule not found: $ruleName" -Level INFO
            }
        }
        catch {
            Write-LogMessage "   ⚠️  Could not remove firewall rule $($ruleName): $($_.Exception.Message)" -Level WARN
        }
    }
    
    Write-LogMessage "✅ Firewall rules removed`n" -Level INFO

    # ─────────────────────────────────────────────────────────────────────────────
    # Step 4: Delete application folders
    # ─────────────────────────────────────────────────────────────────────────────
    Write-LogMessage "🗂️  Step 4: Deleting application folders..." -Level INFO
    
    foreach ($app in $appsToRemove) {
        $appFolder = $app.Folder
        
        if (-not (Test-Path $appFolder)) {
            Write-LogMessage "   Folder does not exist: $appFolder" -Level INFO
            continue
        }
        
        Write-LogMessage "   Deleting: $appFolder" -Level INFO
        
        # Check folder size before deletion
        try {
            $folderSize = (Get-ChildItem -Path $appFolder -Recurse -File -ErrorAction SilentlyContinue | 
                Measure-Object -Property Length -Sum -ErrorAction SilentlyContinue).Sum
            $folderSizeMB = [math]::Round($folderSize / 1MB, 2)
            Write-LogMessage "      Size: $folderSizeMB MB" -Level INFO
        }
        catch {
            # Ignore size calculation errors
        }
        
        # Delete folder
        try {
            Remove-Item -Path $appFolder -Recurse -Force -ErrorAction Stop
            Write-LogMessage "   ✅ Deleted: $appFolder" -Level INFO
        }
        catch {
            Write-LogMessage "   ⚠️  Could not delete folder: $($_.Exception.Message)" -Level WARN
            Write-LogMessage "      💡 Some files may be locked. Try rebooting and running uninstall again." -Level WARN
            
            # Try to delete individual files that aren't locked
            try {
                Get-ChildItem -Path $appFolder -Recurse -Force -ErrorAction SilentlyContinue | 
                    Remove-Item -Force -Recurse -ErrorAction SilentlyContinue
                
                # Try to remove the main folder again
                if (Test-Path $appFolder) {
                    Remove-Item -Path $appFolder -Force -ErrorAction SilentlyContinue
                }
            }
            catch {
                # Ignore errors in cleanup attempt
            }
        }
        
        # Verify folder is deleted
        if (Test-Path $appFolder) {
            Write-LogMessage "   ⚠️  Folder still exists: $appFolder" -Level WARN
        }
    }
    
    Write-LogMessage "✅ Application folders deleted`n" -Level INFO

    # ─────────────────────────────────────────────────────────────────────────────
    # Step 5: Remove desktop shortcuts
    # ─────────────────────────────────────────────────────────────────────────────
    Write-LogMessage "🖥️  Step 5: Removing desktop shortcuts..." -Level INFO
    
    $desktopPaths = @(
        "$env:USERPROFILE\OneDrive - Dedge AS\Skrivebord",
        "$env:USERPROFILE\Desktop",
        "$env:USERPROFILE\Skrivebord",
        [Environment]::GetFolderPath('Desktop')
    ) | Where-Object { -not [string]::IsNullOrEmpty($_) -and (Test-Path $_ -PathType Container) } | Select-Object -Unique
    
    $shortcutNames = @("Server Monitor Dashboard.lnk", "Server Monitor Dashboard Tray.lnk")
    
    foreach ($desktopPath in $desktopPaths) {
        foreach ($shortcutName in $shortcutNames) {
            $shortcutPath = Join-Path $desktopPath $shortcutName
            if (Test-Path $shortcutPath) {
                try {
                    Remove-Item -Path $shortcutPath -Force -ErrorAction Stop
                    Write-LogMessage "   ✅ Removed shortcut: $shortcutPath" -Level INFO
                }
                catch {
                    Write-LogMessage "   ⚠️  Could not remove shortcut: $($_.Exception.Message)" -Level WARN
                }
            }
        }
    }
    
    Write-LogMessage "✅ Desktop shortcuts removed`n" -Level INFO

    # ─────────────────────────────────────────────────────────────────────────────
    # Step 6: Remove Start Menu shortcuts
    # ─────────────────────────────────────────────────────────────────────────────
    Write-LogMessage "📋 Step 6: Removing Start Menu shortcuts..." -Level INFO
    
    $startMenuPath = Join-Path -Path $env:APPDATA -ChildPath "Microsoft\Windows\Start Menu\Programs"
    
    # Check for shortcuts in Dedge folder
    $startMenuFolders = @(
        (Join-Path $startMenuPath "Dedge"),
        $startMenuPath
    )
    
    foreach ($folder in $startMenuFolders) {
        if (Test-Path $folder) {
            foreach ($shortcutName in $shortcutNames) {
                $shortcutPath = Join-Path $folder $shortcutName
                if (Test-Path $shortcutPath) {
                    try {
                        Remove-Item -Path $shortcutPath -Force -ErrorAction Stop
                        Write-LogMessage "   ✅ Removed: $shortcutPath" -Level INFO
                    }
                    catch {
                        Write-LogMessage "   ⚠️  Could not remove: $($_.Exception.Message)" -Level WARN
                    }
                }
            }
        }
    }
    
    Write-LogMessage "✅ Start Menu shortcuts removed`n" -Level INFO

    # ─────────────────────────────────────────────────────────────────────────────
    # Final summary
    # ─────────────────────────────────────────────────────────────────────────────
    $summary = @"

═══════════════════════════════════════════════════════
  Dashboard Uninstallation Complete
═══════════════════════════════════════════════════════

✅ Processes stopped:
   • ServerMonitorDashboard
   • ServerMonitorDashboard.Tray

✅ Removed from startup

✅ Firewall rules removed (port 8998)

✅ Folders deleted:
   • $env:OptPath\DedgeWinApps\ServerMonitorDashboard
   • $env:OptPath\DedgeWinApps\ServerMonitorDashboard.Tray

✅ Shortcuts removed (Desktop & Start Menu)

The Server Monitor Dashboard has been completely removed.

═══════════════════════════════════════════════════════
"@

    Write-LogMessage $summary -Level INFO

}
catch {
    Write-LogMessage "❌ Failed to uninstall Dashboard: $($_.Exception.Message)" -Level ERROR
    Write-LogMessage "Stack trace: $($_.ScriptStackTrace)" -Level ERROR
    exit 1
}
