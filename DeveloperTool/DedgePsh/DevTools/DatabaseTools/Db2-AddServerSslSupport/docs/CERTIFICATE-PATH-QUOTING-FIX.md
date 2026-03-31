# Certificate Path Quoting Fix

## Problem Description

The `Manage-ClientCertificates.ps1` script was failing when importing SSL certificates to DBeaver's JRE truststore due to improper handling of paths containing spaces.

### Error Message
```
Error details: Illegal option:  Files\DBeaver\jre\lib\security\cacerts
keytool -importcert [OPTION]...
```

### Root Cause
The keytool command was receiving unquoted paths containing spaces, causing it to interpret parts of the path as separate command-line options.

## Solution Applied

### 1. Enhanced Path Quoting in `Invoke-KeytoolCommand`

**Before:**
```powershell
$process = Start-Process -FilePath $KeytoolPath -ArgumentList $Arguments -Wait -PassThru
```

**After:**
```powershell
# Quote arguments that contain spaces
$quotedArgs = @()
foreach ($arg in $Arguments) {
    if ($arg -match '\s' -and -not ($arg.StartsWith('"') -and $arg.EndsWith('"'))) {
        $quotedArgs += "`"$arg`""
    } else {
        $quotedArgs += $arg
    }
}

$process = Start-Process -FilePath $KeytoolPath -ArgumentList $quotedArgs -Wait -PassThru
```

### 2. Path Normalization in `Find-JavaEnvironment`

Added path trimming and normalization:
```powershell
# Normalize path separators and ensure no trailing backslash
$targetJre = $targetJre.TrimEnd('\')
```

### 3. Certificate File Path Validation in `Add-Certificate`

Added certificate file path normalization:
```powershell
# Normalize certificate file path
$CertificateFile = $CertificateFile.Trim().Trim('"')
```

### 4. Enhanced Debugging Output

Added comprehensive debugging information:
```powershell
Write-ColorOutput "Debug - Keytool Path: $KeytoolPath" "DarkGray"
Write-ColorOutput "Debug - Arguments: $($Arguments -join ' ')" "DarkGray"
Write-ColorOutput "Executing: $quotedKeytoolPath $($quotedArgs -join ' ')" "Cyan"
```

## Files Modified

1. **`Manage-ClientCertificates.ps1`**
   - Fixed `Invoke-KeytoolCommand` function for proper path quoting
   - Enhanced `Find-JavaEnvironment` function with path normalization
   - Improved `Add-Certificate` function with path validation
   - Added comprehensive debugging output

2. **`Test-CertificateImport.bat`** (New)
   - Test script to verify the fix works correctly
   - Tests DBeaver certificate import (most likely to fail with spaces)

## How the Fix Works

### Path Quoting Logic
1. **Detection**: Check if arguments contain spaces using regex `\s`
2. **Validation**: Ensure the argument isn't already quoted
3. **Quoting**: Wrap arguments containing spaces in double quotes
4. **Execution**: Pass quoted arguments to keytool via Start-Process

### Common Problematic Paths
- `C:\Program Files\DBeaver\jre\lib\security\cacerts`
- `C:\Program Files\Java\jre\lib\security\cacerts`
- Certificate files on network shares with spaces

## Testing the Fix

### Run the Test Script
```cmd
Test-CertificateImport.bat
```

### Manual Testing
```cmd
pwsh.exe -ExecutionPolicy Bypass -File "Manage-ClientCertificates.ps1" ^
  -ServerHostname "t-no1fkmdev-db.DEDGE.fk.no" ^
  -CertificateFile "\\server\path\to\cert.cer" ^
  -Action "add" ^
  -Target "dbeaver"
```

## Expected Behavior After Fix

### Successful Import
```
Debug - Keytool Path: C:\Program Files\DBeaver\jre\bin\keytool.exe
Debug - Arguments: -import -alias hostname -file cert.cer -keystore "C:\Program Files\DBeaver\jre\lib\security\cacerts" -storepass changeit -noprompt
Executing: "C:\Program Files\DBeaver\jre\bin\keytool.exe" -import -alias hostname -file cert.cer -keystore "C:\Program Files\DBeaver\jre\lib\security\cacerts" -storepass changeit -noprompt
Certificate imported successfully!
```

### Key Improvements
- Proper quoting of paths containing spaces
- Clear debugging output showing exactly what command is executed
- Better error handling and reporting
- Path normalization to prevent trailing backslash issues

## Compatibility

### PowerShell Versions
- Works with Windows PowerShell 5.1
- Works with PowerShell Core 7.x

### Java Versions
- Compatible with Oracle JRE/JDK
- Compatible with OpenJDK
- Compatible with DBeaver's bundled JRE

### Windows Versions
- Windows 10/11
- Windows Server 2016/2019/2022

## Related Files

The fix also improves the generated client scripts:
- `Install-Db2-SSL-Support-Dbeaver.bat`
- `Install-Db2-SSL-Support-Java.bat`
- `Uninstall-Db2-SSL-Support-Dbeaver.bat`
- `Uninstall-Db2-SSL-Support-Java.bat`

All these scripts now properly handle paths with spaces when calling the fixed `Manage-ClientCertificates.ps1` script. 