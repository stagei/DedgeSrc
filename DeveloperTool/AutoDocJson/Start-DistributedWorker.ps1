#Requires -Version 7
<#
.SYNOPSIS
    Starts the AutoDocJson distributed worker.
.DESCRIPTION
    Builds and launches AutoDocJson in --worker mode, which watches the server's
    BatchRunnerStarted.json trigger file and processes worklist items from the
    shared _regenerate_worklist folder on the server.

    The server name is read from AutoDocJson\appsettings.json (AutoDocJson:ServerName).
    This script refuses to run on the server itself.
.EXAMPLE
    .\Start-DistributedWorker.ps1
.EXAMPLE
    .\Start-DistributedWorker.ps1 -SkipBuild
#>

[CmdletBinding()]
param(
    [switch]$SkipBuild
)

$ErrorActionPreference = 'Stop'
$projectPath = Join-Path $PSScriptRoot 'AutoDocJson'

Write-Host ""
Write-Host "AutoDocJson Distributed Worker" -ForegroundColor Cyan
Write-Host "==============================" -ForegroundColor Cyan
Write-Host ""

# Stop any existing worker
$existing = Get-Process -Name 'AutoDocJson' -ErrorAction SilentlyContinue |
    Where-Object { $_.CommandLine -match '--worker' -or $_.CommandLine -match '-worker' }
if ($existing) {
    foreach ($proc in $existing) {
        Write-Host "Stopping existing worker (PID: $($proc.Id)) ..." -ForegroundColor Yellow
        Stop-Process -Id $proc.Id -Force -ErrorAction SilentlyContinue
    }
    Start-Sleep -Seconds 2
}

if (-not $SkipBuild) {
    Write-Host "Building AutoDocJson..." -ForegroundColor Yellow
    dotnet build "$projectPath" --configuration Debug --verbosity quiet
    if ($LASTEXITCODE -ne 0) {
        Write-Host "Build failed!" -ForegroundColor Red
        exit 1
    }
    Write-Host "Build succeeded." -ForegroundColor Green
    Write-Host ""
}

Write-Host "Starting worker (Ctrl+C to stop)..." -ForegroundColor Cyan
Write-Host ""

dotnet run --project "$projectPath" --no-build -- --worker
exit $LASTEXITCODE
