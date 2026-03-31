# AlertWKMon Module

## Overview
The AlertWKMon module provides functionality for sending alert messages to the WKMonitor system based on return codes. It creates and writes monitoring alert messages to files that can be picked up by the WKMonitor system.

## Functions

### AlertWKMon
Sends alert messages to WKMonitor based on return codes.

#### Parameters
- **program**: The name of the program or application generating the alert.
- **kode**: The return code. If not "0000", triggers an alert message.
- **melding**: The actual message content to be logged.

#### Behavior
- If the code is not "0000" (success), writes a detailed alert message including timestamp, program name, code, computer name, and custom message to both the Logger system and a monitor file.
- For successful codes (0000), only logs to the Logger system.
- Monitor files are created with format: [ComputerName][Timestamp].MON
- The path for monitor files varies based on the computer name:
  - For p-no1fkmprd-app: Network path (`\\DEDGE.fk.no\erpprog\cobnt\monitor\`)
  - For others: Local path (`.\`)

#### Examples
```powershell
# Create an alert for an error
AlertWKMon -program "MyApp" -kode "ERR1" -melding "Process failed"

# Log a successful operation (no monitor file created)
AlertWKMon -program "Backup" -kode "0000" -melding "Backup completed successfully"
```

## Dependencies
- Logger module

## Version History
- 20211202 fksveeri: First version
- 20240115 fkgeista: Created PowerShell module from script 