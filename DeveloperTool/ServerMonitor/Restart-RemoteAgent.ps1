#!/usr/bin/env pwsh
# Remotely restart ServerMonitor service on target server

param(
    [string]$Server = "t-no1inltst-db"
)

Write-Host "Restarting ServerMonitor service on $Server..." -ForegroundColor Yellow

try {
    # Try to restart the service remotely
    Invoke-Command -ComputerName $Server -ScriptBlock {
        Write-Host "Stopping ServerMonitor service..."
        Stop-Service -Name "ServerMonitor" -Force -ErrorAction SilentlyContinue
        Start-Sleep -Seconds 3
        
        Write-Host "Starting ServerMonitor service..."
        Start-Service -Name "ServerMonitor" -ErrorAction Stop
        
        $service = Get-Service -Name "ServerMonitor"
        Write-Host "Service status: $($service.Status)"
    } -ErrorAction Stop
    
    Write-Host "`n✅ Service restarted successfully!" -ForegroundColor Green
}
catch {
    Write-Host "`n❌ Remote restart failed: $($_.Exception.Message)" -ForegroundColor Red
    Write-Host "`nTry manually:" -ForegroundColor Yellow
    Write-Host "  1. RDP to $Server" -ForegroundColor Gray
    Write-Host "  2. Run: Restart-Service ServerMonitor" -ForegroundColor Gray
    Write-Host "  Or run the install script:" -ForegroundColor Gray
    Write-Host "  & 'C:\opt\src\DedgeSrc\DedgeSystemTools\Folders\DedgeCommon\Software\DedgeWinApps\ServerMonitor\ServerMonitorAgent'" -ForegroundColor Gray
}

Write-Host "`nWaiting 10 seconds for service to start..." -ForegroundColor Gray
Start-Sleep -Seconds 10

# Test connectivity
Write-Host "`nTesting connectivity..." -ForegroundColor Yellow
& "$PSScriptRoot\Test-Connectivity.ps1" -Server $Server
