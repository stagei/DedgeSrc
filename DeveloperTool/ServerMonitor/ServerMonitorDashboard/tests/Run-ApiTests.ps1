<#
.SYNOPSIS
    Automated API tests for ServerMonitor Dashboard
.DESCRIPTION
    Tests all Dashboard API endpoints and outputs results to screen and JSON file
.EXAMPLE
    .\Run-ApiTests.ps1
    .\Run-ApiTests.ps1 -BaseUrl "http://localhost:5100"
#>

param(
    [string]$BaseUrl = "http://localhost:5100",
    [string]$OutputPath = "$PSScriptRoot\test-results.json"
)

$ErrorActionPreference = "Continue"

Write-Host "═══════════════════════════════════════════════════════════════" -ForegroundColor Cyan
Write-Host "  ServerMonitor Dashboard - API Tests" -ForegroundColor Cyan
Write-Host "═══════════════════════════════════════════════════════════════" -ForegroundColor Cyan
Write-Host "  Base URL: $BaseUrl"
Write-Host "  Output:   $OutputPath"
Write-Host "  Time:     $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')"
Write-Host "═══════════════════════════════════════════════════════════════" -ForegroundColor Cyan
Write-Host ""

$results = @()
$passCount = 0
$failCount = 0

function Test-Endpoint {
    param(
        [string]$Name,
        [string]$Method,
        [string]$Url,
        [object]$Body = $null,
        [string]$ExpectedType = "object"
    )
    
    $result = @{
        Name = $Name
        Method = $Method
        Url = $Url
        Timestamp = Get-Date -Format "o"
        Success = $false
        StatusCode = $null
        ResponseTimeMs = $null
        Response = $null
        Error = $null
        Validation = @()
    }
    
    Write-Host "Testing: $Name..." -NoNewline
    
    try {
        $stopwatch = [System.Diagnostics.Stopwatch]::StartNew()
        
        $params = @{
            Uri = $Url
            Method = $Method
            ContentType = "application/json"
            ErrorAction = "Stop"
        }
        
        if ($Body) {
            $params.Body = ($Body | ConvertTo-Json -Depth 10)
        }
        
        $response = Invoke-RestMethod @params
        $stopwatch.Stop()
        
        $result.Success = $true
        $result.StatusCode = 200
        $result.ResponseTimeMs = $stopwatch.ElapsedMilliseconds
        $result.Response = $response
        
        # Validate response based on expected type
        switch ($ExpectedType) {
            "bool" {
                if ($response -is [bool]) {
                    $result.Validation += "✓ Response is boolean"
                } else {
                    $result.Validation += "✗ Expected boolean, got $($response.GetType().Name)"
                    $result.Success = $false
                }
            }
            "object" {
                if ($null -ne $response) {
                    $result.Validation += "✓ Response is not null"
                } else {
                    $result.Validation += "✗ Response is null"
                    $result.Success = $false
                }
            }
            "array" {
                if ($response -is [array] -or $response.Count -ge 0) {
                    $result.Validation += "✓ Response is array/collection"
                } else {
                    $result.Validation += "✗ Expected array"
                    $result.Success = $false
                }
            }
        }
        
        $script:passCount++
        Write-Host " ✅ PASS ($($stopwatch.ElapsedMilliseconds)ms)" -ForegroundColor Green
        
    }
    catch {
        $stopwatch.Stop()
        $result.Error = $_.Exception.Message
        $result.ResponseTimeMs = $stopwatch.ElapsedMilliseconds
        
        # Try to get status code from exception
        if ($_.Exception.Response) {
            $result.StatusCode = [int]$_.Exception.Response.StatusCode
        }
        
        $script:failCount++
        Write-Host " ❌ FAIL: $($_.Exception.Message)" -ForegroundColor Red
    }
    
    return $result
}

# ═══════════════════════════════════════════════════════════════
# Run Tests
# ═══════════════════════════════════════════════════════════════

Write-Host "`n📋 Running API Tests...`n" -ForegroundColor Yellow

# 1. Health Check
$results += Test-Endpoint `
    -Name "GET /api/IsAlive" `
    -Method "GET" `
    -Url "$BaseUrl/api/IsAlive" `
    -ExpectedType "bool"

# 2. Get Servers
$results += Test-Endpoint `
    -Name "GET /api/servers" `
    -Method "GET" `
    -Url "$BaseUrl/api/servers" `
    -ExpectedType "object"

# 3. Get Version
$results += Test-Endpoint `
    -Name "GET /api/version" `
    -Method "GET" `
    -Url "$BaseUrl/api/version" `
    -ExpectedType "object"

# 4. Refresh Servers
$results += Test-Endpoint `
    -Name "POST /api/servers/refresh" `
    -Method "POST" `
    -Url "$BaseUrl/api/servers/refresh" `
    -ExpectedType "object"

# 5. Get servers (after refresh)
$serversResult = Test-Endpoint `
    -Name "GET /api/servers (post-refresh)" `
    -Method "GET" `
    -Url "$BaseUrl/api/servers" `
    -ExpectedType "object"
$results += $serversResult

# 6. Get snapshot for first available server (if any)
if ($serversResult.Success -and $serversResult.Response.servers.Count -gt 0) {
    $firstServer = $serversResult.Response.servers[0].name
    
    $results += Test-Endpoint `
        -Name "GET /api/snapshot/$firstServer (live)" `
        -Method "GET" `
        -Url "$BaseUrl/api/snapshot/$firstServer`?useCached=false" `
        -ExpectedType "object"
    
    $results += Test-Endpoint `
        -Name "GET /api/snapshot/$firstServer (cached)" `
        -Method "GET" `
        -Url "$BaseUrl/api/snapshot/$firstServer`?useCached=true" `
        -ExpectedType "object"
} else {
    Write-Host "⚠️  Skipping snapshot tests - no servers available" -ForegroundColor Yellow
}

# 7. Get specific server
if ($serversResult.Success -and $serversResult.Response.servers.Count -gt 0) {
    $firstServer = $serversResult.Response.servers[0].name
    
    $results += Test-Endpoint `
        -Name "GET /api/servers/$firstServer" `
        -Method "GET" `
        -Url "$BaseUrl/api/servers/$firstServer" `
        -ExpectedType "object"
}

# 8. Get non-existent server (should return 404)
Write-Host "Testing: GET /api/servers/NonExistentServer123..." -NoNewline
try {
    $response = Invoke-RestMethod -Uri "$BaseUrl/api/servers/NonExistentServer123" -Method GET -ErrorAction Stop
    $results += @{
        Name = "GET /api/servers/{nonexistent}"
        Success = $false
        Error = "Expected 404, got success"
        StatusCode = 200
    }
    $script:failCount++
    Write-Host " ❌ FAIL: Expected 404" -ForegroundColor Red
}
catch {
    if ($_.Exception.Response.StatusCode -eq 404) {
        $results += @{
            Name = "GET /api/servers/{nonexistent}"
            Success = $true
            StatusCode = 404
            Validation = @("✓ Correctly returned 404")
        }
        $script:passCount++
        Write-Host " ✅ PASS (correctly returned 404)" -ForegroundColor Green
    } else {
        $results += @{
            Name = "GET /api/servers/{nonexistent}"
            Success = $false
            Error = $_.Exception.Message
        }
        $script:failCount++
        Write-Host " ❌ FAIL: $($_.Exception.Message)" -ForegroundColor Red
    }
}

# ═══════════════════════════════════════════════════════════════
# Summary
# ═══════════════════════════════════════════════════════════════

Write-Host "`n═══════════════════════════════════════════════════════════════" -ForegroundColor Cyan
Write-Host "  Test Results Summary" -ForegroundColor Cyan
Write-Host "═══════════════════════════════════════════════════════════════" -ForegroundColor Cyan
Write-Host "  Total Tests: $($passCount + $failCount)"
Write-Host "  Passed:      $passCount" -ForegroundColor Green
Write-Host "  Failed:      $failCount" -ForegroundColor $(if ($failCount -gt 0) { "Red" } else { "Green" })
Write-Host "═══════════════════════════════════════════════════════════════" -ForegroundColor Cyan

# ═══════════════════════════════════════════════════════════════
# Save Results
# ═══════════════════════════════════════════════════════════════

$outputData = @{
    TestRun = @{
        Timestamp = Get-Date -Format "o"
        BaseUrl = $BaseUrl
        TotalTests = $passCount + $failCount
        Passed = $passCount
        Failed = $failCount
        Duration = "N/A"
    }
    Results = $results
}

$outputData | ConvertTo-Json -Depth 10 | Set-Content -Path $OutputPath -Encoding UTF8
Write-Host "`n📄 Results saved to: $OutputPath" -ForegroundColor Cyan

# Return exit code based on results
if ($failCount -gt 0) {
    Write-Host "`n❌ Some tests failed!" -ForegroundColor Red
    exit 1
} else {
    Write-Host "`n✅ All tests passed!" -ForegroundColor Green
    exit 0
}
