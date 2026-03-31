#Requires -Version 5.1
<#
.SYNOPSIS
    Downloads all necessary tools for Generic Log Handler implementation to support air-gapped installation.

.DESCRIPTION
    This script downloads all required software, installers, and packages needed to implement
    the Generic Log Handler solution with IBM DB2 on an air-gapped Windows Server 2025.
    
    All downloads are organized into categorized folders for easy transfer and installation.

.PARAMETER DownloadPath
    The path where all tools will be downloaded. Default is C:\LoggingToolsDownload

.PARAMETER SkipWinget
    Skip winget downloads (useful if winget is not available on download machine)

.EXAMPLE
    .\Download-LoggingTools.ps1 -DownloadPath "D:\OfflineInstall"
    
.EXAMPLE
    .\Download-LoggingTools.ps1 -SkipWinget
#>

[CmdletBinding()]
param(
    [Parameter(Mandatory = $false)]
    [string]$DownloadPath = "C:\LoggingToolsDownload",
    
    [Parameter(Mandatory = $false)]
    [switch]$SkipWinget
)

# Import GlobalFunctions if available
try {
    Import-Module GlobalFunctions -Force -ErrorAction SilentlyContinue
} catch {
    # Fallback logging function if GlobalFunctions not available
    function Write-LogMessage {
        param([string]$Message, [string]$Level = "INFO")
        $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
        Write-Host "[$timestamp] [$Level] $Message"
    }
}

# Tool definitions with download URLs and metadata
$Tools = @{
    "Core Database" = @(
        @{
            Name = "IBM DB2 12.1 Community Edition"
            WingetId = ""
            DirectUrl = "https://www.ibm.com/support/pages/db2-community-edition"
            FileName = "db2-community-edition-12.1.0.0-windows-x64.exe"
            Description = "IBM DB2 12.1 Community Edition database server"
            Category = "Database"
            Size = "~1.2GB"
            Critical = $true
        },
        @{
            Name = "IBM Data Studio"
            WingetId = ""
            DirectUrl = "https://www.ibm.com/support/pages/ibm-data-studio"
            FileName = "ibm-data-studio-4.1.3-windows-x64.exe"
            Description = "IBM Data Studio for DB2 administration and development"
            Category = "Database"
            Size = "~200MB"
            Critical = $true
        }
    )
    "Development Platform" = @(
        @{
            Name = "Visual Studio 2022 Community"
            WingetId = "Microsoft.VisualStudio.2022.Community"
            DirectUrl = "https://aka.ms/vs/17/release/vs_community.exe"
            FileName = "vs_community.exe"
            Description = "Visual Studio 2022 Community Edition"
            Category = "Development"
            Size = "~4GB (bootstrapper)"
            Critical = $true
        },
        @{
            Name = ".NET 8 SDK"
            WingetId = "Microsoft.DotNet.SDK.8"
            DirectUrl = "https://download.microsoft.com/download/8/4/8/848036c1-61b0-4651-b36e-3ca0bb0d52c1/dotnet-sdk-8.0.204-win-x64.exe"
            FileName = "dotnet-sdk-8.0.204-win-x64.exe"
            Description = ".NET 8.0 SDK for development"
            Category = "Development"
            Size = "~200MB"
            Critical = $true
        },
        @{
            Name = ".NET 8 Runtime"
            WingetId = "Microsoft.DotNet.Runtime.8"
            DirectUrl = "https://download.microsoft.com/download/8/4/8/848036c1-61b0-4651-b36e-3ca0bb0d52c1/dotnet-runtime-8.0.4-win-x64.exe"
            FileName = "dotnet-runtime-8.0.4-win-x64.exe"
            Description = ".NET 8.0 Runtime for production"
            Category = "Development"
            Size = "~55MB"
            Critical = $true
        },
        @{
            Name = "ASP.NET Core 8 Runtime"
            WingetId = "Microsoft.DotNet.AspNetCore.8"
            DirectUrl = "https://download.microsoft.com/download/8/4/8/848036c1-61b0-4651-b36e-3ca0bb0d52c1/aspnetcore-runtime-8.0.4-win-x64.exe"
            FileName = "aspnetcore-runtime-8.0.4-win-x64.exe"
            Description = "ASP.NET Core 8.0 Runtime"
            Category = "Development"
            Size = "~20MB"
            Critical = $true
        }
    )
    "Database Tools" = @(
        @{
            Name = "DBeaver Community"
            WingetId = "dbeaver.dbeaver"
            DirectUrl = "https://dbeaver.io/files/dbeaver-ce-latest-x86_64-setup.exe"
            FileName = "dbeaver-ce-latest-x86_64-setup.exe"
            Description = "Universal database tool"
            Category = "Database"
            Size = "~100MB"
            Critical = $false
        }
    )
    "Utilities" = @(
        @{
            Name = "Git for Windows"
            WingetId = "Git.Git"
            DirectUrl = "https://github.com/git-for-windows/git/releases/download/v2.43.0.windows.1/Git-2.43.0-64-bit.exe"
            FileName = "Git-2.43.0-64-bit.exe"
            Description = "Git version control system"
            Category = "Utilities"
            Size = "~50MB"
            Critical = $true
        },
        @{
            Name = "7-Zip"
            WingetId = "7zip.7zip"
            DirectUrl = "https://www.7-zip.org/a/7z2301-x64.exe"
            FileName = "7z2301-x64.exe"
            Description = "File archiver for extracting packages"
            Category = "Utilities"
            Size = "~1.5MB"
            Critical = $false
        },
        @{
            Name = "Notepad++"
            WingetId = "Notepad++.Notepad++"
            DirectUrl = "https://github.com/notepad-plus-plus/notepad-plus-plus/releases/download/v8.6/npp.8.6.Installer.x64.exe"
            FileName = "npp.8.6.Installer.x64.exe"
            Description = "Advanced text editor"
            Category = "Utilities"
            Size = "~4MB"
            Critical = $false
        }
    )
    "API Testing" = @(
        @{
            Name = "Postman"
            WingetId = "Postman.Postman"
            DirectUrl = "https://dl.pstmn.io/download/latest/win64"
            FileName = "Postman-win64-Setup.exe"
            Description = "API development and testing tool"
            Category = "Testing"
            Size = "~200MB"
            Critical = $false
        }
    )
}

function Initialize-DownloadEnvironment {
    param([string]$BasePath)
    
    Write-LogMessage "Initializing download environment at: $BasePath"
    
    # Create main download directory
    if (-not (Test-Path $BasePath)) {
        New-Item -ItemType Directory -Path $BasePath -Force | Out-Null
        Write-LogMessage "Created download directory: $BasePath"
    }
    
    # Create category subdirectories
    $Categories = @("Database", "Development", "Utilities", "Testing", "Packages", "Documentation")
    foreach ($Category in $Categories) {
        $CategoryPath = Join-Path $BasePath $Category
        if (-not (Test-Path $CategoryPath)) {
            New-Item -ItemType Directory -Path $CategoryPath -Force | Out-Null
            Write-LogMessage "Created category directory: $Category"
        }
    }
    
    # Create manifest file
    $ManifestPath = Join-Path $BasePath "INSTALLATION_MANIFEST.txt"
    $Manifest = "Generic Log Handler - Offline Installation Package`n" +
    "Generated: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')`n" +
    "Download Path: $BasePath`n`n" +
    "INSTALLATION ORDER:`n" +
    "1. Database/db2-community-edition-*.exe (Install IBM DB2 first)`n" +
    "2. Database/ibm-data-studio-*.exe (Install IBM Data Studio)`n" +
    "3. Development/dotnet-*.exe (Install all .NET components)`n" +
    "4. Development/vs_community.exe (Install Visual Studio)`n" +
    "5. Utilities/* (Install utilities as needed)`n`n" +
    "SPECIAL REQUIREMENTS:`n" +
    "- IBM DB2 Client: Download from IBM Support portal if needed`n" +
    "- IBM Data Studio: Optional but recommended for DB2 administration`n`n" +
    "For detailed installation instructions, see Docs\TechnicalToolSelectionGuide.md"
    
    Set-Content -Path $ManifestPath -Value $Manifest -Encoding UTF8
    Write-LogMessage "Created installation manifest"
}

function Test-WingetAvailability {
    try {
        $null = Get-Command winget -ErrorAction Stop
        $wingetVersion = winget --version
        Write-LogMessage "Winget available: $wingetVersion"
        return $true
    } catch {
        Write-LogMessage "Winget not available on this system" -Level "WARN"
        return $false
    }
}

function Test-RequiredTools {
    $RequiredTools = @("Invoke-WebRequest", "New-Item", "Test-Path", "Get-ChildItem")
    $MissingTools = @()
    
    foreach ($Tool in $RequiredTools) {
        if (-not (Get-Command $Tool -ErrorAction SilentlyContinue)) {
            $MissingTools += $Tool
        }
    }
    
    if ($MissingTools.Count -gt 0) {
        Write-LogMessage "Missing required PowerShell cmdlets: $($MissingTools -join ', ')" -Level "ERROR"
        return $false
    }
    
    Write-LogMessage "All required PowerShell cmdlets are available" -Level "INFO"
    return $true
}

function Download-WithWinget {
    param(
        [string]$WingetId,
        [string]$DestinationPath,
        [string]$FileName
    )
    
    try {
        Write-LogMessage "Downloading $WingetId using winget..."
        
        # Use winget download command (if available in newer versions)
        $wingetResult = winget download --id $WingetId --download-directory $DestinationPath 2>&1
        
        if ($LASTEXITCODE -eq 0) {
            Write-LogMessage "Successfully downloaded $WingetId" -Level "INFO"
            return $true
        } else {
            Write-LogMessage "Winget download failed for $WingetId : $wingetResult" -Level "WARN"
            return $false
        }
    } catch {
        Write-LogMessage "Error downloading with winget: $($_.Exception.Message)" -Level "ERROR"
        return $false
    }
}

function Download-WithWebClient {
    param(
        [string]$Url,
        [string]$DestinationPath,
        [string]$FileName
    )
    
    $FilePath = Join-Path $DestinationPath $FileName
    
    try {
        Write-LogMessage "Downloading $FileName from $Url..."
        
        # Use Invoke-WebRequest with progress and retry logic
        $ProgressPreference = 'SilentlyContinue'
        $MaxRetries = 3
        $RetryCount = 0
        
        do {
            try {
                Invoke-WebRequest -Uri $Url -OutFile $FilePath -UseBasicParsing -TimeoutSec 300
                break
            } catch {
                $RetryCount++
                if ($RetryCount -lt $MaxRetries) {
                    Write-LogMessage "Download attempt $RetryCount failed, retrying in 5 seconds..." -Level "WARN"
                    Start-Sleep -Seconds 5
                } else {
                    throw
                }
            }
        } while ($RetryCount -lt $MaxRetries)
        
        $ProgressPreference = 'Continue'
        
        if (Test-Path $FilePath) {
            $FileSize = (Get-Item $FilePath).Length
            $FileSizeMB = [math]::Round($FileSize / 1MB, 2)
            Write-LogMessage "Successfully downloaded $FileName ($FileSizeMB MB)" -Level "INFO"
            return $true
        } else {
            Write-LogMessage "Download failed: File not found at $FilePath" -Level "ERROR"
            return $false
        }
    } catch {
        Write-LogMessage "Error downloading $FileName : $($_.Exception.Message)" -Level "ERROR"
        return $false
    }
}

function Download-Tool {
    param(
        [hashtable]$Tool,
        [string]$CategoryPath,
        [bool]$UseWinget
    )
    
    $FilePath = Join-Path $CategoryPath $Tool.FileName
    
    # Check if file already exists
    if (Test-Path $FilePath) {
        $FileSize = (Get-Item $FilePath).Length
        $FileSizeMB = [math]::Round($FileSize / 1MB, 2)
        Write-LogMessage "File already exists: $($Tool.FileName) ($FileSizeMB MB) - Skipping download" -Level "INFO"
        return $true
    }
    
    $Success = $false
    
    # Try winget first if available and not skipped
    if ($UseWinget -and $Tool.WingetId) {
        $Success = Download-WithWinget -WingetId $Tool.WingetId -DestinationPath $CategoryPath -FileName $Tool.FileName
    }
    
    # Fallback to direct download if winget failed or not available
    if (-not $Success -and $Tool.DirectUrl) {
        $Success = Download-WithWebClient -Url $Tool.DirectUrl -DestinationPath $CategoryPath -FileName $Tool.FileName
    }
    
    if (-not $Success) {
        Write-LogMessage "Failed to download $($Tool.Name)" -Level "ERROR"
        return $false
    }
    
    return $true
}

function Create-NuGetPackageScript {
    param([string]$BasePath)
    
    $PackagesPath = Join-Path $BasePath "Packages"
    $ScriptPath = Join-Path $PackagesPath "Download-NuGetPackages.ps1"
    
    $NuGetScript = "#Requires -Version 5.1`n" +
    "<#`n" +
    ".SYNOPSIS`n" +
    "    Downloads NuGet packages for offline installation`n" +
    "    `n" +
    ".DESCRIPTION`n" +
    "    This script downloads all required NuGet packages for the Generic Log Handler project.`n" +
    "    Run this script on a machine with internet access, then copy the packages to the air-gapped server.`n" +
    "    `n" +
    ".PARAMETER PackagesPath`n" +
    "    Path where NuGet packages will be downloaded`n" +
    "#>`n`n" +
    "param(`n" +
    "    [string]`$PackagesPath = `".\packages`"`n" +
    ")`n`n" +
    "# Required NuGet packages for DB2-based Generic Log Handler`n" +
    "`$Packages = @(`n" +
    "    `"IBM.Data.DB2.Core:3.1.0.500`",`n" +
    "    `"IBM.EntityFrameworkCore:3.1.0.500`",`n" +
    "    `"Microsoft.EntityFrameworkCore:9.0.1`",`n" +
    "    `"Microsoft.EntityFrameworkCore.Tools:9.0.1`",`n" +
    "    `"Microsoft.EntityFrameworkCore.Design:9.0.1`",`n" +
    "    `"Microsoft.Extensions.Configuration:9.0.1`",`n" +
    "    `"Microsoft.Extensions.Configuration.Json:9.0.1`",`n" +
    "    `"Microsoft.Extensions.Logging:9.0.1`",`n" +
    "    `"Microsoft.Extensions.Logging.Abstractions:9.0.1`",`n" +
    "    `"Microsoft.Extensions.Configuration.Abstractions:9.0.1`",`n" +
    "    `"Microsoft.Extensions.DependencyInjection.Abstractions:9.0.1`",`n" +
    "    `"Microsoft.Extensions.Diagnostics.HealthChecks:8.0.0`",`n" +
    "    `"Microsoft.Extensions.Diagnostics.HealthChecks.EntityFrameworkCore:8.0.0`",`n" +
    "    `"Serilog.Extensions.Hosting:7.0.0`",`n" +
    "    `"Serilog.Sinks.File:5.0.0`",`n" +
    "    `"Serilog.Sinks.Console:5.0.0`",`n" +
    "    `"System.IO.FileSystem.Watcher:4.3.0`",`n" +
    "    `"Newtonsoft.Json:13.0.4`",`n" +
    "    `"System.Xml.XDocument:4.3.0`",`n" +
    "    `"CsvHelper:30.0.1`",`n" +
    "    `"System.Data.Odbc:8.0.0`",`n" +
    "    `"Microsoft.AspNetCore.Authentication.Negotiate:8.0.1`",`n" +
    "    `"Microsoft.AspNetCore.Authentication.JwtBearer:8.0.1`",`n" +
    "    `"Microsoft.AspNetCore.RateLimiting:7.0.0-rc.2.22476.2`",`n" +
    "    `"Microsoft.AspNetCore.OpenApi:10.0.2`",`n" +
    "    `"Scalar.AspNetCore:2.12.36`",`n" +
    "    `"System.ComponentModel.Annotations:5.0.0`",`n" +
    "    `"System.Linq.Dynamic.Core:1.6.9`"`n" +
    ")`n`n" +
    "Write-Host `"Creating NuGet packages directory: `$PackagesPath`"`n" +
    "if (-not (Test-Path `$PackagesPath)) {`n" +
    "    New-Item -ItemType Directory -Path `$PackagesPath -Force | Out-Null`n" +
    "}`n`n" +
    "Write-Host `"Downloading NuGet packages...`"`n" +
    "`$DownloadedCount = 0`n" +
    "`$FailedCount = 0`n`n" +
    "foreach (`$Package in `$Packages) {`n" +
    "    `$PackageName, `$Version = `$Package -split `":`"`n" +
    "    Write-Host `"Downloading `$PackageName version `$Version...`"`n" +
    "    `n" +
    "    try {`n" +
    "        # Check if nuget command is available`n" +
    "        if (-not (Get-Command nuget -ErrorAction SilentlyContinue)) {`n" +
    "            Write-Host `"✗ NuGet CLI not found. Please install NuGet CLI or use dotnet restore instead.`" -ForegroundColor Red`n" +
    "            `$FailedCount++`n" +
    "            continue`n" +
    "        }`n" +
    "        `n" +
    "        nuget install `$PackageName -Version `$Version -OutputDirectory `$PackagesPath -NoCache -NonInteractive`n" +
    "        Write-Host `"✓ Downloaded `$PackageName`" -ForegroundColor Green`n" +
    "        `$DownloadedCount++`n" +
    "    } catch {`n" +
    "        Write-Host `"✗ Failed to download `$PackageName : `$(`$_.Exception.Message)`" -ForegroundColor Red`n" +
    "        `$FailedCount++`n" +
    "    }`n" +
    "}`n`n" +
    "Write-Host `"`nNuGet Package Download Summary:`" -ForegroundColor Cyan`n" +
    "Write-Host `"Successfully downloaded: `$DownloadedCount`" -ForegroundColor Green`n" +
    "Write-Host `"Failed downloads: `$FailedCount`" -ForegroundColor Red`n`n" +
    "Write-Host `"`nNuGet packages downloaded to: `$PackagesPath`"`n" +
    "Write-Host `"Copy this folder to your air-gapped server and use 'dotnet add package' with --source parameter`""

    Set-Content -Path $ScriptPath -Value $NuGetScript -Encoding UTF8
    Write-LogMessage "Created NuGet package download script: $ScriptPath"
}

function Create-InstallationScript {
    param([string]$BasePath)
    
    $ScriptPath = Join-Path $BasePath "Install-All.ps1"
    
    $InstallScript = "#Requires -Version 5.1 -RunAsAdministrator`n" +
    "<#`n" +
    ".SYNOPSIS`n" +
    "    Installs all downloaded tools for Generic Log Handler implementation`n" +
    "    `n" +
    ".DESCRIPTION`n" +
    "    This script installs all previously downloaded tools in the correct order`n" +
    "    for air-gapped Generic Log Handler implementation.`n" +
    "    `n" +
    ".PARAMETER InstallPath`n" +
    "    Base path where tools were downloaded`n" +
    "#>`n`n" +
    "param(`n" +
    "    [string]`$InstallPath = \`"C:\LoggingToolsDownload\`"`n" +
    ")`n`n" +
    "function Install-Tool {`n" +
    "    param(`n" +
    "        [string]`$Path,`n" +
    "        [string]`$Arguments = \`"/VERYSILENT /NORESTART\`"`n" +
    "    )`n" +
    "    `n" +
    "    if (Test-Path `$Path) {`n" +
    "        Write-Host \`"Installing: `$(Split-Path `$Path -Leaf)\`"`n" +
    "        Start-Process -FilePath `$Path -ArgumentList `$Arguments -Wait -NoNewWindow`n" +
    "        Write-Host \`"✓ Completed: `$(Split-Path `$Path -Leaf)\`" -ForegroundColor Green`n" +
    "    } else {`n" +
    "        Write-Host \`"✗ Not found: `$Path\`" -ForegroundColor Red`n" +
    "    }`n" +
    "}`n`n" +
    "Write-Host \`"=== Generic Log Handler - Offline Installation ===\`" -ForegroundColor Yellow`n" +
    "Write-Host \`"Installation Path: `$InstallPath\`" -ForegroundColor Cyan`n`n" +
    "# Install in order of dependencies`n" +
    "Write-Host \`"`n1. Installing Core Database Tools...\`" -ForegroundColor Yellow`n" +
    "`$DB2Files = Get-ChildItem -Path (Join-Path `$InstallPath \`"Database\`") -Filter \`"db2-community-edition-*.exe\`" -ErrorAction SilentlyContinue`n" +
    "if (`$DB2Files) {`n" +
    "    Write-Host \`"Installing IBM DB2 12.1 Community Edition...\`"`n" +
    "    Install-Tool `$DB2Files[0].FullName \`"/SILENT\`"`n" +
    "    Write-Host \`"Note: DB2 installation may require manual configuration steps\`"`n" +
    "}`n`n" +
    "`$DataStudioFiles = Get-ChildItem -Path (Join-Path `$InstallPath \`"Database\`") -Filter \`"ibm-data-studio-*.exe\`" -ErrorAction SilentlyContinue`n" +
    "if (`$DataStudioFiles) {`n" +
    "    Install-Tool `$DataStudioFiles[0].FullName \`"/SILENT\`"`n" +
    "}`n`n" +
    "Write-Host \`"`n2. Installing .NET Development Platform...\`" -ForegroundColor Yellow`n" +
    "`$RuntimeFiles = Get-ChildItem -Path (Join-Path `$InstallPath \`"Development\`") -Filter \`"dotnet-runtime-*-win-x64.exe\`" -ErrorAction SilentlyContinue`n" +
    "if (`$RuntimeFiles) {`n" +
    "    Install-Tool `$RuntimeFiles[0].FullName \`"/quiet\`"`n" +
    "}`n`n" +
    "`$AspNetCoreFiles = Get-ChildItem -Path (Join-Path `$InstallPath \`"Development\`") -Filter \`"aspnetcore-runtime-*-win-x64.exe\`" -ErrorAction SilentlyContinue`n" +
    "if (`$AspNetCoreFiles) {`n" +
    "    Install-Tool `$AspNetCoreFiles[0].FullName \`"/quiet\`"`n" +
    "}`n`n" +
    "`$SDKFiles = Get-ChildItem -Path (Join-Path `$InstallPath \`"Development\`") -Filter \`"dotnet-sdk-*-win-x64.exe\`" -ErrorAction SilentlyContinue`n" +
    "if (`$SDKFiles) {`n" +
    "    Install-Tool `$SDKFiles[0].FullName \`"/quiet\`"`n" +
    "}`n`n" +
    "Write-Host \`"`n3. Installing Utilities...\`" -ForegroundColor Yellow`n" +
    "`$GitFiles = Get-ChildItem -Path (Join-Path `$InstallPath \`"Utilities\`") -Filter \`"Git-*-64-bit.exe\`" -ErrorAction SilentlyContinue`n" +
    "if (`$GitFiles) {`n" +
    "    Install-Tool `$GitFiles[0].FullName \`"/VERYSILENT\`"`n" +
    "}`n`n" +
    "`$SevenZipFiles = Get-ChildItem -Path (Join-Path `$InstallPath \`"Utilities\`") -Filter \`"7z*-x64.exe\`" -ErrorAction SilentlyContinue`n" +
    "if (`$SevenZipFiles) {`n" +
    "    Install-Tool `$SevenZipFiles[0].FullName \`"/S\`"`n" +
    "}`n`n" +
    "`$NotepadFiles = Get-ChildItem -Path (Join-Path `$InstallPath \`"Utilities\`") -Filter \`"npp.*.Installer.x64.exe\`" -ErrorAction SilentlyContinue`n" +
    "if (`$NotepadFiles) {`n" +
    "    Install-Tool `$NotepadFiles[0].FullName \`"/S\`"`n" +
    "}`n`n" +
    "Write-Host \`"`n4. Installing Optional Tools...\`" -ForegroundColor Yellow`n" +
    "`$DBeaverFiles = Get-ChildItem -Path (Join-Path `$InstallPath \`"Database\`") -Filter \`"dbeaver-ce-*-x86_64-setup.exe\`" -ErrorAction SilentlyContinue`n" +
    "if (`$DBeaverFiles) {`n" +
    "    Install-Tool `$DBeaverFiles[0].FullName`n" +
    "}`n`n" +
    "`$PostmanFiles = Get-ChildItem -Path (Join-Path `$InstallPath \`"Testing\`") -Filter \`"Postman-win64-Setup.exe\`" -ErrorAction SilentlyContinue`n" +
    "if (`$PostmanFiles) {`n" +
    "    Install-Tool `$PostmanFiles[0].FullName`n" +
    "}`n`n" +
    "Write-Host \`"`n5. Installing Visual Studio (this may take a while)...\`" -ForegroundColor Yellow`n" +
    "`$VSInstaller = Join-Path `$InstallPath \`"Development\vs_community.exe\`"`n" +
    "if (Test-Path `$VSInstaller) {`n" +
    "    Write-Host \`"Starting Visual Studio installation...\`"`n" +
    "    & `$VSInstaller --quiet --wait --add Microsoft.VisualStudio.Workload.NetWeb --add Microsoft.VisualStudio.Workload.ManagedDesktop`n" +
    "}`n`n" +
    "Write-Host \`"`n=== Installation Complete ===\`" -ForegroundColor Green`n" +
    "Write-Host \`"Next Steps:\`" -ForegroundColor Cyan`n" +
    "Write-Host \`"1. Configure IBM DB2 (see DatabaseSchemas/DB2_Installation_Guide.md)\`"`n" +
    "Write-Host \`"2. Install IBM DB2 Client if needed\`"`n" +
    "Write-Host \`"3. Set up development environment\`"`n" +
    "Write-Host \`"4. Run database schema setup (see DatabaseSchemas/DB2_Schema.sql)\`""

    Set-Content -Path $ScriptPath -Value $InstallScript -Encoding UTF8
    Write-LogMessage "Created installation script: $ScriptPath"
}

function Create-DocumentationPackage {
    param([string]$BasePath)
    
    $DocsPath = Join-Path $BasePath "Documentation"
    
    # Copy existing documentation files
    $DocFiles = @(
        "Docs\TechnicalToolSelectionGuide.md",
        "Docs\LoggingToolSpecification.md",
        "Docs\DatabaseSolutionsComparison.md"
    )
    
    foreach ($DocFile in $DocFiles) {
        if (Test-Path $DocFile) {
            Copy-Item $DocFile -Destination $DocsPath -Force
            Write-LogMessage "Copied documentation: $DocFile"
        }
    }
    
    # Copy sample configurations
    $ConfigPath = Join-Path $DocsPath "sample-configurations"
    if (-not (Test-Path $ConfigPath)) {
        New-Item -ItemType Directory -Path $ConfigPath -Force | Out-Null
    }
    
    if (Test-Path "sample-configurations") {
        Copy-Item "sample-configurations\*" -Destination $ConfigPath -Recurse -Force
        Write-LogMessage "Copied sample configurations"
    }
}

# Main execution
Write-LogMessage "Starting Generic Log Handler tools download..." -Level "INFO"
Write-LogMessage "Download path: $DownloadPath" -Level "INFO"

# Validate required tools
if (-not (Test-RequiredTools)) {
    Write-LogMessage "Required tools validation failed. Exiting." -Level "ERROR"
    exit 1
}

# Initialize environment
Initialize-DownloadEnvironment -BasePath $DownloadPath

# Check winget availability
$WingetAvailable = $false
if (-not $SkipWinget) {
    $WingetAvailable = Test-WingetAvailability
}

# Download summary
$TotalTools = 0
$SuccessfulDownloads = 0
$FailedDownloads = @()

# Download all tools by category
foreach ($Category in $Tools.Keys) {
    Write-LogMessage "Processing category: $Category" -Level "INFO"
    
    $CategoryPath = Join-Path $DownloadPath (($Tools[$Category][0].Category))
    
    foreach ($Tool in $Tools[$Category]) {
        $TotalTools++
        
        Write-LogMessage "Downloading: $($Tool.Name) ($($Tool.Size))"
        
        $Success = Download-Tool -Tool $Tool -CategoryPath $CategoryPath -UseWinget $WingetAvailable
        
        if ($Success) {
            $SuccessfulDownloads++
        } else {
            $FailedDownloads += $Tool.Name
        }
    }
}

# Create additional scripts and documentation
Write-LogMessage "Creating additional scripts and documentation..."
Create-NuGetPackageScript -BasePath $DownloadPath
Create-InstallationScript -BasePath $DownloadPath
Create-DocumentationPackage -BasePath $DownloadPath

# Create special downloads instructions
$SpecialPath = Join-Path $DownloadPath "SPECIAL_DOWNLOADS.txt"
$SpecialInstructions = "SPECIAL DOWNLOADS REQUIRED`n" +
"==========================`n`n" +
"The following items require manual download due to licensing or access restrictions:`n`n" +
"1. IBM DB2 CLIENT (if needed)`n" +
"   URL: https://www.ibm.com/support/pages/db2-clients-and-drivers`n" +
"   Download: IBM Data Server Runtime Client v12.1`n" +
"   Notes: Requires IBM account, download v12.1.0.x for Windows x64`n`n" +
"2. VISUAL STUDIO OFFLINE INSTALLER (optional)`n" +
"   Command: vs_community.exe --layout C:\VSOffline --add Microsoft.VisualStudio.Workload.NetWeb`n" +
"   Notes: Run this on internet-connected machine to create full offline installer`n`n" +
"OPTIONAL TOOLS:`n" +
"- JetBrains DataGrip (commercial license required)`n" +
"- Docker Desktop (requires Windows Pro/Enterprise)`n`n" +
"For detailed installation instructions, see Documentation\TechnicalToolSelectionGuide.md"

Set-Content -Path $SpecialPath -Value $SpecialInstructions -Encoding UTF8

# Final summary
Write-LogMessage "=== DOWNLOAD SUMMARY ===" -Level "INFO"
Write-LogMessage "Total tools: $TotalTools" -Level "INFO"
Write-LogMessage "Successfully downloaded: $SuccessfulDownloads" -Level "INFO"
Write-LogMessage "Failed downloads: $($FailedDownloads.Count)" -Level "INFO"

if ($FailedDownloads.Count -gt 0) {
    Write-LogMessage "Failed tools:" -Level "WARN"
    foreach ($Failed in $FailedDownloads) {
        Write-LogMessage "  - $Failed" -Level "WARN"
    }
}

Write-LogMessage "Download location: $DownloadPath" -Level "INFO"
Write-LogMessage "Next step: Copy entire folder to air-gapped server and run Install-All.ps1" -Level "INFO"

# Calculate total download size
$TotalSize = 0
Get-ChildItem -Path $DownloadPath -Recurse -File | ForEach-Object {
    $TotalSize += $_.Length
}
$TotalSizeMB = [math]::Round($TotalSize / 1MB, 2)
Write-LogMessage "Total download size: $TotalSizeMB MB" -Level "INFO"

Write-LogMessage "Generic Log Handler tools download completed!" -Level "INFO"
