Import-Module ScheduledTask-Handler -Force

if ($env:COMPUTERNAME.ToLower().Trim() -eq "dedge-server") {
    New-ScheduledTask -SourceFolder $PSScriptRoot -TaskFolder "DevTools" -RecreateTask $true -RunFrequency "Every30Minutes" -StartHour 6 -RunAsUser $true
}

