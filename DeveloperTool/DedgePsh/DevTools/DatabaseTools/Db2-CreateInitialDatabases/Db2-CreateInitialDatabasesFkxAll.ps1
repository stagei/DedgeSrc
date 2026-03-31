Import-Module GlobalFunctions -Force
Import-Module Db2-Handler -Force

$DropExistingDatabases = $true
$scriptName = Join-Path -Path $PSScriptRoot -ChildPath Db2-CreateInitialDatabases.ps1
$GetBackupFromEnvironment = ""
. $scriptName -DatabaseType "BothDatabases" -PrimaryInstanceName "DB2" -DropExistingDatabases:$DropExistingDatabases -GetBackupFromEnvironment $GetBackupFromEnvironment -SmsNumbers @()

$DropExistingDatabases = $true
$scriptName = Join-Path -Path $PSScriptRoot -ChildPath Db2-CreateInitialDatabases.ps1
$GetBackupFromEnvironment = ""
. $scriptName -DatabaseType "BothDatabases" -PrimaryInstanceName "DB2D" -DropExistingDatabases:$DropExistingDatabases -GetBackupFromEnvironment $GetBackupFromEnvironment -SmsNumbers @()

$DropExistingDatabases = $true
$scriptName = Join-Path -Path $PSScriptRoot -ChildPath Db2-CreateInitialDatabases.ps1
$GetBackupFromEnvironment = ""
. $scriptName -DatabaseType "BothDatabases" -PrimaryInstanceName "DB2Q" -DropExistingDatabases:$DropExistingDatabases -GetBackupFromEnvironment $GetBackupFromEnvironment -SmsNumbers @()

