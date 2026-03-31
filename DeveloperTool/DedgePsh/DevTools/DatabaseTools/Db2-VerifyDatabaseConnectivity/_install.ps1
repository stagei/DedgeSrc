Import-Module ScheduledTask-Handler -Force
Import-Module Infrastructure -Force

if ((Test-IsServer) -and $env:COMPUTERNAME.ToLower().EndsWith("-app")) {
    New-ScheduledTask -SourceFolder $PSScriptRoot -TaskFolder "DevTools" -RecreateTask $true -RunFrequency "Every15Minutes" -StartHour 0 -StartMinute 01 -RunAsUser $true -RunAtOnce $true
}
elseif (-not (Test-IsServer) -and $env:USERNAME.ToLower() -eq "FKGEISTA") {
    New-ScheduledTask -SourceFolder $PSScriptRoot -TaskFolder "DevTools" -RecreateTask $true -RunFrequency "Daily" -StartHour 07 -StartMinute 00 -RunAsUser $true -RunAtOnce $true
}
