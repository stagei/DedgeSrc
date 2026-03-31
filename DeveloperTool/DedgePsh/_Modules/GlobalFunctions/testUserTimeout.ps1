Import-Module GlobalFunctions -Force
Import-Module Db2-Handler -Force

# Handle automatic selection of primary instance
$PrimaryInstanceName = Get-UserConfirmationWithTimeout -PromptMessage "Choose Primary Instance Name: " -TimeoutSeconds 30 -AllowedResponses $(Get-InstanceNameList) -ProgressMessage "Choose primary instance"

# Handle automatic selection of database type
$allowedResponses = @("PrimaryDb", "FederatedDb", "BothDatabases")
$DatabaseType = Get-UserConfirmationWithTimeout -PromptMessage "Choose Database Type: " -TimeoutSeconds 30 -AllowedResponses $allowedResponses -ProgressMessage "Choose database type"
Write-LogMessage "Chosen Database Type: $DatabaseType" -Level INFO

# Handle drop existing databases
$dropExistingDatabasesString = Get-UserConfirmationWithTimeout -PromptMessage "Drop existing databases:" -TimeoutSeconds 30 -ProgressMessage "Drop existing databases"
Write-LogMessage "Chosen Drop Existing Databases: $dropExistingDatabasesString" -Level INFO
$DropExistingDatabases = $dropExistingDatabasesString.ToUpper() -eq "Y"

# Handle automatic selection of federated instance
$FederatedInstanceName = Get-FederatedInstanceNameFromPrimaryInstanceName -PrimaryInstanceName $PrimaryInstanceName
if (-not [string]::IsNullOrEmpty($FederatedInstanceName)) {
    Write-LogMessage "Automatically chosen Federated Instance Name using Primary Instance Name: $FederatedInstanceName" -Level INFO
}

