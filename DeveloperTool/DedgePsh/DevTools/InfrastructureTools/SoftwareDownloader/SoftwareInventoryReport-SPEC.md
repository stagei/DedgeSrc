# Software Inventory Report Specification

**Author:** Geir Helge Starholm, www.dEdge.no  
**Created:** 2026-01-28  
**Purpose:** Complete overview of available software modules and their current versions

---

## Overview

This specification defines a comprehensive software inventory system that generates an HTML report showing all available software modules, their versions, installation status, and installation commands. The system aggregates data from multiple sources:

1. **Winget Packages** - Downloaded packages with version metadata
2. **VS Code Extensions** - Downloaded VSIX files
3. **Windows Applications** - Traditional Windows installers
4. **Cursor/VSCode Installers** - System installers
5. **Ollama Models** - Installed AI models

The report provides a complete overview (not an update log) of all software modules available in the Dedge environment.

---

## WorkObject Structure

Similar to `AzureDevOpsGitCheckIn.ps1`, create a comprehensive WorkObject for tracking:

```powershell
$script:WorkObject = [PSCustomObject]@{
    # Job Information
    Name                      = "SoftwareInventoryReport"
    Description               = "Complete Software Inventory and Version Report"
    ScriptPath                = $PSCommandPath
    ExecutionTimestamp        = Get-Date -Format 'yyyy-MM-dd HH:mm:ss'
    ExecutionUser             = "$env:USERDOMAIN\$env:USERNAME"
    ComputerName              = $env:COMPUTERNAME
    
    # Execution Status
    Success                   = $false
    Status                    = "Running"
    ErrorMessage              = $null
    
    # Execution Phases
    WingetPackagesScanned     = $false
    VSCodeExtensionsScanned   = $false
    WindowsAppsScanned        = $false
    InstallersScanned         = $false
    OllamaModelsScanned       = $false
    ReportGenerated           = $false
    
    # Statistics
    TotalWingetPackages       = 0
    TotalVSCodeExtensions     = 0
    TotalWindowsApps          = 0
    TotalInstallers           = 0
    TotalOllamaModels         = 0
    
    # Timing
    StartTime                 = Get-Date
    EndTime                   = $null
    Duration                  = $null
    
    # Script and Output Tracking
    ScriptArray               = @()
    
    # Results Collections
    WingetPackages            = @()
    VSCodeExtensions          = @()
    WindowsApps               = @()
    SystemInstallers          = @()
    OllamaModels              = @()
}
```

---

## Data Sources and Collection Methods

### 1. Winget Packages

**Source:** `Get-WingetAppsPath()` folder (typically `C:\opt\src\DedgeSrc\DedgeSystemTools\Folders\DedgeCommon\Software\WingetApps`)

**Collection Method:**
- Scan folder structure: Each subfolder name = Package ID
- Read `version.txt` file in each package folder
- Extract package metadata from folder contents

**Example Structure:**
```
C:\opt\src\DedgeSrc\DedgeSystemTools\Folders\DedgeCommon\Software\WingetApps\
├── Microsoft.VisualStudioCode\
│   ├── version.txt                    # Contains: "1.85.2"
│   └── [downloaded installer files]
└── Ollama.Ollama\
    ├── version.txt                    # Contains: "0.1.25"
    └── [downloaded installer files]
```

**Data Object Example:**
```powershell
[PSCustomObject]@{
    PackageId        = "Microsoft.VisualStudioCode"
    Name             = "Visual Studio Code"
    Version          = "1.85.2"
    DownloadPath     = "C:\opt\src\DedgeSrc\DedgeSystemTools\Folders\DedgeCommon\Software\WingetApps\Microsoft.VisualStudioCode"
    VersionFilePath  = "C:\opt\src\DedgeSrc\DedgeSystemTools\Folders\DedgeCommon\Software\WingetApps\Microsoft.VisualStudioCode\version.txt"
    InstallCommand   = "Install-WingetPackage -AppName 'Microsoft.VisualStudioCode'"
    Category         = "Winget"
    LastModified     = "2026-01-28 14:30:00"
}
```

**Install Function Reference:**
- Function: `Install-WingetPackage` (in `SoftwareUtils.psm1`)
- Location: `_Modules\SoftwareUtils\SoftwareUtils.psm1:4860+`
- Example: `Install-WingetPackage -AppName "Microsoft.VisualStudioCode"`

---

### 2. VS Code Extensions

**Source:** `Get-ExtentionArray()` function returns array, `Start-VsixDownload` exports HTML

**Collection Method:**
- Call `Get-ExtentionArray()` to get extension list
- Check download paths: `Join-Path $(Get-SoftwarePath) "VSCodeExtensions"`
- Read VSIX files in folder: `*.vsix` files named by ExtensionId

**Example Structure:**
```
C:\opt\src\DedgeSrc\DedgeSystemTools\Folders\DedgeCommon\Software\VSCodeExtensions\
├── ms-python.python.vsix
├── halcyontechltd.vscode-db2i.vsix
├── shd101wyy.markdown-preview-enhanced.vsix
└── [other .vsix files]
```

**Data Object Example:**
```powershell
[PSCustomObject]@{
    ExtensionId      = "ms-python.python"
    Description      = "Python extension for VS Code"
    DownloadPath     = "C:\opt\src\DedgeSrc\DedgeSystemTools\Folders\DedgeCommon\Software\VSCodeExtensions\ms-python.python.vsix"
    FileName         = "ms-python.python.vsix"
    FileSize         = 5242880  # bytes
    LastModified     = "2026-01-28 10:15:00"
    InstallCommand   = "Install-VSCodeExtension -ExtensionId 'ms-python.python'"
    Category         = "VSCodeExtension"
}
```

**Install Function Reference:**
- Function: `Install-VSCodeExtension` (in `SoftwareUtils.psm1`)
- Location: `_Modules\SoftwareUtils\SoftwareUtils.psm1:1211+`
- Example: `Install-VSCodeExtension -ExtensionId "ms-python.python"`

---

### 3. Windows Applications

**Source:** `Get-WindowsAppsPath()` folder (typically `C:\opt\src\DedgeSrc\DedgeSystemTools\Folders\DedgeCommon\Software\WindowsApps`)

**Collection Method:**
- Scan folder structure: Each subfolder name = Application name
- Find executables: Look for `*.msi`, `*.exe`, `*.bat`, `*.cmd`, `*.ps1` files
- Extract version from installer files or folder structure

**Example Structure:**
```
C:\opt\src\DedgeSrc\DedgeSystemTools\Folders\DedgeCommon\Software\WindowsApps\
├── Db2\
│   ├── DataServer.x86_64\
│   │   └── setup.exe
│   └── Client\
│       └── db2setup.exe
├── SQL Server\
│   └── SQLServer2022-SSEI-Dev.exe
└── [other application folders]
```

**Data Object Example:**
```powershell
[PSCustomObject]@{
    ApplicationName  = "Db2"
    SubFolder         = "DataServer.x86_64"
    FullId            = "Db2.DataServer.x86_64"
    InstallerPath     = "C:\opt\src\DedgeSrc\DedgeSystemTools\Folders\DedgeCommon\Software\WindowsApps\Db2\DataServer.x86_64\setup.exe"
    InstallerType     = "exe"
    Version           = "11.5.9.0"  # Extracted from installer or folder
    InstallCommand    = "Start-Process -FilePath 'C:\opt\src\DedgeSrc\DedgeSystemTools\Folders\DedgeCommon\Software\WindowsApps\Db2\DataServer.x86_64\setup.exe' -ArgumentList '/S'"
    Category          = "WindowsApp"
    LastModified      = "2026-01-28 09:00:00"
}
```

**Install Function Reference:**
- Function: `Get-AllSoftwareConfigs` (in `SoftwareUtils.psm1`)
- Location: `_Modules\SoftwareUtils\SoftwareUtils.psm1:1362+`
- Note: Windows apps may use custom installation scripts

---

### 4. System Installers (Cursor/VSCode)

**Source:** Network paths for system installers

**Collection Method:**
- Scan `C:\opt\src\DedgeSrc\DedgeSystemTools\Folders\DedgeCommon\Software\WindowsApps\Cursor System-Installer`
- Scan `C:\opt\src\DedgeSrc\DedgeSystemTools\Folders\DedgeCommon\Software\WindowsApps\VSCode System-Installer`
- Extract version from filename or file properties

**Example Structure:**
```
C:\opt\src\DedgeSrc\DedgeSystemTools\Folders\DedgeCommon\Software\WindowsApps\
├── Cursor System-Installer\
│   └── CursorSetup-x64-1.1.7.exe
└── VSCode System-Installer\
    └── VSCodeSetup-x64-1.85.2.exe
```

**Data Object Example:**
```powershell
[PSCustomObject]@{
    ApplicationName  = "Cursor"
    InstallerType   = "SystemInstaller"
    InstallerPath   = "C:\opt\src\DedgeSrc\DedgeSystemTools\Folders\DedgeCommon\Software\WindowsApps\Cursor System-Installer\CursorSetup-x64-1.1.7.exe"
    FileName         = "CursorSetup-x64-1.1.7.exe"
    Version          = "1.1.7"  # Extracted from filename
    FileSize         = 157286400  # bytes
    LastModified     = "2026-01-28 12:00:00"
    InstallCommand   = "Start-Process -FilePath 'C:\opt\src\DedgeSrc\DedgeSystemTools\Folders\DedgeCommon\Software\WindowsApps\Cursor System-Installer\CursorSetup-x64-1.1.7.exe' -ArgumentList '/S'"
    Category         = "SystemInstaller"
}
```

**Install Function Reference:**
- Cursor: Manual installation or custom script
- VSCode: Can use `Install-WingetPackage -AppName "Microsoft.VisualStudioCode"` or manual installer

---

### 5. Ollama Models

**Source:** `Get-OllamaModels -IncludeDetails` from OllamaHandler module

**Collection Method:**
- Call `Get-OllamaModels -IncludeDetails` from OllamaHandler module
- Returns array of PSCustomObjects with model details

**Data Object Example:**
```powershell
[PSCustomObject]@{
    Name             = "llama3.1:8b"
    Model            = "llama3.1:8b"
    Size             = 4.7  # GB
    SizeGB           = "4.7 GB"
    ModifiedAt       = "2026-01-15T10:30:00Z"
    Family            = "llama"
    ParameterSize     = "8B"
    QuantizationLevel = "Q4_0"
    InstallCommand    = "Install-OllamaModel -ModelName 'llama3.1:8b'"
    Category          = "OllamaModel"
}
```

**Install Function Reference:**
- Function: `Install-OllamaModel` (in `OllamaHandler.psm1`)
- Location: `_Modules\OllamaHandler\OllamaHandler.psm1`
- Example: `Install-OllamaModel -ModelName "llama3.1:8b"`

---

## Implementation Function

Create a function `Get-SoftwareInventory` that:

1. **Scans Winget Packages:**
   ```powershell
   $wingetPath = Get-WingetAppsPath
   $wingetPackages = Get-ChildItem -Path $wingetPath -Directory | ForEach-Object {
       $versionFile = Join-Path $_.FullName "version.txt"
       $version = if (Test-Path $versionFile) { Get-Content $versionFile } else { "Unknown" }
       [PSCustomObject]@{
           PackageId = $_.Name
           Version = $version
           # ... other properties
       }
   }
   ```

2. **Scans VS Code Extensions:**
   ```powershell
   $extensions = Get-ExtentionArray
   $vsixPath = Join-Path $(Get-SoftwarePath) "VSCodeExtensions"
   foreach ($ext in $extensions) {
       $vsixFile = Join-Path $vsixPath "$($ext.Id).vsix"
       if (Test-Path $vsixFile) {
           $fileInfo = Get-Item $vsixFile
           # Add to collection with file details
       }
   }
   ```

3. **Scans Windows Apps:**
   ```powershell
   $windowsAppsPath = Get-WindowsAppsPath
   $windowsApps = Get-ChildItem -Path $windowsAppsPath -Directory | ForEach-Object {
       # Find executables recursively
       $executables = Get-ChildItem -Path $_.FullName -File -Include "*.msi","*.exe","*.bat","*.cmd","*.ps1" -Recurse
       # Build objects for each executable
   }
   ```

4. **Scans System Installers:**
   ```powershell
   $installerPaths = @(
       "C:\opt\src\DedgeSrc\DedgeSystemTools\Folders\DedgeCommon\Software\WindowsApps\Cursor System-Installer",
       "C:\opt\src\DedgeSrc\DedgeSystemTools\Folders\DedgeCommon\Software\WindowsApps\VSCode System-Installer"
   )
   foreach ($path in $installerPaths) {
       $installers = Get-ChildItem -Path $path -File -Filter "*.exe"
       # Extract version from filename or file properties
   }
   ```

5. **Gets Ollama Models:**
   ```powershell
   Import-Module OllamaHandler -Force -ErrorAction SilentlyContinue
   # Note: Use OllamaHandler module directly, not SoftwareUtils wrapper
   $ollamaModels = OllamaHandler\Get-OllamaModels -IncludeDetails
   # Returns array of PSCustomObjects with Name, Model, Size, SizeGB, ModifiedAt, Family, ParameterSize, QuantizationLevel
   ```

---

## Complete WorkObject Example

```powershell
$script:WorkObject = [PSCustomObject]@{
    Name                      = "SoftwareInventoryReport"
    Description               = "Complete Software Inventory and Version Report"
    ScriptPath                = $PSCommandPath
    ExecutionTimestamp        = "2026-01-28 16:00:00"
    ExecutionUser             = "DEDGE\FKGEISTA"
    ComputerName              = "30237-FK"
    Success                   = $true
    Status                    = "Completed"
    
    WingetPackagesScanned     = $true
    VSCodeExtensionsScanned   = $true
    WindowsAppsScanned         = $true
    InstallersScanned         = $true
    OllamaModelsScanned        = $true
    ReportGenerated            = $true
    
    TotalWingetPackages       = 28
    TotalVSCodeExtensions     = 15
    TotalWindowsApps          = 12
    TotalInstallers           = 2
    TotalOllamaModels         = 5
    
    StartTime                 = Get-Date "2026-01-28 16:00:00"
    EndTime                   = Get-Date "2026-01-28 16:02:30"
    Duration                  = New-TimeSpan -Seconds 150
    
    WingetPackages = @(
        [PSCustomObject]@{
            PackageId        = "Microsoft.VisualStudioCode"
            Name             = "Visual Studio Code"
            Version          = "1.85.2"
            DownloadPath     = "C:\opt\src\DedgeSrc\DedgeSystemTools\Folders\DedgeCommon\Software\WingetApps\Microsoft.VisualStudioCode"
            InstallCommand   = "Install-WingetPackage -AppName 'Microsoft.VisualStudioCode'"
            Category         = "Winget"
        }
        # ... more packages
    )
    
    VSCodeExtensions = @(
        [PSCustomObject]@{
            ExtensionId      = "ms-python.python"
            Description      = "Python extension for VS Code"
            DownloadPath     = "C:\opt\src\DedgeSrc\DedgeSystemTools\Folders\DedgeCommon\Software\VSCodeExtensions\ms-python.python.vsix"
            InstallCommand   = "Install-VSCodeExtension -ExtensionId 'ms-python.python'"
            Category         = "VSCodeExtension"
        }
        # ... more extensions
    )
    
    WindowsApps = @(
        [PSCustomObject]@{
            ApplicationName  = "Db2"
            FullId            = "Db2.DataServer.x86_64"
            InstallerPath    = "C:\opt\src\DedgeSrc\DedgeSystemTools\Folders\DedgeCommon\Software\WindowsApps\Db2\DataServer.x86_64\setup.exe"
            Version           = "11.5.9.0"
            InstallCommand    = "Start-Process -FilePath 'C:\opt\src\DedgeSrc\DedgeSystemTools\Folders\DedgeCommon\Software\WindowsApps\Db2\DataServer.x86_64\setup.exe' -ArgumentList '/S'"
            Category          = "WindowsApp"
        }
        # ... more apps
    )
    
    SystemInstallers = @(
        [PSCustomObject]@{
            ApplicationName  = "Cursor"
            InstallerPath    = "C:\opt\src\DedgeSrc\DedgeSystemTools\Folders\DedgeCommon\Software\WindowsApps\Cursor System-Installer\CursorSetup-x64-1.1.7.exe"
            Version          = "1.1.7"
            InstallCommand   = "Start-Process -FilePath 'C:\opt\src\DedgeSrc\DedgeSystemTools\Folders\DedgeCommon\Software\WindowsApps\Cursor System-Installer\CursorSetup-x64-1.1.7.exe' -ArgumentList '/S'"
            Category         = "SystemInstaller"
        },
        [PSCustomObject]@{
            ApplicationName  = "VSCode"
            InstallerPath    = "C:\opt\src\DedgeSrc\DedgeSystemTools\Folders\DedgeCommon\Software\WindowsApps\VSCode System-Installer\VSCodeSetup-x64-1.85.2.exe"
            Version          = "1.85.2"
            InstallCommand   = "Start-Process -FilePath 'C:\opt\src\DedgeSrc\DedgeSystemTools\Folders\DedgeCommon\Software\WindowsApps\VSCode System-Installer\VSCodeSetup-x64-1.85.2.exe' -ArgumentList '/SILENT'"
            Category         = "SystemInstaller"
        }
    )
    
    OllamaModels = @(
        [PSCustomObject]@{
            Name             = "llama3.1:8b"
            SizeGB           = "4.7 GB"
            ParameterSize    = "8B"
            ModifiedAt       = "2026-01-15T10:30:00Z"
            InstallCommand   = "Install-OllamaModel -ModelName 'llama3.1:8b'"
            Category         = "OllamaModel"
        }
        # ... more models
    )
    
    ScriptArray = @(
        [PSCustomObject]@{
            Name            = "Winget-Scan"
            FirstTimestamp  = "2026-01-28 16:00:05"
            LastTimestamp   = "2026-01-28 16:00:45"
            Script          = "Get-ChildItem -Path `"$wingetPath`" -Directory"
            Output          = "Found 28 winget packages"
        }
        # ... more script executions
    )
}
```

---

## HTML Report Export

Export using `Export-WorkObjectToHtmlFile`:

```powershell
$reportPath = Join-Path (Get-ApplicationDataPath) "SoftwareInventoryReport-$(Get-Date -Format 'yyyyMMdd-HHmmss').html"
Export-WorkObjectToHtmlFile -WorkObject $script:WorkObject `
    -FileName $reportPath `
    -Title "Software Inventory Report - Complete Overview" `
    -AddToDevToolsWebPath $true `
    -DevToolsWebDirectory "Software/Inventory" `
    -AutoOpen $true
```

---

## Installation Command Examples

### Winget Packages
```powershell
# Visual Studio Code
Install-WingetPackage -AppName "Microsoft.VisualStudioCode"

# Ollama
Install-WingetPackage -AppName "Ollama.Ollama"
```

### VS Code Extensions
```powershell
# Python extension
Install-VSCodeExtension -ExtensionId "ms-python.python"

# DB2 extension
Install-VSCodeExtension -ExtensionId "halcyontechltd.vscode-db2i"
```

### Windows Apps
```powershell
# Db2 DataServer
Start-Process -FilePath "C:\opt\src\DedgeSrc\DedgeSystemTools\Folders\DedgeCommon\Software\WindowsApps\Db2\DataServer.x86_64\setup.exe" -ArgumentList "/S"

# SQL Server
Start-Process -FilePath "C:\opt\src\DedgeSrc\DedgeSystemTools\Folders\DedgeCommon\Software\WindowsApps\SQL Server\SQLServer2022-SSEI-Dev.exe" -ArgumentList "/QUIET"
```

### System Installers
```powershell
# Cursor
Start-Process -FilePath "C:\opt\src\DedgeSrc\DedgeSystemTools\Folders\DedgeCommon\Software\WindowsApps\Cursor System-Installer\CursorSetup-x64-1.1.7.exe" -ArgumentList "/S"

# VSCode System Installer
Start-Process -FilePath "C:\opt\src\DedgeSrc\DedgeSystemTools\Folders\DedgeCommon\Software\WindowsApps\VSCode System-Installer\VSCodeSetup-x64-1.85.2.exe" -ArgumentList "/SILENT"
```

### Ollama Models
```powershell
# Llama 3.1 8B
Install-OllamaModel -ModelName "llama3.1:8b"

# Code Llama
Install-OllamaModel -ModelName "codellama:7b"
```

---

## Function Integration in SoftwareDownloader.ps1

Add after line 9:

```powershell
# Generate comprehensive software inventory report
Get-SoftwareInventory
```

The function should:
1. Initialize WorkObject
2. Scan all sources (winget, extensions, Windows apps, installers, Ollama)
3. Populate WorkObject with collected data
4. Export to HTML report
5. Return WorkObject

---

## Report Sections

The HTML report should display:

1. **Summary Statistics**
   - Total packages by category
   - Scan completion status
   - Execution duration

2. **Winget Packages Table**
   - Package ID, Name, Version, Install Command

3. **VS Code Extensions Table**
   - Extension ID, Description, File Path, Install Command

4. **Windows Applications Table**
   - Application Name, Subfolder, Version, Installer Path, Install Command

5. **System Installers Table**
   - Application Name, Version, Installer Path, Install Command

6. **Ollama Models Table**
   - Model Name, Size, Parameters, Modified Date, Install Command

7. **Script Execution Log**
   - All script executions with timestamps (from ScriptArray)

---

## Notes

- This is a **complete inventory**, not an update log
- All software modules are listed regardless of installation status
- Install commands are provided for each item
- Version information is extracted from files/folders where available
- The report serves as a reference for available software in the environment
