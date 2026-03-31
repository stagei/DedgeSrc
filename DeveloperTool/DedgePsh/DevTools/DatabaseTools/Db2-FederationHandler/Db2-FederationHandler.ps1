

param(
    [Parameter(Mandatory = $false)]
    [string]$InstanceName = "DB2",
    [Parameter(Mandatory = $false)]
    [string]$TargetDatabaseName = "",
    [Parameter(Mandatory = $false)]
    [string]$LinkedDatabaseName = "",
    [Parameter(Mandatory = $false)]
    [ValidateSet("Standard", "History")]
    [string]$FederationType = "Standard",
    [Parameter(Mandatory = $false)]
    [ValidateSet("Setup", "Refresh", "SetupAndRefresh")]
    [string]$HandleType = "SetupAndRefresh", [Parameter(Mandatory = $false)]
    [string[]]$SmsNumbers = @(),
    [Parameter(Mandatory = $false)]
    [switch]$RegenerateAllNicknames = $false,
    [Parameter(Mandatory = $false)]
    [switch]$WhatIf = $false
)

# Standard: TargetDatabaseName eg. (XINLTST) linker til alle tabeller i LinkedDatabaseName (INLTST)
# History: TargetDatabaseName eg. (INLTST) linker til alle tabeller i LinkedDatabaseName (INLHST)

Import-Module GlobalFunctions -Force
Import-Module Db2-Handler -Force
Import-Module Infrastructure -Force
Import-Module NetSecurity -Force

########################################################################################################
# Main
########################################################################################################
try {
    Write-LogMessage $(Get-InitScriptName) -Level JOB_STARTED

    # Check if script is running on a db2 server and as administrator
    Test-Db2ServerAndAdmin

    # Only call user choice function if SmsNumbers parameter was not provided at all
    # If an empty array was explicitly passed, respect that choice
    if (-not $PSBoundParameters.ContainsKey('SmsNumbers')) {
        $SmsNumbers = Get-UserChoiceForSmsNumbers
    }
    Add-FederationSupportToDatabases -TargetDatabaseName $TargetDatabaseName -LinkedDatabaseName $LinkedDatabaseName -InstanceName $InstanceName -FederationType $FederationType -HandleType $HandleType -RegenerateAllNicknames:$RegenerateAllNicknames -SmsNumbers $SmsNumbers -WhatIf:$WhatIf
    Write-LogMessage $(Get-InitScriptName) -Level JOB_COMPLETED
}
catch {
    Write-LogMessage $(Get-InitScriptName) -Level JOB_FAILED -Exception $_
    exit 1
}
finally {
    Reset-OverrideAppDataFolder
}

