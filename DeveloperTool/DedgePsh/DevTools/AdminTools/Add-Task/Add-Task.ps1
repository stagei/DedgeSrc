
param (
    [Parameter(Mandatory = $false)]
    [string]$Command = ""
)

Import-Module ScheduledTask-Handler -Force
Import-Module Infrastructure -Force
Import-Module Deploy-Handler -Force
$foundTask = $false
if ($Command -eq "") {
    Add-SelectedScheduledTasks
    $foundTask = $true
}
elseif ($Command -ne "") {
    if ($Command.Contains("\") -and $Command.StartsWith("\")) {
        $Command = $Command.Substring(1)
    }
    $splitTaskName = $Command.Split("\")
    $newTaskName = $splitTaskName[-1] ?? ""
    $newTaskFolder = $splitTaskName[-2] ?? ""
    $executable = Install-OurPshApp -AppName $newTaskName -ReturnExecutablePath $true

    if (-not (Test-Path $executable -PathType Leaf)) {
        Write-Host "Task not found"
        exit
    }

    $foundTask = Add-SelectedScheduledTasks -TaskName $newTaskName -TaskFolder $newTaskFolder
    if (-not $foundTask) {
        Write-Host "Task not found"
    }
}

if ($Command -eq "--help" -or $Command -eq "-h" -or $Command -eq "/?" -or -not $foundTask) {
    Write-Host ""
    Write-Host ("-" * 75)
    Write-Host "Usage: Add-Task [TaskName]"
    Write-Host ""
    Write-Host "Options:"
    Write-Host "  TaskName         The name of the task to add"
    Write-Host "  -h, --help, /?   Show this help message"
    Write-Host "Example:"
    Write-Host "  Add-Task TaskName  # Adds a task"
    Write-Host '  Add-Task "TaskFolder\TaskName"  # Adds a task to a specific folder'
    Write-Host ("-" * 75)
    exit
}

