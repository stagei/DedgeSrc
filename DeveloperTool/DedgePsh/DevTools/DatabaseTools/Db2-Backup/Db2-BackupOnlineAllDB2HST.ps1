Import-Module GlobalFunctions -Force
Import-Module Db2-Handler -Force

$scriptName = Join-Path -Path $PSScriptRoot -ChildPath Db2-Backup.ps1
. $scriptName -InstanceName "DB2HST" -DatabaseType "PrimaryDb" -SmsNumbers @()

