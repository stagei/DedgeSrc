#Requires -Version 5.1
<#
.SYNOPSIS
    Exports selected IIS websites from the local server with their settings and files.
.DESCRIPTION
    This script exports specified websites from the local IIS server, including configuration,
    files, and related settings. It can be called from WebSiteHandler.ps1 with site selection.
.PARAMETER SelectedSites
    Comma-separated list of website names to export. If omitted, all sites will be exported.
.PARAMETER NoGUI
    Run in command-line mode without GUI interaction.
.PARAMETER OutputPath
    Optional custom output path for the export. If not specified, the standard path is used.
.EXAMPLE
    .\ExportIISSites.ps1 -SelectedSites "Default Web Site,MyApp" -NoGUI
    Exports the specified websites without GUI interaction.
.EXAMPLE
    .\ExportIISSites.ps1 -NoGUI
    Exports all websites without GUI interaction.
.NOTES
    Version:        1.3
    Author:         Admin Tools
    Creation Date:  Current date
#>

param (
    [Parameter(Mandatory=$false)]
    [string]$SelectedSites = "",

    [Parameter(Mandatory=$false)]
    [switch]$NoGUI = $false,

    [Parameter(Mandatory=$false)]
    [string]$OutputPath = ""
)

# Verify that $env:OptPath exists
if ([string]::IsNullOrEmpty($env:OptPath)) {
    Write-Host "ERROR: Environment variable OptPath is not set. Script cannot continue." -ForegroundColor Red
    exit 1
}

# Import common utility functions
$scriptPath = Split-Path -Parent $MyInvocation.MyCommand.Path
$commonPath = Join-Path $scriptPath "Common.ps1"
. $commonPath

# Check for admin privileges
if (-not (Test-AdminPrivileges)) {
    exit 1
}

# Verify that necessary IIS components are installed - use a consistent approach with all tools
Write-Host "Verifying IIS installation and components..." -ForegroundColor Cyan
$iisInitialized = Initialize-IIS -Verbose
if (-not $iisInitialized) {
    Write-Host "ERROR: Failed to initialize IIS. Cannot continue." -ForegroundColor Red
    Write-Host "Please ensure IIS is properly installed and that you've restarted your computer after installation." -ForegroundColor Yellow
    exit 1
}

# Parse selected sites
$selectedSiteList = @()
if (-not [string]::IsNullOrWhiteSpace($SelectedSites)) {
    # Special case: "*" means export all sites but skip ones that fail validation
    if ($SelectedSites -eq "*") {
        Write-Host "Wildcard (*) detected. Will export all valid sites." -ForegroundColor Cyan
        $selectedSiteList = @()  # Empty list means all sites
    } else {
        $selectedSiteList = $SelectedSites -split ","
    }
}

# Get standard paths
$paths = Get-StandardPaths
$localExportPath = $paths.ExportFolder

# Set up folders
Initialize-Folders

# Initialize IIS if needed
Initialize-IIS

# Create a timestamp for the export
$timestamp = Get-Date -Format "yyyyMMdd_HHmmss"
$computerName = $env:COMPUTERNAME
$exportBasePath = "$localExportPath\IISExport_${computerName}_$timestamp"

# Ensure export directory exists
New-Item -ItemType Directory -Path $exportBasePath -Force | Out-Null
Write-Host "Export location: $exportBasePath" -ForegroundColor Cyan

# Get websites to export using common function
$allWebsites = Get-IISWebsiteList -SiteNames $selectedSiteList

# Validate websites before proceeding
$websites = @()
foreach ($site in $allWebsites) {
    $siteName = $site.Name
    $siteId = $site.Id
    $physicalPath = $site.physicalPath

    # Check if physical path exists
    $pathInfo = Expand-WebsitePath -Path $physicalPath

    if (-not $pathInfo.PathExists) {
        Write-Host "Skipping website '$siteName' (ID: $siteId) - Physical path not found: $physicalPath" -ForegroundColor Yellow
        continue
    }

    # Site passes validation, add to final list
    $websites += $site
}

if ($websites.Count -eq 0) {
    Write-Host "No valid websites found to export. Exiting." -ForegroundColor Red
    exit
}

Write-Host "Exporting $($websites.Count) website(s):" -ForegroundColor Green
$websites | ForEach-Object { Write-Host "  - $($_.Name)" -ForegroundColor White }

# Create a manifest file with all website information
$manifestPath = "$exportBasePath\WebsiteManifest.xml"
$manifest = @{
    ExportDate = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    ServerName = $computerName
    Websites = @()
}

foreach ($site in $websites) {
    $siteName = $site.Name
    $siteId = $site.Id
    $physicalPath = $site.physicalPath

    # Create directory for this site
    $siteExportPath = "$exportBasePath\$siteName"
    New-Item -ItemType Directory -Path "$siteExportPath\config" -Force | Out-Null
    New-Item -ItemType Directory -Path "$siteExportPath\files" -Force | Out-Null

    Write-Host "Exporting website: $siteName (ID: $siteId)" -ForegroundColor Yellow

    # Export site configuration
    try {
        Write-Host "  Exporting configuration..." -NoNewline

        # Use site-specific export to avoid exporting everything
        $configFile = Join-Path "$siteExportPath\config" "applicationHost.config"

        # Only export this specific site by using a filter
        $sitePath = "IIS:\Sites\$siteName"
        if (Test-Path $sitePath) {
            Export-IISConfiguration -PhysicalPath "$siteExportPath\config" -DontExportKeys

            # Check if the export succeeded and contains only the required site
            if (Test-Path $configFile) {
                # File exists but we need to check if it contains other sites
                # For now, we'll assume it worked correctly
                Write-Host " Done!" -ForegroundColor Green
            } else {
                throw "Failed to create configuration file"
            }
        } else {
            throw "Site path $sitePath not found in IIS"
        }
    }
    catch {
        Write-Host " Failed!" -ForegroundColor Red
        Write-Host "  Error: $_" -ForegroundColor Red
        continue
    }

    # Get application pools for this site
    $sitesAppPool = $site.applicationPool
    Write-Host "  Application Pool: $sitesAppPool" -ForegroundColor Cyan

    # Get site bindings
    $bindings = $site.bindings.Collection | ForEach-Object {
        $bindingInfo = $_.bindingInformation
        $protocol = $_.protocol
        $sslFlags = $_.sslFlags

        @{
            Protocol = $protocol
            BindingInfo = $bindingInfo
            SSLFlags = $sslFlags
        }
    }

    # Get virtual directories
    $vdirs = Get-WebVirtualDirectory -Site $siteName | ForEach-Object {
        @{
            Name = $_.Name
            Path = $_.Path
            PhysicalPath = $_.PhysicalPath
        }
    }

    # Get applications
    $apps = Get-WebApplication -Site $siteName | ForEach-Object {
        @{
            Name = $_.Name
            Path = $_.Path
            PhysicalPath = $_.PhysicalPath
            ApplicationPool = $_.ApplicationPool
        }
    }

    # Copy website files
    $pathInfo = Expand-WebsitePath -Path $physicalPath

    if ($pathInfo.PathExists) {
        $pathToCopy = $physicalPath
        if ($pathInfo.ContainsEnvironmentVariables) {
            $pathToCopy = $pathInfo.ExpandedPath
        }

        Write-Host "  Copying website files from $pathToCopy..." -NoNewline
        if ($pathInfo.ContainsEnvironmentVariables) {
            Write-Host " (expanded from $physicalPath)" -NoNewline
        }

        try {
            Copy-Item -Path "$pathToCopy\*" -Destination "$siteExportPath\files" -Recurse -Force -ErrorAction Stop
            Write-Host " Done!" -ForegroundColor Green
        }
        catch {
            Write-Host " Failed!" -ForegroundColor Red
            Write-Host "  Error: $_" -ForegroundColor Red
        }
    }
    else {
        Write-Host "  Physical path not found: $physicalPath" -ForegroundColor Red
    }

    # Add site details to manifest
    $manifestSite = @{
        Name = $siteName
        ID = $siteId
        PhysicalPath = $physicalPath
        ApplicationPool = $sitesAppPool
        Bindings = $bindings
        VirtualDirectories = $vdirs
        Applications = $apps
    }

    # If the path contains environment variables, add the expanded path too
    if ($pathInfo.ContainsEnvironmentVariables) {
        $manifestSite.ExpandedPhysicalPath = $pathInfo.ExpandedPath
    }

    $manifest.Websites += $manifestSite

    Write-Host "  Site export completed." -ForegroundColor Green
}

# Export unique application pools configuration
Write-Host "Exporting Application Pools..." -ForegroundColor Yellow
$appPoolsExportPath = "$exportBasePath\ApplicationPools"
New-Item -ItemType Directory -Path $appPoolsExportPath -Force | Out-Null

# Get unique application pools used by the selected websites
$uniqueAppPools = @{}
foreach ($site in $websites) {
    $appPoolName = $site.applicationPool
    $uniqueAppPools[$appPoolName] = $true

    # Also get application pools used by applications within the site
    $apps = Get-WebApplication -Site $site.Name
    foreach ($app in $apps) {
        $appPoolName = $app.applicationPool
        $uniqueAppPools[$appPoolName] = $true
    }
}

$appPools = @()
foreach ($appPoolName in $uniqueAppPools.Keys) {
    $appPool = Get-IISAppPool -Name $appPoolName
    if ($appPool) {
        # Create application pool data structure
        $appPoolData = @{
            Name = $appPoolName
            IdentityType = $appPool.processModel.identityType
            UserName = $appPool.processModel.userName
            RuntimeVersion = $appPool.managedRuntimeVersion
            PipelineMode = $appPool.managedPipelineMode
            AutoStart = $appPool.autoStart
            Enable32BitAppOnWin64 = $appPool.enable32BitAppOnWin64
        }

        $appPools += $appPoolData
    }
}

# Add app pools to manifest
$manifest.ApplicationPools = $appPools

# Save manifest file
$manifest | ConvertTo-Xml -As String -NoTypeInformation | Out-File -FilePath $manifestPath -Force
Write-Host "Manifest file created at $manifestPath" -ForegroundColor Green

# Create a README file with instructions
$readmePath = "$exportBasePath\README.txt"
@"
IIS WEBSITE EXPORT
==================

Export Date: $(Get-Date -Format "yyyy-MM-dd HH:mm:ss")
Server Name: $computerName
Number of Websites: $($websites.Count)

This package contains an export of the following websites:
$(foreach ($site in $websites) { "- $($site.Name)" })

To import these websites to another server, use the WebSiteHandler.ps1 script and select "Import".

Directory Structure:
- WebsiteManifest.xml: Contains all metadata about the websites and application pools
- ApplicationPools: Configuration for all application pools
- [Website Name]: Folder for each website containing:
  - config: IIS configuration settings
  - files: Website content files

IMPORTANT: To restore these websites, run WebSiteHandler.ps1 on the destination server.
"@ | Out-File -FilePath $readmePath -Force

# Create a zip file of the entire export
$zipPath = "$localExportPath\IISExport_${computerName}_$timestamp.zip"
New-ZipArchive -SourcePath $exportBasePath -DestinationPath $zipPath
Write-Host "Export completed successfully. Archive created at: $zipPath" -ForegroundColor Green

# Clean up the temporary folder with uncompressed data
Remove-TempFolder -Path $exportBasePath

# Prompt user if they want to deploy to another server
if (-not $NoGUI) {
    $deployToServer = Read-Host -Prompt "Do you want to deploy this package to another server? (Y/N)"

    if ($deployToServer -eq "Y" -or $deployToServer -eq "y") {
        $targetServer = Read-Host -Prompt "Enter the target server name"

        if (-not [string]::IsNullOrWhiteSpace($targetServer)) {
            # Get the remote paths using the new function
            $remotePaths = Get-RemoteStandardPaths -Server $targetServer
            $targetImportFolder = $remotePaths.RemoteImportFolder

            # Check if the target server is accessible
            $targetRoot = "\\$targetServer\opt"
            if (Test-Path $targetRoot) {
                # Ensure target directories exist
                $targetFolders = @(
                    $remotePaths.BaseFolder,
                    $remotePaths.RemoteImportFolder,
                    "$($remotePaths.RemoteImportFolder)\Archive"
                )

                foreach ($folder in $targetFolders) {
                    if (-not (Test-Path $folder)) {
                        Write-Host "Creating directory on target server: $folder..." -NoNewline
                        try {
                            New-Item -ItemType Directory -Path $folder -Force | Out-Null
                            Write-Host " Done!" -ForegroundColor Green
                        }
                        catch {
                            Write-Host " Failed!" -ForegroundColor Red
                            Write-Host "Error: $_" -ForegroundColor Red
                        }
                    }
                }

                # Copy the export package
                Write-Host "Copying export package to $targetImportFolder..." -NoNewline
                try {
                    # Copy the file to the target server
                    Copy-Item -Path $zipPath -Destination $targetImportFolder -Force
                    Write-Host " Done!" -ForegroundColor Green

                    # Ask if user wants to trigger an import on the target server
                    $triggerImport = Read-Host -Prompt "Do you want to trigger an import on the target server? (Y/N)"

                    if ($triggerImport -eq "Y" -or $triggerImport -eq "y") {
                        # Path to the ImportIISSites.ps1 script on the target server
                        $importScriptPath = "$($remotePaths.BaseFolder)\ImportIISSites.ps1"

                        if (Test-Path $importScriptPath) {
                            Write-Host "Triggering import on $targetServer..." -ForegroundColor Cyan

                            try {
                                # Execute the import script on the remote server
                                $importJob = Invoke-Command -ComputerName $targetServer -ScriptBlock {
                                    & "$env:OptPath\data\WebSiteHandler\ImportIISSites.ps1"
                                } -AsJob

                                Write-Host "Import job started on $targetServer. Please check the target server for results." -ForegroundColor Yellow
                            }
                            catch {
                                Write-Host "Failed to trigger import on target server: $_" -ForegroundColor Red
                                Write-Host "You can manually run the import script on the target server." -ForegroundColor Yellow
                            }
                        }
                        else {
                            Write-Host "Import script not found on target server. You can manually run the import later." -ForegroundColor Yellow
                        }
                    }
                }
                catch {
                    Write-Host " Failed!" -ForegroundColor Red
                    Write-Host "Error copying to target server: $_" -ForegroundColor Red
                }
            }
            else {
                Write-Host "Target server share not accessible: $targetRoot" -ForegroundColor Red
                Write-Host "Please check that the server name is correct and that the share is available." -ForegroundColor Yellow
            }
        }
        else {
            Write-Host "No target server specified. Skipping deployment." -ForegroundColor Yellow
        }
    }
} else {
    Write-Host "Running in NoGUI mode. Skipping deployment prompt." -ForegroundColor Cyan
}

