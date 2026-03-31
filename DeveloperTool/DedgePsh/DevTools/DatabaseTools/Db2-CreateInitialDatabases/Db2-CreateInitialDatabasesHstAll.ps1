Import-Module GlobalFunctions -Force
Import-Module Db2-Handler -Force

$DropExistingDatabases = $true
$scriptName = Join-Path -Path $PSScriptRoot -ChildPath Db2-CreateInitialDatabases.ps1
. $scriptName -DatabaseType "BothDatabases" -PrimaryInstanceName "DB2HST" -DropExistingDatabases:$DropExistingDatabases -SmsNumbers @()

