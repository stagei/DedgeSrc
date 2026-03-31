Import-Module GlobalFunctions -Force
Import-Module Db2-Handler -Force
# Check if script is running on a db2 server and as administrator
Test-Db2ServerAndAdmin

# Only call user choice function if SmsNumbers parameter was not provided at all
# If an empty array was explicitly passed, respect that choice
if (-not $PSBoundParameters.ContainsKey('SmsNumbers')) {
    $SmsNumbers = Get-UserChoiceForSmsNumbers
}

$DropExistingDatabases = $true
$scriptName = Join-Path -Path $PSScriptRoot -ChildPath Db2-CreateInitialDatabases.ps1
. $scriptName -DatabaseType "FederatedDb" -PrimaryInstanceName "DB2" -DropExistingDatabases:$DropExistingDatabases -SmsNumbers $SmsNumbers



Import-Module GlobalFunctions -Force
Import-Module Db2-Handler -Force
Import-Module Infrastructure -Force
Import-Module NetSecurity -Force

########################################################################################################
# Main
########################################################################################################
try {
    Write-LogMessage $(Get-InitScriptName) -Level JOB_STARTED

    Add-FederationSupportToDatabases -InstanceName "DB2" -FederationType "Standard" -HandleType "SetupAndRefresh" -RegenerateAllNicknames -SmsNumbers $SmsNumbers 
    Write-LogMessage $(Get-InitScriptName) -Level JOB_COMPLETED
}
catch {
    Write-LogMessage $(Get-InitScriptName) -Level JOB_FAILED -Exception $_
    exit 1
}
finally {
    Reset-OverrideAppDataFolder
}

