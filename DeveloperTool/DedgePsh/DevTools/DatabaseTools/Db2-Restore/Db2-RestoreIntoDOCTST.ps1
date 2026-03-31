Import-Module GlobalFunctions -Force
Import-Module Db2-Handler -Force

$InstanceName = "DB2D"
$DatabaseType = "PrimaryDb"
$GetBackupFromEnvironment = ""
$SmsNumbers = @("+4797188358")
$scriptName = Join-Path -Path $PSScriptRoot -ChildPath Db2-Restore.ps1
. $scriptName -DatabaseType $DatabaseType -PrimaryInstanceName $InstanceName -GetBackupFromEnvironment $GetBackupFromEnvironment -SmsNumbers $SmsNumbers

