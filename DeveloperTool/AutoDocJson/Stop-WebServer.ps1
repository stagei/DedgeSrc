#Requires -Version 7
<#
.SYNOPSIS
    Stops the AutoDocJson.Web local development server.
.DESCRIPTION
    Finds and stops any running AutoDocJson.Web process.
#>

$ErrorActionPreference = 'Stop'

$processes = Get-Process -Name 'AutoDocJson.Web' -ErrorAction SilentlyContinue
if (-not $processes) {
    Write-Host "AutoDocJson.Web is not running." -ForegroundColor Yellow
    exit 0
}

foreach ($proc in $processes) {
    Write-Host "Stopping AutoDocJson.Web (PID: $($proc.Id)) ..." -ForegroundColor Cyan
    Stop-Process -Id $proc.Id -Force
}

Start-Sleep -Seconds 1

# Verify stopped
$remaining = Get-Process -Name 'AutoDocJson.Web' -ErrorAction SilentlyContinue
if ($remaining) {
    Write-Host "Warning: Process still running. Try running as Administrator." -ForegroundColor Red
    exit 1
} else {
    Write-Host "AutoDocJson.Web stopped successfully." -ForegroundColor Green
    exit 0
}
