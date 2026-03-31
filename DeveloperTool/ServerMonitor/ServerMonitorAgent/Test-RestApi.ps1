#!/usr/bin/env pwsh
<#
.SYNOPSIS
    Tests REST API functionality while ServerMonitor is running
#>

$startTime = Get-Date
Write-Host "══════════════════════════════════════════════════════" -ForegroundColor Cyan
Write-Host "  ⏱️  START: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')" -ForegroundColor Yellow
Write-Host "  🌐 REST API Testing" -ForegroundColor Yellow
Write-Host "══════════════════════════════════════════════════════`n" -ForegroundColor Cyan

# Kill existing
Get-Process -Name "ServerMonitor" -ErrorAction SilentlyContinue | Stop-Process -Force
Start-Sleep -Seconds 2

# Start ServerMonitor
$exePath = "C:\opt\src\ServerMonitor\ServerMonitorAgent\src\ServerMonitor\ServerMonitorAgent\bin\Release\net10.0-windows\win-x64\ServerMonitor.exe"
Write-Host "Starting ServerMonitor..." -ForegroundColor Cyan
$process = Start-Process -FilePath $exePath -PassThru -WindowStyle Minimized

Write-Host "Waiting 10 seconds for REST API to initialize..." -ForegroundColor Yellow
Start-Sleep -Seconds 10

$port = 8999
$baseUrl = "http://localhost:$port"

# Test 1: Health endpoint
Write-Host "`n📊 Test 1: Health Endpoint" -ForegroundColor Cyan
try {
    $response = Invoke-RestMethod -Uri "$baseUrl/api/snapshot/health" -Method Get -TimeoutSec 5
    Write-Host "✅ Health endpoint responding" -ForegroundColor Green
    Write-Host ($response | ConvertTo-Json -Depth 3) -ForegroundColor White
} catch {
    Write-Host "❌ Health endpoint failed: $($_.Exception.Message)" -ForegroundColor Red
}

# Test 2: Full snapshot
Write-Host "`n📊 Test 2: Full Snapshot Endpoint" -ForegroundColor Cyan
try {
    $response = Invoke-RestMethod -Uri "$baseUrl/api/snapshot" -Method Get -TimeoutSec 5
    Write-Host "✅ Snapshot endpoint responding" -ForegroundColor Green
    Write-Host "Snapshot keys: $($response.PSObject.Properties.Name -join ', ')" -ForegroundColor Gray
    
    if ($response.Processor) {
        Write-Host "CPU Usage: $($response.Processor.OverallUsagePercent)%" -ForegroundColor White
    }
    if ($response.Memory) {
        Write-Host "Memory: $($response.Memory.UsedGB) GB / $($response.Memory.TotalGB) GB" -ForegroundColor White
    }
} catch {
    Write-Host "❌ Snapshot endpoint failed: $($_.Exception.Message)" -ForegroundColor Red
}

# Test 3: Alerts endpoint
Write-Host "`n📊 Test 3: Alerts Endpoint" -ForegroundColor Cyan
try {
    $response = Invoke-RestMethod -Uri "$baseUrl/api/snapshot/alerts" -Method Get -TimeoutSec 5
    Write-Host "✅ Alerts endpoint responding" -ForegroundColor Green
    Write-Host "Alert count: $($response.Count)" -ForegroundColor White
} catch {
    Write-Host "❌ Alerts endpoint failed: $($_.Exception.Message)" -ForegroundColor Red
}

# Test 3b: External Events endpoint
Write-Host "`n📊 Test 3b: External Events Endpoint" -ForegroundColor Cyan
try {
    $response = Invoke-RestMethod -Uri "$baseUrl/api/snapshot/external-events" -Method Get -TimeoutSec 5
    Write-Host "✅ External events endpoint responding" -ForegroundColor Green
    Write-Host "External event count: $($response.Count)" -ForegroundColor White
} catch {
    Write-Host "❌ External events endpoint failed: $($_.Exception.Message)" -ForegroundColor Red
}

# Test 4: Individual monitor endpoints
Write-Host "`n📊 Test 4: Individual Monitor Endpoints" -ForegroundColor Cyan
$endpoints = @("processor", "memory", "disks", "network", "uptime")
foreach ($ep in $endpoints) {
    try {
        $response = Invoke-RestMethod -Uri "$baseUrl/api/snapshot/$ep" -Method Get -TimeoutSec 3
        Write-Host "  ✅ /$ep" -ForegroundColor Green
    } catch {
        Write-Host "  ❌ /$ep - $($_.Exception.Message)" -ForegroundColor Red
    }
}

# Test 5: Swagger UI
Write-Host "`n📊 Test 5: Swagger UI" -ForegroundColor Cyan
try {
    $response = Invoke-WebRequest -Uri "$baseUrl/swagger/index.html" -Method Get -TimeoutSec 5
    Write-Host "✅ Swagger UI accessible (Status: $($response.StatusCode))" -ForegroundColor Green
    Write-Host "Open in browser: $baseUrl/swagger" -ForegroundColor Cyan
} catch {
    Write-Host "❌ Swagger UI failed: $($_.Exception.Message)" -ForegroundColor Red
}

# Kill process
Write-Host "`n🔪 Stopping ServerMonitor..." -ForegroundColor Yellow
Stop-Process -Id $process.Id -Force -ErrorAction SilentlyContinue

$totalElapsed = ((Get-Date) - $startTime).TotalSeconds
Write-Host "`n══════════════════════════════════════════════════════" -ForegroundColor Cyan
Write-Host "  ⏱️  END: $(Get-Date -Format 'HH:mm:ss')" -ForegroundColor Yellow
Write-Host "  Total Duration: $([math]::Round($totalElapsed, 1))s" -ForegroundColor Yellow
Write-Host "══════════════════════════════════════════════════════" -ForegroundColor Cyan

