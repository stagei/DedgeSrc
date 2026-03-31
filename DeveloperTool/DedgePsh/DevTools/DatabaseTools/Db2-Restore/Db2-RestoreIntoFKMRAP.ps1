Import-Module GlobalFunctions -Force
Import-Module Db2-Handler -Force

$InstanceName = "DB2"
$DatabaseType = "PrimaryDb"
$GetBackupFromEnvironment = "PRD"
$SmsNumbers = @("+4797188358", "+4795762742")
$scriptName = Join-Path -Path $PSScriptRoot -ChildPath Db2-Restore.ps1
. $scriptName -DatabaseType $DatabaseType -PrimaryInstanceName $InstanceName -GetBackupFromEnvironment $GetBackupFromEnvironment -SmsNumbers $SmsNumbers

