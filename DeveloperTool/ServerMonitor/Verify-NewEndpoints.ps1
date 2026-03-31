#!/usr/bin/env pwsh
# Verify new API endpoints after restart

param(
    [string]$Server = "t-no1inltst-db"
)

$baseUrl = "http://$Server`:8999"
Write-Host "Verifying API endpoints on $baseUrl" -ForegroundColor Cyan
Write-Host ""

$tests = @(
    @{ Name = "IsAlive"; Path = "/api/Health/IsAlive" },
    @{ Name = "CurrentVersion"; Path = "/api/Health/CurrentVersion" },
    @{ Name = "Snapshot"; Path = "/api/Snapshot" }
)

$allPassed = $true
foreach ($test in $tests) {
    Write-Host "$($test.Name): " -NoNewline
    try {
        $response = Invoke-RestMethod -Uri "$baseUrl$($test.Path)" -TimeoutSec 5 -ErrorAction Stop
        Write-Host "✅ " -ForegroundColor Green -NoNewline
        if ($test.Name -eq "CurrentVersion") {
            Write-Host "v$($response.version) on $($response.machineName)" -ForegroundColor Gray
        } elseif ($test.Name -eq "IsAlive") {
            Write-Host "$response" -ForegroundColor Gray
        } else {
            Write-Host "OK" -ForegroundColor Gray
        }
    }
    catch {
        Write-Host "❌ $($_.Exception.Message)" -ForegroundColor Red
        $allPassed = $false
    }
}

Write-Host ""
if ($allPassed) {
    Write-Host "🎉 All endpoints working! New version deployed successfully." -ForegroundColor Green
} else {
    Write-Host "⚠️  Some endpoints failed. Please restart the service." -ForegroundColor Yellow
}
