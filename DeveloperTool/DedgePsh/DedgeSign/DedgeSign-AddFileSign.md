# DedgeSign-AddFileSign

Signs a single file using Azure Trusted Signing.

> Developed by Geir Helge Starholm (Dedge AS)  
> Copyright © Dedge AS

## Synopsis

This script signs a single file using Azure Trusted Signing. It is used by `DedgeSign.ps1` but can also be called directly.

## Prerequisites

1. Windows SDK (for SignTool)
   - Required path: `C:\Program Files (x86)\Windows Kits\10\bin\10.0.22621.0\x64\signtool.exe`
2. Microsoft Trusted Signing Client Tools
   - Dlib path: `%LOCALAPPDATA%\Microsoft\MicrosoftTrustedSigningClientTools\Azure.CodeSigning.Dlib.dll`

## Parameters

| Parameter | Type   | Required | Description |
|-----------|--------|----------|-------------|
| FilePath  | String | Yes      | The path to the file to sign |

## Usage

```powershell
# Sign a single file
.\DedgeSign-AddFileSign.ps1 -FilePath "C:\MyApp\bin\Release\MyApp.exe"
```

## Notes

- The script checks if the file is already signed before attempting to sign it
- Uses Azure Trusted Signing with browser-based authentication
- Returns exit code 0 on success, non-zero on failure 