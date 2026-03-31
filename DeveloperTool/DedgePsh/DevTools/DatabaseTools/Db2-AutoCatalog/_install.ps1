Import-Module ScheduledTask-Handler -Force
if (-not $env:COMPUTERNAME.EndsWith("-db") -and -not $env:COMPUTERNAME.EndsWith( "-db01") -and -not $env:COMPUTERNAME.EndsWith( "-db02")) {
    New-ScheduledTask -SourceFolder $PSScriptRoot -TaskFolder "DevTools" -RecreateTask $true -RunFrequency "Daily" -StartHour 2 -RunAsUser $true -RunAtOnce $true
}
else {
    Write-Host "This is a database server, skipping task creation"
}

