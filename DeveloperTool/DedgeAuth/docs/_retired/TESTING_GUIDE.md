# DedgeAuth Comprehensive Testing Guide

## Overview

This guide explains how to run comprehensive security and tenant isolation tests for DedgeAuth.

## Prerequisites

1. **API Running**: DedgeAuth API must be running on `http://localhost:8100`
   ```powershell
   cd src\DedgeAuth.Api
   dotnet run
   ```

2. **Database Access**: PostgreSQL must be accessible at `t-no1fkxtst-db:8432`

3. **PowerShell**: PowerShell 7+ with execution policy allowing scripts
   ```powershell
   Set-ExecutionPolicy -ExecutionPolicy RemoteSigned -Scope CurrentUser
   ```

4. **PostgreSQL Client**: `psql.exe` must be available for database tests

## Test Structure

### Security Tests (12 scripts)
- Password Security
- Account Lockout
- JWT Token Security
- CORS Configuration
- Rate Limiting
- Debug Endpoints
- Authorization Policies
- API Authorization
- Refresh Token Security
- Secrets Exposure
- Configuration Validation
- Token Revocation

### Tenant Isolation Tests
- Database Isolation (user-tenant associations)
- API Isolation (tenant data filtering)
- Theme/CSS Isolation (tenant-specific themes)
- Web/UI Isolation (tenant branding)

## Running Tests

### Step 1: Start the API

```powershell
cd src\DedgeAuth.Api
dotnet run
```

Wait for API to be ready (check `http://localhost:8100/health`)

### Step 2: Setup Test Data

```powershell
cd scripts
.\Setup-TenantIsolationTestData.ps1 -BaseUrl "http://localhost:8100"
```

**Note**: This creates test data definitions. You may need to manually create tenants and users via API or database if you don't have admin access.

### Step 3: Run Security Tests

```powershell
cd scripts
.\Test-Security-Local.ps1 -BaseUrl "http://localhost:8100" -OutputPath "..\docs"
```

**Output**:
- Console output with test results
- JSON report: `docs/SECURITY_TEST_RESULTS_LOCAL_YYYYMMDD_HHMMSS.json`
- HTML report: `docs/SECURITY_TEST_RESULTS_LOCAL_YYYYMMDD_HHMMSS.html`

### Step 4: Run Tenant Isolation Tests

```powershell
cd scripts
.\Test-TenantIsolation.ps1 -BaseUrl "http://localhost:8100"
```

**Output**:
- Console output with test results
- JSON report: `docs/TENANT_ISOLATION_TEST_RESULTS_YYYYMMDD_HHMMSS.json`
- HTML report: `docs/TENANT_ISOLATION_TEST_RESULTS_YYYYMMDD_HHMMSS.html`

## Test Results

### Understanding Results

- **PASS**: Test passed successfully
- **FAIL**: Test failed (check message for details)

### Common Issues

1. **API Not Running**
   - Error: "No connection could be made because the target machine actively refused it"
   - Solution: Start the API with `dotnet run`

2. **Database Connection Failed**
   - Error: "Failed to connect to PostgreSQL"
   - Solution: Verify database is running and connection string is correct

3. **Test Users Don't Exist**
   - Error: "Login failed" or "Could not obtain test token"
   - Solution: Create test users manually or via DatabaseSeeder

4. **Tenants Not Found**
   - Error: "Could not retrieve Tenant A/B theme CSS"
   - Solution: Create test tenants via API or database

## Expected Test Coverage

### Security Tests
- ✅ 7 Security fixes implemented
- ✅ 12 Security test scripts created
- ✅ All security aspects covered

### Tenant Isolation Tests
- ✅ Database isolation (4 tests)
- ✅ API isolation (3 tests)
- ✅ Theme/CSS isolation (5 tests)
- ✅ Web/UI isolation (2 tests)
- ✅ Total: 14 tenant isolation tests

## Manual Verification

Some tests verify code structure. For comprehensive testing:

1. **Create Test Tenants**
   - Tenant A: `tenant-a.test` with red theme (#FF0000)
   - Tenant B: `tenant-b.test` with blue theme (#0000FF)

2. **Create Test Users**
   - `user-a1@tenant-a.test` / `TestPass123!`
   - `user-a2@tenant-a.test` / `TestPass123!`
   - `user-b1@tenant-b.test` / `TestPass123!`
   - `user-b2@tenant-b.test` / `TestPass123!`

3. **Verify Theme Isolation**
   - Access `http://localhost:8100/tenants/tenant-a/theme.css` → should contain #FF0000
   - Access `http://localhost:8100/tenants/tenant-b/theme.css` → should contain #0000FF
   - Verify no color leakage between tenants

4. **Verify API Isolation**
   - Login as Tenant A user
   - Call `/api/auth/me` → should return Tenant A info
   - Verify cannot access Tenant B data

## Reports

All test reports are generated in the `docs/` folder:

- **JSON Reports**: Machine-readable format for automation
- **HTML Reports**: Human-readable format with summary statistics

Open HTML reports in a browser for detailed test results.
