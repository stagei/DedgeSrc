<#
.SYNOPSIS
    Shared Azure/Azure DevOps helper functions.

.DESCRIPTION
    This module centralizes common Azure DevOps helper logic for scripts.

    IMPORTANT:
    - GlobalFunctions.psm1 must not import modules.
    - This module imports GlobalFunctions and other helper modules instead.

    Current responsibilities:
    - Resolve AzureAccessTokens.json from standard locations (same method as Azure-NugetVersionPush.ps1)
    - Provide Get-AzureDevOpsPat backed by AzureAccessTokens.json (Id like '*AzureDevOpsExtPat*')
    - Helper to authenticate Azure DevOps CLI without env vars
#>
$modulesToImport = @("GlobalFunctions", "SoftwareUtils")
foreach ($moduleName in $modulesToImport) {
    $loadedModule = Get-Module -Name $moduleName
    if ($loadedModule -eq $false -or $env:USERNAME -in @("FKGEISTA", "FKSVEERI")) {
        Import-Module $moduleName -Force
    }
    else {
        Write-Host "Module $moduleName already loaded" -ForegroundColor Yellow
    }
}

# Module-level cache for AzureAccessTokens.json location resolution.
# Must be initialized as a hashtable so property assignment works when the cache is cold.
$script:AzureAccessTokensFileCache = @{
    Result    = $null
    Timestamp = [DateTime]::MinValue
    CacheTTL  = [TimeSpan]::FromMinutes(5)
}

if (-not (Get-Command az -ErrorAction SilentlyContinue)) {
    Install-WingetPackage -AppName "Microsoft.AzureCLI" 
}


function Get-AzureAccessTokensFileCandidates {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $false)]
        [string]$AzureAccessTokensFileName = 'AzureAccessTokens.json'
    )

    $searchPaths = @()
    
    # Priority 1: Shared location for scheduled tasks/service accounts
    # This allows service accounts to find credentials without user profile access
    if ($env:OptPath) { 
        $searchPaths += Join-Path $env:OptPath 'data\AzureCredentials'
    }
    # Also check standard shared locations on servers
    $sharedLocations = @(
        'E:\opt\data\AzureCredentials',
        'C:\opt\data\AzureCredentials',
        'C:\opt\src\DedgeSrc\DedgeSystemTools\Folders\Opt\data\AzureCredentials'
    )
    foreach ($sharedLoc in $sharedLocations) {
        if (Test-Path $sharedLoc -PathType Container -ErrorAction SilentlyContinue) {
            $searchPaths += $sharedLoc
        }
    }
    
    # Priority 2: User-specific locations (works in interactive sessions)
    if ($env:OneDriveCommercial) { $searchPaths += $env:OneDriveCommercial }
    if ($env:OneDrive) { $searchPaths += $env:OneDrive }

    if ($env:USERPROFILE) {
        $searchPaths += Join-Path $env:USERPROFILE 'Documents'
        $searchPaths += Join-Path $env:USERPROFILE 'AppData\Roaming'
        $searchPaths += Join-Path $env:USERPROFILE 'AppData\Local'
    }

    $seenPaths = @{}
    $found = @()

    # Log search context for debugging scheduled task issues
    Write-LogMessage "Searching for $AzureAccessTokensFileName - Context: User=$($env:USERNAME), UserProfile=$($env:USERPROFILE), OptPath=$($env:OptPath)" -Level DEBUG
    
    foreach ($searchPath in $searchPaths) {
        if (-not (Test-Path $searchPath -PathType Container -ErrorAction SilentlyContinue)) { 
            Write-LogMessage "  Search path does not exist: $searchPath" -Level DEBUG
            continue 
        }

        $candidate = Join-Path $searchPath $AzureAccessTokensFileName
        if (-not (Test-Path $candidate -PathType Leaf -ErrorAction SilentlyContinue)) { 
            Write-LogMessage "  File not found in: $searchPath" -Level DEBUG
            continue 
        }

        $fileInfo = Get-Item -LiteralPath $candidate
        $fullPath = $fileInfo.FullName

        if (-not $seenPaths.ContainsKey($fullPath)) {
            $seenPaths[$fullPath] = $true
            $found += [PSCustomObject]@{
                FullName      = $fullPath
                LastWriteTime = $fileInfo.LastWriteTime
            }
            Write-LogMessage "  FOUND: $fullPath (Modified: $($fileInfo.LastWriteTime))" -Level DEBUG
        }
    }

    if ($found.Count -eq 0) {
        Write-LogMessage "AzureAccessTokens.json not found in any of the $($searchPaths.Count) search paths. Searched: $($searchPaths -join '; ')" -Level WARN
    }

    return $found
}

function Get-AzureAccessTokensFile {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $false)]
        [string]$AzureAccessTokensFileName = 'AzureAccessTokens.json',

        [Parameter(Mandatory = $false)]
        [switch]$SkipCache
        <#
    .SYNOPSIS
        Resolves the AzureAccessTokens.json file path from standard locations.
    .DESCRIPTION
        Uses Get-AzureAccessTokensFileCandidates, selects the most recently modified,
        and returns an object with SelectedPath and Candidates. Results are cached.
    #>
    )

    # Check cache first to avoid duplicate warnings within the same operation
    if (-not $SkipCache -and $script:AzureAccessTokensFileCache.Result -and 
        ((Get-Date) - $script:AzureAccessTokensFileCache.Timestamp) -lt $script:AzureAccessTokensFileCache.CacheTTL) {
        Write-LogMessage "Using cached AzureAccessTokens.json location: $($script:AzureAccessTokensFileCache.Result.SelectedPath)" -Level DEBUG
        return $script:AzureAccessTokensFileCache.Result
    }

    $candidates = Get-AzureAccessTokensFileCandidates -AzureAccessTokensFileName $AzureAccessTokensFileName
    if (-not $candidates -or $candidates.Count -eq 0) {
        $result = [PSCustomObject]@{
            SelectedPath = $null
            Candidates   = @()
        }
        # Cache empty result too
        $script:AzureAccessTokensFileCache.Result = $result
        $script:AzureAccessTokensFileCache.Timestamp = Get-Date
        return $result
    }

    $selected = $candidates | Sort-Object -Property LastWriteTime -Descending | Select-Object -First 1

    if ($candidates.Count -gt 1) {
        Write-LogMessage "Found $($candidates.Count) instances of $($AzureAccessTokensFileName):" -Level INFO
        foreach ($c in $candidates) {
            $marker = if ($c.FullName -eq $selected.FullName) { " [SELECTED]" } else { "" }
            Write-LogMessage "  - $($c.FullName) (Modified: $($c.LastWriteTime.ToString('yyyy-MM-dd HH:mm:ss')))$marker" -Level INFO
        }
    }

    $result = [PSCustomObject]@{
        SelectedPath = $selected.FullName
        Candidates   = $candidates
    }

    # Update cache
    $script:AzureAccessTokensFileCache.Result = $result
    $script:AzureAccessTokensFileCache.Timestamp = Get-Date

    return $result
}

function Get-AzureAccessTokens {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $false)]
        [string]$AzureAccessTokensFileName = 'AzureAccessTokens.json'
    )

    $fileInfo = Get-AzureAccessTokensFile -AzureAccessTokensFileName $AzureAccessTokensFileName
    <#
    .SYNOPSIS
        Loads and returns all token entries from AzureAccessTokens.json.
    .DESCRIPTION
        Reads the file resolved by Get-AzureAccessTokensFile and returns tokens as an array.
    #>
    if (-not $fileInfo.SelectedPath) {
        return @()
    }

    $data = Get-Content -LiteralPath $fileInfo.SelectedPath -Raw | ConvertFrom-Json
    if ($data -is [System.Array]) { return $data }
    if ($null -ne $data) { return @($data) }

    return @()
}

function Get-AzureAccessTokenById {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$IdLike,

        [Parameter(Mandatory = $false)]
        [string]$AzureAccessTokensFileName = 'AzureAccessTokens.json'
        <#
    .SYNOPSIS
        Returns the first token entry whose Id matches a wildcard pattern.
    .DESCRIPTION
        Loads tokens via Get-AzureAccessTokens and filters by Id -like IdLike.
    #>
    )

    $tokens = Get-AzureAccessTokens -AzureAccessTokensFileName $AzureAccessTokensFileName
    if (-not $tokens) { return $null }

    return ($tokens | Where-Object { $_.Id -like $IdLike } | Select-Object -First 1)
}

function Get-AzureDevOpsPat {
    <#
    .SYNOPSIS
        Gets Azure DevOps PAT from AzureAccessTokens.json.

    .DESCRIPTION
        Reads tokens from AzureAccessTokens.json (searched in standard locations by AzureTokenStore)
        and returns the Token for the first entry whose Id matches '*AzureDevOpsExtPat*'.

        If not found or Token is empty, returns $null.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $false)]
        [string]$IdLike = '*AzureDevOpsExtPat*',

        [Parameter(Mandatory = $false)]
        [string]$AzureAccessTokensFileName = 'AzureAccessTokens.json'
    )

    $tokenObj = Get-AzureAccessTokenById -IdLike $IdLike -AzureAccessTokensFileName $AzureAccessTokensFileName
    if ($tokenObj -and -not [string]::IsNullOrWhiteSpace($tokenObj.Token)) {
        return $tokenObj.Token
    }

    return $null
}

function Get-AzureDevOpsCredentials {
    <#
    .SYNOPSIS
        Gets Azure DevOps credentials (PAT, Email, Organization) from AzureAccessTokens.json.

    .DESCRIPTION
        Returns a PSCustomObject with all credential information needed for Azure DevOps operations:
        - Pat: The PAT token
        - Email: The email address associated with the token
        - EmailEncoded: URL-encoded email (@ replaced with %40) for use in Git URLs
        - Organization: The Azure DevOps organization name
        - Id: The token Id from the JSON file

        This function consolidates credential retrieval to avoid hardcoding values.
        
        If the credentials file doesn't exist or required fields are missing, the function
        will prompt the user (with a 15-second timeout) to enter the missing information.
        If the user doesn't respond or declines, the function returns with an error.

    .PARAMETER IdLike
        Wildcard pattern to match the token Id. Default is '*AzureDevOpsExtPat*'.

    .PARAMETER AzureAccessTokensFileName
        Name of the AzureAccessTokens.json file.

    .PARAMETER PromptForMissing
        If $true (default), prompts user to enter missing credentials interactively.
        If $false, returns error without prompting.

    .PARAMETER PromptTimeoutSeconds
        Timeout in seconds for user confirmation prompt. Default is 15.

    .EXAMPLE
        $creds = Get-AzureDevOpsCredentials
        Write-Host "Email: $($creds.Email)"
        Write-Host "Email (URL-encoded): $($creds.EmailEncoded)"
        Write-Host "PAT: $($creds.Pat.Substring(0,10))..."

    .EXAMPLE
        $creds = Get-AzureDevOpsCredentials -IdLike '*MyCustomPat*'
        if ($creds.Success) {
            # Use credentials
        }

    .EXAMPLE
        # Non-interactive mode (no prompts)
        $creds = Get-AzureDevOpsCredentials -PromptForMissing:$false

    .OUTPUTS
        PSCustomObject with Success, Pat, Email, EmailEncoded, Organization, Id, and ErrorMessage properties.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $false)]
        [string]$IdLike = '*AzureDevOpsExtPat*',

        [Parameter(Mandatory = $false)]
        [string]$AzureAccessTokensFileName = 'AzureAccessTokens.json',

        [Parameter(Mandatory = $false)]
        [bool]$PromptForMissing = $true,

        [Parameter(Mandatory = $false)]
        [int]$PromptTimeoutSeconds = 15
    )

    $result = [PSCustomObject]@{
        Success      = $false
        Pat          = $null
        Email        = $null
        EmailEncoded = $null
        Organization = $null
        Id           = $null
        ErrorMessage = $null
    }

    # Helper function to prompt user for missing credentials
    function Request-MissingCredentials {
        param(
            [string]$Reason,
            [string]$ExistingId,
            [string]$ExistingToken,
            [string]$ExistingEmail,
            [string]$ExistingOrganization
        )

        Write-LogMessage "Azure DevOps credentials incomplete or missing: $Reason" -Level WARN

        # Check if we should prompt (interactive session and PromptForMissing enabled)
        if (-not $PromptForMissing) {
            Write-LogMessage "PromptForMissing is disabled, skipping interactive setup" -Level DEBUG
            return $null
        }

        if (-not [Environment]::UserInteractive) {
            Write-LogMessage "Non-interactive session detected, cannot prompt for credentials" -Level WARN
            return $null
        }

        # Use Get-UserConfirmationWithTimeout to ask user if they want to set up credentials
        Write-Host ""
        Write-LogMessage "Missing Azure DevOps credentials detected" -Level WARN
        
        try {
            $confirmResponse = Get-UserConfirmationWithTimeout `
                -PromptMessage "Would you like to configure Azure DevOps credentials now?" `
                -TimeoutSeconds $PromptTimeoutSeconds `
                -DefaultResponse "N" `
                -AllowedResponses @("Y", "N") `
                -ProgressMessage "Waiting for response..."

            if ($confirmResponse -ne "Y") {
                Write-LogMessage "User declined or timed out. Skipping credential setup." -Level INFO
                return $null
            }
        }
        catch {
            Write-LogMessage "Error during confirmation prompt: $($_.Exception.Message)" -Level WARN
            return $null
        }

        Write-Host ""
        Write-Host "================================" -ForegroundColor Cyan
        Write-Host " Azure DevOps Credential Setup" -ForegroundColor Cyan
        Write-Host "================================" -ForegroundColor Cyan
        Write-Host ""

        # Determine default Id from pattern
        $defaultId = $IdLike.Replace('*', '')
        if ([string]::IsNullOrWhiteSpace($defaultId)) {
            $defaultId = "AzureDevOpsExtPat"
        }

        # Prompt for Id
        $tokenId = $ExistingId
        if ([string]::IsNullOrWhiteSpace($tokenId)) {
            Write-Host "Token Id (unique identifier for this credential)" -ForegroundColor Yellow
            Write-Host "  Default: $defaultId" -ForegroundColor Gray
            $inputId = Read-Host "  Enter Id (or press Enter for default)"
            $tokenId = if ([string]::IsNullOrWhiteSpace($inputId)) { $defaultId } else { $inputId.Trim() }
        }
        else {
            Write-Host "Token Id: $tokenId (existing)" -ForegroundColor Gray
        }

        # Prompt for PAT (required)
        $pat = $ExistingToken
        if ([string]::IsNullOrWhiteSpace($pat)) {
            Write-Host ""
            Write-Host "Personal Access Token (PAT) - REQUIRED" -ForegroundColor Yellow
            Write-Host "  Get your PAT from: https://dev.azure.com/<org>/_usersSettings/tokens" -ForegroundColor Gray
            $pat = Read-Host "  Enter PAT"
            if ([string]::IsNullOrWhiteSpace($pat)) {
                Write-LogMessage "PAT is required. Aborting setup." -Level ERROR
                return $null
            }
        }
        else {
            Write-Host "PAT: $($pat.Substring(0, [Math]::Min(10, $pat.Length)))... (existing)" -ForegroundColor Gray
        }

        # Prompt for Email (required)
        $email = $ExistingEmail
        if ([string]::IsNullOrWhiteSpace($email)) {
            Write-Host ""
            Write-Host "Email address associated with the PAT - REQUIRED" -ForegroundColor Yellow
            Write-Host "  This must match the account that created the PAT" -ForegroundColor Gray
            $email = Read-Host "  Enter email"
            if ([string]::IsNullOrWhiteSpace($email)) {
                Write-LogMessage "Email is required. Aborting setup." -Level ERROR
                return $null
            }
            # Basic email validation
            if ($email -notmatch '^[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}$') {
                Write-LogMessage "Invalid email format: $email. Aborting setup." -Level ERROR
                return $null
            }
        }
        else {
            Write-Host "Email: $email (existing)" -ForegroundColor Gray
        }

        # Prompt for Organization (optional but recommended)
        $organization = $ExistingOrganization
        if ([string]::IsNullOrWhiteSpace($organization)) {
            Write-Host ""
            Write-Host "Azure DevOps Organization name (optional but recommended)" -ForegroundColor Yellow
            Write-Host "  Example: 'Dedge' from https://dev.azure.com/Dedge" -ForegroundColor Gray
            $organization = Read-Host "  Enter organization (or press Enter to skip)"
        }
        else {
            Write-Host "Organization: $organization (existing)" -ForegroundColor Gray
        }

        # Description
        $description = "Azure DevOps PAT for automated operations"
        Write-Host ""
        Write-Host "Description (optional)" -ForegroundColor Yellow
        $inputDesc = Read-Host "  Enter description (or press Enter for default)"
        if (-not [string]::IsNullOrWhiteSpace($inputDesc)) {
            $description = $inputDesc.Trim()
        }

        Write-Host ""
        Write-Host "Saving credentials..." -ForegroundColor Cyan

        # Register the token
        $registerResult = Register-AzureAccessToken `
            -Id $tokenId `
            -Token $pat `
            -Email $email `
            -Organization $organization `
            -Description $description

        if ($registerResult.Success) {
            Write-Host "Credentials saved successfully!" -ForegroundColor Green
            Write-LogMessage "Credentials saved to $($registerResult.FilePath)" -Level INFO
            return $registerResult.TokenEntry
        }
        else {
            Write-LogMessage "Failed to save credentials: $($registerResult.Message)" -Level ERROR
            return $null
        }
    }

    try {
        # Check if file exists at all
        $fileInfo = Get-AzureAccessTokensFile -AzureAccessTokensFileName $AzureAccessTokensFileName
        
        if (-not $fileInfo.SelectedPath) {
            # File doesn't exist - prompt to create
            Write-LogMessage "AzureAccessTokens.json file not found" -Level WARN
            
            $newToken = Request-MissingCredentials -Reason "AzureAccessTokens.json file not found"
            if (-not $newToken) {
                $result.ErrorMessage = "AzureAccessTokens.json not found and user declined to create credentials"
                return $result
            }
            
            # Re-read after creation
            $tokenObj = Get-AzureAccessTokenById -IdLike $IdLike -AzureAccessTokensFileName $AzureAccessTokensFileName
        }
        else {
            $tokenObj = Get-AzureAccessTokenById -IdLike $IdLike -AzureAccessTokensFileName $AzureAccessTokensFileName
        }
        
        # Check if token was found
        if (-not $tokenObj) {
            Write-LogMessage "No token found matching Id pattern '$IdLike'" -Level WARN
            
            $newToken = Request-MissingCredentials -Reason "No token matching '$IdLike' found"
            if (-not $newToken) {
                $result.ErrorMessage = "No token found matching '$IdLike' and user declined to create credentials"
                return $result
            }
            
            # Re-read after creation
            $tokenObj = Get-AzureAccessTokenById -IdLike $IdLike -AzureAccessTokensFileName $AzureAccessTokensFileName
            if (-not $tokenObj) {
                $result.ErrorMessage = "Failed to retrieve newly created token"
                return $result
            }
        }

        # Check for empty Token
        if ([string]::IsNullOrWhiteSpace($tokenObj.Token)) {
            Write-LogMessage "Token '$($tokenObj.Id)' has empty Token value" -Level WARN
            
            $newToken = Request-MissingCredentials `
                -Reason "Token value is empty" `
                -ExistingId $tokenObj.Id `
                -ExistingEmail $tokenObj.Email `
                -ExistingOrganization $tokenObj.Organization
            
            if (-not $newToken) {
                $result.ErrorMessage = "Token '$($tokenObj.Id)' has empty Token value and user declined to update"
                return $result
            }
            
            # Re-read after update
            $tokenObj = Get-AzureAccessTokenById -IdLike $IdLike -AzureAccessTokensFileName $AzureAccessTokensFileName
        }

        # Check for missing Email
        if ([string]::IsNullOrWhiteSpace($tokenObj.Email)) {
            Write-LogMessage "Token '$($tokenObj.Id)' has no Email configured" -Level WARN
            
            $newToken = Request-MissingCredentials `
                -Reason "Email is missing" `
                -ExistingId $tokenObj.Id `
                -ExistingToken $tokenObj.Token `
                -ExistingOrganization $tokenObj.Organization
            
            if (-not $newToken) {
                $result.ErrorMessage = "Token '$($tokenObj.Id)' has no Email and user declined to update"
                return $result
            }
            
            # Re-read after update
            $tokenObj = Get-AzureAccessTokenById -IdLike $IdLike -AzureAccessTokensFileName $AzureAccessTokensFileName
        }

        # Final validation
        if ([string]::IsNullOrWhiteSpace($tokenObj.Token) -or [string]::IsNullOrWhiteSpace($tokenObj.Email)) {
            $result.ErrorMessage = "Credentials still incomplete after setup attempt"
            Write-LogMessage $result.ErrorMessage -Level ERROR
            return $result
        }

        # Success - populate result
        $result.Success = $true
        $result.Pat = $tokenObj.Token
        $result.Email = $tokenObj.Email
        $result.EmailEncoded = $tokenObj.Email.Replace('@', '%40')
        $result.Organization = $tokenObj.Organization
        $result.Id = $tokenObj.Id

        Write-LogMessage "Successfully loaded credentials for token '$($tokenObj.Id)'" -Level DEBUG
        Write-LogMessage "  Email: $($result.Email)" -Level DEBUG
        Write-LogMessage "  Email (URL-encoded): $($result.EmailEncoded)" -Level DEBUG
        Write-LogMessage "  Organization: $(if($result.Organization){$result.Organization}else{'<not set>'})" -Level DEBUG
        Write-LogMessage "  PAT Length: $($result.Pat.Length) characters" -Level DEBUG
    }
    catch {
        $result.ErrorMessage = "Error loading credentials: $($_.Exception.Message)"
        Write-LogMessage $result.ErrorMessage -Level ERROR -Exception $_

        # Emit rich diagnostics so failures are traceable without a debugger
        Write-LogMessage "  [DIAG] Exception type : $($_.Exception.GetType().FullName)" -Level ERROR
        Write-LogMessage "  [DIAG] Stack trace     : $($_.ScriptStackTrace)" -Level ERROR
        Write-LogMessage "  [DIAG] Failing object  : $($_.TargetObject | Out-String)" -Level ERROR

        # Dump what Get-AzureAccessTokensFile returned so we know if file was found at all
        try {
            $diagFile = Get-AzureAccessTokensFile -SkipCache
            Write-LogMessage "  [DIAG] AzureAccessTokens.json resolved path: $(if($diagFile.SelectedPath){$diagFile.SelectedPath}else{'<not found>'})" -Level ERROR
            if ($diagFile.SelectedPath -and (Test-Path $diagFile.SelectedPath)) {
                $rawJson = Get-Content $diagFile.SelectedPath -Raw -ErrorAction SilentlyContinue
                $parsed  = $rawJson | ConvertFrom-Json -ErrorAction SilentlyContinue
                $ids     = if ($parsed) { ($parsed | ForEach-Object { $_.Id }) -join ', ' } else { '<parse failed>' }
                Write-LogMessage "  [DIAG] Token Ids in file: $ids" -Level ERROR
                Write-LogMessage "  [DIAG] IdLike filter used: $IdLike" -Level ERROR
            }
        }
        catch {
            Write-LogMessage "  [DIAG] Secondary diagnostic query also failed: $($_.Exception.Message)" -Level ERROR
        }

        # Dump the cache state so we know if initialization was the problem
        Write-LogMessage "  [DIAG] Cache state - Result is null: $($null -eq $script:AzureAccessTokensFileCache.Result)" -Level ERROR
        Write-LogMessage "  [DIAG] Cache state - Timestamp: $($script:AzureAccessTokensFileCache.Timestamp)" -Level ERROR
    }

    return $result
}

function Assert-AzureDevOpsCliLogin {
    <#
    .SYNOPSIS
        Logs in to Azure DevOps CLI using a PAT (no env vars).

    .DESCRIPTION
        Loads PAT via Get-AzureDevOpsPat (AzureAccessTokens.json) and authenticates
        Azure DevOps CLI by running:

            <PAT> | az devops login --organization <orgUrl>

        Returns $true if login succeeded, otherwise $false.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$OrganizationUrl,

        [Parameter(Mandatory = $false)]
        [string]$IdLike = '*AzureDevOpsExtPat*',

        [Parameter(Mandatory = $false)]
        [string]$AzureAccessTokensFileName = 'AzureAccessTokens.json'
    )

    $pat = Get-AzureDevOpsPat -IdLike $IdLike -AzureAccessTokensFileName $AzureAccessTokensFileName
    if ([string]::IsNullOrWhiteSpace($pat)) {
        return $false
    }

    try {
        $null = ($pat | az devops login --organization $OrganizationUrl 2>&1)
        return ($LASTEXITCODE -eq 0)
    }
    catch {
        return $false
    }
}

function Test-AzureDevOpsPat {
    <#
    .SYNOPSIS
        Tests if an Azure DevOps PAT token is valid by making an API call.

    .DESCRIPTION
        Tests the PAT by making an HTTP request to Azure DevOps REST API.
        Returns a PSCustomObject with test results including success status,
        HTTP status code, and any error messages.

    .EXAMPLE
        $result = Test-AzureDevOpsPat -Pat "your-pat-token" -Organization "Dedge"
        if ($result.Success) { Write-Host "Token is valid" }
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$Pat,

        [Parameter(Mandatory = $true)]
        [string]$Organization,

        [Parameter(Mandatory = $false)]
        [string]$Project = $null
    )

    $result = [PSCustomObject]@{
        Success      = $false
        StatusCode   = $null
        ErrorMessage = $null
        TestTime     = Get-Date -Format 'yyyy-MM-dd HH:mm:ss'
    }

    if ([string]::IsNullOrWhiteSpace($Pat)) {
        $result.ErrorMessage = "PAT token is null or empty"
        return $result
    }

    try {
        # Construct API URL - test with organization info endpoint
        $apiUrl = "https://dev.azure.com/$Organization/_apis/projects?api-version=6.0"
        if ($Project) {
            $apiUrl = "https://dev.azure.com/$Organization/$Project/_apis/git/repositories?api-version=6.0"
        }

        # Create basic auth header
        $base64AuthInfo = [Convert]::ToBase64String([Text.Encoding]::ASCII.GetBytes(":$Pat"))
        $headers = @{
            Authorization = "Basic $base64AuthInfo"
        }

        # Make the API call
        $response = Invoke-WebRequest -Uri $apiUrl -Method Get -Headers $headers -UseBasicParsing -ErrorAction Stop

        $result.Success = $true
        $result.StatusCode = $response.StatusCode
    }
    catch {
        $result.Success = $false
        if ($_.Exception.Response) {
            $result.StatusCode = [int]$_.Exception.Response.StatusCode.value__
            $result.ErrorMessage = "HTTP $($result.StatusCode): $($_.Exception.Message)"
        }
        else {
            $result.StatusCode = 0
            $result.ErrorMessage = $_.Exception.Message
        }
    }

    return $result
}

function Update-AzureAccessTokensWithEmail {
    <#
    .SYNOPSIS
        Ensures all items in AzureAccessTokens.json have an Email property.

    .DESCRIPTION
        Reads AzureAccessTokens.json, checks each token entry for an Email property,
        and prompts the user for missing emails. For local files, uses the provided
        default email. Updates the JSON file with the email addresses.

    .PARAMETER DefaultEmail
        Default email address to use for local files when Email is missing.
        If not provided and running interactively, will prompt for each missing email.

    .PARAMETER AzureAccessTokensFileName
        Name of the AzureAccessTokens.json file to update.

    .EXAMPLE
        Update-AzureAccessTokensWithEmail -DefaultEmail "user@example.com"
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $false)]
        [string]$DefaultEmail = $null,

        [Parameter(Mandatory = $false)]
        [string]$AzureAccessTokensFileName = 'AzureAccessTokens.json'
    )

    $fileInfo = Get-AzureAccessTokensFile -AzureAccessTokensFileName $AzureAccessTokensFileName
    if (-not $fileInfo.SelectedPath) {
        Write-LogMessage "AzureAccessTokens.json file not found" -Level ERROR
        return $false
    }

    Write-LogMessage "Reading AzureAccessTokens.json from: $($fileInfo.SelectedPath)" -Level INFO

    try {
        $tokens = Get-AzureAccessTokens -AzureAccessTokensFileName $AzureAccessTokensFileName
        if (-not $tokens -or $tokens.Count -eq 0) {
            Write-LogMessage "No tokens found in AzureAccessTokens.json" -Level WARN
            return $false
        }

        $updated = $false
        $missingEmails = @()

        # Check each token for missing Email property
        foreach ($token in $tokens) {
            $hasEmail = $token.PSObject.Properties.Name -contains 'Email' -and -not [string]::IsNullOrWhiteSpace($token.Email)
            
            if (-not $hasEmail) {
                $missingEmails += $token
                Write-LogMessage "Token '$($token.Id)' is missing Email property" -Level WARN
            }
        }

        if ($missingEmails.Count -eq 0) {
            Write-LogMessage "All tokens already have Email property" -Level INFO
            return $true
        }

        # Determine if we should use default email or prompt
        $useDefault = $false
        if (-not [string]::IsNullOrWhiteSpace($DefaultEmail)) {
            $useDefault = $true
            Write-LogMessage "Using default email for missing entries: $DefaultEmail" -Level INFO
        }
        elseif (-not [Environment]::UserInteractive) {
            # Non-interactive session, use default if available
            if ($env:USERNAME -eq "FKGEISTA" -or $env:COMPUTERNAME -like "*30237*") {
                $DefaultEmail = "geir.helge.starholm@Dedge.no"
                $useDefault = $true
                Write-LogMessage "Non-interactive session detected, using default email: $DefaultEmail" -Level INFO
            }
            else {
                Write-LogMessage "Non-interactive session and no default email provided. Cannot update tokens." -Level ERROR
                return $false
            }
        }

        # Update missing emails
        foreach ($token in $missingEmails) {
            $email = $null
            
            if ($useDefault) {
                $email = $DefaultEmail
            }
            else {
                # Interactive prompt
                Write-Host "`nToken ID: $($token.Id)" -ForegroundColor Yellow
                if ($token.PSObject.Properties.Name -contains 'Description') {
                    Write-Host "Description: $($token.Description)" -ForegroundColor Gray
                }
                
                $promptText = "Enter email address for this token"
                if (-not [string]::IsNullOrWhiteSpace($DefaultEmail)) {
                    $promptText += " (or press Enter to use default: $DefaultEmail)"
                }
                $promptText += ":"
                
                $email = Read-Host $promptText
                
                if ([string]::IsNullOrWhiteSpace($email) -and -not [string]::IsNullOrWhiteSpace($DefaultEmail)) {
                    $email = $DefaultEmail
                }
                
                if ([string]::IsNullOrWhiteSpace($email)) {
                    Write-LogMessage "Email not provided for token '$($token.Id)', skipping..." -Level WARN
                    continue
                }
            }

            # Validate email format (basic check)
            if ($email -notmatch '^[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}$') {
                Write-LogMessage "Invalid email format for token '$($token.Id)': $email" -Level ERROR
                continue
            }

            # Add or update Email property
            if ($token.PSObject.Properties.Name -contains 'Email') {
                $token.Email = $email
            }
            else {
                $token | Add-Member -MemberType NoteProperty -Name "Email" -Value $email -Force
            }
            
            Write-LogMessage "Updated token '$($token.Id)' with email: $email" -Level INFO
            $updated = $true
        }

        if ($updated) {
            # Convert back to JSON and save
            $jsonContent = $tokens | ConvertTo-Json -Depth 10
            $jsonContent | Set-Content -Path $fileInfo.SelectedPath -Encoding UTF8 -Force
            Write-LogMessage "Successfully updated AzureAccessTokens.json with email addresses" -Level INFO
            return $true
        }
        else {
            Write-LogMessage "No tokens were updated" -Level WARN
            return $false
        }
    }
    catch {
        Write-LogMessage "Error updating AzureAccessTokens.json: $($_.Exception.Message)" -Level ERROR
        return $false
    }
}

function Register-AzureAccessToken {
    <#
    .SYNOPSIS
        Registers or updates a token entry in AzureAccessTokens.json.

    .DESCRIPTION
        Adds a new token entry or updates an existing one (matched by Id) in the
        AzureAccessTokens.json file. Supports all standard token properties:
        Id, Token, Email, Organization, Description.

        If the file doesn't exist, it creates a new file in the user's Documents folder.
        If a token with the same Id exists, it updates that entry (unless -NoUpdate is specified).

    .PARAMETER Id
        Unique identifier for the token entry (e.g., "AzureDevOpsExtPat").

    .PARAMETER Token
        The actual token/PAT value.

    .PARAMETER Email
        Email address associated with the token (required for Azure DevOps PAT).

    .PARAMETER Organization
        Azure DevOps organization name (e.g., "Dedge").

    .PARAMETER Description
        Optional description of what the token is used for.

    .PARAMETER ExpirationDate
        Optional expiration date for the token (for tracking purposes).

    .PARAMETER NoUpdate
        If specified, will not update existing entries with the same Id.
        Returns $false if entry already exists.

    .PARAMETER FilePath
        Optional specific file path to use. If not provided, uses the standard
        AzureAccessTokens.json location (Documents folder).

    .PARAMETER AzureAccessTokensFileName
        Name of the AzureAccessTokens.json file.

    .EXAMPLE
        Register-AzureAccessToken -Id "AzureDevOpsExtPat" -Token "xxx" -Email "user@domain.com" -Organization "myorg"

    .EXAMPLE
        Register-AzureAccessToken -Id "MyServicePat" -Token "yyy" -Email "svc@domain.com" -Description "Service account PAT"

    .OUTPUTS
        PSCustomObject with Success, Message, FilePath, and TokenEntry properties.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        [string]$Id,

        [Parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        [string]$Token,

        [Parameter(Mandatory = $true)]
        [ValidatePattern('^[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}$')]
        [string]$Email,

        [Parameter(Mandatory = $false)]
        [string]$Organization = $null,

        [Parameter(Mandatory = $false)]
        [string]$Description = $null,

        [Parameter(Mandatory = $false)]
        [datetime]$ExpirationDate = [datetime]::MinValue,

        [Parameter(Mandatory = $false)]
        [switch]$NoUpdate,

        [Parameter(Mandatory = $false)]
        [string]$FilePath = $null,

        [Parameter(Mandatory = $false)]
        [string]$AzureAccessTokensFileName = 'AzureAccessTokens.json'
    )

    $result = [PSCustomObject]@{
        Success    = $false
        Message    = $null
        FilePath   = $null
        TokenEntry = $null
        Action     = $null  # 'Created', 'Updated', or 'Skipped'
    }

    try {
        # Determine file path
        $targetFilePath = $FilePath
        if ([string]::IsNullOrWhiteSpace($targetFilePath)) {
            # Try to find existing file first
            $fileInfo = Get-AzureAccessTokensFile -AzureAccessTokensFileName $AzureAccessTokensFileName
            if ($fileInfo.SelectedPath) {
                $targetFilePath = $fileInfo.SelectedPath
                Write-LogMessage "Using existing AzureAccessTokens.json: $targetFilePath" -Level DEBUG
            }
            else {
                # Create new file in Documents folder
                $documentsPath = Join-Path $env:USERPROFILE 'Documents'
                if (-not (Test-Path $documentsPath -PathType Container)) {
                    New-Item -Path $documentsPath -ItemType Directory -Force | Out-Null
                }
                $targetFilePath = Join-Path $documentsPath $AzureAccessTokensFileName
                Write-LogMessage "Creating new AzureAccessTokens.json: $targetFilePath" -Level INFO
            }
        }

        $result.FilePath = $targetFilePath

        # Load existing tokens or create empty array
        $tokens = @()
        if (Test-Path $targetFilePath -PathType Leaf) {
            try {
                $content = Get-Content -LiteralPath $targetFilePath -Raw -ErrorAction Stop
                if (-not [string]::IsNullOrWhiteSpace($content)) {
                    $parsed = $content | ConvertFrom-Json
                    if ($parsed -is [System.Array]) {
                        $tokens = [System.Collections.ArrayList]@($parsed)
                    }
                    elseif ($null -ne $parsed) {
                        $tokens = [System.Collections.ArrayList]@($parsed)
                    }
                    else {
                        $tokens = [System.Collections.ArrayList]@()
                    }
                }
                else {
                    $tokens = [System.Collections.ArrayList]@()
                }
            }
            catch {
                Write-LogMessage "Error reading existing file, starting fresh: $($_.Exception.Message)" -Level WARN
                $tokens = [System.Collections.ArrayList]@()
            }
        }
        else {
            $tokens = [System.Collections.ArrayList]@()
        }

        # Check if token with same Id already exists
        $existingIndex = -1
        for ($i = 0; $i -lt $tokens.Count; $i++) {
            if ($tokens[$i].Id -eq $Id) {
                $existingIndex = $i
                break
            }
        }

        # Build the token entry with consistent property order
        $tokenEntry = [ordered]@{
            Id    = $Id
            Token = $Token
        }

        # Add Description if provided (after Id, before Email)
        if (-not [string]::IsNullOrWhiteSpace($Description)) {
            $tokenEntry['Description'] = $Description
        }

        # Add Email (required)
        $tokenEntry['Email'] = $Email

        # Add Organization if provided
        if (-not [string]::IsNullOrWhiteSpace($Organization)) {
            $tokenEntry['Organization'] = $Organization
        }

        # Add ExpirationDate if provided
        if ($ExpirationDate -ne [datetime]::MinValue) {
            $tokenEntry['ExpirationDate'] = $ExpirationDate.ToString('yyyy-MM-dd')
        }

        # Add metadata
        $tokenEntry['LastUpdated'] = (Get-Date).ToString('yyyy-MM-dd HH:mm:ss')

        # Convert to PSCustomObject for consistent JSON output
        $tokenEntryObject = [PSCustomObject]$tokenEntry

        if ($existingIndex -ge 0) {
            # Token exists
            if ($NoUpdate) {
                $result.Success = $false
                $result.Message = "Token with Id '$Id' already exists and -NoUpdate was specified"
                $result.Action = 'Skipped'
                $result.TokenEntry = $tokens[$existingIndex]
                Write-LogMessage $result.Message -Level WARN
                return $result
            }

            # Update existing entry
            $tokens[$existingIndex] = $tokenEntryObject
            $result.Action = 'Updated'
            Write-LogMessage "Updated existing token entry: $Id" -Level INFO
        }
        else {
            # Add new entry
            $tokens.Add($tokenEntryObject) | Out-Null
            $result.Action = 'Created'
            Write-LogMessage "Created new token entry: $Id" -Level INFO
        }

        # Convert to JSON with proper formatting
        # Ensure array format even for single item
        if ($tokens.Count -eq 1) {
            $jsonContent = "[$([Environment]::NewLine)    " + ($tokens[0] | ConvertTo-Json -Depth 10 -Compress:$false).Replace([Environment]::NewLine, "$([Environment]::NewLine)    ") + "$([Environment]::NewLine)]"
        }
        else {
            $jsonContent = $tokens | ConvertTo-Json -Depth 10
        }

        # Write to file
        $jsonContent | Set-Content -Path $targetFilePath -Encoding UTF8 -Force

        $result.Success = $true
        $result.Message = "Successfully $($result.Action.ToLower()) token '$Id' in $targetFilePath"
        $result.TokenEntry = $tokenEntryObject

        Write-LogMessage $result.Message -Level INFO
        Write-LogMessage "Token details - Id: $Id, Email: $Email, Organization: $(if($Organization){$Organization}else{'<not set>'})" -Level DEBUG
    }
    catch {
        $result.Success = $false
        $result.Message = "Error registering token: $($_.Exception.Message)"
        Write-LogMessage $result.Message -Level ERROR -Exception $_
    }

    return $result
}

function Remove-AzureAccessToken {
    <#
    .SYNOPSIS
        Removes a token entry from AzureAccessTokens.json.

    .DESCRIPTION
        Removes a token entry by Id from the AzureAccessTokens.json file.

    .PARAMETER Id
        The Id of the token entry to remove.

    .PARAMETER AzureAccessTokensFileName
        Name of the AzureAccessTokens.json file.

    .EXAMPLE
        Remove-AzureAccessToken -Id "OldToken"

    .OUTPUTS
        PSCustomObject with Success, Message, and RemovedEntry properties.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        [string]$Id,

        [Parameter(Mandatory = $false)]
        [string]$AzureAccessTokensFileName = 'AzureAccessTokens.json'
    )

    $result = [PSCustomObject]@{
        Success      = $false
        Message      = $null
        RemovedEntry = $null
    }

    try {
        $fileInfo = Get-AzureAccessTokensFile -AzureAccessTokensFileName $AzureAccessTokensFileName
        if (-not $fileInfo.SelectedPath) {
            $result.Message = "AzureAccessTokens.json file not found"
            Write-LogMessage $result.Message -Level ERROR
            return $result
        }

        $tokens = Get-AzureAccessTokens -AzureAccessTokensFileName $AzureAccessTokensFileName
        if (-not $tokens -or $tokens.Count -eq 0) {
            $result.Message = "No tokens found in AzureAccessTokens.json"
            Write-LogMessage $result.Message -Level WARN
            return $result
        }

        # Find and remove the token
        $tokenToRemove = $tokens | Where-Object { $_.Id -eq $Id }
        if (-not $tokenToRemove) {
            $result.Message = "Token with Id '$Id' not found"
            Write-LogMessage $result.Message -Level WARN
            return $result
        }

        $remainingTokens = @($tokens | Where-Object { $_.Id -ne $Id })
        $result.RemovedEntry = $tokenToRemove

        # Write updated array back to file
        if ($remainingTokens.Count -eq 0) {
            "[]" | Set-Content -Path $fileInfo.SelectedPath -Encoding UTF8 -Force
        }
        else {
            $jsonContent = $remainingTokens | ConvertTo-Json -Depth 10
            # Ensure array format for single item
            if ($remainingTokens.Count -eq 1) {
                $jsonContent = "[$([Environment]::NewLine)    " + ($remainingTokens[0] | ConvertTo-Json -Depth 10 -Compress:$false).Replace([Environment]::NewLine, "$([Environment]::NewLine)    ") + "$([Environment]::NewLine)]"
            }
            $jsonContent | Set-Content -Path $fileInfo.SelectedPath -Encoding UTF8 -Force
        }

        $result.Success = $true
        $result.Message = "Successfully removed token '$Id' from $($fileInfo.SelectedPath)"
        Write-LogMessage $result.Message -Level INFO
    }
    catch {
        $result.Success = $false
        $result.Message = "Error removing token: $($_.Exception.Message)"
        Write-LogMessage $result.Message -Level ERROR -Exception $_
    }

    return $result
}

function Get-AzureAccessTokenSummary {
    <#
    .SYNOPSIS
        Gets a summary of all tokens in AzureAccessTokens.json.

    .DESCRIPTION
        Returns a summary of all token entries without exposing the actual token values.
        Useful for listing and verifying token configurations.

    .PARAMETER AzureAccessTokensFileName
        Name of the AzureAccessTokens.json file.

    .PARAMETER ShowTokenPrefix
        If specified, shows the first N characters of the token. Default is 0 (hidden).

    .EXAMPLE
        Get-AzureAccessTokenSummary
        Get-AzureAccessTokenSummary -ShowTokenPrefix 10

    .OUTPUTS
        Array of PSCustomObjects with token summary information.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $false)]
        [string]$AzureAccessTokensFileName = 'AzureAccessTokens.json',

        [Parameter(Mandatory = $false)]
        [int]$ShowTokenPrefix = 0
    )

    $fileInfo = Get-AzureAccessTokensFile -AzureAccessTokensFileName $AzureAccessTokensFileName
    if (-not $fileInfo.SelectedPath) {
        Write-LogMessage "AzureAccessTokens.json file not found" -Level WARN
        return @()
    }

    $tokens = Get-AzureAccessTokens -AzureAccessTokensFileName $AzureAccessTokensFileName
    if (-not $tokens -or $tokens.Count -eq 0) {
        Write-LogMessage "No tokens found in AzureAccessTokens.json" -Level WARN
        return @()
    }

    $summary = @()
    foreach ($token in $tokens) {
        $tokenPreview = "***hidden***"
        if ($ShowTokenPrefix -gt 0 -and $token.Token) {
            $previewLength = [Math]::Min($ShowTokenPrefix, $token.Token.Length)
            $tokenPreview = $token.Token.Substring(0, $previewLength) + "..."
        }

        $summary += [PSCustomObject]@{
            Id             = $token.Id
            TokenPreview   = $tokenPreview
            TokenLength    = if ($token.Token) { $token.Token.Length } else { 0 }
            Email          = $token.Email
            Organization   = $token.Organization
            Description    = $token.Description
            ExpirationDate = $token.ExpirationDate
            LastUpdated    = $token.LastUpdated
        }
    }

    Write-LogMessage "Found $($summary.Count) token(s) in $($fileInfo.SelectedPath)" -Level INFO
    return $summary
}

#region Azure CLI / Key Vault

function Test-AzureConnection {
    <#
    .SYNOPSIS
        Tests if Azure CLI (az) is authenticated.
    #>
    [CmdletBinding()]
    param()
    try {
        $null = az account show --query name -o tsv 2>$null
        return ($LASTEXITCODE -eq 0)
    }
    catch { return $false }
}

function Assert-AzureCliLogin {
    <#
    .SYNOPSIS
        Ensures user is logged in to Azure CLI.
    #>
    [CmdletBinding()]
    param()
    if (Test-AzureConnection) { return }
    Write-LogMessage "Please log in to Azure..." -Level WARN
    az login
    if (-not (Test-AzureConnection)) {
        Write-LogMessage "Failed to authenticate with Azure. Exiting." -Level ERROR
        throw "Azure CLI authentication failed."
    }
}

function Test-AzureKeyVault {
    <#
    .SYNOPSIS
        Tests if an Azure Key Vault exists and is accessible.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][string]$KeyVaultName,
        [Parameter(Mandatory = $false)][string]$SubscriptionId = $null
    )
    $showArgs = @("keyvault", "show", "--name", $KeyVaultName)
    if ($SubscriptionId) { $showArgs += "--subscription"; $showArgs += $SubscriptionId }
    $null = az @showArgs 2>&1
    return ($LASTEXITCODE -eq 0)
}

function Assert-AzureKeyVaultAccess {
    <#
    .SYNOPSIS
        Ensures an Azure Key Vault exists and is accessible.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][string]$KeyVaultName,
        [Parameter(Mandatory = $false)][string]$SubscriptionId = $null
    )
    if (-not (Test-AzureKeyVault -KeyVaultName $KeyVaultName -SubscriptionId $SubscriptionId)) {
        Write-LogMessage "Key Vault '$KeyVaultName' not found or inaccessible." -Level ERROR
        throw "Key Vault '$KeyVaultName' not found or inaccessible."
    }
}

function ConvertTo-KeyVaultSecretName {
    <#
    .SYNOPSIS
        Normalizes secret names for Azure Key Vault (underscores to hyphens).
    #>
    [CmdletBinding()]
    param([Parameter(Mandatory = $false)][string]$Name)
    if ([string]::IsNullOrWhiteSpace($Name)) { return $Name }
    return $Name.Trim() -replace '_', '-'
}

function Invoke-AzKeyVaultSecretCmd {
    <#
    .SYNOPSIS
        Low-level Azure CLI wrapper for keyvault secret operations.
    #>
    [CmdletBinding()]
    param(
        [string]$SubCommand, [string]$VaultName, [string]$Name = $null, [string]$Value = $null,
        [string]$ContentType = $null, [string]$Subscription = $null, [switch]$UseFileForValue
    )
    $azCmdArgs = @("keyvault", "secret", $SubCommand, "--vault-name", $VaultName)
    if ($Name) { $azCmdArgs += "--name"; $azCmdArgs += $Name }
    $tmpFile = $null
    if ($UseFileForValue -and $Value) {
        $tmpFile = [System.IO.Path]::GetTempFileName()
        [System.IO.File]::WriteAllText($tmpFile, $Value, [System.Text.UTF8Encoding]::new($false))
        $azCmdArgs += "--file"; $azCmdArgs += $tmpFile
    }
    elseif ($Value) { $azCmdArgs += "--value"; $azCmdArgs += $Value }
    if ($ContentType -and $SubCommand -eq "set") { $azCmdArgs += "--content-type"; $azCmdArgs += $ContentType }
    if ($Subscription) { $azCmdArgs += "--subscription"; $azCmdArgs += $Subscription }
    try {
        $result = az @azCmdArgs 2>&1
        $exitCode = $LASTEXITCODE
    }
    finally {
        if ($tmpFile -and (Test-Path $tmpFile -ErrorAction SilentlyContinue)) {
            Remove-Item $tmpFile -Force -ErrorAction SilentlyContinue
        }
    }
    return @{ Output = $result; ExitCode = $exitCode }
}

function Set-AzureKeyVaultSecret {
    <#
    .SYNOPSIS
        Creates or updates an Azure Key Vault secret.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][string]$KeyVaultName,
        [Parameter(Mandatory = $true)][string]$SecretName,
        [Parameter(Mandatory = $true)][string]$SecretValue,
        [Parameter(Mandatory = $false)][string]$SubscriptionId = $null
    )
    $azSubArg = if ($SubscriptionId) { @("--subscription", $SubscriptionId) } else { @() }
    $secretShow = az keyvault secret show --vault-name $KeyVaultName --name $SecretName @azSubArg 2>$null
    $secretDeleted = az keyvault secret show-deleted --vault-name $KeyVaultName --name $SecretName @azSubArg 2>$null
    if ($secretShow) {
        Write-LogMessage "Updating existing secret '$SecretName'..." -Level INFO
        $r = Invoke-AzKeyVaultSecretCmd -SubCommand "set" -VaultName $KeyVaultName -Name $SecretName -Value $SecretValue -Subscription $SubscriptionId
    }
    elseif ($secretDeleted) {
        Write-LogMessage "Secret '$SecretName' is soft-deleted. Recovering first..." -Level WARN
        az keyvault secret recover --vault-name $KeyVaultName --name $SecretName @azSubArg 2>&1 | Out-Null
        if ($LASTEXITCODE -ne 0) { throw "Failed to recover soft-deleted secret '$SecretName'." }
        $r = Invoke-AzKeyVaultSecretCmd -SubCommand "set" -VaultName $KeyVaultName -Name $SecretName -Value $SecretValue -Subscription $SubscriptionId
    }
    else {
        Write-LogMessage "Creating new secret '$SecretName'..." -Level INFO
        $r = Invoke-AzKeyVaultSecretCmd -SubCommand "set" -VaultName $KeyVaultName -Name $SecretName -Value $SecretValue -Subscription $SubscriptionId
    }
    if ($r.ExitCode -ne 0) { Write-LogMessage "Secret Set failed: $($r.Output)" -Level ERROR; throw "Secret Set failed: $($r.Output)" }
    Write-LogMessage "Secret '$SecretName' created/updated successfully." -Level INFO
    return $r.Output
}

function Get-AzureKeyVaultSecret {
    <#
    .SYNOPSIS
        Retrieves an Azure Key Vault secret value.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][string]$KeyVaultName,
        [Parameter(Mandatory = $true)][string]$SecretName,
        [Parameter(Mandatory = $false)][string]$SubscriptionId = $null
    )
    $r = Invoke-AzKeyVaultSecretCmd -SubCommand "show" -VaultName $KeyVaultName -Name $SecretName -Subscription $SubscriptionId
    if ($r.ExitCode -ne 0) { Write-LogMessage "Failed to get secret '$SecretName': $($r.Output)" -Level ERROR; throw "Failed to get secret: $($r.Output)" }
    return $r.Output
}

function Get-AzureKeyVaultSecretList {
    <#
    .SYNOPSIS
        Lists Azure Key Vault secrets (key, contentType, lastChanged, enabled).
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][string]$KeyVaultName,
        [Parameter(Mandatory = $false)][string]$SubscriptionId = $null,
        [Parameter(Mandatory = $false)][switch]$FormatTable
    )
    $azSubArg = if ($SubscriptionId) { @("--subscription", $SubscriptionId) } else { @() }
    $result = az keyvault secret list --vault-name $KeyVaultName @azSubArg --query "[].{key:name, contentType:contentType, lastChanged:attributes.updated, enabled:attributes.enabled}" -o json 2>&1
    if ($LASTEXITCODE -ne 0) { Write-LogMessage "Failed to list secrets: $result" -Level ERROR; throw "Failed to list secrets: $result" }
    $list = $result | ConvertFrom-Json
    if ($FormatTable) { $list | Format-Table -AutoSize }
    else { return $list }
}

function Remove-AzureKeyVaultSecret {
    <#
    .SYNOPSIS
        Soft-deletes an Azure Key Vault secret.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][string]$KeyVaultName,
        [Parameter(Mandatory = $true)][string]$SecretName,
        [Parameter(Mandatory = $false)][string]$SubscriptionId = $null
    )
    $azSubArg = if ($SubscriptionId) { @("--subscription", $SubscriptionId) } else { @() }
    Write-LogMessage "Soft-deleting secret '$SecretName'..." -Level WARN
    az keyvault secret delete --vault-name $KeyVaultName --name $SecretName @azSubArg 2>&1 | Out-Null
    if ($LASTEXITCODE -ne 0) { throw "Failed to delete secret '$SecretName'." }
    Write-LogMessage "Secret '$SecretName' soft-deleted." -Level INFO
}

function Restore-AzureKeyVaultSecret {
    <#
    .SYNOPSIS
        Recovers a soft-deleted Azure Key Vault secret.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][string]$KeyVaultName,
        [Parameter(Mandatory = $true)][string]$SecretName,
        [Parameter(Mandatory = $false)][string]$SubscriptionId = $null
    )
    $azSubArg = if ($SubscriptionId) { @("--subscription", $SubscriptionId) } else { @() }
    Write-LogMessage "Recovering soft-deleted secret '$SecretName'..." -Level INFO
    az keyvault secret recover --vault-name $KeyVaultName --name $SecretName @azSubArg 2>&1 | Out-Null
    if ($LASTEXITCODE -ne 0) { throw "Failed to recover secret '$SecretName'." }
    Write-LogMessage "Secret '$SecretName' recovered successfully." -Level INFO
}

function Import-AzureKeyVaultSecretsFromTsv {
    <#
    .SYNOPSIS
        Imports secrets from a TSV file (contentType, key, secret) into Azure Key Vault.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][string]$KeyVaultName,
        [Parameter(Mandatory = $true)][string]$ImportPath,
        [Parameter(Mandatory = $false)][string]$SubscriptionId = $null,
        [Parameter(Mandatory = $false)][string]$ScriptRoot = $null
    )
    $resolvedPath = if ([System.IO.Path]::IsPathRooted($ImportPath)) { $ImportPath } else { Join-Path $ScriptRoot $ImportPath }
    if (-not (Test-Path $resolvedPath -PathType Leaf)) { throw "Import file not found: $resolvedPath" }
    $rows = Import-Csv -Path $resolvedPath -Delimiter "`t" -Encoding UTF8
    if (-not $rows -or $rows.Count -eq 0) { return @{ Imported = 0; Failed = 0 } }
    $requiredCols = @("contentType", "key", "secret")
    $firstRow = $rows | Select-Object -First 1
    foreach ($col in $requiredCols) {
        if (-not ($firstRow.PSObject.Properties.Name -contains $col)) { throw "TSV must have columns: contentType, key, secret. Missing: $col" }
    }
    $azSubArg = if ($SubscriptionId) { @("--subscription", $SubscriptionId) } else { @() }
    $imported = 0; $failed = 0
    foreach ($row in $rows) {
        $keyRaw = $row.key; $secretVal = $row.secret; $contentType = $row.contentType
        if ([string]::IsNullOrWhiteSpace($keyRaw)) { continue }
        $key = ConvertTo-KeyVaultSecretName -Name $keyRaw
        $secretDeleted = az keyvault secret show-deleted --vault-name $KeyVaultName --name $key @azSubArg 2>$null
        if ($secretDeleted) { az keyvault secret recover --vault-name $KeyVaultName --name $key @azSubArg 2>&1 | Out-Null }
        $ct = if ([string]::IsNullOrWhiteSpace($contentType)) { $null } else { $contentType.Trim() }
        $r = Invoke-AzKeyVaultSecretCmd -SubCommand "set" -VaultName $KeyVaultName -Name $key -Value $secretVal -ContentType $ct -Subscription $SubscriptionId -UseFileForValue
        if ($r.ExitCode -eq 0) { $imported++; Write-LogMessage "Imported: $key" -Level INFO }
        else { $failed++; Write-LogMessage "Failed '$key': $($r.Output)" -Level ERROR }
    }
    Write-LogMessage "Import complete: $imported succeeded, $failed failed." -Level INFO
    return @{ Imported = $imported; Failed = $failed }
}

function Export-AzureKeyVaultSecretsToTsv {
    <#
    .SYNOPSIS
        Exports Azure Key Vault secrets to a TSV file (contentType, key, secret).
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][string]$KeyVaultName,
        [Parameter(Mandatory = $true)][string]$OutputPath,
        [Parameter(Mandatory = $false)][string]$SubscriptionId = $null
    )
    $list = Get-AzureKeyVaultSecretList -KeyVaultName $KeyVaultName -SubscriptionId $SubscriptionId
    if (-not $list -or $list.Count -eq 0) {
        "contentType`tkey`tsecret" | Out-File -FilePath $OutputPath -Encoding utf8
        return
    }
    $lines = [System.Collections.Generic.List[string]]::new()
    $lines.Add("contentType`tkey`tsecret")
    foreach ($item in $list) {
        $key = $item.key; $contentType = if ($item.contentType) { $item.contentType } else { "" }
        try {
            $raw = Get-AzureKeyVaultSecret -KeyVaultName $KeyVaultName -SecretName $key -SubscriptionId $SubscriptionId
            $obj = $raw | ConvertFrom-Json
            $secretVal = if ($obj.value) { $obj.value } else { "" }
            $lines.Add("$contentType`t$key`t$secretVal")
            Write-LogMessage "Exported: $key" -Level INFO
        }
        catch { Write-LogMessage "Failed to export '$key': $($_.Exception.Message)" -Level ERROR }
    }
    $lines | Out-File -FilePath $OutputPath -Encoding utf8
    Write-LogMessage "Export complete: $($lines.Count - 1) secret(s) written to $OutputPath" -Level INFO
}

#endregion Azure CLI / Key Vault

#region Azure Blob Storage

function Assert-AzModule {
    <#
    .SYNOPSIS
        Ensures one or more Az.* PowerShell modules are available, installing if needed.

    .DESCRIPTION
        Handles the full bootstrap sequence required to install Az modules reliably on
        both Windows 11 developer machines and Windows Server 2025 Datacenter:

          1. Ensures the NuGet package provider is registered (required by Install-Module).
          2. Ensures PSGallery is trusted (avoids interactive prompts).
          3. For each requested module: checks availability, installs if missing, then imports.

        Scope selection:
          - AllUsers  : used when running as Administrator (servers, scheduled tasks).
          - CurrentUser: used for interactive developer sessions without elevation.

        On servers, modules installed in AllUsers scope are available to all users and
        service accounts, which is the correct behaviour for scheduled tasks and services.

    .PARAMETER ModuleNames
        One or more Az.* module names to ensure (e.g. 'Az.Storage', 'Az.Accounts').

    .PARAMETER MinimumVersion
        Optional minimum version requirement passed to Install-Module / Import-Module.

    .PARAMETER Force
        Re-installs even if the module is already present.

    .EXAMPLE
        Assert-AzModule -ModuleNames 'Az.Storage'

    .EXAMPLE
        Assert-AzModule -ModuleNames @('Az.Accounts', 'Az.Storage') -MinimumVersion '5.0.0'
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string[]]$ModuleNames,

        [string]$MinimumVersion = "",

        [switch]$Force
    )

    # ── Scope: AllUsers when elevated (servers/tasks), CurrentUser otherwise ──────
    $isAdmin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole(
        [Security.Principal.WindowsBuiltInRole]::Administrator)
    $scope = if ($isAdmin) { 'AllUsers' } else { 'CurrentUser' }

    Write-LogMessage "Assert-AzModule: scope=$scope elevated=$isAdmin modules=$($ModuleNames -join ', ')" -Level DEBUG

    # ── NuGet provider — required by Install-Module on fresh systems ──────────────
    try {
        $nuget = Get-PackageProvider -Name NuGet -ErrorAction SilentlyContinue
        if (-not $nuget -or $nuget.Version -lt [Version]'2.8.5.201') {
            Write-LogMessage "Installing NuGet package provider..." -Level INFO
            Install-PackageProvider -Name NuGet -MinimumVersion '2.8.5.201' -Scope $scope -Force -ErrorAction Stop | Out-Null
            Write-LogMessage "NuGet provider installed" -Level INFO
        }
    }
    catch {
        # On PS7 + PSResourceGet, NuGet provider may not be needed — continue anyway
        Write-LogMessage "NuGet provider check skipped: $($_.Exception.Message)" -Level DEBUG
    }

    # ── PSGallery trust — suppress confirmation prompts ───────────────────────────
    try {
        $gallery = Get-PSRepository -Name PSGallery -ErrorAction SilentlyContinue
        if ($gallery -and $gallery.InstallationPolicy -ne 'Trusted') {
            Set-PSRepository -Name PSGallery -InstallationPolicy Trusted -ErrorAction SilentlyContinue
            Write-LogMessage "PSGallery set to Trusted" -Level DEBUG
        }
    }
    catch {
        Write-LogMessage "PSGallery trust check skipped: $($_.Exception.Message)" -Level DEBUG
    }

    # ── Install and import each module ────────────────────────────────────────────
    foreach ($moduleName in $ModuleNames) {
        $importParams = @{ Name = $moduleName; ErrorAction = 'SilentlyContinue' }
        if ($MinimumVersion) { $importParams['MinimumVersion'] = $MinimumVersion }

        $alreadyLoaded = Get-Module -Name $moduleName
        if (-not $alreadyLoaded -or $Force) {
            $available = if ($MinimumVersion) {
                Get-Module -Name $moduleName -ListAvailable |
                Where-Object { $_.Version -ge [Version]$MinimumVersion } |
                Select-Object -First 1
            }
            else {
                Get-Module -Name $moduleName -ListAvailable | Select-Object -First 1
            }

            if (-not $available -or $Force) {
                Write-LogMessage "Installing $moduleName (scope: $scope)..." -Level INFO
                try {
                    $installParams = @{
                        Name         = $moduleName
                        Scope        = $scope
                        Force        = $true
                        AllowClobber = $true
                        Repository   = 'PSGallery'
                        ErrorAction  = 'Stop'
                    }
                    if ($MinimumVersion) { $installParams['MinimumVersion'] = $MinimumVersion }

                    Install-Module @installParams
                    Write-LogMessage "$moduleName installed successfully" -Level INFO
                }
                catch {
                    # AllUsers failed (e.g. no admin on this path) — fall back to CurrentUser
                    if ($scope -eq 'AllUsers') {
                        Write-LogMessage "AllUsers install failed, retrying as CurrentUser: $($_.Exception.Message)" -Level WARN
                        $installParams['Scope'] = 'CurrentUser'
                        Install-Module @installParams
                        Write-LogMessage "$moduleName installed to CurrentUser" -Level INFO
                    }
                    else {
                        throw
                    }
                }
            }

            Import-Module @importParams -Force
            Write-LogMessage "$moduleName loaded" -Level DEBUG
        }
    }
}

function Resolve-AzureStorageCredentials {
    <#
    .SYNOPSIS
        Internal helper — resolves Azure Storage credentials from config file or parameters.
    .DESCRIPTION
        Checks for AzureStorage.json in the caller's script folder first, then in the
        user config folder. Falls back to the supplied parameter values if neither exists.
        Returns a PSCustomObject with StorageAccountName and StorageAccountKey.
    #>
    param(
        [string]$StorageAccountName,
        [string]$StorageAccountKey,
        [string]$ConfigFolder = ""
    )

    $localConfig = if ($ConfigFolder) { Join-Path $ConfigFolder "AzureStorage.json" } else { $null }
    $userConfig = "C:\opt\data\UserConfig\$($env:USERNAME)\AzureStorage.json"
    $configFile = if ($localConfig -and (Test-Path $localConfig)) { $localConfig }
    elseif (Test-Path $userConfig) { $userConfig }
    else { $null }

    if ($configFile) {
        $cfg = Get-Content $configFile -Raw | ConvertFrom-Json
        if (-not [string]::IsNullOrWhiteSpace($cfg.StorageAccountKey)) {
            $StorageAccountName = $cfg.StorageAccountName
            $StorageAccountKey = $cfg.StorageAccountKey
            Write-LogMessage "Using credentials from $configFile" -Level INFO
        }
    }

    return [PSCustomObject]@{
        StorageAccountName = $StorageAccountName
        StorageAccountKey  = $StorageAccountKey
    }
}

function Invoke-AzureContainerUpload {
    <#
    .SYNOPSIS
        Uploads one or more files to an Azure Blob Storage container.

    .DESCRIPTION
        Validates and uploads files supplied via -UploadFileList. The caller is responsible
        for resolving which files to upload.

        Container is auto-created if it does not exist (private/Off).
        Blob path = yyyy/MM/dd/<filename> based on the file's LastWriteTime.

        Credentials are resolved from AzureStorage.json (ConfigFolder then user config)
        before falling back to parameter defaults.

    .PARAMETER StorageAccountName
        Azure Storage account name.

    .PARAMETER StorageAccountKey
        Azure Storage account key. Config file overrides this if present.

    .PARAMETER ContainerName
        Container name. Defaults to server hostname in lowercase. Auto-created if missing.

    .PARAMETER UploadFileList
        One or more full file paths to upload.

    .PARAMETER ConfigFolder
        Optional folder path to search for AzureStorage.json (typically the caller's PSScriptRoot).

    .EXAMPLE
        Invoke-AzureContainerUpload -UploadFileList "C:\reports\report.pdf"

    .EXAMPLE
        Invoke-AzureContainerUpload -UploadFileList @("C:\a.csv","C:\b.csv") -ContainerName "mycontainer"
    #>
    [CmdletBinding()]
    param(
        [string]$StorageAccountName = "pbackup14532",
        [string]$StorageAccountKey = "cFlkO82oWLXedSrgWFbCV38MWtfcd6D3Auxs98uLQuswOjeC6RU4kASA5LXpDjA+OgbKTKNxLmKmSrEDveKtrw==",
        [string]$ContainerName = "",
        [string[]]$UploadFileList = @(),
        [string]$ConfigFolder = ""
    )

    Assert-AzModule -ModuleNames @('Az.Accounts', 'Az.Storage')

    $creds = Resolve-AzureStorageCredentials `
        -StorageAccountName $StorageAccountName `
        -StorageAccountKey  $StorageAccountKey `
        -ConfigFolder       $ConfigFolder

    if ([string]::IsNullOrWhiteSpace($ContainerName)) {
        $ContainerName = $env:COMPUTERNAME.ToLower()
    }

    $ctx = New-AzStorageContext -StorageAccountName $creds.StorageAccountName -StorageAccountKey $creds.StorageAccountKey

    Write-LogMessage "Storage account : $($creds.StorageAccountName)" -Level INFO
    Write-LogMessage "Container       : $ContainerName" -Level INFO

    $container = Get-AzStorageContainer -Name $ContainerName -Context $ctx -ErrorAction SilentlyContinue
    if (-not $container) {
        Write-LogMessage "Container '$ContainerName' not found — creating..." -Level INFO
        New-AzStorageContainer -Name $ContainerName -Context $ctx -Permission Off | Out-Null
        Write-LogMessage "Container '$ContainerName' created (private)" -Level INFO
    }

    if ($UploadFileList.Count -eq 0) {
        Write-LogMessage "No files specified — use -UploadFileList to pass one or more file paths" -Level WARN
        return
    }

    $UploadFileLists = [System.Collections.Generic.List[System.IO.FileInfo]]::new()
    foreach ($path in $UploadFileList) {
        if (-not (Test-Path $path)) {
            throw "File not found: $path"
        }
        $UploadFileLists.Add((Get-Item $path))
    }

    Write-LogMessage "Files to upload: $($UploadFileLists.Count)" -Level INFO

    $result = [System.Collections.Generic.List[PSCustomObject]]::new()

    foreach ($file in $UploadFileLists) {
        $blobPath = "$($file.LastWriteTime.ToString('yyyy\/MM\/dd', [System.Globalization.CultureInfo]::InvariantCulture))/$($file.Name)"
        $sizeMB = [Math]::Round($file.Length / 1MB, 2)

        Write-LogMessage "Uploading: $($file.Name) ($sizeMB MB) -> $blobPath" -Level INFO
        $uploadStart = Get-Date

        Set-AzStorageBlobContent `
            -File      $file.FullName `
            -Container $ContainerName `
            -Blob      $blobPath `
            -Context   $ctx `
            -Force | Out-Null

        $elapsed = [Math]::Round(((Get-Date) - $uploadStart).TotalSeconds, 1)
        Write-LogMessage "  Done in $($elapsed)s" -Level INFO

        $result.Add([PSCustomObject]@{
                Name     = $file.Name
                SizeMB   = $sizeMB
                Date     = $file.LastWriteTime
                BlobPath = $blobPath
                Elapsed  = $elapsed
            })
    }

    $totalMB = [Math]::Round(($result | Measure-Object SizeMB -Sum).Sum, 2)
    Write-LogMessage "Upload complete: $($result.Count) file(s), $totalMB MB total" -Level INFO
    Write-LogMessage ($result | Format-Table Name, SizeMB, Date, Elapsed -AutoSize | Out-String) -Level INFO
}

function Invoke-AzureContainerDownload {
    <#
    .SYNOPSIS
        Downloads one or more blobs from an Azure Blob Storage container.

    .DESCRIPTION
        Downloads blobs specified by -BlobList from the given container to a local
        destination folder. Each blob is saved using only its filename (last path segment),
        preserving nothing of the yyyy/MM/dd folder structure unless -KeepBlobPath is set.

        Credentials are resolved from AzureStorage.json (ConfigFolder then user config)
        before falling back to parameter defaults.

    .PARAMETER StorageAccountName
        Azure Storage account name.

    .PARAMETER StorageAccountKey
        Azure Storage account key. Config file overrides this if present.

    .PARAMETER ContainerName
        Container name. Defaults to server hostname in lowercase.

    .PARAMETER BlobList
        One or more blob paths inside the container (e.g. '2026/02/26/report.pdf').

    .PARAMETER DestinationFolder
        Local folder where downloaded files are saved. Created if it does not exist.
        Defaults to the current directory.

    .PARAMETER KeepBlobPath
        When set, recreates the blob's folder structure under DestinationFolder.
        e.g. blob '2026/02/26/file.txt' -> '<DestinationFolder>\2026\02\26\file.txt'

    .PARAMETER ConfigFolder
        Optional folder path to search for AzureStorage.json (typically the caller's PSScriptRoot).

    .EXAMPLE
        Invoke-AzureContainerDownload -BlobList '2026/02/26/testupload.tst' -DestinationFolder 'C:\downloads'

    .EXAMPLE
        Invoke-AzureContainerDownload -BlobList @('2026/02/26/a.csv','2026/02/26/b.csv') -ContainerName 'mycontainer'
    #>
    [CmdletBinding()]
    param(
        [string]$StorageAccountName = "pbackup14532",
        [string]$StorageAccountKey = "cFlkO82oWLXedSrgWFbCV38MWtfcd6D3Auxs98uLQuswOjeC6RU4kASA5LXpDjA+OgbKTKNxLmKmSrEDveKtrw==",
        [string]$ContainerName = "",
        [string[]]$BlobList = @(),
        [string]$DestinationFolder = "",
        [switch]$KeepBlobPath,
        [string]$ConfigFolder = ""
    )

    Assert-AzModule -ModuleNames @('Az.Accounts', 'Az.Storage')

    $creds = Resolve-AzureStorageCredentials `
        -StorageAccountName $StorageAccountName `
        -StorageAccountKey  $StorageAccountKey `
        -ConfigFolder       $ConfigFolder

    if ([string]::IsNullOrWhiteSpace($ContainerName)) {
            $ContainerName = $env:COMPUTERNAME.ToLower()
        }

        if ([string]::IsNullOrWhiteSpace($DestinationFolder)) {
            $DestinationFolder = $PWD.Path
        }

        if (-not (Test-Path $DestinationFolder)) {
            New-Item -Path $DestinationFolder -ItemType Directory -Force | Out-Null
            Write-LogMessage "Created destination folder: $DestinationFolder" -Level INFO
        }

        Write-LogMessage "Storage account : $($creds.StorageAccountName)" -Level INFO
        Write-LogMessage "Container       : $ContainerName" -Level INFO
        Write-LogMessage "Destination     : $DestinationFolder" -Level INFO

        if ($BlobList.Count -eq 0) {
            Write-LogMessage "No blobs specified — use -BlobList to pass one or more blob paths" -Level WARN
            return
        }

        $ctx = New-AzStorageContext -StorageAccountName $creds.StorageAccountName -StorageAccountKey $creds.StorageAccountKey

        Write-LogMessage "Blobs to download: $($BlobList.Count)" -Level INFO

        $result = [System.Collections.Generic.List[PSCustomObject]]::new()

        foreach ($blobPath in $BlobList) {
            if ($KeepBlobPath) {
                # Recreate the blob folder structure locally
                $localRelative = $blobPath -replace '/', [System.IO.Path]::DirectorySeparatorChar
                $localPath = Join-Path $DestinationFolder $localRelative
                $localDir = Split-Path $localPath -Parent
                if (-not (Test-Path $localDir)) {
                    New-Item -Path $localDir -ItemType Directory -Force | Out-Null
                }
            }
            else {
                # Flatten — use only the filename
                $fileName = Split-Path $blobPath -Leaf
                $localPath = Join-Path $DestinationFolder $fileName
            }

            Write-LogMessage "Downloading: $blobPath -> $localPath" -Level INFO
            $downloadStart = Get-Date

            try {
                Get-AzStorageBlobContent `
                    -Blob      $blobPath `
                    -Container $ContainerName `
                    -Destination $localPath `
                    -Context   $ctx `
                    -Force | Out-Null
            }
            catch {
                Write-LogMessage "Failed to download '$blobPath': $($_.Exception.Message)" -Level ERROR
                continue
            }

            $elapsed = [Math]::Round(((Get-Date) - $downloadStart).TotalSeconds, 1)
            $sizeMB = if (Test-Path $localPath) { [Math]::Round((Get-Item $localPath).Length / 1MB, 2) } else { 0 }
            Write-LogMessage "  Done in $($elapsed)s ($sizeMB MB) -> $localPath" -Level INFO

            $result.Add([PSCustomObject]@{
                    BlobPath  = $blobPath
                    LocalPath = $localPath
                    SizeMB    = $sizeMB
                    Elapsed   = $elapsed
                })
        }

        $totalMB = [Math]::Round(($result | Measure-Object SizeMB -Sum).Sum, 2)
        Write-LogMessage "Download complete: $($result.Count) file(s), $totalMB MB total" -Level INFO
        Write-LogMessage ($result | Format-Table BlobPath, LocalPath, SizeMB, Elapsed -AutoSize | Out-String) -Level INFO
    }

    function Test-AzureContainerBlob {
        <#
    .SYNOPSIS
        Checks whether a specific blob already exists in an Azure Blob Storage container.

    .DESCRIPTION
        Returns a PSCustomObject with:
          - Exists      : [bool]   true if the blob was found
          - BlobPath    : [string] the blob path that was checked
          - ContainerName: [string] the container that was checked
          - SizeMB      : [double] size in MB if found, 0 otherwise
          - LastModified : [datetime?] UTC last-modified timestamp if found, $null otherwise

        Credentials are resolved from AzureStorage.json (ConfigFolder then user config)
        before falling back to parameter defaults.

    .PARAMETER StorageAccountName
        Azure Storage account name.

    .PARAMETER StorageAccountKey
        Azure Storage account key. Config file overrides this if present.

    .PARAMETER ContainerName
        Container name. Defaults to server hostname in lowercase.

    .PARAMETER BlobPath
        The blob path to check (e.g. '2026/02/26/report.pdf').

    .PARAMETER ConfigFolder
        Optional folder path to search for AzureStorage.json.

    .EXAMPLE
        $r = Test-AzureContainerBlob -BlobPath '2026/02/26/report.pdf' -ContainerName 'mycontainer'
        if ($r.Exists) { Write-Host "Already uploaded ($($r.SizeMB) MB, $($r.LastModified))" }

    .OUTPUTS
        PSCustomObject with Exists, BlobPath, ContainerName, SizeMB, LastModified.
    #>
        [CmdletBinding()]
        param(
            [string]$StorageAccountName = "pbackup14532",
            [string]$StorageAccountKey = "cFlkO82oWLXedSrgWFbCV38MWtfcd6D3Auxs98uLQuswOjeC6RU4kASA5LXpDjA+OgbKTKNxLmKmSrEDveKtrw==",
            [string]$ContainerName = "",
            [Parameter(Mandatory = $true)]
            [string]$BlobPath,
            [string]$ConfigFolder = ""
        )

        Assert-AzModule -ModuleNames @('Az.Accounts', 'Az.Storage')

        $creds = Resolve-AzureStorageCredentials `
            -StorageAccountName $StorageAccountName `
            -StorageAccountKey  $StorageAccountKey `
            -ConfigFolder       $ConfigFolder

        if ([string]::IsNullOrWhiteSpace($ContainerName)) {
            $ContainerName = $env:COMPUTERNAME.ToLower()
        }

        $ctx = New-AzStorageContext -StorageAccountName $creds.StorageAccountName -StorageAccountKey $creds.StorageAccountKey
        $blob = Get-AzStorageBlob -Blob $BlobPath -Container $ContainerName -Context $ctx -ErrorAction SilentlyContinue

        $result = [PSCustomObject]@{
            Exists        = $null -ne $blob
            BlobPath      = $BlobPath
            ContainerName = $ContainerName
            SizeMB        = if ($blob) { [Math]::Round($blob.Length / 1MB, 4) } else { 0 }
            LastModified  = if ($blob) { $blob.LastModified.UtcDateTime } else { $null }
        }

        $status = if ($result.Exists) { "EXISTS ($($result.SizeMB) MB, modified $($result.LastModified.ToString('yyyy-MM-dd HH:mm:ss')) UTC)" } else { "NOT FOUND" }
        Write-LogMessage "Blob '$BlobPath' in '$ContainerName': $status" -Level INFO

        return $result
    }

    function Remove-AzureContainerBlob {
        <#
    .SYNOPSIS
        Deletes one or more blobs from an Azure Blob Storage container.

    .DESCRIPTION
        Removes blobs specified by -BlobList from the given container.
        Each blob is logged before deletion. Non-existent blobs are warned and skipped.

        Credentials are resolved from AzureStorage.json (ConfigFolder then user config)
        before falling back to parameter defaults.

    .PARAMETER StorageAccountName
        Azure Storage account name.

    .PARAMETER StorageAccountKey
        Azure Storage account key. Config file overrides this if present.

    .PARAMETER ContainerName
        Container name. Defaults to server hostname in lowercase.

    .PARAMETER BlobList
        One or more blob paths to delete (e.g. '2026/02/26/report.pdf').

    .PARAMETER WhatIf
        Lists what would be deleted without actually removing anything.

    .PARAMETER ConfigFolder
        Optional folder path to search for AzureStorage.json.

    .EXAMPLE
        Remove-AzureContainerBlob -BlobList '2026/02/26/testupload.tst' -ContainerName '30237-fk'

    .EXAMPLE
        Remove-AzureContainerBlob -BlobList @('2026/02/26/a.txt','2026/02/26/b.txt') -WhatIf
    #>
        [CmdletBinding()]
        param(
            [string]$StorageAccountName = "pbackup14532",
            [string]$StorageAccountKey = "cFlkO82oWLXedSrgWFbCV38MWtfcd6D3Auxs98uLQuswOjeC6RU4kASA5LXpDjA+OgbKTKNxLmKmSrEDveKtrw==",
            [string]$ContainerName = "",
            [string[]]$BlobList = @(),
            [switch]$WhatIf,
            [string]$ConfigFolder = ""
        )

        Assert-AzModule -ModuleNames @('Az.Accounts', 'Az.Storage')

        $creds = Resolve-AzureStorageCredentials `
            -StorageAccountName $StorageAccountName `
            -StorageAccountKey  $StorageAccountKey `
            -ConfigFolder       $ConfigFolder

        if ([string]::IsNullOrWhiteSpace($ContainerName)) {
            $ContainerName = $env:COMPUTERNAME.ToLower()
        }

        Write-LogMessage "Storage account : $($creds.StorageAccountName)" -Level INFO
        Write-LogMessage "Container       : $ContainerName" -Level INFO
        if ($WhatIf) { Write-LogMessage "Mode            : WHATIF — no blobs will be deleted" -Level WARN }

        if ($BlobList.Count -eq 0) {
            Write-LogMessage "No blobs specified — use -BlobList to pass one or more blob paths" -Level WARN
            return
        }

        $ctx = New-AzStorageContext -StorageAccountName $creds.StorageAccountName -StorageAccountKey $creds.StorageAccountKey

        Write-LogMessage "Blobs to delete: $($BlobList.Count)" -Level INFO

        $deleted = [System.Collections.Generic.List[string]]::new()
        $skipped = [System.Collections.Generic.List[string]]::new()

        foreach ($blobPath in $BlobList) {
            $exists = Get-AzStorageBlob -Blob $blobPath -Container $ContainerName -Context $ctx -ErrorAction SilentlyContinue

            if (-not $exists) {
                Write-LogMessage "  NOT FOUND (skipped): $blobPath" -Level WARN
                $skipped.Add($blobPath)
                continue
            }

            if ($WhatIf) {
                Write-LogMessage "  WHATIF — would delete: $blobPath ($([Math]::Round($exists.Length / 1MB, 2)) MB)" -Level INFO
                $deleted.Add($blobPath)
            }
            else {
                Write-LogMessage "  Deleting: $blobPath" -Level INFO
                Remove-AzStorageBlob -Blob $blobPath -Container $ContainerName -Context $ctx -Force
                $deleted.Add($blobPath)
                Write-LogMessage "  Deleted: $blobPath" -Level INFO
            }
        }

        $action = if ($WhatIf) { "Would delete" } else { "Deleted" }
        Write-LogMessage "$action $($deleted.Count) blob(s), skipped $($skipped.Count) (not found)" -Level INFO
    }

    function Get-AzureContainerListContent {
        <#
    .SYNOPSIS
        Lists blobs in an Azure Storage container.

    .DESCRIPTION
        Connects to an Azure Storage account and lists blobs with name, size, and
        last modified date. Supports prefix filtering and a DaysBack time window.

        Credentials are resolved from AzureStorage.json (ConfigFolder then user config)
        before falling back to parameter defaults.

    .PARAMETER StorageAccountName
        Azure Storage account name.

    .PARAMETER StorageAccountKey
        Azure Storage account key. Config file overrides this if present.

    .PARAMETER ContainerName
        Container name. Defaults to server hostname in lowercase.

    .PARAMETER Filter
        Optional blob name prefix filter (e.g. "2026/02" for a specific month).

    .PARAMETER DaysBack
        Only return blobs modified within the last N days. 0 = all (default).

    .PARAMETER ConfigFolder
        Optional folder path to search for AzureStorage.json (typically the caller's PSScriptRoot).

    .EXAMPLE
        Get-AzureContainerListContent -ContainerName "mycontainer"

    .EXAMPLE
        Get-AzureContainerListContent -ContainerName "mycontainer" -Filter "2026/02" -DaysBack 7
    #>
        [CmdletBinding()]
        param(
            [string]$StorageAccountName = "pbackup14532",
            [string]$StorageAccountKey = "cFlkO82oWLXedSrgWFbCV38MWtfcd6D3Auxs98uLQuswOjeC6RU4kASA5LXpDjA+OgbKTKNxLmKmSrEDveKtrw==",
            [string]$ContainerName = "",
            [string]$Filter = "",
            [int]$DaysBack = 0,
            [string]$ConfigFolder = ""
        )

        Assert-AzModule -ModuleNames @('Az.Accounts', 'Az.Storage')

        $creds = Resolve-AzureStorageCredentials `
            -StorageAccountName $StorageAccountName `
            -StorageAccountKey  $StorageAccountKey `
            -ConfigFolder       $ConfigFolder

        if ([string]::IsNullOrWhiteSpace($ContainerName)) {
            $ContainerName = $env:COMPUTERNAME.ToLower()
        }

        Write-LogMessage "Storage account : $($creds.StorageAccountName)" -Level INFO
        Write-LogMessage "Container       : $ContainerName" -Level INFO
        if ($Filter) { Write-LogMessage "Filter          : $Filter*" -Level INFO }
        if ($DaysBack) { Write-LogMessage "DaysBack        : $DaysBack" -Level INFO }

        $ctx = New-AzStorageContext -StorageAccountName $creds.StorageAccountName -StorageAccountKey $creds.StorageAccountKey

        $listParams = @{ Container = $ContainerName; Context = $ctx }
        if ($Filter) { $listParams['Prefix'] = $Filter }

        Write-LogMessage "Fetching blob list..." -Level INFO
        $blobs = Get-AzStorageBlob @listParams

        if ($DaysBack -gt 0) {
            $cutoff = (Get-Date).AddDays(-$DaysBack)
            $blobs = $blobs | Where-Object { $_.LastModified.DateTime -gt $cutoff }
        }

        if (-not $blobs -or $blobs.Count -eq 0) {
            Write-LogMessage "No blobs found matching the criteria." -Level WARN
            return
        }

        $sorted = $blobs | Sort-Object { $_.LastModified } -Descending
        $totalBytes = ($sorted | Measure-Object -Property Length -Sum).Sum
        $totalGB = [Math]::Round($totalBytes / 1GB, 2)

        Write-LogMessage "Found $($sorted.Count) blob(s) — total size: $totalGB GB" -Level INFO

        $separator = '-' * 100
        Write-Host ""
        Write-Host $separator
        Write-Host ("{0,-60} {1,12} {2,-22}" -f "Name", "Size (MB)", "Last Modified (UTC)")
        Write-Host $separator
        foreach ($blob in $sorted) {
            $sizeMB = [Math]::Round($blob.Length / 1MB, 2)
            $modified = $blob.LastModified.UtcDateTime.ToString("yyyy-MM-dd HH:mm:ss")
            Write-Host ("{0,-60} {1,12:N2} {2,-22}" -f $blob.Name, $sizeMB, $modified)
        }
        Write-Host $separator
        Write-Host ("{0,-60} {1,12:N2} {2,-22}" -f "TOTAL ($($sorted.Count) files)", $([Math]::Round($totalBytes / 1MB, 2)), "")
        Write-Host ""
    }

    #endregion Azure Blob Storage

    #region Git Repository Cloning

    function Initialize-AzureDevOpsGitCredentials {
        <#
    .SYNOPSIS
        Configures Git credentials for non-interactive Azure DevOps operations.

    .DESCRIPTION
        Sets up environment variables and Git configuration to prevent interactive
        credential prompts. Writes PAT credentials to .git-credentials file.

    .PARAMETER Pat
        The Personal Access Token for authentication.

    .PARAMETER Email
        The email address associated with the PAT.
    #>
        [CmdletBinding()]
        param(
            [Parameter(Mandatory = $true)]
            [string]$Pat,

            [Parameter(Mandatory = $true)]
            [string]$Email
        )

        Write-LogMessage "Configuring Git credentials for non-interactive operation..." -Level DEBUG

        # Disable Git Credential Manager to prevent interactive dialogs
        $env:GCM_INTERACTIVE = "never"
        $env:GIT_TERMINAL_PROMPT = "0"
        $env:GIT_ASKPASS = "echo"
        $env:GCM_ALLOW_WINDOWSAUTH = "0"
        $env:GCM_CREDENTIAL_STORE = "plaintext"

        # Kill any running GCM processes
        Get-Process -Name "git-credential-manager*", "git-credential-manager-core*", "gcm*" -ErrorAction SilentlyContinue | 
        Stop-Process -Force -ErrorAction SilentlyContinue

        # Configure git to use store helper instead of credential managers
        git config --global --unset-all credential.helper manager-core 2>$null | Out-Null
        git config --global --unset-all credential.helper manager 2>$null | Out-Null
        git config --global --unset-all credential.helper wincred 2>$null | Out-Null
        git config --global credential.helper store 2>$null | Out-Null
        git config --global credential.interactive never 2>$null | Out-Null

        # Write credentials to .git-credentials file
        $gitCredentialsPath = Join-Path $env:USERPROFILE ".git-credentials"
        $emailEncoded = $Email.Replace('@', '%40')

        # Remove old Azure DevOps entries
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

        # Add credentials for Azure DevOps domains
        Add-Content -Path $gitCredentialsPath -Value "https://$($emailEncoded):$Pat@dev.azure.com"
        Add-Content -Path $gitCredentialsPath -Value "https://$($emailEncoded):$Pat@Dedge.visualstudio.com"

        Write-LogMessage "Git credentials configured successfully" -Level DEBUG
    }

    function Restore-GitCredentialManager {
        <#
    .SYNOPSIS
        Restores Git Credential Manager to normal operation after automated execution.
    #>
        [CmdletBinding()]
        param()

        try {
            git config --global --unset-all credential.helper store 2>$null | Out-Null
            git config --global --unset-all credential.interactive 2>$null | Out-Null
            git config --global credential.helper manager-core 2>$null | Out-Null

            Remove-Item Env:\GCM_INTERACTIVE -ErrorAction SilentlyContinue
            Remove-Item Env:\GIT_TERMINAL_PROMPT -ErrorAction SilentlyContinue
            Remove-Item Env:\GIT_ASKPASS -ErrorAction SilentlyContinue
            Remove-Item Env:\GCM_ALLOW_WINDOWSAUTH -ErrorAction SilentlyContinue
            Remove-Item Env:\GCM_CREDENTIAL_STORE -ErrorAction SilentlyContinue

            Write-LogMessage "Git Credential Manager restored" -Level DEBUG
        }
        catch {
            Write-LogMessage "Warning: Failed to restore Git Credential Manager: $($_.Exception.Message)" -Level WARN
        }
    }

    function Sync-AzureDevOpsRepository {
        <#
    .SYNOPSIS
        Clones or updates an Azure DevOps repository.

    .DESCRIPTION
        Clones a repository from Azure DevOps if it doesn't exist locally,
        or pulls the latest changes if it does. Uses AzureAccessTokens.json
        for authentication.

    .PARAMETER RepositoryName
        Name of the repository to clone (e.g., "Dedge", "DedgePsh").

    .PARAMETER TargetFolder
        Local folder path where the repository should be cloned to.

    .PARAMETER Organization
        Azure DevOps organization name. Default is "Dedge".

    .PARAMETER Project
        Azure DevOps project name. Default is "Dedge".

    .PARAMETER Force
        If specified, removes the existing repository and clones fresh.

    .EXAMPLE
        Sync-AzureDevOpsRepository -RepositoryName "DedgePsh" -TargetFolder "C:\opt\work\DedgePsh"

    .EXAMPLE
        Sync-AzureDevOpsRepository -RepositoryName "Dedge" -TargetFolder "C:\opt\work\Dedge" -Force

    .OUTPUTS
        PSCustomObject with Success, Action (Cloned/Pulled/Failed), and Message properties.
    #>
        [CmdletBinding()]
        param(
            [Parameter(Mandatory = $true)]
            [ValidateNotNullOrEmpty()]
            [string]$RepositoryName,

            [Parameter(Mandatory = $true)]
            [ValidateNotNullOrEmpty()]
            [string]$TargetFolder,

            [Parameter(Mandatory = $false)]
            [string]$Organization = "Dedge",

            [Parameter(Mandatory = $false)]
            [string]$Project = "Dedge",

            [Parameter(Mandatory = $false)]
            [switch]$Force
        )

        $result = [PSCustomObject]@{
            Success    = $false
            Action     = $null
            Message    = $null
            Repository = $RepositoryName
            Folder     = $TargetFolder
        }

        try {
            Write-LogMessage "Syncing repository: $RepositoryName to $TargetFolder" -Level INFO

            # Get Azure DevOps credentials
            $creds = Get-AzureDevOpsCredentials -PromptForMissing:$false -ErrorAction SilentlyContinue
        
            $repoBaseUrl = "dev.azure.com/$Organization/$Project/_git"
        
            if ($creds.Success) {
                # Configure Git credentials
                Initialize-AzureDevOpsGitCredentials -Pat $creds.Pat -Email $creds.Email
            
                # Build authenticated URL
                $emailEncoded = $creds.Email.Replace('@', '%40')
                $repoUrl = "https://$($emailEncoded):$($creds.Pat)@$repoBaseUrl/$RepositoryName"
            }
            else {
                Write-LogMessage "No Azure DevOps credentials available, attempting without explicit auth" -Level WARN
                $repoUrl = "https://$Organization@$repoBaseUrl/$RepositoryName"
            }

            $gitFolder = Join-Path $TargetFolder ".git"
            $repoExists = Test-Path $gitFolder

            # Handle Force flag - remove existing repo
            if ($Force -and $repoExists) {
                Write-LogMessage "Force flag set, removing existing repository..." -Level INFO
            
                # Use robocopy trick to handle locked files
                $emptyDir = Join-Path $env:TEMP "EmptyDir_$(Get-Random)"
                New-Item -Path $emptyDir -ItemType Directory -Force | Out-Null
                robocopy $emptyDir $TargetFolder /MIR /R:1 /W:1 /NJH /NJS /NFL /NDL /NC /NS 2>&1 | Out-Null
                Remove-Item -Path $emptyDir -Force -ErrorAction SilentlyContinue
                Remove-Item -Path $TargetFolder -Recurse -Force -ErrorAction SilentlyContinue
            
                $repoExists = $false
            }

            if ($repoExists) {
                # Pull latest changes
                Write-LogMessage "Repository exists, pulling latest changes..." -Level INFO
            
                Push-Location $TargetFolder
                try {
                    git reset --hard HEAD 2>&1 | Out-Null
                    git clean -fd 2>&1 | Out-Null
                    $pullOutput = git pull 2>&1
                
                    if ($LASTEXITCODE -eq 0) {
                        $result.Success = $true
                        $result.Action = "Pulled"
                        $result.Message = "Successfully pulled latest changes for $RepositoryName"
                        Write-LogMessage $result.Message -Level INFO
                    }
                    else {
                        $result.Action = "Failed"
                        $result.Message = "Git pull failed: $pullOutput"
                        Write-LogMessage $result.Message -Level WARN
                    }
                }
                finally {
                    Pop-Location
                }
            }
            else {
                # Clone repository
                Write-LogMessage "Cloning repository $RepositoryName..." -Level INFO
            
                # Create parent directory
                $parentDir = Split-Path $TargetFolder -Parent
                if (-not (Test-Path $parentDir)) {
                    New-Item -Path $parentDir -ItemType Directory -Force | Out-Null
                }

                $cloneOutput = git clone $repoUrl $TargetFolder 2>&1
            
                if ($LASTEXITCODE -eq 0) {
                    $result.Success = $true
                    $result.Action = "Cloned"
                    $result.Message = "Successfully cloned $RepositoryName to $TargetFolder"
                    Write-LogMessage $result.Message -Level INFO
                }
                else {
                    $result.Action = "Failed"
                    $result.Message = "Git clone failed: $cloneOutput"
                    Write-LogMessage $result.Message -Level ERROR
                }
            }

            # Restore Git Credential Manager
            if ($creds.Success) {
                Restore-GitCredentialManager
            }
        }
        catch {
            $result.Action = "Failed"
            $result.Message = "Error syncing repository: $($_.Exception.Message)"
            Write-LogMessage $result.Message -Level ERROR -Exception $_
        
            # Attempt to restore Git Credential Manager even on error
            Restore-GitCredentialManager
        }

        return $result
    }

    function Sync-MultipleAzureDevOpsRepositories {
        <#
    .SYNOPSIS
        Clones or updates multiple Azure DevOps repositories.

    .DESCRIPTION
        Syncs multiple repositories in a single call. Each repository is
        defined by name and target folder.

    .PARAMETER Repositories
        Array of hashtables with 'Name' and 'Folder' keys.

    .PARAMETER Organization
        Azure DevOps organization name. Default is "Dedge".

    .PARAMETER Project
        Azure DevOps project name. Default is "Dedge".

    .PARAMETER Force
        If specified, removes existing repositories and clones fresh.

    .EXAMPLE
        $repos = @(
            @{ Name = "Dedge"; Folder = "C:\opt\work\Dedge" },
            @{ Name = "DedgePsh"; Folder = "C:\opt\work\DedgePsh" }
        )
        Sync-MultipleAzureDevOpsRepositories -Repositories $repos

    .OUTPUTS
        PSCustomObject with overall Success status and array of Results per repository.
    #>
        [CmdletBinding()]
        param(
            [Parameter(Mandatory = $true)]
            [array]$Repositories,

            [Parameter(Mandatory = $false)]
            [string]$Organization = "Dedge",

            [Parameter(Mandatory = $false)]
            [string]$Project = "Dedge",

            [Parameter(Mandatory = $false)]
            [switch]$Force
        )

        $overallResult = [PSCustomObject]@{
            Success      = $false
            SuccessCount = 0
            FailedCount  = 0
            Results      = @()
        }

        foreach ($repo in $Repositories) {
            $repoResult = Sync-AzureDevOpsRepository `
                -RepositoryName $repo.Name `
                -TargetFolder $repo.Folder `
                -Organization $Organization `
                -Project $Project `
                -Force:$Force

            $overallResult.Results += $repoResult

            if ($repoResult.Success) {
                $overallResult.SuccessCount++
            }
            else {
                $overallResult.FailedCount++
            }
        }

        $overallResult.Success = ($overallResult.SuccessCount -gt 0)

        Write-LogMessage "Repository sync complete: $($overallResult.SuccessCount) succeeded, $($overallResult.FailedCount) failed" -Level INFO

        return $overallResult
    }

    function Get-AzureDevOpsRepositories {
        <#
    .SYNOPSIS
        Discovers all Git repositories in an Azure DevOps project.
    
    .DESCRIPTION
        Uses the Azure DevOps REST API to retrieve a list of all Git repositories
        in the specified project. Requires valid Azure DevOps credentials.
    
    .PARAMETER Organization
        Azure DevOps organization name. Default is "Dedge".
    
    .PARAMETER Project
        Azure DevOps project name. Default is "Dedge".
    
    .PARAMETER ApiVersion
        Azure DevOps API version. Default is "7.1".
    
    .EXAMPLE
        $repos = Get-AzureDevOpsRepositories -Organization "Dedge" -Project "Dedge"
        foreach ($repo in $repos) {
            Write-Host "Found repository: $($repo.Name)"
        }
    
    .OUTPUTS
        Array of hashtables with Name property for each repository.
        Returns empty array on failure.
    #>
        [CmdletBinding()]
        param(
            [Parameter(Mandatory = $false)]
            [string]$Organization = "Dedge",
        
            [Parameter(Mandatory = $false)]
            [string]$Project = "Dedge",
        
            [Parameter(Mandatory = $false)]
            [string]$ApiVersion = "7.1"
        )
    
        $repositories = @()
    
        try {
            Write-LogMessage "Discovering repositories in Azure DevOps project: $Organization/$Project" -Level INFO
        
            # Get Azure DevOps credentials
            $creds = Get-AzureDevOpsCredentials -PromptForMissing:$false -ErrorAction SilentlyContinue
        
            if (-not $creds.Success) {
                Write-LogMessage "No Azure DevOps credentials available for repository discovery" -Level WARN
                return $repositories
            }
        
            # Encode PAT for Authorization header
            $base64AuthInfo = [Convert]::ToBase64String([Text.Encoding]::ASCII.GetBytes(":$($creds.Pat)"))
            $headers = @{
                Authorization = "Basic $base64AuthInfo"
            }
        
            # Get the list of repositories using Azure DevOps REST API
            $reposUrl = "https://dev.azure.com/$Organization/$Project/_apis/git/repositories?api-version=$ApiVersion"
        
            Write-LogMessage "Calling Azure DevOps API: $reposUrl" -Level DEBUG
        
            $reposResponse = Invoke-RestMethod -Uri $reposUrl -Method Get -Headers $headers -ErrorAction Stop
        
            if ($reposResponse.value -and $reposResponse.value.Count -gt 0) {
                foreach ($repo in $reposResponse.value) {
                    $repositories += @{
                        Name      = $repo.name
                        Id        = $repo.id
                        Url       = $repo.url
                        RemoteUrl = $repo.remoteUrl
                    }
                }
            
                Write-LogMessage "Discovered $($repositories.Count) repositories in project $Project" -Level INFO
            }
            else {
                Write-LogMessage "No repositories found in project $Project" -Level WARN
            }
        }
        catch {
            Write-LogMessage "Error discovering repositories: $($_.Exception.Message)" -Level WARN
            Write-LogMessage "Stack trace: $($_.ScriptStackTrace)" -Level DEBUG
            return $repositories  # Return empty array on error
        }
    
        return $repositories
    }

    #endregion Git Repository Cloning

function Sync-AzureDevOpsRepository {
    <#
    .SYNOPSIS
        Clones or updates an Azure DevOps repository.

    .DESCRIPTION
        Clones a repository from Azure DevOps if it doesn't exist locally,
        or pulls the latest changes if it does. Uses AzureAccessTokens.json
        for authentication.

    .PARAMETER RepositoryName
        Name of the repository to clone (e.g., "Dedge", "DedgePsh").

    .PARAMETER TargetFolder
        Local folder path where the repository should be cloned to.

    .PARAMETER Organization
        Azure DevOps organization name. Default is "Dedge".

    .PARAMETER Project
        Azure DevOps project name. Default is "Dedge".

    .PARAMETER Force
        If specified, removes the existing repository and clones fresh.

    .EXAMPLE
        Sync-AzureDevOpsRepository -RepositoryName "DedgePsh" -TargetFolder "C:\opt\work\DedgePsh"

    .EXAMPLE
        Sync-AzureDevOpsRepository -RepositoryName "Dedge" -TargetFolder "C:\opt\work\Dedge" -Force

    .OUTPUTS
        PSCustomObject with Success, Action (Cloned/Pulled/Failed), and Message properties.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        [string]$RepositoryName,

        [Parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        [string]$TargetFolder,

        [Parameter(Mandatory = $false)]
        [string]$Organization = "Dedge",

        [Parameter(Mandatory = $false)]
        [string]$Project = "Dedge",

        [Parameter(Mandatory = $false)]
        [switch]$Force
    )

    $result = [PSCustomObject]@{
        Success    = $false
        Action     = $null
        Message    = $null
        Repository = $RepositoryName
        Folder     = $TargetFolder
    }

    try {
        Write-LogMessage "Syncing repository: $RepositoryName to $TargetFolder" -Level INFO

        # Get Azure DevOps credentials
        $creds = Get-AzureDevOpsCredentials -PromptForMissing:$false -ErrorAction SilentlyContinue
        
        $repoBaseUrl = "dev.azure.com/$Organization/$Project/_git"
        
        if ($creds.Success) {
            # Configure Git credentials
            Initialize-AzureDevOpsGitCredentials -Pat $creds.Pat -Email $creds.Email
            
            # Build authenticated URL
            $emailEncoded = $creds.Email.Replace('@', '%40')
            $repoUrl = "https://$($emailEncoded):$($creds.Pat)@$repoBaseUrl/$RepositoryName"
        }
        else {
            Write-LogMessage "No Azure DevOps credentials available, attempting without explicit auth" -Level WARN
            $repoUrl = "https://$Organization@$repoBaseUrl/$RepositoryName"
        }

        $gitFolder = Join-Path $TargetFolder ".git"
        $repoExists = Test-Path $gitFolder

        # Handle Force flag - remove existing repo
        if ($Force -and $repoExists) {
            Write-LogMessage "Force flag set, removing existing repository..." -Level INFO
            
            # Use robocopy trick to handle locked files
            $emptyDir = Join-Path $env:TEMP "EmptyDir_$(Get-Random)"
            New-Item -Path $emptyDir -ItemType Directory -Force | Out-Null
            robocopy $emptyDir $TargetFolder /MIR /R:1 /W:1 /NJH /NJS /NFL /NDL /NC /NS 2>&1 | Out-Null
            Remove-Item -Path $emptyDir -Force -ErrorAction SilentlyContinue
            Remove-Item -Path $TargetFolder -Recurse -Force -ErrorAction SilentlyContinue
            
            $repoExists = $false
        }

        if ($repoExists) {
            # Pull latest changes
            Write-LogMessage "Repository exists, pulling latest changes..." -Level INFO
            
            Push-Location $TargetFolder
            try {
                git reset --hard HEAD 2>&1 | Out-Null
                git clean -fd 2>&1 | Out-Null
                $pullOutput = git pull 2>&1
                
                if ($LASTEXITCODE -eq 0) {
                    $result.Success = $true
                    $result.Action = "Pulled"
                    $result.Message = "Successfully pulled latest changes for $RepositoryName"
                    Write-LogMessage $result.Message -Level INFO
                }
                else {
                    $result.Action = "Failed"
                    $result.Message = "Git pull failed: $pullOutput"
                    Write-LogMessage $result.Message -Level WARN
                }
            }
            finally {
                Pop-Location
            }
        }
        else {
            # Clone repository
            Write-LogMessage "Cloning repository $RepositoryName..." -Level INFO
            
            # Create parent directory
            $parentDir = Split-Path $TargetFolder -Parent
            if (-not (Test-Path $parentDir)) {
                New-Item -Path $parentDir -ItemType Directory -Force | Out-Null
            }

            $cloneOutput = git clone $repoUrl $TargetFolder 2>&1
            
            if ($LASTEXITCODE -eq 0) {
                $result.Success = $true
                $result.Action = "Cloned"
                $result.Message = "Successfully cloned $RepositoryName to $TargetFolder"
                Write-LogMessage $result.Message -Level INFO
            }
            else {
                $result.Action = "Failed"
                $result.Message = "Git clone failed: $cloneOutput"
                Write-LogMessage $result.Message -Level ERROR
            }
        }

        # Restore Git Credential Manager
        if ($creds.Success) {
            Restore-GitCredentialManager
        }
    }
    catch {
        $result.Action = "Failed"
        $result.Message = "Error syncing repository: $($_.Exception.Message)"
        Write-LogMessage $result.Message -Level ERROR -Exception $_
        
        # Attempt to restore Git Credential Manager even on error
        Restore-GitCredentialManager
    }

    return $result
}

function Sync-MultipleAzureDevOpsRepositories {
    <#
    .SYNOPSIS
        Clones or updates multiple Azure DevOps repositories.

    .DESCRIPTION
        Syncs multiple repositories in a single call. Each repository is
        defined by name and target folder.

    .PARAMETER Repositories
        Array of hashtables with 'Name' and 'Folder' keys.

    .PARAMETER Organization
        Azure DevOps organization name. Default is "Dedge".

    .PARAMETER Project
        Azure DevOps project name. Default is "Dedge".

    .PARAMETER Force
        If specified, removes existing repositories and clones fresh.

    .EXAMPLE
        $repos = @(
            @{ Name = "Dedge"; Folder = "C:\opt\work\Dedge" },
            @{ Name = "DedgePsh"; Folder = "C:\opt\work\DedgePsh" }
        )
        Sync-MultipleAzureDevOpsRepositories -Repositories $repos

    .OUTPUTS
        PSCustomObject with overall Success status and array of Results per repository.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [array]$Repositories,

        [Parameter(Mandatory = $false)]
        [string]$Organization = "Dedge",

        [Parameter(Mandatory = $false)]
        [string]$Project = "Dedge",

        [Parameter(Mandatory = $false)]
        [switch]$Force
    )

    $overallResult = [PSCustomObject]@{
        Success      = $false
        SuccessCount = 0
        FailedCount  = 0
        Results      = @()
    }

    foreach ($repo in $Repositories) {
        $repoResult = Sync-AzureDevOpsRepository `
            -RepositoryName $repo.Name `
            -TargetFolder $repo.Folder `
            -Organization $Organization `
            -Project $Project `
            -Force:$Force

        $overallResult.Results += $repoResult

        if ($repoResult.Success) {
            $overallResult.SuccessCount++
        }
        else {
            $overallResult.FailedCount++
        }
    }

    $overallResult.Success = ($overallResult.SuccessCount -gt 0)

    Write-LogMessage "Repository sync complete: $($overallResult.SuccessCount) succeeded, $($overallResult.FailedCount) failed" -Level INFO

    return $overallResult
}

function Get-AzureDevOpsRepositories {
    <#
    .SYNOPSIS
        Discovers all Git repositories in an Azure DevOps project.
    
    .DESCRIPTION
        Uses the Azure DevOps REST API to retrieve a list of all Git repositories
        in the specified project. Requires valid Azure DevOps credentials.
    
    .PARAMETER Organization
        Azure DevOps organization name. Default is "Dedge".
    
    .PARAMETER Project
        Azure DevOps project name. Default is "Dedge".
    
    .PARAMETER ApiVersion
        Azure DevOps API version. Default is "7.1".
    
    .EXAMPLE
        $repos = Get-AzureDevOpsRepositories -Organization "Dedge" -Project "Dedge"
        foreach ($repo in $repos) {
            Write-Host "Found repository: $($repo.Name)"
        }
    
    .OUTPUTS
        Array of hashtables with Name property for each repository.
        Returns empty array on failure.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $false)]
        [string]$Organization = "Dedge",
        
        [Parameter(Mandatory = $false)]
        [string]$Project = "Dedge",
        
        [Parameter(Mandatory = $false)]
        [string]$ApiVersion = "7.1"
    )
    
    $repositories = @()
    
    try {
        Write-LogMessage "Discovering repositories in Azure DevOps project: $Organization/$Project" -Level INFO
        
        # Get Azure DevOps credentials
        $creds = Get-AzureDevOpsCredentials -PromptForMissing:$false -ErrorAction SilentlyContinue
        
        if (-not $creds.Success) {
            Write-LogMessage "No Azure DevOps credentials available for repository discovery" -Level WARN
            return $repositories
        }
        
        # Encode PAT for Authorization header
        $base64AuthInfo = [Convert]::ToBase64String([Text.Encoding]::ASCII.GetBytes(":$($creds.Pat)"))
        $headers = @{
            Authorization = "Basic $base64AuthInfo"
        }
        
        # Get the list of repositories using Azure DevOps REST API
        $reposUrl = "https://dev.azure.com/$Organization/$Project/_apis/git/repositories?api-version=$ApiVersion"
        
        Write-LogMessage "Calling Azure DevOps API: $reposUrl" -Level DEBUG
        
        $reposResponse = Invoke-RestMethod -Uri $reposUrl -Method Get -Headers $headers -ErrorAction Stop
        
        if ($reposResponse.value -and $reposResponse.value.Count -gt 0) {
            foreach ($repo in $reposResponse.value) {
                $repositories += @{
                    Name = $repo.name
                    Id = $repo.id
                    Url = $repo.url
                    RemoteUrl = $repo.remoteUrl
                }
            }
            
            Write-LogMessage "Discovered $($repositories.Count) repositories in project $Project" -Level INFO
        }
        else {
            Write-LogMessage "No repositories found in project $Project" -Level WARN
        }
    }
    catch {
        Write-LogMessage "Error discovering repositories: $($_.Exception.Message)" -Level WARN
        Write-LogMessage "Stack trace: $($_.ScriptStackTrace)" -Level DEBUG
        return $repositories  # Return empty array on error
    }
    
    return $repositories
}

#endregion Git Repository Cloning

#region Azure DevOps Repository Creation
C:\opt\src\DedgePsh\_Modules\AzureFunctions\AzureFunctions.psm1
function New-AzureDevOpsRepo {
    <#
    .SYNOPSIS
        Creates a new Git repository in an Azure DevOps project, initializes local git,
        and optionally pushes all code.

    .DESCRIPTION
        End-to-end workflow for publishing a local source folder to a new Azure DevOps repo:
          1. Ensures Azure CLI + DevOps extension are installed and logged in.
          2. Creates a new repo in the specified project via 'az repos create'.
          3. Initializes git in the local folder (if not already a repo).
          4. Adds the Azure DevOps remote.
          5. Optionally creates the initial commit and pushes all code.

        Requires the Azure DevOps CLI extension and valid credentials
        (PAT via Assert-AzureDevOpsCliLogin).

    .PARAMETER RepoName
        Name of the new repository to create in Azure DevOps.

    .PARAMETER LocalPath
        Path to the local source folder. Defaults to the current directory.

    .PARAMETER Organization
        Azure DevOps organization name. Default: "Dedge".

    .PARAMETER Project
        Azure DevOps project name. Default: "Dedge".

    .PARAMETER CommitMessage
        Commit message for the initial commit. If empty, no commit/push is performed.

    .PARAMETER GitIgnoreContent
        Content for a .gitignore file. If provided and no .gitignore exists, one is created.
        Use the special value 'dotnet' for a standard .NET gitignore (bin/, obj/, .vs/, *.user).

    .PARAMETER SkipPush
        If set, creates the repo and initializes git but does not commit or push.

    .EXAMPLE
        New-AzureDevOpsRepo -RepoName "MyApp" -LocalPath "C:\opt\src\MyApp" -CommitMessage "Initial commit"

    .EXAMPLE
        New-AzureDevOpsRepo -RepoName "MyLib" -GitIgnoreContent 'dotnet'

    .EXAMPLE
        New-AzureDevOpsRepo -RepoName "Scripts" -Project "Infrastructure" -SkipPush

    .OUTPUTS
        PSCustomObject with Success, RepoName, RemoteUrl, RepoId, and ErrorMessage properties.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$RepoName,

        [Parameter(Mandatory = $false)]
        [string]$LocalPath = (Get-Location).Path,

        [Parameter(Mandatory = $false)]
        [string]$Organization = "Dedge",

        [Parameter(Mandatory = $false)]
        [string]$Project = "Dedge",

        [Parameter(Mandatory = $false)]
        [string]$CommitMessage = "",

        [Parameter(Mandatory = $false)]
        [string]$GitIgnoreContent = "",

        [switch]$SkipPush
    )

    $result = [PSCustomObject]@{
        Success      = $false
        RepoName     = $RepoName
        RemoteUrl    = ""
        RepoId       = ""
        ErrorMessage = ""
    }

    # ── Pre-flight checks ────────────────────────────────────────────────────
    if (-not (Test-Path $LocalPath -PathType Container)) {
        $result.ErrorMessage = "Local path does not exist: $($LocalPath)"
        Write-LogMessage $result.ErrorMessage -Level ERROR
        return $result
    }

    $azCmd = Get-Command az -ErrorAction SilentlyContinue
    if (-not $azCmd) {
        $result.ErrorMessage = "Azure CLI (az) is not installed or not in PATH"
        Write-LogMessage $result.ErrorMessage -Level ERROR
        return $result
    }

    $gitCmd = Get-Command git -ErrorAction SilentlyContinue
    if (-not $gitCmd) {
        $result.ErrorMessage = "Git is not installed or not in PATH"
        Write-LogMessage $result.ErrorMessage -Level ERROR
        return $result
    }

    # ── Azure DevOps CLI login ───────────────────────────────────────────────
    $orgUrl = "https://dev.azure.com/$($Organization)"
    Write-LogMessage "Ensuring Azure DevOps CLI login for $($orgUrl)" -Level INFO

    $loginOk = Assert-AzureDevOpsCliLogin -OrganizationUrl $orgUrl
    if (-not $loginOk) {
        $result.ErrorMessage = "Failed to authenticate with Azure DevOps CLI. Check your PAT in AzureAccessTokens.json."
        Write-LogMessage $result.ErrorMessage -Level ERROR
        return $result
    }

    az devops configure --defaults "organization=$($orgUrl)" "project=$($Project)" 2>&1 | Out-Null

    # ── Check if repo already exists ─────────────────────────────────────────
    Write-LogMessage "Checking if repo '$($RepoName)' already exists in $($Organization)/$($Project)" -Level INFO
    $existingRepos = az repos list --project $Project -o json 2>&1
    if ($LASTEXITCODE -eq 0) {
        $repoList = $existingRepos | ConvertFrom-Json
        $existing = $repoList | Where-Object { $_.name -eq $RepoName }
        if ($existing) {
            Write-LogMessage "Repo '$($RepoName)' already exists (ID: $($existing.id))" -Level WARN
            $result.RepoId = $existing.id
            $result.RemoteUrl = "https://dev.azure.com/$($Organization)/$($Project)/_git/$($RepoName)"
            $result.ErrorMessage = "Repository already exists"

            $hasRemote = git -C $LocalPath remote 2>&1
            if ($LASTEXITCODE -eq 0 -and $hasRemote -contains 'origin') {
                Write-LogMessage "Remote 'origin' already configured" -Level INFO
            }
            elseif (Test-Path (Join-Path $LocalPath '.git') -PathType Container) {
                git -C $LocalPath remote add origin $result.RemoteUrl 2>&1 | Out-Null
                Write-LogMessage "Added remote 'origin' pointing to existing repo" -Level INFO
            }

            $result.Success = $true
            return $result
        }
    }

    # ── Create the repo ──────────────────────────────────────────────────────
    Write-LogMessage "Creating repo '$($RepoName)' in $($Organization)/$($Project)" -Level INFO
    $createOutput = az repos create --name $RepoName --project $Project -o json 2>&1
    if ($LASTEXITCODE -ne 0) {
        $result.ErrorMessage = "az repos create failed: $($createOutput)"
        Write-LogMessage $result.ErrorMessage -Level ERROR
        return $result
    }

    $repoInfo = $createOutput | ConvertFrom-Json
    $result.RepoId = $repoInfo.id
    $result.RemoteUrl = "https://dev.azure.com/$($Organization)/$($Project)/_git/$($RepoName)"
    Write-LogMessage "Repo created: $($result.RemoteUrl) (ID: $($result.RepoId))" -Level INFO

    # ── Initialize local git ─────────────────────────────────────────────────
    $gitDir = Join-Path $LocalPath '.git'
    if (-not (Test-Path $gitDir -PathType Container)) {
        Write-LogMessage "Initializing git in $($LocalPath)" -Level INFO
        git -C $LocalPath init 2>&1 | Out-Null
        if ($LASTEXITCODE -ne 0) {
            $result.ErrorMessage = "git init failed"
            Write-LogMessage $result.ErrorMessage -Level ERROR
            return $result
        }
    }
    else {
        Write-LogMessage "Git already initialized in $($LocalPath)" -Level INFO
    }

    # ── Add remote ───────────────────────────────────────────────────────────
    $remotes = git -C $LocalPath remote 2>&1
    if ($remotes -contains 'origin') {
        $currentUrl = git -C $LocalPath remote get-url origin 2>&1
        if ($currentUrl -ne $result.RemoteUrl) {
            Write-LogMessage "Updating remote 'origin' from '$($currentUrl)' to '$($result.RemoteUrl)'" -Level WARN
            git -C $LocalPath remote set-url origin $result.RemoteUrl 2>&1 | Out-Null
        }
    }
    else {
        git -C $LocalPath remote add origin $result.RemoteUrl 2>&1 | Out-Null
        Write-LogMessage "Added remote 'origin': $($result.RemoteUrl)" -Level INFO
    }

    # ── Create .gitignore if requested ───────────────────────────────────────
    $gitignorePath = Join-Path $LocalPath '.gitignore'
    if ($GitIgnoreContent -and -not (Test-Path $gitignorePath)) {
        if ($GitIgnoreContent -eq 'dotnet') {
            $GitIgnoreContent = @"
bin/
obj/
*.user
*.suo
.vs/
*.DotSettings.user
"@
        }
        Set-Content -Path $gitignorePath -Value $GitIgnoreContent -Encoding utf8
        Write-LogMessage "Created .gitignore" -Level INFO
    }

    # ── Commit and push ──────────────────────────────────────────────────────
    if ($SkipPush) {
        Write-LogMessage "SkipPush specified — repo created and git initialized, no commit/push" -Level INFO
        $result.Success = $true
        return $result
    }

    if ([string]::IsNullOrWhiteSpace($CommitMessage)) {
        $CommitMessage = "Initial commit - $($RepoName)"
    }

    Write-LogMessage "Staging all files in $($LocalPath)" -Level INFO
    git -C $LocalPath add -A 2>&1 | Out-Null

    $status = git -C $LocalPath status --porcelain 2>&1
    if (-not $status) {
        Write-LogMessage "No files to commit" -Level WARN
        $result.Success = $true
        return $result
    }

    $fileCount = @($status).Count
    Write-LogMessage "Committing $($fileCount) file(s): $($CommitMessage)" -Level INFO
    git -C $LocalPath commit -m $CommitMessage 2>&1 | Out-Null
    if ($LASTEXITCODE -ne 0) {
        $result.ErrorMessage = "git commit failed"
        Write-LogMessage $result.ErrorMessage -Level ERROR
        return $result
    }

    Write-LogMessage "Pushing to origin/main" -Level INFO
    $pushOutput = git -C $LocalPath push -u origin main 2>&1
    if ($LASTEXITCODE -ne 0) {
        $branchName = git -C $LocalPath branch --show-current 2>&1
        Write-LogMessage "Retrying push with branch '$($branchName)'" -Level WARN
        $pushOutput = git -C $LocalPath push -u origin $branchName 2>&1
        if ($LASTEXITCODE -ne 0) {
            $result.ErrorMessage = "git push failed: $($pushOutput)"
            Write-LogMessage $result.ErrorMessage -Level ERROR
            return $result
        }
    }

    Write-LogMessage "Successfully pushed to $($result.RemoteUrl)" -Level INFO
    $result.Success = $true
    return $result
}

#endregion Azure DevOps Repository Creation

#region Azure DevOps REST API — Work Items

function Invoke-AdoRestApi {
    <#
    .SYNOPSIS
        Generic Azure DevOps REST API caller with PAT auth, bearer fallback, and UTF-8 encoding.
    .DESCRIPTION
        Sends an HTTP request to the Azure DevOps REST API. Authentication is resolved automatically:
        1. PAT via Get-AzureDevOpsPat (AzureAccessTokens.json)
        2. Bearer token via az account get-access-token (Azure CLI)
        3. Throws with fix instructions if both fail

        Request bodies are serialized to JSON and encoded as UTF-8 bytes to preserve
        Norwegian characters (æøåÆØÅ) in titles, descriptions, and comments.
    .PARAMETER Uri
        Full REST API URI.
    .PARAMETER Method
        HTTP method (Get, Post, Patch, Delete).
    .PARAMETER Body
        Request body — accepts a hashtable/array (auto-serialized) or a JSON string.
    .PARAMETER ContentType
        Content type header. Default: application/json-patch+json; charset=utf-8
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Uri,

        [Parameter(Mandatory)]
        [ValidateSet('Get', 'Post', 'Patch', 'Delete', 'Put')]
        [string]$Method,

        [Parameter()]
        [object]$Body,

        [Parameter()]
        [string]$ContentType = "application/json-patch+json; charset=utf-8"
    )

    $headers = $null

    $pat = Get-AzureDevOpsPat
    if ($pat) {
        $base64Auth = [Convert]::ToBase64String([Text.Encoding]::ASCII.GetBytes(":$($pat)"))
        $headers = @{ "Authorization" = "Basic $base64Auth" }
    }
    else {
        try {
            $tokenJson = az account get-access-token --resource "499b84ac-1321-427f-aa17-267ca6975798" 2>$null
            if ($LASTEXITCODE -eq 0 -and $tokenJson) {
                $token = ($tokenJson | ConvertFrom-Json).accessToken
                $headers = @{ "Authorization" = "Bearer $token" }
            }
        }
        catch { }
    }

    if (-not $headers) {
        throw "ADO authentication failed. Run 'az login' or configure PAT in AzureAccessTokens.json."
    }

    $params = @{ Uri = $Uri; Method = $Method; Headers = $headers }
    if ($Body) {
        $json = if ($Body -is [string]) { $Body } else { ConvertTo-Json -InputObject $Body -Depth 10 }
        $params['Body'] = [System.Text.Encoding]::UTF8.GetBytes($json)
        $params['ContentType'] = $ContentType
    }

    Invoke-RestMethod @params
}

function Get-AdoWorkItem {
    <#
    .SYNOPSIS
        Fetches an Azure DevOps work item by ID.
    .PARAMETER WorkItemId
        The work item ID.
    .PARAMETER Fields
        Optional comma-separated field names to return (e.g. "System.Title,System.State").
    .PARAMETER Organization
        ADO organization. Defaults to Get-AzureDevOpsOrganization.
    .PARAMETER Project
        ADO project. Defaults to Get-AzureDevOpsProject.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [int]$WorkItemId,

        [Parameter()]
        [string]$Fields,

        [Parameter()]
        [string]$Organization,

        [Parameter()]
        [string]$Project
    )

    if (-not $Organization) { $Organization = Get-AzureDevOpsOrganization }
    if (-not $Project) { $Project = Get-AzureDevOpsProject }

    $uri = "https://dev.azure.com/$($Organization)/$($Project)/_apis/wit/workitems/$($WorkItemId)?api-version=7.0"
    if ($Fields) { $uri += "&`$fields=$($Fields)" }

    Invoke-AdoRestApi -Uri $uri -Method Get
}

function New-AdoWorkItem {
    <#
    .SYNOPSIS
        Creates an Azure DevOps work item via REST API with proper UTF-8 encoding.
    .PARAMETER Type
        Work item type: User Story, Task, Bug, or Epic.
    .PARAMETER Title
        Work item title (supports Norwegian characters).
    .PARAMETER Description
        HTML description (optional, can be set later via Set-AdoWorkItemField).
    .PARAMETER AssignedTo
        Assignee email or display name.
    .PARAMETER Tags
        Semicolon-separated tags.
    .PARAMETER ParentId
        Parent work item ID for hierarchy linking.
    .PARAMETER Organization
        ADO organization. Defaults to Get-AzureDevOpsOrganization.
    .PARAMETER Project
        ADO project. Defaults to Get-AzureDevOpsProject.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [ValidateSet('Epic', 'User Story', 'Task', 'Bug')]
        [string]$Type,

        [Parameter(Mandatory)]
        [string]$Title,

        [Parameter()]
        [string]$Description,

        [Parameter()]
        [string]$AssignedTo,

        [Parameter()]
        [string]$Tags,

        [Parameter()]
        [int]$ParentId = 0,

        [Parameter()]
        [string]$Organization,

        [Parameter()]
        [string]$Project
    )

    if (-not $Organization) { $Organization = Get-AzureDevOpsOrganization }
    if (-not $Project) { $Project = Get-AzureDevOpsProject }

    $patchDoc = @(
        @{ op = "add"; path = "/fields/System.Title"; value = $Title }
    )
    if ($Description) {
        $patchDoc += @{ op = "add"; path = "/fields/System.Description"; value = $Description }
    }
    if ($AssignedTo) {
        $patchDoc += @{ op = "add"; path = "/fields/System.AssignedTo"; value = $AssignedTo }
    }
    if ($Tags) {
        $patchDoc += @{ op = "add"; path = "/fields/System.Tags"; value = $Tags }
    }

    $escapedType = [Uri]::EscapeDataString($Type)
    $baseUrl = "https://dev.azure.com/$($Organization)/$($Project)"
    $createUri = "$($baseUrl)/_apis/wit/workitems/`$$($escapedType)?api-version=7.0"

    $workItem = Invoke-AdoRestApi -Uri $createUri -Method Post -Body $patchDoc
    Write-LogMessage "Created $($Type) '$($Title)' with ID: $($workItem.id)" -Level INFO

    if ($ParentId -gt 0) {
        $linkDoc = @(
            @{
                op    = "add"
                path  = "/relations/-"
                value = @{
                    rel = "System.LinkTypes.Hierarchy-Reverse"
                    url = "$($baseUrl)/_apis/wit/workItems/$($ParentId)"
                }
            }
        )
        $linkUri = "$($baseUrl)/_apis/wit/workitems/$($workItem.id)?api-version=7.0"
        try {
            Invoke-AdoRestApi -Uri $linkUri -Method Patch -Body $linkDoc | Out-Null
            Write-LogMessage "Linked WI $($workItem.id) to parent $($ParentId)" -Level INFO
        }
        catch {
            Write-LogMessage "Failed to link to parent $($ParentId): $($_.Exception.Message)" -Level WARN
        }
    }

    return $workItem
}

function Set-AdoWorkItemField {
    <#
    .SYNOPSIS
        Updates one or more fields on an Azure DevOps work item via REST PATCH.
    .DESCRIPTION
        Accepts a hashtable of field paths to values. Handles arbitrarily large payloads
        (e.g. HTML descriptions with embedded base64 images).
    .PARAMETER WorkItemId
        The work item ID.
    .PARAMETER Fields
        Hashtable mapping field reference names to values.
        Example: @{ "System.Description" = $html; "System.State" = "Active" }
    .PARAMETER Organization
        ADO organization. Defaults to Get-AzureDevOpsOrganization.
    .PARAMETER Project
        ADO project. Defaults to Get-AzureDevOpsProject.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [int]$WorkItemId,

        [Parameter(Mandatory)]
        [hashtable]$Fields,

        [Parameter()]
        [string]$Organization,

        [Parameter()]
        [string]$Project
    )

    if (-not $Organization) { $Organization = Get-AzureDevOpsOrganization }
    if (-not $Project) { $Project = Get-AzureDevOpsProject }

    $patchDoc = @()
    foreach ($key in $Fields.Keys) {
        $patchDoc += @{ op = "replace"; path = "/fields/$($key)"; value = $Fields[$key] }
    }

    $uri = "https://dev.azure.com/$($Organization)/$($Project)/_apis/wit/workitems/$($WorkItemId)?api-version=7.0"
    Invoke-AdoRestApi -Uri $uri -Method Patch -Body $patchDoc
}

#endregion Azure DevOps REST API — Work Items

Export-ModuleMember -Function * -Alias *
