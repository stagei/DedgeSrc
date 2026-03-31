#Requires -Version 7
<#
.SYNOPSIS
    Starts the AutoDocJson.Web local development server.
.DESCRIPTION
    Launches the ASP.NET Core web application on http://localhost:5280
    and opens the browser automatically.
#>

$ErrorActionPreference = 'Stop'
$projectPath = Join-Path $PSScriptRoot 'AutoDocJson.Web'

# Stop if already running
$existing = Get-Process -Name 'AutoDocJson.Web' -ErrorAction SilentlyContinue
if ($existing) {
    foreach ($proc in $existing) {
        Write-Host "Stopping existing AutoDocJson.Web (PID: $($proc.Id)) ..." -ForegroundColor Yellow
        Stop-Process -Id $proc.Id -Force -ErrorAction SilentlyContinue
    }
    Start-Sleep -Seconds 2
}

Write-Host "Starting AutoDocJson.Web on http://localhost:5280 ..." -ForegroundColor Cyan
Start-Process -FilePath 'dotnet' -ArgumentList "run --project `"$projectPath`"" -NoNewWindow -PassThru | Out-Null

# Wait for the server to become available
$maxWait = 30
$waited = 0
while ($waited -lt $maxWait) {
    Start-Sleep -Seconds 1
    $waited++
    try {
        $null = Invoke-WebRequest -Uri 'http://localhost:5280/' -UseBasicParsing -TimeoutSec 2 -ErrorAction Stop
        Write-Host "Server is ready at http://localhost:5280/" -ForegroundColor Green
        Start-Process 'http://localhost:5280/'
        exit 0
    } catch {
        # Not ready yet
    }
}

Write-Host "Server did not respond within $($maxWait) seconds. Check for errors." -ForegroundColor Red
exit 1
