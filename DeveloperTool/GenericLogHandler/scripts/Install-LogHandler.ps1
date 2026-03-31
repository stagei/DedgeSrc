#Requires -Version 5.1 -RunAsAdministrator
<#
.SYNOPSIS
    Installs and configures the Generic Log Handler system on Windows Server 2025

.DESCRIPTION
    This script installs all components of the Generic Log Handler system:
    - PostgreSQL database with TimescaleDB
    - Import service as Windows service
    - Web API as IIS application (serves API and static web UI from wwwroot)
    - Configuration and initial setup

.PARAMETER InstallPath
    Base installation path. Default is C:\GenericLogHandler

.PARAMETER DatabasePassword
    Password for the postgres database user

.PARAMETER SkipDatabase
    Skip database installation (assumes PostgreSQL is already installed)

.EXAMPLE
    .\Install-LogHandler.ps1 -DatabasePassword "SecurePassword123"
#>

[CmdletBinding()]
param(
    [Parameter(Mandatory = $false)]
    [string]$InstallPath = "C:\GenericLogHandler",
    
    [Parameter(Mandatory = $true)]
    [SecureString]$DatabasePassword,
    
    [Parameter(Mandatory = $false)]
    [switch]$SkipDatabase
)

# Import GlobalFunctions if available
try {
    Import-Module GlobalFunctions -Force -ErrorAction SilentlyContinue
} catch {
    function Write-LogMessage {
        param([string]$Message, [string]$Level = "INFO")
        $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
        Write-Host "[$timestamp] [$Level] $Message"
    }
}

function Test-Administrator {
    $currentUser = [Security.Principal.WindowsIdentity]::GetCurrent()
    $principal = New-Object Security.Principal.WindowsPrincipal($currentUser)
    return $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}

function Install-Prerequisites {
    Write-LogMessage "Installing prerequisites..." -Level "INFO"
    
    # Check for .NET 8
    $dotnetVersion = dotnet --version 2>$null
    if (-not $dotnetVersion -or $dotnetVersion -notmatch "^8\.") {
        Write-LogMessage "Installing .NET 8 SDK..." -Level "INFO"
        $dotnetInstaller = Join-Path $env:TEMP "dotnet-sdk-8.0.101-win-x64.exe"
        Invoke-WebRequest -Uri "https://download.microsoft.com/download/8/4/8/848036c1-61b0-4651-b36e-3ca0bb0d52c1/dotnet-sdk-8.0.101-win-x64.exe" -OutFile $dotnetInstaller
        Start-Process -FilePath $dotnetInstaller -ArgumentList "/quiet" -Wait -NoNewWindow
        Remove-Item $dotnetInstaller -Force
    }
    
    Write-LogMessage "Prerequisites installed successfully" -Level "INFO"
}

function Install-Database {
    if ($SkipDatabase) {
        Write-LogMessage "Skipping database installation" -Level "INFO"
        return
    }
    
    Write-LogMessage "Installing PostgreSQL..." -Level "INFO"
    
    # Download and install PostgreSQL
    $pgInstaller = Join-Path $env:TEMP "postgresql-16.1-1-windows-x64.exe"
    if (-not (Test-Path $pgInstaller)) {
        Write-LogMessage "Downloading PostgreSQL installer..." -Level "INFO"
        Invoke-WebRequest -Uri "https://get.enterprisedb.com/postgresql/postgresql-16.1-1-windows-x64.exe" -OutFile $pgInstaller
    }
    
    # Convert SecureString to plain text for installation
    $plainPassword = [System.Runtime.InteropServices.Marshal]::PtrToStringAuto([System.Runtime.InteropServices.Marshal]::SecureStringToBSTR($DatabasePassword))
    
    $installArgs = @(
        "--mode", "unattended",
        "--superpassword", $plainPassword,
        "--servicename", "postgresql-x64-16",
        "--datadir", "C:\Program Files\PostgreSQL\16\data",
        "--prefix", "C:\Program Files\PostgreSQL\16"
    )
    
    Start-Process -FilePath $pgInstaller -ArgumentList $installArgs -Wait -NoNewWindow
    
    # Add PostgreSQL to PATH
    $pgPath = "C:\Program Files\PostgreSQL\16\bin"
    $currentPath = [Environment]::GetEnvironmentVariable("PATH", "Machine")
    if ($currentPath -notlike "*$pgPath*") {
        [Environment]::SetEnvironmentVariable("PATH", "$currentPath;$pgPath", "Machine")
        $env:PATH += ";$pgPath"
    }
    
    # Install TimescaleDB
    Write-LogMessage "Installing TimescaleDB..." -Level "INFO"
    $timescaleInstaller = Join-Path $env:TEMP "timescaledb-postgresql-16-2.13.0-windows-amd64.zip"
    if (-not (Test-Path $timescaleInstaller)) {
        Write-LogMessage "Downloading TimescaleDB..." -Level "INFO"
        Invoke-WebRequest -Uri "https://github.com/timescale/timescaledb/releases/download/2.13.0/timescaledb-postgresql-16-2.13.0-windows-amd64.zip" -OutFile $timescaleInstaller
    }
    
    # Extract and install TimescaleDB
    $extractPath = Join-Path $env:TEMP "timescaledb"
    Expand-Archive -Path $timescaleInstaller -DestinationPath $extractPath -Force
    & (Join-Path $extractPath "timescaledb-postgresql-16-2.13.0-windows-amd64\setup.exe") --yes
    
    Write-LogMessage "Database installation completed" -Level "INFO"
}

function Setup-Database {
    Write-LogMessage "Setting up database schema..." -Level "INFO"
    
    $plainPassword = [System.Runtime.InteropServices.Marshal]::PtrToStringAuto([System.Runtime.InteropServices.Marshal]::SecureStringToBSTR($DatabasePassword))
    $env:PGPASSWORD = $plainPassword
    
    # Create database
    try {
        $createDbResult = & psql -U postgres -c "CREATE DATABASE logs;" 2>&1
        if ($LASTEXITCODE -eq 0 -or $createDbResult -like "*already exists*") {
            Write-LogMessage "Database 'logs' created or already exists" -Level "INFO"
        }
    } catch {
        Write-LogMessage "Error creating database: $($_.Exception.Message)" -Level "ERROR"
    }
    
    # Enable TimescaleDB extension
    try {
        & psql -U postgres -d logs -c "CREATE EXTENSION IF NOT EXISTS timescaledb;"
        Write-LogMessage "TimescaleDB extension enabled" -Level "INFO"
    } catch {
        Write-LogMessage "Error enabling TimescaleDB: $($_.Exception.Message)" -Level "ERROR"
    }
    
    # Run schema creation script
    $schemaFile = Join-Path $InstallPath "schema\clickhouse-schema.sql"
    if (Test-Path $schemaFile) {
        try {
            & psql -U postgres -d logs -f $schemaFile
            Write-LogMessage "Database schema created successfully" -Level "INFO"
        } catch {
            Write-LogMessage "Error creating schema: $($_.Exception.Message)" -Level "ERROR"
        }
    }
    
    Remove-Item Env:\PGPASSWORD
}

function Install-ImportService {
    Write-LogMessage "Installing Import Service..." -Level "INFO"
    
    $servicePath = Join-Path $InstallPath "ImportService"
    New-Item -ItemType Directory -Path $servicePath -Force | Out-Null
    
    # Build and publish the import service
    $srcPath = Join-Path $PSScriptRoot "..\src\GenericLogHandler.ImportService"
    if (Test-Path $srcPath) {
        Set-Location $srcPath
        dotnet publish -c Release -o $servicePath --self-contained false
        Set-Location $PSScriptRoot
    }
    
    # Create Windows service
    $serviceExe = Join-Path $servicePath "GenericLogHandler.ImportService.exe"
    if (Test-Path $serviceExe) {
        # Remove existing service if it exists
        $existingService = Get-Service -Name "GenericLogHandlerImport" -ErrorAction SilentlyContinue
        if ($existingService) {
            Stop-Service -Name "GenericLogHandlerImport" -Force
            & sc.exe delete "GenericLogHandlerImport"
        }
        
        # Create new service
        New-Service -Name "GenericLogHandlerImport" -BinaryPathName $serviceExe -DisplayName "Generic Log Handler Import Service" -Description "Imports logs from multiple sources" -StartupType Automatic
        
        Write-LogMessage "Import Service installed successfully" -Level "INFO"
    } else {
        Write-LogMessage "Import Service executable not found" -Level "ERROR"
    }
}

function Install-WebApi {
    Write-LogMessage "Installing Web API..." -Level "INFO"
    
    # Enable IIS and ASP.NET Core hosting
    Enable-WindowsOptionalFeature -Online -FeatureName IIS-WebServerRole, IIS-WebServer, IIS-CommonHttpFeatures, IIS-HttpErrors, IIS-HttpLogging, IIS-RequestFiltering, IIS-StaticContent, IIS-NetFxExtensibility45, IIS-ASPNET45 -All
    
    # Install ASP.NET Core Hosting Bundle
    $hostingBundle = Join-Path $env:TEMP "dotnet-hosting-8.0.1-win.exe"
    if (-not (Test-Path $hostingBundle)) {
        Write-LogMessage "Downloading ASP.NET Core Hosting Bundle..." -Level "INFO"
        Invoke-WebRequest -Uri "https://download.microsoft.com/download/8/4/8/848036c1-61b0-4651-b36e-3ca0bb0d52c1/dotnet-hosting-8.0.1-win.exe" -OutFile $hostingBundle
    }
    Start-Process -FilePath $hostingBundle -ArgumentList "/quiet" -Wait -NoNewWindow
    
    # Restart IIS
    iisreset
    
    $apiPath = Join-Path $InstallPath "WebAPI"
    New-Item -ItemType Directory -Path $apiPath -Force | Out-Null
    
    # Build and publish the Web API
    $srcPath = Join-Path $PSScriptRoot "..\src\GenericLogHandler.WebApi"
    if (Test-Path $srcPath) {
        Set-Location $srcPath
        dotnet publish -c Release -o $apiPath --self-contained false
        Set-Location $PSScriptRoot
    }
    
    # Create IIS application
    Import-Module WebAdministration -Force
    
    # Remove existing application if it exists
    if (Get-WebApplication -Name "LogHandlerAPI" -Site "Default Web Site" -ErrorAction SilentlyContinue) {
        Remove-WebApplication -Name "LogHandlerAPI" -Site "Default Web Site"
    }
    
    # Create new application
    New-WebApplication -Name "LogHandlerAPI" -Site "Default Web Site" -PhysicalPath $apiPath -ApplicationPool "DefaultAppPool"
    
    Write-LogMessage "Web API installed successfully" -Level "INFO"
}

function Create-Configuration {
    Write-LogMessage "Creating configuration files..." -Level "INFO"
    
    $configPath = Join-Path $InstallPath "Config"
    New-Item -ItemType Directory -Path $configPath -Force | Out-Null
    
    # Copy sample configuration
    $sampleConfig = Join-Path $PSScriptRoot "..\sample-configurations\import-config.json"
    $targetConfig = Join-Path $configPath "import-config.json"
    
    if (Test-Path $sampleConfig) {
        Copy-Item -Path $sampleConfig -Destination $targetConfig -Force
        
        # Update database connection string
        $plainPassword = [System.Runtime.InteropServices.Marshal]::PtrToStringAuto([System.Runtime.InteropServices.Marshal]::SecureStringToBSTR($DatabasePassword))
        $connectionString = "Host=localhost;Database=logs;Username=postgres;Password=$plainPassword"
        
        $config = Get-Content $targetConfig | ConvertFrom-Json
        $config.database.connection_string = $connectionString
        $config | ConvertTo-Json -Depth 10 | Set-Content $targetConfig
        
        Write-LogMessage "Configuration file created: $targetConfig" -Level "INFO"
    }
    
    # Create appsettings.json for Web API
    $apiSettings = @{
        "ConnectionStrings" = @{
            "DefaultConnection" = "Host=localhost;Database=logs;Username=postgres;Password=$([System.Runtime.InteropServices.Marshal]::PtrToStringAuto([System.Runtime.InteropServices.Marshal]::SecureStringToBSTR($DatabasePassword)))"
        }
        "Logging" = @{
            "LogLevel" = @{
                "Default" = "Information"
                "Microsoft.AspNetCore" = "Warning"
            }
        }
        "AllowedHosts" = "*"
    }
    
    $apiSettingsPath = Join-Path $InstallPath "WebAPI\appsettings.json"
    $apiSettings | ConvertTo-Json -Depth 5 | Set-Content $apiSettingsPath
}

function Start-Services {
    Write-LogMessage "Starting services..." -Level "INFO"
    
    # Start Import Service
    Start-Service -Name "GenericLogHandlerImport" -ErrorAction SilentlyContinue
    
    # Restart IIS
    iisreset
    
    Write-LogMessage "Services started successfully" -Level "INFO"
}

function Test-Installation {
    Write-LogMessage "Testing installation..." -Level "INFO"
    
    # Test database connection
    try {
        $plainPassword = [System.Runtime.InteropServices.Marshal]::PtrToStringAuto([System.Runtime.InteropServices.Marshal]::SecureStringToBSTR($DatabasePassword))
        $env:PGPASSWORD = $plainPassword
        $dbTest = & psql -U postgres -d logs -c "SELECT 1;" 2>&1
        if ($LASTEXITCODE -eq 0) {
            Write-LogMessage "Database connection: OK" -Level "INFO"
        } else {
            Write-LogMessage "Database connection: FAILED - $dbTest" -Level "ERROR"
        }
        Remove-Item Env:\PGPASSWORD
    } catch {
        Write-LogMessage "Database test error: $($_.Exception.Message)" -Level "ERROR"
    }
    
    # Test Import Service
    $importService = Get-Service -Name "GenericLogHandlerImport" -ErrorAction SilentlyContinue
    if ($importService -and $importService.Status -eq "Running") {
        Write-LogMessage "Import Service: Running" -Level "INFO"
    } else {
        Write-LogMessage "Import Service: Not running" -Level "WARN"
    }
    
    # Test Web API
    try {
        $apiResponse = Invoke-WebRequest -Uri "http://localhost/LogHandlerAPI/health" -UseBasicParsing -TimeoutSec 10 -ErrorAction SilentlyContinue
        if ($apiResponse.StatusCode -eq 200) {
            Write-LogMessage "Web API: OK" -Level "INFO"
        } else {
            Write-LogMessage "Web API: Response code $($apiResponse.StatusCode)" -Level "WARN"
        }
    } catch {
        Write-LogMessage "Web API: Not accessible" -Level "WARN"
    }
    
    # Web UI is served from same WebApi (wwwroot)
    try {
        $uiResponse = Invoke-WebRequest -Uri "http://localhost/LogHandlerAPI/" -UseBasicParsing -TimeoutSec 10 -ErrorAction SilentlyContinue
        if ($uiResponse.StatusCode -eq 200) {
            Write-LogMessage "Web UI (WebApi): OK" -Level "INFO"
        } else {
            Write-LogMessage "Web UI: Response code $($uiResponse.StatusCode)" -Level "WARN"
        }
    } catch {
        Write-LogMessage "Web UI: Not accessible" -Level "WARN"
    }
}

# Main installation process
try {
    Write-LogMessage "Starting Generic Log Handler installation..." -Level "INFO"
    Write-LogMessage "Installation path: $InstallPath" -Level "INFO"
    
    if (-not (Test-Administrator)) {
        throw "This script must be run as Administrator"
    }
    
    # Create installation directory
    New-Item -ItemType Directory -Path $InstallPath -Force | Out-Null
    
    # Installation steps
    Install-Prerequisites
    Install-Database
    Setup-Database
    Install-ImportService
    Install-WebApi
    Create-Configuration
    Start-Services
    Test-Installation
    
    Write-LogMessage "=== INSTALLATION COMPLETE ===" -Level "INFO"
    Write-LogMessage "Web UI and API: http://localhost/LogHandlerAPI (single app; UI served from wwwroot)" -Level "INFO"
    Write-LogMessage "Installation Directory: $InstallPath" -Level "INFO"
    Write-LogMessage "" -Level "INFO"
    Write-LogMessage "Next Steps:" -Level "INFO"
    Write-LogMessage "1. Configure log sources in: $InstallPath\Config\import-config.json" -Level "INFO"
    Write-LogMessage "2. Open the web interface at http://localhost/LogHandlerAPI" -Level "INFO"
    Write-LogMessage "3. Check service status in Services.msc" -Level "INFO"
    
} catch {
    Write-LogMessage "Installation failed: $($_.Exception.Message)" -Level "ERROR"
    Write-LogMessage "Check the log for details and try again" -Level "ERROR"
    exit 1
}
