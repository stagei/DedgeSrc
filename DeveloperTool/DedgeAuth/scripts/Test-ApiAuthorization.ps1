# Test API Authorization
# Verifies API endpoints are properly authorized

param(
    [string]$BaseUrl = "http://localhost:8100"
)

. "$PSScriptRoot\SecurityTestHelpers.ps1"

Write-Host "Testing API Authorization..." -ForegroundColor Yellow

try {
    # Test 1: Protected endpoints require auth
    # Note: /api/apps is intentionally public (for URL fallback)
    $protectedEndpoints = @(
        "/api/auth/me",
        "/api/auth/logout",
        "/api/users"
    )
    
    foreach ($endpoint in $protectedEndpoints) {
        $response = Invoke-ApiRequest -Url "$BaseUrl$endpoint" -Method GET
        
        $isProtected = -not $response.Success -and $response.StatusCode -eq 401
        
        Write-TestResult -TestName "Endpoint Protection: $endpoint" -Category "API Authorization" `
            -Passed $isProtected `
            -Message "$endpoint $(if ($isProtected) { 'requires authentication' } else { 'allows anonymous access' })"
    }
    
    # Test 2: Public endpoints accessible
    $publicEndpoints = @(
        "/health",
        "/api/auth/register",
        "/api/auth/login",
        "/api/apps"  # Intentionally public for URL fallback
    )
    
    foreach ($endpoint in $publicEndpoints) {
        $response = Invoke-ApiRequest -Url "$BaseUrl$endpoint" -Method $(if ($endpoint -match "login|register") { "POST" } else { "GET" })
        
        Write-TestResult -TestName "Public Endpoint: $endpoint" -Category "API Authorization" `
            -Passed ($response.Success -or $response.StatusCode -ne 401) `
            -Message "$endpoint $(if ($response.Success -or $response.StatusCode -ne 401) { 'accessible' } else { 'blocked' })"
    }
}
catch {
    Write-TestResult -TestName "API Authorization" -Category "API Authorization" `
        -Passed $false `
        -Message "Failed to test API authorization: $($_.Exception.Message)"
}

Write-Host ""
