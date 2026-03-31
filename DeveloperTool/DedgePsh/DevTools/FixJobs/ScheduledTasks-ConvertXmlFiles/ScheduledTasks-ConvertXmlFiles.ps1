# Script to convert server custom scheduled tasks from Windows Task Scheduler exports
# This script processes exported task XML files and prepares them for conversion
Import-Module GlobalFunctions -Force
function Convert-ScheduledTaskCommand {
    param (
        [Parameter(Mandatory = $true)]
        [PSCustomObject]$fileObject,
        [Parameter(Mandatory = $true)]
        [string]$content
    )
    # Extract  all info from <Triggers>
    $fileObject.Triggers = @()
    $regex = "<Triggers>(.*?)</Triggers>"
    $match = [regex]::Match($content, $regex, [System.Text.RegularExpressions.RegexOptions]::Singleline)
    if ($match.Success) {
        $triggersContent = $match.Groups[1].Value

        # Create trigger object with all possible properties
        $triggerObject = [PSCustomObject]@{
            StartBoundary             = $null
            EndBoundary               = $null
            Enabled                   = $null
            ExecutionTimeLimit        = $null
            Id                        = $null

            # Calendar Trigger properties
            ScheduleByDay             = $null
            DaysInterval              = $null

            # Weekly Schedule properties
            ScheduleByWeek            = $null
            DaysOfWeek                = $null
            WeeksInterval             = $null

            # Monthly Schedule properties
            ScheduleByMonth           = $null
            MonthsOfYear              = $null
            DaysOfMonth               = $null

            # Monthly Day of Week Schedule properties
            ScheduleByMonthDayOfWeek  = $null
            Months                    = $null
            DaysOfWeek_Monthly        = $null
            WeeksOfMonth              = $null

            # Time Trigger properties
            TimeTrigger               = $null

            # Boot Trigger properties
            BootTrigger               = $null
            Delay                     = $null

            # Logon Trigger properties
            LogonTrigger              = $null
            UserId                    = $null

            # Idle Trigger properties
            IdleTrigger               = $null

            # Registration Trigger properties
            RegistrationTrigger       = $null

            # Session State Change Trigger properties
            SessionStateChangeTrigger = $null
            StateChange               = $null

            # Event Trigger properties
            EventTrigger              = $null
            Subscription              = $null

            # Repetition properties
            Interval                  = $null
            Duration                  = $null
            StopAtDurationEnd         = $null
        }

        # Extract all trigger properties
        $regex = "<StartBoundary>(.*?)</StartBoundary>"
        $match = [regex]::Match($triggersContent, $regex)
        if ($match.Success) {
            $triggerObject.StartBoundary = $match.Groups[1].Value
        }

        $regex = "<EndBoundary>(.*?)</EndBoundary>"
        $match = [regex]::Match($triggersContent, $regex)
        if ($match.Success) {
            $triggerObject.EndBoundary = $match.Groups[1].Value
        }

        $regex = "<Enabled>(.*?)</Enabled>"
        $match = [regex]::Match($triggersContent, $regex)
        if ($match.Success) {
            $triggerObject.Enabled = $match.Groups[1].Value
        }

        $regex = "<ExecutionTimeLimit>(.*?)</ExecutionTimeLimit>"
        $match = [regex]::Match($triggersContent, $regex)
        if ($match.Success) {
            $triggerObject.ExecutionTimeLimit = $match.Groups[1].Value
        }

        $regex = "<Id>(.*?)</Id>"
        $match = [regex]::Match($triggersContent, $regex)
        if ($match.Success) {
            $triggerObject.Id = $match.Groups[1].Value
        }

        # Calendar Trigger properties
        $regex = "<ScheduleByDay>(.*?)</ScheduleByDay>"
        $match = [regex]::Match($triggersContent, $regex)
        if ($match.Success) {
            $triggerObject.ScheduleByDay = $match.Groups[1].Value
        }

        $regex = "<DaysInterval>(.*?)</DaysInterval>"
        $match = [regex]::Match($triggersContent, $regex)
        if ($match.Success) {
            $triggerObject.DaysInterval = $match.Groups[1].Value
        }

        # Weekly Schedule properties
        $regex = "<ScheduleByWeek>(.*?)</ScheduleByWeek>"
        $match = [regex]::Match($triggersContent, $regex)
        if ($match.Success) {
            $triggerObject.ScheduleByWeek = $match.Groups[1].Value
        }

        $regex = "<DaysOfWeek>(.*?)</DaysOfWeek>"
        $match = [regex]::Match($triggersContent, $regex)
        if ($match.Success) {
            $triggerObject.DaysOfWeek = $match.Groups[1].Value
        }

        $regex = "<WeeksInterval>(.*?)</WeeksInterval>"
        $match = [regex]::Match($triggersContent, $regex)
        if ($match.Success) {
            $triggerObject.WeeksInterval = $match.Groups[1].Value
        }

        # Monthly Schedule properties
        $regex = "<ScheduleByMonth>(.*?)</ScheduleByMonth>"
        $match = [regex]::Match($triggersContent, $regex)
        if ($match.Success) {
            $triggerObject.ScheduleByMonth = $match.Groups[1].Value
        }

        $regex = "<MonthsOfYear>(.*?)</MonthsOfYear>"
        $match = [regex]::Match($triggersContent, $regex)
        if ($match.Success) {
            $triggerObject.MonthsOfYear = $match.Groups[1].Value
        }

        $regex = "<DaysOfMonth>(.*?)</DaysOfMonth>"
        $match = [regex]::Match($triggersContent, $regex)
        if ($match.Success) {
            $triggerObject.DaysOfMonth = $match.Groups[1].Value
        }

        # Monthly Day of Week Schedule properties
        $regex = "<ScheduleByMonthDayOfWeek>(.*?)</ScheduleByMonthDayOfWeek>"
        $match = [regex]::Match($triggersContent, $regex)
        if ($match.Success) {
            $triggerObject.ScheduleByMonthDayOfWeek = $match.Groups[1].Value
        }

        $regex = "<Months>(.*?)</Months>"
        $match = [regex]::Match($triggersContent, $regex)
        if ($match.Success) {
            $triggerObject.Months = $match.Groups[1].Value
        }

        $regex = "<WeeksOfMonth>(.*?)</WeeksOfMonth>"
        $match = [regex]::Match($triggersContent, $regex)
        if ($match.Success) {
            $triggerObject.WeeksOfMonth = $match.Groups[1].Value
        }

        # Time Trigger properties
        $regex = "<TimeTrigger>(.*?)</TimeTrigger>"
        $match = [regex]::Match($triggersContent, $regex)
        if ($match.Success) {
            $triggerObject.TimeTrigger = $match.Groups[1].Value
        }

        # Boot Trigger properties
        $regex = "<BootTrigger>(.*?)</BootTrigger>"
        $match = [regex]::Match($triggersContent, $regex)
        if ($match.Success) {
            $triggerObject.BootTrigger = $match.Groups[1].Value
        }

        $regex = "<Delay>(.*?)</Delay>"
        $match = [regex]::Match($triggersContent, $regex)
        if ($match.Success) {
            $triggerObject.Delay = $match.Groups[1].Value
        }

        # Logon Trigger properties
        $regex = "<LogonTrigger>(.*?)</LogonTrigger>"
        $match = [regex]::Match($triggersContent, $regex)
        if ($match.Success) {
            $triggerObject.LogonTrigger = $match.Groups[1].Value
        }

        $regex = "<UserId>(.*?)</UserId>"
        $match = [regex]::Match($triggersContent, $regex)
        if ($match.Success) {
            $triggerObject.UserId = $match.Groups[1].Value
        }

        # Idle Trigger properties
        $regex = "<IdleTrigger>(.*?)</IdleTrigger>"
        $match = [regex]::Match($triggersContent, $regex)
        if ($match.Success) {
            $triggerObject.IdleTrigger = $match.Groups[1].Value
        }

        # Registration Trigger properties
        $regex = "<RegistrationTrigger>(.*?)</RegistrationTrigger>"
        $match = [regex]::Match($triggersContent, $regex)
        if ($match.Success) {
            $triggerObject.RegistrationTrigger = $match.Groups[1].Value
        }

        # Session State Change Trigger properties
        $regex = "<SessionStateChangeTrigger>(.*?)</SessionStateChangeTrigger>"
        $match = [regex]::Match($triggersContent, $regex)
        if ($match.Success) {
            $triggerObject.SessionStateChangeTrigger = $match.Groups[1].Value
        }

        $regex = "<StateChange>(.*?)</StateChange>"
        $match = [regex]::Match($triggersContent, $regex)
        if ($match.Success) {
            $triggerObject.StateChange = $match.Groups[1].Value
        }

        # Event Trigger properties
        $regex = "<EventTrigger>(.*?)</EventTrigger>"
        $match = [regex]::Match($triggersContent, $regex)
        if ($match.Success) {
            $triggerObject.EventTrigger = $match.Groups[1].Value
        }

        $regex = "<Subscription>(.*?)</Subscription>"
        $match = [regex]::Match($triggersContent, $regex)
        if ($match.Success) {
            $triggerObject.Subscription = $match.Groups[1].Value
        }

        # Repetition properties
        $regex = "<Interval>(.*?)</Interval>"
        $match = [regex]::Match($triggersContent, $regex)
        if ($match.Success) {
            $triggerObject.Interval = $match.Groups[1].Value
        }

        $regex = "<Duration>(.*?)</Duration>"
        $match = [regex]::Match($triggersContent, $regex)
        if ($match.Success) {
            $triggerObject.Duration = $match.Groups[1].Value
        }

        $regex = "<StopAtDurationEnd>(.*?)</StopAtDurationEnd>"
        $match = [regex]::Match($triggersContent, $regex)
        if ($match.Success) {
            $triggerObject.StopAtDurationEnd = $match.Groups[1].Value
        }

        $fileObject.Triggers = $triggerObject

        # Extract Command, WorkingDirectory, and Arguments using regex
        $regex = "<Command>(.*?)</Command>"
        $match = [regex]::Match($xmlContent, $regex)
        $command = if ($match.Success) { $match.Groups[1].Value } else { "" }

        $regex = "<WorkingDirectory>(.*?)</WorkingDirectory>"
        $match = [regex]::Match($xmlContent, $regex)
        $workingDirectory = if ($match.Success) { $match.Groups[1].Value } else { "" }

        $regex = "<Arguments>(.*?)</Arguments>"
        $match = [regex]::Match($xmlContent, $regex)
        $arguments = if ($match.Success) { $match.Groups[1].Value } else { "" }

        # Create schtasks.exe command based on XML content
        $scriptLines = @()
        $scriptLines += "@echo off"
        $scriptLines += "REM Scheduled task creation script converted from XML"
        $scriptLines += "REM Original file: $($fileObject.OriginalFilename)"
        $scriptLines += "REM Converted on: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')"
        $scriptLines += ""

        # Build schtasks.exe command
        $taskName = [System.IO.Path]::GetFileNameWithoutExtension($fileObject.OriginalFilename)
        $schtaskExePath = Get-CommandPathWithFallback -Name "schtasks"
        $schtasksCmd = "$schtaskExePath /create /tn `"$taskName`""

        # Add command and arguments
        if ($command) {
            $schtasksCmd += " /tr `"$command"
            if ($arguments) {
                $schtasksCmd += " $arguments"
            }
            $schtasksCmd += "`""
        }

        # Add working directory if specified
        if ($workingDirectory) {
            $schtasksCmd += " /s localhost"  # Required for /it parameter
        }

        # Add user context
        if ($fileObject.UserId) {
            $schtasksCmd += " /ru `"$($fileObject.UserId)`""
        }

        # Add schedule based on trigger type
        if ($triggerObject.StartBoundary) {
            $startTime = $triggerObject.StartBoundary
            # Parse time from ISO format if needed
            if ($startTime -match "T(\d{2}:\d{2}:\d{2})") {
                $timeOnly = $matches[1]
                $schtasksCmd += " /st $timeOnly"
            }
        }

        # Determine schedule type and frequency
        if ($triggerObject.Interval) {
            $schtasksCmd += " /sc minute /mo $($triggerObject.Interval -replace 'PT(\d+)M', '$1')"
        }
        elseif ($triggerObject.DaysOfWeek) {
            $schtasksCmd += " /sc weekly /d $($triggerObject.DaysOfWeek)"
        }
        elseif ($triggerObject.DaysOfMonth) {
            $schtasksCmd += " /sc monthly /d $($triggerObject.DaysOfMonth)"
        }
        else {
            $schtasksCmd += " /sc once"
        }

        # Add enabled/disabled state
        if ($triggerObject.Enabled -eq "false") {
            $schtasksCmd += " /disable"
        }

        # Force creation (overwrite if exists)
        $schtasksCmd += " /f"

        $scriptLines += "REM Create scheduled task using schtasks.exe"
        $scriptLines += $schtasksCmd
        $scriptLines += ""
        $scriptLines += "if %errorlevel% equ 0 ("
        $scriptLines += "    echo Task '$taskName' created successfully"
        $scriptLines += ") else ("
        $scriptLines += "    echo Failed to create task '$taskName' - Error: %errorlevel%"
        $scriptLines += ")"

        $fileObject.ShedTaskExeScript = $scriptLines -join "`r`n"

        # Export the script to a .bat file
        $batFileName = $destinationPath.Replace("\XML\", "\BAT\").Replace(".xml", ".bat")
        $parentPath = Split-Path $batFileName -Parent
        if (-not (Test-Path $parentPath -PathType Container)) {
            New-Item -Path $parentPath -ItemType Directory | Out-Null
        }
        #Set-Content -Path $batFileName -Value $($fileObject.ShedTaskExeScript) -Encoding ASCII
        $fileObject.ShedTaskExeScriptFileName = $batFileName
    }
}
# Define the path to the custom tasks folder relative to the script location
$customTasksPath = Join-Path $PsScriptRoot "customtasks"

# Verify that the custom tasks directory exists
if (-not (Test-Path $customTasksPath -PathType Container)) {
    Write-LogMessage "Custom tasks path not found: $customTasksPath" -Level ERROR
    exit 1
}
$enablePerNewMachineComputerList = @()
$disablePerOldMachineComputerList = @()
$errorList = @()
$warningList = @()
$convertedList = @()
$commandArgumentsList = @()
$azurePrdDate = Get-Date -Year 2025 -Month 6 -Day 9 -Hour 9 -Minute 0 -Second 0 -Millisecond 0 | Get-Date -Format "yyyy-MM-ddTHH:mm:ss.ffffff"
# Get all first-level directories (server folders) in the custom tasks path
$computerInfoList = Get-ComputerInfoJson
$computerInfoList = $computerInfoList | Where-Object { $_.Type.ToLower().Contains("server") -and -not $_.Name.ToLower().Contains("fkx") }

$removeFilesPath = "$env:OptPath\src\DedgePsh\DevTools\AdminTools\ScheduledTasks-AddServerTasks\customtasks"

# Remove the ConvertedFiles directory if it exists
if (Test-Path $removeFilesPath -PathType Container) {
    Remove-Item -Path $removeFilesPath -Recurse -Force
}

# Process each server folder
try {
    $firstLevelFolders = Get-ChildItem -Path $customTasksPath -Directory
    foreach ($oldMachine in $firstLevelFolders) {
        try {

            $oldMachineName = $oldMachine.Name

            $oldMachineCompInfo = $computerInfoList | Where-Object { $_.Name -eq $oldMachineName }
            if ([string]::IsNullOrEmpty($oldMachineCompInfo.Name)) {
                Write-LogMessage "Computer info not found for $oldMachineName" -Level ERROR
                continue
            }
            $secondLevelCustomTasksPath = $customTasksPath + "\" + $oldMachineName
            $secondLevelFolders = Get-ChildItem -Path $secondLevelCustomTasksPath -Directory
            foreach ($newMachine in $secondLevelFolders) {

                $newMachineName = $newMachine.Name
                $newMachineCompInfo = $computerInfoList | Where-Object { $_.Name -eq $newMachineName }
                if ([string]::IsNullOrEmpty($newMachineCompInfo.Name)) {
                    Write-LogMessage "Computer info not found for $newMachineName" -Level ERROR
                    continue
                }
                $serviceUsername = ""
                if ($newMachineName.ToLower().StartsWith("p-no1")) {
                    $serviceUsername = "p1_srv_"
                }
                elseif ($newMachineName.ToLower().StartsWith("t-no1")) {
                    $serviceUsername = "t1_srv_"
                }

                #p1_srv_fkmprd_app

                $temp = $newMachineName.Replace("p-no1", "").Replace("t-no1", "")
                $serviceUsername += $temp.Replace("-", "_")
                $serviceUsername = $env:USERDOMAIN + "\" + $serviceUsername

                # Define the path to the Windows Direct Export folder for this server
                $distributionPath = "$env:OptPath\src\DedgePsh\DevTools\AdminTools\ScheduledTasks-AddServerTasks\customtasks\$newMachineName\"
                $distributionPathXml = "$distributionPath\XML"

                # Remove the ConvertedFiles directory if it exists
                if (-not (Test-Path $distributionPath -PathType Container)) {
                    New-Item -Path $distributionPath -ItemType Directory | Out-Null
                }
                if (-not (Test-Path $distributionPathXml -PathType Container)) {
                    New-Item -Path $distributionPathXml -ItemType Directory | Out-Null
                }

                # Get all exported task files from the Windows Direct Export folder
                $exportFiles = Get-ChildItem -Path $newMachine.ResolvedTarget -File -Recurse

                # Copy each exported file to ConvertedFiles with .xml extension
                foreach ($file in $exportFiles) {

                    $originalPath = $file.FullName
                    $splitPath = $originalPath.Split("\WindowsDirectExport")[1]
                    $destinationPath = Join-Path $distributionPathXml $splitPath
                    $destinationPath = $destinationPath

                    $destinationPath = $destinationPath -replace "KAT", "SIT"
                    $destinationPath = $destinationPath -replace "FAT", "MIG"

                    if (-not $destinationPath.EndsWith(".xml")) {
                        $destinationPath += ".xml"
                    }
                    # Create the destination folder if it doesn't exist
                    $destinationFolderPath = Split-Path $destinationPath -Parent
                    if (-not (Test-Path $destinationFolderPath -PathType Container)) {
                        New-Item -Path $destinationFolderPath -ItemType Directory | Out-Null
                    }
                    # Copy the file to the ConvertedFiles directory
                    try {
                        Copy-Item -Path $file.FullName -Destination $destinationPath -Force
                    }
                    catch {
                        Write-Host "Error: $($_.Exception.Message)" -ForegroundColor Red
                        $fileObject.Severity = "ERROR"
                        $fileObject.SeverityMessage = "Error: $($_.Exception.Message)"
                    }

                    $content = Get-Content $originalPath
                    $fileObject = [PSCustomObject]@{
                        Severity                  = "INFO"
                        SeverityMessage           = ""
                        Server                    = $newMachineName
                        OldServer                 = $oldMachineName
                        Date                      = ""
                        Author                    = ""
                        StartBoundary             = ""
                        Enabled                   = ""
                        UserId                    = ""
                        Command                   = ""
                        WorkingDirectory          = ""
                        Arguments                 = ""
                        OriginalFilename          = $originalPath
                        OriginalContent           = @($content.Split("`n"))
                        ConvertedFilename         = $destinationPath
                        ConvertedContent          = @()
                        Triggers                  = @()
                        ShedTaskExeScript         = @()
                        ShedTaskExeScriptFileName = ""
                        OriginalCommand           = ""
                        OriginalArguments         = ""
                    }

                    try {
                        $originalContent = $content
                        # DENNE FUNKER IKKE ENDA
                        # $content = $content.Replace("$env:OptPath\DedgePshApps\DedgePsh", "$env:OptPath\DedgePshApps")
                        # $content = $content.Replace("<Command>$env:OptPath\apps", "<Command>$env:OptPath\DedgeWinApps")
                        # $content = $content.Replace("c:\sched", "$env:OptPath\DedgePshApps\Start-BsbaorScripts")
                        # $content = $content.Replace("C:\sched", "$env:OptPath\DedgePshApps\Start-BsbaorScripts")
                        # $content = $content.Replace("$env:OptPath\run_gxbfloi.bat", "$env:OptPath\DedgePshApps\Run-Gxbfloi\Run-Gxbfloi.ps1")
                        # $content = $content.Replace("f:\batch", "$env:OptPath\DedgePshApps\Ehandel-Test")
                        # $content = $content.Replace("F:\batch", "$env:OptPath\DedgePshApps\Ehandel-Test")
                        # $content = $content.Replace("F:\COBVFT\cdsimport\start_cdsimport.bat", "E:\COBVFT\cdsimport\start_cdsimport.bat")
                        # $content = $content.Replace("<Command>STARTCOBDOK.BAT</Command>", "<Command>K:\COBDOK\STARTCOBDOK.BAT</Command>")

                        # $content = $content.Replace("c:\APPS\", "$env:OptPath\DedgeWinApps\")
                        # $content = $content.Replace("C:\apps\", "$env:OptPath\DedgeWinApps\")
                        # $content = $content.Replace("c:\apps\", "$env:OptPath\DedgeWinApps\")
                        # $content = $content.Replace("C:\APPS\", "$env:OptPath\DedgeWinApps\")

                        # $content = $content.Replace("f:\opt", "$env:OptPath")
                        # $content = $content.Replace("$env:OptPath", "$env:OptPath")
                        # $content = $content.Replace("d:\opt", "$env:OptPath")
                        # $content = $content.Replace("f:\psh", "$env:OptPath\DedgePshApps")
                        # $content = $content.Replace("e:\psh", "$env:OptPath\DedgePshApps")
                        # $content = $content.Replace("d:\psh", "$env:OptPath\DedgePshApps")
                        # $content = $content.Replace("f:\psh", "$env:OptPath\DedgePshApps")
                        # $content = $content.Replace("e:\psh", "$env:OptPath\DedgePshApps")
                        # $content = $content.Replace("d:\psh", "$env:OptPath\DedgePshApps")

                        # $content = $content.Replace("F:\opt", "$env:OptPath")
                        # $content = $content.Replace("$env:OptPath", "$env:OptPath")
                        # $content = $content.Replace("D:\opt", "$env:OptPath")
                        # $content = $content.Replace("F:\psh", "$env:OptPath\DedgePshApps")
                        # $content = $content.Replace("E:\psh", "$env:OptPath\DedgePshApps")
                        # $content = $content.Replace("D:\psh", "$env:OptPath\DedgePshApps")
                        # $content = $content.Replace("F:\psh", "$env:OptPath\DedgePshApps")
                        # $content = $content.Replace("E:\psh", "$env:OptPath\DedgePshApps")
                        # $content = $content.Replace("D:\psh", "$env:OptPath\DedgePshApps")

                        # $content = $content.Replace("F:\OPT", "$env:OptPath")
                        # $content = $content.Replace("$env:OptPath", "$env:OptPath")
                        # $content = $content.Replace("D:\OPT", "$env:OptPath")
                        # $content = $content.Replace("F:\PSH", "$env:OptPath\DedgePshApps")
                        # $content = $content.Replace("E:\PSH", "$env:OptPath\DedgePshApps")
                        # $content = $content.Replace("D:\PSH", "$env:OptPath\DedgePshApps")
                        # $content = $content.Replace("F:\PSH", "$env:OptPath\DedgePshApps")
                        # $content = $content.Replace("E:\PSH", "$env:OptPath\DedgePshApps")
                        # $content = $content.Replace("D:\PSH", "$env:OptPath\DedgePshApps")

                    }
                    catch {
                        Write-Host "Error: $($_.Exception.Message)" -ForegroundColor Red
                        $fileObject.Severity = "ERROR"
                        $fileObject.SeverityMessage = "Error: $($_.Exception.Message)"
                    }
                    Write-Host "Filename: $destinationPath"

                    foreach ($line in $content) {
                        $originalLine = $line
                        if ($line.ToUpper() -notmatch "SIT|MIG" -and $line.ToUpper() -match "KAT|FAT") {
                            $line = $line -replace "KAT", "SIT"
                            $line = $line -replace "FAT", "MIG"
                        }
                        if ($line.ToLower() -match "c:\\opt\\psh\DedgePshApps") {
                            $line = $line -ireplace "c:\\opt\\psh", "$env:OptPath\DedgePshApps"
                        }
                        if ($line.ToLower() -match "c:\\opt\\psh") {
                            $line = $line -ireplace "c:\\opt\\psh", "$env:OptPath\DedgePshApps"
                        }
                        if ($line.ToLower() -match "c:\\opt\\DedgePshApps\\DedgePsh") {
                            $line = $line -ireplace ".*c:\\opt\\DedgePshApps\\DedgePsh.*", "$env:OptPath\DedgePshApps"
                        }
                        if ($line.ToLower() -match "c:\\opt\\apps") {
                            $line = $line -ireplace "<Command>c:\\opt\\apps", "<Command>$env:OptPath\DedgeWinApps"
                        }
                        if ($line.ToLower() -match "c:\\sched") {
                            $line = $line -ireplace "c:\\sched", "$env:OptPath\DedgePshApps\Start-BsbaorScripts"
                        }
                        if ($line.ToLower() -match "C:\\opt\\run_gxbfloi\.bat") {
                            $line = $line -ireplace "C:\\opt\\run_gxbfloi\.bat", "$env:OptPath\DedgePshApps\Run-Gxbfloi\Run-Gxbfloi.ps1"
                        }
                        if ($line.ToLower() -match "f:\\batch") {
                            $line = $line -ireplace "f:\\batch", "$env:OptPath\DedgePshApps\Ehandel-Test"
                        }
                        if ($line.ToLower() -match "F:\\COBVFT\\cdsimport\\start_cdsimport\.bat") {
                            $line = $line -ireplace "F:\\COBVFT\\cdsimport\\start_cdsimport\.bat", "E:\COBVFT\cdsimport\start_cdsimport.bat"
                        }
                        if ($line.ToLower() -match "<command>STARTCOBDOK\.BAT</command>") {
                            $line = $line -ireplace "<Command>STARTCOBDOK\.BAT</Command>", "<Command>K:\COBDOK\STARTCOBDOK.BAT</Command>"
                        }

                        if ($line.ToLower() -match "c:\\apps\\") {
                            $line = $line -ireplace "c:\\apps\\", "$env:OptPath\DedgeWinApps\"
                        }

                        if ($line.ToLower() -match "[def]:\\opt") {
                            $line = $line -ireplace "[def]:\\opt", "$env:OptPath"
                        }
                        if ($line.ToLower() -match "[def]:\\psh") {
                            $line = $line -ireplace "[def]:\\psh", "$env:OptPath\DedgePshApps"
                        }
                        if ($line.ToLower() -match "[def]:\\opt\\psh") {
                            $line = $line -ireplace "[def]:\\opt\\psh", "$env:OptPath\DedgePshApps"
                        }

                        if ($line.ToLower() -match "E:\\opt\\apps") {
                            $line = $line -ireplace "E:\\opt\\apps", "$env:OptPath\DedgeWinApps"
                        }

                        if ($line -match "<Command>") {
                            Write-Host "Command: $line" -ForegroundColor Yellow
                            $x = 1
                        }

                        if ($line -imatch "DM010Runner") {
                            $x = 1
                        }

                        if ($line.ToLower().Contains("$env:OptPath\DedgePshApps\DedgePsh")) {
                            $line = $line -ireplace "$env:OptPath\DedgePshApps\DedgePsh", "$env:OptPath\DedgePshApps"
                            $pos = $line.ToLower().IndexOf("$env:OptPath\DedgePshApps\DedgePsh")

                        }

                        #Write-Host "Original: $originalLine"
                        if ($line.Trim().ToLower().StartsWith("<date>")) {
                            $regex = "<Date>(.*?)</Date>"
                            $newDate = Get-Date -Format "yyyy-MM-ddTHH:mm:ss.ffffff"
                            $match = [regex]::Match($line, $regex)
                            if ($match.Success) {
                                $line = $line.Replace($match.Groups[0].Value, "<Date>$newDate</Date>")
                            }
                            $fileObject.Date = $line
                        }
                        if ($line.Trim().ToLower().StartsWith("<author>")) {
                            $regex = "<Author>(.*?)</Author>"
                            $match = [regex]::Match($line, $regex)
                            if ($match.Success) {
                                $line = $line.Replace($match.Groups[0].Value, "<Author>$("$env:USERDOMAIN\" + $newMachineCompInfo.ServiceUserName)</Author>")
                            }
                            $fileObject.Author = $line
                        }
                        if ($line.Trim().ToLower().StartsWith("<startboundary>")) {
                            $regex = "<StartBoundary>(.*?)</StartBoundary>"
                            if ($newMachineCompInfo.Environments -contains "PRD") {
                                $newDate = $azurePrdDate
                            }
                            else {
                                $newDate = Get-Date -Format "yyyy-MM-ddTHH:mm:ss.ffffff"
                            }
                            $fileObject.StartBoundary = $newDate
                            $match = [regex]::Match($line, $regex)
                            if ($match.Success) {
                                $line = $line.Replace($match.Groups[0].Value, "<StartBoundary>$newDate</StartBoundary>")
                            }
                            $fileObject.StartBoundary = $line
                        }
                        if ($line.Trim().ToLower().StartsWith("<enabled>")) {
                            $regex = "<Enabled>(.*?)</Enabled>"
                            if ($newMachineCompInfo.Environments -contains "PRD") {
                                $enabled = "false"
                            }
                            else {
                                $enabled = "false"
                            }
                            $match = [regex]::Match($line, $regex)
                            if ($match.Success) {
                                $line = $line.Replace($match.Groups[0].Value, "<Enabled>$enabled</Enabled>")
                            }
                            $fileObject.Enabled = $line
                        }
                        if ($line.Trim().ToLower().StartsWith("<userid>")) {
                            $regex = "<UserId>(.*?)</UserId>"
                            $match = [regex]::Match($line, $regex)
                            if ($match.Success) {
                                $line = $line.Replace($match.Groups[0].Value, "<UserId>$("$env:USERDOMAIN\" + $newMachineCompInfo.ServiceUserName)</UserId>")
                            }
                            $fileObject.UserId = $line
                        }
                        if ($line.Trim().ToLower().StartsWith("<command>")) {
                            if ($originalPath.Contains("Start CDS-Import")) {
                                $x = 1
                            }
                            $regex = "<Command>(.*?)</Command>"
                            $match = [regex]::Match($line, $regex)
                            $currentContent = $null
                            if ($match.Success) {
                                $temp = $match.Groups[1].Value
                                if ($temp.ToLower().Contains("\psh\")) {
                                    if ($temp.ToLower().Contains("\opt\psh\")) {
                                        $temp = $temp.Replace("\opt\psh\", "\opt\DedgePshApps\")
                                        $line = "       <Command>" + $temp + "</Command>"
                                    }
                                    elseif ($temp.ToLower().Contains("\psh\")) {
                                        $temp = $temp.Replace("\psh\", "\opt\DedgePshApps\")
                                        $line = "       <Command>" + $temp + "</Command>"
                                    }
                                    else {
                                        # Debug here
                                        $x = 1
                                    }
                                }

                            }
                            elseif ($line -match "(?i)F:\\COBVFT") {
                                $line = $line -ireplace "F:\\COBVFT", "E:\COBVFT"
                            }
                            elseif ($line.Trim().ToLower().Contains("pwsh.exe")) {
                                # Do nothing
                            }
                            elseif ($line.Trim().ToLower().Contains("<command>$env:OptPath\apps")) {
                                $line = $line.Replace("$env:OptPath\apps", "$env:OptPath\DedgeWinApps")
                            }
                            elseif ($line.Trim().ToLower().Contains("<command>n:\cobnt\e03start.bat</command>") -and $newMachineCompInfo.Name.ToLower().Contains("tst")) {
                                $line = "       <Command>N:\COBTST\E03START.bat</Command>"
                            }
                            elseif ($line.Trim() -eq ("<Command>E:\COBVFT\cdsimport\start_cdsimport.bat</Command>")) {
                                # Do nothing
                                $x = 1
                            }
                            elseif ($line.Trim().ToLower().EndsWith("cmd.exe</command>")) {
                                # Do nothing
                                $x = 1
                            }
                            elseif ($line.Trim().ToLower().EndsWith("pwsh.exe</command>")) {
                                # Do nothing
                                $x = 1
                            }
                            elseif ($line.Trim().ToLower().EndsWith("powershell.exe</command>")) {
                                # Do nothing
                                $x = 1
                            }
                            elseif ($line.Trim().ToLower().EndsWith("cmd</command>")) {
                                # Do nothing
                                $x = 1
                            }
                            elseif ($line.Trim().ToLower().EndsWith("pwsh</command>")) {
                                # Do nothing
                                $x = 1
                            }
                            elseif ($line.Trim().ToLower().EndsWith("powershell</command>")) {
                                # Do nothing
                                $x = 1
                            }
                            elseif ($line.Trim().ToLower().Contains("$env:OptPath\DedgePshApps")) {
                                # Do nothing
                                $x = 1
                            }
                            elseif ($line.Trim().ToLower().Contains("$env:OptPath\DedgeWinApps")) {
                                # Do nothing
                                $x = 1
                            }
                            elseif ($line.Trim().ToLower().Contains("$env:OptPath\fkpythonapps")) {
                                # Do nothing
                                $x = 1
                            }
                            elseif ($line.Trim().ToLower().Contains("$env:OptPath\fknodejsapps")) {
                                # Do nothing
                                $x = 1
                            }
                            elseif ($line.Trim().ToLower().Contains("k:\cobdok") -and $newMachineCompInfo.Name.ToLower().Contains("tst")) {
                                # Do nothing
                            }
                            elseif ($line.Trim().ToLower().Contains("n:\cobtst") -and $newMachineCompInfo.Name.ToLower().Contains("tst")) {
                                # Do nothing
                            }
                            elseif ($line.Trim().ToLower().Contains("n:\cobnt") -and $newMachineCompInfo.Name.ToLower().Contains("prd")) {
                                # Do nothing
                                $x = 1
                            }
                            elseif ($line.Trim().ToLower().Contains("k:\") -and -not $newMachineCompInfo.Name.ToLower().Contains("prd")) {
                                $fileObject.Severity = "WARNING"
                                $fileObject.SeverityMessage = "Command path contains K:\. Verify manually. Environment is $($newMachineCompInfo.Environments -join ",")"
                            }
                            elseif ($line.Trim().ToLower().Contains("k:\") -and $newMachineCompInfo.Name.ToLower().Contains("prd")) {
                                $fileObject.Severity = "ERROR"
                                $fileObject.SeverityMessage = "Command path contains K:\. Verify manually. Environment is $($newMachineCompInfo.Environments -join ",")"
                            }
                            elseif ([string]::IsNullOrEmpty($currentContent)) {
                                # Do nothing
                                $x = 1
                            }
                            elseif ($line -match "(?i)rexx") {
                                # Do nothing
                                $x = 1
                            }
                            elseif ($line -match "(?i)db2cmd") {
                                # Do nothing
                                $x = 1
                            }
                            else {
                                # Debug here
                                Write-Host "Command: $line" -ForegroundColor Red
                                $fileObject.Severity = "ERROR"
                                $fileObject.SeverityMessage = "Command"
                            }
                            $line = $line.Replace("</Command></Command>", "</Command>")

                            $fileObject.Command = $line
                        }

                        if ($line.Trim().ToLower().StartsWith("<workingdirectory>")) {
                            if ($originalPath.Contains("D365 Integrasjoner\CDSMonitor")) {
                                $x = 1
                            }

                            $regex = "<WorkingDirectory>(.*?)</WorkingDirectory>"
                            $match = [regex]::Match($line, $regex)
                            $currentContent = $null
                            if ($match.Success) {
                                $temp = $match.Groups[1].Value
                                if ($temp.ToLower().Contains("\psh\")) {
                                    if ($temp.ToLower().Contains("\opt\psh\")) {
                                        $temp = $temp.Replace("\opt\psh\", "\opt\DedgePshApps\")
                                        $line = "       <WorkingDirectory>" + $temp + "</WorkingDirectory>"
                                    }
                                    elseif ($temp.ToLower().Contains("\psh\")) {
                                        $temp = $temp.Replace("\psh\", "\opt\DedgePshApps\")
                                        $line = "       <WorkingDirectory>" + $temp + "</WorkingDirectory>"
                                    }
                                    else {
                                        # Debug here
                                        $x = 1
                                    }
                                }
                            }
                            elseif ([string]::IsNullOrEmpty($newMachineCompInfo.Name)) {
                                # Do nothing
                                $x = 1
                            }
                            elseif ($line.Trim().Contains("$env:OptPath\apps")) {
                                $line = $line.Replace("$env:OptPath\apps", "$env:OptPath\DedgeWinApps")
                            }
                            elseif ($line.Trim() -eq "") {
                                $line = "       <WorkingDirectory></WorkingDirectory>"
                            }

                            elseif ($line.Trim().ToLower().Contains("<workingdirectory>n:\cobnt</workingdirectory>") -and $fileObject.Command.Contains("<Command>N:\COBNT\E03START.bat</Command>")) {
                                $line = "       <WorkingDirectory>N:\COBTST</WorkingDirectory>"
                            }

                            elseif ($line.Trim().ToLower().Contains("n:\cobnt")) {
                                # Do nothing
                                $x = 1
                            }
                            elseif ($line.Trim().ToLower().Contains("k:\cobdok") -and $newMachineCompInfo.Name.ToLower().Contains("tst")) {
                                # Do nothing
                                $x = 1
                            }
                            elseif ($line.Trim().ToLower().Contains("k:\cobdok")) {
                                # Do nothing
                                $x = 1
                            }
                            elseif ($line.Trim().ToLower().Contains("$env:OptPath\DedgePshApps")) {
                                # Do nothing
                                $x = 1
                            }
                            elseif ($line.Trim().ToLower().Contains("$env:OptPath\DedgeWinApps")) {
                                # Do nothing
                                $x = 1
                            }
                            elseif ($line.Trim().ToLower().Contains("$env:OptPath\fkpythonapps")) {
                                # Do nothing
                                $x = 1
                            }
                            elseif ($line.Trim().ToLower().Contains("$env:OptPath\fknodejsapps")) {
                                # Do nothing
                                $x = 1
                            }
                            elseif ($line.Trim().ToLower().Contains("n:\cobtst") -and $newMachineCompInfo.Name.ToLower().Contains("tst")) {
                                # Do nothing
                                $x = 1
                            }
                            elseif ($line.Trim().ToLower().Contains("n:\cobtst") -and $newMachineCompInfo.Name.ToLower().Contains("tst")) {
                                # Do nothing
                                $x = 1
                            }
                            elseif ($line.Trim().ToLower().Contains("n:\cobtst") -and $newMachineCompInfo.Name.ToLower().Contains("fsp")) {
                                # Do nothing
                                $x = 1
                            }
                            elseif ($line.Trim().ToLower().Contains("n:\cobnt") -and $newMachineCompInfo.Name.ToLower().Contains("prd")) {
                                # Do nothing
                                $x = 1
                            }
                            elseif ($line.Trim().ToLower().Contains("k:\fkavd") -and -not $newMachineCompInfo.Name.ToLower().Contains("prd")) {
                                # Do nothing
                                $x = 1
                            }
                            elseif ([string]::IsNullOrEmpty($currentContent)) {
                                # Do nothing
                                $x = 1
                            }
                            elseif ($line -match "(?i)\\\\[^\\]+\\") {
                                $fileObject.Severity = "WARNING"
                                $fileObject.SeverityMessage = "WorkingDirectory path contains UNC paths. Verify manually."
                            }
                            elseif ($line -match "(?i)[a-z]:\\") {
                                $fileObject.Severity = "WARNING"
                                $fileObject.SeverityMessage = "WorkingDirectory path contains other than handled drive paths. Verify manually."
                            }
                            elseif ($line -notmatch "(?i)[a-z]:\\" -and $line -notmatch "(?i)\\\\[^\\]+\\") {
                                # Do nothing
                                $x = 1
                            }
                            else {
                                # Debug here
                                Write-Host "WorkingDirectory: $line" -ForegroundColor Red
                                $fileObject.Severity = "ERROR"
                                $fileObject.SeverityMessage = "WorkingDirectory"
                            }
                            $fileObject.WorkingDirectory = $line
                        }

                        if ($line.Trim().ToLower().StartsWith("<arguments>")) {

                            $regex = "<Arguments>(.*?)</Arguments>"
                            $match = [regex]::Match($line, $regex)
                            $args = ""
                            if ($match.Success) {
                                $temp = $match.Groups[1].Value
                                if ($temp.ToLower().Contains("\psh\")) {
                                    if ($temp.ToLower().Contains("\opt\psh\")) {
                                        $temp = $temp.Replace("\opt\psh\", "\opt\DedgePshApps\")
                                        $line = "       <Arguments>" + $temp + "</Arguments>"
                                    }
                                    elseif ($temp.ToLower().Contains("\psh\")) {
                                        $temp = $temp.Replace("\psh\", "\opt\DedgePshApps\")
                                        $line = "       <Arguments>" + $temp + "</Arguments>"
                                    }
                                    else {
                                        # Debug here
                                        $x = 1
                                    }
                                }
                                elseif ($temp.ToLower().Contains("\apps\")) {
                                    if ($temp.ToLower().Contains("\opt\apps\")) {
                                        $temp = $temp.Replace("\opt\apps\", "\opt\DedgeWinApps\")
                                        $line = "       <Arguments>" + $temp + "</Arguments>"
                                    }
                                    elseif ($temp.ToLower().Contains("\apps\")) {
                                        $temp = $temp.Replace("\apps\", "\opt\DedgeWinApps\")
                                        $line = "       <Arguments>" + $temp + "</Arguments>"
                                    }
                                    else {
                                        # Debug here
                                        $x = 1
                                    }
                                }
                                elseif ($args.Trim().ToLower().Contains("n:\cobtst") -and $newMachineCompInfo.Name.ToLower().Contains("tst")) {
                                    # Do nothing
                                    $x = 1
                                }
                                elseif ($args.Trim().ToLower().Contains("n:\cobnt") -and $newMachineCompInfo.Name.ToLower().Contains("prd")) {
                                    # Do nothing
                                    $x = 1
                                }

                                elseif ($args.Trim().ToLower().Contains("$env:OptPath\DedgePshApps")) {
                                    # Do nothing
                                    $x = 1
                                }
                                elseif ($args.Trim().ToLower().Contains("$env:OptPath\DedgeWinApps")) {
                                    # Do nothing
                                    $x = 1
                                }
                                elseif ($args.Trim().ToLower().Contains("$env:OptPath\fkpythonapps")) {
                                    # Do nothing
                                    $x = 1
                                }
                                elseif ($args.Trim().ToLower().Contains("$env:OptPath\fknodejsapps")) {
                                    # Do nothing
                                    $x = 1
                                }
                                elseif ($args -notmatch "(?i)[a-z]:\\" -and $args -notmatch "(?i)\\\\[^\\]+\\") {
                                    # Do nothing
                                    $x = 1
                                }
                                else {
                                    # Debug here
                                    $fileObject.Severity = "ERROR"
                                    $fileObject.SeverityMessage = "Arguments"
                                }
                                $line = "       <Arguments>" + $args + "</Arguments>"
                            }

                            if ($line.Contains("</WorkingDirectory></WorkingDirectory>")) {
                                $line = $line.Replace("</WorkingDirectory></WorkingDirectory>", "</WorkingDirectory>")
                            }
                            $fileObject.Arguments = $line

                        }

                        if ($line -match "\\SIT\\MIG") {
                            $x = 1
                        }
                        $fileObject.ConvertedContent += $line

                    }

                    # Convert-ScheduledTaskCommand -fileObject $fileObject -content $fileObject.ConvertedContent

                    if ($newMachineName -eq "t-no1fkmfsp-app") {
                        if ($fileObject.Command -notmatch "C:\\opt\\DedgePshApps\\MIG" -and $fileObject.Command -notmatch "C:\\opt\\DedgePshApps\\VFK" -and $fileObject.Command -notmatch "C:\\opt\\DedgePshApps\\VFT") {
                            $fileObject.Command = $fileObject.Command.Replace("$env:OptPath\DedgePshApps\", "$env:OptPath\DedgePshApps\SIT\")
                        }
                    }

                    $fileObject.ConvertedFilename = $fileObject.ConvertedFilename.Replace("\\", "\")
                    Set-Content -Path $destinationPath -Value $fileObject.ConvertedContent
                    $convertedList += $fileObject
                    # Extract original command using regex
                    $commandRegex = "<Command>(.*?)</Command>"
                    $commandMatch = [regex]::Match($originalContent, $commandRegex, [System.Text.RegularExpressions.RegexOptions]::Singleline)
                    if ($commandMatch.Success) {
                        $fileObject.OriginalCommand = $commandMatch.Groups[1].Value.Trim()
                    }
                    else {
                        $fileObject.OriginalCommand = ""
                    }
                    # Extract original arguments using regex
                    $argumentsRegex = "<Arguments>(.*?)</Arguments>"
                    $argumentsMatch = [regex]::Match($originalContent, $argumentsRegex, [System.Text.RegularExpressions.RegexOptions]::Singleline)
                    if ($argumentsMatch.Success) {
                        $fileObject.OriginalArguments = $argumentsMatch.Groups[1].Value.Trim()
                    }
                    else {
                        $fileObject.OriginalArguments = ""
                    }
                    $commandArgumentsObject = [PSCustomObject]@{
                        TaskName      = $($($fileObject.ConvertedFilename.Split("\XML\")[-1]).Replace(".xml", "").ToString())
                        ToServer      = $($newMachineName)
                        ToCommand     = $($fileObject.Command.Replace("<Command>", "").Replace("</Command>", "").Trim())
                        ToArguments   = $($fileObject.Arguments.Replace("<Arguments>", "").Replace("</Arguments>", "").Trim())
                        FromServer    = $($oldMachineName)
                        FromCommand   = $($fileObject.OriginalCommand.Replace("<Command>", "").Replace("</Command>", "").Trim())
                        FromArguments = $($fileObject.OriginalArguments.Replace("<Arguments>", "").Replace("</Arguments>", "").Trim())
                    }
                    $commandArgumentsList += $commandArgumentsObject
                    if ($commandArgumentsObject.TaskName -eq "ERROR") {
                        Write-LogMessage "Error: TaskName is ERROR" -Level Error
                    }
                    if ($commandArgumentsObject.ToServer -eq "ERROR") {
                        Write-LogMessage "Error: ToServer is ERROR" -Level Error
                    }
                    if ($commandArgumentsObject.ToCommand -eq "ERROR") {
                        Write-LogMessage "Error: ToCommand is ERROR" -Level Error
                    }
                    if ($commandArgumentsObject.ToArguments -eq "ERROR") {
                        Write-LogMessage "Error: ToArguments is ERROR" -Level Error
                    }
                    if ($commandArgumentsObject.FromServer -eq "ERROR") {
                        Write-LogMessage "Error: FromServer is ERROR" -Level Error
                    }
                    if ($commandArgumentsObject.FromCommand -eq "ERROR") {
                        Write-LogMessage "Error: FromCommand is ERROR" -Level Error
                    }
                    if ($commandArgumentsObject.FromArguments -eq "ERROR") {
                        Write-LogMessage "Error: FromArguments is ERROR" -Level Error
                    }

                    if ($fileObject.Enabled.Contains("false")) {
                        $obj = [PSCustomObject]@{
                            Server      = $newMachineName
                            TaskName    = $($fileObject.ConvertedFilename.Split("\XML\")[-1]).Replace(".xml", "").ToString()
                            SchedScript = ""
                        }
                        $schtaskExePath = Get-CommandPathWithFallback -Name "schtasks"
                        $schedScript = "$schtaskExePath /Change /TN `"$($obj.TaskName)`" /ENABLE"
                        $obj.SchedScript = $schedScript
                        $enablePerNewMachineComputerList += $obj
                    }
                    $obj = [PSCustomObject]@{
                        Server      = $oldMachineName
                        TaskName    = $($fileObject.OriginalFilename.Split("\WindowsDirectExport\")[-1]).Replace(".xml", "")
                        SchedScript = ""
                    }
                    $schtaskExePath = Get-CommandPathWithFallback -Name "schtasks"
                    $schedScript = "$schtaskExePath /Change /TN `"$($obj.TaskName)`" /DISABLE"
                    $obj.SchedScript = $schedScript
                    $disablePerOldMachineComputerList += $obj

                }
            }
        }
        catch {
            Write-LogMessage "Error: $($_.Exception.Message)" -Level Error -Exception $_
        }
    }
}
catch {
    Write-LogMessage "Error: $($_.Exception.Message)" -Level Error -Exception $_
}

# if ($errorList.Count -gt 0) {
#     $errorList | ConvertTo-Json -Depth 10 | Out-File "$($PsScriptRoot)\errorlist.json"
#     $errorList | Format-Table -Property Severity , SeverityMessage, Server, Date, Author, StartBoundary, Enabled, UserId, Command, WorkingDirectory, Arguments, OriginalFilename, ConvertedFilename | Out-String | Write-Host -ForegroundColor Red
# }

if ($convertedList.Count -gt 0) {
    foreach ($item in $convertedList | Where-Object { $_.Severity -ne "INFO" }) {
        $color = switch ($item.Severity) {
            "ERROR" { "Red" }
            "WARNING" { "Yellow" }
            default { "White" }
        }
        $item | Format-List -Property Severity , SeverityMessage, Server, OldServer, Date, Author, StartBoundary, Enabled, UserId, Command, WorkingDirectory, Arguments, OriginalFilename, ConvertedFilename | Out-String | Write-Host -ForegroundColor $color
    }
    Write-Host "All OK: $(($convertedList | Where-Object { $_.Severity -eq "INFO" }).Count)" -ForegroundColor Green
    Write-Host "Warnings: $(($convertedList | Where-Object { $_.Severity -eq "WARNING" }).Count)" -ForegroundColor Yellow
    Write-Host "Errors: $(($convertedList | Where-Object { $_.Severity -eq "ERROR" }).Count)" -ForegroundColor Red
    Write-Host "Converted in total: $($convertedList.Count) files" -ForegroundColor Green
    $convertedList | ConvertTo-Json -Depth 10 | Out-File "$($PsScriptRoot)\AllScheduledTasksInfo.json"
    Write-Host "Converted list exported to $($PsScriptRoot)\AllScheduledTasksInfo.json" -ForegroundColor Green
}
else {
    Write-Host "No converted files" -ForegroundColor Green
    Remove-Item "$($PsScriptRoot)\convertedlist.json" -Force -ErrorAction SilentlyContinue
}

if (($convertedList | Where-Object { $_.Severity -eq "WARNING" }).Count -gt 0) {
    $warningList = $convertedList | Where-Object { $_.Severity -eq "WARNING" }
    $warningList | ConvertTo-Json -Depth 10 | Out-File "$($PsScriptRoot)\warninglist.json"
    Write-Host "Warnings exported to $($PsScriptRoot)\warninglist.json" -ForegroundColor Yellow
}
else {
    Remove-Item "$($PsScriptRoot)\warninglist.json" -Force -ErrorAction SilentlyContinue
    Write-Host "No warnings" -ForegroundColor Green
}

if (($convertedList | Where-Object { $_.Severity -eq "ERROR" }).Count -gt 0) {
    $errorList = $convertedList | Where-Object { $_.Severity -eq "ERROR" }
    $errorList | ConvertTo-Json -Depth 10 | Out-File "$($PsScriptRoot)\errorlist.json"
    Write-Host "Errors exported to $($PsScriptRoot)\errorlist.json" -ForegroundColor Red
}
else {
    Remove-Item "$($PsScriptRoot)\errorlist.json" -Force -ErrorAction SilentlyContinue
    Write-Host "No errors" -ForegroundColor Green
}

$commandArgumentsList | ConvertTo-Json -Depth 10 | Out-File "$($PsScriptRoot)\commandargumentslist.json"
$commandArgumentsList | ConvertTo-Csv -Delimiter "¤" -NoTypeInformation | Out-File "$($PsScriptRoot)\commandargumentslist.csv"

Write-Host "Command arguments list exported to $($PsScriptRoot)\commandargumentslist.json" -ForegroundColor Green

$newMachineComputerList = $enablePerNewMachineComputerList | Select-Object -Property Server | Sort-Object -Property Server -Unique

foreach ($item in $newMachineComputerList) {
    $outputFolder = "\\" + $item.Server.Trim() + "\Opt\Data\EnableScheduledTasks"
    Get-ChildItem -Path $outputFolder -Recurse | Remove-Item -Force -ErrorAction SilentlyContinue
    Write-Host "." -NoNewline
}

foreach ($item in $enablePerNewMachineComputerList) {
    $outputFolder = "\\" + $item.Server.Trim() + "\Opt\Data\EnableScheduledTasks"
    if (-not (Test-Path $outputFolder)) {
        New-Item -ItemType Directory -Path $outputFolder
    }
    $outputFile = $outputFolder + "\Enable_" + $item.TaskName.Replace("\", "_").Replace("/", "_") + ".bat"
    $item.SchedScript | Out-File $outputFile
    #Write-Host "Exported scheduled task $($item.TaskName) bat-script for $($item.Server) to $outputFile" -ForegroundColor Green
    Write-Host "." -NoNewline
}

$oldMachineComputerList = $disablePerOldMachineComputerList | Select-Object -Property Server | Sort-Object -Property Server -Unique

foreach ($item in $oldMachineComputerList) {
    $outputFolder = "\\" + $item.Server.Trim() + "\Opt\Data\DisableScheduledTasks"
    Get-ChildItem -Path $outputFolder -Recurse | Remove-Item -Force -ErrorAction SilentlyContinue
    Write-Host "." -NoNewline
}

foreach ($item in $disablePerOldMachineComputerList) {
    try {
        $outputFolder = "\\" + $item.Server.Trim() + "\Opt\Data\DisableScheduledTasks"
        if (-not (Test-Path $outputFolder)) {
            New-Item -ItemType Directory -Path $outputFolder
        }
        $outputFile = $outputFolder + "\Disable_" + $($item.TaskName.Replace("\", "_").Replace("/", "_")) + ".bat"
        $item.SchedScript | Out-File $outputFile
        # Write-Host "Exported scheduled task $($item.TaskName) bat-script for $($item.Server) to $outputFile" -ForegroundColor Green
        Write-Host "." -NoNewline
    }
    catch {
        Write-LogMessage "Error during export of file $outputFile" -Level Error -Exception $_
    }
}
Write-Host "`n"
Write-Host "All done" -ForegroundColor Green

