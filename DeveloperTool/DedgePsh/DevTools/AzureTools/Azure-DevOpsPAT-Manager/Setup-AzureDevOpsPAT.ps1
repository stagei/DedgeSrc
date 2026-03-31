<#
.SYNOPSIS
    Automated Azure DevOps Personal Access Token (PAT) setup and configuration

.DESCRIPTION
    This script guides you through creating a new Azure DevOps PAT and automatically
    saves it in a user-specific secure location. Each team member has their own
    isolated PAT storage.
    
    Features:
    1. Opens PAT creation page in browser
    2. Guides through PAT creation
    3. Securely accepts PAT input (hidden)
    4. Validates PAT works
    5. Saves to user-specific location
    6. Configures Azure CLI

.PARAMETER Email
    Your email address (auto-detected from username if not provided)

.PARAMETER Organization
    Azure DevOps organization name (default: Dedge)

.PARAMETER Project
    Azure DevOps project name (default: Dedge)

.PARAMETER SkipValidation
    Skip PAT validation step

.EXAMPLE
    .\Setup-AzureDevOpsPAT.ps1
    # Email auto-detected from $env:USERNAME

.EXAMPLE
    .\Setup-AzureDevOpsPAT.ps1 -Email "user@company.com"

.EXAMPLE
    .\Setup-AzureDevOpsPAT.ps1 -Organization "myorg" -Project "myproject"
#>

[CmdletBinding()]
param(
    [Parameter(Mandatory = $false)]
    [ValidatePattern('^\S+@\S+\.\S+$')]
    [string]$Email,
    
    [Parameter(Mandatory = $false)]
    [string]$Organization = "Dedge",
    
    [Parameter(Mandatory = $false)]
    [string]$Project = "Dedge",
    
    [switch]$SkipValidation
)

Import-Module GlobalFunctions -Force

#region Auto-detect User Information

# If email not provided, auto-detect based on $env:USERNAME
if ([string]::IsNullOrEmpty($Email)) {
    $Email = switch ($env:USERNAME) {
        "FKGEISTA" { "geir.helge.starholm@Dedge.no" }
        "FKSVEERI" { "svein.morten.erikstad@Dedge.no" }
        "FKMISTA"  { "mina.marie.starholm@Dedge.no" }
        "FKCELERI" { "Celine.Andreassen.Erikstad@Dedge.no" }
        default {
            Write-Host "⚠ Unknown username: $($env:USERNAME)" -ForegroundColor Yellow
            Write-Host "Please provide email with -Email parameter" -ForegroundColor Yellow
            throw "Email is required for unknown users"
        }
    }
    
    Write-Host "✓ Auto-detected email for $($env:USERNAME): $Email" -ForegroundColor Green
}

#endregion

#region Helper Functions

function Show-Banner {
    Write-Host "`n╔════════════════════════════════════════════════════════════════╗" -ForegroundColor Cyan
    Write-Host "║  Azure DevOps PAT Setup & Configuration Tool                  ║" -ForegroundColor Cyan
    Write-Host "╚════════════════════════════════════════════════════════════════╝" -ForegroundColor Cyan
    Write-Host "User:         $env:USERNAME" -ForegroundColor Gray
    Write-Host "Email:        $Email" -ForegroundColor Gray
    Write-Host "Organization: $Organization" -ForegroundColor Gray
    Write-Host "Project:      $Project`n" -ForegroundColor Gray
}

function Open-PATCreationPage {
    param([string]$Organization)
    
    $patUrl = "https://dev.azure.com/$Organization/_usersSettings/tokens"
    
    Write-Host "`n================================================================" -ForegroundColor Yellow
    Write-Host "  Step 1: Create Personal Access Token (PAT)" -ForegroundColor Yellow
    Write-Host "================================================================" -ForegroundColor Yellow
    
    Write-Host "`nOpening PAT creation page in your browser..." -ForegroundColor Green
    Write-Host "URL: $patUrl`n" -ForegroundColor Gray
    
    Write-Host "Please follow these steps in the browser:" -ForegroundColor Cyan
    Write-Host "  1. Click 'New Token' button" -ForegroundColor White
    Write-Host "  2. Enter a name (e.g., 'PowerShell Automation - Full Access')" -ForegroundColor White
    Write-Host "  3. Set expiration (recommend: 90 days or more)" -ForegroundColor White
    Write-Host "  4. Select scopes (REQUIRED for all features):" -ForegroundColor White
    Write-Host "     [x] Work Items: Read, Write and Manage" -ForegroundColor Green
    Write-Host "         (Create/update work items, add comments, attachments)" -ForegroundColor Gray
    Write-Host "     [x] Code: Read and Write" -ForegroundColor Green
    Write-Host "         (Read repositories, link code files)" -ForegroundColor Gray
    Write-Host "     [x] Packaging: Read and Write" -ForegroundColor Green
    Write-Host "         (Manage NuGet packages and artifacts)" -ForegroundColor Gray
    Write-Host "  5. Click 'Create'" -ForegroundColor White
    Write-Host "  6. IMPORTANT: Copy the token immediately (you won't see it again!)`n" -ForegroundColor Yellow
    
    Start-Process $patUrl
    
    Write-Host "Press any key after you've created and copied the PAT..." -ForegroundColor Cyan
    $null = $Host.UI.RawUI.ReadKey('NoEcho,IncludeKeyDown')
}

function Get-SecurePAT {
    Write-Host "`n================================================================" -ForegroundColor Yellow
    Write-Host "  Step 2: Enter Your New PAT Token" -ForegroundColor Yellow
    Write-Host "================================================================" -ForegroundColor Yellow
    
    Write-Host "`nPaste your PAT token (input will be hidden):" -ForegroundColor Cyan
    $securePAT = Read-Host -AsSecureString
    
    # Convert to plain text for validation and storage
    $BSTR = [System.Runtime.InteropServices.Marshal]::SecureStringToBSTR($securePAT)
    $plainPAT = [System.Runtime.InteropServices.Marshal]::PtrToStringAuto($BSTR)
    [System.Runtime.InteropServices.Marshal]::ZeroFreeBSTR($BSTR)
    
    if ([string]::IsNullOrWhiteSpace($plainPAT)) {
        throw "PAT token cannot be empty"
    }
    
    return $plainPAT
}

function Test-AzureDevOpsPAT {
    param(
        [string]$PAT,
        [string]$Organization,
        [string]$Project
    )
    
    Write-Host "`n================================================================" -ForegroundColor Yellow
    Write-Host "  Step 3: Validating PAT Token" -ForegroundColor Yellow
    Write-Host "================================================================" -ForegroundColor Yellow
    
    try {
        Write-Host "`nTesting PAT token..." -ForegroundColor Cyan
        
        # Build auth header
        $base64Auth = [Convert]::ToBase64String([Text.Encoding]::ASCII.GetBytes(":$PAT"))
        $headers = @{
            "Authorization" = "Basic $base64Auth"
            "Content-Type"  = "application/json"
        }
        
        # Test by getting project info
        $uri = "https://dev.azure.com/$Organization/_apis/projects/$Project`?api-version=7.0"
        
        $result = Invoke-RestMethod -Uri $uri -Method Get -Headers $headers -ErrorAction Stop
        
        if ($result.name -eq $Project) {
            Write-Host "✓ PAT token is valid!" -ForegroundColor Green
            Write-Host "✓ Successfully connected to project: $Project" -ForegroundColor Green
            return $true
        }
        else {
            Write-Host "✗ PAT token validation failed: Unexpected response" -ForegroundColor Red
            return $false
        }
    }
    catch {
        Write-Host "✗ PAT token validation failed!" -ForegroundColor Red
        Write-Host "Error: $($_.Exception.Message)" -ForegroundColor Red
        
        if ($_.Exception.Message -match '401') {
            Write-Host "`nPossible causes:" -ForegroundColor Yellow
            Write-Host "  • PAT token is invalid or expired" -ForegroundColor Gray
            Write-Host "  • PAT doesn't have required permissions" -ForegroundColor Gray
            Write-Host "  • Organization or project name is incorrect" -ForegroundColor Gray
        }
        
        return $false
    }
}

function Save-UserPATConfiguration {
    param(
        [string]$PAT,
        [string]$Organization,
        [string]$Project,
        [string]$Email
    )
    
    Write-Host "`n================================================================" -ForegroundColor Yellow
    Write-Host "  Step 4: Saving User-Specific Configuration" -ForegroundColor Yellow
    Write-Host "================================================================" -ForegroundColor Yellow
    
    try {
        # Create user-specific config directory
        $userConfigDir = Join-Path $env:OptPath "data\UserConfig\$env:USERNAME"
        
        if (-not (Test-Path $userConfigDir)) {
            Write-Host "`nCreating user config directory..." -ForegroundColor Cyan
            New-Item -ItemType Directory -Path $userConfigDir -Force | Out-Null
        }
        
        # User-specific PAT file
        $configFile = Join-Path $userConfigDir "AzureDevOpsPat.json"
        
        Write-Host "`nSaving configuration to user-specific location..." -ForegroundColor Cyan
        Write-Host "Location: $configFile" -ForegroundColor Gray
        
        # Create configuration object
        $config = @{
            Organization = $Organization
            Project      = $Project
            PAT          = $PAT
            LastUpdated  = (Get-Date).ToString("yyyy-MM-dd HH:mm:ss")
            UpdatedBy    = $env:USERNAME
            Email        = $Email
        }
        
        # Save configuration
        $config | ConvertTo-Json | Set-Content -Path $configFile -Encoding UTF8
        
        Write-Host "✓ Configuration saved successfully!" -ForegroundColor Green
        Write-Host "✓ PAT stored securely in user-specific location" -ForegroundColor Green
        
        # Update environment variable for current session
        $env:AZURE_DEVOPS_PAT = $PAT
        
        return $configFile
    }
    catch {
        Write-Host "✗ Failed to save configuration" -ForegroundColor Red
        Write-Host "Error: $($_.Exception.Message)" -ForegroundColor Red
        throw
    }
}

function Update-CommonConfigFile {
    param(
        [string]$PAT,
        [string]$Email,
        [string]$Organization,
        [string]$Project
    )
    
    Write-Host "`n================================================================" -ForegroundColor Yellow
    Write-Host "  Step 5: Update Common Config File (Service Account)" -ForegroundColor Yellow
    Write-Host "================================================================" -ForegroundColor Yellow
    
    $commonConfigPath = "C:\opt\src\DedgeSrc\DedgeSystemTools\Folders\DedgeCommon\Configfiles\GlobalSettings.json"
    
    Write-Host "`nService account detected: $Email" -ForegroundColor Cyan
    Write-Host "Common config file: $commonConfigPath" -ForegroundColor Gray
    Write-Host "`nThis will update ONLY the Pat field in GlobalSettings.json" -ForegroundColor White
    Write-Host "  • Pat: [new PAT token]" -ForegroundColor Gray
    Write-Host "  • PatComment: Privileges and expiry info" -ForegroundColor Gray
    Write-Host "`nOrganization, Project, and Repository fields will NOT be changed" -ForegroundColor Yellow
    
    # Get PAT privileges and expiry
    Write-Host "`nPlease provide PAT details for documentation:" -ForegroundColor Cyan
    Write-Host "Recommended: Work Items (RWM); Code (RW); Packaging (RW)" -ForegroundColor Gray
    $patPrivileges = Read-Host "PAT privileges (press Enter for recommended, or type custom)"
    
    if ([string]::IsNullOrWhiteSpace($patPrivileges)) {
        $patPrivileges = "Work Items (Read Write Manage); Code (Read Write); Packaging (Read Write)"
        Write-Host "Using recommended privileges" -ForegroundColor Green
    }
    
    $patExpiryDays = Read-Host "PAT expiry in days (default: 90, press Enter to accept)"
    if ([string]::IsNullOrWhiteSpace($patExpiryDays)) {
        $patExpiryDays = "90"
        Write-Host "Using 90 days expiry" -ForegroundColor Green
    }
    
    $response = Read-Host "`nDo you want to update the common config file? (y/n)"
    
    if ($response -ne 'y') {
        Write-Host "Skipping common config update" -ForegroundColor Yellow
        return $false
    }
    
    try {
        # Check if file exists
        if (-not (Test-Path $commonConfigPath)) {
            Write-Host "⚠ Common config file not found: $commonConfigPath" -ForegroundColor Yellow
            Write-Host "Skipping update" -ForegroundColor Gray
            return $false
        }
        
        Write-Host "`nReading common config file..." -ForegroundColor Cyan
        $commonConfig = Get-Content $commonConfigPath -Raw | ConvertFrom-Json
        
        # Create backup
        $backupPath = $commonConfigPath -replace '\.json$', "_backup_$(Get-Date -Format 'yyyyMMddHHmmss').json"
        Write-Host "Creating backup: $backupPath" -ForegroundColor Cyan
        Copy-Item $commonConfigPath $backupPath -Force
        
        # Update ONLY the Pat field and add metadata
        Write-Host "Updating Pat field in AzureDevOps section..." -ForegroundColor Cyan
        
        # Check if AzureDevOps section exists
        if (-not $commonConfig.PSObject.Properties['AzureDevOps']) {
            Write-Host "⚠ AzureDevOps section does not exist in GlobalSettings.json" -ForegroundColor Yellow
            Write-Host "Skipping update - please ensure AzureDevOps section exists first" -ForegroundColor Yellow
            return $false
        }
        
        # Update ONLY the Pat field
        if ($commonConfig.AzureDevOps.PSObject.Properties['Pat']) {
            $commonConfig.AzureDevOps.Pat = $PAT
        }
        else {
            $commonConfig.AzureDevOps | Add-Member -MemberType NoteProperty -Name 'Pat' -Value $PAT -Force
        }
        
        # Add or update PatComment
        $expiryDate = (Get-Date).AddDays([int]$patExpiryDays).ToString("yyyy-MM-dd")
        $patComment = "Privileges: $patPrivileges | Expires: $expiryDate | Updated: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss') by $env:USERNAME"
        
        if ($commonConfig.AzureDevOps.PSObject.Properties['PatComment']) {
            $commonConfig.AzureDevOps.PatComment = $patComment
        }
        else {
            $commonConfig.AzureDevOps | Add-Member -MemberType NoteProperty -Name 'PatComment' -Value $patComment -Force
        }
        
        # Save updated config
        Write-Host "Saving updated config..." -ForegroundColor Cyan
        $commonConfig | ConvertTo-Json -Depth 10 | Set-Content -Path $commonConfigPath -Encoding UTF8
        
        Write-Host "`n✓ Common config file updated successfully!" -ForegroundColor Green
        Write-Host "✓ Backup saved to: $backupPath" -ForegroundColor Green
        Write-Host "✓ Service account PAT is now available globally in GlobalSettings.json" -ForegroundColor Green
        Write-Host "`n  Fields updated:" -ForegroundColor Cyan
        Write-Host "    • Pat: [updated with new token]" -ForegroundColor White
        Write-Host "    • PatComment: $patComment" -ForegroundColor White
        Write-Host "`n  Fields unchanged (preserved):" -ForegroundColor Cyan
        Write-Host "    • Organization: $($commonConfig.AzureDevOps.Organization)" -ForegroundColor Gray
        Write-Host "    • Project: $($commonConfig.AzureDevOps.Project)" -ForegroundColor Gray
        Write-Host "    • Repository: $($commonConfig.AzureDevOps.Repository)" -ForegroundColor Gray
        
        return $true
    }
    catch {
        Write-Host "✗ Failed to update common config file" -ForegroundColor Red
        Write-Host "Error: $($_.Exception.Message)" -ForegroundColor Red
        Write-LogMessage "Failed to update common config: $($_.Exception.Message)" -Level ERROR -Exception $_
        return $false
    }
}

function Test-AzureCLI {
    Write-Host "`n================================================================" -ForegroundColor Yellow
    Write-Host "  Step 6: Configuring Azure CLI" -ForegroundColor Yellow
    Write-Host "================================================================" -ForegroundColor Yellow
    
    try {
        Write-Host "`nChecking Azure CLI installation..." -ForegroundColor Cyan
        
        $null = az --version 2>&1
        if ($LASTEXITCODE -ne 0) {
            Write-Host "⚠ Azure CLI not installed" -ForegroundColor Yellow
            Write-Host "Install with: winget install Microsoft.AzureCLI" -ForegroundColor Gray
            return $false
        }
        
        Write-Host "✓ Azure CLI is installed" -ForegroundColor Green
        
        # Check Azure DevOps extension
        Write-Host "Checking Azure DevOps extension..." -ForegroundColor Cyan
        $extensions = az extension list --output json 2>&1 | ConvertFrom-Json
        $devopsExt = $extensions | Where-Object { $_.name -eq 'azure-devops' }
        
        if (-not $devopsExt) {
            Write-Host "Installing Azure DevOps extension..." -ForegroundColor Yellow
            az extension add --name azure-devops --yes 2>&1 | Out-Null
            Write-Host "✓ Azure DevOps extension installed" -ForegroundColor Green
        }
        else {
            Write-Host "✓ Azure DevOps extension is installed" -ForegroundColor Green
        }
        
        # Configure Azure CLI with PAT
        Write-Host "Configuring Azure CLI..." -ForegroundColor Cyan
        $env:AZURE_DEVOPS_EXT_PAT = $PAT
        az devops configure --defaults organization="https://dev.azure.com/$Organization" project="$Project" --use-git-aliases true 2>&1 | Out-Null
        
        Write-Host "✓ Azure CLI configured successfully!" -ForegroundColor Green
        
        return $true
    }
    catch {
        Write-Host "⚠ Azure CLI configuration warning: $($_.Exception.Message)" -ForegroundColor Yellow
        return $false
    }
}

function Show-Summary {
    param(
        [string]$ConfigFile,
        [bool]$ValidationSuccess,
        [bool]$AzureCLIConfigured,
        [bool]$CommonConfigUpdated = $false
    )
    
    Write-Host "`n╔════════════════════════════════════════════════════════════════╗" -ForegroundColor Green
    Write-Host "║  Setup Complete!                                               ║" -ForegroundColor Green
    Write-Host "╚════════════════════════════════════════════════════════════════╝" -ForegroundColor Green
    
    Write-Host "`n✓ Configuration Summary:" -ForegroundColor Cyan
    Write-Host "  User:         $env:USERNAME" -ForegroundColor White
    Write-Host "  Email:        $Email" -ForegroundColor White
    Write-Host "  Organization: $Organization" -ForegroundColor White
    Write-Host "  Project:      $Project" -ForegroundColor White
    Write-Host "  Config File:  $ConfigFile" -ForegroundColor White
    
    Write-Host "`n✓ Status:" -ForegroundColor Cyan
    Write-Host "  PAT Validation:     $(if ($ValidationSuccess) { '✓ Passed' } else { '✗ Failed' })" -ForegroundColor $(if ($ValidationSuccess) { 'Green' } else { 'Red' })
    Write-Host "  Configuration:      ✓ Saved" -ForegroundColor Green
    Write-Host "  Common Config:      $(if ($CommonConfigUpdated) { '✓ Updated' } else { '⊝ N/A' })" -ForegroundColor $(if ($CommonConfigUpdated) { 'Green' } else { 'Gray' })
    Write-Host "  Azure CLI:          $(if ($AzureCLIConfigured) { '✓ Configured' } else { '⚠ Not configured' })" -ForegroundColor $(if ($AzureCLIConfigured) { 'Green' } else { 'Yellow' })
    
    if ($CommonConfigUpdated) {
        Write-Host "`n✓ Common Config (GlobalSettings.json):" -ForegroundColor Cyan
        Write-Host "  • Updated: C:\opt\src\DedgeSrc\DedgeSystemTools\Folders\DedgeCommon\Configfiles\GlobalSettings.json" -ForegroundColor White
        Write-Host "  • Service account PAT now available globally to all servers" -ForegroundColor White
        Write-Host "  • Backup created with timestamp" -ForegroundColor Gray
    }
    
    Write-Host "`n✓ Next Steps:" -ForegroundColor Cyan
    Write-Host "  1. Restart PowerShell to apply changes" -ForegroundColor White
    Write-Host "  2. Test with: /ado command in Cursor" -ForegroundColor White
    Write-Host "  3. Or test manually:" -ForegroundColor White
    Write-Host "     cd C:\opt\src\DedgePsh\DevTools\AdminTools\Azure-DevOpsUserStoryManager" -ForegroundColor Gray
    Write-Host "     .\Azure-DevOpsUserStoryManager.ps1 -WorkItemId 274033 -Action Get" -ForegroundColor Gray
    
    Write-Host "`n✓ PAT Token Security:" -ForegroundColor Cyan
    Write-Host "  • Token stored in user-specific location: $ConfigFile" -ForegroundColor Gray
    if ($CommonConfigUpdated) {
        Write-Host "  • Also stored in global common config for service account access" -ForegroundColor Gray
    }
    Write-Host "  • Isolated from other users" -ForegroundColor Gray
    Write-Host "  • Expires in: 90 days (or your selected duration)" -ForegroundColor Gray
    Write-Host "  • Re-run this script when token expires" -ForegroundColor Gray
    
    Write-Host "`n🎉 Azure DevOps is now configured and ready to use!`n" -ForegroundColor Green
}

#endregion

#region Main Execution

try {
    Show-Banner
    
    Write-LogMessage "Starting Azure DevOps PAT setup for $Email" -Level INFO
    
    # Step 1: Open PAT creation page
    Open-PATCreationPage -Organization $Organization
    
    # Step 2: Get PAT from user
    $PAT = Get-SecurePAT
    
    # Step 3: Validate PAT (unless skipped)
    $validationSuccess = $true
    if (-not $SkipValidation) {
        $validationSuccess = Test-AzureDevOpsPAT -PAT $PAT -Organization $Organization -Project $Project
        
        if (-not $validationSuccess) {
            $retry = Read-Host "`nDo you want to continue anyway? (y/n)"
            if ($retry -ne 'y') {
                throw "PAT validation failed. Please create a new PAT with correct permissions."
            }
        }
    }
    else {
        Write-Host "`n⚠ Skipping PAT validation (as requested)" -ForegroundColor Yellow
    }
    
    # Step 4: Save user-specific configuration
    $configFile = Save-UserPATConfiguration -PAT $PAT -Organization $Organization -Project $Project -Email $Email
    
    # Step 5: Check if service account and update common config if requested
    $commonConfigUpdated = $false
    if ($Email -ieq "srv_Dedge_repo@Dedge.onmicrosoft.com") {
        $commonConfigUpdated = Update-CommonConfigFile -PAT $PAT -Email $Email -Organization $Organization -Project $Project
    }
    
    # Step 6: Configure Azure CLI
    $azureCLIConfigured = Test-AzureCLI
    
    # Show summary
    Show-Summary -ConfigFile $configFile -ValidationSuccess $validationSuccess -AzureCLIConfigured $azureCLIConfigured -CommonConfigUpdated $commonConfigUpdated
    
    Write-LogMessage "Azure DevOps PAT setup completed successfully for $env:USERNAME" -Level INFO
}
catch {
    Write-Host "`n╔════════════════════════════════════════════════════════════════╗" -ForegroundColor Red
    Write-Host "║  Setup Failed!                                                 ║" -ForegroundColor Red
    Write-Host "╚════════════════════════════════════════════════════════════════╝" -ForegroundColor Red
    
    Write-Host "`nError: $($_.Exception.Message)" -ForegroundColor Red
    Write-LogMessage "Azure DevOps PAT setup failed: $($_.Exception.Message)" -Level ERROR -Exception $_
    
    Write-Host "`nTroubleshooting:" -ForegroundColor Yellow
    Write-Host "  1. Verify your email and organization are correct" -ForegroundColor Gray
    Write-Host "  2. Ensure PAT has required permissions (Work Items, Code, Packaging)" -ForegroundColor Gray
    Write-Host "  3. Check that organization and project names are correct" -ForegroundColor Gray
    Write-Host "  4. Try creating the PAT again" -ForegroundColor Gray
    
    exit 1
}

#endregion
