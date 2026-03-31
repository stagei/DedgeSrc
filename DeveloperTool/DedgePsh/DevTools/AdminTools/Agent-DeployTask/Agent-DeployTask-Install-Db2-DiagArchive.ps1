Import-Module GlobalFunctions -Force
Import-Module Agent-Handler -Force
# File Watcher Script to Monitor Directory and Start Process
Deploy-AgentTask -TaskName "Install-Db2-DiagArchive" -SourceScript "$env:OptPath\src\DedgePsh\DevTools\DatabaseTools\Db2-DiagArchive\_install.ps1" -ComputerNameList @("*inlprd-db")

