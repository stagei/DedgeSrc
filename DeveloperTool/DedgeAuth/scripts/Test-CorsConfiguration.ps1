# Test CORS Configuration
# Verifies CORS is properly configured

param(
    [string]$BaseUrl = "http://localhost:8100"
)

. "$PSScriptRoot\SecurityTestHelpers.ps1"

Write-Host "Testing CORS Configuration..." -ForegroundColor Yellow

try {
    # Test 1: CORS headers present on API requests
    # Use GET request and check response headers
    $response = Invoke-WebRequest -Uri "$BaseUrl/api/auth/me" `
        -Method GET `
        -Headers @{ "Origin" = "http://localhost:3000" } `
        -ErrorAction SilentlyContinue
    
    $hasCorsHeaders = $response.Headers.ContainsKey("Access-Control-Allow-Origin")
    
    Write-TestResult -TestName "CORS Headers Present" -Category "CORS Configuration" `
        -Passed $hasCorsHeaders `
        -Message "CORS headers $(if ($hasCorsHeaders) { 'present' } else { 'missing' })"
    
    # Test 2: CORS doesn't allow all origins (in production)
    # In development, localhost origins are allowed
    $allOriginsAllowed = $response.Headers["Access-Control-Allow-Origin"] -eq "*"
    
    Write-TestResult -TestName "CORS Origin Restriction" -Category "CORS Configuration" `
        -Passed (-not $allOriginsAllowed) `
        -Message "CORS $(if ($allOriginsAllowed) { 'allows all origins (security risk)' } else { 'restricts origins correctly' })"
}
catch {
    Write-TestResult -TestName "CORS Configuration" -Category "CORS Configuration" `
        -Passed $false `
        -Message "Failed to test CORS: $($_.Exception.Message)"
}

Write-Host ""
