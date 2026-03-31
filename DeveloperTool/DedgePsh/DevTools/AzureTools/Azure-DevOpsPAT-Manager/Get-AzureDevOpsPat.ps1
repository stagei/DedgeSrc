<#
.SYNOPSIS
    Functions for retrieving Azure DevOps PAT from user-specific storage

.DESCRIPTION
    These functions should be copied into GlobalFunctions.psm1 to enable
    automatic PAT loading from user-specific storage locations.
    
    Each user has their PAT stored in:
    C:\opt\data\UserConfig\{USERNAME}\AzureDevOpsPat.json

.NOTES
    Add these functions to GlobalFunctions.psm1 near other Azure DevOps functions
#>

function Get-CurrentUserConfig {
    <#
    .SYNOPSIS
    Gets configuration for the current logged-in user
    
    .DESCRIPTION
    Returns user-specific configuration (email, SMS, full name) based on $env:USERNAME
    
    .OUTPUTS
    PSCustomObject with Username, FullName, Email, SmsNumber
    #>
    
    $username = $env:USERNAME
    
    $userConfig = switch ($username) {
        "FKGEISTA" {
            [PSCustomObject]@{
                Username  = "FKGEISTA"
                FullName  = "Geir Helge Starholm"
                Email     = "geir.helge.starholm@Dedge.no"
                SmsNumber = "+4797188358"
            }
        }
        "FKSVEERI" {
            [PSCustomObject]@{
                Username  = "FKSVEERI"
                FullName  = "Svein Morten Erikstad"
                Email     = "svein.morten.erikstad@Dedge.no"
                SmsNumber = "+4795762742"
            }
        }
        "FKMISTA" {
            [PSCustomObject]@{
                Username  = "FKMISTA"
                FullName  = "Mina Marie Starholm"
                Email     = "mina.marie.starholm@Dedge.no"
                SmsNumber = "+4799348397"
            }
        }
        "FKCELERI" {
            [PSCustomObject]@{
                Username  = "FKCELERI"
                FullName  = "Celine Andreassen Erikstad"
                Email     = "Celine.Andreassen.Erikstad@Dedge.no"
                SmsNumber = "+4745269945"
            }
        }
        default {
            Write-LogMessage "Unknown username: $username, using default configuration" -Level WARN
            [PSCustomObject]@{
                Username  = $username
                FullName  = "Unknown User"
                Email     = "geir.helge.starholm@Dedge.no"
                SmsNumber = "+4797188358"
            }
        }
    }
    
    return $userConfig
}

function Get-CurrentUserEmail {
    <#
    .SYNOPSIS
    Gets email address for the current user
    #>
    $userConfig = Get-CurrentUserConfig
    return $userConfig.Email
}

function Get-CurrentUserSms {
    <#
    .SYNOPSIS
    Gets SMS number for the current user
    #>
    $userConfig = Get-CurrentUserConfig
    return $userConfig.SmsNumber
}

function Get-CurrentUserFullName {
    <#
    .SYNOPSIS
    Gets full name for the current user
    #>
    $userConfig = Get-CurrentUserConfig
    return $userConfig.FullName
}

function Get-AzureDevOpsPatConfigFile {
    <#
    .SYNOPSIS
    Gets the path to the user-specific Azure DevOps PAT configuration file
    
    .DESCRIPTION
    Returns: C:\opt\data\UserConfig\{USERNAME}\AzureDevOpsPat.json
    #>
    try {
        $username = $env:USERNAME
        $userConfigDir = Join-Path $env:OptPath "data\UserConfig\$username"
        $configFile = Join-Path $userConfigDir "AzureDevOpsPat.json"
        
        return $configFile
    }
    catch {
        Write-LogMessage "Failed to get PAT config file path: $($_.Exception.Message)" -Level WARN
        return $null
    }
}

function Test-AzureDevOpsPatConfigured {
    <#
    .SYNOPSIS
    Checks if current user has Azure DevOps PAT configured
    #>
    $configFile = Get-AzureDevOpsPatConfigFile
    return ($configFile -and (Test-Path $configFile))
}

function Get-AzureDevOpsStoredConfig {
    <#
    .SYNOPSIS
    Retrieves stored Azure DevOps configuration for current user
    #>
    try {
        $configFile = Get-AzureDevOpsPatConfigFile
        
        if ($configFile -and (Test-Path $configFile)) {
            $config = Get-Content $configFile -Raw | ConvertFrom-Json
            return $config
        }
        
        return $null
    }
    catch {
        Write-LogMessage "Failed to read Azure DevOps config: $($_.Exception.Message)" -Level WARN
        return $null
    }
}

function Get-AzureDevOpsPat {
    <#
    .SYNOPSIS
    Gets the Azure DevOps Personal Access Token for current user
    
    .DESCRIPTION
    Retrieves PAT from: C:\opt\data\UserConfig\{USERNAME}\AzureDevOpsPat.json
    If file doesn't exist, prompts user to run setup.
    
    .PARAMETER Silent
    If specified, doesn't prompt user, just throws error
    #>
    [CmdletBinding()]
    param(
        [switch]$Silent
    )
    
    $isConfigured = Test-AzureDevOpsPatConfigured
    
    if (-not $isConfigured) {
        $username = $env:USERNAME
        $configFile = Get-AzureDevOpsPatConfigFile
        
        if ($Silent) {
            throw "Azure DevOps PAT not configured for user $username. Expected location: $configFile"
        }
        
        Write-Host "`n⚠️  Azure DevOps PAT Not Configured" -ForegroundColor Yellow
        Write-Host "═══════════════════════════════════════════" -ForegroundColor Yellow
        Write-Host "User:     $username" -ForegroundColor Gray
        Write-Host "Expected: $configFile" -ForegroundColor Gray
        Write-Host "`nPAT file does not exist for your user." -ForegroundColor White
        
        Write-Host "`n📋 To set up Azure DevOps integration:" -ForegroundColor Cyan
        Write-Host "   cd C:\opt\src\DedgePsh\DevTools\AdminTools\Azure-DevOpsPAT-Manager" -ForegroundColor Gray
        Write-Host "   .\Setup-AzureDevOpsPAT.ps1" -ForegroundColor Green
        
        $response = Read-Host "`nWould you like to run the setup now? (y/n)"
        
        if ($response -eq 'y') {
            Write-Host "`nLaunching PAT setup..." -ForegroundColor Green
            $setupScript = Join-Path $env:OptPath "src\DedgePsh\DevTools\AdminTools\Azure-DevOpsPAT-Manager\Setup-AzureDevOpsPAT.ps1"
            
            if (Test-Path $setupScript) {
                & $setupScript
                
                # Try to get PAT again after setup
                $storedConfig = Get-AzureDevOpsStoredConfig
                if ($storedConfig -and $storedConfig.PAT) {
                    return $storedConfig.PAT
                }
            }
            else {
                Write-Host "Setup script not found: $setupScript" -ForegroundColor Red
            }
        }
        
        throw "Azure DevOps PAT not configured for user $username"
    }
    
    # Get from stored config
    $storedConfig = Get-AzureDevOpsStoredConfig
    if ($storedConfig -and $storedConfig.PAT) {
        return $storedConfig.PAT
    }
    
    # Fallback to environment variable
    if ($env:AZURE_DEVOPS_PAT) {
        return $env:AZURE_DEVOPS_PAT
    }
    
    throw "Azure DevOps PAT not found in configuration file"
}

function Get-AzureDevOpsOrganization {
    <#
    .SYNOPSIS
    Gets the Azure DevOps organization name
    #>
    $storedConfig = Get-AzureDevOpsStoredConfig
    if ($storedConfig -and $storedConfig.Organization) {
        return $storedConfig.Organization
    }
    return "Dedge"
}

function Get-AzureDevOpsProject {
    <#
    .SYNOPSIS
    Gets the Azure DevOps project name
    #>
    $storedConfig = Get-AzureDevOpsStoredConfig
    if ($storedConfig -and $storedConfig.Project) {
        return $storedConfig.Project
    }
    return "Dedge"
}

function Get-AzureDevOpsRepository {
    <#
    .SYNOPSIS
    Gets the Azure DevOps repository name
    #>
    $storedConfig = Get-AzureDevOpsStoredConfig
    if ($storedConfig -and $storedConfig.Repository) {
        return $storedConfig.Repository
    }
    return "DedgePsh"
}

function Test-AzureDevOpsConfig {
    <#
    .SYNOPSIS
    Tests if Azure DevOps configuration is valid
    #>
    try {
        $org = Get-AzureDevOpsOrganization
        $project = Get-AzureDevOpsProject
        $pat = Get-AzureDevOpsPat -Silent
        
        if ([string]::IsNullOrWhiteSpace($org) -or 
            [string]::IsNullOrWhiteSpace($project) -or 
            [string]::IsNullOrWhiteSpace($pat)) {
            return $false
        }
        
        $base64Auth = [Convert]::ToBase64String([Text.Encoding]::ASCII.GetBytes(":$pat"))
        $headers = @{
            "Authorization" = "Basic $base64Auth"
        }
        
        $uri = "https://dev.azure.com/$org/_apis/projects/$project`?api-version=7.0"
        $result = Invoke-RestMethod -Uri $uri -Method Get -Headers $headers -ErrorAction Stop
        
        return ($result.name -eq $project)
    }
    catch {
        Write-LogMessage "Azure DevOps configuration test failed: $($_.Exception.Message)" -Level WARN
        return $false
    }
}

function Show-AzureDevOpsConfig {
    <#
    .SYNOPSIS
    Displays current Azure DevOps configuration for current user
    #>
    Write-Host "`n═══ Azure DevOps Configuration ═══" -ForegroundColor Cyan
    
    try {
        $username = $env:USERNAME
        $configFile = Get-AzureDevOpsPatConfigFile
        $isConfigured = Test-AzureDevOpsPatConfigured
        
        Write-Host "Current User:       " -NoNewline -ForegroundColor Yellow
        Write-Host $username -ForegroundColor White
        
        Write-Host "Config File:        " -NoNewline -ForegroundColor Yellow
        Write-Host $configFile -ForegroundColor Gray
        
        if ($isConfigured) {
            $storedConfig = Get-AzureDevOpsStoredConfig
            
            Write-Host "Status:             " -NoNewline -ForegroundColor Yellow
            Write-Host "✓ Configured" -ForegroundColor Green
            
            Write-Host "`nConfiguration Details:" -ForegroundColor Cyan
            Write-Host "  Organization:     " -NoNewline -ForegroundColor Yellow
            Write-Host $storedConfig.Organization -ForegroundColor White
            
            Write-Host "  Project:          " -NoNewline -ForegroundColor Yellow
            Write-Host $storedConfig.Project -ForegroundColor White
            
            Write-Host "  Email:            " -NoNewline -ForegroundColor Yellow
            Write-Host $storedConfig.Email -ForegroundColor White
            
            Write-Host "  PAT Configured:   " -NoNewline -ForegroundColor Yellow
            Write-Host $(if ($storedConfig.PAT) { "Yes" } else { "No" }) -ForegroundColor $(if ($storedConfig.PAT) { "Green" } else { "Red" })
            
            Write-Host "  Last Updated:     " -NoNewline -ForegroundColor Yellow
            Write-Host $storedConfig.LastUpdated -ForegroundColor White
            
            Write-Host "  Updated By:       " -NoNewline -ForegroundColor Yellow
            Write-Host $storedConfig.UpdatedBy -ForegroundColor White
            
            Write-Host "`nTesting connection..." -ForegroundColor Cyan
            $isValid = Test-AzureDevOpsConfig
            
            Write-Host "Connection Status:  " -NoNewline -ForegroundColor Yellow
            if ($isValid) {
                Write-Host "✓ Connected" -ForegroundColor Green
            }
            else {
                Write-Host "✗ Failed" -ForegroundColor Red
                Write-Host "  PAT may be expired. Run Setup-AzureDevOpsPAT.ps1 to update." -ForegroundColor Yellow
            }
        }
        else {
            Write-Host "Status:             " -NoNewline -ForegroundColor Yellow
            Write-Host "✗ Not Configured" -ForegroundColor Red
            
            Write-Host "`n⚠️  PAT file does not exist for user: $username" -ForegroundColor Yellow
            Write-Host "`nTo configure Azure DevOps:" -ForegroundColor Cyan
            Write-Host "  cd C:\opt\src\DedgePsh\DevTools\AdminTools\Azure-DevOpsPAT-Manager" -ForegroundColor Gray
            Write-Host "  .\Setup-AzureDevOpsPAT.ps1" -ForegroundColor Green
        }
    }
    catch {
        Write-Host "Error: $($_.Exception.Message)" -ForegroundColor Red
    }
    
    Write-Host "═══════════════════════════════════`n" -ForegroundColor Cyan
}

<#
.NOTES
Copy these functions to GlobalFunctions.psm1:

- Get-CurrentUserConfig
- Get-CurrentUserEmail
- Get-CurrentUserSms
- Get-CurrentUserFullName
- Get-AzureDevOpsPatConfigFile
- Test-AzureDevOpsPatConfigured
- Get-AzureDevOpsStoredConfig
- Get-AzureDevOpsPat
- Get-AzureDevOpsOrganization
- Get-AzureDevOpsProject
- Get-AzureDevOpsRepository
- Test-AzureDevOpsConfig
- Show-AzureDevOpsConfig

Then add to Export-ModuleMember at the end of GlobalFunctions.psm1
#>
