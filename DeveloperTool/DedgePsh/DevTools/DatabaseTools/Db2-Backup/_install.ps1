Import-Module ScheduledTask-Handler -Force
Import-Module GlobalFunctions -Force

if (-not (Test-IsServer)) {
    Write-LogMessage "Not a server, skipping Db2-Backup installation" -Level INFO
    exit 0
}

if ($(Get-EnvironmentFromServerName) -eq "PRD") {
    New-ScheduledTask -SourceFolder $PSScriptRoot -TaskFolder "DevTools" -RecreateTask $true -RunFrequency "Daily" -StartHour 0 -StartMinute 15 -RunAsUser $true
}
elseif ($(Get-EnvironmentFromServerName) -ne "RAP") {
    New-ScheduledTask -SourceFolder $PSScriptRoot -TaskFolder "DevTools" -RecreateTask $true -RunFrequency "Weekly" -StartHour 1 -StartMinute 15 -RunAsUser $true
}

