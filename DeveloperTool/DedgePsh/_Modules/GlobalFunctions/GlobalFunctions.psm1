# Used to control which log messages are displayed to the console.

<#
.SYNOPSIS
    Provides global utility functions and configuration management for the Dedge PowerShell environment.

.DESCRIPTION
    This module contains essential global functions and utilities used throughout the Dedge PowerShell
    environment. It manages global settings, configuration file paths, Azure DevOps integration,
    directory structures, and provides common utility functions for string manipulation, file operations,
    and system administration tasks. Serves as the foundation layer for other modules.

.EXAMPLE
    Get-GlobalSettings
    # Retrieves the global configuration settings for the environment

.EXAMPLE
    Get-ConfigFilesPath
    # Returns the path to the configuration files directory
#>

function Get-UncPathFromLocalPath {
    param(
        [Parameter(Mandatory = $true)]
        [string]$LocalPath
    )
    return $LocalPath.Replace($env:OptPath, "\\$env:COMPUTERNAME.DEDGE.fk.no\opt")
}
function Get-LocalPathFromUncPath {
    param(
        [Parameter(Mandatory = $true)]
        [string]$UncPath
    )
    return $UncPath.Replace("\\$env:COMPUTERNAME.DEDGE.fk.no\opt", $env:OptPath)
}

function ConvertTo-DocViewUrl {
    param(
        [Parameter(Mandatory = $true)]
        [string]$UncPath
    )
    $contentRoot = "C:\opt\src\DedgeSrc\DedgeSystemTools\Folders\Opt\Webs\DocViewWeb\Content\"
    if (-not $UncPath.StartsWith($contentRoot, [System.StringComparison]::OrdinalIgnoreCase)) {
        throw "Path must be under $($contentRoot): $($UncPath)"
    }
    $relative = $UncPath.Substring($contentRoot.Length).Replace('\', '/')
    $encoded = [Uri]::EscapeDataString($relative).Replace('%2F', '/')
    return "http://dedge-server/DocView/#$($encoded)"
}

function Get-MostRecentlyChangedFileInFolder {
    param(
        [Parameter(Mandatory = $true)]
        [string]$FolderPath,
        [Parameter(Mandatory = $false)]
        [string]$Suffix = "",
        [Parameter(Mandatory = $false)]
        [switch]$Recursive
    )
    $gciParams = @{ Path = $FolderPath; File = $true; ErrorAction = 'SilentlyContinue' }
    if ($Recursive) { $gciParams['Recurse'] = $true }
    if (-not [string]::IsNullOrWhiteSpace($Suffix)) {
        # Normalize: accept "log", ".log", or "*.log" — all produce "*.log"
        $cleanSuffix = $Suffix.TrimStart('*').TrimStart('.')
        $gciParams['Filter'] = "*.$cleanSuffix"
    }
    $file = Get-ChildItem @gciParams | Sort-Object LastWriteTime -Descending | Select-Object -First 1
    if ($null -ne $file) {
        return $file.FullName
    }
    else {
        return $null
    }
}

# Global configuration paths
# These are initialized unconditionally to ensure they're always set,
# even when module is imported in parallel runspaces (ForEach-Object -Parallel)
# where module caching can prevent re-execution of module-level code.
$global:RemoteCommonConfigFilesFolder = "C:\opt\src\DedgeSrc\DedgeSystemTools\Folders\DedgeCommon\Configfiles"
$global:LocalCommonConfigFilesFolder = "$env:OptPath\data\DedgeCommon\Configfiles"
$global:RemoteGlobalSettingsFile = Join-Path $global:RemoteCommonConfigFilesFolder "GlobalSettings.json"

# Defensive re-initialization function for parallel runspace scenarios
# Call this at the start of any parallel block that uses GlobalFunctions
function Initialize-GlobalFunctionsForParallel {
    <#
    .SYNOPSIS
        Ensures GlobalFunctions global variables are properly initialized.
    .DESCRIPTION
        In ForEach-Object -Parallel runspaces, module-level variable assignments
        may not execute due to caching. This function guarantees the globals are set.
    .EXAMPLE
        # In a parallel block:
        Import-Module GlobalFunctions -Force
        Initialize-GlobalFunctionsForParallel
    #>
    if (-not $global:RemoteCommonConfigFilesFolder) {
        $global:RemoteCommonConfigFilesFolder = "C:\opt\src\DedgeSrc\DedgeSystemTools\Folders\DedgeCommon\Configfiles"
    }
    if (-not $global:LocalCommonConfigFilesFolder) {
        $global:LocalCommonConfigFilesFolder = "$env:OptPath\data\DedgeCommon\Configfiles"
    }
    if (-not $global:RemoteGlobalSettingsFile) {
        $global:RemoteGlobalSettingsFile = Join-Path $global:RemoteCommonConfigFilesFolder "GlobalSettings.json"
    }
}

# TODO MAYBE REMOVE THIS
# $global:OurPythonAppsName = "FkPythonApps"
# $global:OurNodeJsAppsName = "FkNodeJsApps"
# $global:OurWinAppsName = "DedgeWinApps"
# $global:OurPshAppsName = "DedgePshApps"


function Set-LogLevel {
    param(
        [Parameter(Mandatory = $true)]
        [ValidateSet("DEBUG", "INFO", "WARN", "ERROR", "TRACE")]
        [string]$LogLevel
    )
    Write-Host "LogLevel changed from $global:LogLevel to $LogLevel" -ForegroundColor Yellow
    $global:LogLevel = $LogLevel
    Start-Sleep -Seconds 1
}


function Reset-LogLevel {
    $global:LogLevel = "INFO"
}
if (Get-Variable -Name LogLevel -Scope Global -ErrorAction SilentlyContinue) {
    if ($global:LogLevel -notin @("DEBUG", "TRACE", "INFO", "WARN", "ERROR", "FATAL", "JOB_STARTED", "JOB_COMPLETED", "JOB_FAILED")) {
        Reset-LogLevel
    } 
    # else {
    #     Write-Host "LogLevel remained unchanged to $($global:LogLevel)" -ForegroundColor Yellow
    # }
}
else {
    $global:LogLevel = "INFO"
}

function Get-LogLevel {
    return $global:LogLevel
}

 
function Reset-OverrideAppDataFolder {
    $global:OverrideAppDataFolder = ""
    # remove the variable from the scope
    Remove-Variable -Name OverrideAppDataFolder -Scope Global -ErrorAction SilentlyContinue
    $null = Add-GlobalDynamicLogFileNames -Force
}

function Set-OverrideAppDataFolder {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Path
    )
    $existingPath = $global:OverrideAppDataFolder
    if (-not [string]::IsNullOrEmpty($Path)) {
        $global:OverrideAppDataFolder = $Path
    }
    else {
        Reset-OverrideAppDataFolder    
    }

    if ($Path -ne $existingPath) {
        $null = Add-GlobalDynamicLogFileNames -Force
    }
}

function Use-OverrideAppDataFolder {
    if (Get-Variable -Name OverrideAppDataFolder -Scope Global -ErrorAction SilentlyContinue) {
        if (-not [string]::IsNullOrEmpty($global:OverrideAppDataFolder)) {
            return $true
        }
        else {
            return $false
        }
    }
    return $false
}

function Get-OverrideAppDataFolder {
    return $global:OverrideAppDataFolder
}

function Set-OverrideLogFileName {
    param(
        [Parameter(Mandatory = $false)]
        [string]$FileName
    )
    $global:OverrideLogFileName = $FileName
    if (-not [string]::IsNullOrEmpty($FileName)) {
        $null = Add-GlobalDynamicLogFileNames -Force
    }
}

function Get-OverrideLogFileName {
    return $global:OverrideLogFileName
}

if (Get-Variable -Name OverrideAppDataFolder -Scope Global -ErrorAction SilentlyContinue) {
    if ([string]::IsNullOrEmpty($global:OverrideAppDataFolder)) {
        $global:OverrideAppDataFolder = ""
    }
    else {
        Write-Host "OverrideAppDataFolder remained unchanged to $($global:OverrideAppDataFolder)" -ForegroundColor Yellow
    }
}
else {
    $global:OverrideAppDataFolder = ""
}

if (-not (Get-Variable -Name OverrideLogFileName -Scope Global -ErrorAction SilentlyContinue)) {
    $global:OverrideLogFileName = ""
}

function Get-CommonSettings {
    if (-not (Get-Variable -Name FkGlobalSettings -Scope Global -ErrorAction SilentlyContinue) -and $null -eq $global:FkGlobalSettings) {
        $commonSettings = Get-Content $(Get-GlobalSettingsJsonFilename) | ConvertFrom-Json
        $databasev2Settings = Get-Content $(Get-DatabasesV2JsonFilename) | ConvertFrom-Json | Where-Object { $_.IsActive -eq $true }
        Add-Member -InputObject $commonSettings -MemberType NoteProperty -Name "DatabaseSettings" -Value $databasev2Settings -Force
        $global:FkGlobalSettings = $commonSettings
    }
    return $global:FkGlobalSettings
}

# function Sync-GlobalSettingsToLocalFolder {
#     try {
#         $localGlobalSettingFile = $(Join-Path $global:LocalCommonConfigFilesFolder "FkAllGlobalSettings$($PID).json")
#         if (Test-Path $localGlobalSettingFile -PathType Leaf) {
#             $lastWriteTime = Get-Item -Path $localGlobalSettingFile -Force | Select-Object -ExpandProperty LastWriteTime -ErrorAction SilentlyContinue 
#             if ($lastWriteTime) {
#                 $diffSeconds = ((Get-Date) - $lastWriteTime).TotalSeconds
#                 if ($diffSeconds -le 300) {
#                     $global:FkGlobalSettings = Get-Content -Path $localGlobalSettingFile -Raw | ConvertFrom-Json
#                     if ($(Get-LogLevel) -in @("DEBUG", "TRACE")) {
#                         Write-Host "Loaded cached global settings from local folder: $($lastWriteTime.ToString("yyyy-MM-dd HH:mm:ss.fff"))" -ForegroundColor Yellow
#                     }
#                     return $global:FkGlobalSettings
#                 }
#             }
#         }
     
#         $localFilesChanged = $false

#         if (Get-Variable -Name RemoteCommonConfigFilesFolder -Scope Global -ErrorAction SilentlyContinue) {
#             if (Test-Path $global:RemoteCommonConfigFilesFolder -PathType Container) {
#                 if ( $(Get-LogLevel) -in @("DEBUG", "TRACE")) {
#                     Write-Host "Syncing global settings to local folder" -ForegroundColor Yellow
#                 }
#                 if (-not (Test-Path $global:LocalCommonConfigFilesFolder -PathType Container)) {
#                     New-Item -ItemType Directory -Path $global:LocalCommonConfigFilesFolder -Force | Out-Null
#                 }
#                 # Robocopy parameters:
#                 # $global:RemoteCommonConfigFilesFolder - Source directory to copy from
#                 # $global:LocalCommonConfigFilesFolder - Destination directory to copy to
#                 # /E    - Copy subdirectories, including empty ones
#                 # /NFL  - No File List - don't log file names
#                 # /NDL  - No Directory List - don't log directory names
#                 # /NJH  - No Job Header
#                 # /NJS  - No Job Summary
#                 # /NC   - No Class - don't log file classes
#                 # /NS   - No Size - don't log file sizes
#                 # /LOG: - Write log to specified file
            
#                 # Run robocopy and capture the exit code to check for changes
#                 $robocopyPath = (Get-CommandPathWithFallback -Name "RoboCopy")
#                 $command = "$robocopyPath $global:RemoteCommonConfigFilesFolder $global:LocalCommonConfigFilesFolder /XD 'Backup' /E 2>&1"
#                 $null = Invoke-Expression $command

#                 # Robocopy exit codes:
#                 # 0 = No files copied
#                 # 1 = Files copied successfully
#                 # 2+ = Some failures occurred
            
#                 if ($LASTEXITCODE -eq 0) {
#                     $localFilesChanged = $false
#                 }            
#                 else {
#                     $localFilesChanged = $true
#                 }
#             }
#         }

#         if (-not ($localFilesChanged -eq $false -and $global:FkGlobalSettings -and $null -ne $global:FkGlobalSettings)) {
#             if ($(Get-LogLevel) -in @("DEBUG", "TRACE")) {
#                 Write-Host "Loading global settings from local folder" 
#             }
            
#             $globalSettingFile = $(Get-ChildItem -Path $global:LocalCommonConfigFilesFolder -Filter "GlobalSettings.json" -File)
#             $workGlobalSettings = Get-Content -Path $globalSettingFile.FullName -Raw | ConvertFrom-Json
#             $workGlobalSettingsToJson = $workGlobalSettings
#             if ($(Get-LogLevel) -in @("DEBUG", "TRACE")) {
#                 Write-Host "  - Loaded global settings from $($globalSettingFile.FullName)" -ForegroundColor Yellow
#             }

#             foreach ($file in $(Get-ChildItem -Path $global:LocalCommonConfigFilesFolder -Filter "*.json" -File)) {
#                 if ($file.BaseName -eq "FkGlobalSettings") {
#                     continue
#                 }
#                 $currentSettings = Get-Content -Path $file.FullName -Raw | ConvertFrom-Json
#                 Add-Member -InputObject $workGlobalSettingsToJson -MemberType NoteProperty -Name $($file.BaseName.TrimStart("Fk")) -Value $currentSettings -Force
#                 if ($file.BaseName -eq "FkDatabasesV2") {
#                     Add-Member -InputObject $workGlobalSettings -MemberType NoteProperty -Name $($file.BaseName.TrimStart("Fk")) -Value $currentSettings -Force
#                     if ($(Get-LogLevel) -in @("DEBUG", "TRACE")) {
#                         Write-Host $("       Added group element $($file.BaseName.TrimStart("Fk")) to global settings") -ForegroundColor Yellow
#                     }
#                     }
#                 # if ($(Get-LogLevel) -in @("DEBUG", "TRACE")) {
#                 #     Write-Host $("       Added group element $($file.BaseName.TrimStart("Fk")) to json global settings") -ForegroundColor Yellow
#                 # }

#                 # Set-Variable -Name $file.BaseName -Value $currentSettings -Scope Global
#             }
#             if ($(Get-LogLevel) -in @("DEBUG", "TRACE")) {
#                 Write-Host "  - All files loaded as global variables into `$workGlobalSettingsToJson" -ForegroundColor Yellow
#             }
#             # Save as local json file with retry logic and atomic write
#             $maxRetries = 1
#             $retryDelayMs = 200
#             $retryCount = 0
#             $writeSuccessful = $false
            
#             # Create a temporary file for atomic write operation
#             $tempFile = "$localGlobalSettingFile$($PID).tmp"
            
#             while ($retryCount -lt $maxRetries -and -not $writeSuccessful) {
#                 try {
                    
#                         # Write to temporary file first (atomic operation)
#                         $jsonContent = $workGlobalSettings | ConvertTo-Json -Depth 100
                    
#                         # Use .NET FileStream for better control over file access
#                         $fileStream = [System.IO.FileStream]::new($tempFile, [System.IO.FileMode]::Create, [System.IO.FileAccess]::Write, [System.IO.FileShare]::None)
#                         try {
#                             $writer = [System.IO.StreamWriter]::new($fileStream, [System.Text.Encoding]::UTF8)
#                             try {
#                                 $writer.Write($jsonContent)
#                                 $writer.Flush()
#                             }
#                             finally {
#                                 $writer.Dispose()
#                             }
#                         }
#                         finally {
#                             $fileStream.Dispose()
#                         }
                    
#                     if ($(Get-LogLevel) -in @("DEBUG", "TRACE")) {
#                         Write-Host "  - Wrote global settings to temporary file: $($tempFile)" -ForegroundColor Yellow
#                     }
                    
#                     # If temp file write succeeded, atomically move it to the final location
#                     # This ensures other processes don't see partial writes
#                     if (Test-Path $localGlobalSettingFile) {
#                         Remove-Item -Path $localGlobalSettingFile -Force
#                     }
#                     Move-Item -Path $tempFile -Destination $localGlobalSettingFile -Force
#                     if ($(Get-LogLevel) -in @("DEBUG", "TRACE")) {
#                         Write-Host "  - Moved temporary file to final location: $($localGlobalSettingFile)" -ForegroundColor Yellow
#                     }
                    
#                     $writeSuccessful = $true
#                 }
#                 catch {
#                     $retryCount++
#                     if (Test-Path $tempFile) {
#                         Remove-Item -Path $tempFile -Force -ErrorAction SilentlyContinue
#                     }
                    
#                     if ($retryCount -ge $maxRetries) {
#                         if ($(Get-LogLevel) -in @("DEBUG", "TRACE")) {
#                             Write-Host "Failed to write global settings file after $maxRetries attempts. Skipping saving global settings to local file." -ForegroundColor Yellow
#                         }

#                         throw $_
#                     }
#                     else {
#                         if ($(Get-LogLevel) -in @("DEBUG", "TRACE")) {
#                             Write-Host "Retry $retryCount/$($maxRetries): Failed to write global settings file, retrying in $($retryDelayMs) ms. `nError: $($_.Exception.Message)" -ForegroundColor Yellow
#                         }
#                         Start-Sleep -Milliseconds $retryDelayMs
#                     }
#                 }
#             }
#             if ($(Get-LogLevel) -in @("DEBUG", "TRACE")) {
#                 Write-Host "  - Saved global settings to $($globalSettingFile.FullName)" -ForegroundColor Yellow
#             }

#         }
#         # Get filecount from Local
#         $localFileCount = $(Get-ChildItem -Path $global:LocalCommonConfigFilesFolder -Filter "*.json" -File).Count
#         if ($localFileCount -eq 0) {
#             if ($(Get-LogLevel) -in @("DEBUG", "TRACE")) {
#                 Write-Host "No local files found, using remote files. Execution halted." -ForegroundColor Redfffffffffffff
#             }
#         }
#         $global:FkGlobalSettings = $workGlobalSettings
#         return $workGlobalSettings
#     }
#     catch {
#         Write-Host "Error loading global settings: $($_.Exception.Message)" -ForegroundColor Red 
#         throw
#     }
#     finally {
#         # Free up memory by removing the variable
#         $workGlobalSettingsToJson = $null
        
#     }
# }

# # Cache the settings to avoid repeated file reads
# $global:FkGlobalSettings = $null

<#
.SYNOPSIS
    Returns cached global settings to avoid repeated file reads.

.DESCRIPTION
    Retrieves cached global settings or loads them if not already cached.
    Improves performance by avoiding repeated file system access.

.EXAMPLE
    $settings = Get-CachedGlobalConfiguration
    # Gets cached global settings
#>
function Get-CachedGlobalConfiguration {
    #return Sync-GlobalSettingsToLocalFolder
    return Get-CommonSettings
}


<#
.SYNOPSIS
    Gets the default domain from global settings.

.DESCRIPTION
    Returns the organization's default domain from the global configuration.

.EXAMPLE
    $domain = Get-DefaultDomain
    # Returns the default domain (e.g., "DEDGE.fk.no")
#>
function Get-DefaultDomain {
    $settings = Get-CachedGlobalConfiguration
    return $settings.Organization.DefaultDomain
}
<#
.SYNOPSIS
    Gets the path to configuration files directory.

.DESCRIPTION
    Returns the full path to the configuration files directory by combining
    the common path with the configuration directory name.

.EXAMPLE
    $configPath = Get-ConfigFilesPath
    # Returns path to configuration files directory
#>
function Get-ConfigFilesPath {
    $settings = Get-CachedGlobalConfiguration
    return $(Join-Path $settings.Paths.Common $settings.Directories.Configfiles)
}
<#
.SYNOPSIS
    Gets the filename for the computer information JSON file.

.DESCRIPTION
    Returns the full path to the ComputerInfo.json configuration file.

.EXAMPLE
    $filename = Get-ComputerInfoJsonFilename
    # Returns path to ComputerInfo.json
#>
function Get-ComputerInfoJsonFilename {
    $settings = Get-CachedGlobalConfiguration
    return Join-Path $(Get-ConfigFilesPath) $settings.Config.ComputerInfo
}
<#
.SYNOPSIS
    Gets the filename for the AD information JSON file.

.DESCRIPTION
    Returns the full path to the AD information JSON configuration file.

.EXAMPLE
    $filename = Get-AdInfoJsonFilename
    # Returns path to AD information JSON file
#>
function Get-AdInfoJsonFilename {
    $settings = Get-CachedGlobalConfiguration
    return Join-Path $(Get-ConfigFilesPath) $settings.Config.AdInfo
}
<#
.SYNOPSIS
    Gets the filename for the server types JSON file.

.DESCRIPTION
    Returns the full path to the server types JSON configuration file.

.EXAMPLE
    $filename = Get-ServerTypesJsonFilename
    # Returns path to server types JSON file
#>
function Get-ServerTypesJsonFilename {
    $settings = Get-CachedGlobalConfiguration
    return Join-Path $(Get-ConfigFilesPath) $settings.Config.ServerTypes
}

<#
.SYNOPSIS
    Gets the filename for the port group JSON file.

.DESCRIPTION
    Returns the full path to the port group JSON configuration file.

.EXAMPLE
    $filename = Get-PortGroupJsonFilename
    # Returns path to port group JSON file
#>
function Get-PortGroupJsonFilename {
    $settings = Get-CachedGlobalConfiguration
    return Join-Path $(Get-ConfigFilesPath) $settings.Config.PortGroup
}

<#
.SYNOPSIS
    Gets the filename for the server port groups mapping JSON file.

.DESCRIPTION
    Returns the full path to the server port groups mapping JSON configuration file.

.EXAMPLE
    $filename = Get-ServerPortGroupsMappingJsonFilename
    # Returns path to server port groups mapping JSON file
#>
function Get-ServerPortGroupsMappingJsonFilename {
    $settings = Get-CachedGlobalConfiguration
    return Join-Path $(Get-ConfigFilesPath) $settings.Config.ServerPortGroupsMapping
}

<#
.SYNOPSIS
    Gets computer information from JSON configuration file.

.DESCRIPTION
    Reads and parses the computer information JSON file, returning the data as PowerShell objects.

.EXAMPLE
    $computers = Get-ComputerInfoJson
    # Returns all computer information from the JSON file
#>
function Get-ComputerInfoJson {
    return [PSCustomObject[]] $(Get-Content -Path $(Get-ComputerInfoJsonFilename) | ConvertFrom-Json)
}

<#
.SYNOPSIS
    Gets AD information from JSON configuration file.

.DESCRIPTION
    Reads and parses the AD information JSON file, returning the data as PowerShell objects.

.EXAMPLE
    $adInfo = Get-AdInfoJson
    # Returns AD information from the JSON file
#>
function Get-AdInfoJson {
    return [PSCustomObject] $(Get-Content -Path $(Get-AdInfoJsonFilename) | ConvertFrom-Json)
}
<#
.SYNOPSIS
    Gets server types from JSON configuration file.

.DESCRIPTION
    Reads and parses the server types JSON file, returning the data as PowerShell objects.

.EXAMPLE
    $serverTypes = Get-ServerTypesJson
    # Returns server types from the JSON file
#>
function Get-ServerTypesJson {
    return [PSCustomObject[]] $(Get-Content $(Get-ServerTypesJsonFilename) | ConvertFrom-Json)
}

<#
.SYNOPSIS
    Gets port group information from JSON configuration file.

.DESCRIPTION
    Reads and parses the port group JSON file, returning the data as PowerShell objects.

.EXAMPLE
    $portGroups = Get-PortGroupJson
    # Returns port group information from the JSON file
#>
function Get-PortGroupJson {
    return [PSCustomObject[]] $(Get-Content $(Get-PortGroupJsonFilename) | ConvertFrom-Json)
}

<#
.SYNOPSIS
    Gets server port groups mapping from JSON configuration file.

.DESCRIPTION
    Reads and parses the server port groups mapping JSON file, returning the data as PowerShell objects.

.EXAMPLE
    $mapping = Get-ServerPortGroupsMappingJson
    # Returns server port groups mapping from the JSON file
#>
function Get-ServerPortGroupsMappingJson {
    return [PSCustomObject[]] $(Get-Content $(Get-ServerPortGroupsMappingJsonFilename) | ConvertFrom-Json)
}

function Set-ComputerInfoJson {
    param(
        [Parameter(Mandatory = $true)]
        [PSCustomObject[]]$computers
    )
    $jsonFilePath = $(Get-ComputerInfoJsonFilename)
    $computers | ConvertTo-Json -Depth 100 | Set-Content -Path $jsonFilePath
}

<#
.SYNOPSIS
    Saves port group information to JSON configuration file.

.DESCRIPTION
    Converts port group objects to JSON format and saves them to the port group configuration file.

.PARAMETER Content
    The port group content to save to the JSON file.

.EXAMPLE
    Set-PortGroupJson -Content $portGroupArray
    # Saves port group information to the JSON file
#>
function Set-PortGroupJson {
    param(
        [Parameter(Mandatory = $true)]
        $Content
    )
    $Content | ConvertTo-Json -Depth 100 | Set-Content $(Get-PortGroupJsonFilename)
}

<#
.SYNOPSIS
    Saves server types to JSON configuration file.

.DESCRIPTION
    Converts server types objects to JSON format and saves them to the server types configuration file.

.PARAMETER Content
    The server types content to save to the JSON file.

.EXAMPLE
    Set-ServerTypesJson -Content $serverTypesArray
    # Saves server types to the JSON file
#>
function Set-ServerTypesJson {
    param(
        [Parameter(Mandatory = $true)]
        $Content
    )
    $Content | ConvertTo-Json -Depth 100 | Set-Content $(Get-ServerTypesJsonFilename)
}

<#
.SYNOPSIS
    Saves server port groups mapping to JSON configuration file.

.DESCRIPTION
    Converts server port groups mapping objects to JSON format and saves them 
    to the server port groups mapping configuration file.

.PARAMETER Content
    The server port groups mapping content to save to the JSON file.

.EXAMPLE
    Set-ServerTypesPortGroupJson -Content $mappingArray
    # Saves server port groups mapping to the JSON file
#>
function Set-ServerTypesPortGroupJson {
    param(
        [Parameter(Mandatory = $true)]
        $Content
    )
    $Content | ConvertTo-Json -Depth 100 | Set-Content $(Get-ServerPortGroupsMappingJsonFilename)
}

<#
.SYNOPSIS
    Gets the Azure DevOps organization name from global settings.

.DESCRIPTION
    Returns the Azure DevOps organization name configured in the global settings.

.EXAMPLE
    $org = Get-AzureDevOpsOrganization
    # Returns the Azure DevOps organization name
#>
function Get-AzureDevOpsOrganization {
    $settings = Get-CachedGlobalConfiguration
    return $settings.AzureDevOps.Organization
}

<#
.SYNOPSIS
    Gets the Azure DevOps project name from global settings.

.DESCRIPTION
    Returns the Azure DevOps project name configured in the global settings.

.EXAMPLE
    $project = Get-AzureDevOpsProject
    # Returns the Azure DevOps project name
#>
function Get-AzureDevOpsProject {
    $settings = Get-CachedGlobalConfiguration
    return $settings.AzureDevOps.Project
}

<#
.SYNOPSIS
    Gets the Azure DevOps repository name from global settings.

.DESCRIPTION
    Returns the Azure DevOps repository name configured in the global settings.

.EXAMPLE
    $repo = Get-AzureDevOpsRepository
    # Returns the Azure DevOps repository name
#>
function Get-AzureDevOpsRepository {
    $settings = Get-CachedGlobalConfiguration
    return $settings.AzureDevOps.Repository
}

<#
.SYNOPSIS
    Gets the Azure DevOps Personal Access Token from global settings.

.DESCRIPTION
    Returns the Azure DevOps Personal Access Token configured in the global settings.
    This token is used for authentication with Azure DevOps services.

.EXAMPLE
    $pat = Get-AzureDevOpsPat
    # Returns the Azure DevOps PAT

.NOTES
    This function returns sensitive authentication information.
#>
function Get-AzureDevOpsPat {
    $settings = Get-CachedGlobalConfiguration
    return $settings.AzureDevOps.Pat
}

<#
.SYNOPSIS
    Gets the DevTools web path from global settings.

.DESCRIPTION
    Returns the file system path to the DevTools web directory configured in global settings.

.EXAMPLE
    $webPath = Get-DevToolsWebPath
    # Returns the DevTools web path
#>
function Get-DevToolsWebPath {
    $settings = Get-CachedGlobalConfiguration
    return $settings.Paths.DevToolsWebContent
}
<#
.SYNOPSIS
    Gets the common logging path from global settings.

.DESCRIPTION
    Returns the file system path to the common logging directory configured in global settings.

.EXAMPLE
    $logPath = Get-CommonLogPath
    # Returns the common logging path
#>
function Get-CommonLogPath {
    $settings = Get-CachedGlobalConfiguration
    return $settings.Paths.CommonLog
}

<#
.SYNOPSIS
    Gets the DevTools web URL from global settings.

.DESCRIPTION
    Returns the web URL for accessing the DevTools web interface configured in global settings.

.EXAMPLE
    $webUrl = Get-DevToolsWebPathUrl
    # Returns the DevTools web URL
#>
function Get-DevToolsWebPathUrl {
    $settings = Get-CachedGlobalConfiguration
    return $settings.Paths.DevToolsWebUrl
}
<#
.SYNOPSIS
    Gets the common shared path from global settings.

.DESCRIPTION
    Returns the common shared file system path configured in global settings.
    This is typically used as the base path for shared resources.

.EXAMPLE
    $commonPath = Get-CommonPath
    # Returns the common shared path
#>
function Get-CommonPath {
    $settings = Get-CachedGlobalConfiguration
    return $settings.Paths.Common
}
<#
.SYNOPSIS
    Gets the temporary FK path from global settings.

.DESCRIPTION
    Returns the temporary file path configured in global settings.
    Creates the directory if it doesn't exist.

.EXAMPLE
    $tempPath = Get-TempFkPath
    # Returns the temporary FK path
#>
function Get-TempFkPath {
    $settings = Get-CachedGlobalConfiguration
    return $settings.Paths.TempFk
}
<#
.SYNOPSIS
    Gets the AD information file path from global settings.

.DESCRIPTION
    Returns the path to the Active Directory information file configured in global settings.

.EXAMPLE
    $adPath = Get-AdInfoPath
    # Returns the AD information file path
#>
function Get-AdInfoPath {
    $settings = Get-CachedGlobalConfiguration
    return $settings.Paths.AdInfo
}
<#
.SYNOPSIS
    Gets the configuration files resources path.

.DESCRIPTION
    Returns the path to the configuration files resources directory by combining
    the common path with the configuration resources directory name.

.EXAMPLE
    $resourcesPath = Get-ConfigFilesResourcesPath
    # Returns path to configuration resources directory
#>
function Get-ConfigFilesResourcesPath {
    $settings = Get-CachedGlobalConfiguration
    return $(Join-Path $settings.Paths.Common $settings.Directories.ConfigResources)
}
<#
.SYNOPSIS
    Gets the software installation path.

.DESCRIPTION
    Returns the path to the software directory by combining the common path
    with the software directory name.

.EXAMPLE
    $softwarePath = Get-SoftwarePath
    # Returns path to software directory
#>
function Get-SoftwarePath {
    $settings = Get-CachedGlobalConfiguration
    return $(Join-Path $settings.Paths.Common $settings.Directories.Software)
}

<#
.SYNOPSIS
    Gets the PowerShell default applications path.

.DESCRIPTION
    Returns the path to the PowerShell applications directory by combining
    the common path with the PowerShell apps directory name.

.EXAMPLE
    $pshAppsPath = Get-PowershellDefaultAppsPath
    # Returns path to PowerShell apps directory
#>
function Get-PowershellDefaultAppsPath {
    $settings = Get-CachedGlobalConfiguration
    return $(Join-Path $settings.Paths.Common $settings.Directories.PowerShellApps)
}

<#
.SYNOPSIS
    Gets the Windows default applications path.

.DESCRIPTION
    Returns the path to the Windows applications directory by combining
    the common path with the Windows apps directory name.

.EXAMPLE
    $winAppsPath = Get-WindowsDefaultAppsPath
    # Returns path to Windows apps directory
#>
function Get-WindowsDefaultAppsPath {
    $settings = Get-CachedGlobalConfiguration
    return $(Join-Path $settings.Paths.Common $settings.Directories.WindowsApps)
}
<#
.SYNOPSIS
    Gets the Node.js default applications path.

.DESCRIPTION
    Returns the path to the Node.js applications directory by combining
    the common path with the Node.js apps directory name.

.EXAMPLE
    $NodeJsAppsPath = Get-NodeDefaultAppsPath
    # Returns path to Node.js apps directory
#>
function Get-NodeDefaultAppsPath {
    $settings = Get-CachedGlobalConfiguration
    return $(Join-Path $settings.Paths.Common $settings.Directories.NodeJsApps)
}

<#
.SYNOPSIS
    Gets the Python default applications path.

.DESCRIPTION
    Returns the path to the Python applications directory by combining
    the common path with the Python apps directory name.

.EXAMPLE
    $pythonAppsPath = Get-PythonDefaultAppsPath
    # Returns path to Python apps directory
#>
function Get-PythonDefaultAppsPath {
    $settings = Get-CachedGlobalConfiguration
    return $(Join-Path $settings.Paths.Common $settings.Directories.PythonApps)
}

<#
.SYNOPSIS
    Gets the Rexx default applications path.

.DESCRIPTION
    Returns the path to the IBM Object Rexx applications directory by combining
    the common path with the Rexx apps directory name.

.EXAMPLE
    $rexxAppsPath = Get-RexxDefaultAppsPath
    # Returns path to Rexx apps directory
#>
function Get-RexxDefaultAppsPath {
    $settings = Get-CachedGlobalConfiguration
    return $(Join-Path $settings.Paths.Common $settings.Directories.RexxApps)
}


<#
.SYNOPSIS
    Gets the common log files path.

.DESCRIPTION
    Returns the path to the common log files directory by combining
    the common path with the log files directory name.

.EXAMPLE
    $logPath = Get-CommonLogFilesPath
    # Returns path to common log files directory
#>
function Get-CommonLogFilesPath {
    $settings = Get-CachedGlobalConfiguration
    return $(Join-Path $settings.Paths.Common $settings.Directories.Logfiles)
}

function Get-ScriptLogPath {
    $settings = Get-CachedGlobalConfiguration

    # Get script name of calling script
    $callStack = Get-PSCallStack
    $callingScript = $callStack[1].ScriptName
    try {
        $callingScriptFileNameOnly = Split-Path $callingScript -Leaf
    }
    catch {
        $callingScriptFileNameOnly = ""
    }
    try {
        $callingScriptFolder = $callingScriptFileNameOnly.Replace(".ps1", "").Trim()
    }
    catch {
        $callingScriptFolder = ""
    }
    if ([string]::IsNullOrEmpty($callingScript)) {
        $returnPath = Join-Path $settings.Paths.Common $settings.Directories.Logfiles
    }
    else {
        $returnPath = Join-Path $settings.Paths.Common $settings.Directories.Logfiles $callingScriptFolder
    }
    if (-not (Test-Path -Path $returnPath -PathType Container)) {
        try {
            New-Item -ItemType Directory -Path $returnPath
        }
        catch {
            Write-LogMessage "Failed to create directory at $returnPath. Using current directory." -Level WARN -Exception $_
            $returnPath = $PWD.Path
        }
    }
    return $returnPath
}

function Get-TempFkPath {
    $settings = Get-CachedGlobalConfiguration
    $path = $settings.Paths.TempFk
    if (-not (Test-Path -Path $path -PathType Container)) {
        try {
            New-Item -ItemType Directory -Path $path -Force | Out-Null
        }
        catch {
            Write-LogMessage "Failed to create directory at $path" -Level WARN -Exception $_
        }
    }
    return $path
}

function Get-WingetAppsPath {
    $settings = Get-CachedGlobalConfiguration
    $path = $(Join-Path $settings.Paths.Common $settings.Directories.WingetApps)    
    if (-not (Test-Path -Path $path -PathType Container)) {
        try {
            New-Item -ItemType Directory -Path $path -Force | Out-Null
        }
        catch {
            Write-LogMessage "Failed to create directory at $path" -Level WARN -Exception $_
        }
    }
    return $path
}

function Get-WindowsAppsPath {
    $settings = Get-CachedGlobalConfiguration
    $path = $(Join-Path $settings.Paths.Common $settings.Directories.OtherWindowsApps)
    if (-not (Test-Path -Path $path -PathType Container)) {
        try {
            New-Item -ItemType Directory -Path $path -Force | Out-Null
        }
        catch {
            Write-LogMessage "Failed to create directory at $path" -Level WARN -Exception $_
        }
    }
    return $path
}


# function Get-OptDataPath {
#     $returnPath = & {
#         # Get script name of calling script
#         $callStack = Get-PSCallStack | Select-Object -Property * 
#         $correctCallingScriptStackFrame = $null
#         for ($i = $callStack.Count - 1; $i -ge 0; $i--) {
#             if (-not [string]::IsNullOrEmpty($callStack[$i].ScriptName) -and -not $callStack[$i].ScriptName.ToLower().Contains(".psm1")) {
#                 $correctCallingScriptStackFrame = $callStack[$i]
#                 break
#             }
#         }
#         if ($null -eq $correctCallingScriptStackFrame) {
#             $correctCallingScriptStackFrame = $callStack[0]
#         }
#         $callingScript = $correctCallingScriptStackFrame.ScriptName
#         $callingScriptFolder = Split-Path -Path $correctCallingScriptStackFrame.ScriptName -Parent | Split-Path -Leaf
#         if ($callingScript -eq "") {
#             $returnPath = Join-Path $env:OptPath "data"
#         }
#         else {
#             $returnPath = Join-Path $env:OptPath "data" $callingScriptFolder
#         }
#         if (-not (Test-Path -Path $returnPath -PathType Container)) {
#             try {
#                 New-Item -ItemType Directory -Path $returnPath
#             }
#             catch {
#                 Write-LogMessage "Failed to create directory at $returnPath. Using current directory." -Level WARN -Exception $_
#                 $returnPath = $PWD.Path
#             }
#         }
#         return $returnPath
#     } 
#     return $returnPath
# }

function Get-ApplicationDataPath {
    param(
        [Parameter(Mandatory = $false)]
        [switch]$Force = $false
    )
    if (-not [string]::IsNullOrEmpty($global:OverrideAppDataFolder) -and -not $Force) {
        return $global:OverrideAppDataFolder
    }
    $returnPath = & {
        $callingScript = Get-FullScriptPath
        $callingScriptFolder = Split-Path -Path $callingScript -Parent | Split-Path -Leaf
        if ($callingScript -eq "") {
            $returnPath = $(Join-Path $env:OptPath "data")
        }
        else {
            $returnPath = $(Join-Path $env:OptPath "data" $callingScriptFolder)
        }
        if (-not (Test-Path -Path $returnPath -PathType Container)) {
            try {
                New-Item -ItemType Directory -Path $returnPath | Out-Null
            }
            catch {
                Write-LogMessage "Failed to create directory at $returnPath. Using current directory: $($PWD.Path)" -Level WARN -Exception $_
                $returnPath = $PWD.Path
            }
        }
        return $returnPath
    } 

    if ($returnPath.GetType() -eq [System.String]) {
        return $returnPath.ToString()
    }
    elseif ($returnPath.GetType() -eq [object[]]) {
        return $returnPath[0].Path.ToString()
    }
}

<#
.SYNOPSIS
    Contains logging-related utility functions for PowerShell modules.

.DESCRIPTION
    This module provides functions for dynamic log file management and writing log messages
    with different severity levels. It supports per-module log files and formatted logging
    with timestamps and metadata.
#>

<#
.SYNOPSIS
    Gets a dynamic log file name based on the calling module.

.DESCRIPTION
    Creates and manages a global variable containing the log file path for each module.
    The log file name includes the module name and timestamp.

.OUTPUTS
    System.String. The full path to the log file.
#>
function Add-GlobalDynamicLogFileNames {
    param (
        [Parameter(Mandatory = $false)]
        [switch]$Force
    )
    
    $allStackFrames = (Get-PSCallStack | Where-Object { $_.FunctionName -ne "<ScriptBlock>" })
    $stackFrame = $allStackFrames | Select-Object -Last 1

    if ($stackFrame -and $stackFrame.InvocationInfo -and $stackFrame.InvocationInfo.ScriptName -and $stackFrame.InvocationInfo.ScriptName.ToUpper().Contains(".PS1")) {
        $location = Split-Path -Path $stackFrame.InvocationInfo.ScriptName -Parent | Split-Path -Leaf
    }
    elseif ($stackFrame -and $stackFrame.Location) {
        $location = $stackFrame.Location.Split(".")[0]
    }
    else {
        # Fallback: all stack frames were <ScriptBlock> (e.g. catch block in a .ps1).
        # Try to resolve location from the full call stack including <ScriptBlock> entries.
        $fallbackFrame = Get-PSCallStack | Where-Object { $_.ScriptName } | Select-Object -Last 1
        if ($fallbackFrame -and $fallbackFrame.ScriptName) {
            $location = Split-Path -Path $fallbackFrame.ScriptName -Parent | Split-Path -Leaf
        }
        else {
            $location = "UnknownScript"
        }
    }

    # Create dynamic global log file variable name based on calling module
    $globalVarName = "ScriptLogFilesFor$location"

    # Try to get existing log files to increase performance
    if (-not $Force) {
        if (Get-Variable -Name $globalVarName -ErrorAction SilentlyContinue) {
            $logFiles = Get-Variable -Name $globalVarName -ValueOnly
            $validatedOk = $true
            foreach ($logFile in $logFiles) {
                if (-not $logFile.Contains("FkLog_")) {
                    $validatedOk = $false
                    break
                }
            }
            if ($validatedOk) {
                return $logFiles
            }
        }
    }

    # Add new log files not already existing
    $logFiles = @()
      
    $resultPath = $(Join-Path $env:OptPath "\data\" $location)
    if (-not (Test-Path $resultPath -PathType Container -ErrorAction SilentlyContinue)) {
        New-Item -ItemType Directory -Path $resultPath -Force -ErrorAction SilentlyContinue | Out-Null
    }
    $logFiles += $(Join-Path $resultPath $("FkLog_$(Get-Date -Format 'yyyyMMdd').log"))
   
    $resultPath = $(Join-Path $env:OptPath "\data\AllPwshLog")
    if (-not (Test-Path $resultPath -PathType Container -ErrorAction SilentlyContinue)) {
        New-Item -ItemType Directory -Path $resultPath -Force -ErrorAction SilentlyContinue | Out-Null
    }
    $logFiles += $(Join-Path $resultPath $("FkLog_$(Get-Date -Format 'yyyyMMdd').log"))


    if (Use-OverrideAppDataFolder) {
        # Initialize logFile variable with a default path or custom OverrideLogFileName
        $resultPath = Get-OverrideAppDataFolder
        if (-not (Test-Path $resultPath -PathType Container -ErrorAction SilentlyContinue)) {
            New-Item -ItemType Directory -Path $resultPath -Force -ErrorAction SilentlyContinue | Out-Null
        }
        $logFileName = if (-not [string]::IsNullOrEmpty($global:OverrideLogFileName)) { $global:OverrideLogFileName } else { "FkLog_$(Get-Date -Format 'yyyyMMdd').log" }
        $global:CurrentLogFilePath = Join-Path $resultPath $logFileName
        $logFiles += $global:CurrentLogFilePath
    }    

    Set-Variable -Name $globalVarName -Value $logFiles -Scope Global

    if ($global:LogLevel -eq "DEBUG" -or $global:LogLevel -eq "TRACE") {
        foreach ($logFile in $logFiles) {
            Write-Host "Log file: $logFile" -ForegroundColor Yellow
        }
    }

    $logFiles = $logFiles | Sort-Object -Unique
    $global:LogFiles = $logFiles
    return $logFiles
}
function Write-JobCompletionInfo {
    param(
        [Parameter(Mandatory = $false)]
        [string]$LogMessageBlankIndent,
        [Parameter(Mandatory = $false)]
        [string]$ForegroundColor
    )
    if (-not [string]::IsNullOrEmpty($global:OverrideLogFileName)) {
        Write-Host $LogMessageBlankIndent "Job Log file local path: $($global:OverrideLogFileName)" -ForegroundColor $ForegroundColor
        Write-Host $LogMessageBlankIndent "Job Log file UNC path: $(Get-UncPathFromLocalPath -LocalPath $global:OverrideLogFileName)" -ForegroundColor $ForegroundColor
    }
    if (-not [string]::IsNullOrEmpty($global:OverrideAppDataFolder)) {
        Write-Host $LogMessageBlankIndent "Job AppData folder local path: $($global:OverrideAppDataFolder)" -ForegroundColor $ForegroundColor
        Write-Host $LogMessageBlankIndent "Job AppData folder UNC path: $(Get-UncPathFromLocalPath -LocalPath $global:OverrideAppDataFolder)" -ForegroundColor $ForegroundColor
        # most recently changed file in the folder
        $mostRecentlyChangedFile = Get-MostRecentlyChangedFileInFolder -FolderPath $global:OverrideAppDataFolder
        if (-not [string]::IsNullOrEmpty($mostRecentlyChangedFile)) {
            Write-Host $LogMessageBlankIndent "Most recently changed file local path: $($mostRecentlyChangedFile)" -ForegroundColor $ForegroundColor
            Write-Host $LogMessageBlankIndent "Most recently changed file UNC path: $(Get-UncPathFromLocalPath -LocalPath $mostRecentlyChangedFile)" -ForegroundColor $ForegroundColor
        }
    }
}
<#
.SYNOPSIS
    Writes a formatted log message with metadata.

.DESCRIPTION
    Writes log messages with severity levels, timestamps, and optional exception details.
    Messages are written both to a log file and the console with appropriate coloring.

.PARAMETER Message
    The message to log.

.PARAMETER Level
    The severity level of the message (TRACE, DEBUG, INFO, WARN, ERROR, FATAL).
    Defaults to INFO.

.PARAMETER Exception
    Optional exception object to include detailed error information in the log.

.EXAMPLE
    Write-LogMessage "Operation completed successfully" -Level INFO
    Write-LogMessage "Operation failed" -Level ERROR -Exception $_.Exception
#>
function Write-LogMessage {
    param (
        [Parameter(Mandatory = $false)]
        [string]$Message,
        [Parameter(Mandatory = $false)]
        [ValidateSet("TRACE", "DEBUG", "INFO", "WARN", "ERROR", "FATAL", "JOB_STARTED", "JOB_COMPLETED", "JOB_FAILED")]
        [string]$Level = "INFO",
        [Parameter(Mandatory = $false)]
        # Using [System.Management.Automation.ErrorRecord] is correct since it matches
        # the $_ object type in PowerShell catch blocks. This allows direct passing
        # of the error object from catch statements like:
        # try { ... } catch { Write-LogMessage "Error" -Level Error -Exception $_ }
        [object]$Exception = $null,
        [Parameter(Mandatory = $false)]
        [System.ConsoleColor]$ForegroundColor,
        [Parameter(Mandatory = $false)]
        [switch]$NoNewline = $false,
        [Parameter(Mandatory = $false)]
        [string]$BatOriginScriptFileName = "",
        [Parameter(Mandatory = $false)]
        [Alias("Quiet")]
        [switch]$QuietMode,
        [Parameter(Mandatory = $false)]
        [ValidateSet("Powershell", "Db2", "Bat")]
        [string]$LogOriginType = "Powershell"
    )
    if ([string]::IsNullOrEmpty($Message)) {
        # Only output blank line, skip rest of function
        Write-Host
        return
    }
    try {
        $logStartDateTime = Get-Date 
        $originalException = $Exception
        $exceptionOffset = -1
        $exceptionLineNumber = -1
        $exceptionStatement = ""
        $exceptionFunctionName = ""

        if ($originalException.InvocationInfo) {
            if ($originalException.ScriptStackTrace) {
                try {
                    $exceptionFunctionName = $originalException.ScriptStackTrace.Split("`n")[0].Split(",")[0].Trim().Substring(3)
                }
                catch {
                    $exceptionFunctionName = ""
                }
            }


            if ($originalException.InvocationInfo.OffsetInLine) {
                $exceptionOffset = $originalException.InvocationInfo.OffsetInLine
            }
            if ($originalException.InvocationInfo.ScriptLineNumber) {
                $exceptionLineNumber = $originalException.InvocationInfo.ScriptLineNumber
            }
            if ($originalException.InvocationInfo.Line) {
                $exceptionStatement = $originalException.InvocationInfo.Line
            }
            if ($originalException.InvocationInfo.Line) {
                $exceptionLine = $originalException.InvocationInfo.Line
            }
        }  
        elseif ($originalException.Exception.CommandInvocation) {
            if ($originalException.Exception.CommandInvocation.ScriptLineNumber) {  
                $exceptionLineNumber = $originalException.Exception.CommandInvocation.ScriptLineNumber
            }
            if ($originalException.Exception.CommandInvocation.OffsetInLine) {
                $exceptionOffset = $originalException.Exception.CommandInvocation.OffsetInLine
            }
            if ($originalException.Exception.CommandInvocation.Line) {
                $exceptionStatement = $originalException.Exception.CommandInvocation.Line
            }
        }
        elseif ($originalException.ScriptStackTrace -like "*line *") {
            #"at Get-ServerConfiguration, $env:OptPath\src\DedgePsh\_Modules\Infrastructure\Infrastructure.psm1: line 346
            # at <ScriptBlock>, $env:OptPath\src\DedgePsh\DevTools\InfrastructureTools\PortCheckTool\PortCheckTool2.ps1: line 10
            # at <ScriptBlock>, <No file>: line 1"

            $exceptionLineNumber = $originalException.ScriptStackTrace.Split("`n")[0].Split("line ")[-1]
        }

        if ($exceptionStatement -ne "") {
            $exceptionStatement = $exceptionStatement.Replace("`n", "")
        }

        if ($Exception -is [System.Management.Automation.ErrorRecord]) {
            $Exception = $originalException.Exception
        }    
        elseif ($Exception -is [System.Exception]) {
            $Exception = $Exception.InnerException
        }
        elseif ($Exception -is [string] -or $Exception -is [System.String]) {
            $Exception = New-Object System.Exception($Exception)
        }
        else {
            $Exception = $null
        }


        $logFiles = Add-GlobalDynamicLogFileNames 
        $timestamp = $logStartDateTime.ToString("yyyy-MM-dd HH:mm:ss")
        $timeOnly = $logStartDateTime.ToString("HH:mm:ss")
        $length = ( "[$timestamp] " + "[$Level] ".PadRight(7)).Length 
        $lengthTimeOnly = ( "[$timeOnly]" + "[$Level] ".PadRight(7)).Length 
        $stackFrames = Get-PSCallStack | Select-Object -Property *
        $stackFrame = $stackFrames | Select-Object -First 1 -Skip 1
        $location = $stackFrame.Location.Split(":")[0]
        $lineNumber = $stackFrame.Location.Split(":")[1]
        $logMessageStartLevel = "[$Level] " 
        $logMessage = "$($Message.Trim())"
        $functionName = ""
        $location = ""
        $lineNumber = ""
        # Get detailed call stack information
        $stackFrame = (Get-PSCallStack | Where-Object { $_.Command -ne "<ScriptBlock>" -and $_.Command -ne "" } | Select-Object -First 1 -Skip 1)
        if ($stackFrame) {
            if ($stackFrame.FunctionName -eq "<ScriptBlock>") {
                $functionName = "Main"
            }
            else {
                $functionName = $stackFrame.FunctionName
                $sourceFilePath = $stackFrame.ScriptName
            }
            $location = $stackFrame.Location.Split(".")[0]
            $lineNumber = $stackFrame.ScriptLineNumber
        }

        if (-not [string]::IsNullOrEmpty($exceptionFunctionName)) {
            $functionName = $exceptionFunctionName
        }

        if (-not [string]::IsNullOrEmpty($functionName)) { 
            $logMessageStart = "[$timeOnly] " + "[$PID] " + "[$($location).$($functionName).$($lineNumber.ToString().Trim().Replace('line ', ''))] " 
        }
        else {
            $logMessageStart = "[$timeOnly] " + "[$PID] " + "[$($location).$($lineNumber.ToString().Trim().Replace('line ', ''))] " 
        }


        if (-not ($ForegroundColor -is [System.ConsoleColor])) {
            if ($Level -eq "TRACE") {
                $ForegroundColor = "DarkGray"
            }
            elseif ($Level -eq "DEBUG") {
                $ForegroundColor = "Gray"
            }
            elseif ($Level -eq "INFO") {
                $ForegroundColor = "White"
            }
            elseif ($Level -eq "WARN") {
                $ForegroundColor = "Yellow"
            }
            elseif ($Level -eq "ERROR") {
                $ForegroundColor = "Red"
            }
            elseif ($Level -eq "FATAL") {
                $ForegroundColor = "Red"
            }
            elseif ($Level -eq "JOB_STARTED") {
                $ForegroundColor = "Green"
            }
            elseif ($Level -eq "JOB_COMPLETED") {
                $ForegroundColor = "Green"
            }
            elseif ($Level -eq "JOB_FAILED") {
                $ForegroundColor = "Red"
            }
        }

        # Determine if the message should be shown based on the log level
        $LogLevel = $(Get-LogLevel)
        $doLogMessage = $false
        if ($QuietMode) {
            $doLogMessage = $false
        }
        elseif ($LogLevel -eq "TRACE" -and $Level -in @("TRACE", "DEBUG", "INFO", "WARN", "ERROR", "FATAL")) {
            $doLogMessage = $true        
        }
        elseif ($LogLevel -eq "DEBUG" -and $Level -in @("DEBUG", "INFO", "WARN", "ERROR", "FATAL")) {
            $doLogMessage = $true
        }
        elseif ($LogLevel -eq "INFO" -and $Level -in @("INFO", "WARN", "ERROR", "FATAL")) {
            $doLogMessage = $true
        }
        elseif ($LogLevel -eq "WARN" -and $Level -in @("WARN", "ERROR", "FATAL")) {
            $doLogMessage = $true
        }
        elseif ($LogLevel -eq "ERROR" -and $Level -in @("ERROR", "FATAL")) {
            $doLogMessage = $true
        }
        elseif ($LogLevel -eq "FATAL" -and $Level -in @("FATAL")) {
            $doLogMessage = $true
        }
        elseif ($Level -in @("JOB_STARTED")) {
            $doLogMessage = $true
        }
        elseif ($Level -in @("JOB_COMPLETED")) {
            $doLogMessage = $true
        }
        elseif ($Level -in @("JOB_FAILED")) {
            $doLogMessage = $true
        }

        # Set the timestamp log color based on the log origin type
        $timeStampLogColor = "Cyan"
        if ($LogOriginType -eq "Powershell") {
            $timeStampLogColor = "Cyan"
        }
        elseif ($LogOriginType -eq "Db2") {
            $timeStampLogColor = "Magenta"
        }
        elseif ($LogOriginType -eq "Bat") {
            $timeStampLogColor = "DarkYellow"
        }
        $logMessageBlankIndent = " " * ($logMessageStart.Length + $logMessageStartLevel.Length)

        if ($doLogMessage) {
            if ($logMessage -match "\n") {
                $length = $logMessageStart.Length + $logMessageStartLevel.Length 
                $logMessageLines = $logMessage -split "\n"
                $logMessage = ($logMessageLines | ForEach-Object -Process {
                        if ($logMessageLines[0] -eq $_) {
                            $_
                        }
                        else {
                            $logMessageBlankIndent + $_
                        }
                    }) -join "`n"
            }

            if ($ForegroundColor -is [System.ConsoleColor]) {
                $validForGroundColors = @("Black", "DarkBlue", "DarkGreen", "DarkCyan", "DarkRed", "DarkMagenta", "DarkYellow", "Gray", "DarkGray", "Blue", "Green", "Cyan", "Red", "Magenta", "Yellow", "White")
                if ($validForGroundColors -contains $ForegroundColor) {
                    if ($NoNewline) {
                        Write-Host $logMessageStart -NoNewline -ForegroundColor $timeStampLogColor
                        Write-Host $logMessageStartLevel -NoNewline -ForegroundColor $ForegroundColor   
                        if ($Level -in @( "JOB_COMPLETED", "JOB_FAILED")) {
                            Write-JobCompletionInfo -LogMessageBlankIndent $logMessageBlankIndent -ForegroundColor $ForegroundColor
                        }
                        Write-Host $logMessage -ForegroundColor $ForegroundColor -NoNewline
                    }
                    else {
                        Write-Host $logMessageStart -NoNewline -ForegroundColor $timeStampLogColor
                        Write-Host $logMessageStartLevel -NoNewline -ForegroundColor $ForegroundColor   
                        if ($Level -in @( "JOB_COMPLETED", "JOB_FAILED")) {
                            Write-JobCompletionInfo -LogMessageBlankIndent $logMessageBlankIndent -ForegroundColor $ForegroundColor
                        }
                        Write-Host $logMessage -ForegroundColor $ForegroundColor
                    }
                }
                else {
                    if ($NoNewline) {
                        Write-Host $logMessageStart -NoNewline -ForegroundColor $timeStampLogColor
                        Write-Host $logMessageStartLevel -NoNewline -ForegroundColor $ForegroundColor   
                        if ($Level -in @( "JOB_COMPLETED", "JOB_FAILED")) {
                            Write-JobCompletionInfo -LogMessageBlankIndent $logMessageBlankIndent -ForegroundColor $ForegroundColor
                        }
                        Write-Host $logMessage -ForegroundColor White -NoNewline
                    }
                    else {
                        Write-Host $logMessageStart -NoNewline -ForegroundColor $timeStampLogColor
                        Write-Host $logMessageStartLevel -NoNewline -ForegroundColor $ForegroundColor   
                        if ($Level -in @( "JOB_COMPLETED", "JOB_FAILED")) {
                            Write-JobCompletionInfo -LogMessageBlankIndent $logMessageBlankIndent -ForegroundColor $ForegroundColor
                        }
                        Write-Host $logMessage -ForegroundColor White
                    }
                }
            }
            else {
                switch ($Level) {
                    "TRACE" { 
                        if ($NoNewline) {
                            Write-Host $logMessageStart -NoNewline -ForegroundColor $timeStampLogColor
                            Write-Host $logMessageStartLevel -NoNewline -ForegroundColor $ForegroundColor   
                            Write-Host $logMessage -ForegroundColor Gray -NoNewline
                        }
                        else {
                            Write-Host $logMessageStart -NoNewline -ForegroundColor $timeStampLogColor
                            Write-Host $logMessageStartLevel -NoNewline -ForegroundColor $ForegroundColor   
                            Write-Host $logMessage -ForegroundColor Gray 
                        }
                    }
                    "DEBUG" { 
                        if ($NoNewline) {
                            Write-Host $logMessageStart -NoNewline -ForegroundColor $timeStampLogColor
                            Write-Host $logMessageStartLevel -NoNewline -ForegroundColor $ForegroundColor   
                            Write-Host $logMessage -ForegroundColor Gray -NoNewline
                        }
                        else {
                            Write-Host $logMessageStart -NoNewline -ForegroundColor $timeStampLogColor
                            Write-Host $logMessageStartLevel -NoNewline -ForegroundColor $ForegroundColor   
                            Write-Host $logMessage -ForegroundColor Gray 
                        }
                    }
                    "INFO" { 
                        if ($NoNewline) {
                            Write-Host $logMessageStart -NoNewline -ForegroundColor $timeStampLogColor
                            Write-Host $logMessageStartLevel -NoNewline -ForegroundColor $ForegroundColor   
                            Write-Host $logMessage -ForegroundColor White -NoNewline
                        }
                        else {
                            Write-Host $logMessageStart -NoNewline -ForegroundColor $timeStampLogColor
                            Write-Host $logMessageStartLevel -NoNewline -ForegroundColor $ForegroundColor   
                            Write-Host $logMessage -ForegroundColor White 
                        }
                    }
                    "WARN" { 
                        if ($NoNewline) {
                            Write-Host $logMessageStart -NoNewline -ForegroundColor $timeStampLogColor
                            Write-Host $logMessageStartLevel -NoNewline -ForegroundColor $ForegroundColor   
                            Write-Host $logMessage -ForegroundColor Yellow -NoNewline
                        }
                        else {
                            Write-Host $logMessageStart -NoNewline -ForegroundColor $timeStampLogColor
                            Write-Host $logMessageStartLevel -NoNewline -ForegroundColor $ForegroundColor   
                            Write-Host $logMessage -ForegroundColor Yellow 
                        }
                    }
                    "ERROR" { 
                        if ($NoNewline) {
                            Write-Host $logMessageStart -NoNewline -ForegroundColor $timeStampLogColor
                            Write-Host $logMessageStartLevel -NoNewline -ForegroundColor $ForegroundColor   
                            Write-Host $logMessage -ForegroundColor Red -NoNewline
                        }
                        else {
                            Write-Host $logMessageStart -NoNewline -ForegroundColor $timeStampLogColor
                            Write-Host $logMessageStartLevel -NoNewline -ForegroundColor $ForegroundColor   
                            Write-Host $logMessage -ForegroundColor Red 
                        }
                    }
                    "FATAL" { 
                        if ($NoNewline) {
                            Write-Host $logMessageStart -NoNewline -ForegroundColor $timeStampLogColor
                            Write-Host $logMessageStartLevel -NoNewline -ForegroundColor $ForegroundColor   
                            Write-Host $logMessage -ForegroundColor Red -NoNewline
                        }
                        else {
                            Write-Host $logMessageStart -NoNewline -ForegroundColor $timeStampLogColor
                            Write-Host $logMessageStartLevel -NoNewline -ForegroundColor $ForegroundColor   
                            Write-Host $logMessage -ForegroundColor Red 
                        }
                    }
                    "JOB_STARTED" { 
                        if ($NoNewline) {
                            Write-Host $logMessageStart -NoNewline -ForegroundColor $timeStampLogColor
                            Write-Host $logMessageStartLevel -NoNewline -ForegroundColor $ForegroundColor   
                            Write-Host $logMessage -ForegroundColor Green -NoNewline
                        }
                        else {
                            Write-Host $logMessageStart -ForegroundColor $timeStampLogColor -NoNewline
                            Write-Host $logMessageStartLevel -NoNewline -ForegroundColor $ForegroundColor   
                            Write-Host $logMessage -ForegroundColor Green 
                        }
                    }
                    "JOB_COMPLETED" { 
                        if ($NoNewline) {
                            Write-Host $logMessageStart -NoNewline -ForegroundColor $timeStampLogColor
                            Write-Host $logMessageStartLevel -NoNewline -ForegroundColor $ForegroundColor   
                            Write-Host $logMessage -ForegroundColor Green -NoNewline
                            Write-JobCompletionInfo -LogMessageBlankIndent $logMessageBlankIndent -ForegroundColor $ForegroundColor
                            Write-Progress -Completed

                        }
                        else {
                            Write-Host $logMessageStart -NoNewline -ForegroundColor $timeStampLogColor
                            Write-Host $logMessageStartLevel -NoNewline -ForegroundColor $ForegroundColor   
                            Write-Host $logMessage -ForegroundColor Green 
                            Write-JobCompletionInfo -LogMessageBlankIndent $logMessageBlankIndent -ForegroundColor $ForegroundColor
                            Write-Progress -Completed

                        }
                    }
                    "JOB_FAILED" { 
                        if ($NoNewline) {
                            Write-Host $logMessageStart -NoNewline -ForegroundColor $timeStampLogColor
                            Write-Host $logMessageStartLevel -NoNewline -ForegroundColor $ForegroundColor   
                            Write-Host $logMessage -ForegroundColor Red -NoNewline
                            Write-JobCompletionInfo -LogMessageBlankIndent $logMessageBlankIndent -ForegroundColor $ForegroundColor
                            Write-Progress -Completed

                        }
                        else {
                            Write-Host $logMessageStart -NoNewline -ForegroundColor $timeStampLogColor
                            Write-Host $logMessageStartLevel -NoNewline -ForegroundColor $ForegroundColor   
                            Write-Host $logMessage -ForegroundColor Red 
                            Write-JobCompletionInfo -LogMessageBlankIndent $logMessageBlankIndent -ForegroundColor $ForegroundColor
                            Write-Progress -Completed
                        }
                    }
                    default { 
                        if ($NoNewline) {
                            Write-Host $logMessageStart -NoNewline -ForegroundColor $timeStampLogColor
                            Write-Host $logMessageStartLevel -NoNewline -ForegroundColor $ForegroundColor   
                            Write-Host $logMessage -NoNewline
                        }
                        else {
                            Write-Host $logMessageStart -NoNewline -ForegroundColor $timeStampLogColor
                            Write-Host $logMessageStartLevel -NoNewline -ForegroundColor $ForegroundColor   
                            Write-Host $logMessage 
                        }
                    }
                }
            } 
        }
        $exObject = $null
        if ($null -ne $Exception) {
            if ($doLogMessage) {
                #Write-Host "ExceptionType at $($exceptionLineNumber): $($Exception.GetType().Name)"
                if ($Exception -is [System.Exception]) {
                    # PositionMessage
                    # Find function name where the error is thrown
                    $functionName = ""
                    if ($null -ne $Exception.ErrorRecord.InvocationInfo.MyCommand.Name) {
                        $functionName = $Exception.ErrorRecord.InvocationInfo.MyCommand.Name
                    }
                    elseif ($null -ne $Exception.ErrorRecord.InvocationInfo.MyCommand.Path) {
                        $functionName = $Exception.ErrorRecord.InvocationInfo.MyCommand.Path.Split("\")[-1].Replace(".ps1", "").Replace(".PS1", "")
                    }
                    else {
                        $functionName = "Main"
                    }
                    if ($functionName -ne "" -and $functionName.Contains(".")) {
                        $functionName = $functionName.Split(".")[-1]
                    }
                    $length = ( "[$timeOnly] " + "[$Level] ".PadRight(7)).Length 
                    #$length = ( "[$timestamp] " + "[$Level] ".PadRight(7)).Length 
                    $currLength = $length# - "Exception: ".Length
                    $messageLine = ""
                    if ($Exception.ErrorId) {
                        $messageLine += "$($Exception.ErrorId) at $($exceptionLineNumber)"
                    }
                    if ($Exception.Message) {
                        $messageLine += " - $($Exception.Message.TrimEnd("."))"
                        $messageLine = $messageLine.StartsWith(" - ") ? $messageLine.Substring(3) : $messageLine
                    }
                    if ($exceptionLineNumber -ne -1) {
                        $messageLine += ", at line $($exceptionLineNumber)"
                    }
                    if ($exceptionOffset -ne -1) {
                        $messageLine += ", offset $($exceptionOffset)"
                    }
                    if ($messageLine -ne "") {
                        Write-Host $((" " * $currLength) + [char]0x21B3 + " Exception : $messageLine") -ForegroundColor $ForegroundColor
                    }
                    if ($exceptionStatement -ne "") {
                        Write-Host $((" " * $currLength) + [char]0x21B3 + "   Line    : $exceptionStatement") -ForegroundColor $ForegroundColor
                    }
                    if ($exceptionOffset -ne -1) {
                        Write-Host $((" " * $currLength) + [char]0x21B3 + "   Position:$(' ' * ($exceptionOffset + 8))^") -ForegroundColor $ForegroundColor
                    }
               
                    $currLength = $length
        
                    $stackFrames = Get-PSCallStack | Select-Object -Property * 
                    $stackFramesTable = $stackFrames | Format-Table -AutoSize -Property Command, Location, FunctionName, ScriptLineNumber, ScriptName, Position  | Out-String
                    $count = 0  
                    Write-Host $((" " * $currLength) + [char]0x21B3 + " StackFrames " ) -ForegroundColor $ForegroundColor
                    $length += 4
                    foreach ($line in $stackFramesTable.Split("`n")) {
                        if ($line.Trim() -eq "") {
                            continue
                        }
                        # elseif ($line.Trim().StartsWith("Write-LogMessage")) {
                        #     continue
                        # }
                        elseif ($count -eq 0) {
                            Write-Host (((" " * ($length - 2)) + [char]0x21B3 + " " + $line)) -ForegroundColor $ForegroundColor
                        }
                        else {
                            Write-Host $((" " * $length) + $line) -ForegroundColor $ForegroundColor
                        }
                        $count++
                    }
                }
                $exObject = [PSCustomObject] @{
                    ErrorId           = $Exception.ErrorId ?? "Unknown"
                    ExceptionType     = $Exception.GetType().Name ?? "Unknown"
                    Message           = $Exception.Message ?? "Unknown"
                    StackTrace        = $Exception.StackTrace ?? "Unknown"
                    InnerException    = $Exception.InnerException ?? "Unknown"
                    CommandInvocation = $Exception.CommandInvocation
                    ScriptLineNumber  = $Exception.ScriptLineNumber ?? "Unknown"
                    ScriptName        = $Exception.ScriptName ?? "Unknown"
                    Position          = $Exception.Position ?? "Unknown"
                }
          
            }
        } 
        $null = & {   
            if ($doLogMessage) {
                # Create all logging folder if it doesn't exist
                $allLoggingFolder = Join-Path $env:OptPath "data\AllPwshLog"
                if (-not (Test-Path $allLoggingFolder -PathType Container)) {
                    New-Item -ItemType Directory -Path $allLoggingFolder -Force | Out-Null
                }
                # Create all logging file if it doesn't exist
                $getDate = $logStartDateTime.ToString("yyyyMMdd")
                $allLoggingFile = Join-Path $allLoggingFolder $($env:COMPUTERNAME + "_" + $getDate + ".log")
                $additionalLogEntryInfo = ""
                if ($exObject) {
                    $additionalLogEntryInfo = " | Exception at $($logObject.LineNumber): $($exObject.ExceptionType) - $($exObject.Message) "
                    if ($exObject.InnerException) {
                        $additionalLogEntryInfo += " | InnerException: $($exObject.InnerException.Message) "
                    }
                    if ($exObject.CommandInvocation) {
                        $additionalLogEntryInfo += " | CommandInvocation: $($exObject.CommandInvocation.Statement) "
                    }
                    if ($exObject.ScriptLineNumber) {
                        $additionalLogEntryInfo += " | ScriptLineNumber: $($exObject.ScriptLineNumber) "
                    }
                    if ($exObject.ScriptName) {
                        $additionalLogEntryInfo += " | ScriptName: $($exObject.ScriptName) "
                    }   
                }
                $logEntry = "$timestamp|$env:COMPUTERNAME|$Level|$LogOriginType|$PID|$location|$functionName|$lineNumber|$env:USERDOMAIN\$env:USERNAME|$Message" + $additionalLogEntryInfo
                foreach ($logFile in $logFiles) {
                    try {
                        if (-not $logFile.Contains("<No file>")) {
                            if (-not (Test-Path $logFile -PathType Leaf)) {
                                New-Item -ItemType File -Path $logFile -Force -ErrorAction SilentlyContinue | Out-Null
                            }
                            if ($global:LogLevel -eq "DEBUG" -or $global:LogLevel -eq "TRACE") {
                                Write-Host "Writing log entry to file $($logFile): `nLogEntry: $($logEntry.Trim())" -ForegroundColor Yellow
                            }
                            Add-Content -Path $logFile -Value $logEntry | Out-Null
                        }
                    }
                    catch {
                        Write-Host "Failed to write log entry to file $logFile" -ForegroundColor Yellow
                    }
                }
        


                if (Test-Path $(Get-CommonLogPath) -PathType Container) {
                    if ($Level -in @("WARN", "ERROR", "FATAL", "JOB_STARTED", "JOB_COMPLETED", "JOB_FAILED" )) {
                        $logJsonObject = [PSCustomObject] @{
                            Timestamp      = $logStartDateTime.ToString("yyyy-MM-dd HH:mm:ss.fff")
                            ComputerName   = $env:COMPUTERNAME
                            ProcessId      = $PID
                            Level          = $Level 
                            Location       = $location
                            FunctionName   = $functionName
                            LineNumber     = [int]$lineNumber.ToString().Trim().Replace("line ", "") ?? 0
                            User           = "$env:USERDOMAIN\$env:USERNAME"
                            Message        = $Message        
                            SourceFilePath = if ($sourceFilePath) { $sourceFilePath } else { $null }
                            LogFiles       = $logFiles
                        }
                        
                        if (-not [string]::IsNullOrEmpty($Exception.Message)) {
                            #$logJsonObject | Add-Member -MemberType NoteProperty -Name "Exception" -Value $exObject -Force
                            Add-Member -InputObject $logJsonObject -MemberType NoteProperty -Name "ErrorId" -Value $Exception.ErrorId -Force
                            Add-Member -InputObject $logJsonObject -MemberType NoteProperty -Name "ExceptionType" -Value $Exception.GetType().Name -Force
                            Add-Member -InputObject $logJsonObject -MemberType NoteProperty -Name "Message" -Value $Exception.Message -Force
                            Add-Member -InputObject $logJsonObject -MemberType NoteProperty -Name "StackTrace" -Value $Exception.StackTrace -Force
                            Add-Member -InputObject $logJsonObject -MemberType NoteProperty -Name "InnerException" -Value $Exception.InnerException -Force
                            Add-Member -InputObject $logJsonObject -MemberType NoteProperty -Name "CommandInvocation" -Value $Exception.CommandInvocation -Force
                            Add-Member -InputObject $logJsonObject -MemberType NoteProperty -Name "ScriptLineNumber" -Value $Exception.ScriptLineNumber -Force
                            Add-Member -InputObject $logJsonObject -MemberType NoteProperty -Name "ScriptName" -Value $Exception.ScriptName -Force
                            Add-Member -InputObject $logJsonObject -MemberType NoteProperty -Name "LinePosition" -Value $Exception.Position -Force
                        }
                        # Find number of levels in the object
                        
                        # Create a deep copy of the object with max 10 levels
                        function Copy-ObjectWithMaxDepth {
                            param(
                                [Parameter(Mandatory)]
                                $InputObject,
                                [int]$MaxDepth = 10,
                                [int]$CurrentDepth = 0
                            )
                            
                            if ($CurrentDepth -ge $MaxDepth) {
                                return "[Truncated - Max depth $MaxDepth reached]"
                            }
                            
                            if ($null -eq $InputObject) {
                                return $null
                            }
                            
                            # Handle value types and strings
                            if ($InputObject -is [System.ValueType] -or $InputObject -is [string]) {
                                return $InputObject
                            }
                            
                            # Handle special PowerShell types that should be converted to strings
                            if ($InputObject -is [System.Management.Automation.ErrorRecord]) {
                                return @{
                                    ErrorMessage          = $InputObject.Exception.Message
                                    CategoryInfo          = $InputObject.CategoryInfo.ToString()
                                    FullyQualifiedErrorId = $InputObject.FullyQualifiedErrorId
                                    ScriptStackTrace      = $InputObject.ScriptStackTrace
                                    PositionMessage       = $InputObject.InvocationInfo.PositionMessage
                                }
                            }
                            
                            if ($InputObject -is [System.Exception]) {
                                return @{
                                    ExceptionType         = $InputObject.GetType().Name
                                    Message               = $InputObject.Message
                                    StackTrace            = $InputObject.StackTrace
                                    InnerExceptionMessage = $InputObject.InnerException?.Message
                                }
                            }
                            
                            # Handle other complex types that might cause issues
                            $typeName = $InputObject.GetType().Name
                            if ($typeName -in @('CommandInvocation', 'InvocationInfo', 'CallStackFrame', 'RuntimeDefinedParameter')) {
                                return $InputObject.ToString()
                            }
                            
                            # Handle arrays and collections
                            if ($InputObject -is [System.Collections.IEnumerable] -and $InputObject -isnot [string]) {
                                $newArray = @()
                                try {
                                    foreach ($item in $InputObject) {
                                        $newArray += Copy-ObjectWithMaxDepth -InputObject $item -MaxDepth $MaxDepth -CurrentDepth ($CurrentDepth + 1)
                                    }
                                }
                                catch {
                                    return "[Array conversion failed: $($_.Exception.Message)]"
                                }
                                return $newArray
                            }
                            
                            # Handle PSCustomObject and other objects
                            $newObject = [PSCustomObject]@{}
                            try {
                                foreach ($property in $InputObject.PSObject.Properties) {
                                    try {
                                        # Skip properties that are known to cause issues
                                        if ($property.Name -in @('SyncRoot', 'CompilerServices', 'Module', 'Assembly')) {
                                            continue
                                        }
                                        
                                        $propertyValue = $null
                                        try {
                                            $propertyValue = $property.Value
                                        }
                                        catch {
                                            # If we can't access the property value, skip it
                                            continue
                                        }
                                        
                                        $copiedValue = Copy-ObjectWithMaxDepth -InputObject $propertyValue -MaxDepth $MaxDepth -CurrentDepth ($CurrentDepth + 1)
                                        Add-Member -InputObject $newObject -MemberType NoteProperty -Name $property.Name -Value $copiedValue -Force
                                    }
                                    catch {
                                        # If individual property fails, add error info instead
                                        Add-Member -InputObject $newObject -MemberType NoteProperty -Name $property.Name -Value "[Property access failed: $($_.Exception.Message)]" -Force
                                    }
                                }
                            }
                            catch {
                                return "[Object conversion failed: $($_.Exception.Message)]"
                            }
                            
                            return [PSCustomObject]$newObject
                        }
                        
                        # Create a copy of logJsonObject limited to 10 levels
                        $logJsonObject = Copy-ObjectWithMaxDepth -InputObject $logJsonObject -MaxDepth 10

                        $outputFolder = "$(Get-CommonLogPath)\Psh"
                        if (-not (Test-Path $outputFolder -PathType Container)) {
                            New-Item -ItemType Directory -Path $outputFolder -Force | Out-Null
                        }
                        $fileName = "FkLog_DT-$($logStartDateTime.ToString("yyyyMMddHHmmssfff"))_LEV-$($Level)_DNS-$($env:COMPUTERNAME)_PID-$($PID).json"
                        $jsonFilename = "$outputFolder\$fileName"
                        $logJsonObject | ConvertTo-Json -Depth 100 -ErrorAction SilentlyContinue | Out-File -FilePath $jsonFilename -Encoding UTF8 -ErrorAction SilentlyContinue
                        # $logJsonObject | ConvertTo-Json -Depth 100 -ErrorAction SilentlyContinue | Out-File -FilePath $jsonFilename -Encoding UTF8 -ErrorAction SilentlyContinue
                    }
                }
            }

        } 
    }
    catch {
        # Use Write-Host to write the log entry since Write-LogMessage is current function
        Write-Host "Failed to write log entry" -ForegroundColor Red
        Write-Host "Error: $_" -ForegroundColor Red
        # foreach ($line in $_.ScriptStackTrace.Split("`n")) {
        #     Write-Host "  $line" -ForegroundColor Red
        # }
        Write-Host "`nDetailed error properties:" -ForegroundColor Red
        $errorObject = [PSCustomObject]$_ 
        foreach ($level1 in ($errorObject | Get-Member -MemberType Properties)) {
            $propertyName = $level1.Name
            $propertyValue = $errorObject.$propertyName
            if ($level1.MemberType -eq "NoteProperty") {
                Write-Host "  $propertyName : $propertyValue" -ForegroundColor Red
            }
            else {
                if ($propertyValue -is [System.Collections.IEnumerable]) {
                    foreach ($level2 in $propertyValue) {
                        Write-Host "  $($level1.Name)  $($level2.Name) : $($level2.ToString())" -ForegroundColor DarkYellow
                    }
                }
            }
        }
    }
    # Reset override app data folder if job is completed or failed
    if ($Level -in @("JOB_COMPLETED", "JOB_FAILED")) {
        Reset-OverrideAppDataFolder
    }

}


function Send-Email {
    <#
.SYNOPSIS
Sends an email message through the organization's SMTP server.

            .DESCRIPTION
            The FKASendEmail function provides a simplified interface for sending emails through the organization's SMTP server.
It wraps the PowerShell Send-MailMessage cmdlet with predefined server settings and error handling.

.PARAMETER To
The email address of the recipient.

.PARAMETER From
The email address of the sender.

.PARAMETER Subject
The subject line of the email.

.PARAMETER Body
The content of the email message.

.PARAMETER HtmlBody
If provided, sends the email with HTML formatting.

.PARAMETER Attachments
An array of file paths to attach to the email.

.EXAMPLE
FKASendEmail -To "recipient@example.com" -From "sender@example.com" -Subject "Test Email" -Body "This is a test email."

.EXAMPLE
FKASendEmail -To "recipient@example.com" -From "sender@example.com" -Subject "HTML Test" -Body "<h1>Hello World</h1><p>This is an HTML email.</p>" -HtmlBody

.EXAMPLE
FKASendEmail -To "recipient@example.com" -From "sender@example.com" -Subject "Report" -Body "Please find the attached report." -Attachments @("C:\Reports\report.pdf", "C:\Reports\data.xlsx")

.NOTES
This module uses the deprecated Send-MailMessage cmdlet. In future versions, it may be updated to use alternative methods for sending emails.
#>
    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $true)]
        [string]$To,
        [Parameter(Mandatory = $true)]
        [string]$From,
        [Parameter(Mandatory = $true)]
        [string]$Subject,
        [Parameter(Mandatory = $false)]
        [string]$Body,
        [Parameter(Mandatory = $false)]
        [string]$HtmlBody,
        [Parameter(Mandatory = $false)]
        [string[]]$Attachments,
        [Parameter(Mandatory = $false)]
        [string]$Cc = "",
        [Parameter(Mandatory = $false)]
        [string]$Bcc = "",
        [Parameter(Mandatory = $false)]
        [string]$Encoding = "UTF8",
        [Parameter(Mandatory = $false)]
        [string]$Priority = "Normal"
    )
    try {
        $messageBody = $null
        if (-not [string]::IsNullOrEmpty($HtmlBody)) {
            $messageBody = $HtmlBody
            Write-LogMessage "Sending email to $To from $From with subject $Subject (HTML body)" -Level INFO -Quiet
        }
        else {
            $messageBody = $Body
            Write-LogMessage "Sending email to $To from $From with subject $Subject" -Level INFO
        }

        $newAttachments = @()
        foreach ($attachment in $Attachments) {
            if (Test-Path $attachment -PathType Leaf) {
                $newAttachments += $attachment
            }
            else {
                Write-LogMessage "Attachment not found. Skipping attachment $attachment" -Level WARN
            }
        }
        $params = @{
            To          = $To
            From        = $From
            SmtpServer  = "smtp.DEDGE.fk.no" 
            Subject     = $Subject
            ErrorAction = 'SilentlyContinue'
            Encoding    = $Encoding ?? "UTF8"
            Priority    = $Priority ?? "Normal"
        }
        if (-not [string]::IsNullOrEmpty($HtmlBody)) { 
            $params.Body = $HtmlBody 
            $params.BodyAsHtml = $true
        }
        else { 
            $params.Body = $messageBody 
            $params.BodyAsHtml = $false
        }
        if ($newAttachments) { $params.Attachments = $newAttachments }
        if (-not [string]::IsNullOrEmpty($Cc)) { $params.Cc = $Cc }
        if (-not [string]::IsNullOrEmpty($Bcc)) { $params.Bcc = $Bcc }
        Send-MailMessage @params
        Write-LogMessage "Email sent successfully to $To from $From with subject $Subject" -Level INFO
    }
    catch {
        Write-LogMessage "Failed to send email to $To from $From with subject $Subject" -Level ERROR -Exception $_
    }
}
<#
.SYNOPSIS
Sends SMS messages via the organization's SMS web service.

.DESCRIPTION
The Send-Sms function sends SMS messages using the organization's SOAP web service.
It handles various input formats for recipients and provides detailed logging.

.PARAMETER Receiver
The phone number of the recipient(s). Should include country code (e.g., "+4712345678").
Can be a single string, comma-separated string, array, or other collection.

.PARAMETER Message
The text message to be sent.

.EXAMPLE
Send-Sms -Receiver "+4712345678" -Message "This is a test message"

.EXAMPLE
Send-Sms -Receiver "+4712345678,+4787654321" -Message "This is a test message"

.EXAMPLE
Send-Sms -Receiver @("+4712345678", "+4787654321") -Message "This is a test message"

.NOTES
This function logs the SMS sending activity using the Logger module.
#>
function Send-Sms {
    param(
        [Parameter(Mandatory = $true)]
        [object] $Receiver,
        [Parameter(Mandatory = $true)]
        [string] $Message
    )

    try {
        # Convert $Receiver to a normalized array of strings
        $receiverArray = @()
    
        if ($Receiver.Count) {
            foreach ($item in $Receiver) {
                if ($item -is [string]) {
                    $receiverArray += $item.Trim()
                }
            }
        }
        elseif ($Receiver -is [string]) {
            # Handle comma-separated string
            if ($Receiver.Contains(",")) {
                $receiverArray = $Receiver.Split(",") | ForEach-Object { $_.Trim() } | Where-Object { $_ -ne "" }
            }
            else {
                $receiverArray += $Receiver.Trim()
            }
        }
        elseif ($Receiver -is [array] -or $Receiver -is [System.Collections.IEnumerable]) {
            # Handle arrays and other collections
            foreach ($item in $Receiver) {
                if ($item -is [string]) {
                    $receiverArray += $item.Trim()
                }
            }
        }
        else {
            # Handle single non-string object by converting to string
            $receiverArray += $Receiver.ToString().Trim()
        }
    
        # Remove any empty entries
        $receiverArray = $receiverArray | Where-Object { $_ -ne "" }
    
        if ($receiverArray.Count -eq 0) {
            Write-LogMessage "No valid receivers provided for SMS" -Level WARN
            return
        }
    
        # Process each receiver one at a time
        foreach ($receiver in $receiverArray) {
            Write-LogMessage "Sending SMS to $receiver with message: $Message" -Level INFO
        
            try {
                $req = (New-Object System.Net.WebClient)
                $req.Headers.Add("Content-Type", "application/xml")
                $xmlPayload = "<?xml version=""1.0""?><SESSION><CLIENT>fk</CLIENT><PW>fksmsnet</PW><MSGLST><MSG><TEXT>$Message</TEXT><RCV>$receiver</RCV><SND>23022222</SND></MSG></MSGLST></SESSION>"
                $null = $req.UploadString("http://sms3.pswin.com/sms", $xmlPayload)
                Write-LogMessage "SMS sent successfully to $receiver" -Level INFO
            }
            catch {
                Write-LogMessage "Failed to process SMS for receiver $receiver" -Level ERROR -Exception $_
            }
        }
    }
    catch {
        Write-LogMessage "Failed to process SMS sending request" -Level ERROR -Exception $_
    }
}

<#
.SYNOPSIS
Sends a message to Microsoft Teams via webhook or Microsoft Graph API.

.DESCRIPTION
The Send-TeamsMessage function provides two methods for sending messages to Microsoft Teams:
1. Webhook mode: Send messages to a Teams channel via Incoming Webhook URL
2. Graph API mode: Send direct chat messages to users by their email address using Microsoft Graph

For Webhook mode, you need an Incoming Webhook URL from your Teams channel.
For Graph API mode, you need Azure AD app credentials with Chat.ReadWrite permissions.

.PARAMETER To
The recipient email address(es) for Graph API mode. Can be a single email, 
comma-separated string, or array of emails.

.PARAMETER Message
The text message to send. Supports plain text or basic markdown formatting.

.PARAMETER Title
Optional title/header for the message (appears bold in Teams).

.PARAMETER WebhookUrl
The Incoming Webhook URL for sending to a Teams channel.
When specified, the function operates in Webhook mode.

.PARAMETER ThemeColor
The accent color for the message card (hex color without #). Default is "0076D7" (Microsoft blue).

.PARAMETER UseGraphApi
Switch to use Microsoft Graph API for sending direct messages to users.
Requires Azure AD app configuration in GlobalSettings.json.

.PARAMETER Sections
Optional array of additional sections for Adaptive Card format.
Each section is a hashtable with 'title' and 'text' keys.

.EXAMPLE
Send-TeamsMessage -WebhookUrl "https://outlook.office.com/webhook/..." -Message "Deployment completed successfully"

Sends a simple message to a Teams channel via webhook.

.EXAMPLE
Send-TeamsMessage -WebhookUrl "https://outlook.office.com/webhook/..." -Title "Build Status" -Message "Build #123 passed all tests" -ThemeColor "00FF00"

Sends a message with a title and green accent color to a Teams channel.

.EXAMPLE
Send-TeamsMessage -To "geir.helge.starholm@Dedge.no" -Message "Server backup completed" -UseGraphApi

Sends a direct chat message to a user via Microsoft Graph API.

.EXAMPLE
Send-TeamsMessage -To "user1@company.com,user2@company.com" -Title "Alert" -Message "Database maintenance starting in 10 minutes" -UseGraphApi

Sends a direct message to multiple users via Graph API.

.NOTES
Webhook mode:
- Create an Incoming Webhook connector in your Teams channel
- No authentication required, just the webhook URL
- Messages appear as channel posts

Graph API mode:
- Requires Azure AD app with Chat.ReadWrite permissions
- Configuration stored in GlobalSettings.json under "MicrosoftGraph" section
- Messages appear as direct chat from the app

Author: Geir Helge Starholm, www.dEdge.no
#>
function Send-TeamsMessage {
    [CmdletBinding(DefaultParameterSetName = 'Webhook')]
    param(
        [Parameter(Mandatory = $true, ParameterSetName = 'GraphApi')]
        [object]$To,
        
        [Parameter(Mandatory = $true)]
        [string]$Message,
        
        [Parameter(Mandatory = $false)]
        [string]$Title,
        
        [Parameter(Mandatory = $true, ParameterSetName = 'Webhook')]
        [string]$WebhookUrl,
        
        [Parameter(Mandatory = $false)]
        [string]$ThemeColor = "0076D7",
        
        [Parameter(Mandatory = $false, ParameterSetName = 'GraphApi')]
        [switch]$UseGraphApi,
        
        [Parameter(Mandatory = $false)]
        [hashtable[]]$Sections
    )

    try {
        if ($PSCmdlet.ParameterSetName -eq 'Webhook' -or -not $UseGraphApi) {
            # ========================
            # WEBHOOK MODE
            # ========================
            Send-TeamsMessageViaWebhook -WebhookUrl $WebhookUrl -Message $Message -Title $Title -ThemeColor $ThemeColor -Sections $Sections
        }
        else {
            # ========================
            # GRAPH API MODE
            # ========================
            Send-TeamsMessageViaGraphApi -To $To -Message $Message -Title $Title
        }
    }
    catch {
        Write-LogMessage "Failed to send Teams message" -Level ERROR -Exception $_
    }
}

<#
.SYNOPSIS
Internal function to send Teams message via Incoming Webhook.
#>
function Send-TeamsMessageViaWebhook {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$WebhookUrl,
        
        [Parameter(Mandatory = $true)]
        [string]$Message,
        
        [Parameter(Mandatory = $false)]
        [string]$Title,
        
        [Parameter(Mandatory = $false)]
        [string]$ThemeColor = "0076D7",
        
        [Parameter(Mandatory = $false)]
        [hashtable[]]$Sections
    )

    try {
        Write-LogMessage "Sending Teams message via webhook" -Level INFO

        # Build the message card payload (Office 365 Connector Card format)
        $payload = @{
            "@type"      = "MessageCard"
            "@context"   = "http://schema.org/extensions"
            "themeColor" = $ThemeColor
            "summary"    = if ($Title) { $Title } else { $Message.Substring(0, [Math]::Min(50, $Message.Length)) }
        }

        # Add title if provided
        if (-not [string]::IsNullOrEmpty($Title)) {
            $payload["title"] = $Title
        }

        # Build sections
        $cardSections = @()
        
        # Main message section
        $mainSection = @{
            "activityTitle" = ""
            "text"          = $Message
            "markdown"      = $true
        }
        $cardSections += $mainSection

        # Add additional sections if provided
        if ($Sections) {
            foreach ($section in $Sections) {
                $cardSections += @{
                    "activityTitle" = $section.title
                    "text"          = $section.text
                    "markdown"      = $true
                }
            }
        }

        $payload["sections"] = $cardSections

        # Convert to JSON
        $jsonPayload = $payload | ConvertTo-Json -Depth 10 -Compress

        # Send the request
        $headers = @{
            "Content-Type" = "application/json"
        }

        $response = Invoke-RestMethod -Uri $WebhookUrl -Method Post -Body $jsonPayload -Headers $headers -ErrorAction Stop

        Write-LogMessage "Teams message sent successfully via webhook" -Level INFO
        return $true
    }
    catch {
        Write-LogMessage "Failed to send Teams message via webhook: $($_.Exception.Message)" -Level ERROR -Exception $_
        return $false
    }
}

<#
.SYNOPSIS
Internal function to send Teams direct message via Microsoft Graph API.

.DESCRIPTION
Sends a chat message directly to a user by their email address using Microsoft Graph API.
Requires Azure AD app configuration with Chat.ReadWrite permissions.

.NOTES
Graph API configuration should be in GlobalSettings.json:
{
    "MicrosoftGraph": {
        "TenantId": "your-tenant-id",
        "ClientId": "your-app-client-id",
        "ClientSecret": "your-app-client-secret"
    }
}
#>
function Send-TeamsMessageViaGraphApi {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [object]$To,
        
        [Parameter(Mandatory = $true)]
        [string]$Message,
        
        [Parameter(Mandatory = $false)]
        [string]$Title
    )

    try {
        # Convert $To to a normalized array of email addresses (same pattern as Send-Sms)
        $recipientArray = @()
    
        if ($To.Count) {
            foreach ($item in $To) {
                if ($item -is [string]) {
                    $recipientArray += $item.Trim()
                }
            }
        }
        elseif ($To -is [string]) {
            # Handle comma-separated string
            if ($To.Contains(",")) {
                $recipientArray = $To.Split(",") | ForEach-Object { $_.Trim() } | Where-Object { $_ -ne "" }
            }
            else {
                $recipientArray += $To.Trim()
            }
        }
        elseif ($To -is [array] -or $To -is [System.Collections.IEnumerable]) {
            foreach ($item in $To) {
                if ($item -is [string]) {
                    $recipientArray += $item.Trim()
                }
            }
        }
        else {
            $recipientArray += $To.ToString().Trim()
        }
    
        # Remove any empty entries
        $recipientArray = $recipientArray | Where-Object { $_ -ne "" }
    
        if ($recipientArray.Count -eq 0) {
            Write-LogMessage "No valid recipients provided for Teams message" -Level WARN
            return $false
        }

        # Load Graph API configuration from GlobalSettings.json
        $globalSettingsPath = Join-Path $env:OptPath "DedgeCommon\ConfigFiles\GlobalSettings.json"
        if (-not (Test-Path $globalSettingsPath -PathType Leaf)) {
            Write-LogMessage "GlobalSettings.json not found at $globalSettingsPath. Cannot send Teams message via Graph API." -Level ERROR
            return $false
        }

        $globalSettings = Get-Content $globalSettingsPath -Raw | ConvertFrom-Json
        
        if (-not $globalSettings.MicrosoftGraph) {
            Write-LogMessage "MicrosoftGraph configuration not found in GlobalSettings.json. Please add TenantId, ClientId, and ClientSecret." -Level ERROR
            return $false
        }

        $graphConfig = $globalSettings.MicrosoftGraph
        $tenantId = $graphConfig.TenantId
        $clientId = $graphConfig.ClientId
        $clientSecret = $graphConfig.ClientSecret

        if ([string]::IsNullOrEmpty($tenantId) -or [string]::IsNullOrEmpty($clientId) -or [string]::IsNullOrEmpty($clientSecret)) {
            Write-LogMessage "Incomplete MicrosoftGraph configuration. Ensure TenantId, ClientId, and ClientSecret are set." -Level ERROR
            return $false
        }

        # Get access token from Azure AD
        Write-LogMessage "Acquiring Microsoft Graph access token" -Level DEBUG
        
        $tokenUrl = "https://login.microsoftonline.com/$tenantId/oauth2/v2.0/token"
        $tokenBody = @{
            client_id     = $clientId
            scope         = "https://graph.microsoft.com/.default"
            client_secret = $clientSecret
            grant_type    = "client_credentials"
        }

        $tokenResponse = Invoke-RestMethod -Uri $tokenUrl -Method Post -Body $tokenBody -ContentType "application/x-www-form-urlencoded" -ErrorAction Stop
        $accessToken = $tokenResponse.access_token

        if ([string]::IsNullOrEmpty($accessToken)) {
            Write-LogMessage "Failed to acquire access token for Microsoft Graph" -Level ERROR
            return $false
        }

        $headers = @{
            "Authorization" = "Bearer $accessToken"
            "Content-Type"  = "application/json"
        }

        # Build the message content
        $messageContent = if (-not [string]::IsNullOrEmpty($Title)) {
            "<b>$Title</b><br/><br/>$Message"
        }
        else {
            $Message
        }

        # Process each recipient
        $successCount = 0
        foreach ($recipient in $recipientArray) {
            try {
                Write-LogMessage "Sending Teams message to $recipient via Graph API" -Level INFO

                # Get user ID from email
                $userUrl = "https://graph.microsoft.com/v1.0/users/$recipient"
                $userResponse = Invoke-RestMethod -Uri $userUrl -Headers $headers -Method Get -ErrorAction Stop
                $userId = $userResponse.id

                if ([string]::IsNullOrEmpty($userId)) {
                    Write-LogMessage "Could not find user ID for $recipient" -Level WARN
                    continue
                }

                # Create or get existing chat with the user
                # Using chat between the app and the user
                $chatBody = @{
                    chatType = "oneOnOne"
                    members  = @(
                        @{
                            "@odata.type"     = "#microsoft.graph.aadUserConversationMember"
                            "roles"           = @("owner")
                            "user@odata.bind" = "https://graph.microsoft.com/v1.0/users/$userId"
                        }
                    )
                } | ConvertTo-Json -Depth 5

                $chatUrl = "https://graph.microsoft.com/v1.0/chats"
                $chatResponse = Invoke-RestMethod -Uri $chatUrl -Headers $headers -Method Post -Body $chatBody -ErrorAction Stop
                $chatId = $chatResponse.id

                if ([string]::IsNullOrEmpty($chatId)) {
                    Write-LogMessage "Could not create/get chat with user $recipient" -Level WARN
                    continue
                }

                # Send the message to the chat
                $messageBody = @{
                    body = @{
                        contentType = "html"
                        content     = $messageContent
                    }
                } | ConvertTo-Json -Depth 5

                $messageUrl = "https://graph.microsoft.com/v1.0/chats/$chatId/messages"
                $null = Invoke-RestMethod -Uri $messageUrl -Headers $headers -Method Post -Body $messageBody -ErrorAction Stop

                Write-LogMessage "Teams message sent successfully to $recipient" -Level INFO
                $successCount++
            }
            catch {
                Write-LogMessage "Failed to send Teams message to $($recipient): $($_.Exception.Message)" -Level ERROR -Exception $_
            }
        }

        if ($successCount -eq $recipientArray.Count) {
            Write-LogMessage "All $successCount Teams messages sent successfully via Graph API" -Level INFO
            return $true
        }
        elseif ($successCount -gt 0) {
            Write-LogMessage "Sent $successCount of $($recipientArray.Count) Teams messages via Graph API" -Level WARN
            return $true
        }
        else {
            Write-LogMessage "Failed to send any Teams messages via Graph API" -Level ERROR
            return $false
        }
    }
    catch {
        Write-LogMessage "Failed to send Teams message via Graph API: $($_.Exception.Message)" -Level ERROR -Exception $_
        return $false
    }
}

function Get-ExecutableExtensions {
    return @("*.ps1", "*.psm1", "*.exe", "*.cmd", "*.bat", "*.exe", "*.dll", "*.msi", "*.sys", "*.ocx", "*.ax", "*.cpl", "*.drv", "*.efi", "*.mui", "*.scr", "*.tsp", "*.plugin", "*.xll", "*.wll", "*.pyd", "*.pyo", "*.pyc", "*.jar", "*.war", "*.ear", "*.class", "*.xpi", "*.crx", "*.nex", "*.xbap", "*.application", "*.manifest", "*.appref-ms", "*.gadget", "*.widget", "*.ipa", "*.apk", "*.xap", "*.msix", "*.msixbundle", "*.appx", "*.appxbundle", "*.msp", "*.mst", "*.msu", "*.tlb", "*.com" )
}
function Get-AdditionalAllowedContentExtensions {
    return @("*.sql", "*.ini", "*.cfg", "*.xml", "*.js", "*.html", "*.css", "*.ico", "*.png", "*.jpg", "*.jpeg", "*.gif", "*.bmp", "*.tiff", "*.ico", "*.webp", "*.json", "*.md", "*.unsigned", "*.csv", "*.dat", "*.txt", "*.log", "*.bak", "*.old", "*.tmp", "*.temp", "*.tempfile", "*.tempfolder", "*.tempfile", "*.tempfolder", "*.xlsx", "*.xls", "*.doc", "*.docx", "*.ppt", "*.pptx", "*.odt", "*.ods", "*.odp", "*.odg", "*.odf", "*.odc", "*.odm", "*.odc")
}
function Start-DedgeSignFile {
    param(
        [Parameter(Mandatory = $true)]
        [string]$FilePath
    )
    # $DedgeSignPath = Join-Path $env:OptPath "DedgePshApps\DedgeSign"
    # $DedgeSignScript = Join-Path $DedgeSignPath "DedgeSign.ps1"
    # if (-not (Test-Path $DedgeSignScript -PathType Leaf)) {
    #     $DedgeSignPath = Join-Path $env:OptPath "src\DedgePsh\DevTools\AdminTools\DedgeSign"
    #     $DedgeSignScript = Join-Path $DedgeSignPath "DedgeSign.ps1"
    # }
    # $result = & $DedgeSignScript -Path $FilePath -Action Add -NoConfirm
    $result = Invoke-DedgeSign -Path $FilePath -Action Add -NoConfirm
    if (-not $result) {
        Write-LogMessage "Failed to sign file $FilePath" -Level ERROR
        throw
    }
}

function Start-DedgeSignFolder {
    param(
        [Parameter(Mandatory = $true)]
        [string]$FolderPath,
        [Parameter()]
        [bool]$Recursive = $true,
        [Parameter()]
        [bool]$Parallel = $true
    )


    $DedgeSignPath = Join-Path $env:OptPath "DedgePshApps\DedgeSign"
    $DedgeSignScript = Join-Path $DedgeSignPath "DedgeSign.ps1"
    if (-not (Test-Path $DedgeSignScript -PathType Leaf)) {
        $DedgeSignPath = Join-Path $env:OptPath "src\DedgePsh\DevTools\AdminTools\DedgeSign"
        $DedgeSignScript = Join-Path $DedgeSignPath "DedgeSign.ps1"
    }
    if ($Recursive) {
        if ($Parallel) {
            $result = & $DedgeSignScript -Path $FolderPath -Action Add -NoConfirm -Recursive -Parallel
        }
        else {
            $result = & $DedgeSignScript -Path $FolderPath -Action Add -NoConfirm -Recursive
        }
    }
    else {
        if ($Parallel) {
            $result = & $DedgeSignScript -Path $FolderPath -Action Add -NoConfirm -Parallel
        }
        else {
            $result = & $DedgeSignScript -Path $FolderPath -Action Add -NoConfirm
        }
    }
    if ($result -ne 0) {
        Write-LogMessage "Failed to sign file $FilePath" -Level ERROR
        throw
    }
}

function Remove-PathFromSemicolonSeparatedVariable {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Variable,

        [Parameter(Mandatory = $true)]
        [string]$Path    
    )

    # Split path into array and remove empty entries
    $pathArray = $Variable.Split('; ', [System.StringSplitOptions]::RemoveEmptyEntries) 

    # Remove path if it exists
    if ($pathArray -contains $Path) {
        $pathArray = $pathArray | Where-Object { $_ -ne $Path }
        Write-LogMessage "Removed '$Path' from variable $Variable" -Level INFO
    }
    else {
        Write-LogMessage "'$Path' not found during path removal of non-existing path in variable $Variable" -Level INFO
    }
    # Join array elements with semicolons, filtering out any elements that are just whitespace
    $returnVariable = ""
    foreach ($path in $pathArray) {
        if ($path.Trim() -ne "") {
            $returnVariable += $path + ";"
        }
    }

    return $returnVariable
}
function Add-PathToSemicolonSeparatedVariable {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Variable,

        [Parameter(Mandatory = $true)]
        [string]$Path
    )

    # Split path into array and remove empty entries
    $pathArray = $Variable.Split('; ', [System.StringSplitOptions]::RemoveEmptyEntries)

    # Remove path if it exists
    if ($pathArray -notcontains $Path) {
        $pathArray += $Path
        Write-LogMessage "Added '$Path' to variable $Variable" -Level INFO
    }
    else {
        Write-LogMessage "'$Path' already exists in variable $Variable" -Level INFO
    }
    # Join array elements with semicolons, filtering out any elements that are just whitespace
    $returnVariable = ""
    foreach ($path in $pathArray) {
        if ($path.Trim() -ne "") {
            $returnVariable += $path + ";"
        }
    }

    return $returnVariable
}

function Show-MessageBox {
    param (
        [Parameter(Mandatory = $true)]
        [string]$Message,
        [Parameter(Mandatory = $false)]
        [string]$Title = "Information",
        [Parameter(Mandatory = $false)]
        [int]$Timeout = 0,
        [Parameter(Mandatory = $false)]
        [int]$Style = 64  # 64 = Information icon
    )

    $scriptBlock = {
        param($Message, $Title, $Timeout, $Style)
        Add-Type -AssemblyName System.Windows.Forms
        [System.Windows.Forms.MessageBox]::Show($Message, $Title, [System.Windows.Forms.MessageBoxButtons]::OK, $Style)
    }

    $job = Start-Job -ScriptBlock $scriptBlock -ArgumentList $Message, $Title, $Timeout, $Style
    return $job
}
function Close-MessageBox {
    param (
        [System.Management.Automation.Job]$Job
    )
    try {
        if ($Job) {
            Stop-Job -Job $Job -ErrorAction SilentlyContinue
            Remove-Job -Job $Job -Force -ErrorAction SilentlyContinue
        }
    }
    catch {}
}
function Start-ModuleRefresh {
    $allModules = Get-Module -ListAvailable -Refresh 
    $optModules = $allModules | Where-Object { $_.Path -like "*\opt\*" }
    # Add LastWriteTime property to each module object
    $optModules = $optModules | Select-Object *, @{
        Name       = 'LastChanged'
        Expression = { 
            $modulePath = $_.Path
            if (Test-Path $modulePath) {
                (Get-Item $modulePath).LastWriteTime
            }
            else {
                $null
            }
        }
    }

    $optModules | Format-Table -AutoSize -Property Name, Path, LastChanged
}

function Set-PSModulePath {
    param (
        [Parameter(Mandatory = $false)]
        [string]$OptPath = $env:OptPath
    )
    # Update PSModulePath
    $RemovePSModulePaths = @("$env:OptPath\DedgePsh\_Modules", "$env:OptPath\Apps\CommonModules", "$env:OptPath\DedgePshApps\CommonModules", "$env:OptPath\psh\_Modules")
    $AddPSModulePaths = @("$env:OptPath\src\DedgePsh\_Modules", "$env:OptPath\DedgePshApps\CommonModules")
    $PSModulePathOriginal = [Environment]::GetEnvironmentVariable("PSModulePath", [EnvironmentVariableTarget]::Machine)

    # First remove paths we don't want
    $validPaths = @()
    foreach ($path in ($PSModulePathOriginal -split ";")) {
        $skipPath = $false
        foreach ($removePath in $RemovePSModulePaths) {
            if ($path -like "*$removePath*") {
                $skipPath = $true
                break
            }
        }
        if (-not $skipPath -and (Test-Path $path -PathType Container)) {
            $validPaths += $path
        }
    }

    # Then add new paths if they exist
    foreach ($path in $AddPSModulePaths) {
        if (Test-Path $path -PathType Container) {
            $validPaths += $path
        }
    }

    # Join back into single string
    $PSModulePathOriginal = $validPaths -join ";"


    if ($PSModulePathOriginal) {
        [System.Environment ]::SetEnvironmentVariable("PSModulePath", $PSModulePathOriginal, [System.EnvironmentVariableTarget]::Machine)
        Write-LogMessage "Set PSModulePath environment variable" -Level INFO
    }
    
    Write-LogMessage "PSModulePath in priority order:" -Level INFO
    $paths = [System.Environment ]::GetEnvironmentVariable("PSModulePath", [System.EnvironmentVariableTarget]::Machine) -split ";"
    for ($i = 0; $i -lt $paths.Count; $i++) {
        Write-LogMessage "  $($i + 1). $($paths[$i])" -Level INFO
    }
    Start-ModuleRefresh
}

<#
.SYNOPSIS
Flattens objects with array properties into multiple objects.

.DESCRIPTION
Takes an object that contains array properties and converts it into multiple objects,
where each object has a single value from each array property.

.PARAMETER InputObject
The object containing array properties to flatten.

.EXAMPLE
$flattenedObjects = ConvertTo-FlattenedObject -InputObject $complexObject
# Returns multiple objects with array properties flattened

.OUTPUTS
Array of PSCustomObjects with flattened properties
#>
function ConvertTo-FlattenedObject {
    param (
        [Parameter(Mandatory = $true)]
        $InputObject,
    
        [Parameter(Mandatory = $false)]
        [string[]]$ExcludeArrayProperties = @(),
    
        [Parameter(DontShow)]
        [int]$Depth = 0
    )

    try {
        # Base case: null or primitive value
        if ($null -eq $InputObject -or 
            $InputObject -is [string] -or 
            $InputObject -is [int] -or 
            $InputObject -is [long] -or 
            $InputObject -is [double] -or 
            $InputObject -is [bool] -or 
            $InputObject -is [datetime]) {
            return $InputObject
        }
    
        # Handle array input
        if ($InputObject -is [System.Array]) {
            # If this is a top-level array, process each item and return the combined results
            if ($Depth -eq 0) {
                $result = @()
                foreach ($item in $InputObject) {
                    $flattenedItems = ConvertTo-FlattenedObject -InputObject $item -ExcludeArrayProperties $ExcludeArrayProperties -Depth ($Depth + 1)
                    if ($flattenedItems -is [System.Array]) {
                        $result += $flattenedItems
                    }
                    else {
                        $result += @($flattenedItems)
                    }
                }
                return $result
            }
        
            # For nested arrays, process each item
            $processedArray = @()
            foreach ($item in $InputObject) {
                $processedArray += ConvertTo-FlattenedObject -InputObject $item -ExcludeArrayProperties $ExcludeArrayProperties -Depth ($Depth + 1)
            }
            return $processedArray
        }
    
        # Handle object input
        if ($InputObject -is [PSCustomObject] -or $InputObject -is [hashtable]) {
            # Convert hashtable to PSCustomObject for consistent handling
            if ($InputObject -is [hashtable]) {
                $newObj = [PSCustomObject]@{}
                foreach ($key in $InputObject.Keys) {
                    $newObj | Add-Member -MemberType NoteProperty -Name $key -Value $InputObject[$key]
                }
                $InputObject = $newObj
            }
        
            # First, recursively process all properties
            foreach ($property in $InputObject.PSObject.Properties) {
                $propName = $property.Name
                $propValue = $property.Value
            
                # Recursively process the property value
                $InputObject.$propName = ConvertTo-FlattenedObject -InputObject $propValue -ExcludeArrayProperties $ExcludeArrayProperties -Depth ($Depth + 1)
            }
        
            # Find all array properties to flatten
            $arrayProperties = @()
            foreach ($property in $InputObject.PSObject.Properties) {
                $propName = $property.Name
                $propValue = $property.Value
            
                # Skip excluded array properties
                if ($propValue -is [System.Array] -and -not ($ExcludeArrayProperties -contains $propName)) {
                    $arrayProperties += $propName
                }
            }
        
            # If no arrays to flatten, return the processed object
            if ($arrayProperties.Count -eq 0) {
                return $InputObject
            }
        
            # Start with just this object
            $result = @($InputObject)
        
            # Process each array property
            foreach ($arrayProp in $arrayProperties) {
                $newResult = @()
            
                foreach ($item in $result) {
                    $arrayValues = $item.$arrayProp
                
                    # Skip if not an array or empty
                    if (-not ($arrayValues -is [System.Array]) -or $arrayValues.Count -eq 0) {
                        $newResult += $item
                        continue
                    }
                
                    # Create a new object for each array value
                    foreach ($value in $arrayValues) {
                        $newItem = Copy-ObjectDeep -InputObject $item
                    
                        # Replace the array with the single value
                        $newItem | Add-Member -MemberType NoteProperty -Name $arrayProp -Value $value -Force
                    
                        $newResult += $newItem
                    }
                }
            
                $result = $newResult
            }
        
            return $result
        }
    
        # For any other type, return as is
        return $InputObject
    }
    catch {
        Write-LogMessage "Error converting input object to flattened object" -Level ERROR -Exception $_
        return $InputObject
    }
}

<#
.SYNOPSIS
Creates a deep copy of an object.

.DESCRIPTION
Creates a deep copy of an object, including all nested objects and arrays.

.PARAMETER InputObject
The object to copy.

.EXAMPLE
$deepCopy = Copy-ObjectDeep -InputObject $originalObject
# Returns a deep copy of the original object

.OUTPUTS
A deep copy of the input object
#>
function Copy-ObjectDeep {
    param (
        [Parameter(Mandatory = $true)]
        $InputObject
    )

    if ($null -eq $InputObject) { return $null }

    if ($InputObject -is [System.Array]) {
        $copy = @()
        foreach ($item in $InputObject) {
            $copy += (Copy-ObjectDeep -InputObject $item)
        }
        return $copy
    }
    elseif ($InputObject -is [PSCustomObject]) {
        $copy = [PSCustomObject]@{}
        foreach ($property in $InputObject.PSObject.Properties) {
            $copy | Add-Member -MemberType NoteProperty -Name $property.Name -Value (Copy-ObjectDeep -InputObject $property.Value)
        }
        return $copy
    }
    else {
        # For primitive types, return as is
        return $InputObject
    }
}





















<#
.SYNOPSIS
Flattens an array of objects by expanding array properties into multiple objects.

.DESCRIPTION
Takes an array of objects and expands any array properties within them,
creating multiple objects where each has a single value from the array properties.

.PARAMETER InputObject
The array of objects to flatten.

.EXAMPLE
$flattenedArray = ConvertTo-FlattenedObjectFromArrayRows -InputObject $complexArray
# Returns an expanded array with array properties flattened

.OUTPUTS
Array of PSCustomObjects with flattened array properties
#>
function ConvertTo-FlattenedObjectFromArrayRows {
    param (
        [Parameter(Mandatory = $true)]
        $InputObject
    )
    if ($InputObject -isnot [System.Array]) {
        try {
            $temp = @()
            $temp += $InputObject
            $InputObject = $temp
        }
        catch {
            Write-LogMessage "Error converting input object to array" -Level ERROR -Exception $_
            return $InputObject
        }
    }

    $flattenedResult = @()
    foreach ($item in $InputObject) {
        # Use a generic function to flatten arrays in the object
        $flattenedItems = ConvertTo-FlattenedObject -InputObject $item
        $flattenedResult += $flattenedItems
    }
    return $flattenedResult
}

<#
.SYNOPSIS
Flattens nested properties by moving them to the parent object with prefixes.

.DESCRIPTION
Takes an object with nested properties and moves them to the parent object,
prefixing the property names with the name of the containing property.
Handles multiple levels of nesting recursively.
Avoids redundant prefixes when the property name already contains the prefix.

.PARAMETER InputObject
The object containing nested properties to flatten.

.PARAMETER PrefixSeparator
The separator to use between the prefix and the property name. Default is "_".

.PARAMETER CurrentPrefix
Internal parameter used for recursion. Do not specify manually.

.EXAMPLE
$flattenedObject = ConvertTo-FlattenedHierarchy -InputObject $complexObject
# Returns an object with all nested properties moved to the parent level

.OUTPUTS
PSCustomObject with flattened hierarchy
#>
function ConvertTo-FlattenedHierarchy {
    param (
        [Parameter(Mandatory = $true)]
        [PSCustomObject]$InputObject,
    
        [Parameter(Mandatory = $false)]
        [string]$PrefixSeparator = "",
    
        [Parameter(Mandatory = $false)]
        [string]$CurrentPrefix = ""
    )

    try {
        # Create a new object to hold flattened properties
        $result = [PSCustomObject]@{}
    
        # Process all properties of the input object
        foreach ($prop in $InputObject.PSObject.Properties) {
            $propName = $prop.Name
            $propValue = $prop.Value
        
            # Determine the new property name with prefix
            # Check if the property name already contains the prefix to avoid redundancy
            $newPropName = if ($CurrentPrefix) {
                # Check if property name already starts with the prefix
                if ($propName.StartsWith($CurrentPrefix, [StringComparison]::OrdinalIgnoreCase)) {
                    $propName
                }
                else {
                    # Check if property name is a singular form of the prefix (e.g. Port vs Ports)
                    $singularPrefix = $CurrentPrefix -replace 's$', ''
                    if ($propName.StartsWith($singularPrefix, [StringComparison]::OrdinalIgnoreCase)) {
                        $propName
                    }
                    else {
                        "$CurrentPrefix$PrefixSeparator$propName"
                    }
                }
            }
            else {
                $propName
            }
        
            # Handle different types of property values
            if ($propValue -is [PSCustomObject]) {
                # Recursively flatten nested object and add its properties
                $nestedPrefix = $newPropName
                $nestedResult = ConvertTo-FlattenedHierarchy -InputObject $propValue -PrefixSeparator $PrefixSeparator -CurrentPrefix $nestedPrefix
            
                # Add all flattened properties from the nested object
                foreach ($nestedProp in $nestedResult.PSObject.Properties) {
                    $result | Add-Member -NotePropertyName $nestedProp.Name -NotePropertyValue $nestedProp.Value -Force
                }
            
                # Also keep the original property if it's a top-level one
                if (-not $CurrentPrefix) {
                    $result | Add-Member -NotePropertyName $propName -NotePropertyValue $propValue -Force
                }
            }
            elseif ($propValue -is [System.Array]) {
                # For arrays, keep them as is
                $result | Add-Member -NotePropertyName $newPropName -NotePropertyValue $propValue -Force
            }
            else {
                # For primitive values, add them with the prefixed name
                $result | Add-Member -NotePropertyName $newPropName -NotePropertyValue $propValue -Force
            }
        }
    
        return $result
    }
    catch {
        Write-LogMessage "Error flattening object hierarchy" -Level ERROR -Exception $_
        return $InputObject
    }
}




<#
.SYNOPSIS
Processes server configuration data to flatten both arrays and nested hierarchies.

.DESCRIPTION
Combines the functionality of ConvertTo-FlattenedObject and ConvertTo-FlattenedHierarchy
to process server configuration data, flattening arrays into multiple objects and
moving all nested properties up to the parent level.

.PARAMETER InputObject
The server configuration data to process.

.PARAMETER KeepOriginalProperties
If specified, keeps the original nested properties in addition to the flattened ones.

.EXAMPLE
$processedData = ConvertTo-FlattenedArrayRows -InputObject $serverConfig
# Returns processed server configuration data

.OUTPUTS
Array of PSCustomObjects with processed configuration
#>
function ConvertTo-FlattenedArrayRows {
    param (
        [Parameter(Mandatory = $true)]
        $InputObject,
    
        [Parameter(Mandatory = $false)]
        [switch]$KeepOriginalProperties
    )

    try {
        # First flatten arrays to create multiple objects
        $flattenedArrays = ConvertTo-FlattenedObjectFromArrayRows -InputObject $InputObject
    
        # Then flatten hierarchies in each resulting object
        $result = @()
        foreach ($item in $flattenedArrays) {
            $flattenedHierarchy = ConvertTo-FlattenedHierarchy -InputObject $item
        
            # If we don't want to keep original properties, remove them
            if (-not $KeepOriginalProperties) {
                # Find all properties that have flattened versions
                $propsToRemove = @()
                foreach ($prop in $flattenedHierarchy.PSObject.Properties) {
                    if ($prop.Value -is [PSCustomObject]) {
                        $propsToRemove += $prop.Name
                    }
                }
            
                # Remove the original nested properties
                foreach ($propName in $propsToRemove) {
                    $flattenedHierarchy.PSObject.Properties.Remove($propName)
                }
            }
        
            $result += $flattenedHierarchy
        }
    
        return $result
    }
    catch {
        Write-LogMessage "Error processing server configuration" -Level ERROR -Exception $_
        return $InputObject
    }
}


function Get-WordsFromString {
    param(
        [string]$InputString
    )

    # Handle empty input
    if ([string]::IsNullOrWhiteSpace($InputString)) {
        return @()
    }

    # Handle PascalCase and camelCase specially
    if ($InputString -match '^[A-Z][a-z0-9]+([A-Z][a-z0-9]+)*$' -or 
        $InputString -match '^[a-z][a-z0-9]+([A-Z][a-z0-9]+)+$') {
        # Add spaces between camelCase transitions (lowercase to uppercase)
        $withSpaces = [regex]::Replace($InputString, '([a-z0-9])([A-Z])', '$1 $2')
        # Add spaces between acronym and word (e.g., "XMLHttpRequest" -> "XML Http Request")
        $withSpaces = [regex]::Replace($withSpaces, '([A-Z])([A-Z][a-z])', '$1 $2')
        $result = $withSpaces -split '\s+' | Where-Object { $_ -ne "" }
    
        return $result
    }

    # If string is already snake_case
    if ($InputString -match '^[a-z0-9]+(_[a-z0-9]+)*$') {
        return $InputString -split '_' | Where-Object { $_ -ne "" }
    }

    # If string is already kebab-case
    elseif ($InputString -match '^[a-z0-9]+(-[a-z0-9]+)*$') {
        return $InputString -split '-' | Where-Object { $_ -ne "" }
    }

    # Handle strings with spaces
    elseif ($InputString -match '\s') {
        # Split by spaces first
        $parts = $InputString -split '\s+' | Where-Object { $_ -ne "" }
    
        # Then process each part for camelCase within words
        $words = @()
        foreach ($part in $parts) {
            # Skip empty parts
            if ([string]::IsNullOrWhiteSpace($part)) {
                continue
            }
        
            # Check if the part contains camelCase or PascalCase patterns
            if ($part -match '[a-z][A-Z]' -or $part -match '[A-Z]{2,}[a-z]') {
                # For camelCase or PascalCase parts
                $subParts = [regex]::Replace($part, '([a-z0-9])([A-Z])', '$1 $2')
                $subParts = [regex]::Replace($subParts, '([A-Z])([A-Z][a-z])', '$1 $2')
                $words += $subParts -split '\s+' | Where-Object { $_ -ne "" }
            }
            else {
                $words += $part
            }
        }
    
        # Make sure we have at least one word
        if ($words.Count -eq 0) {
            $words = @($InputString)
        }
    
        return $words
    }

    # For strings with special characters or other formats
    else {
        # First, handle all uppercase (e.g., "THIS_IS_ALL_CAPS")
        if ($InputString -ceq $InputString.ToUpper() -and $InputString -match '[_\-\s]') {
            $result = $InputString.ToLower() -split '[_\-\s]+' | Where-Object { $_ -ne "" }
        
            # Make sure we have at least one word
            if ($result.Count -eq 0) {
                $result = @($InputString.ToLower())
            }
        
            return $result
        }
    
        # Handle special single-word cases
        if (!($InputString -match '\s') && !($InputString -match '[_\-]')) {
            return @($InputString)
        }
    
        # Replace special chars with spaces
        $cleanString = $InputString -replace '[^\w\s]', ' '
        # Clean up multiple spaces
        $cleanString = $cleanString -replace '\s+', ' '
    
        # If the string is a single word or empty after cleaning, return appropriately
        if ([string]::IsNullOrWhiteSpace($cleanString)) {
            return @($InputString)
        }
        elseif (!$cleanString.Contains(" ")) {
            return @($cleanString)
        }
    
        $result = $cleanString -split ' ' | Where-Object { $_ -ne "" }
    
        # Make sure we have at least one word
        if ($result.Count -eq 0) {
            $result = @($InputString)
        }
    
        return $result
    }
}

Update-TypeData -TypeName System.String -MemberName ToCapitalize -MemberType ScriptMethod -Value {
    if ([string]::IsNullOrWhiteSpace($this)) { return $this }

    try {
        # Handle empty string
        if ($this.Length -eq 0) { return $this }
    
        # Handle single character
        if ($this.Length -eq 1) { return $this.ToUpper() }
    
        # Split into words - use our custom function
        $words = Get-WordsFromString -InputString $this
    
        # If no words were found, capitalize the original string
        if ($words.Count -eq 0) { 
            return $this.Substring(0, 1).ToUpper() + $this.Substring(1).ToLower()
        }
    
        # Capitalize first word, lowercase the rest
        $result = @()
        for ($i = 0; $i -lt $words.Count; $i++) {
            if ($i -eq 0) {
                # First word: capitalize first letter, lowercase rest
                if ($words[$i].Length -gt 0) {
                    $firstChar = $words[$i].Substring(0, 1).ToUpper()
                    $rest = ""
                    if ($words[$i].Length -gt 1) {
                        $rest = $words[$i].Substring(1).ToLower()
                    }
                    $result += $firstChar + $rest
                }
            }
            else {
                # Other words: all lowercase
                $result += $words[$i].ToLower()
            }
        }
    
        return [string]::Join(" ", $result)
    }
    catch {
        # Fallback for error cases
        if ($this.Length -gt 0) {
            $firstChar = $this.Substring(0, 1).ToUpper()
            $rest = ""
            if ($this.Length -gt 1) {
                $rest = $this.Substring(1).ToLower()
            }
            return $firstChar + $rest
        }
        return $this
    }
} -Force

Update-TypeData -TypeName System.String -MemberName ToTitleCase -MemberType ScriptMethod -Value {
    if ([string]::IsNullOrWhiteSpace($this)) { return $this }

    try {
        # Handle empty string
        if ($this.Length -eq 0) { return $this }
    
        # Handle single character
        if ($this.Length -eq 1) { return $this.ToUpper() }
    
        # Split into words - use our custom function
        $words = Get-WordsFromString -InputString $this
    
        # If no words were found, capitalize the original string
        if ($words.Count -eq 0) { 
            return $this.Substring(0, 1).ToUpper() + $this.Substring(1).ToLower()
        }
    
        # Capitalize each word
        $result = @()
        foreach ($word in $words) {
            if ($word.Length -gt 0) {
                $firstChar = $word.Substring(0, 1).ToUpper()
                $rest = ""
                if ($word.Length -gt 1) {
                    $rest = $word.Substring(1).ToLower()
                }
                $result += $firstChar + $rest
            }
        }
    
        return [string]::Join(" ", $result)
    }
    catch {
        # Fallback for error cases
        if ($this -match '\s') {
            # If it has spaces already, capitalize each word
            return (Get-Culture).TextInfo.ToTitleCase($this.ToLower())
        }
        elseif ($this.Length -gt 0) {
            $firstChar = $this.Substring(0, 1).ToUpper()
            $rest = ""
            if ($this.Length -gt 1) {
                $rest = $this.Substring(1).ToLower()
            }
            return $firstChar + $rest
        }
        return $this
    }
} -Force

Update-TypeData -TypeName System.String -MemberName ToCamelCase -MemberType ScriptMethod -Value {
    if ([string]::IsNullOrWhiteSpace($this)) { return $this }

    try {
        # Handle empty string
        if ($this.Length -eq 0) { return $this }
    
        # Handle single character
        if ($this.Length -eq 1) { return $this.ToLower() }
    
        # Check if already in camelCase format to prevent unnecessary processing
        if ($this -cmatch '^[a-z][a-zA-Z0-9]*$' -and $this -match '[A-Z]') {
            return $this
        }
    
        # Split into words - use our custom function
        $words = Get-WordsFromString -InputString $this
    
        # If no words were found, handle specially
        if ($words.Count -eq 0) { 
            return $this.ToLower()
        }
    
        # First word lowercase, others capitalized
        $result = $words[0].ToLower()
    
        for ($i = 1; $i -lt $words.Count; $i++) {
            if ($words[$i].Length -gt 0) {
                $firstChar = $words[$i].Substring(0, 1).ToUpper()
                $rest = ""
                if ($words[$i].Length -gt 1) {
                    $rest = $words[$i].Substring(1).ToLower()
                }
                $result += $firstChar + $rest
            }
        }
    
        # Ensure special case handling for empty result
        if ([string]::IsNullOrEmpty($result)) {
            return $this.ToLower()
        }
    
        return $result
    }
    catch {
        # Fallback for error cases
        if ($this.Length -gt 0) {
            $firstChar = $this.Substring(0, 1).ToLower()
            $rest = ""
            if ($this.Length -gt 1) {
                $rest = $this.Substring(1)
            }
            return $firstChar + $rest
        }
        return $this
    }
} -Force

Update-TypeData -TypeName System.String -MemberName ToPascalCase -MemberType ScriptMethod -Value {
    if ([string]::IsNullOrWhiteSpace($this)) { return $this }

    try {
        # Handle empty string
        if ($this.Length -eq 0) { return $this }
    
        # Handle single character
        if ($this.Length -eq 1) { return $this.ToUpper() }
    
        # Check if already in PascalCase format to prevent unnecessary processing
        if ($this -cmatch '^[A-Z][a-zA-Z0-9]*$' -and $this -match '[a-z]') {
            return $this
        }
    
        # Split into words - use our custom function
        $words = Get-WordsFromString -InputString $this
    
        # If no words were found, capitalize just the first letter
        if ($words.Count -eq 0) { 
            return $this.Substring(0, 1).ToUpper() + $this.Substring(1).ToLower()
        }
    
        # Capitalize each word
        $result = ""
        foreach ($word in $words) {
            if ($word.Length -gt 0) {
                $firstChar = $word.Substring(0, 1).ToUpper()
                $rest = ""
                if ($word.Length -gt 1) {
                    $rest = $word.Substring(1).ToLower()
                }
                $result += $firstChar + $rest
            }
        }
    
        # Ensure special case handling for empty result
        if ([string]::IsNullOrEmpty($result)) {
            return $this.Substring(0, 1).ToUpper() + $this.Substring(1).ToLower()
        }
    
        return $result
    }
    catch {
        # Fallback for error cases
        if ($this.Length -gt 0) {
            $firstChar = $this.Substring(0, 1).ToUpper()
            $rest = ""
            if ($this.Length -gt 1) {
                $rest = $this.Substring(1)
            }
            return $firstChar + $rest
        }
        return $this
    }
} -Force

function ConvertCamelOrPascalToSnakeCase {
    param([string]$InputString)

    if ([string]::IsNullOrWhiteSpace($InputString)) { return $InputString }

    # Special case for already snake_case strings
    if ($InputString -match '^[a-z0-9_]+$') {
        return $InputString
    }

    # Special case for ALL_CAPS strings
    if ($InputString -match '^[A-Z0-9_]+$') {
        return $InputString.ToLower()
    }

    # Handle spaced strings (like "XML HTTP API") by treating them specially
    if ($InputString -match '\s') {
        return $InputString.Replace(' ', '_').ToLower()
    }

    # Handle kebab-case strings
    if ($InputString -match '-') {
        return $InputString.Replace('-', '_').ToLower()
    }

    # Now we're left with camelCase or PascalCase

    # First, handle camelCase and PascalCase transitions (lowercase to uppercase)
    $result = [regex]::Replace($InputString, '([a-z0-9])([A-Z])', '$1_$2')

    # Then handle consecutive uppercase letters followed by lowercase (acronyms)
    $result = [regex]::Replace($result, '([A-Z])([A-Z][a-z])', '$1_$2')

    # Convert to lowercase and return
    return $result.ToLower()
}

function ConvertCamelOrPascalToKebabCase {
    param([string]$InputString)

    if ([string]::IsNullOrWhiteSpace($InputString)) { return $InputString }

    # Special case for already kebab-case strings
    if ($InputString -match '^[a-z0-9\-]+$') {
        return $InputString
    }

    # Special case for ALL-CAPS strings
    if ($InputString -match '^[A-Z0-9_\-]+$') {
        return $InputString.Replace('_', '-').ToLower()
    }

    # Handle spaced strings (like "XML HTTP API") by treating them specially
    if ($InputString -match '\s') {
        return $InputString.Replace(' ', '-').ToLower()
    }

    # Handle snake_case strings
    if ($InputString -match '_') {
        return $InputString.Replace('_', '-').ToLower()
    }

    # Now we're left with camelCase or PascalCase

    # First, handle camelCase and PascalCase transitions (lowercase to uppercase)
    $result = [regex]::Replace($InputString, '([a-z0-9])([A-Z])', '$1-$2')

    # Then handle consecutive uppercase letters followed by lowercase (acronyms)
    $result = [regex]::Replace($result, '([A-Z])([A-Z][a-z])', '$1-$2')

    # Convert to lowercase and return
    return $result.ToLower()
}

Update-TypeData -TypeName System.String -MemberName ToSnakeCase -MemberType ScriptMethod -Value {
    if ([string]::IsNullOrWhiteSpace($this)) { return $this }

    try {
        # Handle empty string
        if ($this.Length -eq 0) { return $this }
    
        # Handle single character
        if ($this.Length -eq 1) { return $this.ToLower() }
    
        # Check if already in snake_case format to prevent unnecessary processing
        if ($this -match '^[a-z0-9]+(_[a-z0-9]+)*$') {
            return $this
        }
    
        # Check if input is kebab-case and convert directly
        if ($this -match '^[a-z0-9]+(-[a-z0-9]+)*$') {
            return $this -replace '-', '_'
        }
    
        # Special handling for camelCase and PascalCase patterns
        if ($this -match '[a-z][A-Z]' -or ($this -cmatch '^[A-Z]' -and $this -match '[a-z]')) {
            return ConvertCamelOrPascalToSnakeCase -InputString $this
        }
    
        # Handle regular space-separated words
        if ($this -match '\s') {
            return ($this -replace '\s+', '_').ToLower()
        }
    
        # Last resort: convert any non-alphanumeric chars to underscores
        $result = $this.ToLower() -replace '[^a-z0-9]', '_' -replace '_+', '_' -replace '^_|_$', ''
        return $result
    }
    catch {
        # Fallback for error cases - simple conversion
        return $this.ToLower() -replace '[^a-z0-9]', '_' -replace '_+', '_' -replace '^_|_$', ''
    }
} -Force

Update-TypeData -TypeName System.String -MemberName ToKebabCase -MemberType ScriptMethod -Value {
    if ([string]::IsNullOrWhiteSpace($this)) { return $this }

    try {
        # Handle empty string
        if ($this.Length -eq 0) { return $this }
    
        # Handle single character
        if ($this.Length -eq 1) { return $this.ToLower() }
    
        # Check if already in kebab-case format to prevent unnecessary processing
        if ($this -match '^[a-z0-9]+(-[a-z0-9]+)*$') {
            return $this
        }
    
        # Check if input is snake_case and convert directly
        if ($this -match '^[a-z0-9]+(_[a-z0-9]+)*$') {
            return $this -replace '_', '-'
        }
    
        # Special handling for camelCase and PascalCase patterns
        if ($this -match '[a-z][A-Z]' -or ($this -cmatch '^[A-Z]' -and $this -match '[a-z]')) {
            return ConvertCamelOrPascalToKebabCase -InputString $this
        }
    
        # Handle regular space-separated words
        if ($this -match '\s') {
            return ($this -replace '\s+', '-').ToLower()
        }
    
        # Last resort: convert any non-alphanumeric chars to hyphens
        $result = $this.ToLower() -replace '[^a-z0-9]', '-' -replace '-+', '-' -replace '^-|-$', ''
        return $result
    }
    catch {
        # Fallback for error cases - simple conversion
        return $this.ToLower() -replace '[^a-z0-9]', '-' -replace '-+', '-' -replace '^-|-$', ''
    }
} -Force

# DO NOT remove the helper function - it's needed by the string conversion methods
# Remove-Item Function:\Get-WordsFromString -ErrorAction SilentlyContinue

function Get-ApplicationsJsonFilename {
    return $(Join-Path $global:RemoteCommonConfigFilesFolder "Applications.json")
}

function Get-DatabaseCurrentVersionsJsonFilename {
    return $(Join-Path $global:RemoteCommonConfigFilesFolder "DatabaseCurrentVersions.json")
}

function Get-DatabasesJsonFilename {
    return $(Join-Path $global:RemoteCommonConfigFilesFolder "Databases.json")
}
function Get-DatabasesV2JsonFilename {
    return $(Join-Path $global:RemoteCommonConfigFilesFolder "DatabasesV2.json")
}
function Get-ServerMonitorConfigJsonFilename {
    return $(Join-Path $global:RemoteCommonConfigFilesFolder "ServerMonitorConfig.json")
}

function Get-EnvironmentsJsonFilename {
    return Join-Path $(Get-ConfigFilesPath) "Environments.json"
}

function Get-GlobalSettingsJsonFilename {
    return $(Join-Path $global:RemoteCommonConfigFilesFolder "GlobalSettings.json")
}

function Get-ApplicationsJson {
    return [PSCustomObject[]] $(Get-Content $(Get-ApplicationsJsonFilename) | ConvertFrom-Json)
}

function Get-DatabaseCurrentVersionsJson {
    return [PSCustomObject[]] $(Get-Content $(Get-DatabaseCurrentVersionsJsonFilename) | ConvertFrom-Json)
}

function Get-DatabasesJson {
    return [PSCustomObject[]] $(Get-Content $(Get-DatabasesJsonFilename) | ConvertFrom-Json)
}

function Get-DatabasesV2Json {
    return [PSCustomObject[]] $(Get-Content $(Get-DatabasesV2JsonFilename) | ConvertFrom-Json)
}

function Get-EnvironmentsJson {
    return [PSCustomObject[]] $(Get-Content $(Get-EnvironmentsJsonFilename) | ConvertFrom-Json)
}

function Get-GlobalSettingsJson {
    return [PSCustomObject] $(Get-Content $(Get-GlobalSettingsJsonFilename) | ConvertFrom-Json)
}
function Get-OllamaTemplatesJsonFilename {
    return $(Join-Path $global:RemoteCommonConfigFilesFolder "Resources" "OllamaTemplates.json")
}

function Set-ApplicationsJson {
    param(
        [Parameter(Mandatory = $true)]
        $Content
    )
    $Content | ConvertTo-Json -Depth 100 | Set-Content $(Get-ApplicationsJsonFilename)
}

function Set-DatabaseCurrentVersionsJson {
    param(
        [Parameter(Mandatory = $true)]
        $Content
    )
    $Content | ConvertTo-Json -Depth 100 | Set-Content $(Get-DatabaseCurrentVersionsJsonFilename)
}

function Set-DatabasesJson {
    param(
        [Parameter(Mandatory = $true)]
        $Content
    )
    $Content | ConvertTo-Json -Depth 100 | Set-Content $(Get-DatabasesJsonFilename)
}

function Set-EnvironmentsJson {
    param(
        [Parameter(Mandatory = $true)]
        $Content
    )
    $Content | ConvertTo-Json -Depth 100 | Set-Content $(Get-EnvironmentsJsonFilename)
}

function Set-GlobalSettingsJson {
    param(
        [Parameter(Mandatory = $true)]
        $Content
    )
    $Content | ConvertTo-Json -Depth 100 | Set-Content $(Get-GlobalSettingsJsonFilename)
}

function Save-UsingPandoc {
    param(
        [Parameter(Mandatory = $true)]
        $InputFile,
        [Parameter(Mandatory = $true)]
        $OutputFile,
        [Parameter(Mandatory = $false)]
        [bool]$AutoOpen = $false
    )
    try {
        # Get the file extension from the output file
        $extension = [System.IO.Path]::GetExtension($OutputFile)
        if ($extension -eq ".docx") {
            $text = "Word"
            $convertTo = "--to=docx"
        }
        elseif ($extension -eq ".html") {
            $text = "HTML"
            $convertTo = "--to=html"
        }
        elseif ($extension -eq ".pdf") {
            $text = "PDF"
            $convertTo = "--to=pdf"
        }
        elseif ($extension -eq ".md") {
            $text = "Markdown" 
            $convertTo = "--to=markdown"
        }
        elseif ($extension -eq ".txt") {
            $text = "Text"
            $convertTo = "--to=txt"
        }
        elseif ($extension -eq ".csv") {
            $text = "CSV"
            $convertTo = "--to=csv"
        }
        elseif ($extension -eq ".json") {
            $text = "JSON"
            $convertTo = "--to=json"
        }
        elseif ($extension -eq ".xml") {
            $text = "XML"
            $convertTo = "--to=xml"
        }
        else {
            $convertTo = ""

        }
        $tempResultFile = Join-Path $env:TEMP "pandoc-result-$(Get-Random).txt"
        $command = "pandoc -s `"$InputFile`" -o `"$OutputFile`""
        $command += " $convertTo"
        $command += " 2>$tempResultFile"
        Write-LogMessage "Pandoc command: $command" -Level INFO
        Invoke-Expression $command
        $result = Get-Content $tempResultFile
    
        if ($null -ne $result) {    
            if ($result -match "permission denied") {
                # Kill any processes holding the output file
                $killed = $false
                $processes = Get-Process | Where-Object { $_.MainWindowTitle -match [regex]::Escape($text) }
                $processes | ConvertTo-Json -Depth 100 | Out-File (Join-Path $PSScriptRoot "debug.json")
                if ($processes.Count -gt 0) {
                    if ($($processes | ForEach-Object { $_.CommandLine }) -notmatch [regex]::Escape($OutputFile)) {
                        $response = Read-Host "The $text document appears to be in use. Would you like to close all open $text applications? (Y/N)"
                        if ($response -eq 'Y' -or $response -eq 'y') {
                            Write-LogMessage "User chose to close all open $text applications" -Level INFO
                        }
                        else {
                            Write-LogMessage "User chose not to close $text applications - aborting" -Level WARNING
                            return
                        }
                    }
                    else {
                        Write-LogMessage "The $text document appears to be in use by $text application. Automatically killing process." -Level INFO
                    }
                }
                else {
                    Write-LogMessage "No $text applications are open but file is still locked. Aborting." -Level ERROR
                    return
                }
                foreach ($process in $processes) {
                    try {
                        $process | Stop-Process -Force
                        $killed = $true
                    }
                    catch {
                        Write-LogMessage "Failed to kill process $($process.Name)" -Level ERROR -Exception $_
                        $killed = $false
                    }
                }
                if ($killed) {
                    Start-Sleep -Seconds 1
                    & pandoc -s $InputFile -o $OutputFile 2>$tempResultFile
                    $result = Get-Content $tempResultFile
                
                    if ($null -ne $result) {    
                        Write-LogMessage "$text document generated at: $OutputFile" -Level INFO
                    }
                }
                else {
                    Write-LogMessage "Failed to kill process $($process.Name)" -Level ERROR -Exception $_
                }
            }
            else {
                if ($result -match "ERROR") {
                    Write-LogMessage "$text generation failed: $result" -Level ERROR
                    return
                }
            }
        }

        if ($AutoOpen) {
            Start-Process "`"$OutputFile`""
        }

    }
    catch {
        Write-LogMessage "Failed to save $text using pandoc" -Level ERROR -Exception $_
    }
}

function Add-FolderForFileIfNotExists {
    <#
    .SYNOPSIS
        Creates the directory structure for a given file path if it doesn't exist
    
    .DESCRIPTION
        Takes a file path and ensures the parent directory exists, creating it if necessary.
        Provides robust error handling and optional folder path return.
    
    .PARAMETER FileName
        The full file path for which to create the parent directory
    
    .PARAMETER ReturnFolder
        If specified, returns the folder path that was created/verified
    
    .EXAMPLE
        Add-FolderForFileIfNotExists -FileName "C:\Logs\MyApp\app.log"
        # Creates C:\Logs\MyApp\ if it doesn't exist
    
    .EXAMPLE
        $logFolder = Add-FolderForFileIfNotExists -FileName "C:\Logs\MyApp\app.log" -ReturnFolder
        # Creates folder and returns "C:\Logs\MyApp"
    #>
    param(
        [Parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        [string]$FileName,
        [Parameter(Mandatory = $false)]
        [switch]$ReturnFolder = $false
    )
    
    $fileFolder = ""
    $fileFolder = Split-Path -Path $FileName -Parent
    $createdFolder = New-Item -ItemType Directory -Path $fileFolder -Force -ErrorAction SilentlyContinue    
    Write-LogMessage "Created folder: $createdFolder" -Level TRACE
    if (-not (Test-Path $fileFolder -PathType Container)) {
        Write-LogMessage "Folder could not be created: $fileFolder " -Level ERROR
        return
    }
    # Return folder path if requested
    if ($ReturnFolder) {
        return $fileFolder
    }
}   

function Remove-IllegalCharactersFromPath {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Path
    )
    $illegalChars = [System.IO.Path]::GetInvalidFileNameChars() + [System.IO.Path]::GetInvalidPathChars()
    $hasIllegalChars = $false
    foreach ($char in $illegalChars) {
        if ($Path.Contains($char)) {
            $hasIllegalChars = $true
            break
        }
    }
    if ($hasIllegalChars) {
        Write-LogMessage "Path contains illegal characters for windows and for unc paths: $Path. Replacing illegal characters with _" -Level WARN
        $illegalChars = $illegalChars | ForEach-Object { [char]$_ }        
        $Path = $Path.Replace($illegalChars, "_")
        Write-LogMessage "Path after replacing illegal characters: $Path" -Level WARN
    }
    return $Path
}
function Get-HtmlTemplate {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Title,
        [Parameter(Mandatory = $false)]
        [string]$AddStyleContent,
        [Parameter(Mandatory = $true)]
        [string]$Content
    )
    
    # Try to load shared template from Resources folder (shared with C# DedgeCommon)
    $sharedTemplatePath = "C:\opt\src\DedgeSrc\DedgeSystemTools\Folders\DedgeCommon\Configfiles\Resources\HtmlTemplate.html"
    
    if (Test-Path $sharedTemplatePath) {
        try {
            Write-LogMessage "Loading shared HTML template from: $sharedTemplatePath" -Level DEBUG
            $template = Get-Content $sharedTemplatePath -Raw -Encoding UTF8
            
            # Replace placeholders
            $template = $template.Replace("{{TITLE}}", $Title.Trim())
            $template = $template.Replace("{{CONTENT}}", $Content)
            $template = $template.Replace("{{ADDITIONAL_STYLE}}", $AddStyleContent)
            
            Write-LogMessage "Using shared HTML template (identical to C# DedgeCommon)" -Level DEBUG
            return $template
        }
        catch {
            Write-LogMessage "Failed to load shared template, using built-in template: $($_.Exception.Message)" -Level WARN
        }
    }
    else {
        Write-LogMessage "Shared template not found at $sharedTemplatePath, using built-in template" -Level DEBUG
    }
    
    # Fallback to built-in template
    return @"
<!DOCTYPE html>
<html>
<head>
<title>$($Title.Trim())</title>
<style>
    :root {
        --bg-primary: #f5f5f5;
        --bg-secondary: #ffffff;
        --text-primary: #333333;
        --text-secondary: #666666;
        --border-color: #dddddd;
        --accent-color: #4CAF50;
        --accent-hover: #45a049;
        --table-bg: #ffffff;
        --table-header-bg: #4CAF50;
        --table-row-even: #f9f9f9;
        --table-row-hover: #f5f5f5;
        --success-color: #4CAF50;
        --failure-color: #f44336;
        --shadow: 0 2px 4px rgba(0,0,0,0.1);
    }
    
    [data-theme="dark"] {
        --bg-primary: #1a1a1a;
        --bg-secondary: #2d2d2d;
        --text-primary: #e0e0e0;
        --text-secondary: #b0b0b0;
        --border-color: #404040;
        --accent-color: #4a9eff;
        --accent-hover: #66b3ff;
        --table-bg: #2d2d2d;
        --table-header-bg: #2d5a2d;
        --table-row-even: #3a3a3a;
        --table-row-hover: #4a4a4a;
        --success-color: #4CAF50;
        --failure-color: #f44336;
        --shadow: 0 2px 4px rgba(0,0,0,0.3);
    }
    
    body { 
        font-family: 'Segoe UI', Tahoma, Geneva, Verdana, sans-serif; 
        margin: 20px;
        background-color: var(--bg-primary);
        color: var(--text-primary);
        transition: background-color 0.3s ease, color 0.3s ease;
    }
    .container {
        background-color: var(--bg-secondary);
        border-radius: 8px;
        padding: 20px;
        box-shadow: var(--shadow);
        transition: background-color 0.3s ease, box-shadow 0.3s ease;
    }
    table { 
        border-collapse: collapse; 
        width: 100%; 
        margin-top: 20px;
        background-color: var(--table-bg);
        transition: background-color 0.3s ease;
    }
    th, td { 
        border: 1px solid var(--border-color); 
        padding: 12px 8px; 
        text-align: left; 
        color: var(--text-primary);
        transition: background-color 0.3s ease, color 0.3s ease, border-color 0.3s ease;
    }
    th { 
        background-color: var(--table-header-bg); 
        color: white;
        font-weight: bold;
    }
    tr:nth-child(even) { 
        background-color: var(--table-row-even); 
    }
    tr:hover {
        background-color: var(--table-row-hover);
    }
    h1 { 
        color: var(--text-primary);
        margin-bottom: 20px;
        transition: color 0.3s ease;
    }
    .timestamp { 
        color: var(--text-secondary); 
        font-style: italic; 
        margin-top: 20px;
        transition: color 0.3s ease;
    }
    .success { 
        color: var(--success-color); 
        font-weight: bold;
    }
    .failure { 
        color: var(--failure-color); 
        font-weight: bold;
    }
    a {
        color: var(--accent-color);
        text-decoration: none;
        transition: color 0.3s ease;
    }
    a:hover {
        color: var(--accent-hover);
        text-decoration: underline;
    }

    $(if (-not [string]::IsNullOrEmpty($AddStyleContent)) { $AddStyleContent })

</style>
</head>
<body>
<div class="container">
    <div style="display: grid; grid-template-columns: 1fr 1fr; gap: 20px; align-items: center; margin-bottom: 20px;">
        <div style="justify-self: start;">
            <h1 style="margin: 0;">$Title</h1>
        </div>
        <div style="justify-self: end;">
            <a href="$(Get-DevToolsWebPathUrl)" target="_blank">
                <img src="https://www.Dedge.no/Features/Shared/img/dedge-logo.svg" alt="FK Logo" style="height: 50px;">
            </a>
        </div>
    </div>
    $Content
    <p class="timestamp">Generated on $(Get-Date -Format "yyyy-MM-dd HH:mm:ss") from $($env:COMPUTERNAME) by $($env:USERNAME)</p>
</div>
</body>
</html>
"@
}
function Get-AdminInboxFilename {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Path,
        [Parameter(Mandatory = $false)]
        [string]$Suggestion = ""
    )
    $pathSplit = $Path.Split("\")

    # Handle folder structure 
    $determinedRelativePath = ""
    $fkAdminFolderStructureKeyWordsArray = @()
    $allDatabases = @()
    $allInstances = @()
    if (Test-IsDbServer) {
        $allDatabases = Get-DatabasesV2Json | ForEach-Object { $_.Database.ToUpper() } | Select-Object -Unique
        $allInstances = Get-DatabasesV2Json | Where-Object { $_.IsActive -eq $true -and $_.ServerName -eq $env:COMPUTERNAME } | Select-Object -ExpandProperty AccessPoints | Where-Object { $_.IsActive -eq $true } | Select-Object -ExpandProperty InstanceName | Select-Object -Unique | ForEach-Object { $_.ToUpper() }

        foreach ($element in $pathSplit) {
            foreach ($database in $allDatabases) {
                if ($element.ToUpper() -contains $database) {
                    if (-not $determinedRelativePath.StartsWith("DB2")) {
                        $determinedRelativePath += "DB2\"
                    }
                    $determinedRelativePath += $database + "\"
                    break
                }
            }    
            if (-not[string]::IsNullOrEmpty($determinedRelativePath)) {
                break
            }
        }
    }
    return $determinedRelativePath

}

function Save-HtmlOutput {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Title,
        [Parameter(Mandatory = $false)]
        [string]$AddStyleContent,
        [Parameter(Mandatory = $true)]
        [string]$Content,
        [Parameter(Mandatory = $true)]
        [string]$OutputFile,
        [Parameter(Mandatory = $false)]
        [bool]$AddToDevToolsWebPath = $false,
        [Parameter(Mandatory = $false)]
        [string]$DevToolsWebDirectory = "",        
        [Parameter(Mandatory = $false)]
        [bool]$AutoOpen = $false,
        [Parameter(Mandatory = $false)]
        [switch]$NoTitleAutoFormat 
    )

    $htmlTemplate = Get-HtmlTemplate -Title $Title -AddStyleContent $AddStyleContent -Content $Content
 

    Add-FolderForFileIfNotExists -FileName $OutputFile
    # Check if filename contains illegal characters for windows and for unc paths
    
    $illegalChars = [System.IO.Path]::GetInvalidFileNameChars() + [System.IO.Path]::GetInvalidPathChars()
    $hasIllegalChars = $false
    foreach ($char in $illegalChars) {  
        if ($OutputFile.Contains($char)) {
            $hasIllegalChars = $true
            break
        }
    }
    if ($hasIllegalChars) {
        Write-LogMessage "Output file contains illegal characters for windows and for unc paths: $OutputFile. Replacing illegal characters with _" -Level DEBUG
        $illegalChars = $illegalChars | ForEach-Object { [char]$_ }        
        $OutputFile = $OutputFile.Replace($illegalChars, "_")
        Write-LogMessage "Output file after replacing illegal characters: $OutputFile" -Level DEBUG
    }

    Write-LogMessage "Output file: $OutputFile" -Level DEBUG
    $fileFolder = Split-Path -Path $OutputFile -Parent
    Write-LogMessage "File folder: $fileFolder" -Level DEBUG
    if (-not (Test-Path $fileFolder -PathType Container)) {
        New-Item -ItemType Directory -Path $fileFolder -Force -ErrorAction SilentlyContinue | Out-Null
        if (-not (Test-Path $fileFolder -PathType Container)) {
            Write-LogMessage "File folder could not be created: $fileFolder. Skipping save..." -Level WARN
            return
        }      
    }

    $htmlTemplate | Out-File $OutputFile
    Write-LogMessage "Local HTML saved to path #1: $OutputFile" -Level INFO
    $AutoOpenFile = $OutputFile

    # try {
    #     $getFkAdminInboxFilename = Get-AdminInboxFilename -Path $OutputFile
    #     if ($getFkAdminInboxFilename) {
    #         $fkAdminInboxFolder = $(Join-Path $(Get-DevToolsWebPath) "Inbox")
    #         if (-not (Test-Path $fkAdminInboxFolder -PathType Container)) {
    #             New-Item -ItemType Directory -Path $fkAdminInboxFolder -Force -ErrorAction SilentlyContinue | Out-Null
    #         }
    #         $outputFileWebServerUncPath = $(Join-Path $fkAdminInboxFolder $getFkAdminInboxFilename.Name)
    #         try {
    #             $htmlTemplate | Out-File $outputFileWebServerUncPath
    #             Write-LogMessage "Remote HTML saved to FK Admin Inbox: $outputFileWebServerUncPath" -Level INFO
    #         }
    #         catch {
    #             Write-LogMessage "Failed to save remote HTML to FK Admin Inbox: $($outputFileWebServerUncPath): $($_.Exception.Message)" -Level WARN
    #         }
    #     }
    #     Write-LogMessage "Local HTML saved to URL: $OutputFile`nRemote HTML saved to FK Admin Inbox: $outputFileWebServerUncPath" -Level INFO
    # }
    # catch {
    #     Write-LogMessage "Failed to save HTML to UNC path: $($outputFileWebServerUncPath): $($_.Exception.Message)" -Level WARN
    # }
    


    if ($AddToDevToolsWebPath) {
        try {
            $outputFileWebServerUncFolderPath = $(Join-Path $(Get-DevToolsWebPath) $DevToolsWebDirectory).ToString()
            if (-not (Test-Path $outputFileWebServerUncFolderPath -PathType Container)) {
                New-Item -ItemType Directory -Path $outputFileWebServerUncFolderPath -Force -ErrorAction SilentlyContinue | Out-Null
            }
            if (-not (Test-Path $fileFolder -PathType Container)) {
                Write-LogMessage "File folder could not be created: $fileFolder. Skipping secondary save..." -Level WARN
                return 
            }
            $htmlPageUncPath = $(Join-Path $outputFileWebServerUncFolderPath $(if ($NoTitleAutoFormat) { $Title } else { $Title.ToTitleCase() })).ToString() + ".html"
            $htmlPagePath = $($(Get-DevToolsWebPathUrl) + "/" + $($DevToolsWebDirectory.TrimStart("\").TrimEnd("\")) + "/" + $(if ($NoTitleAutoFormat) { $Title } else { $Title.ToTitleCase() }) + ".html").Replace("\", "/").Replace(" ", "%20")
            $AutoOpenFile = $htmlPagePath
            if (-not [string]::IsNullOrEmpty($OutputFile) -and $OutputFile.ToLower() -ne $htmlPageUncPath.ToLower()) {
                try {
                    $htmlTemplate | Out-File $htmlPageUncPath
                    Write-LogMessage "Remote HTML saved to path #2: $htmlPageUncPath" -Level INFO
                }
                catch {
                    Write-LogMessage "Failed to save remote HTML to UNC path #2: $($htmlPageUncPath): $($_.Exception.Message)" -Level WARN
                }
            }
            Write-LogMessage "Local HTML saved to URL: $htmlPagePath`nRemote HTML saved to UNC path: $htmlPageUncPath" -Level INFO
        }
        catch {
            Write-LogMessage "Failed to save HTML to UNC path: $($htmlPageUncPath): $($_.Exception.Message)" -Level WARN
        }
    }

    if ($AutoOpen -and $AutoOpenFile) {
        Start-Process $AutoOpenFile
    }
    # Return the first non-null file path in order of priority:
    # 1. AutoOpenFile (HTML file opened in browser if AutoOpen is true)
    # 2. outputFileExcel (Excel file if generated) 
    # 3. outputFileWord (Word file if generated)
    # 4. outputFile (Original HTML file)
    return $AutoOpenFile ?? $outputFileExcel ?? $outputFileWord ?? $outputFile
}

function Get-AdInfoForCurrentUser {
    $adInfoPath = Get-AdInfoPath
    $content = Get-Content $adInfoPath
    $adInfo = $content | ConvertFrom-Json
    $adInfoForCurrentUser = $adInfo | Where-Object { $_.samaccountname -eq $env:USERNAME }
    return $adInfoForCurrentUser
}


function Get-ComputerNameList {
    param(
        [Parameter(Mandatory = $false)]
        [string[]]$ComputerNameList = @() 
    )
    if ($ComputerNameList -is [string]) {
        if ($ComputerNameList.Contains(',')) {
            $ComputerNameList = @($ComputerNameList.Split(','))
        }
        else {
            $ComputerNameList = @($ComputerNameList)
        }
    }
    if ($ComputerNameList.Count -eq 1 -and $ComputerNameList[0] -eq '*') {
        # Will return only servers if not workstation
        $ComputerNameList = @()
        $ComputerNameList += Get-ServerListForPlatform -Platform "Azure"
        $ComputerNameList += Get-WorkstationListForPlatform -Platform "Azure"
        $ComputerNameList = @($ComputerNameList | Where-Object { $_ -and ($_.ToLower().StartsWith("t-no1") -or $_.ToLower().StartsWith("p-no1")) })
    }
    elseif ($ComputerNameList.Count -eq 1 -and $ComputerNameList[0].Contains('*')) {
        $regexPattern = $ComputerNameList[0]

        $ComputerNameList = @()
        $ComputerNameList += Get-ServerListForPlatform -Platform "Azure"
        $ComputerNameList += Get-WorkstationListForPlatform -Platform "Azure"
        # Convert wildcard pattern to regex pattern
        # Example: "*-db" becomes ".*-db$"
    
        #check if already regex pattern
        if (-not ($regexPattern.Contains('.*') -and -not $regexPattern.StartsWith('^') -and -not $regexPattern.EndsWith('$'))) {
            $regexPattern = $regexPattern.Replace('*', '.*')
            if (-not $regexPattern.EndsWith('$')) {
                $regexPattern = "$regexPattern$"
            }
        }
        $ComputerNameListNew = @()
        Write-LogMessage "Finding computers matching regex pattern: $regexPattern" -Level INFO -ForegroundColor Yellow
        foreach ($computerName in $ComputerNameList) {
            if ($computerName -match $regexPattern) {
                $ComputerNameListNew += $computerName
                # Write-LogMessage "Found computer matching regex pattern: $computerName" -Level INFO -ForegroundColor White
            }
        }
        $ComputerNameList = $ComputerNameListNew
    }
    elseif ($ComputerNameList.Count -eq 1 -and $ComputerNameList[0] -eq "Workstation") {
        $ComputerNameList = Get-WorkstationList
    }
    # Remove empty elements from ComputerNameList
    $ComputerNameList = @($ComputerNameList | Where-Object { -not [string]::IsNullOrWhiteSpace($_) })
    # Remove local computer from list if present
    try {
        $ComputerNameList = @($ComputerNameList | Where-Object { $_.ToLower() -ne $env:COMPUTERNAME.ToLower() })
    }
    catch {
        $ComputerNameList = @()
    }
    return $ComputerNameList
}

function Get-ComputerInfo {
    param(
        [Parameter(Mandatory = $false)]
        [string]$ComputerName = $env:COMPUTERNAME
    )

    $computers = Get-ComputerInfoJson
    $computerInfo = $computers | Where-Object { $_.Name -eq $ComputerName }

    if ($computerInfo) {
        return $computerInfo
    }
    else {
        Write-LogMessage "No computer info found for computer: $ComputerName" -Level WARN
        return $null
    }
}

function Start-RoboCopyRemoteDeploy {
    param(
        [Parameter(Mandatory = $true)]
        [string]$SourceFolder,
        [Parameter(Mandatory = $false)]
        [string]$DestinationComputerName = $env:COMPUTERNAME,
        [Parameter(Mandatory = $false)]
        [string]$SubFolder = "",
        [Parameter(Mandatory = $false)]
        [switch]$Recurse,
        [Parameter(Mandatory = $false)]
        [switch]$QuietMode
    )
    if (-not $subFolder) {
        $subFolder = ""
    }
    $fromFolder = $SourceFolder + $subFolder
    $applicationTechnologyFolderName = Get-ApplicationTechnologyFolderName -FromFolder $fromFolder
    
    $currentFolder = Split-Path -Path $SourceFolder -Leaf
    $deployFolder = $("\\$DestinationComputerName\opt\$applicationTechnologyFolderName\$currentFolder" + $subFolder)
 
    Write-LogMessage "Getting robocopy path..." -Level TRACE
    $getCommandWorks = $false
    try {
        $robocopyPath = (Get-Command "RoboCopy" -ErrorAction SilentlyContinue).Path
        if (-not $robocopyPath.ToLower().Contains("robocopy.exe")) {
            throw "Robocopy not found in path"
        }
        $getCommandWorks = $true
    }
    catch {
        Write-Host "!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!"
        Write-Host "!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!"
        Write-Host "Robocopy not found in path, using C:\Windows\System32\robocopy.exe" -ForegroundColor Red
        Write-Host "!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!"
        Write-Host "!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!"
        Test-System32Path
        $robocopyPath = "C:\Windows\System32\robocopy.exe"
        $getCommandWorks = $false
    }

    # Find the longest length between fromFolder and deployFolder for formatting
    $maxPathLength = [Math]::Max($fromFolder.Length, $deployFolder.Length)
    # /MIR - Mirror directory tree (equivalent to /E plus /PURGE) - copies subdirectories and removes files that no longer exist in source
    # /R:3 - Number of retries on failed copies (default is 1 million, setting to 3 for faster failure)
    # /W:1 - Wait time between retries in seconds (default is 30 seconds, setting to 1 for faster execution)
    $lineLength = $maxPathLength + 32
    $title = " ROBOCOPY REMOTE DEPLOY "
    $lpadding = ($lineLength - $title.Length) / 2
    if (($lineLength - $title.Length) % 2 -eq 1) {
        $rpadding = $lpadding + 1
    }
    else {
        $rpadding = $lpadding
    }
    if (-not $QuietMode) {
        # Write-Host ("-" * $lineLength) -ForegroundColor Cyan
        Write-Host ("=" * $lpadding )$title("=" * $rpadding) -ForegroundColor Cyan
        # Write-Host ("-" * $lineLength) -ForegroundColor Cyan
        Write-Host "Initiating Robocopy deployment..." -ForegroundColor Cyan
        Write-Host " - AppType                    : $applicationTechnologyFolderName" -ForegroundColor White
        Write-Host " - AppName/Folder             : $currentFolder" -ForegroundColor White
        Write-Host " - Source                     : $fromFolder" -ForegroundColor White
        Write-Host " - Destination                : $deployFolder" -ForegroundColor White
        Write-Host " - Recurse                    : $Recurse" -ForegroundColor White
        Write-Host " - RobocopyPath               : $robocopyPath" -ForegroundColor White
        Write-Host " - GetCommandWorks            : $getCommandWorks" -ForegroundColor White
        # Write-Host ("-" * $lineLength) -ForegroundColor Cyan
        Write-Host 
    }
    $startTime = Get-Date

    if ($recurse) {
        $robocopyOutput = robocopy "$fromFolder" "$deployFolder" /PURGE /MIR /R:3 /W:1 /XF "_QuickDeploy*.ps1" "_deployAll.ps1" "_deploy.ps1" 2>&1
    }
    else {
        # /PURGE removes files in destination that don't exist in source
        # Without /E or /S, only files in root directory are copied
        $robocopyOutput = robocopy "$fromFolder" "$deployFolder" /PURGE /R:3 /W:1 /XF "_QuickDeploy*.ps1" "_deployAll.ps1" "_deploy.ps1" 2>&1
    }
    $robocopyExitCode = $LASTEXITCODE
    $endTime = Get-Date
    $elapsedTime = ($endTime - $startTime).TotalSeconds
    if (-not $QuietMode) {
        Write-Host "Results" -ForegroundColor Cyan
        Write-Host " - Processing time  : $elapsedTime seconds" -ForegroundColor White
    }
        
    # Parse robocopy output for statistics
    $totalFiles = 0
    $copiedFiles = 0
    $skippedFiles = 0
    $failedFiles = 0
    $extraFiles = 0
    $totalDirs = 0
    $copiedDirs = 0
        
    foreach ($line in $robocopyOutput) {
        if ($line -match "Files :\s+(\d+)\s+(\d+)\s+(\d+)\s+\d+\s+(\d+)\s+(\d+)") {
            $totalFiles = [int]$matches[1]
            $copiedFiles = [int]$matches[2]
            $skippedFiles = [int]$matches[3]
            $failedFiles = [int]$matches[4]
            $extraFiles = [int]$matches[5]
        }
        if ($line -match "Dirs :\s+(\d+)\s+(\d+)\s+(\d+)\s+(\d+)") {
            $totalDirs = [int]$matches[1]
            $copiedDirs = [int]$matches[2]
            $skippedDirs = [int]$matches[3]
            $extraDirs = [int]$matches[4]
        }
    }
    if (-not $QuietMode) {
 
        if ($recurse) {
            Write-Host " - Total directories          : $totalDirs" -ForegroundColor White
            Write-Host " - Copied/Updated directories : $copiedDirs" -ForegroundColor White
            Write-Host " - Unchanged directories      : $skippedDirs" -ForegroundColor White
            Write-Host " - Removed directories        : $extraDirs" -ForegroundColor White
            # Write-Host ("-" * $lineLength) -ForegroundColor Cyan
            Write-Host
        }
        Write-Host " - Total files                : $totalFiles" -ForegroundColor White
        Write-Host " - Copied/Updated files       : $copiedFiles" -ForegroundColor White
        Write-Host " - Unchanged files            : $skippedFiles" -ForegroundColor White
        Write-Host " - Failed files               : $failedFiles" -ForegroundColor White
        Write-Host " - Removed files              : $extraFiles" -ForegroundColor White
        # Write-Host ("-" * $lineLength) -ForegroundColor Cyan
        Write-Host
        Write-Host "Status" -ForegroundColor Cyan
    }
    if ($robocopyExitCode -eq 0) {
        $foregroundColor = "Green"
        if (-not $QuietMode) {
            Write-Host " - No files copied (all files up to date)" -ForegroundColor $foregroundColor
        }
    }
    elseif ($robocopyExitCode -eq 1) {
        $foregroundColor = "Green"
        if (-not $QuietMode) {
            Write-Host " - Files copied successfully" -ForegroundColor $foregroundColor
        }
    }
    elseif ($robocopyExitCode -eq 2) {
        $foregroundColor = "Yellow"
        if (-not $QuietMode) {
            Write-Host " - Extra files/directories detected and removed" -ForegroundColor $foregroundColor
        }
    }
    elseif ($robocopyExitCode -eq 3) {
        $foregroundColor = "Green"
        if (-not $QuietMode) {
            Write-Host " - Files copied and extra files removed" -ForegroundColor $foregroundColor
        }
    }
    elseif ($robocopyExitCode -ge 8) {
        $foregroundColor = "Red"
        if (-not $QuietMode) {
            Write-Host " - Errors occurred during copy operation (Exit code: $robocopyExitCode)" -ForegroundColor $foregroundColor
            Write-Host "Robocopy output" -ForegroundColor $foregroundColor
            $robocopyOutput | ForEach-Object { Write-Host $_ -ForegroundColor $foregroundColor }
        }
    }
    else {
        $foregroundColor = "Yellow"
        if (-not $QuietMode) {
            Write-Host " - Operation completed with exit code $robocopyExitCode" -ForegroundColor $foregroundColor
        }
    }
    if ($foregroundColor -eq "Green") {
        $level = "INFO"
    }
    elseif ($foregroundColor -eq "Yellow") {
        $level = "WARN"
    }
    elseif ($foregroundColor -eq "Red") {
        $level = "ERROR"
    }
    Write-LogMessage "Robocopy Result: Directories: $totalDirs total, $copiedDirs copied/updated, $skippedDirs unchanged, $extraDirs removed" -Level $level
    Write-LogMessage "Robocopy Result: Files: $totalFiles total, $copiedFiles copied/updated, $skippedFiles unchanged, $failedFiles failed, $extraFiles removed" -Level $level
    if (-not $QuietMode) {
        Write-Host ("=" * $lineLength) -ForegroundColor Cyan
    }
    
}

<#
.SYNOPSIS
Displays robocopy operation results and statistics in a formatted output.

.DESCRIPTION
Processes robocopy output and exit codes to display comprehensive statistics about the copy operation,
including file and directory counts, operation status, and appropriate color-coded messages.
Logs the results using Write-LogMessage for audit purposes.

.PARAMETER SourceFolder
The source folder path for the robocopy operation.

.PARAMETER DestinationFolder
The destination folder path for the robocopy operation.

.PARAMETER Recurse
Switch parameter indicating if the operation was recursive (affects display of directory statistics).

.PARAMETER QuietMode
Switch parameter to suppress console output while still logging results.

.PARAMETER Exclude
Array of strings specifying file/folder patterns to exclude from the operation.

.PARAMETER Include
Array of strings specifying file/folder patterns to include in the operation.

.PARAMETER ApplicationTechnologyFolderName
Optional parameter specifying the application technology folder name for the operation.

.EXAMPLE
Show-RobocopyResults -SourceFolder "C:\Source" -DestinationFolder "C:\Dest" -Recurse -QuietMode:$false

.EXAMPLE
Show-RobocopyResults -SourceFolder "C:\Source" -DestinationFolder "C:\Dest" -Exclude @("*.tmp", "*.log") -Include @("*.ps1")

.NOTES
Exit codes interpretation:
- 0: No files copied (all up to date)
- 1: Files copied successfully
- 2: Extra files/directories detected and removed
- 3: Files copied and extra files removed
- 8+: Errors occurred during operation


    # Robocopy Parameters Reference:
    # 
    # COPY OPTIONS:
    # /S           - Copy subdirectories (excluding empty ones)
    # /E           - Copy subdirectories (including empty ones)
    # /LEV:n       - Copy only the top n levels of the source directory tree
    # /Z           - Copy files in restartable mode
    # /B           - Copy files in backup mode
    # /ZB          - Use restartable mode; if access denied use backup mode
    # /J           - Copy using unbuffered I/O (recommended for large files)
    # /EFSRAW      - Copy all encrypted files in EFS RAW mode
    # /COPY:flags  - What to copy for files (default is /COPY:DAT)
    #                D=Data, A=Attributes, T=Timestamps, S=Security=NTFS ACLs, O=Owner info, U=aUditing info
    # /SEC         - Copy files with security (equivalent to /COPY:DATS)
    # /COPYALL     - Copy all file info (equivalent to /COPY:DATSOU)
    # /NOCOPY      - Copy no file info (useful with /PURGE)
    # /SECFIX      - Fix file security on all files, even skipped files
    # /TIMFIX      - Fix file times on all files, even skipped files
    #
    # FILE SELECTION OPTIONS:
    # /A           - Copy only files with the Archive attribute set
    # /M           - Copy only files with the Archive attribute and reset it
    # /IA:attrs    - Include only files with any of the given attributes set
    # /XA:attrs    - Exclude files with any of the given attributes set
    # /XF file     - Exclude files matching given names/paths/wildcards
    # /XD dirs     - Exclude directories matching given names/paths
    # /XC          - Exclude changed files
    # /XN          - Exclude newer files
    # /XO          - Exclude older files
    # /XX          - Exclude extra files and directories
    # /XL          - Exclude lonely files and directories
    # /IS          - Include same files
    # /IT          - Include tweaked files
    # /MAX:n       - Maximum file size - exclude files bigger than n bytes
    # /MIN:n       - Minimum file size - exclude files smaller than n bytes
    # /MAXAGE:n    - Maximum file age - exclude files older than n days/date
    # /MINAGE:n    - Minimum file age - exclude files newer than n days/date
    # /MAXLAD:n    - Maximum last access date - exclude files unused since n
    # /MINLAD:n    - Minimum last access date - exclude files used since n
    #
    # RETRY OPTIONS:
    # /R:n         - Number of retries on failed copies (default 1 million)
    # /W:n         - Wait time between retries (default 30 seconds)
    # /REG         - Save /R:n and /W:n in the Registry as default settings
    # /TBD         - Wait for sharenames To Be Defined (retry error 67)
    #
    # LOGGING OPTIONS:
    # /L           - List only - don't copy, timestamp or delete any files
    # /X           - Report all extra files, not just those selected
    # /V           - Produce verbose output, showing skipped files
    # /TS          - Include source file time stamps in the output
    # /FP          - Include full pathname of files in the output
    # /BYTES       - Print sizes as bytes
    # /NS          - No size - don't log file sizes
    # /NC          - No class - don't log file classes
    # /NFL         - No file list - don't log file names
    # /NDL         - No directory list - don't log directory names
    # /NP          - No progress - don't display percentage copied
    # /ETA         - Show estimated time of arrival of copied files
    #
    # JOB OPTIONS:
    # /JOB:jobname - Take parameters from the named job file
    # /SAVE:jobname- Save parameters to the named job file
    # /QUIT        - Quit after processing command line (to view parameters)
    # /NOSD        - No source directory is specified
    # /NODD        - No destination directory is specified
    # /IF          - Include the following files
    #
    # MIRROR/PURGE OPTIONS:
    # /MIR         - Mirror a directory tree (equivalent to /E plus /PURGE)
    # /PURGE       - Delete dest files/dirs that no longer exist in source
    # /MIR         - Mirror directory tree (equivalent to /E plus /PURGE)
    #
    # Note: To include specific file types, you can use wildcards in the source path
    # or use /IF parameter followed by file patterns. However, /IF is not commonly used.
    # Instead, you can specify file patterns directly in the source path or use
    # PowerShell filtering before calling robocopy.
    #
    # Example for PowerShell files only:
    # robocopy $fromFolder $deployFolder *.ps1 *.psm1 /PURGE /MIR /R:3 /W:1
    # This will copy only .ps1 and .psm1 files from source to destination
    #
    # For include file suffixes, consider filtering files in PowerShell first:
    # $includeExtensions = @("*.ps1", "*.psm1", "*.txt")
    # Then copy only those files, or use multiple robocopy calls with specific patterns
    # ROBOCOPY EXIT CODES:
    # 0  - No files were copied. No failure was encountered. No files were mismatched.
    # 1  - One or more files were copied successfully (that is, new files have arrived).
    # 2  - Some Extra files or directories were detected. No files were mismatched.
    # 3  - Some files were copied. Additional files were present. No failure was encountered.
    # 4  - Some Mismatched files or directories were detected. Examine the output log for details.
    # 5  - Some files were copied. Some files were mismatched. No failure was encountered.
    # 6  - Additional files and mismatched files exist. No files were copied and no failures were encountered.
    # 7  - Files were copied, a file mismatch was present, and additional files were present.
    # 8  - Several files did not copy (copy errors occurred and the retry limit was exceeded).
    # 16 - Serious error. Robocopy did not copy any files. Either a usage error or an error due to insufficient access privileges on the source or destination directories.
    #
    # Exit codes are bit flags that can be combined:
    # Bit 0 (1)  - One or more files were copied successfully
    # Bit 1 (2)  - Extra files or directories were detected
    # Bit 2 (4)  - Mismatched files or directories were detected
    # Bit 3 (8)  - Copy errors occurred and retry limit was exceeded
    # Bit 4 (16) - Serious error occurred
    #
    # Exit codes 0-7 are considered successful operations
    # Exit codes 8 and above indicate errors or failures

#>




function Start-RoboCopy {
    param(
        [Parameter(Mandatory = $true)]
        [string]$SourceFolder,
        [Parameter(Mandatory = $false)]
        [string]$DestinationFolder,
        [Parameter(Mandatory = $false)]
        [switch]$Recurse,
        [Parameter(Mandatory = $false)]
        [switch]$QuietMode,
        [Parameter(Mandatory = $false)]
        [string[]]$Exclude = @(),
        [Parameter(Mandatory = $false)]
        [string[]]$Include = @(),
        [Parameter(Mandatory = $false)]
        [switch]$NoPurge,
        [Parameter(Mandatory = $false)]
        [string]$ApplicationTechnologyFolderName,
        [Parameter(Mandatory = $false)]
        [switch]$ForcePush
    )

    $SourceFolder = $SourceFolder.TrimEnd("\")
    $DestinationFolder = $DestinationFolder.TrimEnd("\")
    $fromFolder = $SourceFolder
    $deployFolder = $DestinationFolder

    # Note: Paths with spaces are handled by escaped quotes in the robocopy command string
    # PowerShell cmdlets (Test-Path, New-Item) handle spaces automatically without quotes

    $currentFolder = Split-Path -Path $SourceFolder -Leaf
 
    if (Test-Path $deployFolder -PathType Leaf) {
        Remove-Item -Path $deployFolder -Force -ErrorAction SilentlyContinue | Out-Null
    }

    if (-not (Test-Path $deployFolder -PathType Container)) {
        New-Item -Path $deployFolder -ItemType Directory -Force -ErrorAction SilentlyContinue | Out-Null
    }


    # Find the longest length between fromFolder and deployFolder for formatting
    $maxPathLength = [Math]::Max($fromFolder.Length, $deployFolder.Length)
    # /MIR - Mirror directory tree (equivalent to /E plus /PURGE) - copies subdirectories and removes files that no longer exist in source
    # /R:3 - Number of retries on failed copies (default is 1 million, setting to 3 for faster failure)
    # /W:1 - Wait time between retries in seconds (default is 30 seconds, setting to 1 for faster execution)
    $lineLength = $maxPathLength + 32
    $title = " FKA ROBOCOPY DEPLOYMENT "
    $lpadding = ($lineLength - $title.Length) / 2
    if (($lineLength - $title.Length) % 2 -eq 1) {
        $rpadding = $lpadding + 1
    }
    else {
        $rpadding = $lpadding
    }
    $getCommandWorks = $false
    try {
        $robocopyPath = Get-CommandPathWithFallback "RoboCopy" -ErrorAction SilentlyContinue

        if (-not $robocopyPath.ToLower().Contains("robocopy.exe")) {
            throw "Robocopy not found in path"
        }
        $getCommandWorks = $true
    }
    catch {
        Write-LogMessage "Robocopy not found in path, using C:\Windows\System32\robocopy.exe" -Level ERROR
        Test-System32Path
        $robocopyPath = "C:\Windows\System32\robocopy.exe"
    }

    if (-not $QuietMode) {
        Write-LogMessage "Initiating Robocopy deployment..." -Level INFO
        Write-Host ("=" * $lpadding )$title("=" * $rpadding) -ForegroundColor Cyan
        if ($ApplicationTechnologyFolderName) {
            Write-Host " - AppType                    : $ApplicationTechnologyFolderName" -ForegroundColor White
        }
        Write-Host " - AppName/Folder             : $currentFolder" -ForegroundColor White
        Write-Host " - SourceFolder               : $fromFolder" -ForegroundColor White
        Write-Host " - DestinationFolder          : $deployFolder" -ForegroundColor White
        Write-Host " - Recurse                    : $Recurse" -ForegroundColor White
        Write-Host " - RobocopyPath               : $robocopyPath" -ForegroundColor White
        Write-Host " - GetCommandWorks            : $getCommandWorks" -ForegroundColor White
        Write-Host 
    }
    $startTime = Get-Date

    $excludeString = ""
    $Exclude += "_QuickDeploy*.ps1"
    $Exclude += "_deployAll.ps1"
    $Exclude += "_deploy.ps1"
    $Exclude += "*.unsigned"
    $Exclude = $Exclude  | Sort-Object -Unique
    $excludeString = $($Exclude | ForEach-Object { "`"" + $_ + "`"" } | Join-String -Separator " ")
    $excludeString = "/XF " + $excludeString 


    if ($ApplicationTechnologyFolderName) {
        if ($ApplicationTechnologyFolderName -eq "FkPshApp") {
            if (-not $Include) {
                $Include = @()
            }
            $includeString = ""
            $Include += "*.ps1"
            $Include += "*.psm1"
            $Include += "*.psd1"
            $Include += "*.ps1xml"
            $Include += "*.md"

        }
        elseif ($ApplicationTechnologyFolderName -eq "FkNodeJsApps") {
            if (-not $Include) {
                $Include = @()
            }
            $includeString = ""
            $Include += "*.*"
        }
        elseif ($ApplicationTechnologyFolderName -eq "FkPythonApps") {
            if (-not $Include) {
                $Include = @()
            }
            $includeString = ""
            $Include += "*.*"
        }
        elseif ($ApplicationTechnologyFolderName -eq "DedgeWinApps") {
            if (-not $Include) {
                $Include = @()
            }
            $includeString = ""
            $Include += "*.*"
        }
        if ($Include) {
            if ($Include.Count -gt 0) {
                $Include = $Include  | Sort-Object -Unique  
                $includeString = $($Include | ForEach-Object { "`"" + $_ + "`"" } | Join-String -Separator " ")
                $includeString = "/IF " + $includeString 
            }
        }
    }



    # /PURGE deletes destination files/folders that no longer exist in source
    if (-not $NoPurge) {
        $command = "$robocopyPath `"$fromFolder`" `"$deployFolder`" /PURGE"
    }
    else {
        $command = "$robocopyPath `"$fromFolder`" `"$deployFolder`""
    }
    Write-LogMessage "Robocopy Command: $command" -Level DEBUG

    if ($Recurse) {
        if ($NoPurge) {
            $command += " /E /R:3 /W:1"
        }
        else {
            $command += " /MIR /R:3 /W:1"
        }
    }
    else {
        $command += " /R:3 /W:1"
    }

    if ($excludeString) {
        $command += " $excludeString"
    }

    if ($includeString) {
        $command += " $includeString"
    }
    $command += " /TS /V /BYTES /FP"

    if ($ForcePush) {
        $command += " /IS /IT"
    }

    if (-not $QuietMode) {
        Write-Host $command
    }

    if (-not $QuietMode) {
        Write-LogMessage "Robocopy Command: $command" -Level TRACE
        Write-LogMessage "Starting Robocopy operation to folder: $deployFolder" -Level INFO 
    }
    
    # Execute robocopy with same privileges as current session
    $robocopyOutput = Invoke-Expression $command
    $robocopyExitCode = $LASTEXITCODE
    $endTime = Get-Date
    $elapsedTime = ($endTime - $startTime).TotalSeconds
    if (-not $QuietMode) {
        Write-Host "Results" -ForegroundColor Cyan
        Write-Host " - Processing time  : $elapsedTime seconds" -ForegroundColor White
    }


    # Write-LogMessage "Robocopy Output: $($robocopyOutput | Select-String -Pattern "Newer")" -Level INFO




    $transferredFilesInfo = @()
    foreach ($line in $robocopyOutput) {
        $line = $line.Trim()
        if ($line.StartsWith("Newer") -or $line.StartsWith("New File")) {
            try {
                # Robocopy output format with /FP /V /BYTES flags:
                # Status    Size(bytes)    DateTime    FullPath
                # Example: "Newer    123456    2024-12-10 12:34:56    C:\path\to\file with spaces.txt"
                
                $line = $line.Replace("Newer", "").Replace("New File", "").Trim()
                
                # Use regex to extract: Size (digits), DateTime (date time), and FullPath (everything after)
                # Regex explanation:
                # ^\s*                  - Start, optional whitespace
                # (\d+)                 - Capture group 1: file size (one or more digits)
                # \s+                   - One or more whitespace
                # (\d{4}-\d{2}-\d{2}\s+\d{2}:\d{2}:\d{2})  - Capture group 2: datetime (YYYY-MM-DD HH:MM:SS)
                # \s+                   - One or more whitespace
                # (.+)                  - Capture group 3: full file path (everything remaining)
                # $                     - End of string
                if ($line -match '^\s*(\d+)\s+(\d{4}-\d{2}-\d{2}\s+\d{2}:\d{2}:\d{2})\s+(.+)$') {
                    $fileSize = $matches[1]
                    $fileDateTime = $matches[2]
                    $sourceFilePath = $matches[3].Trim()
                    
                    # Calculate destination path
                    $destinationFilePath = $sourceFilePath.Replace($fromFolder, $deployFolder)
                    
                    # Get file info with error handling
                    $sourceFileInfo = $null
                    $destinationFileInfo = $null
                    
                    if (Test-Path -Path $sourceFilePath -PathType Leaf) {
                        $sourceFileInfo = Get-Item -Path $sourceFilePath -ErrorAction SilentlyContinue
                    }
                    else {
                        Write-LogMessage "Source file not found: $($sourceFilePath)" -Level WARN
                        continue
                    }
                    
                    if (Test-Path -Path $destinationFilePath -PathType Leaf) {
                        $destinationFileInfo = Get-Item -Path $destinationFilePath -ErrorAction SilentlyContinue
                    }
                    else {
                        Write-LogMessage "Destination file not found: $($destinationFilePath)" -Level WARN
                        continue
                    }
                    
                    # Only proceed if both files exist
                    if ($null -ne $sourceFileInfo -and $null -ne $destinationFileInfo) {
                        $objectToAdd = [PSCustomObject]@{
                            SourceFolder            = $sourceFileInfo.Directory.FullName
                            SourceFileSize          = $sourceFileInfo.Length
                            SourceFileDateTime      = $sourceFileInfo.LastWriteTime.ToString("yyyy-MM-dd HH:mm:ss.fff")
                            SourceFileName          = $sourceFileInfo.Name
                            DestinationFolder       = $destinationFileInfo.Directory.FullName
                            DestinationFileSize     = $destinationFileInfo.Length
                            DestinationFileDateTime = $destinationFileInfo.LastWriteTime.ToString("yyyy-MM-dd HH:mm:ss.fff")
                            DestinationFileName     = $destinationFileInfo.Name
                        }
                        
                        if ($sourceFileInfo.Length -ne $destinationFileInfo.Length -or $sourceFileInfo.LastWriteTime -ne $destinationFileInfo.LastWriteTime) {
                            Add-Member -InputObject $objectToAdd -MemberType NoteProperty -Name "Transferred" -Value $false
                        }
                        else {
                            Add-Member -InputObject $objectToAdd -MemberType NoteProperty -Name "Transferred" -Value $true
                        }
                        $transferredFilesInfo += $objectToAdd
                    }
                }
                else {
                    Write-LogMessage "Could not parse robocopy output line: $($line)" -Level DEBUG
                }
            }
            catch {
                Write-LogMessage "Error processing robocopy output line: $($line)" -Level WARN -Exception $_
                # Continue processing other lines
                continue
            }
        }
    }

    #Write-LogMessage "Transferred Files Info: $($transferredFilesInfo | ConvertTo-Json )" -Level INFO
    

    $addMessage = ""
    try {
        if ($robocopyExitCode -gt 8) {
            $addMessage = $($($robocopyOutput -Join "`n").Split("------------------------------------------------------------------------------")[-1]).Trim().Replace("`r", ". ")
            Write-LogMessage "Additional Message: $addMessage" -Level ERROR
        }
        # else {
        #     $addMessage = $($($robocopyOutput -Join "`n").Split("------------------------------------------------------------------------------")[-1]).Trim().Replace("`r", ". ")
        #     Write-LogMessage "Additional Message: $addMessage" -Level WARN
        # }
    }
    catch {
        $addMessage = ""
    }


    # Parse robocopy output for statistics
    $totalFiles = 0
    $copiedFiles = 0
    $skippedFiles = 0
    $failedFiles = 0
    $extraFiles = 0
    $totalDirs = 0
    $copiedDirs = 0
    $skippedDirs = 0
    $extraDirs = 0
        

    foreach ($line in $robocopyOutput) {
        if ($line -match "Files :\s+(\d+)\s+(\d+)\s+(\d+)\s+\d+\s+(\d+)\s+(\d+)") {
            $totalFiles = [int]$matches[1]
            $copiedFiles = [int]$matches[2]
            $skippedFiles = [int]$matches[3]
            $failedFiles = [int]$matches[4]
            $extraFiles = [int]$matches[5]
        }
        if ($line -match "Dirs :\s+(\d+)\s+(\d+)\s+(\d+)\s+(\d+)") {
            $totalDirs = [int]$matches[1]
            $copiedDirs = [int]$matches[2]
            $skippedDirs = [int]$matches[3]
            $extraDirs = [int]$matches[4]
        }
    }
    if (-not $QuietMode) {
 
        if ($recurse) {
            Write-Host " - Total directories          : $totalDirs" -ForegroundColor White
            Write-Host " - Copied/Updated directories : $copiedDirs" -ForegroundColor White
            Write-Host " - Unchanged directories      : $skippedDirs" -ForegroundColor White
            Write-Host " - Removed directories        : $extraDirs" -ForegroundColor White
            # Write-Host ("-" * $lineLength) -ForegroundColor Cyan
            Write-Host
        }
        Write-Host " - Total files                : $totalFiles" -ForegroundColor White
        Write-Host " - Copied/Updated files       : $copiedFiles" -ForegroundColor White
        Write-Host " - Unchanged files            : $skippedFiles" -ForegroundColor White
        Write-Host " - Failed files               : $failedFiles" -ForegroundColor White
        Write-Host " - Removed files              : $extraFiles" -ForegroundColor White
        # Write-Host ("-" * $lineLength) -ForegroundColor Cyan
        Write-Host
        Write-Host "Status" -ForegroundColor Cyan
    }
    $operationSuccessful = $false
    $message = ""
    if ($robocopyExitCode -eq 0) {
        $foregroundColor = "Green"
        $message = " - No files copied (all files up to date)"
        if (-not $QuietMode) {
            Write-Host $message -ForegroundColor $foregroundColor
        }
    }
    elseif ($robocopyExitCode -eq 1) {
        $foregroundColor = "Green"
        $message = " - Files copied successfully"
        if (-not $QuietMode) {
            Write-Host $message -ForegroundColor $foregroundColor
        }
    }
    elseif ($robocopyExitCode -eq 2) {
        $foregroundColor = "Yellow"
        $message = " - Extra files/directories detected and removed"
        if (-not $QuietMode) {
            Write-Host $message -ForegroundColor $foregroundColor
        }
    }
    elseif ($robocopyExitCode -eq 3) {
        $foregroundColor = "Green"
        $message = " - Files copied and extra files removed"
        if (-not $QuietMode) {
            Write-Host $message -ForegroundColor $foregroundColor
        }
    }
    elseif ($robocopyExitCode -ge 8) {
        $foregroundColor = "Red"
        $message = " - Errors occurred during copy operation (Exit code: $robocopyExitCode)"
        if (-not $QuietMode) {
            Write-Host $message -ForegroundColor $foregroundColor
            Write-Host "Robocopy output" -ForegroundColor $foregroundColor
            $robocopyOutput | ForEach-Object { Write-Host $_ -ForegroundColor $foregroundColor }
        }
    }
    else {
        $foregroundColor = "Yellow"
        $message = " - Operation completed with exit code $robocopyExitCode"
        if (-not $QuietMode) {
            Write-Host $message -ForegroundColor $foregroundColor
        }
    }
    if ($foregroundColor -eq "Green") {
        $level = "INFO"
        $operationSuccessful = $true
    }
    elseif ($foregroundColor -eq "Yellow") {
        $level = "WARN"
        $operationSuccessful = $true
    }
    elseif ($foregroundColor -eq "Red") {
        $level = "ERROR"
        $operationSuccessful = $false
    }
    # Alternative parameter names could be: -SuppressConsoleOutput, -QuietMode, -SilentLogging, -HideConsoleOutput, -DisableConsoleOutput
    Write-LogMessage "Robocopy Result: Directories: $totalDirs total, $copiedDirs copied/updated, $skippedDirs unchanged, $extraDirs removed" -Level $level -QuietMode:$QuietMode
    Write-LogMessage "Robocopy Result: Files: $totalFiles total, $copiedFiles copied/updated, $skippedFiles unchanged, $failedFiles failed, $extraFiles removed" -Level $level -QuietMode:$QuietMode
    if (-not $QuietMode) {
        Write-Host ("=" * $lineLength) -ForegroundColor Cyan
    }
    $resultObject = [PSCustomObject]@{
        OperationSuccessful = $operationSuccessful
        SourceFolder        = $SourceFolder
        DeployFolder        = $DeployFolder
        Recurse             = $Recurse
        Exclude             = $Exclude
        RobocopyOutput      = $robocopyOutput
        ErrorLevel          = $level
        RobocopyExitCode    = $robocopyExitCode
        ResultMessage       = $($message.TrimStart(" - "))
        ElapsedTime         = $elapsedTime
        Command             = $command
        AdditionalMessage   = $addMessage
        Output              = $robocopyOutput
        ChangedFiles        = $transferredFilesInfo
        Statistics          = [PSCustomObject]@{
            TotalDirs    = $totalDirs
            CopiedDirs   = $copiedDirs
            RemovedDirs  = $removedDirs
            ExtraDirs    = $extraDirs

            TotalFiles   = $totalFiles
            CopiedFiles  = $copiedFiles
            SkippedFiles = $skippedFiles
            FailedFiles  = $failedFiles
            ExtraFiles   = $extraFiles
        }
    }
    return $resultObject
}

<#
.SYNOPSIS
Gets the full path to an executable in the system PATH.

.DESCRIPTION
Retrieves the full path to a specified executable by using Get-Command.
Returns null if the executable is not found or not available in the system PATH.

.PARAMETER ExecutableName
The name of the executable to find (e.g., "winget", "git", "notepad").

.EXAMPLE
$wingetPath = Get-ExecutablePath -ExecutableName "winget"
if ($wingetPath) {
    Write-Host "Winget found at: $wingetPath"
} else {
    Write-Host "Winget not found"
}

.EXAMPLE
$gitPath = Get-ExecutablePath -ExecutableName "git"

.OUTPUTS
String containing the full path to the executable, or $null if not found
#>
function Get-ExecutablePath {
    param (
        [Parameter(Mandatory = $true)]
        [string]$ExecutableName
    )
    
    try {
        $executablePath = $(Get-Command $ExecutableName -ErrorAction SilentlyContinue).Path
        return $executablePath
    }
    catch {
        Write-LogMessage "Failed to get path for executable: $ExecutableName" -Level WARN -Exception $_
        return $null
    }
}





function Get-AvalibleAccessPointForDatabase {
    param (
        [Parameter(Mandatory = $false)]
        [string]$DatabaseName,
        [Parameter(Mandatory = $false)]
        [string]$ComputerName
    )
    if ([string]::IsNullOrEmpty($DatabaseName) ) {
        if ([string]::IsNullOrEmpty($ComputerName)) {
            $ComputerName = $env:COMPUTERNAME
        }
        if ($ComputerName.Length -ge 11) {
            $DatabaseName = $ComputerName.Substring(5, 6).ToUpper()
        }
        else {
            Write-LogMessage "It is not possible to determine the database name from the computer name" -Level WARN
            Write-Host "Unable to determine database name. Please choose an option:" -ForegroundColor Yellow
            Write-Host "1 - Use BASISPRO as database name" -ForegroundColor Green
            Write-Host "2 - Enter custom database name" -ForegroundColor Cyan
            Write-Host "3 - Quit" -ForegroundColor Yellow
            
            $userChoice = Read-Host "Enter your choice (1,2,3)"
            
            switch ($userChoice) {
                "1" {
                    $DatabaseName = "BASISPRO"
                    Write-LogMessage "User selected BASISPRO as database name" -Level INFO
                }
                "O" {
                    $DatabaseName = Read-Host "Enter database name"
                    if ([string]::IsNullOrEmpty($DatabaseName)) {
                        Write-LogMessage "No database name provided, exiting" -Level ERROR
                        throw "No database name provided"
                    }
                    Write-LogMessage "User provided custom database name: $DatabaseName" -Level INFO
                }
                "Q" {
                    Write-LogMessage "User chose to quit" -Level INFO
                    throw "User cancelled operation"
                }
                default {
                    Write-LogMessage "Invalid choice provided: $userChoice" -Level ERROR
                    throw "Invalid choice. Please select 1, 2, or 3"
                }
            }
        }
    }
    
    $allDatabases = Get-DatabasesV2Json
    $currAccessPoints = $allDatabases | Where-Object { $_.Database -eq $DatabaseName -and $_.Version -eq "2.0" } | Select-Object -ExpandProperty AccessPoints
    
    
    if ($currAccessPoints.Count -eq 0) {
        $currAccessPoint = Get-DatabasesV2Json | Where-Object { $_.Version -eq "2.0" } | Select-Object -ExpandProperty AccessPoints | Where-Object { $_.Name -eq $DatabaseName -and $_.AccessPointType -eq "Alias" }
    }
    elseif ($currAccessPoints.Count -gt 1) {
        $currAccessPoint = $currAccessPoints | Where-Object { $_.AccessPointType -eq "Alias" } | Select-Object -First 1
    }
    
    if (-not $currAccessPoint) {
        Write-Error "No access point found for $DatabaseName"
        throw "No access point found for $DatabaseName"
    }       
    return $currAccessPoint
}

















function Set-ApplicationTechnologyInfo {
    param (
        [Parameter(Mandatory = $true)]
        [string]$SourceFolder,
        [Parameter(Mandatory = $false)]
        [int]$PowerShellFiles = 0,
        [Parameter(Mandatory = $false)]
        [int]$NodeFiles = 0,
        [Parameter(Mandatory = $false)]
        [int]$PythonFiles = 0,
        [Parameter(Mandatory = $false)]
        [int]$RexxFiles = 0,
        [Parameter(Mandatory = $false)]
        [int]$ExeFiles = 0,
        [Parameter(Mandatory = $false)]
        [bool]$SkipModuleDeployment = $false,
        [Parameter(Mandatory = $false)]
        [bool]$SkipSign = $false
    )
    $appTech = "Unknown"
    $appFolder = "Unknown"
    $appName = $SourceFolder.Substring($SourceFolder.LastIndexOf('\') + 1)
    $executableExtensions = @()
    $allowedContentExtensions = @()
    $isDevTools = $false

    if (($SourceFolder.ToLower().Contains("DedgePsh") -or $SourceFolder.ToLower().Contains("DedgePshApps")) -and $PowerShellFiles -eq 0) {
        $PowerShellFiles += 1
    }   
    if (($SourceFolder.ToLower().Contains("Dedgenodejs") -or $SourceFolder.ToLower().Contains("fknodejsapps")) -and $NodeFiles -eq 0) {
        $NodeFiles += 1
    }
    if (($SourceFolder.ToLower().Contains("Dedgepython") -or $SourceFolder.ToLower().Contains("fkpythonapps")) -and $PythonFiles -eq 0) {
        $PythonFiles += 1
    }

    

    if ($NodeFiles -gt 0) {
        $appTech = "Node.js"
        $appFolder = Get-NodeDefaultAppsPath 
        $appFolder = $appFolder.Substring($appFolder.LastIndexOf('\') + 1)
    }
    elseif ($PythonFiles -gt 0) {
        $appTech = "Python"
        $appFolder = Get-PythonDefaultAppsPath 
        $appFolder = $appFolder.Substring($appFolder.LastIndexOf('\') + 1)
        $executableExtensions = @( "*.py", "*.pyw", "*.pyc", "*.pyo", "*.pyd")
        #$allowedContentExtensions = Get-AdditionalAllowedContentExtensions
        $allowedContentExtensions += @("*.*")

        

        $allowedContentExtensions += @("*.txt")
    }
    elseif ($PowerShellFiles -gt 0 -and $ExeFiles -eq 0) {
        $appTech = "PowerShell"
        $appFolder = Get-PowershellDefaultAppsPath 
        $appFolder = $appFolder.Substring($appFolder.LastIndexOf('\') + 1)
        if ($SourceFolder.ToLower().Contains("devtools") ) {
            $isDevTools = $true
        }
          
        if ($appName.ToLower().Contains("_modules")) {
            $appName = "CommonModules"
        }
            
        if ($appName -eq "CommonModules") {
            $allowedContentExtensions = @("*.md")
            $executableExtensions = @( "*.psm1")
        }
        elseif ($appName -eq "DedgeSign") {
            $allowedContentExtensions = @("*.md")
            $executableExtensions = @( "*.ps1", "*.psm1", "*.bat", "*.cmd")
        }
        else {
            $allowedContentExtensions = Get-AdditionalAllowedContentExtensions
            $executableExtensions = @( "*.ps1", "*.bat", "*.cmd")
        }

    }
    elseif ($ExeFiles -gt 0) {
        $appTech = "Windows"
        $appFolder = Get-WindowsDefaultAppsPath 
        $appFolder = $appFolder.Substring($appFolder.LastIndexOf('\') + 1)
        $executableExtensions = @( "*.exe", "*.com", "*.cmd", "*.bat", "*.dll", "*.msi", "*.sys", "*.ocx", "*.ax", "*.cpl", "*.drv", "*.efi", "*.mui", "*.scr", "*.tsp", "*.plugin", "*.xll", "*.wll", "*.jar", "*.war", "*.ear", "*.class", "*.xpi", "*.crx", "*.nex", "*.xbap", "*.application", "*.manifest", "*.appref-ms", "*.gadget", "*.widget", "*.ipa", "*.apk", "*.xap", "*.msix", "*.msixbundle", "*.appx", "*.appxbundle", "*.msp", "*.mst", "*.msu", "*.tlb")
        $allowedContentExtensions = Get-AdditionalAllowedContentExtensions
    }
  
    $allowedContentExtensions += @("*.version")
    $relativePath = $appFolder + "\" + $appName
  
   

    $currentDeployFileInfo = [PSCustomObject]@{
        Timestamp                = Get-Date
        AppName                  = $appName
        AppFolder                = $appFolder
        AppTechnology            = $appTech
        SourceFolder             = $SourceFolder
        RelativePath             = $relativePath
        PowerShellFiles          = $PowerShellFiles
        NodeFiles                = $NodeFiles
        PythonFiles              = $PythonFiles
        ExeFiles                 = $ExeFiles
        TotalFiles               = $PowerShellFiles + $NodeFiles + $PythonFiles + $ExeFiles
        SkipModuleDeployment     = $SkipModuleDeployment
        SkipSign                 = $SkipSign
        IsDevTools               = $isDevTools
        ExecutableExtensions     = $executableExtensions
        AllowedContentExtensions = $allowedContentExtensions
    }
    $global:PreviousDeployFileInfo = $currentDeployFileInfo
    $global:PreviouSourceFolder = $SourceFolder
    return $currentDeployFileInfo
}
  
function Get-SourceFolderFileInfo {
    param (
        [Parameter(Mandatory = $true)]
        [string]$SourceFolder
    )
    # if ($global:PreviouFromFolder -eq $FromFolder -and $global:PreviousDeployFileInfo) {
    #   if ($global:PreviousDeployFileInfo.Timestamp -gt (Get-Date).AddSeconds(-30)) {
    #     return $global:PreviousDeployFileInfo
    #   }
    # }
  
    $skipModuleDeployment = $false
    $skipSign = $false
    $powerShellFiles = $(Get-ChildItem -Path "$SourceFolder\*.ps1" -Exclude @("_deploy.ps1", "_install.ps1", "_uninstall.ps1", "_QuickDeploy*.ps1", "_old" ) -ErrorAction Stop -File).Count
    $powerShellFiles += $(Get-ChildItem -Path "$SourceFolder\*.psm1" -Exclude @("_deploy.ps1", "_install.ps1", "_uninstall.ps1", "_QuickDeploy*.ps1", "_old")  -ErrorAction Stop -File).Count
    if ($SourceFolder.ToLower().Contains("DedgePsh") -or $SourceFolder.ToLower().Contains("DedgePshApps")) {
        $powerShellBatFiles = $(Get-ChildItem -Path "$SourceFolder\*.bat" -Exclude @("_old") -File).Count
        if ($powerShellFiles -eq 0 -and $powerShellBatFiles -gt 0) {
            $skipModuleDeployment = $true
            $skipSign = $true
            return Set-ApplicationTechnologyInfo -SourceFolder $SourceFolder -PowerShellFiles $powerShellBatFiles -NodeFiles 0 -PythonFiles 0 -RexxFiles 0 -ExeFiles 0 -SkipModuleDeployment $skipModuleDeployment -SkipSign $skipSign
        }
        else {
            $powerShellFiles += $powerShellBatFiles
        }
    }
    elseif ($SourceFolder.ToLower().Contains("Dedgenodejs") -or $SourceFolder.ToLower().Contains("fknodejsapps")) {
        $nodeFiles = $(Get-ChildItem -Path "$SourceFolder\*.js" -Exclude @("_deploy.ps1", "_install.ps1", "_uninstall.ps1", "_QuickDeploy*.ps1", "_old") -File).Count
        $nodeFiles += $(Get-ChildItem -Path "$SourceFolder\*.mjs" -Exclude @("_deploy.ps1", "_install.ps1", "_uninstall.ps1", "_QuickDeploy*.ps1", "_old") -File).Count
    }
    elseif ($SourceFolder.ToLower().Contains("Dedgepython") -or $SourceFolder.ToLower().Contains("fkpythonapps")) {
        $pythonFiles = $(Get-ChildItem -Path "$SourceFolder\*.py" -Exclude @("_deploy.ps1", "_install.ps1", "_uninstall.ps1", "_QuickDeploy*.ps1", "_old") -File).Count
    }
    else {
        $pythonFiles = $(Get-ChildItem -Path "$SourceFolder\*.py*" -Exclude @("_deploy.ps1", "_install.ps1", "_uninstall.ps1", "_QuickDeploy*.ps1", "_old") -File).Count
        $exeFiles = $(Get-ChildItem -Path "$SourceFolder\*.exe" -File).Count
        $exeFiles += $(Get-ChildItem -Path "$SourceFolder\*.com" -File).Count 
        $exeFiles += $(Get-ChildItem -Path "$SourceFolder\*.cmd" -File).Count
        $exeFiles += $(Get-ChildItem -Path "$SourceFolder\*.dll" -File).Count
        if (-not $SourceFolder.ToLower().Contains("DedgePsh")) {
            $exeFiles += $(Get-ChildItem -Path "$SourceFolder\*.bat" -File).Count
        }
    }
  
    
    return Set-ApplicationTechnologyInfo -SourceFolder $SourceFolder -PowerShellFiles $powerShellFiles -NodeFiles $nodeFiles -PythonFiles $pythonFiles -RexxFiles $rexxFiles -ExeFiles $exeFiles -SkipModuleDeployment $skipModuleDeployment -SkipSign $skipSign
}
  
function Get-ApplicationTechnologyType {
    param (
        [Parameter(Mandatory = $true)]
        [string]$SourceFolder
    )
    $currentDeployFileInfo = Get-SourceFolderFileInfo -SourceFolder $SourceFolder
  
    return $currentDeployFileInfo.AppTechnology
}
  
function Get-ApplicationTechnologyFolderName {
    param (
        [Parameter(Mandatory = $true)]
        [string]$SourceFolder
    )
    $currentDeployFileInfo = Get-SourceFolderFileInfo -SourceFolder $SourceFolder
  
    return $currentDeployFileInfo.AppFolder
}

function Test-System32Path {    
    $env:Path += ";$env:SystemRoot\System32"
    $splitPath = $($env:Path.Split(";"))
    $testedPaths = @()
    $system32PathFound = $false
    foreach ($path in $splitPath) {
        $obj = [PSCustomObject]@{
            Path   = $path
            Exists = $(Test-Path $path)
        }
        $testedPaths += $obj
        if ($path.ToLower().EndsWith("system32") -eq $true) {
            $system32PathFound = $true
        }
 
    }
    if (-not $system32PathFound) {
        $obj = [PSCustomObject]@{
            Path   = "$env:SystemRoot\System32"
            Exists = $(Test-Path "$env:SystemRoot\System32")
        }
        $testedPaths += $obj
    }
    # if (-not $powershellPathFound) {
    #     $obj = [PSCustomObject]@{
    #         Path   = "$env:SystemRoot\System32\WindowsPowerShell\v1.0"
    #         Exists = $(Test-Path "$env:SystemRoot\System32\WindowsPowerShell\v1.0")
    #     }
    #     $testedPaths += $obj
        
    #     $obj = [PSCustomObject]@{
    #         Path   = "C:\Program Files\PowerShell\7\"
    #         Exists = $(Test-Path "C:\Program Files\PowerShell\7")
    #     }
    #     $testedPaths += $obj
    #     Write-LogMessage "Powershell path not found, adding to path" -Level WARN
    # }
    
    $testedPaths = $testedPaths | Sort-Object -Property Path, Exists -Unique
    $testedPaths | Format-Table -AutoSize -Property Path, Exists

    $testedPaths = $testedPaths | Where-Object { $_.Exists -eq $true }
    # $env:Path = $testedPaths -join ";"
    # $env:Path = $env:Path.TrimEnd(";")
}


# function Get-PrimaryDbNameFromInstanceName {
#     param(
#         [Parameter(Mandatory = $true)]
#         [string]$InstanceName
#     )
#     $jsonResult = Get-DatabasesV2Json | Where-Object { $_.ServerName.ToLower().Trim() -eq $env:COMPUTERNAME.ToLower().Trim() -and $_.IsActive -eq $true -and $_.Provider -eq "DB2" }
#     $catalogName = $jsonResult | Select-Object -ExpandProperty AccessPoints | Where-Object { $_.IsActive -eq $true -and $_.InstanceName -eq $InstanceName -and $_.AccessPointType -eq "PrimaryDb" } | Select-Object -First 1 | Select-Object -ExpandProperty CatalogName
#     if ([string]::IsNullOrEmpty($catalogName)) {
#         Write-LogMessage "Primary database name not found for instance name $InstanceName" -Level ERROR
#         throw "Primary database name not found for instance name $InstanceName"
#     }
#     return $catalogName
# }


# function Get-FederatedDbNameFromInstanceName {
#     param(
#         [Parameter(Mandatory = $true)]
#         [string]$InstanceName
#     )
#     $jsonResult = Get-DatabasesV2Json | Where-Object { $_.ServerName.ToLower().Trim() -eq $env:COMPUTERNAME.ToLower().Trim() -and $_.IsActive -eq $true -and $_.Provider -eq "DB2" }
#     $catalogName = $jsonResult | Select-Object -ExpandProperty AccessPoints | Where-Object { $_.IsActive -eq $true -and $_.InstanceName -eq $InstanceName -and $_.AccessPointType -eq "FederatedDb" } | Select-Object -First 1 | Select-Object -ExpandProperty CatalogName
#     if ([string]::IsNullOrEmpty($catalogName)) {
#         Write-LogMessage "Federated database name not found for instance name $InstanceName" -Level ERROR
#         throw "Federated database name not found for instance name $InstanceName"
#     }
#     return $catalogName
# }



function Get-ApplicationNameFromInstanceName {
    param(
        [Parameter(Mandatory = $true)]
        [string]$InstanceName
    )
    $jsonResult = Get-DatabasesV2Json | Where-Object { $_.ServerName.ToLower().Trim() -eq $env:COMPUTERNAME.ToLower().Trim() -and $_.IsActive -eq $true -and $_.Provider -eq "DB2" }
    foreach ($database in $jsonResult) {
        $accessPoints = $database.AccessPoints
        # Look for any access point with this instance name
        if ($accessPoints | Where-Object { $_.InstanceName -eq $InstanceName }) {
            # Now find the primary access point (AccessPointType -eq "PrimaryDb") among this array
            $primary = $accessPoints | Where-Object { $_.AccessPointType -eq "PrimaryDb" }
            if ($primary) {
                $application = $jsonResult | Where-Object { $_.Database -eq $primary.CatalogName } | Select-Object -ExpandProperty Application
                if (-not [string]::IsNullOrEmpty($application)) {
                    return $application
                }
            }
        }
    }
    Write-LogMessage "Application not found for instance name $InstanceName" -Level ERROR
    throw "Application not found for instance name $InstanceName"
}



function Get-EnvironmentNameFromInstanceName {
    param(
        [Parameter(Mandatory = $true)]
        [string]$InstanceName
    )
    $jsonResult = Get-DatabasesV2Json | Where-Object { $_.ServerName.ToLower().Trim() -eq $env:COMPUTERNAME.ToLower().Trim() -and $_.IsActive -eq $true -and $_.Provider -eq "DB2" }
    foreach ($database in $jsonResult) {
        $accessPoints = $database.AccessPoints
        # Look for any access point with this instance name
        if ($accessPoints | Where-Object { $_.InstanceName -eq $InstanceName }) {
            # Now find the primary access point (AccessPointType -eq "PrimaryDb") among this array
            $primary = $accessPoints | Where-Object { $_.AccessPointType -eq "PrimaryDb" }
            if ($primary) {
                $environment = $jsonResult | Where-Object { $_.Database -eq $primary.CatalogName } | Select-Object -ExpandProperty Environment
                if (-not [string]::IsNullOrEmpty($environment)) {
                    return $environment
                }
            }
        }
    }
    Write-LogMessage "Environment not found for instance name $InstanceName" -Level ERROR
    throw "Environment not found for instance name $InstanceName"
}

function Get-ApplicationNameFromInstanceName {
    param(
        [Parameter(Mandatory = $true)]
        [string]$InstanceName
    )
    $jsonResult = Get-DatabasesV2Json | Where-Object { $_.ServerName.ToLower().Trim() -eq $env:COMPUTERNAME.ToLower().Trim() -and $_.IsActive -eq $true -and $_.Provider -eq "DB2" }
    foreach ($database in $jsonResult) {
        $accessPoints = $database.AccessPoints
        # Look for any access point with this instance name
        if ($accessPoints | Where-Object { $_.InstanceName -eq $InstanceName }) {
            # Now find the primary access point (AccessPointType -eq "PrimaryDb") among this array
            $primary = $accessPoints | Where-Object { $_.AccessPointType -eq "PrimaryDb" }
            if ($primary) {
                $application = $jsonResult | Where-Object { $_.Database -eq $primary.CatalogName } | Select-Object -ExpandProperty Application
                if (-not [string]::IsNullOrEmpty($application)) {
                    return $application
                }
            }
        }
    }
    Write-LogMessage "Application not found for instance name $InstanceName" -Level ERROR
    throw "Application not found for instance name $InstanceName"
}



function Get-PrimaryDbNameFromInstanceName {
    param(
        [Parameter(Mandatory = $true)]
        [string]$InstanceName
    )
    if ($InstanceName.ToUpper().EndsWith("FED")) {
        $InstanceName = $InstanceName.Replace("FED", "").ToUpper()
    }
    $jsonResult = Get-DatabasesV2Json | Where-Object { $_.ServerName.ToLower().Trim() -eq $env:COMPUTERNAME.ToLower().Trim() -and $_.IsActive -eq $true -and $_.Provider -eq "DB2" }
    foreach ($database in $jsonResult) {
        $accessPoints = $database.AccessPoints
        # Look for any access point with this instance name
        if ($accessPoints | Where-Object { $_.InstanceName -eq $InstanceName }) {
            # Now find the primary access point (AccessPointType -eq "PrimaryDb") among this array
            $primary = $accessPoints | Where-Object { $_.AccessPointType -eq "PrimaryDb" }
            if ($primary) {
                return $primary.CatalogName
            }
        }
    }
    Write-LogMessage "Primary database name not found for instance name $InstanceName" -Level ERROR
    throw "Primary database name not found for instance name $InstanceName"
}

function Get-FederatedDbNameFromInstanceName {
    param(
        [Parameter(Mandatory = $true)]
        [string]$InstanceName
    )
    if (-not $InstanceName.ToUpper().EndsWith("FED")) {
        $InstanceName = $InstanceName.ToUpper() + "FED"
    }

    $jsonResult = Get-DatabasesV2Json | Where-Object { $_.ServerName.ToLower().Trim() -eq $env:COMPUTERNAME.ToLower().Trim() -and $_.IsActive -eq $true -and $_.Provider -eq "DB2" }
    foreach ($database in $jsonResult) {
        $accessPoints = $database.AccessPoints
        # Look for any access point with this instance name
        if ($accessPoints | Where-Object { $_.InstanceName -eq $InstanceName }) {
            # Now find the federated access point (AccessPointType -eq "FederatedDb") among this array
            $federated = $accessPoints | Where-Object { $_.AccessPointType -eq "FederatedDb" }
            if ($federated) {
                return $federated.CatalogName
            }
        }
    }
    # When UseNewConfigurations has removed federated DBs, callers expect no throw (return $null)
    Write-LogMessage "Federated database name not found for instance name $InstanceName (may be expected when UseNewConfigurations is true)" -Level WARN
    return $null
}

function Get-Db2InstanceNames {
    param(
        [Parameter(Mandatory = $false)]
        [switch]$IncludeFederated = $false
    )
    $instances = db2ilist | Out-String
    $instancesArray = $instances -split "`n" | ForEach-Object { $_.Trim() } | Where-Object { $_ -ne "" } 
    if (-not $IncludeFederated) {
        $instancesArray = $instancesArray | Where-Object { $_ -ne "" -and -not $_.Trim().ToUpper().EndsWith("FED") }
    }
    $instancesArray = $instancesArray | Sort-Object
    return $instancesArray
}

function Get-DatabaseTypeFromInstanceName {
    param(
        [Parameter(Mandatory = $true)]
        [string]$InstanceName
    )
    $jsonResult = Get-DatabasesV2Json | Where-Object { $_.ServerName.ToLower().Trim() -eq $env:COMPUTERNAME.ToLower().Trim() -and $_.IsActive -eq $true -and $_.Provider -eq "DB2" }
    foreach ($database in $jsonResult) {
        $accessPoints = $database.AccessPoints
        # Look for any access point with this instance name and is active and is either PrimaryDb or FederatedDb. Will only return one access point.
        $foundAccessPoint = $accessPoints | Where-Object { $_.InstanceName -eq $InstanceName -and $_.IsActive -eq $true -and $_.AccessPointType -in @("PrimaryDb", "FederatedDb") } | Select-Object -First 1
        if ($foundAccessPoint) {
            if ($foundAccessPoint.AccessPointType -eq "PrimaryDb") {
                return "PrimaryDb"
            }
            else {
                return "FederatedDb"
            }
        }
    }
    Write-LogMessage "Database type not found for instance name $InstanceName" -Level ERROR
    throw "Database type not found for instance name $InstanceName"
}

function Get-DatabaseNameFromInstanceName {
    param(
        [Parameter(Mandatory = $true)]
        [string]$InstanceName
    )
    $jsonResult = Get-DatabasesV2Json | Where-Object { $_.ServerName.ToLower().Trim() -eq $env:COMPUTERNAME.ToLower().Trim() -and $_.IsActive -eq $true -and $_.Provider -eq "DB2" }
    foreach ($database in $jsonResult) {
        $accessPoints = $database.AccessPoints
        # Look for any access point with this instance name and is active and is either PrimaryDb or FederatedDb. Will only return one access point.
        $foundAccessPoint = $accessPoints | Where-Object { $_.InstanceName -eq $InstanceName -and $_.IsActive -eq $true -and $_.AccessPointType -in @("PrimaryDb", "FederatedDb") } | Select-Object -First 1
        if ($foundAccessPoint) {
            return $foundAccessPoint.CatalogName
        }
    }
    Write-LogMessage "Database type not found for instance name $InstanceName" -Level ERROR
    throw "Database type not found for instance name $InstanceName"
}


function Get-DatabaseNameFromServerName {
    if (Test-IsServer) {
        if (-not $env:COMPUTERNAME.ToUpper().Contains("FKMFSP-APP") -and -not $env:COMPUTERNAME.ToUpper().Contains("INLPRD-APP")) {
            return $env:COMPUTERNAME.ToUpper().Substring(5, 6)
        }
        else {
            Write-LogMessage "Database name not found for server $env:COMPUTERNAME because it is a FSP App server. Run this script on the database server to get the database name." -Level WARN
            return $null
        }
    }
    else {
        return $null
    }
}

function Get-FederatedDatabaseNameFromServerName {
    if (Test-IsServer) {
        if ($env:COMPUTERNAME.ToUpper().Contains("FKMFSP-APP") -or $env:COMPUTERNAME.ToUpper().Contains("INLPRD-APP")) {
            Write-LogMessage "Federated database name not found for server $env:COMPUTERNAME because it is a FSP App server. Run this script on the database server to get the federated database name." -Level WARN
            return $null
        }
        else {
            return "X$(Get-DatabaseNameFromServerName)"             
        }
    }
    else {
        return $null
    }
}
function Get-InstanceNameList {
    param(
        [Parameter(Mandatory = $false)]
        [string]$DatabaseType
    )
    $jsonResult = Get-DatabasesV2Json | Where-Object { $_.ServerName.ToLower().Trim() -eq $env:COMPUTERNAME.ToLower().Trim() -and $_.IsActive -eq $true -and $_.Provider -eq "DB2" }
    $accessPoints = $jsonResult | Select-Object -ExpandProperty AccessPoints | Where-Object { $_.IsActive -eq $true } 
    if ($PSBoundParameters.ContainsKey("DatabaseType") -and -not [string]::IsNullOrEmpty($DatabaseType)) {
        $accessPoints = $accessPoints | Where-Object { $_.AccessPointType -eq $DatabaseType }
    }
    $instanceNames = $accessPoints | Select-Object -ExpandProperty InstanceName -Unique | Sort-Object
    return $instanceNames
}

function Get-FederatedInstanceNameFromPrimaryInstanceName {
    param(
        [Parameter(Mandatory = $true)]
        [string]$PrimaryInstanceName
    )
    $jsonResult = Get-DatabasesV2Json | Where-Object { $_.ServerName.ToLower().Trim() -eq $env:COMPUTERNAME.ToLower().Trim() -and $_.IsActive -eq $true -and $_.Provider -eq "DB2" }
    $primaryAccessPoint = $jsonResult | Select-Object -ExpandProperty AccessPoints | Where-Object { $_.IsActive -eq $true -and $_.InstanceName.ToUpper() -eq $PrimaryInstanceName.ToUpper() -and $_.AccessPointType -eq "PrimaryDb" } | Select-Object -First 1
    $fedAccessPoint = $jsonResult | Where-Object { $_.Database -eq $primaryAccessPoint.CatalogName -and $_.IsActive -eq $true } | Select-Object -ExpandProperty AccessPoints | Where-Object { $_.IsActive -eq $true -and $_.AccessPointType -eq "FederatedDb" } | Select-Object -First 1 | Select-Object -ExpandProperty InstanceName 
    return $fedAccessPoint
    
}
function Get-DatabaseNameList {
    param(
        [Parameter(Mandatory = $false)]
        [string]$DatabaseType,
        [Parameter(Mandatory = $false)]
        [string]$InstanceName,
        [Parameter(Mandatory = $false)]
        [switch]$SkipAlias = $false,
        [Parameter(Mandatory = $false)]
        [switch]$SkipFederated = $false
    )
    $jsonResult = Get-DatabasesV2Json | Where-Object { $_.ServerName.ToLower().Trim() -eq $env:COMPUTERNAME.ToLower().Trim() -and $_.IsActive -eq $true -and $_.Provider -eq "DB2" }
    $accessPoints = $jsonResult.AccessPoints
    if ($PSBoundParameters.ContainsKey("DatabaseType") -and -not [string]::IsNullOrEmpty($DatabaseType)) {
        $accessPoints = $accessPoints | Where-Object { $_.AccessPointType -eq $DatabaseType }
    }
    if ($PSBoundParameters.ContainsKey("InstanceName") -and -not [string]::IsNullOrEmpty($InstanceName)) {
        $accessPoints = $accessPoints | Where-Object { $_.InstanceName -eq $InstanceName }
    }
    if ($SkipAlias) {
        $accessPoints = $accessPoints | Where-Object { $_.AccessPointType -ne "Alias" }
    }
    if ($SkipFederated) {
        $accessPoints = $accessPoints | Where-Object { $_.AccessPointType -ne "FederatedDb" }
    }
    $databaseNames = $accessPoints | Where-Object { $_.IsActive -eq $true } | Select-Object -ExpandProperty CatalogName -Unique

    return $databaseNames
}

function Get-PrimaryInstanceName {
    return "DB2"
}

function Get-DatabaseTypeFromInstanceName {
    param(
        [Parameter(Mandatory = $true)]
        [string]$InstanceName
    )
    if ($InstanceName.ToUpper().EndsWith("FED")) {
        return "FederatedDb"
    }
    else {
        return "PrimaryDb"
    }    
}

function Get-PrimaryInstanceNameFromFederatedInstanceName {
    param(
        [Parameter(Mandatory = $true)]
        [string]$FederatedInstanceName
    )
    if ($FederatedInstanceName.ToUpper() -eq "DB2FED") {
        return "DB2"
    }
    elseif ($FederatedInstanceName.ToUpper() -eq "DB2HFED") {
        return "DB2HST"
    }
    else {
        return $null
    }
}


function Get-PrimaryDb2DataDisk {
    if (Test-IsServer -Quiet $true) {
        if ($env:COMPUTERNAME.ToLower().EndsWith("-db")) {
            return "E:"
        }
        else {
            Write-LogMessage "Db2 primary disk not found for server $env:COMPUTERNAME because it is not a database server. Run this script on the database server to get the Db2 primary disk." -Level WARN
            return $null
        }
    }
}



function Get-CommandPathWithFallback {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $true)]
        [string]$Name,
        [Parameter(Mandatory = $false)]
        [switch]$Quiet = $false
    )
     
    # if ($Name.Contains(".")) {
    #     $Name = $Name.Split(".")[0].Trim().ToLower()
    # }
    # else {
    $Name = $Name.Trim().ToLower()
    # }


    $commandPath = Get-Command -Name "$Name" -ErrorAction SilentlyContinue
    

    if ($null -ne $commandPath) {
        if ($commandPath.GetType() -eq [Object[]]) {
            $commandPath = $commandPath[0]
            Write-LogMessage "Command $Name found in multiple paths. Using first path: $commandPath" -Level WARN -Quiet:$Quiet
        }
        else {
            $commandPath = $commandPath.Path
        }

        if (-not (Test-Path $commandPath -PathType Leaf -ErrorAction SilentlyContinue)) {
            Write-LogMessage "Executable $($Name).exe from Get-Command not found in the path $commandPath. Attempting to find it in other paths." -Level WARN -Quiet:$Quiet
            $commandPath = $null
        }
    }
    
    
    if ([string]::IsNullOrEmpty($commandPath)) {
        $potentialPaths = @()
        # Handle DB2 commands
        if ($Name.Contains("db2")) {
            $potentialPaths += "C:\DbInst\BIN"
            $potentialPaths += "C:\Program Files\IBM\SQLLIB\BIN"
            $potentialPaths += "C:\Program Files (x86)\IBM\SQLLIB\BIN"
        }
        # Handle Powershell 7 commands
        elseif ($Name.Contains("pwsh")) {
            $potentialPaths += "C:\Program Files\PowerShell\7"
        }
        # Handle Powershell 5 commands
        elseif ($Name.ToLower().Contains("powershell")) {
            $potentialPaths += "C:\Windows\System32\WindowsPowerShell\v1.0"
        }
        elseif ($Name.ToLower().Contains("ollama")) {
            $potentialPaths += "$env:USERPROFILE\AppData\Local\Programs\Ollama"
        }
        elseif ($Name.ToLower().Contains("cursor")) {
            $potentialPaths += "$env:USERPROFILE\AppData\Local\Programs\Cursor"
            $potentialPaths += "C:\Program Files\Cursor"
        }
        elseif ($Name.ToLower().Contains("code")) {
            $potentialPaths += "$env:USERPROFILE\AppData\Local\Programs\Microsoft VS Code\bin"
            $potentialPaths += "C:\Program Files\Microsoft VS Code\bin"
        }
        elseif ($Name.ToLower().Contains("appcmd")) {
            $potentialPaths += Join-Path $env:WINDIR 'System32\inetsrv'
        }
        # Handle Windows commands
        else {
            $potentialPaths += "C:\Windows\System32"
            $potentialPaths += "C:\Windows\SysWOW64"
            $potentialPaths += "C:\Windows\System32\Wbem"
            $potentialPaths += "C:\Windows\System32\WindowsPowerShell\v1.0"
            $potentialPaths += "C:\Windows\System32\OpenSSH"
            $potentialPaths += "C:\Program Files (x86)\Microsoft\Edge\Application"
        }

        if ($potentialPaths.Count -gt 0) {
            foreach ($path in $potentialPaths) {
                if (Test-Path $path -PathType Container) {
                    # Write-Verbose "Checking path for executable: $path"
                    $commandPath = Join-Path $path "$Name.exe"
                    if (Test-Path $commandPath -PathType Leaf) {
                        Write-LogMessage "Command $Name found in path using advanced method: $commandPath" -Level TRACE -Quiet:$Quiet
                        break
                    }
                    # Write-Verbose "Checking path for executable: $path"
                    $commandPath = Join-Path $path "$Name.cmd"
                    if (Test-Path $commandPath -PathType Leaf) {
                        Write-LogMessage "Command $Name found in path using advanced method: $commandPath" -Level TRACE -Quiet:$Quiet
                        break
                    }
                    # Write-Verbose "Checking path for executable: $path"
                    $commandPath = Join-Path $path "$Name.bat"
                    if (Test-Path $commandPath -PathType Leaf) {
                        Write-LogMessage "Command $Name found in path using advanced method: $commandPath" -Level TRACE -Quiet:$Quiet
                        break
                    }
                }
            }
        }
    }
    if ([string]::IsNullOrEmpty($commandPath) -or -not (Test-Path $commandPath -PathType Leaf)) {
        # Continue: Logs the error and continues execution
        Write-LogMessage "Command-path $($Name) not found by Get-Command or in any of the following paths: $($potentialPaths -join ", "). Returning $Name as the command path." -Level WARN -Quiet:$Quiet
        $commandPath = $Name
    }

    return $commandPath
}

function Get-OldServiceUsernameFromServerName {
    if (Test-IsServer) {
        $serviceUsername = ""
        if ($env:COMPUTERNAME.ToLower().StartsWith("p-no1")) {
            $serviceUsername = "p1_srv_"
        }
        elseif ($env:COMPUTERNAME.ToLower().StartsWith("t-no1")) {
            $serviceUsername = "t1_srv_"
        }

        $temp = $env:COMPUTERNAME.Replace("p-no1", "").Replace("t-no1", "")
        $serviceUsername += $temp.Replace("-", "_")
        return $serviceUsername
    
    }
    else {
        return $null
    }
}


function Get-ApplicationFromServerName {
    if (Test-IsServer) {
        return $env:COMPUTERNAME.Substring(5, 3).ToUpper()
    }
    else {
        return $null
    }
}

function Get-EnvironmentFromServerName {
    if (Test-IsServer) {
        $environment = $env:COMPUTERNAME.Substring(8, 3).ToUpper()
        if ($environment -eq "VCT") {
            return "TST"
        }
        else {
            return $environment
        }
    }
    else {
        return $null
    }
}


<#
.SYNOPSIS
    Sends alert messages to WKMonitor for monitoring application status and errors.

.DESCRIPTION
    Creates and writes monitoring alert messages to a file for the WKMonitor system.
    If the code is not "0000" (success), writes a detailed alert message including
    timestamp, program name, code, computer name, and custom message to both the
    Logger system and a monitor file. For successful codes, only logs to the Logger system.

.PARAMETER Program
    The name of the program or application generating the alert.

.PARAMETER Code
    The return code. If not "0000", triggers an alert message.

.PARAMETER Message
    The actual message content to be logged.

.EXAMPLE
    Send-FkAlert -Program "MyApp" -Code "ERR1" -Message "Process failed"
    # Creates an alert monitor file with the error message

.EXAMPLE
    Send-FkAlert -Program "Backup" -Code "0000" -Message "Backup completed successfully"
    # Only logs to Logger system, no monitor file created

.NOTES
    Monitor files are created with format: [ComputerName][Timestamp].MON
    The path for monitor files varies based on the computer name:
    - For environment TST: Network path \\DEDGE.fk.no\erpprog\cobtst\monitor\   
    - For environment PRD: Network path \\DEDGE.fk.no\erpprog\cobnt\monitor\
#>
function Send-FkAlert {
    param (
        [Parameter(Mandatory = $true)]
        [string] $Program,
        [Parameter(Mandatory = $true)]
        [string] $Code,
        [Parameter(Mandatory = $false)]
        [string] $Message,
        [Parameter(Mandatory = $false)]
        [switch] $Force
    )
    Write-LogMessage "Sending alert to monitor with $Program - $Code - $Message" -Level INFO
    if ($Code -ne "0000" -or $Force) {
    
        $wkmon = $Program + " " + $Code + " " + $Env:Computername + ": " + $Message
        $wkmonNewMessage = "Program $Program completed with exit code $Code on machine $Env:Computername and reported message: $Message"
        #Db2-Backup 0000 t-no1inltst-db: Backup av INLTST ferdig!
        if ($Code -ne "0000") {
            Write-LogMessage $wkmonNewMessage -Level ERROR
        }
        else {
            Write-LogMessage $wkmonNewMessage -Level INFO
        }
    
        $wkmon = (Get-Date -format ("yyyyMMddHHmmss")) + " " + $wkmon

        if ($(Get-EnvironmentFromServerName) -eq "PRD" -or $(Get-EnvironmentFromServerName) -eq "RAP") {
            $wkmonpath = "\\DEDGE.fk.no\erpprog\cobnt\monitor\"
            Write-LogMessage "Sending alert to PRD monitor path: $wkmonpath" -Level INFO
        }
        else {
            $wkmonpath = "\\DEDGE.fk.no\erpprog\cobtst\monitor\"
            Write-LogMessage "Sending alert to TST monitor path: $wkmonpath" -Level INFO
        }
        
        $wkmonfilename = Join-Path $wkmonpath ($env:Computername + (Get-Date -Format("yyyyMMddHHmmss")) + ".MON")
        Out-File -FilePath $wkmonfilename -InputObject ($wkmon).ToString() -Encoding ascii 
        Write-LogMessage "Alert sent to monitor path: $wkmonfilename" -Level INFO
    }
    else {
        Write-LogMessage "Alert not sent due to code $Code and that it was not a forced alert" -Level INFO
    }
}

function Find-ValidDrives {
    param(
        [Parameter(Mandatory = $false)]
        [bool]$SkipSystemDrive = $true
    )
    # Find lastdrive folder
    if ($SkipSystemDrive) {
        $driveArray = @("G", "F", "E", "D")
    }
    else {
        $driveArray = @("G", "F", "E", "D", "C")
    }
    $lastDrive = $null
    $validDrives = @()
    foreach ($drive in $driveArray) {
        if (Test-Path -Path "$($drive):\") {
            Write-LogMessage "Drive $($drive): exists" -Level TRACE
            if ($null -eq $lastDrive) {
                $lastDrive = "$($drive)"
            }
            $validDrives += $drive
        }
    }

    return $validDrives
}

function Find-ExistingFolder {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Name,
        [Parameter(Mandatory = $false)]
        [string]$PreferredDrive = $null,
        [Parameter(Mandatory = $false)]
        [switch]$Quiet = $false,
        [Parameter(Mandatory = $false)]
        [switch]$SkipRecreateFolders = $false
    )

    $ValidDrives = Find-ValidDrives
    if ($null -ne $PreferredDrive -and $PreferredDrive -in $ValidDrives) {
        $lastDrive = $PreferredDrive
    }
    else {
        $lastDrive = $ValidDrives[0]
    }

    # Find folder with name
    $folder = $null
    foreach ($drive in $validDrives) {
        if (Test-Path -Path "$($drive):\$Name") {
            $folder = "$($drive):\$Name"
            break;
        }
    }
    
    # Check if folder does not exist
    if ([string]::IsNullOrEmpty($folder)) {
        Write-LogMessage "$Name folder not found, creating new folder on $($lastDrive):\$Name" -Level INFO -QuietMode:$Quiet
        # New-Item -Path "$($lastDrive):\$Name" -ItemType Directory -Force | Out-Null
        $folder = "$($lastDrive):\$Name"
        Add-Folder -Path $folder -AdditionalAdmins $(Get-AdditionalAdmins -AdditionalAdmins @()) -EveryonePermission "Read"
        return $folder
    }
    else {
        if (-not $SkipRecreateFolders) {
            Write-LogMessage "$Name folder found on $($folder), recreating folder" -Level INFO
            Add-Folder -Path $folder -AdditionalAdmins $(Get-AdditionalAdmins -AdditionalAdmins @()) -EveryonePermission "Read"
        }
        return $folder
    }   
    
}
function Get-InitScriptName {
    param(
        [Parameter(Mandatory = $false)]
        [string]$Path = $null
    )
    $scriptName = "Main"
    try {
        if (-not [string]::IsNullOrEmpty($MyInvocation.ScriptName)) {
            $scriptName = $(Split-Path -Path $MyInvocation.ScriptName -Leaf)
            return $scriptName
        }
        if (-not [string]::IsNullOrEmpty($MyInvocation.MyCommand.Path)) {
            $scriptName = $(Split-Path -Path $MyInvocation.MyCommand.Path -Leaf)
            return $scriptName
        }
        if (-not [string]::IsNullOrEmpty($MyInvocation.MyCommand.Path)) {
            $scriptName = $(Split-Path -Path $MyInvocation.MyCommand.Path -Leaf)
            return $scriptName
        }
        if (-not [string]::IsNullOrEmpty($Path)) {
            if ($null -ne $Path) {
                $scriptName = $(Split-Path -Path $Path -Leaf)
                return $scriptName
            }
        }
    }
    catch {}
    return $scriptName
}


function Get-FullScriptPath {
    param(
        [Parameter(Mandatory = $false)]
        [string]$Path = $null
    )
    $returnPath = & {
        # Get script name of calling script
        $callStack = Get-PSCallStack | Select-Object -Property * 
        $correctCallingScriptStackFrame = $null
        for ($i = $callStack.Count - 1; $i -ge 0; $i--) {
            if (-not [string]::IsNullOrEmpty($callStack[$i].ScriptName) -and -not $callStack[$i].ScriptName.ToLower().Contains(".psm1")) {
                $correctCallingScriptStackFrame = $callStack[$i]
                break
            }
        }
        if ($null -eq $correctCallingScriptStackFrame) {
            $correctCallingScriptStackFrame = $callStack[0]
        }
        $callingScript = $correctCallingScriptStackFrame.ScriptName
        return $callingScript
    } 

    if ($returnPath.GetType() -eq [System.String]) {
        return $returnPath
    }
    elseif ($returnPath.GetType() -eq [object[]]) {
        return $returnPath[0].Path
    }
    return $returnPath
}
function Format-FileNameAsHtmlHyperlink {
    param(
        [Parameter(Mandatory = $true)]
        [string]$FileName,
        [Parameter(Mandatory = $false)]
        [string]$Target = "_blank"
    )
    # "C:\opt\src\DedgeSrc\DedgeSystemTools\Folders\Opt\Webs\FkAdminWeb\Content\Db2\Db2 Auto Generated Catalogs Scipts.html"
    # file://dedge-server/Opt/Webs/FkAdminWeb/Content/Db2/Db2%20Auto%20Generated%20Catalogs%20Scipts.html
    
    # Convert UNC paths and drive-lettered Windows paths to file:// URL format with URL-encoded spaces
    $hrefFileName = $FileName
    if ($hrefFileName -match "^\\\\([^\\]+)\\(.+)$") {
        # UNC path: \\server\share\path...
        $hrefFileName = "file://" + ($hrefFileName -replace "^\\\\+", "") -replace "\\", "/"
        $hrefFileName = $hrefFileName -replace " ", "%20"
    }
    elseif ($hrefFileName -match "^[c-zC-Z]:(\\|/).+") {
        # Local path: C:\path\to\file or C:/path/to/file
        $hrefFileName = "file:///" + ($hrefFileName -replace "\\", "/")
        $hrefFileName = $hrefFileName -replace " ", "%20"
    }
    return "<a href='$($hrefFileName)' target='$($Target)'>$($FileName)</a>"
}

function ConvertTo-HyperlinkText {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Text
    )
    
    <#
    Regex patterns for detecting file paths:
    - UNC path pattern: \\server\share\path\file.ext
    - Drive path pattern: C:\path\file.ext or D:/path/file.ext
    
    Based on patterns from Format-FileNameAsHtmlHyperlinkWithTarget:
    - UNC: ^\\\\([^\\]+)\\(.+)$
    - Drive: ^[c-zC-Z]:(\\|/).+
    
    Modified for inline detection (not anchored):
    #>
    
    # Pattern 1: UNC paths - \\server\share\path\file.ext
    # Match: \\word\word or more, exclude spaces and HTML chars
    $uncPattern = '\\\\[^\\]+\\[^\s<>"]+'
    
    # Pattern 2: Drive paths - C:\path\file.ext or D:/path/file.ext  
    # Must have at least one path separator after drive letter
    $drivePattern = '[c-zC-Z]:[/\\][^\s<>"]*[/\\][^\s<>"]+'
    
    # Replace UNC paths with hyperlinks
    $Text = [regex]::Replace($Text, $uncPattern, {
            param($match)
            $path = $match.Value
            Format-FileNameAsHtmlHyperlink -FileName $path -Target "_blank"
        })
    
    # Replace drive paths with hyperlinks
    $Text = [regex]::Replace($Text, $drivePattern, {
            param($match)
            $path = $match.Value
            Format-FileNameAsHtmlHyperlink -FileName $path -Target "_blank"
        })
    
    return $Text
}

function Export-WorkObjectToJsonFile {
    param(
        [Parameter(Mandatory = $true)]
        [PSCustomObject]$WorkObject,
        [Parameter(Mandatory = $false)]
        [string]$FileName
    )
    try {
        Write-LogMessage "Exporting database object to json file: $($FileName)" -Level INFO
        Add-FolderForFileIfNotExists -FileName $FileName
        $WorkObject | ConvertTo-Json -Compress:$false -Depth 100 | Set-Content -Path $FileName | Out-Null

        # Export database object to json file using C# code
        # $jsonOptions = [System.Text.Json.JsonSerializerOptions]::new()
        # $jsonOptions.WriteIndented = $true
        # $jsonOptions.ReferenceHandler = [System.Text.Json.Serialization.ReferenceHandler]::Preserve
        # $jsonContent = [System.Text.Json.JsonSerializer]::Serialize($WorkObject, $jsonOptions)
        # Set-Content -Path $FileName -Value $jsonContent -Encoding UTF8

        Write-LogMessage "Database object exported to $FileName" -Level INFO
    }
    catch {
        Write-LogMessage "Error exporting database object to file: $($FileName)" -Level ERROR -Exception $_
        throw $_
    }
}

function Export-WorkObjectToHtmlFile {
    param(
        [Parameter(Mandatory = $true)]
        [PSCustomObject]$WorkObject,
        [Parameter(Mandatory = $false)]
        [string]$FileName,
        [Parameter(Mandatory = $false)]
        [string]$Title = "Object Export",
        [Parameter(Mandatory = $false)]
        [bool]$AddToDevToolsWebPath = $false,
        [Parameter(Mandatory = $false)]
        [string]$DevToolsWebDirectory = "",
        [Parameter(Mandatory = $false)]
        [bool]$AutoOpen = $false,
        [Parameter(Mandatory = $false)]
        [switch]$NoTitleAutoFormat = $false
    )
    try {
        Write-LogMessage "Exporting database object to file: $($FileName)" -Level INFO
        Add-FolderForFileIfNotExists -FileName $FileName
        # Ensure ScriptArray property exists and is always an array (handles null, single item, or existing array)
        if (-not ($WorkObject.PSObject.Properties.Name -contains 'ScriptArray')) {
            Add-Member -InputObject $WorkObject -MemberType NoteProperty -Name 'ScriptArray' -Value @() -Force
        }
        else {
            $WorkObject.ScriptArray = @($WorkObject.ScriptArray)
        }

        $htmlFile = $FileName
        $addStyleContent = @"
        body {
            max-width: 100vw;
            overflow-x: hidden;
        }
        .tab-container { 
            display: flex;
            margin: 20px 0;
            min-height: 400px;
            max-width: calc(100vw - 40px);
        }
        .tab-headers { 
            width: 250px;
            min-width: 250px;
            border-right: 2px solid #ddd;
            padding-right: 0;
            display: flex;
            flex-direction: column;
        }
        .tab-button { 
            background-color: #f1f1f1; 
            border: none; 
            padding: 12px 15px; 
            cursor: pointer; 
            font-size: 14px; 
            margin-bottom: 2px;
            text-align: left;
            border-radius: 5px 0 0 5px;
            white-space: normal;
            word-wrap: break-word;
        }
        .tab-button:hover { background-color: #ddd; }
        .tab-button.active { 
            background-color: #007acc; 
            color: white; 
        }
        .tab-content { 
            display: none; 
            padding: 20px; 
            border: 1px solid #ddd; 
            border-left: none;
            flex-grow: 1;
            overflow-x: auto;
            max-width: calc(100vw - 310px);
        }
        table {
            table-layout: auto;
            max-width: 100%;
        }
        table td, table th {
            max-width: 400px;
            word-wrap: break-word;
            overflow-wrap: break-word;
            word-break: break-word;
        }
        .monaco-editor-container { 
            border: 1px solid #ddd; 
            margin: 10px 0; 
            min-height: 300px;
            height: 500px;
        }
        .code-block { 
            background-color: #f8f8f8; 
            border: 1px solid #ddd; 
            padding: 15px; 
            margin: 10px 0; 
            font-family: 'Courier New', monospace; 
            white-space: pre-wrap; 
            overflow-x: auto;
            border-radius: 3px;
        }
    </style>
    <script src="https://cdnjs.cloudflare.com/ajax/libs/monaco-editor/0.45.0/min/vs/loader.min.js"></script>
    <style>
"@
        
        # Separate properties into scalar, array, and multiline
        $scalarProperties = @()
        $arrayProperties = @()
        $multilineProperties = @()
        
        foreach ($property in $WorkObject.PSObject.Properties) {
            if ($property.MemberType -eq "NoteProperty") {
                if ($property.Name -match "(scriptarray)$") {
                    continue
                }
                # Check if property is an array of objects (table-worthy)
                if ($property.Value -is [array] -and $property.Value.Count -gt 0 -and $property.Value[0] -is [PSCustomObject]) {
                    $arrayProperties += $property
                }
                else {
                    $scalarProperties += $property
                }
            }
        }

        # Start tabbed interface
        $htmlContent += "<div class='tab-container'>"
        
        # Tab headers - Properties first, then ScriptArray
        $htmlContent += "<div class='tab-headers'>"
        
        # Properties tab button (always first and active)
        $htmlContent += "<button class='tab-button active' onclick='showTab(0)'>Properties</button>"
        # make sure ScriptArray is an array, and if not convert it to an array
      
        # ScriptArray tab buttons
        if ($WorkObject.ScriptArray -and $WorkObject.ScriptArray.Count -gt 0) {
            $WorkObject.ScriptArray = $WorkObject.ScriptArray | Sort-Object -Property FirstTimestamp -Descending

            for ($i = 0; $i -lt $WorkObject.ScriptArray.Count; $i++) {
                $script = $WorkObject.ScriptArray[$i]
                $tabIndex = $i + 1  # Offset by 1 since Properties is tab 0
                if ($script.FirstTimestamp -eq $script.LastTimestamp) {
                    $htmlContent += "<button class='tab-button' onclick='showTab($tabIndex)'>$($script.Name)<br>Created: $($script.FirstTimestamp)</button>"
                }
                else {
                    $htmlContent += "<button class='tab-button' onclick='showTab($tabIndex)'>$($script.Name)<br>Created: $($script.FirstTimestamp)<br>Modified: $($script.LastTimestamp)</button>"
                }

            }
        }
        
        $htmlContent += "</div>"
        
        # Tab contents
        $htmlContent += "<div style='flex-grow: 1; position: relative;'>"
        
        # Properties tab content (first tab, index 0)
        $htmlContent += "<div id='tab-0' class='tab-content' style='display: block;'>"
        
        # Display scalar properties in main table
        if ($scalarProperties.Count -gt 0) {
            $htmlContent += "<h2>Properties</h2>"
            $htmlContent += "<table style='border-collapse: collapse; width: 100%; margin-bottom: 20px;'>"
            $htmlContent += "<tr style='background-color: #f2f2f2;'><th style='border: 1px solid #ddd; padding: 8px; text-align: left;'>Property</th><th style='border: 1px solid #ddd; padding: 8px; text-align: left;'>Value</th></tr>"
            foreach ($property in $scalarProperties) {
                if ($property.Value -is [array]) {
                    $propertyValue = ($property.Value -join "<br>")
                }
                else {
                    $propertyValue = $property.Value -replace "`r`n", "<br>" -replace "`n", "<br>" -replace "`r", "<br>"
                }
                
                # Auto-detect and hyperlink file paths (only if not already a hyperlink)
                if ($propertyValue -notmatch '<a href=') {
                    # Drive path pattern FIRST (to avoid matching 'e:' in 'file://')
                    # Pattern: [letter]:\ or [letter]:/ followed by path (allows spaces)
                    # Stops at: < > " or end of string, allows spaces in path
                    $propertyValue = [regex]::Replace($propertyValue, '(?<!fil)[c-zC-Z]:[/\\](?:[^<>"\\]*\\)*[^<>"\\]+(?:\.[a-zA-Z0-9]+)?', {
                            param($m)
                            $path = $m.Value
                            $href = "file:///" + ($path -replace "\\", "/") -replace " ", "%20"
                            "<a href='$href' target='_blank'>$path</a>"
                        })
                    
                    # UNC path pattern AFTER drive paths
                    # Pattern: \\server\share\path (allows spaces)
                    # Stops at: < > " or end of string
                    $propertyValue = [regex]::Replace($propertyValue, '\\\\[^\\<>"]+(?:\\[^\\<>"]+)+', {
                            param($m)
                            $path = $m.Value
                            $href = "file://" + ($path -replace "^\\\\+", "") -replace "\\", "/" -replace " ", "%20"
                            "<a href='$href' target='_blank'>$path</a>"
                        })
                }
                
                $htmlContent += "<tr><td style='border: 1px solid #ddd; padding: 8px; font-weight: bold;'>$($property.Name)</td><td style='border: 1px solid #ddd; padding: 8px;'>$propertyValue</td></tr>"
            }
            $htmlContent += "</table>"
        }
        
        # Add multiline properties with headings
        foreach ($property in $multilineProperties) {
            $htmlContent += "<h2>$($property.Name)</h2>"
            $htmlContent += "<div style='border: 1px solid #ccc; padding: 10px; margin: 10px 0; background-color: #f9f9f9; font-family: Courier New, monospace; white-space: pre-wrap;'>$($property.Value)</div>"
        }
        
        # Add array properties as tables with headers
        foreach ($arrayProp in $arrayProperties) {
            $htmlContent += "<h2>$($arrayProp.Name)</h2>"
            
            if ($arrayProp.Value.Count -gt 0) {
                # Get all unique property names from all objects in the array
                $allPropertyNames = @()
                foreach ($item in $arrayProp.Value) {
                    foreach ($prop in $item.PSObject.Properties) {
                        if ($prop.MemberType -eq "NoteProperty" -and $allPropertyNames -notcontains $prop.Name) {
                            $allPropertyNames += $prop.Name
                        }
                    }
                }
                
                # Create table
                $htmlContent += "<table style='border-collapse: collapse; width: 100%; margin-bottom: 20px;'>"
                
                # Header row
                $htmlContent += "<tr style='background-color: #4CAF50; color: white;'>"
                foreach ($propName in $allPropertyNames) {
                    $htmlContent += "<th style='border: 1px solid #ddd; padding: 8px; text-align: left;'>$propName</th>"
                }
                $htmlContent += "</tr>"
                
                # Data rows
                $rowIndex = 0
                foreach ($item in $arrayProp.Value) {
                    $rowStyle = if ($rowIndex % 2 -eq 0) { "background-color: #f9f9f9;" } else { "background-color: #ffffff;" }
                    $htmlContent += "<tr style='$rowStyle'>"
                    foreach ($propName in $allPropertyNames) {
                        $cellValue = if ($item.$propName) { 
                            if ($item.$propName -is [array]) {
                                ($item.$propName -join ", ")
                            }
                            else {
                                $item.$propName.ToString() -replace "`r`n", "<br>" -replace "`n", "<br>" -replace "`r", "<br>"
                            }
                        }
                        else { "" }
                        
                        # Auto-detect and hyperlink file paths (only if not already a hyperlink)
                        if ($cellValue -notmatch '<a href=') {
                            # Drive path pattern FIRST (to avoid matching 'e:' in 'file://')
                            # Pattern: [letter]:\ or [letter]:/ followed by path (allows spaces)
                            # Stops at: < > " or end of string, allows spaces in path
                            $cellValue = [regex]::Replace($cellValue, '(?<!fil)[c-zC-Z]:[/\\](?:[^<>"\\]*\\)*[^<>"\\]+(?:\.[a-zA-Z0-9]+)?', {
                                    param($m)
                                    $path = $m.Value
                                    $href = "file:///" + ($path -replace "\\", "/") -replace " ", "%20"
                                    "<a href='$href' target='_blank'>$path</a>"
                                })
                            
                            # UNC path pattern AFTER drive paths
                            # Pattern: \\server\share\path (allows spaces)
                            # Stops at: < > " or end of string
                            $cellValue = [regex]::Replace($cellValue, '\\\\[^\\<>"]+(?:\\[^\\<>"]+)+', {
                                    param($m)
                                    $path = $m.Value
                                    $href = "file://" + ($path -replace "^\\\\+", "") -replace "\\", "/" -replace " ", "%20"
                                    "<a href='$href' target='_blank'>$path</a>"
                                })
                        }
                        
                        $htmlContent += "<td style='border: 1px solid #ddd; padding: 8px;'>$cellValue</td>"
                    }
                    $htmlContent += "</tr>"
                    $rowIndex++
                }
                
                $htmlContent += "</table>"
                $htmlContent += "<p style='color: #666; font-size: 0.9em;'>Total: $($arrayProp.Value.Count) items</p>"
            }
            else {
                $htmlContent += "<p style='color: #999;'>No items in array</p>"
            }
        }
        
        $htmlContent += "</div>"
        
        # ScriptArray tab contents with Monaco Editor and fallback
        if ($WorkObject.ScriptArray -and $WorkObject.ScriptArray.Count -gt 0) {
            for ($i = 0; $i -lt $WorkObject.ScriptArray.Count; $i++) {
                $script = $WorkObject.ScriptArray[$i]
                $tabIndex = $i + 1  # Offset by 1 since Properties is tab 0
                $htmlContent += "<div id='tab-$tabIndex' class='tab-content' style='display: none;'>"
                
                # Store content in JSON script tags (safer than HTML attributes)
                $scriptJson = ($script.Script | ConvertTo-Json)
                $outputJson = ($script.Output | ConvertTo-Json)
                
                $htmlContent += "<script type='application/json' id='data-script-$i'>$scriptJson</script>"
                $htmlContent += "<script type='application/json' id='data-output-$i'>$outputJson</script>"
                
                # Script section with Monaco Editor and fallback
                $htmlContent += "<h3>Script</h3>"
                $htmlContent += "<div id='editor-script-$i' class='monaco-editor-container'></div>"
                $htmlContent += "<pre id='fallback-script-$i' class='code-block' style='display:none;'></pre>"
                
                # Output section with Monaco Editor and fallback
                $htmlContent += "<h3>Output</h3>"
                $htmlContent += "<div id='editor-output-$i' class='monaco-editor-container'></div>"
                $htmlContent += "<pre id='fallback-output-$i' class='code-block' style='display:none;'></pre>"
                
                $htmlContent += "</div>"
            }
        }
        
        $htmlContent += "</div>"  # Close flex-grow div
        $htmlContent += "</div>"  # Close tab-container
        
        # Add Monaco Editor initialization with fallback for offline mode
        $htmlContent += @"
        <script>
        var editors = {};
        var monacoLoaded = false;
        
        // Define fallback function BEFORE trying to load Monaco
        function showFallbackContent() {
            // Hide all Monaco editor containers
            var editorContainers = document.querySelectorAll('.monaco-editor-container');
            for (var i = 0; i < editorContainers.length; i++) {
                editorContainers[i].style.display = 'none';
            }
            
            // Show and populate fallback pre elements
"@
        
        # Add fallback content population for each script
        if ($WorkObject.ScriptArray -and $WorkObject.ScriptArray.Count -gt 0) {
            for ($i = 0; $i -lt $WorkObject.ScriptArray.Count; $i++) {
                $htmlContent += @"

            var scriptFallback$i = document.getElementById('fallback-script-$i');
            var outputFallback$i = document.getElementById('fallback-output-$i');
            if (scriptFallback$i && outputFallback$i) {
                scriptFallback$i.textContent = JSON.parse(document.getElementById('data-script-$i').textContent);
                outputFallback$i.textContent = JSON.parse(document.getElementById('data-output-$i').textContent);
                scriptFallback$i.style.display = 'block';
                outputFallback$i.style.display = 'block';
            }
"@
            }
        }
        
        $htmlContent += @"

        }
        
        // Set timeout for Monaco loading (fallback if CDN fails/no internet)
        var monacoTimeout = setTimeout(function() {
            if (!monacoLoaded) {
                console.log('Monaco Editor failed to load from CDN - using fallback text display');
                showFallbackContent();
            }
        }, 5000);
        
        // Only try to load Monaco if require is available
        if (typeof require !== 'undefined') {
            require.config({ paths: { 'vs': 'https://cdnjs.cloudflare.com/ajax/libs/monaco-editor/0.45.0/min/vs' }});
            
            require(['vs/editor/editor.main'], function() {
                clearTimeout(monacoTimeout);
                monacoLoaded = true;
                
                // Register custom language with DB2, PowerShell, and SQL keywords
            monaco.languages.register({ id: 'db2batch' });
            
            monaco.languages.setMonarchTokensProvider('db2batch', {
                defaultToken: '',
                tokenPostfix: '.db2batch',
                ignoreCase: true,
                
                // DB2, SQL, PowerShell, and Batch keywords
                keywords: [
                    // Batch/CMD keywords
                    'echo', 'set', 'call', 'goto', 'if', 'else', 'for', 'in', 'do', 'rem', 'pause', 'exit', 'cd', 'md', 'rd', 'copy', 'move', 'del', 'dir', 'cls', 'start',
                    // DB2 commands
                    'db2', 'catalog', 'uncatalog', 'tcpip', 'node', 'database', 'remote', 'server', 'authentication', 'terminate', 'connect', 'update', 'cli', 'cfg',
                    'using', 'clnt_krb_plugin', 'kerberos', 'kerberos_sspi', 'ntlm', 'target', 'principal', 'system', 'odbc', 'user', 'data', 'source',
                    // SQL keywords
                    'select', 'from', 'where', 'insert', 'into', 'values', 'update', 'delete', 'create', 'drop', 'alter', 'table', 'index', 'view',
                    'join', 'inner', 'outer', 'left', 'right', 'on', 'and', 'or', 'not', 'null', 'as', 'order', 'by', 'group', 'having', 'distinct',
                    'count', 'sum', 'avg', 'max', 'min', 'timestamp', 'current', 'sysibm', 'sysdummy1',
                    // PowerShell keywords
                    'powershell', 'command', 'write-host', 'foregroundcolor', 'out-file', 'filepath', 'append', 'new-object', 'try', 'catch', 'throw'
                ],
                
                operators: ['=', '>', '<', '!', '==', '!=', '<=', '>=', '&&', '||', '+', '-', '*', '/', '%'],
                
                symbols: /[=><!~?:&|+\-*\/\^%]+/,
                escapes: /\\(?:[abfnrtv\\"']|x[0-9A-Fa-f]{1,4}|u[0-9A-Fa-f]{4}|U[0-9A-Fa-f]{8})/,
                
                tokenizer: {
                    root: [
                        // Comments
                        [/^rem\s.*$$/, 'comment'],
                        [/^::.*$$/, 'comment'],
                        [/--.*$$/, 'comment.sql'],
                        
                        // Labels
                        [/^:[a-zA-Z_]\w*/, 'type.identifier'],
                        
                        // Environment variables
                        [/%[a-zA-Z_]\w*%/, 'variable'],
                        
                        // SQL in strings (approximate detection)
                        [/"[^"]*\b(select|insert|update|delete|create|drop|from|where)\b[^"]*"/, 'string.sql'],
                        [/'[^']*\b(select|insert|update|delete|create|drop|from|where)\b[^']*'/, 'string.sql'],
                        
                        // Strings
                        [/"([^"\\]|\\.)*$$?/, 'string.invalid'],
                        [/'([^'\\]|\\.)*$$?/, 'string.invalid'],
                        [/"/, 'string', '@string_double'],
                        [/'/, 'string', '@string_single'],
                        
                        // Numbers
                        [/\d+/, 'number'],
                        
                        // Keywords
                        [/[a-z_$][\w$]*/, {
                            cases: {
                                '@keywords': 'keyword',
                                '@default': 'identifier'
                            }
                        }],
                        
                        // Operators
                        [/@symbols/, 'operator'],
                        
                        // Whitespace
                        [/[ \t\r\n]+/, ''],
                    ],
                    
                    string_double: [
                        [/[^\\"]+/, 'string'],
                        [/@escapes/, 'string.escape'],
                        [/\\./, 'string.escape.invalid'],
                        [/"/, 'string', '@pop']
                    ],
                    
                    string_single: [
                        [/[^\\']+/, 'string'],
                        [/@escapes/, 'string.escape'],
                        [/\\./, 'string.escape.invalid'],
                        [/'/, 'string', '@pop']
                    ]
                }
            });
            
            // Configure language settings
            monaco.languages.setLanguageConfiguration('db2batch', {
                comments: {
                    lineComment: 'rem',
                },
                brackets: [
                    ['(', ')'],
                ],
                autoClosingPairs: [
                    { open: '(', close: ')' },
                    { open: '"', close: '"' },
                    { open: "'", close: "'" },
                ],
            });
            
"@
        
        # Add editor initialization for each script
        if ($WorkObject.ScriptArray -and $WorkObject.ScriptArray.Count -gt 0) {
            for ($i = 0; $i -lt $WorkObject.ScriptArray.Count; $i++) {
                $htmlContent += @"
            // Script editor $i
            var scriptData$i = JSON.parse(document.getElementById('data-script-$i').textContent);
            editors['script-$i'] = monaco.editor.create(document.getElementById('editor-script-$i'), {
                value: scriptData$i,
                language: 'db2batch',
                theme: 'vs-dark',
                readOnly: true,
                contextmenu: false,
                minimap: { enabled: true },
                scrollBeyondLastLine: false,
                automaticLayout: true,
                fontSize: 13,
                lineNumbers: 'on',
                renderWhitespace: 'selection',
                wordWrap: 'off'
            });
            
            // Output editor $i
            var outputData$i = JSON.parse(document.getElementById('data-output-$i').textContent);
            editors['output-$i'] = monaco.editor.create(document.getElementById('editor-output-$i'), {
                value: outputData$i,
                language: 'db2batch',
                theme: 'vs-dark',
                readOnly: true,
                contextmenu: false,
                minimap: { enabled: true },
                scrollBeyondLastLine: false,
                automaticLayout: true,
                fontSize: 13,
                lineNumbers: 'on',
                renderWhitespace: 'selection',
                wordWrap: 'off'
            });
            
"@
            }
        }
        
        $htmlContent += @"
            }, function(err) {
                // Monaco failed to load - use fallback
                clearTimeout(monacoTimeout);
                console.error('Monaco Editor failed to load:', err);
                showFallbackContent();
            });
        } else {
            // require is not defined (loader.min.js failed to load)
            console.log('RequireJS loader not available - Monaco cannot be loaded');
            showFallbackContent();
        }
        
        function showTab(tabIndex) {
            // Hide all tab contents
            var tabContents = document.querySelectorAll('.tab-content');
            for (var i = 0; i < tabContents.length; i++) {
                tabContents[i].style.display = 'none';
            }
            
            // Remove active class from all buttons
            var tabButtons = document.querySelectorAll('.tab-button');
            for (var i = 0; i < tabButtons.length; i++) {
                tabButtons[i].classList.remove('active');
            }
            
            // Show selected tab content
            document.getElementById('tab-' + tabIndex).style.display = 'block';
            
            // Add active class to selected button
            tabButtons[tabIndex].classList.add('active');
            
            // Trigger layout update for Monaco editors in the active tab (only if Monaco loaded)
            if (monacoLoaded) {
                setTimeout(function() {
                    for (var key in editors) {
                        if (editors.hasOwnProperty(key)) {
                            editors[key].layout();
                        }
                    }
                }, 10);
            }
        }
        </script></body></html>
"@
        $null = Save-HtmlOutput -Title $title -AddStyleContent $addStyleContent -Content $htmlContent -OutputFile $htmlFile -AddToDevToolsWebPath $AddToDevToolsWebPath -DevToolsWebDirectory $DevToolsWebDirectory -AutoOpen $AutoOpen -NoTitleAutoFormat:$NoTitleAutoFormat

        # Set-Content -Path $htmlFile -Value $htmlContent
        Write-LogMessage "Database object exported to $htmlFile" -Level INFO
    }
    catch {
        # Export is non-critical, log the error but don't stop the calling job
        Write-LogMessage "Error exporting database object to file: $($FileName) - continuing execution" -Level WARN -Exception $_
    }
}

function Get-UserConfirmationWithTimeout {
    param(
        [Parameter(Mandatory = $false)]
        [string]$PromptMessage = "Please confirm (Y/N)",
        [Parameter(Mandatory = $false)]
        [int]$TimeoutSeconds = 10,
        [Parameter(Mandatory = $false)]
        [string]$DefaultResponse = "",
        [Parameter(Mandatory = $false)]
        [string[]]$AllowedResponses = @("Y", "N"),
        [Parameter(Mandatory = $false)]
        [string]$ProgressMessage = "Choose response",
        [Parameter(Mandatory = $false)]
        [bool]$AddNumberToAllowedResponses = $true,
        [Parameter(Mandatory = $false)]
        [switch]$ThrowOnTimeout = $false
    )
    if ($AllowedResponses -contains "Y" -and $AllowedResponses -contains "N") {
        $AddNumberToAllowedResponses = $false
        if ([string]::IsNullOrEmpty($DefaultResponse)) {
            $DefaultResponse = "N"
        }
    }
    $foundInPromptMessageCounter = 0
    foreach ($allowedResponse in $AllowedResponses) {
        if ($PromptMessage -contains $allowedResponse) {
            $foundInPromptMessageCounter++
        }
    }

    

    if ($AddNumberToAllowedResponses) {
        if ($AllowedResponses.Count -lt 10) {
            $counter = 1
            $menuAllowedResponses = @()
            foreach ($tempAllowedResponse in $AllowedResponses) {
                $menuAllowedResponses += "$($counter). $($tempAllowedResponse)"
                $counter++
            }
            $AllowedResponses = $menuAllowedResponses
        }
        else {
            $abcArray = "A".."Z" | ForEach-Object { $_ }
            $counter = 0
            $menuAllowedResponses = @()
            foreach ($tempAllowedResponse in $AllowedResponses) {
                $menuAllowedResponses += "$($abcArray[$counter]). $($tempAllowedResponse)"
                $counter++
            }
            $AllowedResponses = $menuAllowedResponses
        }
    }   
    if ($AllowedResponses -contains "Y" -and $AllowedResponses -contains "N" -and $AllowedResponses.Count -eq 2) {
        $allowedResponsesString = "(" + ($AllowedResponses -join " / ") + ")"
    }
    else {
        $allowedResponsesString = "`n  - " + $($AllowedResponses -join "`n  - ")
    }
    
    if ($foundInPromptMessageCounter -ne $AllowedResponses.Count) {
        if ($PromptMessage.Contains("?") -and -not $AddNumberToAllowedResponses) {
            $splitQuestion = $PromptMessage.Split("?")
            $PromptMessage = $splitQuestion[0] + "?" + $allowedResponsesString + " " + $splitQuestion[1] + " "
        }
        else {
            $PromptMessage = $PromptMessage + " " + $allowedResponsesString + " `nSelect response: "
        }
    }
    
    $allowedResponsesFirstLetter = $AllowedResponses | ForEach-Object { $_.Substring(0, 1) }
    $allowedResponsesFirstLetterSortUnique = $allowedResponsesFirstLetter | Sort-Object -Unique
    if (-not $AddNumberToAllowedResponses) {
        if ($allowedResponsesFirstLetterSortUnique.Count -ne $allowedResponsesFirstLetter.Count) {
            Write-LogMessage "AllowedResponsesFirstLetter contains duplicate values" -Level ERROR
            throw "AllowedResponsesFirstLetter contains duplicate values"
        }
    }
    
    if (-not [string]::IsNullOrEmpty($DefaultResponse)) {
        $defaultResponseFirstLetter = $DefaultResponse.Substring(0, 1)
    }
    elseif ($AllowedResponses.Count -gt 0) {
        if ($defaultResponseFirstLetter -notin $allowedResponsesFirstLetter) {
            $defaultResponseFirstLetter = $allowedResponsesFirstLetter[0]
            $DefaultResponse = $AllowedResponses[0]
        }
        else {
            $DefaultResponse = $DefaultResponse
        }
    }
    
    $response = $DefaultResponse
    if ($AllowedResponses.Count -eq 1) {
        Write-Host "Only one response allowed: $DefaultResponse (Auto-continued)" -ForegroundColor Yellow
    }
    else {
        $startTime = Get-Date
        $defaultRefreshTimeMs = 200
        $elapsedTimeMs = 0
        $elapsedLimitMs = 1000
        $remainingTimeoutSeconds = $TimeoutSeconds
        # Write-Host "Remaining timeout: " -NoNewline
        # Progress bar
        Write-LogMessage "PromptMessage: $PromptMessage / DefaultResponse: $DefaultResponse / AllowedResponses: $($AllowedResponses -join ", ") / AddNumberToAllowedResponses: $AddNumberToAllowedResponses" -Level INFO -QuietMode
        Write-Host " "
        Write-Host "------------------------------------------------------------------------------------------------" -ForegroundColor Cyan
        Write-Host $PromptMessage -ForegroundColor Cyan -NoNewline
        Write-Progress -Activity $ProgressMessage -PercentComplete 0 -Status "Remaining timeout: $remainingTimeoutSeconds"
        $increment = 100 / $TimeoutSeconds
        $totalProgress = 0
        $timedOut = $true
        while ((Get-Date).Subtract($startTime).TotalSeconds -lt $TimeoutSeconds) {
            if ([Console]::KeyAvailable) {
                $key = [Console]::ReadKey($true)
                # if ($key.Key -ne "") {
                #     Write-Host "Key: $($key.Key)($($key.KeyChar))" -ForegroundColor Green
                if ($key.KeyChar -in $allowedResponsesFirstLetter) {
                    $response = $key.KeyChar.ToString().ToUpper()
                    $timedOut = $false
                    break
                }
                # }
            }
            Start-Sleep -Milliseconds $defaultRefreshTimeMs
            $elapsedTimeMs += $defaultRefreshTimeMs
            if ($elapsedTimeMs -ge $elapsedLimitMs) {
                $elapsedTimeMs = 0
                $remainingTimeoutSeconds -= 1
                $totalProgress += $increment
                Write-Progress -Activity $ProgressMessage -PercentComplete $totalProgress -Status "Remaining timeout: $remainingTimeoutSeconds"
            }
        }
        
        # Write response AFTER loop completes (not during loop)
        Write-Progress -Activity $ProgressMessage -Completed
        if ($timedOut) {
            if ($ThrowOnTimeout) {
                throw "Timed out. Using default response: $DefaultResponse"
            }
            Write-Host "$DefaultResponse (Auto-continued)" -ForegroundColor Yellow
        }
        else {
            Write-Host "$response" -ForegroundColor Green
        }
    }
    # find response in AllowedResponses
    if ($AllowedResponses[0].Trim().Length -gt 1) {
        $response = $AllowedResponses | Where-Object { $_.Substring(0, 1) -eq $response.Substring(0, 1) }
        if ($AddNumberToAllowedResponses) {
            $posFirstSpace = $response.IndexOf(" ")
            if ($posFirstSpace -gt 0) {
                $response = $response.Substring($posFirstSpace + 1).Trim()
            }
            else {
                $response = $response.Trim()
            }
            # $response = $response.Split(" ")[1].Trim()
        }
    }

    if ($timedOut) {
        Write-LogMessage "Timed out. Using default response: $DefaultResponse" -Level WARN -QuietMode
    }
    else {
        Write-LogMessage "Response received: $response" -Level INFO -QuietMode
    }
    return $response.ToString().Trim()
}
function Open-FileWithEditor {
    param(
        [Parameter(Mandatory = $true)]
        [string]$FilePath
    )
    $cursor = Get-CommandPathWithFallback -Name "cursor"
    if ($cursor) {
        Write-LogMessage "Opening $FilePath with Cursor" -Level INFO
        Start-Process $cursor -ArgumentList $filePath
    }
    else {
        $code = Get-CommandPathWithFallback -Name "code"
        if ($code) {
            Write-LogMessage "Opening $FilePath with Code" -Level INFO
            Start-Process $code -ArgumentList $FilePath
        }
        else {
            Write-LogMessage "Opening $FilePath with Notepad" -Level INFO
            Start-Process notepad.exe -ArgumentList $FilePath
        }
    }  
}

function Export-RegListResultsToJsonFile {
    param(
        [Parameter(Mandatory = $true)]
        [PSCustomObject[]]$OutputResult,
        [Parameter(Mandatory = $true)]
        [string]$FilePath
    )
    $parentFolder = Split-Path -Path $FilePath -Parent
    if (-not (Test-Path $parentFolder)) {
        New-Item -ItemType Directory -Path $parentFolder | Out-Null
    }
    $OutputResult | ConvertTo-Json -Depth 100 | Set-Content -Path $FilePath
    Write-LogMessage "Results exported to $FilePath" -Level INFO
    $cursor = Get-CommandPathWithFallback -Name "cursor"
    if ($cursor) {
        Write-LogMessage "Opening $FilePath with Cursor" -Level INFO
        Start-Process $cursor -ArgumentList $filePath
    }
    else {
        $code = Get-CommandPathWithFallback -Name "code"
        if ($code) {
            Write-LogMessage "Opening $FilePath with Code" -Level INFO
            Start-Process $code -ArgumentList $filePath
        }
        else {
            Write-LogMessage "Opening $FilePath with Notepad" -Level INFO
            Start-Process notepad.exe -ArgumentList $filePath
        }
    }   
    Start-Process $parentFolder -WindowStyle Normal
}
function Show-RegListResults {
    param(
        [Parameter(Mandatory = $true)]
        [PSCustomObject[]]$result,
        [Parameter(Mandatory = $false)]
        [PSCustomObject[]]$inaccessiblePaths,
        [Parameter(Mandatory = $false)]
        [switch]$OutputJson
    )

    # Determine output format based on number of unique paths
    $uniquePaths = $result | Select-Object -ExpandProperty Path -Unique
    $pathCount = $uniquePaths.Count

    Write-LogMessage "Found $($result.Count) registry entries across $pathCount unique paths" -Level INFO

    # Display inaccessible paths in yellow if any were found
    if ($inaccessiblePaths.Count -gt 0) {
        Write-Host "`nInaccessible Registry Paths:" -ForegroundColor Yellow
        Write-Host "=========================" -ForegroundColor Yellow
        foreach ($path in $inaccessiblePaths) {
            Write-Host "  - $path" -ForegroundColor Yellow
        }
        Write-Host "`n" -ForegroundColor Yellow
    }
  
    if ($OutputJson -or $result.Count -gt 30) {
        Export-RegListResultsToJsonFile -OutputResult $result -FilePath $(Join-Path $(Get-ApplicationDataPath) "Reg-List.json")
    }

    if ($pathCount -gt 0 -and $pathCount -lt 200) {
        # Get first full path
        $firstPath = $result[0].Path

        $numberOfElements = $result.Count
        $widestElement = 0
        foreach ($item in $result) {
            $allElementsInItemAsString = ""
            foreach ($property in $item.PSObject.Properties) {
                $propertyValue = if ($null -ne $property.Value) { $property.Value.ToString() } else { "" }
                $allElementsInItemAsString += $propertyValue.Trim() + " "
            }
            $currentElement = $allElementsInItemAsString.Length
            if ($currentElement -gt $widestElement) {
                $widestElement = $currentElement
            }
            $numberOfElements = $numberOfElements + 1
        }



        # Single folder or no folders - output as Format-List
        if ($widestElement -gt 200) {
            $widestElement = 200
        }
        Write-Host "`n"
        Write-Host ("=" * $widestElement) -ForegroundColor Green
        Write-Host "Content of: $($firstPath):" -ForegroundColor Green
        Write-Host ("=" * $widestElement) -ForegroundColor Green
        if ($result.Count -gt 0) {
            $result | Format-Table -AutoSize -Property Name, Value, DataType, RelativePath
        }
        else {
            Write-LogMessage "No registry entries found matching the search criteria" -Level WARN
        }
    }
}

<#
.SYNOPSIS
    Searches for registry properties based on input parameters.

.DESCRIPTION
    This script searches for registry properties related to the input parameter.
    Supports wildcard patterns (*) in registry paths. Automatically converts registry path formats:
    - HKCU\ to HKCU: format
    - Computer\HKEY_CURRENT_USER\ to HKCU: format (English regedit)
    - Datamaskin\HKEY_CURRENT_USER\ to HKCU: format (Norwegian regedit)
    
    Behavior:
    - If path points to a specific property: lists only that property with datatype and value
    - If path points to a folder: lists all properties in that folder
    - If -Recurse is set: includes all properties in subfolders
    - Always includes datatype and value information for each property
    
    Output format depends on the number of folders found:
    - Multiple folders: ConvertTo-Json
    - Single folder: Format-List

.PARAMETER SearchString
    The registry path or search term to look for. Can be a full registry path, wildcard pattern, regedit copied path, or search term.

.PARAMETER Recurse
    If specified, searches recursively through all subfolders.

.EXAMPLE
    .\Reg-List.ps1 -SearchString "HKCU\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced"
    Searches for properties in the specified registry path.

.EXAMPLE
    .\Reg-List.ps1 -SearchString "HKCU\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced" -Recurse
    Searches recursively through the specified registry path and all subfolders.

.EXAMPLE
    .\Reg-List.ps1 -SearchString "HKCU\Software\Microsoft\Windows\CurrentVersion\Explorer\*" -Recurse
    Searches for all registry keys under Explorer using wildcard pattern.

.EXAMPLE
    .\Reg-List.ps1 -SearchString "HKLM\Software\Microsoft\Windows\CurrentVersion\*" -Recurse
    Searches for all registry keys under CurrentVersion using wildcard pattern.

.EXAMPLE
    .\Reg-List.ps1 -SearchString "Computer\HKEY_CURRENT_USER\Software\Micro Focus\NetExpress\5.1\IDE\Edit Clipboard"
    Searches using a path copied from regedit (English version).

.EXAMPLE
    .\Reg-List.ps1 -SearchString "Datamaskin\HKEY_CURRENT_USER\Software\Micro Focus\NetExpress\5.1\IDE\Edit Clipboard"
    Searches using a path copied from regedit (Norwegian version).

.EXAMPLE
    .\Reg-List.ps1 -SearchString "HKCU\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced\ShowEncryptCompressedColor"
    Lists only the specific property with its datatype and value.

.EXAMPLE
    .\Reg-List.ps1 -SearchString "HKCU\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced" -Recurse
    Lists all properties in the Advanced folder and all subfolders with datatype and value information.

.NOTES
    Author: Geir Helge Starholm, www.dEdge.no
#>
function Get-RegListSearchResults {
    param(
        [Parameter(Mandatory = $true)]
        [string]$SearchString,
        [Parameter(Mandatory = $false)]
        [switch]$Recurse,
        [Parameter(Mandatory = $false)]
        [switch]$OutputJson

    )


    function Convert-RegistryPath {
        param(
            [string]$SearchString,
            [bool]$containsWildcards
        )
    
        $convertedPath = $SearchString
    
        try {
            # Handle regedit copied paths (Computer\HKEY_CURRENT_USER\... or Datamaskin\HKEY_CURRENT_USER\...)
            if (($SearchString.StartsWith("Computer\HKEY_CURRENT_USER\") -or 
                    $SearchString.StartsWith("Computer\HKEY_LOCAL_MACHINE\") -or 
                    $SearchString.StartsWith("Computer\HKEY_CLASSES_ROOT\") -or 
                    $SearchString.StartsWith("Computer\HKEY_USERS\") -or 
                    $SearchString.StartsWith("Computer\HKEY_CURRENT_CONFIG\") -or
                    $SearchString.StartsWith("Datamaskin\HKEY_CURRENT_USER\") -or 
                    $SearchString.StartsWith("Datamaskin\HKEY_LOCAL_MACHINE\") -or 
                    $SearchString.StartsWith("Datamaskin\HKEY_CLASSES_ROOT\") -or 
                    $SearchString.StartsWith("Datamaskin\HKEY_USERS\") -or 
                    $SearchString.StartsWith("Datamaskin\HKEY_CURRENT_CONFIG\"))) {
            
                # Remove Computer\ or Datamaskin\ prefix
                if ($SearchString.StartsWith("Computer\")) {
                    $pathWithoutPrefix = $SearchString.Substring(9)  # Remove "Computer\"
                }
                elseif ($SearchString.StartsWith("Datamaskin\")) {
                    $pathWithoutPrefix = $SearchString.Substring(11)  # Remove "Datamaskin\"
                }
            
                # Convert full hive names to short forms
                $pathWithoutPrefix = $pathWithoutPrefix.Replace("HKEY_CURRENT_USER\", "HKCU:")
                $pathWithoutPrefix = $pathWithoutPrefix.Replace("HKEY_LOCAL_MACHINE\", "HKLM:")
                $pathWithoutPrefix = $pathWithoutPrefix.Replace("HKEY_CLASSES_ROOT\", "HKCR:")
                $pathWithoutPrefix = $pathWithoutPrefix.Replace("HKEY_USERS\", "HKU:")
                $pathWithoutPrefix = $pathWithoutPrefix.Replace("HKEY_CURRENT_CONFIG\", "HKCC:")
            
                $convertedPath = $pathWithoutPrefix
                Write-LogMessage "Converted regedit path from $SearchString to $convertedPath" -Level INFO
                Write-LogMessage "Path after hive: '$($convertedPath.Substring(5))'" -Level INFO
            }
            # Handle short registry path format (HKCU\ to HKCU:)
            elseif ($SearchString.StartsWith("HKCU\") -or $SearchString.StartsWith("HKLM\") -or $SearchString.StartsWith("HKCR\") -or $SearchString.StartsWith("HKU\") -or $SearchString.StartsWith("HKCC\")) {
                $convertedPath = $SearchString.Replace("HKCU\", "HKCU:")
                $convertedPath = $convertedPath.Replace("HKLM\", "HKLM:")
                $convertedPath = $convertedPath.Replace("HKCR\", "HKCR:")
                $convertedPath = $convertedPath.Replace("HKU\", "HKU:")
                $convertedPath = $convertedPath.Replace("HKCC\", "HKCC:")
                Write-LogMessage "Converted registry path from $SearchString to $convertedPath" -Level INFO
                Write-LogMessage "Original path: '$SearchString', Converted path: '$convertedPath'" -Level INFO
            }
        }
        catch {
            Write-LogMessage "Error converting registry path format" -Level ERROR -Exception $_
            $convertedPath = $SearchString
        }
    
        return $convertedPath
    }

    function Test-RegistryPath {
        param(
            [string]$convertedPath
        )
    
        $isValidRegistryPath = $false
        $isRegistryProperty = $false
        $registryPath = $null
        $searchTerm = $null
        $maxValidPath = $null
    
        try {
            # First check if it's a registry key (folder)
            if (Test-Path -Path $convertedPath -PathType Container -ErrorAction Stop) {
                $isValidRegistryPath = $true
                $registryPath = $convertedPath
                Write-LogMessage "Valid registry key (folder) detected: $registryPath" -Level INFO
            }
            # If not a key, check if it's a registry property (value)
            elseif (Test-Path -Path $convertedPath -ErrorAction Stop) {
                $isRegistryProperty = $true
                $registryPath = $convertedPath
                Write-LogMessage "Valid registry property (value) detected: $registryPath" -Level INFO
            }
            else {
                # Try to find the maximum valid path from the search string
                Write-LogMessage "Path not valid, attempting to find maximum valid path" -Level INFO
                $pathParts = $convertedPath -split '\\'
                $currentPath = ""
            
                foreach ($part in $pathParts) {
                    try {
                        $testPath = if ($currentPath -eq "") { $part } else { "$currentPath\$part" }
                    
                        if (Test-Path -Path $testPath -ErrorAction SilentlyContinue) {
                            $maxValidPath = $testPath
                            $currentPath = $testPath
                        }
                        else {
                            # Found the point where path becomes invalid, use remaining parts as search term
                            $remainingParts = $pathParts[($pathParts.IndexOf($part))..($pathParts.Length - 1)]
                            $searchTerm = $remainingParts -join '\'
                            break
                        }
                    }
                    catch {
                        Write-LogMessage "Error testing path part: $part" -Level WARN -Exception $_
                        break
                    }
                }
            
                if ($maxValidPath) {
                    $isValidRegistryPath = $true
                    $registryPath = $maxValidPath
                    Write-LogMessage "Found maximum valid path: $registryPath" -Level INFO
                    Write-LogMessage "Using remaining part as search term: $searchTerm" -Level INFO
                }
            }
        }
        catch {
            Write-LogMessage "Search string is not a valid registry path, treating as search term" -Level INFO
        }
    
        return [PSCustomObject]@{
            IsValidRegistryPath = $isValidRegistryPath
            IsRegistryProperty  = $isRegistryProperty
            RegistryPath        = $registryPath
            SearchTerm          = $searchTerm
            MaxValidPath        = $maxValidPath
        }
    }

    function Add-FolderEntry {
        param(
            [string]$folderPath,
            [string]$folderName
        )
        $returnObject = [PSCustomObject]@{
            result            = @()
            inaccessiblePaths = @()
        }
        try {
            # Calculate relative path from the registry hive
            $relativePath = $folderPath -replace "^.*?::", "" -replace "^.*?:", ""
        
            $returnObject.result = @( [PSCustomObject]@{
                    Path         = $folderPath
                    Name         = $folderName
                    Value        = $null
                    DataType     = "Folder"
                    KeyPath      = $folderPath
                    RelativePath = $relativePath
                    ItemType     = "Folder"
                })
            
        }
        catch {
            Write-LogMessage "Error adding folder entry: $folderPath" -Level WARN -Exception $_
            $returnObject.inaccessiblePaths += $folderPath
        }
        return $returnObject
    }

    function Get-SingleRegistryProperty {
        param(
            [string]$registryPath
        )
    
        Write-LogMessage "Processing single registry property: $registryPath" -Level INFO
        $returnObject = [PSCustomObject]@{
            result            = @()
            inaccessiblePaths = @()
        }

        try {
            $propertyName = Split-Path -Path $registryPath -Leaf
            $keyPath = Split-Path -Path $registryPath -Parent
            $propertyValue = Get-ItemPropertyValue -Path $keyPath -Name $propertyName -ErrorAction SilentlyContinue
            $propertyInfo = Get-ItemProperty -Path $keyPath -Name $propertyName -ErrorAction SilentlyContinue

            if ($null -ne $propertyValue) {
                # Calculate relative path from the registry hive
                $relativePath = $registryPath -replace "^.*?::", "" -replace "^.*?:", ""
            
                $returnObject.result += [PSCustomObject]@{
                    Path         = $registryPath
                    Name         = $propertyName
                    Value        = $propertyValue
                    DataType     = if ($propertyInfo) { $propertyInfo.PSObject.Properties[$propertyName].TypeNameOfValue } else { "Unknown" }
                    KeyPath      = $keyPath
                    RelativePath = $relativePath
                    ItemType     = "Property"
                }
            }
        }
        catch {
            Write-LogMessage "Inaccessible registry property: ${registryPath} - $($_.Exception.Message)" -Level WARN -Exception $_
            $returnObject.inaccessiblePaths += $registryPath
        }
        return $returnObject
    }

    function Get-RegistryProperties {
        param(
            [string]$searchPath,
            [bool]$Recurse,
            [string]$filterTerm = $null
        )
    
        Write-LogMessage "Searching in registry path: $searchPath" -Level INFO
        $returnObject = [PSCustomObject]@{
            result            = @()
            inaccessiblePaths = @()
        }
        try {
            # First, get properties from the current path
            $currentProperties = Get-ItemProperty -Path $searchPath -ErrorAction SilentlyContinue
            if ($currentProperties) {
                foreach ($prop in $currentProperties.PSObject.Properties) {
                    if ($prop.Name -notin @("PSPath", "PSParentPath", "PSChildName", "PSDrive", "PSProvider")) {
                        # Apply search term filter if specified
                        $shouldInclude = $true
                        if ($filterTerm) {
                            $propValue = if ($null -ne $prop.Value) { $prop.Value.ToString() } else { "" }
                            $shouldInclude = ($prop.Name -like "*$filterTerm*" -or 
                                $propValue -like "*$filterTerm*")
                        }
                    
                        if ($shouldInclude) {
                            # Calculate relative path from the registry hive
                            $relativePath = $searchPath -replace "^.*?::", "" -replace "^.*?:", ""
                        
                            $returnObject.result += [PSCustomObject]@{
                                Path         = $searchPath
                                Name         = $prop.Name
                                Value        = $prop.Value
                                DataType     = $prop.TypeNameOfValue
                                KeyPath      = $searchPath
                                RelativePath = $relativePath
                                ItemType     = "Property"
                            }
                        }
                    }
                }
            }
            
            if ($Recurse) {
                $childItems = Get-ChildItem -Path $searchPath -Recurse -ErrorAction SilentlyContinue
            }
            else {
                $childItems = Get-ChildItem -Path $searchPath -ErrorAction SilentlyContinue
            }
        
            if ($childItems) {
                foreach ($item in $childItems) {
                    try {
                        # Add folder entry if it's a container
                        if ($item.PSIsContainer) {
                            $shouldIncludeFolder = $true
                            if ($filterTerm) {
                                $shouldIncludeFolder = $item.Name -like "*$filterTerm*"
                            }
                            if ($shouldIncludeFolder) {
                                $folderResult = Add-FolderEntry -folderPath $item.PSPath -folderName $item.Name
                                $returnObject.result += $folderResult.result[0]
                                $returnObject.inaccessiblePaths += $folderResult.inaccessiblePaths
                            }
                        }
                
                        $properties = Get-ItemProperty -Path $item.PSPath -ErrorAction SilentlyContinue
                        if ($properties) {
                            # Extract individual properties with datatype and value
                            foreach ($prop in $properties.PSObject.Properties) {
                                if ($prop.Name -notin @("PSPath", "PSParentPath", "PSChildName", "PSDrive", "PSProvider")) {
                                    # Apply search term filter if specified
                                    $shouldInclude = $true
                                    if ($filterTerm) {
                                        $propValue = if ($null -ne $prop.Value) { $prop.Value.ToString() } else { "" }
                                        $shouldInclude = ($prop.Name -like "*$filterTerm*" -or 
                                            $propValue -like "*$filterTerm*" -or 
                                            $item.Name -like "*$filterTerm*")
                                    }
                            
                                    if ($shouldInclude) {
                                        # Calculate relative path from the registry hive
                                        $relativePath = $item.PSPath -replace "^.*?::", "" -replace "^.*?:", ""
                                
                                        $returnObject.result += [PSCustomObject]@{
                                            Path         = $item.PSPath
                                            Name         = $prop.Name
                                            Value        = $prop.Value
                                            DataType     = $prop.TypeNameOfValue
                                            KeyPath      = $item.PSPath
                                            RelativePath = $relativePath
                                            ItemType     = "Property"
                                        }
                                    }
                                }
                            }
                        }
                    }
                    catch {
                        $returnObject.inaccessiblePaths += $item.PSPath
                        Write-LogMessage "Inaccessible registry path: $($item.PSPath) - $($_.Exception.Message)" -Level WARN -Exception $_
                    }
                }
            }
        }
        catch {
            Write-LogMessage "Error in registry search" -Level ERROR -Exception $_
        }
        return $returnObject
    }

    function Get-RegistryPropertiesFromPath {
        param(
            [string]$searchPath,
            [string]$filterTerm = $null
        )
    
        $returnObject = [PSCustomObject]@{
            result            = @()
            inaccessiblePaths = @()
        }
        
        try {
            $properties = Get-ItemProperty -Path $searchPath -ErrorAction Stop
            if ($properties) {
                # Extract individual properties with datatype and value
                foreach ($prop in $properties.PSObject.Properties) {
                    if ($prop.Name -notin @("PSPath", "PSParentPath", "PSChildName", "PSDrive", "PSProvider")) {
                        # Apply search term filter if specified
                        $shouldInclude = $true
                        if ($filterTerm) {
                            $propValue = if ($null -ne $prop.Value) { $prop.Value.ToString() } else { "" }
                            $shouldInclude = ($prop.Name -like "*$filterTerm*" -or 
                                $propValue -like "*$filterTerm*")
                        }
                    
                        if ($shouldInclude) {
                            # Calculate relative path from the registry hive
                            $relativePath = $searchPath -replace "^.*?::", "" -replace "^.*?:", ""
                        
                            $returnObject.result += [PSCustomObject]@{
                                Path         = $searchPath
                                Name         = $prop.Name
                                Value        = $prop.Value
                                DataType     = $prop.TypeNameOfValue
                                KeyPath      = $searchPath
                                RelativePath = $relativePath
                                ItemType     = "Property"
                            }
                        }
                    }
                }
            }
            else {
                # No properties found, check if this is a folder and list subfolders
                if (Test-Path -Path $searchPath -PathType Container -ErrorAction SilentlyContinue) {
                    Write-LogMessage "No properties found in $searchPath, listing subfolders" -Level INFO
                    
                    # Add the folder itself as an entry
                    $relativePath = $searchPath -replace "^.*?::", "" -replace "^.*?:", ""
                    $folderName = Split-Path -Path $searchPath -Leaf
                    
                    # $returnObject.result += [PSCustomObject]@{
                    #     Path         = $searchPath
                    #     Name         = $folderName
                    #     Value        = $null
                    #     DataType     = "Folder"
                    #     KeyPath      = $searchPath
                    #     RelativePath = $relativePath
                    #     ItemType     = "Folder"
                    # }
                    
                    # List subfolders
                    try {
                        $subfolders = Get-ChildItem -Path $searchPath -ErrorAction SilentlyContinue | Where-Object { $_.PSIsContainer }
                        foreach ($subfolder in $subfolders) {
                            $shouldIncludeSubfolder = $true
                            if ($filterTerm) {
                                $shouldIncludeSubfolder = $subfolder.Name -like "*$filterTerm*"
                            }
                            
                            if ($shouldIncludeSubfolder) {
                                $subfolderRelativePath = $subfolder.PSPath -replace "^.*?::", "" -replace "^.*?:", ""
                                
                                $returnObject.result += [PSCustomObject]@{
                                    Path         = $subfolder.PSPath
                                    Name         = $subfolder.PSChildName
                                    Value        = $null
                                    DataType     = "Folder"
                                    KeyPath      = ""
                                    RelativePath = "."
                                    ItemType     = "Folder"
                                }
                            }
                        }
                    }
                    catch {
                        Write-LogMessage "Error listing subfolders in ${searchPath}: $($_.Exception.Message)" -Level WARN -Exception $_
                    }
                }
            }
        }
        catch {
            $returnObject.inaccessiblePaths += $searchPath
            Write-LogMessage "Inaccessible registry path: ${searchPath} - $($_.Exception.Message)" -Level WARN -Exception $_
        }
        return $returnObject
    }

    function Search-RegistryHives {
        param(
            [string]$SearchString,
            [bool]$Recurse
        )
    
        Write-LogMessage "Searching for registry entries containing: $SearchString" -Level INFO
    
        $returnObject = [PSCustomObject]@{
            result            = @()
            inaccessiblePaths = @()
        }
        
        # Define common registry hives to search
        $registryHives = @(
            "HKCU:",
            "HKLM:",
            "HKCR:",
            "HKU:",
            "HKCC:"
        )
    
        foreach ($hive in $registryHives) {
            try {
                Write-LogMessage "Searching in registry hive: ${hive}" -Level INFO
            
                if ($Recurse) {
                    $items = Get-ChildItem -Path $hive -Recurse -ErrorAction SilentlyContinue | Where-Object {
                        $_.PSPath -like "*$SearchString*" -or $_.Name -like "*$SearchString*"
                    }
                }
                else {
                    $items = Get-ChildItem -Path $hive -ErrorAction SilentlyContinue | Where-Object {
                        $_.PSPath -like "*$SearchString*" -or $_.Name -like "*$SearchString*"
                    }
                }
            
                if ($items) {
                    foreach ($item in $items) {
                        try {
                            # Add folder entry if it's a container
                            if ($item.PSIsContainer) {
                                $folderResult = Add-FolderEntry -folderPath $item.PSPath -folderName $item.Name
                                $returnObject.result += $folderResult.result[0]
                                $returnObject.inaccessiblePaths += $folderResult.inaccessiblePaths
                            }
                    
                            $properties = Get-ItemProperty -Path $item.PSPath -ErrorAction SilentlyContinue
                            if ($properties) {
                                # Extract individual properties with datatype and value
                                foreach ($prop in $properties.PSObject.Properties) {
                                    if ($prop.Name -notin @("PSPath", "PSParentPath", "PSChildName", "PSDrive", "PSProvider")) {

                                        # Calculate relative path from the registry hive
                                        $relativePath = $item.PSPath -replace "^.*?::", "" -replace "^.*?:", ""
                                
                                        $returnObject.result += [PSCustomObject]@{
                                            Path         = $item.PSPath
                                            Name         = $prop.Name
                                            Value        = $prop.Value
                                            DataType     = $prop.TypeNameOfValue
                                            KeyPath      = $item.PSPath
                                            RelativePath = $relativePath
                                            ItemType     = "Property"
                                        }
                                    }
                                }
                            }
                        }
                        catch {
                            $returnObject.inaccessiblePaths += $item.PSPath
                            Write-LogMessage "Inaccessible registry path: $($item.PSPath) - $($_.Exception.Message)" -Level WARN -Exception $_
                        }
                    }
                }
            }
            catch {
                Write-LogMessage "Error searching in registry hive ${hive}: $($_.Exception.Message)" -Level WARN -Exception $_
            }
        }
        return $returnObject
    }

   
    # Main execution
    try {
        Write-LogMessage "Starting registry search for: $SearchString" -Level INFO
        
    
        # Check if search string contains wildcards
        $containsWildcards = $SearchString.Contains("*")
    
        # Convert registry path format if needed
        $convertedPath = Convert-RegistryPath -SearchString $SearchString -containsWildcards $containsWildcards
    
        # Test if the converted path is a valid registry path
        $pathInfo = Test-RegistryPath -convertedPath $convertedPath

        $returnObject = [PSCustomObject]@{
            result            = @()
            inaccessiblePaths = @()
        }
    
        if ($pathInfo.IsRegistryProperty) {
            # Handle single registry property (value)
            $returnObject = Get-SingleRegistryProperty -registryPath $pathInfo.RegistryPath
        }
        elseif ($pathInfo.IsValidRegistryPath -or $containsWildcards) {
            # Search in specific registry path or with wildcards
            $searchPath = if ($containsWildcards) { $convertedPath } else { $pathInfo.RegistryPath }
            $filterTerm = if ($pathInfo.SearchTerm) { $pathInfo.SearchTerm } else { $null }
        
            if ($containsWildcards) {
                # Handle wildcard patterns
                Write-LogMessage "Wildcard pattern detected, using Get-ChildItem with wildcards" -Level INFO
                $returnObject = Get-RegistryProperties -searchPath $searchPath -Recurse $Recurse -filterTerm $filterTerm
            }
            else {
                # Handle exact path (registry key/folder)
                if ($Recurse) {
                    $returnObject = Get-RegistryProperties -searchPath $searchPath -Recurse $true -filterTerm $filterTerm
                }
                else {
                    $returnObject = Get-RegistryPropertiesFromPath -searchPath $searchPath -filterTerm $filterTerm
                }
            }
        }
        else {
            # Search for registry entries containing the search string
            $returnObject = Search-RegistryHives -SearchString $SearchString -Recurse $Recurse
        }
        if ($OutputJson) {
            Export-RegListResultsToJsonFile -OutputResult $returnObject.result -FilePath $(Join-Path $(Get-ApplicationDataPath) "Reg-List.json")
        }
    
        return $returnObject
    }
    catch {
        Write-LogMessage "Error during registry search: $($_.Exception.Message)" -Level ERROR -Exception $_
        return [PSCustomObject]@{
            result            = @()
            inaccessiblePaths = @()
        }
    }
    finally {
        Write-LogMessage "Registry search completed" -Level INFO
    }
}


<#
.SYNOPSIS
    Logs RDP admin connections with source machine names for security auditing
.DESCRIPTION
    Monitors Windows Security Event Log for RDP logon events and logs admin connections
    with source machine information using the existing Write-LogMessage infrastructure
.AUTHOR
    Geir Helge Starholm, www.dEdge.no
#>

function Find-RdpConnectedMachineAndUserInfo {
    <#
    .SYNOPSIS
        Gets RDP connection information including source machine names for admin users
    .DESCRIPTION
        Queries Windows Security Event Log for RDP logon events and returns information
        about admin connections with source machine details for security auditing
    .PARAMETER HoursBack
        Number of hours to look back for RDP events (default: 24)
    .PARAMETER MaxEvents
        Maximum number of events to process (default: 100)
    .PARAMETER LogResults
        Whether to log the results using Write-LogMessage (default: true)
    .EXAMPLE
        Find-RdpConnectedMachineAndUserInfo
        # Gets RDP admin connections from last 24 hours
    .EXAMPLE
        Find-RdpConnectedMachineAndUserInfo -HoursBack 48 -MaxEvents 200
        # Gets RDP admin connections from last 48 hours, max 200 events
    .EXAMPLE
        Find-RdpConnectedMachineAndUserInfo -LogResults $false
        # Gets RDP admin connections but doesn't log to file
    .AUTHOR
        Geir Helge Starholm, www.dEdge.no
    #>
    
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $false)]
        [int]$HoursBack = 24,
        
        [Parameter(Mandatory = $false)]
        [int]$MaxEvents = 100,
        
        [Parameter(Mandatory = $false)]
        [bool]$LogResults = $true
    )

    $startTime = (Get-Date).AddHours(-$HoursBack)
    Write-LogMessage "Checking RDP admin connections from last $HoursBack hours (since $($startTime.ToString('yyyy-MM-dd HH:mm:ss')))" -Level INFO
    
    $results = @()
    
    try {
        # Event ID 4624 = Successful logon
        # LogonType 10 = Remote Interactive (RDP)
        # LogonType 3 = Network (sometimes used for RDP)
        $logonEvents = Get-WinEvent -FilterHashtable @{
            LogName   = 'Security'
            ID        = 4624
            StartTime = $startTime
        } -MaxEvents $MaxEvents -ErrorAction SilentlyContinue
        
        foreach ($event in $logonEvents) {
            $xml = [xml]$event.ToXml()
            $eventData = @{}
            
            # Parse event data
            foreach ($data in $xml.Event.EventData.Data) {
                $eventData[$data.Name] = $data.'#text'
            }
            
            # Check if it's an RDP connection (LogonType 10 or 3)
            if ($eventData.LogonType -in @('10', '3')) {
                $userName = $eventData.TargetUserName
                $domain = $eventData.TargetDomainName
                $sourceIP = $eventData.IpAddress
                $sourceMachine = $eventData.WorkstationName
                $logonTime = $event.TimeCreated
                
                # Check if user is admin
                $isAdmin = $false
                try {
                    $userGroups = Get-ADUser -Identity "$domain\$userName" -Properties MemberOf -ErrorAction SilentlyContinue
                    if ($userGroups) {
                        $adminGroups = @('Domain Admins', 'Enterprise Admins', 'Administrators', 'Schema Admins')
                        $isAdmin = $userGroups.MemberOf | Where-Object { 
                            $adminGroups -contains (Get-ADGroup -Identity $_ -ErrorAction SilentlyContinue).Name 
                        }
                    }
                }
                catch {
                    # If AD lookup fails, check local admin groups
                    $localAdmins = Get-LocalGroupMember -Group "Administrators" -ErrorAction SilentlyContinue
                    $isAdmin = $localAdmins | Where-Object { $_.Name -eq "$domain\$userName" }
                }
                
                if ($isAdmin) {
                    $result = [PSCustomObject]@{
                        EventType     = 'RDP_ADMIN_LOGON'
                        UserName      = "$domain\$userName"
                        SourceIP      = $sourceIP
                        SourceMachine = $sourceMachine
                        LogonTime     = $logonTime
                        LogonType     = $eventData.LogonType
                        ProcessName   = $eventData.ProcessName
                        EventId       = $event.Id
                    }
                    $results += $result
                    
                    if ($LogResults) {
                        $logMessage = "ADMIN RDP CONNECTION: User '$($result.UserName)' connected from machine '$($result.SourceMachine)' (IP: $($result.SourceIP)) at $($result.LogonTime.ToString('yyyy-MM-dd HH:mm:ss'))"
                        Write-LogMessage $logMessage -Level INFO
                        
                        # Also log to a dedicated admin access log
                        $adminLogPath = "$env:OptPath\data\AllPwshLog\AdminAccess_$(Get-Date -Format 'yyyyMMdd').log"
                        $adminLogEntry = "$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss') | ADMIN_RDP | $($result.UserName) | $($result.SourceMachine) | $($result.SourceIP) | $($result.LogonTime.ToString('yyyy-MM-dd HH:mm:ss'))"
                        Add-Content -Path $adminLogPath -Value $adminLogEntry -Force
                    }
                }
            }
        }
        
        # Also check for failed logon attempts (Event ID 4625)
        $failedLogonEvents = Get-WinEvent -FilterHashtable @{
            LogName   = 'Security'
            ID        = 4625
            StartTime = $startTime
        } -MaxEvents $MaxEvents -ErrorAction SilentlyContinue
        
        foreach ($event in $failedLogonEvents) {
            $xml = [xml]$event.ToXml()
            $eventData = @{}
            
            foreach ($data in $xml.Event.EventData.Data) {
                $eventData[$data.Name] = $data.'#text'
            }
            
            if ($eventData.LogonType -in @('10', '3')) {
                $result = [PSCustomObject]@{
                    EventType     = 'RDP_LOGON_FAILED'
                    UserName      = "$($eventData.TargetDomainName)\$($eventData.TargetUserName)"
                    SourceIP      = $eventData.IpAddress
                    SourceMachine = $eventData.WorkstationName
                    LogonTime     = $event.TimeCreated
                    LogonType     = $eventData.LogonType
                    FailureReason = $eventData.SubStatus
                    EventId       = $event.Id
                }
                $results += $result
                
                if ($LogResults) {
                    $logMessage = "FAILED RDP ATTEMPT: User '$($result.UserName)' failed to connect from machine '$($result.SourceMachine)' (IP: $($result.SourceIP)) at $($result.LogonTime.ToString('yyyy-MM-dd HH:mm:ss')) - Reason: $($result.FailureReason)"
                    Write-LogMessage $logMessage -Level WARN
                }
            }
        }
        
        Write-LogMessage "Found $($results.Count) RDP events (admin connections and failed attempts)" -Level INFO
        
        # Return the results
        return $results
    }
    catch {
        Write-LogMessage "Error checking RDP admin connections: $($_.Exception.Message)" -Level ERROR -Exception $_
        return @()
    }
}



function Get-CobolExecutablePaths {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Version,
        # [Parameter(Mandatory = $false)]
        # [ValidateSet("x64", "x86", "Any")]
        # [string]$Architecture = "",
        [bool]$ForceServer = $false,
        [Parameter(Mandatory = $false)]
        [switch]$FormatPsCustomObject,
        [Parameter(Mandatory = $false)]
        [switch]$Quiet
    )
    if ($ForceServer) {
        $programFilesPaths = @(
            @{Path = "C:\Program Files"; Architecture = "x64" }
        )   
        $potentialPaths = @(
            @{
                Path     = "Micro Focus\Server 5.1"            # Server 5.1
                Version  = "MF"
                ToolType = "RUNTIME"
                ExeList  = @("runw.exe", "run.exe")
                Group    = "Standard Server"
            }
        )
        $subPaths = @(
            # Base paths
            @{
                Path = "bin"
                Type = "Bin"
            }
        )
    }
    else {
        $programFilesPaths = @(
            @{Path = "C:\Program Files"; Architecture = "x64" },
            @{Path = "C:\Program Files (x86)"; Architecture = "Any" }
        )
                
        $potentialPaths = @(
            @{
                Path     = "Micro Focus\Visual COBOL\Base"           # Visual COBOL
                Version  = "VC"
                ToolType = "IDE"
                ExeList  = @("runw.exe", "run.exe", "cobol.exe")
                Group    = "Visual COBOL"
            },
            @{
                Path     = "Micro Focus\Visual COBOL\DialogSystem"           # Visual COBOL
                Version  = "VC"
                ToolType = "DSIDE"
                ExeList  = @("dswin.exe")
                Group    = "Visual COBOL"
            },
            @{
                Path     = "Micro Focus\Enterprise Developer\Base"   # Enterprise Developer
                Version  = "MF"
                ToolType = "IDE"
                ExeList  = @("runw.exe", "run.exe", "cobol.exe")
                Group    = "Enterprise Developer"
            },
            @{
                Path     = "Micro Focus\Enterprise Developer\DialogSystem"   # Enterprise Developer
                Version  = "MF"
                ToolType = "DSIDE"
                ExeList  = @("dswin.exe")
                Group    = "Enterprise Developer"
            },
            @{
                Path     = "Micro Focus\Net Express 5.1\Base"  # Development Tools
                Version  = "MF"
                ToolType = "IDE"
                ExeList  = @("runw.exe", "run.exe", "cobol.exe")
                Group    = "Net Express"
            },
            @{
                Path     = "Micro Focus\Net Express 5.1\DialogSystem"  # Development Tools
                Version  = "MF"
                ToolType = "DSIDE"
                ExeList  = @("dswin.exe")
                Group    = "Net Express"
            },
            @{
                Path     = "Micro Focus\Enterprise Server"      # Enterprise Server
                Version  = "MF" 
                ToolType = "RUNTIME"
                ExeList  = @("runw.exe", "run.exe")
                Group    = "Enterprise Server"
            },
            @{
                Path     = "Micro Focus\Server 5.1"            # Server 5.1
                Version  = "MF"
                ToolType = "RUNTIME"
                ExeList  = @("runw.exe", "run.exe")
                Group    = "Standard Server"
            }
        )
    
        $subPaths = @(
            # Base paths
            @{
                Path = "bin"
                Type = "Bin"
            },
            @{
                Path = "bin64"
                Type = "Bin"
            },
            # @{
            #     Path         = "bin\WIN64"
            #     Type         = "Bin"
            #     Architecture = "x64"
            # },
            @{
                Path         = "lib"
                Type         = "Lib"
                Architecture = "Any"
            },
            @{
                Path         = "lib64"
                Type         = "Lib"
                Architecture = "Any"
            }
            #,
            # @{
            #     Path         = "lib\WIN64"
            #     Type         = "Lib"
            #     Architecture = "x64"
            # }
        )
    }

    # Convert all arrays to PSCustomObject
    $programFilesPaths = [PSCustomObject[]]$programFilesPaths
    $potentialPaths = [PSCustomObject[]]$potentialPaths
    $subPaths = [PSCustomObject[]]$subPaths

    $actualPaths = @()
    foreach ($programFilesPath in $programFilesPaths) {
        foreach ($potentialPath in $potentialPaths) {
            foreach ($subPath in $subPaths) {
                if ($potentialPath.Version -eq $Version) {
                    $actualPath = Join-Path $programFilesPath.Path $potentialPath.Path $subPath.Path
                    if ((Test-Path $actualPath -PathType Container) -or $ForceServer) {
                        Write-LogMessage "Found path $actualPath" -Level INFO -QuietMode:$Quiet

                        $allExeFound = $true
                        $tempExeList = @()
                        try {
                            $tempExeList = $potentialPath.ExeList
                        }
                        catch {
                            $tempExeList = @()
                        }

                        $fullPathExeList = @()
                        if ($actualPath.Contains("\bin")) {
                            foreach ($exe in $tempExeList) {
                                $fullPathExe = Join-Path $actualPath $exe
                                if ((-not (Test-Path $fullPathExe -PathType Leaf)) -and -not $ForceServer) {
                                    Write-LogMessage "Exe $exe not found in path $fullPathExe" -Level WARN -QuietMode:$Quiet
                                    $allExeFound = $false
                                }
                                else {
                                    if ($FormatPsCustomObject) {
                                        $fullPathExeList += [PSCustomObject]@{
                                            Path = $fullPathExe
                                            Name = $exe
                                        }
                                    }
                                    else {
                                        $fullPathExeList += @{
                                            Path = $fullPathExe
                                            Name = $exe
                                        }
                                    }
                                    Write-LogMessage "Exe $exe found in path $actualPath" -Level INFO -QuietMode:$Quiet 
                                }
                            }
                        }

                    
                        if ($allExeFound) {
                            if ( $subPath.Architecture -eq "x64" -or $programFilesPath.Architecture -eq "x64" -or $subPath.Architecture -eq "Any" -or $programFilesPath.Architecture -eq "Any") {
                                $architecture = "x64"
                            }
                            else {
                                $architecture = "x86"
                            }

                            if ($FormatPsCustomObject) {
                                $actualPaths += [PSCustomObject]@{
                                    Version      = $potentialPath.Version
                                    Group        = $potentialPath.Group
                                    BasePath     = $(Join-Path $programFilesPath.Path $potentialPath.Path).ToString().Trim()
                                    Type         = $subPath.Type
                                    Architecture = $architecture
                                    Path         = $actualPath
                                    ExeList      = $fullPathExeList
                                    ToolType     = $potentialPath.ToolType
                                }
                            }
                            else {
                                $actualPaths += @{
                                    Version      = $potentialPath.Version
                                    Group        = $potentialPath.Group
                                    BasePath     = (Join-Path $programFilesPath.Path $potentialPath.Path)
                                    Type         = $subPath.Type
                                    Architecture = $architecture
                                    Path         = $actualPath
                                    ExeList      = $fullPathExeList
                                    ToolType     = $potentialPath.ToolType
                                }
                            } 
                        }
                    }
                }
            }
        }
    }
    # Returns array of hashtables containing Version, BasePath, Type, Architecture and Path
    return $actualPaths
}

function Test-IsServer {
    param(
        [Parameter(Mandatory = $false)]
        [bool]$Quiet = $true
    )
    # Get operating system name using CIM
    $osInfo = Get-CimInstance -ClassName Win32_OperatingSystem
    if (-not $Quiet) {
        Write-Host "Operating System: $($osInfo.Caption)" -ForegroundColor Cyan
        Write-Host ""
    }
    if ($osInfo.Caption -like "*Server*") {
        $isServer = $true
        if (-not $Quiet) {
            Write-Host "Running server configuration" -ForegroundColor Cyan
        }
    }
    else {
        $isServer = $false
        if (-not $Quiet) {
            Write-Host "Running workstation configuration" -ForegroundColor Cyan
        }
    }   
    return $isServer
}
function Test-IsDb2Server {
    param(
        [Parameter(Mandatory = $false)]
        [bool]$Quiet = $true
    )
    if (-not (Test-IsServer -Quiet $Quiet)) {
        return $false
    }
    if (Test-Path -Path "C:\DbInst") {
        $isDb2Server = $true
    }
    else {
        $isDb2Server = $false
    }
    
    return $isDb2Server
}
function Get-GlobalEnvironmentSettings {
    param(
        [Parameter(Mandatory = $false)]
        [string]$OverrideVersion = $null,
        [Parameter(Mandatory = $false)]
        [string]$OverrideDatabase = $null,
        [Parameter(Mandatory = $false)]
        [string]$OverrideCobolObjectPath = $null,
        [Parameter(Mandatory = $false)]
        [switch]$Force
    )
    if ([string]::IsNullOrEmpty($OverrideVersion) -or [string]::IsNullOrEmpty($OverrideDatabase) -or [string]::IsNullOrEmpty($OverrideCobolObjectPath)) {
        $Force = $true
    }
    if ($global:FkEnvironmentSettings -and -not $Force) {
        return $global:FkEnvironmentSettings
    }

    if (-not $Force) {
        $test = Get-Variable -Name "FkEnvironmentSettings" -Scope Global -ErrorAction SilentlyContinue
        if ( $null -ne $test.Value) {
            $test = $global:FkEnvironmentSettings
            $test = $test.Version
            if (-not [string]::IsNullOrEmpty($test) -and $($test.ToUpper() ?? "") -in @("MF", "VC")) {
                return $global:FkEnvironmentSettings
            }
        }
    }

    if ($(Get-LogLevel) -in @("DEBUG", "TRACE")) {
        Write-Host "Getting global environment settings" -ForegroundColor Yellow
    }

    $cobolObjectPath = ""
    $version = ""
    if (-not [string]::IsNullOrEmpty($OverrideVersion)) {
        $version = $OverrideVersion
        $global:CobolVersion = $version
    }
    elseif (-not [string]::IsNullOrEmpty($global:CobolVersion) -and $global:CobolVersion -in @("MF", "VC")) {
        $version = $global:CobolVersion
    }
    else {
        $global:CobolVersion = "MF"
        $version = $global:CobolVersion
    }

    
    if (-not [string]::IsNullOrEmpty($OverrideCobolObjectPath)) {
        $cobolObjectPath = $OverrideCobolObjectPath
        $global:CobolObjectPath = $cobolObjectPath
    }
    elseif (-not [string]::IsNullOrEmpty($global:CobolObjectPath)) {
        $cobolObjectPath = $global:CobolObjectPath
    }
    else {
        $global:CobolObjectPath = "\\DEDGE.fk.no\erpprog\cobnt\"
        $cobolObjectPath = $global:CobolObjectPath
    }
    
    $settings = [PSCustomObject]@{
        DedgePshAppsPath   = ""
        Database        = ""
        CobolObjectPath = $cobolObjectPath
        Version         = $version
        IsServer        = $(Test-IsServer -Quiet $true) 
        Application     = ""
        Environment     = ""
        ScriptPath      = $(Get-FullScriptPath)
        AccessPoint     = $null
    }
    if ($settings.IsServer) {
        Add-member -InputObject $settings -MemberType NoteProperty -Name Application -Value $(Get-ApplicationFromServerName) -Force
        Add-member -InputObject $settings -MemberType NoteProperty -Name Environment -Value $(Get-EnvironmentFromServerName) -Force
    }

    $temp = @(
        $(Get-CobolExecutablePaths -Version $version -FormatPsCustomObject -Quiet)
    )
    $allExeList = $temp | Select-Object -ExpandProperty ExeList
    $allExeList = $allExeList | Where-Object { $_.Name -in @("cobol.exe", "dswin.exe", "run.exe", "runw.exe") } | Select-Object -ExpandProperty Path


    
    
    foreach ($exe in $allExeList) {        
        if ($exe.Contains("cobol.exe")) {
            Add-member -InputObject $settings -MemberType NoteProperty -Name "CobolCompilerExecutable" -Value $exe.ToString() -Force
        }
        elseif ($exe.Contains("dswin.exe")) {
            Add-member -InputObject $settings -MemberType NoteProperty -Name "CobolDsWinExecutable" -Value $exe.ToString() -Force
        }
        elseif ($exe.Contains("run.exe")) {
            Add-member -InputObject $settings -MemberType NoteProperty -Name "CobolRuntimeExecutable" -Value $exe.ToString() -Force
        }
        elseif ($exe.Contains("runw.exe")) {
            Add-member -InputObject $settings -MemberType NoteProperty -Name "CobolWindowsRuntimeExecutable" -Value $exe.ToString() -Force
        }
    }

    Add-member -InputObject $settings -MemberType NoteProperty -Name DedgePshAppsPath -Value "$env:OptPath\DedgePshApps\" -Force

  
    $allDbInfo = Get-DatabasesV2Json | Where-Object { $_.IsActive -eq $true } 
    $currDbInfo = $null
    $currAccessPoint = $null
    


    # Priority 1: OverrideDatabase > Server > Default
    if (-not [string]::IsNullOrEmpty($OverrideDatabase)) {
        foreach ($item in $allDbInfo) {
            $currDbInfo = $item
            foreach ($accessPoint in $currDbInfo.AccessPoints) {
                if ($accessPoint.CatalogName -eq $OverrideDatabase) {
                    $currAccessPoint = $accessPoint
                    break
                }
            }
            if ($currAccessPoint) {
                break
            }
            $currAccessPoint = $null
            $currDbInfo = $null
        }
        if ($currAccessPoint) {
            if ($currDbInfo.PrimaryCatalogName -ne $currAccessPoint.CatalogName) {
                $currAccessPoint = $currDbInfo.AccessPoints | Where-Object { $_.CatalogName -eq $currDbInfo.PrimaryCatalogName } | Select-Object -First 1
            }
            $settings.AccessPoint = $currAccessPoint
        }
    }
    elseif ((Test-IsServer) -and $env:COMPUTERNAME.ToLower() -notlike "*fsp*") {
        $tempDatabase = Get-DatabaseNameFromServerName
        $currDbInfo = $allDbInfo | Where-Object { $_.Database -eq $tempDatabase } 
        $currAccessPoint = $currDbInfo.AccessPoints | Where-Object { $_.CatalogName -eq $currDbInfo.PrimaryCatalogName } | Select-Object -First 1
        if ($currAccessPoint) {
            $settings.AccessPoint = $currAccessPoint
        }
    }
    elseif ((Test-IsServer) -and $env:COMPUTERNAME.ToLower() -like "*fsp*") {
        $scriptPath = Get-FullScriptPath
        if (-not [string]::IsNullOrEmpty($scriptPath) -and $scriptPath.Contains("\_")) {
            $scriptPathSplit = $scriptPath.Split("\_")
            $lastPart = $scriptPathSplit[-1].Split("\")[0]
            $tempDatabase = "FKM$($lastPart.ToUpper())"
            $currDbInfo = $allDbInfo | Where-Object { $_.Database -eq $tempDatabase } 
            $currAccessPoint = $currDbInfo.AccessPoints | Where-Object { $_.CatalogName -eq $currDbInfo.PrimaryCatalogName } | Select-Object -First 1
            if ($currAccessPoint) {
                $settings.AccessPoint = $currAccessPoint
            }
        }
    }
    else {        
        $tempDatabase = "FKMPRD"
        $currDbInfo = $allDbInfo | Where-Object { $_.Database -eq $tempDatabase } 
        $currAccessPoint = $currDbInfo.AccessPoints | Where-Object { $_.CatalogName -eq $currDbInfo.PrimaryCatalogName } | Select-Object -First 1
        if ($currAccessPoint) {
            $settings.AccessPoint = $currAccessPoint
        }
    }
    


    if ($settings.AccessPoint) {
        Add-Member -InputObject $settings -MemberType NoteProperty -Name "DatabaseInternalName" -Value $currDbInfo.Database -Force
        Add-Member -InputObject $settings -MemberType NoteProperty -Name "DatabaseNorwegianDescription" -Value $currDbInfo.NorwegianDescription -Force
        Add-Member -InputObject $settings -MemberType NoteProperty -Name "DatabaseEnglishDescription" -Value $currDbInfo.Description -Force
        Add-Member -InputObject $settings -MemberType NoteProperty -Name "DatabaseServerName" -Value $currDbInfo.ServerName -Force
        Add-Member -InputObject $settings -MemberType NoteProperty -Name "DatabaseProvider" -Value $currDbInfo.Provider -Force
        Add-Member -InputObject $settings -MemberType NoteProperty -Name "DatabaseApplication" -Value $currDbInfo.Application -Force
        Add-Member -InputObject $settings -MemberType NoteProperty -Name "DatabaseEnvironment" -Value $currDbInfo.Environment -Force
    }

    if ($settings.AccessPoint -and -not [string]::IsNullOrEmpty($settings.DatabaseApplication) -and -not [string]::IsNullOrEmpty($settings.DatabaseEnvironment)) {
        $settings.Application = $settings.DatabaseApplication
        $settings.Environment = $settings.DatabaseEnvironment
        $settings.Database = $settings.AccessPoint.CatalogName
    }
    else {
        $settings.Application = "FKM"
        $settings.Environment = "PRD"
        if ([string]::IsNullOrEmpty($settings.Database)) {
            $settings.Database = "BASISPRO"
        }
    }
  
    $settings.CobolObjectPath = switch ($settings.Database) {
        'FKAVDNT' {
            "\\DEDGE.fk.no\erputv\Utvikling\fkavd\nt\"
        }
        'BASISTST' {
            "\\DEDGE.fk.no\erpprog\cobtst\"
        }
        'BASISVFT' {
            "\\DEDGE.fk.no\erpprog\cobtst\cobvft\"
        }
        'BASISVFK' {
            "\\DEDGE.fk.no\erpprog\cobtst\cobvfk\"
        }
        'BASISMIG' {
            "\\DEDGE.fk.no\erpprog\cobtst\cobmig\"
        }
        'BASISSIT' {
            "\\DEDGE.fk.no\erpprog\cobtst\cobsit\"
        }
        'BASISPER' {
            "\\DEDGE.fk.no\erpprog\cobtst\cobper\"
        }
        'BASISFUT' {
            "\\DEDGE.fk.no\erpprog\cobtst\cobfut\"
        }
        'BASISKAT' {
            "\\DEDGE.fk.no\erpprog\cobtst\cobkat\"
        }
        'BASISRAP' {
            "\\DEDGE.fk.no\erpprog\cobtst\cobrap\"
        }
        'BASISPRO' {
            "\\DEDGE.fk.no\erpprog\cobnt\"
        }
        'FKNTOTST' {
            "\\DEDGE.fk.no\erpprog\cobtst\"
        }
        'FKNTOTPRD' {
            "\\DEDGE.fk.no\erpprog\cobprd\"
        }
        'FKKONTO' {
            "\\DEDGE.fk.no\erpprog\cobnt\"
        }
        'FKNTOTDEV' {
            "\\DEDGE.fk.no\erputv\Utvikling\fkavd\nt\"
        }
        default {
            "\\DEDGE.fk.no\erpprog\cobnt\"
        }
    }
    # If server is an App server and environment is 3 characters long, find the folder in the App server
    if (($settings.IsServer) -and ($env:COMPUTERNAME.ToUpper().EndsWith("-APP")) -and $settings.Environment.Length -eq 3) {
        $findFolderName = "COB$($settings.Environment)"

        # IMPORTANT:
        # - We must NOT create COB<ENV> folders as a side-effect of reading settings.
        # - `Find-ExistingFolder` will create the folder if it is missing, regardless of `-SkipRecreateFolders`.
        # - Therefore, we only *search* for an existing folder and only override when it already exists.
        # - Additionally: The COB<ENV> folder must contain enough compiled objects to be considered valid.
        #   Requirement: at least 100 *.int files (recursively) before we use it.
        $validDrives = Find-ValidDrives
        $foundFolderPath = $null
        foreach ($drive in $validDrives) {
            $candidatePath = "$($drive):\$($findFolderName)"
            if (Test-Path -Path $candidatePath -PathType Container) {
                $foundFolderPath = $candidatePath
                break
            }
        }

        if (-not [string]::IsNullOrEmpty($foundFolderPath)) {
            $intFileCount = 0
            try {
                $intFileCount = @(Get-ChildItem -Path $foundFolderPath -Filter "*.int" -File -Recurse -ErrorAction SilentlyContinue).Count
            }
            catch {
                Write-LogMessage "Failed counting *.int files in $($foundFolderPath): $($_.Exception.Message)" -Level DEBUG
                $intFileCount = 0
            }

            if ($intFileCount -ge 100) {
                Write-LogMessage "Using existing $($findFolderName) folder: $($foundFolderPath) (intCount=$($intFileCount))" -Level DEBUG
                if (-not $foundFolderPath.EndsWith("\")) {
                    $foundFolderPath = "$($foundFolderPath)\"
                }
                $settings.CobolObjectPath = $foundFolderPath
            }
            else {
                Write-LogMessage "$($findFolderName) exists at $($foundFolderPath) but only has $($intFileCount) *.int files; keeping default CobolObjectPath: $($settings.CobolObjectPath)" -Level DEBUG
            }
        }
        else {
            Write-LogMessage "$($findFolderName) folder not found; keeping default CobolObjectPath: $($settings.CobolObjectPath)" -Level DEBUG
        }
    }

    $ediStandardPath = "\\DEDGE.fk.no\ERPdata\EDI"
    Add-Member -InputObject $settings -MemberType NoteProperty -Name "EdiStandardPath" -Value $ediStandardPath -Force
    if ($settings.Application -eq "FKM") {
        $d365Path = ""
        switch ($settings.Environment) {
            "DEV" {
                $d365Path = "C:\TempFk\d365\DEV"
                if (-not (Test-Path -Path $d365Path -PathType Container)) {
                    New-Item -ItemType Directory -Path $d365Path -Force | Out-Null
                }
            }
            "TST" {
                $d365Path = "C:\TempFk\d365\TST"
                if (-not (Test-Path -Path $d365Path -PathType Container)) {
                    New-Item -ItemType Directory -Path $d365Path -Force | Out-Null
                }
            }
            "VFK" {
                $d365Path = "$($ediStandardPath)\d365\varefaks\int"
            }
            "VFT" {
                $d365Path = "$($ediStandardPath)\d365\vareftest\int"
            }
            "SIT" {
                $d365Path = "$($ediStandardPath)\d365\KAT\int"
            }
            "KAT" {
                $d365Path = "$($ediStandardPath)\d365\KAT\int"
            }
            "MIG" {
                $d365Path = "$($ediStandardPath)\d365\fkaperformance\int"
            }
            "FUT" {
                $d365Path = "$($ediStandardPath)\d365\funksjonstest\int"
            }
            "PER" {
                $d365Path = "$($ediStandardPath)\d365\fkaperformance\int"
            }
            "PRD" {
                $d365Path = "$($ediStandardPath)\d365\prod\int"
            }
            default {
                $d365Path = "$($ediStandardPath)\d365\prod\int"
            }
        }
        Add-Member -InputObject $settings -MemberType NoteProperty -Name "EdiD365EnvironmentPath" -Value $d365Path -Force
    }


    # C:\TempFk\ERPdata\EDI\d365\varefaks DEV
    # C:\TempForsprang\ERPdata\EDI\d365\varefaks TST
    # \\DEDGE.fk.no\ERPdata\EDI\d365\varefaks VFK
    # \\DEDGE.fk.no\ERPdata\EDI\d365\vareftest VFT
    # \\DEDGE.fk.no\ERPdata\EDI\d365\KAT SIT
    # \\DEDGE.fk.no\ERPdata\EDI\d365\KAT KAT
    # \\DEDGE.fk.no\ERPdata\EDI\d365\fkaperformance MIG
    # \\DEDGE.fk.no\ERPdata\EDI\d365\funksjonstest FUT
    # \\DEDGE.fk.no\ERPdata\EDI\d365\fkaperformance PER
    # \\DEDGE.fk.no\ERPdata\EDI\d365\prod PROD




    $global:FkEnvironmentSettings = $settings
    $global:CobolVersion = $settings.Version
    $global:pshRootpath = $settings.DedgePshAppsPath
    $global:db2Database = $settings.Database
    # Add the EDI d365 path as environment variable
    $global:EdiD365Path = $settings.EdiD365EnvironmentPath
    $global:EnvironmentSettings = $settings

    $env:Database = $settings.Database
    $env:EdiD365Path = $settings.EdiD365EnvironmentPath
    $env:CobolObjectPath = $settings.CobolObjectPath
    $env:EdiStandardPath = $settings.EdiStandardPath
    return $settings
}
<#
    .SYNOPSIS
        Maps standard network drives based on the current environment and computer name.

    .DESCRIPTION
        This function maps network drives using the same logic as the Map-NetworkDrives.bat file.
        It maps common drives (F:, K:, N:, R:, X:) and special drives (M:, Y:, Z:) for specific servers.

    .EXAMPLE
        Map-NetworkDrives
        Maps all standard network drives for the current computer.

    .NOTES
        Author: Geir Helge Starholm, www.dEdge.no
        Based on DevTools/AdminTools/Map-NetworkDrives/Map-NetworkDrives.bat
    #>
    
function Set-NetworkDrives {
    param(
        [Parameter(Mandatory = $false)]
        [bool]$Persist = $true
    )
    if ($(Get-LogLevel) -in @("DEBUG", "TRACE")) {
        Write-Host "Starting network drive mapping" -ForegroundColor Yellow
    }
    try {
        # Map common drives for all computers
        if (-not (Get-PSDrive -Name "F" -ErrorAction SilentlyContinue)) {
            if ($(Get-LogLevel) -in @("DEBUG", "TRACE")) {
                Write-Host "Mapping drive F: to \\DEDGE.fk.no\Felles" -ForegroundColor Yellow
            }
            New-PSDrive -Name "F" -PSProvider FileSystem -Root "\\DEDGE.fk.no\Felles" -Persist:$Persist -ErrorAction SilentlyContinue | Out-Null
        }
        else {
            if ($(Get-LogLevel) -in @("DEBUG", "TRACE")) {
                Write-Host "Drive F: already mapped" -ForegroundColor Yellow
            }
        }
        
        if (-not (Get-PSDrive -Name "K" -ErrorAction SilentlyContinue)) {
            if ($(Get-LogLevel) -in @("DEBUG", "TRACE")) {
                Write-Host "Mapping drive K: to \\DEDGE.fk.no\erputv\Utvikling" -ForegroundColor Yellow
            }
            New-PSDrive -Name "K" -PSProvider FileSystem -Root "\\DEDGE.fk.no\erputv\Utvikling" -Persist:$Persist -ErrorAction SilentlyContinue | Out-Null
        }
        else {
            if ($(Get-LogLevel) -in @("DEBUG", "TRACE")) {
                Write-Host "Drive K: already mapped" -ForegroundColor Yellow
            }
        }
        
        if (-not (Get-PSDrive -Name "N" -ErrorAction SilentlyContinue)) {
            if ($(Get-LogLevel) -in @("DEBUG", "TRACE")) {
                Write-Host "Mapping drive N: to \\DEDGE.fk.no\erpprog" -ForegroundColor Yellow
            }
            New-PSDrive -Name "N" -PSProvider FileSystem -Root "\\DEDGE.fk.no\erpprog" -Persist:$Persist -ErrorAction SilentlyContinue | Out-Null
            
        }
        else {
            if ($(Get-LogLevel) -in @("DEBUG", "TRACE")) {
                Write-Host "Drive N: already mapped" -ForegroundColor Yellow
            }
        }
        
        if (-not (Get-PSDrive -Name "R" -ErrorAction SilentlyContinue)) {
            if ($(Get-LogLevel) -in @("DEBUG", "TRACE")) {
                Write-Host "Mapping drive R: to \\DEDGE.fk.no\erpdata" -ForegroundColor Yellow
            }
            New-PSDrive -Name "R" -PSProvider FileSystem -Root "\\DEDGE.fk.no\erpdata" -Persist:$Persist -ErrorAction SilentlyContinue | Out-Null
        }
        else {
            if ($(Get-LogLevel) -in @("DEBUG", "TRACE")) {
                Write-Host "Drive R: already mapped" -ForegroundColor Yellow
            }
        }
        
        if (-not (Get-PSDrive -Name "X" -ErrorAction SilentlyContinue)) {
            if ($(Get-LogLevel) -in @("DEBUG", "TRACE")) {
                Write-Host "Mapping drive X: to C:\opt\src\DedgeSrc\DedgeSystemTools\Folders\DedgeCommon" -ForegroundColor Yellow
            }
            New-PSDrive -Name "X" -PSProvider FileSystem -Root "C:\opt\src\DedgeSrc\DedgeSystemTools\Folders\DedgeCommon" -Persist:$Persist -ErrorAction SilentlyContinue | Out-Null
        }
        else {
            if ($(Get-LogLevel) -in @("DEBUG", "TRACE")) {
                Write-Host "Drive X: already mapped" -ForegroundColor Yellow
            }
        }
        
        # Special mappings for specific computer
        $computerName = $env:COMPUTERNAME
        if ($computerName -eq "p-no1fkmprd-app") {
            if ($(Get-LogLevel) -in @("DEBUG", "TRACE")) {
                Write-Host "Detected production server, mapping additional drives" -ForegroundColor Yellow
            }
            
            if (-not (Get-PSDrive -Name "M" -ErrorAction SilentlyContinue)) {
                # Create credential for M: drive
                $securePassword = ConvertTo-SecureString "Namdal10" -AsPlainText -Force
                $credential = New-Object System.Management.Automation.PSCredential("Administrator", $securePassword)
                
                if ($(Get-LogLevel) -in @("DEBUG", "TRACE")) {
                    Write-Host "Mapping drive M: to \\sfknam01.DEDGE.fk.no\Felles_NKM\NKM_Utlast" -ForegroundColor Yellow
                }
                New-PSDrive -Name "M" -PSProvider FileSystem -Root "\\sfknam01.DEDGE.fk.no\Felles_NKM\NKM_Utlast" -Credential $credential -Persist:$Persist -ErrorAction SilentlyContinue | Out-Null
            }
            else {
                if ($(Get-LogLevel) -in @("DEBUG", "TRACE")) {
                    Write-Host "Drive M: already mapped" -ForegroundColor Yellow
                }
            }

            if (-not (Get-PSDrive -Name "Y" -ErrorAction SilentlyContinue)) {
                # Create credential for Y: and Z: drives
                $securePassword2 = ConvertTo-SecureString "FiloDeig01!" -AsPlainText -Force
                $credential2 = New-Object System.Management.Automation.PSCredential("SKAERP13", $securePassword2)
                
                if ($(Get-LogLevel) -in @("DEBUG", "TRACE")) {
                    Write-Host "Mapping drive Y: to \\10.60.0.4\fabrikkdata" -ForegroundColor Yellow
                }
                New-PSDrive -Name "Y" -PSProvider FileSystem -Root "\\10.60.0.4\fabrikkdata" -Credential $credential2 -Persist:$Persist -ErrorAction SilentlyContinue | Out-Null
            }
            else {
                if ($(Get-LogLevel) -in @("DEBUG", "TRACE")) {
                    Write-Host "Drive Y: already mapped" -ForegroundColor Yellow
                }
            }
            
            if (-not (Get-PSDrive -Name "Z" -ErrorAction SilentlyContinue)) {
                # Create credential for Z: drive (reuse credential2 from Y: drive)
                $securePassword2 = ConvertTo-SecureString "FiloDeig01!" -AsPlainText -Force
                $credential2 = New-Object System.Management.Automation.PSCredential("SKAERP13", $securePassword2)
                
                if ($(Get-LogLevel) -in @("DEBUG", "TRACE")) {
                    Write-Host "Mapping drive Z: to \\10.60.0.4\produksjon" -ForegroundColor Yellow
                }
                New-PSDrive -Name "Z" -PSProvider FileSystem -Root "\\10.60.0.4\produksjon" -Credential $credential2 -Persist:$Persist -ErrorAction SilentlyContinue | Out-Null
            }
            else {
                if ($(Get-LogLevel) -in @("DEBUG", "TRACE")) {
                    Write-Host "Drive Z: already mapped" -ForegroundColor Yellow
                }
            }
        }
        
        if ($(Get-LogLevel) -in @("DEBUG", "TRACE")) {
            Write-Host "Network drive mapping completed successfully" -ForegroundColor Yellow
        }
    }
    catch {
        if ($(Get-LogLevel) -in @("DEBUG", "TRACE")) {
            Write-Host "Error mapping network drives: $($_.Exception.Message)" -ForegroundColor Red
        }
        throw
    }
}

function Get-SmsNumbersArray {
    param(
        [Parameter(Mandatory = $false)]
        [string]$Environment
    )
    $smsOptions = @{
        "1" = [PSCustomObject]@{
            "Description" = "Geir Helge Starholm"
            "Numbers"     = @("+4797188358")
        }
        "2" = [PSCustomObject]@{
            "Description" = "Svein Morten Erikstad"
            "Numbers"     = @("+4795762742")
        }
    }
    return $smsOptions
}

function Get-SmsNumbers {
    param(
        [Parameter(Mandatory = $false)]
        [string]$Environment
    )
    $smsOptions = Get-SmsNumbersArray
    $smsNumbers = @()
    foreach ($option in $smsOptions.Values) {
        $smsNumbers += $option.Numbers
    }
    return @($smsNumbers)
}
function Get-UserChoiceForSmsNumbers {  
    
    Write-LogMessage "Getting SMS numbers for notifications" -Level INFO

    # Predefined options for SMS numbers
    $smsOptions = Get-SmsNumbersArray
    # Get all the numbers from the smsOptions
    $allNumbers = @()
    $maxKey = 0
    foreach ($key in $($smsOptions.Keys | Sort-Object)) {
        $allNumbers += $smsOptions[$key].Numbers
        if ($key -gt $maxKey) {
            $maxKey = [int]$key
        }
    }

    $maxKey += 1
    $smsOptions += @{
        "$($maxKey)" = [PSCustomObject]@{
            "Description" = "Notify all"
            "Numbers"     = $allNumbers
        }
    }

    $maxKey += 1
    $smsOptions += @{
        "$($maxKey)" = [PSCustomObject]@{
            "Description" = "No SMS notifications"
            "Numbers"     = @()
        }
    }
    
    # Build prompt message
    $promptMessage = "Choose SMS notification recipients:`n"
    foreach ($key in $smsOptions.Keys | Sort-Object) {
        $promptMessage += "$key) $($smsOptions[$key].Description)`n"
    }
      
    if ((Test-IsServer -Quiet $true) -and ($(Get-EnvironmentFromServerName) -eq "PRD" -or $(Get-EnvironmentFromServerName) -eq "RAP" -or $(Get-EnvironmentFromServerName) -eq "HST"))<#  #> {
        # get Notify all option from array
        $smsNumbers = $smsOptions["3"].Numbers
        Write-LogMessage "Standard production mode notification selected. Notification will be sent to SMS numbers: $($smsNumbers -join ', ')" -Level INFO
        return $smsNumbers
    }

    $allowedResponses = @()
    foreach ($key in $($smsOptions.Keys | Sort-Object)) {
        $currentResponse = $smsOptions[$key].Description
        if ($smsOptions[$key].Numbers.Length -gt 0) {
            $currentResponse += " (" + $($smsOptions[$key].Numbers -join ', ') + ")"
        }
        $allowedResponses += $currentResponse
    }

    $userChoice = Get-UserConfirmationWithTimeout -PromptMessage $promptMessage -TimeoutSeconds 30 -AllowedResponses $allowedResponses -ProgressMessage "Choose SMS recipients" -DefaultResponse " "
    
    # eg. "Notify all (+4797188358, +4795762742)"
    if ($userChoice.Contains("(")) {
        $userChoice = $userChoice.Split("(")[0].Trim()
    }

    foreach ($key in $smsOptions.Keys) {
        if ($smsOptions[$key].Description -eq $userChoice) {
            $selectedSmsNumbers = $smsOptions[$key].Numbers
            break
        }
    }
    Write-LogMessage "Selected SMS numbers: $($selectedSmsNumbers -join ', ')" -Level INFO
    
    return $selectedSmsNumbers
}

function Add-ScriptAndOutputToWorkObject {
    param(
        [Parameter(Mandatory = $true)]
        [PSCustomObject]$WorkObject,
        [Parameter(Mandatory = $true)]
        [string]$Name,
        [Parameter(Mandatory = $true)]
        [string]$Script,
        [Parameter(Mandatory = $false)]
        [string]$Output = $null
    )
    Write-LogMessage "Adding script and output to work object" -Level INFO
    try {
        if ($Output -is [array]) {
            $Output = $Output -join "`n"
        }
        elseif ($null -eq $Output) {
            $Output = "N/A"
        }
    }
    catch {
        $Output = "N/A"
    }

    try {
        if ($Script -is [array]) {
            $Script = $Script -join "`n"
        }
        if ($Output -is [array]) {
            $Output = $Output -join "`n"
        }
        # Add echo Timestamp to script
        $Script = "`n___________________________________________________________________________`n-- Script executed at $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')`n___________________________________________________________________________`n$Script"
        if ($null -eq $Output) {
            $Output = ""
        }
        $Output = "`n___________________________________________________________________________`n-- Output result from script execution at $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')`n___________________________________________________________________________`n$Output"

        
        # Check and get current name from current script array
        $currentScriptArray = $WorkObject.ScriptArray
        $currentElement = $currentScriptArray | Where-Object { $_.Name -eq $Name } | Select-Object -First 1

        if ($null -ne $currentElement) {
            $WorkObject.ScriptArray = $currentScriptArray | Where-Object { $_.Name -ne $Name }
            $currentElement.Script += $Script
            $currentElement.Output += $Output
            $currentElement.LastTimestamp = $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')
        }
        else {
            $newObject = [PSCustomObject]@{
                Name           = $Name
                FirstTimestamp = $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')
                LastTimestamp  = $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')
                Script         = $Script
                Output         = $Output
            }
            $currentScriptArray += $newObject
        }
        Add-Member -InputObject $WorkObject -NotePropertyName "ScriptArray" -NotePropertyValue $currentScriptArray -Force
    }
    catch {
        Write-LogMessage "Error adding script and output to work object" -Level ERROR -Exception $_
        throw $_
    }
    return $WorkObject
}

function Get-ValidServerNameList {
    $serverNameList = Get-ComputerInfoJson | Where-Object { $_.Platform -ne "Digiplex" -and ($_.Type -eq "Server") } | Select-Object -ExpandProperty Name
    $serverNameListArray = @($serverNameList | Sort-Object -Unique)
    $validServerNameList = @()
    foreach ($serverName in $serverNameListArray) {
        $testPath = "\\$serverName\opt"
        if (Test-Path $testPath -PathType Container) {
            $validServerNameList += $serverName
        }
    }
    return $validServerNameList
}


function Test-AllPlaySounds {
    Write-LogMessage "Testing all play sounds" -Level INFO  
    $soundNames = @("Ding", "Notify", "Error", "Exclamation", "Information", "Pop-up Blocked", "Default", "Chimes", "Chord", "Tada")
    foreach ($sound in $soundNames) {
        Write-Host "Playing sound: $sound" -ForegroundColor Cyan
        Start-PlaySound -SoundName $sound
        Start-Sleep -Seconds 3
    }
}
function Start-PlaySound {
    param (
        [Parameter(Mandatory = $false)]
        [ValidateSet("Ding", "Notify", "Error", "Exclamation", "Information", "Pop-up Blocked", "Default", "Chimes", "Chord", "Tada")]
        [string]$SoundName = "Tada"
    ) 
    # Play completion sound
    try {
        if (-not ([System.Management.Automation.PSTypeName]'Sound').Type) {
            Add-Type -TypeDefinition @"
      using System;
      using System.Runtime.InteropServices;
      public class Sound {
        [DllImport("winmm.dll", SetLastError = true)]
        public static extern bool PlaySound(string pszSound, IntPtr hmod, uint fdwSound);
      }
"@
        }
        if ($SoundName -eq "Ding") {
            $soundPath = "$env:WINDIR\Media\Windows Ding.wav" # Ding sound
        }
        elseif ($SoundName -eq "Notify") {
            $soundPath = "$env:WINDIR\Media\Windows Notify.wav" # Notification sound
        }
        elseif ($SoundName -eq "Error") {
            $soundPath = "$env:WINDIR\Media\Windows Error.wav" # Error sound
        }
        elseif ($SoundName -eq "Exclamation") {
            $soundPath = "$env:WINDIR\Media\Windows Exclamation.wav" # Warning/exclamation sound
        }
        elseif ($SoundName -eq "Information") {
            $soundPath = "$env:WINDIR\Media\Windows Information Bar.wav" # Information sound
        }
        elseif ($SoundName -eq "Pop-up Blocked") {
            $soundPath = "$env:WINDIR\Media\Windows Pop-up Blocked.wav" # Pop-up blocked sound
        }
        elseif ($SoundName -eq "Default") {
            $soundPath = "$env:WINDIR\Media\Windows Default.wav" # Default system sound
        }
        elseif ($SoundName -eq "Chimes") {
            $soundPath = "$env:WINDIR\Media\chimes.wav" # Classic chimes sound
        }
        elseif ($SoundName -eq "Chord") {
            $soundPath = "$env:WINDIR\Media\chord.wav" # Classic chord sound
        }
        elseif ($SoundName -eq "Tada") {
            $soundPath = "$env:WINDIR\Media\tada.wav" # Classic tada sound
        }
        [Sound]::PlaySound($soundPath, [IntPtr]::Zero, 0x00020000)
    }
    catch {
        Write-LogMessage "Could not play completion sound: $($_.Exception.Message)" -Level WARNING
    }
}

function Get-CodeLineCount {
    param (
        [string]$RootPath = "$env:OptPath\src\DedgePsh\_Modules"
    )  
    $ps1Files = Get-ChildItem -Path $RootPath  -Include "*.ps1", "*.psm1", "*.bat" -Recurse -File -ErrorAction SilentlyContinue | Where-Object { $_.DirectoryName -notmatch '\\_old\\' } | Select-Object -ExpandProperty FullName

    $totalLines = 0

    foreach ($file in $ps1Files) {
        try {
            $lineCount = (Get-Content $file).Count
            $totalLines += $lineCount
        }
        catch {
            Write-Warning "Could not read file: $($file)"
        }
    }

    Write-Output "Total lines of PowerShell code (excluding '_old' folders): $totalLines"
    return $totalLines
}

function Test-GlobalEnvironmentSettings {
    $workObject = Get-GlobalEnvironmentSettings

    $ListOutput = $workObject | Format-List -Property * | Out-String
    #$content = Get-Content -Path $workObject.ScriptPath
    #$workObject = Add-ScriptAndOutputToWorkObject -WorkObject $workObject -Name "Test-GlobalEnvironmentSettings" -Script $($content -join "`n") -Output $ListOutput

    Write-LogMessage "List output: `n$ListOutput" -Level INFO
    $applicationDataPath = Get-ApplicationDataPath
    $ouputFilePath = Join-Path $applicationDataPath "$($workObject.DatabaseInternalName)-GlobalEnvironmentSettingsVerification.html"
    Export-WorkObjectToHtmlFile -WorkObject $workObject -FileName $ouputFilePath -Title "Global Environment Settings Verification" -DevToolsWebDirectory "Db2/$($workObject.DatabaseInternalName.ToUpper())" -AutoOpen:$false

    $globalLoggingPath = Get-CommonLogPath
    $jsonFilePath = Join-Path $globalLoggingPath "Server\GlobalEnvironmentSettingsVerification" "$($env:COMPUTERNAME).$($workObject.DatabaseInternalName)-$(Get-Date -Format 'yyyyMMdd-HHmmssfff').json"
    Export-WorkObjectToJsonFile -WorkObject $workObject -FileName $jsonFilePath

}
function Start-TestGlobalEnvironmentSettings {
    param(
        [Parameter(Mandatory = $false)]
        [string]$FilePath = $null
    )
    if ([string]::IsNullOrEmpty($FilePath)) {
        $FilePath = Join-Path $env:OptPath "DedgePshApps\Test-GlobalEnvironmentSettings\Test-GlobalEnvironmentSettings.ps1"
    }
    try {
        $cmdArgs = @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', "`"$($FilePath)`"") 
        $appdataPath = Get-ApplicationDataPath
        $logFile = Join-Path $appdataPath "GlobalEnvironmentSettingsVerification-$(Get-Date -Format 'yyyyMMdd-HHmmssfff').log"
        $commandString = "pwsh.exe $($cmdArgs -join ' ') > `"$($logFile)`""
        Write-LogMessage "Command string: cmd /c $commandString" -Level INFO
        & cmd /c $commandString
        $exitCode = $LASTEXITCODE
        if ($exitCode -ne 0) {
            Write-LogMessage "Failed to test global environment settings" -Level ERROR
        }
        else {
            Write-LogMessage "Successfully tested global environment settings" -Level INFO
        }
    }
    catch {
        Write-LogMessage "Failed to test global environment settings" -Level ERROR -Exception $_
    }
}


function Get-EventLogData {
    <#
    .SYNOPSIS
        Retrieves event log data based on specified criteria
    #>
    param(
        [string[]]$LogNames,
        [datetime]$StartTime,
        [datetime]$EndTime = (Get-Date),
        [string[]]$FilterWords = @(),
        [string[]]$ProviderNames = @(),
        [int[]]$EventIds = @(),
        [string[]]$Levels = @(),
        [switch]$ExcludeInformational
    )

    try {
        $filterHashtable = @{
            LogName   = $LogNames
            StartTime = $StartTime
            EndTime   = $EndTime
        }

        if ($EventIds.Count -gt 0) {
            $filterHashtable.ID = $EventIds
        }

        if ($Levels.Count -gt 0) {
            $filterHashtable.Level = $Levels
        }

        Write-LogMessage "Querying event logs..." -Level INFO
        $events = Get-WinEvent -FilterHashtable $filterHashtable -ErrorAction SilentlyContinue

        if ($ExcludeInformational) {
            $events = $events | Where-Object { $_.LevelDisplayName -ne "Information" -and $_.LevelDisplayName -ne "Verbose" }
        }

        if ($ProviderNames.Count -gt 0) {
            $events = $events | Where-Object { $_.ProviderName -in $ProviderNames }
        }

        if ($FilterWords.Count -gt 0) {
            $events = $events | Where-Object {
                $message = $_.Message
                $FilterWords | ForEach-Object {
                    if ($message -like "*$_*") { return $true }
                }
                return $false
            }
        }

        return $events
    }
    catch {
        Write-LogMessage "Error retrieving event log data: $($_.Exception.Message)" -Level ERROR
        return @()
    }
}

function Export-EventLogResults {
    <#
    .SYNOPSIS
        Exports event log results to a file and opens it
    #>
    param(
        [object[]]$Events,
        [string]$ReportType,
        [string]$TimeSpanDescription,
        [bool]$LimitProperties = $true
    )

    if ($Events.Count -eq 0) {
        Write-LogMessage "No events found matching the specified criteria." -Level WARN
        return
    }
    if ($LimitProperties -eq $true) {
        $Events = $Events | Select-Object TimeCreated, Id, LevelDisplayName, LogName, ProviderName, Message
    }


    # Format events with optimized column widths - Message gets the most space
    $formattedEvents = $Events | Format-Table -Property @(
        @{Name = "TimeCreated"; Expression = { $_.TimeCreated.ToString("yyyy-MM-dd HH:mm:ss") }; Width = 19 },
        @{Name = "Id"; Expression = { $_.Id }; Width = 6 },
        @{Name = "Level"; Expression = { $_.LevelDisplayName }; Width = 11 },
        @{Name = "LogName"; Expression = { $_.LogName }; Width = 12 },
        @{Name = "ProviderName"; Expression = { $_.ProviderName }; Width = 20 },
        @{Name = "Message"; Expression = { $_.Message } }
    ) -Wrap | Out-String

    $applicationFolder = Join-Path $(Get-ApplicationDataPath) "EventLogExport" $(Get-Date -Format "yyyyMMdd-HHmmss")
    if (-not (Test-Path -Path $applicationFolder -PathType Container)) {
        New-Item -ItemType Directory -Path $applicationFolder -Force | Out-Null
    }

    $sanitizedReportType = Remove-IllegalCharactersFromPath -Path $ReportType
    $fileName = Join-Path $applicationFolder "$($sanitizedReportType)_$($TimeSpanDescription).log"
    $fileName = Remove-IllegalCharactersFromPath -Path $fileName
    $eventData = $Events
    # Get Windows uptime
    $uptime = (Get-Date) - (Get-CimInstance -ClassName Win32_OperatingSystem).LastBootUpTime
    $uptimeFormatted = "{0} days, {1:D2}:{2:D2}:{3:D2}" -f $uptime.Days, $uptime.Hours, $uptime.Minutes, $uptime.Seconds

    Add-Member -InputObject $eventData -MemberType NoteProperty -Name "ReportType" -Value $ReportType -Force
    Add-Member -InputObject $eventData -MemberType NoteProperty -Name "TimeSpanDescription" -Value $TimeSpanDescription -Force
    Add-Member -InputObject $eventData -MemberType NoteProperty -Name "ComputerName" -Value $env:COMPUTERNAME -Force
    Add-Member -InputObject $eventData -MemberType NoteProperty -Name "SystemUptime" -Value $uptimeFormatted -Force
    Add-Member -InputObject $eventData -MemberType NoteProperty -Name "Generated" -Value $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss') -Force
    Add-Member -InputObject $eventData -MemberType NoteProperty -Name "TotalEvents" -Value $Events.Count -Force

    $jsonFile = Join-Path $applicationFolder "$($sanitizedReportType)_$($TimeSpanDescription).json"
    $jsonFile = Remove-IllegalCharactersFromPath -Path $jsonFile
    $eventData | ConvertTo-Json | Set-Content -Path $jsonFile -Encoding UTF8

    # Create report header
    $reportHeader = @"
═══════════════════════════════════════════════════════════════
Windows Event Log Analysis Report
═══════════════════════════════════════════════════════════════
Report Type: $ReportType
Generated: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')
Time Span: $TimeSpanDescription
Total Events: $($Events.Count)
Computer: $env:COMPUTERNAME
System Uptime: $uptimeFormatted
═══════════════════════════════════════════════════════════════

"@

    $fullReport = $reportHeader + $formattedEvents
    $fullReport | Set-Content -Path $fileName -Encoding UTF8

    Write-LogMessage "Found $($Events.Count) events" -Level INFO
    Write-LogMessage "Report exported to: $fileName" -Level INFO

    # Open file with enhanced error handling
    $openSuccess = Open-FileWithEditorSafe -FilePath $fileName
    if (-not $openSuccess) {
        Write-LogMessage "Could not open file automatically. Report saved to: $fileName" -Level WARN
        Write-LogMessage "Please open the file manually to view the results." -Level INFO
    }
    # Open file with enhanced error handling
    $openSuccess = Open-FileWithEditorSafe -FilePath $jsonFile
    if (-not $openSuccess) {
        Write-LogMessage "Could not open file automatically. Report saved to: $jsonFile" -Level WARN
        Write-LogMessage "Please open the file manually to view the results." -Level INFO
    }
}


<#
.SYNOPSIS
    Checks if the current user has administrator privileges.

.DESCRIPTION
    Tests whether the current PowerShell session is running with administrator privileges
    by checking the WindowsPrincipal identity and role membership.

.OUTPUTS
    System.Boolean
    Returns $true if the current user has administrator privileges, otherwise $false.

.EXAMPLE
    Test-IsAdmin
    # Returns $true if running as administrator, $false otherwise

.EXAMPLE
    if (Test-IsAdmin) {
        Write-Host "Running with admin privileges"
    } else {
        Write-Host "Not running as administrator"
    }

.NOTES
    This function checks the current session's privileges, not the user's inherent
    administrative group membership. A user in the Administrators group must explicitly
    run PowerShell "as Administrator" for this to return $true.
#>
function Test-IsAdmin {
    [CmdletBinding()]
    [OutputType([bool])]
    param()
    
    try {
        $currentIdentity = [Security.Principal.WindowsIdentity]::GetCurrent()
        $principal = New-Object Security.Principal.WindowsPrincipal($currentIdentity)
        $adminRole = [Security.Principal.WindowsBuiltInRole]::Administrator
        
        return $principal.IsInRole($adminRole)
    }
    catch {
        Write-LogMessage "Error checking administrator privileges: $($_.Exception.Message)" -Level ERROR
        return $false
    }
}


########################################################################################
# Set the global variables for the global environment settings
########################################################################################
if (-not (Get-Variable -Name GetGlobalEnvironmentSettings -Scope Global -ErrorAction SilentlyContinue)) {
    $Global:GetGlobalEnvironmentSettings = $true
}
# Wrapped in try-catch so a failure here (e.g. missing COBOL, unreachable network share)
# does not abort the entire module import and leave Write-LogMessage unavailable.
try {
    if ($Global:GetGlobalEnvironmentSettings -eq $true -and $null -eq $global:FkEnvironmentSettings) {
        Get-GlobalEnvironmentSettings
        $Global:GetGlobalEnvironmentSettings = $false
    }
}
catch {
    Write-Host "WARNING: Get-GlobalEnvironmentSettings failed during module init: $($_.Exception.Message)" -ForegroundColor Yellow
}

try {
    if (-not (Get-PSDrive -Name "K" -ErrorAction SilentlyContinue)) {
        Set-NetworkDrives
    }
}
catch {
    Write-Host "WARNING: Set-NetworkDrives failed during module init: $($_.Exception.Message)" -ForegroundColor Yellow
}

#region Cursor Command Utilities

function Convert-MermaidToBase64 {
    <#
    .SYNOPSIS
        Renders mermaid code to SVG via mmdc and returns the base64-encoded string.
    .PARAMETER MermaidCode
        Mermaid diagram source code. Alternative to InputFile.
    .PARAMETER InputFile
        Path to a .mmd file. Alternative to MermaidCode.
    .PARAMETER Name
        Diagram name for temp files. Default: "diagram".
    .PARAMETER Background
        SVG background color. Default: "white".
    .PARAMETER Width
        SVG width in pixels. Default: 900.
    #>
    [CmdletBinding()]
    param(
        [Parameter(ParameterSetName = 'Code')]
        [string]$MermaidCode,

        [Parameter(ParameterSetName = 'File')]
        [string]$InputFile,

        [Parameter()]
        [string]$Name = "diagram",

        [Parameter()]
        [string]$Background = "white",

        [Parameter()]
        [int]$Width = 900
    )

    if (-not (Get-Command mmdc.cmd -ErrorAction SilentlyContinue)) {
        throw "mmdc.cmd not found. Install via: npm install -g @mermaid-js/mermaid-cli"
    }

    $dir = Join-Path $env:TEMP "mermaid_render_$([guid]::NewGuid().ToString('N').Substring(0,8))"
    New-Item -ItemType Directory -Path $dir -Force | Out-Null

    try {
        if ($PSCmdlet.ParameterSetName -eq 'Code') {
            $mmdFile = Join-Path $dir "$($Name).mmd"
            $MermaidCode | Out-File -FilePath $mmdFile -Encoding utf8 -Force
        }
        else {
            $mmdFile = $InputFile
        }

        $svgFile = Join-Path $dir "$($Name).svg"
        & mmdc.cmd -i $mmdFile -o $svgFile -b $Background -w $Width 2>&1 | Out-Null

        if (-not (Test-Path $svgFile)) {
            throw "mmdc failed to produce SVG output for '$($Name)'"
        }

        return [System.Convert]::ToBase64String([System.IO.File]::ReadAllBytes($svgFile))
    }
    finally {
        Remove-Item $dir -Recurse -Force -ErrorAction SilentlyContinue
    }
}

function Get-ProjectTech {
    <#
    .SYNOPSIS
        Detects the dominant technology in a project folder by scanning file extensions.
    .PARAMETER ProjectPath
        Path to the project folder to scan.
    .OUTPUTS
        String: PowerShell, CSharp, Cobol, Python, or NodeJS.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$ProjectPath
    )

    $files = Get-ChildItem -Path $ProjectPath -Recurse -File -ErrorAction SilentlyContinue |
        Where-Object { $_.DirectoryName -notmatch '\\(bin|obj|node_modules|dist|build|\.git|__pycache__|venv|\.venv)\\?' }

    $counts = @{
        PowerShell = ($files | Where-Object { $_.Extension -in '.ps1', '.psm1', '.psd1' }).Count
        CSharp     = ($files | Where-Object { $_.Extension -in '.cs', '.csproj', '.sln' }).Count
        Cobol      = ($files | Where-Object { $_.Extension -in '.cbl', '.cpy', '.cob' }).Count
        Python     = ($files | Where-Object { $_.Extension -eq '.py' }).Count
        NodeJS     = ($files | Where-Object { $_.Extension -in '.js', '.ts', '.mjs' }).Count
    }

    $dominant = $counts.GetEnumerator() | Sort-Object Value -Descending | Select-Object -First 1
    if ($dominant.Value -eq 0) { return "Unknown" }
    return $dominant.Name
}

function Find-ReferencedRules {
    <#
    .SYNOPSIS
        Scans project files for .mdc rule references and copies matching rules to a target directory.
    .PARAMETER ProjectRoot
        Path to the project folder to scan.
    .PARAMETER RulesDir
        Path to the .cursor/rules/ folder containing rule files.
    .PARAMETER TargetDir
        Destination folder where matching rule files are copied.
    .OUTPUTS
        Array of copied file names.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$ProjectRoot,

        [Parameter(Mandatory)]
        [string]$RulesDir,

        [Parameter(Mandatory)]
        [string]$TargetDir
    )

    $sourceFiles = Get-ChildItem -Path $ProjectRoot -Recurse -Include '*.md', '*.ps1', '*.mdc' -File -ErrorAction SilentlyContinue

    if (-not $sourceFiles) { return @() }

    # Regex: match filenames ending in .mdc — word chars, hyphens, dots
    $hits = Select-String -Path $sourceFiles.FullName -Pattern '[A-Za-z0-9_.-]+\.mdc' -AllMatches |
        ForEach-Object { $_.Matches.Value } | Sort-Object -Unique

    if (-not (Test-Path $TargetDir)) {
        New-Item -Path $TargetDir -ItemType Directory -Force | Out-Null
    }

    $copied = @()
    foreach ($rule in $hits) {
        $src = Join-Path $RulesDir $rule
        if (Test-Path $src) {
            Copy-Item $src (Join-Path $TargetDir $rule) -Force
            $copied += $rule
        }
    }

    return $copied
}

function Publish-ToDocView {
    <#
    .SYNOPSIS
        Publishes a markdown file to the DocView portal, refreshes cache, and returns the URL.
    .PARAMETER SourceFile
        Path to the markdown file to publish.
    .PARAMETER Tech
        Technology category: PowerShell, CSharp, Cobol, Python, or NodeJS.
    .PARAMETER RelativePath
        Relative path under System/<Tech>/ for the target directory (e.g. "DedgePsh\DevTools\DatabaseTools").
    .PARAMETER DescriptiveTitle
        Filename for the published doc (e.g. "Db2-ShadowDatabase - Shadow Database Pipeline.md").
    .OUTPUTS
        PSCustomObject with DocViewUrl and TargetPath properties.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$SourceFile,

        [Parameter(Mandatory)]
        [ValidateSet('PowerShell', 'CSharp', 'Cobol', 'Python', 'NodeJS')]
        [string]$Tech,

        [Parameter(Mandatory)]
        [string]$RelativePath,

        [Parameter(Mandatory)]
        [string]$DescriptiveTitle
    )

    $docShareRoot = "C:\opt\src\DedgeSrc\DedgeSystemTools\Folders\Opt\Webs\DocViewWeb\Content"
    $targetDir = Join-Path $docShareRoot "System\$($Tech)\$($RelativePath)"

    if (-not (Test-Path $targetDir)) {
        New-Item -Path $targetDir -ItemType Directory -Force | Out-Null
    }

    $destPath = Join-Path $targetDir $DescriptiveTitle
    Copy-Item -Path $SourceFile -Destination $destPath -Force

    try {
        Invoke-RestMethod -Uri "http://dedge-server/DocView/api/document/refresh" -Method Post -TimeoutSec 30 | Out-Null
    }
    catch {
        Write-LogMessage "DocView cache refresh failed: $($_.Exception.Message)" -Level WARN
    }

    $docViewUrl = ConvertTo-DocViewUrl $destPath

    return [PSCustomObject]@{
        DocViewUrl = $docViewUrl
        TargetPath = $destPath
    }
}

#endregion Cursor Command Utilities

Export-ModuleMember -Function *

