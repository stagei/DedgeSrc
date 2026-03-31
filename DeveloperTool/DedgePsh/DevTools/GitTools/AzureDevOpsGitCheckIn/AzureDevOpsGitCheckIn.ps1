# Author: Geir Helge Starholm, Dedge AS
# Title: Azure DevOps Git Check-In Automation
# Description: Copies5 files from development to Azure DevOps repo with validation
param(
    [Parameter(Mandatory = $false)]
    [int]$StopHour = 23
)
Import-Module -Name GlobalFunctions -Force
Import-Module -Name Infrastructure -Force
Import-Module -Name Db2-Handler -Force
Import-Module -Name AzureFunctions -Force

# Disable Git Credential Manager interactive prompts to prevent dialogs during automated execution
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

$appdataPath = Get-ApplicationDataPath
Set-OverrideAppDataFolder -Path $appdataPath

# Initialize comprehensive WorkObject for tracking execution
$script:WorkObject = [PSCustomObject]@{
    # Job Information
    Name                      = "AzureDevOpsGitCheckIn"
    Description               = "Azure DevOps Git Check-In Automation"
    ScriptPath                = $PSCommandPath
    ExecutionTimestamp        = Get-Date -Format 'yyyy-MM-dd HH:mm:ss'
    ExecutionUser             = "$env:USERDOMAIN\$env:USERNAME"
    ComputerName              = $env:COMPUTERNAME
    
    # Execution Status (Success property at top level for easy access)
    Success                   = $false
    Status                    = "Running"
    OverallSuccess            = $false
    ErrorMessage              = $null
    
    # Configuration
    Organization              = $null
    Project                   = $null
    Repository                = $null
    GitFolders                = $null
    
    # Execution Phases
    NetworkPathsValidated     = $false
    FoldersInitialized        = $false
    CobdokModulesRetrieved    = $false
    GitRepoInitialized        = $false
    SourceFilesCopied         = $false
    FilesProcessed            = $false
    ChangesCommitted          = $false
    ChangesPushed             = $false
    
    # Statistics
    TotalFilesCopied          = 0
    TotalFilesExcluded        = 0
    TotalFilesInRepo          = 0
    ExcludedFilesDetails      = @()
    
    # Timing
    StartTime                 = Get-Date
    EndTime                   = $null
    Duration                  = $null
    LastSuccessfulRun         = $null
    
    # Script and Output Tracking
    ScriptArray               = @()
    
    # Results
    CommitMessage             = $null
    CommitHash                = $null
    PushResult                = $null
}


# Import required modules
$ErrorActionPreference = "Stop"
try {
    Import-Module -Name OdbcHandler -Force
}
catch {
    Write-LogMessage "Failed to import OdbcHandler module" -Level Error -Exception $_
    exit 1
}
try {
    Import-Module -Name FKASendSMSDirect -Force
}
catch {
    Write-LogMessage "Failed to import FKASendSMSDirect module" -Level Error -Exception $_
    exit 1
}
try {
    Import-Module -Name Export-Array -Force
}
catch {
    Write-LogMessage "Failed to import Export-Array module" -Level Error -Exception $_
}

# Service account configuration - will be loaded from AzureAccessTokens.json
# These script-level variables are set after loading credentials from Get-AzureDevOpsCredentials
$script:ServiceAccountEmail = $null
$script:ServiceAccountEmailEncoded = $null
$script:AzureDevOpsCredentials = $null  # Holds the full credential object

# Configuration
$config = @{
    Organization = "Dedge"
    Project      = "Dedge"
    Repository   = "Dedge"
    Pat          = $null  # Will be loaded from AzureAccessTokens.json via Get-AzureDevOpsCredentials
    GitFolders   = @{
        # COBOL source files
        cbl                  = @{
            Sources = @(
                @{
                    Path   = "\\DEDGE.fk.no\erputv\Utvikling\fkavd\nt"
                    Filter = @("*.cbl", "*.md")
                }
            )
        }
        # Copy files
        cpy                  = @{
            Sources = @(
                @{
                    Path   = "\\DEDGE.fk.no\erputv\Utvikling\fkavd\nt"
                    Filter = @("*.cpy", "*.cpb")
                }
            )
        }
        # System copy files
        "sys\cpy"            = @{
            Sources = @(
                @{
                    Path   = "\\DEDGE.fk.no\erputv\Utvikling\fkavd\Sys\cpy"
                    Filter = @("*.cpy", "*.dcl", "*.cpx")
                }
            )
        }
        # GS files
        gs                   = @{
            Sources = @(
                @{
                    Path   = "\\DEDGE.fk.no\erputv\Utvikling\fkavd\nt"
                    Filter = "*.gs"
                }
            )
        }
        # Import files
        imp                  = @{
            Sources = @(
                @{
                    Path   = "\\DEDGE.fk.no\erputv\Utvikling\fkavd\nt"
                    Filter = "*.imp"
                }
            )
        }
        # REXX files
        rexx                 = @{
            Sources = @(
                @{
                    Path   = "\\DEDGE.fk.no\erputv\Utvikling\fkavd\nt"
                    Filter = "*.rex"
                }
            )
        }
        rexx_prod            = @{
            Sources = @(
                @{
                    Path   = "\\DEDGE.fk.no\erpprog\cobnt"
                    Filter = "*.rex"
                }
            )
        }
        # Batch files
        bat                  = @{
            Sources = @(
                @{
                    Path   = "\\DEDGE.fk.no\erputv\Utvikling\fkavd\nt"
                    Filter = @("*.bat", "*.cmd")
                }
            )
        }
        bat_prod             = @{
            Sources = @(
                @{
                    Path   = "\\DEDGE.fk.no\erpprog\cobnt"
                    Filter = "*.bat"
                }
            )
        }
        # SQL files
        sql                  = @{
            Sources = @(
                @{
                    Path   = "\\DEDGE.fk.no\erputv\Utvikling\fkavd\sql"
                    Filter = @("*.cre", "*.sql", "*.ins")
                }
            )
        }
        "sql\CDS"            = @{
            Sources = @(
                @{
                    Path   = "\\DEDGE.fk.no\erputv\Utvikling\fkavd\sql\CDS"
                    Filter = "*.*"
                }
            )
        }
        sql_prod             = @{
            Sources = @(
                @{
                    Path   = "\\DEDGE.fk.no\erpprog\cobnt\sql"
                    Filter = "*.sql"
                }
            )
        }
        # TILTP logs
        tiltp                = @{
            Sources = @(
                @{
                    Path   = "\\DEDGE.fk.no\erputv\Utvikling\fkavd\nt\TILTP"
                    Filter = "*.log"
                }
            )
        }
        # Scheduled Tasks
        ExportScheduledTasks = @{
            Sources = @(
                @{
                    Path      = "\\p-no1fkmprd-app\opt\data\ScheduledTasksExport"
                    Filter    = "*.xml"
                    Recursive = $true
                }
            )
        }
    }
}
Add-Member -InputObject $script:WorkObject -MemberType NoteProperty -Name "Organization" -Value $config.Organization -Force
Add-Member -InputObject $script:WorkObject -MemberType NoteProperty -Name "Project" -Value $config.Project -Force
Add-Member -InputObject $script:WorkObject -MemberType NoteProperty -Name "Repository" -Value $config.Repository -Force
Add-Member -InputObject $script:WorkObject -MemberType NoteProperty -Name "GitFolders" -Value $config.GitFolders -Force

function Initialize-GitCredentials {
    <#
    .SYNOPSIS
        Configures git credentials to prevent interactive dialogs during automated execution.
    
    .DESCRIPTION
        Sets up git credential store with the Azure DevOps PAT and disables
        interactive credential prompts to ensure the script runs unattended.
    #>
    param(
        [Parameter(Mandatory = $true)]
        [string]$Pat
    )
    
    Write-LogMessage "Configuring git credentials for automated execution..." -Level INFO
    
    # DEBUG: Log authentication details before credential configuration
    Write-LogMessage "DEBUG - Credential Configuration:" -Level DEBUG
    Write-LogMessage "  Service Account Email: $($script:ServiceAccountEmail)" -Level DEBUG
    Write-LogMessage "  Service Account Email (URL-encoded): $($script:ServiceAccountEmailEncoded)" -Level DEBUG
    Write-LogMessage "  PAT (first 10 chars): $($Pat.Substring(0, [Math]::Min(10, $Pat.Length)))..." -Level DEBUG
    
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
    git config --global credential.helper store | Out-Null
    git config --global credential.credentialStore plaintext | Out-Null
    git config --global credential.useHttpPath true | Out-Null
    
    # CRITICAL: Disable interactive credential prompts
    git config --global credential.interactive never | Out-Null
    
    # Disable Git Credential Manager for Azure DevOps specifically
    git config --global credential.https://dev.azure.com.interactive never | Out-Null
    git config --global credential.https://*.visualstudio.com.interactive never | Out-Null
    
    # Ensure credentials file exists and contains our PAT
    # Format: https://username:PAT@domain
    # For Azure DevOps, use the service account email (URL-encoded) with PAT as password
    $credFile = "$env:USERPROFILE\.git-credentials"
    # Use script-level constant for service account email (URL-encoded)
    $serviceEmail = $script:ServiceAccountEmailEncoded
    # Store credentials for BOTH domains (dev.azure.com and visualstudio.com)
    $credContentDev = "https://$($serviceEmail):$($Pat)@dev.azure.com"
    $credContentVS = "https://$($serviceEmail):$($Pat)@Dedge.visualstudio.com"
    
    Write-LogMessage "DEBUG - Storing credentials for domains:" -Level DEBUG
    Write-LogMessage "  dev.azure.com: https://$($serviceEmail):***@dev.azure.com" -Level DEBUG
    Write-LogMessage "  visualstudio.com: https://$($serviceEmail):***@Dedge.visualstudio.com" -Level DEBUG
    
    # Remove duplicate Azure DevOps entries if they exist (both domains)
    if (Test-Path $credFile) {
        $existingCreds = Get-Content $credFile -ErrorAction SilentlyContinue | Where-Object { 
            $_ -notlike "*dev.azure.com*" -and $_ -notlike "*visualstudio.com*" 
        }
        if ($existingCreds) {
            $existingCreds | Set-Content $credFile
        }
        else {
            # File exists but no non-Azure creds, clear it
            Set-Content $credFile -Value ""
        }
    }
    
    # Add our PAT credentials for both domains
    Add-Content -Path $credFile -Value $credContentDev
    Add-Content -Path $credFile -Value $credContentVS
    
    # Configure git user identity using script-level constant
    git config --global user.name "Dedge AzureDevOpsGitCheckIn" | Out-Null
    git config --global user.email $script:ServiceAccountEmail | Out-Null
    
    Write-LogMessage "DEBUG - Git user identity configured:" -Level DEBUG
    Write-LogMessage "  user.name: Dedge AzureDevOpsGitCheckIn" -Level DEBUG
    Write-LogMessage "  user.email: $($script:ServiceAccountEmail)" -Level DEBUG
    
    Write-LogMessage "Git credentials configured successfully" -Level INFO
}

function Restore-GitCredentialManager {
    <#
    .SYNOPSIS
        Restores Git Credential Manager to normal operation after automated execution.
    
    .DESCRIPTION
        Re-enables Git Credential Manager by restoring manager-core helper
        and removing the restrictions that were set for automated execution.
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

function Test-NetworkPaths {
    Write-LogMessage "Validating network paths..." -Level INFO
    $validationResults = @()
    $allValid = $true
    
    # Check all source paths from GitFolders configuration
    foreach ($folder in $config.GitFolders.GetEnumerator()) {
        foreach ($source in $folder.Value.Sources) {
            $isValid = Test-Path $source.Path
            $validationResults += "Path: $($source.Path) - $(if($isValid){'✓ Accessible'}else{'✗ NOT Accessible'})"
            
            if (-not $isValid) {
                $allValid = $false
                Write-LogMessage "Network path NOT accessible: $($source.Path)" -Level ERROR
                throw "Required network path not accessible: $($source.Path)"
            }
            else {
                Write-LogMessage "Network path accessible: $($source.Path)" -Level DEBUG
            }
        }
    }
    
    $script:WorkObject.NetworkPathsValidated = $allValid
    $script:WorkObject = Add-ScriptAndOutputToWorkObject -WorkObject $script:WorkObject -Name "Test-NetworkPaths" -Script "Network path validation" -Output ($validationResults -join "`n")
    
    Write-LogMessage "All network paths validated successfully" -Level INFO
}

function Initialize-Folders {
    Write-LogMessage "Initializing folders..." -Level INFO
    $basePath = "$env:OptPath\data\AzureDevOpsGitCheckIn"
    $folderResults = @()

    # Define only the base required paths
    $paths = @(
        $basePath,
        "$basePath\gitrepo",
        "$basePath\log",
        "$basePath\tmp",
        "$basePath\cobdok"
    )

    # Create base paths
    foreach ($path in $paths) {
        if (-not (Test-Path $path -PathType Container)) {
            Add-Folder -Path $path -AdditionalAdmins @("$env:USERDOMAIN\ACL_ERPUTV_Utvikling_Full", "$env:USERDOMAIN\ACL_Dedge_Servere_Utviklere")
            $folderResults += "Created: $path"
            Write-LogMessage "Created directory: $path" -Level INFO
        }
        else {
            $folderResults += "Exists: $path"
            Write-LogMessage "Directory already exists: $path" -Level DEBUG
        }
    }
    
    $script:WorkObject.FoldersInitialized = $true
    $script:WorkObject = Add-ScriptAndOutputToWorkObject -WorkObject $script:WorkObject -Name "Initialize-Folders" -Script "Folder initialization" -Output ($folderResults -join "`n")
}

function Get-CobdokModules {
    param(
        [string]$cobdokFolder = "$env:OptPath\data\AzureDevOpsGitCheckIn\cobdok"
    )

    Write-LogMessage "Retrieving module data from COBDOK..." -Level INFO
    # Import and process the module data
    try {
        $query = "SELECT * FROM dbm.modul"
        $modules = Get-QueryResultDirect -RemoteDatabaseName "COBDOK" -Query $query
        $excludedFiles = $modules | Where-Object { $_.system -and $_.system.Contains("UTGATT") }

        Write-LogMessage "Found $($excludedFiles.Count) excluded files based on UTGATT in COBDOK" -Level INFO
        
        $outputDetails = @(
            "Query: $query",
            "Total modules retrieved: $($modules.Count)",
            "Modules marked as UTGATT: $($excludedFiles.Count)"
        )
        
        $script:WorkObject.CobdokModulesRetrieved = $true
        $script:WorkObject = Add-ScriptAndOutputToWorkObject -WorkObject $script:WorkObject -Name "Get-CobdokModules" -Script $query -Output ($outputDetails -join "`n")
        
        return $excludedFiles
    }
    catch {
        Write-LogMessage "Failed to process module data from COBDOK" -Level Error -Exception $_
        $script:WorkObject = Add-ScriptAndOutputToWorkObject -WorkObject $script:WorkObject -Name "Get-CobdokModules" -Script "COBDOK query" -Output "ERROR: $($_.Exception.Message)"
        throw
    }
}

function Test-CblFileCount {
    param (
        [string]$repoPath,
        [int]$minimumFiles = 1000
    )

    Write-LogMessage "Checking CBL file count in repository..." -Level INFO
    $cblFiles = Get-ChildItem -Path (Join-Path $repoPath "cbl") -Filter "*.CBL" -File
    $fileCount = ($cblFiles | Measure-Object).Count

    Write-LogMessage "Found $fileCount CBL files in repository" -Level INFO
    return $fileCount -ge $minimumFiles
}

function Get-LatestFileDate {
    param (
        [string]$repoPath
    )

    Write-LogMessage "Checking latest file date in repository..." -Level INFO

    try {
        $latestFile = Get-ChildItem -Path $repoPath -Recurse -File -Include "*.bat", "*.cbl", "*.gs", "*.imp", "*.cpb", "*.cpx", "*.dcl", "*.cpy", "*.rex" | Sort-Object LastWriteTime -Descending | Select-Object -First 1

        if ($latestFile) {
            Write-LogMessage "Latest file found: $($latestFile.Name) - $($latestFile.LastWriteTime)" -Level INFO
            $adjustedDate = $latestFile.LastWriteTime.AddDays(-1)
            Write-LogMessage "Using adjusted date: $adjustedDate (1 day earlier to ensure coverage)" -Level INFO
            return $adjustedDate
        }
    }
    catch {
        Write-LogMessage "Error checking latest file date" -Level Error -Exception $_
        return $null
    }

    Write-LogMessage "No files found in repository" -Level WARN
    return $null
}

function Copy-SourceFiles {
    param (
        [Parameter(Mandatory = $true)]
        [string]$targetRoot,
        [Parameter(Mandatory = $true)]
        [array]$allFiltersFromConfig,
        [Parameter(Mandatory = $true)]
        [bool]$fullClonePerformed
    )

    Write-LogMessage "Starting source file copy..." -Level INFO
    $copyResults = @()
    $totalFilesCopied = 0
    
    # Get latest file date from repository
    $latestFileDate = Get-LatestFileDate -repoPath $targetRoot
    $copyResults += "Latest file date in repo: $latestFileDate"

    $maxAge = $null  # Default to null (copy all files)

    if ($latestFileDate -and -not $fullClonePerformed) {
        $daysSinceLatest = [math]::Ceiling(((Get-Date) - $latestFileDate).TotalDays)
        $maxAge = "/MAXAGE:$daysSinceLatest"
        $copyResults += "Using incremental copy with MAXAGE: $daysSinceLatest days"
        Write-LogMessage "Using maxAge of $daysSinceLatest days based on latest file date (adjusted): $latestFileDate" -Level INFO
    }
    else {
        $copyResults += "Using full copy (no age restriction)"
        Write-LogMessage "No reference date found. Copying all files without maxAge filter" -Level INFO
    }

    # Process each destination folder
    foreach ($folder in $config.GitFolders.GetEnumerator()) {
        $targetFolder = Join-Path $targetRoot $folder.Key

        # Create target folder if it doesn't exist
        if (-not (Test-Path $targetFolder -PathType Container)) {
            Write-LogMessage "Creating target folder: $targetFolder" -Level INFO
            Add-Folder -Path $targetFolder -AdditionalAdmins @("$env:USERDOMAIN\ACL_ERPUTV_Utvikling_Full", "$env:USERDOMAIN\ACL_Dedge_Servere_Utviklere")
        }

        foreach ($source in $folder.Value.Sources) {
            # Handle multiple filters if specified
            $filters = $source.Filter
            if ($filters -isnot [array]) { $filters = @($filters) }

            foreach ($filter in $filters) {
                $robocopyArgs = @(
                    $source.Path
                    $targetFolder
                    $filter
                    "/NFL"   # No file liste
                    "/NDL"   # No directory list
                    "/NJH"   # No job header
                    "/NJS"   # No job summary
                    "/NC"    # No class
                    "/NS"    # No size
                    "/NP"    # No progress
                )
                Write-LogMessage "Max age: $(if ($null -eq $maxAge) { '<null>' } else { $maxAge })" -Level INFO
                if (-not [string]::IsNullOrEmpty($maxAge)) {
                    $robocopyArgs += $maxAge
                }

                if ($source.Recursive) {
                    $robocopyArgs += "/S"
                }

                Write-LogMessage "Copying $filter from $($source.Path) to $targetFolder $(if($null -ne $maxAge){"with maxAge filter"}else{"without age restriction"})" -Level INFO
                # foreach ($arg in $robocopyArgs) {
                #     Write-LogMessage "Robocopy argument: $arg" -Level INFO
                # }
                $robocopyArgs = $robocopyArgs -join " "
                Write-LogMessage "Robocopy arguments: $robocopyArgs" -Level INFO
                $result = Start-Process robocopy -ArgumentList $robocopyArgs -NoNewWindow -Wait -PassThru
                #Write-LogMessage "Robocopy result: $result" -Level INFO

                if ($result.ExitCode -gt 7) {
                    Write-LogMessage "Robocopy failed with exit code $($result.ExitCode) when copying $filter" -Level ERROR
                    $copyResults += "ERROR: Robocopy failed for $filter with exit code $($result.ExitCode)"
                    throw "Robocopy failed with exit code $($result.ExitCode) when copying $filter"
                }
                else {
                    $copyResults += "Copied $filter from $($source.Path) to $targetFolder (Exit code: $($result.ExitCode))"
                    if ($result.ExitCode -gt 0) {
                        $totalFilesCopied++
                    }
                }
            }
        }
    }
    
    $script:WorkObject.SourceFilesCopied = $true
    $script:WorkObject.TotalFilesCopied = $totalFilesCopied
    $script:WorkObject = Add-ScriptAndOutputToWorkObject -WorkObject $script:WorkObject -Name "Copy-SourceFiles" -Script "Robocopy operations" -Output ($copyResults -join "`n")
    
    Write-LogMessage "Source file copy completed. Folders processed: $($config.GitFolders.Count)" -Level INFO
}

function Initialize-GitRepo {
    param (
        [string]$repoPath,
        [string]$repoUrl,
        [string]$pat
    )

    Write-LogMessage "Initializing Git repository at $repoPath" -Level INFO
    $gitInitResults = @()
    $gitInitResults += "Repository path: $repoPath"
    $gitInitResults += "Repository URL: $repoUrl"
    $gitCommands = @()

    # Configure git credentials for automated execution
    Initialize-GitCredentials -Pat $pat
    
    # Track credential configuration commands
    $gitCommands += "git config --global credential.helper store"
    $gitCommands += "git config --global credential.credentialStore plaintext"
    $gitCommands += "git config --global user.name 'Dedge AzureDevOpsGitCheckIn'"
    $gitCommands += "git config --global user.email '$($script:ServiceAccountEmail)'"
    
    # Construct authenticated URL with PAT embedded for clone operations
    # Use script-level constant for service account email (URL-encoded)
    $serviceEmail = $script:ServiceAccountEmailEncoded
    
    # DEBUG: Log authentication details before clone/fetch operations
    Write-LogMessage "DEBUG - Git Repository Authentication:" -Level DEBUG
    Write-LogMessage "  Repository URL: $repoUrl" -Level DEBUG
    Write-LogMessage "  Service Account Email: $($script:ServiceAccountEmail)" -Level DEBUG
    Write-LogMessage "  Service Account Email (URL-encoded): $serviceEmail" -Level DEBUG
    Write-LogMessage "  PAT (first 10 chars): $($pat.Substring(0, [Math]::Min(10, $pat.Length)))..." -Level DEBUG
    
    $authenticatedUrl = $repoUrl
    if ($repoUrl -match '^https://([^\.]+)\.visualstudio\.com/(.+)$') {
        # visualstudio.com format - use service email with PAT
        $orgName = $matches[1]
        $path = $matches[2]
        $authenticatedUrl = "https://$($serviceEmail):$($pat)@$orgName.visualstudio.com/$path"
        Write-LogMessage "Using authenticated visualstudio.com URL format with service account email" -Level INFO
        
        # Also prepare dev.azure.com format as fallback (stored for potential future use)
        $pathNoCollection = $path -replace '^DefaultCollection/', ''
        $script:authenticatedUrlDev = "https://$($serviceEmail):$($pat)@dev.azure.com/$orgName/$pathNoCollection"
        Write-LogMessage "Alternative dev.azure.com format available as fallback" -Level DEBUG
    }
    elseif ($repoUrl -match '^https://dev\.azure\.com/([^/]+)/(.+)$') {
        # dev.azure.com format - use service email with PAT
        $orgName = $matches[1]
        $path = $matches[2]
        $authenticatedUrl = "https://$($serviceEmail):$($pat)@dev.azure.com/$orgName/$path"
        Write-LogMessage "Using authenticated dev.azure.com URL format with service account email" -Level INFO
    }
    else {
        Write-LogMessage "Warning: Could not parse repository URL format: $repoUrl" -Level WARN
        Write-LogMessage "Attempting to inject PAT into original URL format" -Level WARN
        # Fallback: try to inject PAT into existing URL with service email
        if ($repoUrl -match '^https://([^/]+)(.+)$') {
            $hostname = $matches[1]
            $path = $matches[2]
            $authenticatedUrl = "https://$($serviceEmail):$($pat)@$hostname$path"
            Write-LogMessage "Using fallback authenticated URL format with service account email" -Level WARN
        }
    }
    
    # Ensure we're starting in a known location
    $parentDir = Split-Path $repoPath -Parent
    if (-not (Test-Path $parentDir)) {
        New-Item -ItemType Directory -Path $parentDir -Force | Out-Null
        Write-LogMessage "Created parent directory: $parentDir" -Level INFO
    }
    Set-Location $parentDir

    # Configure safe directory first
    $safeDirPath = $repoPath.Replace('\', '/')
    Write-LogMessage "Configuring safe directory: $safeDirPath" -Level INFO
    $safeDirOutput = git config --global --add safe.directory $safeDirPath 2>&1
    $gitCommands += "git config --global --add safe.directory $safeDirPath"
    $gitInitResults += "Safe directory config: Exit code $LASTEXITCODE, Output: $($safeDirOutput -join ' ')"

    # Check if directory exists and is a git repo
    $isGitRepo = Test-Path (Join-Path $repoPath ".git")
    $fullClonePerformed = $false
    if ($isGitRepo) {
        Write-LogMessage "Existing repository found. Resetting..." -Level INFO
        Set-Location $repoPath

        try {
            # Reset any pending changes
            $resetOutput = git reset --hard 2>&1
            $gitCommands += "git reset --hard"
            $gitInitResults += "Reset --hard: Exit code $LASTEXITCODE, Output: $($resetOutput -join ' ')"
            if ($LASTEXITCODE -ne 0) {
                Write-LogMessage "Git reset failed: $($resetOutput -join ' ')" -Level WARN
            }
            
            $cleanOutput = git clean -fd 2>&1
            $gitCommands += "git clean -fd"
            $gitInitResults += "Clean -fd: Exit code $LASTEXITCODE, Output: $($cleanOutput -join ' ')"
            if ($LASTEXITCODE -ne 0) {
                Write-LogMessage "Git clean failed: $($cleanOutput -join ' ')" -Level WARN
            }

            # Fetch latest and reset to origin/master
            $fetchOutput = git fetch origin 2>&1
            $gitCommands += "git fetch origin"
            $gitInitResults += "Fetch origin: Exit code $LASTEXITCODE, Output: $($fetchOutput -join ' ')"
            if ($LASTEXITCODE -ne 0) {
                Write-LogMessage "Git fetch failed with exit code: $LASTEXITCODE" -Level ERROR
                Write-LogMessage "Fetch output: $($fetchOutput -join "`n")" -Level ERROR
                throw "Git fetch failed: $($fetchOutput -join ' ')"
            }
            
            $resetOutput = git reset --hard origin/master 2>&1
            $gitCommands += "git reset --hard origin/master"
            $gitInitResults += "Reset --hard origin/master: Exit code $LASTEXITCODE, Output: $($resetOutput -join ' ')"
            if ($LASTEXITCODE -ne 0) {
                Write-LogMessage "Git reset to origin/master failed: $($resetOutput -join ' ')" -Level WARN
            }
            
            $cleanOutput = git clean -fd 2>&1
            $gitCommands += "git clean -fd (after reset)"
            $gitInitResults += "Clean -fd (after reset): Exit code $LASTEXITCODE, Output: $($cleanOutput -join ' ')"
            if ($LASTEXITCODE -ne 0) {
                Write-LogMessage "Git clean after reset failed: $($cleanOutput -join ' ')" -Level WARN
            }
        }
        catch {
            Write-LogMessage "Failed to reset existing repository" -Level ERROR -Exception $_
            Write-LogMessage "Removing existing repository..." -Level INFO

            # Move back up before removing
            Set-Location (Split-Path $repoPath -Parent) | Out-Null

            # Remove existing directory with retry logic
            if (Test-Path $repoPath) {
                $maxRetries = 3
                $retryCount = 0
                $removed = $false
                while ($retryCount -lt $maxRetries -and -not $removed) {
                    try {
                        Get-Process -Name "git" -ErrorAction SilentlyContinue | Stop-Process -Force -ErrorAction SilentlyContinue
                        Start-Sleep -Seconds 1
                        Remove-Item -Path $repoPath -Recurse -Force -ErrorAction Stop
                        $removed = $true
                    }
                    catch {
                        $retryCount++
                        if ($retryCount -lt $maxRetries) {
                            try {
                                $emptyDir = Join-Path $env:TEMP "EmptyDir_$(Get-Random)"
                                New-Item -ItemType Directory -Path $emptyDir -Force | Out-Null
                                robocopy $emptyDir $repoPath /MIR /R:0 /W:0 /NFL /NDL /NJH /NJS | Out-Null
                                Remove-Item -Path $repoPath -Force -ErrorAction Stop
                                Remove-Item -Path $emptyDir -Force -ErrorAction SilentlyContinue
                                $removed = $true
                            }
                            catch {
                                Start-Sleep -Seconds 2
                            }
                        }
                        else {
                            Write-LogMessage "Could not remove repository folder, but continuing" -Level WARN
                        }
                    }
                }
            }

            # Fresh clone with authenticated URL
            Write-LogMessage "Performing fresh clone..." -Level INFO
            $cloneTarget = Split-Path $repoPath -Leaf
            $cloneCmd = "git clone $authenticatedUrl $cloneTarget"
            $gitCommands += $cloneCmd
            $cloneOutput = git clone $authenticatedUrl $cloneTarget 2>&1
            $gitInitResults += "Clone (retry): Exit code $LASTEXITCODE, Output: $($cloneOutput -join ' ')"
            if ($LASTEXITCODE -ne 0) {
                Write-LogMessage "Git clone failed with exit code: $LASTEXITCODE" -Level ERROR
                Write-LogMessage "Clone output: $($cloneOutput -join "`n")" -Level ERROR
                throw "Git clone failed: $($cloneOutput -join ' ')"
            }
            Write-LogMessage "Clone completed successfully" -Level INFO
            $fullClonePerformed = $true
        }
    }
    else {
        Write-LogMessage "No valid git repository found. Performing fresh clone..." -Level INFO

        # Remove existing directory with retry logic
        if (Test-Path $repoPath) {
            $maxRetries = 3
            $retryCount = 0
            $removed = $false
            while ($retryCount -lt $maxRetries -and -not $removed) {
                try {
                    # Kill any git processes that might be locking files
                    Get-Process -Name "git" -ErrorAction SilentlyContinue | Stop-Process -Force -ErrorAction SilentlyContinue
                    Start-Sleep -Seconds 1
                    Remove-Item -Path $repoPath -Recurse -Force -ErrorAction Stop
                    $removed = $true
                }
                catch {
                    $retryCount++
                    if ($retryCount -lt $maxRetries) {
                        Write-LogMessage "Failed to remove repository folder (attempt $retryCount/$maxRetries), trying robocopy method..." -Level WARN
                        try {
                            $emptyDir = Join-Path $env:TEMP "EmptyDir_$(Get-Random)"
                            New-Item -ItemType Directory -Path $emptyDir -Force | Out-Null
                            robocopy $emptyDir $repoPath /MIR /R:0 /W:0 /NFL /NDL /NJH /NJS | Out-Null
                            Remove-Item -Path $repoPath -Force -ErrorAction Stop
                            Remove-Item -Path $emptyDir -Force -ErrorAction SilentlyContinue
                            $removed = $true
                            Write-LogMessage "Successfully removed repository folder using robocopy" -Level INFO
                        }
                        catch {
                            if ($retryCount -lt $maxRetries) {
                                Write-LogMessage "Robocopy method also failed, retrying in 2 seconds..." -Level WARN
                                Start-Sleep -Seconds 2
                            }
                        }
                    }
                    else {
                        Write-LogMessage "Failed to remove repository folder after $maxRetries attempts, but continuing - git clone may overwrite" -Level WARN
                        # Don't throw - let git clone attempt to proceed
                    }
                }
            }
        }

        # Clone the repository with authenticated URL
        Write-LogMessage "Cloning repository from $repoUrl..." -Level INFO
        $cloneTarget = Split-Path $repoPath -Leaf
        $cloneCmd = "git clone $authenticatedUrl $cloneTarget"
        $gitCommands += $cloneCmd
        $cloneOutput = git clone $authenticatedUrl $cloneTarget 2>&1
        $gitInitResults += "Clone: Exit code $LASTEXITCODE, Output: $($cloneOutput -join ' ')"
        if ($LASTEXITCODE -ne 0) {
            Write-LogMessage "Git clone failed with exit code: $LASTEXITCODE" -Level ERROR
            Write-LogMessage "Clone output: $($cloneOutput -join "`n")" -Level ERROR
            throw "Git clone failed: $($cloneOutput -join ' ')"
        }
        Write-LogMessage "Clone completed successfully" -Level INFO
        $fullClonePerformed = $true
    }

    # Verify repository
    if (-not (Test-Path (Join-Path $repoPath ".git"))) {
        Write-LogMessage "Repository verification failed. Expected .git folder at: $(Join-Path $repoPath '.git')" -Level ERROR
        Write-LogMessage "Repository path exists: $(Test-Path $repoPath)" -Level ERROR
        Write-LogMessage "Repository path contents: $(if (Test-Path $repoPath) { (Get-ChildItem $repoPath -ErrorAction SilentlyContinue | Select-Object -First 5 | ForEach-Object { $_.Name }) -join ', ' } else { 'Path does not exist' })" -Level ERROR
        throw "Failed to initialize git repository - .git folder not found after clone"
    }

    # Final setup
    Set-Location $repoPath
    $longpathsOutput = git config core.longpaths true 2>&1
    $gitCommands += "git config core.longpaths true"
    $gitInitResults += "Config core.longpaths: Exit code $LASTEXITCODE, Output: $($longpathsOutput -join ' ')"

    Add-Privilege -Path $repoPath -AdditionalAdmins @("$env:USERDOMAIN\ACL_ERPUTV_Utvikling_Full", "$env:USERDOMAIN\ACL_Dedge_Servere_Utviklere")
    
    $gitInitResults += "Full clone performed: $fullClonePerformed"
    $gitInitResults += "Repository initialized successfully"
    
    # Add all git commands to ScriptArray
    $gitCommandsOutput = "Git Commands Executed:`n" + ($gitCommands -join "`n")
    $script:WorkObject = Add-ScriptAndOutputToWorkObject -WorkObject $script:WorkObject -Name "GitCommands" -Script "All git commands executed" -Output $gitCommandsOutput
    
    $script:WorkObject.GitRepoInitialized = $true
    $script:WorkObject = Add-ScriptAndOutputToWorkObject -WorkObject $script:WorkObject -Name "Initialize-GitRepo" -Script "Git repository initialization" -Output ($gitInitResults -join "`n")
    
    Write-LogMessage "Repository initialized successfully" -Level INFO
    return $fullClonePerformed
}

function Update-GitRepo {
    param (
        [string]$repoPath,
        [array]$excludedFiles,
        [string]$discardedFolder,
        [array]$allFiltersFromConfig
    )

    if (-not $repoPath) {
        throw "Repository path is null or empty"
    }

    Set-Location $repoPath

    # Configure safe directory before git operations
    $safeDirPath = $repoPath.Replace('\', '/')
    Write-LogMessage "Configuring safe directory for git operations: $safeDirPath" -Level INFO
    git config --global --add safe.directory $safeDirPath | Out-Null
    # Create a discarded folder to files that should not be included in the git repo
    if (-not (Test-Path $discardedFolder -PathType Container)) {
        Add-Folder -Path $discardedFolder -AdditionalAdmins @("$env:USERDOMAIN\ACL_ERPUTV_Utvikling_Full", "$env:USERDOMAIN\ACL_Dedge_Servere_Utviklere")
    }
    # Process files
    $files = Get-ChildItem -Path $repoPath -Recurse -File -ErrorAction Stop
    Write-LogMessage "Found $($files.Count) files in repository" -Level INFO
    $excludedFiles = @($excludedFiles | ForEach-Object { $_.MODUL.ToUpper().Trim() })
    # foreach ($file in $excludedFiles) {
    #     Write-LogMessage "Excluded File: $($file.FullName)" -Level INFO
    # }
    # Export-ArrayToTxtFile -Content $excludedFiles -OutputPath ".\ExcludedFiles.txt"
    $finalExcludedFiles = @()
    $gitMvCommands = @()
    if ($null -ne $files) {
        foreach ($file in $files) {
            if ($null -eq $file) { continue }
            # if ($file.FullName.ToUpper().Trim().Contains("BKHOPPG") -or $file.FullName.ToUpper().Trim().Contains("KTHOKOR")) {
            #     Write-LogMessage "Debug Here" -Level INFO
            # }
            # Export array of files to log

            # Skip if file should be excluded
            $excludedReason = $null
            $excludedReason = Test-FileExclusion $file $excludedFiles $allFiltersFromConfig
            if ($null -ne $excludedReason) {
                $repoPathFile = $file.FullName.Split("Dedge\")[1]
                $discardedFolderFile = Join-Path $discardedFolder $repoPathFile
                $splitPath = Split-Path $discardedFolderFile -Parent
                if (Test-Path $splitPath -PathType Container) {
                    Add-Folder -Path $splitPath -AdditionalAdmins @("$env:USERDOMAIN\ACL_ERPUTV_Utvikling_Full", "$env:USERDOMAIN\ACL_Dedge_Servere_Utviklere")
                }
                $finalExcludedFiles += New-Object PSObject -Property ([ordered]@{
                        Date                = Get-Date
                        RepoFilePath        = $repoPathFile
                        DiscardedFolderFile = $discardedFolderFile
                        ExcludedReason      = $excludedReason
                    })

                # Move file to discarded folder
                try {
                    Move-Item -Path $file.FullName -Destination $splitPath -Force -ErrorAction SilentlyContinue
                }
                catch {
                    Write-LogMessage "Failed to move file to discarded folder. File: $($file.FullName) SplitPath: $($splitPath)" -Level ERROR -Exception $_
                }
                continue
            }
            # Normalize file name case
            $upperName = $file.Name.ToUpper()
            if ($file.Name -ne $upperName -and (Test-Path $file.FullName)) {
                $mvOutput = git mv $file.Name $upperName 2>&1
                $gitMvCommands += "git mv $($file.Name) $upperName (Exit code: $LASTEXITCODE, Output: $($mvOutput -join ' '))"
            }
        }
    }
    $outputPath = "$(Get-DevToolsWebPath)\Azure DevOps Git CheckIn\Excluded Files.html"
    Export-ArrayToHtmlFile -Content $finalExcludedFiles -OutputPath $outputPath -Title "Excluded Files"
    
    # Track excluded files statistics
    $script:WorkObject.TotalFilesExcluded = $finalExcludedFiles.Count
    $script:WorkObject.ExcludedFilesDetails = $finalExcludedFiles
    $script:WorkObject.TotalFilesInRepo = $files.Count - $finalExcludedFiles.Count

    # Track git commands
    $gitCommands = @()
    if ($gitMvCommands.Count -gt 0) {
        $gitCommands += "Git mv commands executed: $($gitMvCommands.Count)"
        $gitCommands += $gitMvCommands
    }
    $addOutput = git add . 2>&1
    $gitCommands += "git add ."
    $gitOperationResults = @()
    $gitOperationResults += "Git add: Exit code $LASTEXITCODE, Output: $($addOutput -join ' ')"

    # Commit changes
    $commitMessage = "Automated update: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')"
    if ($commitMessage -eq "") {
        $commitMessage = "Automated update"
    }
    
    $gitOperationResults += "Commit message: $commitMessage"
    $commitOutput = git commit -m $commitMessage 2>&1
    $gitOperationResults += "Commit output: $commitOutput"
    
    # Capture commit hash if successful
    if ($LASTEXITCODE -eq 0) {
        $commitHash = git rev-parse HEAD
        $script:WorkObject.ChangesCommitted = $true
        $script:WorkObject.CommitMessage = $commitMessage
        $script:WorkObject.CommitHash = $commitHash
        $gitOperationResults += "Commit hash: $commitHash"
        Write-LogMessage "Changes committed successfully. Hash: $commitHash" -Level INFO
    }
    else {
        $gitOperationResults += "Commit result: Exit code $LASTEXITCODE"
        Write-LogMessage "Commit completed with exit code: $LASTEXITCODE" -Level WARN
    }

    # Push changes using PAT authentication
    Write-LogMessage "Pushing changes to remote..." -Level INFO
    
    # DEBUG: Log authentication details before push operation
    Write-LogMessage "DEBUG - Git Push Authentication:" -Level DEBUG
    Write-LogMessage "  Service Account Email: $($script:ServiceAccountEmail)" -Level DEBUG
    Write-LogMessage "  PAT (first 10 chars): $($config.Pat.Substring(0, [Math]::Min(10, $config.Pat.Length)))..." -Level DEBUG
    Write-LogMessage "  Auth Method: Basic Auth with email:PAT format" -Level DEBUG
    
    # Use service account email with PAT for Basic Auth (email:PAT format)
    $encodedPat = [Convert]::ToBase64String([Text.Encoding]::ASCII.GetBytes("$($script:ServiceAccountEmail):$($config.Pat)"))
    $pushOutput = git -c http.extraheader="Authorization: Basic $encodedPat" push origin master 2>&1
    $gitOperationResults += "Push output: $pushOutput"
    
    if ($LASTEXITCODE -eq 0) {
        $script:WorkObject.ChangesPushed = $true
        $script:WorkObject.PushResult = "Success"
        $gitOperationResults += "Push successful"
        Write-LogMessage "Changes pushed successfully to remote" -Level INFO
    }
    else {
        $script:WorkObject.PushResult = "Failed with exit code $LASTEXITCODE"
        $gitOperationResults += "Push failed with exit code: $LASTEXITCODE"
        Write-LogMessage "Push failed with exit code: $LASTEXITCODE" -Level ERROR
    }
    
    $script:WorkObject.FilesProcessed = $true
    $script:WorkObject = Add-ScriptAndOutputToWorkObject -WorkObject $script:WorkObject -Name "Update-GitRepo" -Script "Git add, commit, and push operations" -Output ($gitOperationResults -join "`n")
}

function Test-FileExclusion {
    param(
        [System.IO.FileInfo]$file,
        [array]$excludedFiles,
        [array]$allFiltersFromConfig
    )

    $fileName = [System.IO.Path]::GetFileNameWithoutExtension($file.Name).ToUpper().Trim()

    $extension = "*" + $file.Extension.Trim().ToLower()

    # Exclude specific files
    if ($excludedFiles -contains $fileName) {
        return "File excluded because it is marked as UTGATT in COBDOK"
    }

    if ($allFiltersFromConfig -contains $extension) {
        if ($file.Name -match "\s" ) {
            return "File excluded because it contains a space in the name"
        }

        if ($file.Name.Contains("-OLD") -or $file.Name.Contains("_OLD") -or $file.Name.Contains("-GML") -or $file.Name.Contains("_GML") -or $file.Name.Contains("-GAMMEL") -or $file.Name.Contains("_GAMMEL")) {
            return "File excluded because it seems to be an old file"
        }
        if ($file.Name -match "\d{8}") {
            return "File excluded because it contains 8 consecutive digits that seem to be a date"
        }

        # if ($fileName.Contains("KTHOKOR") -or $fileName.Contains("BKHOPPG")) {
        #     Write-LogMessage "Debug Here" -Level INFO
        # }
    }
    else {
        return "File excluded because filter does not currently include $extension"
    }
    return $null
}

function Test-GitStatus {
    param (
        [string]$logPath = "$env:OptPath\data\AzureDevOpsGitCheckIn\log\GitStatus.log"
    )

    Write-LogMessage "Checking git status..." -Level INFO

    # Execute git status and redirect output to log file
    git status *> $logPath

    # Get git status and search for "fatal"
    $gitStatus = Get-Content $logPath
    if ($gitStatus -match "fatal") {
        Write-LogMessage "Git status contains fatal error: $gitStatus" -Level ERROR
        throw "Git operation failed"
    }

    Write-LogMessage "Git status check passed" -Level INFO
    return $logPath
}

function Start-GitCheckIn {
    param (
        [Parameter(Mandatory = $true)]
        [bool]$isRetry,
        [Parameter(Mandatory = $true)]
        [array]$allFiltersFromConfig
    )

    Write-LogMessage "Starting Git Check-In process $(if($isRetry){'(Retry with full copy)'})" -Level INFO

    if (-not $config.Pat) {
        throw "Azure DevOps PAT not configured"
    }

    Test-NetworkPaths

    $excludedFiles = Get-CobdokModules

    $repoPath = "$env:OptPath\data\AzureDevOpsGitCheckIn\gitrepo\Dedge"
    $discardedFolder = "$env:OptPath\data\AzureDevOpsGitCheckIn\discarded_files"
    # remove the discarded folder if it exists
    if (Test-Path $discardedFolder -PathType Container) {
        Remove-Item -Path $discardedFolder -Recurse -Force
    }
    Add-Folder -Path $discardedFolder -AdditionalAdmins @("$env:USERDOMAIN\ACL_ERPUTV_Utvikling_Full", "$env:USERDOMAIN\ACL_Dedge_Servere_Utviklere")

    $repoUrl = "https://Dedge.visualstudio.com/DefaultCollection/Dedge/_git/Dedge"

    if ($isRetry) {
        Write-LogMessage "Retry: Removing all files from repository folder" -Level INFO
        Set-Location $env:OptPath\data\AzureDevOpsGitCheckIn\
        if (Test-Path $repoPath) {
            # Wait for any git processes to finish and retry removal
            $maxRetries = 5
            $retryCount = 0
            $removed = $false
            while ($retryCount -lt $maxRetries -and -not $removed) {
                try {
                    # Kill any git processes that might be locking files
                    Get-Process -Name "git" -ErrorAction SilentlyContinue | Stop-Process -Force -ErrorAction SilentlyContinue
                    Start-Sleep -Seconds 2
                    
                    # Try standard removal first
                    Remove-Item -Path $repoPath -Recurse -Force -ErrorAction Stop
                    $removed = $true
                    Write-LogMessage "Successfully removed repository folder" -Level INFO
                }
                catch {
                    $retryCount++
                    if ($retryCount -lt $maxRetries) {
                        Write-LogMessage "Failed to remove repository folder (attempt $retryCount/$maxRetries), trying robocopy method..." -Level WARN
                        # Try using robocopy to delete (more robust for locked files)
                        try {
                            $emptyDir = Join-Path $env:TEMP "EmptyDir_$(Get-Random)"
                            New-Item -ItemType Directory -Path $emptyDir -Force | Out-Null
                            robocopy $emptyDir $repoPath /MIR /R:0 /W:0 /NFL /NDL /NJH /NJS | Out-Null
                            Remove-Item -Path $repoPath -Force -ErrorAction Stop
                            Remove-Item -Path $emptyDir -Force -ErrorAction SilentlyContinue
                            $removed = $true
                            Write-LogMessage "Successfully removed repository folder using robocopy" -Level INFO
                        }
                        catch {
                            Write-LogMessage "Robocopy method also failed, retrying in 3 seconds..." -Level WARN
                            Start-Sleep -Seconds 3
                        }
                    }
                    else {
                        Write-LogMessage "Failed to remove repository folder after $maxRetries attempts: $($_.Exception.Message)" -Level ERROR
                        # Don't throw - continue anyway, Initialize-GitRepo will handle it
                        Write-LogMessage "Continuing despite removal failure - Initialize-GitRepo will attempt cleanup" -Level WARN
                    }
                }
            }
        }
    }

    $fullClonePerformed = Initialize-GitRepo -repoPath $repoPath -repoUrl $repoUrl -pat $config.Pat
    Test-GitStatus
    Copy-SourceFiles -targetRoot $repoPath -allFiltersFromConfig $allFiltersFromConfig -fullClonePerformed $fullClonePerformed
    Update-GitRepo -repoPath $repoPath -excludedFiles $excludedFiles -discardedFolder $discardedFolder -allFiltersFromConfig $allFiltersFromConfig
}

# Main execution
try {
    if (-not $env:OptPath) {
        throw "OptPath environment variable not set"
    }

    Write-LogMessage "$($MyInvocation.MyCommand.Name)" -Level JOB_STARTED
    
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
    git config --global --unset-all credential.https://dev.azure.com.helper 2>$null | Out-Null
    git config --global --unset-all credential.https://*.visualstudio.com.helper 2>$null | Out-Null
    
    # Ensure store helper is set as the ONLY helper
    git config --global credential.helper store 2>$null | Out-Null
    git config --global credential.credentialStore plaintext 2>$null | Out-Null
    
    Write-LogMessage "Git Credential Manager disabled successfully" -Level INFO
    
    # Load Azure DevOps credentials (PAT, Email, Organization) from AzureAccessTokens.json
    Write-LogMessage "Loading Azure DevOps credentials from AzureAccessTokens.json..." -Level INFO
    Write-LogMessage "  Running as user : $($env:USERDOMAIN)\$($env:USERNAME)" -Level INFO
    Write-LogMessage "  USERPROFILE     : $($env:USERPROFILE)" -Level INFO
    Write-LogMessage "  OptPath         : $($env:OptPath)" -Level INFO
    Write-LogMessage "  IdLike filter   : *AzureDevOpsExtPat*" -Level INFO

    try {
        $script:AzureDevOpsCredentials = Get-AzureDevOpsCredentials -IdLike '*AzureDevOpsExtPat*'
    }
    catch {
        # Wrap the inner exception so we get the real stack trace in the log, not just the error message
        Write-LogMessage "Get-AzureDevOpsCredentials threw an unhandled exception" -Level ERROR -Exception $_
        Write-LogMessage "  Exception type  : $($_.Exception.GetType().FullName)" -Level ERROR
        Write-LogMessage "  Stack trace     : $($_.ScriptStackTrace)" -Level ERROR
        Write-LogMessage "  InnerException  : $($_.Exception.InnerException?.Message)" -Level ERROR
        throw "Credential loading threw an unhandled exception: $($_.Exception.Message)"
    }

    if (-not $script:AzureDevOpsCredentials -or -not $script:AzureDevOpsCredentials.Success) {
        $credErr = if ($script:AzureDevOpsCredentials) { $script:AzureDevOpsCredentials.ErrorMessage } else { '<Get-AzureDevOpsCredentials returned null>' }
        Write-LogMessage "Failed to load Azure DevOps credentials: $credErr" -Level ERROR
        # Log properties that ARE present on the returned object to help diagnose partial results
        if ($script:AzureDevOpsCredentials) {
            Write-LogMessage "  Returned object properties: $(($script:AzureDevOpsCredentials | Get-Member -MemberType NoteProperty | Select-Object -ExpandProperty Name) -join ', ')" -Level ERROR
            Write-LogMessage "  Success        : $($script:AzureDevOpsCredentials.Success)" -Level ERROR
            Write-LogMessage "  Pat (present)  : $(-not [string]::IsNullOrWhiteSpace($script:AzureDevOpsCredentials.Pat))" -Level ERROR
            Write-LogMessage "  Email (present): $(-not [string]::IsNullOrWhiteSpace($script:AzureDevOpsCredentials.Email))" -Level ERROR
        }
        throw "Azure DevOps credentials not found or incomplete. Error: $credErr"
    }
    
    # Set script-level variables from loaded credentials
    $config.Pat = $script:AzureDevOpsCredentials.Pat
    $script:ServiceAccountEmail = $script:AzureDevOpsCredentials.Email
    $script:ServiceAccountEmailEncoded = $script:AzureDevOpsCredentials.EmailEncoded
    
    # Override Organization from JSON if available, otherwise use config default
    if (-not [string]::IsNullOrWhiteSpace($script:AzureDevOpsCredentials.Organization)) {
        $config.Organization = $script:AzureDevOpsCredentials.Organization
    }
    
    Write-LogMessage "Azure DevOps credentials loaded successfully from token '$($script:AzureDevOpsCredentials.Id)'" -Level INFO
    
    # DEBUG: Log service account and PAT details (now loaded from JSON, not hardcoded)
    Write-LogMessage "DEBUG - Azure DevOps Configuration (from AzureAccessTokens.json):" -Level DEBUG
    Write-LogMessage "  Token Id: $($script:AzureDevOpsCredentials.Id)" -Level DEBUG
    Write-LogMessage "  Organization: $($config.Organization)" -Level DEBUG
    Write-LogMessage "  Project: $($config.Project)" -Level DEBUG
    Write-LogMessage "  Repository: $($config.Repository)" -Level DEBUG
    Write-LogMessage "  Service Account Email: $($script:ServiceAccountEmail)" -Level DEBUG
    Write-LogMessage "  Service Account Email (URL-encoded): $($script:ServiceAccountEmailEncoded)" -Level DEBUG
    Write-LogMessage "  PAT (first 10 chars): $($config.Pat.Substring(0, [Math]::Min(10, $config.Pat.Length)))..." -Level DEBUG
    Write-LogMessage "  PAT Length: $($config.Pat.Length) characters" -Level DEBUG
    
    # Test the PAT token validity
    Write-LogMessage "Testing Azure DevOps PAT token validity..." -Level INFO
    Write-LogMessage "DEBUG - PAT Test: Using email '$($script:ServiceAccountEmail)' with PAT against dev.azure.com" -Level DEBUG
    $patTestResult = Test-AzureDevOpsPat -Pat $config.Pat -Organization $config.Organization -Project $config.Project
    $script:WorkObject = Add-Member -InputObject $script:WorkObject -MemberType NoteProperty -Name "PatTestResult" -Value $patTestResult -Force -PassThru
    
    if ($patTestResult.Success) {
        Write-LogMessage "PAT token test successful (HTTP $($patTestResult.StatusCode))" -Level INFO
        $script:WorkObject = Add-ScriptAndOutputToWorkObject -WorkObject $script:WorkObject -Name "PatTokenTest" -Script "Azure DevOps PAT token validation" -Output "SUCCESS: Token is valid (HTTP $($patTestResult.StatusCode))"
    }
    else {
        Write-LogMessage "PAT token test failed: $($patTestResult.ErrorMessage)" -Level ERROR
        $script:WorkObject = Add-ScriptAndOutputToWorkObject -WorkObject $script:WorkObject -Name "PatTokenTest" -Script "Azure DevOps PAT token validation" -Output "FAILED: $($patTestResult.ErrorMessage) (HTTP Status: $($patTestResult.StatusCode))"
        throw "Azure DevOps PAT token validation failed: $($patTestResult.ErrorMessage)"
    }
    
    $isRetry = $false
    $timestampFile = Join-Path $env:OptPath "data\AzureDevOpsGitCheckIn\last_successful_run.txt"
    if (Test-Path $timestampFile) {
        $timestamp = Get-Content $timestampFile
        Write-LogMessage "Last successful run: $timestamp" -Level INFO
        # Find difference between last successful run and now
        $lastSuccessfulRun = Get-Date $timestamp
        $now = Get-Date
        $difference = $now - $lastSuccessfulRun
        Write-LogMessage "Difference between last successful run and now: $difference" -Level INFO
        if ($difference.TotalHours -gt 24) {
            Write-LogMessage "Last successful run was more than 24 hours ago" -Level INFO
            $isRetry = $true
        }
        else {
            $isRetry = $false
        }
    }
    else {
        Write-LogMessage "No previous successful run found" -Level INFO
        $isRetry = $true
    }

    Initialize-Folders
    # Load last successful run timestamp
    if (Test-Path $timestampFile) {
        $timestamp = Get-Content $timestampFile
        $script:WorkObject.LastSuccessfulRun = $timestamp
        Write-LogMessage "Last successful run: $timestamp" -Level INFO
    }
    
    $allFiltersFromConfig = $config.GitFolders.GetEnumerator() | ForEach-Object {
        $_.Value.Sources | ForEach-Object {
            if ($_.Filter -ne "*.*") {
                $_.Filter
            }
        }
    }
    Write-LogMessage "All filters from config: $($allFiltersFromConfig -join ", ")" -Level INFO
    
    try {
        # First attempt with normal copy
        Start-GitCheckIn -isRetry:$isRetry -allFiltersFromConfig $allFiltersFromConfig
        
        # Mark as successful
        $script:WorkObject.Success = $true
        $script:WorkObject.Status = "Completed"
        $script:WorkObject.OverallSuccess = $true
    }
    catch {
        if ($_.Exception.Message -like "*Git operation failed*") {
            Write-LogMessage "First attempt failed with Git operation error" -Level ERROR -Exception $_
            Write-LogMessage "Retrying with full copy..." -Level INFO
            
            $script:WorkObject = Add-ScriptAndOutputToWorkObject -WorkObject $script:WorkObject -Name "Retry-Attempt" -Script "Retry with full copy after git error" -Output "First attempt failed: $($_.Exception.Message)"
            
            # Second attempt with full copy
            try {
                Start-GitCheckIn -isRetry:$true -allFiltersFromConfig $allFiltersFromConfig
                $script:WorkObject.Success = $true
                $script:WorkObject.Status = "Completed (after retry)"
                $script:WorkObject.OverallSuccess = $true
            }
            catch {
                $script:WorkObject.Success = $false
                $script:WorkObject.Status = "Failed"
                $script:WorkObject.OverallSuccess = $false
                $script:WorkObject.ErrorMessage = $_.Exception.Message
                throw
            }
        }
        else {
            $script:WorkObject.Success = $false
            $script:WorkObject.Status = "Failed"
            $script:WorkObject.OverallSuccess = $false
            $script:WorkObject.ErrorMessage = $_.Exception.Message
            Write-LogMessage "Error during Git check-in process" -Level ERROR -Exception $_
            throw
        }
    }
    
    # Calculate duration
    $script:WorkObject.EndTime = Get-Date
    $script:WorkObject.Duration = $script:WorkObject.EndTime - $script:WorkObject.StartTime
    
    # Save timestamp of successful completion
    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    $timestamp | Out-File -FilePath $timestampFile -Force
    Write-LogMessage "Saved completion timestamp to $timestampFile" -Level INFO
    Write-LogMessage "Process completed successfully" -Level INFO
    Write-LogMessage "$($MyInvocation.MyCommand.Name)" -Level JOB_COMPLETED
    
    # Send success alert
    $successMessage = "Azure DevOps Git Check-In completed successfully`n" +
                     "Files copied: $($script:WorkObject.TotalFilesCopied)`n" +
                     "Files excluded: $($script:WorkObject.TotalFilesExcluded)`n" +
                     "Files in repo: $($script:WorkObject.TotalFilesInRepo)`n" +
                     "Duration: $($script:WorkObject.Duration.ToString('hh\:mm\:ss'))"
    
    Send-FkAlert -Program "AzureDevOpsGitCheckIn" -Code "0000" -Message $successMessage

    # Add final log content
    $logContent = Get-Content -Path $global:CurrentLogFilePath
    $script:WorkObject = Add-ScriptAndOutputToWorkObject -WorkObject $script:WorkObject -Name "ExecutionLog" -Script "Complete execution log" -Output ($logContent -join "`n")

    # Export comprehensive HTML report
    $reportPath = Join-Path $(Get-ApplicationDataPath) "AzureDevOpsGitCheckIn_$(Get-Date -Format 'yyyyMMdd_HHmmss').html"
    Export-WorkObjectToHtmlFile -WorkObject $script:WorkObject -FileName $reportPath -Title "Azure DevOps Git Check-In - Execution Report" -AutoOpen $false -AddToDevToolsWebPath $true -DevToolsWebDirectory "Jobs"
    
    Write-LogMessage "Execution report exported to: $reportPath" -Level INFO
    
    # Export JSON report to local folder only
    $jsonPath = Join-Path $(Get-ApplicationDataPath) "AzureDevOpsGitCheckIn_$(Get-Date -Format 'yyyyMMdd_HHmmss').json"
    $script:WorkObject | ConvertTo-Json -Depth 10 | Set-Content -Path $jsonPath -Encoding UTF8
    Write-LogMessage "JSON report exported to: $jsonPath" -Level INFO
    
    # Re-enable Git Credential Manager for normal user operations
    Restore-GitCredentialManager
}
catch {
    # Update work object with failure information
    $script:WorkObject.Success = $false
    $script:WorkObject.Status = "Failed"
    $script:WorkObject.OverallSuccess = $false
    $script:WorkObject.ErrorMessage = $_.Exception.Message
    $script:WorkObject.EndTime = Get-Date
    $script:WorkObject.Duration = $script:WorkObject.EndTime - $script:WorkObject.StartTime
    
    Write-LogMessage "Main execution failed" -Level ERROR -Exception $_
    Write-LogMessage "$($MyInvocation.MyCommand.Name)" -Level JOB_FAILED
    
    # Add failure details to work object
    $failureDetails = @(
        "Error occurred at line: $($_.InvocationInfo.ScriptLineNumber)",
        "Error message: $($_.Exception.Message)",
        "Stack trace: $($_.ScriptStackTrace)"
    )
    $script:WorkObject = Add-ScriptAndOutputToWorkObject -WorkObject $script:WorkObject -Name "ExecutionError" -Script "Failure details" -Output ($failureDetails -join "`n")
    
    # Add final log content even on failure
    try {
        $logContent = Get-Content -Path $global:CurrentLogFilePath -ErrorAction SilentlyContinue
        if ($logContent) {
            $script:WorkObject = Add-ScriptAndOutputToWorkObject -WorkObject $script:WorkObject -Name "ExecutionLog" -Script "Complete execution log (with errors)" -Output ($logContent -join "`n")
        }
    }
    catch {
        Write-LogMessage "Could not retrieve log content for work object" -Level WARN
    }
    
    # Export failure report
    try {
        $reportPath = Join-Path $(Get-ApplicationDataPath) "AzureDevOpsGitCheckIn_FAILED_$(Get-Date -Format 'yyyyMMdd_HHmmss').html"
        Export-WorkObjectToHtmlFile -WorkObject $script:WorkObject -FileName $reportPath -Title "Azure DevOps Git Check-In - FAILURE Report" -AutoOpen $false -AddToDevToolsWebPath $true -DevToolsWebDirectory "JobReports"
        Write-LogMessage "Failure report exported to: $reportPath" -Level INFO
    }
    catch {
        Write-LogMessage "Could not export failure report" -Level WARN -Exception $_
    }
    
    # Export JSON report to local folder only (even on failure)
    try {
        $jsonPath = Join-Path $(Get-ApplicationDataPath) "AzureDevOpsGitCheckIn_FAILED_$(Get-Date -Format 'yyyyMMdd_HHmmss').json"
        $script:WorkObject | ConvertTo-Json -Depth 10 | Set-Content -Path $jsonPath -Encoding UTF8
        Write-LogMessage "JSON failure report exported to: $jsonPath" -Level INFO
    }
    catch {
        Write-LogMessage "Could not export JSON failure report" -Level WARN -Exception $_
    }
    
    # Re-enable Git Credential Manager even on failure
    Restore-GitCredentialManager
    
    # Send alerts
    $errorMessage = "Azure DevOps Git Check-In FAILED`n" +
                   "Line: $($_.InvocationInfo.ScriptLineNumber)`n" +
                   "Error: $($_.Exception.Message)`n" +
                   "Duration: $($script:WorkObject.Duration.ToString('hh\:mm\:ss'))"
    
    Send-Sms -Receiver "+4797188358" -Message $errorMessage
    Send-FkAlert -Program "AzureDevOpsGitCheckIn" -Code "9999" -Message $errorMessage
    exit 1
}

