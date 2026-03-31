# Script to convert server custom scheduled tasks from Windows Task Scheduler exports
# This script processes exported task XML files and prepares them for conversion
Import-Module GlobalFunctions -Force
# Define the path to the custom tasks folder relative to the script location
function Convert-ScheduledTaskContent {
    param (
        [Parameter(Mandatory = $true)]
        [string]$content,
        [Parameter(Mandatory = $true)]
        [string]$RegexAllPaths
    )
    # Capture all the file and folder paths before the command, both standard, relative and UNC paths and add them to the fileAndFolderPathsCapturedBefore array
    $currentCaptureTemp = @()
    $matchTemp = @()
    $matchTemp = [regex]::Matches($content, $RegexAllPaths)
    $index = 0
    foreach ($item in $matchTemp) {
        $currentCaptureTemp += [PSCustomObject]@{
            Index      = $index
            BeforePath = $item.Value.Trim()
            AfterPath  = ""
        }
        $index++
    }

    if ($content.ToLower().Contains("c:\")) {
        $content = $content -ireplace "c:\\", "E:\"
    }
    if ($content.ToLower().Contains("d:\")) {
        $content = $content -ireplace "d:\\", "E:\"
    }
    if ($content.ToLower().Contains("f:\")) {
        $content = $content -ireplace "f:\\", "E:\"
    }

    if ($content.ToLower().Contains("e:\sched")) {
        $content = $content -ireplace "e:\\sched", "$env:OptPath\DedgePshApps\Sched"
    }
    if ($content.ToLower().Contains("e:\batch")) {
        $content = $content -ireplace "e:\\batch", "$env:OptPath\DedgePshApps\Batch"
    }
    if ($content.ToLower().Contains("e:\\cobvft\\cdsimport\\start_cdsimport\.bat")) {
        $content = $content -ireplace "e:\\cobvft\\cdsimport\\start_cdsimport\.bat", "$env:OptPath\DedgePshApps\COBVFT\cdsimport\start_cdsimport.bat"
    }
    if ($content.ToLower().Contains("<command>startcobdok.bat</command>")) {
        $content = $content -ireplace "startcobdok\.bat", "K:\COBDOK\STARTCOBDOK.BAT"
    }
    if ($content.ToLower().Contains("e:\psh")) {
        $content = $content -ireplace "e:\\psh", "$env:OptPath\DedgePshApps"
    }
    if ($content.ToLower().Contains("e:\apps")) {
        $content = $content -ireplace "e:\\apps", "$env:OptPath\DedgeWinApps"
    }
    if ($content.ToLower().Contains("$env:OptPath\psh")) {
        $content = $content -ireplace "e:\\opt\\psh", "$env:OptPath\DedgePshApps"
    }
    if ($content.ToLower().Contains("$env:OptPath\apps")) {
        $content = $content -ireplace "e:\\opt\\apps", "$env:OptPath\DedgeWinApps"
    }
    if ($content.ToLower().Contains("$env:OptPath\psh\DedgePshApps")) {
        $content = $content -ireplace "e:\\opt\\psh\\DedgePshApps", "$env:OptPath\DedgePshApps"
    }
    if ($content.ToLower().Contains("$env:OptPath\apps\DedgePshApps")) {
        $content = $content -ireplace "e:\\opt\\apps\\DedgePshApps", "$env:OptPath\DedgeWinApps"
    }
    if ($content.ToLower().Contains("$env:OptPath\DedgePshApps\DedgePsh")) {
        $content = $content -ireplace "e:\\opt\\DedgePshApps\\DedgePsh", "$env:OptPath\DedgePshApps"
    }

    # Capture all the file and folder paths before the command, both standard, relative and UNC paths and add them to the fileAndFolderPathsCapturedBefore array
    $matchTemp = @()
    $matchTemp = [regex]::Matches($content, $RegexAllPaths)
    $index = 0
    try {
        foreach ($item in $matchTemp) {
            if ($currentCaptureTemp[$index]) {
                $currentCaptureTemp[$index].AfterPath = $item.Value.Trim()
            }
            $index++
        }
    }
    catch {
    }
    $resultObject = [PSCustomObject]@{
        Content                           = $content.Trim()
        CurrentFileAndFolderPathsCaptured = $currentCaptureTemp
    }
    return $resultObject
}

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

$allFileAndFolderPathsCaptured = @()

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
                $distributionPath = "$env:OptPath\src\DedgePsh\DevTools\AdminTools\ScheduledTasks-AddServerTasks"

                # Remove the ConvertedFiles directory if it exists

                # Get all exported task files from the Windows Direct Export folder
                $exportFiles = Get-ChildItem -Path $newMachine.ResolvedTarget -File -Recurse

                # Copy each exported file to ConvertedFiles with .xml extension
                foreach ($file in $exportFiles) {

                    $originalPath = $file.FullName
                    $splitPath = $($originalPath.Split("\customtasks\")[1] ?? "Unknown").TrimEnd("\").TrimStart("\").Trim()
                    $taskName = $($splitPath.Split("\")[-1] ?? "Unknown").TrimEnd("\").TrimStart("\").Trim()
                    $destinationPath = Join-Path $distributionPath "\customtasks\" $splitPath
                    $destinationPath = $destinationPath.Replace("WindowsDirectExport\", "\") + ".xml"

                    if (-not (Test-Path $(Split-Path $destinationPath -Parent) -PathType Container)) {
                        New-Item -Path $(Split-Path $destinationPath -Parent) -ItemType Directory | Out-Null
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

                    }
                    catch {
                        Write-Host "Error: $($_.Exception.Message)" -ForegroundColor Red
                        $fileObject.Severity = "ERROR"
                        $fileObject.SeverityMessage = "Error: $($_.Exception.Message)"
                    }
                    Write-Host "Filename: $destinationPath"
                    $fileAndFolderPathsCapturedInCurrentFile = @()

                    foreach ($line in $content) {
                        $originalLine = $line

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

                        $RegexAllPaths = "(([a-zA-Z]:\\[^<]*)|(\\.\\[^<]*)|(//[^<]*))"

                        if ($line.Trim().ToLower().StartsWith("<command>") -or $line.Trim().ToLower().StartsWith("<arguments>") -or $line.Trim().ToLower().StartsWith("<workingdirectory>")) {
                            if ($line.Trim().ToLower().StartsWith("<command>")) {
                                $regex = "<Command>(.*?)</Command>"
                            }
                            elseif ($line.Trim().ToLower().StartsWith("<arguments>")) {
                                $regex = "<Arguments>(.*?)</Arguments>"
                            }
                            else {
                                $regex = "<WorkingDirectory>(.*?)</WorkingDirectory>"
                            }

                            $match = [regex]::Match($line, $regex)
                            $currentContent = $null
                            if ($match.Success) {
                                $currentContent = $match.Groups[1].Value.Trim()
                                $currentContentObjArray = Convert-ScheduledTaskContent $currentContent -RegexAllPaths $RegexAllPaths
                                $currentContent = $currentContentObjArray.Content
                                if ($line.Trim().ToLower().StartsWith("<command>")) {
                                    $line = $line.Replace($match.Groups[0].Value, "<Command>$currentContent</Command>")
                                }
                                elseif ($line.Trim().ToLower().StartsWith("<arguments>")) {
                                    $line = $line.Replace($match.Groups[0].Value, "<Arguments>$currentContent</Arguments>")
                                }
                                else {
                                    $line = $line.Replace($match.Groups[0].Value, "<WorkingDirectory>$currentContent</WorkingDirectory>")
                                }

                            }

                            foreach ($item in $currentContentObjArray) {
                                foreach ($item2 in $item.CurrentFileAndFolderPathsCaptured) {

                                    $beforeDirectoryPath = ""
                                    $afterDirectoryPath = ""
                                    $partFrom = ""
                                    if ($item2.BeforePath.ToLower().Trim().StartsWith("c:") -or $item2.BeforePath.ToLower().Trim().StartsWith("d:") -or $item2.BeforePath.ToLower().Trim().StartsWith("e:") -or $item2.BeforePath.ToLower().Trim().StartsWith("f:") ) {
                                        try {
                                            if ($item2.BeforePath.Split("\")[-1].Contains(".")) {
                                                $posLastSlash = $($item2.BeforePath.Trim().Substring(2).TrimStart(":").TrimStart("\").TrimEnd("\")).LastIndexOf("\")
                                                $partFrom = $($item2.BeforePath.Trim().Substring(2).TrimStart(":").TrimStart("\").TrimEnd("\")).Substring(0, $posLastSlash)
                                            }
                                            else {
                                                $partFrom = $item2.BeforePath.Trim().Substring(2).TrimStart(":").TrimStart("\").TrimEnd("\")
                                            }
                                        }
                                        catch {
                                            continue
                                        }
                                    }
                                    else {
                                        continue
                                    }

                                    $partTo = ""
                                    if ($item2.AfterPath.ToLower().Trim().StartsWith("c:") -or $item2.AfterPath.ToLower().Trim().StartsWith("d:") -or $item2.AfterPath.ToLower().Trim().StartsWith("e:") -or $item2.AfterPath.ToLower().Trim().StartsWith("f:") ) {
                                        try {
                                            $posLastSlash = $($item2.AfterPath.Trim().Substring(2).TrimStart(":").TrimStart("\").TrimEnd("\")).LastIndexOf("\")
                                            if ($item2.AfterPath.Split("\")[-1].Contains(".")) {
                                                $partTo = $($item2.AfterPath.Trim().Substring(2).TrimStart(":").TrimStart("\").TrimEnd("\")).Substring(0, $posLastSlash)
                                            }
                                            else {
                                                $partTo = $item2.AfterPath.Trim().Substring(2).TrimStart(":").TrimStart("\").TrimEnd("\")
                                            }
                                        }
                                        catch {
                                            continue
                                        }
                                    }
                                    else {
                                        continue
                                    }

                                    $copyFromUnc = "\\" + $oldMachineName + "\" + $partFrom
                                    $copyToUnc = "\\" + $newMachineName + "\" + $partTo

                                    $fileAndFolderPathsCapturedInCurrentFile += [PSCustomObject]@{
                                        OldServer           = $oldMachineName
                                        NewServer           = $newMachineName
                                        TaskName            = $taskName
                                        Line                = $line
                                        BeforePath          = $item2.BeforePath
                                        AfterPath           = $item2.AfterPath
                                        BeforeDirectoryPath = $beforeDirectoryPath
                                        AfterDirectoryPath  = $afterDirectoryPath
                                        CopyFromUnc         = $copyFromUnc
                                        CopyToUnc           = $copyToUnc
                                    }
                                }
                            }
                        }

                        $fileObject.ConvertedContent += $line
                    }

                    $allFileAndFolderPathsCaptured += $fileAndFolderPathsCapturedInCurrentFile
                    $fileObject.ConvertedFilename = $fileObject.ConvertedFilename.Replace("\\", "\")
                    Set-Content -Path $fileObject.ConvertedFilename -Value $fileObject.ConvertedContent
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

$allFileAndFolderPathsCaptured | ConvertTo-Json -Depth 10 | Out-File "$($PsScriptRoot)\allFileAndFolderPathsCaptured.json"

$distinctCopyStatements = @()
foreach ($item in $allFileAndFolderPathsCaptured) {
    $command = "xcopy " + $item.CopyFromUnc + " " + $item.CopyToUnc + " /E /I /Y"
    $distinctCopyStatements += $command
}
$distinctCopyStatements = $distinctCopyStatements | Sort-Object -Unique
$distinctCopyStatements | Out-File "$($PsScriptRoot)\distinctCopyStatements.txt"

Write-Host "All file and folder paths captured exported to $($PsScriptRoot)\allFileAndFolderPathsCaptured.json" -ForegroundColor Green

Write-Host "`n"
Write-Host "All done" -ForegroundColor Green

