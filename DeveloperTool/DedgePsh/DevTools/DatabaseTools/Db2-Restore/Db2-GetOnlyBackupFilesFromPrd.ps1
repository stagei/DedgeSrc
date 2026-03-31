Import-Module GlobalFunctions -Force
Import-Module Db2-Handler -Force

$SmsNumbers = @("+4797188358")
$scriptName = Join-Path -Path $PSScriptRoot -ChildPath Db2-Restore.ps1
. $scriptName -DatabaseType "PrimaryDb" -PrimaryInstanceName "DB2" -GetBackupFromEnvironment "PRD" -SmsNumbers $SmsNumbers -GetOnlyBackupFilesFromEnvironment

