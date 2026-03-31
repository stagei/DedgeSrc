Import-Module GlobalFunctions -Force
# Process each server folder
try {
    $jsonFileName = "$env:OptPath\src\DedgePsh\DevTools\AdminTools\ScheduledTasks-ConvertXmlFiles\commandargumentslist.json"
    $jsonContent = Get-Content -Path $jsonFileName -Raw | ConvertFrom-Json

    # {
    #     "TaskName": "FixJob",
    #     "ToServer": "p-no1fkmprd-app",
    #     "ToCommand": "C:\\opt\\DedgeWinApps\\FixJob\\FixJob.exe",
    #     "ToArguments": "",
    #     "FromServer": "p-no1batch-vm01",
    #     "FromCommand": "E:\\opt\\apps\\FixJob\\FixJob.exe",
    #     "FromArguments": ""
    #   },

    $vscodePath = "$env:USERPROFILE\AppData\Local\Programs\Microsoft VS Code\Code.exe"

    $searchSourceRepositoryPath = "$env:OptPath\src\DedgePsh"
    $searchLoevel =2

    foreach ($item in $jsonContent) {
        Write-Host "TaskName: $($item.TaskName)"
        Write-Host "ToServer: $($item.ToServer)"
        Write-Host "ToCommand: $($item.ToCommand)"
        Write-Host "ToArguments: $($item.ToArguments)"
        Write-Host "FromServer: $($item.FromServer)"
        Write-Host "FromCommand: $($item.FromCommand)"
        Write-Host "FromArguments: $($item.FromArguments)"
        Write-Host "---"
    }

}
catch {
    <#Do this if a terminating exception happens#>
}

