# WKMon Module

## Overview
The WKMon module provides functionality for sending monitoring messages to the WKMonitor system. It creates and writes standardized monitoring messages to files that can be processed by the WKMonitor system for centralized monitoring and alerting.

## Dependencies
- Logger module

## Exported Functions

### WKMon
Sends messages to the WKMonitor system.

#### Parameters
- **program**: The name of the program or application generating the message.
- **kode**: A code identifier for the message type or category.
- **melding**: The actual message content to be logged.

#### Behavior
- Creates a monitoring message with timestamp, program name, code, computer name, and custom message
- Determines the appropriate path for the monitoring file based on the computer name
- Writes the message to a file with a specific naming convention (ComputerName + Timestamp + .MON)
- Also logs the message using the Logger module
- Special handling for p-no1fkmprd-app server to use a network path

#### Examples
```powershell
# Send an error message to WKMonitor
WKMon -program "MyApp" -kode "ERR001" -melding "Process failed"

# Send an informational message to WKMonitor
WKMon -program "Backup" -kode "INFO" -melding "Backup completed successfully"

# Send a warning message to WKMonitor
WKMon -program "DiskCheck" -kode "WARN" -melding "Disk space below 10% threshold"
```

## File Format
The monitoring files are created with the following format:
- Filename: `ComputerName + Timestamp + .MON`
- Content: `Timestamp Program Code ComputerName: Message`

## Usage Notes
- The module automatically determines the appropriate path for monitoring files
- For p-no1fkmprd-app server, files are written to a network share
- For other computers, files are written to the current directory
- Messages are also logged using the Logger module for additional visibility 