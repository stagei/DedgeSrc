#Requires -Version 5.1
<#
.SYNOPSIS
    Imports IIS websites from a backup package to the local server.
.DESCRIPTION
    This script automatically imports IIS websites from backup packages in the Import folder,
    applies settings correctly, and restarts IIS. After successful import, packages are moved
    to the Archive folder.
.PARAMETER ImportPath
    Optional path to a specific import file or directory. If not specified, all files in the standard import folder will be processed.
.PARAMETER NoGUI
    Run in command-line mode without GUI interaction.
.PARAMETER Force
    Force import even if websites already exist.
.EXAMPLE
    .\ImportIISSites.ps1 -NoGUI
    Imports all website packages from the standard import folder.
.EXAMPLE
    .\ImportIISSites.ps1 -ImportPath "C:\path\to\import.zip" -NoGUI
    Imports a specific website package file.
.NOTES
    Version:        1.3
    Author:         Admin Tools
    Creation Date:  Current date
#>
param (
    [Parameter(Mandatory=$false)]
    [string]$ImportPath = "",

    [Parameter(Mandatory=$false)]
    [switch]$NoGUI = $false,

    [Parameter(Mandatory=$false)]
    [switch]$Force
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

# Get standard paths
$paths = Get-StandardPaths
$importPath = $paths.ImportFolder
$archivePath = $paths.ArchiveFolder

# Ensure paths exist
Initialize-Folders

# Initialize IIS if needed
Initialize-IIS

function Import-IISConfiguration {
    param (
        [string]$ImportPath
    )

    # Check if the ImportPath contains the manifest file
    $manifestPath = "$ImportPath\WebsiteManifest.xml"
    if (-not (Test-Path $manifestPath)) {
        # Look for a subfolder that may contain the export
        $subfolders = Get-ChildItem -Path $ImportPath -Directory
        foreach ($folder in $subfolders) {
            if (Test-Path "$($folder.FullName)\WebsiteManifest.xml") {
                $ImportPath = $folder.FullName
                $manifestPath = "$ImportPath\WebsiteManifest.xml"
                break
            }
        }
    }

    if (-not (Test-Path $manifestPath)) {
        Write-Host "Cannot find WebsiteManifest.xml in the specified location." -ForegroundColor Red
        return $false
    }

    # Load the manifest file
    [xml]$xmlManifest = Get-Content -Path $manifestPath

    Write-Host "Loading manifest from: $manifestPath" -ForegroundColor Cyan
    Write-Host "Export was created on: $($xmlManifest.Objects.Object.Property | Where-Object { $_.Name -eq 'ExportDate' } | Select-Object -ExpandProperty '#text')" -ForegroundColor Cyan
    Write-Host "Source server: $($xmlManifest.Objects.Object.Property | Where-Object { $_.Name -eq 'ServerName' } | Select-Object -ExpandProperty '#text')" -ForegroundColor Cyan

    # Ensure WEBS folder exists
    if (-not (Test-Path $paths.WebsFolder)) {
        New-Item -ItemType Directory -Path $paths.WebsFolder -Force | Out-Null
        Write-Host "Created WEBS folder: $($paths.WebsFolder)" -ForegroundColor Green
    }

    # Import Application Pools
    Write-Host "`nImporting Application Pools..." -ForegroundColor Yellow
    $appPoolNodes = $xmlManifest.Objects.Object.Property | Where-Object { $_.Name -eq 'ApplicationPools' } | Select-Object -ExpandProperty 'Object'

    foreach ($appPoolNode in $appPoolNodes) {
        $appPoolProps = $appPoolNode.Property
        $appPoolName = ($appPoolProps | Where-Object { $_.Name -eq 'Name' }).'#text'
        $runtimeVersion = ($appPoolProps | Where-Object { $_.Name -eq 'RuntimeVersion' }).'#text'
        $pipelineMode = ($appPoolProps | Where-Object { $_.Name -eq 'PipelineMode' }).'#text'
        $identityType = ($appPoolProps | Where-Object { $_.Name -eq 'IdentityType' }).'#text'
        $userName = ($appPoolProps | Where-Object { $_.Name -eq 'UserName' }).'#text'
        $enable32BitAppOnWin64 = ($appPoolProps | Where-Object { $_.Name -eq 'Enable32BitAppOnWin64' }).'#text' -eq 'True'

        Write-Host "  Creating Application Pool: $appPoolName" -NoNewline

        # Check if the app pool already exists
        if (Test-Path "IIS:\AppPools\$appPoolName") {
            Write-Host " Already exists! Replacing..." -ForegroundColor Yellow
            # Remove existing app pool
            Remove-WebAppPool -Name $appPoolName
        }

        # Create the application pool
        try {
            $newAppPool = New-WebAppPool -Name $appPoolName -ErrorAction Stop

            # Set app pool properties
            if ($runtimeVersion -ne "") { $newAppPool.managedRuntimeVersion = $runtimeVersion }
            if ($pipelineMode -ne "") { $newAppPool.managedPipelineMode = $pipelineMode }
            if ($identityType -ne "") { $newAppPool.processModel.identityType = $identityType }
            if ($userName -ne "") { $newAppPool.processModel.userName = $userName }
            $newAppPool.enable32BitAppOnWin64 = $enable32BitAppOnWin64
            $newAppPool | Set-Item

            Write-Host " Done!" -ForegroundColor Green
        }
        catch {
            Write-Host " Failed!" -ForegroundColor Red
            Write-Host "  Error: $_" -ForegroundColor Red
        }
    }

    # Import Websites
    Write-Host "`nImporting Websites..." -ForegroundColor Yellow
    $websiteNodes = $xmlManifest.Objects.Object.Property | Where-Object { $_.Name -eq 'Websites' } | Select-Object -ExpandProperty 'Object'

    foreach ($websiteNode in $websiteNodes) {
        $websiteProps = $websiteNode.Property
        $siteName = ($websiteProps | Where-Object { $_.Name -eq 'Name' }).'#text'
        $siteId = [int]($websiteProps | Where-Object { $_.Name -eq 'ID' }).'#text'
        $originalPhysicalPath = ($websiteProps | Where-Object { $_.Name -eq 'PhysicalPath' }).'#text'
        $expandedPathNode = $websiteProps | Where-Object { $_.Name -eq 'ExpandedPhysicalPath' }
        $appPoolName = ($websiteProps | Where-Object { $_.Name -eq 'ApplicationPool' }).'#text'

        # Determine the new physical path based on the website name
        $physicalPath = Get-WebsiteTargetPath -SiteName $siteName

        Write-Host "Importing website: $siteName (ID: $siteId)" -ForegroundColor Yellow
        Write-Host "  Original path: $originalPhysicalPath" -ForegroundColor DarkGray
        Write-Host "  New destination path: $physicalPath" -ForegroundColor Cyan

        # Create the physical directory if it doesn't exist
        if (-not (Test-Path $physicalPath)) {
            Write-Host "  Creating physical directory: $physicalPath" -NoNewline
            try {
                New-Item -ItemType Directory -Path $physicalPath -Force | Out-Null
                Write-Host " Done!" -ForegroundColor Green
            }
            catch {
                Write-Host " Failed!" -ForegroundColor Red
                Write-Host "  Error: $_" -ForegroundColor Red
                continue
            }
        }

        # Copy website files
        $siteFilesSource = "$ImportPath\$siteName\files"
        if (Test-Path $siteFilesSource) {
            Write-Host "  Copying website files to $physicalPath..." -NoNewline
            try {
                Copy-Item -Path "$siteFilesSource\*" -Destination $physicalPath -Recurse -Force
                Write-Host " Done!" -ForegroundColor Green
            }
            catch {
                Write-Host " Failed!" -ForegroundColor Red
                Write-Host "  Error: $_" -ForegroundColor Red
            }
        }
        else {
            Write-Host "  No website files found at $siteFilesSource" -ForegroundColor Yellow
        }

        # Check if site already exists
        if (Test-Path "IIS:\Sites\$siteName") {
            # Instead of replacing the site, create a new site with an incremented name
            Write-Host "  Website $siteName already exists! Creating with new name..." -ForegroundColor Yellow

            # Find the highest number suffix that already exists
            $basePattern = [regex]::Escape($siteName)
            $existingSites = Get-Website | Where-Object { $_.Name -match "^$basePattern\d+$" } | Select-Object -ExpandProperty Name

            $highestNumber = 0
            foreach ($existingSite in $existingSites) {
                if ($existingSite -match "$basePattern(\d+)$") {
                    $number = [int]$matches[1]
                    if ($number -gt $highestNumber) {
                        $highestNumber = $number
                    }
                }
            }

            # Use one higher than the highest existing number
            $newNumber = $highestNumber + 1
            $newSiteName = "$siteName$newNumber"

            Write-Host "  Will create as $newSiteName instead" -ForegroundColor Cyan

            # Update the site name for the rest of the process
            $siteName = $newSiteName

            # Update the physical path based on the new site name
            $oldPhysicalPath = $physicalPath
            $physicalPath = Get-WebsiteTargetPath -SiteName $siteName

            # Create the new directory if it doesn't exist
            if (-not (Test-Path $physicalPath)) {
                Write-Host "  Creating physical directory: $physicalPath" -NoNewline
                try {
                    New-Item -ItemType Directory -Path $physicalPath -Force | Out-Null
                    Write-Host " Done!" -ForegroundColor Green

                    # Copy files from the original destination to the new one
                    if (Test-Path "$siteFilesSource\*") {
                        Write-Host "  Copying website files to new location: $physicalPath..." -NoNewline
                        try {
                            Copy-Item -Path "$siteFilesSource\*" -Destination $physicalPath -Recurse -Force
                            Write-Host " Done!" -ForegroundColor Green
                        }
                        catch {
                            Write-Host " Failed!" -ForegroundColor Red
                            Write-Host "  Error: $_" -ForegroundColor Red
                        }
                    }
                }
                catch {
                    Write-Host " Failed!" -ForegroundColor Red
                    Write-Host "  Error: $_" -ForegroundColor Red
                    continue
                }
            }
        }

        # Get bindings
        $bindingsNode = $websiteProps | Where-Object { $_.Name -eq 'Bindings' } | Select-Object -ExpandProperty 'Object'
        $bindings = @()

        foreach ($bindingNode in $bindingsNode) {
            $bindingProps = $bindingNode.Property
            $protocol = ($bindingProps | Where-Object { $_.Name -eq 'Protocol' }).'#text'
            $bindingInfo = ($bindingProps | Where-Object { $_.Name -eq 'BindingInfo' }).'#text'
            $sslFlags = [int]($bindingProps | Where-Object { $_.Name -eq 'SSLFlags' }).'#text'

            $bindings += @{
                Protocol = $protocol
                BindingInformation = $bindingInfo
                SSLFlags = $sslFlags
            }
        }

        # Create the website
        Write-Host "  Creating website with bindings..." -NoNewline
        try {
            # First binding for site creation
            $firstBinding = @{
                Protocol = $bindings[0].Protocol
                BindingInformation = $bindings[0].BindingInformation
            }

            # Attempt to create the site with the specified ID
            try {
                New-Website -Name $siteName -Id $siteId -PhysicalPath $physicalPath -ApplicationPool $appPoolName -Bindings $firstBinding -ErrorAction Stop
            }
            catch {
                # If creation with specific ID fails, try without specifying ID
                New-Website -Name $siteName -PhysicalPath $physicalPath -ApplicationPool $appPoolName -Bindings $firstBinding -ErrorAction Stop
            }

            # Add the rest of the bindings
            for ($i = 1; $i -lt $bindings.Count; $i++) {
                New-WebBinding -Name $siteName -Protocol $bindings[$i].Protocol -BindingInformation $bindings[$i].BindingInformation
                # Set SSL flags if needed
                if ($bindings[$i].SSLFlags -gt 0) {
                    Set-WebBinding -Name $siteName -BindingInformation $bindings[$i].BindingInformation -PropertyName sslFlags -Value $bindings[$i].SSLFlags
                }
            }

            Write-Host " Done!" -ForegroundColor Green
        }
        catch {
            Write-Host " Failed!" -ForegroundColor Red
            Write-Host "  Error: $_" -ForegroundColor Red
            continue
        }

        # Import virtual directories
        $vdirNodes = $websiteProps | Where-Object { $_.Name -eq 'VirtualDirectories' } | Select-Object -ExpandProperty 'Object'
        if ($vdirNodes -ne $null) {
            Write-Host "  Importing virtual directories..." -ForegroundColor Cyan

            foreach ($vdirNode in $vdirNodes) {
                $vdirProps = $vdirNode.Property
                $vdirName = ($vdirProps | Where-Object { $_.Name -eq 'Name' }).'#text'
                $vdirPath = ($vdirProps | Where-Object { $_.Name -eq 'Path' }).'#text'
                $originalVdirPhysicalPath = ($vdirProps | Where-Object { $_.Name -eq 'PhysicalPath' }).'#text'

                # Generate new path for virtual directory based on site name and vdir name
                $vdirPhysicalPath = Join-Path -Path $physicalPath -ChildPath $vdirName
                Write-Host "    Virtual directory path will be: $vdirPhysicalPath" -ForegroundColor Cyan

                # Create the directory if it doesn't exist
                if (-not (Test-Path $vdirPhysicalPath)) {
                    New-Item -ItemType Directory -Path $vdirPhysicalPath -Force | Out-Null
                }

                Write-Host "    Creating Virtual Directory: $vdirPath" -NoNewline
                try {
                    New-WebVirtualDirectory -Site $siteName -Name $vdirName -PhysicalPath $vdirPhysicalPath
                    Write-Host " Done!" -ForegroundColor Green
                }
                catch {
                    Write-Host " Failed!" -ForegroundColor Red
                    Write-Host "    Error: $_" -ForegroundColor Red
                }
            }
        }

        # Import applications
        $appNodes = $websiteProps | Where-Object { $_.Name -eq 'Applications' } | Select-Object -ExpandProperty 'Object'
        if ($appNodes -ne $null) {
            Write-Host "  Importing applications..." -ForegroundColor Cyan

            foreach ($appNode in $appNodes) {
                $appProps = $appNode.Property
                $appName = ($appProps | Where-Object { $_.Name -eq 'Name' }).'#text'
                $appPath = ($appProps | Where-Object { $_.Name -eq 'Path' }).'#text'
                $originalAppPhysicalPath = ($appProps | Where-Object { $_.Name -eq 'PhysicalPath' }).'#text'
                $appAppPool = ($appProps | Where-Object { $_.Name -eq 'ApplicationPool' }).'#text'

                # Generate new path for application based on site name and app name
                $appPhysicalPath = Join-Path -Path $physicalPath -ChildPath "app_$appName"
                Write-Host "    Application path will be: $appPhysicalPath" -ForegroundColor Cyan

                # Create the directory if it doesn't exist
                if (-not (Test-Path $appPhysicalPath)) {
                    New-Item -ItemType Directory -Path $appPhysicalPath -Force | Out-Null
                }

                Write-Host "    Creating Application: $appPath" -NoNewline
                try {
                    New-WebApplication -Site $siteName -Name $appName -PhysicalPath $appPhysicalPath -ApplicationPool $appAppPool
                    Write-Host " Done!" -ForegroundColor Green
                }
                catch {
                    Write-Host " Failed!" -ForegroundColor Red
                    Write-Host "    Error: $_" -ForegroundColor Red
                }
            }
        }

        Write-Host "  Website import completed." -ForegroundColor Green
    }

    return $true
}

function Test-WebsitesHealth {
    param (
        [object[]]$Websites
    )

    $allHealthy = $true

    foreach ($site in $Websites) {
        $siteName = $site.Name
        Write-Host "Checking health of website: $siteName..." -NoNewline

        # Check if site exists in IIS
        $iisWebsite = Get-Website -Name $siteName -ErrorAction SilentlyContinue
        if (-not $iisWebsite) {
            Write-Host " Failed! Website does not exist in IIS." -ForegroundColor Red
            $allHealthy = $false
            continue
        }

        # Check if site is started
        if ($iisWebsite.State -ne "Started") {
            try {
                Start-Website -Name $siteName
                $iisWebsite = Get-Website -Name $siteName
                if ($iisWebsite.State -ne "Started") {
                    Write-Host " Failed! Website could not be started." -ForegroundColor Red
                    $allHealthy = $false
                    continue
                }
            }
            catch {
                Write-Host " Failed! Error starting website: $_" -ForegroundColor Red
                $allHealthy = $false
                continue
            }
        }

        # Check if app pool is running
        $appPoolName = $iisWebsite.applicationPool
        $appPool = Get-IISAppPool -Name $appPoolName -ErrorAction SilentlyContinue
        if (-not $appPool) {
            Write-Host " Failed! Application pool '$appPoolName' does not exist." -ForegroundColor Red
            $allHealthy = $false
            continue
        }

        if ($appPool.State -ne "Started") {
            try {
                Start-WebAppPool -Name $appPoolName
                $appPool = Get-IISAppPool -Name $appPoolName
                if ($appPool.State -ne "Started") {
                    Write-Host " Failed! Application pool '$appPoolName' could not be started." -ForegroundColor Red
                    $allHealthy = $false
                    continue
                }
            }
            catch {
                Write-Host " Failed! Error starting application pool: $_" -ForegroundColor Red
                $allHealthy = $false
                continue
            }
        }

        # Check bindings
        $hasBindings = $iisWebsite.Bindings.Collection.Count -gt 0
        if (-not $hasBindings) {
            Write-Host " Warning! Website has no bindings." -ForegroundColor Yellow
        }

        Write-Host " Healthy!" -ForegroundColor Green
    }

    return $allHealthy
}

# Main execution flow
Write-Host "`n=== Automatic IIS Website Import Tool ===`n" -ForegroundColor Cyan
Write-Host "Import folder: $importPath" -ForegroundColor Cyan
Write-Host "Archive folder: $archivePath" -ForegroundColor Cyan
Write-Host "Website destination: $($paths.WebsFolder)" -ForegroundColor Cyan

# Find zip files in the import directory
$zipFiles = @()

# If a specific import path is specified
if (-not [string]::IsNullOrEmpty($ImportPath)) {
    if (Test-Path $ImportPath -PathType Leaf) {
        # Single file specified
        if ($ImportPath.EndsWith(".zip")) {
            $zipFiles = @(Get-Item -Path $ImportPath)
        } else {
            Write-Host "Specified import path is not a ZIP file: $ImportPath" -ForegroundColor Red
            exit
        }
    } elseif (Test-Path $ImportPath -PathType Container) {
        # Directory specified
        $zipFiles = Get-ChildItem -Path $ImportPath -Filter "*.zip" -File
    } else {
        Write-Host "Import path not found: $ImportPath" -ForegroundColor Red
        exit
    }
} else {
    # Use standard import folder
    $zipFiles = Get-ChildItem -Path $importPath -Filter "*.zip" -File
}

if ($zipFiles.Count -eq 0) {
    Write-Host "No import packages found" -ForegroundColor Yellow
    exit
}

Write-Host "Found $($zipFiles.Count) import package(s):" -ForegroundColor Green
$zipFiles | ForEach-Object { Write-Host "  - $($_.Name)" -ForegroundColor White }

# Process each import package
foreach ($zipFile in $zipFiles) {
    Write-Host "`nProcessing import package: $($zipFile.Name)" -ForegroundColor Cyan

    # Extract the package
    $tempExtractPath = Join-Path $env:TEMP "IISImport_$(Get-Random)"
    New-Item -ItemType Directory -Path $tempExtractPath -Force | Out-Null
    Expand-ZipArchive -ZipFilePath $zipFile.FullName -DestinationPath $tempExtractPath

    # Import the websites
    $importSuccess = Import-IISConfiguration -ImportPath $tempExtractPath

    if ($importSuccess) {
        # Load the manifest to get the website names for health checks
        $manifestPath = Get-ChildItem -Path $tempExtractPath -Filter "WebsiteManifest.xml" -Recurse | Select-Object -First 1
        if ($manifestPath) {
            [xml]$xmlManifest = Get-Content -Path $manifestPath.FullName
            $websiteNodes = $xmlManifest.Objects.Object.Property | Where-Object { $_.Name -eq 'Websites' } | Select-Object -ExpandProperty 'Object'

            # Get the actual website names from IIS as some might have been renamed during import
            $websites = @()
            $existingWebsites = Get-Website | Select-Object Name

            foreach ($websiteNode in $websiteNodes) {
                $websiteProps = $websiteNode.Property
                $originalSiteName = ($websiteProps | Where-Object { $_.Name -eq 'Name' }).'#text'

                # Look for the original name or any name that starts with originalName followed by numbers
                $matchedSites = $existingWebsites | Where-Object {
                    $_.Name -eq $originalSiteName -or $_.Name -match "^$([regex]::Escape($originalSiteName))\d+$"
                }

                foreach ($matchedSite in $matchedSites) {
                    $websites += @{ Name = $matchedSite.Name }
                }
            }

            # Restart IIS
            Write-Host "`nRestarting IIS to apply all settings..." -NoNewline
            try {
                iisreset /restart
                Write-Host " Done!" -ForegroundColor Green
            }
            catch {
                Write-Host " Failed!" -ForegroundColor Red
                Write-Host "Error restarting IIS: $_" -ForegroundColor Red
            }

            if ($websites.Count -gt 0) {
                # Verify website health
                Write-Host "`nVerifying website health..." -ForegroundColor Cyan
                $allHealthy = Test-WebsitesHealth -Websites $websites

                if ($allHealthy) {
                    Write-Host "`nAll websites are healthy! Import successful." -ForegroundColor Green
                }
                else {
                    Write-Host "`nSome websites have health issues. Please check the logs." -ForegroundColor Red
                }
            } else {
                Write-Host "`nNo matching websites found in IIS to check health." -ForegroundColor Yellow
            }
        }
        else {
            Write-Host "Warning: Could not find manifest file for health checks." -ForegroundColor Yellow
        }
    }
    else {
        Write-Host "`nImport failed or was incomplete." -ForegroundColor Red
    }

    # Clean up temp folder
    Remove-TempFolder -Path $tempExtractPath

    # Always move the import file to archive, even if import had issues
    if (-not $importSuccess) {
        Write-Host "`nImport had issues, but will still archive the package." -ForegroundColor Yellow
    }

    # Move package to archive regardless of success (prevents reprocessing the same file)
    $archiveFilePath = Join-Path $archivePath $zipFile.Name
    Write-Host "Moving import package to archive..." -NoNewline
    try {
        Move-Item -Path $zipFile.FullName -Destination $archiveFilePath -Force
        Write-Host " Done!" -ForegroundColor Green
    }
    catch {
        Write-Host " Failed!" -ForegroundColor Red
        Write-Host "Error moving package to archive: $_" -ForegroundColor Red
    }
}

Write-Host "`nImport process completed." -ForegroundColor Green

