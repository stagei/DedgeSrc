Import-Module -Name Agent-Handler

Deploy-AgentTask -TaskName "InstallTelnet" -SourceScript "$env:OptPath\src\DedgePsh\DevTools\InfrastructureTools\ServerSetup\installTelnet.ps1" -ComputerNameList "p-no1fkmprd-soa"

