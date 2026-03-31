# DedgeSign

Azure Trusted Signing Tool for automatic file signing.

> Developed by Geir Helge Starholm (Dedge AS)  
> Copyright © Dedge AS

## Synopsis

This PowerShell script automatically adds or removes digital signatures from executable files using Azure Trusted Signing with browser-based authentication.

## Prerequisites

1. Windows SDK (for SignTool)
   - Download from: https://go.microsoft.com/fwlink/p/?linkid=2196241
   - Required path: `C:\Program Files (x86)\Windows Kits\10\bin\10.0.22621.0\x64\signtool.exe`

2. Microsoft Trusted Signing Client Tools
   - Download from: https://download.microsoft.com/download/6d9cb638-4d5f-438d-9f21-23f0f4405944/TrustedSigningClientTools.msi
   - This will install Dlib at: `%LOCALAPPDATA%\Microsoft\MicrosoftTrustedSigningClientTools\Azure.CodeSigning.Dlib.dll`

3. PowerShell 7 or later
   - Must be run as Administrator

## Parameters

| Parameter  | Type   | Required | Default | Description |
|-----------|--------|----------|---------|-------------|
| Path      | String | No       | "."     | File, directory, or pattern to process |
| Recursive | Switch | No       | False   | Include subdirectories when scanning |
| Action    | String | No       | "Add"   | Action to perform: 'Add' or 'Remove' |
| NoConfirm | Switch | No       | False   | Skip confirmation prompt |

## Usage Examples

### 1. Single File Mode
```powershell
# Add signature
.\DedgeSign.ps1 -Path path\to\file.exe -Action Add

# Remove signature
.\DedgeSign.ps1 -Path path\to\file.exe -Action Remove
```

### 2. Directory Mode
```powershell
# Current directory (non-recursive)
.\DedgeSign.ps1 -Action Add

# Specific directory (recursive)
.\DedgeSign.ps1 -Path path\to\directory -Recursive -Action Add
```

### 3. Pattern Mode
```powershell
# Sign all PowerShell files in current directory
.\DedgeSign.ps1 -Path *.ps1 -Action Add

# Remove signatures from DLLs
.\DedgeSign.ps1 -Path C:\Project\bin\*.dll -Action Remove
```

## Supported File Types

- Executables (.exe)
- Libraries (.dll)
- PowerShell (.ps1, .psm1, .psd1)
- Scripts (.vbs, .wsf, .js)
- Installers (.msi, .msix, .appx)
- System Files (.sys, .drv)
- And many other executable formats

## Notes

- The script automatically detects file signatures before processing
- Supports both adding and removing signatures
- Can process multiple files in batch
- Provides detailed progress and status information 