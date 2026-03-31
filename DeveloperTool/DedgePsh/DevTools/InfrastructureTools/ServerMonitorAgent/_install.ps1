Import-Module ScheduledTask-Handler -Force
Import-Module Infrastructure -Force

if (Test-IsServer) {
    New-ScheduledTask -SourceFolder $PSScriptRoot -TaskFolder "DevTools" -RecreateTask $true -RunFrequency "Daily" -StartHour 0 -StartMinute 01 -RunAsUser $false
}
