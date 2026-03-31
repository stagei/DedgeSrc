#Requires -Version 7.0

<#
.SYNOPSIS
    Deployment script for Server Health Monitor Check Tool

.DESCRIPTION
    This script builds, publishes, and deploys the Server Health Monitor Check Tool to target servers.
    Compatible with Deploy-Handler module if available.

.PARAMETER ComputerNameList
    List of target computers to deploy to. Supports wildcards.

.PARAMETER BuildFirst
    Build and publish before deploying. Default: true

.PARAMETER InstallAsService
    Install as Windows Service on target computers. Default: false

.EXAMPLE
    .\\_deploy.ps1 -ComputerNameList @("*-db")
    Deploys to all servers matching *-db pattern

.EXAMPLE
    .\\_deploy.ps1 -ComputerNameList @("SERVER01") -InstallAsService
    Deploys and installs as service on SERVER01
#>

[CmdletBinding()]
param(
    [string[]]$ComputerNameList = @(),
    
    [bool]$BuildFirst = $true,
    
    [switch]$InstallAsService
)

$ErrorActionPreference = "Stop"

Write-Host "=== Server Health Monitor Check Tool - Deployment ===" -ForegroundColor Cyan

# Build and publish if requested
if ($BuildFirst) {
    Write-Host "`nBuilding and publishing..." -ForegroundColor Yellow
    & "$PSScriptRoot\Install\Build-And-Publish.ps1" -Configuration Release
    
    if ($LASTEXITCODE -ne 0) {
        Write-Error "Build failed"
        exit 1
    }
}

# Check if Deploy-Handler module is available
$deployHandlerAvailable = Get-Module -ListAvailable -Name Deploy-Handler -ErrorAction SilentlyContinue

if ($deployHandlerAvailable -and $ComputerNameList.Count -gt 0) {
    Write-Host "`nUsing Deploy-Handler module..." -ForegroundColor Green
    
    try {
        Import-Module Deploy-Handler -Force -ErrorAction Stop
        Deploy-Files -FromFolder $PSScriptRoot -ComputerNameList $ComputerNameList
        
        Write-Host "Deployment completed successfully" -ForegroundColor Green
    }
    catch {
        Write-Error "Deploy-Handler failed: $($_.Exception.Message)"
        exit 1
    }
}
else {
    if ($ComputerNameList.Count -eq 0) {
        Write-Host "`nNo target computers specified. Local build only." -ForegroundColor Yellow
        Write-Host "To deploy to remote servers, specify -ComputerNameList parameter" -ForegroundColor Gray
    }
    else {
        Write-Warning "Deploy-Handler module not found. Manual deployment required."
        Write-Host "`nPublished files location:" -ForegroundColor Gray
        Write-Host "  $PSScriptRoot\src\ServerMonitor\ServerMonitorAgent\bin\Release\net10.0-windows\win-x64\publish" -ForegroundColor White
    }
}

Write-Host "`n=== Deployment Complete ===" -ForegroundColor Cyan

