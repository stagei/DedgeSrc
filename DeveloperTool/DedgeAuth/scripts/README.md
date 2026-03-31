# DedgeAuth Scripts

This directory contains PowerShell test scripts for DedgeAuth.

## Server Deployment Scripts

IIS and database setup scripts are maintained separately in DedgePsh and distributed to servers automatically during publish:

| Script | Location |
|--------|----------|
| IIS config | `C:\opt\src\DedgePsh\DevTools\WebSites\DedgeAuth\DedgeAuth-IISConfig\DedgeAuth-IISConfig.ps1` |
| Database setup | `C:\opt\src\DedgePsh\DevTools\WebSites\DedgeAuth\DedgeAuth-DatabaseSetup\DedgeAuth-DatabaseSetup.ps1` |

## Testing Scripts

### Security Tests

| Script | Description |
|--------|-------------|
| `Test-Security-Local.ps1` | Master script that runs all security tests |
| `Test-PasswordSecurity.ps1` | Tests password hashing and requirements |
| `Test-AccountLockout.ps1` | Tests account lockout functionality |
| `Test-JwtTokenSecurity.ps1` | Tests JWT token security |
| `Test-CorsConfiguration.ps1` | Tests CORS configuration |
| `Test-RateLimiting.ps1` | Tests rate limiting policies |
| `Test-DebugEndpoints.ps1` | Tests debug endpoint security |
| `Test-AuthorizationPolicies.ps1` | Tests authorization policies |
| `Test-ApiAuthorization.ps1` | Tests API endpoint authorization |
| `Test-RefreshTokenSecurity.ps1` | Tests refresh token security |
| `Test-SecretsExposure.ps1` | Tests for secrets exposure |
| `Test-ConfigurationValidation.ps1` | Validates configuration |
| `Test-TokenRevocation.ps1` | Tests token revocation |

### Tenant Isolation Tests

| Script | Description |
|--------|-------------|
| `Test-TenantIsolation.ps1` | Tests tenant isolation (database, API, theme) |
| `Setup-TenantIsolationTestData.ps1` | Sets up test data for tenant isolation tests |

### Helper Scripts

| Script | Description |
|--------|-------------|
| `SecurityTestHelpers.ps1` | Helper functions for security testing |

## Run Security Tests

```powershell
cd scripts
.\Test-Security-Local.ps1 -BaseUrl "http://localhost:8100" -OutputPath "..\docs"
```

## See Also

- `docs\IIS-Default-Website-Setup.md` - Manual IIS configuration guide
- `docs\TESTING_GUIDE.md` - Testing guide
