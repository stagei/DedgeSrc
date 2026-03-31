<#
.SYNOPSIS
    Manages software installation, updates, and configuration using various package managers.

.DESCRIPTION
    This module provides utilities for software management, primarily using winget
    but also supporting other package managers. It handles software installation,
    updates, version tracking, and configuration management across multiple systems.

.EXAMPLE
    Install-WingetApplication -Name "Microsoft.VisualStudioCode" -Version "1.60.0"
    # Installs a specific version of VS Code using winget

.EXAMPLE
    Update-AllApplications
    # Updates all installed applications using available package managers
#>



$modulesToImport = @("GlobalFunctions", "Infrastructure", "Export-Array")
foreach ($moduleName in $modulesToImport) {
    if (-not (Get-Module -Name $moduleName) -or $env:USERNAME -in @("FKGEISTA", "FKSVEERI")) {
        Import-Module $moduleName -Force
    }
} 



function Test-FileExists {
    param (
        [Parameter(Mandatory = $true)]
        [string]$FilePath
    )
    
    return Test-Path -Path $FilePath -PathType Leaf
}

# Example usage to check for a specific exe
function Test-ApplicationInstalled {
    param (
        [Parameter(Mandatory = $true)]
        [string]$ExeName,
        
        [Parameter(Mandatory = $false)]
        [string[]]$SearchPaths = @("C:\Program Files", "C:\Program Files (x86)", "$env:USERPROFILE\AppData\Local", "$env:USERPROFILE\AppData\Roaming")
    )
    foreach ($basePath in $SearchPaths) {
        if (-not (Test-Path $basePath)) {
            continue
        }
        
        # Use Get-ChildItem to recursively search for the exe
        $found = Get-ChildItem -Path $basePath -Filter $ExeName -Recurse -ErrorAction SilentlyContinue | 
        Select-Object -First 1
        
        if ($found) {
            return $found.FullName
        }
    }
    
    return $false
}
function Get-ApplicationLogFilename {
    $networkRoot = "C:\opt\src\DedgeSrc\DedgeSystemTools\Folders\DedgeCommon\Logs\InstallationData"
    if (-not (Test-Path $networkRoot -PathType Container)) {
        New-Item -Path $networkRoot -ItemType Directory -Force | Out-Null
    }
    $computerPath = Join-Path $networkRoot $env:COMPUTERNAME.ToLower()
    if (-not (Test-Path $computerPath -PathType Container)) {
        New-Item -Path $computerPath -ItemType Directory -Force | Out-Null
    }
    $userPath = Join-Path $computerPath $env:USERNAME.ToLower()
    if (-not (Test-Path $userPath -PathType Container)) {
        New-Item -Path $userPath -ItemType Directory -Force | Out-Null
    }

    # Try to read from all-time log
    $allTimeLogFile = Join-Path $userPath "installation_log.json"
    return $allTimeLogFile
}
function Get-ApplicationLogData {
    $logData = @{}
    # Network paths
    $allTimeLogFile = Get-ApplicationLogFilename
    # Try to read from all-time log
    if (Test-Path $allTimeLogFile) {
        try {
            $logContent = Get-Content $allTimeLogFile -Raw
            if (-not [string]::IsNullOrWhiteSpace($logContent)) {
                $jsonData = $logContent | ConvertFrom-Json
                if ($null -ne $jsonData) {
                    # Convert from PSCustomObject to hashtable
                    foreach ($property in $jsonData.PSObject.Properties) {
                        $logData[$property.Name] = $property.Value
                    }
                }
            }
        }
        catch {
            Write-LogMessage "Warning: Could not read log file. Creating new log." -Level WARN -Exception $_
        }
    }
    
    if (-not $logData.ContainsKey($env:COMPUTERNAME)) {
        $logData[$env:COMPUTERNAME] = @()
    }
    return $logData
}
function Set-ApplicationLogData {
    param (
        [Parameter(Mandatory = $true)]
        [hashtable]$LogData
    )
    $logData = @{}
    # Network paths
    $allTimeLogFile = Get-ApplicationLogFilename
   
    # Try to read from all-time log
    $logData | ConvertTo-Json -Depth 10 | Set-Content $allTimeLogFile -Force
   
}

function Write-ApplicationLogEntry {
    param (
        [Parameter(Mandatory = $false)]
        [string]$AppName,
        [Parameter(Mandatory = $false)]
        [string]$Status,
        [Parameter(Mandatory = $false)]
        [string]$Message
    )
    $logData = Get-ApplicationLogData

    $entry = @{
        Application = $AppName
        Date        = (Get-Date).ToString("yyyy-MM-dd HH:mm:ss")
        Status      = $Status
        Message     = $Message
        Computer    = $env:COMPUTERNAME
        User        = $env:USERNAME
    }

    $logData[$env:COMPUTERNAME] += $entry
    # Save log data to file
    Set-ApplicationLogData -LogData $logData
    
}

function Write-ApplicationLog {
    param (
        [string]$AppName,
        [string]$Status,
        [string]$Message
    )
    try {
        Write-ApplicationLogEntry -AppName $AppName -Status $Status -Message $Message
    }
    catch {
    }
}



<#
.SYNOPSIS
    Saves application information to a file.

.DESCRIPTION
    Saves application metadata including name, version, and source to a JSON file
    in the specified download folder.

.PARAMETER AppInfo
    Object containing application information to save.

.PARAMETER DownloadFolder
    The folder where the application metadata should be saved.

.EXAMPLE
    $appInfo = @{
        Name = "MyApp"
        Version = "1.0.0"
        Source = "winget"
    }
    Save-Application -AppInfo $appInfo -DownloadFolder "C:\Downloads"
    # Saves application metadata to a JSON file
#>
function Save-Application {
    param (
        [string]$Application,
        [string]$subfolder,
        [string]$wingetVersion
    )
    try {
        # Create subfolder
        New-Item -ItemType Directory -Path $subfolder -Force -ErrorAction SilentlyContinue | Out-Null
        # Download application
        winget download $Application --download-directory $subfolder
        # Set version.txt
        Set-Content -Path $subfolder\version.txt -Value $wingetVersion -Force | Out-Null
        Write-LogMessage "Success!" -Level INFO
    }
    catch {
        Write-LogMessage "Failed to download and save application" -Level ERROR -Exception $_
    }
}

<#
.SYNOPSIS
    Downloads applications using winget.

.DESCRIPTION
    Downloads specified applications using the winget package manager and saves them
    to a specified folder. Also saves metadata about the downloaded applications.

.PARAMETER DownloadFolder
    The folder where applications should be downloaded.

.EXAMPLE
    Start-WingetDownload -DownloadFolder "C:\Downloads"
    # Downloads applications using winget to the specified folder
#>
function Start-WingetDownload ($DownloadFolder) {
    if (-not $DownloadFolder) {
        $DownloadFolder = Get-WingetAppsPath
    }
    # Check if the download folder exists, if not create itn
    if (-not (Test-Path -Path $DownloadFolder)) {
        New-Item -ItemType Directory -Path $DownloadFolder
    }
    $getApplicationsFromFile = $false

    if ($getApplicationsFromFile) {
        # Read Install-Applications.ps1 and extract winget install commands using regex
        $installScript = Get-Content -Path ".\Install-Applications.ps1" -Raw
        $regex = "winget install ([^|]+)"
        $wingetMatches = [regex]::Matches($installScript, $regex)
        $applications = $wingetMatches.Groups[1].Value.Trim().Split(" ")

    }
    else {
        $applications = @(
            "Microsoft.AzureCLI",
            "Anysphere.Cursor",
            "DBeaver.DBeaver.Community",
            "ElementLabs.LMStudio",
            "Git.Git",
            "Google.Chrome",
            "Microsoft.Azd",
            "Microsoft.DotNet.Framework.DeveloperPack_4",
            "Microsoft.DotNet.HostingBundle.8",
            "Microsoft.DotNet.HostingBundle.9",
            "Microsoft.DotNet.HostingBundle.10",
            "Microsoft.DotNet.SDK.8",
            "Microsoft.DotNet.SDK.9",
            "Microsoft.DotNet.SDK.10",
            "Microsoft.DotNet.Runtime.8",
            "Microsoft.DotNet.Runtime.9",
            "Microsoft.DotNet.Runtime.10",
            "Microsoft.DotNet.AspNetCore.8",
            "Microsoft.DotNet.AspNetCore.9",
            "Microsoft.DotNet.AspNetCore.10",
            "Microsoft.PowerAutomateDesktop",
            "Microsoft.PowerShell",
            "Microsoft.PowerToys",
            "Microsoft.SQLServer.2022.Developer",
            "Microsoft.SQLServerManagementStudio",
            "Microsoft.Azure.TrustedSigningClientTools",
            "Microsoft.VisualStudio.Community",
            "Microsoft.VisualStudio.2022.Community",
            "Microsoft.VisualStudio.2022.Professional",
            "Microsoft.VisualStudioCode",
            "Notepad++.Notepad++",
            "OpenJS.NodeJS.LTS",
            "Ollama.Ollama",
            "JohnMacFarlane.Pandoc"
        )
    }

    Write-LogMessage "Starting winget downloads..." -Level INFO

    foreach ($Application in $applications) {
        $AppName = $Application.Split()[0]
        Write-LogMessage "Downloading package: $AppName" -Level INFO
        try {
            # Get application details from winget show
            $wingetPath = Get-ExecutablePath -ExecutableName "winget.exe"
            if (-not $wingetPath) {
                Write-LogMessage "winget not found, please install winget" -Level ERROR
                return
            }
            
            $appDetails = & "$wingetPath" "show" $Application
            if ( -not $appDetails) {
                Write-LogMessage "Failed to get application details" -Level ERROR
                return
            }
            $wingetVersion = ($appDetails | Select-String "Version: (.+)").Matches.Groups[1].Value.Trim()
    
            # Check if subfolder exists $DownloadFolder\$Application
            $subfolder = Join-Path -Path $DownloadFolder.Trim() -ChildPath $Application.Trim()
            # if ($Application -eq "DBeaver.DBeaver.Community") {
            #     Remove-Item -Path $subfolder -Recurse -Force -ErrorAction SilentlyContinue | Out-Null
            # }

            if (-not (Test-Path -Path $subfolder -PathType Container)) {
                Write-LogMessage "New application, downloading..." -Level INFO
                Save-Application -Application $Application -subfolder $subfolder -wingetVersion $wingetVersion
            }
            else {
                # check the sufolder for version.txt
                if (Test-Path -Path $subfolder\version.txt -PathType Leaf) {
                    $version = Get-Content -Path $subfolder\version.txt
                }
                else {
                    $version = "0.0.0.0"
                }   
                if ($version) {            
                    # Compare the version with the winget show version
                    if ($version -eq $wingetVersion) {
                        Write-LogMessage "Already downloaded current version, skipping..." -Level WARN
                        continue
                    }
                    else {
                        # Delete the subfolder if it exists
                        if (Test-Path -Path $subfolder -PathType Container) {
                            Remove-Item -Path $subfolder -Recurse -Force -ErrorAction SilentlyContinue | Out-Null
                        }
                        Write-LogMessage "Adding application version of $Application $wingetVersion to $subfolder, downloading..." -Level INFO

                        Save-Application -Application $Application -subfolder $subfolder -wingetVersion $wingetVersion
                    }
                }
            }
        }
        catch {
            Write-LogMessage "Failed" -Level ERROR -Exception $_
        }
    }

    # Create a report on each application and version that is present in the download folder
    $report = @()
    foreach ($Application in $applications) {
        $subfolder = Join-Path -Path $DownloadFolder.Trim() -ChildPath $Application.Trim()
        if (Test-Path -Path $subfolder -PathType Container) {
            $version = Get-Content -Path (Join-Path -Path $subfolder -ChildPath "version.txt")
            $report += [PSCustomObject]@{
                Application = $Application
                Version     = $version
                Path        = $subfolder
            }
        }
    }
    $outputPath = Join-Path (Get-DevToolsWebPath) "Software" "Winget Downloaded Applications.html"
    Export-ArrayToHtmlFile -Content $report -OutputPath $outputPath -Title "Winget Downloaded Applications" -AutoOpen:$false -NoTitleAutoFormat -AddToDevToolsWebPath $true -DevToolsWebDirectory "Software/WingetApplications"

    Write-LogMessage "All done!" -Level INFO
}

function Copy-LocalWingetPackageGetExecutable {
    param (

        [Parameter(Mandatory = $true)]
        [string]$AppName,
        [Parameter(Mandatory = $false)]
        [bool]$ForceCopy = $false
    )
    # First check if application is already downloaded locally
    $downloadedApps = Get-DownloadedWingetPackages
    $localWingetPath = Get-WingetAppsPath
    $tempPath = Get-TempFkPath

    Write-LogMessage "Checking if $AppName is already downloaded..." -Level INFO
    if ($downloadedApps -contains $AppName) {
        Write-LogMessage "Yes!" -Level INFO
        
        # Create destination folder
        $destPath = Join-Path $tempPath $AppName
        Write-LogMessage "Copying package to $destPath..." -Level INFO
        
        try {
            if ((-not (Test-Path $destPath -PathType Container)) -or $ForceCopy) {
                # Remove existing folder if it exists and SkipCopy is false
                Remove-Item $destPath -Recurse -Force
                Start-Sleep -Seconds 2
                
                # Copy folder 
                $sourcePath = Join-Path $localWingetPath $AppName
                Copy-Item -Path $sourcePath -Destination $destPath -Recurse -Force
                Write-LogMessage "Done!" -Level INFO
            }
            # Check for exe/msi files
            $installerFiles = Get-ChildItem -Path $destPath -Recurse -Include "*.msi", "*.exe"
            
            if ($installerFiles.Count -eq 1) {
                # Single installer found - run as admin
                return $true, $installerFiles[0].FullName
            }
            else {
                return $false, $destPath
            }
        }
        catch {
            Write-LogMessage "Failed" -Level ERROR -Exception $_
            throw "Failed to copy package: $($_.Exception.Message)"
        }
    }
    else {
        return $false, $null
    }
}
function Get-InstallerPath {
    param ( 
        [Parameter(Mandatory = $true)]
        [string]$AppName,
        [Parameter(Mandatory = $false)]
        [bool]$ForceCopy = $false,
        [Parameter(Mandatory = $false)]
        [bool]$ShowSelection = $false
    )
    $isExecutable, $installerPath = Copy-LocalWingetPackageGetExecutable -AppName $AppName -ForceCopy $ForceCopy
    if (-not $isExecutable) {
        if ($ShowSelection) {
            $installerFiles = Get-ChildItem -Path $installerPath -Recurse -Include "*.msi", "*.exe"
            $choice = Read-Host "Multiple installers found, please select one: $($installerFiles.Name -join ", ")"
            $installerPath = $installerFiles | Where-Object { $_.Name -eq $choice }
        }
        else {
            throw "Multiple installers found, please specify which one to use"
        }
    }
    return $installerPath
}
function Get-MsiInstallArgs {
    param (
        [Parameter(Mandatory = $true)]
        [string]$InstallerPath,
        [Parameter(Mandatory = $true)]
        [string]$AppName,
        [Parameter(Mandatory = $false)]
        [ValidateSet("Direct", "MsiExec", "ArgsOnly")]
        [string]$ExecutionMode = "MsiExec",
        [Parameter(Mandatory = $false)]
        [switch]$ShowAnalysis = $false,
        [Parameter(Mandatory = $false)]
        [switch]$GenerateHtmlReport = $false

    )
    $finalCommand = ""
    $finalArgs = ""
    Write-LogMessage "Processing MSI file: $InstallerPath" -Level INFO
    
    $installer = New-Object -ComObject WindowsInstaller.Installer
    $database = $installer.OpenDatabase($InstallerPath, 0)
        
    Write-LogMessage "Reading MSI properties..." -Level WARN
        
    $properties = @{}
    $view = $database.OpenView("SELECT Property, Value FROM Property")
    $view.Execute()
        
    while ($record = $view.Fetch()) {
        $propName = $record.StringData(1)
        $propValue = $record.StringData(2)
        $properties[$propName] = $propValue
    }

    # Standard MSI properties (these are globally recognized)
    $standardProperties = @{
        'ALLUSERS'                 = '1'                    # Install for all users
        'REBOOT'                   = 'ReallySuppress'       # Prevent reboot
        'MSIRESTARTMANAGERCONTROL' = 'Disable'             # Disable restart manager
        'ARPNOREPAIR'              = '1'                    # Disable repair option
        'ARPNOMODIFY'              = '1'                    # Disable modify option
        'MSIDISABLERMRESTART'      = '1'                    # Disable restart prompt
        'SUPPRESSMSGBOXES'         = '1'                    # Suppress messages
    }

    # Application-specific properties (may or may not exist in the MSI)
    $appSpecificProperties = @{
        'ADDCONTEXTMENUHANDLERS' = '1'               # Add context menu handlers (app-specific)
        'ADDEXPLORERCONTEXTMENU' = '1'               # Add to Explorer context menu (app-specific)
        'REGISTER_MANIFEST'      = '1'               # Register shell extensions (app-specific)
        'USE_MU'                 = '1'               # Enable context menu integration (app-specific)
        'ACCEPTEULA'             = '1'               # Accept EULA (app-specific)
        'ACCEPT_EULA'            = '1'               # Alternative EULA acceptance
        'EULA'                   = '1'               # Another EULA variant
        'UI_PASSIVE'             = '1'               # Enable passive UI mode
        'PASSIVE'                = '1'               # Alternative passive mode
    }

    Write-LogMessage "MSI Properties Analysis:" -Level INFO
        
    # Create property analysis table
    $propertyAnalysis = @()
        
    # Analyze standard properties
    foreach ($prop in $standardProperties.Keys) {
        $propertyAnalysis += [PSCustomObject]@{
            Property       = $prop
            Value          = $standardProperties[$prop]
            Type           = "Standard MSI"
            Source         = "Windows Installer SDK"
            ConfirmedInMSI = $properties.ContainsKey($prop)
            Description    = switch ($prop) {
                'ALLUSERS' { "Install application for all users when set to 1" }
                'REBOOT' { "Controls system reboot behavior (ReallySuppress prevents reboot)" }
                'MSIRESTARTMANAGERCONTROL' { "Controls Windows Restart Manager integration" }
                'ARPNOREPAIR' { "Disables repair option in Add/Remove Programs when set to 1" }
                'ARPNOMODIFY' { "Disables modify option in Add/Remove Programs when set to 1" }
                'MSIDISABLERMRESTART' { "Disables Restart Manager prompt" }
                'SUPPRESSMSGBOXES' { "Suppresses message boxes during installation" }
                default { "Standard Windows Installer property" }
            }
        }
    }

    # Analyze app-specific properties
    foreach ($prop in $appSpecificProperties.Keys) {
        $propertyAnalysis += [PSCustomObject]@{
            Property       = $prop
            Value          = $appSpecificProperties[$prop]
            Type           = "Application Specific"
            Source         = "Application MSI"
            ConfirmedInMSI = $properties.ContainsKey($prop)
            Description    = switch ($prop) {
                'ADDCONTEXTMENUHANDLERS' { "Adds application handlers to Windows context menu" }
                'ADDEXPLORERCONTEXTMENU' { "Adds application to Explorer context menu" }
                'REGISTER_MANIFEST' { "Registers application shell extensions" }
                'USE_MU' { "Enables context menu integration" }
                { $_ -match 'EULA|ACCEPT_EULA|ACCEPTEULA' } { "Automatically accepts End User License Agreement" }
                { $_ -match 'UI_PASSIVE|PASSIVE' } { "Enables passive installation mode" }
                default { "Application-specific custom property" }
            }
        }
    }

    # Analyze MSI-defined properties not in our standard or app-specific lists
    foreach ($prop in $properties.Keys) {
        if (-not ($standardProperties.ContainsKey($prop) -or $appSpecificProperties.ContainsKey($prop))) {
            $propertyAnalysis += [PSCustomObject]@{
                Property       = $prop
                Value          = $properties[$prop]
                Type           = "Custom"
                Source         = "MSI Package"
                ConfirmedInMSI = $true
                Description    = "Custom property defined in MSI package"
            }
        }
    }
    if ($ShowAnalysis) {
        $propertyAnalysis | Format-Table -AutoSize
    }
    if ($GenerateHtmlReport) {
        $htmlPath = Join-Path $(Get-DevToolsWebPath)  "MSI Property Analysis" "$($AppName).html"
        Export-ArrayToHtmlFile -Content $propertyAnalysis -Title "MSI Property Analysis for $($AppName)" -AutoOpen -OutputPath $htmlPath -AddToDevToolsWebPath "Software/MSI Analysis"
    }

    # Build install arguments string after analysis
    $installArgs = ""  # Start with empty string
    Write-LogMessage "Building install arguments..." -Level WARN

    # Add all standard properties
    foreach ($prop in $standardProperties.Keys) {
        $installArgs += " $prop=$($standardProperties[$prop])"
    }

    # Always add REGISTER_MANIFEST and SUPPRESSMSGBOXES
    $installArgs += " REGISTER_MANIFEST=1 SUPPRESSMSGBOXES=1"

    # Add all context menu and integration properties if they exist in MSI
    foreach ($prop in @('ADDCONTEXTMENUHANDLERS', 'ADDEXPLORERCONTEXTMENU', 'USE_MU')) {
        if ($properties.ContainsKey($prop)) {
            $installArgs += " $prop=1"
        }
    }

    # Add EULA acceptance if any variant exists
    foreach ($prop in @('ACCEPTEULA', 'ACCEPT_EULA', 'EULA')) {
        if ($properties.ContainsKey($prop)) {
            $installArgs += " $prop=1"
        }
    }

    # Add passive mode if supported
    foreach ($prop in @('UI_PASSIVE', 'PASSIVE')) {
        if ($properties.ContainsKey($prop)) {
            $installArgs += " $prop=1"
        }
    }
    # For MSI files, we need to ensure the path is quoted if it contains spaces
    # Format final command based on execution mode
    if ($ExecutionMode -eq "MsiExec") {
        $finalCommand = "msiexec.exe"
        $finalArgs = "/i `"$InstallerPath`" /qn $installArgs"
    }
    elseif ($ExecutionMode -eq "Direct") {
        $finalCommand = "`"$InstallerPath`""
        $finalArgs = "/qn $installArgs"
    }

    Write-LogMessage "Final install arguments: $finalCommand $finalArgs" -Level INFO


    # Cleanup COM objects
    [System.Runtime.InteropServices.Marshal]::ReleaseComObject($view) | Out-Null
    [System.Runtime.InteropServices.Marshal]::ReleaseComObject($database) | Out-Null
    [System.Runtime.InteropServices.Marshal]::ReleaseComObject($installer) | Out-Null
    [System.GC]::Collect()
    [System.GC]::WaitForPendingFinalizers()
    $json = @{  
        Command   = $finalCommand
        Arguments = $finalArgs
    } | ConvertTo-Json
    return $json
}





function Get-ExeInstallArgs {
    param (
        [Parameter(Mandatory = $true)]
        [string]$InstallerPath,
        [Parameter(Mandatory = $true)]
        [string]$AppName,        
        [Parameter(Mandatory = $false)]
        [bool]$ForceCopy = $false,        
        [Parameter(Mandatory = $false)]
        [ValidateSet("Direct", "MsiExec", "ArgsOnly")]
        [string]$ExecutionMode = "Direct",
        [Parameter(Mandatory = $false)]
        [switch]$ShowAnalysis = $false,
        [Parameter(Mandatory = $false)]
        [switch]$GenerateHtmlReport = $false

    )
    
    # Common silent install switches for various installers
    $commonSwitches = @(
        '/S', # Standard silent install
        '/SILENT', # InnoSetup
        '/VERYSILENT', # InnoSetup
        '/NORESTART', # Prevent restart
        '/SUPPRESSMSGBOXES', # Suppress messages
        '/NOCANCEL', # Prevent cancellation
        '/CLOSEAPPLICATIONS', # Close conflicting apps
        '/SP-', # Disable startup prompt
        '/ALLUSERS=1'          # Install for all users
    )

        
    $installArgs = $commonSwitches -join ' '
    $finalCommand = ""
    $finalArgs = $installArgs
    if ($ExecutionMode -eq "Direct") {
        $finalCommand = "`"$InstallerPath`" "
    }
        
    Write-LogMessage "Using standard EXE silent install switches: $installArgs" -Level INFO
    $obj = [PSCustomObject]@{
        Command   = $finalCommand
        Arguments = $finalArgs
    }
    return $obj
}
function Get-MsiAnalysis {
    param (
        [Parameter(Mandatory = $true)]
        [string]$AppName
    )
    $finalCommand = ""
    $finalArgs = ""
    $installerPath = Get-InstallerPath -AppName $AppName -ForceCopy $false -ShowSelection $true
    $extension = [System.IO.Path]::GetExtension($installerPath)

    if ($extension -eq ".msi") {
        # $obj = `
        Get-MsiInstallArgs -InstallerPath $installerPath -AppName $AppName -ExecutionMode "Direct" -ShowAnalysis -GenerateHtmlReport
    }
    else {
        throw "Unsupported file extension: $extension"
    }
    return (@{
            Command   = $finalCommand
            Arguments = $finalArgs
        } | ConvertTo-Json)
}
<#
.SYNOPSIS
    Gets the command and arguments to run for a winget package.

.DESCRIPTION
    Gets the command and arguments to run for a winget package.
#>
function Get-FilesAndCommandToRun {
    param (
        [Parameter(Mandatory = $true)]
        [string]$AppName,
        [Parameter(Mandatory = $false)]
        [bool]$ForceCopy = $false,
        [Parameter(Mandatory = $false)]
        [bool]$ShowSelection = $false
    )
    $installerPath = Get-InstallerPath -AppName $AppName -ForceCopy $ForceCopy -ShowSelection $ShowSelection
   
    $extension = [System.IO.Path]::GetExtension($installerPath)
    if ($extension -eq ".msi") {
        $json = Get-MsiInstallArgs -InstallerPath $installerPath -AppName $AppName -ExecutionMode "Direct"
    }
    elseif ($extension -eq ".exe") {
        $json = Get-ExeInstallArgs -InstallerPath $installerPath -AppName $AppName -ExecutionMode "Direct" 
    }
    else {
        $json = @{
            Command   = $installerPath
            Arguments = ""
        } | ConvertTo-Json
    }
    return $json
}
    
# <#
# .SYNOPSIS
#     Installs a winget package from a local file.

# .DESCRIPTION
#     Installs a winget package using a locally downloaded installer file.
#     Supports various installation methods and parameters.

# .PARAMETER InstallerPath
#     Path to the local installer file.

# .PARAMETER Silent
#     If true, performs a silent installation.

# .PARAMETER Args
#     Additional arguments to pass to the installer.

# .PARAMETER QueryWinget
#     If true, queries winget to check if the application is installed.

# .PARAMETER WaitForInstaller
#     If true, waits for the installer to complete.

# .EXAMPLE
#     Install-WingetPackage -InstallerPath "C:\Downloads\MyApp.exe" -Silent $true
#     # Installs the application silently from local file
# #>
# function Install-WingetPackage2 {
#     param(
#         [Parameter(Mandatory = $true)]
#         [string]$AppName,
        
#         [Parameter(Mandatory = $false)]
#         [string]$Executable = "",

#         [Parameter(Mandatory = $false)]
#         [string]$InstallArgs = "",

#         [Parameter(Mandatory = $false)]
#         [bool]$QueryWinget = $false,

#         [Parameter(Mandatory = $false)]
#         [bool]$WaitForInstaller = $false,

#         [Parameter(Mandatory = $false)]
#         [bool]$AutoArgs = $false
        
#     )


#     # Check if already installed using winget
#     Write-LogMessage "Checking if $AppName is installed..." -Level INFO
#     if ($QueryWinget -eq $true) {
#         #verify winget is installed
#         $null = Get-Command winget -ErrorAction Stop
#         if ($null -ne $wingetResult) {
#             Write-LogMessage "winget is not installed" -Level ERROR
#             $wingetResult = winget list --id $AppName --exact | Out-String
#             if ($wingetResult -match $AppName) {
#                 $version = if ($wingetResult -match "(\d+\.[\d\.]+)") { $matches[1] } else { "unknown" }
#                 Write-LogMessage "Yes. Version $version is installed" -Level INFO
#                 return
#             }
#             Write-LogMessage "Not installed" -Level WARN
#         }
#     }
#     $finalCommand = ""
#     $finalArgs = ""
#     try {   
#         $json = Get-FilesAndCommandToRun -AppName $AppName -ForceCopy $false -ShowSelection $true
#         $obj = $json | ConvertFrom-Json
#         $finalCommand = $obj.Command.Trim()
#         $finalArgs = $obj.Arguments.Trim()
#         if ([string]::IsNullOrEmpty($finalCommand)) {
#             Write-LogMessage "No installer files found" -Level ERROR
#             throw "No installer files found"
#         }
#     }
#     catch {
#         Write-LogMessage "Error getting files and command to run" -Level ERROR -Exception $_
#         throw "Error getting files and command to run"
#     }
#     if (-not $AutoArgs) {
#         $finalArgs = $InstallArgs
#     }
  

#     Write-LogMessage "Installing $AppName from: `n$finalCommand $finalArgs..." -Level INFO
#     try {
#         if ($WaitForInstaller) {
#             Start-Process -FilePath $finalCommand -ArgumentList $finalArgs -Wait -NoNewWindow -Verb RunAs
#             Write-LogMessage "Installation completed successfully" -Level INFO
#             return
#         }
#         else {
#             Start-Process -FilePath $finalCommand -ArgumentList $finalArgs -Verb RunAs
#             Write-LogMessage "Installation started (no wait)" -Level INFO
#             return
#         }
#     }
#     catch {
#         Write-LogMessage "Failed to install $AppName" -Level ERROR -Exception $_
#         Write-LogMessage "Command: $finalCommand" -Level ERROR
#         Write-LogMessage "Arguments: $finalArgs" -Level ERROR
#     }

# }

<#
.SYNOPSIS
    Gets a list of downloaded winget packages.

.DESCRIPTION
    Returns an array of winget packages that have been downloaded locally.

.EXAMPLE
    $packages = Get-DownloadedWingetPackages
    # Returns array of downloaded winget packages
#>
function Get-DownloadedWingetPackages {
    $localWingetPath = Get-WingetAppsPath
    $list = Get-ChildItem -Path $localWingetPath -Directory | Select-Object -ExpandProperty Name
    return $list
}

<#
.SYNOPSIS
    Displays a list of downloaded winget packages.

.DESCRIPTION
    Shows a formatted list of winget packages that have been downloaded locally,
    including their metadata.

.EXAMPLE
    Show-DownloadedWingetPackages
    # Displays list of downloaded winget packages
#>
function Show-DownloadedWingetPackages {
    $list = Get-DownloadedWingetPackages
    # show list in a table
    Write-LogMessage ("=" * 80) -Level INFO
    Write-LogMessage "List of downloaded winget packages:" -Level INFO
    Write-LogMessage ("-" * 80) -Level INFO
    $list | Format-Table -AutoSize
    Write-LogMessage ("-" * 80) -Level INFO
}
# function Install-WingetPackage {
#     param (
#         [Parameter(Mandatory)]
#         [string]$AppName
#     )

#     # First check if application is already downloaded locally
#     $downloadedApps = Get-DownloadedWingetPackages
#     $localWingetPath = Get-WingetAppsPath
#     $tempPath = Get-TempFkPath

#     Write-LogMessage "Checking if $AppName is already downloaded..." -Level INFO
#     if ($downloadedApps -contains $AppName) {
#         Write-LogMessage "Yes!" -Level INFO
        
#         # Create destination folder
#         $destPath = Join-Path $tempPath $AppName
#         Write-LogMessage "Copying package to $destPath..." -Level INFO
        
#         try {
#             # Remove existing folder if it exists
#             if (Test-Path $destPath -PathType Container) {
#                 Remove-Item $destPath -Recurse -Force
#             }
            
#             # Copy folder
#             $sourcePath = Join-Path $localWingetPath $AppName
#             Copy-Item -Path $sourcePath -Destination $destPath -Recurse
#             Write-LogMessage "Done!" -Level INFO
#             # Check for exe/msi files
#             $installerFiles = Get-ChildItem -Path $destPath -Recurse -Include "*.msi", "*.exe"
            
#             if ($installerFiles.Count -eq 1) {
#                 # Single installer found - run as admin
#                 Write-LogMessage "Running installer..." -Level INFO
#                 Start-Process -FilePath $installerFiles[0].FullName -Verb RunAs
#                 Write-LogMessage "Done!" -Level INFO
#             }
#             else {
#                 # Multiple or no installers - open explorer
#                 Write-LogMessage "Opening Explorer..." -Level INFO
#                 Start-Process explorer.exe -ArgumentList $destPath
#                 Write-LogMessage "Done!" -Level INFO
#             }
#         }
#         catch {
#             Write-LogMessage "Failed!" -Level ERROR -Exception $_
#             throw "Failed to copy package: $($_.Exception.Message)"
#         }
#     }
#     else {
#         Write-LogMessage "No" -Level WARN
        
#         # Check if winget is installed
#         Write-LogMessage "Checking if winget is installed..." -Level INFO
#         try {
#             $null = Get-Command winget -ErrorAction Stop
#             Write-LogMessage "Yes!" -Level INFO
            
#             # Install using winget
#             Write-LogMessage "Installing $AppName using winget..." -Level INFO
#             winget install --id $AppName --accept-source-agreements --accept-package-agreements
#         }
#         catch {
#             Write-LogMessage "No" -Level ERROR -Exception $_
#             throw "Winget is not installed. Please install winget first."
#         }
#     }
# }
function Set-Db2ServerConfig {
    param (
        [Parameter(Mandatory = $false)]
        [string]$AppName = "Db2 Server 12.1"
    )
    
}

function Get-VSCodeExtension {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $true)]
        [string]$ExtensionId
    )

    try {
        # VS Code Marketplace API URL base
        $baseUrl = "https://marketplace.visualstudio.com/_apis/public/gallery/extensionquery"
        
        # Split extension ID into publisher and extension name
        $publisher, $extensionName = $ExtensionId.Split('.')
        
        if (-not $extensionName) {
            $extensionName = $publisher
            $publisher = $ExtensionId.Split('-')[0]
        }

        # Create request headers
        $headers = @{
            'Content-Type' = 'application/json'
            'Accept'       = 'application/json;api-version=7.1-preview.1'
            'User-Agent'   = 'Mozilla/5.0'
        }

        # Create request body
        $body = @{
            filters = @(
                @{
                    criteria = @(
                        @{
                            filterType = 7
                            value      = "$publisher.$extensionName"
                        }
                    )
                }
            )
            flags   = 2047
        } | ConvertTo-Json -Depth 10

        # Get extension metadata
        $response = Invoke-RestMethod -Uri $baseUrl -Method Post -Headers $headers -Body $body
        
        if (-not $response.results) {
            throw "Extension not found: $ExtensionId"
        }

        # Get download URL from response
        $downloadUrl = $response.results[0].extensions[0].versions[0].files | 
        Where-Object { $_.assetType -eq "Microsoft.VisualStudio.Services.VSIXPackage" } |
        Select-Object -ExpandProperty source

        # Create the destination directory if it doesn't exist
        $downloadPath = Join-Path $(Get-SoftwarePath) "VSCodeExtensions"
        if (-not (Test-Path $downloadPath -PathType Container)) {
            New-Item -ItemType Directory -Path $downloadPath | Out-Null
        }

        # Download the VSIX file
        $vsixPath = Join-Path $downloadPath "$ExtensionId.vsix"
        
        Write-LogMessage "Downloading extension from: $downloadUrl" -Level INFO
        Write-LogMessage "Saving to: $vsixPath" -Level INFO

        Invoke-WebRequest -Uri $downloadUrl -OutFile $vsixPath -UseBasicParsing
        
        Write-LogMessage "Successfully downloaded extension to: $vsixPath" -Level INFO

        if ($ExtensionId -eq "halcyontechltd.vscode-db2i") {
            try {
                $appdataFolder = $(Get-ApplicationDataPath) + "\$($ExtensionId)Dependencies"
                Remove-Item -Path $appdataFolder -Recurse -Force -ErrorAction SilentlyContinue | Out-Null
                New-Item -ItemType Directory -Path $appdataFolder -ErrorAction SilentlyContinue | Out-Null
                Set-Location $appdataFolder
                $commands = @(
                    "npm install ibm_db@3.3.0",
                    "npm pack ibm_db@3.3.0"
                )  
    
                foreach ($command in $commands) {
                    $commandOutput = Invoke-Expression $command
                    Write-Output $commandOutput
                }

                # Check if the package is downloaded
                $files = Get-ChildItem -Path $appdataFolder -Filter "*.tgz"
                if ($files.Count -ne 0) {
                    $targetFolder = Join-Path $(Get-SoftwarePath) "VSCodeExtensions\halcyontechltd.vscode-db2i"
                    if (-not (Test-Path $targetFolder -PathType Container)) {
                        New-Item -ItemType Directory -Path $targetFolder -ErrorAction SilentlyContinue | Out-Null
                    }
                    # Zip folder to zip file
                    $zipFile = Join-Path $appdataFolder "node_dependencies.zip"
                    Compress-Archive -Path $appdataFolder -DestinationPath $zipFile
                    Copy-Item -Path $zipFile -Destination $targetFolder -Force
                    Remove-Item -Path $zipFile -Force
                }
                Pop-Location
            }
            catch {
                Write-LogMessage "Failed to download node dependencies for $ExtensionId" -Level WARN
            }
        }
        return $vsixPath
    }
    catch {
        Write-LogMessage "Failed to download extension" -Level ERROR -Exception $_
        return $null
    }
}

function Get-ExtentionArray {
    return @(
        [PSCustomObject]@{
            Description  = "Enhanced log file viewer and analyzer"
            Id           = "berublan.vscode-log-viewer" 
            DownloadPath = ""
        },
        [PSCustomObject]@{
            Description  = "Hex editor for viewing and editing binary files"
            Id           = "ms-vscode.hexeditor"
            DownloadPath = ""
        },
        [PSCustomObject]@{
            Description  = "Support for Makefile projects in VS Code"
            Id           = "ms-vscode.makefile-tools"
            DownloadPath = ""
        },
        [PSCustomObject]@{
            Description  = "PowerShell language support for VS Code"
            Id           = "ms-vscode.powershell"
            DownloadPath = ""
        },
        [PSCustomObject]@{
            Description  = "Run batch files directly from VS Code"
            Id           = "nilssoderman.batch-runner"
            DownloadPath = ""
        },
        [PSCustomObject]@{
            Description  = "Launch a local development server for web pages"
            Id           = "ritwickdey.liveserver"
            DownloadPath = ""
        },
        [PSCustomObject]@{
            Description  = "Code formatter for JavaScript, TypeScript, and more"
            Id           = "esbenp.prettier-vscode"
            DownloadPath = ""
        },
        [PSCustomObject]@{
            Description  = "Prettier and ESLint integration for VS Code"
            Id           = "rvest.vs-code-prettier-eslint"
            DownloadPath = ""
        },
        [PSCustomObject]@{
            Description  = "Mermaid diagram support in Markdown"
            Id           = "bierner.markdown-mermaid"
            DownloadPath = ""
        },
        [PSCustomObject]@{
            Description  = "Enhanced Markdown preview with extra features"
            Id           = "shd101wyy.markdown-preview-enhanced"
            DownloadPath = ""
        }
    )
}
function Start-VsixDownload {
    $extensions = Get-ExtentionArray

    Write-LogMessage ("-" * 75) -Level INFO
    Write-LogMessage "Starting VSCode extension downloads..." -Level INFO
    Write-LogMessage ("-" * 75) -Level INFO

    foreach ($extension in $extensions) {
        Write-LogMessage "Downloading $($extension.Description)..." -Level INFO
        $result = Get-VSCodeExtension -ExtensionId $extension.Id -Verbose

        if ($result) {
            $extension.DownloadPath = $result
        }
        else {
            Write-LogMessage "Failed to download extension" -Level ERROR
        }   
    }

    $outputFolder = Join-Path (Get-ApplicationDataPath) "Software\VSCode Extensions"
    $outputPath = Join-Path $outputFolder "VSCode Extensions.html"
    Export-ArrayToHtmlFile -Content $extensions -OutputPath $outputPath -Title "VSCode Extensions" -AddToDevToolsWebPath $true -DevToolsWebDirectory "Software/VSCode Extensions" -NoTitleAutoFormat
}
function Install-Extension {
    param (
        [Parameter(Mandatory = $true)]
        [string]$ExtensionId,
        
        [Parameter(Mandatory = $false)]
        [ValidateSet('Microsoft.VisualStudioCode', 'Anysphere.Cursor')]
        [string]$AppName = 'Microsoft.VisualStudioCode'
    )
    
    $vsixPath = Join-Path $(Get-SoftwarePath) "VSCodeExtensions" "$($ExtensionId.ToString()).vsix"
    # Create work folder if it doesn't exist
    $workFolder = "C:\tempfk\Work"
    if (-not (Test-Path $workFolder)) {
        New-Item -ItemType Directory -Path $workFolder -Force | Out-Null
    }

    # Copy vsix file to work folder
    $workPath = Join-Path $workFolder (Split-Path $vsixPath -Leaf)
    Copy-Item -Path $vsixPath -Destination $workPath -Force
    $vsixPath = $workPath

    if (-not (Test-Path $vsixPath -PathType Leaf)) {
        Write-LogMessage "Extension not found: $ExtensionId" -Level ERROR
        return
    }

    try {
        #Write-ApplicationLog -AppName $AppName -Status "Started" -Message "Installing extension $ExtensionId"

        $extension = Get-ExtentionArray | Where-Object { $_.Id -eq $ExtensionId }
        Write-LogMessage "Installing $($extension.Description)..." -Level INFO
        
        $command = ""
        $commandArgs = ""
        # $editorCmd = if ($AppName -eq 'Anysphere.Cursor') { 'cursor' } else { 'code' }
        # $command = " `"$vsixPath`""
        # Write-LogMessage "Running command: $command" -Level INFO
        if ($AppName -eq 'Anysphere.Cursor') {
            $env:Path += ";C:\Program Files\Cursor"
            $command = Get-CommandPathWithFallback -Name "cursor"
            if ([string]::IsNullOrEmpty($command) -or $command -eq "cursor") {
                Write-LogMessage "$AppName is not installed" -Level WARN
                return
            }            
            #$commandArgs = " --install-extension $($vsixPath)" + "  & pause"
            $commandArgs = " --install-extension $($vsixPath)"
        }
        else {
            $env:Path += ";C:\Program Files\Microsoft VS Code\bin"
            $command = Get-CommandPathWithFallback -Name "code"
            if ([string]::IsNullOrEmpty($command) -or $command -eq "code") {
                Write-LogMessage "$AppName is not installed" -Level WARN
                return
            }
            $commandArgs = " --install-extension $($vsixPath)"
            #$commandArgs = " --install-extension $($vsixPath)" + "  & pause"
        }
        $result = Start-Process -FilePath $command -ArgumentList $commandArgs -Wait -PassThru
        if ($result.ExitCode -ne 0) {
            Write-LogMessage "Failed to install extension: $ExtensionId" -Level ERROR
            return $false
        }
        
        Write-LogMessage "Successfully installed extension: $ExtensionId" -Level INFO
        Write-ApplicationLog -AppName $AppName -Status "Completed" -Message "Installation completed for $ExtensionId"
    }
    catch {
        Write-LogMessage "Failed to install extension from path $vsixPath for $ExtensionId" -Level ERROR -Exception $_
        Write-ApplicationLog -AppName $AppName -Status "Failed" -Message "Installation failed for $ExtensionId"
    }
}

function Install-VSCodeExtension {
    param (
        [Parameter(Mandatory = $true)]
        [string]$ExtensionId
    )
    Install-Extension -ExtensionId $ExtensionId -AppName "Microsoft.VisualStudioCode" 
}

function Install-CursorExtension {
    param (
        [Parameter(Mandatory = $true)]
        [string]$ExtensionId
    )
    Install-Extension -ExtensionId $ExtensionId -AppName "Anysphere.Cursor"   
}

function Get-VSCodeInstaller {
    param (
        [Parameter(Mandatory = $false)]
        [string]$DownloadUrl = "https://code.visualstudio.com/docs/?dv=win64",
        [Parameter(Mandatory = $false)] 
        [string]$DestinationPath = "C:\opt\src\DedgeSrc\DedgeSystemTools\Folders\DedgeCommon\Software\WindowsApps\VSCode System-Installer"
    )
    try {
        # Create destination directory if it doesn't exist
        if (-not (Test-Path -Path $DestinationPath)) {
            New-Item -ItemType Directory -Path $DestinationPath -Force | Out-Null
            Write-LogMessage "Created destination directory: $DestinationPath" -Level INFO
        }

        # Download the installer
        Write-LogMessage "Downloading VSCode installer from $DownloadUrl" -Level INFO
        
        #delete all files in the Downloads folder named VSCodeSetup*.exe
        $downloadsPath = (New-Object -ComObject Shell.Application).NameSpace('shell:Downloads').Self.Path
        Get-ChildItem -Path $downloadsPath -Filter "VSCodeSetup*.exe" | Remove-Item -Force

        # Open URL in Edge to trigger auto-download
        $edgePath = Get-CommandPathWithFallback -Name "msedge"
        $null = Start-Process $edgePath -ArgumentList $DownloadUrl -PassThru -WindowStyle Hidden
        # Wait for VSCode installer to appear in Downloads folder
        $downloadsPath = (New-Object -ComObject Shell.Application).NameSpace('shell:Downloads').Self.Path
        $maxWaitTime = 60 # Maximum wait time in seconds
        $waitTime = 0
        do {
            Start-Sleep -Seconds 1
            $waitTime++
            $newVSCode = Get-ChildItem -Path $downloadsPath -Filter "VSCodeSetup*.exe" | Where-Object { $_.LastWriteTime -gt (Get-Date).AddMinutes(-5) }
        } while ($null -eq $newVSCode -and $waitTime -lt $maxWaitTime)
        

        Stop-Process -Name "msedge" -Force

        if ($waitTime -ge $maxWaitTime) {
            throw "Timed out waiting for VSCode installer download"
        }

        Get-ChildItem -Path $DestinationPath -Filter "*.exe" | Remove-Item -Force

        $installerPath = Join-Path $DestinationPath $newVSCode.Name

        Write-LogMessage "Moving $($newVSCode.FullName) to $installerPath" -Level INFO
        Move-Item -Path $newVSCode.FullName -Destination $installerPath -Force
        
        if (Test-Path $installerPath) {
            Write-LogMessage "Successfully downloaded VSCode installer to: $installerPath" -Level INFO
        }
        else {
            Write-LogMessage "Failed to download VSCode installer" -Level ERROR
        }
    }
    catch {
        Write-LogMessage "Error downloading VSCode installer" -Level ERROR -Exception $_
    }
}

function Get-CursorInstaller {
    param (
        [Parameter(Mandatory = $false)]
        [string]$DownloadUrl = "https://cursor.com/api/download?platform=win32-x64&releaseTrack=stable",
        [Parameter(Mandatory = $false)] 
        [string]$DestinationPath = "C:\opt\src\DedgeSrc\DedgeSystemTools\Folders\DedgeCommon\Software\WindowsApps\Cursor System-Installer"
    )

    try {
        # Create destination directory if it doesn't exist
        if (-not (Test-Path -Path $DestinationPath)) {
            New-Item -ItemType Directory -Path $DestinationPath -Force | Out-Null
            Write-LogMessage "Created destination directory: $DestinationPath" -Level INFO
        }


        #delete all files in the Downloads folder named CursorSetup*.exe
        $downloadsPath = (New-Object -ComObject Shell.Application).NameSpace('shell:Downloads').Self.Path
        Get-ChildItem -Path $downloadsPath -Filter "CursorSetup*.exe" | Remove-Item -Force
    
        # Download the installer
        Write-LogMessage "Downloading Cursor installer from $DownloadUrl" -Level INFO
        

        # {"version":"1.1.7","commitSha":"7111807980fa9c93aedd455ffa44b682c0dc1356","downloadUrl":"https://downloads.cursor.com/production/7111807980fa9c93aedd455ffa44b682c0dc1356/win32/x64/system-setup/CursorSetup-x64-1.1.7.exe","rehUrl":"https://cursor.blob.core.windows.net/remote-releases/7111807980fa9c93aedd455ffa44b682c0dc1350/vscode-reh-win32-x64.tar.gz"}
        $json = Invoke-RestMethod -Uri $DownloadUrl
        $downloadUrl = $json.downloadUrl
        Write-LogMessage "Downloading Cursor installer path from $downloadUrl" -Level INFO

        $webClient = New-Object System.Net.WebClient
        $fileName = [System.IO.Path]::GetFileName($downloadUrl)
        $tempPath = Join-Path ([System.IO.Path]::GetTempPath()) $fileName
        $webClient.DownloadFile($downloadUrl, $tempPath)
        $installerPath = Join-Path $DestinationPath $fileName

        Get-ChildItem -Path $DestinationPath -Filter "*.exe" | Remove-Item -Force
        Write-LogMessage "Moving $tempPath to $installerPath" -Level INFO
        Move-Item -Path $tempPath -Destination $installerPath -Force

        Write-LogMessage "Successfully downloaded Cursor installer to: $installerPath" -Level INFO
        
        if (Test-Path $installerPath) {
            Write-LogMessage "Successfully downloaded Cursor installer to: $installerPath" -Level INFO
        }
        else {
            Write-LogMessage "Failed to download Cursor installer" -Level ERROR
        }
    }
    catch {
        Write-LogMessage "Error downloading Cursor installer" -Level ERROR -Exception $_
    }
}


function Install-Git {
    #C:\Program Files\Git\bin
    #    Silent: /SP- /VERYSILENT /SUPPRESSMSGBOXES /NORESTART
    #    SilentWithProgress: /SP- /SILENT /SUPPRESSMSGBOXES /NORESTART
    #    Log: /LOG="<LOGPATH>"
    #    InstallLocation: /DIR="<INSTALLPATH>"
    Install-WingetPackage -AppName "Git.Git" -WaitForInstaller $true -InstallArgs "/SP- /VERYSILENT /SUPPRESSMSGBOXES /NORESTART /DIR=""C:\Program Files\Git"""
    # $tempPath = [System.Environment]::GetEnvironmentVariable('Path', [System.EnvironmentVariableTarget]::Machine) + ";C:\Program Files\Git\bin"
    # $tempPath = Remove-PathFromSemicolonSeparatedVariable -Variable $tempPath -Path "C:\Program Files\Git\bin"
    # $tempPath = Remove-PathFromSemicolonSeparatedVariable -Variable $tempPath -Path "C:\Program Files\Git\bin"
    # $tempPath = Add-PathToSemicolonSeparatedVariable -Variable $tempPath -Path "C:\Program Files\Git\bin"
    # [System.Environment]::SetEnvironmentVariable('Path', $tempPath, [System.EnvironmentVariableTarget]::Machine)
    # $env:Path = $env:Path + ";C:\Program Files\Git\bin"
    # Remove-Module Infrastructure -ErrorAction SilentlyContinue
    # Write-LogMessage "Git installed and path set" -Level INFO
    # foreach ($path in $tempPath.Split(';')) {
    #     if ($path -ne "") {
    #         Write-LogMessage $path
    #     }
    # }
}
function Get-AllSoftwareConfigs {
    return @()
    $allApps = @()
    $otherAppsPath = Get-WindowsAppsPath  # TODO: FIX FIX FIX
    if (Test-Path $otherAppsPath -PathType Container) {
        foreach ($dir in (Get-ChildItem -Path $otherAppsPath -Directory)) {
            $obj = [PSCustomObject]@{
                Id   = $dir.Name
                Path = $dir.FullName
            }
            Write-LogMessage "Processing $($dir.FullName)" -Level INFO
            $filterlist = @("*setup*.msi", "*setup*.exe", "*setup*.bat", "*setup*.cmd", "*setup*.ps1", "*install*.msi", "*install*.exe", "*install*.bat", "*install*.cmd", "*install*.ps1", "*msi", "*exe", "*bat", "*cmd", "*ps1")
            # look recursively
            Write-LogMessage ('Looking recursively for executables in ' + $dir.FullName + ' with command: Get-ChildItem -Path ' + $dir.FullName + ' -File -Include "*.msi", "*.exe", "*.bat", "*.cmd", "*.ps1" -Recurse') -Level INFO
            foreach ($file in (Get-ChildItem -Path $($dir.FullName) -File -Include "*.msi", "*.exe", "*.bat", "*.cmd", "*.ps1" -Recurse)) {
                if ($filterlist -contains $file.Name) {
                    $obj.Executables += $file.Name 
                    # Add additional subfolders to the $obj.Id, eg if original was "Db2" , add "Db2.DataServer.x86_64" if this is the path it is found in
                    $relativePath = $file.FullName.Substring($dir.FullName.Length + 1)
                    $subfolders = Split-Path $relativePath -Parent
                    if ($subfolders) {
                        $obj.Id = $dir.Name + "." + ($subfolders -replace '\\', '.')
                    }
                    else {
                        $obj.Id = $dir.Name
                    }
                }
            }
            if ($obj.Executables.Count -gt 0) { 
                $allApps += $obj
            }
        }                       
    }
    $wingetPath = Join-Path $(Get-WingetAppsPath)
    if (Test-Path $wingetPath -PathType Container) {
        foreach ($dir in (Get-ChildItem -Path $wingetPath -Directory)) {
            $obj = [PSCustomObject]@{
                Id   = $dir.Name
                Path = $dir.FullName
            }
            foreach ($file in (Get-ChildItem -Path $dir.FullName -File -Include "*.msi", "*.exe", "*.bat", "*.cmd")) {
                $obj.Executables += $file.Name
            }
            $allApps += $obj
        }                
    }
    # debug
    $allApps | Format-Table -AutoSize | Out-String | Write-LogMessage -Level INFO


    # custom setting from Id to add boolean scriptblock to checked if alreday installed, and arguments to install as automatically as possible
    foreach ($app in $allApps) {
        if ($app.Id -eq "Git.Git") {
            $app.IsInstalled = {
                $null = Get-Command git -ErrorAction SilentlyContinue
                return $?   
            }
            $app.Args = "/SP- /VERYSILENT /SUPPRESSMSGBOXES /NORESTART /DIR=""C:\Program Files\Git"""
        }
    }
    
}
function Get-SoftwareConfig {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Id
    )
    return 
    if ($Id -eq "") {
        return @()
    }
    $allApps = Get-AllSoftwareConfigs
    return $allApps | Where-Object { $_.Id -eq $Id }
}






function Test-AllApplications {
    Write-LogMessage "Verifiserer installerte programmer..." -ForegroundColor Cyan
    
    # Initialize log data with retry logic
    $logData = Get-ApplicationLogData
    if ($null -eq $logData) {
        Write-LogMessage "Fortsetter uten loggdata..." -ForegroundColor Yellow
        $computerLogs = @()
    }
    else {
        $computerLogs = if ($logData.ContainsKey($env:COMPUTERNAME)) { 
            $logData[$env:COMPUTERNAME] 
        }
        else { 
            @() 
        }
    }

    # Count number of Success in computerLogs
    $successCount = $computerLogs | Where-Object { $_.Status -eq "Success" } | Measure-Object | Select-Object -ExpandProperty Count
    if ($successCount -lt 3) {
        Write-LogMessage "Sjekker installasjoner..." -ForegroundColor Yellow
    }
    else {
        return
    }
    
    $applications = @(
        @{ Name = "PowerShell 7"; ExeName = "pwsh.exe" }
        @{ Name = "Visual Studio Code"; ExeName = "code.exe" }
        @{ Name = "Visual Studio 2022"; ExeName = "devenv.exe" }
        @{ Name = "Git"; ExeName = "git.exe" }
        @{ Name = "Node.js LTS"; ExeName = "node.exe" }
        @{ Name = "Cursor AI"; ExeName = "cursor.exe" }
        @{ Name = "IBM Data Server Client"; ExeName = "db2.exe" }
        @{ Name = "SQL Server 2022 Developer"; ExeName = "sqlservr.exe" }
        @{ Name = "Azure Data Studio"; ExeName = "azuredatastudio.exe" }
        @{ Name = "SQL Server Management Studio"; ExeName = "ssms.exe" }
        @{ Name = "DBeaver"; ExeName = "dbeaver.exe" }
        @{ Name = "NetExpress"; ExeName = "dswin.exe" }
        @{ Name = "SPF Editor"; ExeName = "spfse.exe" }
        @{ Name = "QMF for Windows"; ExeName = "qmfwin.exe" }
        @{ Name = "IBM ObjectRexx"; ExeName = "rexx.exe" }
        @{ Name = ".NET 8 SDK"; ExeName = "dotnet.exe" }
        @{ Name = "Microsoft Office"; ExeName = "winword.exe" }
        @{ Name = "Notepad++"; ExeName = "notepad++.exe" }
        @{ Name = "Google Chrome"; ExeName = "chrome.exe" }
    )

    $results = @{
        NeedsAttention = @()
        Verified       = @()
    }

    foreach ($app in $applications) {
        Write-LogMessage "Sjekker $($app.Name)..." -NoNewline
        
        # Check installation logs first
        $latestLog = $computerLogs | 
        Where-Object { $_.Application -eq $app.Name } | 
        Sort-Object { [DateTime]::Parse($_.Date) } -Descending | 
        Select-Object -First 1

        if ($latestLog -and $latestLog.Status -eq "Success") {
            Write-LogMessage "Verifisert (logg)" -ForegroundColor Green
            $results.Verified += $app.Name
            continue  # Skip Install-Check if log verification is successful
        }

        # Only perform Install-Check if log verification failed
        $isInstalled = Install-Check -exeName $app.ExeName -AppName $app.Name 
        
        if ($isInstalled) {
            Write-LogMessage "Installert (Oppdatert logg nå)" -ForegroundColor Yellow
            $results.NeedsAttention += @{
                Name        = $app.Name
                Installed   = $true
                LogStatus   = if ($latestLog) { $latestLog.Status } else { "Missing" }
                LastLogDate = if ($latestLog) { $latestLog.Date } else { "Never" }
                Reason      = "Needs logging"
            }
        }
        else {
            Write-LogMessage "Ikke installert" -ForegroundColor Red
            $results.NeedsAttention += @{
                Name        = $app.Name
                Installed   = $false
                LogStatus   = if ($latestLog) { $latestLog.Status } else { "Missing" }
                LastLogDate = if ($latestLog) { $latestLog.Date } else { "Never" }
                Reason      = "Not installed"
            }
        }
    }

    Write-LogMessage "Oppsummering:" -ForegroundColor Cyan
    Write-LogMessage "Verifiserte programmer ($($results.Verified.Count)):" -ForegroundColor Green
    $results.Verified | ForEach-Object { Write-LogMessage "- $($_.Name)" }
    
    if ($results.NeedsAttention.Count -gt 0) {
        Write-LogMessage "Programmer som trenger oppmerksomhet ($($results.NeedsAttention.Count)):" -ForegroundColor Yellow
        foreach ($app in $results.NeedsAttention) {
            Write-LogMessage "- $($app.Name)" -ForegroundColor Yellow
            Write-LogMessage "Status: $($app.Reason)" -ForegroundColor Yellow
            Write-LogMessage "Siste logg: $($app.LogStatus) ($($app.LastLogDate))" -ForegroundColor Yellow
        }
    }

    return $results
}


function New-StandardFolders {
    Write-Host "Oppretter standardmapper..."
    $username = $env:USERNAME.ToLower()
    
    # Create TEMPFK first
    $tempfkPath = "C:\TEMPFK"
    Write-Host "Oppretter $tempfkPath..." -NoNewline
    try {
        Add-Folder -Path $tempfkPath -AdditionalAdmins @("$env:USERDOMAIN\$env:USERNAME")
    }
    catch {
        Write-Host " Mislyktes: $($_.Exception.Message)$(if($_.Exception.InnerException){" $($_.Exception.InnerException.Message)"})" -ForegroundColor Red
    }
    
    # Create user-specific TEMPFK folder
    $userTempPath = "C:\TEMPFK\$username"
    Write-Host "Oppretter $userTempPath..." -NoNewline
    try {
        Add-Folder -Path $userTempPath -AdditionalAdmins @("$env:USERDOMAIN\$env:USERNAME")        
    }
    catch {
        Write-Host " Mislyktes: $($_.Exception.Message)$(if($_.Exception.InnerException){" $($_.Exception.InnerException.Message)"})" -ForegroundColor Red
    }
    
    # Create remaining folders
    $folders = @(
        @{ Path = "$env:OptPath\work"; Desc = "work mappe" },
        @{ Path = "$env:OptPath\data"; Desc = "data mappe" },
        @{ Path = "$env:OptPath\DedgePshApps"; Desc = "apps mappe" },
        @{ Path = "$env:OptPath\install"; Desc = "install mappe" },
        @{ Path = "$env:OptPath\webs"; Desc = "webs mappe" },
        @{ Path = "$env:OptPath\src"; Desc = "src mappe" }
    )

    foreach ($folder in $folders) {
        Write-Host "Oppretter $($folder.Path)..." -NoNewline
        try {   
            Add-Folder -Path $folder.Path -AdditionalAdmins @("$env:USERDOMAIN\$env:USERNAME")
        }
        catch {
            Write-Host " Mislyktes: $($_.Exception.Message)$(if($_.Exception.InnerException){" $($_.Exception.InnerException.Message)"})" -ForegroundColor Red
        }
    }
}

function Clear-NetExpressRegistry {
    Write-Host "Retter opp Dialog System miljøvariabler..." -NoNewline
    try {
        $regPath = "HKLM:\SOFTWARE\Wow6432Node\Micro Focus\NetExpress\5.1\Dialog System\5.1\Environment"
    
        # Create a temporary script to modify registry with elevated permissions
        $tempScript = @"
`$regPath = "$regPath"
if (Test-Path `$regPath) {
    `$currentPath = Get-ItemProperty -Path `$regPath -Name "PATH" | Select-Object -ExpandProperty "PATH"
    `$cleanPath = `$currentPath -replace '"', ''
    Set-ItemProperty -Path `$regPath -Name "PATH" -Value `$cleanPath
}
"@
    
        $scriptPath = Join-Path $env:TEMP "CleanNetExpressRegistry.ps1"
        $tempScript | Out-File -FilePath $scriptPath -Encoding UTF8
    
        # Run the temporary script with elevated permissions
        $process = Start-Process powershell.exe -ArgumentList "-ExecutionPolicy Bypass -File `"$scriptPath`"" -Verb RunAs -Wait -PassThru
    
        if ($process.ExitCode -eq 0) {
            Write-Host " Vellykket!" -ForegroundColor Green
            Write-ApplicationLog -AppName "NetExpress" -Status "Success" -Message "Registry cleaned successfully"
            Write-LogMessage "Endringene vil tre i kraft etter omstart av Windows Explorer" -Level WARN 
            $script:reboot = $true
        }
        else {
            throw "Failed to modify registry (Exit code: $($process.ExitCode))"
        }
    }
    catch {
        Write-Host " Mislyktes: $($_.Exception.Message)$(if($_.Exception.InnerException){" $($_.Exception.InnerException.Message)"})" -ForegroundColor Red
        Write-ApplicationLog -AppName "NetExpress" -Status "Failed" -Message "Failed to clean registry: $_"
    }
    finally {
        # Clean up temporary script
        if (Test-Path $scriptPath) {
            Remove-Item -Path $scriptPath -Force
        }
    }
}

function New-DialogSystemShortcut {
    Write-Host "Oppretter DialogSystem snarvei..." -NoNewline
    try {
        $WshShell = New-Object -ComObject WScript.Shell
        $desktopPath = [Environment]::GetFolderPath("Desktop")
        $shortcutPath = Join-Path $desktopPath "DialogSystem Administrator.lnk"
        $targetPath = "C:\Program Files (x86)\Micro Focus\Net Express 5.1\DIALOGSYSTEM\Bin\DSWIN.exe"

        # Create shortcut
        $shortcut = $WshShell.CreateShortcut($shortcutPath)
        $shortcut.TargetPath = $targetPath
        $shortcut.IconLocation = "$targetPath,0"
        $shortcut.Save()

        # Set shortcut to run as administrator
        $bytes = [System.IO.File]::ReadAllBytes($shortcutPath)
        $bytes[0x15] = $bytes[0x15] -bor 0x20 # Set run as administrator flag
        [System.IO.File]::WriteAllBytes($shortcutPath, $bytes)

        Write-Host " Vellykket!" -ForegroundColor Green
        Write-ApplicationLog -AppName "NetExpress" -Status "Success" -Message "Dialog System Administrator shortcut created successfully"
    }
    catch {
        Write-Host " Mislyktes: $($_.Exception.Message)$(if($_.Exception.InnerException){" $($_.Exception.InnerException.Message)"})" -ForegroundColor Red
        Write-ApplicationLog -AppName "NetExpress" -Status "Failed" -Message "Failed to create Dialog System Administrator shortcut: $_"
    }
    try {
        $WshShell = New-Object -ComObject WScript.Shell
        $desktopPath = [Environment]::GetFolderPath("Desktop")
        $shortcutPath = Join-Path $desktopPath "DialogSystem.lnk"
        $targetPath = "C:\Program Files (x86)\Micro Focus\Net Express 5.1\DIALOGSYSTEM\Bin\DSWIN.exe"

        # Create shortcut
        $shortcut = $WshShell.CreateShortcut($shortcutPath)
        $shortcut.TargetPath = $targetPath
        $shortcut.IconLocation = "$targetPath,0"
        $shortcut.Save()

        # # Set shortcut to run as administrator
        # $bytes = [System.IO.File]::ReadAllBytes($shortcutPath)
        # $bytes[0x15] = $bytes[0x15] -bor 0x20 # Set run as administrator flag
        # [System.IO.File]::WriteAllBytes($shortcutPath, $bytes)

        Write-Host " Vellykket!" -ForegroundColor Green
        Write-ApplicationLog -AppName "NetExpress" -Status "Success" -Message "Dialog System shortcut created successfully"
    }
    catch {
        Write-Host " Mislyktes: $($_.Exception.Message)$(if($_.Exception.InnerException){" $($_.Exception.InnerException.Message)"})" -ForegroundColor Red
        Write-ApplicationLog -AppName "NetExpress" -Status "Failed" -Message "Failed to create Dialog System shortcut: $_"
    }
}

function Install-WithStatus {
    param (
        [string]$AppName,
        [scriptblock]$InstallCommand
    )
    
    Write-Host "Installerer $AppName..." -NoNewline
    try {
        & $InstallCommand | Out-Null
        if ($LASTEXITCODE -eq 0) {
            Write-Host " Vellykket!" -ForegroundColor Green
        } 
        elseif ($LASTEXITCODE -eq -1978335189) {
            Write-Host " Allerede installert" -ForegroundColor Green
        }
        else {
            Write-Host " Mislyktes (Feilkode: $LASTEXITCODE)" -ForegroundColor Red
        }
    }
    catch {
        Write-Host " Mislyktes: $($_.Exception.Message)$(if($_.Exception.InnerException){" $($_.Exception.InnerException.Message)"})" -ForegroundColor Red
    }
}

function Restart-ComputerWithPrompt {
    Write-Host "Omstart av datamaskinen..." -NoNewline
    try {
        $title = "Bekreft omstart"
        $message = "Er du sikker på at du vil starte datamaskinen på nytt nå?`n`nLagre alt arbeid før du fortsetter."
        $yes = New-Object System.Management.Automation.Host.ChoiceDescription "&Ja", "Starter datamaskinen på nytt nå."
        $no = New-Object System.Management.Automation.Host.ChoiceDescription "&Nei", "Avbryter omstart."
        $options = [System.Management.Automation.Host.ChoiceDescription[]]($yes, $no)
        
        $result = $host.UI.PromptForChoice($title, $message, $options, 1)
        
        if ($result -eq 0) {
            Write-Host " Starter på nytt..." -ForegroundColor Yellow
            Write-ApplicationLog -AppName "System" -Status "Progress" -Message "User initiated system restart"
            
            # Add a slight delay to allow the log to be written
            Start-Sleep -Seconds 2
            
            # Restart the computer
            Restart-Computer -Force
        }
        else {
            Write-Host " Avbrutt" -ForegroundColor Yellow
            Write-ApplicationLog -AppName "System" -Status "Warning" -Message "System restart cancelled by user"
        }
    }
    catch {
        Write-Host " Mislyktes: $($_.Exception.Message)$(if($_.Exception.InnerException){" $($_.Exception.InnerException.Message)"})" -ForegroundColor Red
        Write-ApplicationLog -AppName "System" -Status "Failed" -Message "Failed to initiate system restart: $_"
    }
}
# $scriptBlock = {
#     param($Message, $Title, $Timeout, $Style)
#     Add-Type -AssemblyName System.Windows.Forms
#     [System.Windows.Forms.MessageBox]::Show($Message, $Title, [System.Windows.Forms.MessageBoxButtons]::OK, $Style)
# }



function Remove-TempFiles {
    Write-Host "Sletter midlertidige filer..." -NoNewline
    try {
        $tempPath = "C:\TEMPFK\TempInstallFiles"
        if (Test-Path -Path $tempPath) {
            # Get list of files and folders before deletion
            $items = Get-ChildItem -Path $tempPath -Recurse
            
            # Save log files to user profile before deletion
            if (Test-Path $tempLogPath) {
                Copy-Item -Path $tempLogPath -Destination $userLogPath -Force
            }
            
            # Delete everything except the base directory
            Get-ChildItem -Path $tempPath -Recurse | Remove-Item -Force -Recurse
            
            $itemCount = ($items | Measure-Object).Count
            Write-Host " Vellykket! ($itemCount filer/mapper slettet)" -ForegroundColor Green
            Write-ApplicationLog -AppName "System" -Status "Success" -Message "Temporary files cleaned up: $itemCount items deleted"
        }
        else {
            Write-Host " Ingen filer å slette" -ForegroundColor Yellow
        }
    }
    catch {
        Write-Host " Mislyktes: $($_.Exception.Message)$(if($_.Exception.InnerException){" $($_.Exception.InnerException.Message)"})" -ForegroundColor Red
        Write-ApplicationLog -AppName "System" -Status "Failed" -Message "Failed to clean up temporary files: $_"
    }
}

function Backup-RegistryKey {
    param (
        [Parameter(Mandatory = $true)]
        [string]$RegistryPath,
        [string]$BackupRoot = "C:\opt\src\DedgeSrc\DedgeSystemTools\Folders\DedgeCommon\Software\FkAppConfig\DataStore"
    )

    try {
        # 1. Create necessary folders
        $machineName = $env:COMPUTERNAME.ToLower()
        $userFolder = $env:USERNAME
        $backupFolder = Join-Path $BackupRoot $machineName | Join-Path -ChildPath $userFolder | Join-Path -ChildPath "RegBackup"
        
        if (-not (Test-Path -Path $backupFolder -PathType Container)) {
            New-Item -Path $backupFolder -ItemType Directory -Force | Out-Null
        }

        # 2.1 Build reg key filename
        # Convert full registry path to a filename-safe string
        $timestamp = Get-Date -Format "yyyyMMdd-HHmmss"
        $regKeyName = $RegistryPath -replace "^[A-Z]+:\\", "" # Remove drive part (HKLM:\, HKCU:\, etc.)
        
        # 2.2 Replace illegal chars and clean up double hyphens
        $illegalChars = '[\\/:*?"<>|]'
        $regKeyName = $regKeyName -replace $illegalChars, "-"
        $regKeyName = $regKeyName -replace " ", "-"        
        # Clean up multiple hyphens (loop until no more double hyphens exist)
        do {
            $regKeyName = $regKeyName -replace "--", "-"
        } while ($regKeyName -match "--")
        
        # Trim hyphens from start and end
        $regKeyName = $regKeyName.Trim("-")
        
        # Create final filename
        $backupFile = Join-Path $backupFolder "$regKeyName`_$timestamp.reg"

        #check if the registry key exists
        if (-not (Test-Path -Path $RegistryPath -PathType Container)) {
            Write-Host "Registry key does not exist: $RegistryPath. Nothing to backup." -ForegroundColor Green
            return $null
        }

        # Export the registry key
        $process = Start-Process "reg.exe" -ArgumentList "export", "`"$RegistryPath`"", "`"$backupFile`"", "/y" -NoNewWindow -Wait -PassThru

        if ($process.ExitCode -eq 0) {
            Write-Host "Registry backup created: $backupFile" -ForegroundColor Green
            return $backupFile
        }
        else {
            throw "Failed to export registry key. Exit code: $($process.ExitCode)"
        }
    }
    catch {
        Write-Host "Failed to backup registry key: $($_.Exception.Message)$(if($_.Exception.InnerException){" $($_.Exception.InnerException.Message)"})" -ForegroundColor Red
        Write-ErrorLog -Source "Registry Backup" -Message "Failed to backup registry key $RegistryPath" -ErrorDetails $_
        return $null
    }
}
function Find-Executable {
    param (
        [string]$exeName,
        [bool]$reportAllFindsToConsole = $false
    )
    $exeNameBaseName = $exeName.ToLower().Trim()
    if ($exeNameBaseName -eq "") {
        return $null
    }
    if ($exeName.Contains(".")) {
        $exeSplit = $exeName.Split(".")
        $exeNameBaseName = $exeSplit[0].ToLower().Trim()
    }
    
    # search for $exeName in registry paths that contain user programs or machine wide programs
    $result = [System.Collections.ArrayList]@()
    
    # Registry paths to search
    $registryPaths = @(
        "HKCU:\Software\Microsoft\Windows\CurrentVersion\Uninstall",
        "HKCU:\Software\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall",
        "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall",
        "HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall"
    )
    # DisplayIcon
    foreach ($path in $registryPaths) {
        if (Test-Path $path) {
            Get-ChildItem -Path $path -ErrorAction SilentlyContinue | ForEach-Object {
                $key = $_
                try {
                    # chekc if there are a property called DisplayIcon
                    if ($key.Property.Contains("DisplayIcon")) {
                        $displayIcon = Get-ItemPropertyValue -Path $key.PSPath -Name "DisplayIcon" -ErrorAction SilentlyContinue
                        $displayIcon = $displayIcon.ToString().ToLower()
                        $foundExePath = $displayIcon
                        $foundExePathLower = $displayIcon.ToString().ToLower()

                        $pos = $foundExePathLower.IndexOf($exeNameBaseName.ToLower())
                        if ($pos -gt 0 -and $foundExePathLower.Contains(".exe")) {  
                            $pos2 = $foundExePathLower.IndexOf(".exe")
                            $foundExePathLower = $foundExePathLower.Substring(0, ($pos2 + 4))
                            $foundExePath = $foundExePath.Substring(0, ($pos2 + 4)) 
                            $result.Add([PSCustomObject]@{
                                    Type = "Registry"
                                    Path = $foundExePath
                                }) | Out-Null
                        }
                    }
                }
                catch {
                    # Silently continue if property doesn't exist
                }
            }
        }
    }
    
    # If none  found check disk paths for exeName
    #if ($result.Count -eq 0) {
    #    }
    $diskPaths = @(
        "C:\Program Files",
        "C:\Program Files (x86)",
        "C:\SPFSE",
        "$env:OptPath\Programs"
    )
    foreach ($path in $diskPaths) {
        # Check if path exists
        if (Test-Path -Path "$path" -PathType Container) {
            if ($exeName.ToLower().Contains(".exe")) {
                $potentialExePath = Get-ChildItem -Path "$path" -Filter $exeName -Recurse -ErrorAction SilentlyContinue
            }
            else {
                $potentialExePath = Get-ChildItem -Path "$path" -Filter "$($exeName + "*.exe")"  -Recurse -ErrorAction SilentlyContinue
            }
            foreach ($item in $potentialExePath) {  
                if ($item.PSIsContainer) {
                    continue
                }
                if ($item.Name.ToLower().Contains($exeNameBaseName.ToLower())) {
                    $result.Add([PSCustomObject]@{
                            Type = "Disk"
                            Path = $item.FullName
                        }) | Out-Null
                }
            }
        }
    }

    if ($reportAllFindsToConsole -and $result.Count -gt 0) {
        Write-Host ""
        Write-Host "Funnet følgende installasjoner av $exeName på denne maskinen:" -ForegroundColor Green
        Write-Host "-".PadRight(110, '-') -ForegroundColor Green
        Write-Host $("Type".PadRight(10) + "|" + "Sti".PadRight(100)) -ForegroundColor Yellow
        Write-Host "-".PadRight(110, '-') -ForegroundColor Green
        foreach ($item in $result) {
            Write-Host $($($item.Type).PadRight(10) + "|" + $($item.Path)) -ForegroundColor Green
        }
        Write-Host "-".PadRight(110, '-') -ForegroundColor Green
        Write-Host ""
    }
    return $result
}


function Install-Check {
    param (
        [string]$exeName,
        [string]$appName
    )
    $test = Find-Executable -exeName $exeName -reportAllFindsToConsole $true
    if ($test.Count -gt 0) {
        Write-Host " Allerede installert" -ForegroundColor Green
        Write-ApplicationLog -AppName $appName -Status "Success" -Message "Application already installed"
    }
    
    if ($test.Count -gt 0) {
        return $true
    }
    return $false
}
# create function to search for exe in registry, and return the current exe path

function Open-RegBackupFolder {
    Write-Host "Åpner RegBackup mappe..." -NoNewline
    try {
        # Build the RegBackup path
        $backupRoot = "C:\opt\src\DedgeSrc\DedgeSystemTools\Folders\DedgeCommon\Logs\InstallationData"
        $machineName = $env:COMPUTERNAME.ToLower()
        $userFolder = $env:USERNAME
        $backupFolder = Join-Path $backupRoot $machineName | Join-Path -ChildPath $userFolder | Join-Path -ChildPath "RegBackup"
        
        if (-not (Test-Path -Path $backupFolder -PathType Container)) {
            New-Item -Path $backupFolder -ItemType Directory -Force | Out-Null
        }

        # Open the folder in Explorer
        Start-Process "explorer.exe" -ArgumentList $backupFolder
        Write-Host " Vellykket!" -ForegroundColor Green
    }
    catch {
        Write-Host " Mislyktes: ${_}" -ForegroundColor Red
        Write-ErrorLog -Source "RegBackup" -Message "Failed to open RegBackup folder" -ErrorDetails ${_}
    }
}

function Start-InstallProcess {
    param(
        [Parameter(Mandatory = $true)]
        [string]$AppName,
        [Parameter(Mandatory = $false)]
        [string]$InstallerPath = "",
        [Parameter(Mandatory = $false)]
        [string]$InstallArgs = "",
        [Parameter(Mandatory = $false)]
        [string]$CustomConfigFunction = ""
    )

    Write-LogMessage "Starting install process for $AppName with parameters: `nInstallerPath: $InstallerPath`nInstallArgs: $InstallArgs`nCustomConfigFunction: $CustomConfigFunction" -Level INFO
    try {
        if ([string]::IsNullOrEmpty($InstallerPath) -and [string]::IsNullOrEmpty($CustomConfigFunction)) {
            Write-LogMessage "No installer path or custom config function provided" -Level ERROR
            # Start explorer.exe in the current directory
            return $false
        }

        Write-ApplicationLog -AppName $AppName -Status "Started" -Message "Installation started"
        try {    
            if (-not ([string]::IsNullOrEmpty($InstallerPath))) {
                $isMsi = [System.IO.Path]::GetExtension($InstallerPath).ToLower() -eq ".msi"

                if ($isMsi) {
                    $msiArgs = "/i `"$InstallerPath`" /qn /norestart"
                    if (-not ([string]::IsNullOrEmpty($InstallArgs))) {
                        $msiArgs += " $InstallArgs"
                    }
                    Write-LogMessage "Starting $AppName via msiexec: msiexec.exe $msiArgs" -Level INFO
                    $result = Start-Process -FilePath "msiexec.exe" -ArgumentList $msiArgs -Verb RunAs -Wait -PassThru
                    if ($result.ExitCode -ne 0) {
                        Write-LogMessage "msiexec returned exit code: $($result.ExitCode) for $AppName" -Level ERROR
                        return $false
                    }
                }
                elseif (-not ([string]::IsNullOrEmpty($InstallArgs))) {
                    Write-LogMessage "Starting $AppName with installer path and arguments: $InstallerPath $InstallArgs" -Level INFO
                    $result = Start-Process -FilePath $InstallerPath -ArgumentList $InstallArgs -Verb RunAs -Wait -PassThru
                    if ($result.ExitCode -ne 0) {
                        Write-LogMessage "Installer returned exit code: $($result.ExitCode) for $AppName" -Level ERROR
                        return $false
                    }
                }
                else {
                    Write-LogMessage "Starting $AppName with installer path: $InstallerPath" -Level INFO
                    $result = Start-Process -FilePath $InstallerPath -Verb RunAs -Wait -PassThru
                    if ($result.ExitCode -ne 0) {
                        Write-LogMessage "Installer returned exit code: $($result.ExitCode) for $AppName" -Level ERROR
                        return $false
                    }
                }
            }
        }
        catch {
            try {
                Write-ApplicationLog -AppName $AppName -Status "Restarting" -Message "Primary installation method failed. Restarting using secondary method..."
                if ($isMsi) {
                    $msiArgs = "/i `"$InstallerPath`" /qn /norestart"
                    if (-not ([string]::IsNullOrEmpty($InstallArgs))) {
                        $msiArgs += " $InstallArgs"
                    }
                    & msiexec.exe $msiArgs.Split(' ')
                }
                else {
                    & $InstallerPath $InstallArgs
                }
                if ($LASTEXITCODE -ne 0) {
                    Write-LogMessage "Installer returned exit code: $LASTEXITCODE for $AppName" -Level ERROR
                    return $false
                }
            }
            catch {
                Write-LogMessage "Failed to restart installer for $AppName" -Level ERROR -Exception $_
                Write-ApplicationLog -AppName $AppName -Status "Failed" -Message "Installation failed"
                return $false
            }
        }

        Write-ApplicationLog -AppName $AppName -Status "Completed" -Message "Installation completed"
        if (-not ([string]::IsNullOrEmpty($CustomConfigFunction))) {
            Write-ApplicationLog -AppName $AppName -Status "Started" -Message "Configuration started"
            Write-LogMessage "Starting $AppName with custom config function: $CustomConfigFunction" -Level INFO
            try {
                & $CustomConfigFunction
                Write-ApplicationLog -AppName $AppName -Status "Completed" -Message "Configuration completed"
                Write-LogMessage "Configuration completed" -Level INFO
            }
            catch {
                Write-ApplicationLog -AppName $AppName -Status "Failed" -Message "Configuration failed"
                Write-LogMessage "Configuration failed" -Level ERROR -Exception $_
            }
        }
        return $true
    }
    catch {
        Write-LogMessage "Failed to install ${AppName}" -Level ERROR -Exception $_
        Write-ApplicationLog -AppName $AppName -Status "Failed" -Message "Installation failed"
        return $false
    }
}


function Set-GitUserIdentity {
    $orgUrl = "https://dev.azure.com/Dedge"
    Write-Host "Azure DevOps organization URL: $orgUrl" -ForegroundColor Green
    $fullName = Read-Host "Enter your full name (for Git commits)"
    $email = Read-Host "Enter your email address (should match Azure DevOps account)"

    # Configure Git user identity
    Write-Host "Configuring Git user identity..." -ForegroundColor Green
    $gitPath = "C:\Program Files\Git\bin\git.exe"
    if (-not (Test-Path -Path $gitPath -PathType Leaf)) {
        Write-Host "Git is not installed" -ForegroundColor Red
        return
    }
   
    # Configure Git user identity
    Write-Host "Configuring Git user identity..." -ForegroundColor Green
    
    & $gitPath config --global user.name "$fullName"
    & $gitPath config --global user.email "$email"
    # Configure Git credential helper for Azure DevOps
    & $gitPath config --global credential.helper manager-core

    # Configure default branch name
    & $gitPath config --global init.defaultBranch main

    # Configure line endings for Windows
    & $gitPath config --global core.autocrlf true

    Write-LogMessage "Git configuration complete for $fullName" -Level INFO
}

function Set-DB2ClientConfig {
    param(
        [string]$Version = "x86"
    )
    Write-LogMessage "Konfigurerer DB2 Client..." -NoNewline
    try {
    
        # Add DB2 paths to PATH for both User and Machine
        Write-LogMessage "Legger til DB2 i PATH..." -NoNewline
        if ($Version -eq "x86") {
            $db2Path = "C:\Program Files (x86)\IBM\SQLLIB"
        }
        else {
            $db2Path = "C:\Program Files\IBM\SQLLIB"
        }
        $clidriverPath = "$db2Path\clidriver"
        # $db2CliPath = "$db2Path\BIN\db2cli.exe"

        $db2Paths = @(
            "$db2Path\BIN",
            "$db2Path\FUNCTION"
        )
        # "$clidriverPath",
        # "$db2Path\INCLUDE",
        # "$db2Path\LIB",

        # Update PATH for User
        $currentPath = [Environment]::GetEnvironmentVariable("Path", "User")
        $pathsToAdd = $db2Paths | Where-Object { $currentPath -notlike "*$_*" }
        
        if ($pathsToAdd.Count -gt 0) {
            $newPath = ($currentPath.Split(';') + $pathsToAdd | Select-Object -Unique) -join ';'
            [Environment]::SetEnvironmentVariable("Path", $newPath, "User")
        }

        # Set DB2 environment variables for User
        
        $db2Vars = @{
            "DB2CLP"      = "DB20FADE"
            "DB2INSTANCE" = "DB2"
            "DB2PATH"     = $db2Path
            # "DB2HOME"     = "$db2Path\BIN"
            "IBM_DB_HOME" = $clidriverPath
        }

        foreach ($var in $db2Vars.GetEnumerator()) {
            [Environment]::SetEnvironmentVariable($var.Key, $var.Value, "User")
            Write-LogMessage "Vellykket (User)! $($var.Key) = $($var.Value)" -ForegroundColor Green
            Write-ApplicationLog -AppName "IBM Data Server Client" -Status "Progress" -Message "Environment variables set successfully for User"
        }

        
        Start-OurPshApp -AppName "Db2-AutoCatalog\Db2-AutoCatalog"
    }
    catch {
        Write-LogMessage "Mislyktes: $($_.Exception.Message)$(if($_.Exception.InnerException){" $($_.Exception.InnerException.Message)"})" -Level ERROR -Exception $_
        Write-ApplicationLog -AppName "IBM Data Server Client" -Status "Failed" -Message "Configuration failed: $($_.Exception.Message)$(if($_.Exception.InnerException){" $($_.Exception.InnerException.Message)"})"
    }
}

function Set-PwshEnvironment {
    Write-LogMessage "Konfigurerer PowerShell 7 kontekstmeny..." -NoNewline
    try {
        # Backup registry keys before modification
        $keysToBackup = @(
            "HKCU\SOFTWARE\Classes\Directory\Background\shell\PowerShell7",
            "HKCU\SOFTWARE\Classes\Directory\Background\shell\PowerShell7\command"
        )

        foreach ($key in $keysToBackup) {
            Backup-RegistryKey -RegistryPath $key
        }

        # Create registry keys for PowerShell 7 context menu
        $pwshPath = "C:\Program Files\PowerShell\7\pwsh.exe"
        
        # Create the shell command key
        $shellKey = "HKCU:\SOFTWARE\Classes\Directory\Background\shell\PowerShell7"
        $commandKey = "$shellKey\command"
        
        if (-not (Test-Path $shellKey)) {
            New-Item -Path $shellKey -Force | Out-Null
        }
        if (-not (Test-Path $commandKey)) {
            New-Item -Path $commandKey -Force | Out-Null
        }
        
        # Set the display name and icon
        Set-ItemProperty -Path $shellKey -Name "(Default)" -Value "Open with PowerShell &7" -Force
        Set-ItemProperty -Path $commandKey -Name "(Default)" -Value "`"$pwshPath`" -NoExit -Command Set-Location -LiteralPath `"%V`"" -Force 
        Set-ItemProperty -Path $shellKey -Name "Icon" -Value "$pwshPath" -Type String -Force

        Write-LogMessage "Vellykket!" -ForegroundColor Green
        Write-ApplicationLog -AppName "Environment Setup" -Status "Success" -Message "PowerShell 7 context menu configured"
    }
    catch {
        Write-LogMessage "Mislyktes: $($_.Exception.Message)$(if($_.Exception.InnerException){" $($_.Exception.InnerException.Message)"})" -Level ERROR -Exception $_
        Write-ApplicationLog -AppName "Environment Setup" -Status "Failed" -Message "Failed to configure PowerShell 7 context menu: $($_.Exception.Message)$(if($_.Exception.InnerException){" $($_.Exception.InnerException.Message)"})"
    }
}

function Set-PwshEnvironmentRunAsAdmin {
    Write-LogMessage "Konfigurerer PowerShell 7 kontekstmeny som administrator..." -NoNewline
    try {
        # Backup registry keys before modification
        $keysToBackup = @(
            "HKCU\SOFTWARE\Classes\Directory\Background\shell\PowerShell7Admin",
            "HKCU\SOFTWARE\Classes\Directory\Background\shell\PowerShell7Admin\command"
        )

        foreach ($key in $keysToBackup) {
            Backup-RegistryKey -RegistryPath $key
        }

        # Create registry keys for PowerShell 7 admin context menu
        $pwshPath = "C:\Program Files\PowerShell\7\pwsh.exe"
        
        # Create the shell command key
        $shellKey = "HKCU:\SOFTWARE\Classes\Directory\Background\shell\PowerShell7Admin"
        $commandKey = "$shellKey\command"
        
        if (-not (Test-Path $shellKey)) {
            New-Item -Path $shellKey -Force | Out-Null
        }
        if (-not (Test-Path $commandKey)) {
            New-Item -Path $commandKey -Force | Out-Null
        }
        
        # Set the display name and icon
        Set-ItemProperty -Path $shellKey -Name "(Default)" -Value "Open with PowerShell 7 (&Admin)" -Force
        Set-ItemProperty -Path $commandKey -Name "(Default)" -Value "`"$pwshPath`" -NoExit -Command Set-Location -LiteralPath `"%V`" -Verb RunAs" -Force 
        Set-ItemProperty -Path $shellKey -Name "Icon" -Value "$pwshPath" -Type String -Force
        Set-ItemProperty -Path $shellKey -Name "HasLUAShield" -Value "" -Type String -Force

        Write-LogMessage "Vellykket!" -ForegroundColor Green
        Write-ApplicationLog -AppName "Environment Setup" -Status "Success" -Message "PowerShell 7 admin context menu configured"
        
        Write-LogMessage "Endringene vil tre i kraft etter omstart av Windows Explorer" -Level WARN
        $script:reboot = $true
    }
    catch {
        Write-LogMessage "Mislyktes: $($_.Exception.Message)$(if($_.Exception.InnerException){" $($_.Exception.InnerException.Message)"})" -Level ERROR -Exception $_
        Write-ApplicationLog -AppName "Environment Setup" -Status "Failed" -Message "Failed to configure PowerShell 7 admin context menu: $($_.Exception.Message)$(if($_.Exception.InnerException){" $($_.Exception.InnerException.Message)"})"
    }
}

# function Set-ConfigVSCode {
#     Write-LogMessage "Konfigurerer VS Code miljø..." -NoNewline
#     try {
#         Set-UserEnvironment
#         Write-LogMessage "Vellykket!" -ForegroundColor Green
#         Write-ApplicationLog -AppName "Visual Studio Code" -Status "Success" -Message "Environment configuration completed successfully"
#     }
#     catch {
#         Write-LogMessage "Mislyktes: $($_.Exception.Message)$(if($_.Exception.InnerException){" $($_.Exception.InnerException.Message)"})" -Level ERROR -Exception $_
#         Write-ApplicationLog -AppName "Visual Studio Code" -Status "Failed" -Message "Environment configuration failed: $($_.Exception.Message)$(if($_.Exception.InnerException){" $($_.Exception.InnerException.Message)"})"
#     }
# }

function SetCursorConfig {
    Write-LogMessage "Configuring Cursor context menu... This may take a while..." -NoNewline
    try {
        # Backup registry keys before modification
        $keysToBackup = @(
            "HKCU\SOFTWARE\Classes\Directory\Background\shell\cursor",
            "HKCU\SOFTWARE\Classes\Directory\Background\shell\cursor\command",
            "HKCU\SOFTWARE\Classes\Directory\Background\shell\cursor (Admin)",
            "HKCU\SOFTWARE\Classes\Directory\Background\shell\cursor (Admin)\command",
            "HKCU\SOFTWARE\Classes\Directory\shell\cursor",
            "HKCU\SOFTWARE\Classes\Directory\shell\cursor\command",
            "HKCU\SOFTWARE\Classes\Directory\shell\cursor (Admin)",
            "HKCU\SOFTWARE\Classes\Directory\shell\cursor (Admin)\command",
            "HKCU\SOFTWARE\Classes\*\shell\Open with Cursor",
            "HKCU\SOFTWARE\Classes\*\shell\Open with Cursor\command",
            "HKCU\SOFTWARE\Classes\*\shell\Open with Cursor (Admin)",
            "HKCU\SOFTWARE\Classes\*\shell\Open with Cursor (Admin)\command",
            "HKCU\SOFTWARE\Classes\*\shell\Edit with Cursor (Admin)",
            "HKCU\SOFTWARE\Classes\*\shell\Edit with Cursor (Admin)\command"
        )

        foreach ($key in $keysToBackup) {
            Backup-RegistryKey -RegistryPath $key
        }

        # Find Cursor executable path
        $cursorPath = Get-ChildItem -Path "$env:LOCALAPPDATA\Programs" -Filter "cursor.exe" -Recurse | 
        Select-Object -ExpandProperty FullName -First 1
        
        if (-not $cursorPath) {
            Write-LogMessage "Mislyktes: Cursor ikke funnet" -Level ERROR
            Write-ApplicationLog -AppName "Cursor" -Status "Failed" -Message "Cursor executable not found"
            return
        }
        # Clean up existing entries to avoid duplicates
        $keysToRemove = @(
            "HKCU:\SOFTWARE\Classes\Directory\Background\shell\cursor (Admin)",
            "HKCU:\SOFTWARE\Classes\Directory\shell\cursor (Admin)", 
            "HKCU:\SOFTWARE\Classes\Directory\shell\CursorAdmin",
            "HKCU:\SOFTWARE\Classes\*\shell\Open with Cursor (Admin)",
            "HKCU:\SOFTWARE\Classes\*\shell\Edit with Cursor (Admin)"
        )

        foreach ($key in $keysToRemove) {
            if (Test-Path $key) {
                Remove-Item -Path $key -Force -Recurse
            }
        }

        # Create registry content
        $regContent = @"
Windows Registry Editor Version 5.00

; Open files

[HKEY_CURRENT_USER\Software\Classes\*\shell\Open with Cursor (Admin)]
@="Edit with Cursor (Admin)"
"Icon"="$($cursorPath.Replace('\', '\\')),0"
"HasLUAShield"=""
[HKEY_CURRENT_USER\Software\Classes\*\shell\Open with Cursor (Admin)\command]
@="powershell -WindowStyle Hidden -Command \"Start-Process '$($cursorPath.Replace('\', '\\'))' -ArgumentList '%1' -Verb RunAs\""


[HKEY_CURRENT_USER\Software\Classes\Directory\shell\cursor (Admin)]
@="Open Folder as Cursor Project (Admin)"
"Icon"="$($cursorPath.Replace('\', '\\')),0"
"HasLUAShield"=""
[HKEY_CURRENT_USER\Software\Classes\Directory\shell\cursor (Admin)\command]
@="powershell -WindowStyle Hidden -Command \"Start-Process '$($cursorPath.Replace('\', '\\'))' -ArgumentList '%V' -Verb RunAs\""


[HKEY_CURRENT_USER\Software\Classes\Directory\Background\shell\cursor (Admin)]
@="Open Folder as Cursor Project (Admin)"
"Icon"="$($cursorPath.Replace('\', '\\')),0"
"HasLUAShield"=""
[HKEY_CURRENT_USER\Software\Classes\Directory\Background\shell\cursor (Admin)\command]
@="powershell -WindowStyle Hidden -Command \"Start-Process '$($cursorPath.Replace('\', '\\'))' -ArgumentList '%V' -Verb RunAs\""
"@

        # Apply registry changes using .reg file
        $regFilePath = Join-Path $env:TEMP "cursor_context_menu.reg"
        $backupPath = Join-Path $env:TEMP "cursor_backup.reg"
        
        Set-Content -Path $regFilePath -Value $regContent -Encoding Unicode
        Set-Content -Path $backupPath -Value $regContent -Encoding Unicode
        
        # Import registry file
        $process = Start-Process -FilePath "regedit.exe" -ArgumentList "/s", "`"$regFilePath`"" -PassThru -Wait
        
        if ($process.ExitCode -ne 0) {
            throw "Failed to import registry file (Exit code: $($process.ExitCode))"
        }
        
        # Clean up temporary file
        Remove-Item $regFilePath -Force -ErrorAction SilentlyContinue

        # Restart Explorer to apply changes
        Get-Process -Name explorer -ErrorAction SilentlyContinue | Stop-Process -Force

        Write-LogMessage "Vellykket!" -ForegroundColor Green
        Write-ApplicationLog -AppName "System Configuration" -Status "Success" -Message "Cursor configuration completed successfully"
        Write-LogMessage "Endringene vil tre i kraft etter omstart av Windows Explorer" -Level WARN
        $script:reboot = $true
        
        <# 
        # OLD IMPLEMENTATION - KEPT FOR REFERENCE
        $cursorPath = ""
        try {
            #Default Open w&ith C&ursor
            #Icon C:\Users\fkgeista\AppData\Local\Programs\cursor\Cursor.exe
            #command\default "C:\Users\fkgeista\AppData\Local\Programs\cursor\Cursor.exe" "%V"
            #Find Cursor executable path
            $cursorPath = Get-ChildItem -Path "$env:LOCALAPPDATA\Programs" -Filter "cursor.exe" -Recurse | Select-Object -ExpandProperty FullName -First 1
          

            # # Create registry keys for file context menu
            # $fileShellKey = "HKCU:\SOFTWARE\Classes\*\shell\cursor"
            # $fileCommandKey = "$fileShellKey\command"
            # $fileAdminShellKey = "HKCU:\SOFTWARE\Classes\*\shell\cursor (Admin)" 
            # $fileAdminCommandKey = "$fileAdminShellKey\command"

            # Create registry keys for directory context menu
            $dirShellKey = "HKCU:\SOFTWARE\Classes\Directory\shell\cursor"
            $dirCommandKey = "$dirShellKey\command"
            $dirAdminShellKey = "HKCU:\SOFTWARE\Classes\Directory\shell\cursor (Admin)"
            $dirAdminCommandKey = "$dirAdminShellKey\command"

            # Create registry keys for directory background context menu
            $dirBgShellKey = "HKCU:\SOFTWARE\Classes\Directory\Background\shell\cursor"
            $dirBgCommandKey = "$dirBgShellKey\command"
            $dirBgAdminShellKey = "HKCU:\SOFTWARE\Classes\Directory\Background\shell\cursor (Admin)"
            $dirBgAdminCommandKey = "$dirBgAdminShellKey\command"

            # Remove existing keys
            $keys = @($fileShellKey, $fileAdminShellKey, $dirShellKey, $dirAdminShellKey, $dirBgShellKey, $dirBgAdminShellKey)
            # foreach ($key in $keys) {
            #     if (Test-Path $key) {
            #         Remove-Item -Path $key -Force -Recurse
            #     }
            # Create new keys
            foreach ($key in $keys) {
                New-Item -Path $key -Force | Out-Null
                New-Item -Path "$key\command" -Force | Out-Null
            }

            # Configure file context menu
            Set-ItemProperty -Path $fileShellKey -Name "(Default)" -Value "Edit with Cursor" -Force
            Set-ItemProperty -Path $fileShellKey -Name "Icon" -Value "$cursorPath,0" -Force
            Set-ItemProperty -Path $fileCommandKey -Name "(Default)" -Value "`"$cursorPath`" `"%1`"" -Force

            Set-ItemProperty -Path $fileAdminShellKey -Name "(Default)" -Value "Edit with Cursor (Admin)" -Force
            Set-ItemProperty -Path $fileAdminShellKey -Name "Icon" -Value "$cursorPath,0" -Force
            Set-ItemProperty -Path $fileAdminShellKey -Name "HasLUAShield" -Value "" -Force
            Set-ItemProperty -Path $fileAdminCommandKey -Name "(Default)" -Value "powershell -WindowStyle Hidden -Command `"Start-Process '$cursorPath' -ArgumentList '%1' -Verb RunAs`"" -Force

            # Configure directory context menu
            Set-ItemProperty -Path $dirShellKey -Name "(Default)" -Value "Open Folder as Cursor Project" -Force
            Set-ItemProperty -Path $dirShellKey -Name "Icon" -Value "$cursorPath,0" -Force
            Set-ItemProperty -Path $dirCommandKey -Name "(Default)" -Value "`"$cursorPath`" `"%1`"" -Force

            Set-ItemProperty -Path $dirAdminShellKey -Name "(Default)" -Value "Open Folder as Cursor Project (Admin)" -Force
            Set-ItemProperty -Path $dirAdminShellKey -Name "Icon" -Value "$cursorPath,0" -Force
            Set-ItemProperty -Path $dirAdminShellKey -Name "HasLUAShield" -Value "" -Force
            Set-ItemProperty -Path $dirAdminCommandKey -Name "(Default)" -Value "powershell -WindowStyle Hidden -Command `"Start-Process '$cursorPath' -ArgumentList '%1' -Verb RunAs`"" -Force

            # Configure directory background context menu
            Set-ItemProperty -Path $dirBgShellKey -Name "(Default)" -Value "Open Folder as Cursor Project" -Force
            Set-ItemProperty -Path $dirBgShellKey -Name "Icon" -Value "$cursorPath,0" -Force
            Set-ItemProperty -Path $dirBgCommandKey -Name "(Default)" -Value "`"$cursorPath`" `"%V`"" -Force

            Set-ItemProperty -Path $dirBgAdminShellKey -Name "(Default)" -Value "Open Folder as Cursor Project (Admin)" -Force
            Set-ItemProperty -Path $dirBgAdminShellKey -Name "Icon" -Value "$cursorPath,0" -Force
            Set-ItemProperty -Path $dirBgAdminShellKey -Name "HasLUAShield" -Value "" -Force
            Set-ItemProperty -Path $dirBgAdminCommandKey -Name "(Default)" -Value "powershell -WindowStyle Hidden -Command `"Start-Process '$cursorPath' -ArgumentList '%V' -Verb RunAs`"" -Force

            Get-Process -Name explorer -ErrorAction SilentlyContinue | Stop-Process -Force
        }
        catch {
            Write-LogMessage "Mislyktes: $($_.Exception.Message)$(if($_.Exception.InnerException){" $($_.Exception.InnerException.Message)"})" -Level ERROR -Exception $_
            Write-ApplicationLog -AppName "Cursor" -Status "Failed" -Message $("Failed to locate Cursor: " + $_.Exception.Message + $(if ($_.Exception.InnerException) { " $($_.Exception.InnerException.Message)" }))
            return $null
        }

        try {
            # Backup registry keys before modification
            $keysToBackup = @(
                "HKCU\SOFTWARE\Classes\Directory\Background\shell\Cursor",
                "HKCU\SOFTWARE\Classes\Directory\Background\shell\Cursor\command",
                "HKCU\SOFTWARE\Classes\Directory\shell\Cursor",
                "HKCU\SOFTWARE\Classes\Directory\shell\Cursor\command",
                "HKCU\SOFTWARE\Classes\Directory\shell\CursorAdmin",
                "HKCU\SOFTWARE\Classes\Directory\shell\CursorAdmin\command",
                "HKCU\SOFTWARE\Classes\*\shell\Cursor",
                "HKCU\SOFTWARE\Classes\*\shell\Cursor\command"
            )

            foreach ($key in $keysToBackup) {
                Backup-RegistryKey -RegistryPath $key
            }

            $regContent = @"
Windows Registry Editor Version 5.00

; Open files
[HKEY_CURRENT_USER\Software\Classes\*\shell\Open with Cursor]
@="Edit with Cursor"
"Icon"="C:\\Users\\$env:USERNAME\\AppData\\Local\\Programs\\cursor\\cursor.exe,0"
[HKEY_CURRENT_USER\Software\Classes\*\shell\Open with Cursor\command]
@="\"C:\\Users\\$env:USERNAME\\AppData\\Local\\Programs\\cursor\\cursor.exe\" \"%1\""


[HKEY_CURRENT_USER\Software\Classes\*\shell\Open with Cursor (Admin)]
@="Edit with Cursor (Admin)"
"Icon"="C:\\Users\\$env:USERNAME\\AppData\\Local\\Programs\\cursor\\cursor.exe,0"
"HasLUAShield"=""
[HKEY_CURRENT_USER\Software\Classes\*\shell\Open with Cursor (Admin)\command]

@="powershell -WindowStyle Hidden -Command \"Start-Process 'C:\\Users\\$env:USERNAME\\AppData\\Local\\Programs\\cursor\\cursor.exe' -ArgumentList '%1' -Verb RunAs\""


; This will make it appear when you right click ON a folder
; The "Icon" line can be removed if you don't want the icon to appear
[HKEY_CURRENT_USER\Software\Classes\Directory\shell\cursor]
@="Open Folder as Cursor Project"
"Icon"="C:\\Users\\$env:USERNAME\\AppData\\Local\\Programs\\cursor\\cursor.exe,0"
[HKEY_CURRENT_USER\Software\Classes\Directory\shell\cursor\command]
@="\"C:\\Users\\$env:USERNAME\\AppData\\Local\\Programs\\cursor\\cursor.exe\" \"%1\""


[HKEY_CURRENT_USER\Software\Classes\Directory\shell\cursor (Admin)]
@="Open Folder as Cursor Project (Admin)"
"Icon"="C:\\Users\\$env:USERNAME\\AppData\\Local\\Programs\\cursor\\cursor.exe,0"
"HasLUAShield"=""
[HKEY_CURRENT_USER\Software\Classes\Directory\shell\cursor (Admin)\command]

@="powershell -WindowStyle Hidden -Command \"Start-Process 'C:\\Users\\$env:USERNAME\\AppData\\Local\\Programs\\cursor\\cursor.exe' -ArgumentList '%1' -Verb RunAs\""


; This will make it appear when you right click INSIDE a folder
; The "Icon" line can be removed if you don't want the icon to appear
[HKEY_CURRENT_USER\Software\Classes\Directory\Background\shell\cursor]
@="Open Folder as Cursor Project"
"Icon"="C:\\Users\\$env:USERNAME\\AppData\\Local\\Programs\\cursor\\cursor.exe,0"
[HKEY_CURRENT_USER\Software\Classes\Directory\Background\shell\cursor\command]
@="\"C:\\Users\\$env:USERNAME\\AppData\\Local\\Programs\\cursor\\cursor.exe\" \"%V\""


[HKEY_CURRENT_USER\Software\Classes\Directory\Background\shell\cursor (Admin)]
@="Open Folder as Cursor Project (Admin)"
"Icon"="C:\\Users\\$env:USERNAME\\AppData\\Local\\Programs\\cursor\\cursor.exe,0"
"HasLUAShield"=""
[HKEY_CURRENT_USER\Software\Classes\Directory\Background\shell\cursor (Admin)\command]

@="powershell -WindowStyle Hidden -Command \"Start-Process 'C:\\Users\\$env:USERNAME\\AppData\\Local\\Programs\\cursor\\cursor.exe' -ArgumentList '%V' -Verb RunAs\""
"@

            # Add Cursor to Explorer context menu
            $cursorPath = [System.IO.Path]::Combine($env:LOCALAPPDATA, "Programs", "Cursor", "Cursor.exe")
            if (Test-Path $cursorPath -PathType Leaf) {
                
                $regFilePath = ".\cursor_context_menu.reg"
                Set-Content -Path $regFilePath -Value $regContent
                Set-Content -Path ".\cursor_backup.reg" -Value $regContent
                regedit.exe /s $regFilePath
                Remove-Item $regFilePath -Force

            }

            Write-LogMessage "Vellykket!" -ForegroundColor Green
            Write-ApplicationLog -AppName "System Configuration" -Status "Success" -Message "Cursor configuration completed successfully"
            Write-LogMessage "Endringene vil tre i kraft etter omstart av Windows Explorer" -Level WARN
            $script:reboot = $true
        }
        catch {
            Write-LogMessage "Mislyktes: $($_.Exception.Message)$(if($_.Exception.InnerException){" $($_.Exception.InnerException.Message)"})" -Level ERROR -Exception $_
            Write-ApplicationLog -AppName "System Configuration" -Status "Failed" -Message $("Configuration failed: " + $_.Exception.Message + $(if ($_.Exception.InnerException) { " $($_.Exception.InnerException.Message)" }))
        }
        #>
    }
    catch {
        Write-LogMessage "Mislyktes: $($_.Exception.Message)$(if($_.Exception.InnerException){" $($_.Exception.InnerException.Message)"})" -Level ERROR -Exception $_
        Write-ApplicationLog -AppName "System Configuration" -Status "Failed" -Message $("Configuration failed: " + $_.Exception.Message + $(if ($_.Exception.InnerException) { " $($_.Exception.InnerException.Message)" }))
    }
}

function SetPowerShell7Config {
    Write-LogMessage "Configuring PowerShell 7 context menu... This may take a while..." -NoNewline
    try {
        # Backup registry keys before modification
        $keysToBackup = @(
            "HKCU\SOFTWARE\Classes\Directory\Background\shell\pwsh7",
            "HKCU\SOFTWARE\Classes\Directory\Background\shell\pwsh7\command",
            "HKCU\SOFTWARE\Classes\Directory\Background\shell\pwsh7 (Admin)",
            "HKCU\SOFTWARE\Classes\Directory\Background\shell\pwsh7 (Admin)\command",
            "HKCU\SOFTWARE\Classes\Directory\shell\pwsh7",
            "HKCU\SOFTWARE\Classes\Directory\shell\pwsh7\command",
            "HKCU\SOFTWARE\Classes\Directory\shell\pwsh7 (Admin)",
            "HKCU\SOFTWARE\Classes\Directory\shell\pwsh7 (Admin)\command"
        )

        foreach ($key in $keysToBackup) {
            Backup-RegistryKey -RegistryPath $key
        }

        # Find Cursor executable path
        $pwshPath = Get-ChildItem -Path "$env:PROGRAMFILES\PowerShell\7\pwsh.exe" -Filter "pwsh.exe" -Recurse | 
        Select-Object -ExpandProperty FullName -First 1
        
        if (-not $pwshPath) {
            Write-LogMessage "Mislyktes: PowerShell 7 ikke funnet" -Level ERROR
            Write-ApplicationLog -AppName "PowerShell 7" -Status "Failed" -Message "PowerShell 7 executable not found"
            return
        }
        # Clean up existing entries to avoid duplicates
        $keysToRemove = @(
            "HKCU:\SOFTWARE\Classes\Directory\Background\shell\pwsh7 (Admin)",
            "HKCU:\SOFTWARE\Classes\Directory\shell\pwsh7 (Admin)"
        )

        foreach ($key in $keysToRemove) {
            if (Test-Path $key) {
                Remove-Item -Path $key -Force -Recurse
            }
        }

        # Create registry content
        $regContent = @"
Windows Registry Editor Version 5.00

; Open files

[HKEY_CURRENT_USER\Software\Classes\Directory\shell\pwsh7 (Admin)]
@="Open Folder with PowerShell 7 (Admin)"
"Icon"="$($pwshPath.Replace('\', '\\')),0"
"HasLUAShield"=""
[HKEY_CURRENT_USER\Software\Classes\Directory\shell\pwsh7 (Admin)\command]
@="powershell -WindowStyle Hidden -Command \"Start-Process '$($pwshPath.Replace('\', '\\'))' -ArgumentList '%V' -Verb RunAs\""


[HKEY_CURRENT_USER\Software\Classes\Directory\Background\shell\pwsh7 (Admin)]
@="Open Folder with PowerShell 7 (Admin)"
"Icon"="$($pwshPath.Replace('\', '\\')),0"
"HasLUAShield"=""
[HKEY_CURRENT_USER\Software\Classes\Directory\Background\shell\pwsh7 (Admin)\command]
@="powershell -WindowStyle Hidden -Command \"Start-Process '$($pwshPath.Replace('\', '\\'))' -ArgumentList '%V' -Verb RunAs\""
"@

        # Apply registry changes using .reg file
        $regFilePath = Join-Path $env:TEMP "pwsh7_context_menu.reg"
        $backupPath = Join-Path $env:TEMP "pwsh7_backup.reg"

        Set-Content -Path $regFilePath -Value $regContent -Encoding Unicode
        Set-Content -Path $backupPath -Value $regContent -Encoding Unicode
        
        # Import registry file
        $process = Start-Process -FilePath "regedit.exe" -ArgumentList "/s", "`"$regFilePath`"" -PassThru -Wait
        
        if ($process.ExitCode -ne 0) {
            throw "Failed to import registry file (Exit code: $($process.ExitCode))"
        }
        
        # Clean up temporary file
        Remove-Item $regFilePath -Force -ErrorAction SilentlyContinue

        # Restart Explorer to apply changes
        Get-Process -Name explorer -ErrorAction SilentlyContinue | Stop-Process -Force

        Write-LogMessage "Vellykket!" -ForegroundColor Green
        Write-ApplicationLog -AppName "System Configuration" -Status "Success" -Message "PowerShell 7 configuration completed successfully"
        Write-LogMessage "Endringene vil tre i kraft etter omstart av Windows Explorer" -Level WARN
        $script:reboot = $true
    }
    catch {
        Write-LogMessage "Mislyktes: $($_.Exception.Message)$(if($_.Exception.InnerException){" $($_.Exception.InnerException.Message)"})" -Level ERROR -Exception $_
        Write-ApplicationLog -AppName "System Configuration" -Status "Failed" -Message $("Configuration failed: " + $_.Exception.Message + $(if ($_.Exception.InnerException) { " $($_.Exception.InnerException.Message)" }))
    }
}



function SetExplorerConfig {
    Write-LogMessage "Configuring Explorer context menu... This may take a while..." -NoNewline
    try {
        # Backup registry keys before modification
        $keysToBackup = @(
            "HKCU\SOFTWARE\Classes\Directory\Background\shell\FkExplorer",
            "HKCU\SOFTWARE\Classes\Directory\Background\shell\FkExplorer\command",
            "HKCU\SOFTWARE\Classes\Directory\Background\shell\FkExplorer (Admin)",
            "HKCU\SOFTWARE\Classes\Directory\Background\shell\FkExplorer (Admin)\command",
            "HKCU\SOFTWARE\Classes\Directory\shell\FkExplorer",
            "HKCU\SOFTWARE\Classes\Directory\shell\FkExplorer\command",
            "HKCU\SOFTWARE\Classes\Directory\shell\FkExplorer (Admin)",
            "HKCU\SOFTWARE\Classes\Directory\shell\FkExplorer (Admin)\command"
        )

        foreach ($key in $keysToBackup) {
            Backup-RegistryKey -RegistryPath $key
        }

        # Find Cursor executable path
        $explorerPath = $env:WINDIR + "\Explorer.exe"
        
        if (-not $explorerPath) {
            Write-LogMessage "Mislyktes: Explorer ikke funnet" -Level ERROR
            Write-ApplicationLog -AppName "Explorer" -Status "Failed" -Message "Explorer executable not found"
            return
        }
        # Clean up existing entries to avoid duplicates
        $keysToRemove = @(
            "HKCU:\SOFTWARE\Classes\Directory\Background\shell\FkExplorer (Admin)",
            "HKCU:\SOFTWARE\Classes\Directory\shell\FkExplorer (Admin)" 
        )

        foreach ($key in $keysToRemove) {
            if (Test-Path $key) {
                Remove-Item -Path $key -Force -Recurse
            }
        }

        # Create registry content
        $regContent = @"
Windows Registry Editor Version 5.00

; Open files

[HKEY_CURRENT_USER\Software\Classes\Directory\shell\FkExplorer (Admin)]
@="Open Folder with Explorer (Admin)"
"Icon"="$($explorerPath.Replace('\', '\\')),0"
"HasLUAShield"=""
[HKEY_CURRENT_USER\Software\Classes\Directory\shell\FkExplorer (Admin)\command]
@="powershell -WindowStyle Hidden -Command \"Start-Process '$($explorerPath.Replace('\', '\\'))' -ArgumentList '%V' -Verb RunAs\""


[HKEY_CURRENT_USER\Software\Classes\Directory\Background\shell\FkExplorer (Admin)]
@="Open Folder with Explorer (Admin)"
    "Icon"="$($explorerPath.Replace('\', '\\')),0"
"HasLUAShield"=""
[HKEY_CURRENT_USER\Software\Classes\Directory\Background\shell\FkExplorer (Admin)\command]
@="powershell -WindowStyle Hidden -Command \"Start-Process '$($explorerPath.Replace('\', '\\'))' -ArgumentList '%V' -Verb RunAs\""
"@

        # Apply registry changes using .reg file
        $regFilePath = Join-Path $env:TEMP "FkExplorer_context_menu.reg"
        $backupPath = Join-Path $env:TEMP "FkExplorer_backup.reg"

        Set-Content -Path $regFilePath -Value $regContent -Encoding Unicode
        Set-Content -Path $backupPath -Value $regContent -Encoding Unicode
        
        # Import registry file
        $process = Start-Process -FilePath "regedit.exe" -ArgumentList "/s", "`"$regFilePath`"" -PassThru -Wait
        
        if ($process.ExitCode -ne 0) {
            throw "Failed to import registry file (Exit code: $($process.ExitCode))"
        }
        
        # Clean up temporary file
        Remove-Item $regFilePath -Force -ErrorAction SilentlyContinue

        # Restart Explorer to apply changes
        Get-Process -Name explorer -ErrorAction SilentlyContinue | Stop-Process -Force

        Write-LogMessage "Vellykket!" -ForegroundColor Green
        Write-ApplicationLog -AppName "System Configuration" -Status "Success" -Message "Explorer configuration completed successfully"
        Write-LogMessage "Endringene vil tre i kraft etter omstart av Windows Explorer" -Level WARN
        $script:reboot = $true
    }
    catch {
        Write-LogMessage "Mislyktes: $($_.Exception.Message)$(if($_.Exception.InnerException){" $($_.Exception.InnerException.Message)"})" -Level ERROR -Exception $_
        Write-ApplicationLog -AppName "System Configuration" -Status "Failed" -Message $("Configuration failed: " + $_.Exception.Message + $(if ($_.Exception.InnerException) { " $($_.Exception.InnerException.Message)" }))
    }
}

function Set-NetExpressConfig {
    Write-LogMessage "Konfigurerer NetExpress miljø..." -NoNewline
    try {
        # Set environment variables for User only
        $pathAdditions = @(
            "C:\Program Files (x86)\Micro Focus\Net Express 5.1\Base\Bin",
            "C:\Program Files (x86)\Micro Focus\Net Express 5.1\DIALOGSYSTEM\Bin"
        )
    
        $currentPath = [Environment]::GetEnvironmentVariable("Path", "User")
        $newPath = ($currentPath.Split(';') + $pathAdditions | Select-Object -Unique) -join ';'
        [Environment]::SetEnvironmentVariable("Path", $newPath, "User")
        [Environment]::SetEnvironmentVariable("COBDIR", "C:\Program Files (x86)\Micro Focus\Net Express 5.1\base\Bin;C:\Program Files (x86)\Micro Focus\Net Express 5.1\DialogSystem\Bin", "User")
        [Environment]::SetEnvironmentVariable("COBCPY", "K:\fkavd\nt;k:\fkavd\sys\cpy", "User")
    
        # Clean registry and create shortcut
        Clear-NetExpressRegistry
        New-DialogSystemShortcut
        Write-LogMessage "Creating backup of DS.CFG..." -NoNewline
        Copy-Item "C:\Program Files (x86)\Micro Focus\Net Express 5.1\DIALOGSYSTEM\Bin\DS.CFG" -Destination "C:\Program Files (x86)\Micro Focus\Net Express 5.1\DIALOGSYSTEM\Bin\DS.CFG.$(Get-Date -Format 'yyyyMMddHHmmss').BAK" -Force
        Write-LogMessage "Copying correct version of DS.CFG..." -NoNewline
        Copy-Item "C:\opt\src\DedgeSrc\DedgeSystemTools\Folders\DedgeCommon\Software\WindowsApps\MicroFocus NetExpress Pack\DS.CFG" "C:\Program Files (x86)\Micro Focus\Net Express 5.1\DIALOGSYSTEM\Bin\DS.CFG" -Force
        Write-LogMessage "Vellykket!" -ForegroundColor Green
        Write-ApplicationLog -AppName "NetExpress" -Status "Success" -Message "Environment configured successfully"
    }
    catch {
        Write-LogMessage "Mislyktes: ${_}" -Level ERROR -Exception $_
        Write-ApplicationLog -AppName "NetExpress" -Status "Failed" -Message "Configuration failed: $($_.Exception.Message)$(if($_.Exception.InnerException){" $($_.Exception.InnerException.Message)"})"
    }
}

function Set-SpfConfig {
    Write-LogMessage "Konfigurerer SPF miljø..." -NoNewline
    try {
        Add-Folder -Path "C:\SPFSE" -AdditionalAdmins @("$env:USERDOMAIN\$env:USERNAME")
        
        # Backup registry key before modification
        $regPath = "HKCU\Software\Microsoft\Windows NT\CurrentVersion\AppCompatFlags\Layers"
        Backup-RegistryKey -RegistryPath $regPath
        
        # Create/update shortcuts with compatibility mode
        $WshShell = New-Object -ComObject WScript.Shell
        $targetPath = "C:\SPFSE\bin\spf45.exe"

        $desktopPath = [Environment]::GetFolderPath("Desktop")
        $startMenuPath = [Environment]::GetFolderPath("StartMenu")
      
        $shortcuts = @(
            "$desktopPath\SPF Editor 4.5.lnk",
            "$startMenuPath\Programs\SPF Editor 4.5.lnk"
        )

        foreach ($shortcutPath in $shortcuts) {
            # Remove existing shortcut if it exists
            if (Test-Path $shortcutPath -PathType Leaf) {
                Remove-Item $shortcutPath -Force
            }
            $shortcut = $WshShell.CreateShortcut($shortcutPath)
            $shortcut.TargetPath = $targetPath
            $shortcut.IconLocation = "$targetPath,0"
            $shortcut.Save()

            # Set compatibility mode
            $regPath = "Registry::HKCU\Software\Microsoft\Windows NT\CurrentVersion\AppCompatFlags\Layers"
            if (-not (Test-Path $regPath)) {
                New-Item -Path $regPath -Force | Out-Null
            }
            Set-ItemProperty -Path $regPath -Name $shortcutPath -Value "~ WINXPSP2" -Type String
          
        }
        Write-ApplicationLog -AppName "System Configuration" -Status "Success" -Message "Shortcuts and compatibility mode configured successfully"
        
        Write-LogMessage "Vellykket!" -ForegroundColor Green
    }
    catch {
        Write-LogMessage "Mislyktes: $($_.Exception.Message)$(if($_.Exception.InnerException){" $($_.Exception.InnerException.Message)"})" -Level ERROR -Exception $_
        Write-ApplicationLog -AppName "System Configuration" -Status "Failed" -Message "Configuration failed: $($_.Exception.Message)$(if($_.Exception.InnerException){" $($_.Exception.InnerException.Message)"})"
    }
}

function Set-QmfConfig {
    Write-LogMessage "Konfigurerer QMF..." -NoNewline
    try {
        # Backup registry keys before modification
        $keysToBackup = @(
            "HKCU\Software\IBM\QMF for Windows",
            "HKCU\Software\IBM\QMF for Windows\Recent SDFs"
        )

        foreach ($key in $keysToBackup) {
            Backup-RegistryKey -RegistryPath $key
        }

        # Copy nodelock file
        $nodelockSource = "C:\opt\src\DedgeSrc\DedgeSystemTools\Folders\DedgeCommon\Software\WindowsApps\IBM QMF For Windows\qnf81nodelock\nodelock"
        $nodelockDest = "C:\Program Files (x86)\IBM\QMF for Windows\nodelock"
        
        Write-LogMessage "Kopierer nodelock fil..." -NoNewline
        Copy-Item -Path $nodelockSource -Destination $nodelockDest -Force
        Write-LogMessage "Vellykket!" -ForegroundColor Green
        Write-ApplicationLog -AppName "QMF for Windows" -Status "Success" -Message $("nodelock copied successfully")

        # Copy QMFSDF.ini file
        $iniSource = "C:\opt\src\DedgeSrc\DedgeSystemTools\Folders\DedgeCommon\Software\WindowsApps\IBM QMF For Windows\QMFSDF.INI"
        $iniDest = "C:\Program Files (x86)\IBM\QMF for Windows\"
        
        Write-LogMessage "Kopierer QMFSDF.ini fil..." -NoNewline
        Copy-Item -Path $iniSource -Destination $iniDest -Force
        Write-LogMessage "Vellykket!" -ForegroundColor Green
        Write-ApplicationLog -AppName "QMF for Windows" -Status "Success" -Message $("QMFSDF.ini copied successfully")

        # Set registry settings
        $qmfRegPath = "HKCU\Software\IBM\QMF for Windows"
        $qmfRecentSDFsPath = "$qmfRegPath\Recent SDFs"
        
        # Create registry keys using PowerShell
        $qmfRegPathPS = "Registry::$qmfRegPath"
        $qmfRecentSDFsPathPS = "Registry::$qmfRecentSDFsPath"

        # Create base QMF registry key if it doesn't exist
        if (-not (Test-Path -Path $qmfRegPathPS)) {
            New-Item -Path $qmfRegPathPS -Force | Out-Null
        }

        # Create Recent SDFs subkey if it doesn't exist 
        if (-not (Test-Path -Path $qmfRecentSDFsPathPS)) {
            New-Item -Path $qmfRecentSDFsPathPS -Force | Out-Null
        }

        # Set file1, file2 and @ value
        Set-ItemProperty -Path $qmfRecentSDFsPathPS -Name "file1" -Value $iniDest -Type String -Force -ErrorAction SilentlyContinue
        Set-ItemProperty -Path $qmfRecentSDFsPathPS -Name "file2" -Value $iniDest -Type String -Force -ErrorAction SilentlyContinue
        Set-ItemProperty -Path $qmfRecentSDFsPathPS -Name "@" -Value $iniDest -Type String -Force -ErrorAction SilentlyContinue
        Write-LogMessage "QMF configuration completed successfully" -ForegroundColor Green
        Write-ApplicationLog -AppName "QMF for Windows" -Status "Success" -Message "Configuration completed successfully"
    }
    catch {
        Write-LogMessage "Failed to set QMF configuration" -Level ERROR -Exception $_
        Write-ApplicationLog -AppName "QMF for Windows" -Status "Failed" -Message $("Configuration failed: " + $_.Exception.Message)
    }
}

function Set-WindowsNorwegianLanguage {
    Write-LogMessage "Setter Windows språk til norsk..." -NoNewline
    try {
        # Set Norwegian language using rundll32
        Start-Process -FilePath "rundll32.exe" -ArgumentList @(
            "shell32.dll,Control_RunDLL",
            "intl.cpl,,/f:2"
        ) -Wait -PassThru | Out-Null

        # Set Windows display language to Norwegian
        Set-WinUILanguageOverride -Language nb-NO
        Set-WinUserLanguageList nb-NO -Force
        Set-WinDefaultInputMethodOverride -Language nb-NO

        # Set Windows display language using Control Panel
        Start-Process -FilePath "rundll32.exe" -ArgumentList @(
            "shell32.dll,Control_RunDLL",
            "intl.cpl,,/f:1"
        ) -Wait -PassThru | Out-Null

        Write-LogMessage "Vellykket!" -ForegroundColor Green
        Write-ApplicationLog -AppName "System Configuration" -Status "Success" -Message "Successfully set Windows language to Norwegian"
        Write-LogMessage "Endringene vil tre i kraft etter omstart av Windows" -Level WARN
        $script:reboot = $true
    }
    catch {
        Write-LogMessage "Mislyktes: $($_.Exception.Message)$(if($_.Exception.InnerException){" $($_.Exception.InnerException.Message)"})" -Level ERROR -Exception $_
        Write-ApplicationLog -AppName "System Configuration" -Status "Failed" -Message $("Failed to set Windows language: " + $_.Exception.Message + $(if ($_.Exception.InnerException) { " $($_.Exception.InnerException.Message)" }))
    }
}

function Set-WindowsEnglishLanguage {
    Write-LogMessage "Setter Windows språk til engelsk..." -NoNewline
    try {
        # Set English language using rundll32
        Start-Process -FilePath "rundll32.exe" -ArgumentList @(
            "shell32.dll,Control_RunDLL",
            "intl.cpl,,/f:2"
        ) -Wait -PassThru | Out-Null

        # Set Windows display language to English
        Set-WinUILanguageOverride -Language en-US
        Set-WinUserLanguageList en-US -Force
        Set-WinDefaultInputMethodOverride -Language en-US

        # Set Windows display language using Control Panel
        Start-Process -FilePath "rundll32.exe" -ArgumentList @(
            "shell32.dll,Control_RunDLL",
            "intl.cpl,,/f:1"
        ) -Wait -PassThru | Out-Null

        Write-LogMessage "Vellykket!" -ForegroundColor Green
        Write-ApplicationLog -AppName "System Configuration" -Status "Success" -Message "Successfully set Windows language to English"
        Write-LogMessage "Endringene vil tre i kraft etter omstart av Windows" -Level WARN
        $script:reboot = $true
    }
    catch {
        Write-LogMessage "Mislyktes: $($_.Exception.Message)$(if($_.Exception.InnerException){" $($_.Exception.InnerException.Message)"})" -Level ERROR -Exception $_
        Write-ApplicationLog -AppName "System Configuration" -Status "Failed" -Message $("Failed to set Windows language: " + $_.Exception.Message + $(if ($_.Exception.InnerException) { " $($_.Exception.InnerException.Message)" }))
    }
}

function Remove-NonNorwegianKeyboards {
    Write-LogMessage "Fjerner andre tastaturlayouts enn norsk..." -NoNewline


    try {
        # Create and start an elevated process to execute rundll commands
        $processInfo = New-Object System.Diagnostics.ProcessStartInfo
        $processInfo.FileName = "rundll32.exe"
        $processInfo.Arguments = "user32.dll,LoadKeyboardLayout 0414:00000414,1"
        $processInfo.Verb = "runas"
        $processInfo.UseShellExecute = $true
        
        # Execute rundll with elevation to set Norwegian keyboard
        $process = [System.Diagnostics.Process]::Start($processInfo)
        $process.WaitForExit()

        # Remove other keyboard layouts
        $processInfo.Arguments = "user32.dll,UnloadKeyboardLayout"
        $process = [System.Diagnostics.Process]::Start($processInfo)
        $process.WaitForExit()

        Write-LogMessage "Vellykket!" -ForegroundColor Green
        Write-ApplicationLog -AppName "System Configuration" -Status "Success" -Message "Successfully removed non-Norwegian keyboards"
    }
    catch {
        Write-LogMessage "Mislyktes: $($_.Exception.Message)$(if($_.Exception.InnerException){" $($_.Exception.InnerException.Message)"})" -Level ERROR -Exception $_
        Write-ApplicationLog -AppName "System Configuration" -Status "Failed" -Message $("Failed to remove non-Norwegian keyboards: " + $_.Exception.Message + $(if ($_.Exception.InnerException) { " $($_.Exception.InnerException.Message)" }))
    }
}

function Set-DBeaverConfig {
    return ""
    #     Write-LogMessage "Konfigurerer DBeaver..."
    #     try {
    #         # Get workspace path
    #         $workspacePath = (Get-ItemProperty -Path "HKCU:\Software\DBeaverCommunity" -Name "workspace" -ErrorAction SilentlyContinue).workspace
    #         if (-not $workspacePath) {
    #             $workspacePath = "$env:APPDATA\DBeaverData\workspace6"
    #         }

    #         # Find DBeaver executable
    #         $dbeaverPaths = @(
    #             "${env:USERPROFILE}\AppData\Local\DBeaver\dbeaver.exe",
    #             "${env:ProgramFiles}\DBeaver\dbeaver.exe",
    #             "${env:ProgramFiles(x86)}\DBeaver\dbeaver.exe",
    #             "${env:LocalAppData}\Programs\DBeaver\dbeaver.exe",
    #             "${env:ProgramFiles}\DBeaverCE\dbeaver.exe",
    #             "${env:ProgramFiles(x86)}\DBeaverCE\dbeaver.exe",
    #             "${env:LocalAppData}\Programs\DBeaverCE\dbeaver.exe"
    #         )

    #         $dbeaverExe = $dbeaverPaths | Where-Object { Test-Path $_ } | Select-Object -First 1
    #         if (-not $dbeaverExe) {
    #             Write-LogMessage "Mislyktes: DBeaver ikke funnet" -Level ERROR
    #             Write-ApplicationLog -AppName "DBeaver" -Status "Failed" -Message "DBeaver executable not found"
    #             return
    #         }
    #         Write-ApplicationLog -AppName "DBeaver" -Status "Progress" -Message "DBeaver found at: $dbeaverExe"
    
    #         # Create base directories first
    #         $baseDir = "$env:APPDATA\DBeaverData\workspace6"
    #         $dbeaverConfigPath = "$baseDir\.metadata\.plugins\org.jkiss.dbeaver.core"
    #         $preferencesPath = "$baseDir\.metadata\.plugins\org.eclipse.core.runtime\.settings"

    #         # Check if DBeaver is running and kill all related processes
    #         $dbeaverProcesses = Get-Process | Where-Object { $_.ProcessName -match "dbeaver|java" -and $_.MainWindowTitle -match "DBeaver" } -ErrorAction SilentlyContinue
    #         if ($dbeaverProcesses) {
    #             Write-LogMessage "Lukker kjørende DBeaver instanser..." -NoNewline
    #             $dbeaverProcesses | ForEach-Object {
    #                 Stop-Process -Id $_.Id -Force
    #             }
    #             Start-Sleep -Seconds 3
    #             Write-LogMessage "Vellykket!" -ForegroundColor Green
    #             Write-ApplicationLog -AppName "DBeaver" -Status "Progress" -Message "Closed running DBeaver instances"
    #         }

    #         Write-LogMessage "Forbereder workspace..." -NoNewline
    #         # Clean up workspace lock files
    #         $lockFiles = @(
    #             "$baseDir\.metadata\.lock",
    #             "$baseDir\.metadata\.plugins\org.eclipse.e4.workbench\workbench.xmi.backup",
    #             "$baseDir\.metadata\.plugins\org.eclipse.core.resources\.snap"
    #         )

    #         foreach ($lockFile in $lockFiles) {
    #             if (Test-Path $lockFile -PathType Leaf) {
    #                 Remove-Item -Path $lockFile -Force 
    #             }
    #         }

    #         # # Additional cleanup of workspace metadata
    #         # $metadataPath = "$baseDir\.metadata"
    #         # if (Test-Path $metadataPath) {
    #         #     Get-ChildItem -Path $metadataPath -Filter "*.log" -Recurse | Remove-Item -Force -Confirm:$true
    #         #     Get-ChildItem -Path $metadataPath -Filter "*.lock" -Recurse | Remove-Item -Force -Confirm:$true
    #         # }

    #         # Create directories if they don't exist
    #         @($baseDir, $dbeaverConfigPath, $preferencesPath) | ForEach-Object {
    #             if (-not (Test-Path $_)) {
    #                 New-Item -ItemType Directory -Force -Path $_ | Out-Null
    #             }
    #         }

    #         # Set registry settings
    #         $registryPath = "HKCU:\Software\DBeaverCommunity"
    #         if (-not (Test-Path $registryPath)) {
    #             New-Item -Path $registryPath -Force | Out-Null
    #         }
    #         Set-ItemProperty -Path $registryPath -Name "workspace" -Value $baseDir -Force

    #         # Create project file
    #         $projectContent = @"
    # <?xml version="1.0" encoding="UTF-8"?>
    # <projectDescription>
    #     <name>DBeaver</name>
    #     <comment></comment>
    #     <projects>
    #     </projects>
    #     <buildSpec>
    #     </buildSpec>
    #     <natures>
    #         <nature>org.jkiss.dbeaver.DBeaverNature</nature>
    #     </natures>
    # </projectDescription>
    # "@
    #         $projectContent | Out-File -FilePath "$dbeaverConfigPath\.project" -Encoding UTF8 -Force

    #         # Create preferences file
    #         $preferencesContent = @"
    # eclipse.preferences.version=1
    # org.jkiss.dbeaver.core.confirm.exit=false
    # ui.auto.update.check.time=0
    # "@
    #         $preferencesContent | Out-File -FilePath "$preferencesPath\org.jkiss.dbeaver.core.prefs" -Encoding UTF8 -Force

    #         Write-LogMessage "Vellykket!" -ForegroundColor Green
    #         Write-ApplicationLog -AppName "DBeaver" -Status "Progress" -Message "Workspace prepared successfully"

    #         # Create a custom import file in XML format
    #         $importXml = @"
    # <?xml version="1.0" encoding="UTF-8"?>
    # <connections>
    #     <connection 
    #         name="Dedge Utvikling" 
    #         description="Dedge Utvikling"
    #         host="t-no1fkmtst-db.DEDGE.fk.no" 
    #         port="3710" 
    #         database="FKAVDNT" 
    #         url="jdbc:db2://t-no1fkmtst-db.DEDGE.fk.no:3710/FKAVDNT" 
    #         user="DEDGE\$env:USERNAME"         
    #     />
    #     <connection 
    #         name="Dedge Test" 
    #         description="Dedge Test"
    #         host="t-no1fkmtst-db.DEDGE.fk.no" 
    #         port="3701" 
    #         database="BASISTST" 
    #         url="jdbc:db2://t-no1fkmtst-db.DEDGE.fk.no:3701/BASISTST" 
    #         user="DEDGE\$env:USERNAME"                 
    #     />
    #     <connection 
    #         name="Dedge Prod" 
    #         description="Dedge Prod"
    #         host="p-no1fkmprd-db.DEDGE.fk.no" 
    #         port="3700" 
    #         database="BASISPRO" 
    #         url="jdbc:db2://p-no1fkmprd-db.DEDGE.fk.no:3700/BASISPRO" 
    #         user="DEDGE\$env:USERNAME" 
    #     />
    #     <connection 
    #         name="Dedge Rapportering" 
    #         description="Dedge Rapportering"
    #         host="t-no1fkmtst-db.DEDGE.fk.no" 
    #         port="3700" 
    #         database="BASISRAP" 
    #         url="jdbc:db2://t-no1fkmtst-db.DEDGE.fk.no:3700/BASISRAP" 
    #         user="DEDGE\$env:USERNAME" 
    #     />
    #     <connection 
    #         name="Dedge Historikk" 
    #         description="Dedge Historikk"
    #         host="p-no1fkmprd-db.DEDGE.fk.no" 
    #         port="3700" 
    #         database="BASISHST" 
    #         url="jdbc:db2://p-no1fkmprd-db.DEDGE.fk.no:3700/BASISHST" 
    #         user="DEDGE\$env:USERNAME" 
    #     />
    #     <connection 
    #         name="Fkkonto Prod" 
    #         description="Fkkonto Prod"
    #         host="t-no1fkmtst-db.DEDGE.fk.no" 
    #         port="3705" 
    #         database="FKKONTO" 
    #         url="jdbc:db2://t-no1fkmtst-db.DEDGE.fk.no:3705/FKKONTO" 
    #         user="DEDGE\$env:USERNAME" 
    #     />
    #     <connection 
    #         name="Dedge Migrering D365" 
    #         description="Dedge Migrering D365"
    #         host="t-no1fkmtst-db.DEDGE.fk.no" 
    #         port="3711" 
    #         database="BASISMIG" 
    #         url="jdbc:db2://t-no1fkmtst-db.DEDGE.fk.no:3711/BASISMIG" 
    #         user="DEDGE\$env:USERNAME" 
    #     />
    #     <connection 
    #         name="Dedge SIT D365" 
    #         description="Dedge SIT D365"
    #         host="t-no1fkmtst-db.DEDGE.fk.no" 
    #         port="3711" 
    #         database="BASISSIT" 
    #         url="jdbc:db2://t-no1fkmtst-db.DEDGE.fk.no:3711/BASISSIT" 
    #         user="DEDGE\$env:USERNAME" 
    #     />
    #     <connection 
    #         name="Dedge Test D365" 
    #         description="Dedge Test D365"
    #         host="t-no1fkmtst-db.DEDGE.fk.no" 
    #         port="3711" 
    #         database="BASISVFT" 
    #         url="jdbc:db2://t-no1fkmtst-db.DEDGE.fk.no:3711/BASISVFT" 
    #         user="DEDGE\$env:USERNAME" 
    #     />
    #     <connection 
    #         name="Dedge VFK D365" 
    #         description="Dedge VFK D365"
    #         host="t-no1fkmtst-db.DEDGE.fk.no" 
    #         port="3711" 
    #         database="BASISVFK" 
    #         url="jdbc:db2://t-no1fkmtst-db.DEDGE.fk.no:3711/BASISVFK" 
    #         user="DEDGE\$env:USERNAME" 
    #     />
    #     <connection 
    #         name="Visual Cobol POC Development" 
    #         description="Visual Cobol POC Development"
    #         host="t-no1fkmtst-db.DEDGE.fk.no" 
    #         port="3715" 
    #         database="DB2DEV" 
    #         url="jdbc:db2://t-no1fkmtst-db.DEDGE.fk.no:3715/DB2DEV" 
    #         user="DEDGE\$env:USERNAME" 
    #     />
    #     <connection 
    #         name="Dedge POC Test DB2 Version 11.5" 
    #         description="Dedge POC Test DB2 Version 11.5"
    #         host="p-Dedge-vm02.DEDGE.fk.no" 
    #         port="50000" 
    #         database="FKMTST" 
    #         url="jdbc:db2://p-Dedge-vm02.DEDGE.fk.no:50000/FKMTST" 
    #         user="DEDGE\$env:USERNAME" 
    #     />
    #     <connection 
    #         name="Dedge POC Production DB2 Version 11.5" 
    #         description="Dedge POC Production DB2 Version 11.5"
    #         host="p-Dedge-vm01.DEDGE.fk.no" 
    #         port="50000" 
    #         database="FKMPRD" 
    #         url="jdbc:db2://p-Dedge-vm01.DEDGE.fk.no:50000/FKMPRD" 
    #         user="DEDGE\$env:USERNAME" 
    #     />
    # </connections>
    # "@

    #         Write-LogMessage "Vil du bruke databasenavn som tilkoblingsnavn? (J/N) [N]: " -NoNewline
    #         $userInput = Read-Host
    #         if ($userInput.ToLower() -eq "j") {
    #             Write-LogMessage "Oppdaterer tilkoblingsnavn..." -NoNewline
    #             $importXml = $importXml -replace '(?s)(<connection[^>]*\bname=")[^"]*(".*?\bdatabase=")([^"]*)', '$1$3$2$3'
    #             Write-LogMessage "Vellykket!" -ForegroundColor Green
    #             Write-ApplicationLog -AppName "DBeaver" -Status "Progress" -Message "Updated connection names to use database names"
    #         }

    #         Write-LogMessage "Vil du legge til passord i tilkoblingene? (J/N) [N]: " -NoNewline
    #         $addPassword = Read-Host
    #         if ($addPassword.ToLower() -eq "j") {
    #             Write-LogMessage "Skriv inn passord: " -NoNewline
    #             $secureString = Read-Host -AsSecureString
    #             $BSTR = [System.Runtime.InteropServices.Marshal]::SecureStringToBSTR($secureString)
    #             $password = [System.Runtime.InteropServices.Marshal]::PtrToStringAuto($BSTR)

    #             Write-LogMessage "Legger til passord i tilkoblingene..." -NoNewline
    #             $importXml = $importXml -replace 'DEDGE\\\$env:USERNAME', "DEDGE\$env:USERNAME"
    #             $importXml = $importXml -replace 'user="DEDGE\\[^"]*"', "`$0 password=""$password"""
    #             Write-LogMessage "Vellykket!" -ForegroundColor Green
    #             Write-ApplicationLog -AppName "DBeaver" -Status "Progress" -Message "Added passwords to connections"
    #         }

    #         Write-LogMessage "Oppretter importfiler..." -NoNewline
    #         $currentDir = Get-Location
    #         $importPath = Join-Path $currentDir "dbeaver_import.xml"
    #         $importXml | Out-File -FilePath $importPath -Encoding UTF8 -Force

    #         # Create and execute import script
    #         $importScript = @"
    # @echo off
    # "$dbeaverExe" -import "$importPath" -exit
    # "@
    #         $importScriptPath = Join-Path $currentDir "import_dbeaver.bat"
    #         $importScript | Out-File -FilePath $importScriptPath -Encoding ASCII -Force
    #         Write-LogMessage "Vellykket!" -ForegroundColor Green
    #         Write-ApplicationLog -AppName "DBeaver" -Status "Progress" -Message "Created import files"

    #         Write-LogMessage "Importerer tilkoblinger..." -NoNewline

    #         # Create message box thread
    #         $message = 
    #         @"
    # Når DBeaver starter, følg disse stegene:

    # ✓ 1. Gå til 'File -> Import'
    # ✓ 2. Velg 'Third Party Configuration -> Custom'
    # ✓ 3. Klikk 'Next'
    # ✓ 4. I 'Driver selection' velg 'DB2 for LUW'
    # ✓ 5. Klikk 'Next'
    # ✓ 6. I 'Input settings' La XML være valgt og klikk på den oransje mappeikonet
    # ✓ 7. Stien til filen er kopiert til utklippstavlen så du kan lime den rett inn i feltet for filnavn
    #      , eller du kan velge velge filen selv ved å klikke på 'XML fil' og velge filen $importPath
    # ✓ 8. Velg tilkoblingene du vil importere og klikk 'Finish'
    # "@
    #         Write-LogMessage $message -Level INFO -ForegroundColor Yellow
    #         $job = Show-MessageBox -Message $message -Title "DBeaver Import Instructions" -Timeout 0 -Style 64

    #         # Copy import file path to clipboard
    #         Set-Clipboard -Value $importPath
    #         Write-LogMessage "Filbane kopiert til utklippstavle" -Level INFO
   
    #         Start-Process -FilePath $importScriptPath -Wait
    #         Remove-Item $importScriptPath -Force
    #         Remove-Item $importPath -Force
    #         Write-LogMessage "Vellykket!" -ForegroundColor Green
    #         Write-ApplicationLog -AppName "DBeaver" -Status "Success" -Message "DBeaver configuration completed successfully"
    #         Close-MessageBox -Job $job
    #     }
    #     catch {
    #         Write-LogMessage "Mislyktes: $($_.Exception.Message)$(if($_.Exception.InnerException){" $($_.Exception.InnerException.Message)"})" -Level ERROR -Exception $_
    #         Write-ApplicationLog -AppName "DBeaver" -Status "Failed" -Message $("Configuration failed: " + $_.Exception.Message + $(if ($_.Exception.InnerException) { " $($_.Exception.InnerException.Message)" }))
    #     }
}

function Clear-NetExpressRegistry {
    Write-LogMessage "Retter opp Dialog System miljøvariabler..." -NoNewline
    try {
        # Backup registry key before modification
        $regPath = "HKLM\SOFTWARE\Wow6432Node\Micro Focus\NetExpress\5.1\Dialog System\5.1\Environment"
        Backup-RegistryKey -RegistryPath $regPath

        # Create a process to modify registry with elevated permissions
        $regPath = "HKLM:\SOFTWARE\Wow6432Node\Micro Focus\NetExpress\5.1\Dialog System\5.1\Environment"

        $regPath = "HKLM:\SOFTWARE\Wow6432Node\Micro Focus\NetExpress\5.1\Dialog System\5.1\Environment"
        
        # Create a temporary script to modify registry with elevated permissions
        $regPath = "$regPath"
        if (Test-Path $regPath) {
            $currentPath = Get-ItemProperty -Path $regPath -Name "PATH" | Select-Object -ExpandProperty "PATH"
            $cleanPath = $currentPath -replace '"', ''
            Set-ItemProperty -Path $regPath -Name "PATH" -Value $cleanPath
        }

        
     
        Write-LogMessage "Vellykket!" -ForegroundColor Green
        Write-ApplicationLog -AppName "NetExpress" -Status "Success" -Message "Registry cleaned successfully"
        Write-LogMessage "Endringene vil tre i kraft etter omstart av Windows" -Level WARN
        $script:reboot = $true
    }
    catch {
        Write-LogMessage "Mislyktes: $($_.Exception.Message)$(if($_.Exception.InnerException){" $($_.Exception.InnerException.Message)"})" -Level ERROR -Exception $_
        Write-ApplicationLog -AppName "NetExpress" -Status "Failed" -Message $("Failed to clean registry: " + $_.Exception.Message + $(if ($_.Exception.InnerException) { " $($_.Exception.InnerException.Message)" }))

    }
}


function NetExpressMain {
    param(
        [string]$AppName = "NetExpress"
    )
    $tempPath = "C:\TEMPFK\TempInstallFiles\NetExpress51"          
    Write-LogMessage "Installerer $AppName..." -NoNewline
    try {
        $instructions = "Bruk følgende på spørsmål om serienummer og work order:
             User Name: FKA
             Company Name: FKA
             Serial: 743162
             W.O. Number: 317078
 
             Husk å fjerne følgende komponenter:
             - Net Express Support for .NET
             - Workflow Capture Server
             - Support for IBM CICS, IMS AND JCL
             - Unix Option
             - XDB Relational database
 
             Klikk OK når installasjonen er ferdig..."
        $instructionsJob = Show-MessageBox -Message $instructions -Title "NetExpress Installasjon"
 
        # Run main installation
        Write-LogMessage "Kjører NetExpress hovedinstallasjon..." -NoNewline
        $netExpressMainPath = Join-Path $tempPath "NetExpressMain.exe"
        #$mainSetup =
        Start-Process -FilePath $netExpressMainPath -ArgumentList "/s" -Wait -PassThru
             
        # Close the instructions message box after installation completes
        Close-MessageBox -Job $instructionsJob
 
        # if ($mainSetup.ExitCode -ne 0) {
        #     Write-LogMessage "Mislyktes (Feilkode: $($mainSetup.ExitCode))" -ForegroundColor Red
        #     Write-ApplicationLog -AppName "NetExpress" -Status "Failed" -Message "Installation failed with exit code: $($mainSetup.ExitCode)"
        #     return
        # }
        Write-LogMessage "Vellykket!" -ForegroundColor Green
        Write-ApplicationLog -AppName "NetExpress" -Status "Success" -Message "Base installation completed successfully"   
        return $true
    }
    catch {
        Write-LogMessage "Mislyktes: $($_.Exception.Message)$(if($_.Exception.InnerException){" $($_.Exception.InnerException.Message)"})" -Level ERROR -Exception $_
        Write-ApplicationLog -AppName "NetExpress" -Status "Failed" -Message $("Installation failed with error: " + $_.Exception.Message + $(if ($_.Exception.InnerException) { " $($_.Exception.InnerException.Message)" }))
        return $false
    }
    finally {
        if ($instructionsJob) {
            Close-MessageBox -Job $instructionsJob
        }
    }
}
function NetExpressLicensing {
    param(
        [string]$AppName = "NetExpress",
        [string]$InstallPath = "C:\TEMPFK\TempInstallFiles\NetExpress51"
    )
    try {

        $registryPath = "HKLM:\SOFTWARE\Wow6432Node\Micro Focus\Licensing\4.0"
        if (Test-Path -Path $registryPath) {
            try {            
                $value = $(Get-ItemProperty -Path $registryPath -Name "GroupID").GroupID.ToString().Substring(0, 5)
            }
            catch {
                $value = ""
            }
            if ($value.ToString().StartsWith("endag")) {
                Write-LogMessage "Lisenskonfigurasjon allerede utført" -ForegroundColor Green
                Write-ApplicationLog -AppName "NetExpress" -Status "Progress" -Message "License already configured, skipping"
                return
            }
        }
        # Check if licensing is already configured
        # Configure licensing
        $licensingInstructions = @"
LISENSKONFIGURASJON:

1. Velg "Use Network Licensing -> Connection Wizard"
2. Legg inn følgende:
Server: sfk-erp-03
Katalog: /LS4
3. Trykk Neste
4. Legg inn:
GroupID: endag

Klikk OK når installasjonen er ferdig...
"@
        $licensingJob = Show-MessageBox -Message $licensingInstructions -Title "NetExpress Lisenskonfigurasjon"

        Write-LogMessage "Starter lisenskonfigurasjon..." -NoNewline
        Start-Process -FilePath "C:\Program Files (x86)\Micro Focus\Net Express 5.1\Base\Bin\LSWizard.exe" -Wait
        
        # Close licensing message box after configuration
        Close-MessageBox -Job $licensingJob

        Write-LogMessage "Vellykket!" -ForegroundColor Green
        Write-ApplicationLog -AppName "NetExpress" -Status "Progress" -Message "License configuration completed"
    }    
    catch {
        Write-LogMessage "Mislyktes: $($_.Exception.Message)$(if($_.Exception.InnerException){" $($_.Exception.InnerException.Message)"})" -Level ERROR -Exception $_
        Write-ApplicationLog -AppName "NetExpress" -Status "Failed" -Message $("Installation failed with error: " + $_.Exception.Message + $(if ($_.Exception.InnerException) { " $($_.Exception.InnerException.Message)" }))
    }
    finally {
        if ($licensingJob) {
            Close-MessageBox -Job $licensingJob
        }
    }
}
function NetExpressWp5_Install {
    param(
        [string]$AppName = "NetExpress",
        [string]$InstallPath = "C:\TEMPFK\TempInstallFiles\NetExpress51"
    )
    Write-LogMessage "Installerer WP5..." -NoNewline
    # install NetExpressWp5.msp using msiexec

    $wp5Setup = Start-Process -FilePath "$InstallPath\NetExpressWp5.msp" -Wait -PassThru
    if ($wp5Setup.ExitCode -ne 0 -and $wp5Setup.ExitCode -ne 3010) {
        Write-ApplicationLog -AppName $AppName -Status "Failed" -Message "WP5 installation failed with exit code: $($wp5Setup.ExitCode)"
        return $false
    }

    Write-LogMessage "Vellykket!" -ForegroundColor Green
    Write-ApplicationLog -AppName $AppName -Status "Success" -Message "WP5 installation completed successfully"
    return $true
}

function NetExpressWp6_Install {
    param(
        [string]$AppName = "NetExpress",
        [string]$InstallPath = "C:\TEMPFK\TempInstallFiles\NetExpress51"
    )
    Write-LogMessage "Installerer WP6..." -NoNewline
    $wp6Setup = Start-Process -FilePath "$InstallPath\NetExpressWp6.exe" -Wait -PassThru
    # Close WP6 message box after installation

    if ($wp6Setup.ExitCode -eq 0 -or $wp6Setup.ExitCode -eq 3010) {
        Write-LogMessage "Vellykket!" -ForegroundColor Green
        Write-ApplicationLog -AppName $AppName -Status "Success" -Message "All installations completed successfully"
        return $true
    }
    else {
        Write-LogMessage "Mislyktes (Feilkode: $($wp6Setup.ExitCode))" -Level ERROR
        Write-ApplicationLog -AppName $AppName -Status "Failed" -Message "WP6 installation failed with exit code: $($wp6Setup.ExitCode)"
        return $false
    }
}

function Get-NetExpressfiles {
    param(
        [string]$InstallPath = "C:\TEMPFK\TempInstallFiles\NetExpress51"
    )
    try {
        # Create temp directory only for updates
        if (-not (Test-Path -Path $installPath -PathType Container)) {
            New-Item -Path $installPath -ItemType Directory -Force | Out-Null
        }
        # Copy all installation files first
        Write-LogMessage "Kopierer NetExpress installasjonsfiler..." -NoNewline
        # Copy main installation files
        $mainSource = "C:\opt\src\DedgeSrc\DedgeSystemTools\Folders\DedgeCommon\Software\WindowsApps\MicroFocus NetExpress Pack"

        $result = Start-Robocopy -SourceFolder $mainSource -DestinationFolder $installPath -Recurse
        if ($result.OperationSuccessful) {
            Write-LogMessage "Vellykket!" -ForegroundColor Green
            Write-ApplicationLog -AppName $AppName -Status "Progress" -Message "All installation files copied successfully"
            return $true
        }
        else {
            Write-LogMessage "Mislyktes (Feilkode: $($result.RobocopyExitCode) - $($result.ResultMessage))" -Level ERROR     
            Write-ApplicationLog -AppName $AppName -Status "Failed" -Message $("Installation failed with exit code: " + $result.RobocopyExitCode + " - " + $result.ResultMessage)
            return $false
        }

    }
    catch {
        Write-LogMessage "Mislyktes" -Level ERROR -Exception $_
        Write-ApplicationLog -AppName $AppName -Status "Failed" -Message $("Installation failed with error: " + $_.Exception.Message + $(if ($_.Exception.InnerException) { " $($_.Exception.InnerException.Message)" }))
        return $false
    }
}

function Install-NetExpressPrimary {
    param(
        [string]$AppName = "NetExpress",
        [switch]$Force
    )
    Write-LogMessage "Installerer $AppName..." -NoNewline
    Write-ApplicationLog -AppName $AppName -Status "Started" -Message "Installation started"
    $filesCopied = $false
    $isInstalledNow = $false
    $wasInstalledOnStart = $false   

    try {
        if ($Force -eq $true) {
            Write-LogMessage "$($AppName) will be reinstalled due to Force flag" -Level INFO
        }
        else {
            Write-LogMessage "$($AppName) will be installed" -Level INFO
        }
        # Check if NetExpress is already installed before doing anything else
        $netExpressPath = "C:\Program Files (x86)\Micro Focus\Net Express 5.1\Base\Bin\run.exe"
        $wasInstalledOnStart = Test-Path -Path $netExpressPath -PathType Leaf

        
        # Create temp directory only for updates
        $installPath = "C:\TEMPFK\TempInstallFiles\NetExpress51"
        $filesCopied = Get-NetExpressfiles -InstallPath $installPath
        $vcredist2010x64 = Join-Path $installPath "vcredist_x64.exe"
        $vcredist2010x86 = Join-Path $installPath "vcredist_x86.exe"

        Write-LogMessage "Installerer Visual C++ 2010 x64 Redistributable..." -NoNewline
        Start-Process -FilePath $vcredist2010x64 -ArgumentList "/q" -Wait
        
        Write-LogMessage "Installerer Visual C++ 2010 x86 Redistributable..." -NoNewline
        Start-Process -FilePath $vcredist2010x86 -ArgumentList "/q" -Wait
        

        if (-not $wasInstalledOnStart -or $Force -eq $true) {
            $filesCopied = Get-NetExpressfiles -InstallPath $installPath
            if ($filesCopied) {
                $result = NetExpressMain -AppName $AppName -InstallPath $installPath
                if ($result -eq $false) {
                    throw "NetExpress installation failed"
                }
                $isInstalledNow = Test-Path -Path $netExpressPath -PathType Leaf
            }
        }
        else {
            Write-LogMessage "Allerede installert" -ForegroundColor Green
            Write-ApplicationLog -AppName $AppName -Status "Progress" -Message "NetExpress already installed, proceeding with updates"
        }

        NetExpressLicensing -AppName $AppName -InstallPath $installPath

        $instructions = @"
Bruk følgende på spørsmål om serienummer og work order:
User Name: FKA
        Company Name: FKA
        Serial: 743162
        W.O. Number: 317078

        Husk å fjerne følgende komponenter:
        - Net Express Support for .NET
        - Workflow Capture Server
        - Support for IBM CICS, IMS AND JCL
        - Unix Option
        - XDB Relational database        

    VIKTIG INFORMASJON:
    Om man får spørsmål om fjerne lisensen, velg "Retain"

    Installasjonen vil fortsette automatisk...
"@
        if ($isInstalledNow) {
            $result = "WP5 og WP6"
        }
        else {
            Write-LogMessage "Vil du oppdatere til WP5 eller WP6?" -Level WARN
            $options = @("WP5 og WP6", "WP6", "Bare konfigurere", "Avbryt")
            $result = $null
            while ($null -eq $result) {
                Clear-Host
                Write-Host "NetExpress Oppdatering" -ForegroundColor Yellow
                Write-Host "Vil du oppdatere til WP5 eller WP6?"
                Write-Host ""
                for ($i = 0; $i -lt $options.Length; $i++) {
                    Write-Host "$($i + 1). $($options[$i])"
                }
                Write-Host ""
                $choice = Read-Host "Velg et alternativ (1-$($options.Length))"
                if ($choice -match '^\d+$' -and [int]$choice -ge 1 -and [int]$choice -le $options.Length) {
                    $result = $options[[int]$choice - 1]
                }
            }
        }

        if ($result -eq "WP5 og WP6") {
            if (-not $filesCopied) {
                $filesCopied = Get-NetExpressfiles -InstallPath $installPath
            }
            $messageBoxJob = Show-MessageBox -Message $instructions -Title "NetExpress WP5/6 Installasjon"

            # Show WP6 instructions before WP6 installation
            $result = NetExpressWp5_Install -AppName $AppName -InstallPath $installPath
            if ($result -eq $false) {
                throw "WP5 installation failed"
            }
            $result = NetExpressWp6_Install -AppName $AppName -InstallPath $installPath
            if ($result -eq $false) {
                throw "WP6 installation failed"
            }
            Close-MessageBox -Job $messageBoxJob
            Set-NetExpressConfig
        }
        elseif ($result -eq "WP6") {
            if (-not $filesCopied) {
                $filesCopied = Get-NetExpressfiles -InstallPath $installPath
            }
            $messageBoxJob = Show-MessageBox -Message $instructions -Title "NetExpress WP5/6 Installasjon"

            $result = NetExpressWp6_Install -AppName $AppName -InstallPath $installPath
            if ($result -eq $false) {
                throw "WP6 installation failed"
            }
            Close-MessageBox -Job $messageBoxJob
            Set-NetExpressConfig
        }
        elseif ($result -eq "Bare konfigurere") {
            Set-NetExpressConfig
        }
        else {
            Write-LogMessage "Avbryter" -Level WARN
            Write-ApplicationLog -AppName $AppName -Status "Warning" -Message "Installation cancelled"
        }


    }
    catch {
        # Make sure to close any remaining message boxes in case of error
        Write-LogMessage "Mislyktes" -Level ERROR -Exception $_
        Write-ApplicationLog -AppName $AppName -Status "Failed" -Message $("Installation failed with error: " + $_.Exception.Message + $(if ($_.Exception.InnerException) { " $($_.Exception.InnerException.Message)" }))
    }
    finally {
        # Only close message boxes if they exist
        if ($messageBoxJob) { 
            Close-MessageBox -Job $messageBoxJob 
        }
    }
}

function Install-NetExpressNoForce {
    param(
        [string]$AppName = "NetExpress"
    )
    Install-NetExpressPrimary -AppName $AppName 
}

function Install-NetExpressForce {
    param(
        [string]$AppName = "NetExpress"
    )
    Install-NetExpressPrimary -AppName $AppName -Force
}

function Install-MicroFocusServerPack {
    param(
        [string]$AppName = "MicroFocus Server Pack"
    )
    Write-LogMessage "Installerer $AppName..." -NoNewline
    Write-ApplicationLog -AppName $AppName -Status "Started" -Message "Installation started"
    try {
        # Check if NetExpress is already installed before doing anything else
        $netExpressPath = "C:\Program Files (x86)\Micro Focus\Server 5.1\Bin\run.exe"
        $isInstalled = Test-Path -Path $netExpressPath -PathType Leaf

        # Create temp directory only for updates
        $installPath = "C:\TEMPFK\TempInstallFiles\MicroFocusServerPack"
        if (-not (Test-Path -Path $installPath -PathType Container)) {
            New-Item -Path $installPath -ItemType Directory -Force | Out-Null
        }
        # Copy all installation files first
        Write-LogMessage "Kopierer MicroFocus Server Pack installasjonsfiler..." -NoNewline
        # Copy main installation files
        $mainSource = "C:\opt\src\DedgeSrc\DedgeSystemTools\Folders\DedgeCommon\Software\WindowsApps\MicroFocus Server Pack"
        $result = Start-Robocopy -SourceFolder $mainSource -DestinationFolder $installPath -Recurse
        if ($result.OperationSuccessful) {
            Write-LogMessage "Vellykket!" -ForegroundColor Green
            Write-ApplicationLog -AppName $AppName -Status "Progress" -Message "All installation files copied successfully"
            return $true
        }
        else {
            Write-LogMessage "Mislyktes (Feilkode: $($result.RobocopyExitCode) - $($result.ResultMessage))" -Level ERROR     
            Write-ApplicationLog -AppName $AppName -Status "Failed" -Message $("Installation failed with exit code: " + $result.RobocopyExitCode + " - " + $result.ResultMessage)
            return $false
        }
        if ($isInstalled) {
            Write-LogMessage "Allerede installert" -ForegroundColor Green
            Write-ApplicationLog -AppName $AppName -Status "Progress" -Message "NetExpress already installed, proceeding with updates"
        }
        else {
            $messageBoxInstructions = @"
IMPORTANT INFORMATION:
You must install Microsoft .Net Framework 3.5 before installing Micro Focus Server Pack.

- Customer Information:
    - User Name: FKA
    - Company Name: FKA
    - Serial Number: 600000015516
    - W.O. Number: 399869

- License Information:
    - Serial Number: 600000015516
    - License Number: 01280 10001 F4923 C3C04 3271

- Custom Setup:
    - Uncheck: "Enterprise Server"
    - Uncheck: "Support for IBM CICS, IMS and JCL"
- Then just click Next, Install and Finish.

Installation will continue automatically...
"@

            Write-Host $messageBoxInstructions
            $messageBoxJob = Show-MessageBox -Message $messageBoxInstructions -Title "Micro Focus Server Pack Installation"   
            $executable = "Micro Focus Server 5.1 Full (SRP3251000157).exe"
            $execPath = "$InstallPath\$executable"
            Write-LogMessage "Kjører $execPath" -Level INFO
            
            if (-not (Start-InstallProcess -AppName $AppName -InstallerPath $execPath)) {
                Write-ApplicationLog -AppName $AppName -Status "Failed" -Message "WP5 installation failed with exit code: $($wp5Setup.ExitCode)"
                return $false
            }
            if ($messageBoxJob) {
                Close-MessageBox -Job $messageBoxJob    
            }
        }
    
        $messageBoxInstructions = "Just click Next, Install and Finish."
        Write-ApplicationLog -AppName $AppName -Status "Progress" -Message "Starting WrapPack installation"

        $messageBoxJob = Show-MessageBox -Message $messageBoxInstructions -Title "Micro Focus Server Pack Installation"   
        $executable = "Micro Focus Server 5.1 WrapPack #16 (srp3251060079).msp"
        $execPath = "$InstallPath\$executable"
        Write-LogMessage "Kjører $execPath" -Level INFO
        if (-not (Start-InstallProcess -AppName $AppName -InstallerPath $execPath)) {
            Write-ApplicationLog -AppName $AppName -Status "Failed" -Message "WP5 installation failed"
            return $false
        }
        if ($messageBoxJob) {
            Close-MessageBox -Job $messageBoxJob    
        }
        Write-ApplicationLog -AppName $AppName -Status "Completed" -Message "All installations completed successfully"
        return $true
    }
    catch {
        # Make sure to close any remaining message boxes in case of error
        Write-LogMessage "Mislyktes" -Level ERROR -Exception $_
        Write-ApplicationLog -AppName $AppName -Status "Failed" -Message $("Installation failed with error: " + $_.Exception.Message + $(if ($_.Exception.InnerException) { " $($_.Exception.InnerException.Message)" }))
    }
    finally {
        # Only close message boxes if they exist
        if ($messageBoxJob) {
            Close-MessageBox -Job $messageBoxJob
        }
    }
}



function Install-Spf {      
    param(
        [string]$AppName = "SPF Editor"
    )
    Write-LogMessage "Installerer $AppName..." -NoNewline
    Write-ApplicationLog -AppName $AppName -Status "Started" -Message "Installation started"
    try {
        $installPath = "C:\SPFSE"
        Add-Folder -Path $installPath -AdditionalAdmins @("$env:USERDOMAIN\$env:USERNAME")

        # Verify source path exists
        $sourcePath = "C:\opt\src\DedgeSrc\DedgeSystemTools\Folders\DedgeCommon\Software\WindowsApps\SPF Editor\spfse"
        if (-not (Test-Path -Path $sourcePath -PathType Container)) {
            throw "Finner ikke installasjonsfiler på $sourcePath"
        }

        # Copy installation files
        Write-LogMessage "Kopierer installasjonsfiler..." -NoNewline
        $result = Start-Robocopy -SourceFolder $sourcePath -DestinationFolder $installPath -Recurse
        if ($result.OperationSuccessful) {
            Write-LogMessage "Vellykket!" -ForegroundColor Green
            Write-ApplicationLog -AppName $AppName -Status "Progress" -Message "Installation files copied successfully"
            return $true
        }
        else {
            Write-LogMessage "Mislyktes (Feilkode: $($result.RobocopyExitCode) - $($result.ResultMessage))" -Level ERROR     
            Write-ApplicationLog -AppName $AppName -Status "Failed" -Message $("Installation failed with exit code: " + $result.RobocopyExitCode + " - " + $result.ResultMessage)
            return $false
        }
    }
    catch { 
        if (-not (Install-Check -exeName "spfse.exe" -AppName $AppName)) {
            Write-LogMessage "Mislyktes: $($_.Exception.Message)$(if($_.Exception.InnerException){" $($_.Exception.InnerException.Message)"})" -Level ERROR -Exception $_
            Write-ApplicationLog -AppName $AppName -Status "Failed" -Message $("Installation failed with error: " + $_.Exception.Message + $(if ($_.Exception.InnerException) { " $($_.Exception.InnerException.Message)" }))
        }
        return $null
    }
}

function Install-AspNetCoreHosting {
    param(
        [string]$AppName = "ASP.NET Core Hosting Bundle"
    )
    Write-LogMessage "Installerer $AppName..." -NoNewline
    try {
        # Implementation needed
        # Download ASP.NET Core Hosting Bundle
        $installPath = "C:\TEMPFK\TempInstallFiles\AspNetCore"
        if (-not (Test-Path -Path $installPath -PathType Container)) {
            New-Item -Path $installPath -ItemType Directory -Force | Out-Null
        }

        # Download latest .NET 8 Hosting Bundle
        $downloadUrl = "https://download.visualstudio.microsoft.com/download/pr/98ff0a08-a283-428f-8e54-19841d97154c/8c7d5f9600eadf264f04c82c813b7aab/dotnet-hosting-8.0.2-win.exe"
        $installerPath = Join-Path $installPath "dotnet-hosting-8.0.2-win.exe"
        
        Write-LogMessage "Laster ned installasjonsfil..." -NoNewline
        Invoke-WebRequest -Uri $downloadUrl -OutFile $installerPath
        Write-LogMessage "Vellykket!" -ForegroundColor Green
        Write-ApplicationLog -AppName $AppName -Status "Progress" -Message "Installation files downloaded successfully"

        # Install Hosting Bundle
        Write-LogMessage "Installerer..." -NoNewline
        $process = Start-Process -FilePath $installerPath -ArgumentList "/quiet /norestart" -Wait -PassThru

        if ($process.ExitCode -ne 0 -and $process.ExitCode -ne 3010) {
            Write-LogMessage "Mislyktes (Feilkode: $($process.ExitCode))" -Level ERROR
            Write-ApplicationLog -AppName $AppName -Status "Failed" -Message "Installation failed with exit code: $($process.ExitCode)"
            return
        }

        Write-LogMessage "Vellykket!" -ForegroundColor Green
        Write-ApplicationLog -AppName $AppName -Status "Success" -Message "Installation completed successfully"
        Write-LogMessage "Not implemented!" -ForegroundColor Yellow
        Write-ApplicationLog -AppName $AppName -Status "Warning" -Message "Installation not implemented"
    }
    catch { 
        if (-not (Install-Check -exeName "dotnet.exe" -AppName $AppName)) {
            Write-LogMessage "Mislyktes: $($_.Exception.Message)$(if($_.Exception.InnerException){" $($_.Exception.InnerException.Message)"})" -Level ERROR -Exception $_
            Write-ApplicationLog -AppName $AppName -Status "Failed" -Message $("Installation failed with error: " + $_.Exception.Message + $(if ($_.Exception.InnerException) { " $($_.Exception.InnerException.Message)" }))
        }
    }
}

function Install-BatchFileAndGetExecutable {
    param(
        [Parameter(Mandatory = $true)]
        [string]$AppPath,
        [Parameter(Mandatory = $true)] 
        [string]$AppName,
        [Parameter(Mandatory = $false)]
        [bool]$ReturnExecutablePath = $false,
        [Parameter(Mandatory = $false)]
        [string]$RemotePath = ""
    )

    foreach ($file in (Get-ChildItem -Path $AppPath -Filter "*.QuickRun.bat")) {
        $cmdPath = $file.Name.Replace(".QuickRun.bat", ".bat")
        $quickRunPath = $env:OptPath + "\QuickRun"
        Write-LogMessage "Found $cmdPath" -Level INFO
        Copy-Item -Path $file.FullName -Destination "$quickRunPath\$cmdPath" -Force
        Write-LogMessage "$cmdPath is now globally available" -Level INFO
    }
    # if (Test-Path $cmdPath -PathType Leaf) {
    #     $quickRunPath = $env:OptPath + "\QuickRun"

    #     Write-LogMessage "$AppName.QuickRun.bat found in $AppPath" -Level INFO
    #     Copy-Item -Path $cmdPath -Destination "$env:OptPath\QuickRun" -Force
    #     Copy-Item -Path $cmdPath -Destination "$quickRunPath" -Force
    #     Write-LogMessage "$AppName.bat is now globally available" -Level INFO
    # }

    # $cmdPath = $cmdPath.Replace(".bat", ".cmd") 
    # Remove-Item -Path $cmdPath -Force -ErrorAction SilentlyContinue | Out-Null

    # if ($ReturnExecutablePath) {
    #     $executablePath = "$AppPath\$AppName.ps1"
    #     if (Test-Path $executablePath -PathType Leaf) {
    #         return $executablePath
    #     }
    #     else {
    #         Write-LogMessage "Executable not found at $executablePath" -Level ERROR
    #         return $null
    #     }
    # }
    
}

# function Install-BatchFileRemoteToQuickRun {
#     param(
#         [Parameter(Mandatory = $true)]
#         [string]$AppPath,
#         [Parameter(Mandatory = $true)] 
#         [string]$AppName,
#         [Parameter(Mandatory = $false)]
#         [string]$ComputerName = "",
#         [Parameter(Mandatory = $false)]
#         [string]$ApplicationTechnologyFolderName = "DedgePshApps"

#     )

#     $localPath = "$env:OptPath\$ApplicationTechnologyFolderName\$AppName"
#     $localSourcePath = "$env:OptPath\$ApplicationTechnologyFolderName\$AppName"
#     $remotePath = "\\$ComputerName\opt\$ApplicationTechnologyFolderName\$AppName"
#     $remoteQuickRunPath = "\\$ComputerName\opt\QuickRun"


#     if (-not (Test-Path $localPath -PathType Container) -or -not (Test-Path $remotePath -PathType Container) -or -not (Test-Path $remoteQuickRunPath -PathType Container)) {
#         Write-LogMessage "Path not found: $localPath or $remotePath or $remoteQuickRunPath" -Level WARN
#         return
#     }


#     $cmdPath = "$localPath\$AppName.bat"
#     if (Test-Path $cmdPath -PathType Leaf) {
#         $quickRunPath = $env:OptPath + "\QuickRun"

#         Write-LogMessage "$AppName.bat found in $AppPath" -Level INFO
#         Copy-Item -Path $cmdPath -Destination "$env:OptPath\QuickRun" -Force
#         Copy-Item -Path $cmdPath -Destination "$quickRunPath" -Force
#         Write-LogMessage "$AppName.bat is now globally available" -Level INFO
#     }

#     $cmdPath = $cmdPath.Replace(".bat", ".cmd") 
#     Remove-Item -Path $cmdPath -Force -ErrorAction SilentlyContinue | Out-Null

#     if ($ReturnExecutablePath) {
#         $executablePath = "$AppPath\$AppName.ps1"
#         if (Test-Path $executablePath -PathType Leaf) {
#             return $executablePath
#         }
#         else {
#             Write-LogMessage "Executable not found at $executablePath" -Level ERROR
#             return $null
#         }
#     }
    
# }

function Install-OurPshAppSlave {
    param (
        [Parameter(Mandatory = $true)]
        [string]$AppName,
        [Parameter(Mandatory = $false)]
        [bool]$ReturnExecutablePath = $false,
        [Parameter(Mandatory = $false)]
        [switch]$SkipReInstall
    )

    $currentLocation = Get-Location
    $appPath = "$env:OptPath\DedgePshApps\$AppName"
    $appSourcePath = "$(Get-PowershellDefaultAppsPath)\$AppName"

    Write-LogMessage "AppPath: $($appPath)" -Level TRACE
    Write-LogMessage "AppSourcePath: $($appSourcePath)" -Level TRACE

    if (-not (Test-Path $appSourcePath -PathType Container)) {
        Write-LogMessage "$($AppName) does not exist in $($appSourcePath)" -Level WARN
        return
    }

    if (-not (Test-Path $appPath -PathType Container)) {
        New-Item -Path $appPath -ItemType Directory -ErrorAction SilentlyContinue | Out-Null
    }

    $null = Start-Robocopy -SourceFolder $appSourcePath -DestinationFolder $appPath -Recurse -NoPurge -QuietMode
    Write-LogMessage "$($AppName) application deployed to $($appPath)" -Level INFO
  
    # Internal function to handle batch file deployment and executable path return
    $executablePath = Install-BatchFileAndGetExecutable -AppPath $appPath -AppName $AppName -ReturnExecutablePath $ReturnExecutablePath
    Write-LogMessage "ExecutablePath: $executablePath" -Level TRACE
    # Check for and run _install.ps1 if it exists
    if (-not $SkipReInstall) {
        $installScript = Join-Path $appPath "_install.ps1"
        Write-LogMessage "InstallScript: $installScript" -Level TRACE
        if (Test-Path $installScript -PathType Leaf) {
            Write-LogMessage "Found _install.ps1 script, executing..." -Level INFO
            try {
                Set-Location $appPath
                Write-LogMessage "Executing _install.ps1 script..." -Level TRACE
                & $installScript
                Write-LogMessage "_install.ps1 script executed successfully" -Level INFO
            }
            catch {
                Write-LogMessage "Error executing _install.ps1 script: $_" -Level ERROR
            }
        }
        else {
            Write-LogMessage "$($AppName) has no _install.ps1 script, skipping post-install step" -Level TRACE
        }
    }
    Write-LogMessage "CurrentLocation: $currentLocation" -Level TRACE
    Set-Location $currentLocation
    if ($ReturnExecutablePath) {
        Write-LogMessage "Returning executable path: $executablePath" -Level TRACE
        $returnPath = $executablePath
    }
    else {
        Write-LogMessage "Returning app path: $appPath" -Level TRACE
        $returnPath = $appPath
    }

    return $returnPath
}

function Install-OurPshApp {
    <#
    .SYNOPSIS
        Installs a Dedge PowerShell application.
    .PARAMETER AppName
        The name of the PowerShell application to install.
    .PARAMETER ReturnExecutablePath
        If true, returns the path to the installed executable.
    .PARAMETER SkipReInstall
        Skip running _install.ps1 if it exists.
    .PARAMETER AddToStartup
        Add the application to Windows startup (Run at login) for the current user.
    .PARAMETER DisplayName
        Display name for the startup entry. Defaults to AppName.
    #>
    param (
        [Parameter(Mandatory = $true)]
        [string]$AppName,
        [Parameter(Mandatory = $false)]
        [bool]$ReturnExecutablePath = $false,
        [Parameter(Mandatory = $false)]
        [switch]$SkipReInstall,
        [Parameter(Mandatory = $false)]
        [switch]$AddToStartup,
        [Parameter(Mandatory = $false)]
        [string]$DisplayName = "",
        [Parameter(Mandatory = $false)]
        [switch]$CalledByInitMachine = $false
    )
    # Safe logging helper - falls back to Write-Host if Write-LogMessage is unavailable


    $result = $null
    try {
        if ($AppName.ToLower() -ne "commonmodules" -and -not $CalledByInitMachine) {
            $null = Install-OurPshAppSlave -AppName "CommonModules" -SkipReInstall:$SkipReInstall
        }
        $result = Install-OurPshAppSlave -AppName $AppName -SkipReInstall:$SkipReInstall -ReturnExecutablePath:$ReturnExecutablePath

        # Add to Windows startup if requested
        if ($AddToStartup) {
            $appPath = "$env:OptPath\DedgePshApps\$AppName"
            $scriptPath = "$appPath\$AppName.ps1"
        
            # Find PowerShell 7 (pwsh) path - prefer Program Files installation
            $pwshPath = $null
            $pwshLocations = @(
                "$env:ProgramFiles\PowerShell\7\pwsh.exe",
                "$env:ProgramFiles\PowerShell\7-preview\pwsh.exe",
                (Get-Command pwsh -ErrorAction SilentlyContinue)?.Source
            )
            foreach ($loc in $pwshLocations) {
                if (-not [string]::IsNullOrEmpty($loc) -and (Test-Path $loc -PathType Leaf)) {
                    $pwshPath = $loc
                    break
                }
            }

            if ($null -eq $pwshPath) {
                Write-LogMessage "PowerShell 7 (pwsh) not found - cannot add to startup" -Level WARN
            }
            elseif (Test-Path $scriptPath -PathType Leaf) {
                # Use PowerShell 7 with hidden window for startup
                $startupCommand = "`"$pwshPath`" -NoProfile -WindowStyle Hidden -ExecutionPolicy Bypass -File `"$scriptPath`""
            
                $startupRegPath = "HKCU:\Software\Microsoft\Windows\CurrentVersion\Run"
                $startupName = if ([string]::IsNullOrEmpty($DisplayName)) { $AppName } else { $DisplayName }
                try {
                    Set-ItemProperty -Path $startupRegPath -Name $startupName -Value $startupCommand
                    Write-LogMessage "$($startupName) added to 'Run at startup' for current user (using pwsh)" -Level INFO
                }
                catch {
                    Write-LogMessage "Failed to add $($startupName) to startup: $($_.Exception.Message)" -Level WARN
                }
            }
            else {
                Write-LogMessage "Cannot add to startup - script not found: $($scriptPath)" -Level WARN
            }
        }
    }
    catch {
        Write-LogMessage "Error installing $($AppName): $_" -Level ERROR
    }

    return $result
}
function Remove-OurPshApp {
    param (
        [Parameter(Mandatory = $true)]
        [string]$AppName
    )
  
    $appPath = "$env:OptPath\DedgePshApps\$AppName" 
    # Check for and run _uninstall.ps1 if it exists
    $uninstallScript = Join-Path $appPath "_uninstall.ps1"
    if (Test-Path $uninstallScript -PathType Leaf) {
        Write-LogMessage "Found _uninstall.ps1 script, executing..." -Level INFO
        try {
            & $uninstallScript
            Write-LogMessage "_uninstall.ps1 script executed successfully" -Level INFO
        }
        catch {
            Write-LogMessage "Error executing _uninstall.ps1 script: $_" -Level ERROR
        }
    }
    if (Test-Path $appPath -PathType Container) {
        Remove-Item -Path $appPath -Recurse -Force
        Write-LogMessage "$AppName application removed from $appPath" -Level INFO
    }
    else {
        Write-LogMessage "$AppName application not found at $appPath" -Level WARN
    }
    
}
function UnInstall-OurPshApp {
    param (
        [Parameter(Mandatory = $true)]
        [string]$AppName
    )
    Remove-OurPshApp -AppName $AppName
}
  

function Install-OurWinApp {
    <#
    .SYNOPSIS
        Installs a Dedge Windows application and creates shortcuts.
    .PARAMETER AppName
        The name of the Windows application to install.
    .PARAMETER ReturnExecutablePath
        If true, returns the path to the installed executable.
    .PARAMETER SkipReInstall
        Skip running _install.ps1 if it exists.
    .PARAMETER StartMenuFolder
        Folder name for Start Menu shortcut. Defaults to Organization.ShortName from Get-CommonSettings.
    .PARAMETER IconPath
        Path to icon file for shortcuts. Defaults to Organization.IconUncPath from Get-CommonSettings.
    .PARAMETER SkipShortcuts
        Skip creating Desktop and Start Menu shortcuts.
    .PARAMETER DisplayName
        Display name for the shortcut. Defaults to AppName.
    .PARAMETER AddToStartup
        Add the application to Windows startup (Run at login) for the current user.
    #>
    param (
        [Parameter(Mandatory = $true)]
        [string]$AppName,
        [Parameter(Mandatory = $false)]
        [bool]$ReturnExecutablePath = $false,
        [Parameter(Mandatory = $false)]
        [switch]$SkipReInstall,
        [Parameter(Mandatory = $false)]
        [string]$StartMenuFolder = "",
        [Parameter(Mandatory = $false)]
        [string]$IconPath = "",
        [Parameter(Mandatory = $false)]
        [switch]$SkipShortcuts,
        [Parameter(Mandatory = $false)]
        [string]$DisplayName = "",
        [Parameter(Mandatory = $false)]
        [switch]$AddToStartup
    )
    
    $appPath = "$env:OptPath\DedgeWinApps\$AppName"
    if (-not (Test-Path $appPath -PathType Container)) {
        New-Item -Path $appPath -ItemType Directory | Out-Null
    }
    $appSourcePath = $(Get-WindowsDefaultAppsPath) + "\$AppName"

    # ── Stop/kill any running instance BEFORE copying files ───────────────────────
    # Robocopy fails to overwrite locked files if the previous version is still running.
    # We stop the Windows service (if registered) and kill any matching process now,
    # before the copy, so all file handles are released. This applies to both service
    # apps and standard exe apps.
    $preExistingExe = Get-ChildItem -Path $appPath -Filter "*.exe" -File -ErrorAction SilentlyContinue |
        Where-Object { $_.DirectoryName -eq $appPath } | Select-Object -First 1

    # Stop Windows service named $AppName if it exists
    $preExistingSvc = Get-Service -Name $AppName -ErrorAction SilentlyContinue
    if ($preExistingSvc) {
        if ($preExistingSvc.Status -eq 'Running') {
            Write-LogMessage "$($AppName): Stopping running service before file update..." -Level INFO
            Stop-Service -Name $AppName -Force -ErrorAction SilentlyContinue
            Start-Sleep -Seconds 2
        }
        else {
            Write-LogMessage "$($AppName): Service exists but is not running (status: $($preExistingSvc.Status))" -Level DEBUG
        }
    }

    # Kill any process whose name matches the existing exe in the install folder
    if ($preExistingExe) {
        $procName = [System.IO.Path]::GetFileNameWithoutExtension($preExistingExe.FullName)
        $running = Get-Process -Name $procName -ErrorAction SilentlyContinue
        if ($running) {
            Write-LogMessage "$($AppName): Killing $($running.Count) running process(es) '$($procName)' before file update..." -Level INFO
            $running | ForEach-Object { try { $_.Kill(); $_.WaitForExit(3000) } catch {} }
        }
    }
    # ─────────────────────────────────────────────────────────────────────────────

    # Copy-Item -Path $appSourcePath\* -Destination $appPath -Recurse -Force
    $null = Start-Robocopy -SourceFolder $appSourcePath -DestinationFolder $appPath -Recurse -NoPurge -QuietMode
    Write-LogMessage "$AppName application deployed to $appPath" -Level INFO

    # Get default settings for shortcuts if not provided
    if (-not $SkipShortcuts) {
        $settings = $null
        try {
            $settings = Get-CommonSettings
        }
        catch {
            Write-LogMessage "Could not retrieve common settings for defaults: $($_.Exception.Message)" -Level DEBUG
        }

        # Default StartMenuFolder from Organization.ShortName
        if ([string]::IsNullOrEmpty($StartMenuFolder) -and $null -ne $settings) {
            try {
                $StartMenuFolder = $settings.Organization.ShortName
                Write-LogMessage "Using default Start Menu folder from settings: $StartMenuFolder" -Level DEBUG
            }
            catch {
                Write-LogMessage "Could not get Organization.ShortName from settings" -Level DEBUG
            }
        }

        # Default IconPath from Organization.IconUncPath
        if ([string]::IsNullOrEmpty($IconPath) -and $null -ne $settings) {
            try {
                $IconPath = $settings.Organization.IconUncPath
                Write-LogMessage "Using default icon from settings: $IconPath" -Level DEBUG
            }
            catch {
                Write-LogMessage "Could not get Organization.IconUncPath from settings" -Level DEBUG
            }
        }

        # Default DisplayName to AppName
        if ([string]::IsNullOrEmpty($DisplayName)) {
            $DisplayName = $AppName
        }
    }
  
    # Check if <appname>.exe exists in app deployment path
    $exePath = "$appPath\$AppName.exe"
    if (Test-Path $exePath -PathType Leaf) {
        Write-LogMessage "$AppName.exe found in $appPath" -Level INFO

        if (-not $SkipShortcuts) {
            # Resolve the icon path with fallbacks
            $shortcutIconPath = $null
            
            # Try 1: Use provided/settings IconPath if accessible
            if (-not [string]::IsNullOrEmpty($IconPath)) {
                if (Test-Path $IconPath -PathType Leaf) {
                    $shortcutIconPath = $IconPath
                    Write-LogMessage "Using icon from settings: $shortcutIconPath" -Level DEBUG
                }
                else {
                    Write-LogMessage "Icon path from settings not accessible: $IconPath" -Level DEBUG
                }
            }
            
            # Try 2: Check for dedge.ico in the app directory
            if ([string]::IsNullOrEmpty($shortcutIconPath)) {
                $localIconPath = Join-Path $appPath "dedge.ico"
                if (Test-Path $localIconPath -PathType Leaf) {
                    $shortcutIconPath = $localIconPath
                    Write-LogMessage "Using local dedge.ico from app directory: $shortcutIconPath" -Level DEBUG
                }
            }
            
            # Try 3: Copy icon from UNC path to local app directory if accessible
            if ([string]::IsNullOrEmpty($shortcutIconPath) -and -not [string]::IsNullOrEmpty($IconPath)) {
                try {
                    $localIconPath = Join-Path $appPath "dedge.ico"
                    Copy-Item -Path $IconPath -Destination $localIconPath -Force -ErrorAction Stop
                    $shortcutIconPath = $localIconPath
                    Write-LogMessage "Copied icon from UNC to local: $shortcutIconPath" -Level DEBUG
                }
                catch {
                    Write-LogMessage "Could not copy icon from UNC path: $($_.Exception.Message)" -Level DEBUG
                }
            }
            
            # Fallback: Use the executable itself
            if ([string]::IsNullOrEmpty($shortcutIconPath)) {
                $shortcutIconPath = $exePath
                Write-LogMessage "Using executable as icon (fallback): $shortcutIconPath" -Level DEBUG
            }

            # Create Desktop shortcut
            try {
                Add-DesktopShortcut -TargetPath $exePath -ShortcutName $DisplayName -IconPath $shortcutIconPath -RunAsAdmin:$false
                Write-LogMessage "$DisplayName is now available on the desktop" -Level INFO
            }
            catch {
                Write-LogMessage "Failed to create desktop shortcut for $($DisplayName): $($_.Exception.Message)" -Level WARN
            }

            # Create Start Menu shortcut
            try {
                # Determine Start Menu Programs folder
                $startMenuProgramsPath = Join-Path -Path $env:APPDATA -ChildPath "Microsoft\Windows\Start Menu\Programs"
                
                # Create subfolder if StartMenuFolder is specified
                if (-not [string]::IsNullOrEmpty($StartMenuFolder)) {
                    $startMenuFolderPath = Join-Path -Path $startMenuProgramsPath -ChildPath $StartMenuFolder
                    if (-not (Test-Path $startMenuFolderPath -PathType Container)) {
                        New-Item -Path $startMenuFolderPath -ItemType Directory -Force | Out-Null
                        Write-LogMessage "Created Start Menu folder: $startMenuFolderPath" -Level DEBUG
                    }
                    $startMenuShortcutPath = Join-Path -Path $startMenuFolderPath -ChildPath "$DisplayName.lnk"
                }
                else {
                    $startMenuShortcutPath = Join-Path -Path $startMenuProgramsPath -ChildPath "$DisplayName.lnk"
                }

                # Note: $shortcutIconPath already resolved above with fallbacks
                # IconLocation format must be "path,index" - use index 0 for .ico files
                $iconLocationValue = "$shortcutIconPath,0"

                # Create the shortcut using WScript.Shell COM object
                $wshShell = New-Object -ComObject WScript.Shell
                $shortcut = $wshShell.CreateShortcut($startMenuShortcutPath)
                $shortcut.TargetPath = $exePath
                $shortcut.WorkingDirectory = Split-Path $exePath
                $shortcut.IconLocation = $iconLocationValue
                $shortcut.Description = "$DisplayName - Dedge Application"
                $shortcut.Save()

                Write-LogMessage "$DisplayName added to Start Menu: $startMenuShortcutPath" -Level INFO
            }
            catch {
                Write-LogMessage "Failed to create Start Menu shortcut for $($DisplayName): $($_.Exception.Message)" -Level WARN
            }
        }
    }

    # ── Windows Service auto-detection and registration ──────────────────────────
    # Detection: presence of Microsoft.Extensions.Hosting.WindowsService*.dll in the
    # app root means the exe calls UseWindowsService() and must run as a Windows service.
    #
    # Regex explanation for the dll name pattern used by Get-ChildItem -Filter:
    #   Microsoft.Extensions.Hosting.WindowsService*.dll
    #   ^-- literal prefix                              ^-- wildcard covers both
    #       "WindowsService.dll" and "WindowsServices.dll" (naming varies by SDK version)
    $serviceInstalled = $false
    $winSvcDll = Get-ChildItem -Path $appPath -Filter "Microsoft.Extensions.Hosting.WindowsService*.dll" `
                     -File -ErrorAction SilentlyContinue | Select-Object -First 1

    if ($winSvcDll) {
        Write-LogMessage "$($AppName): Windows Service detected (found $($winSvcDll.Name))" -Level INFO

        # Find the primary executable in the app root (skip subfolders like BuildHost-*, clidriver)
        $serviceExe = Get-ChildItem -Path $appPath -Filter "*.exe" -File -ErrorAction SilentlyContinue |
            Where-Object { $_.DirectoryName -eq $appPath } |
            Select-Object -First 1

        if ($serviceExe) {
            $serviceName    = $AppName
            $serviceDisplay = $AppName
            $exeFullPath    = $serviceExe.FullName
            Write-LogMessage "$($AppName): Service exe: $($exeFullPath)" -Level INFO

            try {
                # Stop and remove any existing registration so a path/config change is fully applied.
                # Note: sc.exe delete only MARKS the service for deletion; the SCM releases it
                # when all open handles are closed. We poll until Get-Service no longer finds it
                # (up to 30 s) before proceeding to sc.exe create, to avoid "service already exists".
                $existingSvc = Get-Service -Name $serviceName -ErrorAction SilentlyContinue
                if ($existingSvc) {
                    if ($existingSvc.Status -eq 'Running') {
                        # Service should already be stopped by the pre-copy block, but stop
                        # defensively in case SCM restarted it (e.g. auto-restart on failure).
                        Write-LogMessage "$($AppName): Service still running after copy — stopping again..." -Level INFO
                        Stop-Service -Name $serviceName -Force -ErrorAction SilentlyContinue
                        Start-Sleep -Seconds 2
                    }

                    # Kill any lingering process (pre-copy block may have missed a restart)
                    $procName = [System.IO.Path]::GetFileNameWithoutExtension($exeFullPath)
                    Get-Process -Name $procName -ErrorAction SilentlyContinue |
                        ForEach-Object { try { $_.Kill(); $_.WaitForExit(3000) } catch {} }

                    Write-LogMessage "$($AppName): Marking service '$($serviceName)' for deletion..." -Level INFO
                    $scDel = & sc.exe delete $serviceName 2>&1
                    if ($LASTEXITCODE -eq 0) {
                        Write-LogMessage "$($AppName): Service deletion accepted by SCM" -Level INFO
                    } else {
                        Write-LogMessage "$($AppName): sc.exe delete warning: $($scDel)" -Level WARN
                    }

                    # Poll until SCM fully removes the service (max 30 s in 1-s increments)
                    $waited = 0
                    while ((Get-Service -Name $serviceName -ErrorAction SilentlyContinue) -and $waited -lt 30) {
                        Start-Sleep -Seconds 1
                        $waited++
                    }
                    if (Get-Service -Name $serviceName -ErrorAction SilentlyContinue) {
                        throw "Service '$($serviceName)' still exists after 30 s wait — cannot recreate"
                    }
                    Write-LogMessage "$($AppName): Service fully removed (waited $($waited)s)" -Level INFO
                }

                # Determine service account:
                #   Server  → run as the current domain user (DEDGE\USERNAME) using the
                #             stored password from Infrastructure.Get-SecureStringUserPasswordAsPlainText.
                #             This gives the service the same AD identity as the deploying admin
                #             and access to network shares / databases via that account.
                #   Workstation → LocalSystem (no domain credentials needed for local dev/test).
                $escapedPath    = $exeFullPath -replace '"', '\"'
                $serviceAccount = $null
                $servicePassword = $null

                if (Test-IsServer) {
                    $svcUser = Get-OldServiceUsernameFromServerName
                    if (-not [string]::IsNullOrWhiteSpace($svcUser)) {
                        $serviceAccount = "$($env:USERDOMAIN)\$($svcUser)"
                    }
                    else {
                        $serviceAccount = "$($env:USERDOMAIN)\$($env:USERNAME)"
                    }
                    Write-LogMessage "$($AppName): Server detected — using domain account '$($serviceAccount)' for service" -Level INFO
                    $servicePassword = Get-SecureStringUserPasswordAsPlainText -Username $svcUser
                    if ([string]::IsNullOrEmpty($servicePassword)) {
                        Write-LogMessage "$($AppName): Could not retrieve password for '$($serviceAccount)' — falling back to LocalSystem" -Level WARN
                        $serviceAccount  = $null
                        $servicePassword = $null
                    }
                }
                else {
                    Write-LogMessage "$($AppName): Workstation detected — using LocalSystem for service" -Level INFO
                }

                Write-LogMessage "$($AppName): Registering service '$($serviceName)'..." -Level INFO
                if ($serviceAccount) {
                    $scCreate = & sc.exe create $serviceName `
                        binPath= "`"$($escapedPath)`"" `
                        start= delayed-auto `
                        obj= $serviceAccount `
                        password= $servicePassword `
                        DisplayName= $serviceDisplay 2>&1
                }
                else {
                    $scCreate = & sc.exe create $serviceName `
                        binPath= "`"$($escapedPath)`"" `
                        start= delayed-auto `
                        obj= "LocalSystem" `
                        DisplayName= $serviceDisplay 2>&1
                }
                if ($LASTEXITCODE -ne 0) {
                    throw "sc.exe create failed: $scCreate"
                }
                Write-LogMessage "$($AppName): Service '$($serviceName)' registered (account: $(if ($serviceAccount) { $serviceAccount } else { 'LocalSystem' }))" -Level INFO

                # Configure automatic restart on failure (restart after 60 s, reset counter after 24 h)
                $scFail = & sc.exe failure $serviceName reset= 86400 `
                    actions= restart/60000/restart/60000/restart/60000 2>&1
                if ($LASTEXITCODE -eq 0) {
                    Write-LogMessage "$($AppName): Auto-restart on failure configured" -Level INFO
                } else {
                    Write-LogMessage "$($AppName): Could not configure auto-restart: $($scFail)" -Level WARN
                }

                # Start the service
                Write-LogMessage "$($AppName): Starting service '$($serviceName)'..." -Level INFO
                Start-Service -Name $serviceName -ErrorAction Stop
                $svcStatus = (Get-Service -Name $serviceName -ErrorAction SilentlyContinue).Status
                Write-LogMessage "$($AppName): Service '$($serviceName)' status: $($svcStatus)" -Level INFO
                $serviceInstalled = $true
            }
            catch {
                Write-LogMessage "$($AppName): Failed to register/start service '$($serviceName)': $($_.Exception.Message)" -Level ERROR
            }
        }
        else {
            Write-LogMessage "$($AppName): Windows Service detected but no .exe found in '$($appPath)' root - skipping service registration" -Level WARN
        }
    }

    # Check for and run _install.ps1 if it exists.
    # Runs for both standard apps and Windows services (service config is done above,
    # _install.ps1 handles app-specific extras like firewall rules or URL ACLs).
    # Safety: scan _install.ps1 to prevent recursive Install-OurWinApp calls for this app.
    if (-not $SkipReInstall) {
        $installScript = Join-Path $appPath "_install.ps1"
        Write-LogMessage "InstallScript: $installScript" -Level TRACE
        if (Test-Path $installScript -PathType Leaf) {
            # Guard against recursive invocation: reject if _install.ps1 contains
            # Install-OurWinApp with the current AppName as an argument.
            # Regex breakdown:
            #   Install-OurWinApp  - literal function name
            #   [\s\S]*?           - any chars (non-greedy) between function and AppName
            #   $([regex]::Escape($AppName)) - the exact app name, regex-escaped
            $installScriptContent = Get-Content $installScript -Raw -ErrorAction SilentlyContinue
            $recursionPattern = "Install-OurWinApp[\s\S]*?$([regex]::Escape($AppName))"
            if ($installScriptContent -match $recursionPattern) {
                Write-LogMessage "$($AppName): _install.ps1 contains 'Install-OurWinApp $($AppName)' — skipping to prevent recursion" -Level WARN
            }
            else {
                Write-LogMessage "$($AppName): Executing _install.ps1..." -Level INFO
                try {
                    Set-Location $appPath
                    & $installScript
                    Write-LogMessage "$($AppName): _install.ps1 executed successfully" -Level INFO
                }
                catch {
                    Write-LogMessage "$($AppName): Error executing _install.ps1: $_" -Level ERROR
                }
            }
        }
    }

    # Add to Windows startup if requested
    if ($AddToStartup) {
        $exePath = "$appPath\$AppName.exe"
        if (Test-Path $exePath -PathType Leaf) {
            $startupRegPath = "HKCU:\Software\Microsoft\Windows\CurrentVersion\Run"
            $startupName = if ([string]::IsNullOrEmpty($DisplayName)) { $AppName } else { $DisplayName }
            try {
                Set-ItemProperty -Path $startupRegPath -Name $startupName -Value "`"$exePath`""
                Write-LogMessage "$startupName added to 'Run at startup' for current user" -Level INFO
            }
            catch {
                Write-LogMessage "Failed to add $startupName to startup: $($_.Exception.Message)" -Level WARN
            }
        }
        else {
            Write-LogMessage "Cannot add to startup - executable not found: $exePath" -Level WARN
        }
    }

    if ($ReturnExecutablePath) {
        $executablePath = "$appPath\$AppName.exe"
        if (Test-Path $executablePath -PathType Leaf) {
            return $executablePath
        }
        else {
            Write-LogMessage "Executable not found at $executablePath" -Level ERROR
            return $null
        }
    }
}

function Start-OurWinApp {
    <#
    .SYNOPSIS
        Starts a Dedge Windows application, installing it first if needed.
    .PARAMETER AppName
        The name of the Windows application to start. Use --list to see available apps.
    .PARAMETER Arguments
        Optional array of arguments to pass to the application.
    .PARAMETER NoInstall
        Skip installation check - only start if already installed.
    #>
    param (
        [Parameter(Mandatory = $false)]
        [string]$AppName = "",
        [Parameter(Mandatory = $false, ValueFromRemainingArguments = $true)]
        [object[]]$Arguments,
        [Parameter(Mandatory = $false)]
        [switch]$NoInstall
    )

    if ([string]::IsNullOrEmpty($AppName)) {
        Write-LogMessage "No AppName provided" -Level WARN
        return
    }

    Write-LogMessage "Start-OurWinApp started with AppName: $AppName" -Level INFO

    $appsPath = "$env:OptPath\DedgeWinApps"
    $installedApps = @()
    $availableApps = @()

    # Get installed apps
    if (Test-Path $appsPath) {
        $appsElements = Get-ChildItem -Path $appsPath -Directory | Select-Object Name, FullName
        foreach ($app in $appsElements) {
            $installedApps += [PSCustomObject]@{
                Name = $app.Name
                Type = "Installed FkWinApp"
                Path = $app.FullName
            }
        }
    }

    # Get available apps from source
    $sourceAppsPath = Get-WindowsDefaultAppsPath
    if (Test-Path $sourceAppsPath) {
        $appsElements = Get-ChildItem -Path $sourceAppsPath -Directory | Select-Object Name, FullName
        foreach ($app in $appsElements) {
            if (-not ($installedApps | Where-Object { $_.Name -eq $app.Name })) {
                $availableApps += [PSCustomObject]@{
                    Name = $app.Name
                    Type = "Available FkWinApp"
                    Path = $app.FullName
                }
            }
        }
    }

    $allApps = @()
    $allApps += $installedApps
    $allApps += $availableApps

    # Handle --list parameter
    if ($AppName -eq "--list" -or $AppName -eq "-list" -or $AppName -eq "/list") {
        Write-LogMessage "Available FK Windows Apps:" -Level INFO
        $tableOutput = $allApps | Format-Table -AutoSize -Property * | Out-String
        Write-LogMessage $tableOutput -Level INFO
        return
    }

    # Check if app is installed
    $currentApp = $installedApps | Where-Object { $_.Name -eq $AppName }
    
    if (-not $currentApp) {
        if ($NoInstall) {
            Write-LogMessage "$AppName is not installed. Use Install-OurWinApp to install it first." -Level WARN
            return
        }

        # Check if app is available
        $availableApp = $availableApps | Where-Object { $_.Name -eq $AppName }
        if (-not $availableApp) {
            Write-LogMessage "$AppName is not available. Use --list to see available apps." -Level WARN
            return
        }

        Write-LogMessage "Installing $AppName..." -Level INFO
        Install-OurWinApp -AppName $AppName -SkipShortcuts
        
        # Update installed apps list
        $currentApp = [PSCustomObject]@{
            Name = $AppName
            Type = "Installed FkWinApp"
            Path = "$env:OptPath\DedgeWinApps\$AppName"
        }
    }

    # Build executable path
    $exePath = Join-Path $currentApp.Path "$AppName.exe"
    
    if (-not (Test-Path $exePath -PathType Leaf)) {
        Write-LogMessage "Executable not found: $exePath" -Level ERROR
        return
    }

    Write-LogMessage "Starting $AppName..." -Level INFO

    # Start the application
    try {
        if ($Arguments -and $Arguments.Count -gt 0) {
            $argString = $Arguments -join ' '
            Write-LogMessage "Arguments: $argString" -Level DEBUG
            Start-Process -FilePath $exePath -ArgumentList $Arguments -WorkingDirectory (Split-Path $exePath)
        }
        else {
            Start-Process -FilePath $exePath -WorkingDirectory (Split-Path $exePath)
        }
        Write-LogMessage "$AppName started successfully" -Level INFO
    }
    catch {
        Write-LogMessage "Failed to start $($AppName): $($_.Exception.Message)" -Level ERROR
    }
}

function Remove-OurWinApp {
    param (
        [Parameter(Mandatory = $true)]
        [string]$AppName
    )
    $appPath = "$env:OptPath\DedgeWinApps\$AppName" 
    if (Test-Path $appPath -PathType Container) {
        Remove-Item -Path $appPath -Recurse -Force
        Write-LogMessage "$AppName application removed from $appPath" -Level INFO
    }
    else {
        Write-LogMessage "$AppName application not found at $appPath" -Level WARN
    }
}

function Install-OurNodeApp {
    param (
        [Parameter(Mandatory = $true)]
        [string]$AppName,
        [Parameter(Mandatory = $false)]
        [bool]$ReturnExecutablePath = $false
    )
    
    $appPath = "$env:OptPath\FkNodeJsApps\$AppName"
    if (-not (Test-Path $appPath -PathType Container)) {
        New-Item -Path $appPath -ItemType Directory | Out-Null
    }
    $appSourcePath = $(Get-NodeDefaultAppsPath) + "\$AppName"
    Copy-Item -Path $appSourcePath\* -Destination $appPath -Recurse -Force
    Write-LogMessage "$AppName application deployed to $appPath" -Level INFO
  
    # Check if <appname>.exe exists in app deployment path
    $exePath = "$appPath\$AppName.exe"
    if (Test-Path $exePath -PathType Leaf) {
        Write-LogMessage "$AppName.exe found in $appPath" -Level INFO
        try {
            Add-DesktopShortcut -TargetPath $exePath -ShortcutName $AppName -RunAsAdmin:$false
            Write-LogMessage "$AppName.exe is now available on the desktop" -Level INFO
        }
        catch {
            Write-LogMessage "Failed to create desktop shortcut for $AppName.exe" -Level WARN -Exception $_
            Write-LogMessage "Create manually a shortcut to $exePath on your desktop" -Level WARN
        }
    }
    if ($ReturnExecutablePath) {
        $executablePath = "$appPath\$AppName.exe"
        if (Test-Path $executablePath -PathType Leaf) {
            return $executablePath
        }
        else {
            Write-LogMessage "Executable not found at $executablePath" -Level ERROR
            return $null
        }
    }
}

function Remove-OurNodeApp {
    param (
        [Parameter(Mandatory = $true)]
        [string]$AppName
    )
    $appPath = "$env:OptPath\FkNodeJsApps\$AppName" 
    if (Test-Path $appPath -PathType Container) {
        Remove-Item -Path $appPath -Recurse -Force
        Write-LogMessage "$AppName application removed from $appPath" -Level INFO
    }
    else {
        Write-LogMessage "$AppName application not found at $appPath" -Level WARN
    }
}

function Install-OurPythonApp {
    param (
        [Parameter(Mandatory = $true)]
        [string]$AppName,
        [Parameter(Mandatory = $false)]
        [bool]$ReturnExecutablePath = $false
    )
    
    $appPath = "$env:OptPath\FkPythonApps\$AppName"
    if (-not (Test-Path $appPath -PathType Container)) {
        New-Item -Path $appPath -ItemType Directory | Out-Null
    }
    $appSourcePath = $(Get-PythonDefaultAppsPath) + "\$AppName"
    Copy-Item -Path $appSourcePath\* -Destination $appPath -Recurse -Force
    Write-LogMessage "$AppName application deployed to $appPath" -Level INFO
  
    # Check if <appname>.exe exists in app deployment path
    $exePath = "$appPath\$AppName.exe"
    if (Test-Path $exePath -PathType Leaf) {
        Write-LogMessage "$AppName.exe found in $appPath" -Level INFO
        try {
            Add-DesktopShortcut -TargetPath $exePath -ShortcutName $AppName -RunAsAdmin:$false
            Write-LogMessage "$AppName.exe is now available on the desktop" -Level INFO
        }
        catch {
            Write-LogMessage "Failed to create desktop shortcut for $AppName.exe" -Level WARN -Exception $_
            Write-LogMessage "Create manually a shortcut to $exePath on your desktop" -Level WARN
        }
    }
    if ($ReturnExecutablePath) {
        $executablePath = "$appPath\$AppName.exe"
        if (Test-Path $executablePath -PathType Leaf) {
            return $executablePath
        }
        else {
            Write-LogMessage "Executable not found at $executablePath" -Level ERROR
            return $null
        }
    }
}

function Remove-OurPythonApp {
    param (
        [Parameter(Mandatory = $true)]
        [string]$AppName
    )
    $appPath = "$env:OptPath\FkPythonApps\$AppName" 
    if (Test-Path $appPath -PathType Container) {
        Remove-Item -Path $appPath -Recurse -Force
        Write-LogMessage "$AppName application removed from $appPath" -Level INFO
    }
    else {
        Write-LogMessage "$AppName application not found at $appPath" -Level WARN
    }
}


function Update-AllOurPshApps {
    $appsPath = "$env:OptPath\DedgePshApps"
    $apps = Get-ChildItem -Path $appsPath
    foreach ($app in $apps) {
        Install-OurPshApp -AppName $app.Name -SkipReInstall
    }
    Install-OurPshApp -AppName "CommonModules" -SkipReInstall
}

function Update-AllOurWinApps {
    $appsPath = "$env:OptPath\DedgeWinApps"
    $apps = Get-ChildItem -Path $appsPath
    foreach ($app in $apps) {
        Install-OurWinApp -AppName $app.Name -SkipReInstall
    }
}

function Set-CursorAndVsCodeConfiguration {
    param (
        [Parameter(Mandatory = $false)]
        [string]$AppName = "Microsoft.VisualStudioCode"
    )

    # Install Extensions
    $extensions = Get-ExtentionArray

    foreach ($extension in $extensions) {
        if ($AppName -eq "Anysphere.Cursor") {
            Install-CursorExtension -ExtensionId $extension.Id
        }
        elseif ($AppName -eq "Microsoft.VisualStudioCode") {
            Install-VSCodeExtension -ExtensionId $extension.Id
        }
    }

    # Configure Cursor or VSCode settings
    Set-EditorConfiguration -AppName $AppName
}
function Add-LogViewerConfig {
    param (
        [Parameter(Mandatory = $false)]
        [pscustomobject[]]$LogViewerConfig = @(),
        [Parameter(Mandatory = $true)]
        [string]$Title,
        [Parameter(Mandatory = $true)]
        [string]$Pattern
    )
    $pathToAdd = [pscustomobject]@{
        "pattern" = $Pattern
        "title"   = $Title
    }
    
    # Check if LogViewerConfig has content
    if ($null -ne $LogViewerConfig -and $LogViewerConfig.Count -gt 0) {
        # Check if an entry with the same title already exists
        $existingEntry = $LogViewerConfig | Where-Object { $_.title.ToLower() -eq $pathToAdd.title.ToLower() }
        
        if ($null -eq $existingEntry) {
            # No entry with this title exists, add it
            $LogViewerConfig += $pathToAdd
        }
        elseif ($existingEntry.pattern -ne $pathToAdd.pattern) {
            # Entry exists but with different pattern, update it
            $existingEntry.pattern = $pathToAdd.pattern
        }
        # If entry exists with same pattern, do nothing
    }
    else {
        # LogViewerConfig is empty or null, initialize with the new entry
        $LogViewerConfig = @( $pathToAdd )
    }
    
    return $LogViewerConfig
}
function Set-EditorConfiguration {
    param (
        [Parameter(Mandatory = $true)]
        [string]$AppName
    )

    $ConfigFilePath = ""
    # Configure Log Viewer
    if ($AppName -eq "Microsoft.VisualStudioCode") {    
        #C:\Users\FKGEISTA\AppData\Roaming\Code\User\settings.json
        $ConfigFilePath = "$env:USERPROFILE\AppData\Roaming\Code\User\settings.json"
    }
    elseif ($AppName -eq "Anysphere.Cursor") {
        $ConfigFilePath = "$env:USERPROFILE\AppData\Roaming\Cursor\User\settings.json"
    }
    if ($ConfigFilePath -ne "") {
        # Check if file exists and has content
        if (-not (Test-Path $ConfigFilePath)) {
            New-Item -Path $ConfigFilePath -ItemType File -Force | Out-Null
        }
        # Add config file if it doesn't exist
        if (Test-Path $ConfigFilePath) {
            $fileContent = Get-Content -Path $ConfigFilePath -Raw
            if ([string]::IsNullOrWhiteSpace($fileContent)) {
                # File exists but is empty, create initial JSON structure
                $ConfigFile = @{}
            }
            else {
                # File has content, parse it
                $ConfigFile = $fileContent | ConvertFrom-Json
            }
        }
        else {
            # File doesn't exist, create initial JSON structure
            $ConfigFile = @{}
        }

    }
    # Get Log Viewer Config from ConfigFile
    $logViewerConfig = @()
    if ($ConfigFile.PSObject.Properties.Name -contains "logViewer.watch") {
        $logViewerConfig = $ConfigFile."logViewer.watch"
    }
    else {
        $ConfigFile | Add-Member -MemberType NoteProperty -Name "logViewer.watch" -Value @() -Force
    }


    # Add AllPwshLog
    $potentialPathToAdd = "$env:OptPath\data\AllPwshLog"
    if (-not (Test-Path $potentialPathToAdd)) {
        New-Item -Path $potentialPathToAdd -ItemType Directory -Force | Out-Null
    }

    $logViewerConfig = Add-LogViewerConfig -LogViewerConfig $logViewerConfig -Title "Local AllPwshLog" -Pattern "$env:OptPath\data\AllPwshLog\**.log"
    $db2DiagLastWriteTime = $null
    # Db server specific log viewer config
    if ($env:COMPUTERNAME.ToLower().Contains("-db")) {
        $diagFilesFound = Get-ChildItem -Path "C:\ProgramData\IBM\DB2\DB2COPY1" -Filter "db2diag.log" -Recurse -ErrorAction SilentlyContinue
        foreach ($diagFile in $diagFilesFound) {
            if ($diagFile.DirectoryName.ToUpper().Contains("DB2FED")) {
                $logViewerConfig = Add-LogViewerConfig -LogViewerConfig $logViewerConfig -Title "DB2FED Diag Log" -Pattern $diagFile.FullName
            }
            elseif ($diagFile.DirectoryName.ToUpper().Contains("DB2HFED")) {
                $logViewerConfig = Add-LogViewerConfig -LogViewerConfig $logViewerConfig -Title "DB2HFED Diag Log" -Pattern $diagFile.FullName
            }
            elseif ($diagFile.DirectoryName.ToUpper().Contains("DB2HST")) {
                $logViewerConfig = Add-LogViewerConfig -LogViewerConfig $logViewerConfig -Title "DB2HST Diag Log" -Pattern $diagFile.FullName
            }
            elseif ($diagFile.DirectoryName.ToUpper().Contains("DB2DBQA")) {
                $logViewerConfig = Add-LogViewerConfig -LogViewerConfig $logViewerConfig -Title "DB2DBQA Diag Log" -Pattern $diagFile.FullName
            }
            elseif ($diagFile.DirectoryName.ToUpper().Contains("DB2DOC")) {
                $logViewerConfig = Add-LogViewerConfig -LogViewerConfig $logViewerConfig -Title "DB2DOC Diag Log" -Pattern $diagFile.FullName
            }
            else {
                if ( $null -eq $db2DiagLastWriteTime) {
                    $db2DiagLastWriteTime = $diagFile.LastWriteTime
                    $logViewerConfig = Add-LogViewerConfig -LogViewerConfig $logViewerConfig -Title "DB2 Diag Log" -Pattern $diagFile.FullName
                }
                elseif ($diagFile.LastWriteTime -gt $db2DiagLastWriteTime) {
                    $db2DiagLastWriteTime = $diagFile.LastWriteTime
                    $logViewerConfig = Add-LogViewerConfig -LogViewerConfig $logViewerConfig -Title "DB2 Diag Log" -Pattern $diagFile.FullName
                }
            }
        }
    }    

    $ConfigFile | Add-Member -MemberType NoteProperty -Name "logViewer.watch" -Value @($logViewerConfig) -Force -ErrorAction SilentlyContinue

    # Add security.allowedUNCHosts
    # Add security.allowedUNCHosts property (preserve existing if present)
    $newUncHosts = @("*.DEDGE.fk.no", "p-no1*", "t-no1*")
        
    if ($ConfigFile.PSObject.Properties.Name -contains "security.allowedUNCHosts") {
        # Merge with existing UNC hosts
        $existingHosts = $ConfigFile."security.allowedUNCHosts"
        $mergedHosts = @($existingHosts) + @($newUncHosts) | Select-Object -Unique
        $ConfigFile | Add-Member -MemberType NoteProperty -Name "security.allowedUNCHosts" -Value $mergedHosts -Force -ErrorAction SilentlyContinue
    }
    else {
        # Create new security.allowedUNCHosts property
        $ConfigFile | Add-Member -MemberType NoteProperty -Name "security.allowedUNCHosts" -Value $newUncHosts -Force -ErrorAction SilentlyContinue
    }
  
    # Set workbench.tree.indent to 20
    $ConfigFile | Add-Member -MemberType NoteProperty -Name "workbench.tree.indent" -Value 20 -Force -ErrorAction SilentlyContinue
    # Set workbench.colorTheme to Visual Studio Dark
    $ConfigFile | Add-Member -MemberType NoteProperty -Name "workbench.colorTheme" -Value "Visual Studio Dark" -Force -ErrorAction SilentlyContinue
    # Set json to editor.defaultFormatter to esbenp.prettier-vscode

    $ConfigFile | Add-Member -MemberType NoteProperty -Name "[json]" -Value @{ "editor.defaultFormatter" = "esbenp.prettier-vscode" } -Force -ErrorAction SilentlyContinue
    $ConfigFile | Add-Member -MemberType NoteProperty -Name "[jsonc]" -Value @{ "editor.defaultFormatter" = "esbenp.prettier-vscode" } -Force -ErrorAction SilentlyContinue
    $ConfigFile | Add-Member -MemberType NoteProperty -Name "[html]" -Value @{ "editor.defaultFormatter" = "esbenp.prettier-vscode" } -Force -ErrorAction SilentlyContinue
    $ConfigFile | Add-Member -MemberType NoteProperty -Name "[sql]" -Value @{ "editor.defaultFormatter" = "esbenp.prettier-vscode" } -Force -ErrorAction SilentlyContinue
    $ConfigFile | Add-Member -MemberType NoteProperty -Name "[xml]" -Value @{ "editor.defaultFormatter" = "esbenp.prettier-vscode" } -Force -ErrorAction SilentlyContinue
    $ConfigFile | Add-Member -MemberType NoteProperty -Name "[cbl]" -Value @{ "editor.defaultFormatter" = "esbenp.prettier-vscode" } -Force -ErrorAction SilentlyContinue

    
    Set-Content -Path $ConfigFilePath -Value ($ConfigFile | ConvertTo-Json -Depth 100)
    

}


function Install-WingetPackage {
    param(
        [Parameter(Mandatory = $true)]
        [string]$AppName,
        
        [Parameter(Mandatory = $false)]
        [string]$Executable = "",

        [Parameter(Mandatory = $false)]
        [string]$InstallArgs = "",

        [Parameter(Mandatory = $false)]
        [switch]$QueryWinget,

        [Parameter(Mandatory = $false)]
        [switch]$Force
    )

    Write-ApplicationLog -AppName $AppName -Status "Initiating" -Message "Initiating Winget installation of $AppName"

    # Check if already installed using winget
    Write-LogMessage "Checking if $AppName is installed..." -Level INFO
    if ($QueryWinget.IsPresent) {
        #verify winget is installed
        $wingetCommand = Get-CommandPathWithFallback -Name "winget"
        if ($wingetCommand -ne "winget") {
            $command = "$wingetCommand list --id $AppName --exact"
            Write-LogMessage "Running command: $command" -Level INFO
            $wingetResult = Invoke-Expression $command | Out-String
            # $wingetResult = $wingetCommand list --id $AppName --exact | Out-String
            if ($wingetResult -match $AppName) {
                $version = if ($wingetResult -match "(\d+\.[\d\.]+)") { $matches[1] } else { "unknown" }
                Write-LogMessage "Yes. Application $AppName with Version $version is installed" -Level INFO
                return
            }
            Write-LogMessage "Not installed" -Level WARN
            Write-LogMessage "Application $AppName is not installed using winget. Using fallback to install from downloaded files." -Level WARN
        }
        else {
            if (-not $Force.IsPresent) {
                return ""
            }
        }
    }

    $localWingetPath = Get-WingetAppsPath


    $packagePath = Join-Path $localWingetPath $AppName

    if (-not (Test-Path $packagePath)) {
        Write-LogMessage "Package directory not found: $packagePath" -Level ERROR
        return ""
    }

    $installObject = [PSCustomObject]@{
        AppName              = $AppName
        DefaultExe           = $Executable
        IsInstalledCheck     = ""
        Args                 = ""
        CustomConfigFunction = ""
        ExecutionCommand     = ""
    }

    switch ($AppName) {
        "Microsoft.AzureCLI" {
            $installObject.IsInstalledCheck = if ($(Get-Command -Name "az" -ErrorAction SilentlyContinue) ?? "") { $true.ToString().ToLower() } else { $false.ToString().ToLower() }
            if ([string]::IsNullOrEmpty($InstallArgs)) {
                $installObject.Args = ""
            }
            else {
                $installObject.Args = $InstallArgs
            }
        }
        "Anysphere.Cursor" {
            $installObject.IsInstalledCheck = if ($(Get-Command -Name "cursor" -ErrorAction SilentlyContinue) ?? "") { $true.ToString().ToLower() } else { $false.ToString().ToLower() }
            if ([string]::IsNullOrEmpty($InstallArgs)) {
                $installObject.Args = "/S"
            }
            else {
                $installObject.Args = $InstallArgs
            }
        }
        "Microsoft.AzureDataStudio" {
            $installObject.IsInstalledCheck = if ($(Get-Command -Name "azuredatastudio" -ErrorAction SilentlyContinue) ?? "") { $true.ToString().ToLower() } else { $false.ToString().ToLower() }
            if ([string]::IsNullOrEmpty($InstallArgs)) {
                $installObject.Args = "/S"
            }
            else {
                $installObject.Args = $InstallArgs
            }
        }
        "DBeaver.DBeaver.Community" {
            $installObject.IsInstalledCheck = if ($(Get-Command -Name "dbeaver" -ErrorAction SilentlyContinue) ?? "") { $true.ToString().ToLower() } else { $false.ToString().ToLower() }
            if ([string]::IsNullOrEmpty($InstallArgs)) {
                $installObject.Args = "/S"
            }
            else {
                $installObject.Args = $InstallArgs
            }
            $installObject.CustomConfigFunction = "Set-DBeaverConfig"
        }
        "Microsoft.VisualStudioCode" {
            $installObject.IsInstalledCheck = if ($(Get-Command -Name "code" -ErrorAction SilentlyContinue) ?? "") { $true.ToString().ToLower() } else { $false.ToString().ToLower() }
            if ([string]::IsNullOrEmpty($InstallArgs)) {
                #'/SILENT /mergetasks="!runcode,addcontextmenufiles,addcontextmenufolders"'
                $installObject.Args = "/SILENT /NORESTART /mergetasks=""!runcode,addcontextmenufiles,addcontextmenufolders"""                
            }
            else {
                $installObject.Args = $InstallArgs
            }
        }
        "Notepad++.Notepad++" {
            $installObject.IsInstalledCheck = "C:\Program Files\Notepad++\notepad++.exe"
            Write-LogMessage "Checking if Notepad++ Args: $InstallArgs" -Level INFO
            if ([string]::IsNullOrEmpty($InstallArgs)) {
                $installObject.Args = "/S"
            }
            else {
                $installObject.Args = $InstallArgs
            }
        }
        "Git.Git" {
            $installObject.IsInstalledCheck = if ($(Get-Command -Name "git" -ErrorAction SilentlyContinue) ?? "") { $true.ToString().ToLower() } else { $false.ToString().ToLower() }
            if ([string]::IsNullOrEmpty($InstallArgs)) {
                $installObject.Args = "/SP- /VERYSILENT /SUPPRESSMSGBOXES /NORESTART /DIR=`"C:\Program Files\Git`""
            }
            else {
                $installObject.Args = $InstallArgs
            }
            if ($null -ne $env:IsServer -and $env:IsServer -eq $true) {
                $installObject.CustomConfigFunction = "Set-GitUserIdentity"
            }
        }
        "Microsoft.DotNet.SDK.8" {
            try {
                $dotnetPath = "C:\Program Files\dotnet\dotnet.exe"
                $sdks = & $dotnetPath --list-sdks
                Write-LogMessage "Installed Dotnet SDKs: `n$sdks" -Level INFO
                $sdks = "¤" + $($sdks -Join "¤")
                if ( $sdks.Contains("¤8") ) {
                    $installObject.IsInstalledCheck = $true.ToString()
                }
                else {
                    $installObject.IsInstalledCheck = $false.ToString()
                }
            }
            catch {
                $installObject.IsInstalledCheck = $false.ToString()
            }
            if ([string]::IsNullOrEmpty($InstallArgs)) {
                $installObject.Args = "/install /quiet /norestart"
            }
            else {
                $installObject.Args = $InstallArgs
            }
        }
        "Microsoft.DotNet.SDK.9" {
            try {
                $dotnetPath = "C:\Program Files\dotnet\dotnet.exe"
                $sdks = & $dotnetPath --list-sdks
                Write-LogMessage "Installed Dotnet SDKs: `n$sdks" -Level INFO
                $sdks = "¤" + $($sdks -Join "¤")
                if ( $sdks.Contains("¤9") ) {
                    $installObject.IsInstalledCheck = $true.ToString()
                }
                else {
                    $installObject.IsInstalledCheck = $false.ToString()
                }
            }
            catch {
                $installObject.IsInstalledCheck = $false.ToString()
            }
            if ([string]::IsNullOrEmpty($InstallArgs)) {
                $installObject.Args = "/install /quiet /norestart"
            }
            else {
                $installObject.Args = $InstallArgs
            }
        }
        "Microsoft.DotNet.SDK.10" {
            try {
                $dotnetPath = "C:\Program Files\dotnet\dotnet.exe"
                $sdks = & $dotnetPath --list-sdks
                Write-LogMessage "Installed Dotnet SDKs: `n$sdks" -Level INFO
                $sdks = "¤" + $($sdks -Join "¤")
                if ( $sdks.Contains("¤10") ) {
                    $installObject.IsInstalledCheck = $true.ToString()
                }
                else {
                    $installObject.IsInstalledCheck = $false.ToString()
                }
            }
            catch {
                $installObject.IsInstalledCheck = $false.ToString()
            }
            if ([string]::IsNullOrEmpty($InstallArgs)) {
                $installObject.Args = "/install /quiet /norestart"
            }
            else {
                $installObject.Args = $InstallArgs
            }
        }
        "Microsoft.DotNet.Runtime.8" {
            try {
                $dotnetPath = "C:\Program Files\dotnet\dotnet.exe"
                $runtimes = & $dotnetPath --list-runtimes
                Write-LogMessage "Installed Dotnet Runtimes: `n$runtimes" -Level INFO
                $runtimes = "¤" + $($runtimes -Join "¤")
                if ( $runtimes.Contains("¤Microsoft.NETCore.App 8") ) {
                    $installObject.IsInstalledCheck = $true.ToString()
                }
                else {
                    $installObject.IsInstalledCheck = $false.ToString()
                }
            }
            catch {
                $installObject.IsInstalledCheck = $false.ToString()
            }
            if ([string]::IsNullOrEmpty($InstallArgs)) {
                $installObject.Args = "/install /quiet /norestart"
            }
            else {
                $installObject.Args = $InstallArgs
            }
        }
        "Microsoft.DotNet.Runtime.9" {
            try {
                $dotnetPath = "C:\Program Files\dotnet\dotnet.exe"
                $runtimes = & $dotnetPath --list-runtimes
                Write-LogMessage "Installed Dotnet Runtimes: `n$runtimes" -Level INFO
                $runtimes = "¤" + $($runtimes -Join "¤")
                if ( $runtimes.Contains("¤Microsoft.NETCore.App 9") ) {
                    $installObject.IsInstalledCheck = $true.ToString()
                }
                else {
                    $installObject.IsInstalledCheck = $false.ToString()
                }
            }
            catch {
                $installObject.IsInstalledCheck = $false.ToString()
            }
            if ([string]::IsNullOrEmpty($InstallArgs)) {
                $installObject.Args = "/install /quiet /norestart"
            }
            else {
                $installObject.Args = $InstallArgs
            }
        }
        "Microsoft.DotNet.Runtime.10" {
            try {
                $dotnetPath = "C:\Program Files\dotnet\dotnet.exe"
                $runtimes = & $dotnetPath --list-runtimes
                Write-LogMessage "Installed Dotnet Runtimes: `n$runtimes" -Level INFO
                $runtimes = "¤" + $($runtimes -Join "¤")
                if ( $runtimes.Contains("¤Microsoft.NETCore.App 10") ) {
                    $installObject.IsInstalledCheck = $true.ToString()
                }
                else {
                    $installObject.IsInstalledCheck = $false.ToString()
                }
            }
            catch {
                $installObject.IsInstalledCheck = $false.ToString()
            }
            if ([string]::IsNullOrEmpty($InstallArgs)) {
                $installObject.Args = "/install /quiet /norestart"
            }
            else {
                $installObject.Args = $InstallArgs
            }
        }
        "Microsoft.DotNet.HostingBundle.8" {
            $installObject.IsInstalledCheck = "$env:ProgramFiles\IIS\Asp.Net Core Module\V2\aspnetcorev2.dll"
            if ([string]::IsNullOrEmpty($InstallArgs)) {
                $installObject.Args = "/install /quiet /norestart"
            }
            else {
                $installObject.Args = $InstallArgs
            }
        }
        "Microsoft.DotNet.HostingBundle.9" {
            $installObject.IsInstalledCheck = "$env:ProgramFiles\IIS\Asp.Net Core Module\V2\aspnetcorev2.dll"
            if ([string]::IsNullOrEmpty($InstallArgs)) {
                $installObject.Args = "/install /quiet /norestart"
            }
            else {
                $installObject.Args = $InstallArgs
            }
        }
        "Microsoft.DotNet.HostingBundle.10" {
            $installObject.IsInstalledCheck = "$env:ProgramFiles\IIS\Asp.Net Core Module\V2\aspnetcorev2.dll"
            if ([string]::IsNullOrEmpty($InstallArgs)) {
                $installObject.Args = "/install /quiet /norestart"
            }
            else {
                $installObject.Args = $InstallArgs
            }
        }
        "Microsoft.SQLServer.2022.Developer" {
            $installObject.DefaultExe = "setup.exe"
            $installObject.IsInstalledCheck = "C:\Program Files\Microsoft SQL Server\160\Tools\Binn"
            if ([string]::IsNullOrEmpty($InstallArgs)) {
                $password = Get-SecureStringUserPasswordAsPlainText 
                $installObject.Args = "/Q /IACCEPTSQLSERVERLICENSETERMS /ACTION=Install /FEATURES=SQL,Tools /INSTANCENAME=MSSQLSERVER /SQLSYSADMINACCOUNTS=`"BUILTIN\Administrators`" `"$env:USERDOMAIN\$env:USERNAME`" /SECURITYMODE=SQL /SAPWD=`"$password`""
            }
            else {
                $installObject.Args = $InstallArgs
            }
        }
        "Microsoft.SQLServerManagementStudio" {
            $installObject.IsInstalledCheck = if ($(Get-Command -Name "ssms" -ErrorAction SilentlyContinue) ?? "") { $true.ToString().ToLower() } else { $false.ToString().ToLower() }
            if ([string]::IsNullOrEmpty($InstallArgs)) {
                $installObject.Args = "/install /quiet /norestart"
            }
            else {
                $installObject.Args = $InstallArgs
            }
        }
        "Microsoft.VisualStudioCode" {
            $installObject.IsInstalledCheck = if ($(Get-Command -Name "code" -ErrorAction SilentlyContinue) ?? "") { $true.ToString().ToLower() } else { $false.ToString().ToLower() }
            if ([string]::IsNullOrEmpty($InstallArgs)) {
                $installObject.Args = "/VERYSILENT /MERGETASKS=!runcode,addcontextmenufiles,addcontextmenufolders,associatewithfiles,addtopath /NORESTART"
            }
            else {
                $installObject.Args = $InstallArgs
            }
        }
        "Microsoft.VisualStudio.2022.Community" {
            $installObject.IsInstalledCheck = "C:\Program Files\Microsoft Visual Studio\2022\Community\Common7\IDE\devenv.exe"
            if ([string]::IsNullOrEmpty($InstallArgs)) {
                $installObject.Args = "--quiet --norestart --wait --addProductLang en-US --add Microsoft.VisualStudio.Workload.CoreEditor --add Microsoft.VisualStudio.Workload.NetWeb --add Microsoft.VisualStudio.Workload.ManagedDesktop --add Microsoft.VisualStudio.Workload.NetCoreTools --includeRecommended"
            }
            else {
                $installObject.Args = $InstallArgs
            }
        }
        "Microsoft.VisualStudio.Community" {
            $installObject.IsInstalledCheck = "C:\Program Files\Microsoft Visual Studio\2022\Community\Common7\IDE\devenv.exe"
            if ([string]::IsNullOrEmpty($InstallArgs)) {
                $installObject.Args = "--quiet --norestart --wait --addProductLang en-US --add Microsoft.VisualStudio.Workload.CoreEditor --add Microsoft.VisualStudio.Workload.NetWeb --add Microsoft.VisualStudio.Workload.ManagedDesktop --add Microsoft.VisualStudio.Workload.NetCoreTools --includeRecommended"
            }
            else {
                $installObject.Args = $InstallArgs
            }
        }
        "Microsoft.Azure.TrustedSigningClientTools" {
            $installObject.IsInstalledCheck = if ($(Get-Command -Name "tsctl" -ErrorAction SilentlyContinue) ?? "") { $true.ToString().ToLower() } else { $false.ToString().ToLower() }
            if ([string]::IsNullOrEmpty($InstallArgs)) {
                $installObject.Args = "/install /quiet /norestart"
            }
            else {
                $installObject.Args = $InstallArgs
            }
        }
        "Ollama.Ollama" {
            $installObject.IsInstalledCheck = if ($(Get-Command -Name "ollama" -ErrorAction SilentlyContinue) ?? "") { $true.ToString().ToLower() } else { $false.ToString().ToLower() }
            if ([string]::IsNullOrEmpty($InstallArgs)) {
                $installObject.Args = "/SP- /SILENT /SUPPRESSMSGBOXES /NORESTART"
            }
            else {
                $installObject.Args = $InstallArgs
            }
        }
    }
    try {
        if ($Force -eq $true) {
            Write-LogMessage "$($installObject.AppName) will be reinstalled due to Force flag" -Level INFO
        }
        else {
            if (-not [string]::IsNullOrEmpty($installObject.IsInstalledCheck)) {
                if (Test-IsInstalled -IsInstalledCheck $installObject.IsInstalledCheck) {


                    $response = Get-UserConfirmationWithTimeout -PromptMessage "$($installObject.AppName) is already installed. Install anyway?" -TimeoutSeconds 10 -DefaultResponse "N"
                    
                    if ($response.ToUpper() -ne "Y") {
                        if (-not [string]::IsNullOrEmpty($installObject.CustomConfigFunction)) {
                            $configResponse = Get-UserConfirmationWithTimeout -PromptMessage "Do you want to run configuration?" -TimeoutSeconds 10 -DefaultResponse "N"
                            if ($configResponse.ToUpper() -eq "Y") {
                                Start-InstallProcess -AppName $AppName -CustomConfigFunction $installObject.CustomConfigFunction
                            }
                        }
                        return ""
                    }
                }
            }
        }
    }
    catch {
        Write-LogMessage "Failed to check if $($installObject.AppName) is installed: $($_.Exception.Message)" -Level ERROR -Exception $_
        throw "Failed to check if $($installObject.AppName) is installed: $($_.Exception.Message)"
    }

   
    $sourcePath = Join-Path $(Get-WingetAppsPath) "$AppName"
    #Find Last folder name in SourcePath and use it as TempPath using C:\TEMPFK\TempInstallFiles\<foldername>
    $tempPath = Join-Path "C:\TEMPFK\TempInstallFiles" "$AppName"
    $tempPath = $tempPath.Replace(" ", "_").Replace("++", "PlusPlus")
    # Create temp directory if it doesn't exist
    if (-not (Test-Path -Path $tempPath -PathType Container)) {
        New-Item -Path $tempPath -ItemType Directory -Force | Out-Null
    }

    
    Write-LogMessage "Kopierer installasjonsfiler... $sourcePath to $tempPath" 
    $result = Start-RoboCopy -SourceFolder $sourcePath -DestinationFolder $tempPath -Recurse
    if ($result.OperationSuccessful) {
        Write-LogMessage "Vellykket!" -ForegroundColor Green
        Write-ApplicationLog -AppName $AppName -Status "Progress" -Message "Installation files copied successfully"
    }
    else {
        Write-LogMessage "Mislyktes (Feilkode: $($result.RobocopyExitCode) - $($result.ResultMessage))" -Level ERROR     
        Write-ApplicationLog -AppName $AppName -Status "Failed" -Message $("Installation failed with exit code: " + $result.RobocopyExitCode + " - " + $result.ResultMessage)
    }

    if ([string]::IsNullOrEmpty($Executable)) {
        # Search for common installer file types
        $installerFiles = Get-ChildItem -Path $tempPath -Recurse -Include "*.msi", "*.exe", "*.bat", "*.cmd"
        
        if ($installerFiles.Count -eq 0) {
            Write-LogMessage "No installer files found in $tempPath" -Level ERROR
            return ""
        }
        elseif ($installerFiles.Count -gt 1) {
            Write-LogMessage "Multiple installer files found in $tempPath. Please specify the executable:" -Level WARN
            $installerFiles | ForEach-Object { Write-LogMessage "- $($_.Name)" -Level INFO }
            return ""
        }
        else {
            $installerPath = $installerFiles[0].FullName
        }
    }
    else {
        $installerPath = Join-Path $packagePath $Executable
        if (-not (Test-Path $installerPath -PathType Leaf)) {
            Write-LogMessage "Specified executable not found: $installerPath" -Level ERROR
            return ""
        }
    }
    try {
        # if ($installerPath.Contains(" ")) {
        #     $installerPath = '"' + $installerPath + '"'
        # }
        $result = Start-InstallProcess -AppName $AppName -InstallerPath $installerPath -InstallArgs $installObject.Args -CustomConfigFunction $installObject.CustomConfigFunction
        if ($result -eq $true) {
            if ($AppName -eq "Anysphere.Cursor" -or $AppName -eq "Microsoft.VisualStudioCode") {
                Set-CursorAndVsCodeConfiguration -AppName $AppName
            }
        }
    }
    catch {
        Write-LogMessage "Failed to install $AppName : $($_.Exception.Message)" -Level ERROR -Exception $_
        Write-ApplicationLog -AppName $AppName -Status "Failed" -Message "Installation failed with error: $($_.Exception.Message)"
    }
}
function Test-IsInstalled {
    param (
        [Parameter(Mandatory = $true)]
        [string]$IsInstalledCheck
    )
    if (-not [string]::IsNullOrEmpty($IsInstalledCheck)) {
        if ($IsInstalledCheck.ToLower().Trim() -eq $true.ToString().ToLower().Trim()) {
            return $true
        }
        if (Test-Path $IsInstalledCheck -PathType Leaf) {
            return $true
        }
        if (Test-Path $IsInstalledCheck -PathType Container) {
            return $true
        }
    }
    return $false
}
  
function Install-WindowsApps {
    param (
        [Parameter(Mandatory = $true)]
        [string]$AppName,
        [Parameter(Mandatory = $false)]
        [string]$DefaultExe = "",
        [Parameter(Mandatory = $false)]
        [string]$InstallArgs = "",
        [Parameter(Mandatory = $false)]
        [switch]$Force 
    )
    Write-ApplicationLog -AppName $AppName -Status "Started" -Message "Standard software installation started" 

    $installObject = [PSCustomObject]@{
        AppName               = $AppName
        DefaultExe            = $DefaultExe
        IsInstalledCheck      = ""
        Args                  = ""
        CustomInstallFunction = ""
        CustomConfigFunction  = ""
        ExecutionCommand      = ""
    }
    $defaultTempPath = "C:\TEMPFK\TempInstallFiles"

    $db2ResponseFile = Join-Path $(Get-SoftwarePath) "\Config\Db2\SetupDb2ClientResponceFile.rsp"

    switch ($AppName) {
        "Db2 Client 9.7 x86" {
            $installObject.IsInstalledCheck = if ($(Get-Command -Name "db2" -ErrorAction SilentlyContinue) ?? "") { $true.ToString().ToLower() } else { $false.ToString().ToLower() }
            $installObject.DefaultExe = "setup.exe"
            if ([string]::IsNullOrEmpty($InstallArgs)) {
                $installObject.Args = "/u " + $db2ResponseFile
            }
            else {
                $installObject.Args = $InstallArgs
            }
            $installObject.CustomConfigFunction = "Set-Db2ClientConfig x86"
        }
        "Db2 Client 10.5 x64" {
            $installObject.IsInstalledCheck = if ($(Get-Command -Name "db2" -ErrorAction SilentlyContinue) ?? "") { $true.ToString().ToLower() } else { $false.ToString().ToLower() }
            $installObject.DefaultExe = "setup.exe"
            if ([string]::IsNullOrEmpty($InstallArgs)) {
                $installObject.Args = "/u " + $db2ResponseFile
            }
            else {
                $installObject.Args = $InstallArgs
            }
            $installObject.CustomConfigFunction = "Set-Db2ClientConfig x64"

        }
        "Db2 Client 10.5 x86" {
            $installObject.IsInstalledCheck = if ($(Get-Command -Name "db2" -ErrorAction SilentlyContinue) ?? "") { $true.ToString().ToLower() } else { $false.ToString().ToLower() }
            $installObject.DefaultExe = "setup.exe"
            if ([string]::IsNullOrEmpty($InstallArgs)) {
                $installObject.Args = "/u " + $db2ResponseFile
            }
            else {
                $installObject.Args = $InstallArgs
            }
            $installObject.CustomConfigFunction = "Set-Db2ClientConfig x86"

        }
        "Db2 Client 11.5 x64" {
            $installObject.IsInstalledCheck = if ($(Get-Command -Name "db2" -ErrorAction SilentlyContinue) ?? "") { $true.ToString().ToLower() } else { $false.ToString().ToLower() }
            $installObject.DefaultExe = "setup.exe"
            if ([string]::IsNullOrEmpty($InstallArgs)) {
                $installObject.Args = "/u " + $db2ResponseFile
            }
            else {
                $installObject.Args = $InstallArgs
            }
            $installObject.CustomConfigFunction = "Set-Db2ClientConfig x64"

        }
        "Db2 Client 11.5 x86" {
            $installObject.IsInstalledCheck = if ($(Get-Command -Name "db2" -ErrorAction SilentlyContinue) ?? "") { $true.ToString().ToLower() } else { $false.ToString().ToLower() }
            $installObject.DefaultExe = "setup.exe"
            if ([string]::IsNullOrEmpty($InstallArgs)) {
                $installObject.Args = "/u " + $db2ResponseFile
            }
            else {
                $installObject.Args = $InstallArgs
            }
            $installObject.CustomConfigFunction = "Set-Db2ClientConfig"

        }
        "Db2 Client 12.1 x64" {
            $installObject.IsInstalledCheck = if ($(Get-Command -Name "db2" -ErrorAction SilentlyContinue) ?? "") { $true.ToString().ToLower() } else { $false.ToString().ToLower() }
            $installObject.DefaultExe = "setup.exe"
            if ([string]::IsNullOrEmpty($InstallArgs)) {
                $installObject.Args = "/u " + $db2ResponseFile
            }
            else {
                $installObject.Args = $InstallArgs
            }
            $installObject.CustomConfigFunction = "Set-Db2ClientConfig x64"
        }
        "Db2 Client 12.1 x86" {
            $installObject.IsInstalledCheck = if ($(Get-Command -Name "db2" -ErrorAction SilentlyContinue) ?? "") { $true.ToString().ToLower() } else { $false.ToString().ToLower() }
            $installObject.DefaultExe = "setup.exe"
            if ([string]::IsNullOrEmpty($InstallArgs)) {
                $installObject.Args = "/u " + $db2ResponseFile
            }
            else {
                $installObject.Args = $InstallArgs
            }
            $installObject.CustomConfigFunction = "Set-Db2ClientConfig x86"

        }
        "Db2 Server 11.5 Standard Edition" {
            $installObject.IsInstalledCheck = if ($(Get-Command -Name "db2" -ErrorAction SilentlyContinue) ?? "") { $true.ToString().ToLower() } else { $false.ToString().ToLower() }
            $installObject.DefaultExe = "setup.exe"
            if ([string]::IsNullOrEmpty($InstallArgs)) {
                $installObject.Args = "/p C:\DbInst"
            }
            else {
                $installObject.Args = $InstallArgs
            }
            $installObject.CustomConfigFunction = "Set-Db2ServerConfig"
        }
        "Db2 Server 12.1 Community Edition" {
            $installObject.IsInstalledCheck = if ($(Get-Command -Name "db2" -ErrorAction SilentlyContinue) ?? "") { $true.ToString().ToLower() } else { $false.ToString().ToLower() }
            $installObject.DefaultExe = "setup.exe"
            if ([string]::IsNullOrEmpty($InstallArgs)) {
                $installObject.Args = "/p C:\DbInst"            
            }
            else {
                $installObject.Args = $InstallArgs
            }
            $installObject.CustomConfigFunction = "Set-Db2ServerConfig"
        }
        "Db2 Server 12.1 Standard Edition" {
            $installObject.IsInstalledCheck = if ($(Get-Command -Name "db2" -ErrorAction SilentlyContinue) ?? "") { $true.ToString().ToLower() } else { $false.ToString().ToLower() }
            $installObject.DefaultExe = "setup.exe"
            if ([string]::IsNullOrEmpty($InstallArgs)) {
                $installObject.Args = "/p C:\DbInst"
            }
            else {
                $installObject.Args = $InstallArgs
            }
            $installObject.CustomConfigFunction = "Set-Db2ServerConfig"
        }
        "IBM ObjectRexx" {
            #"C:\Program Files (x86)\ObjREXX\REXX.EXE"
            $installObject.IsInstalledCheck = if ($(Get-Command -Name "rexx" -ErrorAction SilentlyContinue) ?? "") { $true.ToString().ToLower() } else { $false.ToString().ToLower() }
            $installObject.DefaultExe = "setup.exe"                
            if ([string]::IsNullOrEmpty($InstallArgs)) {
                $installObject.Args = "/s /v"
            }
            else {
                $installObject.Args = $InstallArgs
            }
        }
        "IBM QMF For Windows" {
            
            $installObject.IsInstalledCheck = $(Test-IsInstalled -IsInstalledCheck "C:\Program Files (x86)\IBM\QMF for Windows\qmfwin.exe").ToString().ToLower()
            $installObject.DefaultExe = "setup.exe"           
            $installObject.CustomConfigFunction = "Set-QmfConfig"
        }
        "MicroFocus NetExpress Pack" {
            Install-WindowsApps -AppName "Microsoft .Net Framwork 3.5"
            $installObject.IsInstalledCheck = "C:\Program Files (x86)\Micro Focus\Server 5.1\Bin\RUN.EXE"
            if ($Force.IsPresent) {
                $installObject.CustomInstallFunction = "Install-NetExpressForce"
            }
            else {
                $installObject.CustomInstallFunction = "Install-NetExpressForce"
            }
            $installObject.CustomConfigFunction = "Set-MicroFocusServerPackConfig"
            #$installObject.CustomConfigFunction = "Set-MicroFocusServerPackConfig"
        }
        # "MicroFocus License Server" {
        #     $installObject.DefaultExe = "setup.exe"            
        # }
        "MicroFocus Server Pack" {
            # This is a dependency for the MicroFocus Server Pack
            Install-WindowsApps -AppName "Microsoft .Net Framwork 3.5"

            $installObject.DefaultExe = "setup.exe"
            $installObject.CustomInstallFunction = "Install-MicroFocusServerPack"
        
        }      
        "SPF Editor" {
            $installObject.CustomInstallFunction = "Install-Spf"
            $installObject.CustomConfigFunction = "Set-SpfConfig"
        }  
        "Rocket Visual Cobol For Visual Studio 2022" {
            $installObject.DefaultExe = "vcvs2022_100.exe"
        }
        "Rocket Visual Cobol For Visual Studio 2022 Version 11" {
            $installObject.DefaultExe = "vcvs2022_110.exe"
            $installObject.IsInstalledCheck = 'C:\Program Files (x86)\Rocket Software\Visual COBOL\bin\cobol.exe'
        }
        "Rocket Visual Cobol For Visual Studio 2022 Version 11 Update Patch 3" {
            $installObject.DefaultExe = "vcvs2022_110_pu03_390812.exe"
            $installObject.IsInstalledCheck = 'C:\Program Files (x86)\Rocket Software\Visual COBOL\bin\cobol.exe'
        }
        "Rocket Visual Cobol Server Version 11" {
            $installObject.DefaultExe = "cs_110.exe"
            $installObject.IsInstalledCheck = 'C:\Program Files (x86)\Rocket Software\Visual COBOL\bin\cobol.exe'
        }
        "Rocket Visual Cobol Server Version 11 Update Patch 3" {
            $installObject.DefaultExe = "cs_110_pu03_390812.exe"
            $installObject.IsInstalledCheck = 'C:\Program Files (x86)\Rocket Software\Visual COBOL\bin\cobol.exe'
        }
        "Rocket Temp" {
            $installObject.IsInstalledCheck = 'C:\Program Files (x86)\Rocket Software\Visual COBOL\bin\cobol.exe'
        }
        "Microsoft .Net Framwork 3.5" {
            Write-LogMessage "This process can take a while to complete (approximately 10 minutes)" -Level WARN
            $regPath = "HKLM:\SOFTWARE\Microsoft\NET Framework Setup\NDP\v3.5"            
            if (-not (Test-Path $regPath)) {
                $installObject.DefaultExe = "C:\WINDOWS\system32\Dism.exe"
                $installObject.Args = "/Online /Enable-Feature /FeatureName:NetFx3 /All"
                $null = Start-InstallProcess -AppName $AppName -InstallerPath $installObject.DefaultExe -InstallArgs $installObject.Args
            }
            else {
                Write-LogMessage "Microsoft .Net Framwork 3.5 is already installed" -Level INFO
            }
            return ""
        }
        "VSCode System-Installer" {
            Remove-ExistingVSCode
            $installObject.IsInstalledCheck = $(Test-IsInstalled -IsInstalledCheck "C:\Program Files\Microsoft VS Code\bin\code.cmd").ToString().ToLower()
            if ([string]::IsNullOrEmpty($InstallArgs)) {
                $installObject.Args = "/VERYSILENT /MERGETASKS=!runcode,addcontextmenufiles,addcontextmenufolders"                
            }
            else {
                $installObject.Args = $InstallArgs
            }
            $installObject.CustomConfigFunction = "Set-CursorAndVsCodeConfiguration"
        }
        "Cursor System-Installer" {
            $installObject.IsInstalledCheck = $(Test-IsInstalled -IsInstalledCheck "C:\Program Files\Cursor\Cursor.exe").ToString().ToLower()
            if ([string]::IsNullOrEmpty($InstallArgs)) {
                $installObject.Args = "/VERYSILENT /MERGETASKS=!runcode,addcontextmenufiles,addcontextmenufolders"                
            }
            $installObject.CustomConfigFunction = "Set-CursorAndVsCodeConfiguration `"Anysphere.Cursor`""
        }

        "Internet Information Services" {
            Write-LogMessage "Installing IIS using DISM..." -Level INFO
            $installObject.DefaultExe = "C:\WINDOWS\system32\Dism.exe"
            $installObject.Args = "/Online /Enable-Feature /FeatureName:IIS-WebServerRole /FeatureName:IIS-WebServer /All"
            $null = Start-InstallProcess -AppName $AppName -InstallerPath $installObject.DefaultExe -InstallArgs $installObject.Args
            return ""
        }
        "Internet Information Services Management Console" {
            Write-LogMessage "Installing IIS Management Console using DISM..." -Level INFO
            $installObject.DefaultExe = "C:\WINDOWS\system32\Dism.exe"
            $installObject.Args = "/Online /Enable-Feature /FeatureName:IIS-ManagementConsole /All"
            $null = Start-InstallProcess -AppName $AppName -InstallerPath $installObject.DefaultExe -InstallArgs $installObject.Args
            return ""
        }
        "Python" {
            $installObject.IsInstalledCheck = if ($(Get-Command -Name "py" -ErrorAction SilentlyContinue) ?? "") { $true.ToString().ToLower() } else { $false.ToString().ToLower() }
            $installObject.DefaultExe = "python-3.13.3-amd64.exe"
            if ([string]::IsNullOrEmpty($InstallArgs)) {
                $installObject.Args = "/quiet InstallAllUsers=1 PrependPath=1 Include_launcher=1"
            }
            else {
                $installObject.Args = $InstallArgs
            }
        }
        "Sysinternals Suite" {
            $installObject.IsInstalledCheck = $(Get-Command -Name "handle64.exe" -ErrorAction SilentlyContinue) ?? ""
            $installObject.Args = $InstallArgs
        }
        "PostgreSQL.18" {
            $installObject.IsInstalledCheck = if ($(Get-Command -Name "psql" -ErrorAction SilentlyContinue) ?? "") { $true.ToString().ToLower() } else { $false.ToString().ToLower() }
            if ([string]::IsNullOrEmpty($InstallArgs)) {
                # Retrieve the installing user's plaintext password for the service account
                Import-Module Infrastructure -Force -ErrorAction SilentlyContinue
                $servicePassword = Get-SecureStringUserPasswordAsPlainText
                if ([string]::IsNullOrEmpty($servicePassword)) {
                    Write-LogMessage "Could not retrieve service password for PostgreSQL installation. Aborting." -Level ERROR
                    return ""
                }
                $serviceAccount = "DEDGE\$($env:USERNAME)"

                # Ensure data directory exists before installation
                $pgDataDir = "E:\pg"
                if (Test-Path "E:\") {
                    if (-not (Test-Path $pgDataDir)) {
                        New-Item -ItemType Directory -Path $pgDataDir -Force | Out-Null
                        Write-LogMessage "Created PostgreSQL data directory: $($pgDataDir)" -Level INFO
                    }
                    # If PostgreSQL is installed but data dir is NOT on E:\pg, force reinstall
                    $pgConfOnE = Test-Path (Join-Path $pgDataDir "postgresql.conf") -PathType Leaf
                    if (-not $pgConfOnE -and $installObject.IsInstalledCheck -eq "true") {
                        Write-LogMessage "PostgreSQL installed but data directory not at $($pgDataDir) - forcing reinstall" -Level WARN
                        $Force = $true
                    }
                }
                else {
                    # E: drive not available, fall back to default
                    $pgDataDir = "C:\Program Files\PostgreSQL\18\data"
                    Write-LogMessage "E:\ drive not found - using default data directory: $($pgDataDir)" -Level WARN
                }

                # --superaccount/superpassword = database superuser (always "postgres")
                # --serviceaccount/servicepassword = OS user that runs the Windows service
                $installObject.Args = @(
                    "--mode unattended"
                    "--unattendedmodeui minimal"
                    "--superaccount `"postgres`""
                    "--superpassword `"postgres`""
                    "--serviceaccount `"$($serviceAccount)`""
                    "--servicepassword `"$($servicePassword)`""
                    "--datadir `"$($pgDataDir)`""
                    "--serverport 8432"
                    "--enable-components server,pgAdmin,stackbuilder,commandlinetools"
                    "--create_shortcuts 1"
                    "--installer-language en"
                    "--install_runtimes 1"
                ) -join " "
            }
            else {
                $installObject.Args = $InstallArgs
            }
        }

        "PostgreSQL.18.Client" {
            $installObject.IsInstalledCheck = if ($(Get-Command -Name "psql" -ErrorAction SilentlyContinue) ?? "") { $true.ToString().ToLower() } else { $false.ToString().ToLower() }
            if ([string]::IsNullOrEmpty($InstallArgs)) {
                $pgPrefix = "C:\Program Files\PostgreSQL\18"
                $installObject.Args = @(
                    "--mode unattended"
                    "--unattendedmodeui none"
                    "--enable-components commandlinetools"
                    "--disable-components server,pgAdmin,stackbuilder"
                    "--prefix `"$($pgPrefix)`""
                    "--create_shortcuts 1"
                    "--installer-language en"
                    "--install_runtimes 1"
                ) -join " "

                $pgBinPath = "$($pgPrefix)\bin"
                $machinePath = [Environment]::GetEnvironmentVariable("Path", "Machine")
                if ($machinePath -notlike "*$($pgBinPath)*") {
                    $newPath = ($machinePath.TrimEnd(';') + ";$($pgBinPath)")
                    [Environment]::SetEnvironmentVariable("Path", $newPath, "Machine")
                    $env:Path = $env:Path + ";$($pgBinPath)"
                    Write-LogMessage "Added $($pgBinPath) to system PATH" -Level INFO
                }
            }
            else {
                $installObject.Args = $InstallArgs
            }
        }

        Default {

        }
    }
    if (-not [string]::IsNullOrEmpty($installObject.CustomInstallFunction)) {
        & $installObject.CustomInstallFunction
        return ""
    }
    if ($Force -eq $true) {
        Write-LogMessage "$($installObject.AppName) will be reinstalled due to Force flag" -Level INFO
    }
    else {
        if (-not [string]::IsNullOrEmpty($installObject.IsInstalledCheck)) {
            if (Test-IsInstalled -IsInstalledCheck $installObject.IsInstalledCheck) {

                $response = Get-UserConfirmationWithTimeout -PromptMessage "$($installObject.AppName) is already installed. Install anyway?" -TimeoutSeconds 10 -DefaultResponse "N" 
                if ($response.ToUpper() -ne "Y") {
                    if (-not [string]::IsNullOrEmpty($installObject.CustomConfigFunction)) {
                        $configResponse = Get-UserConfirmationWithTimeout -PromptMessage "Do you want to run configuration?" -TimeoutSeconds 10 -DefaultResponse "N"
                        if ($configResponse.ToUpper() -eq "Y") {
                            Invoke-Expression $installObject.CustomConfigFunction
                            if ($LASTEXITCODE -ne 0) {
                                Write-LogMessage "Configuration failed" -Level ERROR
                                Write-ApplicationLog -AppName $AppName -Status "Failed" -Message "Configuration failed"
                            }
                            else {
                                Write-LogMessage "Configuration completed" -Level INFO
                                Write-ApplicationLog -AppName $AppName -Status "Success" -Message "Configuration completed"
                            }
                        }
                    }
                    return ""
                }
            }
        }
    }

    $SourcePath = Join-Path $(Get-WindowsAppsPath) "$AppName"
    if (-not (Test-Path -Path $SourcePath -PathType Container)) {
        Write-LogMessage "Source path not found: $SourcePath. Notify admin." -Level WARN
        return ""
    }
    #Find Last folder name in SourcePath and use it as TempPath using C:\TEMPFK\TempInstallFiles\<foldername>
    $tempPath = Join-Path $defaultTempPath (Split-Path $SourcePath -Leaf)
    $tempPath = $tempPath.Replace(" ", "_")
    # Create temp directory if it doesn't exist
    if (-not (Test-Path -Path $tempPath -PathType Container)) {
        New-Item -Path $tempPath -ItemType Directory -Force | Out-Null
    }
    
    Write-LogMessage "Kopierer installasjonsfiler..." 
    $result = Start-Robocopy -SourceFolder $SourcePath -DestinationFolder $tempPath -Recurse
    if ($result.OperationSuccessful) {
        Write-LogMessage "Vellykket!" -ForegroundColor Green
        Write-ApplicationLog -AppName $AppName -Status "Progress" -Message "Installation files copied successfully"
    }
    else {
        Write-LogMessage "Mislyktes (Feilkode: $($result.RobocopyExitCode) - $($result.ResultMessage))" -Level ERROR     
        Write-ApplicationLog -AppName $AppName -Status "Failed" -Message $("Installation failed with exit code: " + $result.RobocopyExitCode + " - " + $result.ResultMessage)
    }


    # Check if there is a zip file in the temp path and unzip it
    $zipFiles = Get-ChildItem -Path "$tempPath" -Filter "*.zip"
    if ($zipFiles.Count -eq 1) {
        Write-LogMessage "Extracting installation files..." 
        Expand-Archive -Path $zipFiles[0].FullName -DestinationPath $tempPath -Force | Out-Null
    }
    elseif ($zipFiles.Count -gt 1) {
        Write-LogMessage "Multiple zip files found. Opening folder..." 
        Start-Process explorer.exe -ArgumentList $tempPath | Out-Null
        Write-LogMessage "Success!" -ForegroundColor Green
        return
    }
    $executableFile = $null
    # Fine all executable files in the temp path and return the path
    $exeFileList = Get-ChildItem -Path "$tempPath" -Recurse -Include *setup*.msi, *setup*.exe, *setup*.bat, *setup*.cmd
    $exeFileList = $exeFileList | Sort-Object { ($_.FullName -split '\\').Count }, { $_.FullName }
    if ($exeFileList.Count -eq 0) {
        $exeFileList = Get-ChildItem -Path "$tempPath" -Recurse -Include *.msi, *.exe
        $exeFileList = $exeFileList | Sort-Object { ($_.FullName -split '\\').Count }, { $_.FullName }
    }
    elseif ([string]::IsNullOrEmpty($installObject.DefaultExe) -and $exeFileList.Count -eq 1) {
        $executableFile = $exeFileList[0]
    }
    elseif (-not [string]::IsNullOrEmpty($installObject.DefaultExe)) {
        $tempExeFiles = $exeFileList | Where-Object { $_.Name -eq $installObject.DefaultExe }
        if ($tempExeFiles.Count -eq 1) {
            Write-LogMessage "Found installation file: $($tempExeFiles.FullName)" -Level INFO
            $executableFile = $tempExeFiles
            $exeFileList = $tempExeFiles
        }
        else {
            Write-LogMessage "Multiple installation files found. Choose one of the following:" -Level WARN
            $exeFileList = $tempExeFiles
        }
    }

    # If executable file hasn't been determined yet, handle selection or error cases
    if ([string]::IsNullOrEmpty($executableFile)) {
        # If no exe files are found, open the temp path
        if ($exeFileList.Count -eq 0) {
            Write-LogMessage "No installation files found" -Level WARN
            Write-LogMessage "Opening folder..." -ForegroundColor Green
            Start-Process explorer.exe -ArgumentList $tempPath
            return ""
        }
        # If exactly one exe file is found, use it
        elseif ($exeFileList.Count -eq 1) {
            Write-LogMessage "Found installation file: $($exeFileList[0].FullName)" -Level INFO
            $executableFile = $exeFileList[0]
        }
        # If more than one exe file is found, show menu of executable files with numbers
        elseif ($exeFileList.Count -gt 1) {
            # Show menu of executable files with numbers
            Write-LogMessage "Available installation files:"
            $fileList = foreach ($i in 0..($exeFileList.Count - 1)) {
                [PSCustomObject]@{
                    Number = $i + 1
                    Name   = $exeFileList[$i].Name 
                    Path   = $exeFileList[$i].FullName
                }
            }
            # Sort filelist by asc fewest \
            
            $result = $fileList | Format-Table -AutoSize -Property *  | Out-String
            Write-LogMessage $result -ForegroundColor Green
    
            # Get user choice
            do {
                $choice = Read-Host "Select number (1-$($exeFileList.Count))"
            } while (-not ($choice -match '^\d+$' -and [int]$choice -ge 1 -and [int]$choice -le $exeFileList.Count))
    
            $executableFile = $exeFileList[[int]$choice - 1]
        }
    }
    
    # Final check: ensure we have an executable file
    if ([string]::IsNullOrEmpty($executableFile)) {
        Write-LogMessage "No installation file could be determined for $($AppName)" -Level ERROR
        Write-LogMessage "Opening folder in Explorer for manual installation..." -Level WARN
        Start-Process "explorer.exe" -ArgumentList "$tempPath"
        Write-ApplicationLog -AppName $AppName -Status "Failed" -Message "No installation file could be determined"
        return ""
    }
    
    Write-LogMessage "Starting installation with: $($executableFile.FullName)" -Level INFO
    $result = Start-InstallProcess -AppName $AppName -InstallerPath $executableFile.FullName -InstallArgs $installObject.Args -CustomConfigFunction $installObject.CustomConfigFunction
    if (-not $result) {
        Write-LogMessage "Installation failed or missing configuration. Opening folder in Explorer..." -Level WARN
        Start-Process "explorer.exe" -ArgumentList "$tempPath"
    }
}


function Remove-ExistingVSCode {
    if (-not (Test-IsServer)) {
        return
    }
    Write-LogMessage "Checking for VS Code on user" -Level INFO
    if (Test-Path "$env:USERPROFILE\AppData\Local\Programs\Microsoft VS Code\unins000.exe") {
        Start-Process -FilePath "$env:USERPROFILE\AppData\Local\Programs\Microsoft VS Code\unins000.exe" -ArgumentList "/SILENT" -Wait -ErrorAction SilentlyContinue
        Write-LogMessage "Uninstalled VS Code for current user" -Level INFO       
    }
    else {
        Write-LogMessage "VS Code user installation not found" -Level INFO
    }
    
    # Write-LogMessage "Checking for VS Code on machine" -Level INFO
    # if (Test-Path "C:\Program Files\Microsoft VS Code\unins000.exe") {
    #     Start-Process -FilePath "C:\Program Files\Microsoft VS Code\unins000.exe" -ArgumentList "/SILENT" -Wait -ErrorAction SilentlyContinue
    #     Write-LogMessage "Uninstalled VS Code for current machine" -Level INFO
    # }
    # else {
    #     Write-LogMessage "VS Code user installation not found" -Level INFO
    # }       
    # Write-LogMessage "Checking for VS Code on machine" -Level INFO
    # if (Test-Path "C:\Program Files\Microsoft VS Code (x86)\unins000.exe") {
    #     Start-Process -FilePath "C:\Program Files\Microsoft VS Code (x86)\unins000.exe" -ArgumentList "/SILENT" -Wait -ErrorAction SilentlyContinue
    #     Write-LogMessage "Uninstalled VS Code for current machine" -Level INFO
    # }
    # else {
    #     Write-LogMessage "VS Code user installation not found" -Level INFO
    # }   
}


function Install-SelectedApps {
    param (
        [Parameter(Mandatory = $false)]
        [ValidateSet("--All", "--OurPsh", "--OurWin", "--Windows", "--Winget", "All", "FkPsh", "FkWin", "Windows", "Winget", "WinCapabilities")]
        [string]$AppType = "--All",
        [Parameter(Mandatory = $false)]
        [string]$Options = ""
    )
    if ($AppType) {
        $AppType = $AppType.TrimStart("--") 
    }
    if ($Options) {
        $Options = $Options.TrimStart("--")  
    }
    $appObjects = @()
    if ($AppType -eq "All" -or $AppType -eq "Winget") {
        $appsPath = $(Get-WingetAppsPath)
        $apps = Get-ChildItem -Path $appsPath
        $appObjects = @()
        foreach ($app in $apps) {
            $appObjects += [PSCustomObject]@{
                Name = $app.Name
                Type = "Winget Apps"
            }
        }
    }
    if ($AppType -eq "All" -or $AppType -eq "Windows") {
        $appsPath = $(Get-WindowsAppsPath)
        $apps = Get-ChildItem -Path $appsPath
        foreach ($app in $apps) {
            $appObjects += [PSCustomObject]@{
                Name = $app.Name
                Type = "Windows Apps"
            }
        }
        $appObjects += [PSCustomObject]@{
            Name = "Internet Information Services"
            Type = "Windows Apps"
        }
        $appObjects += [PSCustomObject]@{
            Name = "Internet Information Services Management Console" 
            Type = "Windows Apps"
        }
    }   
    if ($AppType -eq "All" -or $AppType -eq "FkWin") {
        $appsPath = $(Get-WindowsDefaultAppsPath)
        $apps = Get-ChildItem -Path $appsPath
        foreach ($app in $apps) {
            $appObjects += [PSCustomObject]@{
                Name = $app.Name
                Type = "FK Windows Apps"
            }
        }
    }
    if ($AppType -eq "All" -or $AppType -eq "FkPsh") {
        $appsPath = $(Get-PowershellDefaultAppsPath)
        $apps = Get-ChildItem -Path $appsPath
        foreach ($app in $apps) {
            $appObjects += [PSCustomObject]@{
                Name = $app.Name
                Type = "FK PowerShell Apps"
            }
        }
    }   
    # try {
    #     if ($AppType -eq "All" -or $AppType -eq "WinCapabilities") {
    #         $apps = & $env:SystemRoot\System32\dism.exe /Online /Get-Capabilities 
    #         foreach ($app in $apps) {
    #             $appObjects += [PSCustomObject]@{
    #                 Name = $app.Name
    #                 Type = "Windows Capabilities"
    #             }
    #         }
    #     }
    # }
    # catch {
    #     Write-LogMessage "Error getting Windows capabilities" -Level WARN
    # }
    if ($Options -eq "updateAll") {
        if ($AppType -eq "FkPsh") {
            Update-AllOurPshApps
        }
        elseif ($AppType -eq "FkWin") {
            Update-AllOurWinApps
        }
        else {
            Write-LogMessage "Invalid update for type $AppType" -Level WARN
            return
        }
    }
    Add-Type -AssemblyName System.Windows.Forms
    Add-Type -AssemblyName System.Drawing

    $form = New-Object System.Windows.Forms.Form
    $form.Text = 'Select Apps to Install'
    $form.Size = New-Object System.Drawing.Size(620, 700)
    $form.StartPosition = 'Manual'
    $form.Location = New-Object System.Drawing.Point(0, 0)
  
    $okButton = New-Object System.Windows.Forms.Button
    $okButton.Location = New-Object System.Drawing.Point(175, 620)
    $okButton.Size = New-Object System.Drawing.Size(75, 23)
    $okButton.Text = 'OK'
    $okButton.DialogResult = [System.Windows.Forms.DialogResult]::OK
    $form.AcceptButton = $okButton
    $form.Controls.Add($okButton)
  
    $cancelButton = New-Object System.Windows.Forms.Button
    $cancelButton.Location = New-Object System.Drawing.Point(250, 620)
    $cancelButton.Size = New-Object System.Drawing.Size(75, 23)
    $cancelButton.Text = 'Cancel'
    $cancelButton.DialogResult = [System.Windows.Forms.DialogResult]::Cancel
    $form.CancelButton = $cancelButton
    $form.Controls.Add($cancelButton)
  
    $label = New-Object System.Windows.Forms.Label
    $label.Location = New-Object System.Drawing.Point(10, 20)
    $label.Size = New-Object System.Drawing.Size(280, 20)
    $label.Text = 'Please select apps to install:'
    $form.Controls.Add($label)

    # Create ListView instead of CheckedListBox
    $listView = New-Object System.Windows.Forms.ListView
    $listView.Location = New-Object System.Drawing.Point(10, 40)
    $listView.Size = New-Object System.Drawing.Size(560, 550)
    $listView.View = [System.Windows.Forms.View]::Details
    $listView.CheckBoxes = $true
    $listView.FullRowSelect = $true

    # Add columns
    $listView.Columns.Add("App", 280) | Out-Null
    $listView.Columns.Add("Type", 260) | Out-Null

    # Add items
    foreach ($app in $appObjects) {
        $item = New-Object System.Windows.Forms.ListViewItem($app.Name)
        $item.SubItems.Add($app.Type) | Out-Null
        $listView.Items.Add($item) | Out-Null
    }

    $form.Controls.Add($listView)
    $form.Topmost = $true
  
    $result = $form.ShowDialog()
  
    if ($result -eq [System.Windows.Forms.DialogResult]::OK) {
        $selectedApps = $listView.CheckedItems
        foreach ($app in $selectedApps) {
            if ($app.SubItems[1].Text -eq "Winget Apps") {
                Install-WingetPackage -AppName $app.Text -Force
            }
            elseif ($app.SubItems[1].Text -eq "Windows Apps") {
                Install-WindowsApps -AppName $app.Text -Force
            }
            elseif ($app.SubItems[1].Text -eq "FK Windows Apps") {
                Install-OurWinApp -AppName $app.Text
            }
            elseif ($app.SubItems[1].Text -eq "FK PowerShell Apps") {
                Install-OurPshApp -AppName $app.Text 
            }
        }
    }
    # Console report of installed apps and types
    Write-LogMessage "Installed apps and types:" -Level INFO
    foreach ($app in $selectedApps) {
        Write-LogMessage "$($app.Text) - $($app.SubItems[1].Text)" -Level INFO
    }
}

function Start-OurPshApp {
    <#
    .SYNOPSIS
        Starts a Dedge PowerShell application, installing it first if needed.
    .PARAMETER AppName
        The name of the PowerShell application to start. Use --list to see available apps.
    .PARAMETER Arguments
        Optional array of arguments to pass to the application.
    #>
    param (
        [Parameter(Mandatory = $false)]
        [string]$AppName = "",
        [Parameter(Mandatory = $false, ValueFromRemainingArguments = $true)]
        [object[]]$Arguments
    )
    $appNameFile = ""
    $countBackSlash = ($AppName.Split("\").Count - 1)
    $countForwardSlash = ($AppName.Split("/").Count - 1)
    $countDot = ($AppName.Split(".").Count - 1)
    $countDotPs1 = ($AppName.ToLower().Split(".ps1").Count - 1)
    if ($countBackSlash -eq 1 -and $countForwardSlash -eq 0 -and $countDot -eq 0 -and $countDotPs1 -eq 0) {
        $appNameFile = $AppName.Split("\")[1] + ".ps1"
        $AppName = $AppName.Split("\")[0]
    }
    elseif ($countBackSlash -eq 0 -and $countForwardSlash -eq 1 -and $countDot -eq 0 -and $countDotPs1 -eq 0) {
        $appNameFile = $AppName.Split("/")[1] + ".ps1"
        $AppName = $AppName.Split("/")[0]
    }
    elseif ($countBackSlash -eq 0 -and $countForwardSlash -eq 0 -and $countDot -eq 1 -and $countDotPs1 -eq 0) {
        $appNameFile = $AppName.Split(".")[1] + ".ps1"
        $AppName = $AppName.Split(".")[0]
    }
    else {
        $appNameFile = ""
    }


    # Make sure boolean parameters are handled properly
    $processedArgs = @()
    for ($i = 0; $i -lt $Arguments.Count; $i++) {
        $arg = $Arguments[$i]
        $processedArgs += $arg
        
        # If this is a potential boolean parameter (ending with ":$true" or ":$false"), handle it
        if ($i + 1 -lt $Arguments.Count) {
            if ($Arguments[$i + 1] -eq "true" -or $Arguments[$i + 1] -eq "false") {
                # Write-Host "  (Converting '$($Arguments[$i + 1])' to boolean for parameter '$arg')" -ForegroundColor Yellow
            }
        }
    }
    if ([string]::IsNullOrEmpty($AppName)) {
        Write-LogMessage "No AppName provided" -Level WARN
        return
    }

    # Add debugging output
    Write-Host "Start-OurPshApp started with AppName: $AppName" -ForegroundColor Green
    # Write-Host "Arguments received by Start-OurPshApp:" -ForegroundColor Green
    # foreach ($arg in $Arguments) {
    #     Write-Host "  $arg" -ForegroundColor Green
    # }

    $appsPath = "$env:OptPath\DedgePshApps"
    $apps = @()
    $installedApps = @()
    $availableApps = @()
    if (Test-Path $appsPath) {
        $appsElements = Get-ChildItem -Path $appsPath -Directory | Select-Object Name, FullName
        foreach ($app in $appsElements) {
            $installedApps += [PSCustomObject]@{
                Name = $app.Name
                Type = "Installed FkPshApp"
                Path = $app.Directory
            }
        }
    }
    $appsPath = Get-PowershellDefaultAppsPath
    if (Test-Path $appsPath) {
        $appsElements = Get-ChildItem -Path $appsPath -Directory | Select-Object Name, FullName
        foreach ($app in $appsElements) {
            if (-not ($apps | Where-Object { $_.Name -eq $app.Name -and $_.Type -eq "Installed FkPshApp" })) {
                $availableApps += [PSCustomObject]@{
                    Name = $app.Name
                    Type = "Available FkPshApp"
                    Path = $app.Directory
                }
            }
        }

        $allApps = @()
        $allApps += $installedApps
        $allApps += $availableApps
        if ($AppName -eq "--list" -or $AppName -eq "-list" -or $AppName -eq "/list") {
            Write-LogMessage "Available FK PowerShell Apps:" -Level INFO
            $tableOutput = $allApps | Format-Table -AutoSize -Property * | Out-String
            Write-LogMessage $tableOutput -Level INFO
            return
        }
        
        if ($installedApps | Where-Object { $_.Name -eq $AppName }) {
            Write-LogMessage "Running $AppName" -Level INFO
        }
        else {
            Write-LogMessage  "Installing $AppName" -Level INFO
            $obj = [PSCustomObject]@{
                Name = $AppName
                Type = "Installed FkPshApp"
                Path = $(Install-OurPshApp -AppName $AppName)
            }
            #Update the apps list to set app as local
            $availableApps | Where-Object { $_.Name -ne $AppName }
            $allApps = @()
            $installedApps += $obj 
            $availableApps | Where-Object { $_.Name -ne $AppName }
            $allApps = @()
            $allApps += $installedApps
            $allApps += $availableApps

            Write-LogMessage "Running $AppName" -Level INFO

        }
        
        
        if ($installedApps | Where-Object { $_.Name -eq $AppName }) {
            Write-LogMessage "Running $AppName" -Level INFO
        }
        else {
            Write-LogMessage  "Installing $AppName" -Level INFO
            $installedApps += [PSCustomObject]@{
                Name = $app.Name
                Type = "Installed FkPshApp"
                Path = $(Install-OurPshApp -AppName $AppName)
            }
            #Update the apps list to set app as local
    
            
        }


        $currentApp = $installedApps | Where-Object { $_.Name -eq $AppName }

        if (-not $currentApp) {
            Write-LogMessage "App still not installed" -Level WARN
            return
        }

        # . Source the app script
        $appFolder = Join-Path $env:OptPath "DedgePshApps" $AppName
        if (-not [string]::IsNullOrEmpty($appNameFile)) {
            $scriptPath = Join-Path $appFolder $appNameFile
        }
        else {
            $scriptPath = Join-Path $appFolder "$AppName.ps1"
        }
        Write-Host "Target script path: $scriptPath" -ForegroundColor Green
        
        if (-not (Test-Path $scriptPath -PathType Leaf)) {
            $availableScripts = @(Get-ChildItem -Path $appFolder -Filter "*.ps1" | Where-Object { $_.Name -notlike '_*' })
            if ($availableScripts.Count -eq 0) {
                Write-LogMessage "No runnable scripts found in folder $($AppName)" -Level WARN
                return
            }
            elseif ($availableScripts.Count -eq 1) {
                $scriptPath = $availableScripts[0].FullName
                Write-LogMessage "Auto-selecting only available script: $($availableScripts[0].Name)" -Level INFO
            }
            else {
                Write-LogMessage "Please select from available scripts in folder $($AppName):" -Level WARN
                for ($i = 0; $i -lt $availableScripts.Count; $i++) {
                    Write-LogMessage "[$($i + 1)] $($availableScripts[$i].Name)" -Level INFO
                }
                $choice = Read-Host "Select script number"
                if ($choice -match '^\d+$' -and [int]$choice -ge 1 -and [int]$choice -le $availableScripts.Count) {
                    $scriptPath = $availableScripts[[int]$choice - 1].FullName
                }
                else {
                    Write-LogMessage "Invalid choice" -Level WARN
                    return
                }
            }
        }
   
        if ($Arguments.Count -gt 0) {
            # Script has parameters, pass arguments accordingly
            # Write-Host "About to execute: $scriptPath with these arguments:" -ForegroundColor Green
            # foreach ($arg in $Arguments) {
            #     Write-Host "  $arg" -ForegroundColor Green
            # }
            
            # Create a parameter hashtable from the arguments array
            $paramHashtable = @{}
            for ($i = 0; $i -lt $Arguments.Count; $i += 2) {
                if ($i + 1 -lt $Arguments.Count) {
                    $paramName = $Arguments[$i].TrimStart('-')
                    $paramValue = $Arguments[$i + 1]
                    
                    # Handle boolean parameters specially
                    if ($paramValue -eq "true" -or $paramValue -eq "$true") {
                        $paramValue = $true
                    }
                    elseif ($paramValue -eq "false" -or $paramValue -eq "$false") {
                        $paramValue = $false
                    }
                    
                    $paramHashtable[$paramName] = $paramValue
                }
            }
            
            Write-Host "Constructed parameter hashtable:" -ForegroundColor Magenta
            foreach ($key in $paramHashtable.Keys) {
                Write-Host "  $key = $($paramHashtable[$key]) (Type: $($paramHashtable[$key].GetType().Name))" -ForegroundColor Magenta
            }
            
            # Call the script with the parameter hashtable
            Invoke-Expression $scriptPath @paramHashtable
            if ($LASTEXITCODE -ne 0) {
                Write-Host "Script failed with exit code $LASTEXITCODE" -ForegroundColor Red
                Write-ApplicationLog -AppName $AppName -Status "Failed" -Message "Script failed with exit code $LASTEXITCODE"
            }
            else {
                Write-ApplicationLog -AppName $AppName -Status "Success" -Message "Script executed successfully"
            }
        }
        else {
            # No arguments to pass
            Write-Host "About to execute: $scriptPath with no arguments" -ForegroundColor Green
            Invoke-Expression $scriptPath
            if ($LASTEXITCODE -ne 0) {
                Write-Host "Script failed with exit code $LASTEXITCODE" -ForegroundColor Red
                Write-ApplicationLog -AppName $AppName -Status "Failed" -Message "Script failed with exit code $LASTEXITCODE"
            }
            else {
                Write-ApplicationLog -AppName $AppName -Status "Success" -Message "Script executed successfully"
            }
        }
    }
}


function Copy-Repository {
    param (
        [string]$repoName,
        [string]$repoUrl,
        [string]$DestinationRoot = "$env:OptPath\src"
    )

    $targetPath = Join-Path $DestinationRoot $repoName
    Write-Host "`nKloner $repoName..." -NoNewline

    try {
        if (Test-Path -Path $targetPath) {
            Write-Host " Eksisterer allerede (hopper over)" -ForegroundColor DarkGray
            return
        }
        git clone $repoUrl $targetPath
        Write-Host " Vellykket!" -ForegroundColor Green
    }
    catch {
        Write-Host " Mislyktes: $_" -ForegroundColor Red
    }
}


##########################################################################################################################
# Repositories
# ##########################################################################################################################
# function Copy-AzureRepos {
#     Clear-Host
#     Write-Host "Azure DevOps Repositories`n" -ForegroundColor Cyan

#     # Azure DevOps Organization and Project details
#     $organization = "Dedge"
#     $project = "Dedge"
#     $apiVersion = "7.1"  # API version
#     $personalAccessToken = "f53cdny64fbuehfy3rofdbz5mxgjnvhlxwmgbjrazg745uey4euq" # Your Personal Access Token with appropriate permissions

#     # Encode PAT for Authorization in the header
#     $base64AuthInfo = [Convert]::ToBase64String([Text.Encoding]::ASCII.GetBytes(":$personalAccessToken"))
#     $headers = @{
#         Authorization = "Basic $base64AuthInfo"
#     }

#     # Get the list of repositories
#     $reposUrl = "https://dev.azure.com/$organization/$project/_apis/git/repositories?api-version=$apiVersion"
#     $reposResponse = Invoke-RestMethod -Uri $reposUrl -Method Get -Headers $headers
#     $repos = $reposResponse.value

#     # Check if git is installed
#     if (-not (Get-Command "git.exe" -ErrorAction SilentlyContinue)) {
#         Write-Host "Git er ikke installert. Installer Git først." -ForegroundColor Red
#         return
#     }

#     # Create source directory if it doesn't exist
#     $srcPath = "$env:OptPath\src"
#     if (-not (Test-Path -Path $srcPath -PathType Container)) {
#         New-Item -Path $srcPath -ItemType Directory -Force | Out-Null
#     }

#     Write-Host "Tilgjengelige repositories:"
#     Write-Host "0. Klon alle repositories"
#     for ($i = 0; $i -lt $repos.Count; $i++) {
#         Write-Host "$($i + 1). $($repos[$i].name)"
#     }
#     Write-Host "`nX. Tilbake til hovedmeny"

#     $selectedIndices = @()
#     while ($true) {
#         $choice = Read-Host "`nVelg repository å klone (0-$($repos.Count), eller X for å gå tilbake, blank for å starte kloning)"

#         if ($choice -eq "") {
#             if ($selectedIndices.Count -eq 0) {
#                 Write-Host "Ingen repositories valgt. Avslutter." -ForegroundColor Yellow
#                 return
#             }
#             Write-Host "`nValgte repositories for kloning:"
#             foreach ($index in $selectedIndices) {
#                 Write-Host "- $($repos[$index].name)"
#             }
#             $confirm = Read-Host "`nBekreft kloning (Y/N)"
#             if ($confirm.ToUpper() -eq "Y" -or $confirm.ToUpper() -eq "J") {
#                 break
#             }
#             else {
#                 $selectedIndices.Clear()
#                 Write-Host "Valg tilbakestilt. Velg på nytt."
#             }
#         }
#         elseif ($choice.ToUpper() -eq "X") {
#             return
#         }
#         elseif ($choice -eq "0") {
#             Write-Host "`nKloner alle repositories..." -ForegroundColor Cyan
#             foreach ($repo in $repos) {
#                 Copy-Repository $repo.name $repo.remoteUrl
#             }
#             return
#         }
#         else {
#             $index = [int]$choice - 1
#             if ($index -ge 0 -and $index -lt $repos.Count) {
#                 if ($selectedIndices.Contains($index)) {
#                     $selectedIndices = $selectedIndices | Where-Object { $_ -ne $index }
#                     Write-Host "Fjernet: $($repos[$index].name)"
#                 }
#                 else {
#                     $selectedIndices += $index
#                     Write-Host "Lagt til: $($repos[$index].name)"
#                 }
#             }
#             else {
#                 Write-Host "Ugyldig valg" -ForegroundColor Red
#             }
#         }
#     }

#     Write-Host "`nStarter kloning av valgte repositories..." -ForegroundColor Cyan
#     foreach ($index in $selectedIndices) {
#         Copy-Repository $repos[$index].name $repos[$index].remoteUrl
#     }
# }

# function Copy-Repository {
#     param (
#         [string]$repoName,
#         [string]$repoUrl
#     )

#     $targetPath = Join-Path "$env:OptPath\src" $repoName
#     Write-Host "`nKloner $repoName..." -NoNewline

#     try {
#         if (Test-Path -Path $targetPath) {
#             Write-Host " Eksisterer allerede" -ForegroundColor Yellow
#             Write-Host "Oppdaterer eksisterende repository..." -NoNewline
#             Push-Location $targetPath
#             git pull
#             Pop-Location
#             Write-Host " Vellykket!" -ForegroundColor Green
#         }
#         else {
#             git clone $repoUrl $targetPath
#             Write-Host " Vellykket!" -ForegroundColor Green
#         }
#     }
#     catch {
#         Write-Host " Mislyktes: $_" -ForegroundColor Red
#     }
# }




function Copy-AzureRepos {
    param (
        [bool]$CloneAll = $false,
        [string]$TargetPath = ""
    )

    try { Clear-Host } catch { }
    Write-Host "Azure DevOps Repositories`n" -ForegroundColor Cyan

    # Azure DevOps Organization and Project details
    $organization = "Dedge"
    $project = "Dedge"
    $apiVersion = "7.1"  # API version
    $personalAccessToken = "f53cdny64fbuehfy3rofdbz5mxgjnvhlxwmgbjrazg745uey4euq" # Your Personal Access Token with appropriate permissions

    # Encode PAT for Authorization in the header
    $base64AuthInfo = [Convert]::ToBase64String([Text.Encoding]::ASCII.GetBytes(":$personalAccessToken"))
    $headers = @{
        Authorization = "Basic $base64AuthInfo"
    }

    # Get the list of repositories
    $reposUrl = "https://dev.azure.com/$organization/$project/_apis/git/repositories?api-version=$apiVersion"
    $reposResponse = Invoke-RestMethod -Uri $reposUrl -Method Get -Headers $headers
    $repos = $reposResponse.value

    # Check if git is installed
    if (-not (Get-Command "git.exe" -ErrorAction SilentlyContinue)) {
        Write-Host "Git er ikke installert. Installer Git først." -ForegroundColor Red
        return
    }

    # Create source directory if it doesn't exist
    $srcPath = if ([string]::IsNullOrWhiteSpace($TargetPath)) { "$env:OptPath\src" } else { $TargetPath }
    if (-not (Test-Path -Path $srcPath -PathType Container)) {
        New-Item -Path $srcPath -ItemType Directory -Force | Out-Null
    }

    if ($CloneAll) {
        Write-Host "`nKloner alle repositories..." -ForegroundColor Cyan
        foreach ($repo in $repos) {
            Copy-Repository -repoName $repo.name -repoUrl $repo.remoteUrl -DestinationRoot $srcPath
        }
        return
    }

    Write-Host "Tilgjengelige repositories:"
    Write-Host "0. Klon alle repositories"
    for ($i = 0; $i -lt $repos.Count; $i++) {
        Write-Host "$($i + 1). $($repos[$i].name)"
    }
    Write-Host "`nX. Tilbake til hovedmeny"

    $selectedIndices = @()
    while ($true) {
        $choice = Read-Host "`nVelg repository å klone (0-$($repos.Count), eller X for å gå tilbake, blank for å starte kloning)"

        if ($choice -eq "") {
            if ($selectedIndices.Count -eq 0) {
                Write-Host "Ingen repositories valgt. Avslutter." -ForegroundColor Yellow
                return
            }
            Write-Host "`nValgte repositories for kloning:"
            foreach ($index in $selectedIndices) {
                Write-Host "- $($repos[$index].name)"
            }
            $confirm = Read-Host "`nBekreft kloning (Y/N)"
            if ($confirm.ToUpper() -eq "Y" -or $confirm.ToUpper() -eq "J") {
                break
            }
            else {
                $selectedIndices.Clear()
                Write-Host "Valg tilbakestilt. Velg på nytt."
            }
        }
        elseif ($choice.ToUpper() -eq "X") {
            return
        }
        elseif ($choice -eq "0") {
            Write-Host "`nKloner alle repositories..." -ForegroundColor Cyan
            foreach ($repo in $repos) {
                Copy-Repository -repoName $repo.name -repoUrl $repo.remoteUrl -DestinationRoot $srcPath
            }
            return
        }
        else {
            $index = [int]$choice - 1
            if ($index -ge 0 -and $index -lt $repos.Count) {
                if ($selectedIndices.Contains($index)) {
                    $selectedIndices = $selectedIndices | Where-Object { $_ -ne $index }
                    Write-Host "Fjernet: $($repos[$index].name)"
                }
                else {
                    $selectedIndices += $index
                    Write-Host "Lagt til: $($repos[$index].name)"
                }
            }
            else {
                Write-Host "Ugyldig valg" -ForegroundColor Red
            }
        }
    }

    Write-Host "`nStarter kloning av valgte repositories..." -ForegroundColor Cyan
    foreach ($index in $selectedIndices) {
        Copy-Repository -repoName $repos[$index].name -repoUrl $repos[$index].remoteUrl -DestinationRoot $srcPath
    }
}
# Export the functions that should be available when importing the module
function Set-DefaultTerminalToConsoleHost {    
    try {    
        Write-LogMessage "Setting default terminal to Windows Console Host" -Level INFO
        $regPath = "HKCU:\Console\%Startup"
        Write-LogMessage "Checking if registry path exists: $regPath" -Level DEBUG
        
        # Create the registry key if it does not exist
        if (-not (Test-Path $regPath)) {
            Write-Verbose "Registry path '$regPath' not found. Creating it."
            Write-LogMessage "Registry path '$regPath' not found. Creating it." -Level DEBUG
            New-Item -Path "HKCU:\Console" -Name "%Startup" -Force | Out-Null
            Write-LogMessage "Created registry path: $regPath" -Level DEBUG
        }
        else {
            Write-LogMessage "Registry path already exists: $regPath" -Level DEBUG
        }
        
        # Set the registry values to make Windows Console Host the default terminal
        Write-Verbose "Setting DelegationConsole and DelegationTerminal values."
        Write-LogMessage "Setting DelegationConsole and DelegationTerminal values" -Level DEBUG

        $consoleHostGuid = "{00000000-0000-0000-0000-000000000000}"
        Write-LogMessage "Using console host GUID: $consoleHostGuid" -Level DEBUG
        
        Set-ItemProperty -Path $regPath -Name "DelegationConsole" -Value $consoleHostGuid -Type String -Force
        Write-LogMessage "Set DelegationConsole to: $consoleHostGuid" -Level DEBUG
        
        Set-ItemProperty -Path $regPath -Name "DelegationTerminal" -Value $consoleHostGuid -Type String -Force
        Write-LogMessage "Set DelegationTerminal to: $consoleHostGuid" -Level DEBUG
        
        Write-LogMessage "Successfully configured Windows Console Host as default terminal" -Level INFO

    }
    catch {
        Write-LogMessage "Failed to set default terminal to Console Host" -Level ERROR -Exception $_
    } 
}

function Add-DesktopShortcut(
    [Parameter(Mandatory = $true)]
    [string]$ShortcutName,
    [Parameter(Mandatory = $true)]
    [string]$TargetPath,
    [Parameter(Mandatory = $false)]
    [string]$Arguments = "",
    [Parameter(Mandatory = $false)]
    [string]$IconPath = "",
    [Parameter(Mandatory = $false)]
    [string]$WorkingDirectory = "",
    [Parameter(Mandatory = $false)]
    [switch]$RunAsAdmin
) {
    try {
        Write-LogMessage "Creating shortcut $ShortcutName at Desktop" -Level INFO
        
        # Try multiple desktop locations (OneDrive, standard Desktop, Norwegian "Skrivebord")
        $desktopPath = @(
            "$env:USERPROFILE\OneDrive - Dedge AS\Skrivebord",
            "$env:USERPROFILE\Desktop",
            "$env:USERPROFILE\Skrivebord",
            [Environment]::GetFolderPath('Desktop')
        ) | Where-Object { -not [string]::IsNullOrEmpty($_) -and (Test-Path $_ -PathType Container) } | Select-Object -First 1
        
        if ([string]::IsNullOrEmpty($desktopPath)) {
            throw "Could not find desktop folder. Tried: OneDrive Skrivebord, Desktop, and Skrivebord"
        }
        
        # Validate target path exists
        if (-not (Test-Path $TargetPath -PathType Leaf)) {
            throw "Target path does not exist: $TargetPath"
        }

        $shortcutPath = Join-Path $desktopPath "$ShortcutName.lnk"
        
        # Remove existing shortcut if present
        if (Test-Path $shortcutPath -PathType Leaf) {
            Remove-Item $shortcutPath -Force -ErrorAction SilentlyContinue
            Write-LogMessage "Removed existing shortcut at $shortcutPath" -Level DEBUG
        }
        
        # Create COM object for shortcut creation.
        # NOTE: This can fail in non-STA contexts (common when running under PowerShell 7 / jobs).
        $wscriptShell = $null
        $shortcut = $null
        try {
            $wscriptShell = New-Object -ComObject WScript.Shell
        }
        catch {
            Write-LogMessage "Failed to create WScript.Shell COM object in current session; will try STA fallback" -Level WARN -Exception $_
        }

        if ($null -ne $wscriptShell) {
            $shortcut = $wscriptShell.CreateShortcut($shortcutPath)
            if ($null -eq $shortcut) {
                throw "Failed to create shortcut object"
            }
            $shortcut.TargetPath = $TargetPath
        }
        
        # FIXED: Added missing $ sign
        if ($TargetPath.ToLower().Contains(".exe") -and [string]::IsNullOrEmpty($IconPath)) {
            $IconPath = $TargetPath
        }
     
        # If COM shortcut object is available, configure & save in-process.
        if ($null -ne $shortcut) {
            if (-not [string]::IsNullOrEmpty($IconPath)) {
                # IconLocation format must be "path,index" - use index 0 for .ico/.exe files
                $shortcut.IconLocation = "$IconPath,0"
            }

            # Set arguments if provided
            if (-not [string]::IsNullOrEmpty($Arguments)) {
                $shortcut.Arguments = $Arguments
            }

            # Set working directory (default to target's directory if not specified)
            if ([string]::IsNullOrEmpty($WorkingDirectory)) {
                $WorkingDirectory = Split-Path -Path $TargetPath -Parent
            }
            $shortcut.WorkingDirectory = $WorkingDirectory
            
            # Save the shortcut
            $shortcut.Save()
            Write-LogMessage "Shortcut saved to $shortcutPath" -Level DEBUG
        }
        else {
            # STA fallback: create shortcut in Windows PowerShell (STA).
            $winPS = Join-Path $env:WINDIR "System32\WindowsPowerShell\v1.0\powershell.exe"
            if (-not (Test-Path $winPS -PathType Leaf)) {
                throw "Cannot create shortcut: WScript.Shell COM unavailable and Windows PowerShell not found at $winPS"
            }

            $targetPathArg = $TargetPath.Replace('"', '""')
            $shortcutPathArg = $shortcutPath.Replace('"', '""')
            $iconPathArg = $IconPath.Replace('"', '""')
            $argumentsArg = $Arguments.Replace('"', '""')
            $workingDirArg = $WorkingDirectory.Replace('"', '""')

            $staCommand = @"
`$ErrorActionPreference = 'Stop'
`$w = New-Object -ComObject WScript.Shell
`$s = `$w.CreateShortcut(""$shortcutPathArg"")
`$s.TargetPath = ""$targetPathArg""
if (-not [string]::IsNullOrEmpty(""$iconPathArg"")) { `$s.IconLocation = ""$iconPathArg,0"" }
if (-not [string]::IsNullOrEmpty(""$argumentsArg"")) { `$s.Arguments = ""$argumentsArg"" }
if (-not [string]::IsNullOrEmpty(""$workingDirArg"")) { `$s.WorkingDirectory = ""$workingDirArg"" }
else { `$s.WorkingDirectory = (Split-Path -Path ""$targetPathArg"" -Parent) }
`$s.Save()
"@

            Write-LogMessage "Creating shortcut via STA fallback: $shortcutPath" -Level DEBUG
            $null = & $winPS -NoProfile -STA -Command $staCommand

            if (-not (Test-Path $shortcutPath -PathType Leaf)) {
                throw "STA fallback reported success but shortcut not found at $shortcutPath"
            }
            Write-LogMessage "Shortcut saved to $shortcutPath (STA fallback)" -Level DEBUG
        }

        if ($RunAsAdmin) {
            # Set shortcut to run as administrator by modifying bytes
            Write-LogMessage "Setting shortcut to run as administrator" -Level DEBUG
            Start-Sleep -Milliseconds 100  # Small delay to ensure file is written
            
            if (Test-Path $shortcutPath -PathType Leaf) {
                $bytes = [System.IO.File]::ReadAllBytes($shortcutPath)
                $bytes[21] = $bytes[21] -bor 32 # Set the admin flag
                [System.IO.File]::WriteAllBytes($shortcutPath, $bytes)
            }
            else {
                Write-LogMessage "Shortcut file not found after save, cannot set run as admin" -Level WARN
            }
        }
        
        Write-LogMessage "Shortcut '$ShortcutName' created successfully at Desktop ($desktopPath)" -Level INFO
        
        # Release COM object
        if ($null -ne $shortcut) {
            [System.Runtime.Interopservices.Marshal]::ReleaseComObject($shortcut) | Out-Null
        }
        if ($null -ne $wscriptShell) {
            [System.Runtime.Interopservices.Marshal]::ReleaseComObject($wscriptShell) | Out-Null
        }
    }
    catch {
        Write-LogMessage "Failed to create desktop shortcut for $ShortcutName" -Level ERROR -Exception $_
        throw $_
    }
}


function Add-TaskBarShortcut(
    [Parameter(Mandatory = $true)]
    [string]$ShortcutName,
    [Parameter(Mandatory = $true)]
    [string]$TargetPath,
    [Parameter(Mandatory = $false)]
    [string]$Arguments = "",
    [Parameter(Mandatory = $false)]
    [string]$IconPath = "",
    [Parameter(Mandatory = $false)]
    [string]$WorkingDirectory = "",
    [Parameter(Mandatory = $false)]
    [switch]$RunAsAdmin
) {
    Write-LogMessage "Creating shortcut $ShortcutName at TaskBar" -Level INFO
    $taskbarPath = "$env:USERPROFILE\AppData\Roaming\Microsoft\Internet Explorer\Quick Launch\User Pinned\TaskBar"

    $shortcutPath = Join-Path $taskbarPath "$ShortcutName.lnk"
    if (Test-Path $shortcutPath) {
        Remove-Item $shortcutPath -Force -ErrorAction SilentlyContinue
    }
    $wscriptShell = New-Object -ComObject WScript.Shell
    $shortcut = $wscriptShell.CreateShortcut($shortcutPath)

    $shortcut.TargetPath = $TargetPath
    if ($TargetPath.ToLower().Contains(".exe") -and -not $IconPath) {
        IconPath = $TargetPath
    }
 
    if ($IconPath) {
        $shortcut.IconLocation = $IconPath
    }

    # Use your suggested command format as arguments
    $shortcut.Arguments = $Arguments

    $shortcut.WorkingDirectory = $WorkingDirectory
    $shortcut.Save()

    if ($RunAsAdmin) {
        # Set shortcut to run as administrator
        Write-Output "Setting shortcut to run as administrator..."
        $bytes = [System.IO.File]::ReadAllBytes($shortcutPath)
        $bytes[21] = $bytes[21] -bor 32 # Set the admin flag
        [System.IO.File]::WriteAllBytes($shortcutPath, $bytes)
    }
    Write-LogMessage "Shortcut $ShortcutName created at TaskBar" -Level INFO
}

#region Ollama Functions - Wrapper functions that call OllamaHandler module
# NOTE: These functions are maintained for backward compatibility.
# The primary implementation is now in the OllamaHandler module.
# Import-Module OllamaHandler for the full functionality.

function Get-OllamaModelLibrary {
    <#
    .SYNOPSIS
        [DEPRECATED] Use OllamaHandler module instead: Get-OllamaModelLibrary
    #>
    [CmdletBinding()]
    param()

    # Try to use OllamaHandler module if available
    if (Get-Module -Name OllamaHandler -ListAvailable) {
        Import-Module OllamaHandler -Force -ErrorAction SilentlyContinue
        if (Get-Command -Name 'Get-OllamaModelLibrary' -Module OllamaHandler -ErrorAction SilentlyContinue) {
            return OllamaHandler\Get-OllamaModelLibrary
        }
    }
    
    # Fallback: minimal implementation
    $url = "https://ollama.com/library"
    try {
        $response = Invoke-WebRequest -Uri $url -UseBasicParsing -TimeoutSec 30
        $html = $response.Content
        $models = @()
        
        # Regex: Match anchors with /library/modelname href
        $modelLinkPattern = '<a[^>]*href="/library/([^/?#"]+)"[^>]*>'
        $modelMatches = [regex]::Matches($html, $modelLinkPattern)
        
        $processedNames = @{}
        foreach ($match in $modelMatches) {
            $modelName = $match.Groups[1].Value
            if (-not $processedNames.ContainsKey($modelName) -and $modelName -notin @("featured", "search", "")) {
                $processedNames[$modelName] = $true
                $models += [PSCustomObject]@{
                    Name        = $modelName
                    Title       = $modelName
                    Description = ""
                    Downloads   = ""
                    Tags        = @()
                }
            }
        }
        return $models
    }
    catch {
        Write-LogMessage "Failed to fetch Ollama library: $($_.Exception.Message)" -Level ERROR
        return @()
    }
}

function Get-OllamaModelList {
    <#
    .SYNOPSIS
        [DEPRECATED] Use OllamaHandler module instead: Get-OllamaRecommendedModels
    #>
    [CmdletBinding()]
    param()
    
    # Try to use OllamaHandler module if available
    if (Get-Module -Name OllamaHandler -ListAvailable) {
        Import-Module OllamaHandler -Force -ErrorAction SilentlyContinue
        if (Get-Command -Name 'Get-OllamaRecommendedModels' -Module OllamaHandler -ErrorAction SilentlyContinue) {
            return OllamaHandler\Get-OllamaRecommendedModels
        }
    }
    
    # Fallback: return minimal static list
    return [pscustomobject[]]@(
        [pscustomobject]@{ Name = "llama3.1:8b"; Title = "Llama 3.1 8B"; Description = "Meta's flagship 8B parameter model."; Downloads = "97.6M"; Tags = @("tools"); ModelGroup = @("LessThan6GB", "LessThan10GB", "Non-GPU") }
        [pscustomobject]@{ Name = "granite4:micro-h"; Title = "Granite 4 Micro-H"; Description = "IBM Granite 4 Micro-H for non-GPU workloads."; Downloads = "226.9K"; Tags = @("tools"); ModelGroup = @("LessThan6GB", "LessThan10GB", "Non-GPU") }
    )
}

function Get-OllamaModels {
    <#
    .SYNOPSIS
        [DEPRECATED] Use OllamaHandler module instead: Install-OllamaModelBatch or Select-OllamaModelsToInstall
    #>
    param(
        [Parameter(Mandatory = $false)]
        [ValidateSet("All", "LessThan6GB", "LessThan10GB", "Non-GPU")]
        [string]$ModelGroup = "Non-GPU"
    )
    
    # Try to use OllamaHandler module
    if (Get-Module -Name OllamaHandler -ListAvailable) {
        Import-Module OllamaHandler -Force -ErrorAction SilentlyContinue
        
        # Get recommended models
        $models = OllamaHandler\Get-OllamaRecommendedModels -ModelGroup $ModelGroup
        if ($models) {
            $modelNames = $models | ForEach-Object { $_.Name }
            return OllamaHandler\Install-OllamaModelBatch -ModelNames $modelNames
        }
    }
    
    Write-LogMessage "OllamaHandler module not available. Please import it first: Import-Module OllamaHandler" -Level WARN
    return $false
}

function Get-OllamaPathInstallIfMissing {
    <#
    .SYNOPSIS
        Gets Ollama path, installing if missing. Wrapper for OllamaHandler\Get-OllamaPath.
    #>
    [CmdletBinding()]
    param()
    
    if (Get-Module -Name OllamaHandler -ListAvailable) {
        Import-Module OllamaHandler -Force -ErrorAction SilentlyContinue
        return OllamaHandler\Get-OllamaPath -InstallIfMissing
    }
    
    # Fallback: check common paths
    $paths = @(
        "$env:LOCALAPPDATA\Programs\Ollama\ollama.exe",
        "$env:ProgramFiles\Ollama\ollama.exe"
    )
    foreach ($p in $paths) {
        if (Test-Path $p) { return $p }
    }
    
    $cmd = Get-Command "ollama" -ErrorAction SilentlyContinue
    if ($cmd) { return $cmd.Source }
    
    return $null
}

function Export-OllamaModel {
    <#
    .SYNOPSIS
        [WRAPPER] Calls OllamaHandler\Export-OllamaModel. Exports model for airgapped transfer.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$ModelName,
        
        [Parameter(Mandatory = $false)]
        [string]$OutputPath = ""
    )

    # Try to use OllamaHandler module
    if (Get-Module -Name OllamaHandler -ListAvailable) {
        Import-Module OllamaHandler -Force -ErrorAction SilentlyContinue
        if ($OutputPath) {
            return OllamaHandler\Export-OllamaModel -ModelName $ModelName -OutputPath $OutputPath
        }
        else {
            return OllamaHandler\Export-OllamaModel -ModelName $ModelName
        }
    }
    
    Write-LogMessage "OllamaHandler module not available. Please install it first." -Level ERROR
    return $null
}

function Import-OllamaModel {
    <#
    .SYNOPSIS
        [WRAPPER] Calls OllamaHandler\Import-OllamaModel. Imports model from ZIP file for airgapped servers.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [ValidateScript({ Test-Path $_ })]
        [string]$ModelPath
    )
    
    # Try to use OllamaHandler module
    if (Get-Module -Name OllamaHandler -ListAvailable) {
        Import-Module OllamaHandler -Force -ErrorAction SilentlyContinue
        return OllamaHandler\Import-OllamaModel -ModelPath $ModelPath
    }
    
    Write-LogMessage "OllamaHandler module not available. Please install it first." -Level ERROR
    return $false
}

#endregion Ollama Functions

# function Export-OllamaModels {
#     <#
#     .SYNOPSIS
#         Exports multiple Ollama models matching a ModelGroup filter for airgapped server transfer.
    
#     .DESCRIPTION
#         Exports all models from the recommended list that match the specified ModelGroup.
#         Each model is exported to a separate .ollama file in the OllamaExport directory.
#         Uses Export-OllamaModel function for each matching model.
    
#     .PARAMETER ModelGroup
#         Filter models by group: All, LessThan6GB, LessThan10GB, or Non-GPU.
#         Default is "Non-GPU".
    
#     .PARAMETER OutputFolder
#         Optional folder path for exported files. If not specified, uses ApplicationDataPath\OllamaExport.
    
#     .EXAMPLE
#         Export-OllamaModels -ModelGroup "Non-GPU"
#         # Exports all Non-GPU models to ApplicationDataPath\OllamaExport
    
#     .EXAMPLE
#         Export-OllamaModels -ModelGroup "LessThan6GB" -OutputFolder "C:\Exports"
#         # Exports all models under 6GB to C:\Exports
#     #>
#     [CmdletBinding()]
#     param(
#         [Parameter(Mandatory = $false)]
#         [ValidateSet("All", "LessThan6GB", "LessThan10GB", "Non-GPU")]
#         [string]$ModelGroup = "Non-GPU",
        
#         [Parameter(Mandatory = $false)]
#         [string]$OutputFolder = ""
#     )
    
#     # Get the model list
#     $ollamaModelList = Get-OllamaModelList
    
#     # Filter by ModelGroup if not "All"
#     if ($ModelGroup -ne "All") {
#         $ollamaModelList = $ollamaModelList | Where-Object { $_.ModelGroup -contains $ModelGroup }
#     }
    
#     if ($ollamaModelList.Count -eq 0) {
#         Write-LogMessage "No models found matching ModelGroup: $ModelGroup" -Level WARN
#         return @()
#     }
    
#     Write-LogMessage "Found $($ollamaModelList.Count) model(s) matching ModelGroup: $ModelGroup" -Level INFO
    
#     # Set output folder
#     if (-not $OutputFolder) {
#         $OutputFolder = Join-Path (Get-ApplicationDataPath) "OllamaExport"
#     }
    
#     if (-not (Test-Path -Path $OutputFolder -PathType Container)) {
#         New-Item -ItemType Directory -Path $OutputFolder -Force -ErrorAction SilentlyContinue | Out-Null
#         Write-LogMessage "Created output folder: $OutputFolder" -Level INFO
#     }
    
#     $exportedFiles = @()
#     $failedExports = @()
    
#     foreach ($model in $ollamaModelList) {
#         Write-LogMessage "Processing model: $($model.Name)" -Level INFO
        
#         $safeModelName = $model.Name -replace '[:\/]', '-'
#         $outputPath = Join-Path $OutputFolder $safeModelName
        
#         $result = Export-OllamaModel -ModelName $model.Name -OutputPath $outputPath
        
#         if ($result) {
#             $exportedFiles += $result
#             Write-LogMessage "Successfully exported $($model.Name) to $result" -Level INFO
#         }
#         else {
#             $failedExports += $model.Name
#             Write-LogMessage "Failed to export $($model.Name)" -Level ERROR
#         }
#     }
    
#     Write-LogMessage "Export completed. Successfully exported: $($exportedFiles.Count), Failed: $($failedExports.Count)" -Level INFO
    
#     if ($failedExports.Count -gt 0) {
#         Write-LogMessage "Failed models: $($failedExports -join ', ')" -Level WARN
#     }
    
#     return @{
#         ExportedFiles = $exportedFiles
#         FailedModels = $failedExports
#         OutputFolder = $OutputFolder
#     }
# }

# function Import-OllamaModels {
#     <#
#     .SYNOPSIS
#         Imports multiple Ollama models from exported files matching a ModelGroup filter.
    
#     .DESCRIPTION
#         Imports all .ollama files from the OllamaExport directory that match models
#         in the recommended list filtered by ModelGroup. Uses Import-OllamaModel function
#         for each matching file.
    
#     .PARAMETER ModelGroup
#         Filter models by group: All, LessThan6GB, LessThan10GB, or Non-GPU.
#         Default is "Non-GPU".
    
#     .PARAMETER ImportFolder
#         Optional folder path containing .ollama files. If not specified, uses ApplicationDataPath\OllamaExport.
    
#     .EXAMPLE
#         Import-OllamaModels -ModelGroup "Non-GPU"
#         # Imports all Non-GPU model files from ApplicationDataPath\OllamaExport
    
#     .EXAMPLE
#         Import-OllamaModels -ModelGroup "LessThan6GB" -ImportFolder "C:\Imports"
#         # Imports all models under 6GB from C:\Imports
#     #>
#     [CmdletBinding()]
#     param(
#         [Parameter(Mandatory = $false)]
#         [ValidateSet("All", "LessThan6GB", "LessThan10GB", "Non-GPU")]
#         [string]$ModelGroup = "Non-GPU",
        
#         [Parameter(Mandatory = $false)]
#         [string]$ImportFolder = ""
#     )
    
#     # Get the model list
#     $ollamaModelList = Get-OllamaModelList
    
#     # Filter by ModelGroup if not "All"
#     if ($ModelGroup -ne "All") {
#         $ollamaModelList = $ollamaModelList | Where-Object { $_.ModelGroup -contains $ModelGroup }
#     }
    
#     if ($ollamaModelList.Count -eq 0) {
#         Write-LogMessage "No models found matching ModelGroup: $ModelGroup" -Level WARN
#         return @()
#     }
    
#     Write-LogMessage "Found $($ollamaModelList.Count) model(s) matching ModelGroup: $ModelGroup" -Level INFO
    
#     # Set import folder
#     if (-not $ImportFolder) {
#         $ImportFolder = Join-Path (Get-ApplicationDataPath) "OllamaExport"
#     }
    
#     if (-not (Test-Path -Path $ImportFolder -PathType Container)) {
#         Write-LogMessage "Import folder does not exist: $ImportFolder" -Level ERROR
#         return @{
#             ImportedModels = @()
#             FailedImports = @()
#             MissingFiles = $ollamaModelList.Name
#         }
#     }
    
#     $importedModels = @()
#     $failedImports = @()
#     $missingFiles = @()
    
#     foreach ($model in $ollamaModelList) {
#         $safeModelName = $model.Name -replace '[:\/]', '-'
#         $modelFolderPath = Join-Path $ImportFolder $safeModelName
        
#         if (-not (Test-Path -Path $modelFolderPath -PathType Container)) {
#             Write-LogMessage "Model folder not found: $modelFolderPath" -Level WARN
#             $missingFiles += $model.Name
#             continue
#         }
        
#         Write-LogMessage "Importing model: $($model.Name) from $modelFolderPath" -Level INFO
        
#         $result = Import-OllamaModel -ModelFolderPath $modelFolderPath
        
#         if ($result) {
#             $importedModels += $model.Name
#             Write-LogMessage "Successfully imported $($model.Name)" -Level INFO
#         }
#         else {
#             $failedImports += $model.Name
#             Write-LogMessage "Failed to import $($model.Name)" -Level ERROR
#         }
#     }
    
#     Write-LogMessage "Import completed. Successfully imported: $($importedModels.Count), Failed: $($failedImports.Count), Missing: $($missingFiles.Count)" -Level INFO
    
#     if ($failedImports.Count -gt 0) {
#         Write-LogMessage "Failed models: $($failedImports -join ', ')" -Level WARN
#     }
    
#     if ($missingFiles.Count -gt 0) {
#         Write-LogMessage "Missing files: $($missingFiles -join ', ')" -Level WARN
#     }
    
#     return @{
#         ImportedModels = $importedModels
#         FailedImports = $failedImports
#         MissingFiles = $missingFiles
#         ImportFolder = $ImportFolder
#     }
# }



function Update-AllWingetApps {
    try {
        if (Test-IsServer) {
            return
        }
        # Main script logic
        $wingetPath = Get-CommandPathWithFallback -Name "winget"
        if ($wingetPath -ne "winget") {
            # Upgrade all winget apps 
            $listCommand = "$wingetPath upgrade"
            Write-LogMessage "Querying upgradable winget apps with command: $listCommand" -Level INFO
    
            $result = & $wingetPath upgrade 2>&1
        
            # Check if there are any upgradable packages
            if ($result -match "No installed package found matching input criteria") {
                Write-LogMessage "No upgradable packages found" -Level INFO
                return
            }
        
            # Find the line number of the header
            $headerIndex = ($result | Select-String -Pattern "^Name\s+Id\s+Version\s+Available\s+Source").LineNumber
            if (-not $headerIndex) {
                Write-LogMessage "Could not find winget upgrade table header. Output format may have changed." -Level WARN
                Write-LogMessage "Raw output: $($result -join "`n")" -Level DEBUG
                return
            }
            # Only process lines after the header and before the summary
            $dataLines = $result[$headerIndex..($result.Count - 1)] | Where-Object { $_ -notmatch '^-+$' -and $_ -notmatch 'upgrades? available' -and $_ -notmatch '^\s*$' }
            Write-Host $($dataLines -join "`n")
            $posOfId = 56

            $wingetIds = @()
            foreach ($line in $dataLines) {
                # Find only the Id column formatted like this: Microsoft.VCRedist.2015+.x64
                # Name                                                    Id                           Version       Available     Source
                # -----------------------------------------------------------------------------------------------------------------------
                # Microsoft Visual C++ 2015-2022 Redistributable (x64) -ÔÇª Microsoft.VCRedist.2015+.x64 14.42.34438.0 14.44.35211.0 winget
                # Microsoft Visual C++ 2015-2022 Redistributable (x86) -ÔÇª Microsoft.VCRedist.2015+.x86 14.42.34438.0 14.44.35211.0 winget
                # 2 upgrades available.         

                $workLine = $line.Substring($posOfId)
                Write-LogMessage "Line: $line" -Level INFO
            

                # Do not remove spaces; keep the original line as is
                # Only remove characters like -ÔÇª (non-ASCII, non-norwegian, non-standard)
                $workLine = $($workLine -replace '[^\x20-\x7EøæåØÆÅ]', '').Trim()

                $workId = $workLine.Split(" ")[0]
                # verify valid id
                $verifyCommand = "$wingetPath show $workId"
                Write-LogMessage "Verify command: $verifyCommand" -Level INFO
                $verifyResult = Invoke-Expression $verifyCommand
                Write-LogMessage "Verify result: $verifyResult" -Level INFO
                if ($verifyResult -match "No package found matching input criteria") {
                    Write-LogMessage "Invalid winget ID: $workId" -Level WARN
                    continue
                }

                $wingetIds += $workId
            }

            if ($wingetIds.Count -eq 0) {
                Write-LogMessage "No valid winget IDs found to upgrade" -Level WARN
                return
            }
        
            Write-LogMessage "Found $($wingetIds.Count) upgradable winget app(s): $($wingetIds -join ', ')" -Level INFO
        
            # Upgrade each package
            foreach ($id in $wingetIds) {
                Write-LogMessage "Upgrading package: $id" -Level INFO
            
                try {
                    # Use Start-Process in a new window so progress is visible, and check exit code after

                    $process = Start-Process -FilePath $wingetPath -ArgumentList "upgrade $id --accept-source-agreements --accept-package-agreements --silent" -Wait -NoNewWindow:$false -PassThru
                    $exitCode = $process.ExitCode

                    if ($exitCode -eq 0) {
                        Write-LogMessage "Successfully upgraded: $id" -Level INFO
                    }
                    else {
                        # Try to detect if uninstall is required by running upgrade again and capturing output
                        $upgradeResult = & $wingetPath upgrade $id --accept-source-agreements --accept-package-agreements --silent 2>&1
                        if ($upgradeResult -match "Please uninstall the package") {
                            Write-LogMessage "Please uninstall the package: $id" -Level ERROR
                            Start-Process -FilePath $wingetPath -ArgumentList "uninstall $id --silent" -Wait -NoNewWindow:$false | Out-Null
                            Write-LogMessage "Uninstalled package: $id" -Level INFO
                            $installProcess = Start-Process -FilePath $wingetPath -ArgumentList "install $id --accept-source-agreements --accept-package-agreements --silent" -Wait -NoNewWindow:$false -PassThru
                            $installExitCode = $installProcess.ExitCode
                            if ($installExitCode -eq 0) {
                                Write-LogMessage "Successfully re-installed package: $id" -Level INFO
                            }
                            else {
                                Write-LogMessage "Failed to upgrade $id. Exit code: $installExitCode" -Level ERROR
                                Write-LogMessage "Upgrade output: $($upgradeResult -join "`n")" -Level ERROR
                            }
                        }
                    }
                }
                catch {
                    Write-LogMessage "Exception occurred while upgrading $id`: $($_.Exception.Message)" -Level ERROR
                }
            }
            Write-LogMessage "Winget upgrade process completed" -Level INFO

        }
    
        else {
            Write-LogMessage "Winget not found on this system" -Level WARN
        }
    }
    catch {
        Write-LogMessage "Error executing winget upgrade: $($_.Exception.Message)" -Level ERROR
    }
}

function Update-AllWindowsApps {    
    $codeCmd = Get-CommandPathWithFallback -Name "code"
    if ($null -ne $codeCmd) {
        #Check if VSCode is running
        $vscodeProcess = Get-Process -Name "code" -ErrorAction SilentlyContinue
        if ($null -ne $vscodeProcess) {
            Write-LogMessage "VSCode is running. Please close it before updating." -Level WARN
            return
        }
        Install-WindowsApps -AppName "VSCode System-Installer"
    }

    if (-not (Test-IsServer)) {
        $cursorCmd = Get-CommandPathWithFallback -Name "cursor"
        if ($null -ne $cursorCmd) {
            #Check if Cursor is running
            $cursorProcess = Get-Process -Name "Cursor" -ErrorAction SilentlyContinue
            if ($null -ne $cursorProcess) {
                Write-LogMessage "Cursor is running. Please close it before updating." -Level WARN
                return
            }
            Install-WindowsApps -AppName "Cursor System-Installer"
        }
    }
}

function ConvertTo-NormalizedVersionObject {
    param(
        [Parameter(Mandatory = $false)]
        [string]$VersionText
    )

    if ([string]::IsNullOrWhiteSpace($VersionText)) {
        return $null
    }

    $match = [regex]::Match($VersionText.Trim(), '\d+(?:\.\d+){0,3}')
    if (-not $match.Success) {
        return $null
    }

    $parts = $match.Value.Split('.')
    while ($parts.Count -lt 4) {
        $parts += "0"
    }
    if ($parts.Count -gt 4) {
        $parts = $parts[0..3]
    }

    try {
        return [version]($parts -join '.')
    }
    catch {
        return $null
    }
}

function Compare-NormalizedVersion {
    param(
        [Parameter(Mandatory = $false)]
        [string]$InstalledVersion,
        [Parameter(Mandatory = $false)]
        [string]$ArchiveVersion
    )

    $installed = ConvertTo-NormalizedVersionObject -VersionText $InstalledVersion
    $archive = ConvertTo-NormalizedVersionObject -VersionText $ArchiveVersion
    if ($null -eq $installed -or $null -eq $archive) {
        return "Unknown"
    }

    if ($archive -gt $installed) {
        return "ArchiveNewer"
    }
    if ($archive -lt $installed) {
        return "InstalledNewer"
    }
    return "Equal"
}

function Get-InstalledWingetPackagesDetailed {
    $result = @()
    $wingetPath = Get-CommandPathWithFallback -Name "winget"
    if ($wingetPath -eq "winget") {
        Write-LogMessage "winget not found. Unable to scan installed winget packages." -Level WARN
        return $result
    }

    try {
        $lines = & $wingetPath list --accept-source-agreements --disable-interactivity 2>&1
        if ($LASTEXITCODE -ne 0 -or $null -eq $lines) {
            Write-LogMessage "winget list failed while reading installed packages." -Level WARN
            return $result
        }

        foreach ($line in $lines) {
            $clean = ($line -replace '[^\x20-\x7EøæåØÆÅ]', '').Trim()
            if ([string]::IsNullOrWhiteSpace($clean)) { continue }
            if ($clean -match '^\-+$') { continue }
            if ($clean -match '^Name\s+Id\s+Version') { continue }
            if ($clean -match 'No installed package found matching input criteria') { continue }

            $match = [regex]::Match($clean, '^(?<Name>.+?)\s{2,}(?<Id>[A-Za-z0-9\.\+\-_]+)\s{2,}(?<Version>\S+)(?:\s{2,}\S+)?(?:\s{2,}\S+)?$')
            if (-not $match.Success) { continue }

            $id = $match.Groups["Id"].Value.Trim()
            $version = $match.Groups["Version"].Value.Trim()
            if ([string]::IsNullOrWhiteSpace($id) -or [string]::IsNullOrWhiteSpace($version)) {
                continue
            }

            $result += [PSCustomObject]@{
                Id               = $id
                Name             = $match.Groups["Name"].Value.Trim()
                InstalledVersion = $version
            }
        }
    }
    catch {
        Write-LogMessage "Failed reading installed winget packages: $($_.Exception.Message)" -Level ERROR -Exception $_
    }
    return $result
}

function Get-ArchiveWingetPackagesDetailed {
    $result = @()
    $archiveRoot = Get-WingetAppsPath
    if (-not (Test-Path $archiveRoot -PathType Container)) {
        Write-LogMessage "Winget archive path not found: $archiveRoot" -Level WARN
        return $result
    }

    foreach ($dir in (Get-ChildItem -Path $archiveRoot -Directory -ErrorAction SilentlyContinue)) {
        $versionFile = Join-Path $dir.FullName "version.txt"
        $archiveVersion = ""
        $isKnown = $false
        if (Test-Path $versionFile -PathType Leaf) {
            $archiveVersion = (Get-Content -Path $versionFile -ErrorAction SilentlyContinue | Select-Object -First 1).Trim()
            $isKnown = ($null -ne (ConvertTo-NormalizedVersionObject -VersionText $archiveVersion))
        }
        $result += [PSCustomObject]@{
            Id             = $dir.Name
            ArchiveVersion = $archiveVersion
            IsVersionKnown = $isKnown
            SourcePath     = $dir.FullName
        }
    }
    return $result
}

function Get-InstalledWindowsProgramsDetailed {
    $result = @()
    $registryPaths = @(
        "HKCU:\Software\Microsoft\Windows\CurrentVersion\Uninstall",
        "HKCU:\Software\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall",
        "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall",
        "HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall"
    )

    foreach ($path in $registryPaths) {
        if (-not (Test-Path $path)) {
            continue
        }
        foreach ($key in (Get-ChildItem -Path $path -ErrorAction SilentlyContinue)) {
            try {
                $item = Get-ItemProperty -Path $key.PSPath -ErrorAction SilentlyContinue
                if ($null -eq $item) { continue }

                $name = "$($item.DisplayName)".Trim()
                $version = "$($item.DisplayVersion)".Trim()
                if ([string]::IsNullOrWhiteSpace($name)) { continue }
                if ([string]::IsNullOrWhiteSpace($version)) { continue }

                $result += [PSCustomObject]@{
                    DisplayName     = $name
                    DisplayVersion  = $version
                    Publisher       = "$($item.Publisher)".Trim()
                    InstallLocation = "$($item.InstallLocation)".Trim()
                }
            }
            catch {
                # Keep scanning; individual uninstall keys can be malformed.
            }
        }
    }

    $result = $result | Sort-Object DisplayName, DisplayVersion -Unique
    return @($result)
}

function Get-ArchiveWindowsPackagesDetailed {
    $result = @()
    $archiveRoot = Get-WindowsAppsPath
    if (-not (Test-Path $archiveRoot -PathType Container)) {
        Write-LogMessage "Windows archive path not found: $archiveRoot" -Level WARN
        return $result
    }

    foreach ($dir in (Get-ChildItem -Path $archiveRoot -Directory -ErrorAction SilentlyContinue)) {
        $allInstallers = Get-ChildItem -Path $dir.FullName -File -Recurse -Include *.exe, *.msi, *.bat, *.cmd, *.ps1 -ErrorAction SilentlyContinue
        if ($allInstallers.Count -eq 0) {
            $result += [PSCustomObject]@{
                AppName          = $dir.Name
                InstallerPath    = ""
                ArchiveVersion   = ""
                IsVersionKnown   = $false
                VersionSource    = "Unknown"
                SourceFolderPath = $dir.FullName
            }
            continue
        }

        $priorityInstallers = $allInstallers | Where-Object { $_.Name -match '(?i)(setup|install)' } | Sort-Object FullName
        $selectedInstaller = if ($priorityInstallers.Count -gt 0) { $priorityInstallers[0] } else { ($allInstallers | Sort-Object FullName)[0] }

        $archiveVersion = ""
        $versionSource = "Unknown"

        try {
            $productVersion = "$($selectedInstaller.VersionInfo.ProductVersion)".Trim()
            $fileVersion = "$($selectedInstaller.VersionInfo.FileVersion)".Trim()
            if ($null -ne (ConvertTo-NormalizedVersionObject -VersionText $productVersion)) {
                $archiveVersion = $productVersion
                $versionSource = "ProductVersion"
            }
            elseif ($null -ne (ConvertTo-NormalizedVersionObject -VersionText $fileVersion)) {
                $archiveVersion = $fileVersion
                $versionSource = "FileVersion"
            }
        }
        catch {
            # Fallback to file name parsing
        }

        if ([string]::IsNullOrWhiteSpace($archiveVersion)) {
            $nameMatch = [regex]::Match($selectedInstaller.Name, '(\d+(?:\.\d+){1,3})')
            if ($nameMatch.Success) {
                $archiveVersion = $nameMatch.Groups[1].Value
                $versionSource = "FileName"
            }
        }

        $result += [PSCustomObject]@{
            AppName          = $dir.Name
            InstallerPath    = $selectedInstaller.FullName
            ArchiveVersion   = $archiveVersion
            IsVersionKnown   = ($null -ne (ConvertTo-NormalizedVersionObject -VersionText $archiveVersion))
            VersionSource    = $versionSource
            SourceFolderPath = $dir.FullName
        }
    }
    return $result
}

function Resolve-WindowsArchiveMatch {
    param(
        [Parameter(Mandatory = $true)]
        [string]$InstalledDisplayName,
        [Parameter(Mandatory = $true)]
        [array]$ArchiveWindowsPackages
    )

    $NormalizeName = {
        param([string]$NameText)
        return (($NameText ?? "") -replace '[^a-zA-Z0-9]+', '').ToLower()
    }

    $aliasMap = @{
        "visualstudiocode" = @("vscodesysteminstaller")
        "cursor"           = @("cursorsysteminstaller")
    }

    $installedNorm = & $NormalizeName $InstalledDisplayName
    if ([string]::IsNullOrWhiteSpace($installedNorm)) {
        return $null
    }

    $exact = $ArchiveWindowsPackages | Where-Object { (& $NormalizeName $_.AppName) -eq $installedNorm } | Select-Object -First 1
    if ($null -ne $exact) {
        return $exact
    }

    if ($aliasMap.ContainsKey($installedNorm)) {
        foreach ($alias in $aliasMap[$installedNorm]) {
            $aliasMatch = $ArchiveWindowsPackages | Where-Object { (& $NormalizeName $_.AppName) -eq $alias } | Select-Object -First 1
            if ($null -ne $aliasMatch) {
                return $aliasMatch
            }
        }
    }

    $containsMatches = $ArchiveWindowsPackages | Where-Object {
        $archiveNorm = & $NormalizeName $_.AppName
        $archiveNorm.Contains($installedNorm) -or $installedNorm.Contains($archiveNorm)
    }
    if ($containsMatches.Count -eq 0) {
        return $null
    }

    return ($containsMatches | Sort-Object { [math]::Abs(((& $NormalizeName $_.AppName).Length) - $installedNorm.Length) }, AppName | Select-Object -First 1)
}

function Update-InstalledSoftwareFromArchives {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $false)]
        [switch]$IncludeWinget,
        [Parameter(Mandatory = $false)]
        [switch]$IncludeWindowsApps,
        [Parameter(Mandatory = $false)]
        [switch]$WhatIf,
        [Parameter(Mandatory = $false)]
        [switch]$ForceReinstall,
        [Parameter(Mandatory = $false)]
        [string]$ReportPath = ""
    )

    if (-not $IncludeWinget -and -not $IncludeWindowsApps) {
        $IncludeWinget = $true
        $IncludeWindowsApps = $true
    }

    $result = [PSCustomObject]@{
        StartedAt             = Get-Date
        ComputerName          = $env:COMPUTERNAME
        Updated               = @()
        UpToDate              = @()
        SkippedUnknownVersion = @()
        SkippedNoArchive      = @()
        Failed                = @()
        Summary               = $null
    }

    Write-LogMessage "Starting version-aware software update from archives" -Level INFO

    if ($IncludeWinget) {
        Write-LogMessage "Processing installed winget packages..." -Level INFO
        $installedWinget = Get-InstalledWingetPackagesDetailed
        $archiveWinget = Get-ArchiveWingetPackagesDetailed
        $archiveWingetById = @{}
        foreach ($pkg in $archiveWinget) { $archiveWingetById[$pkg.Id] = $pkg }

        foreach ($installed in $installedWinget) {
            if (-not $archiveWingetById.ContainsKey($installed.Id)) {
                $result.SkippedNoArchive += [PSCustomObject]@{
                    Type    = "Winget"
                    Name    = $installed.Name
                    Id      = $installed.Id
                    Reason  = "No archive package found"
                }
                continue
            }

            $archive = $archiveWingetById[$installed.Id]
            $comparison = Compare-NormalizedVersion -InstalledVersion $installed.InstalledVersion -ArchiveVersion $archive.ArchiveVersion
            if ($comparison -eq "Unknown") {
                $result.SkippedUnknownVersion += [PSCustomObject]@{
                    Type             = "Winget"
                    Name             = $installed.Name
                    Id               = $installed.Id
                    InstalledVersion = $installed.InstalledVersion
                    ArchiveVersion   = $archive.ArchiveVersion
                    Reason           = "Unparseable or missing version"
                }
                continue
            }

            if ($comparison -eq "ArchiveNewer" -or $ForceReinstall) {
                if ($WhatIf) {
                    $result.Updated += [PSCustomObject]@{
                        Type             = "Winget"
                        Name             = $installed.Name
                        Id               = $installed.Id
                        InstalledVersion = $installed.InstalledVersion
                        ArchiveVersion   = $archive.ArchiveVersion
                        Status           = "WhatIf"
                    }
                }
                else {
                    try {
                        Install-WingetPackage -AppName $installed.Id -Force
                        $result.Updated += [PSCustomObject]@{
                            Type             = "Winget"
                            Name             = $installed.Name
                            Id               = $installed.Id
                            InstalledVersion = $installed.InstalledVersion
                            ArchiveVersion   = $archive.ArchiveVersion
                            Status           = "Updated"
                        }
                    }
                    catch {
                        $result.Failed += [PSCustomObject]@{
                            Type             = "Winget"
                            Name             = $installed.Name
                            Id               = $installed.Id
                            InstalledVersion = $installed.InstalledVersion
                            ArchiveVersion   = $archive.ArchiveVersion
                            Error            = $_.Exception.Message
                        }
                    }
                }
            }
            else {
                $result.UpToDate += [PSCustomObject]@{
                    Type             = "Winget"
                    Name             = $installed.Name
                    Id               = $installed.Id
                    InstalledVersion = $installed.InstalledVersion
                    ArchiveVersion   = $archive.ArchiveVersion
                    Reason           = $comparison
                }
            }
        }
    }

    if ($IncludeWindowsApps) {
        Write-LogMessage "Processing installed Windows applications..." -Level INFO
        $installedPrograms = Get-InstalledWindowsProgramsDetailed
        $archiveWindows = Get-ArchiveWindowsPackagesDetailed

        foreach ($installed in $installedPrograms) {
            $archiveMatch = Resolve-WindowsArchiveMatch -InstalledDisplayName $installed.DisplayName -ArchiveWindowsPackages $archiveWindows
            if ($null -eq $archiveMatch) {
                $result.SkippedNoArchive += [PSCustomObject]@{
                    Type    = "WindowsApp"
                    Name    = $installed.DisplayName
                    Reason  = "No archive package match found"
                }
                continue
            }

            $comparison = Compare-NormalizedVersion -InstalledVersion $installed.DisplayVersion -ArchiveVersion $archiveMatch.ArchiveVersion
            if ($comparison -eq "Unknown") {
                $result.SkippedUnknownVersion += [PSCustomObject]@{
                    Type             = "WindowsApp"
                    Name             = $installed.DisplayName
                    ArchiveApp       = $archiveMatch.AppName
                    InstalledVersion = $installed.DisplayVersion
                    ArchiveVersion   = $archiveMatch.ArchiveVersion
                    Reason           = "Unparseable or missing version"
                }
                continue
            }

            if ($comparison -eq "ArchiveNewer" -or $ForceReinstall) {
                if ($WhatIf) {
                    $result.Updated += [PSCustomObject]@{
                        Type             = "WindowsApp"
                        Name             = $installed.DisplayName
                        ArchiveApp       = $archiveMatch.AppName
                        InstalledVersion = $installed.DisplayVersion
                        ArchiveVersion   = $archiveMatch.ArchiveVersion
                        Status           = "WhatIf"
                    }
                }
                else {
                    try {
                        Install-WindowsApps -AppName $archiveMatch.AppName -Force
                        $result.Updated += [PSCustomObject]@{
                            Type             = "WindowsApp"
                            Name             = $installed.DisplayName
                            ArchiveApp       = $archiveMatch.AppName
                            InstalledVersion = $installed.DisplayVersion
                            ArchiveVersion   = $archiveMatch.ArchiveVersion
                            Status           = "Updated"
                        }
                    }
                    catch {
                        $result.Failed += [PSCustomObject]@{
                            Type             = "WindowsApp"
                            Name             = $installed.DisplayName
                            ArchiveApp       = $archiveMatch.AppName
                            InstalledVersion = $installed.DisplayVersion
                            ArchiveVersion   = $archiveMatch.ArchiveVersion
                            Error            = $_.Exception.Message
                        }
                    }
                }
            }
            else {
                $result.UpToDate += [PSCustomObject]@{
                    Type             = "WindowsApp"
                    Name             = $installed.DisplayName
                    ArchiveApp       = $archiveMatch.AppName
                    InstalledVersion = $installed.DisplayVersion
                    ArchiveVersion   = $archiveMatch.ArchiveVersion
                    Reason           = $comparison
                }
            }
        }
    }

    $result.Summary = [PSCustomObject]@{
        UpdatedCount               = $result.Updated.Count
        UpToDateCount              = $result.UpToDate.Count
        SkippedUnknownVersionCount = $result.SkippedUnknownVersion.Count
        SkippedNoArchiveCount      = $result.SkippedNoArchive.Count
        FailedCount                = $result.Failed.Count
    }

    if (-not [string]::IsNullOrWhiteSpace($ReportPath)) {
        try {
            $reportFolder = Split-Path $ReportPath -Parent
            if (-not [string]::IsNullOrWhiteSpace($reportFolder) -and -not (Test-Path $reportFolder -PathType Container)) {
                New-Item -Path $reportFolder -ItemType Directory -Force | Out-Null
            }
            $result | ConvertTo-Json -Depth 10 | Set-Content -Path $ReportPath -Encoding UTF8
            Write-LogMessage "Upgrade report written to $($ReportPath)" -Level INFO
        }
        catch {
            Write-LogMessage "Failed writing upgrade report to $($ReportPath): $($_.Exception.Message)" -Level WARN -Exception $_
        }
    }

    Write-LogMessage "Software upgrade check completed. Updated=$($result.Summary.UpdatedCount), UpToDate=$($result.Summary.UpToDateCount), SkippedUnknown=$($result.Summary.SkippedUnknownVersionCount), SkippedNoArchive=$($result.Summary.SkippedNoArchiveCount), Failed=$($result.Summary.FailedCount)" -Level INFO
    return $result
}

function Update-AllApps {
    try {
        Update-AllOurPshApps
        Update-AllOurWinApps
        if (-not (Test-IsServer)) {
            Update-AllWingetApps
        }
        Update-AllWindowsApps

        $installDedgePshApps = @(
            "Add-BatchLogonCurrentUser",
            "Add-Task",
            "Chg-Pass",
            "CommonModules",
            "Configure-DefaultTerminalToConsoleHost",
            "Db2-AutoCatalog",
            "Db2-Commands",
            "Db2-CreateDb2CliShortCuts",
            "Get-App",
            "Init-Machine",
            "Inst-Psh",
            "Inst-WinApp",
            "Map-NetworkDrives",
            "PortCheckTool",
            "Run-Psh",
            "Send-Sms",
            "Set-PsModulePath",
            "Set-WinRegionTimeAndLanguage"
        )
        if (-not (Test-IsServer)) {
            $installDedgePshApps += @(
                "Add-OptFolderShare"
                "AddFkUserAsLocalAdmin", 
                "Agent-DeployTask",
                "Azure-DevOpsCloneRepositories",
                "DedgeSign",
                "Import-DbeaverConnections",
                "Refresh-WorkstationSettings",
                "RestoreProdVersionToDev",
                "Setup-TerminalProfiles"
            )
        }
        if (Test-IsServer) {
            $installDedgePshApps += @(
                "Refresh-ServerSettings"
            )
        } 
        ################################################################################
        # Install DedgePshApps
        ################################################################################
        foreach ($app in $installDedgePshApps) {
            try {
                Install-OurPshApp -AppName $app -SkipReInstall
            }
            catch {
                Write-LogMessage "Failed to install $app" -Level ERROR -Exception $_
            }
        }
    }
    catch {
        Write-LogMessage "Error executing winget upgrade: $($_.Exception.Message)" -Level ERROR
    }
}

<#
.SYNOPSIS
    Generates a comprehensive software inventory report of all available software modules.

.DESCRIPTION
    Scans all software sources (Winget packages, VS Code extensions, Windows apps, 
    system installers, Ollama models) and generates an HTML report showing versions, 
    installation paths, and installation commands. Uses WorkObject pattern for tracking.

.EXAMPLE
    Get-SoftwareInventory
    Scans all software sources and generates HTML report

.OUTPUTS
    PSCustomObject - WorkObject containing all inventory data
#>
function Get-SoftwareInventory {
    $startTime = Get-Date
    
    # Initialize comprehensive WorkObject for tracking
    $script:WorkObject = [PSCustomObject]@{
        # Job Information
        Name                    = "SoftwareInventoryReport"
        Description             = "Complete Software Inventory and Version Report"
        ScriptPath              = $PSCommandPath
        ExecutionTimestamp      = Get-Date -Format 'yyyy-MM-dd HH:mm:ss'
        ExecutionUser           = "$env:USERDOMAIN\$env:USERNAME"
        ComputerName            = $env:COMPUTERNAME
        
        # Execution Status
        Success                 = $false
        Status                  = "Running"
        ErrorMessage            = $null
        
        # Execution Phases
        WingetPackagesScanned   = $false
        VSCodeExtensionsScanned = $false
        WindowsAppsScanned      = $false
        InstallersScanned       = $false
        OllamaModelsScanned     = $false
        ReportGenerated         = $false
        
        # Statistics
        TotalWingetPackages     = 0
        TotalVSCodeExtensions   = 0
        TotalWindowsApps        = 0
        TotalInstallers         = 0
        TotalOllamaModels       = 0
        
        # Timing
        StartTime               = $startTime
        EndTime                 = $null
        Duration                = $null
        
        # Script and Output Tracking
        ScriptArray             = @()
        
        # Results Collections
        WingetPackages          = @()
        VSCodeExtensions        = @()
        WindowsApps             = @()
        SystemInstallers        = @()
        OllamaModels            = @()
    }
    
    Write-LogMessage "$($script:WorkObject.Name)" -Level JOB_STARTED
    Write-LogMessage "=============================================" -Level INFO
    Write-LogMessage "  Software Inventory Report Generation" -Level INFO
    Write-LogMessage "=============================================" -Level INFO
    
    # =========================================================================
    # STEP 1: Scan Winget Packages
    # =========================================================================
    Write-LogMessage "Scanning Winget packages..." -Level INFO
    $wingetPackages = @()
    
    try {
        $wingetPath = Get-WingetAppsPath
        if (Test-Path -Path $wingetPath -PathType Container) {
            $wingetPackages = Get-ChildItem -Path $wingetPath -Directory -ErrorAction SilentlyContinue | ForEach-Object {
                $versionFile = Join-Path $_.FullName "version.txt"
                $version = if (Test-Path $versionFile) { 
                    (Get-Content $versionFile -Raw -ErrorAction SilentlyContinue).Trim() 
                }
                else { 
                    "Unknown" 
                }
                $folderInfo = Get-Item $_.FullName -ErrorAction SilentlyContinue
                
                [PSCustomObject]@{
                    PackageId       = $_.Name
                    Name            = $_.Name
                    Version         = $version
                    DownloadPath    = $_.FullName
                    VersionFilePath = $versionFile
                    InstallCommand  = "Install-WingetPackage -AppName '$($_.Name)'"
                    Category        = "Winget"
                    LastModified    = if ($folderInfo) { $folderInfo.LastWriteTime.ToString("yyyy-MM-dd HH:mm:ss") } else { "Unknown" }
                }
            }
            
            $script:WorkObject.WingetPackagesScanned = $true
            $script:WorkObject.TotalWingetPackages = $wingetPackages.Count
            $script:WorkObject.WingetPackages = $wingetPackages
            
            $wingetOutput = @(
                "Winget path: $wingetPath",
                "Packages found: $($wingetPackages.Count)",
                "",
                "Packages:"
            ) + ($wingetPackages | ForEach-Object { "  - $($_.PackageId): $($_.Version)" })
            
            $script:WorkObject = Add-ScriptAndOutputToWorkObject -WorkObject $script:WorkObject `
                -Name "Winget-Scan" `
                -Script "Get-ChildItem -Path `"$wingetPath`" -Directory" `
                -Output ($wingetOutput -join "`n")
            
            Write-LogMessage "Found $($wingetPackages.Count) Winget packages" -Level INFO
        }
        else {
            Write-LogMessage "Winget path not accessible: $wingetPath" -Level WARN
        }
    }
    catch {
        Write-LogMessage "Failed to scan Winget packages: $($_.Exception.Message)" -Level ERROR -Exception $_
        $script:WorkObject.ErrorMessage = "Winget scan failed: $($_.Exception.Message)"
    }
    
    # =========================================================================
    # STEP 2: Scan VS Code Extensions
    # =========================================================================
    Write-LogMessage "Scanning VS Code extensions..." -Level INFO
    $vsCodeExtensions = @()
    
    try {
        $extensions = Get-ExtentionArray
        $vsixPath = Join-Path $(Get-SoftwarePath) "VSCodeExtensions"
        
        foreach ($ext in $extensions) {
            $vsixFile = Join-Path $vsixPath "$($ext.Id).vsix"
            if (Test-Path $vsixFile) {
                $fileInfo = Get-Item $vsixFile
                $vsCodeExtensions += [PSCustomObject]@{
                    ExtensionId    = $ext.Id
                    Description    = $ext.Description
                    DownloadPath   = $vsixFile
                    FileName       = $fileInfo.Name
                    FileSize       = $fileInfo.Length
                    FileSizeKB     = [math]::Round($fileInfo.Length / 1KB, 2)
                    LastModified   = $fileInfo.LastWriteTime.ToString("yyyy-MM-dd HH:mm:ss")
                    InstallCommand = "Install-VSCodeExtension -ExtensionId '$($ext.Id)'"
                    Category       = "VSCodeExtension"
                }
            }
        }
        
        $script:WorkObject.VSCodeExtensionsScanned = $true
        $script:WorkObject.TotalVSCodeExtensions = $vsCodeExtensions.Count
        $script:WorkObject.VSCodeExtensions = $vsCodeExtensions
        
        $vsixOutput = @(
            "VSIX path: $vsixPath",
            "Extensions found: $($vsCodeExtensions.Count)",
            "",
            "Extensions:"
        ) + ($vsCodeExtensions | ForEach-Object { "  - $($_.ExtensionId): $($_.Description)" })
        
        $script:WorkObject = Add-ScriptAndOutputToWorkObject -WorkObject $script:WorkObject `
            -Name "VSCode-Extensions-Scan" `
            -Script "Get-ExtentionArray; Check VSIX files in `"$vsixPath`"" `
            -Output ($vsixOutput -join "`n")
        
        Write-LogMessage "Found $($vsCodeExtensions.Count) VS Code extensions" -Level INFO
    }
    catch {
        Write-LogMessage "Failed to scan VS Code extensions: $($_.Exception.Message)" -Level ERROR -Exception $_
        if ([string]::IsNullOrEmpty($script:WorkObject.ErrorMessage)) {
            $script:WorkObject.ErrorMessage = "VSCode extensions scan failed: $($_.Exception.Message)"
        }
    }
    
    # =========================================================================
    # STEP 3: Scan Windows Applications
    # =========================================================================
    Write-LogMessage "Scanning Windows applications..." -Level INFO
    $windowsApps = @()
    
    try {
        $windowsAppsPath = Get-WindowsAppsPath
        if (Test-Path -Path $windowsAppsPath -PathType Container) {
            $executablePatterns = @("*.msi", "*.exe", "*.bat", "*.cmd", "*.ps1")
            $filterList = @("*setup*.msi", "*setup*.exe", "*setup*.bat", "*setup*.cmd", "*setup*.ps1", "*install*.msi", "*install*.exe", "*install*.bat", "*install*.cmd", "*install*.ps1")
            
            Get-ChildItem -Path $windowsAppsPath -Directory -ErrorAction SilentlyContinue | ForEach-Object {
                $appFolder = $_
                $allExecutables = Get-ChildItem -Path $appFolder.FullName -File -Include $executablePatterns -Recurse -ErrorAction SilentlyContinue
                $executables = $allExecutables | Where-Object { 
                    $fileName = $_.Name.ToLower()
                    $matched = $false
                    foreach ($filter in $filterList) {
                        $pattern = $filter.ToLower().Replace("*", ".*")
                        if ($fileName -match $pattern) {
                            $matched = $true
                            break
                        }
                    }
                    return $matched
                }
                
                foreach ($exe in $executables) {
                    $relativePath = $exe.FullName.Substring($appFolder.FullName.Length + 1)
                    $subfolders = Split-Path $relativePath -Parent
                    $fullId = if ($subfolders) { 
                        "$($appFolder.Name).$($subfolders -replace '\\', '.')" 
                    }
                    else { 
                        $appFolder.Name 
                    }
                    
                    $windowsApps += [PSCustomObject]@{
                        ApplicationName = $appFolder.Name
                        SubFolder       = $subfolders
                        FullId          = $fullId
                        InstallerPath   = $exe.FullName
                        InstallerType   = $exe.Extension.TrimStart('.')
                        FileName        = $exe.Name
                        Version         = "Unknown"
                        FileSize        = $exe.Length
                        FileSizeKB      = [math]::Round($exe.Length / 1KB, 2)
                        InstallCommand  = "Start-Process -FilePath '$($exe.FullName)' -ArgumentList '/S'"
                        Category        = "WindowsApp"
                        LastModified    = $exe.LastWriteTime.ToString("yyyy-MM-dd HH:mm:ss")
                    }
                }
            }
            
            $script:WorkObject.WindowsAppsScanned = $true
            $script:WorkObject.TotalWindowsApps = $windowsApps.Count
            $script:WorkObject.WindowsApps = $windowsApps
            
            $windowsAppsOutput = @(
                "Windows apps path: $windowsAppsPath",
                "Applications found: $($windowsApps.Count)",
                "",
                "Applications:"
            ) + ($windowsApps | ForEach-Object { "  - $($_.FullId): $($_.FileName)" })
            
            $script:WorkObject = Add-ScriptAndOutputToWorkObject -WorkObject $script:WorkObject `
                -Name "Windows-Apps-Scan" `
                -Script "Get-ChildItem -Path `"$windowsAppsPath`" -Directory -Recurse -Include *.msi,*.exe,*.bat,*.cmd,*.ps1" `
                -Output ($windowsAppsOutput -join "`n")
            
            Write-LogMessage "Found $($windowsApps.Count) Windows applications" -Level INFO
        }
        else {
            Write-LogMessage "Windows apps path not accessible: $windowsAppsPath" -Level WARN
        }
    }
    catch {
        Write-LogMessage "Failed to scan Windows applications: $($_.Exception.Message)" -Level ERROR -Exception $_
        if ([string]::IsNullOrEmpty($script:WorkObject.ErrorMessage)) {
            $script:WorkObject.ErrorMessage = "Windows apps scan failed: $($_.Exception.Message)"
        }
    }
    
    # =========================================================================
    # STEP 4: Scan System Installers
    # =========================================================================
    Write-LogMessage "Scanning system installers..." -Level INFO
    $systemInstallers = @()
    
    try {
        $installerPaths = @(
            "C:\opt\src\DedgeSrc\DedgeSystemTools\Folders\DedgeCommon\Software\WindowsApps\Cursor System-Installer",
            "C:\opt\src\DedgeSrc\DedgeSystemTools\Folders\DedgeCommon\Software\WindowsApps\VSCode System-Installer"
        )
        
        foreach ($path in $installerPaths) {
            if (Test-Path $path -PathType Container) {
                $installers = Get-ChildItem -Path $path -File -Filter "*.exe" -ErrorAction SilentlyContinue
                foreach ($installer in $installers) {
                    # Extract version from filename (e.g., CursorSetup-x64-1.1.7.exe -> 1.1.7)
                    $version = "Unknown"
                    if ($installer.Name -match '(\d+\.\d+\.\d+)') {
                        $version = $Matches[1]
                    }
                    
                    $appName = if ($path -match "Cursor") { "Cursor" } elseif ($path -match "VSCode") { "VSCode" } else { "Unknown" }
                    $installArgs = if ($appName -eq "Cursor") { "/S" } else { "/SILENT" }
                    
                    $systemInstallers += [PSCustomObject]@{
                        ApplicationName = $appName
                        InstallerType   = "SystemInstaller"
                        InstallerPath   = $installer.FullName
                        FileName        = $installer.Name
                        Version         = $version
                        FileSize        = $installer.Length
                        FileSizeMB      = [math]::Round($installer.Length / 1MB, 2)
                        LastModified    = $installer.LastWriteTime.ToString("yyyy-MM-dd HH:mm:ss")
                        InstallCommand  = "Start-Process -FilePath '$($installer.FullName)' -ArgumentList '$installArgs'"
                        Category        = "SystemInstaller"
                    }
                }
            }
        }
        
        $script:WorkObject.InstallersScanned = $true
        $script:WorkObject.TotalInstallers = $systemInstallers.Count
        $script:WorkObject.SystemInstallers = $systemInstallers
        
        $installersOutput = @(
            "System installers scanned: $($installerPaths.Count) paths",
            "Installers found: $($systemInstallers.Count)",
            "",
            "Installers:"
        ) + ($systemInstallers | ForEach-Object { "  - $($_.ApplicationName): $($_.FileName) (v$($_.Version))" })
        
        $script:WorkObject = Add-ScriptAndOutputToWorkObject -WorkObject $script:WorkObject `
            -Name "System-Installers-Scan" `
            -Script "Scan system installer paths: $($installerPaths -join ', ')" `
            -Output ($installersOutput -join "`n")
        
        Write-LogMessage "Found $($systemInstallers.Count) system installers" -Level INFO
    }
    catch {
        Write-LogMessage "Failed to scan system installers: $($_.Exception.Message)" -Level ERROR -Exception $_
        if ([string]::IsNullOrEmpty($script:WorkObject.ErrorMessage)) {
            $script:WorkObject.ErrorMessage = "System installers scan failed: $($_.Exception.Message)"
        }
    }
    
    # =========================================================================
    # STEP 5: Get Ollama Models
    # =========================================================================
    Write-LogMessage "Scanning Ollama models..." -Level INFO
    $ollamaModels = @()
    
    try {
        Import-Module OllamaHandler -Force -ErrorAction SilentlyContinue
        $models = OllamaHandler\Get-OllamaModels -IncludeDetails -ErrorAction SilentlyContinue
        
        if ($models) {
            foreach ($model in $models) {
                $ollamaModels += [PSCustomObject]@{
                    Name              = $model.Name
                    Model             = $model.Model
                    Size              = $model.Size
                    SizeGB            = $model.SizeGB
                    ModifiedAt        = $model.ModifiedAt
                    Family            = $model.Family
                    ParameterSize     = $model.ParameterSize
                    QuantizationLevel = $model.QuantizationLevel
                    InstallCommand    = "Install-OllamaModel -ModelName '$($model.Name)'"
                    Category          = "OllamaModel"
                }
            }
            
            $script:WorkObject.OllamaModelsScanned = $true
            $script:WorkObject.TotalOllamaModels = $ollamaModels.Count
            $script:WorkObject.OllamaModels = $ollamaModels
            
            $ollamaOutput = @(
                "Ollama models found: $($ollamaModels.Count)",
                "",
                "Models:"
            ) + ($ollamaModels | ForEach-Object { "  - $($_.Name): $($_.SizeGB) ($($_.ParameterSize))" })
            
            $script:WorkObject = Add-ScriptAndOutputToWorkObject -WorkObject $script:WorkObject `
                -Name "Ollama-Models-Scan" `
                -Script "OllamaHandler\Get-OllamaModels -IncludeDetails" `
                -Output ($ollamaOutput -join "`n")
            
            Write-LogMessage "Found $($ollamaModels.Count) Ollama models" -Level INFO
        }
        else {
            Write-LogMessage "No Ollama models found or Ollama service not running" -Level WARN
        }
    }
    catch {
        Write-LogMessage "Failed to scan Ollama models: $($_.Exception.Message)" -Level WARN -Exception $_
        # Don't set error message for Ollama - it's optional
    }
    
    # =========================================================================
    # STEP 6: Export HTML Report
    # =========================================================================
    Write-LogMessage "Generating HTML report..." -Level INFO
    
    try {
        $endTime = Get-Date
        $script:WorkObject.EndTime = $endTime
        $script:WorkObject.Duration = $endTime - $startTime
        
        $script:WorkObject.Success = $true
        $script:WorkObject.Status = "Completed"
        
        $timestamp = Get-Date -Format "yyyyMMdd-HHmmss"
        $reportPath = Join-Path (Get-ApplicationDataPath) "SoftwareInventoryReport.html"
        
        Export-WorkObjectToHtmlFile -WorkObject $script:WorkObject `
            -FileName $reportPath `
            -Title "Software Inventory Report - Complete Overview" `
            -AddToDevToolsWebPath $true `
            -DevToolsWebDirectory "JobReports" `
            -AutoOpen $true
        
        $script:WorkObject.ReportGenerated = $true
        
        Write-LogMessage "HTML report exported to: $reportPath" -Level INFO
        Write-LogMessage "Summary:" -Level INFO
        Write-LogMessage "  Winget packages: $($script:WorkObject.TotalWingetPackages)" -Level INFO
        Write-LogMessage "  VS Code extensions: $($script:WorkObject.TotalVSCodeExtensions)" -Level INFO
        Write-LogMessage "  Windows apps: $($script:WorkObject.TotalWindowsApps)" -Level INFO
        Write-LogMessage "  System installers: $($script:WorkObject.TotalInstallers)" -Level INFO
        Write-LogMessage "  Ollama models: $($script:WorkObject.TotalOllamaModels)" -Level INFO
        Write-LogMessage "  Duration: $($script:WorkObject.Duration.ToString('hh\:mm\:ss'))" -Level INFO
    }
    catch {
        Write-LogMessage "Failed to export HTML report: $($_.Exception.Message)" -Level ERROR -Exception $_
        $script:WorkObject.Success = $false
        $script:WorkObject.Status = "Failed"
        $script:WorkObject.ErrorMessage = "Report export failed: $($_.Exception.Message)"
    }
    
    Write-LogMessage "$($script:WorkObject.Name)" -Level $(if ($script:WorkObject.Success) { "JOB_COMPLETED" } else { "JOB_FAILED" })
    
    return $script:WorkObject
}

Export-ModuleMember -Function * -Variable *
