#!/usr/bin/env pwsh
#Requires -Version 5.1

<#
.SYNOPSIS
    Legacy-DarkMode - Applies dark theme colors to legacy Windows components.

.DESCRIPTION
    This script modifies Windows registry settings to apply dark mode styling to legacy
    components that don't natively support Windows 11 dark mode, including:
    - MMC snap-ins (Task Scheduler, Event Viewer, Services, etc.)
    - Legacy dialogs and windows
    - System components using classic Win32 controls
    
    The script:
    - Reads color configuration from theme-config.json
    - Backs up current color settings
    - Applies dark mode colors to registry
    - Can revert to original colors

.PARAMETER ConfigFile
    Path to the theme configuration JSON file (default: theme-config.json)

.PARAMETER Revert
    Restores the original color scheme from backup

.PARAMETER ResetToDefault
    Resets to Windows 11 standard light theme (factory defaults)

.PARAMETER NoBackup
    Skip creating a backup of current colors

.PARAMETER NoLogout
    Don't prompt to logout after applying changes

.PARAMETER RestartExplorer
    Restart Explorer.exe to force immediate color refresh (closes and reopens all Explorer windows)

.EXAMPLE
    .\Legacy-DarkMode.ps1
    # Applies dark theme using default config file

.EXAMPLE
    .\Legacy-DarkMode.ps1 -ConfigFile "custom-theme.json"
    # Applies dark theme using custom configuration

.EXAMPLE
    .\Legacy-DarkMode.ps1 -Revert
    # Restores original color scheme from backup

.EXAMPLE
    .\Legacy-DarkMode.ps1 -ResetToDefault
    # Resets to Windows 11 standard light theme colors

.NOTES
    Author: Geir Helge Starholm, www.dEdge.no
    Version: 1.0
    
    IMPORTANT:
    - Changes require logout/login to take full effect
    - A backup of original colors is automatically created
    - Use -Revert to restore original colors
    - Some applications may need to be restarted
    
    LIMITATIONS:
    - Cannot fully theme all MMC components (some use hardcoded colors)
    - Windows 11 modern components are not affected (they use their own theming)
    - Some third-party applications may ignore these settings
#>

[CmdletBinding(DefaultParameterSetName = 'Apply')]
param(
    [Parameter(Mandatory = $false, ParameterSetName = 'Apply')]
    [string]$ConfigFile = "$PSScriptRoot\theme-config.json",
    
    [Parameter(Mandatory = $false, ParameterSetName = 'Revert')]
    [switch]$Revert,
    
    [Parameter(Mandatory = $false, ParameterSetName = 'Reset')]
    [switch]$ResetToDefault,
    
    [Parameter(Mandatory = $false)]
    [switch]$NoBackup,
    
    [Parameter(Mandatory = $false)]
    [switch]$NoLogout,
    
    [Parameter(Mandatory = $false)]
    [switch]$RestartExplorer
)

#region Helper Functions

function ConvertTo-RegistryColor {
    <#
    .SYNOPSIS
        Converts RGB string to Windows registry color format
    #>
    param(
        [Parameter(Mandatory = $true)]
        [string]$RgbString
    )
    
    $parts = $RgbString.Trim() -split '\s+'
    if ($parts.Count -ne 3) {
        throw "Invalid RGB format: $RgbString. Expected 'R G B' format."
    }
    
    $r = [int]$parts[0]
    $g = [int]$parts[1]
    $b = [int]$parts[2]
    
    # Windows registry format is "R G B" as string
    return "$r $g $b"
}

function Backup-CurrentTheme {
    <#
    .SYNOPSIS
        Backs up current Windows color settings
    #>
    param(
        [Parameter(Mandatory = $true)]
        [string]$BackupPath
    )
    
    Write-Host "Creating backup of current theme settings..." -ForegroundColor Cyan
    
    $colorsPath = "HKCU:\Control Panel\Colors"
    $backup = @{
        BackupDate = (Get-Date).ToString("yyyy-MM-dd HH:mm:ss")
        Computer = $env:COMPUTERNAME
        User = $env:USERNAME
        Colors = @{}
    }
    
    # Get all current color values
    $colorKeys = Get-ItemProperty -Path $colorsPath
    foreach ($property in $colorKeys.PSObject.Properties) {
        if ($property.Name -notlike "PS*") {
            $backup.Colors[$property.Name] = $property.Value
        }
    }
    
    # Save backup
    $backup | ConvertTo-Json -Depth 10 | Out-File -FilePath $BackupPath -Encoding UTF8
    Write-Host "✅ Backup saved to: $BackupPath" -ForegroundColor Green
    
    return $backup
}

function Restore-ThemeFromBackup {
    <#
    .SYNOPSIS
        Restores Windows colors from backup file
    #>
    param(
        [Parameter(Mandatory = $true)]
        [string]$BackupPath
    )
    
    if (-not (Test-Path $BackupPath)) {
        Write-Host "❌ Backup file not found: $BackupPath" -ForegroundColor Red
        throw "No backup file found. Cannot revert."
    }
    
    Write-Host "Restoring theme from backup: $BackupPath" -ForegroundColor Cyan
    
    $backup = Get-Content -Path $BackupPath -Raw | ConvertFrom-Json
    $colorsPath = "HKCU:\Control Panel\Colors"
    
    $restoredCount = 0
    foreach ($colorName in $backup.Colors.PSObject.Properties) {
        $name = $colorName.Name
        $value = $colorName.Value
        
        Write-Verbose "  Restoring $name = $value"
        Set-ItemProperty -Path $colorsPath -Name $name -Value $value
        $restoredCount++
    }
    
    Write-Host "✅ Theme restored successfully ($restoredCount colors)" -ForegroundColor Green
    Write-Host "   Backup dated: $($backup.BackupDate)" -ForegroundColor Gray
}

function Reset-ToDefaultTheme {
    <#
    .SYNOPSIS
        Resets Windows colors to factory default Windows 11 light theme
    #>
    Write-Host "Resetting to Windows 11 standard light theme colors..." -ForegroundColor Cyan
    
    # Windows 11 default light theme colors (factory defaults)
    $defaultColors = @{
        "ActiveBorder" = "180 180 180"
        "ActiveTitle" = "0 120 215"
        "AppWorkspace" = "171 171 171"
        "Background" = "0 0 0"
        "ButtonAlternateFace" = "0 0 0"
        "ButtonDkShadow" = "105 105 105"
        "ButtonFace" = "240 240 240"
        "ButtonHilight" = "255 255 255"
        "ButtonLight" = "227 227 227"
        "ButtonShadow" = "160 160 160"
        "ButtonText" = "0 0 0"
        "GradientActiveTitle" = "185 209 234"
        "GradientInactiveTitle" = "215 228 242"
        "GrayText" = "109 109 109"
        "Hilight" = "0 120 215"
        "HilightText" = "255 255 255"
        "HotTrackingColor" = "0 102 204"
        "InactiveBorder" = "244 247 252"
        "InactiveTitle" = "191 205 219"
        "InactiveTitleText" = "0 0 0"
        "InfoText" = "0 0 0"
        "InfoWindow" = "255 255 255"
        "Menu" = "240 240 240"
        "MenuBar" = "240 240 240"
        "MenuHilight" = "0 120 215"
        "MenuText" = "0 0 0"
        "Scrollbar" = "200 200 200"
        "TitleText" = "255 255 255"
        "Window" = "255 255 255"
        "WindowFrame" = "100 100 100"
        "WindowText" = "0 0 0"
    }
    
    $colorsPath = "HKCU:\Control Panel\Colors"
    $appliedCount = 0
    
    foreach ($colorEntry in $defaultColors.GetEnumerator()) {
        $name = $colorEntry.Key
        $value = $colorEntry.Value
        
        Write-Verbose "  Setting $name = $value"
        Set-ItemProperty -Path $colorsPath -Name $name -Value $value
        $appliedCount++
    }
    
    # Also reset modern theme to light mode
    Write-Host "Enabling Windows 11 light mode for apps and system..." -ForegroundColor Cyan
    
    try {
        # Enable light mode for apps
        Set-ItemProperty -Path "HKCU:\Software\Microsoft\Windows\CurrentVersion\Themes\Personalize" `
            -Name "AppsUseLightTheme" -Value 1 -Type DWord -ErrorAction Stop
        
        # Enable light mode for system
        Set-ItemProperty -Path "HKCU:\Software\Microsoft\Windows\CurrentVersion\Themes\Personalize" `
            -Name "SystemUsesLightTheme" -Value 1 -Type DWord -ErrorAction Stop
        
        Write-Host "✅ Modern light mode enabled" -ForegroundColor Green
    }
    catch {
        Write-Host "⚠️  Warning: Failed to enable modern light mode: $($_.Exception.Message)" -ForegroundColor Yellow
    }
    
    Write-Host "✅ Windows 11 default theme restored ($appliedCount colors)" -ForegroundColor Green
}

function Apply-ThemeColors {
    <#
    .SYNOPSIS
        Applies theme colors from configuration to registry
    #>
    param(
        [Parameter(Mandatory = $true)]
        [PSCustomObject]$Config
    )
    
    $colorsPath = "HKCU:\Control Panel\Colors"
    
    Write-Host "Applying theme: $($Config.ThemeName)" -ForegroundColor Cyan
    Write-Host "Description: $($Config.Description)" -ForegroundColor Gray
    
    # Map of config keys to registry value names
    # These registry values control colors for legacy Windows components
    $colorMapping = @{
        # Window and text colors (affects treeviews, listviews, edit controls)
        "Window.Background" = "Window"
        "Window.Text" = "WindowText"
        "Window.Frame" = "WindowFrame"
        
        # Menu colors
        "Menu.Background" = "Menu"
        "Menu.Text" = "MenuText"
        "Menu.Bar" = "MenuBar"
        "MenuHighlight.Background" = "MenuHilight"
        
        # Button and control colors (affects tabs, toolbars, dialogs)
        "ButtonFace.Background" = "ButtonFace"
        "ButtonText.Color" = "ButtonText"
        "ButtonHighlight.Color" = "ButtonHilight"
        "ButtonShadow.Color" = "ButtonShadow"
        "ButtonLight.Color" = "ButtonLight"
        "ButtonDkShadow.Color" = "ButtonDkShadow"
        "ButtonAlternateFace.Color" = "ButtonAlternateFace"
        
        # Title bar colors
        "ActiveTitle.Background" = "ActiveTitle"
        "ActiveTitle.Text" = "TitleText"
        "InactiveTitle.Background" = "InactiveTitle"
        "InactiveTitle.Text" = "InactiveTitleText"
        "GradientActiveTitle.Color" = "GradientActiveTitle"
        "GradientInactiveTitle.Color" = "GradientInactiveTitle"
        
        # Selection and highlight colors
        "GrayText.Color" = "GrayText"
        "Highlight.Background" = "Hilight"
        "Highlight.Text" = "HilightText"
        "HotTrackingColor.Color" = "HotTrackingColor"
        
        # Scrollbar and workspace
        "Scrollbar.Background" = "Scrollbar"
        "AppWorkspace.Background" = "AppWorkspace"
        
        # Tooltip colors
        "InfoWindow.Background" = "InfoWindow"
        "InfoWindow.Text" = "InfoText"
        
        # Border colors
        "ActiveBorder.Color" = "ActiveBorder"
        "InactiveBorder.Color" = "InactiveBorder"
        
        # Desktop background
        "Background.Color" = "Background"
    }
    
    $appliedCount = 0
    
    foreach ($mapping in $colorMapping.GetEnumerator()) {
        $configPath = $mapping.Key
        $regName = $mapping.Value
        
        # Navigate config object
        $parts = $configPath -split '\.'
        $color = $Config.Colors
        
        foreach ($part in $parts) {
            if ($color.PSObject.Properties[$part]) {
                $color = $color.$part
            }
            else {
                Write-Verbose "  Warning: Config path not found: $configPath"
                $color = $null
                break
            }
        }
        
        if ($null -ne $color -and -not [string]::IsNullOrWhiteSpace($color)) {
            try {
                $regColor = ConvertTo-RegistryColor -RgbString $color
                Set-ItemProperty -Path $colorsPath -Name $regName -Value $regColor -ErrorAction Stop
                Write-Verbose "  Applied: $regName = $regColor"
                $appliedCount++
            }
            catch {
                Write-Host "  ⚠️  Failed to set $regName : $($_.Exception.Message)" -ForegroundColor Yellow
            }
        }
    }
    
    Write-Host "✅ Successfully applied $appliedCount color settings" -ForegroundColor Green
}

function Enable-ModernDarkMode {
    <#
    .SYNOPSIS
        Enables modern Windows 11 dark mode for apps and system
    #>
    Write-Host "Enabling Windows 11 dark mode for apps and system..." -ForegroundColor Cyan
    
    try {
        # Enable dark mode for apps
        Set-ItemProperty -Path "HKCU:\Software\Microsoft\Windows\CurrentVersion\Themes\Personalize" `
            -Name "AppsUseLightTheme" -Value 0 -Type DWord -ErrorAction Stop
        
        # Enable dark mode for system
        Set-ItemProperty -Path "HKCU:\Software\Microsoft\Windows\CurrentVersion\Themes\Personalize" `
            -Name "SystemUsesLightTheme" -Value 0 -Type DWord -ErrorAction Stop
        
        Write-Host "✅ Modern dark mode enabled" -ForegroundColor Green
    }
    catch {
        Write-Host "⚠️  Failed to enable modern dark mode: $($_.Exception.Message)" -ForegroundColor Yellow
    }
}

function Update-ExplorerWindows {
    <#
    .SYNOPSIS
        Refreshes Explorer windows and applications to apply new colors
    .DESCRIPTION
        Broadcasts multiple Windows messages to force color refresh:
        * WM_SYSCOLORCHANGE: Notifies apps that system colors changed
        * WM_SETTINGCHANGE: Notifies apps of settings change
        * WM_THEMECHANGED: Notifies apps of theme change
        Optionally restarts Explorer for stubborn applications.
    #>
    param(
        [switch]$RestartExplorer
    )
    
    Write-Host "Refreshing system colors..." -ForegroundColor Cyan
    
    try {
        # Define Win32 API functions for broadcasting messages
        Add-Type -TypeDefinition @"
using System;
using System.Runtime.InteropServices;
public class Win32ColorRefresh {
    public const int HWND_BROADCAST = 0xFFFF;
    public const int WM_SYSCOLORCHANGE = 0x0015;
    public const int WM_SETTINGCHANGE = 0x001A;
    public const int WM_THEMECHANGED = 0x031A;
    public const int SMTO_ABORTIFHUNG = 0x0002;
    
    [DllImport("user32.dll", SetLastError = true, CharSet = CharSet.Auto)]
    public static extern IntPtr SendMessageTimeout(
        IntPtr hWnd, uint Msg, IntPtr wParam, string lParam,
        uint fuFlags, uint uTimeout, out IntPtr lpdwResult);
    
    [DllImport("user32.dll", SetLastError = true)]
    public static extern IntPtr SendMessageTimeout(
        IntPtr hWnd, uint Msg, IntPtr wParam, IntPtr lParam,
        uint fuFlags, uint uTimeout, out IntPtr lpdwResult);
    
    [DllImport("user32.dll")]
    public static extern bool InvalidateRect(IntPtr hWnd, IntPtr lpRect, bool bErase);
    
    [DllImport("user32.dll")]
    public static extern bool UpdateWindow(IntPtr hWnd);
}
"@ -ErrorAction SilentlyContinue
        
        $broadcast = [IntPtr]0xFFFF
        $result = [IntPtr]::Zero
        
        # 1. Broadcast WM_SYSCOLORCHANGE - specifically for system color changes
        Write-Verbose "  Broadcasting WM_SYSCOLORCHANGE..."
        [Win32ColorRefresh]::SendMessageTimeout(
            $broadcast, 
            [Win32ColorRefresh]::WM_SYSCOLORCHANGE,
            [IntPtr]::Zero, 
            [IntPtr]::Zero,
            [Win32ColorRefresh]::SMTO_ABORTIFHUNG, 
            5000, 
            [ref]$result) | Out-Null
        
        # 2. Broadcast WM_SETTINGCHANGE with ImmersiveColorSet
        Write-Verbose "  Broadcasting WM_SETTINGCHANGE (ImmersiveColorSet)..."
        [Win32ColorRefresh]::SendMessageTimeout(
            $broadcast, 
            [Win32ColorRefresh]::WM_SETTINGCHANGE,
            [IntPtr]::Zero, 
            "ImmersiveColorSet",
            [Win32ColorRefresh]::SMTO_ABORTIFHUNG, 
            5000, 
            [ref]$result) | Out-Null
        
        # 3. Broadcast WM_SETTINGCHANGE with Environment
        Write-Verbose "  Broadcasting WM_SETTINGCHANGE (Environment)..."
        [Win32ColorRefresh]::SendMessageTimeout(
            $broadcast, 
            [Win32ColorRefresh]::WM_SETTINGCHANGE,
            [IntPtr]::Zero, 
            "Environment",
            [Win32ColorRefresh]::SMTO_ABORTIFHUNG, 
            5000, 
            [ref]$result) | Out-Null
        
        # 4. Broadcast WM_THEMECHANGED
        Write-Verbose "  Broadcasting WM_THEMECHANGED..."
        [Win32ColorRefresh]::SendMessageTimeout(
            $broadcast, 
            [Win32ColorRefresh]::WM_THEMECHANGED,
            [IntPtr]::Zero, 
            [IntPtr]::Zero,
            [Win32ColorRefresh]::SMTO_ABORTIFHUNG, 
            5000, 
            [ref]$result) | Out-Null
        
        Write-Host "✅ Color change messages broadcast to all applications" -ForegroundColor Green
        
        # Optionally restart Explorer for stubborn legacy apps
        if ($RestartExplorer) {
            Write-Host "Restarting Explorer to force color refresh..." -ForegroundColor Yellow
            Stop-Process -Name explorer -Force -ErrorAction SilentlyContinue
            Start-Sleep -Seconds 2
            Start-Process explorer
            Write-Host "✅ Explorer restarted" -ForegroundColor Green
        }
    }
    catch {
        Write-Host "⚠️  Could not broadcast all settings changes: $($_.Exception.Message)" -ForegroundColor Yellow
    }
}

#endregion

#region Main Script

try {
    $ErrorActionPreference = "Stop"
    
    Write-Host ""
    Write-Host "═══════════════════════════════════════════════════════════" -ForegroundColor Cyan
    Write-Host "        Windows Legacy Components Dark Theme Applicator" -ForegroundColor Cyan
    Write-Host "═══════════════════════════════════════════════════════════" -ForegroundColor Cyan
    Write-Host ""
    
    $backupFile = "$PSScriptRoot\theme-backup.json"
    
    # Handle reset to default
    if ($ResetToDefault) {
        Write-Host "RESET MODE: Restoring Windows 11 default light theme" -ForegroundColor Yellow
        Write-Host ""
        
        Reset-ToDefaultTheme
        Update-ExplorerWindows
        
        Write-Host ""
        Write-Host "✅ Windows 11 default theme restored successfully!" -ForegroundColor Green
        Write-Host ""
        Write-Host "⚠️  IMPORTANT: Log out and back in for full effect" -ForegroundColor Yellow
        Write-Host ""
        
        if (-not $NoLogout) {
            $response = Read-Host "Do you want to log out now? (Y/N)"
            if ($response -eq "Y" -or $response -eq "y") {
                Write-Host "Logging out..." -ForegroundColor Cyan
                logoff
            }
        }
        
        exit 0
    }
    
    # Handle revert
    if ($Revert) {
        Write-Host "REVERT MODE: Restoring original theme colors" -ForegroundColor Yellow
        Write-Host ""
        
        Restore-ThemeFromBackup -BackupPath $backupFile
        Update-ExplorerWindows
        
        Write-Host ""
        Write-Host "✅ Theme reverted successfully!" -ForegroundColor Green
        Write-Host ""
        Write-Host "⚠️  IMPORTANT: Log out and back in for full effect" -ForegroundColor Yellow
        Write-Host ""
        
        if (-not $NoLogout) {
            $response = Read-Host "Do you want to log out now? (Y/N)"
            if ($response -eq "Y" -or $response -eq "y") {
                Write-Host "Logging out..." -ForegroundColor Cyan
                logoff
            }
        }
        
        exit 0
    }
    
    # Verify config file exists
    if (-not (Test-Path $ConfigFile)) {
        Write-Host "❌ Configuration file not found: $ConfigFile" -ForegroundColor Red
        throw "Configuration file not found: $ConfigFile"
    }
    
    # Load configuration
    Write-Host "Loading configuration from: $ConfigFile" -ForegroundColor Cyan
    $config = Get-Content -Path $ConfigFile -Raw | ConvertFrom-Json
    
    Write-Host "Theme: $($config.ThemeName) v$($config.Version)" -ForegroundColor Green
    Write-Host "Author: $($config.Author)" -ForegroundColor Gray
    Write-Host ""
    
    # Display notes
    if ($config.Notes) {
        Write-Host "Important Notes:" -ForegroundColor Yellow
        foreach ($note in $config.Notes) {
            Write-Host "  • $note" -ForegroundColor Yellow
        }
        Write-Host ""
    }
    
    # Create backup
    if (-not $NoBackup) {
        Backup-CurrentTheme -BackupPath $backupFile
        Write-Host ""
    }
    
    # Apply theme colors
    Apply-ThemeColors -Config $config
    Write-Host ""
    
    # Enable modern dark mode
    Enable-ModernDarkMode
    Write-Host ""
    
    # Refresh windows and broadcast color changes
    if ($RestartExplorer) {
        Update-ExplorerWindows -RestartExplorer
    }
    else {
        Update-ExplorerWindows
    }
    
    Write-Host ""
    Write-Host "═══════════════════════════════════════════════════════════" -ForegroundColor Cyan
    Write-Host "✅ Dark theme applied successfully!" -ForegroundColor Green
    Write-Host "═══════════════════════════════════════════════════════════" -ForegroundColor Cyan
    Write-Host ""
    Write-Host "⚠️  IMPORTANT NEXT STEPS:" -ForegroundColor Yellow
    Write-Host "  1. Log out and back in for full effect" -ForegroundColor Yellow
    Write-Host "  2. Restart affected applications (Task Scheduler, etc.)" -ForegroundColor Yellow
    Write-Host "  3. Use '.\Legacy-DarkMode.ps1 -Revert' to restore original theme" -ForegroundColor Gray
    Write-Host "  4. Use '.\Legacy-DarkMode.ps1 -ResetToDefault' to restore Windows 11 defaults" -ForegroundColor Gray
    Write-Host ""
    Write-Host "Backup saved to: $backupFile" -ForegroundColor Gray
    Write-Host ""
    
    if (-not $NoLogout) {
        $response = Read-Host "Do you want to log out now to apply changes? (Y/N)"
        if ($response -eq "Y" -or $response -eq "y") {
            Write-Host "Logging out in 5 seconds..." -ForegroundColor Cyan
            Start-Sleep -Seconds 5
            logoff
        }
    }
}
catch {
    Write-Host "❌ Failed to apply dark theme: $($_.Exception.Message)" -ForegroundColor Red
    Write-Host ""
    Write-Host "If you encounter issues, revert using: .\Legacy-DarkMode.ps1 -Revert" -ForegroundColor Yellow
    Write-Host "Or reset to defaults using: .\Legacy-DarkMode.ps1 -ResetToDefault" -ForegroundColor Yellow
    exit 1
}

#endregion

