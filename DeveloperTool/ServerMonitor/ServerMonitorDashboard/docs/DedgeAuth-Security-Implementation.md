# DedgeAuth Security Implementation Guide

This document describes how to properly implement app-specific authorization in ServerMonitorDashboard using the DedgeAuth authentication system.

## Environment Details

| Resource | URL/Value |
|----------|-----------|
| **DedgeAuth API** | `http://localhost:8100` |
| **DedgeAuth Login Page** | `http://localhost:8100/login.html` |
| **ServerMonitorDashboard** | `http://localhost:8998` |
| **GenericLogHandler** | `http://localhost:52421` |

### Test Users

| User | Password | Tenant | Has ServerMonitorDashboard Access |
|------|----------|--------|-----------------------------------|
| `test.service@Dedge.no` | `TestPass123!` | Dedge.no | ✅ Yes (Admin) |
| `test.service@dedge.no` | `TestPass123!` | dedge.no | ❌ No (tenant has no apps) |

Use the `dedge.no` user to verify that unauthorized access is blocked after implementing the fix.

## Problem Statement

ServerMonitorDashboard currently validates JWT tokens but does **not** enforce app-specific permissions. This means:

- Any authenticated DedgeAuth user can access the dashboard
- Users from tenants without `ServerMonitorDashboard` permissions can still access via direct URL
- The `appPermissions` JWT claim is not being checked

### Root Cause

The current implementation uses `AddDedgeAuth()` which sets up:
- JWT token validation (issuer, audience, signature)
- Session validation middleware
- Redirect to login for unauthenticated users

However, it does **not** enforce that the user has permission for the specific app (`ServerMonitorDashboard`).

## Solution Options

### Option 1: Add `[RequireAppPermission]` Attribute (Recommended)

Add the `[RequireAppPermission]` attribute to controllers that require app-specific access.

#### Step 1: Update Controllers

Add to all controllers that require authentication:

```csharp
using DedgeAuth.Client.Authorization;
using Microsoft.AspNetCore.Authorization;

[ApiController]
[Route("api/[controller]")]
[Authorize]
[RequireAppPermission(AppRoles.ReadOnly, AppRoles.User, AppRoles.Admin)]
public class ServersController : ControllerBase
{
    // ...
}
```

#### Step 2: Available Roles

The `AppRoles` class provides standard roles:

| Role | Description |
|------|-------------|
| `AppRoles.Admin` | Full access - can configure, modify settings |
| `AppRoles.PowerUser` | Extended access - can run scripts, modify alerts |
| `AppRoles.User` | Standard access - can view and interact |
| `AppRoles.ReadOnly` | View-only access |
| `AppRoles.Operator` | ServerMonitor-specific: can operate but not configure |
| `AppRoles.Viewer` | ServerMonitor-specific: view-only |

#### Step 3: Role Hierarchy

The authorization handler respects role hierarchy:
- `Admin` includes all lower roles
- `PowerUser` includes `User`, `Viewer`, `ReadOnly`
- `User` includes `ReadOnly`

### Option 2: Global Fallback Policy

Add a global authorization policy that requires app permission for all authenticated requests.

#### Step 1: Update Program.cs

Add after `builder.Services.AddDedgeAuth()`:

```csharp
// Add global app permission requirement
builder.Services.AddAuthorization(options =>
{
    options.FallbackPolicy = new AuthorizationPolicyBuilder()
        .RequireAuthenticatedUser()
        .AddRequirements(new AppRoleRequirement(new[] { 
            AppRoles.ReadOnly, AppRoles.User, AppRoles.PowerUser, AppRoles.Admin 
        }))
        .Build();
});
```

#### Step 2: Add Required Using

```csharp
using DedgeAuth.Client.Authorization;
```

### Option 3: Middleware-Based Check (Alternative)

Add app permission checking directly in the authentication middleware.

#### Update Program.cs

Add after the session validation middleware:

```csharp
// App permission check middleware
app.Use(async (context, next) =>
{
    var path = context.Request.Path.Value?.ToLower() ?? "";
    var isApiOrSwagger = path.StartsWith("/api/") || path.StartsWith("/swagger") || path == "/health";
    var isStaticFile = path.Contains('.') && !path.EndsWith(".html");
    
    // Skip for API, swagger, health, and non-HTML static files
    if (isApiOrSwagger || isStaticFile)
    {
        await next();
        return;
    }
    
    // Check if user is authenticated
    if (context.User.Identity?.IsAuthenticated == true)
    {
        var appId = app.Configuration["DedgeAuth:AppId"];
        var appPermissionsClaim = context.User.FindFirst("appPermissions")?.Value;
        
        if (!string.IsNullOrEmpty(appPermissionsClaim))
        {
            try
            {
                var permissions = System.Text.Json.JsonSerializer
                    .Deserialize<Dictionary<string, string>>(appPermissionsClaim);
                
                if (permissions == null || !permissions.ContainsKey(appId))
                {
                    // User doesn't have permission for this app
                    context.Response.StatusCode = 403;
                    await context.Response.WriteAsync("Access denied. You do not have permission for this application.");
                    return;
                }
            }
            catch
            {
                // Invalid permissions claim - deny access
                context.Response.StatusCode = 403;
                await context.Response.WriteAsync("Access denied. Invalid permissions.");
                return;
            }
        }
        else
        {
            // No app permissions at all - deny access
            context.Response.StatusCode = 403;
            await context.Response.WriteAsync("Access denied. No application permissions assigned.");
            return;
        }
    }
    
    await next();
});
```

## Implementation Checklist

- [ ] Choose implementation option (1, 2, or 3)
- [ ] Add required using statements
- [ ] Apply attributes or modify Program.cs
- [ ] Test with user who has app permission (should work)
- [ ] Test with user who lacks app permission (should be denied)
- [ ] Test direct URL access from different tenant (should be denied)
- [ ] Update API endpoints to return 403 for unauthorized users

## Configuration Reference

### appsettings.json

Ensure the `AppId` is correctly configured:

```json
{
  "DedgeAuth": {
    "Enabled": true,
    "AuthServerUrl": "http://localhost:8100",
    "JwtSecret": "<shared-secret>",
    "JwtIssuer": "DedgeAuth",
    "JwtAudience": "FKApps",
    "AppId": "ServerMonitorDashboard"
  }
}
```

### JWT Claims Used

| Claim | Description |
|-------|-------------|
| `appPermissions` | JSON object: `{"AppId": "Role", ...}` |
| `globalAccessLevel` | Numeric level: 0=Guest, 1=User, 2=PowerUser, 3=Admin |
| `tenant` | JSON object with tenant info |

## Testing

### Test Case 1: Authorized User

1. Log in as user with `ServerMonitorDashboard` permission
2. Access dashboard directly
3. **Expected**: Dashboard loads normally

### Test Case 2: Unauthorized User (Different Tenant)

1. Log in as user from tenant without ServerMonitorDashboard
2. Navigate to dashboard URL directly: `http://localhost:8998/`
3. **Expected**: "Access denied" or redirect to login

### Test Case 3: Authenticated but No App Permission

1. Log in as user with DedgeAuth access but no ServerMonitorDashboard permission
2. Access dashboard directly
3. **Expected**: 403 Forbidden or "Access denied" message

## Related Documentation

- [DedgeAuth Client Integration](../../../DedgeAuth/docs/integration/client-integration.md)
- [Authentication Flow](../../../DedgeAuth/docs/integration/authentication-flow.md)
- [API Reference](../../../DedgeAuth/docs/integration/api-reference.md)

---

*Created: 2026-02-03*
*Security Issue: Tenant isolation vulnerability - users without app permissions could access via direct URL*
