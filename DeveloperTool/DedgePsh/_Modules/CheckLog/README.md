# CheckLog Module

## Overview
The CheckLog module provides functionality for checking a program's return code file and logging the results. It examines a program's .rc file in a specified network path to check its return code and logs any non-zero return codes.

## Functions

### CheckLog
Checks a program's return code file and logs the results.

#### Parameters
- **program**: The name of the program to check (without file extension). The function will look for a corresponding .rc file.

#### Behavior
- Examines a program's .rc file in a specified network path to check its return code.
- If the return code is not "0000", or if the file is not found, logs an error message to both the Logger system and a monitor file.
- For successful executions (code "0000"), only logs to the Logger system.
- Return code files are expected to be in the format: XXXX[message] where XXXX is the 4-digit return code and [message] is optional text
- Code "0000" indicates success
- Code "0016" is used when the RC file is not found
- Monitor files are created with timestamp and computer name

#### Examples
```powershell
# Check a program's return code and log any issues
CheckLog -program "MyProgram"
```

## Dependencies
- Logger module (implicitly used for logging)

## File Paths
- RC files are expected to be in: `\\DEDGE.fk.no\ERPProg\cobnt\`
- Monitor files are created in: `\\DEDGE.fk.no\erpprog\cobnt\monitor\`

## Version History
- 20211214 fksveeri: First version
- 20240115 fkgeista: Created PowerShell module from script 