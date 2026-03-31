# Db2-Restore.ps1
#
# Restores a Db2 database from backup files
# - Finds latest backup files in restore folder
# - Restores database with proper buffer and parallelism settings
# - Configures logging and other database settings
# - Handles rollforward if needed

param(
    [Parameter(Mandatory = $false)]
    [ValidateSet("PrimaryDb", "FederatedDb", "BothDatabases")]
    [string]$DatabaseType = "",
    [Parameter(Mandatory = $false)]
    [string]$PrimaryInstanceName = "",
    [Parameter(Mandatory = $false)]
    [string]$GetBackupFromEnvironment,
    [Parameter(Mandatory = $false)]
    [string[]]$SmsNumbers = @(),
    [Parameter(Mandatory = $false)]
    [string]$OverrideWorkFolder = "",
    [Parameter(Mandatory = $false)]
    [switch]$GetOnlyBackupFilesFromEnvironment = $false
)

Import-Module -Name GlobalFunctions -Force
Import-Module -Name Db2-Handler -Force

###################################################################################
# Main
###################################################################################
try {
    Write-LogMessage $(Get-InitScriptName) -Level JOB_STARTED
    # Check if script is running on a db2 server and as administrator
    Test-Db2ServerAndAdmin

    if ($(Get-EnvironmentFromServerName) -eq "RAP") {
        $PrimaryInstanceName = "DB2"
        $DatabaseType = "PrimaryDb"
        $GetBackupFromEnvironment = "PRD"
        $SmsNumbers = @("+4797188358", "+4795762742")
    }
    else {
        # Handle automatic selection of primary instance
        if (-not $PSBoundParameters.ContainsKey('PrimaryInstanceName') -and [string]::IsNullOrEmpty($PrimaryInstanceName)) {
            $PrimaryInstanceName = Get-UserChoiceForInstanceName -ThrowOnTimeout -DatabaseType "PrimaryDb"
        }
        # Handle automatic selection of database type
        if (-not $PSBoundParameters.ContainsKey('DatabaseType') -and [string]::IsNullOrEmpty($DatabaseType)) {
            $DatabaseType = Get-UserChoiceForDatabaseType -ThrowOnTimeout -AddBothDatabasesOption
        }
        # Handle automatic selection of backup environment
        if (-not $PSBoundParameters.ContainsKey('GetBackupFromEnvironment') -and [string]::IsNullOrEmpty($GetBackupFromEnvironment)) {
            $GetBackupFromEnvironment = Get-UserChoiceForBackupEnvironment -InstanceName $PrimaryInstanceName -DatabaseType $DatabaseType -ThrowOnTimeout
        }
        # Handle sms numbers selection
        if (-not $PSBoundParameters.ContainsKey('SmsNumbers')) {
            $SmsNumbers = Get-UserChoiceForSmsNumbers
        }
        # Handle automatic selection of production confirmation
        Test-ProductionUserChoiceConfirmation
    }

    $null = Start-Db2Restore -PrimaryInstanceName $PrimaryInstanceName -DatabaseType $DatabaseType -GetBackupFromEnvironment $GetBackupFromEnvironment -SmsNumbers $SmsNumbers -OverrideWorkFolder $OverrideWorkFolder -GetOnlyBackupFilesFromEnvironment:$GetOnlyBackupFilesFromEnvironment
    Write-LogMessage $(Get-InitScriptName) -Level JOB_COMPLETED

}
catch {
    # Send SMS to TechOps if failed
    $message = "Db2-Restore FAILED of databases created for $($DatabaseType) and $($PrimaryInstanceName) on $($env:COMPUTERNAME): $($_.Exception.Message)"
    foreach ($smsNumber in $SmsNumbers) {
        Send-Sms -Receiver $smsNumber -Message $message
    }
    Write-LogMessage "Error: $($_.Exception.Message)" -Level ERROR -Exception $_
    Write-LogMessage $(Get-InitScriptName) -Level JOB_FAILED
    Exit 9
}

