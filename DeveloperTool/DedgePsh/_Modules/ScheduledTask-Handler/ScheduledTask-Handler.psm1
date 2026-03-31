<#
.SYNOPSIS
    Comprehensive management of Windows Scheduled Tasks.

.DESCRIPTION
    This module provides extensive functionality for managing Windows Scheduled Tasks,
    including creation, modification, deletion, and monitoring of tasks. It handles
    task credentials, scheduling, execution tracking, and configuration management.

.EXAMPLE
    New-ScheduledTask -TaskName "DailyBackup" -ScriptPath "C:\Scripts\Backup.ps1" -Schedule "DAILY"
    # Creates a new daily scheduled task

.EXAMPLE
    Get-ScheduledTaskStatus -TaskName "DailyBackup"
    # Retrieves the status of a scheduled task
#>

$modulesToImport = @("GlobalFunctions", "Infrastructure", "Export-Array")
foreach ($moduleName in $modulesToImport) {
  if (-not (Get-Module -Name $moduleName) -or $env:USERNAME -in @("FKGEISTA", "FKSVEERI")) {
    Import-Module $moduleName -Force
  }
} 



$global:SchTaskCommands = @()

  
if ($PSVersionTable.PSVersion.Major -lt 7) {
  Write-LogMessage "This script requires PowerShell 7 or later" -Level ERROR
  exit
}

function Get-FoldersToExclude {
  return @(
    "GoogleSystem",
    "GoogleUserPEH", 
    "Lenovo",
    "PowerToys", 
    "Microsoft"
  )
}

function Get-KeywordsToExclude {
  return @(
    "MicrosoftEdge",
    "OneDrive", 
    "RtkAudUService",
    "SensorFramework",
    "UDI_RegRestore",
    "PowerToys",
    "Autopatch",
    "Lenovo",
    "NextRunTime",
    "Windows"
  )
}

function Get-AllExcludeStrings {
  $result = @()
  $result += Get-FoldersToExclude
  $result += Get-KeywordsToExclude
  $result = $result | Sort-Object -Unique
  return $result
}

# function Get-ScheduledTaskCredentials {
#   param (
#     [Parameter(Mandatory = $false)]
#     [bool]$RunAsUser = $false
#   )
#   $schtasksArgs = @()

#   $username = "$env:USERDOMAIN\$env:USERNAME"
#   $password = Get-SecureStringUserPasswordAsPlainText
#   $env:tempPwd = $password
#   if ($RunAsUser) {
#     $schtasksArgs = @( "/RU", $username, "/RP", ('"' + "%tempPwd%" + '"'))
#   }
#   #set environment variable for password
#   $env:tempPwd = $password
#   [System.Environment]::SetEnvironmentVariable("tempPwd", $password, "User")
#   [System.Environment]::SetEnvironmentVariable("tempPwd", $password, "Machine")
#   [System.Environment]::SetEnvironmentVariable("tempPwd", $password, "Process")

#   return $schtasksArgs
# }

function Get-ScheduledTaskCredentials {
  param (
    [Parameter(Mandatory = $false)]
    [bool]$RunAsUser = $false
  )
  $schtasksArgs = @()

  if (-not $RunAsUser) {
    return $schtasksArgs
  }
  if ($env:USERNAME.ToUpper() -eq "SRVERP13" -or $env:USERNAME.ToUpper() -eq "P1_SRV_FKMPRD_APP") {
    return $schtasksArgs
  } 
  if (Test-AzureVirtualDesktopSessionHost) {
    Write-LogMessage "AVD session host detected - skipping /RU and /RP for scheduled task creation (interactive logged-on context)" -Level INFO
    return $schtasksArgs
  }

  $username = "$env:USERDOMAIN\$env:USERNAME"
  $password = Get-SecureStringUserPasswordAsPlainText
  $env:tempPwd = $password

  $schtasksArgs = @( "/RU", $username, "/RP", $password)
  return $schtasksArgs

}


<#
.SYNOPSIS
    Saves scheduled task configuration files.

.DESCRIPTION
    Saves the configuration files for scheduled tasks to a specified location.
    This includes task definitions, scripts, and any associated files.

.PARAMETER TaskName
    The name of the scheduled task.

.PARAMETER TaskFolder
    The folder where the task is located in Task Scheduler.

.PARAMETER ScriptPath
    The path to the script file associated with the task.

.EXAMPLE
    Save-ScheduledTaskFiles -TaskName "DailyBackup" -TaskFolder "\MyTasks" -ScriptPath "C:\Scripts\Backup.ps1"
    # Saves the task configuration files
#>
function Save-ScheduledTaskFiles {
  param (
    [Parameter(Mandatory = $false)]
    [System.Object[]]$CimTasks = @()
  )

  
  Write-LogMessage "Starting Save-ScheduledTaskFiles function" -Level DEBUG

  # Ensure current user has admin rights
  $currentPrincipal = New-Object Security.Principal.WindowsPrincipal([Security.Principal.WindowsIdentity]::GetCurrent())
  $adminGroup = [Security.Principal.WindowsBuiltInRole]::Administrator

  if (-not $currentPrincipal.IsInRole($adminGroup)) {
    Write-LogMessage "Current user is not in admin group, attempting to add" -Level DEBUG
    $identity = [Security.Principal.WindowsIdentity]::GetCurrent()
    $adsi = [ADSI]"WinNT://$env:COMPUTERNAME"
    $adminGroupObj = $adsi.Children | Where-Object { $_.SchemaClassName -eq 'group' -and $_.Name -eq 'Administrators' }
    $adminGroupObj.Add("WinNT://$env:USERDOMAIN/$($identity.Name)")
    Write-LogMessage "Added current user to administrators group" -Level WARN
  }
  else {
    Write-LogMessage "Current user already has admin rights" -Level DEBUG
  }

  # Grant read access to Tasks folder
  Write-LogMessage "Granting read access to Tasks folder" -Level DEBUG
  $tasksAcl = Get-Acl "C:\Windows\System32\Tasks"
  $identity = [Security.Principal.WindowsIdentity]::GetCurrent()
  $readRule = New-Object System.Security.AccessControl.FileSystemAccessRule(
    $identity.Name,
    "ReadAndExecute",
    "ContainerInherit,ObjectInherit",
    "None",
    "Allow"
  )
  $tasksAcl.AddAccessRule($readRule)
  Set-Acl -Path "C:\Windows\System32\Tasks" -AclObject $tasksAcl
  Write-LogMessage "Granted read access to Tasks folder for user $($env:USERNAME)" -Level INFO

  $sourcePath = "C:\Windows\System32\Tasks"
  $destinationPath = Join-Path $env:OptPath "data\ScheduledTasksExport"
  Write-LogMessage "Source path: $sourcePath, Destination path: $destinationPath" -Level DEBUG

  # Create destination folder if missing, empty it if present
  if (Test-Path $destinationPath -PathType Container) {
    Write-LogMessage "Destination path exists, clearing contents" -Level DEBUG
    Get-ChildItem -Path $destinationPath -Recurse | Remove-Item -Force -Recurse
  }
  else {
    Write-LogMessage "Creating destination directory" -Level DEBUG
    New-Item -ItemType Directory -Path $destinationPath -Force | Out-Null
  }

  # Define folders and keywords to exclude
  Write-LogMessage "Getting exclusion filters" -Level DEBUG
  $foldersToExclude = Get-FoldersToExclude
  $keywordsToExclude = Get-KeywordsToExclude
  Write-LogMessage "Folders to exclude: $($foldersToExclude -join ', ')" -Level DEBUG
  Write-LogMessage "Keywords to exclude: $($keywordsToExclude -join ', ')" -Level DEBUG




  $allTasks = @()
  # Get all task files from source, excluding specific folders and keywords
  Write-LogMessage "Scanning for task files in source path" -Level DEBUG

  if ($CimTasks.Count -gt 0) {
    foreach ($task in $CimTasks) {
      try {
        $fileName = $sourcePath + "\" + $task.TaskPath.TrimStart("\").TrimEnd("\") + "\" + $task.TaskName
        $item = Get-ChildItem -Path $fileName -File
        $allTasks += $item
      }
      catch {
        Write-LogMessage "Error getting task file $($fileName): $($_.Exception.Message)" -Level WARN
      }
    }
  }
  else {
    foreach ($item in (Get-ChildItem -Path $sourcePath -Recurse -File)) {
      $shouldInclude = $true
      
      # Check folders
      foreach ($folder in $foldersToExclude) {
        if ($item.FullName -like "*\$folder\*") {
          Write-LogMessage "Excluding task due to folder filter: $($item.FullName)" -Level DEBUG
          $shouldInclude = $false
          break
        }
      }
  
      # Check keywords
      if ($shouldInclude) {
        foreach ($keyword in $keywordsToExclude) {
          if ($item.Name -like "*$keyword*") {
            Write-LogMessage "Excluding task due to keyword filter: $($item.Name)" -Level DEBUG
            $shouldInclude = $false
            break
          }
        }
      }
      
      if ($shouldInclude) {
        Write-LogMessage "Including task: $($item.FullName)" -Level DEBUG
        $allTasks += $item
      }
    }      
  }
   

  Write-LogMessage "Found $($allTasks.Count) tasks after filtering" -Level INFO

  # Create array to store task information
  $taskInfo = @()
  Write-LogMessage "Starting task processing loop" -Level DEBUG

  # Process each task file
  foreach ($taskFile in $allTasks) {
    try {
      Write-LogMessage "Processing task file: $($taskFile.FullName)" -Level DEBUG
      
      # Calculate relative path to maintain folder structure
      $relativePath = $taskFile.FullName.Substring($sourcePath.Length + 1)
      $destinationFile = Join-Path $destinationPath ($relativePath + ".xml")
      $destinationFolder = Split-Path $destinationFile -Parent
      Write-LogMessage "Relative path: $relativePath, Destination file: $destinationFile" -Level DEBUG

      # Create destination folder if it doesn't exist
      if (-not (Test-Path $destinationFolder)) {
        Write-LogMessage "Creating destination folder: $destinationFolder" -Level DEBUG
        New-Item -ItemType Directory -Path $destinationFolder -Force | Out-Null
      }

      # Copy the task file
      Copy-Item -Path $taskFile.FullName -Destination $destinationFile -Force
      Write-LogMessage "Copied task: $relativePath" -Level INFO

      # Read task XML and extract information
      # try {
      #   Write-LogMessage "Reading XML content for task: $relativePath" -Level DEBUG
      #   $xml = [xml](Get-Content $taskFile.FullName)
        
      #   # Get trigger information
      #   $triggers = $xml.Task.Triggers
      #   $schedule = @()
      #   Write-LogMessage "Processing triggers for task: $relativePath" -Level DEBUG
        
      #   # Get next 30 days of schedule starting from today
      #   $startDate = Get-Date
      #   $endDate = $startDate.AddDays(30)
      #   Write-LogMessage "Schedule calculation period: $($startDate.ToString('yyyy-MM-dd')) to $($endDate.ToString('yyyy-MM-dd'))" -Level DEBUG
        
      #   if ($triggers.TimeTrigger) {
      #     Write-LogMessage "Processing TimeTrigger for task: $relativePath" -Level DEBUG
      #     $startTime = $triggers.TimeTrigger.StartBoundary
      #     $interval = $triggers.TimeTrigger.Repetition.Interval
      #     Write-LogMessage "TimeTrigger - StartTime: $startTime, Interval: $interval" -Level DEBUG
          
      #     # Parse interval into components
      #     if ($interval -match 'PT(\d+)H') {
      #       $hours = [int]$Matches[1]
      #       Write-LogMessage "Parsed interval: $hours hours" -Level DEBUG
            
      #       # Start from today but keep original time
      #       $originalTime = [DateTime]::Parse($startTime)
      #       $currentDate = Get-Date -Year $startDate.Year -Month $startDate.Month -Day $startDate.Day -Hour $originalTime.Hour -Minute $originalTime.Minute
            
      #       while ($currentDate -le $endDate) {
      #         if ($currentDate -ge $startDate) {
      #           $schedule += $currentDate.ToString("yyyy-MM-dd HH:mm")
      #         }
      #         $currentDate = $currentDate.AddHours($hours)
      #       }
      #       Write-LogMessage "Generated $($schedule.Count) schedule entries for TimeTrigger" -Level DEBUG
      #     }
      #   }
      #   elseif ($triggers.CalendarTrigger) {
      #     Write-LogMessage "Processing CalendarTrigger for task: $relativePath" -Level DEBUG
      #     $daysInterval = [int]$triggers.CalendarTrigger.ScheduleByDay.DaysInterval
      #     $startTime = $triggers.CalendarTrigger.StartBoundary
      #     Write-LogMessage "CalendarTrigger - StartTime: $startTime, DaysInterval: $daysInterval" -Level DEBUG
          
      #     # Start from today but keep original time
      #     $originalTime = [DateTime]::Parse($startTime)
      #     $currentDate = Get-Date -Year $startDate.Year -Month $startDate.Month -Day $startDate.Day -Hour $originalTime.Hour -Minute $originalTime.Minute
          
      #     while ($currentDate -le $endDate) {
      #       if ($currentDate -ge $startDate) {
      #         $schedule += $currentDate.ToString("yyyy-MM-dd HH:mm")
      #       }
      #       $currentDate = $currentDate.AddDays($daysInterval)
      #     }
      #     Write-LogMessage "Generated $($schedule.Count) schedule entries for CalendarTrigger" -Level DEBUG
      #   }
      #   else {
      #     Write-LogMessage "No standard time trigger found for task: $relativePath" -Level DEBUG
      #     $schedule += "No standard time trigger found"
      #   }

      #   # Get execution information
      #   $exec = $xml.Task.Actions.Exec
      #   $execPath = if ($exec.Command) { $exec.Command } else { "Not found" }
      #   $execArgs = if ($exec.Arguments) { $exec.Arguments } else { "No arguments" }
      #   Write-LogMessage "Execution info - Path: $execPath, Args: $execArgs" -Level DEBUG
 

      #   # Write-Host "triggers.TimeTrigger: $($triggers.TimeTrigger)"
      #   # Write-Host "triggers.TimeTrigger.Repetition.Interval: $($triggers.TimeTrigger.Repetition.Interval)"
      #   # Write-Host "triggers.CalendarTrigger: $($triggers.CalendarTrigger)" 
      #   # Write-Host "triggers.CalendarTrigger.ScheduleByDay.DaysInterval: $($triggers.CalendarTrigger.ScheduleByDay.DaysInterval)"
        
      #   $interval = if ($triggers.TimeTrigger) { $triggers.TimeTrigger.Repetition.Interval } `
      #     elseif ($triggers.CalendarTrigger) { "Every $($triggers.CalendarTrigger.ScheduleByDay.DaysInterval) days" } `
      #     else { "Unknown" }
      #   Write-LogMessage "Determined interval: $interval" -Level DEBUG
      #   #Write-LogMessage "interval: $interval" -Level INFO
      #   # PT4H means "Period Time 4 Hours" in ISO 8601 duration format
      #   # P = Period
      #   # T = Time (separates Period and Time components)
      #   # 4H = 4 Hours
      #   # Other examples:
      #   # PT1H = Every 1 hour
      #   # PT30M = Every 30 minutes
      #   # P1D = Every 1 day

      #   # Parse ISO 8601 duration format into components
      #   Write-LogMessage "Parsing ISO 8601 duration format: $interval" -Level DEBUG
      #   $intervalElements = if ($interval -match "^P(?:(\d+)D)?(?:T(?:(\d+)H)?(?:(\d+)M)?)?$") {
      #     @{
      #       Days    = if ($Matches[1]) { [int]$Matches[1] } else { 0 }
      #       Hours   = if ($Matches[2]) { [int]$Matches[2] } else { 0 }
      #       Minutes = if ($Matches[3]) { [int]$Matches[3] } else { 0 }
      #     }
      #   }
      #   else {
      #     $null
      #   }

      #   if ($intervalElements) {
      #     Write-LogMessage "Parsed interval elements - Days: $($intervalElements.Days), Hours: $($intervalElements.Hours), Minutes: $($intervalElements.Minutes)" -Level DEBUG
      #   }
      #   else {
      #     Write-LogMessage "Could not parse interval elements from: $interval" -Level DEBUG
      #   }

      #   # Build pretty description
      #   $intervalDescription = if ($intervalElements) {
      #     $parts = @()
      #     if ($intervalElements.Days -gt 0) {
      #       $parts += "$($intervalElements.Days) day$(if($intervalElements.Days -gt 1){'s'})"
      #     }
      #     if ($intervalElements.Hours -gt 0) {
      #       $parts += "$($intervalElements.Hours) hour$(if($intervalElements.Hours -gt 1){'s'})"
      #     }
      #     if ($intervalElements.Minutes -gt 0) {
      #       $parts += "$($intervalElements.Minutes) minute$(if($intervalElements.Minutes -gt 1){'s'})"
      #     }
      #     if ($parts.Count -gt 0) {
      #       "Every " + ($parts -join " and ")
      #     }
      #     else {
      #       "Unknown interval format"
      #     }
      #   }
      #   elseif ($interval -match "^Every \d+ days$") {
      #     $interval  # Already in pretty format
      #   }
      #   else {
      #     "Unknown interval format"
      #   }
      #   $localStartTime = [DateTime]::Parse($startTime).ToLocalTime().ToString("HH:mm")
      #   $intervalDescription = $intervalDescription + " starts at $localStartTime"
      #   Write-LogMessage "Generated interval description: $intervalDescription" -Level DEBUG

      #   # Add to task information array
      #   $taskInfo += [PSCustomObject]@{
      #     "ComputerName"        = $env:COMPUTERNAME
      #     "TaskName"            = $relativePath
      #     "Command"             = $execPath
      #     "Arguments"           = $execArgs
      #     "Schedule"            = $schedule
      #     "TriggerType"         = if ($triggers.TimeTrigger) { "Time Based" } `
      #       elseif ($triggers.CalendarTrigger) { "Calendar Based" } `
      #       else { "Other" }
      #     "Interval"            = $interval
      #     "IntervalDescription" = $intervalDescription
      #     "StartTime"           = if ($triggers.TimeTrigger) { $triggers.TimeTrigger.StartBoundary } `
      #       elseif ($triggers.CalendarTrigger) { $triggers.CalendarTrigger.StartBoundary } `
      #       else { "Unknown" }
      #   }
      #   Write-LogMessage "Added task info for: $relativePath" -Level DEBUG
      #   return $taskInfo
      # }
      # catch {
      #   Write-LogMessage "Error processing XML for $($taskFile.Name)" -Level ERROR -Exception $_
      # }
    }
    catch {
      Write-LogMessage "Error copying $($taskFile.Name)" -Level ERROR -Exception $_
    }
  }
  
  Write-LogMessage "Completed processing all task files" -Level DEBUG

  # Export task information to JSON
  $jsonPath = Join-Path $destinationPath "scheduled_tasks_run_info.json"
  $taskInfo | ConvertTo-Json -Depth 10 | Out-File -FilePath $jsonPath -Force
  
  Write-LogMessage "Scheduled tasks and information exported to $destinationPath" -Level INFO
  Write-LogMessage "Task information saved to $jsonPath" -Level INFO
  return "$($destinationPath.ToString())"
}
function Get-ScheduledTasksForUser {
  param (
    [Parameter(Mandatory = $true)]
    [string]$UserName
  )
  try {

    $excludeStrings = Get-AllExcludeStrings
    if ($UserName.Contains("\")) {
      $userNameOnly = $userName.Split('\')[1]
    }
    else {
      $userNameOnly = $UserName
    }
    $filteredTasks = @()
    $allTasks = Get-CimInstance -ClassName MSFT_ScheduledTask -Namespace root/Microsoft/Windows/TaskScheduler -ErrorAction SilentlyContinue |  Select-Object TaskName, TaskPath, @{Name = 'UserId'; Expression = { $_.Principal.UserId } } | Where-Object { $_.UserId -like "*$userNameOnly*" }
    if ($allTasks) {
      foreach ($task in $allTasks) {
        $taskName = $task.TaskName
        $includeTask = $true
        foreach ($excludeString in $excludeStrings) {
          if ($taskName -like "*$excludeString*") {
            $includeTask = $false
            break
          }
        }
        if ($includeTask) {
          $filteredTasks += $task
        }
      }
    }
  }
  catch {
    Write-LogMessage "Error getting scheduled tasks via CIM: $($_.Exception.Message)" -Level WARN
    $filteredTasks = @()
  }
  return $filteredTasks
}

function Update-ScheduledTaskCredentials {
  param (
    [Parameter(Mandatory = $true)]
    [System.Security.SecureString]$Password,
    [Parameter(Mandatory = $false)]
    [string]$Username = "$env:USERDOMAIN\$env:USERNAME",
    [Parameter(Mandatory = $false)]
    [switch]$Force,
    [Parameter(Mandatory = $false)]
    [string[]]$ChangeFromUserName = @()
  )

  try {

    Write-LogMessage "Starting scheduled task credential update for $Username" -Level WARN
      
  
    # Convert SecureString to plain text for task update
    $BSTR = [System.Runtime.InteropServices.Marshal]::SecureStringToBSTR($Password)
    [System.Runtime.InteropServices.Marshal]::ZeroFreeBSTR($BSTR)
  
    # Get all scheduled tasks that are to be moved
    $filteredTasks = @()
    if ($ChangeFromUserName) {
      foreach ($currentUserName in $ChangeFromUserName) {
        $filteredTasks += Get-ScheduledTasksForUser -UserName $currentUserName
      }
    }

    $filteredTasks += Get-ScheduledTasksForUser -UserName $Username

    if ($filteredTasks.Count -gt 0) {
      Save-ScheduledTaskFiles -CimTasks $filteredTasks
    }
    else {
      Save-ScheduledTaskFiles
    }

    foreach ($task in $filteredTasks) {
      try {
        Update-SingleTaskScheduledTaskCredentials -TaskName $($task.TaskName.TrimStart("\").TrimEnd("\"))  -TaskFolder $($task.TaskPath.TrimStart("\").TrimEnd("\")) -RunWhetherLoggedOnOrNot
      }
      catch {
        Write-LogMessage "Error updating task $($task.TaskName): $($_.Exception.Message)" -Level WARN
      }
    }    
  }
  catch {
    Write-LogMessage "No scheduled tasks found for $Username" -Level INFO
  }
}


function Save-ScheduledTaskFiles2 {
  param (
    [Parameter(Mandatory = $false)]
    [string]$OutputPath = "$env:OptPath\data\ScheduledTasks"
  )
    
  Write-LogMessage "Start exporting of scheduled tasks." -Level WARN
  $taskFolder = "C:\Windows\System32\Tasks"
  Write-LogMessage "Task folder: $taskFolder" -Level WARN
    
  # Create output directory if it doesn't exist
  if (-not (Test-Path $OutputPath)) {
    New-Item -ItemType Directory -Path $OutputPath -Force | Out-Null
  }
    
  # Get all scheduled tasks
  $taskService = New-Object -ComObject Schedule.Service
  $taskService.Connect()
  $rootFolder = $taskService.GetFolder("\")
  $tasks = $rootFolder.GetTasks(0)
    
  foreach ($task in $tasks) {
    if ($task.Name -ne "") {
      $fileName = Join-Path -Path $OutputPath -ChildPath "$($task.Name).xml"
      $task.Export($fileName)
      Write-LogMessage "Saved file $fileName" -Level INFO
    }
  }
  Write-LogMessage "Exporting of scheduled tasks finished." -Level INFO
}

<#
.SYNOPSIS
    Creates a scheduled task overview report.

.DESCRIPTION
    Generates a comprehensive report of all scheduled tasks, including their status,
    last run time, and next run time.

.PARAMETER ReportPath
    The path where the report should be saved.

.EXAMPLE
    New-ScheduledTaskOverviewReport -ReportPath "C:\Reports\TaskOverview.html"
    # Generates an HTML report of all scheduled tasks
#>
function New-ScheduledTaskOverviewReport {
  $servers = Get-ServerList
  # add current computer to the list
  $servers += $env:COMPUTERNAME
  # Initialize array to store all task info
  $allTaskInfo = @()

  Write-LogMessage "Processing tasks from $($servers.Count) servers/machines..." -Level INFO

  foreach ($server in $servers) {
    $sourcePath = "\\$server\opt\data\ScheduledTasksExport"
    if ((Test-PortConnectivity -ComputerName $server -Port 445) -and (Test-PortConnectivity -ComputerName $server -Port 139)) {
      # Check if path exists
      if (Test-Path $sourcePath -PathType Container) {

        Write-LogMessage "Processing tasks from $server..." -Level INFO

      

        # Look for JSON files
        $jsonFile = Join-Path $sourcePath "scheduled_tasks_run_info.json"
        if (Test-Path $jsonFile -PathType Leaf) {
          try {
            # Read and parse JSON file
            $serverTasks = Get-Content $jsonFile | ConvertFrom-Json
          
            # Add tasks to combined array
            $allTaskInfo += $serverTasks
          
            Write-LogMessage "Successfully processed $($serverTasks.Count) tasks from $server" -Level INFO
          }
          catch {
            Write-LogMessage "Error processing JSON from $server" -Level ERROR -Exception $_
          }
        }
        else {
          Write-LogMessage "No task info JSON found for $server" -Level WARN
        }
      }
      else {
        Write-LogMessage "Could not access $sourcePath" -Level WARN
      }
    }
    else {
      Write-LogMessage "Could not access $server" -Level WARN
    }
  }


  # Create output directory if it doesn't exist
  $outputDir = Join-Path $env:optPath "data"
  if (-not (Test-Path $outputDir)) {
    New-Item -ItemType Directory -Path $outputDir -Force | Out-Null
  }

  # Export combined data
  $outputJsonPath = Join-Path $outputDir "ScheduledTaskOverviewReport.json"
  $Title = "$($env:COMPUTERNAME.ToLower()) - Scheduled Tasks Overview Report"
  $outputHtmlPath = Join-Path $outputDir "$Title.html"

  $allTaskInfo | ConvertTo-Json -Depth 10 | Out-File -FilePath $outputJsonPath -Force
  Export-ArrayToHtmlFile -Content $allTaskInfo -OutputPath $outputHtmlPath -Title $Title -AddToDevToolsWebPath "Server/ScheduledTasks"

  #(Get-DevToolsWebPath)

  Write-LogMessage "Generated overview reports:" -Level INFO
  Write-LogMessage "JSON: $outputJsonPath" -Level INFO
  Write-LogMessage "HTML: $outputHtmlPath" -Level INFO

}



<#
.SYNOPSIS
    Gets PowerShell script files from a directory.

.DESCRIPTION
    Retrieves all .ps1 files from the specified directory.

.PARAMETER currentFolder
    The folder to search for .ps1 files. Defaults to $PSScriptRoot.

.EXAMPLE
    $scripts = GetPs1File -currentFolder "C:\Scripts"
    # Returns array of .ps1 files in the specified folder
#>
function GetPs1File ($currentFolder = $PSScriptRoot) {
  # get all ps1 files in the current folder
  $ps1Files = Get-ChildItem -Path $currentFolder -Filter "*.ps1"


  # get the number of ps1 files
  $ps1FilesCount = $ps1Files.Count

  if ($ps1FilesCount -gt 1) {
    # ask user which ps1 file to run by showing the file names and a choice of numbers
    $index = 1
    $ps1Files | ForEach-Object {
      Write-LogMessage "$index - $($_.Name)" -Level INFO
      $index++
    }
    $ps1FileChoice = [int](Read-Host "Which ps1 file to run? (1-$ps1FilesCount)")
    # get the ps1 file
    $ps1File = $ps1Files[$ps1FileChoice - 1]
  }
  elseif ($ps1FilesCount -eq 1) {
    $ps1File = $ps1Files[0]
  }
  else {
    Write-LogMessage "No ps1 files found in $currentFolder" -Level ERROR
    exit
  }
  return $ps1File
}

<#
.SYNOPSIS
    Executes a command in a specified context.

.DESCRIPTION
    Runs a command either locally or remotely based on the provided context.
    Can optionally ignore errors during execution.

.PARAMETER Command
    The command to execute.

.PARAMETER Context
    The execution context (local or remote computer).

.PARAMETER IgnoreError
    If true, continues execution even if errors occur.

.EXAMPLE
    Invoke-SchedTaskCommand -Command "Get-Service" -Context "localhost"
    # Executes the command locally
#>
function Invoke-SchedTaskCommand ($Command, $Context, $IgnoreError = $true) {
  try {
    if ($Command.GetType() -ne [System.String]) {
      Write-LogMessage "Command type: $($Command.GetType())" -Level WARN
      $Command = $Command -join " "
    }

    
    
    # $pos = $Command.IndexOf("/")
    # $schtasksArgs = "/" + $Command.Substring($pos + 1)
    $outputFile = [System.IO.Path]::GetTempFileName()
    $errorFile = [System.IO.Path]::GetTempFileName()
    $jsonFile = Join-Path $(Get-ApplicationDataPath) "schtasks_result.json"
    # Write and execute command
    Remove-Item $outputFile -Force -ErrorAction SilentlyContinue | Out-Null
    $Command = $Command.Trim()

    $schtaskExePath = Get-CommandPathWithFallback -Name "schtasks"
    if ($Command.ToLower() -contains "schtasks") {
      $Command = $Command.Split(" ")[-1]
    }
    $logCommand = $schtaskExePath + " " + $Command

    Write-LogMessage "Running $schtaskExePath with arguments: $Command" -Level DEBUG
    $result = Start-Process $schtaskExePath -ArgumentList $Command -NoNewWindow -Wait -PassThru -RedirectStandardOutput $outputFile -RedirectStandardError $errorFile
    $result | ConvertTo-Json -Compress -Depth 100 | Out-File -FilePath $jsonFile -Force
    $output = Get-Content $outputFile -ErrorAction SilentlyContinue
    $errorOutput = Get-Content $errorFile -ErrorAction SilentlyContinue

    if (-not $global:SchTaskCommands) {
      $global:SchTaskCommands = @()
    }
    $global:SchTaskCommands += [PSCustomObject]@{
      Context      = $Context.ToTitleCase()
      Command      = $logCommand
      Output       = $output
      ErrorOutput  = $errorOutput
      ExitCode     = $result.ExitCode
      Username     = $env:USERNAME
      ComputerName = $env:COMPUTERNAME
      Date         = Get-Date
    }

    Remove-Item $outputFile -Force -ErrorAction SilentlyContinue
    Remove-Item $errorFile -Force -ErrorAction SilentlyContinue

    if ($result.ExitCode -ne 0) {
      $logLevel = if ($IgnoreError) { "DEBUG" } else { "ERROR" }
      Write-LogMessage "Result ExitCode: $($result.ExitCode)" -Level $logLevel
      Write-LogMessage "Output: $output" -Level $logLevel
      Write-LogMessage "Error: $errorOutput" -Level $logLevel
      if (-not $IgnoreError) {
        throw "schtasks.exe failed with exit code $($result.ExitCode)"
      }
    }

    if ($output -notlike "*success*" -and -not $IgnoreError) {
      Write-LogMessage "Failed to $($Context): $output" -Level ERROR
      throw "Failed to $($Context): $output"
    }

    return $output
  }
  catch {
    if (-not $IgnoreError) {
      Write-LogMessage "Failed to $($Context)" -Level ERROR -Exception $_
      throw
    }
  }

}


function Get-ExistingScheduledTasks {
  param (
    [Parameter(Mandatory = $false)]
    [string]$TaskName,
        
    [Parameter(Mandatory = $false)]
    [string]$TaskFolder = "\DevTools",

    [Parameter(Mandatory = $false)]
    [bool]$IgnoreError = $true

  )

  try {

    if ($TaskName -ne "") {
      $TaskName = Set-TaskName $TaskName $TaskFolder
    }
    
    # Write-LogMessage "Getting existing scheduled tasks" -Level INFO -ForegroundColor Green
    
    $schtasksArgs = @(
      "/Query", # Query
      "/FO", "CSV" # Format output as list
    )

    if ($TaskName -ne "") {
      $schtasksArgs += @(
        "/TN", "`"$TaskName`"" # Specifies the task name
      )
    }

    
    $output = Invoke-SchedTaskCommand -Command $($schtasksArgs -join " ") -Context "list scheduled tasks" -IgnoreError $IgnoreError

    $keywordsToExclude = Get-AllExcludeStrings
    $keywordsToExclude += "ERROR:"
    $result = @()
    $count = 0
    foreach ($line in $output) {
      if ($count -eq 0) {
        $count++
        continue
      }
      $shouldInclude = $true
      # Check if line contains any excluded keywords
      foreach ($keyword in $keywordsToExclude) {
        if ($line -like "*$keyword*") {
          $shouldInclude = $false
          break
        }
      }
      if ($shouldInclude -and $line.Trim() -ne "") {
        $splitLine = $line.Split(",")
        if ($splitLine[0] -like "*TaskName*") {
          continue
        }
        $result += @(
          [PSCustomObject]@{
            TaskName    = $($splitLine[0].Split("\")[-1] ?? $splitLine[0]).Replace("`"", "")
            TaskFolder  = $($splitLine[0].Split("\")[-2] ?? "").Replace("`"", "")
            TaskPath    = $($splitLine[0] ?? "").Replace("`"", "")
            NextRunTime = $($splitLine[1] ?? "").Replace("`"", "")
            Status      = $($splitLine[2] ?? "").Replace("`"", "")
          }
        )
      }
      $count++
    }
    if ($result.Count -eq 0) {
      Write-LogMessage "No scheduled tasks found" -Level INFO
    }
    else {
      $result = $result | Sort-Object -Property TaskName
    }
    return $result
  }
  catch {
    if (-not $IgnoreError) {
      Write-LogMessage "Failed to get existing scheduled tasks: $($TaskName): $_" -Level ERROR -Exception $_
      if ($_.Exception.Message -like "*invalid*" -or
        $_.Exception.Message -like "*incorrect*" -or
        $_.Exception.Message -like "*denied*") {
        Remove-UserPasswordAsSecureString
      }

      throw
    }
  }
}

<#
.SYNOPSIS
    Sets the full task name including folder path.

.DESCRIPTION
    Combines the task name and folder path to create a full task path.

.PARAMETER TaskName
    The name of the scheduled task.

.PARAMETER TaskFolder
    The folder where the task is located.

.EXAMPLE
    $fullTaskName = Set-TaskName -TaskName "Backup" -TaskFolder "\MyTasks"
    # Returns "\MyTasks\Backup"
#>
function Set-TaskName (
  [Parameter(Mandatory = $true)]
  [string]$TaskName,

  [Parameter(Mandatory = $false)]
  [string]$TaskFolder = ""
) {
  if ([string]::IsNullOrEmpty($TaskName) -and $TaskName.Contains("\")) {
    return $TaskName
  }

  # Set task name if not provided
  $modifiedTaskFolder = $TaskFolder
  if ($PSScriptRoot -like "*DEVTOOLS*" -and $modifiedTaskFolder -eq "") {
    $modifiedTaskFolder = "DevTools"
  }

  if (-not $TaskName) {
    $scriptName = Get-Item $($$)
    $TaskName = $scriptName.DirectoryName.Split('\')[-1]
    Write-LogMessage "Set TaskName automatically: $TaskName" -Level INFO
  }

  if ($modifiedTaskFolder -ne "" -and $TaskName -notlike "*$modifiedTaskFolder*") {
    $TaskName = "$modifiedTaskFolder\$TaskName"
  }
  
  return $TaskName
}

<#
.SYNOPSIS
    Tests connectivity to a remote computer.

.DESCRIPTION
    Verifies if a remote computer is accessible using various methods.

.PARAMETER ComputerName
    The name of the computer to test.

.EXAMPLE
    Test-ComputerConnection -ComputerName "Server01"
    # Returns true if the computer is accessible
#>
function Test-ComputerConnection {
  param(
    [Parameter(Mandatory = $true)]
    [string]$ComputerName
  )

  if ($ComputerName -ne $env:COMPUTERNAME) {
    if (-not (Test-Connection -ComputerName $ComputerName -Count 1 -Quiet)) {
      throw "Cannot connect to computer: $ComputerName"
    }
    if (-not $Username) {
      throw "Remote computer requires username"
    }
  }
}

function Test-ScheduledTaskExists {
  [CmdletBinding()]
  param (
    [Parameter(Mandatory = $true)]
    [string]$TaskName,
        
    [Parameter(Mandatory = $false)]
    [string]$TaskFolder = "DevTools",
  
    [Parameter(Mandatory = $false)]
    [bool]$IgnoreError = $true
  )

  $existingTasks = Get-ExistingScheduledTasks -TaskName $TaskName -TaskFolder $TaskFolder -IgnoreError $IgnoreError
  if ($existingTasks.Count -eq 0) {
    return $false
  }
  else {  
    return $true
  }
}

function Get-ScheduledTaskRunningStatus {
  [CmdletBinding()]
  param (
    [Parameter(Mandatory = $true)]
    [string]$TaskName,
        
    [Parameter(Mandatory = $false)]
    [string]$TaskFolder = "DevTools",
  
    [Parameter(Mandatory = $false)]
    [bool]$IgnoreError = $true
  )

  
  $TaskName = Set-TaskName $TaskName $TaskFolder
  Write-LogMessage "Getting scheduled task status for $TaskName" -Level INFO
  
  try {
    $schtasksArgs = @(
      "/Query",
      "/TN", "`"$TaskName`""
    )
    $command = $schtasksArgs -join " "
    
    $output = Invoke-SchedTaskCommand -Command $command -Context "get scheduled task status" -IgnoreError $IgnoreError


    # Parse the output to extract task information dynamically
    $resultObject = $null
    
    if ($output -and $output.Count -gt 0) {
      # Find the line with task data (skip header lines)
      $taskLine = $output | Where-Object { $_ -match "^\s*\S+\s+\d{2}\.\d{2}\.\d{4}" -or $_ -match "^\s*\S+.*\s+(Ready|Running|Disabled)" }
      
      if ($taskLine) {
        # Split the line by multiple spaces to get columns
        $columns = $taskLine -split '\s{2,}' | Where-Object { $_ -ne "" }
        
        if ($columns.Count -ge 3) {
          $resultObject = [PSCustomObject]@{
            Folder      = if ($TaskFolder.StartsWith("\")) { $TaskFolder.Substring(1) } else { $TaskFolder }
            TaskName    = $columns[0].Trim()
            NextRunTime = if ($columns.Count -ge 3) { $columns[1].Trim() } else { "" }
            Status      = $columns[-1].Trim()
          }
        }
      }
    }
    
    # Fallback if parsing fails
    if (-not $resultObject) {
      $resultObject = [PSCustomObject]@{
        Folder      = if ($TaskFolder.StartsWith("\")) { $TaskFolder.Substring(1) } else { $TaskFolder }
        TaskName    = $TaskName.Split('\')[-1]
        NextRunTime = ""
        Status      = "Unknown"
      }
    }

    Write-LogMessage "Folder: $($resultObject.Folder), TaskName: $($resultObject.TaskName), NextRunTime: $($resultObject.NextRunTime), Status: $($resultObject.Status)" -Level INFO
    
    if ($output -like "*running*") {
      return $true
    }
    else {
      return  $false
    }
  }
  catch {
    if (-not $IgnoreError) {
      Write-LogMessage "Failed to stop scheduled task: $($_.InvocationInfo.ScriptLineNumber): $_" -Level ERROR -Exception $_
      throw
    }
  }
}

<#
.SYNOPSIS
    Stops a scheduled task.

.DESCRIPTION
    Stops a running scheduled task on the specified computer.

.PARAMETER TaskName
    The name of the task to stop.

.PARAMETER TaskFolder
    The folder containing the task.

.EXAMPLE
    Stop-ScheduledTask -TaskName "Backup" -TaskFolder "\MyTasks"
    # Stops the specified task on the remote computer
#>
function Stop-ScheduledTask {
  [CmdletBinding()]
  param (
    [Parameter(Mandatory = $true)]
    [string]$TaskName,
        
    [Parameter(Mandatory = $false)]
    [string]$TaskFolder = "DevTools",
  
    [Parameter(Mandatory = $false)]
    [bool]$IgnoreError = $true
  )

  if (-not (Test-ScheduledTaskExists -TaskName $TaskName -TaskFolder $TaskFolder -IgnoreError $IgnoreError)) {
    return
  }
  if (-not (Get-ScheduledTaskRunningStatus -TaskName $TaskName -TaskFolder $TaskFolder -IgnoreError $IgnoreError)) {
    Write-LogMessage "Scheduled task $TaskName is not running" -Level INFO
    return
  }
  
  Write-LogMessage "Stopping scheduled task $TaskName" -Level INFO
  
  try {
    $schtasksArgs = @(
      "/End",

      "/TN", "`"$TaskName`""
    )
    #$schtasksArgs += Get-ScheduledTaskCredentials 
    
  
    $null = Invoke-SchedTaskCommand -Command $($schtasksArgs -join " ") -Context "stop scheduled task" -IgnoreError $IgnoreError
  }
  catch {
    if (-not $IgnoreError) {
      Write-LogMessage "Failed to stop scheduled task: $($_.InvocationInfo.ScriptLineNumber): $_" -Level ERROR -Exception $_
      throw
    }
  }
}

<#
.SYNOPSIS
    Disables a scheduled task.

.DESCRIPTION
    Disables a scheduled task on the specified computer, preventing it from running
    on its normal schedule.

.PARAMETER TaskName
    The name of the task to disable.

.PARAMETER TaskFolder
    The folder containing the task.


.EXAMPLE
    Disable-ScheduledTask -TaskName "Backup" -TaskFolder "\MyTasks" 
    # Disables the specified task
#>
function Disable-ScheduledTask {
  [CmdletBinding()]
  param (
    [Parameter(Mandatory = $true)]
    [string]$TaskName,
      
    [Parameter(Mandatory = $false)]
    [string]$TaskFolder = "DevTools",

    [Parameter(Mandatory = $false)]
    [bool]$IgnoreError = $true
  )
  if (-not (Test-ScheduledTaskExists -TaskName $TaskName -TaskFolder $TaskFolder -IgnoreError $IgnoreError)) {
    return
  }
  
  Stop-ScheduledTask -TaskName $TaskName -TaskFolder $TaskFolder -IgnoreError $IgnoreError
  Write-LogMessage "Disabling scheduled task $TaskName" -Level INFO
  


  try {
    $schtasksArgs = @(
      "/Change",
      "/TN", "`"$TaskName`"",
      "/DISABLE"
    )

    
    $null = Invoke-SchedTaskCommand -Command $($schtasksArgs -join " ") -Context "disable scheduled task" -IgnoreError $IgnoreError
  }
  catch {
    if (-not $IgnoreError) {
      Write-LogMessage "Failed to disable scheduled task: $($_.InvocationInfo.ScriptLineNumber): $_" -Level ERROR -Exception $_
      if ($_.Exception.Message -like "*invalid*" -or
        $_.Exception.Message -like "*incorrect*" -or
        $_.Exception.Message -like "*denied*") {
        Remove-UserPasswordAsSecureString
      }

      throw
    }
  }
}

<#
.SYNOPSIS
    Enables a scheduled task.

.DESCRIPTION
    Enables a disabled scheduled task on the specified computer, allowing it to run
    on its normal schedule.

.PARAMETER TaskName
    The name of the task to enable.

.PARAMETER TaskFolder
    The folder containing the task.

.EXAMPLE
    Enable-ScheduledTask -TaskName "Backup" -TaskFolder "\MyTasks" 
    # Enables the specified task
#>
function Enable-ScheduledTask {
  [CmdletBinding()]
  param (
    [Parameter(Mandatory = $true)]
    [string]$TaskName,
 
    [Parameter(Mandatory = $false)]
    [bool]$IgnoreError = $true
  )

  
  Write-LogMessage "Enabling scheduled task $TaskName" -Level INFO
  

  try {
    $schtasksArgs = @(
      "/Change",      
      "/TN", "`"$TaskName`"",
      "/ENABLE"
    )

    
    $null = Invoke-SchedTaskCommand -Command $($schtasksArgs -join " ") -Context "enable scheduled task" -IgnoreError $IgnoreError
  }
  catch {
    if (-not $IgnoreError) {
      Write-LogMessage "Failed to enable scheduled task: $($_.InvocationInfo.ScriptLineNumber): $_" -Level ERROR -Exception $_
      if ($_.Exception.Message -like "*invalid*" -or
        $_.Exception.Message -like "*incorrect*" -or
        $_.Exception.Message -like "*denied*") {
        Remove-UserPasswordAsSecureString
      }

      throw
    }
  }
}

<#
.SYNOPSIS
    Starts a scheduled task immediately.

.DESCRIPTION
    Triggers immediate execution of a scheduled task on the specified computer.

.PARAMETER TaskName
    The name of the task to start.

.PARAMETER TaskFolder
    The folder containing the task.

.EXAMPLE
    Start-ScheduledTask -TaskName "Backup" -TaskFolder "\MyTasks" 
    # Starts the specified task immediately
#>
function Start-ScheduledTask {
  [CmdletBinding()]
  param (
    [Parameter(Mandatory = $true)]
    [string]$TaskName,
  
    [Parameter(Mandatory = $false)]
    [bool]$IgnoreError = $true
  )
  if (-not (Test-ScheduledTaskExists -TaskName $TaskName -TaskFolder $TaskFolder -IgnoreError $IgnoreError)) {
    return
  }
  
  Write-LogMessage "Starting scheduled task $TaskName" -Level INFO
  

  try {
    $schtasksArgs = @(
      "/Run",

      "/TN", "`"$TaskName`""
    )

    
    $null = Invoke-SchedTaskCommand -Command $($schtasksArgs -join " ") -Context "run scheduled task" -IgnoreError $IgnoreError
  }
  catch {
    if (-not $IgnoreError) {
      Write-LogMessage "Failed to run scheduled task" -Level ERROR -Exception $_
      if ($_.Exception.Message -like "*invalid*" -or
        $_.Exception.Message -like "*incorrect*" -or
        $_.Exception.Message -like "*denied*") {
        Remove-UserPasswordAsSecureString
      }

      throw
    }
  }
}


<#
.SYNOPSIS
    Removes a scheduled task.

.DESCRIPTION
    Deletes a scheduled task from the Task Scheduler on the specified computer.

.PARAMETER TaskName
    The name of the task to remove.

.PARAMETER TaskFolder
    The folder containing the task.


.EXAMPLE
    Remove-ScheduledTask -TaskName "Backup" -TaskFolder "\MyTasks" -ComputerName "Server01"
    # Removes the specified task
#>
function Remove-ScheduledTask {
  [CmdletBinding()]
  param (
    [Parameter(Mandatory = $false)]
    [string]$TaskName,
        
    [Parameter(Mandatory = $false)]
    [string]$TaskFolder = "DevTools",

    [Parameter(Mandatory = $false)]
    [string]$SourceFolder,

    [Parameter(Mandatory = $false)]
    [bool]$IgnoreError = $true
  )

  if (-not [string]::IsNullOrEmpty($SourceFolder)) {
    $obj = Get-CommonTaskParams -SourceFolder $SourceFolder -TaskFolder $TaskFolder -SkipExecutableCheck $true
    $TaskName = $obj.TaskName
  }

  try {
    if (-not (Test-ScheduledTaskExists -TaskName $TaskName -TaskFolder $TaskFolder -IgnoreError $IgnoreError)) {
      return
    }
    Disable-ScheduledTask -TaskName $TaskName -TaskFolder $TaskFolder -IgnoreError $IgnoreError

    $TaskName = Set-TaskName $TaskName $TaskFolder

    
    Write-LogMessage "Removing scheduled task $TaskName" -Level INFO

    $schtasksArgs = @(
      "/Delete", # Deletes a scheduled task
      "/TN", "`"$TaskName`"" # Specifies the task name
      "/F" # Forces deletion
    )

    $null = Invoke-SchedTaskCommand -Command $($schtasksArgs -join " ") -Context "delete scheduled task" -IgnoreError $IgnoreError

    Write-LogMessage "Task '$TaskName' deleted successfully on $ComputerName" -Level INFO
  }
  catch {
    if (-not $IgnoreError) {
      Write-LogMessage "Failed to delete scheduled task: $($_.InvocationInfo.ScriptLineNumber): $_" -Level ERROR -Exception $_
      if ($_.Exception.Message -like "*invalid*" -or
        $_.Exception.Message -like "*incorrect*" -or
        $_.Exception.Message -like "*denied*") {
        Remove-UserPasswordAsSecureString
      }

      throw
    }
  }
}

<#
.SYNOPSIS
    Gets the script path for a scheduled task.

.DESCRIPTION
    Retrieves the full path to the script associated with a scheduled task.

.PARAMETER TaskName
    The name of the task.

.PARAMETER TaskFolder
    The folder containing the task.


.EXAMPLE
    $scriptPath = Get-ScriptPath -TaskName "Backup" -TaskFolder "\MyTasks" -ComputerName "Server01"
    # Returns the path to the task's script
#>
function Get-ScriptPath {
  param (
    [Parameter(Mandatory = $true)]
    [string]$Executable,

    [Parameter(Mandatory = $true)]
    [string]$TaskName,

    [Parameter(Mandatory = $false)]
    [string]$TaskFolder = "DevTools"
  )

  $TaskName = Set-TaskName $TaskName $TaskFolder
  $onlyTaskName = $TaskName.Split('\')[-1]
  $onlyTaskName = $onlyTaskName.Split('.')[0]
  if ($Executable.StartsWith($env:OptPath)) {
    $ScriptPath = $Executable
  }
  elseif ($$ -like "*DevTools*" -or $TaskFolder -eq "DevTools") {
    $ScriptPath = $env:OptPath + "\DedgePshApps\$onlyTaskName\$Executable"
  }
  else {
    $ScriptPath = $env:OptPath + "\DedgePshApps\$onlyTaskName\$Executable"
  }
  return $ScriptPath
}

<#
.SYNOPSIS
    Creates a new scheduled task.

.DESCRIPTION
    Creates a new scheduled task with specified settings on the target computer.
    Supports various scheduling options and task configurations.

.PARAMETER TaskName
    The name for the new task.

.PARAMETER TaskFolder
    The folder to create the task in.


.PARAMETER ScriptBlock
    The PowerShell script block to execute.

.PARAMETER Trigger
    The schedule trigger for the task.

.EXAMPLE
    New-ScheduledTask -TaskName "DailyBackup" -TaskFolder "\MyTasks" -ComputerName "Server01" -ScriptBlock { Backup-Data } -Trigger $dailyTrigger
    # Creates a new scheduled task that runs daily
#>
function New-ScheduledTask {
  [CmdletBinding()]
  param (
    [Parameter(Mandatory = $false)]
    [string]$SourceFolder,

    [Parameter(Mandatory = $false)]
    [string]$TaskName,
        
    [Parameter(Mandatory = $false)]
    [string]$Executable,

    [Parameter(Mandatory = $false)]
    [string]$Arguments,
        
    [Parameter(Mandatory = $false)]
    [int]$StartHour = 6,
        
    [Parameter(Mandatory = $false)]
    [int]$StartMinute = 0,

    [Parameter(Mandatory = $false)]
    [string]$TaskFolder = "DevTools",
        
    [Parameter(Mandatory = $false)]
    [bool]$RunAsUser = $true,
        
    [Parameter(Mandatory = $false)]
    [ValidateSet("Highest", "LeastPrivilege")]
    [string]$RunLevel = "Highest",

    [Parameter(Mandatory = $false)]
    [ValidateSet("Daily", "Hourly", "Monthly", "Weekly", "Every30Minutes", "Every15Minutes", "Every5Minutes", "EveryMinute", "Every3Hours", "Once")]
    [string]$RunFrequency = "Daily",

    [Parameter(Mandatory = $false)]
    [ValidateSet("Hidden", "Normal", "Minimized", "Maximized")]
    [string]$WindowStyle = "Hidden",

    [Parameter(Mandatory = $false)]
    [bool]$RunAtOnce = $false,

    [Parameter(Mandatory = $false)]
    [bool]$RecreateTask = $false,

    [Parameter(Mandatory = $false)]
    [string]$XmlFile,

    [Parameter(Mandatory = $false)]
    [ValidateSet("MON", "TUE", "WED", "THU", "FRI", "SAT", "SUN")]
    [string]$DayOfWeek,

    # Date on which a Once task should run (yyyy-MM-dd). Defaults to today.
    [Parameter(Mandatory = $false)]
    [string]$StartDate
  )


  if (-not [string]::IsNullOrEmpty($SourceFolder)) {
    $obj = Get-CommonTaskParams -SourceFolder $SourceFolder -ExecutableName $Executable -TaskFolder $TaskFolder -TaskName $TaskName
    $TaskName = $obj.TaskName
    $Executable = $obj.ExecutablePath
  }

  $existingTask = Test-ScheduledTaskExists -TaskName $TaskName -TaskFolder $TaskFolder -IgnoreError $true
  if ($existingTask -and -not $RecreateTask) {
    Write-LogMessage "Scheduled task $TaskName already exists" -Level WARN
    return
  } 
  elseif ($existingTask -and $RecreateTask) {
    Write-LogMessage "Recreating scheduled task $TaskName" -Level INFO
    Remove-ScheduledTask -TaskName $TaskName -TaskFolder $TaskFolder -IgnoreError $true
  }

  try {
    $TaskName = Set-TaskName $TaskName $TaskFolder
    if (-not [string]::IsNullOrEmpty($XmlFile)) {
      $schtasksArgs = @(
        "/Create", # Creates a new scheduled task
        "/TN", "`"$TaskName`"", # Specifies the task name
        "/XML", "`"$XmlFile`"" # Specifies the XML file to use
        "/F"  # Forces creation, overwriting if exists
      )
      if ($RunAsUser) {
        $credentials = Get-ScheduledTaskCredentials -RunAsUser $RunAsUser
        $schtasksArgs += $credentials
      }
    }
    else {
      

      $ScriptPath = Get-ScriptPath $Executable $TaskName $TaskFolder

    
      Write-LogMessage "Creating scheduled task $TaskName" -Level INFO
    

      # Build schtasks command
      $startTime = "$($StartHour.ToString('00')):$($StartMinute.ToString('00'))"  # Format hour properly
    
      # Handle different file types differently
      $fileExtension = [System.IO.Path]::GetExtension($Executable).ToLower()
    
      switch ($fileExtension) {
        ".ps1" {
          $command = "pwsh.exe"
          $scriptArguments = if ([string]::IsNullOrWhiteSpace($Arguments)) { $null } else { "$Arguments" }
          #$arguments = "-WindowStyle Hidden -ExecutionPolicy Bypass -File '$ScriptPath' $scriptArguments"
          if ($scriptArguments) {
            $arguments = "-WindowStyle $WindowStyle -File '$($ScriptPath.Trim())' $($scriptArguments.Trim())"
          }
          else {
            $arguments = "-WindowStyle $WindowStyle -File '$($ScriptPath.Trim())'"
          }
        }
        ".bat" {
          $command = $Executable.Trim()
          if (-not [string]::IsNullOrWhiteSpace($Arguments)) {
            $arguments = $Arguments
          }
          else {
            $arguments = ""
          }
        }
        ".cmd" {
          $command = $Executable.Trim()
          if (-not [string]::IsNullOrWhiteSpace($Arguments)) {
            $arguments = $Arguments
          }
          else {
            $arguments = ""
          }
        }
        ".exe" {
          $command = $ScriptPath.Trim()
          if (-not [string]::IsNullOrWhiteSpace($Arguments)) {
            $arguments = $Arguments
          }
          else {
            $arguments = ""
          }
        }
        default {
          throw "Unsupported file type: $fileExtension. Supported types are: .ps1, .bat, .cmd, .exe"
        }
      }
      # Setup base schtasks arguments
      $schtasksArgs = @(
        "/Create", # Creates a new scheduled task
        "/TN", "`"$TaskName`"", # Specifies the task name
        "/TR", "`"$command $arguments`"", # Specifies the program/command to run
        "/F"  # Forces creation, overwriting if exists
      )


      # Add schedule-specific arguments based on RunFrequency
      switch ($RunFrequency) {
        "Daily" {
          $schtasksArgs += @(
            "/SC", "DAILY",
            "/ST", $startTime
          )
        }
        "Hourly" {
          $schtasksArgs += @(
            "/SC", "HOURLY",
            "/ST", (Get-Date).AddHours(1).ToString("HH:mm")
          )
        }
        "Every3Hours" {
          $schtasksArgs += @(
            "/SC", "HOURLY",
            "/MO", "3",
            "/ST", $startTime
          )
        }
        "Monthly" {
          $schtasksArgs += @(
            "/SC", "MONTHLY",
            "/ST", $startTime
          )
        }
        "Weekly" {
          $schtasksArgs += @(
            "/SC", "WEEKLY",
            "/ST", $startTime
          )
          if (-not [string]::IsNullOrEmpty($DayOfWeek)) {
            $schtasksArgs += @("/D", $DayOfWeek)
          }
        }
        "Every30Minutes" {
          $schtasksArgs += @(
            "/SC", "MINUTE",
            "/MO", "30",
            "/ST", (Get-Date).AddMinutes(1).ToString("HH:mm")
          )
        }
        "Every15Minutes" {
          $schtasksArgs += @(
            "/SC", "MINUTE",
            "/MO", "15",
            "/ST", (Get-Date).AddMinutes(1).ToString("HH:mm")
          )
        }
        "Every5Minutes" {
          $schtasksArgs += @(
            "/SC", "MINUTE",
            "/MO", "5",
            "/ST", (Get-Date).AddMinutes(1).ToString("HH:mm")
          )
        }
        "EveryMinute" {
          $schtasksArgs += @(
            "/SC", "MINUTE",
            "/MO", "1",
            "/ST", (Get-Date).AddMinutes(1).ToString("HH:mm")
          )
        }
        "Once" {
          # /SD is required for ONCE; without it schtasks defaults to today,
          # and if $startTime is already past the task will never fire.
          # Caller must supply $StartDate already formatted as dd/MM/yyyy (InvariantCulture).
          # Default uses InvariantCulture so / separators are used regardless of server locale.
          $sd = if ([string]::IsNullOrEmpty($StartDate)) {
            (Get-Date).ToString("dd/MM/yyyy", [System.Globalization.CultureInfo]::InvariantCulture)
          }
          else {
            $StartDate
          }
          $schtasksArgs += @(
            "/SC", "ONCE",
            "/SD", $sd,
            "/ST", $startTime
          )
        }
      }
      # Add run level
      if ($RunLevel -eq "Highest") {
        if (Test-AzureVirtualDesktopSessionHost) {
          Write-LogMessage "AVD session host detected - skipping /RL HIGHEST and using default LIMITED run level" -Level INFO
        }
        else {
          $schtasksArgs += "/RL", "HIGHEST"
        }
      }
      # # /et <endtime> Specifies the time of day that a minute or hourly task schedule ends in <HH:MM> 24-hour format. 
      # # After the specified end time, schtasks does not start the task again until the start time recurs. 
      # # By default, task schedules have no end time. This parameter is optional and valid only with a MINUTE or HOURLY schedule.
      # # Add until timestamp if RunFrequency is Daily
      # if ($RunFrequency -eq "Daily" -and -not ([string]::IsNullOrEmpty($EndTimeHour) -and [string]::IsNullOrEmpty($EndTimeMinute))) {
      #   # Add end time parameter - see https://docs.microsoft.com/en-us/windows-server/administration/windows-commands/schtasks-create
      #   # Add end time parameter using null-coalescing operator to default to 23:00 if EndTimeHour/EndTimeMinute are null
      #   $schtasksArgs += "/ET", "$($EndTimeHour.ToString('00')??'23'):$($EndTimeMinute.ToString('00')??'00')"
      # }

      # Add RunAsUser setting
      # if ($RunAsUser) {
      $credentials = Get-ScheduledTaskCredentials -RunAsUser $RunAsUser
      $schtasksArgs += $credentials
      
      # If we're using credentials, ensure the user has batch logon rights
      # if ($credentials.Count -ge 2) {
      #   $username = "$env:USERDOMAIN\$env:USERNAME"
      #   Write-LogMessage "Ensuring user $username has 'Log on as batch job' rights..." -Level INFO
      #   Grant-BatchLogonRight -Username $username
      # }
      # }

    }

    $resultSuccess = $true
    $output = Invoke-SchedTaskCommand -Command $($schtasksArgs -join " ") -Context "create scheduled task" -IgnoreError $false
    # Check for errors
    if ($output -like "*invalid*" -or
      $output -like "*incorrect*" -or
      $output -like "*denied*") {
      Write-LogMessage "Scheduled task $TaskName creation failed due to invalid stored credentials. Password removed from environment variables." -Level ERROR
      $resultSuccess = $false
      Remove-UserPasswordAsSecureString
    }
    elseif ($output -like "*success*") {
      Write-LogMessage "Scheduled task $TaskName created successfully" -Level INFO
      $resultSuccess = $true
    }
    else {
      Write-LogMessage "Scheduled task $TaskName creation failed" -Level ERROR
      $resultSuccess = $false
    }

    # $tempFile = [System.IO.Path]::GetTempFileName()
    # # Write and execute command
    # $schtaskExePath = Get-CommandPathWithFallback -Name "schtasks"
    # $schtasksCommand = "$schtaskExePath " + ($schtasksArgs -join " ") + " > $tempFile 2>&1"
    # Invoke-Expression $schtasksCommand
    # #Write-Host "Command: $schtasksCommand"
    # $output = Get-Content $tempFile
    # Remove-Item $tempFile
    # Write-LogMessage "Output: $output" -Level INFO
    # if ($output -notlike "*successfully*") {
    #   Write-LogMessage "Task '$TaskName' creation failed." -Level ERROR
    #   throw 
    # }
    # else {
    #   Write-LogMessage "Task '$TaskName' created successfully." -Level INFO
    # }    
    if ($RunAtOnce -and $resultSuccess) {
      Write-LogMessage "Auto start scheduled task $TaskName after creation" -Level INFO
      Start-ScheduledTask -TaskName $TaskName
    }
    
  }
  catch {
    Write-LogMessage "Failed to create scheduled task" -Level ERROR -Exception $_
    # if ($output -like "*invalid*" -or
    #   $output -like "*incorrect*" -or
    #   $output -like "*denied*") {
    #   Remove-UserPasswordAsSecureString
    # }
    
    throw
  }
}


<#
.SYNOPSIS
    Updates credentials for a single scheduled task.

.DESCRIPTION
    Updates the username and password for a scheduled task. Can also configure
    whether the task runs only when the user is logged on or runs regardless
    of user logon status.

.PARAMETER TaskName
    The name of the scheduled task to update.

.PARAMETER TaskFolder
    The folder path of the scheduled task (optional).

.PARAMETER RunWhetherLoggedOnOrNot
    When specified, configures the task to run whether the user is logged on or not.
    This stores the password and allows background execution.
    Without this switch, the task runs only when the user is logged on (interactive mode).

.EXAMPLE
    Update-SingleTaskScheduledTaskCredentials -TaskName "MyTask" -RunWhetherLoggedOnOrNot
    # Updates credentials and configures task to run in background

.EXAMPLE
    Update-SingleTaskScheduledTaskCredentials -TaskName "MyTask" -TaskFolder "DevTools"
    # Updates credentials for interactive-only execution
#>
function Update-SingleTaskScheduledTaskCredentials {
  param (
    [Parameter(Mandatory = $true)]
    [string]$TaskName,
    [Parameter(Mandatory = $false)]
    [string]$TaskFolder = "",
    [Parameter(Mandatory = $false)]
    [switch]$RunWhetherLoggedOnOrNot
  )

 
  $TaskName = Set-TaskName $TaskName $TaskFolder

  $schtasksArgs = @("/change", "/tn", "`"$TaskName`"")
    

  # If NOT running whether logged on or not, add /IT flag for interactive-only mode
  # When /RU and /RP are provided WITHOUT /IT, task runs whether logged on or not
  # When /IT is added, task runs only when user is logged on (interactive)
  if (-not $RunWhetherLoggedOnOrNot) {
    $schtasksArgs += "/IT"
    $credentials = Get-ScheduledTaskCredentials -RunAsUser $false
    $schtasksArgs += $credentials
    Write-LogMessage "Configuring task '$TaskName' to run only when user is logged on (interactive mode)" -Level INFO
  }
  else {
    $credentials = Get-ScheduledTaskCredentials -RunAsUser $true
    $schtasksArgs += $credentials
    Write-LogMessage "Configuring task '$TaskName' to run whether user is logged on or not (background mode)" -Level INFO
  }

  $result = Invoke-SchedTaskCommand -Command $($schtasksArgs -join " ") -Context "update scheduled task credentials" -IgnoreError $false
  if ($result -like "*invalid*" -or
    $result -like "*incorrect*" -or
    $result -like "*denied*") {
    Write-LogMessage "Scheduled task $TaskName update failed due to invalid stored credentials. Password removed from environment variables." -Level ERROR
    Remove-UserPasswordAsSecureString
    Get-ProcessedScheduledCommands
  }
  else {
    Write-LogMessage "Scheduled task $TaskName updated successfully" -Level INFO
  }
}


function Add-DefaultScheduledTasksServer {  
}

function Add-SelectedScheduledTasks {
  param (
    [Parameter(Mandatory = $false)]
    [string]$TaskName,

    [Parameter(Mandatory = $false)]
    [string]$TaskFolder = "DevTools"
  )

  
  if ($TaskName) {
    $existingTasks = Get-ExistingScheduledTasks -TaskName $TaskName -TaskFolder $TaskFolder
    if ($existingTasks.Count -eq 1) {
      Write-LogMessage "Scheduled task $TaskName already exists" -Level INFO
      return $true
    }
    else {
      $appFolder = Join-Path $env:OptPath "DedgePshApps\$TaskName"
      $appInstallScript = Join-Path $appFolder "_install.ps1"
      Write-LogMessage "Install script: $appInstallScript" -Level INFO
      if (Test-Path $appInstallScript -PathType Leaf) {
        Invoke-Expression $appInstallScript
        Write-LogMessage "Scheduled task $TaskName created" -Level INFO
        return $true
      }
      else {
        Write-LogMessage "Scheduled task $TaskName not found" -Level ERROR
        return $false
      }
    }
  }

  $existingTasks = Get-ExistingScheduledTasks

  $appsPath = Join-Path $env:OptPath "DedgePshApps"
  $apps = Get-ChildItem -Path $appsPath
  $appObjects = @()
  foreach ($app in $apps) {
    # Check if only one ps1 file in the folder
    $ps1Files = Get-ChildItem -Path $app.FullName -Filter "_install.ps1"
    if ($ps1Files.Count -eq 1) {

      # check if _install.ps1 contains text New-ScheduledTask
      $installScript = Get-Content -Path $ps1Files[0].FullName
      $joinedLower = ($installScript -join " ").ToLower()
      if (-not $joinedLower.Contains("new-ScheduledTask")) {
        continue
      }
      if ( $existingTasks.TaskName -contains $app.Name) {
        $exists = $true
      }
      else {
        $exists = $false
      }

      $appObjects += [PSCustomObject]@{
        Name       = $app.Name
        Type       = "Scheduled Tasks"
        Exists     = $exists
        Executable = $ps1Files[0].FullName
      }
    }
  }

 
  Add-Type -AssemblyName System.Windows.Forms
  Add-Type -AssemblyName System.Drawing

  $form = New-Object System.Windows.Forms.Form
  $form.Text = 'Select Scheduled Tasks to Add or Remove'
  $form.Size = New-Object System.Drawing.Size(1024, 720)
  $form.StartPosition = 'CenterScreen'

  $okButton = New-Object System.Windows.Forms.Button
  $okButton.Location = New-Object System.Drawing.Point(175, 620)
  $okButton.Size = New-Object System.Drawing.Size(75, 23)
  $okButton.Text = 'OK'
  $okButton.DialogResult = [System.Windows.Forms.DialogResult]::OK
  $form.AcceptButton = $okButton
  $form.Controls.Add($okButton)

  $cancelButton = New-Object System.Windows.Forms.Button
  $cancelButton.Location = New-Object System.Drawing.Point(250, 620)
  $cancelButton.Size = New-Object System.Drawing.Size(75, 23)
  $cancelButton.Text = 'Cancel'
  $cancelButton.DialogResult = [System.Windows.Forms.DialogResult]::Cancel
  $form.CancelButton = $cancelButton
  $form.Controls.Add($cancelButton)

  $label = New-Object System.Windows.Forms.Label
  $label.Location = New-Object System.Drawing.Point(10, 20)
  $label.Size = New-Object System.Drawing.Size(280, 20)
  $label.Text = 'Please select scheduled tasks to add or remove:'
  $form.Controls.Add($label)

  # Create ListView instead of CheckedListBox
  $listView = New-Object System.Windows.Forms.ListView
  $listView.Location = New-Object System.Drawing.Point(10, 40)
  $listView.Size = New-Object System.Drawing.Size(1004, 550)
  $listView.View = [System.Windows.Forms.View]::Details
  $listView.CheckBoxes = $true
  $listView.FullRowSelect = $true

  # Add columns
  $listView.Columns.Add("App", 280) | Out-Null
  $listView.Columns.Add("Type", 100) | Out-Null
  $listView.Columns.Add("Exists", 100) | Out-Null
  $listView.Columns.Add("Executable", 360) | Out-Null

  # Add items
  foreach ($app in $appObjects) {
    $item = New-Object System.Windows.Forms.ListViewItem($app.Name)
    $item.SubItems.Add($app.Type) | Out-Null
    $item.SubItems.Add($app.Exists.ToString()) | Out-Null
    if ($app.Exists) {
      $item.Checked = $true
      $item.BackColor = [System.Drawing.SystemColors]::Control
      $item.ForeColor = [System.Drawing.SystemColors]::GrayText
      $item.Tag = "Exists"
    }
    else {
      $item.Tag = "DoesNotExist"
    }
    $item.SubItems.Add($app.Executable) | Out-Null
    $listView.Items.Add($item) | Out-Null
  }

  $form.Controls.Add($listView)
  $form.Topmost = $true

  $result = $form.ShowDialog()

  if ($result -eq [System.Windows.Forms.DialogResult]::OK) {
    $selectedApps = $listView.CheckedItems
    

    foreach ($app2 in $selectedApps) {
      if ($($app2.Tag) -ne "Exists") {
        Write-LogMessage "Adding scheduled task for $($app2.SubItems[0].Text) daily at 2:00 AM" -Level INFO
        New-ScheduledTask -TaskName $app2.SubItems[0].Text -Executable $app2.SubItems[3].Text -RunFrequency "Daily" -StartHour 2
      }
    }
    $selectedApps = $listView.Items | Where-Object { -not $_.Checked }
    foreach ($app2 in $selectedApps) {
      if ($($app2.Tag) -eq "Exists") {
        Write-LogMessage "Removing scheduled task for $($app2.SubItems[0].Text)" -Level INFO
        $addedApp = $existingTasks | Where-Object { $_.TaskName -like "*$($app2.SubItems[0].Text)*" }
        foreach ($app3 in $addedApp) {
          Remove-ScheduledTask -TaskName $app3.TaskName -TaskFolder $app3.TaskFolder
        }
      }
    }
  }
  return $foundTask
  # Console report of installed apps and types
  Write-LogMessage "Added scheduled tasks:" -Level INFO
  foreach ($app in $selectedApps) {
    Write-LogMessage "$($app.Text) - $($app.SubItems[1].Text)" -Level INFO
  }
}


function Get-CommonTaskParams {
  param (
    [Parameter(Mandatory = $true)]
    [string]$SourceFolder,
    [Parameter(Mandatory = $false)]
    [string]$ExecutableName,
    [Parameter(Mandatory = $false)]
    [string]$TaskName,
    [Parameter(Mandatory = $false)]
    [string]$TaskFolder,
    [Parameter(Mandatory = $false)]
    [bool]$SkipExecutableCheck = $false
  )
  $applicationTechnologyFolderName = Get-ApplicationTechnologyFolderName -SourceFolder $SourceFolder
  $appName = $(Split-Path -Path $SourceFolder -Leaf).ToString().Trim()

  $executablePath = $null
  if ([string]::IsNullOrEmpty($ExecutableName)) {
    $executablePath = "$env:OptPath\$applicationTechnologyFolderName\$appName\$appName.ps1"
  }
  else {
    $executablePath = "$env:OptPath\$applicationTechnologyFolderName\$appName\$ExecutableName"
  }
  if (-not [string]::IsNullOrEmpty($TaskName)) {
    $appName = $TaskName
  }
  if (-not [string]::IsNullOrEmpty($TaskFolder)) {
    $taskName = $TaskFolder + "\" + $appName
  }

  if (-not (Test-Path $executablePath -PathType Leaf) -and -not $SkipExecutableCheck) {
    #Find first ps1,exe,bat,cmd file in the folder in that order    
    $files = Get-ChildItem -Path $SourceFolder -Filter "*.ps1" -File
    if ($files.Count -eq 1) {
      $executablePath = $files[0].FullName
    }
    
    if ([string]::IsNullOrEmpty($executablePath)) {
      $files = Get-ChildItem -Path $SourceFolder -Filter "*.exe" -File
      if ($files.Count -eq 1) {
        $executablePath = $files[0].FullName
      }
    }

    if ([string]::IsNullOrEmpty($executablePath)) {
      $files = Get-ChildItem -Path $SourceFolder -Filter "*.bat" -File
      if ($files.Count -eq 1) {
        $executablePath = $files[0].FullName
      }
    }
    
    if ([string]::IsNullOrEmpty($executablePath)) {
      $files = Get-ChildItem -Path $SourceFolder -Filter "*.cmd" -File
      if ($files.Count -eq 1) {
        $executablePath = $files[0].FullName
      }
    }

    if ([string]::IsNullOrEmpty($executablePath)) {
      if ([string]::IsNullOrEmpty($ExecutableName)) {
        throw "Executable not found in $SourceFolder"
      }
      else {
        throw "Executable $ExecutableName not found in $SourceFolder"
      }
    }
  }
  
  return [PSCustomObject]@{
    ExecutablePath = $executablePath
    OnlyTaskName   = $appName
    OnlyTaskFolder = $TaskFolder
    TaskName       = $taskName
  }
}

function Get-ProcessedScheduledCommands {
  param (
    [Parameter(Mandatory = $false)]
    [ValidateSet("Get", "Format-List", "Format-Table")]
    [string]$Format = "Get",
    [Parameter(Mandatory = $false)]
    [string[]]$Properties = @("Command", "Output", "Context"),
    [Parameter(Mandatory = $false)]
    [bool]$Clear = $false,
    [Parameter(Mandatory = $false)]
    [bool]$SkipQuery = $true,
    [Parameter(Mandatory = $false)]
    [bool]$RemovePasswordFromOutput = $true
  )
  $validList = @("Context", "Command", "Output", "Username", "ComputerName", "Date")
  
  # Check if Properties is an array
  [string[]]$validProperties = @()
  $invalidPropertiesFound = $false
  foreach ($property in $Properties) {
    if ($validList -contains $property) {
      $validProperties += $property
    }
    else {
      $invalidPropertiesFound = $true
    }
  }
  # Notify user if invalid properties are found
  if ($invalidPropertiesFound) {
    Write-LogMessage "Auto-removed invalid properties from Properties parameter. Valid list of properties is: $($validList -join ", ")" -Level WARN
  }
  # If SkipQuery is true, skip the query
  if (-not $SkipQuery) {   
    $tempSchTaskCommands = $global:SchTaskCommands
  }
  else {
    $tempSchTaskCommands = $global:SchTaskCommands | Where-Object { -not $_.Command.ToLower().Contains("/query") }
  }
  # If RemovePasswordFromOutput is true, remove the password from the output
  if ($RemovePasswordFromOutput) {
    
    # Remove sensitive password information from command strings for security
    # This replaces password values in /RP (RunPassword) and /P (Password) parameters
    # with asterisks to prevent credential exposure in logs or output
    $tempSchTaskCommands = $tempSchTaskCommands | ForEach-Object { 
      # Replace /RP "password" with /RP "*********" (RunPassword parameter)
      $_.Command = $_.Command -replace "/RP `".*?`"", "/RP `"*********`""
      # Replace /P "password" with /P "*********" (Password parameter)
      $_.Command = $_.Command -replace "/P `".*?`"", "/P `"*********`""
      # Return the modified object
      $_
    }
  }

  $tempSchTaskCommands | Format-List -Property $($validProperties -join ", ")
  if ($Format -eq "Format-List") {
    $command = "`$tempSchTaskCommands | Format-List -Property $($($validProperties -join ", "))"
    Invoke-Expression $command
  }
  elseif ($Format -eq "Format-Table") {
    $command = "`$tempSchTaskCommands | Format-Table -Property $($Properties -join ", ") -AutoSize"
    Invoke-Expression $command
  }
  else {
    return $global:SchTaskCommands
  }  
  if ($Clear) {
    $global:SchTaskCommands = @()
  }
}

Export-ModuleMember -Function *
