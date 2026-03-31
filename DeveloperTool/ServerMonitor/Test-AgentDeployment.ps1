#!/usr/bin/env pwsh
<#
.SYNOPSIS
    Builds, deploys, and tests ServerMonitor agent connectivity
.DESCRIPTION
    1. Builds and publishes all apps
    2. Waits for auto-update to propagate
    3. Tests if the agent is reachable from outside
#>

$ErrorActionPreference = "Stop"
$targetServer = "t-no1inltst-db"
$targetIp = "10.33.103.141"
$targetPort = 8999
$maxRetries = 10
$retryDelaySeconds = 30

Write-Host "═══════════════════════════════════════════════════════════════════════════════" -ForegroundColor Cyan
Write-Host "  ServerMonitor Deployment & Connectivity Test" -ForegroundColor Cyan
Write-Host "═══════════════════════════════════════════════════════════════════════════════" -ForegroundColor Cyan
Write-Host ""

# Step 1: Build and publish
Write-Host "📦 Step 1: Building and publishing..." -ForegroundColor Yellow
Write-Host ""

# Stop local processes first
Stop-Process -Name "ServerMonitorDashboard" -Force -ErrorAction SilentlyContinue
Stop-Process -Name "ServerMonitorDashboard.Tray" -Force -ErrorAction SilentlyContinue
Start-Sleep -Seconds 2

& "$PSScriptRoot\Build-And-Publish.ps1"

if ($LASTEXITCODE -ne 0) {
    Write-Host "❌ Build failed!" -ForegroundColor Red
    exit 1
}

Write-Host ""
Write-Host "✅ Build completed successfully!" -ForegroundColor Green
Write-Host ""

# Step 2: Wait and test connectivity
Write-Host "🔍 Step 2: Testing connectivity to $targetServer (${targetIp}:${targetPort})..." -ForegroundColor Yellow
Write-Host "   Note: The agent needs to auto-update first. This may take a few minutes." -ForegroundColor Gray
Write-Host ""

$testUrls = @(
    "http://${targetIp}:${targetPort}/api/IsAlive",
    "http://${targetIp}:${targetPort}/swagger/index.html"
)

for ($retry = 1; $retry -le $maxRetries; $retry++) {
    Write-Host "   Attempt $retry of $maxRetries..." -ForegroundColor Gray
    
    $allSuccess = $true
    
    foreach ($url in $testUrls) {
        try {
            $response = Invoke-WebRequest -Uri $url -Method GET -TimeoutSec 10 -ErrorAction Stop
            Write-Host "   ✅ $url - Status: $($response.StatusCode)" -ForegroundColor Green
        }
        catch {
            $allSuccess = $false
            $errorMsg = $_.Exception.Message
            if ($errorMsg -match "actively refused") {
                Write-Host "   ❌ $url - Connection refused (agent not listening on external interface)" -ForegroundColor Red
            }
            elseif ($errorMsg -match "timed out") {
                Write-Host "   ❌ $url - Timeout (firewall or agent not running)" -ForegroundColor Red
            }
            else {
                Write-Host "   ❌ $url - Error: $errorMsg" -ForegroundColor Red
            }
        }
    }
    
    if ($allSuccess) {
        Write-Host ""
        Write-Host "═══════════════════════════════════════════════════════════════════════════════" -ForegroundColor Green
        Write-Host "  ✅ SUCCESS! Agent is accessible from outside!" -ForegroundColor Green
        Write-Host "═══════════════════════════════════════════════════════════════════════════════" -ForegroundColor Green
        Write-Host ""
        Write-Host "  Swagger UI: http://${targetIp}:${targetPort}/swagger/index.html" -ForegroundColor Cyan
        Write-Host "  IsAlive:    http://${targetIp}:${targetPort}/api/IsAlive" -ForegroundColor Cyan
        Write-Host ""
        exit 0
    }
    
    if ($retry -lt $maxRetries) {
        Write-Host ""
        Write-Host "   Waiting $retryDelaySeconds seconds for agent to update..." -ForegroundColor Gray
        Write-Host "   (The tray app checks for updates every ~30 seconds)" -ForegroundColor DarkGray
        Write-Host ""
        Start-Sleep -Seconds $retryDelaySeconds
    }
}

Write-Host ""
Write-Host "═══════════════════════════════════════════════════════════════════════════════" -ForegroundColor Red
Write-Host "  ❌ FAILED: Agent is still not accessible after $maxRetries attempts" -ForegroundColor Red
Write-Host "═══════════════════════════════════════════════════════════════════════════════" -ForegroundColor Red
Write-Host ""
Write-Host "  Possible causes:" -ForegroundColor Yellow
Write-Host "  1. Agent hasn't auto-updated yet (try waiting longer)" -ForegroundColor Gray
Write-Host "  2. Firewall on target server blocking port $targetPort" -ForegroundColor Gray
Write-Host "  3. Agent service not running on target server" -ForegroundColor Gray
Write-Host ""
Write-Host "  Manual steps to fix:" -ForegroundColor Yellow
Write-Host "  1. Connect to $targetServer" -ForegroundColor Gray
Write-Host "  2. Restart ServerMonitor service: Restart-Service ServerMonitor" -ForegroundColor Gray
Write-Host "  3. Check firewall: Get-NetFirewallRule -DisplayName '*ServerMonitor*'" -ForegroundColor Gray
Write-Host ""
exit 1
