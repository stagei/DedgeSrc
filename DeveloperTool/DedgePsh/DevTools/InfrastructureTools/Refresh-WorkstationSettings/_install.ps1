Import-Module ScheduledTask-Handler -Force
Import-Module Infrastructure -Force

if (-not (Test-IsServer)) {
    New-ScheduledTask -SourceFolder $PSScriptRoot -TaskFolder "DevTools" -RecreateTask $true -RunFrequency "Daily" -StartHour 9 -RunAsUser $true
}

