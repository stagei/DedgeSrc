<#
.SYNOPSIS
    Parses IBM DB2 diagnostic log files and extracts Warning/Error/Severe/Critical entries as structured JSON.

.DESCRIPTION
    Searches for db2diag.log files in the specified directory, identifies log blocks by timestamp pattern,
    filters for Warning, Error, Severe, and Critical severity levels, and exports each entry
    as a separate JSON file with structured properties.
    
    The script automatically detects DB2 instance names from the file paths (DB2FED, DB2HFED, DB2HST, etc.)
    and organizes snapshots and output by instance name.
    
    When MaxExports is 0 (unlimited), the script tracks the last processed line number
    and the file creation datetime in a user environment variable per instance, allowing
    subsequent runs to resume from where they left off. If the file creation time changes
    (indicating the log was archived and a new file created), the script automatically
    resets to line 1. This is useful for scheduled runs (e.g., every 10 minutes).
    
    Optionally sends alerts to a REST API service for centralized monitoring.

.PARAMETER SearchDirectory
    Directory to search for db2diag.log files. If set to the default test path, the script
    automatically attempts to detect the DB2 installation path using 'db2set DB2INSTPROF' command
    and extracts the path up to and including the first 'DB2' folder (e.g., C:\ProgramData\IBM\DB2).
    If detection fails, it uses the provided default path.

.PARAMETER OutputFolder
    Base folder where JSON files will be exported. Subfolders are created per DB2 instance.
    Defaults to current directory.

.PARAMETER MaxExports
    Maximum number of JSON files to export per instance (for testing). Set to 0 for unlimited/continuous mode.

.PARAMETER StateVariablePrefix
    Prefix for user environment variables to store the last processed line number per instance.
    Only used when MaxExports is 0. Defaults to 'DB2DIAG_LASTLINE_'.
    Full variable name will be: {Prefix}{InstanceName}
    State format: <file_creation_datetime>;<last_line> (e.g., "2026-01-08 15:30:45;12345")
    This tracks both the file creation time and last line to handle log file archiving.

.PARAMETER ResetState
    When specified, resets all state variables and starts processing from line 1.

.PARAMETER SendToAlertApi
    When true (default), sends each detected Warning/Error/Severe/Critical entry to the local Alert API
    at http://localhost:8999/api/Alerts for centralized monitoring and distribution.
    The API health is checked at startup; if unavailable, API logging is automatically disabled.

.PARAMETER MinimumSeverityLevel
    Minimum severity level to export. Can be specified as a level name (e.g., "Error", "Warning") or
    a priority number (0-4, where 0=Critical, 1=Severe, 2=Error, 3=Warning, 4=Info).
    All levels with priority <= the specified minimum will be exported.
    Example: Setting to 2 or "Error" will export Error, Severe, and Critical levels.
    If not specified, all standard levels (Warning, Error, Severe, Critical, Alert, Emergency) are exported.
    Note: "Event" level is always exported regardless of this filter.

.PARAMETER ExportCommonFile
    When specified, exports all entries to a common JSON file (e.g., db2diag_2026-01-05.json)
    in addition to individual JSON files. The common file groups all exported entries together
    with metadata including export date, total entries, and instances processed.

.PARAMETER UseSubfolder
    When true, creates a subfolder based on the db2diag.log last write time using the format
    'yyyyMMdd_HHmmss' to organize exports by time. By default (false), JSON files are exported
    directly to the instance folder without creating a subfolder.

.PARAMETER FileEncoding
    Character encoding to use when reading db2diag.log files. Defaults to 'Windows1252' (ANSI/Western European).
    Valid values: Windows1252, UTF8, UTF7, UTF32, Unicode, ASCII, Default.
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory = $false)]
    [string]$SearchDirectory = "",

    [Parameter(Mandatory = $false)]
    [string]$OutputFolder = "",

    [Parameter(Mandatory = $false)]
    [int]$MaxExports = 9,

    [Parameter(Mandatory = $false)]
    [string]$StateVariablePrefix = 'DB2DIAG_LASTLINE_',

    [Parameter(Mandatory = $false)]
    [switch]$ResetState,

    [Parameter(Mandatory = $false)]
    [bool]$SendToAlertApi = $true,

    [Parameter(Mandatory = $false)]
    [ValidateScript({ $_ -is [string] -or $_ -is [int] })]
    [object]$MinimumSeverityLevel = "Error",

    [Parameter(Mandatory = $false)]
    [bool]$ExportCommonFile = $true,

    [Parameter(Mandatory = $false)]
    [bool]$UseSubfolder = $false,

    [Parameter(Mandatory = $false)]
    [ValidateSet('Windows1252', 'UTF8', 'UTF7', 'UTF32', 'Unicode', 'ASCII', 'Default')]
    [string]$FileEncoding = 'Windows1252'
)

Import-Module GlobalFunctions -Force

<#
    Function: Get-Db2ProgramDataPath
    Gets the DB2 installation path from db2set DB2INSTPROF command and extracts
    the path up to and including the first "DB2" folder.
    
    Example:
    - Command output: C:\PROGRAMDATA\IBM\DB2\DB2COPY1
    - Extracted path: C:\PROGRAMDATA\IBM\DB2
    
    Returns: String path to DB2 folder, or $null if command fails or path not found
#>
function Get-Db2ProgramDataPath {
    try {
        # Call db2set DB2INSTPROF and capture output
        $db2Output = & db2set DB2INSTPROF 2>&1 | Out-String
        
        if ([string]::IsNullOrWhiteSpace($db2Output)) {
            Write-LogMessage "db2set DB2INSTPROF returned no output" -Level WARN
            return $null
        }
        
        # Trim whitespace and newlines
        $db2ProgramDataPath = $db2Output.Trim()
        
        # Find the first occurrence of "DB2" folder in the path
        # Regex pattern explanation:
        # ^          - Start of string
        # (.+?)      - Capture group: match any characters (non-greedy) - this captures everything up to DB2
        # \\DB2      - Literal backslash followed by "DB2" (included in capture group)
        # (?:\\|$)   - Non-capturing group: match either a backslash or end of string (not captured)
        # Example: C:\PROGRAMDATA\IBM\DB2\DB2COPY1 → captures "C:\PROGRAMDATA\IBM\DB2"
        if ($db2ProgramDataPath -match '^(.+?\\DB2)(?:\\|$)') {
            $extractedPath = $matches[1]
            Write-LogMessage "DB2 installation path extracted: $($extractedPath)" -Level INFO
            return $extractedPath
        }
        else {
            Write-LogMessage "Could not find DB2 folder in path: $($db2ProgramDataPath)" -Level WARN
            return $null
        }
    }
    catch {
        Write-LogMessage "Failed to execute db2set command: $($_.Exception.Message)" -Level WARN
        return $null
    }
}

function Test-Db2DiagLogExistsInSearchDirectory {
    param(
        [string]$SearchDirectory
    )
    $db2diagLogFile = Get-ChildItem -Path $SearchDirectory -Filter "db2diag.log" -Recurse -ErrorAction SilentlyContinue | Select-Object -First 1
    if ($null -ne $db2diagLogFile -and (Test-Path $db2diagLogFile.FullName)) {
        return $true
    }
    else {
        return $false
    }
}

# REST API Functions
$script:AlertApiBaseUrl = "http://localhost:8999/api"
$script:AlertApiEnabled = $false

<#
    Function: Test-AlertApiHealth
    Tests if the Alert API service is available by calling the health endpoint.
    Returns $true if API is healthy, $false otherwise.
    
    API Endpoint: GET http://localhost:8999/api/snapshot/health
#>
function Test-AlertApiHealth {
    param(
        [int]$TimeoutSeconds = 5
    )
    
    $healthUrl = "$($script:AlertApiBaseUrl)/snapshot/health"
    
    try {
        $null = Invoke-RestMethod -Uri $healthUrl -Method Get -TimeoutSec $TimeoutSeconds
        Write-LogMessage "Alert API health check passed" -Level INFO
        return $true
    }
    catch [System.Net.WebException] {
        Write-LogMessage "Alert API not available: Connection failed (timeout or service down)" -Level WARN
        return $false
    }
    catch {
        Write-LogMessage "Alert API health check failed: $($_.Exception.Message)" -Level WARN
        return $false
    }
}

<#
    Function: ConvertFrom-Db2Timestamp
    Converts a DB2 diagnostic log timestamp to a DateTime object in Norwegian timezone.
    
    DB2 timestamp format: 2025-11-17-08.12.29.807000+060
    - Date: YYYY-MM-DD
    - Time: HH.MM.SS.microseconds
    - Timezone offset: +/-MMM (minutes from UTC)
    
    Returns: DateTime in Norwegian timezone (Europe/Oslo - CET/CEST)
#>
function ConvertFrom-Db2Timestamp {
    param(
        [Parameter(Mandatory)]
        [string]$Db2Timestamp
    )
    
    try {
        <#
            Regex breakdown for DB2 timestamp:
            ^(\d{4})-(\d{2})-(\d{2})  - Date: YYYY-MM-DD (groups 1,2,3)
            -                          - Separator
            (\d{2})\.(\d{2})\.(\d{2})  - Time: HH.MM.SS (groups 4,5,6)
            \.(\d{6})                  - Microseconds (group 7)
            ([+-])(\d{3})$             - Timezone: sign and offset in minutes (groups 8,9)
        #>
        if ($Db2Timestamp -match '^(\d{4})-(\d{2})-(\d{2})-(\d{2})\.(\d{2})\.(\d{2})\.(\d{6})([+-])(\d{3})$') {
            $year = [int]$Matches[1]
            $month = [int]$Matches[2]
            $day = [int]$Matches[3]
            $hour = [int]$Matches[4]
            $minute = [int]$Matches[5]
            $second = [int]$Matches[6]
            $microseconds = [int]$Matches[7]
            $tzSign = $Matches[8]
            $tzOffsetMinutes = [int]$Matches[9]
            
            # Create local DateTime
            $milliseconds = [int]($microseconds / 1000)
            $localDateTime = [DateTime]::new($year, $month, $day, $hour, $minute, $second, $milliseconds)
            
            # Apply timezone offset to get UTC first
            $offsetMinutes = if ($tzSign -eq '+') { - $tzOffsetMinutes } else { $tzOffsetMinutes }
            $utcDateTime = $localDateTime.AddMinutes($offsetMinutes)
            
            # Convert UTC to Norwegian time (Europe/Oslo)
            # Get Norwegian timezone info
            $norwegianTz = [System.TimeZoneInfo]::FindSystemTimeZoneById('W. Europe Standard Time')
            $norwegianDateTime = [System.TimeZoneInfo]::ConvertTimeFromUtc($utcDateTime, $norwegianTz)
            
            return $norwegianDateTime
        }
        else {
            Write-LogMessage "Could not parse DB2 timestamp: $($Db2Timestamp)" -Level DEBUG
            return $null
        }
    }
    catch {
        Write-LogMessage "Error parsing DB2 timestamp: $($_.Exception.Message)" -Level DEBUG
        return $null
    }
}

<#
    Function: Send-Db2AlertToApi
    Sends a DB2 diagnostic alert to the local Alert API service.
    
    Parameters:
        - ExportObject: The parsed log entry object to send
        - InstanceName: The DB2 instance name (for metadata)
        - SourceFile: The source db2diag.log file path
    
    API Endpoint: POST http://localhost:8999/api/Alerts
#>
function Send-Db2AlertToApi {
    param(
        [Parameter(Mandatory)]
        [PSCustomObject]$ExportObject,
        
        [Parameter(Mandatory)]
        [string]$InstanceName,
        
        [Parameter(Mandatory)]
        [string]$SourceFile
    )
    
    $alertUrl = "$($script:AlertApiBaseUrl)/Alerts"
    
    # Map DB2 level to API severity (Error/Severe = Critical, Warning = Warning)
    $severityMap = @{
        'Severe'   = 'Critical'
        'Error'    = 'Critical'
        'Critical' = 'Critical'
        'Warning'  = 'Warning'
    }
    $apiSeverity = $severityMap[$ExportObject.Level]
    if ([string]::IsNullOrEmpty($apiSeverity)) { $apiSeverity = 'Informational' }
    
    # Parse DB2 timestamp and convert to Norwegian time (ISO 8601 with timezone)
    $db2NorwegianTimestamp = ConvertFrom-Db2Timestamp -Db2Timestamp $ExportObject.Timestamp
    $timestampIso = if ($null -ne $db2NorwegianTimestamp) {
        # Format as ISO 8601 with timezone offset (e.g., 2025-11-17T08:12:29.807+01:00)
        $db2NorwegianTimestamp.ToString("yyyy-MM-ddTHH:mm:ss.fffzzz")
    }
    else {
        # Fallback to current Norwegian time
        $norwegianTz = [System.TimeZoneInfo]::FindSystemTimeZoneById('W. Europe Standard Time')
        $nowNorwegian = [System.TimeZoneInfo]::ConvertTimeFromUtc([DateTime]::UtcNow, $norwegianTz)
        $nowNorwegian.ToString("yyyy-MM-ddTHH:mm:ss.fffzzz")
    }
    
    # Build externalEventCode: Unique identifier combining instance, level, and record ID
    # Format: DB2DIAG_{INSTANCE}_{LEVEL}_{RECORDID}
    $externalEventCode = "DB2DIAG_$($InstanceName)_$($ExportObject.Level)_$($ExportObject.RecordId)"
    
    # Build category: Use database name if available
    $category = if ($ExportObject.DatabaseName_DB) {
        "Database/$($ExportObject.DatabaseName_DB)"
    }
    else {
        "Database"
    }
    
    # Build message: Include instance, database, and message text
    $messageParts = @()
    $messageParts += "[$($InstanceName)]"
    if ($ExportObject.DatabaseName_DB) { $messageParts += "[$($ExportObject.DatabaseName_DB)]" }
    if ($ExportObject.MessageText_MESSAGE) {
        $messageParts += $ExportObject.MessageText_MESSAGE
    }
    else {
        $messageParts += "DB2 $($ExportObject.Level) detected"
    }
    $messageText = $messageParts -join ' '
    
    # Build metadata: Include ALL properties from the ExportObject (all as strings for API compatibility)
    $metadata = @{
        # Original DB2 fields
        Db2Timestamp                       = [string]$ExportObject.Timestamp
        Db2TimestampNorwegian              = if ($db2NorwegianTimestamp) { $db2NorwegianTimestamp.ToString("yyyy-MM-dd HH:mm:ss.fff") } else { "" }
        RecordId                           = [string]$ExportObject.RecordId
        Level                              = [string]$ExportObject.Level
        LevelPriority                      = if ($ExportObject.LevelPriority) { [string]$ExportObject.LevelPriority } else { "" }
        SourceLineNumber                   = if ($ExportObject.SourceLineNumber) { [string]$ExportObject.SourceLineNumber } else { "" }
        
        # Process information
        ProcessId_PID                      = if ($ExportObject.ProcessId_PID) { [string]$ExportObject.ProcessId_PID } else { "" }
        ThreadId_TID                       = if ($ExportObject.ThreadId_TID) { [string]$ExportObject.ThreadId_TID } else { "" }
        ProcessName_PROC                   = if ($ExportObject.ProcessName_PROC) { [string]$ExportObject.ProcessName_PROC } else { "" }
        
        # Instance and database
        InstanceName_INSTANCE              = if ($ExportObject.InstanceName_INSTANCE) { [string]$ExportObject.InstanceName_INSTANCE } else { "" }
        Instance                           = [string]$InstanceName
        PartitionNumber_NODE               = if ($ExportObject.PartitionNumber_NODE) { [string]$ExportObject.PartitionNumber_NODE } else { "" }
        DatabaseName_DB                    = if ($ExportObject.DatabaseName_DB) { [string]$ExportObject.DatabaseName_DB } else { "" }
        
        # Application information
        ApplicationHandle_APPHDL           = if ($ExportObject.ApplicationHandle_APPHDL) { [string]$ExportObject.ApplicationHandle_APPHDL } else { "" }
        ApplicationId_APPID                = if ($ExportObject.ApplicationId_APPID) { [string]$ExportObject.ApplicationId_APPID } else { "" }
        UnitOfWorkId_UOWID                 = if ($ExportObject.UnitOfWorkId_UOWID) { [string]$ExportObject.UnitOfWorkId_UOWID } else { "" }
        LastActivityId_LAST_ACTID          = if ($ExportObject.LastActivityId_LAST_ACTID) { [string]$ExportObject.LastActivityId_LAST_ACTID } else { "" }
        AuthorizationId_AUTHID             = if ($ExportObject.AuthorizationId_AUTHID) { [string]$ExportObject.AuthorizationId_AUTHID } else { "" }
        HostName_HOSTNAME                  = if ($ExportObject.HostName_HOSTNAME) { [string]$ExportObject.HostName_HOSTNAME } else { "" }
        
        # EDU information
        EngineDispatchableUnitId_EDUID     = if ($ExportObject.EngineDispatchableUnitId_EDUID) { [string]$ExportObject.EngineDispatchableUnitId_EDUID } else { "" }
        EngineDispatchableUnitName_EDUNAME = if ($ExportObject.EngineDispatchableUnitName_EDUNAME) { [string]$ExportObject.EngineDispatchableUnitName_EDUNAME } else { "" }
        
        # Function and error details
        FunctionAndProbe_FUNCTION          = if ($ExportObject.FunctionAndProbe_FUNCTION) { [string]$ExportObject.FunctionAndProbe_FUNCTION } else { "" }
        MessageText_MESSAGE                = if ($ExportObject.MessageText_MESSAGE) { [string]$ExportObject.MessageText_MESSAGE } else { "" }
        CalledFunction_CALLED              = if ($ExportObject.CalledFunction_CALLED) { [string]$ExportObject.CalledFunction_CALLED } else { "" }
        ReturnCode_RETCODE                 = if ($ExportObject.ReturnCode_RETCODE) { [string]$ExportObject.ReturnCode_RETCODE } else { "" }
        
        # Source file info
        SourceFile                         = [string]$SourceFile
        ServerName                         = [string]$env:COMPUTERNAME
    }
    
    # Add Description info if available (ZRC, Probe, Message, Level descriptions)
    if ($ExportObject.Description) {
        if ($ExportObject.Description.ZrcCode) {
            $metadata['ZrcDescription'] = if ($ExportObject.Description.ZrcCode.description) { [string]$ExportObject.Description.ZrcCode.description } else { "" }
            $metadata['ZrcCategory'] = if ($ExportObject.Description.ZrcCode.category) { [string]$ExportObject.Description.ZrcCode.category } else { "" }
            $metadata['ZrcSeverity'] = if ($ExportObject.Description.ZrcCode.severity) { [string]$ExportObject.Description.ZrcCode.severity } else { "" }
        }
        if ($ExportObject.Description.ProbeCode) {
            $metadata['ProbeDescription'] = if ($ExportObject.Description.ProbeCode.description) { [string]$ExportObject.Description.ProbeCode.description } else { "" }
            $metadata['ProbeCategory'] = if ($ExportObject.Description.ProbeCode.category) { [string]$ExportObject.Description.ProbeCode.category } else { "" }
        }
        if ($ExportObject.Description.MessageInfo) {
            $metadata['MessageDescription'] = if ($ExportObject.Description.MessageInfo.description) { [string]$ExportObject.Description.MessageInfo.description } else { "" }
            $metadata['MessageRecommendation'] = if ($ExportObject.Description.MessageInfo.recommendation) { [string]$ExportObject.Description.MessageInfo.recommendation } else { "" }
        }
        if ($ExportObject.Description.LevelInfo) {
            $metadata['LevelDescription'] = if ($ExportObject.Description.LevelInfo.description) { [string]$ExportObject.Description.LevelInfo.description } else { "" }
            $metadata['LevelAction'] = if ($ExportObject.Description.LevelInfo.action) { [string]$ExportObject.Description.LevelInfo.action } else { "" }
        }
    }
    
    # Add CallStack if present (convert array to string)
    if ($ExportObject.CallStack_CALLSTACK -and $ExportObject.CallStack_CALLSTACK.Count -gt 0) {
        $metadata['CallStack'] = [string]($ExportObject.CallStack_CALLSTACK -join "`n")
    }
    
    # Add DataSections count if present (convert to string)
    if ($ExportObject.DataSections -and $ExportObject.DataSections.Count -gt 0) {
        $metadata['DataSectionsCount'] = [string]$ExportObject.DataSections.Count
    }
    
    # Build surveillance config: Configure throttling per severity
    # Critical: Alert immediately (maxOccurrences = 0)
    # Warning: Alert after 3 occurrences within 15 minutes
    $surveillance = if ($apiSeverity -eq 'Critical') {
        @{
            maxOccurrences     = 0      # Alert immediately
            timeWindowMinutes  = 5      # Reset window
            suppressedChannels = @()    # Send to all channels
        }
    }
    else {
        @{
            maxOccurrences     = 3      # Alert on 3rd occurrence
            timeWindowMinutes  = 15     # Within 15 minutes
            suppressedChannels = @('SMS')  # Don't send SMS for warnings
        }
    }
    
    # Build the alert payload matching API schema
    $alertPayload = @{
        severity          = $apiSeverity
        externalEventCode = $externalEventCode
        category          = $category
        message           = $messageText
        timestamp         = $timestampIso
        serverName        = $env:COMPUTERNAME
        source            = "Db2-DiagTracker"
        metadata          = $metadata
        surveillance      = $surveillance
    }
    
    # Retry logic for transient failures
    $maxRetries = 3
    $retryDelaySeconds = 2
    $attempt = 0
    
    while ($attempt -lt $maxRetries) {
        $attempt++
    
    try {
        $jsonBody = $alertPayload | ConvertTo-Json -Depth 10 -Compress
            
            if ($attempt -gt 1) {
                Write-LogMessage "[$($InstanceName)] Retry attempt $attempt of $maxRetries for alert: $($externalEventCode)" -Level DEBUG
            }
        
        Write-LogMessage "[$($InstanceName)] Sending alert to API: $($externalEventCode)" -Level DEBUG
        Write-LogMessage "[$($InstanceName)] Payload (first 500 chars): $($jsonBody.Substring(0, [Math]::Min(500, $jsonBody.Length)))..." -Level DEBUG
        
        $response = Invoke-RestMethod -Uri $alertUrl -Method Post -Body $jsonBody -ContentType "application/json" -TimeoutSec 10
        
        Write-LogMessage "[$($InstanceName)] Alert sent successfully. EventId: $($response.eventId)" -Level INFO
        return $true
    }
        catch [System.Net.WebException] {
            # Network or timeout error - retry
            if ($attempt -lt $maxRetries) {
                Write-LogMessage "[$($InstanceName)] Network error (attempt $attempt/$maxRetries). Retrying in $($retryDelaySeconds)s..." -Level WARN
                Start-Sleep -Seconds $retryDelaySeconds
                $retryDelaySeconds *= 2  # Exponential backoff
                continue
            }
            else {
                # Max retries reached
                Write-LogMessage "[$($InstanceName)] Max retries ($maxRetries) reached. Network error: $($_.Exception.Message)" -Level WARN
                return $false
            }
    }
    catch {
        # Extract detailed error information
        $errorDetails = if ($_.ErrorDetails.Message) {
            try {
                $errorObj = $_.ErrorDetails.Message | ConvertFrom-Json
                $errorObj | ConvertTo-Json -Compress
            }
            catch {
                $_.ErrorDetails.Message
            }
        }
        else {
            $_.Exception.Message
        }
        
        $statusCode = if ($_.Exception.Response) {
            $_.Exception.Response.StatusCode.value__
        }
        else {
            "N/A"
        }
        
        Write-LogMessage "[$($InstanceName)] API request failed (HTTP $($statusCode)): $($errorDetails)" -Level WARN
        Write-LogMessage "[$($InstanceName)] Request payload: $($jsonBody)" -Level DEBUG
            
            # Non-network errors don't retry
        return $false
    }
}
    
    # If we get here, all retries failed
    Write-LogMessage "[$($InstanceName)] Failed to send alert after $maxRetries attempts" -Level WARN
    return $false
}


# Helper Functions
<#
    Function: Get-ZrcDescription
    Looks up a ZRC code in the message map and returns the description
    ZRC codes appear in RETCODE like: ZRC=0x00000036=54
#>
function Get-ZrcDescription {
    param(
        [string]$RetCode,
        [PSCustomObject]$Map
    )
    
    if ([string]::IsNullOrWhiteSpace($RetCode) -or $null -eq $Map) {
        return $null
    }
    
    # Extract ZRC hex code from RETCODE string (e.g., "ZRC=0x00000036=54")
    <#
        Regex: Extract ZRC hex code
        ZRC=                    - Literal "ZRC="
        (0x[0-9A-Fa-f]+)        - Group 1: Hex code starting with 0x
    #>
    if ($RetCode -match 'ZRC=(0x[0-9A-Fa-f]+)') {
        $zrcHex = $Matches[1].ToUpper()
        
        # Try exact match first
        if ($Map.zrcCodes.PSObject.Properties.Name -contains $zrcHex) {
            return $Map.zrcCodes.$zrcHex
        }
        
        # Try with lowercase 0x prefix
        $zrcLower = "0x" + $zrcHex.Substring(2).ToUpper()
        if ($Map.zrcCodes.PSObject.Properties.Name -contains $zrcLower) {
            return $Map.zrcCodes.$zrcLower
        }
        
        # Try matching just the last 4 hex digits (short form)
        $shortCode = "0x" + $zrcHex.Substring($zrcHex.Length - 4).ToUpper()
        if ($Map.zrcCodes.PSObject.Properties.Name -contains $shortCode) {
            return $Map.zrcCodes.$shortCode
        }
    }
    
    return $null
}

<#
    Function: Get-ProbeDescription
    Looks up a function/probe combination in the message map
    FUNCTION lines look like: "DB2 UDB, common communication, sqlcctcptest, probe:11"
#>
function Get-ProbeDescription {
    param(
        [string]$FunctionStr,
        [PSCustomObject]$Map
    )
    
    if ([string]::IsNullOrWhiteSpace($FunctionStr) -or $null -eq $Map) {
        return $null
    }
    
    # Extract function name and probe number
    <#
        Regex: Extract function and probe
        (\w+(?:::\w+)?),\s*probe:(\d+)   - Function name (with optional ::method), probe number
    #>
    if ($FunctionStr -match '(\w+(?:::\w+)?),\s*probe:(\d+)') {
        $funcName = $Matches[1]
        $probeNum = $Matches[2]
        $probeKey = "$($funcName):$($probeNum)"
        
        if ($Map.probeCodes.PSObject.Properties.Name -contains $probeKey) {
            return $Map.probeCodes.$probeKey
        }
    }
    
    return $null
}

<#
    Function: Get-MessageDescription
    Looks up a message pattern in the message map
#>
function Get-MessageDescription {
    param(
        [string]$Message,
        [PSCustomObject]$Map
    )
    
    if ([string]::IsNullOrWhiteSpace($Message) -or $null -eq $Map) {
        return $null
    }
    
    # Check for exact or partial match in message patterns
    foreach ($pattern in $Map.messagePatterns.PSObject.Properties.Name) {
        if ($Message -like "*$pattern*") {
            return $Map.messagePatterns.$pattern
        }
    }
    
    return $null
}

<#
    Function: Get-LevelDescription
    Looks up the severity level description
#>
function Get-LevelDescription {
    param(
        [string]$Level,
        [PSCustomObject]$Map
    )
    
    if ([string]::IsNullOrWhiteSpace($Level) -or $null -eq $Map) {
        return $null
    }
    
    if ($Map.levelDescriptions.PSObject.Properties.Name -contains $Level) {
        return $Map.levelDescriptions.$Level
    }
    
    return $null
}

<#
    Function: Get-LevelPriority
    Gets the priority value for a severity level from the message map.
    Returns the priority number, or null if level not found.
#>
function Get-LevelPriority {
    param(
        [string]$Level,
        [PSCustomObject]$Map
    )
    
    if ([string]::IsNullOrWhiteSpace($Level) -or $null -eq $Map) {
        return $null
    }
    
    $levelInfo = Get-LevelDescription -Level $Level -Map $Map
    if ($null -ne $levelInfo -and $null -ne $levelInfo.priority) {
        return [int]$levelInfo.priority
    }
    
    return $null
}

<#
    Function: Resolve-MinimumSeverityLevel
    Resolves the minimum severity level parameter to a priority number.
    Accepts either a level name (e.g., "Error", "Warning") or a priority number (e.g., 2).
    Returns the priority number, or null if invalid.
#>
function Resolve-MinimumSeverityLevel {
    param(
        [object]$InputValue,
        [PSCustomObject]$Map
    )
    
    if ($null -eq $InputValue) {
        return $null
    }
    
    # If it's already a number, return it
    if ($InputValue -is [int]) {
        return $InputValue
    }
    
    # If it's a string, try to parse as number first
    if ($InputValue -is [string]) {
        $asInt = 0
        if ([int]::TryParse($InputValue, [ref]$asInt)) {
            return $asInt
        }
        
        # Try to find the level in the map
        $priority = Get-LevelPriority -Level $InputValue -Map $Map
        if ($null -ne $priority) {
            return $priority
        }
    }
    
    Write-LogMessage "Invalid minimum severity level: $($InputValue). Use level name (e.g., 'Error', 'Warning') or priority number (0-4)." -Level WARN
    return $null
}


# API Health Check at Startup
if ($SendToAlertApi) {
    Write-LogMessage "Checking Alert API availability..." -Level INFO
    $script:AlertApiEnabled = Test-AlertApiHealth -TimeoutSeconds 5
    if (-not $script:AlertApiEnabled) {
        Write-LogMessage "Alert API is not available. API logging will be disabled for this run." -Level WARN
    }
}
else {
    Write-LogMessage "Alert API logging is disabled by parameter." -Level INFO
    $script:AlertApiEnabled = $false
}


# DB2 Instance Detection and File Discovery
<#
    Function: Get-Db2InstanceFromPath
    Determines the DB2 instance name from the file path
    Known instances: DB2FED, DB2HFED, DB2HST, DB2DBQA, DB2DOC, DB2 (default)
#>
function Get-Db2InstanceFromPath {
    param([string]$FilePath)
    
    $upperPath = $FilePath.ToUpper()
    
    if ($upperPath.Contains("DB2FED")) { return "DB2FED" }
    elseif ($upperPath.Contains("DB2HFED")) { return "DB2HFED" }
    elseif ($upperPath.Contains("DB2HST")) { return "DB2HST" }
    elseif ($upperPath.Contains("DB2DBQA")) { return "DB2DBQA" }
    elseif ($upperPath.Contains("DB2DOC")) { return "DB2DOC" }
    else { return "DB2" }
}





# Function to parse properties from log block content
function ConvertFrom-LogBlockContent {
    param(
        [Parameter(Mandatory)]
        [PSCustomObject]$Block,
        
        [Parameter(Mandatory)]
        [regex]$HeaderPattern,
        
        [Parameter(Mandatory)]
        [regex]$KeyValuePattern
    )
    
    $contentLines = $Block.RawContent -split "`n"
    $properties = @{}
    $dataSection = $null
    $callStack = [System.Collections.ArrayList]::new()
    $inCallStack = $false
    
    foreach ($line in $contentLines) {
        # Skip empty lines
        if ([string]::IsNullOrWhiteSpace($line)) { continue }
        
        # Skip the header line (already parsed)
        if ($line -match $headerPattern) {
            $dataSection = $null
            $inCallStack = $false
            continue
        }
        
        # Check for CALLSTCK section
        if ($line -match '^CALLSTCK\s*:') {
            $dataSection = $null
            $inCallStack = $true
            continue
        }
        
        # Check for DATA section header
        if ($line -match '^DATA\s+#(\d+)\s*:\s*(.+)$') {
            $dataNum = $Matches[1]
            $dataType = $Matches[2]
            $dataSection = [PSCustomObject]@{
                Number = [int]$dataNum
                Type   = $dataType.Trim()
                Lines  = [System.Collections.ArrayList]::new()
            }
            [void]$Block.DataSections.Add($dataSection)
            $inCallStack = $false
            continue
        }
        
        # If we're in a callstack, collect stack frames
        if ($inCallStack -and $line -match '^\s*\[\d+\]') {
            [void]$callStack.Add($line.Trim())
            continue
        }
        
        # If we're in a data section, capture ALL lines until we hit a property line or new section
        if ($null -ne $dataSection) {
            # Check if this line looks like a property (key:value pattern) - indicates end of DATA section
            if ($line -match $keyValuePattern) {
                # This is a property line, not data - end the data section
                $dataSection = $null
                # Fall through to process as property
            }
            else {
                # This is data content - capture it (all non-property lines are data)
            [void]$dataSection.Lines.Add($line.Trim())
            continue
            }
        }
        
        # Try to extract key-value pairs from the line (property lines)
        $inCallStack = $false
        
        # Use regex to find all key:value pairs on the line
        $kvMatches = [regex]::Matches($line, $keyValuePattern)
        foreach ($kv in $kvMatches) {
            $key = $kv.Groups[1].Value.Trim()
            $value = $kv.Groups[2].Value.Trim()
            
            # Don't overwrite if key already exists (take first occurrence)
            if (-not $properties.ContainsKey($key)) {
                $properties[$key] = $value
            }
        }
    }
    
    # Add callstack if found
    if ($callStack.Count -gt 0) {
        $properties['CALLSTACK'] = $callStack.ToArray()
    }
    
    $Block.Properties = $properties
}



###################################################################################
###################################################################################
###################################################################################
# Main
###################################################################################
###################################################################################
###################################################################################
###################################################################################



# Determine search directory
if ([string]::IsNullOrEmpty($SearchDirectory)) {
    # No SearchDirectory provided, try to detect DB2 installation path
    Write-LogMessage "No SearchDirectory provided. Attempting to detect DB2 program data path..." -Level INFO
    $db2ProgramDataPath = Get-Db2ProgramDataPath
    
    if ($(Test-IsDb2Server) -and $null -ne $db2ProgramDataPath -and (Test-Db2DiagLogExistsInSearchDirectory -SearchDirectory $db2ProgramDataPath)) {
        $SearchDirectory = $db2ProgramDataPath
        Write-LogMessage "✅ Using detected DB2 path: $($SearchDirectory)" -Level INFO
    }
    else {
        # Fall back to script root for testing
        $SearchDirectory = $PSScriptRoot
        if (Test-Db2DiagLogExistsInSearchDirectory -SearchDirectory $SearchDirectory) {
            Write-LogMessage "Using script root as test path: $($SearchDirectory)" -Level INFO
        }
        else {
            Write-LogMessage "Could not detect DB2 path containing db2diag.log" -Level ERROR
            throw "Could not find db2diag.log in detected path or script root"
        }
    }
}
else {
    # User provided SearchDirectory - validate it
    Write-LogMessage "Using user-provided SearchDirectory: $($SearchDirectory)" -Level INFO
}

# Search for db2diag.log files in the specified directory
Write-LogMessage "Searching for db2diag.log files in: $($SearchDirectory)" -Level INFO

if (-not (Test-Path $SearchDirectory)) {
    Write-LogMessage "Search directory not found: $($SearchDirectory)" -Level ERROR
    throw "Search directory not found: $SearchDirectory"
}

if ([string]::IsNullOrEmpty($OutputFolder)) {
    $OutputFolder = Get-ApplicationDataPath
}

$diagFilesFound = Get-ChildItem -Path $SearchDirectory -Filter "db2diag.log" -Recurse -ErrorAction SilentlyContinue

if ($null -eq $diagFilesFound -or $diagFilesFound.Count -eq 0) {
    Write-LogMessage "No db2diag.log files found in: $($SearchDirectory)" -Level WARN
    return [PSCustomObject]@{
        SearchDirectory = $SearchDirectory
        FilesFound      = 0
        Message         = "No db2diag.log files found"
    }
}

Write-LogMessage "Found $(@($diagFilesFound).Count) db2diag.log file(s)" -Level INFO

# Get application data path for storing snapshots
$appDataPath = Get-ApplicationDataPath
$snapshotBaseFolder = Join-Path $appDataPath "Db2DiagSnapshots"

# Load Message Map (once, outside loop for performance)
$messageMapPath = Join-Path $PSScriptRoot 'db2DiagMessageMap.json'
$messageMap = $null
if (Test-Path $messageMapPath) {
    try {
        $messageMap = Get-Content -Path $messageMapPath -Raw | ConvertFrom-Json
        Write-LogMessage "Loaded message map from: $($messageMapPath)" -Level INFO
    }
    catch {
        Write-LogMessage "Failed to load message map: $($_.Exception.Message)" -Level WARN
    }
}
else {
    Write-LogMessage "Message map not found at: $($messageMapPath)" -Level WARN
}

# Compile regex patterns once (outside loop for performance)
$headerPattern = [regex]::new('^(\d{4}-\d{2}-\d{2}-\d{2}\.\d{2}\.\d{2}\.\d{6}[+-]\d{3})\s+(\S+)\s+LEVEL:\s*(\w+)', [System.Text.RegularExpressions.RegexOptions]::Compiled)
$keyValuePattern = [regex]::new('(\w+)\s*:\s*([^\s].*?)(?=\s{2,}\w+\s*:|$)', [System.Text.RegularExpressions.RegexOptions]::Compiled)

# Process each found db2diag.log file
$allResults = @()
$isContinuousMode = ($MaxExports -eq 0)
$commonExportEntries = [System.Collections.ArrayList]::new()

# Iterate through each found db2diag.log file, parse log blocks, filter by
# severity level, and export matching entries to JSON files.

$instanceCount = 0
foreach ($diagFile in $diagFilesFound) {
    $instanceCount++
    
    # Update overall progress
    Write-Progress -Id 0 -Activity "Processing DB2 Instances" -Status "Instance $instanceCount of $($diagFilesFound.Count): $($diagFile.DirectoryName)" -PercentComplete (($instanceCount / $diagFilesFound.Count) * 100)
    
    $instanceName = Get-Db2InstanceFromPath -FilePath $diagFile.DirectoryName
    $stateVariableName = "$($StateVariablePrefix)$($instanceName)"
    
    Write-LogMessage "Processing instance: $($instanceName) - File: $($diagFile.FullName)" -Level INFO
    
    try {
    
    # State Management for this instance
    # State format: <file_creation_datetime>;<last_line>
    # Example: 2026-01-08 15:30:45;12345
    $startLine = 1
    $currentFileCreationTime = $diagFile.CreationTime.ToString('yyyy-MM-dd HH:mm:ss')
    
    if ($ResetState) {
        [Environment]::SetEnvironmentVariable($stateVariableName, $null, 'User')
        Write-LogMessage "Reset state variable: $($stateVariableName)" -Level INFO
    }
    
    # Always load and use saved state if available (even when testing with MaxExports > 0)
    $savedState = [Environment]::GetEnvironmentVariable($stateVariableName, 'User')
    
    # Log environment variable state at start
    if (-not [string]::IsNullOrWhiteSpace($savedState)) {
        Write-LogMessage "[$($instanceName)] 📋 Environment variable at start: '$($stateVariableName)' = '$($savedState)'" -Level INFO
    }
    else {
        Write-LogMessage "[$($instanceName)] 📋 Environment variable at start: '$($stateVariableName)' = (not set)" -Level INFO
    }
    
    if (-not [string]::IsNullOrWhiteSpace($savedState)) {
            # Parse state: <creation_datetime>;<last_line>
            $stateParts = $savedState -split ';'
            if ($stateParts.Count -eq 2) {
                $savedFileCreationTime = $stateParts[0]
                $savedLineStr = $stateParts[1]
                
                # Validate saved line number
                $savedLineNum = 0
                if ([int]::TryParse($savedLineStr, [ref]$savedLineNum) -and $savedLineNum -gt 0) {
                    # Compare file creation times
                    if ($savedFileCreationTime -eq $currentFileCreationTime) {
                        # Same file - resume from saved line
                        $startLine = $savedLineNum
                        Write-LogMessage "[$($instanceName)] Resuming from line $($startLine) (file creation: $($currentFileCreationTime))" -Level INFO
                    }
                    else {
                        # Different file (archived and new file created) - immediately update environment variable
                        Write-LogMessage "[$($instanceName)] File creation time changed (saved: $($savedFileCreationTime), current: $($currentFileCreationTime)). File was archived." -Level WARN
                        $startLine = 1
                        $stateValue = "$($currentFileCreationTime);1"
                        [Environment]::SetEnvironmentVariable($stateVariableName, $stateValue, 'User')
                        Write-LogMessage "[$($instanceName)] ✅ Immediately updated environment variable to new file: '$($stateVariableName)' = '$($stateValue)'" -Level INFO
                    }
                }
                else {
                    # Invalid line number in state - reset environment variable immediately
                    Write-LogMessage "[$($instanceName)] Invalid state format (line number: '$($savedLineStr)'). Starting from line 1." -Level WARN
                    $startLine = 1
                    $stateValue = "$($currentFileCreationTime);1"
                    [Environment]::SetEnvironmentVariable($stateVariableName, $stateValue, 'User')
                    Write-LogMessage "[$($instanceName)] ✅ Reset environment variable to current file: '$($stateVariableName)' = '$($stateValue)'" -Level INFO
                }
            }
            else {
                # Old format or corrupted state - reset environment variable immediately
                Write-LogMessage "[$($instanceName)] Invalid or old state format detected. Starting from line 1." -Level WARN
                $startLine = 1
                $stateValue = "$($currentFileCreationTime);1"
                [Environment]::SetEnvironmentVariable($stateVariableName, $stateValue, 'User')
                Write-LogMessage "[$($instanceName)] ✅ Reset environment variable to current file: '$($stateVariableName)' = '$($stateValue)'" -Level INFO
            }
    }
    else {
        # No saved state - initialize environment variable immediately
        Write-LogMessage "[$($instanceName)] No saved state. Starting from line 1." -Level INFO
        $startLine = 1
        $stateValue = "$($currentFileCreationTime);1"
        [Environment]::SetEnvironmentVariable($stateVariableName, $stateValue, 'User')
        Write-LogMessage "[$($instanceName)] ✅ Initialized environment variable: '$($stateVariableName)' = '$($stateValue)'" -Level INFO
    }
    
    
    # Copy file to ApplicationDataPath snapshot folder
    $instanceSnapshotFolder = Join-Path $snapshotBaseFolder $instanceName
    if (-not (Test-Path $instanceSnapshotFolder)) {
        New-Item -Path $instanceSnapshotFolder -ItemType Directory -Force | Out-Null
        Write-LogMessage "Created snapshot folder: $($instanceSnapshotFolder)" -Level INFO
    }
    # Clean up old snapshot files BEFORE creating new one (keep last 7 days)
    try {
        $cutoffDate = (Get-Date).AddDays(-7)
        $oldSnapshots = Get-ChildItem -Path $instanceSnapshotFolder -Filter "db2diag_*.log" -ErrorAction SilentlyContinue | Where-Object { $_.LastWriteTime -lt $cutoffDate }
        if ($oldSnapshots.Count -gt 0) {
            Write-LogMessage "[$($instanceName)] Cleaning up $($oldSnapshots.Count) old snapshot(s) older than 7 days" -Level INFO
            foreach ($oldFile in $oldSnapshots) {
                Remove-Item $oldFile.FullName -Force -ErrorAction SilentlyContinue
                Write-LogMessage "[$($instanceName)] Deleted old snapshot: $($oldFile.Name)" -Level DEBUG
            }
        }
    }
    catch {
        Write-LogMessage "[$($instanceName)] Warning: Could not clean up old snapshots: $($_.Exception.Message)" -Level WARN
    }
    
    # Create snapshot with current timestamp (not file's LastWriteTime to avoid immediate cleanup)
    $snapshotFileName = "db2diag_$(Get-Date -Format 'yyyyMMdd_HHmmss').log"
    $tempFilePath = Join-Path $instanceSnapshotFolder $snapshotFileName
    
    try {
        Copy-Item -Path $diagFile.FullName -Destination $tempFilePath -Force
        Write-LogMessage "[$($instanceName)] Created snapshot: $($tempFilePath)" -Level INFO
    }
    catch {
        Write-LogMessage "[$($instanceName)] Failed to create snapshot: $($_.Exception.Message). Skipping." -Level ERROR
        continue
    }
    
    
    # Create instance-specific output folder
    $instanceOutputFolder = Join-Path $OutputFolder $instanceName
    if (-not (Test-Path $instanceOutputFolder)) {
        New-Item -Path $instanceOutputFolder -ItemType Directory -Force | Out-Null
        Write-LogMessage "Created output folder: $($instanceOutputFolder)" -Level INFO
    }
    
    # Determine export folder: subfolder by date/time or directly in instance folder
    if ($UseSubfolder) {
        # Create subfolder based on last write time of db2diag.log file
        $lastWriteTimeFolder = ($diagFile.LastWriteTime).ToString('yyyyMMdd_HHmmss')
        $exportSubfolder = Join-Path $instanceOutputFolder $lastWriteTimeFolder
        if (-not (Test-Path $exportSubfolder)) {
            New-Item -Path $exportSubfolder -ItemType Directory -Force | Out-Null
            Write-LogMessage "Created export subfolder: $($exportSubfolder)" -Level INFO
        }
        else {
            Write-LogMessage "Using existing export subfolder: $($exportSubfolder)" -Level INFO
        }
    }
    else {
        # Export directly to instance folder (default)
        $exportSubfolder = $instanceOutputFolder
        Write-LogMessage "Exporting to instance folder (no subfolder): $($exportSubfolder)" -Level INFO
    }
    
    # Resolve minimum severity level filter (message map and regex patterns loaded outside loop)
    $minimumPriority = Resolve-MinimumSeverityLevel -InputValue $MinimumSeverityLevel -Map $messageMap

    # Build target levels based on minimum priority filter
    # "Event" level is always included regardless of filter
    $targetLevels = [System.Collections.ArrayList]::new()

    if ($null -eq $minimumPriority) {
        # No filter - include all standard levels from message map
        if ($null -ne $messageMap -and $null -ne $messageMap.levelDescriptions) {
            foreach ($levelName in $messageMap.levelDescriptions.PSObject.Properties.Name) {
                [void]$targetLevels.Add($levelName)
            }
        }
    }
    else {
        # Filter by priority - include all levels with priority <= minimumPriority
        if ($null -ne $messageMap -and $null -ne $messageMap.levelDescriptions) {
            foreach ($levelName in $messageMap.levelDescriptions.PSObject.Properties.Name) {
                $levelInfo = $messageMap.levelDescriptions.$levelName
                if ($null -ne $levelInfo.priority -and [int]$levelInfo.priority -le $minimumPriority) {
                    [void]$targetLevels.Add($levelName)
                }
            }
        }
    }

    # Always include "Event" level regardless of filter
    if (-not ($targetLevels -contains 'Event')) {
        [void]$targetLevels.Add('Event')
    }

    if ($null -ne $minimumPriority) {
        Write-LogMessage "Filtering by minimum severity priority: $($minimumPriority) (levels: $($targetLevels -join ', '))" -Level INFO
    }
    else {
        Write-LogMessage "No severity filter applied. Including all levels: $($targetLevels -join ', ')" -Level INFO
    }

    Write-LogMessage "[$($instanceName)] Parsing snapshot file: $($tempFilePath)" -Level INFO

    $totalLines = 0
    $lastProcessedLine = $startLine
    $lastBlockEndLine = 0
    
    # Map encoding parameter to .NET encoding object
    $encodingObj = switch ($FileEncoding) {
        'Windows1252' { [System.Text.Encoding]::GetEncoding(1252) }  # ANSI/Western European (default for DB2 logs)
        'UTF8'        { [System.Text.Encoding]::UTF8 }
        'UTF7'        { [System.Text.Encoding]::UTF7 }
        'UTF32'       { [System.Text.Encoding]::UTF32 }
        'Unicode'     { [System.Text.Encoding]::Unicode }
        'ASCII'       { [System.Text.Encoding]::ASCII }
        'Default'     { [System.Text.Encoding]::Default }
        default       { [System.Text.Encoding]::GetEncoding(1252) }  # Default to Windows-1252
    }
    
    # Read all lines from snapshot file
    Write-LogMessage "[$($instanceName)] Reading snapshot file into memory..." -Level INFO
    $lines = Get-Content -Path $tempFilePath -Encoding ([System.Text.Encoding]::GetEncoding($encodingObj.CodePage).WebName)
    $totalLines = $lines.Count
    Write-LogMessage "[$($instanceName)] File contains $($totalLines) lines" -Level INFO
    
    # Sanity check: If startLine is beyond total lines, reset to line 1
    if ($startLine -gt $totalLines) {
        Write-LogMessage "[$($instanceName)] Start line $($startLine) is beyond file length $($totalLines). Resetting to line 1." -Level WARN
        $startLine = 1
    }
    
    if ($startLine -gt 1) {
        $linesSkipped = $startLine - 1
        Write-LogMessage "[$($instanceName)] Skipping $($linesSkipped) lines (starting from line $($startLine), previously exported blocks)" -Level INFO
    }
    
    # Optimized single-pass parsing: Find headers, build blocks, and process immediately
    Write-LogMessage "[$($instanceName)] Searching and processing blocks with matching severity levels..." -Level INFO
    Write-LogMessage "[$($instanceName)] Target levels: $($targetLevels -join ', ')" -Level DEBUG
    
    # Start timer for performance statistics
    $processingStartTime = Get-Date
    
    # Single-pass: search, build, and process blocks immediately
    $blocksProcessed = 0
    $exportCount = 0
    $apiAlertCount = 0
    $lastExportedBlock = $null
    
    for ($i = ($startLine - 1); $i -lt $totalLines; $i++) {
        # Early exit if we've reached MaxExports limit
        if ($MaxExports -gt 0 -and $blocksProcessed -ge $MaxExports) {
            Write-LogMessage "[$($instanceName)] Reached MaxExports limit ($($MaxExports)) at line $($i + 1), stopping search" -Level INFO
            break
        }
        
        $line = $lines[$i]
        
        # Fast pre-filter: skip lines that don't contain "LEVEL:"
        if (-not $line.Contains("LEVEL:")) {
            continue
        }
        
        # Check if line matches header pattern
        if ($line -match $headerPattern) {
            $level = $Matches[3]  # Extract level from regex match
            
            # Check if this level is in our target levels
            if ($level -in $targetLevels) {
                # Found a matching header - build block immediately
                $blocksProcessed++
                
                # Update progress every 10 blocks
                if ($blocksProcessed % 10 -eq 0 -or $blocksProcessed -eq 1) {
                    Write-Progress -Id 1 -Activity "Processing blocks for $($instanceName)" -Status "Found and processing $blocksProcessed blocks" -PercentComplete -1
                }
                
                $headerLineNumber = $i + 1  # 1-based line number
                $timestamp = $Matches[1]
                $recordId = $Matches[2]
                
                # Build block by reading lines from header until blank line or EOF
                $blockStartLine = $headerLineNumber
                $currentLines = [System.Collections.ArrayList]::new()
                [void]$currentLines.Add($line)
                
                # Read forward from line after header until blank line or EOF
                for ($j = $i + 1; $j -lt $totalLines; $j++) {
                    $blockLine = $lines[$j]
                    
                    # Stop at blank line (marks end of block)
                    if ([string]::IsNullOrWhiteSpace($blockLine)) {
                        $i = $j  # Update outer loop index to skip processed lines
                        break
                    }
                    
                    [void]$currentLines.Add($blockLine)
                    $i = $j  # Update outer loop index
                }
                
                # Create block object
                $blockEndLine = $blockStartLine + $currentLines.Count - 1
                $lastBlockEndLine = $blockEndLine
                $lastProcessedLine = $blockEndLine
                
                $block = [PSCustomObject]@{
                    Timestamp       = $timestamp
                    RecordId        = $recordId
                    Level           = $level
                    LineNumber      = $blockStartLine
                    EndLineNumber   = $blockEndLine
                    Properties      = @{}
                    RawContent      = ($currentLines -join "`n")
                    DataSections    = [System.Collections.ArrayList]::new()
                }
                
                # IMMEDIATELY PROCESS THIS BLOCK
    # Parse properties for this block
                ConvertFrom-LogBlockContent -Block $block -HeaderPattern $headerPattern -KeyValuePattern $keyValuePattern
    
    # Look up descriptions from message map
    $zrcInfo = Get-ZrcDescription -RetCode $block.Properties['RETCODE'] -Map $messageMap
    $probeInfo = Get-ProbeDescription -FunctionStr $block.Properties['FUNCTION'] -Map $messageMap
    $messageInfo = Get-MessageDescription -Message $block.Properties['MESSAGE'] -Map $messageMap
    $levelInfo = Get-LevelDescription -Level $block.Level -Map $messageMap
    
    # Build description info object
    $descriptionInfo = $null
    if ($null -ne $zrcInfo -or $null -ne $probeInfo -or $null -ne $messageInfo -or $null -ne $levelInfo) {
        $descriptionInfo = [PSCustomObject]@{
                        ZrcCode     = if ($zrcInfo) { $zrcInfo } else { $null }
                        ProbeCode   = if ($probeInfo) { $probeInfo } else { $null }
                        MessageInfo = if ($messageInfo) { $messageInfo } else { $null }
                        LevelInfo   = if ($levelInfo) { $levelInfo } else { $null }
                    }
                }
                
                # Convert DB2 timestamp to Norwegian time for display
                $norwegianTimestamp = ConvertFrom-Db2Timestamp -Db2Timestamp $block.Timestamp
                $norwegianTimestampString = if ($norwegianTimestamp) {
                    $norwegianTimestamp.ToString("yyyy-MM-dd HH:mm:ss.fff zzz")
                }
                else {
                    $block.Timestamp
                }
                
                # Create the export object with structured properties
                $exportObject = [PSCustomObject]@{
                    Timestamp                          = $block.Timestamp
                    TimestampNorwegian                 = $norwegianTimestampString
                    TimestampParsed                    = $norwegianTimestamp
                    RecordId                           = $block.RecordId
                    Level                              = $block.Level
                    LevelPriority                      = if ($levelInfo) { $levelInfo.priority } else { $null }
                    SourceLineNumber                   = $block.LineNumber
                    Description                        = $descriptionInfo
                    ProcessId_PID                      = $block.Properties['PID']
                    ThreadId_TID                       = $block.Properties['TID']
                    ProcessName_PROC                   = $block.Properties['PROC']
                    InstanceName_INSTANCE              = $block.Properties['INSTANCE']
                    PartitionNumber_NODE               = $block.Properties['NODE']
                    DatabaseName_DB                    = $block.Properties['DB']
                    ApplicationHandle_APPHDL           = $block.Properties['APPHDL']
                    ApplicationId_APPID                = $block.Properties['APPID']
                    UnitOfWorkId_UOWID                 = $block.Properties['UOWID']
                    LastActivityId_LAST_ACTID          = $block.Properties['LAST_ACTID']
                    AuthorizationId_AUTHID             = $block.Properties['AUTHID']
                    HostName_HOSTNAME                  = $block.Properties['HOSTNAME']
                    EngineDispatchableUnitId_EDUID     = $block.Properties['EDUID']
                    EngineDispatchableUnitName_EDUNAME = $block.Properties['EDUNAME']
                    FunctionAndProbe_FUNCTION          = $block.Properties['FUNCTION']
                    MessageText_MESSAGE                = $block.Properties['MESSAGE']
                    CalledFunction_CALLED              = $block.Properties['CALLED']
                    ReturnCode_RETCODE                 = $block.Properties['RETCODE']
                    CallStack_CALLSTACK                = $block.Properties['CALLSTACK']
                    DataSections                       = @($block.DataSections | ForEach-Object {
                        [PSCustomObject]@{
                            Number = $_.Number
                            Type   = $_.Type
                            Data   = $_.Lines.ToArray()
                        }
                    })
                    RawContentLines                    = @($block.RawContent -split "`n")
                }
                
                # Generate filename based on timestamp and record ID
                $safeTimestamp = $block.Timestamp -replace '[:\.]', '-'
                $fileName = "db2diag_$($safeTimestamp)_$($block.RecordId).json"
                $outputPath = Join-Path $exportSubfolder $fileName
                
                # Check if file already exists and is recent (within last hour) - skip if so
                $skipExport = $false
                if (Test-Path $outputPath) {
                    $existingFile = Get-Item $outputPath
                    if ($existingFile.LastWriteTime -gt (Get-Date).AddHours(-1)) {
                        $skipExport = $true
                    }
                }
                
                if (-not $skipExport) {
                    # Export to JSON
                    try {
                        $exportObject | ConvertTo-Json -Depth 10 | Out-File -FilePath $outputPath -Encoding UTF8
                        $exportCount++
                        $lastExportedBlock = $block
                        
                        # Add to common export collection if enabled
                        if ($ExportCommonFile) {
                            [void]$commonExportEntries.Add($exportObject)
                        }
                    }
                    catch {
                        Write-LogMessage "[$($instanceName)] Failed to export block at line $($block.LineNumber): $($_.Exception.Message)" -Level ERROR -Exception $_
                    }
                }
                
                # Send alert to API if enabled and healthy
                if ($script:AlertApiEnabled) {
                    $apiResult = Send-Db2AlertToApi -ExportObject $exportObject -InstanceName $instanceName -SourceFile $diagFile.FullName
                    if ($apiResult) { $apiAlertCount++ }
                }
            }
        }
    }
    
    # Clear progress bar
    Write-Progress -Id 1 -Activity "Processing blocks for $($instanceName)" -Completed
    
    # Calculate processing statistics
    $processingEndTime = Get-Date
    $processingDuration = $processingEndTime - $processingStartTime
    $linesProcessed = if ($lastProcessedLine -gt 0) { $lastProcessedLine - $startLine + 1 } else { 0 }
    $processingRate = if ($processingDuration.TotalSeconds -gt 0) { [math]::Round($linesProcessed / $processingDuration.TotalSeconds, 0) } else { 0 }
    
    Write-LogMessage "[$($instanceName)] Processed $($blocksProcessed) blocks, exported $($exportCount) to JSON" -Level INFO
    Write-LogMessage "[$($instanceName)] ⏱️  Performance: Processed $($linesProcessed) lines (from $($startLine) to $($lastProcessedLine)) in $($processingDuration.TotalSeconds.ToString('F2')) seconds ($($processingRate) lines/sec)" -Level INFO
    
    # If no blocks were found, update last processed line to end of file
    if ($blocksProcessed -eq 0) {
        $lastProcessedLine = $totalLines
        $lastBlockEndLine = $totalLines
    }

    # Copy snapshot to network share if on DB2 server and matching blocks found
    if ($blocksProcessed -gt 0 -and (Test-IsDb2Server)) {
        try {
            $serverName = $env:COMPUTERNAME
            $networkShareBase = "C:\opt\src\DedgeSrc\DedgeSystemTools\Folders\Commonlogging\Db2\Server"
            $networkSharePath = Join-Path $networkShareBase "$($serverName)\$($instanceName)"
            
            # Create folder structure if it doesn't exist
            if (-not (Test-Path $networkSharePath)) {
                Write-LogMessage "[$($instanceName)] Creating network share folder: $($networkSharePath)" -Level INFO
                New-Item -Path $networkSharePath -ItemType Directory -Force | Out-Null
            }
            
            # Copy snapshot file to network share
            $snapshotFileName = Split-Path $tempFilePath -Leaf
            $networkDestination = Join-Path $networkSharePath $snapshotFileName
            Write-LogMessage "[$($instanceName)] Copying snapshot to network share: $($networkDestination)" -Level INFO
            Copy-Item -Path $tempFilePath -Destination $networkDestination -Force -ErrorAction Stop
            Write-LogMessage "[$($instanceName)] ✅ Snapshot copied to network share successfully" -Level INFO
        }
        catch {
            Write-LogMessage "[$($instanceName)] ⚠️  Failed to copy snapshot to network share: $($_.Exception.Message)" -Level WARN
        }
    }
    elseif ($blocksProcessed -gt 0) {
        Write-LogMessage "[$($instanceName)] Not a DB2 server (Test-IsDb2Server = false), skipping network share copy" -Level DEBUG
    }

    # State Save for this instance
    # Save state for next run (always save, even when testing with MaxExports > 0)
    # State format: <file_creation_datetime>;<last_line>
    
    # Determine next start line based on what we processed
    if ($null -ne $lastExportedBlock) {
        # Blocks were exported - use last exported block's end line
        $nextStartLine = $lastExportedBlock.EndLineNumber + 1
        $stateValue = "$($currentFileCreationTime);$($nextStartLine)"
        [Environment]::SetEnvironmentVariable($stateVariableName, $stateValue, 'User')
        Write-LogMessage "[$($instanceName)] Saved state: Creation time: $($currentFileCreationTime), Next line: $($nextStartLine) (last exported block ended at line $($lastExportedBlock.EndLineNumber))" -Level INFO
    }
    elseif ($lastBlockEndLine -gt 0) {
        # No blocks were exported but we parsed blocks (they didn't match severity filter)
        # Use the end line of the last parsed block to avoid reprocessing
        $nextStartLine = $lastBlockEndLine + 1
        $stateValue = "$($currentFileCreationTime);$($nextStartLine)"
        [Environment]::SetEnvironmentVariable($stateVariableName, $stateValue, 'User')
        Write-LogMessage "[$($instanceName)] Saved state: Creation time: $($currentFileCreationTime), Next line: $($nextStartLine) (no matching blocks, last block ended at line $($lastBlockEndLine))" -Level INFO
    }
    else {
        # No blocks found at all - save current position
        $nextStartLine = $lastProcessedLine + 1
        $stateValue = "$($currentFileCreationTime);$($nextStartLine)"
        [Environment]::SetEnvironmentVariable($stateVariableName, $stateValue, 'User')
        Write-LogMessage "[$($instanceName)] Saved state: Creation time: $($currentFileCreationTime), Next line: $($nextStartLine) (no blocks found)" -Level INFO
    }
    
    # Log the environment variable content for verification
    $savedEnvValue = [Environment]::GetEnvironmentVariable($stateVariableName, 'User')
    Write-LogMessage "[$($instanceName)] ✅ Environment variable '$($stateVariableName)' = '$($savedEnvValue)'" -Level INFO
    

    # Add result for this instance
    # Calculate next start line based on what was processed (always calculate, regardless of MaxExports)
    $calculatedNextStartLine = if ($null -ne $lastExportedBlock) {
        $lastExportedBlock.EndLineNumber + 1
    }
    elseif ($lastBlockEndLine -gt 0) {
        $lastBlockEndLine + 1
    }
    else {
        $lastProcessedLine + 1
    }
    
    $allResults += [PSCustomObject]@{
        InstanceName         = $instanceName
        SourceFile           = $diagFile.FullName
        SnapshotFile         = $tempFilePath
        FileCreationTime     = $currentFileCreationTime
        TotalLinesRead       = $totalLines
        StartLine            = $startLine
        LastProcessedLine    = $lastProcessedLine
        LastBlockEndLine     = if ($lastBlockEndLine -gt 0) { $lastBlockEndLine } else { $null }
        LastExportedEndLine  = if ($null -ne $lastExportedBlock) { $lastExportedBlock.EndLineNumber } else { $null }
        MatchingBlocksParsed = $blocksProcessed
        ExportedCount        = $exportCount
        ApiAlertsSent        = $apiAlertCount
        OutputFolder         = $exportSubfolder
        ContinuousMode       = $isContinuousMode
        NextStartLine        = $calculatedNextStartLine
    }

    }
    catch {
        Write-LogMessage "[$($instanceName)] Fatal error processing instance: $($_.Exception.Message)" -Level ERROR -Exception $_
        Write-LogMessage "[$($instanceName)] Stack trace: $($_.ScriptStackTrace)" -Level ERROR
        continue
    }
}  # End of foreach ($diagFile in $diagFilesFound)

# Complete overall progress bar
Write-Progress -Id 0 -Activity "Processing DB2 Instances" -Completed

# Common Export File
if ($ExportCommonFile -and $commonExportEntries.Count -gt 0) {
    # Generate common filename with timestamp to avoid overwriting
    $commonFileName = "db2diag_$(Get-Date -Format 'yyyy-MM-dd_HHmmss').json"
    $commonOutputPath = Join-Path $OutputFolder $commonFileName
    
    # Create common export object with metadata
    $commonExport = [PSCustomObject]@{
        ExportDate      = (Get-Date -Format 'yyyy-MM-dd HH:mm:ss')
        TotalEntries    = $commonExportEntries.Count
        Instances       = @($allResults | Select-Object -ExpandProperty InstanceName -Unique)
        MinimumSeverity = if ($null -ne $minimumPriority) { $minimumPriority } else { "None" }
        Entries         = @($commonExportEntries)
    }
    
    # Export to JSON
    $commonExport | ConvertTo-Json -Depth 10 | Out-File -FilePath $commonOutputPath -Encoding UTF8
    Write-LogMessage "Exported common file: $($commonOutputPath) with $($commonExportEntries.Count) entries" -Level INFO
}


# Log summary of environment variables updated
Write-LogMessage "═══════════════════════════════════════════════════════════" -Level INFO
Write-LogMessage "  Processing Complete - Environment Variables Updated" -Level INFO
Write-LogMessage "═══════════════════════════════════════════════════════════" -Level INFO

foreach ($result in $allResults) {
    $envVarName = "$($StateVariablePrefix)$($result.InstanceName)"
    $envVarValue = [Environment]::GetEnvironmentVariable($envVarName, 'User')
    if ($null -ne $envVarValue) {
        Write-LogMessage "  $($envVarName) = '$($envVarValue)'" -Level INFO
    }
    else {
        Write-LogMessage "  $($envVarName) = (not set)" -Level WARN
    }
}

Write-LogMessage "═══════════════════════════════════════════════════════════" -Level INFO
Write-LogMessage "Processing complete. Processed $($allResults.Count) DB2 instance(s)." -Level INFO

# Return summary of all instances
#$allResults
