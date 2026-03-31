# DedgeSign-RemoveFileSign

Removes digital signatures from files.

> Developed by Geir Helge Starholm (Dedge AS)  
> Copyright © Dedge AS

## Synopsis

This script removes digital signatures from a single file. It is used by `DedgeSign.ps1` but can also be called directly.

## Parameters

| Parameter | Type   | Required | Description |
|-----------|--------|----------|-------------|
| FilePath  | String | Yes      | The path to the file to remove signature from |

## Supported File Types

### Script Files (Content Replacement)
- PowerShell Scripts (.ps1)
- PowerShell Modules (.psm1)
- PowerShell Data Files (.psd1)
- VBScript (.vbs)
- Windows Script Files (.wsf)
- JavaScript (.js)

### Binary Files (SignTool)
- Executables (.exe)
- DLLs (.dll)
- Installers (.msi)
- System Files (.sys)
- And many other binary formats

## Usage

```powershell
# Remove signature from a file
.\DedgeSign-RemoveFileSign.ps1 -FilePath "C:\MyApp\bin\Release\MyApp.exe"
```

## Notes

- The script checks if the file has a signature before attempting removal
- Uses different methods for script files vs binary files
- Returns exit code 0 on success, non-zero on failure 