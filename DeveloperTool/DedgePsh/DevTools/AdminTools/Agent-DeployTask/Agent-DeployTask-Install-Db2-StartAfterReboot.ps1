Import-Module GlobalFunctions -Force
Import-Module Agent-Handler -Force
# File Watcher Script to Monitor Directory and Start Process
Deploy-AgentTask -TaskName "Install-Db2-StartAfterReboot" -SourceScript "$env:OptPath\src\DedgePsh\DevTools\AdminTools\Agent-DeployTask\templates\InstallDb2-StartAfterReboot.ps1" -ComputerNameList @("*-db")

