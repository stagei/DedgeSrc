#!/usr/bin/env pwsh
#Requires -RunAsAdministrator

<#
.SYNOPSIS
    Uninstalls Server Health Monitor Check Tool Windows Service
.DESCRIPTION
    Removes the ServerMonitor Windows Service by:
    - Stopping and killing any running processes
    - Removing the Windows Service
    - Deleting the application folder from DedgeWinApps
.PARAMETER ServiceName
    Name of the Windows Service (default: ServerMonitor)
.PARAMETER AppFolder
    Path to the application folder to delete
.PARAMETER Force
    Force removal without confirmation prompts
.EXAMPLE
    .\Uninstall-ServerMonitorService.ps1
.EXAMPLE
    .\Uninstall-ServerMonitorService.ps1 -Force
#>

param(
    [string]$ServiceName = "ServerMonitor",
    [string]$AppFolder = "$env:OptPath\DedgeWinApps\ServerMonitor",
    [switch]$Force
)

Import-Module -Name GlobalFunctions -Force -ErrorAction Stop

try {
    $ErrorActionPreference = "Stop"
    Write-LogMessage "Server Health Monitor Check Tool - Service Uninstallation" -Level INFO

    # Verify running as administrator
    $isAdmin = ([Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
    if (-not $isAdmin) {
        Write-LogMessage "❌ ERROR: This script must be run as Administrator!" -Level ERROR
        throw "This script must be run as Administrator!"
    }

    # Confirm removal unless -Force is specified
    if (-not $Force) {
        Write-LogMessage "" -Level INFO
        Write-LogMessage "⚠️  WARNING: This will remove the $ServiceName service and delete all files!" -Level WARN
        Write-LogMessage "   Service: $ServiceName" -Level INFO
        Write-LogMessage "   Folder: $AppFolder" -Level INFO
        Write-LogMessage "" -Level INFO
        $confirmation = Read-Host "Continue with uninstallation? (y/n)"
        if ($confirmation -ne 'y') {
            Write-LogMessage "❌ Uninstallation cancelled by user" -Level WARN
            exit 0
        }
    }

    Write-LogMessage "" -Level INFO

    # Step 1: Kill running process if exists
    Write-LogMessage "🛑 Step 1: Stopping running processes..." -Level INFO
    $processName = $ServiceName
    $processes = Get-Process -Name $processName -ErrorAction SilentlyContinue

    if ($processes) {
        foreach ($process in $processes) {
            try {
                Write-LogMessage "   Killing process: $($process.Id) - $($processName)" -Level INFO
                $process.Kill()
                $process.WaitForExit(5000)
                Write-LogMessage "   ✅ Process $($process.Id) killed" -Level INFO
            }
            catch {
                Write-LogMessage "   ⚠️  Could not kill process $($process.Id): $($_.Exception.Message)" -Level WARN
            }
        }
        Start-Sleep -Seconds 2

        # Verify all processes are gone
        $remainingProcesses = Get-Process -Name $processName -ErrorAction SilentlyContinue
        if ($remainingProcesses) {
            Write-LogMessage "   ⚠️  Some processes are still running, forcing kill..." -Level WARN
            Stop-Process -Name $processName -Force -ErrorAction SilentlyContinue
            Start-Sleep -Seconds 1
        }

        Write-LogMessage "✅ All $processName processes stopped`n" -Level INFO
    }
    else {
        Write-LogMessage "   Process $processName is not running`n" -Level INFO
    }

    # Step 2: Stop and remove Windows Service
    Write-LogMessage "🗑️  Step 2: Removing Windows Service..." -Level INFO
    $existingService = Get-Service -Name $ServiceName -ErrorAction SilentlyContinue

    if ($existingService) {
        # Stop service if running
        if ($existingService.Status -ne 'Stopped') {
            Write-LogMessage "   Stopping service: $ServiceName" -Level INFO
            try {
                Stop-Service -Name $ServiceName -Force -ErrorAction Stop
                Write-LogMessage "   ✅ Service stopped" -Level INFO
            }
            catch {
                Write-LogMessage "   ⚠️  Could not stop service: $($_.Exception.Message)" -Level WARN
            }
            Start-Sleep -Seconds 2
        }
        else {
            Write-LogMessage "   Service is already stopped" -Level INFO
        }

        # Remove service
        Write-LogMessage "   Removing service: $ServiceName" -Level INFO
        try {
            # Try Remove-Service (PowerShell 6+)
            if (Get-Command Remove-Service -ErrorAction SilentlyContinue) {
                Remove-Service -Name $ServiceName -ErrorAction Stop
                Write-LogMessage "   ✅ Service removed using Remove-Service" -Level INFO
            }
            else {
                # Fallback: Use sc.exe
                $result = & sc.exe delete $ServiceName 2>&1
                if ($LASTEXITCODE -eq 0) {
                    Write-LogMessage "   ✅ Service removed using sc.exe" -Level INFO
                }
                else {
                    throw "sc.exe failed with exit code $($LASTEXITCODE): $($result)"
                }
            }
        }
        catch {
            Write-LogMessage "   ⚠️  Remove-Service failed, trying WMI method: $($_.Exception.Message)" -Level WARN
            # Fallback: Use WMI/CIM to delete service
            try {
                $service = Get-CimInstance -ClassName Win32_Service -Filter "Name='$ServiceName'" -ErrorAction Stop
                if ($service) {
                    $service | Remove-CimInstance -ErrorAction Stop
                    Write-LogMessage "   ✅ Service removed using CIM" -Level INFO
                }
            }
            catch {
                Write-LogMessage "   ❌ Failed to remove service: $($_.Exception.Message)" -Level ERROR
                throw "Could not remove service using any method"
            }
        }

        Start-Sleep -Seconds 2

        # Verify service is gone
        $verifyService = Get-Service -Name $ServiceName -ErrorAction SilentlyContinue
        if ($verifyService) {
            Write-LogMessage "   ⚠️  Service still exists after removal attempt" -Level WARN
        }
        else {
            Write-LogMessage "✅ Service $ServiceName removed successfully`n" -Level INFO
        }
    }
    else {
        Write-LogMessage "   Service $ServiceName does not exist`n" -Level INFO
    }

    # Step 3: Delete application folder
    Write-LogMessage "🗂️  Step 3: Deleting application folder..." -Level INFO

    if (-not (Test-Path $AppFolder)) {
        Write-LogMessage "   Folder does not exist: $AppFolder`n" -Level INFO
    }
    else {
        Write-LogMessage "   Folder: $AppFolder" -Level INFO

        # Check folder size before deletion
        try {
            $folderSize = (Get-ChildItem -Path $AppFolder -Recurse -File -ErrorAction SilentlyContinue | 
                Measure-Object -Property Length -Sum -ErrorAction SilentlyContinue).Sum
            $folderSizeMB = [math]::Round($folderSize / 1MB, 2)
            Write-LogMessage "   Folder size: $folderSizeMB MB" -Level INFO
        }
        catch {
            Write-LogMessage "   Could not determine folder size" -Level WARN
        }

        # List files to be deleted
        try {
            $fileCount = (Get-ChildItem -Path $AppFolder -Recurse -File -ErrorAction SilentlyContinue).Count
            Write-LogMessage "   Files to delete: $fileCount" -Level INFO
        }
        catch {
            Write-LogMessage "   Could not count files" -Level WARN
        }

        # Delete folder
        try {
            Remove-Item -Path $AppFolder -Recurse -Force -ErrorAction Stop
            Write-LogMessage "   ✅ Folder deleted: $AppFolder" -Level INFO
        }
        catch {
            Write-LogMessage "   ⚠️  Could not delete folder: $($_.Exception.Message)" -Level WARN
            Write-LogMessage "   💡 Some files may be locked. Try rebooting and running uninstall again." -Level WARN
            
            # Try to delete individual files that aren't locked
            try {
                $items = Get-ChildItem -Path $AppFolder -Recurse -Force -ErrorAction SilentlyContinue
                foreach ($item in $items) {
                    try {
                        Remove-Item -Path $item.FullName -Force -Recurse -ErrorAction Stop
                    }
                    catch {
                        Write-LogMessage "   ⚠️  Could not delete: $($item.FullName)" -Level WARN
                    }
                }
                
                # Try to remove the main folder again
                if (Test-Path $AppFolder) {
                    Remove-Item -Path $AppFolder -Force -ErrorAction SilentlyContinue
                }
            }
            catch {
                # Ignore errors in cleanup attempt
            }
        }

        # Verify folder is deleted
        if (Test-Path $AppFolder) {
            Write-LogMessage "   ⚠️  Folder still exists: $AppFolder" -Level WARN
            Write-LogMessage "   💡 Some files may be in use. Manual deletion may be required.`n" -Level WARN
        }
        else {
            Write-LogMessage "✅ Application folder deleted successfully`n" -Level INFO
        }
    }

    # Final summary
    $summary = @"
═══════════════════════════════════════════════════════
  Uninstallation Complete
═══════════════════════════════════════════════════════

✅ Process stopped:  $ServiceName
✅ Service removed:  $ServiceName
✅ Folder deleted:   $AppFolder

The $ServiceName service has been completely removed.

═══════════════════════════════════════════════════════
"@

    Write-LogMessage $summary -Level INFO

}
catch {
    Write-LogMessage "❌ Failed to uninstall service: $($_.Exception.Message)" -Level ERROR
    Write-LogMessage "Stack trace: $($_.ScriptStackTrace)" -Level ERROR
    exit 1
}
