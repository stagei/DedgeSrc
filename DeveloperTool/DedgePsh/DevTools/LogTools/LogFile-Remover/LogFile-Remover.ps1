param(
    [Parameter(Mandatory = $false)]
    [bool]$WhatIf = $false
)
Import-Module GlobalFunctions -Force

$totalLogFiles = 0
$validDrives = Find-ValidDrives -SkipSystemDrive:$true
Write-LogMessage "Found $($validDrives.Count) valid drives" -Level INFO
$instanceNameList = @()
if (Test-IsDb2Server) {
    $instanceNameList = Get-Db2InstanceNames
}
$excludePatterns = @(
    "DedgeCommon",
    "programdata",
    "program files",
    "windows",
    "users",
    "appdata",
    "temp",
    "commonlogging"
)
foreach ($drive in $validDrives) {
    $logFiles = @()

    if ($drive -eq "C") {
        $logFiles = @()
        $foldersToScan = @("opt", "tempfk")
        foreach ($folder in $foldersToScan) {
            $path = "$($drive):\$folder"
            if (Test-Path $path) {
                $logFiles += Get-ChildItem -Path $path -Include "*.log", "*.out", "*.err" -File -Recurse -ErrorAction SilentlyContinue | Where-Object {
                    $_.LastWriteTime -lt (Get-Date).AddDays(-30)
                }
            }
        }
    }
    else {
        $logFiles = Get-ChildItem -Path "$($drive):\" -Include "*.log", "*.out", "*.err" -File -Recurse -ErrorAction SilentlyContinue | Where-Object {
            $_.LastWriteTime -lt (Get-Date).AddDays(-30)
        }
    }

    if ($drive -eq "E" -and (Test-IsDb2Server)) {
        foreach ($instanceName in $instanceNameList) {
            $excludePatterns += $("e:\" + $instanceName.Trim().ToLower())
        }
    }
    foreach ($pattern in $excludePatterns) {
        $logFiles = $logFiles | Where-Object { $_ -notlike "*$pattern*" }
    }
    Write-LogMessage "Found $($logFiles.Count) log files on drive $($drive)" -Level INFO
    foreach ($logFile in $logFiles) {
        if ($WhatIf -eq $false) {
            Remove-Item -Path $logFile.FullName -Force -ErrorAction SilentlyContinue
            Write-LogMessage "Deleted log file $($logFile.FullName) with last write time $($logFile.LastWriteTime)" -Level INFO
            $totalLogFiles++
        }
        else {
            Write-LogMessage "Would delete log file $($logFile.FullName) with last write time $($logFile.LastWriteTime)" -Level INFO
            $totalLogFiles++
        }
    }
}
if ($WhatIf -eq $false) {
    Write-LogMessage "Log file removal completed. Removed $($totalLogFiles) log files" -Level INFO
    Write-LogMessage "LogFile-Remover.ps1 completed" -Level JOB_COMPLETED
}
else {
    Write-LogMessage "Log file removal simulation completed. Would have removed $($totalLogFiles) log files" -Level INFO
    Write-LogMessage "LogFile-Remover.ps1 completed" -Level JOB_COMPLETED
}

