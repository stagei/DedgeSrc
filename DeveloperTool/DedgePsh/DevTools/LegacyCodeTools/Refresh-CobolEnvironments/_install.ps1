Import-Module ScheduledTask-Handler -Force

if ($env:COMPUTERNAME.ToLower().EndsWith("-app")) {
    New-ScheduledTask -SourceFolder $PSScriptRoot -TaskFolder "DevTools" -RecreateTask $true -RunFrequency "Daily" -StartHour 4 -RunAsUser $true
}

