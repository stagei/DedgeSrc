#Requires -Version 5.1
<#
.SYNOPSIS
    Common utility functions for WebSiteHandler scripts.
.DESCRIPTION
    This file contains shared functionality used by all WebSiteHandler scripts.
    It's designed to be dot-sourced by the main scripts to avoid code duplication.
.NOTES
    Version:        1.0
    Author:         Admin Tools
    Creation Date:  Current date
#>

# Check if running as Administrator
function Test-AdminPrivileges {
    $isAdmin = ([Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
    if (-not $isAdmin) {
        Write-Host "This script requires Administrator privileges. Please run as Administrator." -ForegroundColor Red
        return $false
    }
    return $true
}

# Get website target path based on new requirements
function Get-WebsiteTargetPath {
    param (
        [Parameter(Mandatory = $true)]
        [string]$SiteName
    )

    # Extract the leaf name (last part of the path) if the site name contains a path
    $leafName = $SiteName
    if ($SiteName -match '[\\/]') {
        $leafName = Split-Path -Path $SiteName -Leaf
    }

    # Clean up any invalid characters from the leaf name
    $invalidChars = [System.IO.Path]::GetInvalidFileNameChars()
    $cleanName = $leafName
    foreach ($char in $invalidChars) {
        $cleanName = $cleanName.Replace($char, '_')
    }

    # Construct the new path
    $newPath = Join-Path -Path $env:OptPath -ChildPath "WEBS"
    $newPath = Join-Path -Path $newPath -ChildPath $cleanName

    return $newPath
}

# Setup standard paths - Updated with environment variable support
function Get-StandardPaths {

    $localPaths = @{
        BaseFolder    = Join-Path -Path $env:OptPath -ChildPath "data\WebSiteHandler"
        ExportFolder  = Join-Path -Path $env:OptPath -ChildPath "data\WebSiteHandler\Export"
        ImportFolder  = Join-Path -Path $env:OptPath -ChildPath "data\WebSiteHandler\Import"
        ArchiveFolder = Join-Path -Path $env:OptPath -ChildPath "data\WebSiteHandler\Import\Archive"
        WebsFolder    = Join-Path -Path $env:OptPath -ChildPath "WEBS"
    }
    return $localPaths
}

function Get-RemoteStandardPaths {
    param (
        [Parameter(Mandatory = $true)]
        [string]$Server
    )

    $paths = @{
        BaseFolder         = "\\$Server\opt\data\WebSiteHandler"
        RemoteImportFolder = "\\$Server\opt\data\WebSiteHandler\Import"
    }
    return $paths
}
# Create necessary directories if they don't exist
function Initialize-Folders {
    $paths = Get-StandardPaths
    $folders = @($paths.BaseFolder, $paths.ExportFolder, $paths.ImportFolder, $paths.ArchiveFolder, $paths.WebsFolder)

    foreach ($folder in $folders) {
        if (-not (Test-Path $folder)) {
            try {
                Write-Host "Creating directory: $folder" -NoNewline
                New-Item -ItemType Directory -Path $folder -Force | Out-Null
                Write-Host " Done!" -ForegroundColor Green
            }
            catch {
                Write-Host " Failed!" -ForegroundColor Red
                Write-Host "Error: $_" -ForegroundColor Red
                return $false
            }
        }
    }

    # Setup network share if needed - don't stop on errors
    if (Get-Command Get-SmbShare -ErrorAction SilentlyContinue) {
        $optShareExists = Get-SmbShare -Name "opt" -ErrorAction SilentlyContinue
        if ($null -eq $optShareExists) {
            try {
                Write-Host "Creating 'opt' share..." -NoNewline
                New-SmbShare -Name "opt" -Path "$env:OptPath" -FullAccess "Everyone" | Out-Null
                Write-Host " Done!" -ForegroundColor Green
            }
            catch {
                Write-Host " Failed!" -ForegroundColor Red
                Write-Host "Error: $_" -ForegroundColor Red
                Write-Host "Will continue without network share." -ForegroundColor Yellow
            }
        }
    }
    else {
        Write-Host "SMB cmdlets not available. Network shares will not be created." -ForegroundColor Yellow
    }

    return $true
}

# Check if IIS is installed and install if needed
function Initialize-IIS {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$false)]
        [switch]$Force
    )

    # Use automatic $VerbosePreference for verbose output
    $showVerbose = $VerbosePreference -ne 'SilentlyContinue'

    if ($showVerbose) {
        # Display PowerShell version information
        Write-Host "PowerShell Information:" -ForegroundColor Cyan
        Write-Host "  Version: $($PSVersionTable.PSVersion)" -ForegroundColor White
        Write-Host "  Edition: $($PSVersionTable.PSEdition)" -ForegroundColor White
        Write-Host "  .NET Version: $($PSVersionTable.CLRVersion)" -ForegroundColor White
        Write-Host ""
    }

    Write-Host "Checking IIS installation..." -ForegroundColor Cyan

    # Define comprehensive list of required IIS features - critical features first
    $requiredFeatures = @(
        # Core IIS features
        "IIS-WebServerRole",
        "IIS-WebServer",
        "IIS-CommonHttpFeatures",

        # Management features
        "IIS-ManagementConsole",
        "IIS-WebServerManagementTools",
        "IIS-ManagementScriptingTools",
        "IIS-IIS6ManagementCompatibility",
        "IIS-Metabase"
    )

    # Additional features that are useful but not strictly required
    $recommendedFeatures = @(
        "IIS-ApplicationDevelopment",
        "IIS-ASPNET",
        "IIS-ASPNET45",
        "IIS-NetFxExtensibility",
        "IIS-NetFxExtensibility45",
        "IIS-HealthAndDiagnostics",
        "IIS-HttpLogging",
        "IIS-LoggingLibraries",
        "IIS-RequestMonitor",
        "IIS-HttpTracing",
        "IIS-StaticContent",
        "IIS-DefaultDocument",
        "IIS-DirectoryBrowsing",
        "IIS-WebDAV",
        "IIS-WebSockets"
    )

    try {
        # Get all IIS-related feature states using DISM
        Write-Host "  Querying installed IIS features..." -NoNewline

        $dismOutput = DISM.exe /Online /Get-Features | Where-Object { $_ -match "Feature Name" -or $_ -match "State" }

        # Parse DISM output to get feature state
        $featureStates = @{}
        $currentFeature = $null

        for ($i = 0; $i -lt $dismOutput.Count; $i++) {
            $line = $dismOutput[$i]

            if ($line -match "Feature Name : (.+)") {
                $featureName = $Matches[1].Trim()
                $currentFeature = $featureName
            }
            elseif ($line -match "State : (.+)" -and $currentFeature) {
                $featureStates[$currentFeature] = $Matches[1].Trim()
                $currentFeature = $null
            }
        }

        Write-Host " Done!" -ForegroundColor Green

        # Check which required features need to be installed
        $missingRequiredFeatures = @()
        foreach ($feature in $requiredFeatures) {
            if (-not ($featureStates.ContainsKey($feature)) -or $featureStates[$feature] -ne "Enabled") {
                $missingRequiredFeatures += $feature
            }
        }

        # Check which recommended features could be installed
        $missingRecommendedFeatures = @()
        foreach ($feature in $recommendedFeatures) {
            if (-not ($featureStates.ContainsKey($feature)) -or $featureStates[$feature] -ne "Enabled") {
                $missingRecommendedFeatures += $feature
            }
        }

        # Display feature status if verbose
        if ($showVerbose) {
            Write-Host "IIS Feature Status:" -ForegroundColor Cyan
            foreach ($feature in ($requiredFeatures + $recommendedFeatures)) {
                $state = if ($featureStates.ContainsKey($feature)) { $featureStates[$feature] } else { "Not Found" }
                $isRequired = $requiredFeatures -contains $feature
                $requiredText = if ($isRequired) { " (REQUIRED)" } else { " (Recommended)" }

                $color = if ($state -eq "Enabled") {
                    "Green"
                } else {
                    if ($isRequired) { "Red" } else { "Yellow" }
                }

                Write-Host "  $feature$requiredText`: $state" -ForegroundColor $color
            }
        }

        # Check if installation is needed
        if ($missingRequiredFeatures.Count -gt 0) {
            Write-Host "  Missing required IIS features detected. Installation needed." -ForegroundColor Yellow

            # Install missing required features
            Write-Host "  Installing required IIS features..." -ForegroundColor Cyan

            # Construct the DISM command
            $dismCommand = "dism /online /enable-feature"
            foreach ($feature in $missingRequiredFeatures) {
                $dismCommand += " /featurename:$feature"
            }
            $dismCommand += " /all /NoRestart"

            # Show the command that will be executed
            Write-Host "  Executing: $dismCommand" -ForegroundColor DarkCyan

            # Execute DISM command to install required features
            $result = Invoke-Expression $dismCommand
            if ($LASTEXITCODE -ne 0) {
                Write-Host "  Failed to install required IIS features. Please install manually." -ForegroundColor Red
                Write-Host "  Command to run as administrator: $dismCommand" -ForegroundColor Yellow
                return $false
            }

            Write-Host "  Required IIS features installed successfully." -ForegroundColor Green

            # Check if we should install recommended features too
            if ($Force -and $missingRecommendedFeatures.Count -gt 0) {
                Write-Host "  Installing recommended IIS features (Force flag set)..." -ForegroundColor Cyan

                # Construct the DISM command
                $dismCommand = "dism /online /enable-feature"
                foreach ($feature in $missingRecommendedFeatures) {
                    $dismCommand += " /featurename:$feature"
                }
                $dismCommand += " /all /NoRestart"

                # Show the command that will be executed
                Write-Host "  Executing: $dismCommand" -ForegroundColor DarkCyan

                # Execute DISM command to install recommended features
                $result = Invoke-Expression $dismCommand
                if ($LASTEXITCODE -ne 0) {
                    Write-Host "  Warning: Some recommended features couldn't be installed." -ForegroundColor Yellow
                    Write-Host "  This may not affect core functionality." -ForegroundColor Yellow
                } else {
                    Write-Host "  Recommended IIS features installed successfully." -ForegroundColor Green
                }
            }
            elseif ($missingRecommendedFeatures.Count -gt 0) {
                Write-Host "  Note: Some recommended IIS features are not installed." -ForegroundColor Yellow
                Write-Host "  This may not affect core functionality, but you can install them using:" -ForegroundColor Yellow

                $recommendedCommand = "dism /online /enable-feature"
                foreach ($feature in $missingRecommendedFeatures) {
                    $recommendedCommand += " /featurename:$feature"
                }
                $recommendedCommand += " /all /NoRestart"

                Write-Host "  $recommendedCommand" -ForegroundColor DarkYellow
            }
        }
        else {
            Write-Host "  All required IIS features are installed." -ForegroundColor Green

            if ($missingRecommendedFeatures.Count -gt 0 -and $showVerbose) {
                Write-Host "  Note: Some recommended IIS features are not installed." -ForegroundColor Yellow
                Write-Host "  This may not affect core functionality." -ForegroundColor Yellow
            }
        }

        # Verify WebAdministration module is available
        Write-Host "  Verifying WebAdministration module..." -NoNewline

        # Use our more comprehensive module check function - pass through Verbose preference
        $moduleLoaded = Test-WebAdministrationModule -Verbose:($VerbosePreference -eq 'Continue')

        if ($moduleLoaded) {
            Write-Host " Verified!" -ForegroundColor Green
        }
        else {
            Write-Host " Failed!" -ForegroundColor Red
            Write-Host "  WebAdministration module couldn't be loaded. Try restarting your system." -ForegroundColor Yellow
            return $false
        }

        # Check if we can actually access IIS configuration
        try {
            $websites = Get-Website
            Write-Host "  IIS configuration access verified. Found $($websites.Count) website(s)." -ForegroundColor Green
        }
        catch {
            Write-Host "  Warning: Could access WebAdministration module but failed to read IIS configuration." -ForegroundColor Yellow
            Write-Host "  Error: $_" -ForegroundColor Red
            Write-Host "  You may need to restart your system for IIS installation to complete." -ForegroundColor Yellow
            return $false
        }

        Write-Host "IIS initialization completed successfully." -ForegroundColor Green
        return $true
    }
    catch {
        Write-Host "Error initializing IIS: $_" -ForegroundColor Red
        Write-Host $_.ScriptStackTrace -ForegroundColor Red
        return $false
    }
}

# Verify module is available and load it with appropriate method
function Test-WebAdministrationModule {
    [CmdletBinding()]
    param()

    # Use automatic $VerbosePreference for verbose output
    $showVerbose = $VerbosePreference -ne 'SilentlyContinue'

    # Already loaded?
    if (Get-Module WebAdministration) {
        if ($showVerbose) {
            Write-Host "  WebAdministration module is already loaded." -ForegroundColor Green
        }
        return $true
    }

    if ($showVerbose) {
        Write-Host "  Attempting to load WebAdministration module..." -ForegroundColor Cyan
    }

    # Attempt different loading methods in sequence from most to least preferred
    $loadingMethods = @(
        @{
            Name = "Standard Import (Current PowerShell edition)"
            Code = { Import-Module WebAdministration -ErrorAction Stop }
            Condition = { $true } # Always try this first
        },
        @{
            Name = "PowerShell Core with Windows PowerShell compatibility"
            Code = { Import-Module WebAdministration -UseWindowsPowerShell -ErrorAction Stop }
            Condition = { $PSVersionTable.PSEdition -eq 'Core' }
        },
        @{
            Name = "Full path to WebAdministration module"
            Code = { Import-Module "$env:SystemRoot\System32\WindowsPowerShell\v1.0\Modules\WebAdministration\WebAdministration.psd1" -ErrorAction Stop }
            Condition = { Test-Path -Path "$env:SystemRoot\System32\WindowsPowerShell\v1.0\Modules\WebAdministration\WebAdministration.psd1" }
        },
        @{
            Name = "Full path with SkipEditionCheck"
            Code = { Import-Module "$env:SystemRoot\System32\WindowsPowerShell\v1.0\Modules\WebAdministration\WebAdministration.psd1" -SkipEditionCheck -ErrorAction Stop }
            Condition = { Test-Path -Path "$env:SystemRoot\System32\WindowsPowerShell\v1.0\Modules\WebAdministration\WebAdministration.psd1" }
        },
        @{
            Name = "IISAdministration module (Windows 10/Server 2016+)"
            Code = {
                Import-Module IISAdministration -ErrorAction Stop
                # Create compatible aliases or functions if needed
            }
            Condition = { Get-Module -ListAvailable -Name IISAdministration }
        }
    )

    foreach ($method in $loadingMethods) {
        if (-not (& $method.Condition)) {
            if ($showVerbose) {
                Write-Host "  Skipping method: $($method.Name) - Condition not met" -ForegroundColor DarkGray
            }
            continue
        }

        try {
            if ($showVerbose) {
                Write-Host "  Trying: $($method.Name)..." -NoNewline
            }

            & $method.Code

            # Check if we can access IIS drive
            if (-not (Get-PSDrive -Name IIS -ErrorAction SilentlyContinue)) {
                New-PSDrive -Name IIS -PSProvider WebAdministration -Root "IIS:" -ErrorAction Stop | Out-Null
            }

            if ($showVerbose) {
                Write-Host " Success!" -ForegroundColor Green
            }
            return $true
        }
        catch {
            if ($showVerbose) {
                Write-Host " Failed: $_" -ForegroundColor Red
            }
            # Continue to next method
        }
    }

    # If we get here, all methods failed
    Write-Host "  Failed to load WebAdministration module by any method." -ForegroundColor Red
    Write-Host "  This typically indicates one of the following issues:" -ForegroundColor Yellow
    Write-Host "  1. IIS is not fully installed or missing key components" -ForegroundColor Yellow
    Write-Host "  2. A system restart is required after IIS installation" -ForegroundColor Yellow
    Write-Host "  3. Running in an unsupported PowerShell environment" -ForegroundColor Yellow

    return $false
}

# Function to get IISAdministration app pool
function Get-IISAppPool {
    param (
        [Parameter(Mandatory = $true)]
        [string]$Name,

        [Parameter(Mandatory = $false)]
        [switch]$ErrorIfNotFound = $false
    )

    # First check if we have the WebAdministration module loaded
    if (Get-Module WebAdministration) {
        try {
            return Get-Item "IIS:\AppPools\$Name" -ErrorAction SilentlyContinue
        }
        catch {
            if ($ErrorIfNotFound) {
                Write-Error "Error accessing application pool '$Name': $_"
            }
            return $null
        }
    }
    else {
        # Try via direct WMI/CIM access as fallback
        try {
            $appPool = Get-CimInstance -Namespace "root/MicrosoftIISv2" -ClassName "IIsApplicationPool" -Filter "Name='W3SVC/AppPools/$Name'" -ErrorAction SilentlyContinue
            if ($appPool) {
                # Create a simplified object with key properties
                return [PSCustomObject]@{
                    Name = $Name
                    State = if ($appPool.Started) { "Started" } else { "Stopped" }
                    ManagedRuntimeVersion = $appPool.ManagedRuntimeVersion
                    ManagedPipelineMode = $appPool.ManagedPipelineMode
                }
            }
        }
        catch {
            if ($ErrorIfNotFound) {
                Write-Error "Error accessing application pool '$Name' via WMI: $_"
            }
        }
    }

    if ($ErrorIfNotFound) {
        Write-Error "Application pool '$Name' not found."
    }

    return $null
}

# ZIP file handling utilities
function New-ZipArchive {
    param (
        [string]$SourcePath,
        [string]$DestinationPath
    )

    Write-Host "Creating zip archive at $DestinationPath..." -NoNewline

    try {
        if (Get-Command Compress-Archive -ErrorAction SilentlyContinue) {
            # PowerShell 5.0 or later
            Compress-Archive -Path $SourcePath -DestinationPath $DestinationPath -Force
        }
        else {
            # Use .NET Framework method for older PowerShell versions
            Add-Type -AssemblyName System.IO.Compression.FileSystem
            [System.IO.Compression.ZipFile]::CreateFromDirectory($SourcePath, $DestinationPath)
        }

        Write-Host " Done!" -ForegroundColor Green
        return $true
    }
    catch {
        Write-Host " Failed!" -ForegroundColor Red
        Write-Host "Error: $_" -ForegroundColor Red
        return $false
    }
}

function Expand-ZipArchive {
    param (
        [string]$ZipFilePath,
        [string]$DestinationPath
    )

    Write-Host "Extracting zip file to $DestinationPath..." -NoNewline

    try {
        if (Get-Command Expand-Archive -ErrorAction SilentlyContinue) {
            # PowerShell 5.0 or later
            Expand-Archive -Path $ZipFilePath -DestinationPath $DestinationPath -Force
        }
        else {
            # Use .NET Framework method for older PowerShell versions
            Add-Type -AssemblyName System.IO.Compression.FileSystem
            [System.IO.Compression.ZipFile]::ExtractToDirectory($ZipFilePath, $DestinationPath)
        }

        Write-Host " Done!" -ForegroundColor Green
        return $true
    }
    catch {
        Write-Host " Failed!" -ForegroundColor Red
        Write-Host "Error: $_" -ForegroundColor Red
        return $false
    }
}

# Clean up temporary files
function Remove-TempFolder {
    param (
        [string]$Path
    )

    if (Test-Path $Path) {
        Write-Host "Cleaning up temporary folder: $Path..." -NoNewline
        try {
            Remove-Item -Path $Path -Recurse -Force
            Write-Host " Done!" -ForegroundColor Green
            return $true
        }
        catch {
            Write-Host " Failed!" -ForegroundColor Red
            Write-Host "Error: $_" -ForegroundColor Red
            return $false
        }
    }
    return $true
}

# Expands environment variables in path and returns both original and expanded paths
function Expand-WebsitePath {
    param (
        [Parameter(Mandatory = $true)]
        [string]$Path
    )

    $result = @{
        OriginalPath                 = $Path
        ExpandedPath                 = $Path
        ContainsEnvironmentVariables = $false
        PathExists                   = $false
    }

    # Check if path contains environment variables
    if ($Path -match '%') {
        $expandedPath = [Environment]::ExpandEnvironmentVariables($Path)
        if ($expandedPath -ne $Path) {
            $result.ExpandedPath = $expandedPath
            $result.ContainsEnvironmentVariables = $true
        }
    }

    # Check if original path exists
    if (Test-Path -Path $Path) {
        $result.PathExists = $true
    }
    # If not, check if expanded path exists
    elseif ($result.ContainsEnvironmentVariables -and (Test-Path -Path $result.ExpandedPath)) {
        $result.PathExists = $true
    }

    return $result
}

# Transform a path for cross-server deployment with different drive letters
function Transform-WebsitePath {
    param (
        [Parameter(Mandatory = $true)]
        [string]$Path,

        [Parameter(Mandatory = $true)]
        [string]$DestinationDrive
    )

    # Make sure destination drive has a colon
    if (-not $DestinationDrive.EndsWith(":")) {
        $DestinationDrive = "$DestinationDrive`:"
    }

    # If the path starts with a drive letter, replace it
    if ($Path -match '^[A-Za-z]:') {
        $originalDrive = $Path.Substring(0, 2)
        return $Path.Replace($originalDrive, $DestinationDrive)
    }
    # Otherwise, return the path as is (for UNC paths or unexpanded environment variables)
    else {
        return $Path
    }
}

# Validate and prepare IIS paths, handling special IIS variables and defaults
function Get-IISPath {
    param (
        [Parameter(Mandatory = $true)]
        [string]$Path,

        [Parameter(Mandatory = $false)]
        [string]$DefaultRoot = "%SystemDrive%\inetpub\wwwroot",

        [Parameter(Mandatory = $false)]
        [switch]$CreateIfMissing = $false
    )

    $result = @{
        OriginalPath = $Path
        FinalPath    = $Path
        IsDefault    = $false
        Exists       = $false
    }

    # Use default path if none specified
    if ([string]::IsNullOrWhiteSpace($Path)) {
        $Path = $DefaultRoot
        $result.OriginalPath = $Path
        $result.FinalPath = $Path
        $result.IsDefault = $true
    }

    # First, expand any environment variables
    $expandedPath = [Environment]::ExpandEnvironmentVariables($Path)
    if ($expandedPath -ne $Path) {
        $result.FinalPath = $expandedPath
    }

    # Check if path exists
    if (Test-Path -Path $result.FinalPath) {
        $result.Exists = $true
    }
    # If it doesn't exist but we're asked to create it
    elseif ($CreateIfMissing) {
        try {
            New-Item -ItemType Directory -Path $result.FinalPath -Force | Out-Null
            $result.Exists = $true
        }
        catch {
            Write-Host "Error creating path $($result.FinalPath): $_" -ForegroundColor Red
        }
    }

    return $result
}

# Get all websites matching a filter (or all if no filter provided)
function Get-IISWebsiteList {
    param (
        [Parameter(Mandatory = $false)]
        [string[]]$SiteNames = $null
    )

    # Get all websites
    $allWebsites = Get-Website

    # If no sites specified, return all
    if ($null -eq $SiteNames -or $SiteNames.Count -eq 0) {
        return $allWebsites
    }

    # Otherwise, filter by name
    $websites = @()
    foreach ($siteName in $SiteNames) {
        $site = $allWebsites | Where-Object { $_.Name -eq $siteName }
        if ($site) {
            $websites += $site
        }
        else {
            Write-Host "Warning: Website '$siteName' not found on this server." -ForegroundColor Yellow
        }
    }

    return $websites
}

# Create or update an application pool
function Set-ApplicationPool {
    param (
        [Parameter(Mandatory = $true)]
        [string]$Name,

        [Parameter(Mandatory = $false)]
        [string]$RuntimeVersion = "",

        [Parameter(Mandatory = $false)]
        [string]$PipelineMode = "",

        [Parameter(Mandatory = $false)]
        [string]$IdentityType = "",

        [Parameter(Mandatory = $false)]
        [string]$UserName = "",

        [Parameter(Mandatory = $false)]
        [bool]$Enable32BitAppOnWin64 = $false
    )

    $result = @{
        Success = $false
        AppPool = $null
        Message = ""
    }

    try {
        # Check if the app pool already exists
        $appPoolExists = Test-Path "IIS:\AppPools\$Name"

        if ($appPoolExists) {
            Write-Host "  Application Pool '$Name' already exists, updating settings..." -NoNewline
            $appPool = Get-Item "IIS:\AppPools\$Name"
        }
        else {
            Write-Host "  Creating Application Pool '$Name'..." -NoNewline
            $appPool = New-WebAppPool -Name $Name -ErrorAction Stop
        }

        # Set app pool properties
        if ($RuntimeVersion -ne "") { $appPool.managedRuntimeVersion = $RuntimeVersion }
        if ($PipelineMode -ne "") { $appPool.managedPipelineMode = $PipelineMode }
        if ($IdentityType -ne "") { $appPool.processModel.identityType = $IdentityType }
        if ($UserName -ne "") { $appPool.processModel.userName = $UserName }
        $appPool.enable32BitAppOnWin64 = $Enable32BitAppOnWin64
        $appPool | Set-Item

        $result.Success = $true
        $result.AppPool = $appPool
        $result.Message = "Done!"
        Write-Host " Done!" -ForegroundColor Green
    }
    catch {
        $result.Message = "Error: $_"
        Write-Host " Failed!" -ForegroundColor Red
        Write-Host "  $($result.Message)" -ForegroundColor Red
    }

    return $result
}

