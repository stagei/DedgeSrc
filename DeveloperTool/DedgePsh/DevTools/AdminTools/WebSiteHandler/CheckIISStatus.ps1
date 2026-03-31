#Requires -Version 5.1
<#
.SYNOPSIS
    Checks the status of IIS and its components on the local machine.
.DESCRIPTION
    This script verifies that IIS is properly installed and all required
    components are available. It provides detailed information about
    the status of IIS and can be used for troubleshooting.
.EXAMPLE
    .\CheckIISStatus.ps1
    Runs the script to check IIS status.
.NOTES
    Version:        1.0
    Author:         Admin Tools
    Creation Date:  Current date
#>

# Import common utility functions if available
$scriptPath = Split-Path -Parent $MyInvocation.MyCommand.Path
$commonPath = Join-Path $scriptPath "Common.ps1"
if (Test-Path $commonPath) {
    . $commonPath
}

# Check if running as Administrator
$isAdmin = ([Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
if (-not $isAdmin) {
    Write-Host "This script requires Administrator privileges. Please run as Administrator." -ForegroundColor Red
    exit 1
}

# Display PowerShell version information
Write-Host "PowerShell Information:" -ForegroundColor Cyan
Write-Host "  Version: $($PSVersionTable.PSVersion)" -ForegroundColor White
Write-Host "  Edition: $($PSVersionTable.PSEdition)" -ForegroundColor White
Write-Host "  .NET Version: $($PSVersionTable.CLRVersion)" -ForegroundColor White
Write-Host ""

# Check IIS features using DISM
Write-Host "Checking IIS features using DISM..." -ForegroundColor Cyan
$dismOutput = DISM.exe /Online /Get-Features | Where-Object { $_ -match "Feature Name" -or $_ -match "State" }

# Parse DISM output
$iisFeatures = @()
$currentFeature = $null

for ($i = 0; $i -lt $dismOutput.Count; $i++) {
    $line = $dismOutput[$i]

    if ($line -match "Feature Name : (.+)") {
        $featureName = $Matches[1]
        if ($featureName -like "IIS-*") {
            $currentFeature = @{
                Name = $featureName
                State = "Unknown"
            }
        }
        else {
            $currentFeature = $null
        }
    }
    elseif ($line -match "State : (.+)" -and $currentFeature -ne $null) {
        $currentFeature.State = $Matches[1]
        $iisFeatures += $currentFeature
        $currentFeature = $null
    }
}

# Define required IIS features
$requiredFeatures = @(
    "IIS-WebServerRole",
    "IIS-WebServer",
    "IIS-CommonHttpFeatures",
    "IIS-ManagementConsole",
    "IIS-WebServerManagementTools",
    "IIS-ManagementScriptingTools"
)

# Display feature information
Write-Host "IIS Feature Status:" -ForegroundColor Cyan
$iisFeatures | ForEach-Object {
    $isRequired = $requiredFeatures -contains $_.Name
    $color = if ($_.State -eq "Enabled") { "Green" } else { if ($isRequired) { "Red" } else { "Yellow" } }
    $requiredText = if ($isRequired) { " (REQUIRED)" } else { "" }
    Write-Host "  $($_.Name): $($_.State)$requiredText" -ForegroundColor $color
}

# Check if all required features are enabled
$missingFeatures = $requiredFeatures | Where-Object { ($iisFeatures | Where-Object { $_.Name -eq $_ -and $_.State -eq "Enabled" }) -eq $null }

if ($missingFeatures.Count -gt 0) {
    Write-Host "`nMissing Required IIS Features:" -ForegroundColor Red
    $missingFeatures | ForEach-Object {
        Write-Host "  $_" -ForegroundColor Red
    }

    # Provide DISM command to install missing features
    $dismCommand = "dism /online /enable-feature"
    $missingFeatures | ForEach-Object {
        $dismCommand += " /featurename:$_"
    }
    $dismCommand += " /all"

    Write-Host "`nTo install missing features, run this command in an elevated command prompt:" -ForegroundColor Yellow
    Write-Host $dismCommand -ForegroundColor White
}
else {
    Write-Host "`nAll required IIS features are installed!" -ForegroundColor Green
}

# Test WebAdministration module
Write-Host "`nChecking WebAdministration module..." -ForegroundColor Cyan
try {
    Import-Module WebAdministration -ErrorAction Stop
    Write-Host "  WebAdministration module loaded successfully." -ForegroundColor Green

    # Try to get websites
    $websites = Get-Website
    if ($websites -ne $null) {
        Write-Host "  Successfully accessed IIS configuration." -ForegroundColor Green
        Write-Host "  Found $($websites.Count) website(s) in IIS." -ForegroundColor White
    }
    else {
        Write-Host "  Unable to retrieve website information from IIS." -ForegroundColor Red
    }
}
catch {
    Write-Host "  Failed to load WebAdministration module: $_" -ForegroundColor Red

    # Try alternate method
    try {
        Import-Module "$env:SystemRoot\System32\WindowsPowerShell\v1.0\Modules\WebAdministration\WebAdministration.psd1" -SkipEditionCheck -ErrorAction Stop
        Write-Host "  Alternate method for loading WebAdministration module succeeded." -ForegroundColor Green
    }
    catch {
        Write-Host "  All methods to load WebAdministration module failed." -ForegroundColor Red
        Write-Host "  IIS PowerShell management may not be properly installed." -ForegroundColor Red
    }
}

Write-Host "`nIIS status check completed." -ForegroundColor Cyan

