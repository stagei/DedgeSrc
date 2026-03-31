# DedgePsh PowerShell Modules

Common modules for PowerShell should be placed here and imported into PowerShell using: Import-Module

## Setup

Set default path using PSModulePath:

```powershell
setx PSModulePath "%PSModulePath%;C:\opt\src\DedgePsh\_Modules" /M
```

## Available Modules

### Deploy-Handler
Server deployment and management module.
- **Functions:**
  - `Initialize-NewMachine`: Sets up a new server with administrative access and basic configuration
    ```powershell
    Initialize-NewMachine -ComputerName "t-no1batch-vm02" `
                        -Username "DEDGE\FKGEISTA" `
                        -Password "xxxx!" `
                        -AdditionalAdmins @("DEDGE\FKGEISTA", "DEDGE\FKSVEERI")
    ```
  - `Deploy-Files`: Deploys specified files to target servers
    ```powershell
    Deploy-Files -FromFolder $(Get-Location) `
                -Files @("AzureDevOpsGitCheckIn.ps1", "AzureDevOpsGitCheckIn.bat") `
                -ComputerName "t-no1batch-vm02"
    ```
  - `Deploy-ModulesToServer`: Deploys PowerShell modules to specified server
    ```powershell
    Deploy-ModulesToServer -ComputerName "t-no1batch-vm02"
    ```
  - `Remove-DeployedApp`: Removes a deployed application from specified server
    ```powershell
    Remove-DeployedApp -ComputerName "t-no1batch-vm02" -AppName "MyApp"
    ```

### AlertWKMon
Utility for sending messages to WKMonitor system.
- **Functions:**
  - `AlertWKMon`: Sends monitoring alerts with program code, status code, and message.

### AutoCreateScheduledTask
Handles creation and management of Windows Scheduled Tasks.
- **Functions:**
  - `AutoCreateScheduledTask`: Creates and configures Windows Scheduled Tasks
  - Supports task scheduling with various triggers and actions
  - Handles task credentials and permissions

### CblRun
Handles execution of Dedge batch modules with parameter handling, transcript logging, and RC-file verification.
- **Functions:**
  - `CBLRun`: Executes COBOL programs with database and parameter specifications
  - `SetLocationPshRootPath`: Sets up environment paths based on computer name
  - `Get-RC`: Retrieves return codes from RC files
  - `Test-RC`: Tests if a program's RC file indicates success (0000)

### CheckLog
Log file verification and monitoring module.
- **Functions:**
  - `CheckLog`: Verifies and processes log files for specified programs

### GlobalFunctions
Shared utility functions used across multiple modules.
- **Functions:**
  - Common helper functions for file operations
  - Shared utility methods
  - System-wide configuration functions

### ConvertAnsi1252ToUtf8
Handles character encoding conversion from ANSI 1252 to UTF-8 for files.
- **Functions:**
  - `ConvertAnsi1252ToUtf8`: Converts files from ANSI 1252 to UTF-8 encoding

### ConvertFileFromAnsi1252ToUtf8
File-specific conversion utility for ANSI 1252 to UTF-8.
- **Functions:**
  - `ConvertFileFromAnsi1252ToUtf8`: Converts a specific file from ANSI 1252 to UTF-8

### ConvertStringFromAnsi1252ToUtf8
String-level conversion utility for ANSI 1252 to UTF-8.
- **Functions:**
  - `ConvertStringFromAnsi1252ToUtf8`: Converts a string from ANSI 1252 to UTF-8 encoding

### ConvertUtf8ToAnsi1252
Handles reverse conversion from UTF-8 to ANSI 1252.
- **Functions:**
  - `ConvertUtf8ToAnsi1252`: Converts files from UTF-8 to ANSI 1252 encoding

### Export-Array
Data export module supporting multiple formats.
- **Functions:**
  - `Export-ArrayToCsvFile`: Exports to CSV with custom delimiters
    ```powershell
    $data | Export-ArrayToCsvFile -Headers @("Name", "Status") -Delimiter ";" -AutoOpen
    ```
  - `Export-ArrayToJsonFile`: Exports to JSON format
    ```powershell
    $data | Export-ArrayToJsonFile -Pretty -OpenInNotepad
    ```
  - `Export-ArrayToXmlFile`: Exports to XML format
    ```powershell
    $data | Export-ArrayToXmlFile -RootElementName "Report" -ItemElementName "Entry"
    ```
  - `Export-ArrayToHtmlFile`: Creates HTML reports
    ```powershell
    $data | Export-ArrayToHtmlFile -Title "System Report" -AutoOpen
    ```
  - `Export-ArrayToMarkdownFile`: Generates markdown documentation
    ```powershell
    $data | Export-ArrayToMarkdownFile -Title "Status Report" -OpenInNotepad
    ```
  - `Export-ArrayToTxtFile`: Exports to formatted text
    ```powershell
    $data | Export-ArrayToTxtFile -Title "Plain Text Report"
    ```

### FKASendEmail
Email utility module.
- **Functions:**
  - `FKASendEmail`: Sends emails with attachments and HTML support
    ```powershell
    FKASendEmail -To "geir.helge.starholm@dedge.no" `
                 -From "geir.helge.starholm@dedge.no" `
                 -Subject "Report" `
                 -HtmlBody "<h1>Status Report</h1>" `
                 -Attachments @("report.pdf")
    ```

### FKASendSMSDirect
SMS sending utility module.
- **Functions:**
  - `FKASendSMSDirect`: Sends SMS messages directly through the FKA system

### Infrastructure
System infrastructure management module for handling computer information and connectivity.
- **Functions:**
  - `Get-ComputerInfoJson`: Retrieves computer information from JSON configuration
  - `Set-ComputerInfoJson`: Updates computer information in JSON configuration
  - `Add-ComputerInfo`: Adds new computer information with confirmation option
  - `Remove-ComputerInfo`: Removes computer information with confirmation
  - `Get-ComputerObjectList`: Gets filtered list of computer objects by type, status, and platform
  - `Get-ComputerList`: Gets filtered list of computer names
  - `Get-ServerObjectList`: Gets list of active server objects
  - `Get-ServerList`: Gets list of active server names
  - `Get-WorkstationObjectList`: Gets list of active developer machine objects
  - `Get-WorkstationList`: Gets list of active developer machine names
  - `Test-ComputerConnection`: Tests computer connectivity using DNS, WMI, and RPC
  - `Test-PortConnectivity`: Tests specific port connectivity with latency measurement
  - `Set-ComputerAvailabilityStatus`: Updates and maintains computer availability status
  - `Get-CurrentComputerPlatform`: Detects current computer's platform (Azure/Digiplex/Local)
  - `Add-CurrentComputer`: Adds current computer to infrastructure with specified configuration
- **Features:**
  - JSON-based configuration management
  - Computer information tracking and filtering
  - Infrastructure documentation
  - Comprehensive connectivity testing
  - Platform detection and categorization
  - Automatic backup creation during updates
  - Support for different computer types (Server/Developer Machine)
  - Multiple platform support (Azure/Digiplex/Local)

### Logger
Logging utility module.
- **Functions:**
  - `InitializeLogger`: Initializes logging system
    ```powershell
    InitializeLogger -LogPath "C:\logs" -ModuleName "MyModule"
    ```
  - `Logger`: Logs messages with severity levels
    ```powershell
    Logger -Message "Operation completed" -Severity "INFO"
    Logger -Message "Warning condition" -Severity "WARNING"
    Logger -Message "Error occurred" -Severity "ERROR"
    ```

### MarkdownToHtml
Markdown conversion module.
- **Functions:**
  - `Convert-MarkdownToHtml`: Converts markdown to styled HTML
    ```powershell
    Convert-MarkdownToHtml -InputPath "doc.md" -OutputPath "doc.html" -OpenInBrowser
    ```

### OdbcHandler
ODBC database operations module.
- **Functions:**
  - `Get-OdbcConnection`: Gets ODBC connection information
    ```powershell
    Get-OdbcConnection -Name "MyConnection"
    ```
  - `ExecuteQuery`: Executes a SELECT query
    ```powershell
    ExecuteQuery -ConnectionString "DSN=MyDSN" -Query "SELECT * FROM Table"
    ```
  - `ExecuteNonQuery`: Executes INSERT/UPDATE/DELETE queries
    ```powershell
    ExecuteNonQuery -ConnectionString "DSN=MyDSN" -Query "UPDATE Table SET Field = 'Value'"
    ```

### SoftwareUtils
Windows Package Manager utility module.
- **Functions:**
  - `Install-WingetPackage`: Installs package using winget
    ```powershell
    Install-WingetPackage -AppName "Microsoft.PowerShell"
    ```
  - `Start-WingetDownload`: Downloads package for offline installation
    ```powershell
    Start-WingetDownload -AppName "Microsoft.PowerShell"
    ```
  - `Show-DownloadedWingetPackages`: Lists downloaded packages
    ```powershell
    Show-DownloadedWingetPackages
    ```

### WKMon
WKMonitor integration module.
- **Functions:**
  - `WKMon`: Core WKMonitor functionality
  - System monitoring and alerting

### Character Encoding Modules
Modules for handling character encoding conversions:
- **ConvertAnsi1252ToUtf8**
  ```powershell
  ConvertFileAnsi1252ToUtf8 -InputFile "input.txt" -OutputFile "output.txt"
  ```
- **ConvertUtf8ToAnsi1252**
  ```powershell
  ConvertFileUtf8ToAnsi1252 -InputFile "input.txt" -OutputFile "output.txt"
  ```
- **ConvertStringFromAnsi1252ToUtf8**
  ```powershell
  $utf8String = ConvertStringFromAnsi1252ToUtf8 -convertString $ansiString
  ```

## Usage

Import modules individually as needed:
