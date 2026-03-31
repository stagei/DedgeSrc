param(
    [Parameter(Mandatory = $true)]
    [string]$Message,

    [Parameter(Mandatory = $false)]
    [ValidateSet("INFO", "WARNING", "ERROR", "DEBUG", "SUCCESS")]
    [string]$Level = "INFO",

    [Parameter(Mandatory = $false)]
    [string]$LogFile,

    [Parameter(Mandatory = $false)]
    [switch]$NoTimestamp,

    [Parameter(Mandatory = $false)]
    [switch]$NoConsole,

    [Parameter(Mandatory = $false)]
    [string]$Color = "White"
)

<#
.SYNOPSIS
    Write log messages from batch files with timestamp and level support.

.DESCRIPTION
    This script provides a standardized way to log messages from batch files.
    It can write to both console and log files with timestamps and different log levels.

.PARAMETER Message
    The message to log.

.PARAMETER Level
    The log level (INFO, WARNING, ERROR, DEBUG, SUCCESS). Default is INFO.

.PARAMETER LogFile
    Optional log file path. If not specified, only writes to console.

.PARAMETER NoTimestamp
    Skip adding timestamp to the message.

.PARAMETER NoConsole
    Skip writing to console (only write to log file).

.PARAMETER Color
    Console text color for the message.

.EXAMPLE
    .\Write-LogMessageBat.ps1 -Message "Starting process" -Level "INFO"

.EXAMPLE
    .\Write-LogMessageBat.ps1 -Message "Error occurred" -Level "ERROR" -LogFile "C:\logs\app.log"

.EXAMPLE
    .\Write-LogMessageBat.ps1 -Message "Process completed" -Level "SUCCESS" -Color "Green"
#>

# function Write-LogMessageBat {
#     param(
#         [string]$Message,
#         [string]$Level,
#         [string]$LogFile,
#         [bool]$NoTimestamp,
#         [bool]$NoConsole,
#         [string]$Color
#     )

#     try {
#         # Generate timestamp if not disabled
#         $timestamp = ""
#         if (-not $NoTimestamp) {
#             $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
#         }

#         # Format the message
#         $formattedMessage = ""
#         if ($timestamp) {
#             $formattedMessage = "[$timestamp] [$Level] $Message"
#         } else {
#             $formattedMessage = "[$Level] $Message"
#         }

#         # Write to console unless disabled
#         if (-not $NoConsole) {
#             $consoleColor = switch ($Level.ToUpper()) {
#                 "ERROR" { "Red" }
#                 "WARNING" { "Yellow" }
#                 "SUCCESS" { "Green" }
#                 "DEBUG" { "Cyan" }
#                 "INFO" { $Color }
#                 default { $Color }
#             }

#             Write-Host $formattedMessage -ForegroundColor $consoleColor
#         }

#         # Write to log file if specified
#         if ($LogFile) {
#             # Ensure log directory exists
#             $logDir = Split-Path -Path $LogFile -Parent
#             if ($logDir -and -not (Test-Path -Path $logDir)) {
#                 New-Item -Path $logDir -ItemType Directory -Force | Out-Null
#             }

#             # Append to log file
#             Add-Content -Path $LogFile -Value $formattedMessage -Encoding UTF8
#         }

#         return $true
#     }
#     catch {
#         Write-Error "Failed to write log message: $($_.Exception.Message)"
#         return $false
#     }
# }

# Main execution
Import-Module -Name GlobalFunctions -Force
try {
    Write-LogMessage -Message $Message -Level $Level -LogFile $LogFile -NoTimestamp $NoTimestamp.IsPresent -NoConsole $NoConsole.IsPresent -Color $Color

    if ($result) {
        exit 0
    } else {
        exit 1
    }
}
catch {
    Write-Error "Script execution failed: $($_.Exception.Message)"
    exit 1
}

