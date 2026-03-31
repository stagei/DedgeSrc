Import-Module ScheduledTask-Handler -Force
Import-Module Infrastructure -Force

if (Test-IsServer) {
    New-ScheduledTask -SourceFolder $PSScriptRoot -Executable "AutoDocJson.exe" -Arguments "--regenerate Incremental --skipexisting" -TaskFolder "DevTools" -RecreateTask $true -RunFrequency "Every3Hours" -StartHour 0 -StartMinute 01 -RunAsUser $false
}
