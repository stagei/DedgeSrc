Import-Module GlobalFunctions -Force
Import-Module Agent-Handler -Force
#$computerNameList = Get-ValidServerNameList
$computerNameList = @("*fkxtst-app")
$null = Deploy-AgentTask -TaskName "ServerMonitorAgent" -SourceScript "$env:OptPath\src\DedgePsh\DevTools\InfrastructureTools\ServerMonitorAgent\ServerMonitorAgent.ps1" -ComputerNameList $computerNameList  -WaitForJsonFile $true

