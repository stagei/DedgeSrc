param(
    [Parameter(Mandatory = $false)]
    [string]$OverrideWorkFolder = "",

    # Instance name for the primary database (e.g. "DB2"). Passed by callers from config.json.
    # Defaults to "DB2" for backward compatibility but callers should always pass this.
    [Parameter(Mandatory = $false)]
    [string]$InstanceName = "DB2",

    # Where to get the backup from. "PRD" = wait for/copy PRD backup (used by Step-1 Phase -1).
    # "" (empty) = use existing *.001 already staged in the restore folder (used by Step-4 Phase 3).
    # Defaults to "PRD" so Step-1 Phase -1 callers that don't pass this still work correctly.
    [Parameter(Mandatory = $false)]
    [string]$GetBackupFromEnvironment = "PRD"
)

Import-Module GlobalFunctions -Force
Import-Module Db2-Handler -Force

# UseNewConfigurations version of Db2-CreateInitialDatabasesStdAll.ps1.
# - Phase -1 (Step-1): GetBackupFromEnvironment="PRD", reuses *.001 in restore folder or copies from PRD share.
# - Step-4 Phase 3: GetBackupFromEnvironment="", uses shadow backup already staged in restore folder.
$DropExistingDatabases = $true
$scriptName = Join-Path -Path $PSScriptRoot -ChildPath Db2-CreateInitialDatabases.ps1
$invokeParams = @{
    DatabaseType             = "BothDatabases"
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
