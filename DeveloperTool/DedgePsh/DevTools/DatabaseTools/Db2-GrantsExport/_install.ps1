Import-Module ScheduledTask-Handler -Force
Import-Module GlobalFunctions -Force

if (Test-IsDb2Server) {
    New-ScheduledTask -SourceFolder $PSScriptRoot -Executable "Db2-GrantsExport.ps1" -TaskFolder "DevTools" -RecreateTask $true -RunFrequency "Weekly" -DayOfWeek "SUN" -StartHour 5 -StartMinute 0 -RunAsUser $true
}
