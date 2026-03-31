#!/usr/bin/env pwsh
#Requires -Version 7.0

<#
.SYNOPSIS
    Fix-WallpaperPolicy - Removes registry policies that block wallpaper changes.

.DESCRIPTION
    Removes registry entries set by Group Policy or Intune/MDM that prevent users
    from changing the desktop background in Windows 11 Settings.

    Affected registry values under HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\Explorer:
      - NoActiveDesktop       : Disables Active Desktop entirely
      - NoActiveDesktopChanges: Blocks all wallpaper/desktop background changes

    After removal, Explorer is restarted so the changes take effect immediately
    without requiring a logout.

.PARAMETER NoRestartExplorer
    Skip restarting Explorer after removing the policy values.

.PARAMETER CheckOnly
    Report current state without making any changes.

.EXAMPLE
    .\Fix-WallpaperPolicy.ps1
    # Removes blocking policies and restarts Explorer

.EXAMPLE
    .\Fix-WallpaperPolicy.ps1 -CheckOnly
    # Shows current state without making changes

.EXAMPLE
    .\Fix-WallpaperPolicy.ps1 -NoRestartExplorer
    # Removes policies but does not restart Explorer

.NOTES
    Author: Geir Helge Starholm, www.dEdge.no
    Version: 1.0

    NOTE: Values removed by this script may be re-applied by Intune/MDM on the
    next policy sync cycle. If that happens, the restriction must be lifted from
    the Intune portal (Devices > Configuration Profiles).
#>

[CmdletBinding()]
param(
    [switch]$NoRestartExplorer,
    [switch]$CheckOnly
)

Import-Module GlobalFunctions -Force

#region Constants

$ExplorerPolicyPath = "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\Explorer"

$WallpaperBlockingValues = @(
    'NoActiveDesktop',
    'NoActiveDesktopChanges'
)

$AllPolicyPaths = @(
    "HKCU:\Software\Microsoft\Windows\CurrentVersion\Policies\System",
    "HKCU:\Software\Microsoft\Windows\CurrentVersion\Policies\ActiveDesktop",
    "HKCU:\Software\Policies\Microsoft\Windows\Personalization",
    "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\System",
    "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\Explorer",
    "HKLM:\SOFTWARE\Policies\Microsoft\Windows\Personalization",
    "HKLM:\SOFTWARE\Microsoft\PolicyManager\current\device\Personalization"
)

$WallpaperValueNames = @(
    'NoChangingWallPaper',
    'NoActiveDesktop',
    'NoActiveDesktopChanges',
    'PreventChangingWallPaper',
    'NoDispBackgroundPage'
)

#endregion

#region Helper Functions

function Add-Win32Broadcast {
    Add-Type -TypeDefinition @"
using System;
using System.Runtime.InteropServices;
public class Win32WallpaperFix {
    [DllImport("user32.dll", CharSet = CharSet.Auto)]
    public static extern IntPtr SendMessageTimeout(
        IntPtr hWnd, uint Msg, IntPtr wParam, string lParam,
        uint fuFlags, uint uTimeout, out IntPtr lpdwResult);
    [DllImport("user32.dll")]
    public static extern IntPtr SendMessageTimeout(
        IntPtr hWnd, uint Msg, IntPtr wParam, IntPtr lParam,
        uint fuFlags, uint uTimeout, out IntPtr lpdwResult);
}
"@ -ErrorAction SilentlyContinue
}

function Send-PolicyChangeBroadcast {
    $broadcast = [IntPtr]0xFFFF
    $result = [IntPtr]::Zero
    [Win32WallpaperFix]::SendMessageTimeout($broadcast, 0x001A, [IntPtr]::Zero, "Policy",            0x0002, 5000, [ref]$result) | Out-Null
    [Win32WallpaperFix]::SendMessageTimeout($broadcast, 0x001A, [IntPtr]::Zero, "ImmersiveColorSet", 0x0002, 5000, [ref]$result) | Out-Null
    [Win32WallpaperFix]::SendMessageTimeout($broadcast, 0x031A, [IntPtr]::Zero, [IntPtr]::Zero,      0x0002, 5000, [ref]$result) | Out-Null
    Write-LogMessage "Policy change broadcast sent to all windows" -Level INFO
}

function Get-WallpaperPolicyReport {
    Write-LogMessage "Scanning for wallpaper-blocking policy values..." -Level INFO
    $found = [System.Collections.Generic.List[PSCustomObject]]::new()

    foreach ($path in $AllPolicyPaths) {
        if (-not (Test-Path $path)) { continue }

        $props = Get-ItemProperty $path -ErrorAction SilentlyContinue
        foreach ($valueName in $WallpaperValueNames) {
            $val = $props.$valueName
            if ($null -ne $val) {
                $found.Add([PSCustomObject]@{
                    Path  = $path
                    Name  = $valueName
                    Value = $val
                })
            }
        }
    }

    return $found
}

function Invoke-RestartExplorer {
    Write-LogMessage "Restarting Explorer to apply policy changes..." -Level INFO
    Stop-Process -Name explorer -Force -ErrorAction SilentlyContinue
    Start-Sleep -Seconds 3
    Start-Process explorer
    Start-Sleep -Seconds 2
    $explorerPid = (Get-Process explorer -ErrorAction SilentlyContinue | Select-Object -First 1).Id
    if ($explorerPid) {
        Write-LogMessage "Explorer restarted (PID: $($explorerPid))" -Level INFO
    } else {
        Write-LogMessage "Explorer PID not yet detected - may take a moment to start" -Level WARN
    }
}

#endregion

#region Main

try {
    $ErrorActionPreference = "Stop"

    Write-LogMessage "Fix-WallpaperPolicy starting" -Level INFO

    Add-Win32Broadcast

    # --- CHECK MODE ---
    if ($CheckOnly) {
        Write-LogMessage "CHECK ONLY mode - no changes will be made" -Level INFO
        $report = Get-WallpaperPolicyReport

        if ($report.Count -eq 0) {
            Write-LogMessage "No wallpaper-blocking policies found" -Level INFO
        } else {
            Write-LogMessage "Found $($report.Count) blocking value(s):" -Level WARN
            foreach ($item in $report) {
                Write-LogMessage "  [$($item.Name) = $($item.Value)] in $($item.Path)" -Level WARN
            }
        }
        exit 0
    }

    # --- FIX MODE ---
    $removedCount = 0
    $skippedCount = 0

    Write-LogMessage "Checking Explorer policy key: $($ExplorerPolicyPath)" -Level INFO

    if (-not (Test-Path $ExplorerPolicyPath)) {
        Write-LogMessage "Explorer policy key does not exist - nothing to remove" -Level INFO
    } else {
        foreach ($valueName in $WallpaperBlockingValues) {
            $current = (Get-ItemProperty $ExplorerPolicyPath -ErrorAction SilentlyContinue).$valueName
            if ($null -ne $current) {
                try {
                    Remove-ItemProperty -Path $ExplorerPolicyPath -Name $valueName -Force -ErrorAction Stop
                    Write-LogMessage "Removed: $($valueName) (was: $($current))" -Level INFO
                    $removedCount++
                } catch {
                    Write-LogMessage "Failed to remove $($valueName): $($_.Exception.Message)" -Level ERROR
                }
            } else {
                Write-LogMessage "Not present (already clean): $($valueName)" -Level INFO
                $skippedCount++
            }
        }
    }

    # Also scan and report on any other blocking values in other paths
    $otherBlocking = Get-WallpaperPolicyReport
    if ($otherBlocking.Count -gt 0) {
        Write-LogMessage "Additional blocking values found (not auto-removed - may be MDM-managed):" -Level WARN
        foreach ($item in $otherBlocking) {
            Write-LogMessage "  [$($item.Name) = $($item.Value)] in $($item.Path)" -Level WARN
        }
    }

    Send-PolicyChangeBroadcast

    if (-not $NoRestartExplorer) {
        Invoke-RestartExplorer
    } else {
        Write-LogMessage "Skipping Explorer restart (-NoRestartExplorer specified)" -Level INFO
    }

    if ($removedCount -gt 0) {
        Write-LogMessage "Done. Removed $($removedCount) blocking value(s). Go to Settings > Personalization > Background to change your wallpaper." -Level INFO
    } else {
        Write-LogMessage "Done. No blocking values were present - wallpaper should already be changeable." -Level INFO
    }

    if ($otherBlocking.Count -gt 0) {
        Write-LogMessage "NOTE: Additional MDM-managed values were detected above. If wallpaper is still blocked, the restriction must be lifted from the Intune/MDM portal." -Level WARN
    }
}
catch {
    Write-LogMessage "Fix-WallpaperPolicy failed: $($_.Exception.Message)" -Level ERROR
    exit 1
}

#endregion
