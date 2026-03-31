# Author: Geir Helge Starholm, www.dEdge.no
#
# Task Wrapper Script for Enhanced Logging
# Wraps scheduled task execution with comprehensive logging

param(
    [Parameter(Mandatory = $true)]
    [string]$TaskName,

    [Parameter(Mandatory = $false)]
    [string]$ScriptPath,

    [Parameter(Mandatory = $false)]
    [scriptblock]$ScriptBlock,

    [Parameter(Mandatory = $false)]
    [hashtable]$Parameters = @{},

    [Parameter(Mandatory = $false)]
    [string]$WorkingDirectory,

    [Parameter(Mandatory = $false)]
    [switch]$ShowHelp,

    [Parameter(Mandatory = $false)]
    [switch]$PassThru
)

Import-Module GlobalFunctions -Force

if ($ShowHelp) {
    Write-Host @"
INVOKE-TASK WITH LOGGING
Author: Geir Helge Starholm, www.dEdge.no

DESCRIPTION:
    Wrapper function to add comprehensive logging to scheduled task execution.
    Logs task start, completion, failure, and execution time using Write-LogMessage.

PARAMETERS:
    -TaskName           Name of the task for logging purposes (required)
    -ScriptPath         Path to script file to execute
    -ScriptBlock        Script block to execute directly
    -Parameters         Hashtable of parameters to pass to script/scriptblock
    -WorkingDirectory   Working directory for script execution
    -PassThru           Return result from executed script/scriptblock
    -ShowHelp           Show this help message

EXAMPLES:
    # Execute a script file with logging
    .\Invoke-TaskWithLogging.ps1 -TaskName "DataBackup" -ScriptPath "C:\Scripts\Backup.ps1"

    # Execute with parameters
    .\Invoke-TaskWithLogging.ps1 -TaskName "DataBackup" -ScriptPath "C:\Scripts\Backup.ps1" -Parameters @{Database="MyDB"; Path="C:\Backups"}

    # Execute a script block
    .\Invoke-TaskWithLogging.ps1 -TaskName "SystemCheck" -ScriptBlock { Get-Process | Where-Object CPU -gt 100 }

    # Use in a scheduled task (example scheduled task content):
    # powershell.exe -File "C:\Path\To\Invoke-TaskWithLogging.ps1" -TaskName "MyTask" -ScriptPath "C:\Scripts\MyScript.ps1"

LOG LEVELS USED:
    - JOB_STARTED: When task begins execution
    - JOB_COMPLETED: When task completes successfully
    - JOB_FAILED: When task fails with error
    - INFO: For general status information
    - WARN: For warnings during execution
"@
    exit 0
}

function Invoke-TaskWithLogging {
    param(
        [Parameter(Mandatory = $true)]
        [string]$TaskName,

        [Parameter(Mandatory = $false)]
        [string]$ScriptPath,

        [Parameter(Mandatory = $false)]
        [scriptblock]$ScriptBlock,

        [Parameter(Mandatory = $false)]
        [hashtable]$Parameters = @{},

        [Parameter(Mandatory = $false)]
        [string]$WorkingDirectory,

        [Parameter(Mandatory = $false)]
        [switch]$PassThru
    )

    # Validate input parameters
    if (-not $ScriptPath -and -not $ScriptBlock) {
        Write-LogMessage "ERROR: Either ScriptPath or ScriptBlock must be provided" -Level ERROR
        throw "Either ScriptPath or ScriptBlock must be provided"
    }

    if ($ScriptPath -and $ScriptBlock) {
        Write-LogMessage "WARNING: Both ScriptPath and ScriptBlock provided. ScriptPath will be used." -Level WARN
    }

    $startTime = Get-Date
    $originalLocation = Get-Location
    $result = $null

    try {
        # Log task start
        Write-LogMessage "TASK_STARTED: $TaskName" -Level JOB_STARTED

        # Change working directory if specified
        if ($WorkingDirectory) {
            if (Test-Path $WorkingDirectory) {
                Set-Location $WorkingDirectory
                Write-LogMessage "Changed working directory to: $WorkingDirectory" -Level INFO
            } else {
                Write-LogMessage "Warning: Working directory does not exist: $WorkingDirectory" -Level WARN
            }
        }

        # Execute the task
        if ($ScriptPath) {
            # Validate script file exists
            if (-not (Test-Path $ScriptPath)) {
                throw "Script file not found: $ScriptPath"
            }

            Write-LogMessage "Executing script: $ScriptPath" -Level INFO

            if ($Parameters.Count -gt 0) {
                Write-LogMessage "Script parameters: $($Parameters.Keys -join ', ')" -Level INFO
                $result = & $ScriptPath @Parameters
            } else {
                $result = & $ScriptPath
            }
        } else {
            # Execute script block
            Write-LogMessage "Executing script block for task: $TaskName" -Level INFO

            if ($Parameters.Count -gt 0) {
                Write-LogMessage "Script block parameters: $($Parameters.Keys -join ', ')" -Level INFO
                $result = & $ScriptBlock @Parameters
            } else {
                $result = & $ScriptBlock
            }
        }

        # Calculate execution time
        $endTime = Get-Date
        $duration = $endTime - $startTime

        # Log successful completion
        $completionMessage = "TASK_COMPLETED: $TaskName - Duration: $($duration.TotalMinutes.ToString('F2')) minutes"
        if ($duration.TotalSeconds -lt 60) {
            $completionMessage = "TASK_COMPLETED: $TaskName - Duration: $($duration.TotalSeconds.ToString('F1')) seconds"
        }

        Write-LogMessage $completionMessage -Level JOB_COMPLETED

        # Return result if requested
        if ($PassThru) {
            return $result
        }
    }
    catch {
        # Calculate execution time for failed task
        $endTime = Get-Date
        $duration = $endTime - $startTime

        # Log task failure
        $failureMessage = "TASK_FAILED: $TaskName - Duration: $($duration.TotalMinutes.ToString('F2')) minutes"
        if ($duration.TotalSeconds -lt 60) {
            $failureMessage = "TASK_FAILED: $TaskName - Duration: $($duration.TotalSeconds.ToString('F1')) seconds"
        }

        Write-LogMessage $failureMessage -Level JOB_FAILED -Exception $_

        # Re-throw the exception to maintain error handling behavior
        throw
    }
    finally {
        # Restore original location
        Set-Location $originalLocation
    }
}

# Enhanced function for creating wrapper scheduled tasks
function New-ScheduledTaskWithLogging {
    param(
        [Parameter(Mandatory = $true)]
        [string]$TaskName,

        [Parameter(Mandatory = $true)]
        [string]$ScriptPath,

        [Parameter(Mandatory = $false)]
        [hashtable]$Parameters = @{},

        [Parameter(Mandatory = $false)]
        [string]$Description = "Scheduled task with enhanced logging",

        [Parameter(Mandatory = $false)]
        [string]$StartTime = "02:00",

        [Parameter(Mandatory = $false)]
        [string]$User = "$env:USERDOMAIN\$env:USERNAME",

        [Parameter(Mandatory = $false)]
        [switch]$Daily,

        [Parameter(Mandatory = $false)]
        [switch]$DryRun
    )

    $wrapperScript = $PSCommandPath
    $argumentList = "-File `"$wrapperScript`" -TaskName `"$TaskName`" -ScriptPath `"$ScriptPath`""

    if ($Parameters.Count -gt 0) {
        $paramString = ($Parameters.GetEnumerator() | ForEach-Object { "-$($_.Key) `"$($_.Value)`"" }) -join " "
        $argumentList += " -Parameters @{$paramString}"
    }

    Write-LogMessage "Creating scheduled task with logging wrapper" -Level INFO
    Write-LogMessage "Task Name: $TaskName" -Level INFO
    Write-LogMessage "Script Path: $ScriptPath" -Level INFO
    Write-LogMessage "Arguments: $argumentList" -Level INFO

    if ($DryRun) {
        Write-LogMessage "DRY RUN: Would create scheduled task with these settings" -Level INFO
        return
    }

    try {
        # Create the scheduled task action
        $action = New-ScheduledTaskAction -Execute "powershell.exe" -Argument $argumentList

        # Create the trigger
        if ($Daily) {
            $trigger = New-ScheduledTaskTrigger -Daily -At $StartTime
        } else {
            Write-LogMessage "No trigger specified - task will need to be triggered manually" -Level WARN
            $trigger = $null
        }

        # Create task principal
        $principal = New-ScheduledTaskPrincipal -UserId $User -LogonType Interactive

        # Create task settings
        $settings = New-ScheduledTaskSettingsSet -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries -StartWhenAvailable

        # Register the task
        if ($trigger) {
            Register-ScheduledTask -TaskName $TaskName -Action $action -Trigger $trigger -Principal $principal -Settings $settings -Description $Description
        } else {
            Register-ScheduledTask -TaskName $TaskName -Action $action -Principal $principal -Settings $settings -Description $Description
        }

        Write-LogMessage "Successfully created scheduled task: $TaskName" -Level INFO
    }
    catch {
        Write-LogMessage "Failed to create scheduled task: $TaskName" -Level ERROR -Exception $_
        throw
    }
}

# Call the main function if script is executed directly
if ($TaskName) {
    Invoke-TaskWithLogging -TaskName $TaskName -ScriptPath $ScriptPath -ScriptBlock $ScriptBlock -Parameters $Parameters -WorkingDirectory $WorkingDirectory -PassThru:$PassThru
}

