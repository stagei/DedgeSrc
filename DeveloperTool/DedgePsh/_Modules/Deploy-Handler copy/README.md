# Deploy-Handler Module

Manages deployment of PowerShell modules and configurations across servers.

## Exported Functions

### Deploy-Files
Deploys files to one or more servers.

```powershell
Deploy-Files -FromFolder <string> [-Files <string[]>] [-ComputerNameList <string[]>] [-SkipSign <bool>]
```

### Initialize-NewMachine
Initializes a new machine with required folders and configurations.

```powershell
Initialize-NewMachine [-PreferredOptPath <string>] [-AdditionalAdmins <string[]>] [-AutoReset <bool>] [-IsWorkstation <bool>]
```

### Deploy-ModulesToServer
Deploys PowerShell modules to a specified server.

```powershell
Deploy-ModulesToServer [-ComputerName <string>] [-quiet <bool>]
```

### Remove-DeployedApp
Removes a deployed application from a server.

```powershell
Remove-DeployedApp [-ComputerName <string>] [-AppName <string>]
```

### Deploy-AgentTask
Deploys a task to the agent system.

```powershell
Deploy-AgentTask -TaskName <string> -SourceScript <string> [-ComputerNameList <string[]>]
```

### Copy-FilesToSingleDeployPath
Copies files to a single deployment path.

```powershell
Copy-FilesToSingleDeployPath -DeployPath <string> -DistributionSource <string> -AppName <string> -StagedFilesList <ArrayList>
```

### Start-AgentTaskProcess
Starts the agent task processing system.

```powershell
Start-AgentTaskProcess
```

## Overview
The Deploy-Handler module provides functionality for deploying PowerShell modules and scripts to various servers in the Dedge environment. It handles the deployment process, including creating necessary directories, copying module files, and cleaning up non-essential files after deployment.

### Deploy-Files
Deploys specified files to target servers.

#### Parameters
- **FromFolder**: The source folder containing the files to deploy.
- **Files**: Array of file names to deploy.
- **ComputerName**: The name of the target server to deploy files to.

#### Behavior
- Copies specified files from the source folder to the target server.
- Creates necessary directories if they don't exist.

### Initialize-NewMachine
Sets up a new server with administrative access and basic configuration.

#### Parameters
- **ComputerName**: The name of the target server to initialize.
- **Username**: The username for administrative access.
- **Password**: The password for administrative access.
- **AdditionalAdmins**: Array of additional administrators to add.

#### Behavior
- Configures administrative access on the new server.
- Sets up basic configuration and directories.

### Deploy-ModulesToServer
Deploys PowerShell modules to a specified server.

#### Parameters
- **ComputerName**: The name of the target server to deploy modules to. Can be a server name or drive letter.
- **quiet**: If true, suppresses warning messages when the server path is not accessible.

#### Behavior
- Creates necessary directories on the target server.
- Copies module files to the appropriate locations.
- Handles special cases for specific servers like p-no1fkmprd-app.
- Cleans up non-essential files after deployment.

### Remove-DeployedApp
Removes a deployed application from specified server.

#### Parameters
- **ComputerName**: The name of the target server.
- **AppName**: The name of the application to remove.

#### Behavior
- Removes the specified application from the target server.
- Cleans up associated files and directories.


## Requirements
- PowerShell 7 or later

## Usage Examples
```powershell
# Deploy modules to a specific server
Deploy-ModulesToServer -ComputerName "server01"

# Deploy specific files to a server
Deploy-Files -FromFolder "C:\Scripts" -Files @("script1.ps1", "script2.ps1") -ComputerName "server01"

# Initialize a new machine
Initialize-NewMachine -ComputerName "newserver" -Username "admin" -Password "password" -AdditionalAdmins @("user1", "user2")

# Remove a deployed application
Remove-DeployedApp -ComputerName "server01" -AppName "MyApp"

# Deploy an agent task
Deploy-AgentTask -TaskName "MonitorService" -SourceScript "C:\Scripts\Monitor.ps1" -ComputerNameList @("server01", "server02")
``` 