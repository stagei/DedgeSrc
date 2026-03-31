# Logger Module

## Overview
The Logger module provides standardized logging functionality for PowerShell scripts and modules in the Dedge environment. It supports configurable log file paths, severity levels, and can write to both primary and secondary log files.

## Exported Functions

### InitializeLogger
Initializes the logger with specified settings.

#### Parameters
- **moduleName**: Optional. The name of the module being logged. If not provided, attempts to determine from the calling script.
- **loggerFilename**: Optional. The primary log file path. If not provided, generates a name based on the date and module name.
- **secondaryLoggerFilename**: Optional. A secondary log file path for duplicate logging.

#### Behavior
- Sets up the logging configuration including module name and log file paths
- If module name is not specified, attempts to determine it from the calling script
- Creates log files with standardized naming conventions
- Supports both absolute and relative paths for log files

#### Examples
```powershell
# Initialize with explicit module name and log file
InitializeLogger -moduleName "MyModule" -loggerFilename "app.log"

# Initialize with both primary and secondary log files
InitializeLogger -moduleName "MyModule" -loggerFilename "primary.log" -secondaryLoggerFilename "backup.log"

# Initialize with defaults (auto-detects module name and creates date-based log file)
InitializeLogger
```

### Logger
Logs a message with timestamp and severity level.

#### Parameters
- **message**: The message to log.
- **severity**: Optional. The severity level of the message. Valid values are: "INFO", "WARNING", "ERROR", "FATAL". Defaults to "INFO".

#### Behavior
- Writes a formatted log message to the configured log file(s)
- Each log entry includes timestamp, severity level, module name, and message
- Can write to both primary and secondary log files if configured
- Automatically initializes the logger if not already initialized
- Validates and normalizes severity levels
- Outputs log messages to the console in addition to writing to files

#### Examples
```powershell
# Log an informational message
Logger -message "Process started" -severity "INFO"

# Log an error message
Logger -message "Operation failed" -severity "ERROR"

# Log a warning (using default severity)
Logger -message "Configuration file not found, using defaults"

# Log a fatal error
Logger -message "Critical system failure" -severity "FATAL"
```

## Default Configuration
- Default log directory: `\\DEDGE.fk.no\erpprog\cobnt`
- Default log file naming: `yyyyMMdd_ModuleName.log`
- Default severity level: INFO

## Usage Notes
- The module maintains global state for log file paths and module name
- Log entries are formatted as: `timestamp|SEVERITY|ModuleName|message`
- If the logger is not explicitly initialized, it will auto-initialize with defaults when Logger is first called 