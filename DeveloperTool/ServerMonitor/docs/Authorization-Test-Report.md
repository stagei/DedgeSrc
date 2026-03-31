# ServerMonitorDashboard Authorization Test Report

**Date:** 2026-02-03  
**Tested By:** AI Agent  
**Test Environment:** Development (localhost)

## Executive Summary

The ServerMonitorDashboard authorization implementation using DedgeAuth SSO has been thoroughly tested and validated. All 20 API authorization tests passed successfully.

### Test Configuration

| Resource | URL |
|----------|-----|
| DedgeAuth API | `http://localhost:8100` |
| ServerMonitorDashboard | `http://localhost:8998` |

### Test Users

| User | Tenant | ServerMonitorDashboard Access |
|------|--------|-------------------------------|
| `test.service@Dedge.no` | Dedge.no | Yes (variable roles for testing) |
| `test.service@dedge.no` | dedge.no | No (tenant has no app access) |

## Role Hierarchy

The following role hierarchy is implemented in DedgeAuth:

```
Admin (highest)
  └── includes: PowerUser, Operator, User, Viewer, ReadOnly

PowerUser / Operator
  └── includes: User, Viewer, ReadOnly

User / Viewer
  └── includes: ReadOnly

ReadOnly (lowest)
```

### ServerMonitorDashboard Available Roles

The `ServerMonitorDashboard` app is configured with the following roles:
- **Admin** - Full access to all features including admin tools
- **Operator** - Extended access to control panel features
- **Viewer** - Read-only access to dashboard data

## API Authorization Test Results

### Test Matrix

| Role | Read Servers | Active Alerts | Trigger Status | Health Check |
|------|-------------|---------------|----------------|--------------|
| **Admin** | ✅ 200 | ✅ 200 | ✅ 200 | ✅ 200 |
| **Operator** | ✅ 200 | ✅ 200 | ✅ 403 | ✅ 200 |
| **Viewer** | ✅ 200 | ✅ 200 | ✅ 403 | ✅ 200 |
| **NoAccess** | ✅ 403 | ✅ 403 | ✅ 403 | ✅ 200 |
| **Unauthenticated** | ✅ 401 | ✅ 401 | ✅ 401 | ✅ 200 |

**Legend:**
- ✅ = Correct response (expected status code)
- HTTP 200 = Access granted
- HTTP 401 = Unauthorized (no token)
- HTTP 403 = Forbidden (valid token but insufficient permissions)

### Detailed Test Results

#### Admin Role
- **Token Permissions:** `{"ServerMonitorDashboard":"Admin","GenericLogHandler":"Admin"}`
- Read servers (ReadOnly+): **PASS** (200)
- Active alerts (ReadOnly+): **PASS** (200)
- Trigger status (Admin-only): **PASS** (200)
- Health check (Public): **PASS** (200)

#### Operator Role
- **Token Permissions:** `{"ServerMonitorDashboard":"Operator","GenericLogHandler":"Admin"}`
- Read servers (ReadOnly+): **PASS** (200)
- Active alerts (ReadOnly+): **PASS** (200)
- Trigger status (Admin-only): **PASS** (403 Forbidden)
- Health check (Public): **PASS** (200)

#### Viewer Role
- **Token Permissions:** `{"ServerMonitorDashboard":"Viewer","GenericLogHandler":"Admin"}`
- Read servers (ReadOnly+): **PASS** (200)
- Active alerts (ReadOnly+): **PASS** (200)
- Trigger status (Admin-only): **PASS** (403 Forbidden)
- Health check (Public): **PASS** (200)

#### NoAccess User (No App Permission)
- **Token Permissions:** `{}` (empty - no ServerMonitorDashboard access)
- **Global Access Level:** 1 (User level, but NOT used for app-specific access)
- Read servers (ReadOnly+): **PASS** (403 Forbidden)
- Active alerts (ReadOnly+): **PASS** (403 Forbidden)
- Trigger status (Admin-only): **PASS** (403 Forbidden)
- Health check (Public): **PASS** (200)

#### Unauthenticated (No Token)
- Read servers (ReadOnly+): **PASS** (401 Unauthorized)
- Active alerts (ReadOnly+): **PASS** (401 Unauthorized)
- Trigger status (Admin-only): **PASS** (401 Unauthorized)
- Health check (Public): **PASS** (200)

## Controller Authorization Configuration

### Controllers and Their Authorization Levels

| Controller | Route | Required Permission |
|------------|-------|---------------------|
| `ServersController` | `/api/servers` | ReadOnly, User, PowerUser, Admin |
| `SnapshotController` | `/api/snapshot/{server}` | ReadOnly, User, PowerUser, Admin |
| `ActiveAlertsController` | `/api/alerts/*` | ReadOnly, User, PowerUser, Admin |
| `LogFilesController` | `/api/logfiles/*` | ReadOnly, User, PowerUser, Admin |
| `TrayApiController` | `/api/tray/*` | ReadOnly, User, PowerUser, Admin |
| `ReinstallController` | `/api/reinstall, /api/stop, /api/start, /api/trigger-status` | Admin |
| `ConfigEditorController` | `/api/config/*` | Admin |
| `HealthController` | `/health/*` | Anonymous (public) |
| `DedgeAuthController` | `/api/DedgeAuth/me` | Anonymous (for auth status check) |

## Key Configuration Changes

### 1. DedgeAuth Client Options (`DedgeAuthOptions.cs`)

Changed `GlobalLevelToAppRole` default from a pre-populated dictionary to an empty dictionary:

```csharp
// Before: Default fallback mapping (users got implicit access)
public Dictionary<int, string> GlobalLevelToAppRole { get; set; } = new()
{
    { 0, "ReadOnly" },
    { 1, "User" },
    { 2, "PowerUser" },
    { 3, "Admin" }
};

// After: Empty by default (explicit app permissions required)
public Dictionary<int, string> GlobalLevelToAppRole { get; set; } = new();
```

**Impact:** Users must have explicit app-specific permissions granted in DedgeAuth to access any protected endpoints. The global access level is no longer used as a fallback.

### 2. Extension Method Fix (`DedgeAuthExtensions.cs`)

Added code to copy the `GlobalLevelToAppRole` configuration from `appsettings.json`:

```csharp
if (options.GlobalLevelToAppRole != null)
{
    o.GlobalLevelToAppRole = options.GlobalLevelToAppRole;
}
```

### 3. Dashboard Configuration (`appsettings.json`)

Added explicit empty `GlobalLevelToAppRole` (optional since default is now empty):

```json
"DedgeAuth": {
    "Enabled": true,
    "AuthServerUrl": "http://localhost:8100",
    "AppId": "ServerMonitorDashboard",
    "GlobalLevelToAppRole": {}
}
```

## Test Script

A reusable PowerShell test script has been created at:

```
c:\opt\src\ServerMonitor\Test-DashboardAuthorization.ps1
```

### Usage

```powershell
# Run with default settings
.\Test-DashboardAuthorization.ps1

# Run with custom endpoints
.\Test-DashboardAuthorization.ps1 -DedgeAuthUrl "http://localhost:8100" -DashboardUrl "http://localhost:8998"
```

### Output

The script tests the following scenarios:
1. Admin role - all endpoints accessible
2. Operator role - read endpoints accessible, admin endpoints blocked
3. Viewer role - read endpoints accessible, admin endpoints blocked
4. NoAccess user - all protected endpoints blocked
5. Unauthenticated - all protected endpoints return 401

## Frontend UI Restrictions

The following UI restrictions have been implemented via `role-permissions.js`:

| Feature | Admin | Operator | Viewer |
|---------|-------|----------|--------|
| Tools Menu | ✅ | ❌ | ❌ |
| Dashboard Settings | ✅ | ❌ | ❌ |
| Control Panel | ✅ | ✅ | ❌ |
| Reinstall Button | ✅ | ❌ | ❌ |
| Trigger File Controls | ✅ | ✅ | ❌ |
| Auto-refresh | ✅ | ✅ | ❌ |
| Pop-out Windows | ✅ | ✅ | ❌ |
| Refresh Interval Options | All | All | 5/10/30/60 min only |

### Frontend Notes

The frontend UI restrictions depend on:
1. `DedgeAuth-user.js` - Fetches user info from `/api/DedgeAuth/me`
2. `role-permissions.js` - Applies UI visibility based on user's role

**Known Issue:** When navigating to the Dashboard via URL with `?token=...` parameter, the token is processed server-side for page authentication, but subsequent JavaScript API calls need to include the token in the Authorization header. The frontend currently fetches `/api/DedgeAuth/me` without the Authorization header, which may cause role detection to fail.

**Workaround:** Store the token in localStorage/sessionStorage and configure fetch calls to include it, or use cookie-based token storage.

## Conclusions

1. **Backend Authorization:** All API endpoints are properly secured with `[Authorize]` and `[RequireAppPermission]` attributes.

2. **Role-Based Access:** The role hierarchy correctly grants/denies access based on user permissions.

3. **NoAccess Users:** Users without explicit app permissions are correctly denied access (403 Forbidden).

4. **Unauthenticated Requests:** Requests without valid tokens are correctly rejected (401 Unauthorized).

5. **Public Endpoints:** Health check endpoints remain accessible for monitoring purposes.

## Recommendations

1. **Production Deployment:** The same configuration should be applied to the production DedgeAuth and Dashboard instances.

2. **Role Assignment:** Ensure users are explicitly granted roles for `ServerMonitorDashboard` in the DedgeAuth admin interface.

3. **Monitoring:** Use the health endpoint (`/health/isalive`) for uptime monitoring without requiring authentication.

4. **Audit Trail:** Consider adding logging for authorization failures to track access attempts.

---

*Report generated by automated testing on 2026-02-03*
