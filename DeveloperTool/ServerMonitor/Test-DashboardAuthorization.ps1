<#
.SYNOPSIS
    Tests ServerMonitorDashboard authorization for different user roles.

.DESCRIPTION
    This script tests the authorization implementation for ServerMonitorDashboard by:
    1. Logging in as the test service user
    2. Changing user roles via DedgeAuth API
    3. Getting new tokens and testing API endpoints
    4. Verifying expected access (200) and denial (403) responses

.NOTES
    Author: AI Agent
    Date: 2026-02-03
    Requirements: 
      - DedgeAuth API running at http://localhost:8100
      - ServerMonitorDashboard running at http://localhost:8998
      - Test users configured in DedgeAuth
#>

param(
    [string]$DedgeAuthUrl = "http://localhost:8100",
    [string]$DashboardUrl = "http://localhost:8998",
    [string]$TestUserEmail = "test.service@Dedge.no",
    [string]$TestUserPassword = "TestPass123!",
    [string]$NoAccessEmail = "test.service@dedge.no",
    [string]$NoAccessPassword = "TestPass123!",
    [switch]$Verbose
)

$ErrorActionPreference = "Stop"

# ═══════════════════════════════════════════════════════════════════════════════
# Helper Functions
# ═══════════════════════════════════════════════════════════════════════════════

function Write-TestHeader {
    param([string]$Title)
    Write-Host ""
    Write-Host ("═" * 80) -ForegroundColor Cyan
    Write-Host "  $Title" -ForegroundColor Cyan
    Write-Host ("═" * 80) -ForegroundColor Cyan
}

function Write-TestResult {
    param(
        [string]$Test,
        [int]$Expected,
        [int]$Actual,
        [string]$Description
    )
    
    $passed = $Expected -eq $Actual
    $status = if ($passed) { "PASS" } else { "FAIL" }
    $color = if ($passed) { "Green" } else { "Red" }
    
    $result = [PSCustomObject]@{
        Test = $Test
        Description = $Description
        Expected = $Expected
        Actual = $Actual
        Status = $status
    }
    
    Write-Host ("  {0,-30} {1,-25} Expected: {2} | Actual: {3} | {4}" -f $Test, $Description, $Expected, $Actual, $status) -ForegroundColor $color
    
    return $result
}

function Get-AuthToken {
    param(
        [string]$Email,
        [string]$Password
    )
    
    $loginBody = @{
        email = $Email
        password = $Password
    } | ConvertTo-Json
    
    try {
        $response = Invoke-RestMethod -Uri "$DedgeAuthUrl/api/auth/login" `
            -Method Post `
            -ContentType "application/json" `
            -Body $loginBody `
            -TimeoutSec 10
        
        return $response.accessToken
    }
    catch {
        Write-Host "  ERROR: Failed to login as $($Email): $($_.Exception.Message)" -ForegroundColor Red
        return $null
    }
}

function Get-UserIdFromToken {
    param([string]$Token)
    
    # Decode JWT payload (middle part)
    $parts = $Token.Split('.')
    if ($parts.Length -ge 2) {
        $payload = $parts[1]
        # Add padding if needed
        while ($payload.Length % 4 -ne 0) {
            $payload += "="
        }
        # Replace URL-safe chars
        $payload = $payload.Replace('-', '+').Replace('_', '/')
        $json = [System.Text.Encoding]::UTF8.GetString([Convert]::FromBase64String($payload))
        $claims = $json | ConvertFrom-Json
        return $claims.sub
    }
    return $null
}

function Get-AppPermissions {
    param([string]$Token)
    
    $parts = $Token.Split('.')
    if ($parts.Length -ge 2) {
        $payload = $parts[1]
        while ($payload.Length % 4 -ne 0) {
            $payload += "="
        }
        $payload = $payload.Replace('-', '+').Replace('_', '/')
        $json = [System.Text.Encoding]::UTF8.GetString([Convert]::FromBase64String($payload))
        $claims = $json | ConvertFrom-Json
        
        if ($claims.appPermissions) {
            return $claims.appPermissions | ConvertFrom-Json -AsHashtable
        }
    }
    return @{}
}

function Set-UserAppRole {
    param(
        [string]$AdminToken,
        [string]$UserId,
        [string]$AppId,
        [string]$Role
    )
    
    $headers = @{
        "Authorization" = "Bearer $AdminToken"
        "Content-Type" = "application/json"
    }
    
    $body = @{
        userId = $UserId
        appId = $AppId
        role = $Role
    } | ConvertTo-Json
    
    try {
        $response = Invoke-RestMethod -Uri "$DedgeAuthUrl/api/permissions" `
            -Method Post `
            -Headers $headers `
            -Body $body `
            -TimeoutSec 10
        
        return $true
    }
    catch {
        Write-Host "  ERROR: Failed to set role: $($_.Exception.Message)" -ForegroundColor Red
        return $false
    }
}

function Get-UserPermissionId {
    param(
        [string]$AdminToken,
        [string]$UserId,
        [string]$AppId
    )
    
    $headers = @{
        "Authorization" = "Bearer $AdminToken"
    }
    
    try {
        $permissions = Invoke-RestMethod -Uri "$DedgeAuthUrl/api/permissions/user/$UserId" `
            -Method Get `
            -Headers $headers `
            -TimeoutSec 10
        
        $perm = $permissions | Where-Object { $_.appId -eq $AppId }
        return $perm.id
    }
    catch {
        return $null
    }
}

function Remove-UserAppPermission {
    param(
        [string]$AdminToken,
        [string]$PermissionId
    )
    
    $headers = @{
        "Authorization" = "Bearer $AdminToken"
    }
    
    try {
        Invoke-RestMethod -Uri "$DedgeAuthUrl/api/permissions/$PermissionId" `
            -Method Delete `
            -Headers $headers `
            -TimeoutSec 10
        
        return $true
    }
    catch {
        Write-Host "  ERROR: Failed to remove permission: $($_.Exception.Message)" -ForegroundColor Red
        return $false
    }
}

function Test-Endpoint {
    param(
        [string]$Token,
        [string]$Url,
        [int]$ExpectedStatus
    )
    
    $headers = @{}
    if ($Token) {
        $headers["Authorization"] = "Bearer $Token"
    }
    
    try {
        $response = Invoke-WebRequest -Uri $Url `
            -Method Get `
            -Headers $headers `
            -TimeoutSec 10 `
            -ErrorAction SilentlyContinue `
            -SkipHttpErrorCheck
        
        return $response.StatusCode
    }
    catch {
        # Parse status from exception
        if ($_.Exception.Response) {
            return [int]$_.Exception.Response.StatusCode
        }
        return 0
    }
}

# ═══════════════════════════════════════════════════════════════════════════════
# Test Configuration
# ═══════════════════════════════════════════════════════════════════════════════

$endpoints = @(
    @{ Path = "/api/servers"; Description = "Read servers (ReadOnly+)"; RequiredRole = "ReadOnly" },
    @{ Path = "/api/alerts/active"; Description = "Active alerts (ReadOnly+)"; RequiredRole = "ReadOnly" },
    @{ Path = "/api/trigger-status"; Description = "Trigger status (Admin)"; RequiredRole = "Admin" },
    @{ Path = "/health/isalive"; Description = "Health check (Public)"; RequiredRole = "Public" }
)

# Roles to test (mapped to DedgeAuth ServerMonitorDashboard roles)
$rolesToTest = @(
    @{ Role = "Admin"; ExpectedAccess = @("ReadOnly", "Admin", "Public") },
    @{ Role = "Operator"; ExpectedAccess = @("ReadOnly", "Public") },
    @{ Role = "Viewer"; ExpectedAccess = @("ReadOnly", "Public") }
)

$results = @()

# ═══════════════════════════════════════════════════════════════════════════════
# Pre-flight Checks
# ═══════════════════════════════════════════════════════════════════════════════

Write-TestHeader "Pre-flight Checks"

# Check DedgeAuth
try {
    $gkHealth = Invoke-RestMethod -Uri "$DedgeAuthUrl/api/apps" -Method Get -TimeoutSec 5
    Write-Host "  [OK] DedgeAuth is running at $DedgeAuthUrl" -ForegroundColor Green
}
catch {
    Write-Host "  [FAIL] DedgeAuth is NOT running at $DedgeAuthUrl" -ForegroundColor Red
    exit 1
}

# Check Dashboard
try {
    $dashHealth = Invoke-RestMethod -Uri "$DashboardUrl/health/isalive" -Method Get -TimeoutSec 5
    Write-Host "  [OK] Dashboard is running at $DashboardUrl" -ForegroundColor Green
}
catch {
    Write-Host "  [FAIL] Dashboard is NOT running at $DashboardUrl" -ForegroundColor Red
    exit 1
}

# ═══════════════════════════════════════════════════════════════════════════════
# Get Admin Token for Managing Permissions
# ═══════════════════════════════════════════════════════════════════════════════

Write-TestHeader "Authentication Setup"

Write-Host "  Logging in as admin user ($TestUserEmail)..."
$adminToken = Get-AuthToken -Email $TestUserEmail -Password $TestUserPassword

if (-not $adminToken) {
    Write-Host "  [FAIL] Could not authenticate admin user" -ForegroundColor Red
    exit 1
}

$adminUserId = Get-UserIdFromToken -Token $adminToken
Write-Host "  [OK] Admin token obtained, User ID: $adminUserId" -ForegroundColor Green

# Get current permissions
$currentPerms = Get-AppPermissions -Token $adminToken
Write-Host "  Current app permissions: $($currentPerms | ConvertTo-Json -Compress)" -ForegroundColor Gray

# ═══════════════════════════════════════════════════════════════════════════════
# Test Each Role
# ═══════════════════════════════════════════════════════════════════════════════

foreach ($roleConfig in $rolesToTest) {
    $role = $roleConfig.Role
    $expectedAccess = $roleConfig.ExpectedAccess
    
    Write-TestHeader "Testing Role: $role"
    
    # Set the user's role
    Write-Host "  Setting user role to: $role" -ForegroundColor Yellow
    $setResult = Set-UserAppRole -AdminToken $adminToken -UserId $adminUserId -AppId "ServerMonitorDashboard" -Role $role
    
    if (-not $setResult) {
        Write-Host "  [FAIL] Could not set role to $role" -ForegroundColor Red
        continue
    }
    
    # Get fresh token with new role
    Start-Sleep -Milliseconds 500
    $testToken = Get-AuthToken -Email $TestUserEmail -Password $TestUserPassword
    
    if (-not $testToken) {
        Write-Host "  [FAIL] Could not get token after role change" -ForegroundColor Red
        continue
    }
    
    # Verify role in token
    $tokenPerms = Get-AppPermissions -Token $testToken
    Write-Host "  Token permissions: $($tokenPerms | ConvertTo-Json -Compress)" -ForegroundColor Gray
    
    # Test each endpoint
    foreach ($endpoint in $endpoints) {
        $url = "$DashboardUrl$($endpoint.Path)"
        $requiredRole = $endpoint.RequiredRole
        
        # Determine expected status
        $expectedStatus = if ($requiredRole -eq "Public" -or $expectedAccess -contains $requiredRole) {
            200
        } else {
            403
        }
        
        $actualStatus = Test-Endpoint -Token $testToken -Url $url -ExpectedStatus $expectedStatus
        
        $result = Write-TestResult -Test $role -Description $endpoint.Description -Expected $expectedStatus -Actual $actualStatus
        $results += $result
    }
}

# ═══════════════════════════════════════════════════════════════════════════════
# Test User Without App Permission (NoAccess)
# ═══════════════════════════════════════════════════════════════════════════════

Write-TestHeader "Testing: NoAccess User ($NoAccessEmail)"

# First, ensure the dedge.no user exists and we can log in
Write-Host "  Logging in as NoAccess user ($NoAccessEmail)..."
$noAccessToken = Get-AuthToken -Email $NoAccessEmail -Password $NoAccessPassword

if ($noAccessToken) {
    Write-Host "  [OK] NoAccess user token obtained" -ForegroundColor Green
    
    # Verify this user has no ServerMonitorDashboard permission
    $noAccessPerms = Get-AppPermissions -Token $noAccessToken
    Write-Host "  Token permissions: $($noAccessPerms | ConvertTo-Json -Compress)" -ForegroundColor Gray
    
    # Test each endpoint - should all return 403 except health
    foreach ($endpoint in $endpoints) {
        $url = "$DashboardUrl$($endpoint.Path)"
        $requiredRole = $endpoint.RequiredRole
        
        # For NoAccess, only public endpoints should return 200
        $expectedStatus = if ($requiredRole -eq "Public") {
            200
        } else {
            403
        }
        
        $actualStatus = Test-Endpoint -Token $noAccessToken -Url $url -ExpectedStatus $expectedStatus
        
        $result = Write-TestResult -Test "NoAccess" -Description $endpoint.Description -Expected $expectedStatus -Actual $actualStatus
        $results += $result
    }
}
else {
    Write-Host "  [INFO] NoAccess user does not exist, skipping" -ForegroundColor Yellow
}

# ═══════════════════════════════════════════════════════════════════════════════
# Test Unauthenticated Access
# ═══════════════════════════════════════════════════════════════════════════════

Write-TestHeader "Testing: Unauthenticated Access (No Token)"

foreach ($endpoint in $endpoints) {
    $url = "$DashboardUrl$($endpoint.Path)"
    $requiredRole = $endpoint.RequiredRole
    
    # Without token, only public endpoints should return 200
    $expectedStatus = if ($requiredRole -eq "Public") {
        200
    } else {
        401
    }
    
    $actualStatus = Test-Endpoint -Token $null -Url $url -ExpectedStatus $expectedStatus
    
    $result = Write-TestResult -Test "Unauthenticated" -Description $endpoint.Description -Expected $expectedStatus -Actual $actualStatus
    $results += $result
}

# ═══════════════════════════════════════════════════════════════════════════════
# Restore Admin Role
# ═══════════════════════════════════════════════════════════════════════════════

Write-TestHeader "Cleanup: Restoring Admin Role"

$restoreResult = Set-UserAppRole -AdminToken $adminToken -UserId $adminUserId -AppId "ServerMonitorDashboard" -Role "Admin"
if ($restoreResult) {
    Write-Host "  [OK] Admin role restored for test user" -ForegroundColor Green
}

# ═══════════════════════════════════════════════════════════════════════════════
# Summary
# ═══════════════════════════════════════════════════════════════════════════════

Write-TestHeader "Test Summary"

$passed = ($results | Where-Object { $_.Status -eq "PASS" }).Count
$failed = ($results | Where-Object { $_.Status -eq "FAIL" }).Count
$total = $results.Count

Write-Host ""
$results | Format-Table -Property Test, Description, Expected, Actual, Status -AutoSize
Write-Host ""
Write-Host ("  Total: {0} | Passed: {1} | Failed: {2}" -f $total, $passed, $failed) -ForegroundColor $(if ($failed -eq 0) { "Green" } else { "Red" })
Write-Host ""

# Return results for programmatic use
return $results
