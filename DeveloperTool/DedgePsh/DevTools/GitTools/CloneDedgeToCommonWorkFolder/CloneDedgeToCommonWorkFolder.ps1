<#
.SYNOPSIS
    Clones Dedge and DedgePsh repositories to a common work folder.

.DESCRIPTION
    This script clones the Dedge and DedgePsh Azure DevOps repositories 
    to a local work folder for AutoDoc and other tools to use.
    
    Uses AzureFunctions module for credential management to enable 
    non-interactive Git operations with PAT authentication.
    
    Uses the same robust Git Credential Manager disabling approach
    as AzureDevOpsGitCheckIn.ps1 to prevent interactive dialogs.

.PARAMETER Force
    If specified, removes existing repositories before cloning.
    Otherwise, pulls latest changes if repositories exist.

.EXAMPLE
    .\CloneDedgeToCommonWorkFolder.ps1
    .\CloneDedgeToCommonWorkFolder.ps1 -Force
#>
param(
    [switch]$Force
)

# Import required modules
Import-Module GlobalFunctions -Force -ErrorAction Stop
Import-Module AzureFunctions -Force -ErrorAction Stop

# ============================================================================
# DISABLE GIT CREDENTIAL MANAGER - Prevent interactive dialogs
# ============================================================================
# GCM_INTERACTIVE=never - Prevents Git Credential Manager from showing UI dialogs
# GIT_TERMINAL_PROMPT=0 - Prevents git from prompting for credentials in terminal
# GIT_ASKPASS=echo - Provides a dummy askpass helper that returns empty credentials
# GCM_AUTHORITY= - Prevents GCM from using Windows authentication
# GCM_PROVIDER= - Prevents GCM from using any provider
# GCM_ALLOW_WINDOWSAUTH=0 - Disables Windows authentication in GCM
# GCM_CREDENTIAL_STORE=plaintext - Forces plaintext credential store
$env:GCM_INTERACTIVE = "never"
$env:GIT_TERMINAL_PROMPT = "0"
$env:GIT_ASKPASS = "echo"
$env:GCM_AUTHORITY = ""
$env:GCM_PROVIDER = ""
$env:GCM_ALLOW_WINDOWSAUTH = "0"
$env:GCM_CREDENTIAL_STORE = "plaintext"

# Also set for the current process and child processes
[System.Environment]::SetEnvironmentVariable("GCM_INTERACTIVE", "never", "Process")
[System.Environment]::SetEnvironmentVariable("GIT_TERMINAL_PROMPT", "0", "Process")
[System.Environment]::SetEnvironmentVariable("GIT_ASKPASS", "echo", "Process")
[System.Environment]::SetEnvironmentVariable("GCM_ALLOW_WINDOWSAUTH", "0", "Process")
[System.Environment]::SetEnvironmentVariable("GCM_CREDENTIAL_STORE", "plaintext", "Process")

# Kill any running Git Credential Manager processes that might show dialogs
Get-Process -Name "git-credential-manager*", "git-credential-manager-core*", "gcm*" -ErrorAction SilentlyContinue | Stop-Process -Force -ErrorAction SilentlyContinue

# Configuration
$workFolder = Join-Path $env:OptPath "work\DedgeRepository"
$DedgeFolder = Join-Path $workFolder "Dedge"
$DedgePshFolder = Join-Path $workFolder "DedgePsh"

# Repository URLs (base, without auth)
$repoBaseUrl = "dev.azure.com/Dedge/Dedge/_git"
$repositoryDedge = "Dedge"
$repositoryDedgePsh = "DedgePsh"

# Log folder
$global:logFolder = Join-Path $env:OptPath "data\AllPwshLog"

# Script-level variables for credentials (loaded from AzureAccessTokens.json)
$script:ServiceAccountEmail = $null
$script:ServiceAccountEmailEncoded = $null
$script:AzureDevOpsCredentials = $null

function Initialize-GitCredentials {
    <#
    .SYNOPSIS
        Configures Git credentials for non-interactive operations.
        Uses the same robust approach as AzureDevOpsGitCheckIn.ps1.
    #>
    param(
        [Parameter(Mandatory = $true)]
        [string]$Pat,
        
        [Parameter(Mandatory = $true)]
        [string]$Email
    )

    Write-LogMessage "Configuring Git credentials for non-interactive operation..." -Level INFO
    
    # Kill any running GCM processes before configuring
    Get-Process -Name "git-credential-manager*", "git-credential-manager-core*", "gcm*" -ErrorAction SilentlyContinue | Stop-Process -Force -ErrorAction SilentlyContinue
    
    # Ensure environment variables are set
    $env:GCM_INTERACTIVE = "never"
    $env:GIT_TERMINAL_PROMPT = "0"
    $env:GIT_ASKPASS = "echo"
    $env:GCM_ALLOW_WINDOWSAUTH = "0"
    $env:GCM_CREDENTIAL_STORE = "plaintext"
    
    # CRITICAL: Disable Git Credential Manager completely and use store helper only
    # First, unset any manager helpers that might be configured
    git config --global --unset-all credential.helper manager-core 2>$null | Out-Null
    git config --global --unset-all credential.helper manager 2>$null | Out-Null
    git config --global --unset-all credential.helper wincred 2>$null | Out-Null
    git config --global --unset-all credential.https://dev.azure.com.helper 2>$null | Out-Null
    git config --global --unset-all credential.https://*.visualstudio.com.helper 2>$null | Out-Null
    
    # Set store helper as the only credential helper
    git config --global credential.helper store 2>&1 | Out-Null
    git config --global credential.credentialStore plaintext 2>&1 | Out-Null
    git config --global credential.useHttpPath true 2>&1 | Out-Null
    
    # CRITICAL: Disable interactive credential prompts
    git config --global credential.interactive never 2>&1 | Out-Null
    
    # Disable Git Credential Manager for Azure DevOps specifically
    git config --global credential.https://dev.azure.com.interactive never 2>&1 | Out-Null
    git config --global credential.https://*.visualstudio.com.interactive never 2>&1 | Out-Null
    
    # Set user email and name for commits
    git config --global user.email $Email 2>&1 | Out-Null
    git config --global user.name $Email.Split('@')[0] 2>&1 | Out-Null

    # Write credentials to .git-credentials file
    $gitCredentialsPath = Join-Path $env:USERPROFILE ".git-credentials"
    $emailEncoded = $Email.Replace('@', '%40')
    
    # Remove duplicate Azure DevOps entries if they exist (both domains)
    if (Test-Path $gitCredentialsPath) {
        $existingCreds = Get-Content $gitCredentialsPath -ErrorAction SilentlyContinue | Where-Object { 
            $_ -notlike "*dev.azure.com*" -and $_ -notlike "*visualstudio.com*" 
        }
        if ($existingCreds) {
            $existingCreds | Set-Content $gitCredentialsPath
        }
        else {
            Set-Content $gitCredentialsPath -Value ""
        }
    }
    
    # Add credentials for both Azure DevOps domains
    $credContentDev = "https://$($emailEncoded):$Pat@dev.azure.com"
    $credContentVS = "https://$($emailEncoded):$Pat@Dedge.visualstudio.com"
    
    Add-Content -Path $gitCredentialsPath -Value $credContentDev
    Add-Content -Path $gitCredentialsPath -Value $credContentVS
    
    Write-LogMessage "Git credentials configured in $gitCredentialsPath" -Level DEBUG
    Write-LogMessage "Git credentials configured successfully" -Level INFO
}

function Restore-GitCredentialManager {
    <#
    .SYNOPSIS
        Restores Git Credential Manager to normal operation after automated execution.
    #>
    
    Write-LogMessage "Restoring Git Credential Manager to normal operation..." -Level INFO
    
    try {
        # Remove the store helper restriction
        git config --global --unset-all credential.helper store 2>$null | Out-Null
        
        # Re-enable manager-core as the credential helper
        git config --global credential.helper manager-core 2>$null | Out-Null
        
        # Remove interactive restrictions
        git config --global --unset-all credential.interactive 2>$null | Out-Null
        git config --global --unset-all credential.https://dev.azure.com.interactive 2>$null | Out-Null
        git config --global --unset-all credential.https://*.visualstudio.com.interactive 2>$null | Out-Null
        
        # Remove plaintext credential store setting
        git config --global --unset-all credential.credentialStore 2>$null | Out-Null
        
        # Clear environment variables (they will reset on next session anyway)
        Remove-Item Env:\GCM_INTERACTIVE -ErrorAction SilentlyContinue
        Remove-Item Env:\GIT_TERMINAL_PROMPT -ErrorAction SilentlyContinue
        Remove-Item Env:\GIT_ASKPASS -ErrorAction SilentlyContinue
        Remove-Item Env:\GCM_ALLOW_WINDOWSAUTH -ErrorAction SilentlyContinue
        Remove-Item Env:\GCM_CREDENTIAL_STORE -ErrorAction SilentlyContinue
        
        Write-LogMessage "Git Credential Manager restored successfully" -Level INFO
        return $true
    }
    catch {
        Write-LogMessage "Warning: Failed to fully restore Git Credential Manager: $($_.Exception.Message)" -Level WARN
        return $false
    }
}

function Get-AuthenticatedRepoUrl {
    <#
    .SYNOPSIS
        Constructs an authenticated Git URL with embedded PAT.
    #>
    param(
        [Parameter(Mandatory = $true)]
        [string]$RepoName,
        
        [Parameter(Mandatory = $true)]
        [string]$Pat,
        
        [Parameter(Mandatory = $true)]
        [string]$Email
    )

    $emailEncoded = $Email.Replace('@', '%40')
    return "https://$($emailEncoded):$Pat@$repoBaseUrl/$RepoName"
}

function Stop-ProcessesInFolder {
    <#
    .SYNOPSIS
        Stops processes that have files open in the specified folder.
    #>
    param(
        [Parameter(Mandatory = $true)]
        [string]$FolderPath
    )

    try {
        $processes = Get-Process -ErrorAction SilentlyContinue | Where-Object { 
            $_.Path -like "$FolderPath*" -or $_.Path -like "*DSWIN.EXE"
        }

        foreach ($process in $processes) {
            Write-LogMessage "Stopping process: $($process.Name) (PID: $($process.Id))" -Level WARN
            Stop-Process -Id $process.Id -Force -ErrorAction SilentlyContinue
        }
    }
    catch {
        Write-LogMessage "Error stopping processes: $($_.Exception.Message)" -Level WARN -Exception $_
    }
}

function Remove-FolderWithRetry {
    <#
    .SYNOPSIS
        Removes a folder with retry logic for locked files.
    #>
    param(
        [Parameter(Mandatory = $true)]
        [string]$FolderPath,
        
        [int]$MaxRetries = 3
    )

    if (-not (Test-Path $FolderPath)) {
        return $true
    }

    for ($i = 1; $i -le $MaxRetries; $i++) {
        try {
            Write-LogMessage "Attempting to remove folder: $FolderPath (attempt $i of $MaxRetries)" -Level INFO
            
            # Use robocopy trick to remove locked files
            $emptyDir = Join-Path $env:TEMP "EmptyDir_$(Get-Random)"
            New-Item -Path $emptyDir -ItemType Directory -Force | Out-Null
            
            robocopy $emptyDir $FolderPath /MIR /R:1 /W:1 /NJH /NJS /NFL /NDL /NC /NS 2>&1 | Out-Null
            Remove-Item -Path $emptyDir -Force -ErrorAction SilentlyContinue
            Remove-Item -Path $FolderPath -Recurse -Force -ErrorAction Stop
            
            Write-LogMessage "Successfully removed folder: $FolderPath" -Level INFO
            return $true
        }
        catch {
            Write-LogMessage "Failed to remove folder (attempt $i): $($_.Exception.Message)" -Level WARN
            if ($i -lt $MaxRetries) {
                Start-Sleep -Seconds 2
                Stop-ProcessesInFolder -FolderPath $FolderPath
            }
        }
    }

    Write-LogMessage "Failed to remove folder after $MaxRetries attempts: $FolderPath" -Level ERROR
    return $false
}

function Clone-Repository {
    <#
    .SYNOPSIS
        Clones or updates a Git repository.
    #>
    param(
        [Parameter(Mandatory = $true)]
        [string]$RepoUrl,
        
        [Parameter(Mandatory = $true)]
        [string]$TargetFolder,
        
        [Parameter(Mandatory = $true)]
        [string]$RepoName,
        
        [switch]$ForceClone
    )

    $gitFolder = Join-Path $TargetFolder ".git"
    $repoExists = Test-Path $gitFolder

    if ($repoExists -and -not $ForceClone) {
        # Repository exists, pull latest changes
        Write-LogMessage "Repository $RepoName exists, pulling latest changes..." -Level INFO
        
        Push-Location $TargetFolder
        try {
            # Reset and clean
            git reset --hard HEAD 2>&1 | Out-Null
            git clean -fd 2>&1 | Out-Null
            
            # Pull latest
            $pullResult = git pull 2>&1
            if ($LASTEXITCODE -eq 0) {
                Write-LogMessage "Successfully pulled latest changes for $RepoName" -Level INFO
                return $true
            }
            else {
                Write-LogMessage "Git pull failed: $pullResult" -Level WARN
                Write-LogMessage "Will attempt fresh clone..." -Level INFO
                Pop-Location
                $ForceClone = $true
            }
        }
        catch {
            Write-LogMessage "Error during git pull: $($_.Exception.Message)" -Level WARN -Exception $_
            Pop-Location
            $ForceClone = $true
        }
        finally {
            if ((Get-Location).Path -eq $TargetFolder) {
                Pop-Location
            }
        }
    }

    if ($ForceClone -or -not $repoExists) {
        # Remove existing folder if present
        if (Test-Path $TargetFolder) {
            $removed = Remove-FolderWithRetry -FolderPath $TargetFolder
            if (-not $removed) {
                return $false
            }
        }

        # Create parent directory
        $parentDir = Split-Path $TargetFolder -Parent
        if (-not (Test-Path $parentDir)) {
            New-Item -Path $parentDir -ItemType Directory -Force | Out-Null
        }

        # Clone repository
        Write-LogMessage "Cloning repository $RepoName to $TargetFolder" -Level INFO
        
        $cloneResult = git clone $RepoUrl $TargetFolder 2>&1
        if ($LASTEXITCODE -eq 0) {
            Write-LogMessage "Successfully cloned $RepoName" -Level INFO
            return $true
        }
        else {
            Write-LogMessage "Git clone failed: $cloneResult" -Level ERROR
            return $false
        }
    }

    return $true
}

# ============================================================================
# MAIN EXECUTION
# ============================================================================

try {
    Write-LogMessage "========================================" -Level INFO
    Write-LogMessage "Starting CloneDedgeToCommonWorkFolder" -Level INFO
    Write-LogMessage "Work folder: $workFolder" -Level INFO
    Write-LogMessage "Force mode: $Force" -Level INFO
    Write-LogMessage "========================================" -Level INFO

    # CRITICAL: Ensure Git Credential Manager is disabled BEFORE any git operations
    Write-LogMessage "Disabling Git Credential Manager to prevent interactive dialogs..." -Level INFO
    
    # Kill any running GCM processes first
    Get-Process -Name "git-credential-manager*", "git-credential-manager-core*", "gcm*" -ErrorAction SilentlyContinue | Stop-Process -Force -ErrorAction SilentlyContinue
    
    # Set environment variables again (in case they were reset)
    $env:GCM_INTERACTIVE = "never"
    $env:GIT_TERMINAL_PROMPT = "0"
    $env:GIT_ASKPASS = "echo"
    $env:GCM_ALLOW_WINDOWSAUTH = "0"
    $env:GCM_CREDENTIAL_STORE = "plaintext"
    [System.Environment]::SetEnvironmentVariable("GCM_INTERACTIVE", "never", "Process")
    [System.Environment]::SetEnvironmentVariable("GIT_TERMINAL_PROMPT", "0", "Process")
    [System.Environment]::SetEnvironmentVariable("GIT_ASKPASS", "echo", "Process")
    [System.Environment]::SetEnvironmentVariable("GCM_ALLOW_WINDOWSAUTH", "0", "Process")
    [System.Environment]::SetEnvironmentVariable("GCM_CREDENTIAL_STORE", "plaintext", "Process")
    
    # Disable interactive prompts via git config
    git config --global credential.interactive never 2>$null | Out-Null
    git config --global credential.https://dev.azure.com.interactive never 2>$null | Out-Null
    git config --global credential.https://*.visualstudio.com.interactive never 2>$null | Out-Null
    
    # Unset any manager helpers that might trigger GCM
    git config --global --unset-all credential.helper manager-core 2>$null | Out-Null
    git config --global --unset-all credential.helper manager 2>$null | Out-Null
    git config --global --unset-all credential.helper wincred 2>$null | Out-Null
    
    # Ensure store helper is set as the ONLY helper
    git config --global credential.helper store 2>$null | Out-Null
    git config --global credential.credentialStore plaintext 2>$null | Out-Null
    
    Write-LogMessage "Git Credential Manager disabled successfully" -Level INFO

    # Get Azure DevOps credentials - use same pattern as AzureDevOpsGitCheckIn.ps1
    Write-LogMessage "Loading Azure DevOps credentials from AzureAccessTokens.json..." -Level INFO
    $script:AzureDevOpsCredentials = Get-AzureDevOpsCredentials -IdLike '*AzureDevOpsExtPat*'

    if (-not $script:AzureDevOpsCredentials.Success) {
        # Fallback to default credentials if specific token not found
        Write-LogMessage "AzureDevOpsExtPat not found, trying default credentials..." -Level WARN
        $script:AzureDevOpsCredentials = Get-AzureDevOpsCredentials -PromptForMissing:$false
    }

    if (-not $script:AzureDevOpsCredentials.Success) {
        Write-LogMessage "Failed to retrieve Azure DevOps credentials: $($script:AzureDevOpsCredentials.ErrorMessage)" -Level ERROR
        Write-LogMessage "Please ensure AzureAccessTokens.json is configured with a valid PAT" -Level ERROR
        Write-LogMessage "Run: Import-Module AzureFunctions; Get-AzureAccessTokenSummary" -Level INFO
        Restore-GitCredentialManager
        exit 1
    }

    # Set script-level variables from loaded credentials
    $script:ServiceAccountEmail = $script:AzureDevOpsCredentials.Email
    $script:ServiceAccountEmailEncoded = $script:AzureDevOpsCredentials.EmailEncoded
    
    Write-LogMessage "Credentials loaded for: $($script:AzureDevOpsCredentials.Email)" -Level INFO
    Write-LogMessage "Token ID: $($script:AzureDevOpsCredentials.Id)" -Level DEBUG

    # Test PAT validity
    Write-LogMessage "Testing PAT validity..." -Level INFO
    $patTest = Test-AzureDevOpsPat -Pat $script:AzureDevOpsCredentials.Pat -Organization "Dedge"
    if (-not $patTest.Success) {
        Write-LogMessage "PAT validation failed: $($patTest.ErrorMessage)" -Level ERROR
        Write-LogMessage "Please update your PAT in AzureAccessTokens.json" -Level ERROR
        Restore-GitCredentialManager
        exit 1
    }
    Write-LogMessage "PAT is valid (HTTP $($patTest.StatusCode))" -Level INFO

    # Configure Git credentials
    Initialize-GitCredentials -Pat $script:AzureDevOpsCredentials.Pat -Email $script:AzureDevOpsCredentials.Email

    # Stop processes that might lock files
    Stop-ProcessesInFolder -FolderPath $workFolder

    # Create work folder if needed
    if (-not (Test-Path $workFolder)) {
        New-Item -Path $workFolder -ItemType Directory -Force | Out-Null
        Write-LogMessage "Created work folder: $workFolder" -Level INFO
    }

    # Build authenticated URLs
    $authUrlDedge = Get-AuthenticatedRepoUrl -RepoName $repositoryDedge -Pat $script:AzureDevOpsCredentials.Pat -Email $script:AzureDevOpsCredentials.Email
    $authUrlDedgePsh = Get-AuthenticatedRepoUrl -RepoName $repositoryDedgePsh -Pat $script:AzureDevOpsCredentials.Pat -Email $script:AzureDevOpsCredentials.Email

    # Clone/update Dedge repository
    Write-LogMessage "Processing Dedge repository..." -Level INFO
    $DedgeResult = Clone-Repository -RepoUrl $authUrlDedge -TargetFolder $DedgeFolder -RepoName "Dedge" -ForceClone:$Force

    if (-not $DedgeResult) {
        Write-LogMessage "Failed to clone/update Dedge repository" -Level ERROR
        Restore-GitCredentialManager
        exit 1
    }

    # Clone/update DedgePsh repository
    Write-LogMessage "Processing DedgePsh repository..." -Level INFO
    $DedgePshResult = Clone-Repository -RepoUrl $authUrlDedgePsh -TargetFolder $DedgePshFolder -RepoName "DedgePsh" -ForceClone:$Force

    if (-not $DedgePshResult) {
        Write-LogMessage "Failed to clone/update DedgePsh repository" -Level ERROR
        Restore-GitCredentialManager
        exit 1
    }

    # Summary
    Write-LogMessage "========================================" -Level INFO
    Write-LogMessage "CloneDedgeToCommonWorkFolder completed successfully" -Level INFO
    Write-LogMessage "Dedge folder: $DedgeFolder" -Level INFO
    Write-LogMessage "DedgePsh folder: $DedgePshFolder" -Level INFO
    Write-LogMessage "========================================" -Level INFO

    # Restore Git Credential Manager for normal user operations
    Restore-GitCredentialManager
    
    # Return success
    exit 0
}
catch {
    Write-LogMessage "CloneDedgeToCommonWorkFolder failed: $($_.Exception.Message)" -Level ERROR -Exception $_
    
    # Restore Git Credential Manager even on failure
    Restore-GitCredentialManager
    
    exit 1
}