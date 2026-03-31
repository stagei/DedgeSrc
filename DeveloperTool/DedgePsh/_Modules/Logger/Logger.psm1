# Logger.psm1
# Logger module for Powershell
#
# Changelog:
# ------------------------------------------------------------------------------
# 20240115 fkgeista Første versjon
# ------------------------------------------------------------------------------
$global:LoggerFilename = ""
$global:SecondaryLoggerFilename = ""
$global:ModuleName = ""
$defaultPath = "\\DEDGE.fk.no\erpprog\cobnt"

<#
.SYNOPSIS
    Provides standardized logging functionality for PowerShell modules and scripts.

.DESCRIPTION
    This module offers a centralized logging system with configurable log files, severity levels,
    and standardized message formatting. It supports both primary and secondary log files,
    automatic timestamp generation, and module name detection. Designed to provide consistent
    logging across all Dedge PowerShell modules and scripts.

.EXAMPLE
    InitializeLogger -moduleName "MyModule"
    Logger -message "Process started" -severity "INFO"
    # Sets up logging for a module and logs an informational message

.EXAMPLE
    InitializeLogger -moduleName "MyApp" -loggerFilename "app.log" -secondaryLoggerFilename "backup.log"
    Logger -message "Critical error occurred" -severity "ERROR"
    # Sets up dual logging and logs an error message
#>

<#
.SYNOPSIS
    Initializes the logger with specified settings.

.DESCRIPTION
    Sets up the logging configuration including module name and log file paths.
    If not specified, attempts to determine module name from the calling script.
    Creates log files with standardized naming conventions.

.PARAMETER moduleName
    Optional. The name of the module being logged. If not provided, attempts to
    determine from the calling script.

.PARAMETER loggerFilename
    Optional. The primary log file path. If not provided, generates a name based
    on the date and module name.

.PARAMETER secondaryLoggerFilename
    Optional. A secondary log file path for duplicate logging.

.EXAMPLE
    InitializeLogger -moduleName "MyModule" -loggerFilename "app.log"
    # Initializes logging for MyModule to app.log

.EXAMPLE
    InitializeLogger -moduleName "MyModule" -loggerFilename "primary.log" -secondaryLoggerFilename "backup.log"
    # Sets up logging with both primary and secondary log files
#>
function InitializeLogger {
    param(
        [string]$moduleName = "",
        [string]$loggerFilename = "",
        [string]$secondaryLoggerFilename = ""
    )

    if ($moduleName.Length -gt 0) {
        $global:ModuleName = $moduleName
    }

    if ($$.Length -gt 0 -and $global:ModuleName.Length -eq 0) {
        try {
            $global:ModuleName = $$.Split("\")[$$.Split("\").Length - 1].Trim()
        }
        catch {
            $global:ModuleName = ""
        }
    }

    $dtLog = get-date -Format("yyyyMMdd").ToString()
    if ($loggerFilename -eq "" -and $invocation.MyCommand.Name -ne "") {
        $scriptName = $global:ModuleName.Replace(".ps1", "").Replace(".PS1", "")

        $loggerFilename = $defaultPath + "\" + (get-date -Format("yyyyMMdd").ToString()) + "_" + $scriptName + ".log"
    }

    if ($loggerFilename.Contains("\\") -or $loggerFilename.Substring(1, 2).Contains(":\") -or $loggerFilename.StartsWith(".\")) {
        $global:LoggerFilename = $loggerFilename
    }
    else {
        $global:LoggerFilename = $defaultPath + "\" + $dtLog + "_" + $loggerFilename
    }

    if ($secondaryLoggerFilename.Length -gt 0) {
        if ($secondaryLoggerFilename.Contains("\\") -or $secondaryLoggerFilename.Substring(0, 1).Contains(":\") -or $secondaryLoggerFilename.StartsWith(".\")) {
            $global:SecondaryLoggerFilename = $secondaryLoggerFilename
        }
        else {
            $global:SecondaryLoggerFilename = $defaultPath + "\" + (get-date -Format("yyyyMMdd").ToString()) + "_elma.log"
        }
    }
}

<#
.SYNOPSIS
    Logs a message with timestamp and severity level.

.DESCRIPTION
    Writes a formatted log message to the configured log file(s).
    Each log entry includes timestamp, severity level, module name, and message.
    Can write to both primary and secondary log files if configured.

.PARAMETER message
    The message to log.

.PARAMETER severity
    Optional. The severity level of the message. Valid values are:
    "INFO", "WARNING", "ERROR", "FATAL". Defaults to "INFO".

.EXAMPLE
    Logger -message "Process started" -severity "INFO"
    # Logs an informational message

.EXAMPLE
    Logger -message "Operation failed" -severity "ERROR"
    # Logs an error message
#>
function Logger {
    param(
        [string]$message,
        $severity = "INFO"
    )
    if ($global:LoggerFilename.Length -eq 0) {
        InitializeLogger
    }


    $validvalues = @("INFO", "WARNING", "ERROR", "FATAL")
    if ($validvalues -notcontains $severity) {
        $severity = "INFO"
    }

    $dt = get-date -Format("yyyy-MM-dd HH:mm:ss.ffff").ToString()
    
    if ($$.Length -gt 0 -and $global:ModuleName.Length -eq 0) {
        try {
            $global:ModuleName = $$.Split("\")[$$.Split("\").Length - 1].Trim()
        }
        catch {
            $global:ModuleName = ""
        }
    }
    $logmsg = $dt + "`|" + $severity.Trim().ToUpper() + "`|" + $global:ModuleName + "`|" + $message
    
    Write-Host $logmsg
    Add-Content -Path $global:LoggerFilename -Value $logmsg

    if ($global:SecondaryLoggerFilename.Length -gt 0) {
        Add-Content -Path $global:SecondaryLoggerFilename -Value $logmsg
    }
}    

Export-ModuleMember -Function InitializeLogger
Export-ModuleMember -Function Logger


