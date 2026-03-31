# Db2-ManualServerReConfig.ps1
# Author: Geir Helge Starholm, www.dEdge.no
# Purpose: Interactive tool for executing Db2-Handler functions on WorkObjects
# This script provides a menu-driven interface to execute any Db2-Handler function
# that accepts and returns a WorkObject, with smart parameter handling.

Import-Module GlobalFunctions -Force
Import-Module Db2-Handler -Force

########################################################################################################
# Function Metadata Configuration
########################################################################################################

function Get-FunctionMetadata {
    <#
    .SYNOPSIS
        Returns metadata for all Db2-Handler functions that accept WorkObjects.
    #>
    return @(
        # Database Information & State
        @{
            Category  = "Database Information & State"
            Functions = @(
                @{ Name = "Get-CurrentDb2StateInfo"; Description = "Show Current Db2 State Info"; SecondaryParams = @{ GetAllDatabasesInfo = @{ Type = "Switch"; Prompt = "Get all databases info?" } } ; QuickMode = $false }
                @{ Name = "Get-WorkObjectProperties"; Description = "Display Work Object Properties"; SecondaryParams = @{} ; QuickMode = $true }
                @{ Name = "Get-DatabaseConfiguration"; Description = "Get Database Configuration"; SecondaryParams = @{} ; QuickMode = $true }
                @{ Name = "Get-Db2InstanceConfiguration"; Description = "Get Db2 Server Configuration"; SecondaryParams = @{} ; QuickMode = $true }
                @{ Name = "Get-Db2Version"; Description = "Get Db2 Version"; SecondaryParams = @{} ; QuickMode = $true }
                @{ Name = "Get-ExistingDatabases"; Description = "Get Existing Databases"; SecondaryParams = @{} ; QuickMode = $true }
                @{ Name = "Get-ExistingDatabasesList"; Description = "Get Existing Databases List"; SecondaryParams = @{ OverrideInstanceName = @{ Type = "String"; Prompt = "Override instance name (optional)?" } } ; QuickMode = $true }
                @{ Name = "Get-ExistingInstances"; Description = "Get Existing Instances"; SecondaryParams = @{} ; QuickMode = $true }
                @{ Name = "Get-ExistingNodes"; Description = "Get Existing Nodes"; SecondaryParams = @{} ; QuickMode = $true }
                @{ Name = "Show-AllDatabases"; Description = "Show All Databases"; SecondaryParams = @{} ; QuickMode = $true }
                @{ Name = "Test-DatabaseExistance"; Description = "Test Database Existance"; SecondaryParams = @{} ; QuickMode = $false }
                @{ Name = "Test-InstanceExistance"; Description = "Test Instance Existance"; SecondaryParams = @{} ; QuickMode = $false }
                @{ Name = "Test-TableExistance"; Description = "Test Table Existance"; SecondaryParams = @{} ; QuickMode = $false }
                @{ Name = "Test-DatabaseRecoverability"; Description = "Test Database Recoverability"; SecondaryParams = @{} ; QuickMode = $true }
                @{ Name = "Test-ControlSqlStatement"; Description = "Test Control SQL Statement"; SecondaryParams = @{ Force = @{ Type = "Switch"; Prompt = "Force execution?" } } ; QuickMode = $true }
            )
        }
        
        # Database Schema & Objects
        @{
            Category  = "Database Schema & Objects"
            Functions = @(
                @{ Name = "Get-DatabaseTableList"; Description = "Get Database Table List"; SecondaryParams = @{} ; QuickMode = $true }
                @{ Name = "Get-DatabaseSchemaList"; Description = "Get Database Schema List"; SecondaryParams = @{} ; QuickMode = $true }
                @{ Name = "Get-DatabaseListOfFunctions"; Description = "Get Database Functions List"; SecondaryParams = @{ SchemaList = @{ Type = "StringArray"; Prompt = "Enter schema list (comma-separated, optional)?" } } ; QuickMode = $true }
                @{ Name = "Get-DatabaseListOfTables"; Description = "Get Database Tables List"; SecondaryParams = @{ SchemaList = @{ Type = "StringArray"; Prompt = "Enter schema list (comma-separated, optional)?" } } ; QuickMode = $true }
                @{ Name = "Get-DatabaseGrantList"; Description = "Get Database Grant List"; SecondaryParams = @{} ; QuickMode = $true }
            )
        }
        
        # Services & Cataloging
        @{
            Category  = "Services & Cataloging"
            Functions = @(
                @{ Name = "Add-Db2ServicesToServiceFile"; Description = "Add Services to Service File"; SecondaryParams = @{ ServicesMethod = @{ Type = "ValidateSet"; Values = @("Legacy", "PrimaryDb", "FederatedDb", "SslPort", "CompleteRange"); Prompt = "Choose Services Method?" } } ; QuickMode = $true }
                @{ Name = "Get-Db2ServicesToServiceFile"; Description = "Get Services from Service File"; SecondaryParams = @{ ServicesMethod = @{ Type = "ValidateSet"; Values = @("Legacy", "PrimaryDb", "FederatedDb", "SslPort", "CompleteRange"); Prompt = "Choose Services Method?" } } ; QuickMode = $true }
                @{ Name = "Remove-Db2ServicesFromServiceFileSimplified"; Description = "Remove Services from Service File"; SecondaryParams = @{} ; QuickMode = $true }
                @{ Name = "Remove-AllDb2ServicesFromServiceFile"; Description = "Remove All Services from Service File"; SecondaryParams = @{} ; QuickMode = $true }
                @{ Name = "Add-CatalogingForNodes"; Description = "Add Cataloging for Nodes"; SecondaryParams = @{ ServiceMethod = @{ Type = "String"; Prompt = "Enter Service Method?" } } ; QuickMode = $true }
                @{ Name = "Remove-CatalogingForNodes"; Description = "Remove Cataloging for Nodes"; SecondaryParams = @{} ; QuickMode = $true }
                @{ Name = "Add-ServerCatalogingForLocalDatabase"; Description = "Add Server Cataloging for Local Database"; SecondaryParams = @{} ; QuickMode = $true }
                @{ Name = "Remove-CatalogingForDatabase"; Description = "Remove Cataloging for Database"; SecondaryParams = @{} ; QuickMode = $true }
                @{ Name = "Add-OdbcCatalogEntry"; Description = "Add ODBC Catalog Entry"; SecondaryParams = @{ Quiet = @{ Type = "Switch"; Prompt = "Run quietly?" } } ; QuickMode = $true }
            )
        }
        
        # Permissions & Security
        @{
            Category  = "Permissions & Security"
            Functions = @(
                @{ Name = "Set-DatabasePermissions"; Description = "Set Database Permissions"; SecondaryParams = @{} ; QuickMode = $true }
                @{ Name = "Add-SpecificGrants"; Description = "Add Specific Grants"; SecondaryParams = @{} ; QuickMode = $true }
                @{ Name = "Add-Db2AccessGroups"; Description = "Add Db2 Access Groups"; SecondaryParams = @{} ; QuickMode = $true }
                @{ Name = "Remove-Db2AccessGroups"; Description = "Remove Db2 Access Groups"; SecondaryParams = @{} ; QuickMode = $true }
                @{ Name = "Remove-Db2AccessUsersFromGroups"; Description = "Remove Db2 Access Users From Groups"; SecondaryParams = @{} ; QuickMode = $true }
                @{ Name = "Add-FkkontoLocalGroup"; Description = "Add Fkkonto Local Group"; SecondaryParams = @{} ; QuickMode = $true }
                @{ Name = "Remove-FkkontoLocalGroup"; Description = "Remove Fkkonto Local Group"; SecondaryParams = @{} ; QuickMode = $true }
                @{ Name = "Add-Db2DirectoryPermission"; Description = "Add Db2 Directory Permissions"; SecondaryParams = @{} ; QuickMode = $true }
            )
        }
        
        # Database Configuration & Setup
        @{
            Category  = "Database Configuration & Setup"
            Functions = @(
                @{ Name = "Add-Db2Database"; Description = "Add Db2 Database"; SecondaryParams = @{} ; QuickMode = $false }
                @{ Name = "Add-DatabaseConfigurations"; Description = "Add Database Configurations"; SecondaryParams = @{} ; QuickMode = $false }
                @{ Name = "Set-Db2InitialConfiguration"; Description = "Set Db2 Initial Configuration"; SecondaryParams = @{} ; QuickMode = $false }
                @{ Name = "Set-PostRestoreConfiguration"; Description = "Set Post Restore Configuration"; SecondaryParams = @{} ; QuickMode = $false }
                @{ Name = "Set-StandardConfigurations"; Description = "Set Standard Configurations"; SecondaryParams = @{} ; QuickMode = $false }
                @{ Name = "Set-InstanceNameConfiguration"; Description = "Set Instance Name Configuration"; SecondaryParams = @{} ; QuickMode = $false }
                @{ Name = "Set-InstanceServiceUserNameAndPassword"; Description = "Set Instance Service User & Password"; SecondaryParams = @{} ; QuickMode = $false }
                @{ Name = "Add-LoggingToDatabase"; Description = "Add Logging to Database"; SecondaryParams = @{} ; QuickMode = $false }
                @{ Name = "Test-DatabaseGeneralSettings"; Description = "Test Database General Settings"; SecondaryParams = @{ GetAllDatabasesInfo = @{ Type = "Switch"; Prompt = "Get all databases info?" } } ; QuickMode = $false }
                @{ Name = "Test-AndSetRestoredCredentials"; Description = "Test & Set Restored Credentials"; SecondaryParams = @{ GetAllDatabasesInfo = @{ Type = "Switch"; Prompt = "Get all databases info?" } } ; QuickMode = $false }
                @{ Name = "Get-Db2Folders"; Description = "Get/Create Db2 Folders"; SecondaryParams = @{ FolderName = @{ Type = "String"; Prompt = "Folder name (optional)?" }; Quiet = @{ Type = "Switch"; Prompt = "Run quietly?" }; SkipRecreateDb2Folders = @{ Type = "Switch"; Prompt = "Skip recreate Db2 folders?" } } ; QuickMode = $false }
                @{ Name = "New-DatabaseAndConfigurations"; Description = "Create New Database & Configurations"; SecondaryParams = @{} ; QuickMode = $false }
            )
        }
        
        # Firewall & Network
        @{
            Category  = "Firewall & Network"
            Functions = @(
                @{ Name = "Add-FirewallRules"; Description = "Add Firewall Rules"; SecondaryParams = @{} ; QuickMode = $true }
                @{ Name = "Remove-ExistingFirewallRules"; Description = "Remove Existing Firewall Rules"; SecondaryParams = @{} ; QuickMode = $true }
            )
        }
        
        # Federation
        @{
            Category  = "Federation"
            Functions = @(
                @{ Name = "Add-FederationSupport"; Description = "Add Federation Support"; SecondaryParams = @{} ; QuickMode = $false }
                @{ Name = "Get-AllWrappers"; Description = "Get All Wrappers"; SecondaryParams = @{} ; QuickMode = $true }
                @{ Name = "Get-AllServers"; Description = "Get All Servers"; SecondaryParams = @{ ServerName = @{ Type = "String"; Prompt = "Server name (optional)?" }; Port = @{ Type = "String"; Prompt = "Port (optional)?" } } ; QuickMode = $true }
                @{ Name = "Get-AllUserOptions"; Description = "Get All User Options"; SecondaryParams = @{ ServerName = @{ Type = "String"; Prompt = "Server name (optional)?" } } ; QuickMode = $true }
                @{ Name = "Get-ExistingNicknames"; Description = "Get Existing Nicknames"; SecondaryParams = @{} ; QuickMode = $true }
                @{ Name = "Get-ExistingNicknamesNew"; Description = "Get Existing Nicknames (New Method)"; SecondaryParams = @{} ; QuickMode = $true }
                @{ Name = "Start-NicknameHandling"; Description = "Start Nickname Handling"; SecondaryParams = @{ UseNewMethod = @{ Type = "Switch"; Prompt = "Use new method?" }; WhatIf = @{ Type = "Switch"; Prompt = "WhatIf mode?" } } ; QuickMode = $true }
                @{ Name = "Remove-ObsoleteFederationUserMappings"; Description = "Remove Obsolete Federation User Mappings"; SecondaryParams = @{} ; QuickMode = $true }
            )
        }
        
        # Instance Management
        @{
            Category  = "Instance Management"
            Functions = @(
                @{ Name = "Restart-Db2AndActivateDb"; Description = "Restart Db2 & Activate Database"; SecondaryParams = @{} ; QuickMode = $true }
                @{ Name = "Start-Db2AndActivateDb"; Description = "Start Db2 & Activate Database"; SecondaryParams = @{} ; QuickMode = $true }
                @{ Name = "ReStart-InstanceAndActivateDatabase"; Description = "Restart Instance & Activate Database"; SecondaryParams = @{} ; QuickMode = $true }
                @{ Name = "Remove-InstanceName"; Description = "Remove Instance Name"; SecondaryParams = @{} ; QuickMode = $false }
            )
        }
        
        # Backup & Restore
        @{
            Category  = "Backup & Restore"
            Functions = @(
                @{ Name = "Backup-SingleDatabase"; Description = "Backup Single Database"; SecondaryParams = @{} ; QuickMode = $false }
                @{ Name = "Restore-SingleDatabase"; Description = "Restore Single Database"; SecondaryParams = @{} ; QuickMode = $false }
            )
        }
        
        # Queries & Data Operations
        @{
            Category  = "Queries & Data Operations"
            Functions = @(
                @{ Name = "Get-ArrayFromQuery"; Description = "Get Array From Query"; SecondaryParams = @{ SqlSelectStatement = @{ Type = "String"; Prompt = "Enter SQL SELECT statement?" } } ; QuickMode = $true }
                @{ Name = "Get-ControlSqlStatement"; Description = "Get Control SQL Statement"; SecondaryParams = @{ SelectCount = @{ Type = "String"; Prompt = "Select count (optional)?" }; RowCount = @{ Type = "String"; Prompt = "Row count (optional)?" } } ; QuickMode = $true }
                @{ Name = "Start-SetIntegrityAndReorgTable"; Description = "Set Integrity & Reorg Table"; SecondaryParams = @{ TableSchema = @{ Type = "String"; Prompt = "Enter table schema?" } ; TableName = @{ Type = "String"; Prompt = "Enter table name?" } } ; QuickMode = $false }
                @{ Name = "Test-BackupFileIntegrity"; Description = "Test Backup File Integrity"; SecondaryParams = @{ BackupFile = @{ Type = "String"; Prompt = "Enter backup file (optional if present in WorkObject)?" } } ; QuickMode = $false }
            )
        }
        
        # Special Functions
        @{
            Category  = "Special Functions"
            Functions = @(
                @{ Name = "Add-HstSchemaFromFkmNonPrd"; Description = "Add HST Schema from FKM non-production"; SecondaryParams = @{} ; QuickMode = $false }
                @{ Name = "Get-ConnectCommand"; Description = "Get Connect Command"; SecondaryParams = @{} ; QuickMode = $true }
                @{ Name = "Get-SetInstanceNameCommand"; Description = "Get Set Instance Name Command"; SecondaryParams = @{} ; QuickMode = $true }
            )
        }
    )
}

########################################################################################################
# Helper Functions
########################################################################################################

function Show-MenuHeader {
    param(
        [string]$Title,
        [int]$LineLength = 80
    )
    
    $paddingLength = [Math]::Max(0, ($LineLength - $Title.Length) / 2)
    Write-Host ""
    Write-Host ("=" * $LineLength) -ForegroundColor Cyan
    Write-Host (" " * $paddingLength) $Title -ForegroundColor White
    Write-Host ("=" * $LineLength) -ForegroundColor Cyan
    Write-Host ""
}

function Show-CurrentConfig {
    param(
        [string]$InstanceName,
        [string]$DatabaseName,
        [PSCustomObject]$PrimaryWorkObject,
        [PSCustomObject]$FederatedWorkObject
    )
    
    Write-Host "Current Configuration:" -ForegroundColor Yellow
    Write-Host "  Instance Name  : $InstanceName" -ForegroundColor Gray
    Write-Host "  Database Name  : $DatabaseName" -ForegroundColor Gray
    Write-Host "  Primary WO     : $($null -ne $PrimaryWorkObject)" -ForegroundColor Gray
    Write-Host "  Federated WO   : $($null -ne $FederatedWorkObject)" -ForegroundColor Gray
    Write-Host ""
}

function Show-FunctionSynopsis {
    param(
        [string]$FunctionName
    )
    
    Clear-Host
    Show-MenuHeader -Title "Function Synopsis" -LineLength 80
    
    Write-Host "Function: " -NoNewline -ForegroundColor Yellow
    Write-Host $FunctionName -ForegroundColor White
    Write-Host ""
    
    try {
        $help = Get-Help $FunctionName -ErrorAction Stop
        
        if ($help.Synopsis) {
            Write-Host "Synopsis:" -ForegroundColor Cyan
            Write-Host $help.Synopsis -ForegroundColor Gray
            Write-Host ""
        }
        
        if ($help.Description) {
            Write-Host "Description:" -ForegroundColor Cyan
            foreach ($desc in $help.Description) {
                Write-Host $desc.Text -ForegroundColor Gray
            }
            Write-Host ""
        }
        
        if ($help.Parameters) {
            Write-Host "Parameters:" -ForegroundColor Cyan
            foreach ($param in $help.Parameters.Parameter) {
                Write-Host "  -$($param.Name)" -ForegroundColor Yellow -NoNewline
                Write-Host " [$($param.Type.Name)]" -ForegroundColor DarkGray
                if ($param.Description) {
                    foreach ($desc in $param.Description) {
                        Write-Host "    $($desc.Text)" -ForegroundColor Gray
                    }
                }
            }
            Write-Host ""
        }
        
        if ($help.Examples) {
            Write-Host "Examples:" -ForegroundColor Cyan
            foreach ($example in $help.Examples.Example) {
                if ($example.Title) {
                    Write-Host "  $($example.Title)" -ForegroundColor Yellow
                }
                if ($example.Code) {
                    Write-Host "    $($example.Code)" -ForegroundColor DarkGray
                }
                if ($example.Remarks) {
                    foreach ($remark in $example.Remarks) {
                        Write-Host "    $($remark.Text)" -ForegroundColor Gray
                    }
                }
                Write-Host ""
            }
        }
    }
    catch {
        Write-Host "Unable to retrieve help for function: $FunctionName" -ForegroundColor Red
        Write-Host "Error: $($_.Exception.Message)" -ForegroundColor Red
    }
    
    Write-Host ""
    Write-Host ("=" * 80) -ForegroundColor Cyan
    Write-Host "Press any key to return to menu..." -ForegroundColor Yellow
    $null = $Host.UI.RawUI.ReadKey("NoEcho,IncludeKeyDown")
}

function Show-CategorySynopsis {
    param(
        [hashtable]$Category
    )
    
    Clear-Host
    Show-MenuHeader -Title "Category Synopsis: $($Category.Category)" -LineLength 80
    
    Write-Host "All functions in this category:" -ForegroundColor Yellow
    Write-Host ""
    
    foreach ($func in $Category.Functions) {
        Write-Host "$($func.Name)" -ForegroundColor Cyan
        
        try {
            $help = Get-Help $func.Name -ErrorAction SilentlyContinue
            if ($help.Synopsis) {
                Write-Host "  $($help.Synopsis)" -ForegroundColor Gray
            }
            else {
                Write-Host "  No synopsis available" -ForegroundColor DarkGray
            }
        }
        catch {
            Write-Host "  Unable to retrieve synopsis" -ForegroundColor Red
        }
        
        Write-Host ""
    }
    
    Write-Host ("=" * 80) -ForegroundColor Cyan
    Write-Host "Press any key to return to menu..." -ForegroundColor Yellow
    $null = $Host.UI.RawUI.ReadKey("NoEcho,IncludeKeyDown")
}

function Get-SecondaryParameters {
    param(
        [hashtable]$SecondaryParamsDef
    )
    
    $params = @{}
    
    foreach ($paramName in $SecondaryParamsDef.Keys) {
        $paramDef = $SecondaryParamsDef[$paramName]
        $paramType = $paramDef.Type
        $prompt = $paramDef.Prompt
        
        switch ($paramType) {
            "Switch" {
                $response = Read-Host "$prompt (Y/N, default: N)"
                if ($response -eq "Y" -or $response -eq "y") {
                    $params[$paramName] = $true
                }
            }
            "String" {
                $response = Read-Host "$prompt (press Enter to skip)"
                if (-not [string]::IsNullOrWhiteSpace($response)) {
                    $params[$paramName] = $response
                }
            }
            "StringArray" {
                $response = Read-Host "$prompt (press Enter to skip)"
                if (-not [string]::IsNullOrWhiteSpace($response)) {
                    $params[$paramName] = $response -split ',' | ForEach-Object { $_.Trim() }
                }
            }
            "ValidateSet" {
                $allowedValues = $paramDef.Values
                $allowedResponses = Get-UserConfirmationWithTimeout -PromptMessage "$prompt [$($allowedValues -join ', ')]" -TimeoutSeconds 30 -AllowedResponses $allowedValues -ProgressMessage "Choose option" -DefaultResponse ""
                if ($allowedResponses -in $allowedValues) {
                    $params[$paramName] = $allowedResponses
                }
            }
        }
    }
    
    return $params
}

function Invoke-WorkObjectFunction {
    param(
        [string]$FunctionName,
        [PSCustomObject]$WorkObject,
        [hashtable]$AdditionalParams,
        [bool]$QuickMode = $false
    )
    
    $params = @{
        WorkObject = $WorkObject
    }
    if (-not $QuickMode) {
        $WorkObject = Get-DefaultWorkObjects -DatabaseType $WorkObject.DatabaseType -InstanceName $WorkObject.InstanceName -DropExistingDatabases:$WorkObject.DropExistingDatabases 
        if ($WorkObject -is [array]) { $WorkObject = $WorkObject[-1] }
    }
    foreach ($key in $AdditionalParams.Keys) {
        $params[$key] = $AdditionalParams[$key]
    }
    
    Write-LogMessage "Executing: $FunctionName with params: $($params.Keys -join ', ')" -Level INFO
    
    try {
        $result = & $FunctionName @params
        
        if ($result -is [array] -and $result.Count -gt 0) {
            Write-LogMessage "Multiple objects returned, using last one" -Level WARN
            return $result[-1]
        }
        
        return $result
    }
    catch {
        Write-LogMessage "Error executing $($FunctionName): $($_.Exception.Message)" -Level ERROR -Exception $_
        return $WorkObject
    }
}

function Select-WorkObjectTarget {
    param(
        [string]$FunctionName,
        [PSCustomObject]$PrimaryWorkObject,
        [PSCustomObject]$FederatedWorkObject
    )
    
    $availableTargets = @()
    if ($null -ne $PrimaryWorkObject) { $availableTargets += "PrimaryDb" }
    if ($null -ne $FederatedWorkObject) { $availableTargets += "FederatedDb" }
    $availableTargets += "Both"
    
    if ($availableTargets.Count -eq 1) {
        return @($availableTargets[0])
    }
    
    Write-Host "Select target for $($FunctionName):" -ForegroundColor Yellow
    for ($i = 0; $i -lt $availableTargets.Count; $i++) {
        Write-Host "  [$($i+1)] $($availableTargets[$i])"
    }
    
    $choice = Read-Host "Enter choice (default: 1)"
    if ([string]::IsNullOrWhiteSpace($choice)) { $choice = "1" }
    
    $index = [int]$choice - 1
    if ($index -ge 0 -and $index -lt $availableTargets.Count) {
        $selected = $availableTargets[$index]
        if ($selected -eq "Both") {
            return @("PrimaryDb", "FederatedDb")
        }
        else {
            return @($selected)
        }
    }
    
    return @("PrimaryDb")
}

########################################################################################################
# Main
########################################################################################################

try {
    Write-LogMessage $(Get-InitScriptName) -Level JOB_STARTED
    
    if (-not (Test-IsDb2Server)) {
        Write-LogMessage "This script must be run on a DB server" -Level ERROR
        throw "This script must be run on a DB server"
    }
    
    # Initialize variables
    $continue = $true
    $InstanceName = $null
    $DatabaseName = $null
    $primaryWorkObject = $null
    $federatedWorkObject = $null
    $functionMetadata = Get-FunctionMetadata
    
    while ($continue) {
        Clear-Host
        Show-MenuHeader -Title "Db2 Manual Server ReConfig - Enhanced" -LineLength 80
        Show-CurrentConfig -InstanceName $InstanceName -DatabaseName $DatabaseName -PrimaryWorkObject $primaryWorkObject -FederatedWorkObject $federatedWorkObject
        
        # Build menu
        Write-Host "Main Menu:" -ForegroundColor Yellow
        Write-Host "  [Q] Quit" -ForegroundColor White
        Write-Host "  [1] Select Database" -ForegroundColor White
        Write-Host "  [2] View/Export WorkObjects" -ForegroundColor White
        Write-Host ""
        
        if ([string]::IsNullOrEmpty($DatabaseName)) {
            Write-Host "Please select a database first (option 1)" -ForegroundColor Red
            $choice = "1"
        }
        else {
            Write-Host "Function Categories:" -ForegroundColor Yellow
            $categoryIndex = 3
            $categoryMap = @{}
            
            foreach ($category in $functionMetadata) {
                $categoryMap["$categoryIndex"] = $category
                Write-Host "  [$categoryIndex] $($category.Category)" -ForegroundColor Cyan
                $categoryIndex++
            }
            
            Write-Host ""
            Write-Host "TIP: Add '?' after a number (e.g., '4?') to view synopsis" -ForegroundColor DarkGray
            Write-Host ""
            $choice = Read-Host "Enter your choice"
        }
        

        # Check if user requested synopsis for a category
        if ($choice.Contains('?') -or $choice.ToLower().Contains('-h') -or $choice.ToLower().Contains('--h')) {
            $categoryNumber = $choice.Split(' ')[0].Trim()
            if ($categoryMap.ContainsKey($categoryNumber)) {
                Show-CategorySynopsis -Category $categoryMap[$categoryNumber]
                $choice = ""
                continue
            }
        }
        
        switch ($choice.ToUpper()) {
            "Q" {
                Write-LogMessage "User chose to quit" -Level INFO
                $continue = $false
                break
            }
            
            "1" {
                # Select Database
                $InstanceName = $null
                $DatabaseName = $null
                
                $databaseList = Get-DatabasesV2Json | Where-Object { $_.IsActive -eq $true -and $_.Provider -eq "DB2" -and $_.ServerName -eq $env:COMPUTERNAME }
                $AllowedResponses = $databaseList | Select-Object -ExpandProperty Database
                $DatabaseName = Get-UserConfirmationWithTimeout -PromptMessage "Choose Database Name: " -TimeoutSeconds 30 -AllowedResponses $AllowedResponses -ProgressMessage "Choose database"
                
                if (-not [string]::IsNullOrEmpty($DatabaseName)) {
                    $currentDatabase = $databaseList | Where-Object { $_.Database -eq $DatabaseName }
                    $InstanceName = $currentDatabase.AccessPoints[0].InstanceName
                    
                    Write-LogMessage "Loading WorkObjects for database: $DatabaseName, instance: $InstanceName" -Level INFO
                    
                    $primaryWorkObject = Get-DefaultWorkObjects -DatabaseType "PrimaryDb" -InstanceName $InstanceName -DropExistingDatabases:$false -QuickMode
                    if ($primaryWorkObject -is [array]) { $primaryWorkObject = $primaryWorkObject[-1] }
                    
                    $federatedInstanceName = Get-FederatedInstanceNameFromPrimaryInstanceName $InstanceName
                    $federatedWorkObject = Get-DefaultWorkObjects -DatabaseType "FederatedDb" -InstanceName $federatedInstanceName -DropExistingDatabases:$false -QuickMode
                    if ($federatedWorkObject -is [array]) { $federatedWorkObject = $federatedWorkObject[-1] }
                    
                    Write-LogMessage "WorkObjects loaded successfully" -Level INFO
                }
            }
            
            "2" {
                # View/Export WorkObjects
                if ($null -eq $primaryWorkObject -and $null -eq $federatedWorkObject) {
                    Write-Host "No WorkObjects loaded. Please select a database first." -ForegroundColor Red
                    Start-Sleep -Seconds 2
                    continue
                }
                
                $codeExecution = Get-CommandPathWithFallback -Name "code"
                if (Test-Path $codeExecution -PathType Leaf) {
                    Write-LogMessage "Opening WorkObjects as JSON in VS Code" -Level INFO
                    $appDataPath = Get-ApplicationDataPath
                    
                    if ($null -ne $primaryWorkObject) {
                        $file1 = Join-Path $appDataPath "exported_primary_work_object.json"
                        $primaryWorkObject | ConvertTo-Json -Depth 100 | Set-Content -Path $file1
                        Start-Process -FilePath $codeExecution -ArgumentList $file1 -WindowStyle Normal
                    }
                    
                    if ($null -ne $federatedWorkObject) {
                        $file2 = Join-Path $appDataPath "exported_federated_work_object.json"
                        $federatedWorkObject | ConvertTo-Json -Depth 100 | Set-Content -Path $file2
                        Start-Process -FilePath $codeExecution -ArgumentList $file2 -WindowStyle Normal
                    }
                }
                else {
                    Write-Host "VS Code not found" -ForegroundColor Red
                }
                
                Write-Host "Press any key to continue..."
                $null = $Host.UI.RawUI.ReadKey("NoEcho,IncludeKeyDown")
            }
            
            default {
                # Check if it's a category selection
                if ($categoryMap.ContainsKey($choice)) {
                    $selectedCategory = $categoryMap[$choice]
                    
                    Clear-Host
                    Show-MenuHeader -Title $selectedCategory.Category -LineLength 80
                    
                    Write-Host "Available Functions:" -ForegroundColor Yellow
                    for ($i = 0; $i -lt $selectedCategory.Functions.Count; $i++) {
                        $func = $selectedCategory.Functions[$i]
                        Write-Host "  [$($($i+1).ToString().PadLeft(2))] $($func.Name.PadRight(30)) - $($func.Description)" -ForegroundColor White
                    }
                    Write-Host "  [B] Back to main menu" -ForegroundColor Gray
                    Write-Host ""
                    Write-Host "TIP: Add '?' after a number (e.g., '4?') to view detailed synopsis" -ForegroundColor DarkGray
                    Write-Host ""
                    
                    $funcChoice = Read-Host "Select function"
                    
                    if ($funcChoice.ToUpper() -eq "B") {
                        continue
                    }
                    
                    
        
                    # Check if user requested synopsis for a category
                    if ($funcChoice.Contains('?') -or $funcChoice.ToLower().Contains('-h') -or $funcChoice.ToLower().Contains('--h')) {
                        $funcNumber = $funcChoice.Split(' ')[0].Trim()
                        $funcIndex = [int]$funcNumber - 1
                        $selectedFunction = $selectedCategory.Functions[$funcIndex]
                        $functionName = $selectedFunction.Name
                        if (-not [string]::IsNullOrEmpty($functionName)) {
                            Show-FunctionSynopsis -FunctionName $functionName 
                        }
                        continue
                    }
                  
                    
                    $funcIndex = [int]$funcChoice - 1
                    if ($funcIndex -ge 0 -and $funcIndex -lt $selectedCategory.Functions.Count) {
                        $selectedFunction = $selectedCategory.Functions[$funcIndex]
                        $functionName = $selectedFunction.Name

                        $selectedQuickMode = if ($null -ne $selectedFunction.QuickMode) { $selectedFunction.QuickMode } else { $false }
                        Write-Host ""
                        Write-Host "Executing: $($selectedFunction.Description)" -ForegroundColor Green
                        Write-Host ""
                        
                        # Get secondary parameters
                        $additionalParams = @{}
                        if ($selectedFunction.SecondaryParams.Count -gt 0) {
                            $additionalParams = Get-SecondaryParameters -SecondaryParamsDef $selectedFunction.SecondaryParams
                        }
                        
                        # Select target WorkObject(s)
                        $targets = Select-WorkObjectTarget -FunctionName $functionName -PrimaryWorkObject $primaryWorkObject -FederatedWorkObject $federatedWorkObject
                        
                        foreach ($target in $targets) {
                            if ($target -eq "PrimaryDb" -and $null -ne $primaryWorkObject) {
                                Write-Host "Executing on Primary Database..." -ForegroundColor Cyan
                                $primaryWorkObject = Invoke-WorkObjectFunction -FunctionName $functionName -WorkObject $primaryWorkObject -AdditionalParams $additionalParams -QuickMode:$selectedQuickMode
                                if ($primaryWorkObject -is [array]) { $primaryWorkObject = $primaryWorkObject[-1] }
                            }
                            elseif ($target -eq "FederatedDb" -and $null -ne $federatedWorkObject) {
                                Write-Host "Executing on Federated Database..." -ForegroundColor Cyan
                                $federatedWorkObject = Invoke-WorkObjectFunction -FunctionName $functionName -WorkObject $federatedWorkObject -AdditionalParams $additionalParams -QuickMode:$selectedQuickMode
                                if ($federatedWorkObject -is [array]) { $federatedWorkObject = $federatedWorkObject[-1] }
                            }
                        }
                        
                        Write-Host ""
                        Write-Host "Execution completed. Press any key to continue..." -ForegroundColor Green
                        $null = $Host.UI.RawUI.ReadKey("NoEcho,IncludeKeyDown")
                    }
                    else {
                        Write-Host "Invalid function selection" -ForegroundColor Red
                        Start-Sleep -Seconds 2
                    }
                }
                else {
                    Write-Host "Invalid choice. Please try again." -ForegroundColor Red
                    Start-Sleep -Seconds 2
                }
            }
        }
    }
    
    Write-LogMessage $(Get-InitScriptName) -Level JOB_COMPLETED
}
catch {
    Write-LogMessage "Error: $($_.Exception.Message)" -Level ERROR -Exception $_
    Write-LogMessage $(Get-InitScriptName) -Level JOB_FAILED
    Exit 9
}

