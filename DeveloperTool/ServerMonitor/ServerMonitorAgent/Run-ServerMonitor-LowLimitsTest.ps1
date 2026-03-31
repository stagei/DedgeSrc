#!/usr/bin/env pwsh
<#
.SYNOPSIS
    Runs ServerMonitor with LowLimitsTest configuration
.DESCRIPTION
    Sets DOTNET_ENVIRONMENT=LowLimitsTest and runs ServerMonitor with appsettings.LowLimitsTest.json
    This enables DevMode which skips CommonAppsettingsFile sync, perfect for local testing.
#>

$startTime = Get-Date
Write-Host "⏱️  START: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')" -ForegroundColor Yellow
Write-Host "Action: Starting ServerMonitor with LowLimitsTest configuration`n" -ForegroundColor Cyan

# Kill any existing processes
Write-Host "🔪 Killing existing ServerMonitor processes..." -ForegroundColor Red
Get-Process -Name "ServerMonitor" -ErrorAction SilentlyContinue | Stop-Process -Force
Start-Sleep -Seconds 2

# Set environment variable for LowLimitsTest configuration
$env:DOTNET_ENVIRONMENT = "LowLimitsTest"
Write-Host "✅ DOTNET_ENVIRONMENT set to: $env:DOTNET_ENVIRONMENT" -ForegroundColor Green
Write-Host "   This will load: appsettings.LowLimitsTest.json`n" -ForegroundColor Gray

# Path to executable
$exePath = "src\ServerMonitor\ServerMonitorAgent\bin\Release\net10.0-windows\win-x64\ServerMonitor.exe"

if (-not (Test-Path $exePath)) {
    Write-Host "❌ Executable not found: $exePath" -ForegroundColor Red
    Write-Host "   Please build the project first: dotnet build -c Release" -ForegroundColor Yellow
    exit 1
}

Write-Host "✅ Executable found: $exePath" -ForegroundColor Green
Write-Host "🚀 Starting ServerMonitor with LowLimitsTest configuration...`n" -ForegroundColor Cyan

# Start the process with the environment variable
$process = Start-Process -FilePath $exePath -PassThru -WindowStyle Normal -Environment @{
    DOTNET_ENVIRONMENT = "LowLimitsTest"
}

Write-Host "✅ Process started (PID: $($process.Id))" -ForegroundColor Green
Write-Host "`n📋 Configuration details:" -ForegroundColor Cyan
Write-Host "   - Using: appsettings.LowLimitsTest.json" -ForegroundColor White
Write-Host "   - DevMode: true (skips CommonAppsettingsFile sync)" -ForegroundColor White
Write-Host "   - Low thresholds enabled for quick alert generation" -ForegroundColor White
Write-Host "`n💡 Press Ctrl+C to stop the application`n" -ForegroundColor Yellow

# Wait for process to exit
try {
    $process.WaitForExit()
    Write-Host "`n✅ Process exited (Exit Code: $($process.ExitCode))" -ForegroundColor Green
} catch {
    Write-Host "`n⚠️  Process interrupted" -ForegroundColor Yellow
}

$totalElapsed = ((Get-Date) - $startTime).TotalSeconds
Write-Host "`n⏱️  END: $(Get-Date -Format 'HH:mm:ss') | Duration: $([math]::Round($totalElapsed, 1))s" -ForegroundColor Yellow

