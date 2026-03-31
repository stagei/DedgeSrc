Import-Module GlobalFunctions -Force
Import-Module Db2-Handler -Force

$SmsNumbers = @()
$scriptName = Join-Path -Path $PSScriptRoot -ChildPath Db2-FederationHandler.ps1
. $scriptName -FederationType "History" -HandleType "SetupAndRefresh" -TargetDatabaseName "FKMPRD" -LinkedDatabaseName "FKMHST" -SmsNumbers $SmsNumbers

