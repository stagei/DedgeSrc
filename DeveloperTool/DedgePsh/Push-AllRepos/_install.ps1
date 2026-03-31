Import-Module ScheduledTask-Handler -Force
Import-Module GlobalFunctions -Force

if (Test-IsServer) {
    Write-LogMessage "Only for local machines, skipping installation on server" -Level INFO
    exit 0
}

New-ScheduledTask -SourceFolder $PSScriptRoot -TaskFolder "DevTools" -RecreateTask $true -RunFrequency "Daily" -StartHour 23 -StartMinute 50 -RunAsUser $true -RunAtOnce $true

