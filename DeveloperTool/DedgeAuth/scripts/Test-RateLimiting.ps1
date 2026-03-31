# Test Rate Limiting
# Verifies rate limiting is active

param(
    [string]$BaseUrl = "http://localhost:8100"
)

. "$PSScriptRoot\SecurityTestHelpers.ps1"

Write-Host "Testing Rate Limiting..." -ForegroundColor Yellow

try {
    # Test 1: Global rate limiting works
    $requests = 0
    $rateLimited = $false
    
    for ($i = 1; $i -le 110; $i++) {
        $response = Invoke-ApiRequest -Url "$BaseUrl/health" -Method GET
        $requests++
        
        if ($response.StatusCode -eq 429) {
            $rateLimited = $true
            break
        }
        
        Start-Sleep -Milliseconds 50
    }
    
    Write-TestResult -TestName "Global Rate Limiting" -Category "Rate Limiting" `
        -Passed $rateLimited `
        -Message "Global rate limiting $(if ($rateLimited) { 'active' } else { 'not triggered after $requests requests' })"
    
    # Test 2: Login rate limiting stricter
    Start-Sleep -Seconds 2  # Reset window
    
    $loginRateLimited = $false
    for ($i = 1; $i -le 10; $i++) {
        $body = @{
            email = "test@Dedge.no"
            password = "wrongpassword"
        } | ConvertTo-Json
        
        $response = Invoke-ApiRequest -Url "$BaseUrl/api/auth/login" -Method POST -Body $body
        
        if ($response.StatusCode -eq 429) {
            $loginRateLimited = $true
            break
        }
    }
    
    Write-TestResult -TestName "Login Rate Limiting" -Category "Rate Limiting" `
        -Passed $loginRateLimited `
        -Message "Login rate limiting $(if ($loginRateLimited) { 'active (stricter)' } else { 'not triggered' })"
}
catch {
    Write-TestResult -TestName "Rate Limiting" -Category "Rate Limiting" `
        -Passed $false `
        -Message "Failed to test rate limiting: $($_.Exception.Message)"
}

Write-Host ""
