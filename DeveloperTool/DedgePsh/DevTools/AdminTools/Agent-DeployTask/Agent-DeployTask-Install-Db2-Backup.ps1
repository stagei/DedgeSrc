Import-Module GlobalFunctions -Force
Import-Module Agent-Handler -Force

# File Watcher Script to Monitor Directory and Start Process
Deploy-AgentTask -TaskName "ReInstall-Db2-Backup" -SourceScript "$env:OptPath\src\DedgePsh\DevTools\DatabaseTools\Db2-Backup\_install.ps1" -ComputerNameList @("*inltst-db")

