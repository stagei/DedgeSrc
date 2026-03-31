# DedgeAuth Configuration Reference

All properties in the `DedgeAuth` section of `appsettings.json`, mapped to `DedgeAuthOptions`.

## Configuration Properties

| Property | Type | Default | Required | Description |
|----------|------|---------|----------|-------------|
| `Enabled` | bool | `true` | Yes | Master switch. When false, standalone mode — all requests are auto-allowed (see below). |
| `AuthServerUrl` | string | `"http://localhost/DedgeAuth"` | Yes | DedgeAuth API base URL (must be `http://localhost/DedgeAuth` — see note below) |
| `JwtSecret` | string | `""` | Yes | Base64-encoded shared JWT signing secret (must match DedgeAuth server) |
| `JwtIssuer` | string | `"DedgeAuth"` | Yes | JWT issuer (must match DedgeAuth server) |
| `JwtAudience` | string | `"FKApps"` | Yes | JWT audience (must match DedgeAuth server) |
| `AppId` | string | `""` | Yes | Your app's registered ID in DedgeAuth |
| `AccessTokenCookieName` | string? | `null` | No | Cookie name for storing access token (optional, for cookie-based auth) |
| `LoginPath` | string | `"/login"` | No | Fallback login path |
| `SessionValidationCacheTtlSeconds` | int | `30` | No | Cache duration for session validation results (seconds) |
| `ProxyRoutePrefix` | string | `"/api/DedgeAuth"` | No | Route prefix for proxy endpoints (/me and /logout) |
| `SkipPathPrefixes` | string[] | `["/api/", "/scalar", "/health"]` | No | Paths that skip redirect and session validation |
| `GlobalLevelToAppRole` | Dictionary<int,string> | `{}` | No | Maps global access level to app role name |

## AuthServerUrl

**Always set to `http://localhost/DedgeAuth`** — never use a server-specific hostname. The DedgeAuth.Client middleware calls the DedgeAuth API over localhost (server-to-server), and browser-facing URLs (login redirects, asset URLs shown to the user) are derived dynamically from the incoming HTTP request by `DedgeAuthOptions.GetClientFacingAuthUrl()`.

This makes the configuration fully portable across servers — no `appsettings.json` changes are needed when moving to a different environment.

## Minimal Configuration

```json
{
  "DedgeAuth": {
    "Enabled": true,
    "AuthServerUrl": "http://localhost/DedgeAuth",
    "JwtSecret": "your-shared-secret-here",
    "JwtIssuer": "DedgeAuth",
    "JwtAudience": "FKApps",
    "AppId": "YourAppId"
  }
}
```

## Full Configuration

```json
{
  "DedgeAuth": {
    "Enabled": true,
    "AuthServerUrl": "http://localhost/DedgeAuth",
    "JwtSecret": "your-shared-secret-here",
    "JwtIssuer": "DedgeAuth",
    "JwtAudience": "FKApps",
    "AppId": "YourAppId",
    "SessionValidationCacheTtlSeconds": 30,
    "ProxyRoutePrefix": "/api/DedgeAuth",
    "SkipPathPrefixes": ["/api/", "/scalar", "/health"],
    "GlobalLevelToAppRole": {
      "0": "ReadOnly",
      "1": "User",
      "2": "PowerUser",
      "3": "Admin"
    }
  }
}
```

## GlobalLevelToAppRole

Maps global access level integers to app-specific role names. When a user has no explicit app permission but has a global access level, this mapping provides a fallback role.

Default is empty `{}` — no fallback, users must have explicit app permissions.

Example mapping:

```json
"GlobalLevelToAppRole": {
  "0": "ReadOnly",
  "1": "User",
  "2": "PowerUser",
  "3": "Admin"
}
```

## SkipPathPrefixes

Paths matching any prefix in this array will NOT trigger:
- Redirect to DedgeAuth login (unauthenticated users can access these paths)
- Session validation with DedgeAuth server

Default: `["/api/", "/scalar", "/health"]`

### Default prefixes explained

| Prefix | Why skipped |
|--------|------------|
| `/api/` | API endpoints handle their own auth via `[Authorize]` / `[RequireAppPermission]` attributes. The DedgeAuth proxy itself lives under `/api/DedgeAuth/` and must be accessible for login flow. |
| `/scalar` | Scalar API documentation UI (`/scalar/v1`). Must load without auth to display the docs page. |
| `/health` | Health check endpoint for monitoring and load balancers. |

### Common additions

Add custom prefixes if your app has paths that should be accessible without authentication:

```json
"SkipPathPrefixes": ["/api/", "/scalar", "/openapi", "/health", "/public/"]
```

> **OpenAPI / Scalar users:** If your app uses `Microsoft.AspNetCore.OpenApi` with `MapOpenApi()`, the OpenAPI JSON spec is served at `/openapi/v1.json`. Add `"/openapi"` to `SkipPathPrefixes` so the Scalar UI can fetch the spec document without triggering an auth redirect. Without this, the Scalar page loads (since `/scalar` is skipped) but fails to fetch the API spec for unauthenticated users.

## Standalone Mode (Enabled = false)

When `Enabled` is `false`, DedgeAuth enters **standalone mode** — the app works exactly as if DedgeAuth was never added. All requests are automatically allowed with no authentication required. This is useful as a fallback if DedgeAuth is causing issues, or during initial development before DedgeAuth is set up.

Specifically:
- `AddDedgeAuth()` registers minimal auth and authorization services (so `[Authorize]` does not throw)
- The `AppRoleAuthorizationHandler` auto-succeeds all authorization checks
- The default/fallback authorization policy is set to `RequireAssertion(_ => true)` — all requests pass
- `UseDedgeAuth()` only calls `UseAuthentication()` and `UseAuthorization()`
- No token extraction, redirect, or session validation middleware runs
- `MapDedgeAuthProxy()` endpoints are still registered but return `authenticated: false` for `/me`

---

*Last updated: 2026-02-18*
