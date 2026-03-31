# CblRun Module

## Overview
The CblRun module provides functionality for running COBOL programs with parameters, transcript logging, and return code checking. It's designed to execute Dedge batch modules with proper environment setup and monitoring.

## Exported Functions

### CBLRun
Runs a COBOL program with specified parameters and monitors its execution.

#### Parameters
- **Programname**: The name of the COBOL program to run.
- **Database**: The database to use. Must be one of: 'FKAVDNT', 'BASISPRO', 'BASISTST', 'BASISRAP'.
- **CBLParams**: Additional parameters to pass to the COBOL program.

#### Behavior
- Executes a COBOL program using the Micro Focus run.exe, with specified database and parameters.
- Logs the execution, captures output in a transcript file, and checks the return code for success.
- Creates a transcript file with .mfout extension
- Checks return code after execution
- Returns $true if execution was successful, $false otherwise

#### Examples
```powershell
# Run a COBOL program with parameters
CBLRun -Programname "MYPROG" -Database "BASISPRO" -CBLParams @("param1", "param2")
```

## Dependencies
- CheckLog module
- Logger module

## Version History
- 20230110 fksveeri: First version
- 20230111 fksveeri: Production release
- 20231122 fkgeista: Added function to check RC file and return true/false
- 20231123 fkgeista: Added override path for run.exe
- 20231124 fkgeista: Added function to set pshRootPath and run Set-Location
- 20240115 fkgeista: Created PowerShell module from script 