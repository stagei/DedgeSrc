Import-Module ScheduledTask-Handler -Force
Remove-ScheduledTask -SourceFolder $PSScriptRoot -TaskFolder "DevTools"

