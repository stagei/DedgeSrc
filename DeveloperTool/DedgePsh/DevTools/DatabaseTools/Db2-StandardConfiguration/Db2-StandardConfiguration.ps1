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
        if (Get-ApplicationFromServerName -in @("FKM", "VIS")) {
            $PrimaryInstanceName = Get-UserConfirmationWithTimeout -PromptMessage "Choose Primary Instance Name: " -TimeoutSeconds 30 -AllowedResponses $(Get-Db2InstanceNames) -ProgressMessage "Choose primary instance" -ThrowOnTimeout
            Write-LogMessage "Chosen Primary Instance Name: $PrimaryInstanceName" -Level INFO
        }
        else {
            $PrimaryInstanceName = Get-PrimaryInstanceName
            Write-LogMessage "Primary Instance Name defaulted to: $PrimaryInstanceName" -Level INFO
        }

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

    if ($(Get-EnvironmentFromServerName) -eq "PRD" -or $(Get-EnvironmentFromServerName) -eq "RAP") {
        $userConfirmationAnswer = Get-UserConfirmationWithTimeout -PromptMessage "Environment is PRD or RAP, so we need to confirm the action for $($env:COMPUTERNAME)?" -TimeoutSeconds 60 -DefaultResponse "N"
        if ($userConfirmationAnswer.ToUpper() -ne "Y") {
            Write-LogMessage "User tried $($env:USERNAME) to create initial databases on $($env:COMPUTERNAME) but did not confirm. Skipping creation of databases." -Level ERROR
            Exit 3
        }
    }
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

    # Set-LogLevel -LogLevel TRACE
    $appDataPath = Get-ApplicationDataPath
    Set-OverrideAppDataFolder -Path $appDataPath

    if ($env:COMPUTERNAME.ToLower().Contains("prd") ) {
        $response = Get-UserConfirmationWithTimeout -PromptMessage "Are you sure you want to set standard configurations on $($env:COMPUTERNAME)?" -TimeoutSeconds 60 -DefaultResponse "N"
        if ($response.ToUpper() -ne "Y") {
            Write-LogMessage "User tried $($env:USERNAME) to set standard configurations on $($env:COMPUTERNAME) but did not confirm" -Level ERROR
            Send-FkAlert -Program "Db2-StandardConfiguration" -Code "9999" -Message "User tried $($env:USERNAME) to set standard configurations on $($env:COMPUTERNAME) but did not confirm"
            Exit 3
        }
    }

    #########################################################
    # Primary Database
    #########################################################
    if ($DatabaseType -eq "BothDatabases" -or $DatabaseType -eq "PrimaryDb") {
        $workObject = Get-DefaultWorkObjects -DatabaseType "PrimaryDb" -InstanceName $PrimaryInstanceName

        # Create primary database
        $WorkObject = Set-StandardConfigurations -WorkObject $WorkObject

        # Export database object to file
        Write-LogMessage "Exporting database object to file" -Level INFO
        $outputFileName = "$($WorkObject.WorkFolder)\Db2-StandardConfiguration_$($WorkObject.DatabaseName).html"
        Export-WorkObjectToHtmlFile -WorkObject $WorkObject -FileName $outputFileName -Title "Db2 Standard Configuration for $($WorkObject.DatabaseName) $($WorkObject.CreationTimestamp)" -AutoOpen $true -AddToDevToolsWebPath $true -DevToolsWebDirectory "Db2\StandardConfiguration"
    }

    #########################################################
    # Federated Database
    #########################################################
    if ($DatabaseType -eq "BothDatabases" -or $DatabaseType -eq "FederatedDb") {
        if ([string]::IsNullOrEmpty($FederatedInstanceName)) {
            $FederatedInstanceName = "DB2FED"
        }
        $workObject = Get-DefaultWorkObjects -DatabaseType "FederatedDb" -InstanceName $FederatedInstanceName

        # Create federated database
        $WorkObject = Set-StandardConfigurations -WorkObject $WorkObject

        # Export database object to file
        Write-LogMessage "Exporting database object to file" -Level INFO
        $outputFileName = "$($WorkObject.WorkFolder)\Db2-StandardConfiguration_$($WorkObject.DatabaseName).html"
        Export-WorkObjectToHtmlFile -WorkObject $WorkObject -FileName $outputFileName -Title "Db2 Standard Configuration for $($WorkObject.DatabaseName) $($WorkObject.CreationTimestamp)" -AutoOpen $true -AddToDevToolsWebPath $true -DevToolsWebDirectory "Db2/$($WorkObject.DatabaseName.ToUpper())"
    }
  # Send SMS message to notify success
  $message = "Added standard configuration to Db2 database $($WorkObject.DatabaseName) on $($env:COMPUTERNAME)"
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

