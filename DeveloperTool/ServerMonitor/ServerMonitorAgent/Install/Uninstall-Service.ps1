#Requires -Version 7.0
#Requires -RunAsAdministrator

<#
.SYNOPSIS
    Uninstalls Server Health Monitor Check Tool Windows Service

.DESCRIPTION
    This script stops and removes the Server Health Monitor Check Tool Windows Service.

.PARAMETER ServiceName
    Name of the Windows Service to uninstall. Default: ServerMonitor

.PARAMETER Force
    Force uninstall without confirmation

.EXAMPLE
    .\Uninstall-Service.ps1
    Uninstalls the service with confirmation prompt

.EXAMPLE
    .\Uninstall-Service.ps1 -Force
    Uninstalls the service without confirmation
#>

[CmdletBinding()]
param(
    [string]$ServiceName = "ServerMonitor",
    
    [switch]$Force
)

$ErrorActionPreference = "Stop"

Write-Host "=== Server Health Monitor Check Tool - Service Uninstallation ===" -ForegroundColor Cyan

# Check if service exists
$service = Get-Service -Name $ServiceName -ErrorAction SilentlyContinue

if (-not $service) {
    Write-Warning "Service '$($ServiceName)' not found. Nothing to uninstall."
    exit 0
}

Write-Host "Found service: $($ServiceName)" -ForegroundColor Yellow
Write-Host "Status: $($service.Status)" -ForegroundColor Gray

# Confirm uninstallation
if (-not $Force) {
    $confirmation = Read-Host "Are you sure you want to uninstall this service? (y/n)"
    if ($confirmation -ne 'y') {
        Write-Host "Uninstallation cancelled" -ForegroundColor Gray
        exit 0
    }
}

# Stop the service if running
if ($service.Status -eq 'Running') {
    Write-Host "Stopping service..." -ForegroundColor Yellow
    Stop-Service -Name $ServiceName -Force
    
    # Wait for service to stop
    $timeout = 30
    $elapsed = 0
    while ((Get-Service -Name $ServiceName).Status -eq 'Running' -and $elapsed -lt $timeout) {
        Start-Sleep -Seconds 1
        $elapsed++
    }
    
    if ((Get-Service -Name $ServiceName).Status -eq 'Running') {
        Write-Warning "Service did not stop within timeout period. Forcing removal anyway..."
    } else {
        Write-Host "Service stopped" -ForegroundColor Green
    }
}

# Delete the service
Write-Host "Removing service..." -ForegroundColor Yellow
sc.exe delete $ServiceName

if ($LASTEXITCODE -ne 0) {
    Write-Error "Failed to remove service. Exit code: $($LASTEXITCODE)"
    exit 1
}

# Wait for service to be removed
Start-Sleep -Seconds 2

# Verify removal
$serviceCheck = Get-Service -Name $ServiceName -ErrorAction SilentlyContinue
if ($serviceCheck) {
    Write-Warning "Service still exists after deletion command. May require system restart."
} else {
    Write-Host "Service removed successfully" -ForegroundColor Green
}

Write-Host "`n=== Uninstallation Complete ===" -ForegroundColor Cyan

