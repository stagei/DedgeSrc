param(
    [Parameter(Mandatory = $false)]
    [string]$OverrideWorkFolder = "",

    # Instance name of the shadow/target database (e.g. "DB2SH"). Passed by Step-1 from config.json TargetInstance.
    # Defaults to "DB2SH" for backward compatibility but callers should always pass this.
    [Parameter(Mandatory = $false)]
    [string]$InstanceName = "DB2SH"
)

Import-Module GlobalFunctions -Force
Import-Module Db2-Handler -Force

$DropExistingDatabases = $true
$scriptName = Join-Path -Path $PSScriptRoot -ChildPath Db2-CreateInitialDatabases.ps1
$GetBackupFromEnvironment = ""
$invokeParams = @{
    DatabaseType             = "PrimaryDb"
    PrimaryInstanceName      = $InstanceName
    DropExistingDatabases    = $DropExistingDatabases
    GetBackupFromEnvironment = $GetBackupFromEnvironment
    SmsNumbers               = @()
    UseNewConfigurations     = $true
}
if (-not [string]::IsNullOrEmpty($OverrideWorkFolder)) {
    $invokeParams.OverrideWorkFolder = $OverrideWorkFolder
}
. $scriptName @invokeParams
