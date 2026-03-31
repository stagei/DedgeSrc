Import-Module ScheduledTask-Handler -Force
Import-Module Infrastructure -Force
Import-Module SoftwareUtils -Force

Install-WindowsApps -AppName "PostgreSQL.18.Client"


# if ($env:COMPUTERNAME.ToLower() -eq "dedge-server" -or $env:COMPUTERNAME.ToLower() -eq "p-no1fkxprd-app") {
#     New-ScheduledTask -SourceFolder $PSScriptRoot\IIS-RedeployAll.ps1 -TaskFolder "DevTools" -RecreateTask $true -RunFrequency "Daily" -StartHour 0 -StartMinute 01 -RunAsUser $true 
# }

