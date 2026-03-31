# Infrastructure Module

## Overview
The Infrastructure module provides functionality for managing and querying computer information within the Dedge environment. It handles server and developer machine inventory, connectivity testing, and system configuration.

## Dependencies
- GlobalFunctions module

## Exported Functions

### Add-ComputerInfo
Adds a computer to the infrastructure inventory.

#### Parameters
- **computer**: The computer object to add.
- **AutoConfirm**: Optional. Whether to skip confirmation prompts. Default is false.

#### Behavior
- Adds a new computer to the ComputerInfo.json file
- Validates the computer object before adding
- Prompts for confirmation unless AutoConfirm is true

#### Examples
```powershell
# Add a new server
$newComputer = [PSCustomObject]@{
    Name = "SERVER01"
    Type = "Server"
    IsActive = $true
    Platform = "Windows"
}
Add-ComputerInfo -computer $newComputer
```

### Remove-ComputerInfo
Removes a computer from the infrastructure inventory.

#### Parameters
- **computerName**: The name of the computer to remove.

#### Behavior
- Removes a computer from the ComputerInfo.json file
- Prompts for confirmation before removal

#### Examples
```powershell
# Remove a computer
Remove-ComputerInfo -computerName "SERVER01"
```

### Get-ServerList
Returns a list of all active server names.

#### Parameters
None

#### Behavior
- Returns an array of server names from the active servers in the inventory

#### Examples
```powershell
# Get all server names
$servers = Get-ServerList
```

### Get-ServerObjectList
Returns a list of all active server objects.

#### Parameters
None

#### Behavior
- Returns an array of server objects from the active servers in the inventory

#### Examples
```powershell
# Get all server objects
$serverObjects = Get-ServerObjectList
```

### Get-WorkstationList
Returns a list of all active developer machine names.

#### Parameters
None

#### Behavior
- Returns an array of developer machine names from the active machines in the inventory

#### Examples
```powershell
# Get all developer machine names
$devMachines = Get-WorkstationList
```

### Get-WorkstationObjectList
Returns a list of all active developer machine objects.

#### Parameters
None

#### Behavior
- Returns an array of developer machine objects from the active machines in the inventory

#### Examples
```powershell
# Get all developer machine objects
$devMachineObjects = Get-WorkstationObjectList
```

### Get-AllActiveComputerList
Returns a list of all active computer names regardless of type.

#### Parameters
None

#### Behavior
- Returns an array of computer names for all active computers in the inventory

#### Examples
```powershell
# Get all active computer names
$allComputers = Get-AllActiveComputerList
```

### Get-AllActiveComputerObjectList
Returns a list of all active computer objects regardless of type.

#### Parameters
None

#### Behavior
- Returns an array of computer objects for all active computers in the inventory

#### Examples
```powershell
# Get all active computer objects
$allComputerObjects = Get-AllActiveComputerObjectList
```

### Get-CurrentComputerPlatform
Determines the platform of the current computer.

#### Parameters
None

#### Behavior
- Detects whether the current computer is physical, virtual, or cloud-based
- Uses WMI queries to determine the platform

#### Examples
```powershell
# Get the current computer's platform
$platform = Get-CurrentComputerPlatform
```

### Add-CurrentComputer
Adds the current computer to the infrastructure inventory.

#### Parameters
- **AutoConfirm**: Optional. Whether to skip confirmation prompts. Default is false.

#### Behavior
- Gathers information about the current computer
- Creates a computer object with appropriate metadata
- Adds the computer to the inventory

#### Examples
```powershell
# Add the current computer to inventory
Add-CurrentComputer
```

### Set-ComputerAvailabilityStatus
Updates the availability status of computers in the inventory.

#### Parameters
None

#### Behavior
- Tests connectivity to all computers in the inventory
- Updates their IsActive status based on connectivity results
- Creates a backup of the inventory file before making changes

#### Examples
```powershell
# Update availability status of all computers
Set-ComputerAvailabilityStatus
```

### Test-ComputerConnection
Tests connectivity to a remote computer using multiple methods.

#### Parameters
- **ComputerName**: The name of the computer to test connectivity to.

#### Behavior
- Tests connectivity using DNS resolution, WMI, and RPC
- Each test has a timeout to prevent hanging
- Returns true if any connectivity test succeeds

#### Examples
```powershell
# Test connectivity to a server
$isConnected = Test-ComputerConnection -ComputerName "SERVER01"
```

### Test-PortConnectivity
Tests connectivity to a specific port on a remote computer.

#### Parameters
- **Server**: The name of the server to test.
- **Port**: The port number to test.
- **ServiceType**: Optional. A description of the service being tested.

#### Behavior
- Attempts to establish a TCP connection to the specified port
- Returns a custom object with connection status and details

#### Examples
```powershell
# Test SQL Server connectivity
Test-PortConnectivity -Server "SQLSERVER01" -Port 1433 -ServiceType "SQL Server"
```

### Get-ComputerInfoJson
Retrieves computer information from the ComputerInfo.json file.

#### Parameters
None

#### Behavior
- Reads and deserializes the ComputerInfo.json file
- Returns an array of computer objects

#### Examples
```powershell
# Get all computer information
$allComputers = Get-ComputerInfoJson
```

### Set-ComputerInfoJson
Updates the ComputerInfo.json file with new computer information.

#### Parameters
- **computers**: An array of computer objects to save.

#### Behavior
- Serializes the computer objects to JSON
- Writes the JSON to the ComputerInfo.json file

#### Examples
```powershell
# Update computer information
$computers = Get-ComputerInfoJson
$computers[0].Description = "Updated description"
Set-ComputerInfoJson -computers $computers
```

### Get-ComputerMetaData
Gets a computer object by name.

#### Parameters
- **Name**: The name of the computer to retrieve.

#### Behavior
- Searches for a computer with the specified name in the inventory
- Returns the matching computer object

#### Examples
```powershell
# Get metadata for a specific computer
$computerInfo = Get-ComputerMetaData -Name "SERVER01"
```

### Add-Folder
Creates a folder if it doesn't exist.

#### Parameters
- **Path**: The path of the folder to create.

#### Behavior
- Checks if the folder exists
- Creates the folder if it doesn't exist
- Returns the folder path

#### Examples
```powershell
# Create a folder
Add-Folder -Path "C:\Temp\NewFolder"
```

### Add-Privilege
Adds a privilege to a user on a remote computer.

#### Parameters
- **ComputerName**: The name of the remote computer.
- **Username**: The username to grant privileges to.
- **Privilege**: The privilege to grant.

#### Behavior
- Connects to the remote computer
- Adds the specified privilege to the user
- Returns success or failure status

#### Examples
```powershell
# Add administrator privilege
Add-Privilege -ComputerName "SERVER01" -Username "domain\user" -Privilege "Administrator"
```

### Get-DiskInfo
Gets disk information for a computer.

#### Parameters
- **ComputerName**: The name of the computer to query.

#### Behavior
- Retrieves disk space information using WMI
- Returns an array of disk objects with space details

#### Examples
```powershell
# Get disk information
$diskInfo = Get-DiskInfo -ComputerName "SERVER01"
```

### Start-ServerRefresh
Refreshes server information in the inventory.

#### Parameters
None

#### Behavior
- Updates server connectivity status
- Refreshes metadata for all servers
- Updates the inventory file

#### Examples
```powershell
# Refresh server information
Start-ServerRefresh
``` 