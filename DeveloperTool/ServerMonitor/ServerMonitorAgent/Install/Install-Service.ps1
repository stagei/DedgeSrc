#Requires -Version 7.0
#Requires -RunAsAdministrator

<#
.SYNOPSIS
    Installs Server Health Monitor Check Tool as a Windows Service

.DESCRIPTION
    This script installs the Server Health Monitor Check Tool as a Windows Service using sc.exe.
    The service will run under the Local System account by default.

.PARAMETER ServiceName
    Name of the Windows Service. Default: ServerMonitor

.PARAMETER BinaryPath
    Path to the executable. If not specified, uses the parent directory's published output.

.PARAMETER StartupType
    Service startup type: Automatic, Manual, Disabled. Default: Automatic

.EXAMPLE
    .\Install-Service.ps1
    Installs the service with default settings

.EXAMPLE
    .\Install-Service.ps1 -StartupType Manual
    Installs the service with Manual startup type
#>

[CmdletBinding()]
param(
    [string]$ServiceName = "ServerMonitor",
    
    [string]$BinaryPath = "",
    
    [ValidateSet("Automatic", "Manual", "Disabled")]
    [string]$StartupType = "Automatic"
)

$ErrorActionPreference = "Stop"

Write-Host "=== Server Health Monitor Check Tool - Service Installation ===" -ForegroundColor Cyan

# Determine binary path
if ([string]::IsNullOrEmpty($BinaryPath)) {
    $publishPath = Join-Path $PSScriptRoot "..\src\ServerMonitor\ServerMonitorAgent\bin\Release\net10.0-windows\win-x64\publish\ServerMonitor.exe"
    
    if (-not (Test-Path $publishPath)) {
        Write-Error "Binary not found at expected location: $($publishPath)`nPlease build and publish the project first, or specify -BinaryPath parameter."
        exit 1
    }
    
    $BinaryPath = $publishPath
}

Write-Host "Binary Path: $($BinaryPath)" -ForegroundColor Gray

if (-not (Test-Path $BinaryPath)) {
    Write-Error "Binary not found at: $($BinaryPath)"
    exit 1
}

# Check if service already exists
$existingService = Get-Service -Name $ServiceName -ErrorAction SilentlyContinue

if ($existingService) {
    Write-Host "Service '$($ServiceName)' already exists. Stopping and removing..." -ForegroundColor Yellow
    
    if ($existingService.Status -eq 'Running') {
        Stop-Service -Name $ServiceName -Force
        Write-Host "Service stopped" -ForegroundColor Gray
    }
    
    sc.exe delete $ServiceName
    Start-Sleep -Seconds 2
    Write-Host "Existing service removed" -ForegroundColor Gray
}

# Create the service
Write-Host "Creating service '$($ServiceName)'..." -ForegroundColor Green

$startType = switch ($StartupType) {
    "Automatic" { "auto" }
    "Manual" { "demand" }
    "Disabled" { "disabled" }
}

sc.exe create $ServiceName binPath= $BinaryPath start= $startType DisplayName= "Server Health Monitor Check Tool"

if ($LASTEXITCODE -ne 0) {
    Write-Error "Failed to create service. Exit code: $($LASTEXITCODE)"
    exit 1
}

# Set service description
sc.exe description $ServiceName "Monitors server health metrics and generates alerts based on configurable thresholds"

# Configure service recovery options
sc.exe failure $ServiceName reset= 86400 actions= restart/60000/restart/60000/restart/60000

Write-Host "Service created successfully" -ForegroundColor Green

# Start the service if startup type is Automatic
if ($StartupType -eq "Automatic") {
    Write-Host "Starting service..." -ForegroundColor Green
    Start-Service -Name $ServiceName
    
    Start-Sleep -Seconds 3
    
    $service = Get-Service -Name $ServiceName
    if ($service.Status -eq 'Running') {
        Write-Host "Service is running" -ForegroundColor Green
    } else {
        Write-Warning "Service was created but failed to start. Check Event Viewer for details."
    }
}

Write-Host "`n=== Installation Complete ===" -ForegroundColor Cyan
Write-Host "Service Name: $($ServiceName)" -ForegroundColor White
Write-Host "Status: $($(Get-Service -Name $ServiceName).Status)" -ForegroundColor White
Write-Host "`nTo manage the service:" -ForegroundColor Gray
Write-Host "  Start:   Start-Service -Name $($ServiceName)" -ForegroundColor Gray
Write-Host "  Stop:    Stop-Service -Name $($ServiceName)" -ForegroundColor Gray
Write-Host "  Restart: Restart-Service -Name $($ServiceName)" -ForegroundColor Gray
Write-Host "  Status:  Get-Service -Name $($ServiceName)" -ForegroundColor Gray

