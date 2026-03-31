Import-Module GlobalFunctions -Force
Import-Module Agent-Handler -Force
#$computerNameList = Get-ValidServerNameList
$computerNameList = @("*inlprd-db")
$null = Deploy-AgentTask -TaskName "Install-LogFile-Remover" -SourceScript "$env:OptPath\src\DedgePsh\DevTools\LogTools\LogFile-Remover\_install.ps1" -ComputerNameList $computerNameList  -WaitForJsonFile $true

C:\opt\src\DedgePsh\DevTools\InfrastructureTools\ServerMonitorAgent\ServerMonitorAgent.ps1