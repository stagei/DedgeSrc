Import-Module ScheduledTask-Handler -Force

if (Test-IsDb2Server) {
    New-ScheduledTask -SourceFolder $PSScriptRoot -TaskFolder "DevTools" -RecreateTask $true -RunFrequency "Daily" -StartHour 0 -StartMinute 01 -RunAsUser $true -RunAtOnce $true
}

