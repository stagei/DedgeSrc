<#
.SYNOPSIS
    Windows Event Log Analyzer and Exporter

.DESCRIPTION
    A comprehensive tool for analyzing Windows Event Logs with both custom search functionality
    and predefined patterns for common system issues including system reboots, DB2 server issues,
    and system crashes.

.EXAMPLE
    .\Get-EventLog.ps1
    # Displays the main menu with options for custom search or predefined patterns

.NOTES
    Author: Dedge PowerShell Environment
    Version: 2.0
    Dependencies: GlobalFunctions module
#>

Import-Module GlobalFunctions -Force

#region Helper Functions

function Show-MainMenu {
    <#
    .SYNOPSIS
        Displays the main menu for the Event Log Analyzer
    #>
    Clear-Host
    Write-LogMessage ""
    Write-LogMessage "═══════════════════════════════════════════════════════════════" -Level INFO
    Write-LogMessage "              Windows Event Log Analyzer v2.0" -Level INFO
    Write-LogMessage "═══════════════════════════════════════════════════════════════" -Level INFO
    Write-LogMessage ""
    Write-LogMessage "Please select an option:" -Level INFO
    Write-LogMessage ""
    Write-LogMessage "  [1] Custom Event Log Search (Original functionality)" -Level INFO
    Write-LogMessage "  [2] System Reboot Analysis" -Level INFO
    Write-LogMessage "  [3] DB2 Server Issues Analysis" -Level INFO
    Write-LogMessage "  [4] System Crash Analysis" -Level INFO
    Write-LogMessage "  [5] Exit" -Level INFO
    Write-LogMessage ""
    Write-LogMessage "─────────────────────────────────────────────────────────────────" -Level INFO
}

function Get-UserMenuChoice {
    <#
    .SYNOPSIS
        Gets and validates user menu choice
    #>
    do {
        Write-Host "Enter your choice (1-5)" -ForegroundColor Cyan -NoNewline
        $choice = Read-Host 
        if (-not [int]::TryParse($choice, [ref]$null)) {
            Write-LogMessage "Invalid choice. Please enter a number between 1 and 5." -Level WARN
            continue
        }
        else {
            return [int]$choice
        }
        if ($choice -match '^[1-5]$') {
            return [int]$choice
        }
        Write-LogMessage "Invalid choice. Please enter a number between 1 and 5." -Level WARN
    } while ($true)
}
function Get-TimestampsForToday {
    <#
    .SYNOPSIS
        Gets the timestamps for today
    #>
    while ($true) {
        Write-Host "Enter the time in HH:mm format (Default: 00:00)" -ForegroundColor Cyan -NoNewline
        $fromHhmm = Read-Host 
        if (-not $fromHhmm.Contains(":") -or $fromHhmm.Length -ne 5) {
            Write-LogMessage "Invalid input. Please enter the time in HH:mm format." -Level WARN
            continue
        }
        else {
            $fromHhmmSplit = $fromHhmm.Split(":")
            $hh = $fromHhmmSplit[0]
            $mm = $fromHhmmSplit[1]
            $fromTimestamp = [datetime](Get-Date -Hour $hh -Minute $mm -Second 0)
            break
        }
    }
    
    

    # Get until time
    while ($true) {
        Write-Host "Enter the time in HH:mm format (Default: 23:59)" -ForegroundColor Cyan -NoNewline
        $untilHhmm = Read-Host 
        if (-not $untilHhmm.Contains(":") -or $untilHhmm.Length -ne 5) {
            Write-LogMessage "Invalid input. Please enter the time in HH:mm format." -Level WARN
            continue
        }
        else {
            $untilHhmmSplit = $untilHhmm.Split(":")
            $untilHh = $untilHhmmSplit[0]
            $untilMm = $untilHhmmSplit[1]
            $untilTimestamp = [datetime](Get-Date -Hour $untilHh -Minute $untilMm -Second 0)
            if ($untilTimestamp -lt $fromTimestamp) {
                Write-LogMessage "Invalid input. Please enter a time that is after the start time." -Level WARN
                continue
            }
            else {
                break
            }
        }
    }
  

    $object = [PSCustomObject]@{
        FromTimestamp  = $fromTimestamp
        UntilTimestamp = $untilTimestamp
    }
    return $object
}
function Get-TimeSpanInput {
    <#
    .SYNOPSIS
        Gets time span input from user with validation
    #>
    param(
        [string]$PromptText,
        [int]$DefaultValue,
        [string]$Unit = "minutes"
    )

    Write-LogMessage "$PromptText (Default: $DefaultValue $Unit)" -Level INFO -NoNewline -ForegroundColor Cyan 
    $userInput = Read-Host

    if ([string]::IsNullOrWhiteSpace($userInput)) {
        Write-LogMessage "Using default of $DefaultValue $Unit." -Level INFO  
        return $DefaultValue
    }

    if (-not [int]::TryParse($userInput, [ref]$null)) {
        Write-LogMessage "Invalid input. Using default of $DefaultValue $Unit." -Level WARN 
        return $DefaultValue
    }

    return [int]$userInput
}

function Open-FileWithEditorSafe {
    <#
    .SYNOPSIS
        Safely opens a file with the best available editor with enhanced error handling
    #>
    param(
        [Parameter(Mandatory = $true)]
        [string]$FilePath
    )

    try {
        # Verify file exists first
        if (-not (Test-Path -Path $FilePath -PathType Leaf)) {
            Write-LogMessage "File not found: $FilePath" -Level ERROR
            return $false
        }

        # Check for available editors in order of preference
        $editors = @(
            @{ Name = "Cursor"; Command = "cursor" },
            @{ Name = "VS Code"; Command = "code" },
            @{ Name = "Notepad++"; Command = "notepad++" },
            @{ Name = "Notepad"; Command = "notepad" }
        )

        foreach ($editor in $editors) {
            try {
                # First check if the command is available using Get-Command
                $commandPath = Get-Command $editor.Command -ErrorAction SilentlyContinue
                if ($commandPath -and (Test-Path $commandPath.Source -PathType Leaf)) {
                    Write-LogMessage "Opening $FilePath with $($editor.Name)" -Level INFO
                    Start-Process -FilePath $commandPath.Source -ArgumentList "`"$FilePath`"" -ErrorAction Stop
                    return $true
                }
            }
            catch {
                Write-LogMessage "Failed to open with $($editor.Name): $($_.Exception.Message)" -Level DEBUG
                continue
            }
        }

        # If no specific editors found, try the GlobalFunctions approach as fallback
        try {
            Write-LogMessage "Trying GlobalFunctions Open-FileWithEditor as fallback" -Level DEBUG
            Open-FileWithEditor -FilePath $FilePath
            return $true
        }
        catch {
            Write-LogMessage "GlobalFunctions Open-FileWithEditor also failed: $($_.Exception.Message)" -Level DEBUG
        }

        # Final fallback: Use Windows default file association
        Write-LogMessage "Using Windows default application to open file" -Level INFO
        Start-Process -FilePath $FilePath -UseShellExecute -ErrorAction Stop
        return $true
    }
    catch {
        Write-LogMessage "All attempts to open file failed: $($_.Exception.Message)" -Level ERROR
        return $false
    }
}

#endregion

#region Menu Actions

function Invoke-CustomEventLogSearch {
    <#
    .SYNOPSIS
        Executes the original custom event log search functionality
    #>
    Write-LogMessage ""
    Write-LogMessage "═══ Custom Event Log Search ═══" -Level INFO
    Write-LogMessage ""


    # use previous time or minutes back from now
    #$fromMinutesBack = Read-Host "Do you want to use previous time or minutes back from now? (t/n) [Default: n]"
    $usePreviousTime = Get-UserConfirmationWithTimeout -PromptMessage "Do you want to use previous time or minutes back from now? (TimeRange/MinutesBack) [Default: MinutesBack]" -TimeoutSeconds 30 -AllowedResponses @("TimeRange", "MinutesBack") -ProgressMessage "Choose option" -DefaultResponse "MinutesBack" 

    if ($usePreviousTime -eq "TimeRange") {
        $timestamps = Get-TimestampsForToday
        $startTime = $timestamps.FromTimestamp
        $endTime = $timestamps.UntilTimestamp
    }
    else {
        # Get time span
        $fromMinutesBack = Get-TimeSpanInput -PromptText "Enter number of minutes to look back" -DefaultValue 5
        $forMinutesForward = Get-TimeSpanInput -PromptText "Enter number of minutes to look forward from start time" -DefaultValue 0

        # Log search parameters
        $startTime = (Get-Date).AddMinutes(-$fromMinutesBack)
        if ($forMinutesForward -gt 0) {
            $endTime = $startTime.AddMinutes($forMinutesForward)
        }
        else {
            $endTime = (Get-Date)
        }

    }

    # Get log names
    Write-LogMessage "Default is to search Application, System, Security logs." -Level INFO
    Write-LogMessage "Do you want to search all available logs? (y/n) [Default: n]" -Level INFO -NoNewline -ForegroundColor Cyan
    $allLogs = Read-Host

    $logNames = @()
    if ($allLogs.ToLower() -eq "y") {
        Write-LogMessage "Getting all available logs with events..." -Level INFO 
        $logNames = Get-WinEvent -ListLog * -ErrorAction SilentlyContinue |
        Where-Object { $_.RecordCount -gt 0 } |
        Select-Object -ExpandProperty LogName
    }
    else {
        $logNames = @("Application", "System", "Security")
    }

    # Get filter words
    Write-LogMessage "Enter filter words separated by spaces (leave empty for no filter)" -Level INFO -NoNewline
    $filterInput = Read-Host
    $filterWords = if ([string]::IsNullOrWhiteSpace($filterInput)) { @() } else { $filterInput -split '\s+' }

  
    # LevelDisplayName
    $levelDisplayNameArray = @(
        "Critical"
        "Error"
        "Warning"
        "Information"
        "Verbose"
    )
    $userChoice = Get-UserConfirmationWithTimeout -PromptMessage "Minimum level to include in the report:" -TimeoutSeconds 30 -AllowedResponses $levelDisplayNameArray -ProgressMessage "Choose level" -DefaultResponse "Information"

    $chosenLevelsArray = @()
    if ($userChoice -eq "Critical") {
        $chosenLevelsArray += 1
    }
    elseif ($userChoice -eq "Error") {
        $chosenLevelsArray += 1
        $chosenLevelsArray += 2
    }
    elseif ($userChoice -eq "Warning") {
        $chosenLevelsArray += 1
        $chosenLevelsArray += 2
        $chosenLevelsArray += 3
    }
    elseif ($userChoice -eq "Information") {
        $chosenLevelsArray += 1
        $chosenLevelsArray += 2
        $chosenLevelsArray += 3
        $chosenLevelsArray += 4
    }
    elseif ($userChoice -eq "Verbose") {
        $chosenLevelsArray += 1
        $chosenLevelsArray += 2
        $chosenLevelsArray += 3
        $chosenLevelsArray += 4
        $chosenLevelsArray += 5
    }


    $logMessage = @"
Search Parameters:
  - Time Range: $startTime to $endTime
  - Log Names: $($logNames -join ', ')
  - Filter Words: $(if ($filterWords.Count -gt 0) { $filterWords -join ', ' } else { 'None' })
"@
    Write-LogMessage $logMessage -Level INFO

    # Get events
    $events = Get-EventLogData -LogNames $logNames -StartTime $startTime -EndTime $endTime -FilterWords $filterWords -Levels $chosenLevelsArray -LimitProperties $false

    # Export results
    $timeSpanDesc = "From $($startTime.ToString("yyyy-MM-dd HH-mm-ss")) to $($endTime.ToString("yyyy-MM-dd HH-mm-ss"))"
    Export-EventLogResults -Events $events -ReportType "CustomEventLogSearch" -TimeSpanDescription $timeSpanDesc -LimitProperties $false
}

function Invoke-SystemRebootAnalysis {
    <#
    .SYNOPSIS
        Analyzes system reboot events and related issues
    #>
    Write-LogMessage ""
    Write-LogMessage "═══ System Reboot Analysis ═══" -Level INFO
    Write-LogMessage ""

    $hours = Get-TimeSpanInput -PromptText "Enter number of hours to look back" -DefaultValue 12 -Unit "hours"
    $startTime = (Get-Date).AddHours(-$hours)

    Write-LogMessage "Searching for system reboot events and related issues..." -Level INFO

    # System reboot related event IDs
    $rebootEventIds = @(
        1074,  # System shutdown/restart initiated
        1076,  # System shutdown reason
        6005,  # Event log service started (system boot)
        6006,  # Event log service stopped (system shutdown)
        6008,  # Unexpected shutdown
        6009,  # System boot
        12,    # Kernel boot
        13,    # Kernel shutdown
        41,    # System rebooted without cleanly shutting down
        1001,  # Bugcheck (BSOD)
        1002   # Bugcheck recovery
    )

    $logNames = @("System", "Application")

    # Get reboot-related events
    $events = Get-EventLogData -LogNames $logNames -StartTime $startTime -EventIds $rebootEventIds -ExcludeInformational

    # Also search for critical and error events around reboot times
    $criticalEvents = Get-EventLogData -LogNames $logNames -StartTime $startTime -Levels @(1, 2) # Critical and Error

    # Combine and sort all events
    $allEvents = @($events) + @($criticalEvents) | Sort-Object TimeCreated -Descending | Get-Unique -AsString

    $timeSpanDesc = "Last$($hours)Hours"
    Export-EventLogResults -Events $allEvents -ReportType "SystemRebootAnalysis" -TimeSpanDescription $timeSpanDesc -LimitProperties $false
}

function Invoke-Db2ServerAnalysis {
    <#
    .SYNOPSIS
        Analyzes DB2 server related serious events
    #>
    Write-LogMessage ""
    Write-LogMessage "═══ DB2 Server Issues Analysis ═══" -Level INFO
    Write-LogMessage ""

    # Check if this is a DB2 server
    $serverName = $env:COMPUTERNAME
    if ($serverName -notlike "*-db") {
        Write-LogMessage "Warning: This server name ($serverName) does not end with '-db'." -Level WARN
        Write-LogMessage "Do you want to continue with DB2 analysis anyway? (y/n) [Default: y]" -Level INFO -NoNewline -ForegroundColor Cyan
        $continue = Read-Host
        if ($continue.ToLower() -eq "n") {
            Write-LogMessage "DB2 analysis cancelled." -Level INFO
            return
        }
    }

    $hours = Get-TimeSpanInput -PromptText "Enter number of hours to look back" -DefaultValue 12 -Unit "hours"
    $startTime = (Get-Date).AddHours(-$hours)

    Write-LogMessage "Searching for DB2 server related serious events..." -Level INFO

    # DB2 related keywords and providers
    $db2Keywords = @(
        "DB2",
        "database",
        "SQL",
        "deadlock",
        "connection",
        "timeout",
        "crash",
        "corrupted",
        "rollback",
        "recovery",
        "tablespace",
        "backup",
        "restore"
    )

    $logNames = @("Application", "System")

    # Get serious events (Critical, Error, Warning)
    $events = Get-EventLogData -LogNames $logNames -StartTime $startTime -Levels @(1, 2, 3) -FilterWords $db2Keywords

    $timeSpanDesc = "Last$($hours)Hours"
    Export-EventLogResults -Events $events -ReportType "DB2ServerAnalysis" -TimeSpanDescription $timeSpanDesc -LimitProperties $false
}

function Invoke-SystemCrashAnalysis {
    <#
    .SYNOPSIS
        Analyzes events that indicate system crashes or serious issues
    #>
    Write-LogMessage ""
    Write-LogMessage "═══ System Crash Analysis ═══" -Level INFO
    Write-LogMessage ""

    $hours = Get-TimeSpanInput -PromptText "Enter number of hours to look back" -DefaultValue 12 -Unit "hours"
    $startTime = (Get-Date).AddHours(-$hours)

    Write-LogMessage "Searching for system crash and serious error events..." -Level INFO

    # System crash related event IDs
    $crashEventIds = @(
        41,    # Kernel-Power - System rebooted without cleanly shutting down
        1001,  # BugCheck
        1002,  # BugCheck recovery
        6008,  # Unexpected shutdown
        7034,  # Service crashed
        7031,  # Service terminated
        7032,  # Service control manager
        4625,  # Logon failure (security)
        1000,  # Application Error
        1002   # Application Hang
    )

    # Keywords indicating serious system issues
    $crashKeywords = @(
        "crash",
        "hang",
        "stop error",
        "blue screen",
        "BSOD",
        "bugcheck",
        "fatal",
        "corrupted",
        "memory",
        "access violation",
        "stack overflow",
        "heap corruption"
    )

    $logNames = @("System", "Application", "Security")

    # Get crash-related events by ID
    $eventsByIds = Get-EventLogData -LogNames $logNames -StartTime $startTime -EventIds $crashEventIds

    # Get critical and error events
    $criticalEvents = Get-EventLogData -LogNames $logNames -StartTime $startTime -Levels @(1, 2)

    # Get events with crash-related keywords
    $keywordEvents = Get-EventLogData -LogNames $logNames -StartTime $startTime -FilterWords $crashKeywords -ExcludeInformational

    # Combine all events and remove duplicates
    $allEvents = @($eventsByIds) + @($criticalEvents) + @($keywordEvents) |
    Sort-Object TimeCreated -Descending |
    Get-Unique -AsString

    $timeSpanDesc = "Last$($hours)Hours"
    Export-EventLogResults -Events $allEvents -ReportType "SystemCrashAnalysis" -TimeSpanDescription $timeSpanDesc -LimitProperties $false
}

#endregion

#region Main Program

try {
    Write-LogMessage "Windows Event Log Analyzer started" -Level INFO 

    do {
        Show-MainMenu
        $choice = Get-UserMenuChoice

        switch ($choice) {
            1 { Invoke-CustomEventLogSearch }
            2 { Invoke-SystemRebootAnalysis }
            3 { Invoke-Db2ServerAnalysis }
            4 { Invoke-SystemCrashAnalysis }
            5 {
                Write-LogMessage ""
                Write-LogMessage "Thank you for using Windows Event Log Analyzer!" -Level INFO
                Write-LogMessage "Exiting..." -Level INFO
                break
            }
        }

        if ($choice -ne 5) {
            Write-LogMessage ""
            Write-LogMessage "Press any key to return to the main menu..." -Level INFO
            $null = $Host.UI.RawUI.ReadKey("NoEcho,IncludeKeyDown")
        }

    } while ($choice -ne 5)
}
catch {
    try {
        Write-LogMessage "An unexpected error occurred: $($_.Exception.Message)" -Level ERROR -Exception $_
    }
    catch {
        # Fallback if Write-LogMessage itself fails
        Write-Host "CRITICAL ERROR: $($_.Exception.Message)" -ForegroundColor Red
        Write-Host "Additional error in logging system" -ForegroundColor Yellow
    }
    Write-Host "Press any key to exit..." -ForegroundColor Red
    try {
        $null = $Host.UI.RawUI.ReadKey("NoEcho,IncludeKeyDown")
    }
    catch {
        # If even ReadKey fails, just wait a moment
        Start-Sleep -Seconds 3
    }
}
finally {
    try {
        Write-LogMessage "Windows Event Log Analyzer session completed" -Level INFO 
    }
    catch {
        # Fallback if Write-LogMessage fails in finally block
        Write-Host "Session completed" -ForegroundColor Green
    }
}

#endregion

