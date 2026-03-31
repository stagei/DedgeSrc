param(
    [Parameter(Mandatory = $false)]
    [ValidateSet("PrimaryDb", "FederatedDb", "BothDatabases")]
    [string]$DatabaseType,
    [Parameter(Mandatory = $false)]
    [ValidateSet("DB2", "DB2HST")]
    [string]$PrimaryInstanceName,
    [Parameter(Mandatory = $false)]
    [string[]]$SmsNumbers = @()
)

Import-Module GlobalFunctions -Force
Import-Module Db2-Handler -Force
Import-Module Infrastructure -Force
Import-Module NetSecurity -Force

########################################################################################################
# Main
########################################################################################################
try {
    if ([string]::IsNullOrEmpty($DatabaseType) -and [string]::IsNullOrEmpty($PrimaryInstanceName)) {
        # Handle automatic selection of primary instance
        $PrimaryInstanceName = Get-UserConfirmationWithTimeout -PromptMessage "Choose Primary Instance Name: " -TimeoutSeconds 30 -AllowedResponses $(Get-InstanceNameList -DatabaseType "PrimaryDb") -ProgressMessage "Choose primary instance" -ThrowOnTimeout
        Write-LogMessage "Chosen Primary Instance Name: $PrimaryInstanceName" -Level INFO

        # Handle automatic selection of database type
        $allowedResponses = @("PrimaryDb", "FederatedDb", "BothDatabases")
        $DatabaseType = Get-UserConfirmationWithTimeout -PromptMessage "Choose Database Type: " -TimeoutSeconds 30 -AllowedResponses $allowedResponses -ProgressMessage "Choose database type"
        Write-LogMessage "Chosen Database Type: $DatabaseType" -Level INFO

        # Handle automatic selection of federated instance
        $FederatedInstanceName = Get-FederatedInstanceNameFromPrimaryInstanceName -PrimaryInstanceName $PrimaryInstanceName
        if (-not [string]::IsNullOrEmpty($FederatedInstanceName)) {
            Write-LogMessage "Automatically chosen Federated Instance Name using Primary Instance Name: $FederatedInstanceName" -Level INFO
        }
    }

    Write-LogMessage "Database Type: $DatabaseType / PrimaryInstanceName is: $PrimaryInstanceName / FederatedInstanceName is: $FederatedInstanceName" -Level INFO

    Write-LogMessage "$(Split-Path -Path $MyInvocation.MyCommand.Path -Leaf)" -Level JOB_STARTED

    # Check if script is running on a server
    if (-not (Test-IsServer)) {
        Write-LogMessage "This script must be run on a server" -Level ERROR
        Exit 1
    }

    # Check if script is running as administrator
    if (-not ( [Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole] "Administrator")) {
        Write-LogMessage "This script must be run as administrator" -Level ERROR
        Exit 2
    }

    if ($(Get-EnvironmentFromServerName) -eq "PRD" -or $(Get-EnvironmentFromServerName) -eq "RAP") {
        $userConfirmationAnswer = Get-UserConfirmationWithTimeout -PromptMessage "Environment is PRD or RAP, so we need to confirm the action for $($env:COMPUTERNAME)?" -TimeoutSeconds 60 -DefaultResponse "N"
        if ($userConfirmationAnswer.ToUpper() -ne "Y") {
            Write-LogMessage "User tried $($env:USERNAME) to create initial databases on $($env:COMPUTERNAME) but did not confirm. Skipping creation of databases." -Level ERROR
            Exit 3
        }
    }

    # Set-LogLevel -LogLevel TRACE
    $appDataPath = Get-ApplicationDataPath
    Set-OverrideAppDataFolder -Path $appDataPath

    #########################################################
    # Primary Database
    #########################################################
    if ($DatabaseType -eq "BothDatabases" -or $DatabaseType -eq "PrimaryDb") {
        $workObject = Get-DefaultWorkObjects -DatabaseType "PrimaryDb" -InstanceName $PrimaryInstanceName -QuickMode

        # Add specific grants for given application and environment
        $WorkObject = Add-SpecificGrants -WorkObject $WorkObject
        if ($WorkObject -is [array]) { Write-LogMessage "Multiple database objects returned" -Level WARN; $WorkObject = $WorkObject[-1] }

        # Export database object to file
        Write-LogMessage "Exporting database object to file" -Level INFO
        $outputFileName = "$($WorkObject.WorkFolder)\Db2-GrantHandler_$($WorkObject.DatabaseName).html"
        Export-WorkObjectToHtmlFile -WorkObject $WorkObject -FileName $outputFileName -Title "Db2 Grant Handler for $($WorkObject.DatabaseName) $($WorkObject.CreationTimestamp)" -AutoOpen $true -AddToDevToolsWebPath $true -DevToolsWebDirectory "Db2\GrantHandler"
    }

    #########################################################
    # Federated Database
    #########################################################
    if ($DatabaseType -eq "BothDatabases" -or $DatabaseType -eq "FederatedDb") {
        if ([string]::IsNullOrEmpty($FederatedInstanceName)) {
            $FederatedInstanceName = "DB2FED"
        }
        $workObject = Get-DefaultWorkObjects -DatabaseType "FederatedDb" -InstanceName $FederatedInstanceName -QuickMode

        # Add specific grants for given application and environment
        $WorkObject = Add-SpecificGrants -WorkObject $WorkObject
        if ($WorkObject -is [array]) { Write-LogMessage "Multiple database objects returned" -Level WARN; $WorkObject = $WorkObject[-1] }

        # Export database object to file
        Write-LogMessage "Exporting database object to file" -Level INFO
        $outputFileName = "$($WorkObject.WorkFolder)\Db2-GrantHandler_$($WorkObject.DatabaseName).html"
        Export-WorkObjectToHtmlFile -WorkObject $WorkObject -FileName $outputFileName -Title "Db2 Grant Handler for $($WorkObject.DatabaseName) $($WorkObject.CreationTimestamp)" -AutoOpen $true -AddToDevToolsWebPath $true -DevToolsWebDirectory "Db2\GrantHandler"
    }
    # Send SMS message to notify success
    $message = "Added grant handler to Db2 database $($WorkObject.DatabaseName) on $($env:COMPUTERNAME)"
    foreach ($smsNumber in $SmsNumbers) {
        Send-Sms -Receiver $smsNumber -Message $message
    }
    Write-LogMessage $(Split-Path -Path $PSScriptRoot -Leaf) -Level JOB_COMPLETED
}
catch {
    Write-LogMessage "Error during adding standard configuration to Db2 database $($WorkObject.DatabaseName) on $($env:COMPUTERNAME): $($_.Exception.Message)" -Level ERROR
    foreach ($smsNumber in $SmsNumbers) {
        Send-Sms -Receiver $smsNumber -Message $message
    }
    Write-LogMessage $(Split-Path -Path $PSScriptRoot -Leaf) -Level JOB_FAILED -Exception $_
    exit 1
}
finally {
    Reset-OverrideAppDataFolder
}

