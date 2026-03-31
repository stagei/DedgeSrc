# DedgeAuth Implementation Guide
## Replicating DedgeAuth Security, Tenant Isolation, and Theme Isolation Testing

**Target Project:** DedgeAuth (copy of DedgeAuth)  
**Purpose:** Step-by-step guide for an AI to implement the same security improvements, tenant isolation, and theme isolation testing that were performed on DedgeAuth  
**Date:** February 5, 2026

---

## Table of Contents

1. [Overview](#overview)
2. [Prerequisites](#prerequisites)
3. [Phase 1: Security Fixes Implementation](#phase-1-security-fixes-implementation)
4. [Phase 2: Test Infrastructure Setup](#phase-2-test-infrastructure-setup)
5. [Phase 3: Security Testing Scripts](#phase-3-security-testing-scripts)
6. [Phase 4: Tenant Isolation Testing](#phase-4-tenant-isolation-testing)
7. [Phase 5: Theme Isolation Testing](#phase-5-theme-isolation-testing)
8. [Phase 6: Running Tests](#phase-6-running-tests)
9. [Code References](#code-references)

---

## Overview

This guide documents how to replicate all security improvements, tenant isolation verification, and theme isolation testing performed on DedgeAuth. The implementation includes:

- **7 Security Fixes**: CORS, Rate Limiting, Debug Endpoints, Account Lockout, Configuration, Secrets Removal, Token Revocation
- **18 Security Test Scripts**: Comprehensive automated testing
- **14 Tenant Isolation Tests**: Data, theme, and API isolation verification
- **Test Infrastructure**: PowerShell helper functions and result aggregation

---

## Prerequisites

1. **DedgeAuth Project Structure**
   - ASP.NET Core API project (similar to `DedgeAuth.Api`)
   - Services project (similar to `DedgeAuth.Services`)
   - Data project with Entity Framework Core (similar to `DedgeAuth.Data`)
   - PostgreSQL database configured

2. **PowerShell Environment**
   - PowerShell 7+ installed
   - Script execution policy: `Set-ExecutionPolicy -ExecutionPolicy RemoteSigned -Scope CurrentUser`

3. **Test Data**
   - Two test tenants configured (Tenant A and Tenant B)
   - Test users for each tenant
   - Test products for each tenant

4. **Base URL**
   - API running on `http://localhost:8100` (or configure as needed)

---

## Phase 1: Security Fixes Implementation

### Fix 1: CORS Configuration

**File:** `src/DedgeAuth.Api/Program.cs`

**Location:** In `builder.Services.AddCors()` configuration section

**Code to Add/Modify:**

```csharp
// Configure CORS based on environment
builder.Services.AddCors(options =>
{
    if (builder.Environment.IsDevelopment())
    {
        // Development: Allow localhost origins
        options.AddDefaultPolicy(policy =>
        {
            policy.WithOrigins("http://localhost:8100", "http://localhost:3000", "http://127.0.0.1:8100")
                  .AllowAnyHeader()
                  .AllowAnyMethod()
                  .AllowCredentials();
        });
    }
    else
    {
        // Production: Restrict to configured origins
        var allowedOrigins = builder.Configuration.GetSection("Cors:AllowedOrigins").Get<string[]>() 
            ?? new[] { builder.Configuration["AuthConfiguration:BaseUrl"] ?? "https://portal.Dedge.no" };
        
        options.AddDefaultPolicy(policy =>
        {
            policy.WithOrigins(allowedOrigins)
                  .AllowAnyHeader()
                  .AllowAnyMethod()
                  .AllowCredentials();
        });
    }
});
```

**File:** `src/DedgeAuth.Api/appsettings.json`

**Location:** Add new section after `ConnectionStrings`

**Code to Add:**

```json
{
  "Cors": {
    "AllowedOrigins": [
      "https://portal.Dedge.no"
    ]
  }
}
```

**Reference:** See `AzureDeploy/src/DedgeAuth.Api/Program.cs` lines 123-151

---

### Fix 2: Rate Limiting

**File:** `src/DedgeAuth.Api/Program.cs`

**Location:** After `builder.Services.AddOpenApi()` and before `builder.Services.AddDbContext()`

**Code to Add:**

```csharp
// Add rate limiting
builder.Services.AddRateLimiter(options =>
{
    // Global rate limiter
    options.GlobalLimiter = System.Threading.RateLimiting.PartitionedRateLimiter.Create<HttpContext, string>(context =>
        System.Threading.RateLimiting.RateLimitPartition.GetFixedWindowLimiter(
            partitionKey: context.User.Identity?.Name ?? context.Connection.RemoteIpAddress?.ToString() ?? "anonymous",
            factory: partition => new System.Threading.RateLimiting.FixedWindowRateLimiterOptions
            {
                AutoReplenishment = true,
                PermitLimit = 100,
                Window = TimeSpan.FromMinutes(1)
            }));
    
    // Stricter rate limiting for login endpoint
    options.AddPolicy("login", context =>
        System.Threading.RateLimiting.RateLimitPartition.GetFixedWindowLimiter(
            partitionKey: context.Connection.RemoteIpAddress?.ToString() ?? "anonymous",
            factory: partition => new System.Threading.RateLimiting.FixedWindowRateLimiterOptions
            {
                PermitLimit = 5,
                Window = TimeSpan.FromMinutes(1),
                AutoReplenishment = true
            }));
});
```

**Location:** In `var app = builder.Build();` section, add middleware

**Code to Add:**

```csharp
app.UseCors();
app.UseRateLimiter(); // Add rate limiting middleware
app.UseStaticFiles();
```

**File:** `src/DedgeAuth.Api/Controllers/AuthController.cs`

**Location:** Add using statement at top

**Code to Add:**

```csharp
using Microsoft.AspNetCore.RateLimiting;
```

**Location:** On `Login` method, add attribute

**Code to Add:**

```csharp
[HttpPost("login")]
[AllowAnonymous]
[EnableRateLimiting("login")] // Apply stricter rate limiting to login
public async Task<IActionResult> Login([FromBody] LoginRequest request)
{
    // ... existing code
}
```

**Reference:** See `AzureDeploy/src/DedgeAuth.Api/Program.cs` lines 25-49, 162

---

### Fix 3: Debug Endpoints Security

**File:** `src/DedgeAuth.Api/Controllers/DebugController.cs`

**Location:** Add authorization attribute to entire controller class

**Code to Modify:**

```csharp
[ApiController]
[Route("api/[controller]")]
[Authorize(Policy = "GlobalAdmin")] // Require GlobalAdmin for all debug endpoints
public class DebugController : ControllerBase
{
    // ... existing code
}
```

**Location:** In `TestDbConnection` method, remove connection string from response

**Code to Modify:**

```csharp
[HttpGet("db-connection")]
public async Task<IActionResult> TestDbConnection()
{
    var connectionString = _configuration.GetConnectionString("AuthDb");
    
    try
    {
        await using var connection = new NpgsqlConnection(connectionString);
        await connection.OpenAsync();
        
        await using var command = new NpgsqlCommand("SELECT version()", connection);
        var version = await command.ExecuteScalarAsync();

        // Don't expose connection string details - only show status
        return Ok(new
        {
            Status = "Connected",
            PostgreSQLVersion = version?.ToString()
            // ConnectionString removed for security
        });
    }
    catch (Exception ex)
    {
        _logger.LogError(ex, "Database connection failed");
        return StatusCode(500, new { error = ex.Message });
    }
}
```

**Location:** In `GetProductsRaw` and `GetProductsEF` methods, make error messages generic

**Code to Modify:**

```csharp
catch (Exception ex)
{
    _logger.LogError(ex, "Error in GetProductsRaw");
    return StatusCode(500, new { error = "An error occurred while processing the request." });
}
```

**Reference:** See `AzureDeploy/src/DedgeAuth.Api/Controllers/DebugController.cs` lines 11, 111-137, 71-75, 104-108

---

### Fix 4: Account Lockout Logic

**File:** `src/DedgeAuth.Services/AuthService.cs`

**Location:** In `LoginWithPasswordAsync` method, move lockout check BEFORE password verification

**Code to Modify:**

```csharp
public async Task<AuthResult> LoginWithPasswordAsync(string email, string password, string? ipAddress = null)
{
    // ... existing user lookup code ...

    if (!user.IsActive)
    {
        return AuthResult.Failed("Account is inactive.");
    }

    // Check lockout BEFORE password verification
    if (user.IsLockedOut)
    {
        _logger.LogWarning("Login failed - account locked until {LockoutUntil}: {Email} ({UserId})", 
            user.LockoutUntil, email, user.Id);
        return AuthResult.Failed("Invalid email or password."); // Generic message for security
    }

    if (string.IsNullOrEmpty(user.PasswordHash))
    {
        return AuthResult.Failed("Password login is not enabled for this account. Use magic link.");
    }

    if (!BCrypt.Net.BCrypt.Verify(password, user.PasswordHash))
    {
        user.FailedLoginCount++;
        
        if (user.FailedLoginCount >= _config.MaxFailedLoginAttempts)
        {
            user.LockoutUntil = DateTime.UtcNow.AddMinutes(_config.LockoutDurationMinutes);
        }
        await _context.SaveChangesAsync();
        return AuthResult.Failed("Invalid email or password.");
    }
    
    // Password is correct - reset failed login count and lockout
    if (user.FailedLoginCount > 0 || user.LockoutUntil.HasValue)
    {
        user.FailedLoginCount = 0;
        user.LockoutUntil = null;
        await _context.SaveChangesAsync();
    }

    // ... rest of successful login code ...
}
```

**Reference:** See `AzureDeploy/src/DedgeAuth.Services/AuthService.cs` lines 121-157

---

### Fix 5: Configuration Keys

**File:** `src/DedgeAuth.Api/appsettings.json`

**Location:** Add missing configuration keys

**Code to Add:**

```json
{
  "ConnectionStrings": {
    "AuthDb": "Host=localhost;Database=DedgeAuth;Username=postgres;Password=postgres",
    "DefaultConnection": "Host=localhost;Database=DedgeAuth;Username=postgres;Password=postgres"
  },
  "AuthConfiguration": {
    "JwtSecret": "your-secret-key-here",
    "JwtIssuer": "DedgeAuth",
    "JwtAudience": "DedgeAuth",
    "Issuer": "DedgeAuth",
    "Audience": "DedgeAuth"
  }
}
```

**Reference:** See `AzureDeploy/src/DedgeAuth.Api/appsettings.json`

---

### Fix 6: Secrets Removal

**File:** `src/DedgeAuth.Api/appsettings.json`

**Location:** Remove placeholder values from Stripe configuration

**Code to Modify:**

```json
{
  "Payment": {
    "Provider": "Dummy",
    "Stripe": {
      "SecretKey": "",
      "PublishableKey": ""
    }
  }
}
```

**Reference:** See `AzureDeploy/src/DedgeAuth.Api/appsettings.json`

---

### Fix 7: Token Revocation

**File:** `src/DedgeAuth.Api/Controllers/AuthController.cs`

**Location:** On `Logout` method, add authorization requirement

**Code to Modify:**

```csharp
[HttpPost("logout")]
[Authorize] // Add authorization requirement
public async Task<IActionResult> Logout()
{
    var userId = User.FindFirst(System.Security.Claims.ClaimTypes.NameIdentifier)?.Value;
    
    Response.Cookies.Delete("refreshToken");
    
    // Revoke all refresh tokens for this user
    if (Guid.TryParse(userId, out var userGuid))
    {
        var revokedCount = await _authService.RevokeAllUserTokensAsync(userGuid, "self-logout");
    }

    return Ok(new { success = true });
}
```

**Reference:** See `AzureDeploy/src/DedgeAuth.Api/Controllers/AuthController.cs` lines 210-230

---

## Phase 2: Test Infrastructure Setup

### Step 1: Create Test Helpers Script

**File:** `scripts/SecurityTestHelpers.ps1`

**Purpose:** Shared functions for all test scripts

**Code:** Copy entire file from `AzureDeploy/scripts/SecurityTestHelpers.ps1`

**Key Functions:**
- `Write-TestResult` - Records test results to global array
- `Login-AsUser` - Authenticates and returns token
- `Invoke-ApiRequest` - Makes API calls with error handling
- `Get-DatabaseConnection` - Connects to PostgreSQL database
- `Query-Database` - Executes SQL queries
- `Decode-JwtToken` - Decodes JWT tokens
- `Export-TestResults` - Exports results to JSON and HTML
- `Generate-HtmlReport` - Creates HTML report

**Reference:** See `AzureDeploy/scripts/SecurityTestHelpers.ps1` (entire file)

---

### Step 2: Create Master Test Runner

**File:** `scripts/Test-Security-Local.ps1`

**Purpose:** Executes all security test scripts and generates reports

**Code:** Copy entire file from `AzureDeploy/scripts/Test-Security-Local.ps1`

**Key Features:**
- Dot-sources all individual test scripts
- Collects results in global array
- Generates JSON and HTML reports
- Provides summary statistics

**Reference:** See `AzureDeploy/scripts/Test-Security-Local.ps1` (entire file)

---

## Phase 3: Security Testing Scripts

Create the following test scripts in `scripts/` directory. Each script follows the same pattern:

1. Dot-source `SecurityTestHelpers.ps1`
2. Use `Write-TestResult` to record results
3. Use `Login-AsUser` and `Invoke-ApiRequest` for API calls
4. Test specific security aspect

### Script 1: Password Security

**File:** `scripts/Test-PasswordSecurity.ps1`

**Purpose:** Verifies password hashing (BCrypt) and password requirements

**Key Tests:**
- Passwords are hashed with BCrypt
- Password requirements enforced
- Password hash verification

**Reference:** Copy from `AzureDeploy/scripts/Test-PasswordSecurity.ps1`

---

### Script 2: Account Lockout

**File:** `scripts/Test-AccountLockout.ps1`

**Purpose:** Verifies account lockout after failed login attempts

**Key Tests:**
- Account locks after max failed attempts
- Lockout prevents login
- Lockout resets on successful login

**Reference:** Copy from `AzureDeploy/scripts/Test-AccountLockout.ps1`

---

### Script 3: JWT Token Security

**File:** `scripts/Test-JwtTokenSecurity.ps1`

**Purpose:** Verifies JWT token structure and security

**Key Tests:**
- Token contains required claims
- Token expiration works
- Token signature validation

**Reference:** Copy from `AzureDeploy/scripts/Test-JwtTokenSecurity.ps1`

---

### Script 4: CORS Configuration

**File:** `scripts/Test-CorsConfiguration.ps1`

**Purpose:** Verifies CORS is properly configured

**Key Tests:**
- CORS headers present
- CORS doesn't allow all origins
- CORS preflight rejects unauthorized origins

**Reference:** Copy from `AzureDeploy/scripts/Test-CorsConfiguration.ps1` (provided above)

---

### Script 5: Rate Limiting

**File:** `scripts/Test-RateLimiting.ps1`

**Purpose:** Verifies rate limiting is active

**Key Tests:**
- Global rate limiting works
- Login rate limiting stricter
- Rate limit headers present

**Reference:** Copy from `AzureDeploy/scripts/Test-RateLimiting.ps1`

---

### Script 6: Debug Endpoints

**File:** `scripts/Test-DebugEndpoints.ps1`

**Purpose:** Verifies debug endpoints are secured

**Key Tests:**
- Debug endpoints require authentication
- Debug endpoints require admin access
- Debug endpoints don't expose sensitive info

**Reference:** Copy from `AzureDeploy/scripts/Test-DebugEndpoints.ps1` (provided above)

---

### Script 7: SQL Injection Prevention

**File:** `scripts/Test-SqlInjection.ps1`

**Purpose:** Verifies SQL injection protection

**Key Tests:**
- SQL injection attempts fail
- Parameterized queries used
- No SQL errors exposed

**Reference:** Copy from `AzureDeploy/scripts/Test-SqlInjection.ps1`

---

### Script 8: XSS Prevention

**File:** `scripts/Test-XssPrevention.ps1`

**Purpose:** Verifies XSS protection

**Key Tests:**
- Script tags sanitized
- HTML entities encoded
- Content Security Policy headers

**Reference:** Copy from `AzureDeploy/scripts/Test-XssPrevention.ps1`

---

### Script 9: Input Validation

**File:** `scripts/Test-InputValidation.ps1`

**Purpose:** Verifies input validation

**Key Tests:**
- Invalid input rejected
- Validation errors returned
- No injection via input

**Reference:** Copy from `AzureDeploy/scripts/Test-InputValidation.ps1`

---

### Script 10: Error Handling

**File:** `scripts/Test-ErrorHandling.ps1`

**Purpose:** Verifies error handling doesn't expose sensitive info

**Key Tests:**
- Generic error messages
- No stack traces exposed
- No sensitive data in errors

**Reference:** Copy from `AzureDeploy/scripts/Test-ErrorHandling.ps1`

---

### Script 11: Authorization Policies

**File:** `scripts/Test-AuthorizationPolicies.ps1`

**Purpose:** Verifies authorization policies work

**Key Tests:**
- Admin endpoints require admin
- User endpoints require auth
- Unauthorized access blocked

**Reference:** Copy from `AzureDeploy/scripts/Test-AuthorizationPolicies.ps1`

---

### Script 12: API Authorization

**File:** `scripts/Test-ApiAuthorization.ps1`

**Purpose:** Verifies API endpoints are properly authorized

**Key Tests:**
- Protected endpoints require auth
- Public endpoints accessible
- Role-based access works

**Reference:** Copy from `AzureDeploy/scripts/Test-ApiAuthorization.ps1`

---

### Script 13: Refresh Token Security

**File:** `scripts/Test-RefreshTokenSecurity.ps1`

**Purpose:** Verifies refresh token security

**Key Tests:**
- Refresh tokens are HTTP-only cookies
- Refresh tokens expire
- Refresh tokens can be revoked

**Reference:** Copy from `AzureDeploy/scripts/Test-RefreshTokenSecurity.ps1`

---

### Script 14: Session Validation

**File:** `scripts/Test-SessionValidation.ps1`

**Purpose:** Verifies session validation

**Key Tests:**
- Sessions validated correctly
- Expired sessions rejected
- Revoked sessions rejected

**Reference:** Copy from `AzureDeploy/scripts/Test-SessionValidation.ps1`

---

### Script 15: Secrets Exposure

**File:** `scripts/Test-SecretsExposure.ps1`

**Purpose:** Verifies no secrets exposed in responses

**Key Tests:**
- No secrets in API responses
- No secrets in HTML
- No secrets in error messages

**Reference:** Copy from `AzureDeploy/scripts/Test-SecretsExposure.ps1`

---

### Script 16: Configuration Validation

**File:** `scripts/Test-ConfigurationValidation.ps1`

**Purpose:** Verifies configuration is valid

**Key Tests:**
- Required config keys present
- Config values valid
- No placeholder values

**Reference:** Copy from `AzureDeploy/scripts/Test-ConfigurationValidation.ps1`

---

### Script 17: Dependency Vulnerabilities

**File:** `scripts/Test-DependencyVulnerabilities.ps1`

**Purpose:** Checks for known vulnerabilities in dependencies

**Key Tests:**
- No critical vulnerabilities
- Outdated packages identified
- Security advisories checked

**Reference:** Copy from `AzureDeploy/scripts/Test-DependencyVulnerabilities.ps1`

---

## Phase 4: Tenant Isolation Testing

### Step 1: Create Tenant Isolation Test Script

**File:** `scripts/Test-TenantIsolation.ps1`

**Purpose:** Comprehensive tenant isolation testing

**Code:** Copy entire file from `AzureDeploy/scripts/Test-TenantIsolation.ps1`

**Key Test Categories:**

1. **Products Isolation** (3 tests)
   - Users see only their tenant's products
   - Users cannot access other tenant's products
   - TenantId query parameter cannot bypass isolation

2. **Shopping Cart Isolation** (2 tests)
   - Users can only add their tenant's products
   - Users from same tenant have separate carts

3. **Orders Isolation** (1 test)
   - Users see only their orders

4. **Theme/CSS Isolation** (5 tests)
   - Tenant A CSS contains red color (#FF0000)
   - Tenant B CSS contains blue color (#0000FF)
   - No CSS leakage between tenants
   - Primary colors are isolated
   - Display names are isolated

5. **JWT Token Isolation** (2 tests)
   - Tokens contain correct tenant info
   - Tokens cannot access other tenant's data

6. **API Endpoint Isolation** (1 test)
   - Users can access their tenant info

**Reference:** See `AzureDeploy/scripts/Test-TenantIsolation.ps1` (entire file provided above)

---

### Step 2: Create Test Data Setup Script

**File:** `scripts/Setup-TenantIsolationTestData.ps1`

**Purpose:** Creates test tenants, users, and products for isolation testing

**Key Features:**
- Creates Tenant A (tenant-a.test, red theme)
- Creates Tenant B (tenant-b.test, blue theme)
- Creates test users for each tenant
- Creates test products for each tenant
- Saves test data to JSON file

**Reference:** Create similar to `AzureDeploy/scripts/Setup-TenantIsolationTestData.ps1`

---

## Phase 5: Theme Isolation Testing

Theme isolation is tested as part of `Test-TenantIsolation.ps1` (Phase 4). The tests verify:

1. **CSS Isolation**
   - Each tenant's CSS contains their primary color
   - No CSS leakage between tenants
   - CSS variables are tenant-specific

2. **Color Isolation**
   - Primary colors are correctly isolated
   - Theme colors don't leak

3. **Branding Isolation**
   - Display names are isolated
   - Logos are tenant-specific
   - Tenant settings don't leak

**Reference:** See `AzureDeploy/scripts/Test-TenantIsolation.ps1` lines 354-439

---

## Phase 6: Running Tests

### Step 1: Start the API

```powershell
cd src/DedgeAuth.Api
dotnet run
```

Wait for API to be ready (check `http://localhost:8100/health`)

---

### Step 2: Setup Test Data

```powershell
cd scripts
.\Setup-TenantIsolationTestData.ps1 -BaseUrl "http://localhost:8100"
```

---

### Step 3: Run Security Tests

```powershell
cd scripts
.\Test-Security-Local.ps1 -BaseUrl "http://localhost:8100"
```

**Output:**
- Console output with test results
- JSON report: `docs/SECURITY_TEST_RESULTS_LOCAL_YYYYMMDD_HHMMSS.json`
- HTML report: `docs/SECURITY_TEST_RESULTS_LOCAL_YYYYMMDD_HHMMSS.html`

---

### Step 4: Run Tenant Isolation Tests

```powershell
cd scripts
.\Test-TenantIsolation.ps1 -BaseUrl "http://localhost:8100"
```

**Output:**
- Console output with test results
- JSON report: `docs/TENANT_ISOLATION_TEST_RESULTS_YYYYMMDD_HHMMSS.json`

---

### Step 5: Review Results

1. Check console output for immediate feedback
2. Open HTML report in browser for detailed view
3. Review JSON report for programmatic analysis
4. Fix any failing tests
5. Re-run tests until all pass

---

## Code References

### Files Modified in DedgeAuth

1. **Program.cs**
   - Location: `AzureDeploy/src/DedgeAuth.Api/Program.cs`
   - Changes: CORS, Rate Limiting (lines 25-49, 123-151, 162)

2. **AuthService.cs**
   - Location: `AzureDeploy/src/DedgeAuth.Services/AuthService.cs`
   - Changes: Account Lockout Logic (lines 121-157)

3. **AuthController.cs**
   - Location: `AzureDeploy/src/DedgeAuth.Api/Controllers/AuthController.cs`
   - Changes: Rate Limiting, Token Revocation (lines 59, 211)

4. **DebugController.cs**
   - Location: `AzureDeploy/src/DedgeAuth.Api/Controllers/DebugController.cs`
   - Changes: Authorization, Sensitive Info Removal (lines 11, 111-137, 71-75, 104-108)

5. **appsettings.json**
   - Location: `AzureDeploy/src/DedgeAuth.Api/appsettings.json`
   - Changes: Configuration Keys, CORS, Secrets Removal

### Test Scripts Location

All test scripts are in: `AzureDeploy/scripts/`

- `SecurityTestHelpers.ps1` - Helper functions
- `Test-Security-Local.ps1` - Master test runner
- `Test-*.ps1` - Individual test scripts (18 scripts)
- `Test-TenantIsolation.ps1` - Tenant isolation tests
- `Setup-TenantIsolationTestData.ps1` - Test data setup

### Documentation Location

All documentation is in: `AzureDeploy/docs/`

- `SECURITY_FIXES_IMPLEMENTED.md` - Security fixes documentation
- `SECURITY_TESTING_PLAN_LOCAL.md` - Security testing plan
- `TENANT_ISOLATION_TESTING_PLAN.md` - Tenant isolation plan
- `VERIFICATION_SUMMARY.md` - Verification summary

---

## Implementation Checklist

- [ ] **Phase 1: Security Fixes**
  - [ ] Fix 1: CORS Configuration
  - [ ] Fix 2: Rate Limiting
  - [ ] Fix 3: Debug Endpoints Security
  - [ ] Fix 4: Account Lockout Logic
  - [ ] Fix 5: Configuration Keys
  - [ ] Fix 6: Secrets Removal
  - [ ] Fix 7: Token Revocation

- [ ] **Phase 2: Test Infrastructure**
  - [ ] Create `SecurityTestHelpers.ps1`
  - [ ] Create `Test-Security-Local.ps1`

- [ ] **Phase 3: Security Test Scripts**
  - [ ] Create all 18 test scripts
  - [ ] Verify each script works

- [ ] **Phase 4: Tenant Isolation**
  - [ ] Create `Test-TenantIsolation.ps1`
  - [ ] Create `Setup-TenantIsolationTestData.ps1`
  - [ ] Verify test data setup works

- [ ] **Phase 5: Theme Isolation**
  - [ ] Verify theme tests in tenant isolation script

- [ ] **Phase 6: Running Tests**
  - [ ] Run security tests
  - [ ] Run tenant isolation tests
  - [ ] Fix any failing tests
  - [ ] Verify all tests pass

---

## Notes for AI Implementation

1. **File Paths**: Adjust all file paths to match DedgeAuth project structure
2. **Namespace Changes**: Update namespaces from `DedgeAuth.*` to `DedgeAuth.*`
3. **Database**: Ensure PostgreSQL connection strings match DedgeAuth configuration
4. **Test Users**: Create test users matching the email patterns used in tests
5. **Tenant Setup**: Ensure two test tenants exist with different themes
6. **Dependencies**: Install required NuGet packages (RateLimiting, etc.)
7. **PowerShell**: Ensure PowerShell 7+ is available and execution policy allows scripts

---

## Expected Results

After completing all phases:

- ✅ **7 Security Fixes** implemented
- ✅ **18 Security Test Scripts** created and passing
- ✅ **14 Tenant Isolation Tests** created and passing
- ✅ **Theme Isolation** verified
- ✅ **Test Reports** generated (JSON and HTML)
- ✅ **All Tests Passing** (or documented acceptable failures)

---

## Troubleshooting

### Common Issues

1. **PowerShell Script Execution Policy**
   ```powershell
   Set-ExecutionPolicy -ExecutionPolicy RemoteSigned -Scope CurrentUser
   ```

2. **Npgsql.dll Not Found**
   - Build the project first: `dotnet build`
   - Ensure DLLs are in `bin/Debug/net10.0/` or `bin/Release/net10.0/`

3. **Portal Not Available (503 Errors)**
   - Ensure API is running
   - Check database connection
   - Verify appsettings.json configuration

4. **Test Data Not Found**
   - Run `Setup-TenantIsolationTestData.ps1` first
   - Verify test data JSON file exists

5. **Global Variable Not Persisting**
   - Ensure scripts use dot-sourcing (`. $scriptPath`)
   - Use `$Global:SecurityTestResults` for global scope

---

## Conclusion

This guide provides complete instructions for replicating all security improvements, tenant isolation, and theme isolation testing from DedgeAuth to DedgeAuth. Follow each phase sequentially, verify each step, and ensure all tests pass before proceeding to the next phase.

For questions or issues, refer to the original DedgeAuth implementation files listed in the Code References section.
