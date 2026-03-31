param(
    [Parameter(Mandatory = $false)]
    [ValidateSet("PrimaryDb", "FederatedDb", "BothDatabases")]
    [string]$DatabaseType = "",
    [Parameter(Mandatory = $false)]
    [string]$PrimaryInstanceName = "",
    [Parameter(Mandatory = $false)]
    [switch]$DropExistingDatabases = $false,
    [Parameter(Mandatory = $false)]
    [string[]]$SmsNumbers = @(),
    [Parameter(Mandatory = $false)]
    [string]$OverrideWorkFolder = "",
    [Parameter(Mandatory = $false)]
    [string]$GetBackupFromEnvironment,
    [Parameter(Mandatory = $false)]
    [switch]$UseNewConfigurations = $false
)

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

    if (-not $PSBoundParameters.ContainsKey('PrimaryInstanceName')) {
        $PrimaryInstanceName = Get-UserChoiceForInstanceName -ThrowOnTimeout -DatabaseType "PrimaryDb"
    }

    if (-not $PSBoundParameters.ContainsKey('DatabaseType')) {
        $DatabaseType = Get-UserChoiceForDatabaseType -ThrowOnTimeout -AddBothDatabasesOption
    }

    if (-not $PSBoundParameters.ContainsKey('GetBackupFromEnvironment')) {
        $GetBackupFromEnvironment = Get-UserChoiceForBackupEnvironment -InstanceName $PrimaryInstanceName -DatabaseType $DatabaseType -ThrowOnTimeout
    }

    if (-not $PSBoundParameters.ContainsKey('DropExistingDatabases')) {
        $DropExistingDatabases = Get-UserChoiceForDropExistingDatabases 
    }
    if (-not $PSBoundParameters.ContainsKey('UseNewConfigurations')) {
        $UseNewConfigurations = Get-UserChoiceForUseNewConfigurations -DefaultResponse $false
    }
    if (-not $PSBoundParameters.ContainsKey('SmsNumbers')) {
        $SmsNumbers = Get-UserChoiceForSmsNumbers -ThrowOnTimeout
    }

    $federatedInstanceName = ""
    if (($DatabaseType -eq "BothDatabases" -or $DatabaseType -eq "FederatedDb") -and -not $UseNewConfigurations) {
        $federatedInstanceName = Get-FederatedInstanceNameFromPrimaryInstanceName -PrimaryInstanceName $PrimaryInstanceName
        if (-not [string]::IsNullOrEmpty($federatedInstanceName)) {
            Write-LogMessage "Automatically chosen Federated Instance Name using Primary Instance Name: $FederatedInstanceName" -Level INFO
        }
    }
    elseif (($DatabaseType -eq "BothDatabases" -or $DatabaseType -eq "FederatedDb") -and $UseNewConfigurations) {
        Write-LogMessage "UseNewConfigurations: Skipping federated instance — XINLTST is now an alias on the primary instance" -Level INFO
    }

    Test-ProductionUserChoiceConfirmation

    Write-LogMessage "Database Type: $DatabaseType / PrimaryInstanceName is: $PrimaryInstanceName / FederatedInstanceName is: $federatedInstanceName" -Level INFO

    # Set-LogLevel -LogLevel TRACE
    # Set override folder if provided, otherwise use default application data path
    if (-not [string]::IsNullOrEmpty($OverrideWorkFolder)) {
        # Use the explicitly provided override folder
        Set-OverrideAppDataFolder -Path $OverrideWorkFolder
    }
    else {
        # Use default application data path
        $appDataPath = Get-ApplicationDataPath
        Set-OverrideAppDataFolder -Path $appDataPath
    }

    #########################################################
    # Primary Database
    #########################################################
    if ($DatabaseType -eq "BothDatabases" -or $DatabaseType -eq "PrimaryDb") {
        if ([string]::IsNullOrEmpty($PrimaryInstanceName)) {
            throw "PrimaryInstanceName is not set"
        }
        $workObject = Get-DefaultWorkObjects -DatabaseType "PrimaryDb" -InstanceName $PrimaryInstanceName -DropExistingDatabases:$DropExistingDatabases -OverrideWorkFolder $OverrideWorkFolder -SmsNumbers $SmsNumbers -GetBackupFromEnvironment $GetBackupFromEnvironment -UseNewConfigurations:$UseNewConfigurations
        if ($WorkObject -is [array]) { Write-LogMessage "Multiple database objects returned" -Level WARN; $WorkObject = $WorkObject[-1] }
        # Create primary database
        $WorkObject = New-DatabaseAndConfigurations -WorkObject $WorkObject
        if ($WorkObject -is [array]) { Write-LogMessage "Multiple database objects returned" -Level WARN; $WorkObject = $WorkObject[-1] }

    }

    #########################################################
    # Federated Database (skipped when UseNewConfigurations — XINLTST is an alias)
    #########################################################
    if (($DatabaseType -eq "BothDatabases" -or $DatabaseType -eq "FederatedDb") -and -not $UseNewConfigurations) {
        if ([string]::IsNullOrEmpty($federatedInstanceName)) {
            Write-LogMessage "No federated instance found for primary instance '$($PrimaryInstanceName)'. Federated database not configured in DatabasesV2.json — skipping." -Level WARN
            $fedInstExample = "$($PrimaryInstanceName -replace 'DB2','X')"
            $sampleJson = @"

To re-enable federated database support, add an entry like this to DatabasesV2.json:

{
    "DatabaseName": "<DBNAME>",
    "InstanceName": "$($fedInstExample)",
    "AccessPointType": "FederatedDb",
    "ServerName": "$($env:COMPUTERNAME)",
    "BackupEnabled": false,
    "Description": "Federated database on $($fedInstExample)"
}
"@
            Write-Host $sampleJson
        }
        else {
            try {
                $workObject = Get-DefaultWorkObjects -DatabaseType "FederatedDb" -InstanceName $federatedInstanceName -DropExistingDatabases:$DropExistingDatabases -OverrideWorkFolder $OverrideWorkFolder -SmsNumbers $SmsNumbers -GetBackupFromEnvironment $GetBackupFromEnvironment -UseNewConfigurations:$UseNewConfigurations
                if ($WorkObject -is [array]) { Write-LogMessage "Multiple database objects returned" -Level WARN; $WorkObject = $WorkObject[-1] }

                $WorkObject = New-DatabaseAndConfigurations -WorkObject $WorkObject
                if ($WorkObject -is [array]) { Write-LogMessage "Multiple database objects returned" -Level WARN; $WorkObject = $WorkObject[-1] }
            }
            catch {
                Write-LogMessage "Federated database creation failed for instance '$($federatedInstanceName)'. Skipping." -Level WARN

                $sampleJson = @"

To re-enable federated database support, verify the entry in DatabasesV2.json:

{
    "DatabaseName": "<DBNAME>",
    "InstanceName": "$($federatedInstanceName)",
    "AccessPointType": "FederatedDb",
    "ServerName": "$($env:COMPUTERNAME)",
    "BackupEnabled": false,
    "Description": "Federated database on $($federatedInstanceName)"
}
"@
                Write-Host $sampleJson
                Write-LogMessage "Federated database JSON sample printed to console. Job continues without federated database." -Level WARN
            }
        }
    }

    $message = "Db2-CreateInitialDatabase SUCCESS of databases created for $($DatabaseType) and $($PrimaryInstanceName ? $PrimaryInstanceName : $federatedInstanceName) successfully on $($env:COMPUTERNAME)!"
    foreach ($smsNumber in $SmsNumbers) {
        Send-Sms -Receiver $smsNumber -Message $message
    }
    if ($(Get-EnvironmentFromServerName) -eq "PRD" -or $(Get-EnvironmentFromServerName) -eq "RAP") {
        Send-Sms -Receiver "+4795762742" -Message $message
    }
    Write-LogMessage $(Get-InitScriptName) -Level JOB_COMPLETED
}
catch {
    Write-LogMessage "Error: $($_.Exception.Message)" -Level ERROR -Exception $_
    $message = "Error during creation of Db2 databases: $($_.Exception.Message)"
    Send-Sms -Receiver "+4797188358" -Message $message
    if ($(Get-EnvironmentFromServerName) -eq "PRD" -or $(Get-EnvironmentFromServerName) -eq "RAP") {
        Send-Sms -Receiver "+4795762742" -Message $message
    }
    Write-LogMessage $(Get-InitScriptName) -Level JOB_FAILED
    exit 1
}
finally {
    Reset-OverrideAppDataFolder
}

