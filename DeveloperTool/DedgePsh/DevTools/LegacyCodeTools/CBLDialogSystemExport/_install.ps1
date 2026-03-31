Import-Module ScheduledTask-Handler -Force

if ($env:COMPUTERNAME.ToLower().Trim() -eq "dedge-server") {
    New-ScheduledTask -SourceFolder $PSScriptRoot -TaskFolder "DevTools" -RecreateTask $true -RunFrequency "Daily" -StartHour 21 -RunAsUser $true
}

