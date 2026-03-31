Import-Module ScheduledTask-Handler -Force
Import-Module Infrastructure -Force

if ($env:COMPUTERNAME.ToLower().Trim() -eq "dedge-server") {
    New-ScheduledTask -SourceFolder $PSScriptRoot -TaskFolder "DevTools" -RecreateTask $true -RunFrequency "Daily" -StartHour 2 -StartMinute 10 -RunAsUser $false
}
