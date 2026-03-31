Import-Module ScheduledTask-Handler -Force
Import-Module GlobalFunctions -Force

if (-not (Test-IsDb2Server)) {
    Write-LogMessage "Not a Db2 server, skipping Db2-DiagArchive installation" -Level INFO
    exit 0
}

New-ScheduledTask -SourceFolder $PSScriptRoot -TaskFolder "DevTools" -RecreateTask $true -RunFrequency Daily -StartHour 5 -StartMinute 30 -RunAsUser $true

