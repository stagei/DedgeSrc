# Author: Geir Helge Starholm, www.dEdge.no
#
# Scheduled Task Event Monitor
# Monitors Windows Event Log for scheduled task events and logs them using Write-LogMessage

param(
    [Parameter(Mandatory = $false)]
    [switch]$MonitorCurrentUser,

    [Parameter(Mandatory = $false)]
    [string[]]$TaskNames = @(),

    [Parameter(Mandatory = $false)]
    [int]$PollingIntervalSeconds = 30,

    [Parameter(Mandatory = $false)]
    [switch]$RunOnce,

    [Parameter(Mandatory = $false)]
    [int]$MaxEvents = 100,

    [Parameter(Mandatory = $false)]
    [switch]$ShowHelp
)

Import-Module GlobalFunctions -Force

if ($ShowHelp) {
    Write-Host @"
SCHEDULED TASK EVENT MONITOR
Author: Geir Helge Starholm, www.dEdge.no

DESCRIPTION:
    Monitors Windows Event Log for scheduled task events (start, completion, failure)
    and logs them using the existing Write-LogMessage infrastructure.

PARAMETERS:
    -MonitorCurrentUser     Only monitor tasks running as current user
    -TaskNames             Array of task names to monitor (supports wildcards)
    -PollingIntervalSeconds Seconds between event checks (default: 30)
    -RunOnce               Check events once and exit (don't loop)
    -MaxEvents             Maximum events to process per check (default: 100)
    -ShowHelp              Show this help message

EXAMPLES:
    # Monitor all tasks for current user
    .\Start-ScheduledTaskEventMonitor.ps1 -MonitorCurrentUser

    # Monitor specific tasks
    .\Start-ScheduledTaskEventMonitor.ps1 -TaskNames @("DataBackup", "LogCleanup")

    # Run once to check recent events
    .\Start-ScheduledTaskEventMonitor.ps1 -RunOnce

    # Monitor with custom polling interval
    .\Start-ScheduledTaskEventMonitor.ps1 -PollingIntervalSeconds 60

EVENT TYPES MONITORED:
    - Task Started (Event ID 100)
    - Task Triggered (Event ID 110)
    - Action Started (Event ID 200)
    - Task Completed Successfully (Event ID 101)
    - Action Completed (Event ID 201)
    - Task Completed with Errors (Event ID 102)
    - Task Failed to Start (Event ID 103)

LOG LEVELS USED:
    - JOB_STARTED: When task starts
    - JOB_COMPLETED: When task completes successfully
    - JOB_FAILED: When task fails or completes with errors
    - INFO: For other events like triggers and actions
"@
    exit 0
}

function Start-ScheduledTaskEventMonitor {
    param(
        [Parameter(Mandatory = $false)]
        [switch]$MonitorCurrentUser,

        [Parameter(Mandatory = $false)]
        [string[]]$TaskNames = @(),

        [Parameter(Mandatory = $false)]
        [int]$PollingIntervalSeconds = 30,

        [Parameter(Mandatory = $false)]
        [switch]$RunOnce,

        [Parameter(Mandatory = $false)]
        [int]$MaxEvents = 100
    )

    $currentUser = "$env:USERDOMAIN\$env:USERNAME"
    Write-LogMessage "Starting scheduled task event monitor for user: $currentUser" -Level INFO

    if ($MonitorCurrentUser) {
        Write-LogMessage "Monitoring tasks for current user only: $currentUser" -Level INFO
    }

    if ($TaskNames.Count -gt 0) {
        Write-LogMessage "Monitoring specific tasks: $($TaskNames -join ', ')" -Level INFO
    } else {
        Write-LogMessage "Monitoring all scheduled tasks" -Level INFO
    }

    # Task Scheduler Event IDs:
    # 100 - Task started
    # 101 - Task completed successfully
    # 102 - Task completed with errors
    # 103 - Task failed to start
    # 110 - Task triggered
    # 200 - Action started
    # 201 - Action completed

    $eventIds = @(100, 101, 102, 103, 110, 200, 201)

    # Get last check time (start from 5 minutes ago to catch recent events)
    $lastCheckTime = (Get-Date).AddMinutes(-5)

    if (-not $RunOnce) {
        Write-LogMessage "Monitoring task scheduler events. Press Ctrl+C to stop." -Level INFO
        Write-LogMessage "Polling interval: $PollingIntervalSeconds seconds" -Level INFO
    }

    $eventCount = 0

    try {
        do {
            try {
                # Get recent task scheduler events
                $events = Get-WinEvent -FilterHashtable @{
                    LogName = 'Microsoft-Windows-ScheduledTask/Operational'
                    ID = $eventIds
                    StartTime = $lastCheckTime
                } -MaxEvents $MaxEvents -ErrorAction SilentlyContinue

                if ($events) {
                    Write-LogMessage "Processing $($events.Count) task scheduler events" -Level DEBUG

                    foreach ($taskEvent in ($events | Sort-Object TimeCreated)) {
                        $taskName = ""
                        $taskPath = ""
                        $resultCode = ""

                        # Parse event message for task details
                        if ($taskEvent.Message -match 'Task "([^"]+)"') {
                            $taskPath = $matches[1]
                            $taskName = $taskPath.Split('\')[-1]
                        }

                        # Extract result code from message if available
                        if ($taskEvent.Message -match 'result code "([^"]+)"') {
                            $resultCode = $matches[1]
                        } elseif ($taskEvent.Message -match 'return code (\d+)') {
                            $resultCode = $matches[1]
                        }

                        # Check if this is for current user (if monitoring current user only)
                        $shouldLog = $true
                        if ($MonitorCurrentUser -and $taskName) {
                            try {
                                # Try to get task details to check user
                                $taskInfo = Get-ScheduledTask -TaskName $taskName -ErrorAction SilentlyContinue
                                if ($taskInfo) {
                                    $taskPrincipal = $taskInfo.Principal.UserId
                                    if ($taskPrincipal -and $taskPrincipal -ne $currentUser -and $taskPrincipal -ne "SYSTEM") {
                                        $shouldLog = $false
                                        Write-LogMessage "Skipping task $taskName (user: $taskPrincipal, monitoring: $currentUser)" -Level TRACE
                                    }
                                }
                            }
                            catch {
                                # If we can't get task info, log anyway but note the issue
                                Write-LogMessage "Could not verify task user for: $taskName" -Level DEBUG
                            }
                        }

                        # Filter by specific task names if provided
                        if ($TaskNames.Count -gt 0 -and $shouldLog) {
                            $shouldLog = $false
                            foreach ($filterName in $TaskNames) {
                                if ($taskName -like "*$filterName*" -or $taskPath -like "*$filterName*") {
                                    $shouldLog = $true
                                    break
                                }
                            }
                        }

                        if ($shouldLog) {
                            $logLevel = "INFO"
                            $eventType = ""

                            switch ($taskEvent.Id) {
                                100 {
                                    $eventType = "STARTED"
                                    $logLevel = "JOB_STARTED"
                                }
                                110 {
                                    $eventType = "TRIGGERED"
                                    $logLevel = "INFO"
                                }
                                200 {
                                    $eventType = "ACTION_STARTED"
                                    $logLevel = "INFO"
                                }
                                101 {
                                    $eventType = "COMPLETED_SUCCESS"
                                    $logLevel = "JOB_COMPLETED"
                                }
                                201 {
                                    $eventType = "ACTION_COMPLETED"
                                    $logLevel = "INFO"
                                }
                                102 {
                                    $eventType = "COMPLETED_WITH_ERRORS"
                                    $logLevel = "JOB_FAILED"
                                }
                                103 {
                                    $eventType = "FAILED_TO_START"
                                    $logLevel = "JOB_FAILED"
                                }
                                default {
                                    $eventType = "OTHER"
                                    $logLevel = "INFO"
                                }
                            }

                            # Build comprehensive log message
                            $message = "TASK_EVENT: $eventType"
                            if ($taskName) {
                                $message += " - Task: $taskName"
                            }
                            if ($taskPath -and $taskPath -ne $taskName) {
                                $message += " - Path: $taskPath"
                            }
                            if ($resultCode) {
                                $message += " - Result: $resultCode"
                            }
                            $message += " - Time: $($taskEvent.TimeCreated.ToString('yyyy-MM-dd HH:mm:ss'))"

                            Write-LogMessage $message -Level $logLevel
                            $eventCount++
                        }
                    }
                } else {
                    Write-LogMessage "No new task scheduler events found" -Level TRACE
                }

                $lastCheckTime = Get-Date

                if (-not $RunOnce) {
                    Start-Sleep -Seconds $PollingIntervalSeconds
                }
            }
            catch {
                Write-LogMessage "Error monitoring scheduled tasks" -Level ERROR -Exception $_
                if (-not $RunOnce) {
                    Start-Sleep -Seconds $PollingIntervalSeconds
                }
            }
        } while (-not $RunOnce)
    }
    finally {
        Write-LogMessage "Scheduled task monitoring stopped. Processed $eventCount events total." -Level INFO
    }
}

# Call the main function with passed parameters
Start-ScheduledTaskEventMonitor -MonitorCurrentUser:$MonitorCurrentUser -TaskNames $TaskNames -PollingIntervalSeconds $PollingIntervalSeconds -RunOnce:$RunOnce -MaxEvents $MaxEvents

