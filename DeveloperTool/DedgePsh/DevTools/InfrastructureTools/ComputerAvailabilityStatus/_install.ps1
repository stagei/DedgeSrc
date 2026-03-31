Import-Module ScheduledTask-Handler -Force

if ($env:COMPUTERNAME.ToLower().Trim() -eq "dedge-server") {
    New-ScheduledTask -SourceFolder $PSScriptRoot -TaskFolder "DevTools" -RecreateTask $true -RunFrequency "Daily" -StartHour 5 -StartMinute 00 -RunAsUser $true
}

