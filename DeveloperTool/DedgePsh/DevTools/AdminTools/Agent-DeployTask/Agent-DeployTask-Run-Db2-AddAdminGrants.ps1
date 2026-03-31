Import-Module GlobalFunctions -Force
Import-Module Agent-Handler -Force

# File Watcher Script to Monitor Directory and Start Process
$env:OptPath\src\DedgePsh\DevTools\DatabaseTools\_deployDb2All.ps1
Deploy-AgentTask -TaskName "Run-Db2-AddAdminGrants" -SourceScript "$env:OptPath\src\DedgePsh\DevTools\DatabaseTools\Db2-AddAdminGrants\Db2-AddAdminGrants.ps1" -ComputerNameList @("*-db")

