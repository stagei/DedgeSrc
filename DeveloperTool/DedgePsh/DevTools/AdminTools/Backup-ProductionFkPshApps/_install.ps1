Import-Module ScheduledTask-Handler -Force
Import-Module Infrastructure -Force

if ($(Test-IsServer) -and ($env:COMPUTERNAME.ToLower().Contains("prd") -or $env:COMPUTERNAME.ToLower().Contains("rap"))) {
    New-ScheduledTask -SourceFolder $PSScriptRoot -TaskFolder "DevTools" -RecreateTask $true -RunFrequency "Daily" -StartHour 0 -StartMinute 10 -RunAsUser $true -RunAtOnce $true
}

