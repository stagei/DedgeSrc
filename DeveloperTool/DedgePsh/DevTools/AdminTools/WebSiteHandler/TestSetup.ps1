#Requires -Version 5.1
<#
.SYNOPSIS
    Creates test websites in IIS for testing the WebSiteHandler scripts.
.DESCRIPTION
    This script creates simple test websites in IIS to allow testing
    of the export and import functionality in WebSiteHandler.ps1.
.NOTES
    Version:        1.0
    Author:         Admin Tools
    Creation Date:  Current date
#>

# Import common utility functions
$scriptPath = Split-Path -Parent $MyInvocation.MyCommand.Path
$commonPath = Join-Path $scriptPath "Common.ps1"

if (Test-Path $commonPath) {
    . $commonPath
} else {
    Write-Host "Common.ps1 not found at $commonPath" -ForegroundColor Red
    exit
}

# Check for admin privileges
if (-not (Test-AdminPrivileges)) {
    exit
}

# Setup paths
$testDataPath = "$env:OptPath\data"
$testWebsitesPath = Join-Path $testDataPath "TestWebsites"

# Create directories if they don't exist
if (-not (Test-Path $testWebsitesPath)) {
    try {
        Write-Host "Creating test websites directory: $testWebsitesPath" -NoNewline
        New-Item -ItemType Directory -Path $testWebsitesPath -Force | Out-Null
        Write-Host " Done!" -ForegroundColor Green
    }
    catch {
        Write-Host " Failed!" -ForegroundColor Red
        Write-Host "Error: $_" -ForegroundColor Red
        exit
    }
}

# Check if IIS is installed (but don't install it)
$iisInstalled = $false
try {
    $iisInstalled = Initialize-IIS

    if (-not $iisInstalled) {
        Write-Host "Failed to initialize IIS. Please run WebSiteHandler.ps1 first." -ForegroundColor Red
        exit
    }
}
catch {
    Write-Host "Error initializing IIS: $_" -ForegroundColor Red
    Write-Host "Please run WebSiteHandler.ps1 first to install IIS automatically." -ForegroundColor Yellow
    exit
}

# Rest of the TestSetup.ps1 code remains the same...

