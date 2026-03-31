# SoftwareUtils Module

Manages software installation, updates, and configuration using various package managers.

## Overview
The SoftwareUtils module provides functionality for managing software installations and configurations in the Dedge environment. It includes tools for downloading and installing applications via WinGet, managing VS Code extensions, analyzing MSI packages, and customizing system appearance.

## Dependencies
- GlobalFunctions module
- PowerShell 7 or later
- WinGet (for package management functions)

## Exported Functions

### Install-WingetPackage
Installs a winget package from a local file.

```powershell
Install-WingetPackage -AppName <string> [-Executable <string>] [-InstallArgs <string>] [-QueryWinget <bool>] [-WaitForInstaller <bool>]
```

### Install-WingetPackage2
Alternative version of Install-WingetPackage with additional features.

```powershell
Install-WingetPackage2 -AppName <string> [-Executable <string>] [-InstallArgs <string>] [-QueryWinget <bool>] [-WaitForInstaller <bool>] [-AutoArgs <bool>]
```

### Start-WingetDownload
Downloads applications using winget.

```powershell
Start-WingetDownload [-DownloadFolder <string>]
```

### Show-DownloadedWingetPackages
Displays a list of downloaded winget packages.

```powershell
Show-DownloadedWingetPackages
```

### Get-DownloadedWingetPackages
Gets a list of downloaded winget packages.

```powershell
Get-DownloadedWingetPackages
```

### Install-WingetPackage
Installs a winget package.

```powershell
Install-WingetPackage -AppName <string>
```

### Get-VSCodeExtension
Downloads a VS Code extension.

```powershell
Get-VSCodeExtension -ExtensionId <string>
```

### Start-VsixDownload
Downloads VS Code extensions.

```powershell
Start-VsixDownload
```

### Install-VSCodeExtension
Installs a VS Code extension.

```powershell
Install-VSCodeExtension -ExtensionId <string>
```

### Install-CursorExtension
Installs a Cursor extension.

```powershell
Install-CursorExtension -ExtensionId <string>
```

### Get-MsiAnalysis
Analyzes an MSI file.

```powershell
Get-MsiAnalysis -AppName <string>
```

### Get-FilesAndCommandToRun
Gets the command and arguments to run for a winget package.

```powershell
Get-FilesAndCommandToRun -AppName <string> [-ForceCopy <bool>] [-ShowSelection <bool>]
```

## Usage Notes
- Many functions require administrator privileges
- WinGet must be installed for package management functions
- VS Code or Cursor must be installed for extension management functions 