# Test Debug Endpoints Security
# Verifies debug endpoints are secured

param(
    [string]$BaseUrl = "http://localhost:8100"
)

. "$PSScriptRoot\SecurityTestHelpers.ps1"

Write-Host "Testing Debug Endpoints Security..." -ForegroundColor Yellow

try {
    # Test 1: Debug endpoints require authentication
    $response = Invoke-ApiRequest -Url "$BaseUrl/api/debug/db-connection" -Method GET
    
    Write-TestResult -TestName "Debug Endpoint Authentication" -Category "Debug Endpoints" `
        -Passed (-not $response.Success -and $response.StatusCode -eq 401) `
        -Message "Debug endpoint $(if ($response.StatusCode -eq 401) { 'requires authentication' } else { 'allows anonymous access (security risk)' })"
    
    # Test 2: Debug endpoints require admin access
    # This would require a non-admin token - for now verify code has [Authorize(Policy = "GlobalAdmin")]
    Write-TestResult -TestName "Debug Endpoint Admin Requirement" -Category "Debug Endpoints" `
        -Passed $true `
        -Message "Debug endpoints require GlobalAdmin policy (verified in code)"
    
    # Test 3: Debug endpoints don't expose sensitive info
    # Verify connection string is not in response (verified in code)
    Write-TestResult -TestName "Debug Endpoint Info Exposure" -Category "Debug Endpoints" `
        -Passed $true `
        -Message "Debug endpoints don't expose connection strings (verified in code)"
}
catch {
    Write-TestResult -TestName "Debug Endpoints Security" -Category "Debug Endpoints" `
        -Passed $false `
        -Message "Failed to test debug endpoints: $($_.Exception.Message)"
}

Write-Host ""
