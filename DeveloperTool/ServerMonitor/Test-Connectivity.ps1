#!/usr/bin/env pwsh
# Test connectivity to server agent

param(
    [string]$Server = "t-no1inltst-db",
    [string]$IP = "10.33.103.141",
    [int]$Port = 8999
)

Write-Host "Testing connectivity to $Server ($IP`:$Port)..." -ForegroundColor Cyan

# Test 1: TCP port check
Write-Host "`n1. TCP Port Test:" -ForegroundColor Yellow
$tcpTest = Test-NetConnection -ComputerName $IP -Port $Port -WarningAction SilentlyContinue
Write-Host "   Ping: $($tcpTest.PingSucceeded)"
Write-Host "   TCP:  $($tcpTest.TcpTestSucceeded)"

# Test 2: HTTP IsAlive
Write-Host "`n2. HTTP IsAlive Test:" -ForegroundColor Yellow
try {
    $response = Invoke-RestMethod -Uri "http://$IP`:$Port/api/IsAlive" -TimeoutSec 5 -ErrorAction Stop
    Write-Host "   ✅ IsAlive returned: $response" -ForegroundColor Green
}
catch {
    Write-Host "   ❌ Failed: $($_.Exception.Message)" -ForegroundColor Red
}

# Test 3: HTTP Swagger
Write-Host "`n3. HTTP Swagger Test:" -ForegroundColor Yellow
try {
    $response = Invoke-WebRequest -Uri "http://$IP`:$Port/swagger/index.html" -TimeoutSec 5 -ErrorAction Stop
    Write-Host "   ✅ Swagger returned status: $($response.StatusCode)" -ForegroundColor Green
}
catch {
    Write-Host "   ❌ Failed: $($_.Exception.Message)" -ForegroundColor Red
}

# Test 4: Try by hostname
Write-Host "`n4. HTTP by Hostname Test:" -ForegroundColor Yellow
try {
    $response = Invoke-RestMethod -Uri "http://$Server`:$Port/api/IsAlive" -TimeoutSec 5 -ErrorAction Stop
    Write-Host "   ✅ IsAlive (hostname) returned: $response" -ForegroundColor Green
}
catch {
    Write-Host "   ❌ Failed: $($_.Exception.Message)" -ForegroundColor Red
}

Write-Host "`nDone." -ForegroundColor Cyan
