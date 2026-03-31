Import-Module GlobalFunctions -Force

$taskFolder = "DevTools"
$scriptNames = @("Refresh-ServerSettings", "Standardize-ServerConfig", "Db2-DiagInstanceFolderShare")

foreach ($scriptName in $scriptNames) {
    # Kill all pwsh processes whose command line contains this script name
    $targets = @(Get-CimInstance Win32_Process -Filter "Name = 'pwsh.exe'" -ErrorAction SilentlyContinue |
        Where-Object { $_.CommandLine -like "*$($scriptName)*" })

    if ($targets.Count -gt 0) {
        foreach ($proc in $targets) {
            Write-LogMessage "Stopping PID $($proc.ProcessId): $($proc.CommandLine)" -Level WARN
            Stop-Process -Id $proc.ProcessId -Force -ErrorAction SilentlyContinue
        }
        Write-LogMessage "Killed $($targets.Count) pwsh process(es) running $($scriptName)" -Level INFO
    } else {
        Write-LogMessage "No running pwsh processes found for $($scriptName)" -Level INFO
    }

    # Disable the scheduled task
    $taskPath = "\$($taskFolder)\"
    $task = Get-ScheduledTask -TaskPath $taskPath -TaskName $scriptName -ErrorAction SilentlyContinue
    if ($task) {
        Stop-ScheduledTask  -TaskPath $taskPath -TaskName $scriptName -ErrorAction SilentlyContinue
        if ($task.TaskName -ne "Refresh-ServerSettings") {
            Disable-ScheduledTask -TaskPath $taskPath -TaskName $scriptName -ErrorAction Stop | Out-Null
        }
        Write-LogMessage "Scheduled task '\$($taskFolder)\$($scriptName)' stopped and disabled" -Level INFO
    } else {
        Write-LogMessage "Scheduled task '\$($taskFolder)\$($scriptName)' not found on this machine" -Level WARN
    }
}


Install-OurPshApp -AppName "Refresh-ServerSettings"
Install-OurPshApp -AppName "Standardize-ServerConfig"

Install-OurPshApp -AppName "Cursor-ServerOrchestrator"
Start-OurPshApp -AppName "Cursor-ServerOrchestrator"


# List all pwsh.exe processes still running
$remaining = @(Get-CimInstance Win32_Process -Filter "Name = 'pwsh.exe'" -ErrorAction SilentlyContinue)
Write-LogMessage "Remaining pwsh.exe processes ($($remaining.Count) total):" -Level INFO
foreach ($proc in $remaining) {
    Write-LogMessage "  PID $($proc.ProcessId): $($proc.CommandLine)" -Level INFO
}
Read-Host "Press Enter to continue"
exit