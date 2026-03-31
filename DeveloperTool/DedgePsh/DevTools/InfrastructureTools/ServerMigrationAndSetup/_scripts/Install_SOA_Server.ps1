

# Check PowerShell version
if ($PSVersionTable.PSVersion.Major -lt 7) {
    Write-Host "This script requires PowerShell 7 or newer. Current version is $($PSVersionTable.PSVersion)" -ForegroundColor Red
    throw "PowerShell version requirement not met"
}

# Import SoftwareUtils module
$modulePath = Join-Path $PSScriptRoot "SoftwareUtils.psm1"
if (-not (Test-Path $modulePath)) {
    Write-Host "SoftwareUtils module not found at: $modulePath" -ForegroundColor Red
    throw "Required module not found"
}
Import-Module $modulePath -Force

Write-Host "------------------------------------------------------------------------------------------------"
Write-Host " SOA server/Web server installation" -ForegroundColor Yellow
Write-Host "------------------------------------------------------------------------------------------------"

# Verify network paths
$serverSetupPath = "dedge-server\ServerSetup\_install"
$pathsToCheck = @(
    "$serverSetupPath\dotnet-hosting-9.0.1-win.exe",
    "$serverSetupPath\ibm_db2_client_winx64_v11.5\CLIENT\image\setup.exe",
    "$serverSetupPath\ObjRexx\setup.exe",
    "$serverSetupPath\MicroFocusCobol\MF_Server_SOA\dvd-sv51-mf002\setup.exe",
    "$serverSetupPath\MicroFocusCobol\MicroFocusServer_51\setup.exe"
)

Write-Host "`nVerifying installation files..." -NoNewline
$missingPaths = @()
foreach ($path in $pathsToCheck) {
    if (-not (Test-Path -Path $path)) {
        $missingPaths += $path
    }
}

if ($missingPaths.Count -gt 0) {
    Write-Host " Failed!" -ForegroundColor Red
    Write-Host "The following required files are missing:"
    $missingPaths | ForEach-Object { Write-Host " - $_" -ForegroundColor Red }
    $abort = Read-Host "Do you want to abort the script? (Y/N)"
    if ($abort.ToUpper() -eq 'Y') {
        throw "Installation aborted - missing required files"
    }
} else {
    Write-Host " Success!" -ForegroundColor Green
}

#------------------------------------------------------------------------------------------------
# Create TEMPFK and OPT folders
Write-Host "`nCreating needed folder structure..." -NoNewline
try {
    if (-not (Test-Path -Path "C:\TEMPFK")) {
        New-Item -Path "C:\TEMPFK" -ItemType Directory -Force | Out-Null
    }

    if (-not (Test-Path -Path "$env:OptPath\DedgePshApps")) {
        New-Item -Path "$env:OptPath\DedgePshApps" -ItemType Directory -Force | Out-Null
    }

    if (-not (Test-Path -Path "$env:OptPath\data")) {
        New-Item -Path "$env:OptPath\data" -ItemType Directory -Force | Out-Null
    }

    if (-not (Test-Path -Path "$env:OptPath\PSModules")) {
        New-Item -Path "$env:OptPath\PSModules" -ItemType Directory -Force | Out-Null
    }

    Write-Host " Success!" -ForegroundColor Green
    Write-Host "Folder structure created successfully" -ForegroundColor Green
}
catch {
    Write-Host " Failed!" -ForegroundColor Red
    Write-Host $("Failed to create C:\TEMPFK folder: " + $_)
    $abort = Read-Host "Do you want to abort the script? (Y/N)"
    if ($abort.ToUpper() -eq 'Y') {
        throw "Installation aborted"
    }
}

#------------------------------------------------------------------------------------------------
# Install IIS Features

# Ask about CGI installation
Write-Host "`nCGI support is required if the server will run Micro Focus Enterprise Server (SOA) or Visual COBOL Enterprise Server (SOA)."
$installCGI = Read-Host "Do you want to install CGI support? (Y/N)"
$includeCGI = $installCGI.ToUpper() -eq 'Y'

Write-Host "`nInstalling IIS Features..." -NoNewline
try {
    Import-Module ServerManager

    $features = @(
        # Web Server Basic Features
        'Web-Server',
        'Web-WebServer',
        # Common HTTP Features
        'Web-Common-Http',
        'Web-Default-Doc',
        'Web-Dir-Browsing',
        'Web-Http-Errors',
        'Web-Static-Content',
        # Health and Diagnostics
        'Web-Health',
        'Web-Http-Logging',
        # Performance
        'Web-Performance',
        'Web-Stat-Compression',
        # Security
        'Web-Security',
        'Web-Filtering',
        'Web-Basic-Auth',
        'Web-Windows-Auth',
        # Application Development
        'Web-App-Dev',
        'Web-Net-Ext45',
        'Web-Asp-Net45',
        'Web-ISAPI-Ext',
        'Web-ISAPI-Filter',
        # Management Tools
        'Web-Mgmt-Tools',
        'Web-Mgmt-Console',
        # .NET Framework 4.8 Features
        'NET-Framework-45-Core',
        'NET-Framework-45-ASPNET',
        'NET-WCF-Services45',
        'NET-WCF-HTTP-Activation45',
        'NET-WCF-TCP-PortSharing45',
        # Process Model and Config APIs
        'WAS-Process-Model',
        'WAS-Config-APIs'
    )
    # Add CGI if selected
    if ($includeCGI) {
        $features += 'Web-CGI'
        Write-Host "`nAdding CGI support..." -ForegroundColor Yellow
    }

    Install-WindowsFeature -Name $features -IncludeManagementTools -ErrorAction Stop
    Write-Host " Success!" -ForegroundColor Green
    Write-Host "IIS features installed successfully" -ForegroundColor Green
}
catch {
    Write-Host " Failed!" -ForegroundColor Red
    Write-Host $("Failed to install IIS features: " + $_)
    throw
}

#------------------------------------------------------------------------------------------------
# Install .NET 9.0 Hosting Bundle
Write-Host "`nInstalling .NET 9.0 Hosting Bundle..." -NoNewline
try {
    $hostingBundlePath = "$serverSetupPath\dotnet-hosting-9.0.1-win.exe"
    & $hostingBundlePath /quiet /norestart

    Write-Host ".NET 9.0 Hosting Bundle installed successfully" -ForegroundColor Green
}
catch {
    Write-Host " Failed!" -ForegroundColor Red
    Write-Host $("Failed to install .NET 9.0 Hosting Bundle: " + $_)
    # ASk if to abort the script or continue with the installation
    $abort = Read-Host "Do you want to abort the script? (Y/N)"
    if ($abort.ToUpper() -eq 'Y') {
        throw "Installation aborted"
    }
}

#------------------------------------------------------------------------------------------------
# Install DB2 Client
Write-Host "`nDB2 Components that will be installed:"
Write-Host "- DB2 11.5.9 Client"
Write-Host "- DB2 11.5.9 ODBC Driver"
Write-Host "- DB2 11.5.9 JDBC Driver"
Write-Host "- DB2 11.5.9 OLEDB Driver"
Write-Host "- DB2 11.5.9 Python Driver"
Write-Host "- DB2 11.5.9 Node.js Driver"
Write-Host "- DB2 11.5.9 .NET Driver"

Write-Host "`nPress Enter to continue with installation or Ctrl+C to cancel..."
Read-Host

Write-Host "`nInstalling DB2 Client and drivers..." -NoNewline
try {
    # Install DB2 Client with visible progress but no interaction required
    $db2ClientPath = "$serverSetupPath\ibm_db2_client_winx64_v11.5\CLIENT\image\setup.exe"
    & $db2ClientPath /f /l "C:\TEMPFK\db2client_install.log" /i "silent" /components "CLIENT,ODBC_DRIVER,JDBC_DRIVER,OLEDB_DRIVER,PYTHON_DRIVER,NODEJS_DRIVER,NET_DRIVER"

    Write-Host " Success!" -ForegroundColor Green
    Write-Host "DB2 Client and drivers installed successfully" -ForegroundColor Green
}
catch {
    Write-Host " Failed!" -ForegroundColor Red
    Write-Host $("Failed to install DB2 Client and drivers: " + $_)
    $abort = Read-Host "Do you want to abort the script? (Y/N)"
    if ($abort.ToUpper() -eq 'Y') {
        throw "Installation aborted"
    }
}

#------------------------------------------------------------------------------------------------
# Install Visual Studio Code
Write-Host "`nInstalling Visual Studio Code..." -NoNewline
try {
    # Install VS Code from local share
    Install-WingetPackage -AppName "Microsoft.VisualStudioCode"

    Write-Host "Visual Studio Code installed successfully" -ForegroundColor Green
}
catch {
    Write-Host " Failed!" -ForegroundColor Red
    Write-Host $("Failed to install Visual Studio Code: " + $_)
    # Ask if to abort the script or continue with the installation
    $abort = Read-Host "Do you want to abort the script? (Y/N)"
    if ($abort.ToUpper() -eq 'Y') {
        throw "Installation aborted"
    }
}

#------------------------------------------------------------------------------------------------
# Install Notepad++
Write-Host "`nInstalling  Notepad++..." -NoNewline
try {
    # Install Notepad++ from local share
    Install-WingetPackage -AppName "Notepad++.Notepad++"

    Write-Host "Notepad++ installed successfully" -ForegroundColor Green
}
catch {
    Write-Host " Failed!" -ForegroundColor Red
    Write-Host $("Failed to install Notepad++: " + $_)
    # Ask if to abort the script or continue with the installation
    $abort = Read-Host "Do you want to abort the script? (Y/N)"
    if ($abort.ToUpper() -eq 'Y') {
        throw "Installation aborted"
    }
}

#------------------------------------------------------------------------------------------------
# Install PowerShell 7
Write-Host "`nInstalling PowerShell 7..." -NoNewline
try {
    # Install PowerShell 7 from local share
    Install-WingetPackage -AppName "Microsoft.PowerShell"

    Write-Host "PowerShell 7 installed successfully" -ForegroundColor Green
}
catch {
    Write-Host " Failed!" -ForegroundColor Red
    Write-Host $("Failed to install PowerShell 7: " + $_)
    # Ask if to abort the script or continue with the installation
    $abort = Read-Host "Do you want to abort the script? (Y/N)"
    if ($abort.ToUpper() -eq 'Y') {
        throw "Installation aborted"
    }
}

#------------------------------------------------------------------------------------------------
# Install SQL Server Client
Write-Host "`nInstalling SQL Server Client..." -NoNewline
try {
    # Install SQL Server Client from local share
    Install-WingetPackage -AppName "Microsoft.SQLServer.2019.Client"

    Write-Host "SQL Server Client installed successfully" -ForegroundColor Green
}
catch {
    Write-Host " Failed!" -ForegroundColor Red
    Write-Host $("Failed to install SQL Server Client: " + $_)
    # Ask if to abort the script or continue with the installation
    $abort = Read-Host "Do you want to abort the script? (Y/N)"
    if ($abort.ToUpper() -eq 'Y') {
        throw "Installation aborted"
    }
}

#------------------------------------------------------------------------------------------------
# Install Azure Data Studio
Write-Host "`nInstalling Azure Data Studio..." -NoNewline
try {
    # Install Azure Data Studio from local share
    Install-WingetPackage -AppName "Microsoft.AzureDataStudio.SQL"

    Write-Host "Azure Data Studio installed successfully" -ForegroundColor Green
}
catch {
    Write-Host " Failed!" -ForegroundColor Red
    Write-Host $("Failed to install Azure Data Studio: " + $_)
    # Ask if to abort the script or continue with the installation
    $abort = Read-Host "Do you want to abort the script? (Y/N)"
    if ($abort.ToUpper() -eq 'Y') {
        throw "Installation aborted"
    }
}

#------------------------------------------------------------------------------------------------
# Install .NET 8.0
Write-Host "`nInstalling .NET 8.0..." -NoNewline
try {
    # Install .NET 8.0 from local share
    Install-WingetPackage -AppName "Microsoft.DotNet.SDK.8"

    Write-Host ".NET 8.0 installed successfully" -ForegroundColor Green
}
catch {
    Write-Host " Failed!" -ForegroundColor Red
    Write-Host $("Failed to install .NET 8.0: " + $_)
    # Ask if to abort the script or continue with the installation
    $abort = Read-Host "Do you want to abort the script? (Y/N)"
    if ($abort.ToUpper() -eq 'Y') {
        throw "Installation aborted"
    }
}

#------------------------------------------------------------------------------------------------
# Install IBM Object Rexx 8.1
Write-Host "`nInstalling IBM Object Rexx 8.1..." -NoNewline
try {
    $rexxPath = "$serverSetupPath\ObjRexx\setup.exe"
    & $rexxPath

    Write-Host " Success!" -ForegroundColor Green
    Write-Host "IBM Object Rexx 8.1 installed successfully" -ForegroundColor Green
}
catch {
    Write-Host " Failed!" -ForegroundColor Red
    Write-Host $("Failed to install IBM Object Rexx 8.1: " + $_)
    $abort = Read-Host "Do you want to abort the script? (Y/N)"
    if ($abort.ToUpper() -eq 'Y') {
        throw "Installation aborted"
    }
}

#------------------------------------------------------------------------------------------------
# Install Micro Focus Enterprise Server 5.1
Write-Host "`nInstalling Micro Focus Enterprise Server 5.1..." -NoNewline
try {
    # Install Micro Focus Enterprise Server 5.1 using setup.exe
    & "$serverSetupPath\MicroFocusCobol\MF_Server_SOA\dvd-sv51-mf002\setup.exe"

    Write-Host " Success!" -ForegroundColor Green
    Write-Host "Micro Focus Enterprise Server 5.1 installed successfully" -ForegroundColor Green
}
catch {
    Write-Host " Failed!" -ForegroundColor Red
    Write-Host $("Failed to install Micro Focus Enterprise Server 5.1: " + $_)
    # Ask if to abort the script or continue with the installation
    $abort = Read-Host "Do you want to abort the script? (Y/N)"
    if ($abort.ToUpper() -eq 'Y') {
        throw "Installation aborted"
    }
}

#------------------------------------------------------------------------------------------------
# Install Micro Focus Cobol Server Runtime 5.1
Write-Host "`nInstalling Micro Focus Cobol Server Runtime 5.1..." -NoNewline
try {
    # Install Micro Focus Cobol Server Runtime 5.1 using setup.exe
    & "$serverSetupPath\MicroFocusCobol\MicroFocusServer_51\setup.exe"

    Write-Host " Success!" -ForegroundColor Green
    Write-Host "Micro Focus Cobol Server Runtime 5.1 installed successfully" -ForegroundColor Green
}
catch {
    Write-Host " Failed!" -ForegroundColor Red
    Write-Host $("Failed to install Micro Focus Cobol Server Runtime 5.1: " + $_)
    # Ask if to abort the script or continue with the installation
    $abort = Read-Host "Do you want to abort the script? (Y/N)"
    if ($abort.ToUpper() -eq 'Y') {
        throw "Installation aborted"
    }
}

