
Write-Host $env:PSModulePath
Import-Module ScheduledTask-Handler -Force
Import-Module GlobalFunctions -Force
Import-Module Deploy-Handler -Force

Deploy-Files -FromFolder $PSScriptRoot 

