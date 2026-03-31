Import-Module GlobalFunctions -Force
Import-Module Db2-Handler -Force

$DropExistingDatabases = $true
$scriptName = Join-Path -Path $PSScriptRoot -ChildPath Db2-CreateInitialDatabases.ps1
$GetBackupFromEnvironment = "PRD"
. $scriptName -DatabaseType "BothDatabases" -PrimaryInstanceName "DB2" -DropExistingDatabases:$DropExistingDatabases -GetBackupFromEnvironment $GetBackupFromEnvironment -SmsNumbers @() -UseNewConfigurations:$false

