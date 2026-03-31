Import-Module ScheduledTask-Handler -Force

if (Test-IsDb2Server) {
    New-ScheduledTask -SourceFolder $PSScriptRoot -TaskFolder "DevTools" -RecreateTask $true -RunFrequency "Hourly" -StartHour 1 -StartMinute 00 -RunAsUser $true -RunAtOnce $true
}

