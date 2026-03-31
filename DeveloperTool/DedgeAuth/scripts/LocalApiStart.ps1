#!/usr/bin/env pwsh
<#
.SYNOPSIS
    Starts DedgeAuth.Api locally from source for development/testing.

.DESCRIPTION
    Runs 'dotnet run' on the DedgeAuth.Api project in a new window,
    waits for the health endpoint to respond, then opens the login page.

.PARAMETER ApiBaseUrl
    Base URL the API listens on. Default: http://localhost:8100

.PARAMETER NoBrowser
    Do not open the browser after the API is ready.

.EXAMPLE
    .\scripts\LocalApiStart.ps1
    Start the API and open the login page.

.EXAMPLE
    .\scripts\LocalApiStart.ps1 -NoBrowser
    Start the API without opening a browser.
#>

[CmdletBinding()]
param(
    [string]$ApiBaseUrl = "http://localhost:8100",

    [Parameter(Mandatory = $false)]
    [switch]$NoBrowser
)

$ErrorActionPreference = "Stop"
$projectRoot = Split-Path $PSScriptRoot
$apiProjectDir = Join-Path $projectRoot "src\DedgeAuth.Api"
$healthUrl = "$ApiBaseUrl/health"
$openUrl = "$ApiBaseUrl/login.html"

if (-not (Test-Path $apiProjectDir)) {
    Write-Host "  DedgeAuth.Api project not found at: $apiProjectDir" -ForegroundColor Red
    exit 1
}

# Stop any existing local DedgeAuth processes
$stopped = 0
Get-Process -Name "DedgeAuth.Api" -ErrorAction SilentlyContinue | ForEach-Object {
    Write-Host "  Stopping existing DedgeAuth.Api (PID $($_.Id))..." -ForegroundColor Gray
    Stop-Process -Id $_.Id -Force -ErrorAction SilentlyContinue
    $stopped++
}
if ($stopped -gt 0) { Start-Sleep -Seconds 2 }

# Start the API
Write-Host ""
Write-Host "  Starting DedgeAuth.Api from source (new window)..." -ForegroundColor Cyan
Start-Process -FilePath "dotnet" -ArgumentList "run", "--project", $apiProjectDir -WindowStyle Normal

# Wait for health check
Write-Host "  Waiting for API health check at $($healthUrl)..." -ForegroundColor Gray
$deadline = (Get-Date).AddSeconds(30)
$ready = $false
while ((Get-Date) -lt $deadline) {
    try {
        $r = Invoke-WebRequest -Uri $healthUrl -UseBasicParsing -TimeoutSec 3 -ErrorAction Stop
        if ($r.StatusCode -eq 200) { $ready = $true; break }
    } catch { }
    Start-Sleep -Seconds 1
}

if ($ready) {
    Write-Host "  API is ready at $($ApiBaseUrl)" -ForegroundColor Green
    if (-not $NoBrowser) {
        Write-Host "  Opening browser..." -ForegroundColor Gray
        Start-Process $openUrl
    }
} else {
    Write-Host "  API did not respond within 30 seconds. Check the API window for errors." -ForegroundColor Yellow
    Write-Host "  Try opening $($openUrl) manually." -ForegroundColor Yellow
}
Write-Host ""
