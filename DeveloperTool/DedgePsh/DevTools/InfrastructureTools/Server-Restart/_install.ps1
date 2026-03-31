Import-Module ScheduledTask-Handler -Force
Import-Module Infrastructure -Force

if ($(Test-IsDb2Server) -and ($(Get-EnvironmentFromServerName) -eq "RAP" -or $(Get-EnvironmentFromServerName) -eq "PRD")) {
    New-ScheduledTask -SourceFolder $PSScriptRoot -TaskFolder "DevTools" -RecreateTask $true -RunFrequency "Weekly" -DayOfWeek "SUN" -StartHour 07 -StartMinute 00 -RunAsUser $true
}
