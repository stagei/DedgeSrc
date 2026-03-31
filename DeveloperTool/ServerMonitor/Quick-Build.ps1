#!/usr/bin/env pwsh
# Quick build without the full script overhead

$ErrorActionPreference = "Stop"

Write-Host "Stopping local processes..." -ForegroundColor Yellow
Stop-Process -Name "ServerMonitorDashboard*" -Force -ErrorAction SilentlyContinue
Stop-Process -Name "ServerMonitor" -Force -ErrorAction SilentlyContinue  
Stop-Process -Name "ServerMonitorTrayIcon" -Force -ErrorAction SilentlyContinue
Start-Sleep -Seconds 2

Write-Host "Building and publishing..." -ForegroundColor Yellow

# Build Agent
Write-Host "`n=== Building ServerMonitorAgent ===" -ForegroundColor Cyan
dotnet publish "$PSScriptRoot\ServerMonitorAgent\src\ServerMonitor\ServerMonitor.csproj" `
    --configuration Release `
    -p:PublishProfile=Prod `
    -v minimal

if ($LASTEXITCODE -ne 0) { Write-Host "Agent build failed!" -ForegroundColor Red; exit 1 }

# Build TrayIcon  
Write-Host "`n=== Building ServerMonitorTrayIcon ===" -ForegroundColor Cyan
dotnet publish "$PSScriptRoot\ServerMonitorTrayIcon\src\ServerMonitorTrayIcon\ServerMonitorTrayIcon.csproj" `
    --configuration Release `
    -p:PublishProfile=Prod `
    -v minimal

if ($LASTEXITCODE -ne 0) { Write-Host "TrayIcon build failed!" -ForegroundColor Red; exit 1 }

# Build Dashboard
Write-Host "`n=== Building ServerMonitorDashboard ===" -ForegroundColor Cyan
dotnet publish "$PSScriptRoot\ServerMonitorDashboard\src\ServerMonitorDashboard\ServerMonitorDashboard.csproj" `
    --configuration Release `
    --output "C:\opt\src\DedgeSrc\DedgeSystemTools\Folders\DedgeCommon\Software\DedgeWinApps\ServerMonitorDashboard" `
    -v minimal

if ($LASTEXITCODE -ne 0) { Write-Host "Dashboard build failed!" -ForegroundColor Red; exit 1 }

# Build Dashboard.Tray
Write-Host "`n=== Building ServerMonitorDashboard.Tray ===" -ForegroundColor Cyan
dotnet publish "$PSScriptRoot\ServerMonitorDashboard\src\ServerMonitorDashboard.Tray\ServerMonitorDashboard.Tray.csproj" `
    --configuration Release `
    --output "C:\opt\src\DedgeSrc\DedgeSystemTools\Folders\DedgeCommon\Software\DedgeWinApps\ServerMonitorDashboard.Tray" `
    -v minimal

if ($LASTEXITCODE -ne 0) { Write-Host "Dashboard.Tray build failed!" -ForegroundColor Red; exit 1 }

Write-Host "`n✅ All builds completed!" -ForegroundColor Green

# Update trigger file
$triggerFile = "C:\opt\src\DedgeSrc\DedgeSystemTools\Folders\DedgeCommon\Software\Config\ServerMonitor\ReinstallServerMonitor.txt"
$version = "1.0.20"
@"
Version=$version
BuildDate=$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')
"@ | Set-Content -Path $triggerFile -Force
Write-Host "Trigger file updated with version $version" -ForegroundColor Green
