# given a folder, organize files into subfolders by date, excluding todays files
param(
    [string]$folder = "C:\Users\user\Downloads"
)

# function for logging messages to the logfile .\log\OrganizeFiles.log
function LogMessage {
    param(
        [string]$message
    )
    $logFile = ".\log\OrganizeFiles.log"
    $date = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    $message = "$date - $message"
    Write-Host $message
    Add-Content -Path $logFile -Value $message
}

# create log folder if not exists
$logFolder = ".\log"
if (-not (Test-Path -Path $logFolder)) {
    New-Item -Path $logFolder -ItemType Directory
}

# log start message
LogMessage "Starting OrganizeFiles.ps1 script"

#if current time between 5am and 22pm, exit
# LogMessage "Checking if current time is between 5am and 22pm to exit if true"
# $now = Get-Date
# $start = Get-Date -Hour 5 -Minute 0 -Second 0
# $end = Get-Date -Hour 21 -Minute 0 -Second 0
# if ($now -gt $start -and $now -lt $end) {
#     LogMessage "Current time is between 5am and 22pm, exiting"
#     exit
# }
# LogMessage "Current time is not between 5am and 22pm, continuing"

LogMessage "Searching for files older than 1 days in $folder"
$today = Get-Date -Format yyyy-MM-dd
$files = Get-ChildItem -Path $folder -File

LogMessage "Filtering for files older than 1 days"
$filesOlderThan1Days = $files | Where-Object { $_.LastWriteTime -lt (Get-Date).AddDays(-1) }

# log number of files found that is older than 30 days
LogMessage "Found $($filesOlderThan1Days.Count) files older than 1 days"

foreach ($file in $filesOlderThan1Days) {

    # check if current time is between 22pm and 5am and exit if not true
    # $now = Get-Date
    # $start = Get-Date -Hour 21 -Minute 0 -Second 0
    # $end = Get-Date -Hour 5 -Minute 0 -Second 0
    # if ($now -lt $start -and $now -gt $end) {
    #     LogMessage "Current time is not between 22pm and 5am, exiting"
    #     exit
    # }

    $date = $file.LastWriteTime.ToString("yyyy-MM-dd")
    if ($date -ne $today) {
        $newFolder = Join-Path -Path $folder -ChildPath $date
        if (-not (Test-Path -Path $newFolder)) {
            LogMessage "Creating folder $newFolder"
            New-Item -Path $newFolder -ItemType Directory
        }
        Move-Item -Path $file.FullName -Destination $newFolder
    }
}

LogMessage "Files organized into subfolders by date, excluding todays files"

