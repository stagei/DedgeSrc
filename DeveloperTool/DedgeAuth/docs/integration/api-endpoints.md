# DedgeAuth Proxy API Endpoints

Endpoints registered by `MapDedgeAuthProxy()`. These are served by the consumer app (not the DedgeAuth server) and proxy user information from JWT claims and DedgeAuth API calls.

## GET /api/DedgeAuth/me

Returns current user information parsed from JWT claims.

**Authentication:** Anonymous (returns `authenticated: false` when not logged in)

### Response (authenticated)

```json
{
  "authenticated": true,
  "user": {
    "id": "550e8400-e29b-41d4-a716-446655440000",
    "email": "user@example.com",
    "name": "John Doe",
    "globalAccessLevel": "2",
    "globalAccessLevelName": "User"
  },
  "appPermissions": {
    "GenericLogHandler": "Admin",
    "DocView": "User",
    "ServerMonitorDashboard": "PowerUser"
  },
  "currentAppId": "GenericLogHandler",
  "currentAppRole": "Admin",
  "tenant": {
    "name": "Dedge",
    "domain": "Dedge"
  },
  "applications": [
    { "appId": "GenericLogHandler", "url": "http://dedge-server/GenericLogHandler", "isCurrent": true },
    { "appId": "DocView", "url": "http://dedge-server/DocView", "isCurrent": false },
    { "appId": "ServerMonitorDashboard", "url": "http://dedge-server/ServerMonitorDashboard", "isCurrent": false }
  ],
  "DedgeAuthUrl": "http://dedge-server/DedgeAuth"
}
```

### Response (not authenticated)

```json
{
  "authenticated": false
}
```

### Fields

| Field | Type | Description |
|-------|------|-------------|
| `authenticated` | bool | Whether the user is logged in |
| `user.id` | string | User ID (GUID) |
| `user.email` | string | User email address |
| `user.name` | string | Display name |
| `user.globalAccessLevel` | string | Numeric level: 0=None, 1=ReadOnly, 2=User, 3=Admin |
| `user.globalAccessLevelName` | string | Human-readable level name |
| `appPermissions` | object | Map of appId to role name |
| `currentAppId` | string | This app's AppId from configuration |
| `currentAppRole` | string? | User's role in this specific app (null if none) |
| `tenant.name` | string? | Tenant display name |
| `tenant.domain` | string? | Tenant domain identifier |
| `applications` | array | Apps from tenant routing with URLs |
| `applications[].isCurrent` | bool | True if this is the current app |
| `DedgeAuthUrl` | string | DedgeAuth server URL for linking to portal/admin |

## POST /api/DedgeAuth/logout

Revokes the user's session by calling DedgeAuth's logout endpoint.

**Authentication:** Required (`[Authorize]`)

### Request

No body required. Bearer token is read from the `Authorization` header.

### Response

```json
{
  "success": true,
  "redirectUrl": "http://dedge-server/DedgeAuth/login.html"
}
```

### Fields

| Field | Type | Description |
|-------|------|-------------|
| `success` | bool | Always true (best-effort logout) |
| `redirectUrl` | string | URL to redirect the user to after logout |

### Behavior

1. Reads Bearer token from `Authorization` header
2. Calls `POST {AuthServerUrl}/api/auth/logout` with the token
3. Returns redirect URL to DedgeAuth login page
4. If DedgeAuth is unreachable, still returns success (best-effort)

## GET /api/DedgeAuth/ui/{path}

Proxies UI asset requests to the DedgeAuth server. Whitelisted assets only, cached for 1 hour.

**Authentication:** Anonymous

### Whitelisted Assets

| Path | Content Type |
|---|---|
| `api/DedgeAuth/ui/common.css` | `text/css` |
| `api/DedgeAuth/ui/user.css` | `text/css` |
| `api/DedgeAuth/ui/user.js` | `application/javascript` |
| `api/DedgeAuth/ui/theme.js` | `application/javascript` |

Returns 404 for non-whitelisted paths. Returns 502 if the DedgeAuth server is unreachable.

## DedgeAuth Server Endpoints (used by middleware)

These endpoints are on the DedgeAuth API server, called by the DedgeAuth.Client middleware — not directly by consumer app code.

### POST /api/auth/exchange

Exchanges a short-lived auth code for a JWT token (server-to-server call from `DedgeAuthTokenExtractionMiddleware`).

### GET /api/auth/validate

Validates the current session token (called by `DedgeAuthSessionValidationMiddleware`, cached 30s).

### POST /api/visits/record

Records a user visit (fire-and-forget from `DedgeAuthSessionValidationMiddleware` on cache miss).

```json
{
  "appId": "GenericLogHandler",
  "path": "/index.html",
  "ipAddress": "10.0.0.1",
  "userAgent": "Mozilla/5.0..."
}
```

### GET /api/visits/my

Returns the current user's own visit history (any authenticated user).

### GET /api/visits/latest?count=20

Returns the latest visits across all users (GlobalAdmin only).

### GET /api/visits/user/{userId}?page=0&pageSize=50

Returns paginated visit history for a specific user (GlobalAdmin only).

### GET /api/visits/stats

Returns per-app visit counts and unique users for last 24h and 7d (GlobalAdmin only).

## Route Prefix

Default prefix is `/api/DedgeAuth`. Configurable via `DedgeAuthOptions.ProxyRoutePrefix`.

If changed to `/api/auth-proxy`, endpoints become:
- `GET /api/auth-proxy/me`
- `POST /api/auth-proxy/logout`
- `GET /api/auth-proxy/ui/{path}`

---

*Last updated: 2026-02-18*
