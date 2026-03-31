Import-Module ScheduledTask-Handler -Force
Import-Module Infrastructure -Force

if ($(Test-IsServer) -and $env:COMPUTERNAME.ToLower().Contains("fkxprd")) {
    New-ScheduledTask -SourceFolder $PSScriptRoot -TaskFolder "DevTools" -RecreateTask $true -RunFrequency Hourly -StartHour 0 -StartMinute 10 -RunAsUser $true -RunAtOnce $true
}

