Import-Module ScheduledTask-Handler -Force
Import-Module Infrastructure -Force

if (Test-IsServer) {
    New-ScheduledTask -SourceFolder $PSScriptRoot -TaskFolder "DevTools" -RecreateTask $true -RunFrequency "Weekly" -DayOfWeek "SUN" -StartHour 18 -RunAsUser $true
}

