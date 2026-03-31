# Comprehensive DedgeAuth Browser Flow Test
# Tests login and all consumer apps with screenshot capture

param(
    [string]$Email = "geir.helge.starholm@Dedge.no",
    [string]$Password = "GhS-2025!",
    [string]$BaseUrl = "http://localhost",
    [string]$ScreenshotDir = "c:\opt\src\DedgeAuth\screenshots"
)

$ErrorActionPreference = "Continue"

Write-Host "========================================" -ForegroundColor Cyan
Write-Host "DedgeAuth Browser Flow Test" -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor Cyan
Write-Host ""

# Ensure screenshot directory exists
if (-not (Test-Path $ScreenshotDir)) {
    New-Item -ItemType Directory -Path $ScreenshotDir -Force | Out-Null
}

$testResults = @()

# Test 1: Login to DedgeAuth
Write-Host "[1/7] Testing DedgeAuth Login..." -ForegroundColor Yellow
$loginUrl = "$BaseUrl/DedgeAuth/api/auth/login"
try {
    $body = @{
        email = $Email
        password = $Password
    } | ConvertTo-Json
    
    $response = Invoke-RestMethod -Uri $loginUrl -Method Post -Body $body -ContentType "application/json"
    
    if ($response.success -and $response.accessToken) {
        $global:AccessToken = $response.accessToken
        $global:User = $response.user
        
        Write-Host "  ✓ Login successful" -ForegroundColor Green
        Write-Host "    User: $($response.user.displayName)" -ForegroundColor Gray
        Write-Host "    Email: $($response.user.email)" -ForegroundColor Gray
        Write-Host "    Access Level: $($response.user.globalAccessLevel)" -ForegroundColor Gray
        Write-Host "    Token Length: $($response.accessToken.Length) chars" -ForegroundColor Gray
        
        # Decode JWT to show apps
        try {
            $payload = $response.accessToken.Split('.')[1]
            # Add padding if needed
            while ($payload.Length % 4 -ne 0) { $payload += "=" }
            $jsonPayload = [System.Text.Encoding]::UTF8.GetString([System.Convert]::FromBase64String($payload))
            $claims = $jsonPayload | ConvertFrom-Json
            
            if ($claims.appPermissions) {
                $apps = $claims.appPermissions | ConvertFrom-Json
                Write-Host "    Apps:" -ForegroundColor Gray
                $apps.PSObject.Properties | ForEach-Object {
                    Write-Host "      - $($_.Name): $($_.Value)" -ForegroundColor Gray
                }
            }
        } catch {
            Write-Host "    (Could not decode JWT claims)" -ForegroundColor DarkGray
        }
        
        $testResults += [PSCustomObject]@{
            Test = "DedgeAuth Login"
            Status = "PASS"
            Url = $loginUrl
            Details = "Login successful, token acquired"
        }
    } else {
        Write-Host "  ✗ Login failed: $($response.message)" -ForegroundColor Red
        $testResults += [PSCustomObject]@{
            Test = "DedgeAuth Login"
            Status = "FAIL"
            Url = $loginUrl
            Details = $response.message
        }
        Write-Host ""
        Write-Host "Cannot proceed without authentication. Exiting." -ForegroundColor Red
        exit 1
    }
} catch {
    Write-Host "  ✗ Login error: $_" -ForegroundColor Red
    $testResults += [PSCustomObject]@{
        Test = "DedgeAuth Login"
        Status = "FAIL"
        Url = $loginUrl
        Details = $_.Exception.Message
    }
    Write-Host ""
    Write-Host "Cannot proceed without authentication. Exiting." -ForegroundColor Red
    exit 1
}
Write-Host ""

# Function to test an app endpoint
function Test-AppEndpoint {
    param(
        [string]$AppName,
        [string]$AppUrl,
        [string]$Token
    )
    
    Write-Host "[$($testResults.Count + 2)/7] Testing $AppName..." -ForegroundColor Yellow
    Write-Host "  URL: $AppUrl" -ForegroundColor Gray
    
    try {
        # Try to access the app with token
        $headers = @{
            "Authorization" = "Bearer $Token"
        }
        
        $response = Invoke-WebRequest -Uri $AppUrl -Headers $headers -UseBasicParsing -MaximumRedirection 5
        
        $finalUrl = $response.BaseResponse.ResponseUri.AbsoluteUri
        $statusCode = $response.StatusCode
        $contentLength = $response.Content.Length
        
        # Check for styling indicators
        $html = $response.Content
        $hasCSS = $html -match '<link.*?\.css' -or $html -match '<style'
        $hasHeader = $html -match '<header' -or $html -match 'app-header' -or $html -match 'class="header"'
        $hasDarkMode = $html -match 'data-theme="dark"' -or $html -match 'dark-mode' -or $html -match 'theme-dark'
        $hasError = $html -match '404|500|error|Error' -and $html -notmatch 'errorHandler'
        $hasDedgeAuth = $html -match 'DedgeAuth' -or $html -match 'DedgeAuth'
        $hasGreen = $html -match '#008942' -or $html -match 'FK Green'
        
        # Check if redirected
        $redirected = $finalUrl -ne $AppUrl
        
        Write-Host "  ✓ Page loaded" -ForegroundColor Green
        Write-Host "    Status: $statusCode" -ForegroundColor Gray
        Write-Host "    Final URL: $finalUrl" -ForegroundColor Gray
        if ($redirected) {
            Write-Host "    Redirected: Yes" -ForegroundColor Yellow
        }
        Write-Host "    Content Length: $contentLength bytes" -ForegroundColor Gray
        Write-Host "    Has CSS: $(if($hasCSS){'Yes'}else{'No'})" -ForegroundColor Gray
        Write-Host "    Has Header: $(if($hasHeader){'Yes'}else{'No'})" -ForegroundColor Gray
        Write-Host "    Dark Mode: $(if($hasDarkMode){'Yes'}else{'Unknown'})" -ForegroundColor Gray
        Write-Host "    FK Green: $(if($hasGreen){'Yes'}else{'No'})" -ForegroundColor Gray
        Write-Host "    Has Error: $(if($hasError){'Yes'}else{'No'})" -ForegroundColor Gray
        
        $status = if ($hasError) { "WARN" } elseif ($statusCode -eq 200) { "PASS" } else { "WARN" }
        
        $testResults += [PSCustomObject]@{
            Test = $AppName
            Status = $status
            Url = $finalUrl
            StatusCode = $statusCode
            HasCSS = $hasCSS
            HasHeader = $hasHeader
            DarkMode = $hasDarkMode
            HasError = $hasError
            Redirected = $redirected
            Details = "Status $statusCode, Content: $contentLength bytes"
        }
        
    } catch {
        $errorMsg = $_.Exception.Message
        $statusCode = $_.Exception.Response.StatusCode.value__
        
        Write-Host "  ✗ Failed to load" -ForegroundColor Red
        Write-Host "    Error: $errorMsg" -ForegroundColor Red
        if ($statusCode) {
            Write-Host "    Status Code: $statusCode" -ForegroundColor Red
        }
        
        $testResults += [PSCustomObject]@{
            Test = $AppName
            Status = "FAIL"
            Url = $AppUrl
            StatusCode = $statusCode
            Details = $errorMsg
        }
    }
    
    Write-Host ""
}

# Test all consumer apps
Test-AppEndpoint -AppName "GenericLogHandler" -AppUrl "$BaseUrl/GenericLogHandler/" -Token $global:AccessToken
Test-AppEndpoint -AppName "DocView" -AppUrl "$BaseUrl/DocView/" -Token $global:AccessToken
Test-AppEndpoint -AppName "ServerMonitorDashboard" -AppUrl "$BaseUrl/ServerMonitorDashboard/" -Token $global:AccessToken
Test-AppEndpoint -AppName "AutoDocJson" -AppUrl "$BaseUrl/AutoDocJson/" -Token $global:AccessToken
Test-AppEndpoint -AppName "DedgeAuth Admin" -AppUrl "$BaseUrl/DedgeAuth/admin.html" -Token $global:AccessToken

# Summary
Write-Host "========================================" -ForegroundColor Cyan
Write-Host "Test Summary" -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor Cyan

$passCount = ($testResults | Where-Object { $_.Status -eq "PASS" }).Count
$failCount = ($testResults | Where-Object { $_.Status -eq "FAIL" }).Count
$warnCount = ($testResults | Where-Object { $_.Status -eq "WARN" }).Count

Write-Host "Total Tests: $($testResults.Count)" -ForegroundColor White
Write-Host "Passed: $passCount" -ForegroundColor Green
Write-Host "Failed: $failCount" -ForegroundColor Red
Write-Host "Warnings: $warnCount" -ForegroundColor Yellow
Write-Host ""

# Export results
$timestamp = Get-Date -Format "yyyyMMdd_HHmmss"
$reportPath = Join-Path $ScreenshotDir "browser-flow-test_$timestamp.json"
$testResults | ConvertTo-Json -Depth 5 | Out-File $reportPath -Encoding UTF8

Write-Host "Results saved to: $reportPath" -ForegroundColor Cyan
Write-Host ""

# Display detailed results
Write-Host "Detailed Results:" -ForegroundColor Cyan
Write-Host ""
$testResults | Format-Table -AutoSize -Property Test, Status, StatusCode, HasCSS, HasHeader, Redirected

Write-Host ""
Write-Host "Note: Screenshots require Selenium WebDriver or manual capture." -ForegroundColor Yellow
Write-Host "To capture screenshots, use: .\Capture-DedgeAuthScreenshots.ps1" -ForegroundColor Yellow

return $testResults
