<#
.SYNOPSIS
    Deploys .NET NuGet packages to Azure DevOps feeds with automatic version management.

.DESCRIPTION
    Generic, reusable script for deploying any .NET NuGet package with automatic version bumping.
    The script can deploy any NuGet package - not just DedgeCommon!
    
    Features:
    - Automatic version bumping (Major/Minor/Patch) or specific version setting
    - Loads PAT from multiple standard locations (OneDrive, Documents, AppData, etc.)
    - Works with any .csproj file
    - Configurable NuGet feed and Azure DevOps project
    - Interactive menu to select from saved configurations
    - Clean build process with error handling
    - Saves deployment parameters for future use
    - Detects and notifies about duplicate config files

.PARAMETER Organization
    Azure DevOps organization name. Defaults to empty string (will prompt or load from saved config).

.PARAMETER Project
    Azure DevOps project name. Defaults to empty string (will prompt or load from saved config).

.PARAMETER NuGetFeed
    NuGet feed name to push package to. Defaults to empty string (will prompt or load from saved config).

.PARAMETER ProjectFile
    Path to .csproj file (relative or absolute). Defaults to empty string (will show menu to select from saved configs).

.PARAMETER VersionBump
    Version component to bump when not using SpecificVersion. Valid values: Major, Minor, Patch. Default: Patch.

.PARAMETER SpecificVersion
    Set a specific version instead of bumping. Supports partial versions (e.g., "2.0" becomes "2.0.0").
    When set, prompts user to specify if it's a Patch, Minor, or Major change.

.PARAMETER PAT
    Personal Access Token for NuGet feed. If not provided, loads from config files or prompts user.

.PARAMETER ConfigFileName
    Config file name in OneDrive Documents (legacy support). Defaults to "<PackageId>Config.json".

.PARAMETER Force
    Skip confirmation prompts. Use this for automated deployments.

.PARAMETER NoOpenBrowser
    Don't open browser to package page after successful deployment.

.EXAMPLE
    .\Azure-NugetVersionPush.ps1 -ProjectFile "MyLib\MyLib.csproj" -Force
    
    Deploys MyLib with patch version bump using saved configuration or prompts for missing parameters.

.EXAMPLE
    .\Azure-NugetVersionPush.ps1 -ProjectFile "MyLib\MyLib.csproj" -VersionBump Minor -Force
    
    Deploys MyLib with minor version bump.

.EXAMPLE
    .\Azure-NugetVersionPush.ps1 -ProjectFile "MyLib\MyLib.csproj" -SpecificVersion "2.0" -Force
    
    Sets version to 2.0.0 and prompts for version type (Patch/Minor/Major).

.EXAMPLE
    .\Azure-NugetVersionPush.ps1 -Organization "Dedge" -Project "Dedge" -NuGetFeed "Dedge" -ProjectFile "MyLib.csproj" -Force
    
    Deploys with all parameters specified.

.NOTES
    - Config files are searched in: OneDrive, Documents, AppData, C:\opt\data\UserConfig, and $env:OptPath\data
    - If multiple config files found, uses the most recently modified one
    - Successful deployments save configuration to Azure-NugetVersionPush-Config.json in script folder
    - PAT is loaded from AzureAccessTokens.json in standard locations or legacy package-specific configs
    
    Created: 2025-12-17
    Author: Dedge Development Team
#>

param(
    [Parameter(Mandatory = $false)]
    [string]$Organization = "",

    [Parameter(Mandatory = $false)]
    [string]$Project = "",

    [Parameter(Mandatory = $false)]
    [string]$NuGetFeed = "",

    [Parameter(Mandatory = $false)]
    [string]$ProjectFile = "",
    
    [Parameter(Mandatory = $false)]
    [ValidateSet("Major", "Minor", "Patch")]
    [string]$VersionBump = "Patch",
    
    [Parameter(Mandatory = $false)]
    [string]$SpecificVersion,
    
    [Parameter(Mandatory = $false)]
    [string]$PAT,
    
    [Parameter(Mandatory = $false)]
    [string]$AzureAccessTokensFileName = "AzureAccessTokens.json",
    
    
    [Parameter(Mandatory = $false)]
    [switch]$Force,
    
    [Parameter(Mandatory = $false)]
    [switch]$NoOpenBrowser
)

$ErrorActionPreference = "Stop"

Import-Module AzureFunctions -Force -ErrorAction Stop

Write-Host ""
Write-Host "=== Generic NuGet Package Deployment ===" -ForegroundColor Cyan
Write-Host ""

# Check if ProjectFile is empty, or if any other key parameters are empty, and load from saved config
$configFilePath = Join-Path $PSScriptRoot "Azure-NugetVersionPush-Config.json"
$needsConfig = [string]::IsNullOrWhiteSpace($ProjectFile) -or
               [string]::IsNullOrWhiteSpace($Organization) -or 
               [string]::IsNullOrWhiteSpace($Project) -or 
               [string]::IsNullOrWhiteSpace($NuGetFeed)

if ($needsConfig -and (Test-Path $configFilePath)) {
    try {
        $savedConfigs = Get-Content $configFilePath -Raw | ConvertFrom-Json
        
        # Handle both single object and array formats
        $configs = @()
        if ($savedConfigs -is [System.Array]) {
            $configs = $savedConfigs
        }
        elseif ($savedConfigs) {
            $configs = @($savedConfigs)
        }
        
        if ($configs.Count -gt 0) {
            if ([string]::IsNullOrWhiteSpace($ProjectFile)) {
                Write-Host "ProjectFile is missing. Select a saved configuration:" -ForegroundColor Yellow
            }
            else {
                Write-Host "Some parameters are missing. Select a saved configuration:" -ForegroundColor Yellow
            }
            Write-Host ""
            
            # Display menu
            for ($i = 0; $i -lt $configs.Count; $i++) {
                $config = $configs[$i]
                Write-Host "  [$($i + 1)] Organization: $($config.Organization), Project: $($config.Project), Feed: $($config.NuGetFeed)" -ForegroundColor Cyan
                Write-Host "      ProjectFile: $($config.ProjectFile)" -ForegroundColor Gray
            }
            Write-Host "  [0] Skip (use provided parameters only)" -ForegroundColor Gray
            Write-Host ""
            
            $selection = Read-Host "Select configuration (1-$($configs.Count), or 0 to skip)"
            
            if ($selection -match '^\d+$' -and [int]$selection -ge 1 -and [int]$selection -le $configs.Count) {
                $selectedConfig = $configs[[int]$selection - 1]
                
                # Set parameters from selected config (only if they're empty)
                if ([string]::IsNullOrWhiteSpace($Organization) -and $selectedConfig.Organization) {
                    $Organization = $selectedConfig.Organization
                }
                if ([string]::IsNullOrWhiteSpace($Project) -and $selectedConfig.Project) {
                    $Project = $selectedConfig.Project
                }
                if ([string]::IsNullOrWhiteSpace($NuGetFeed) -and $selectedConfig.NuGetFeed) {
                    $NuGetFeed = $selectedConfig.NuGetFeed
                }
                if ([string]::IsNullOrWhiteSpace($ProjectFile) -and $selectedConfig.ProjectFile) {
                    $ProjectFile = $selectedConfig.ProjectFile
                }
                
                Write-Host ""
                Write-Host "Using configuration:" -ForegroundColor Green
                Write-Host "  Organization: $Organization" -ForegroundColor Gray
                Write-Host "  Project: $Project" -ForegroundColor Gray
                Write-Host "  NuGetFeed: $NuGetFeed" -ForegroundColor Gray
                Write-Host "  ProjectFile: $ProjectFile" -ForegroundColor Gray
                Write-Host ""
            }
            elseif ($selection -eq '0') {
                Write-Host "Skipping config selection, using provided parameters only" -ForegroundColor Yellow
                Write-Host ""
            }
            else {
                Write-Host "Invalid selection, using provided parameters only" -ForegroundColor Yellow
                Write-Host ""
            }
        }
    }
    catch {
        Write-Host "  [WARNING] Could not load saved config: $($_.Exception.Message)" -ForegroundColor Yellow
        Write-Host ""
    }
}

# Resolve project file path
if (-not [string]::IsNullOrWhiteSpace($ProjectFile)) {
    if (-not [System.IO.Path]::IsPathRooted($ProjectFile)) {
        $ProjectFile = Join-Path (Get-Location) $ProjectFile
    }
}

# Check project file
if ([string]::IsNullOrWhiteSpace($ProjectFile) -or -not (Test-Path $ProjectFile)) {
    Write-Host "ERROR: Project file not found or not specified: $ProjectFile" -ForegroundColor Red
    Write-Host "Please provide -ProjectFile parameter or select from saved configurations" -ForegroundColor Yellow
    exit 1
}

$projectDir = Split-Path $ProjectFile -Parent
$projectName = [System.IO.Path]::GetFileNameWithoutExtension($ProjectFile)

Write-Host "Project: $projectName" -ForegroundColor White
Write-Host "File: $ProjectFile" -ForegroundColor Gray
Write-Host ""

# Get current version
[xml]$proj = Get-Content $ProjectFile
$currentVersion = $proj.Project.PropertyGroup.Version

if ([string]::IsNullOrEmpty($currentVersion)) {
    Write-Host "ERROR: Version not found in project file" -ForegroundColor Red
    Write-Host "Ensure <Version>X.Y.Z</Version> exists in <PropertyGroup>" -ForegroundColor Yellow
    exit 1
}

Write-Host "Current Version: $currentVersion" -ForegroundColor Yellow

# Determine new version
if ($SpecificVersion) {
    # Allow partial versions (e.g., "2.0" becomes "2.0.0")
    $parts = $SpecificVersion.Split('.')
    
    if ($parts.Count -eq 1) {
        # Just major version provided (e.g., "2")
        $newVersion = "$($parts[0]).0.0"
        Write-Host "Target Version:  $newVersion (specified as $SpecificVersion, auto-completed)" -ForegroundColor Yellow
    }
    elseif ($parts.Count -eq 2) {
        # Major.Minor provided (e.g., "2.0")
        $newVersion = "$($parts[0]).$($parts[1]).0"
        Write-Host "Target Version:  $newVersion (specified as $SpecificVersion, auto-completed)" -ForegroundColor Yellow
    }
    elseif ($parts.Count -eq 3) {
        # Full version provided
        $newVersion = $SpecificVersion
        Write-Host "Target Version:  $newVersion (specified)" -ForegroundColor Yellow
    }
    else {
        Write-Host "ERROR: Invalid version format: $SpecificVersion" -ForegroundColor Red
        Write-Host "Expected: Major, Major.Minor, or Major.Minor.Patch" -ForegroundColor Yellow
        exit 1
    }
    
    # Ask user what type of version change this is
    if (-not $Force) {
        Write-Host ""
        Write-Host "What type of version change is this?" -ForegroundColor Cyan
        Write-Host "  [1] Patch (bug fixes, small changes)" -ForegroundColor Gray
        Write-Host "  [2] Minor (new features, backward compatible)" -ForegroundColor Gray
        Write-Host "  [3] Major (breaking changes)" -ForegroundColor Gray
        Write-Host ""
        
        $versionTypeSelection = Read-Host "Select (1-3)"
        
        $versionType = switch ($versionTypeSelection) {
            "1" { "Patch"; break }
            "2" { "Minor"; break }
            "3" { "Major"; break }
            default { 
                Write-Host "Invalid selection, defaulting to Patch" -ForegroundColor Yellow
                "Patch"
            }
        }
        
        Write-Host "Version type: $versionType" -ForegroundColor Cyan
        Write-Host ""
    }
}
else {
    $parts = $currentVersion.Split('.')
    if ($parts.Count -ne 3) {
        Write-Host "ERROR: Invalid version format. Expected: Major.Minor.Patch" -ForegroundColor Red
        exit 1
    }
    
    $major = [int]$parts[0]
    $minor = [int]$parts[1]
    $patch = [int]$parts[2]
    
    switch ($VersionBump) {
        "Major" { $major++; $minor = 0; $patch = 0 }
        "Minor" { $minor++; $patch = 0 }
        "Patch" { $patch++ }
    }
    
    $newVersion = "$major.$minor.$patch"
    Write-Host "Target Version:  $newVersion ($VersionBump bump)" -ForegroundColor Yellow
}

# Confirm
if (-not $Force) {
    Write-Host ""
    $confirm = Read-Host "Proceed with version bump to $newVersion? (y/n)"
    if ($confirm -ne 'y') {
        Write-Host "Cancelled by user" -ForegroundColor Yellow
        exit 0
    }
}

Write-Host ""
Write-Host "=" * 63 -ForegroundColor Gray

# Step 1: Update version
Write-Host "`nStep 1: Updating version..." -ForegroundColor Cyan
$proj.Project.PropertyGroup.Version = $newVersion
$proj.Save($ProjectFile)
Write-Host "  [OK] Version updated to $newVersion" -ForegroundColor Green

# Step 2: Clean old packages
Write-Host "`nStep 2: Cleaning old packages..." -ForegroundColor Cyan

# Find output directory (check for bin\Release or bin\x64\Release)
$possibleDirs = @(
    (Join-Path $projectDir "bin\Release"),
    (Join-Path $projectDir "bin\x64\Release"),
    (Join-Path $projectDir "bin\Debug"),
    (Join-Path $projectDir "bin\x64\Debug")
)

$packageOutputDir = $null
foreach ($dir in $possibleDirs) {
    if (Test-Path $dir) {
        $packageOutputDir = $dir
        break
    }
}

if ($packageOutputDir) {
    Remove-Item "$packageOutputDir\*.nupkg" -Force -ErrorAction SilentlyContinue
    Write-Host "  [OK] Cleaned old packages from: $packageOutputDir" -ForegroundColor Green
}
else {
    Write-Host "  [INFO] No previous packages found" -ForegroundColor Gray
}

# Step 3: Build Release
Write-Host "`nStep 3: Building Release..." -ForegroundColor Cyan
Write-Host "  Building: $ProjectFile" -ForegroundColor Gray

$buildOutput = dotnet build $ProjectFile -c Release 2>&1
if ($LASTEXITCODE -ne 0) {
    Write-Host "  [ERROR] Build failed" -ForegroundColor Red
    Write-Host $buildOutput
    exit 1
}
Write-Host "  [OK] Build successful" -ForegroundColor Green

# Step 4: Find and verify package
Write-Host "`nStep 4: Locating package..." -ForegroundColor Cyan

# Get PackageId from project file (or use project name)
$packageId = $proj.Project.PropertyGroup.PackageId
if ([string]::IsNullOrEmpty($packageId)) {
    $packageId = $projectName
}

# Search for package in possible locations
$packagePath = $null
$searchDirs = @(
    (Join-Path $projectDir "bin\Release"),
    (Join-Path $projectDir "bin\x64\Release")
)

foreach ($dir in $searchDirs) {
    if (Test-Path $dir) {
        $foundPackage = Get-ChildItem -Path $dir -Filter "$packageId.$newVersion.nupkg" -ErrorAction SilentlyContinue
        if ($foundPackage) {
            $packagePath = $foundPackage.FullName
            break
        }
    }
}

if (-not $packagePath -or -not (Test-Path $packagePath)) {
    Write-Host "  [ERROR] Package not found: $packageId.$newVersion.nupkg" -ForegroundColor Red
    Write-Host "  Searched in: $($searchDirs -join ', ')" -ForegroundColor Gray
    exit 1
}

$packageSize = (Get-Item $packagePath).Length / 1MB
Write-Host "  [OK] Package found" -ForegroundColor Green
Write-Host "  Name: $packageId.$newVersion.nupkg" -ForegroundColor Gray
Write-Host "  Size: $($packageSize.ToString('F2')) MB" -ForegroundColor Gray
Write-Host "  Location: $packagePath" -ForegroundColor Gray

# Step 5: Get PAT
Write-Host "`nStep 5: Getting PAT..." -ForegroundColor Cyan

if ([string]::IsNullOrEmpty($PAT)) {
    # Use shared token discovery logic (AzureFunctions). Prefer a NuGet-specific token entry,
    # but fall back to the general Azure DevOps PAT (Dedge_AzureDevOpsExtPat) when needed.
    try {
        $token = Get-AzureAccessTokenById -IdLike '*NugetAccessToken*' -AzureAccessTokensFileName $AzureAccessTokensFileName
        if ($token -and -not [string]::IsNullOrWhiteSpace($token.Token)) {
            $PAT = $token.Token
            Write-Host "  [OK] Token loaded: $($token.Id)" -ForegroundColor Green
        }
        else {
            $PAT = Get-AzureDevOpsPat -IdLike '*AzureDevOpsExtPat*' -AzureAccessTokensFileName $AzureAccessTokensFileName
            if (-not [string]::IsNullOrWhiteSpace($PAT)) {
                Write-Host "  [OK] Token loaded via Azure DevOps PAT (AzureDevOpsExtPat)" -ForegroundColor Green
            }
        }
    }
    catch {
        Write-Host "  [WARNING] Could not load token from $($AzureAccessTokensFileName): $($_.Exception.Message)" -ForegroundColor Yellow
    }
    
    # Fallback to legacy package-specific config
    if ([string]::IsNullOrEmpty($PAT)) {
        if ([string]::IsNullOrEmpty($ConfigFileName)) {
            $ConfigFileName = "$($packageId)Config.json"
        }
        
        $legacyConfigPath = Join-Path $env:OneDriveCommercial "Documents\$ConfigFileName"
        
        if (Test-Path $legacyConfigPath) {
            Write-Host "  Loading from legacy config: $ConfigFileName" -ForegroundColor Gray
            try {
                $config = Get-Content $legacyConfigPath -Raw | ConvertFrom-Json
                $PAT = $config.PAT
                
                if (-not [string]::IsNullOrEmpty($PAT)) {
                    Write-Host "  [OK] PAT loaded from legacy config" -ForegroundColor Green
                    if ($config.NuGetFeed) {
                        $NuGetFeed = $config.NuGetFeed
                    }
                    elseif ($config.NuGetSource) {
                        # Backward compatibility with old config files
                        $NuGetFeed = $config.NuGetSource
                    }
                }
            }
            catch {
                Write-Host "  [WARNING] Could not load legacy config: $($_.Exception.Message)" -ForegroundColor Yellow
            }
        }
        else {
            Write-Host "  No legacy config file found" -ForegroundColor Gray
            if ($foundConfigs.Count -eq 0) {
                Write-Host "  Searched in standard locations but found no ${AzureAccessTokensFileName}" -ForegroundColor Yellow
                Write-Host "  Recommended: Create config file in one of these locations:" -ForegroundColor Gray
                foreach ($searchPath in $searchPaths) {
                    if (Test-Path $searchPath) {
                        Write-Host "    $(Join-Path $searchPath $AzureAccessTokensFileName)" -ForegroundColor Cyan
                    }
                }
            }
        }
    }
    
    # If still no PAT, prompt user to enter manually
    if ([string]::IsNullOrEmpty($PAT)) {
        Write-Host ""
        Write-Host "  No PAT found in config files. Please enter PAT manually:" -ForegroundColor Yellow
        $PAT = Read-Host "  Enter PAT (or press Enter to skip deployment)"
        
        if ([string]::IsNullOrEmpty($PAT)) {
            Write-Host ""
            Write-Host "[INFO] Package built but NOT deployed" -ForegroundColor Yellow
            Write-Host "Package: $packagePath" -ForegroundColor Cyan
            Write-Host ""
            Write-Host "To deploy later:" -ForegroundColor Cyan
            Write-Host "  .\Azure-NugetVersionPush.ps1 -ProjectFile ""$ProjectFile"" -PAT YOUR_PAT" -ForegroundColor White
            Write-Host ""
            Write-Host "Or create config file: $configPath" -ForegroundColor Cyan
            Write-Host "  {" -ForegroundColor Gray
            Write-Host "    ""PAT"": ""YOUR_PAT""," -ForegroundColor Gray
            Write-Host "    ""Email"": ""your.email@company.com""," -ForegroundColor Gray
            Write-Host "    ""NuGetFeed"": ""$NuGetFeed""" -ForegroundColor Gray
            Write-Host "  }" -ForegroundColor Gray
            exit 0
        }
    }
}
else {
    Write-Host "  [OK] PAT provided via parameter" -ForegroundColor Green
}

# Step 6: Push to feed
Write-Host "`nStep 6: Pushing to NuGet feed ($NuGetFeed)..." -ForegroundColor Cyan

try {
    # When source has configured credentials, use arbitrary API key (Azure DevOps requirement)
    # Otherwise use the PAT as API key
    $apiKey = if ([string]::IsNullOrEmpty($PAT)) { "AzureDevOps" } else { $PAT }
    $pushOutput = dotnet nuget push $packagePath --source $NuGetFeed --api-key $apiKey --skip-duplicate 2>&1
    
    if ($LASTEXITCODE -eq 0) {
        Write-Host "  [OK] Package pushed successfully!" -ForegroundColor Green
        $deployed = $true
    }
    else {
        $deployed = $false
        
        if ($pushOutput -like "*401*" -or $pushOutput -like "*Unauthorized*") {
            Write-Host "  [ERROR] Authentication failed (401)" -ForegroundColor Red
            Write-Host ""
            Write-Host "  Possible causes:" -ForegroundColor Yellow
            Write-Host "    1. PAT has expired" -ForegroundColor Gray
            Write-Host "    2. PAT missing 'Packaging (Read, write, & manage)' permission" -ForegroundColor Gray
            Write-Host "    3. PAT for wrong organization/source" -ForegroundColor Gray
            Write-Host ""
            Write-Host "  Update config file: $configPath" -ForegroundColor Cyan
        }
        elseif ($pushOutput -like "*409*" -or $pushOutput -like "*already exists*") {
            Write-Host "  [INFO] Package $newVersion already exists in $NuGetFeed" -ForegroundColor Yellow
            Write-Host "  Bump version again or check feed" -ForegroundColor Gray
        }
        else {
            Write-Host "  [ERROR] Push failed" -ForegroundColor Red
            Write-Host "  Output: $pushOutput" -ForegroundColor Gray
        }
    }
}
catch {
    Write-Host "  [ERROR] Exception: $($_.Exception.Message)" -ForegroundColor Red
    $deployed = $false
}

# Summary
Write-Host ""
Write-Host "=" * 63 -ForegroundColor Cyan
Write-Host "   Deployment Summary" -ForegroundColor Cyan
Write-Host "=" * 63 -ForegroundColor Cyan
Write-Host ""
Write-Host "Project:    $packageId" -ForegroundColor White
Write-Host "Version:    $currentVersion -> $newVersion" -ForegroundColor White
Write-Host "Package:    $([System.IO.Path]::GetFileName($packagePath))" -ForegroundColor White
Write-Host "Size:       $($packageSize.ToString('F2')) MB" -ForegroundColor White
Write-Host "Feed:       $NuGetFeed" -ForegroundColor White
Write-Host "Build:      [OK]" -ForegroundColor Green

if ($deployed) {
    Write-Host "Deploy:     [OK] Deployed" -ForegroundColor Green
    Write-Host ""
    Write-Host "[SUCCESS] Package $newVersion deployed to $NuGetFeed!" -ForegroundColor Green
    Write-Host ""
    
    # Save deployment parameters to JSON file (avoid duplicates, support multiple configs)
    try {
        $deploymentConfig = @{
            Organization = $Organization
            Project = $Project
            NuGetFeed = $NuGetFeed
            ProjectFile = $ProjectFile
        }
        
        $configFilePath = Join-Path $PSScriptRoot "Azure-NugetVersionPush-Config.json"
        
        # Load existing configs (handle both single object and array formats)
        $allConfigs = @()
        if (Test-Path $configFilePath) {
            try {
                $existingData = Get-Content $configFilePath -Raw | ConvertFrom-Json
                
                # Convert to array format
                if ($existingData -is [System.Array]) {
                    $allConfigs = $existingData
                }
                elseif ($existingData) {
                    $allConfigs = @($existingData)
                }
            }
            catch {
                Write-Host "  [INFO] Could not read existing config, will create new one" -ForegroundColor Gray
            }
        }
        
        # Check for duplicates
        $isDuplicate = $false
        foreach ($existingConfig in $allConfigs) {
            if ($existingConfig.Organization -eq $Organization -and
                $existingConfig.Project -eq $Project -and
                $existingConfig.NuGetFeed -eq $NuGetFeed -and
                $existingConfig.ProjectFile -eq $ProjectFile) {
                $isDuplicate = $true
                break
            }
        }
        
        if ($isDuplicate) {
            Write-Host "Deployment config already exists, skipping save" -ForegroundColor Gray
        }
        else {
            # Add new config to array
            $allConfigs += $deploymentConfig
            
            # Save as array
            $allConfigs | ConvertTo-Json -Depth 10 | Set-Content -Path $configFilePath -Encoding UTF8
            Write-Host "Deployment config saved to: $configFilePath" -ForegroundColor Gray
        }
    }
    catch {
        Write-Host "  [WARNING] Could not save deployment config: $($_.Exception.Message)" -ForegroundColor Yellow
    }
    
    # Open browser to package page
    if (-not $NoOpenBrowser) {
        $packageUrl = $null
        
        # Construct URL based on NuGet feed
        $packageUrl = "https://dev.azure.com/$Organization/$Project/_artifacts/feed/$NuGetFeed/NuGet/$packageId/overview/$newVersion"
        
        if ($packageUrl) {
            Write-Host "Opening package page in browser..." -ForegroundColor Cyan
            Write-Host "  $packageUrl" -ForegroundColor Gray
            Start-Process $packageUrl
        }
        else {
            Write-Host "Package URL: (Could not determine, check feed manually)" -ForegroundColor Gray
        }
        Write-Host ""
    }
    
    Write-Host "Next steps:" -ForegroundColor Yellow
    Write-Host "  1. Update consuming apps: <PackageReference Include=""$packageId"" Version=""$newVersion"" />" -ForegroundColor Gray
    Write-Host "  2. Test in DEV environment" -ForegroundColor Gray
    Write-Host "  3. Deploy to higher environments" -ForegroundColor Gray
}
else {
    Write-Host "Deploy:     [SKIPPED]" -ForegroundColor Yellow
    Write-Host ""
    Write-Host "[INFO] Package built but not deployed" -ForegroundColor Yellow
    Write-Host ""
    Write-Host "To deploy:" -ForegroundColor Cyan
    Write-Host "  .\Azure-NugetVersionPush.ps1 -ProjectFile ""$ProjectFile"" -PAT YOUR_PAT" -ForegroundColor White
}

Write-Host ""
