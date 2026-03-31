Import-Module ScheduledTask-Handler -Force
Import-Module GlobalFunctions -Force

if (-not (Test-IsServer)) {
    Write-LogMessage "Not a server, skipping Db2-Backup installation" -Level INFO
    exit 0
}

if ($(Get-EnvironmentFromServerName) -eq "RAP") {
    New-ScheduledTask -SourceFolder $PSScriptRoot -TaskFolder "DevTools" -RecreateTask $true -RunFrequency "Daily" -StartHour 1 -RunAsUser $true
}

