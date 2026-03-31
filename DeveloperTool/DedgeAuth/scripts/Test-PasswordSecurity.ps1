# Test Password Security
# Verifies password hashing (BCrypt) and password requirements

param(
    [string]$BaseUrl = "http://localhost:8100"
)

. "$PSScriptRoot\SecurityTestHelpers.ps1"

Write-Host "Testing Password Security..." -ForegroundColor Yellow

# Test 1: Verify passwords are hashed (check database)
try {
    $connString = "Host=t-no1fkxtst-db;Database=DedgeAuth;Username=postgres;Password=postgres"
    $conn = Get-DatabaseConnection -ConnectionString $connString -DbHost "t-no1fkxtst-db" -Database "DedgeAuth" -Username "postgres" -Password "postgres"
    
    $query = "SELECT password_hash FROM users WHERE password_hash IS NOT NULL LIMIT 1"
    $result = Query-Database -Connection $conn -Query $query
    
    if ($result) {
        $hash = $result[0]
        # BCrypt hashes start with $2a$, $2b$, or $2y$
        $isBcrypt = $hash -match '^\$2[aby]\$'
        
        Write-TestResult -TestName "Password Hashing" -Category "Password Security" `
            -Passed $isBcrypt `
            -Message "Password hash format: $(if ($isBcrypt) { 'BCrypt (correct)' } else { 'Not BCrypt' })"
    } else {
        Write-TestResult -TestName "Password Hashing" -Category "Password Security" `
            -Passed $false `
            -Message "No password hashes found in database"
    }
}
catch {
    Write-TestResult -TestName "Password Hashing" -Category "Password Security" `
        -Passed $false `
        -Message "Failed to check password hashing: $($_.Exception.Message)"
}

# Test 2: Password requirements (try registering with weak password)
try {
    $weakPasswordBody = @{
        email = "test-weak-pwd-$(Get-Random)@Dedge.no"
        displayName = "Test User"
        password = "123"  # Too short
    } | ConvertTo-Json
    
    $response = Invoke-ApiRequest -Url "$BaseUrl/api/auth/register" -Method POST -Body $weakPasswordBody
    
    # Should fail (password too short)
    Write-TestResult -TestName "Password Length Requirement" -Category "Password Security" `
        -Passed (-not $response.Success) `
        -Message "Weak password $(if (-not $response.Success) { 'correctly rejected' } else { 'was accepted (should be rejected)' })"
}
catch {
    Write-TestResult -TestName "Password Length Requirement" -Category "Password Security" `
        -Passed $false `
        -Message "Failed to test password requirements: $($_.Exception.Message)"
}

Write-Host ""
