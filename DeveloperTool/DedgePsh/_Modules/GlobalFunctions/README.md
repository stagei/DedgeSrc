# GlobalFunctions Module

## Overview
The GlobalFunctions module provides a collection of utility functions for retrieving standard paths and locations used throughout the Dedge environment. These functions ensure consistent access to network shares, configuration directories, and temporary storage locations.

## Exported Functions

### Get-DefaultDomain
Returns the organization's default domain name.

#### Parameters
None

#### Behavior
- Returns the hardcoded domain name "DEDGE.fk.no"

#### Examples
```powershell
# Get the default domain name
$domain = Get-DefaultDomain
# Returns "DEDGE.fk.no"
```

### Get-DevToolsWebPath
Returns the network path to the DevTools web directory.

#### Parameters
None

#### Behavior
- Returns the UNC path to the DevTools web directory

#### Examples
```powershell
# Get the DevTools web directory path
$webPath = Get-DevToolsWebPath
# Returns "\\t-no1batch-vm01\opt\webs\DevTools"
```

### Get-DevToolsWebPathUrl
Returns the HTTP URL to the DevTools web directory.

#### Parameters
None

#### Behavior
- Returns the HTTP URL for accessing the DevTools web content

#### Examples
```powershell
# Get the DevTools web URL
$webUrl = Get-DevToolsWebPathUrl
# Returns "http://t-no1batch-vm01//DevTools"
```

### Get-CommonPath
Returns the network path to the DedgeCommon directory.

#### Parameters
None

#### Behavior
- Returns the UNC path to the DedgeCommon shared directory

#### Examples
```powershell
# Get the common path
$commonPath = Get-CommonPath
# Returns "\\p-Dedge-vm02\DedgeCommon"
```

### Get-ConfigFilesPath
Returns the path to configuration files.

#### Parameters
None

#### Behavior
- Returns the path to the Configfiles directory within DedgeCommon

#### Examples
```powershell
# Get the configuration files path
$configPath = Get-ConfigFilesPath
# Returns "\\p-Dedge-vm02\DedgeCommon\Configfiles"
```

### Get-PowershellDefaultAppsPath
Returns the network path where default PowerShell applications are stored.

#### Parameters
None

#### Behavior
- Returns the UNC path to PowerShell default applications directory

#### Examples
```powershell
# Get the PowerShell default apps path
$appsPath = Get-PowershellDefaultAppsPath
# Returns "\\p-Dedge-vm02\DedgeCommon\PowershellDefault\Apps"
```

### Get-ScriptLogPath
Determines and creates (if necessary) a log directory for the calling script.

#### Parameters
None

#### Behavior
- Examines the call stack to determine the calling script's name
- Creates a log directory based on the script name if it doesn't exist
- Falls back to the current directory if unable to create the log directory
- Returns the path to the appropriate log directory

#### Examples
```powershell
# Get the log path for the current script
$logPath = Get-ScriptLogPath
# Returns a path like "\\p-Dedge-vm02\DedgeCommon\Logs\MyScript"
```

### Get-SoftwarePath
Returns the path where software packages are stored.

#### Parameters
None

#### Behavior
- Returns the path to the Software directory within DedgeCommon

#### Examples
```powershell
# Get the software storage path
$softwarePath = Get-SoftwarePath
# Returns "\\p-Dedge-vm02\DedgeCommon\Software"
```

### Get-TempFkPath
Returns the path to a temporary directory and creates it if it doesn't exist.

#### Parameters
None

#### Behavior
- Returns the path to C:\TEMPFK
- Creates the directory if it doesn't exist
- Warns if unable to create the directory

#### Examples
```powershell
# Get the temporary directory path
$tempPath = Get-TempFkPath
# Returns "C:\TEMPFK" and ensures the directory exists
```

### Get-WingetAppsPath
Returns the path to the WinGet apps directory and creates it if it doesn't exist.

#### Parameters
None

#### Behavior
- Returns the path to the WingetApps directory within the software path
- Creates the directory if it doesn't exist
- Warns if unable to create the directory

#### Examples
```powershell
# Get the WinGet apps directory path
$wingetPath = Get-WingetAppsPath
# Returns "\\p-Dedge-vm02\DedgeCommon\Software\WingetApps"
```

### Get-WindowsAppsPath
Returns the path to the WindowsApps directory and creates it if it doesn't exist.

#### Parameters
None

#### Behavior
- Returns the path to the WindowsApps directory within the software path
- Creates the directory if it doesn't exist
- Warns if unable to create the directory

#### Examples
```powershell
# Get the other apps directory path
$otherAppsPath = Get-WindowsAppsPath
# Returns "\\p-Dedge-vm02\DedgeCommon\Software\WindowsApps"
``` 