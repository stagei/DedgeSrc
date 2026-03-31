# Test Authorization Policies
# Verifies authorization policies work

param(
    [string]$BaseUrl = "http://localhost:8100"
)

. "$PSScriptRoot\SecurityTestHelpers.ps1"

Write-Host "Testing Authorization Policies..." -ForegroundColor Yellow

try {
    # Test 1: Admin endpoints require admin
    $response = Invoke-ApiRequest -Url "$BaseUrl/api/debug/db-connection" -Method GET
    
    Write-TestResult -TestName "Admin Endpoint Protection" -Category "Authorization Policies" `
        -Passed (-not $response.Success) `
        -Message "Admin endpoints $(if (-not $response.Success) { 'require authentication' } else { 'allow anonymous access' })"
    
    # Test 2: User endpoints require auth
    $response = Invoke-ApiRequest -Url "$BaseUrl/api/auth/me" -Method GET
    
    Write-TestResult -TestName "User Endpoint Protection" -Category "Authorization Policies" `
        -Passed (-not $response.Success -and $response.StatusCode -eq 401) `
        -Message "User endpoints $(if ($response.StatusCode -eq 401) { 'require authentication' } else { 'allow anonymous access' })"
    
    # Test 3: Public endpoints accessible
    $response = Invoke-ApiRequest -Url "$BaseUrl/health" -Method GET
    
    Write-TestResult -TestName "Public Endpoint Access" -Category "Authorization Policies" `
        -Passed $response.Success `
        -Message "Public endpoints $(if ($response.Success) { 'accessible' } else { 'blocked incorrectly' })"
}
catch {
    Write-TestResult -TestName "Authorization Policies" -Category "Authorization Policies" `
        -Passed $false `
        -Message "Failed to test authorization: $($_.Exception.Message)"
}

Write-Host ""
