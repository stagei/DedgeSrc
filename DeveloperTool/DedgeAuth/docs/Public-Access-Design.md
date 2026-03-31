# Public Access for DedgeAuth Consumer Apps

**Author:** AI Design Document  
**Created:** 2026-03-09  
**Status:** Proposal  
**Related:** [IIS AllowAnonymousAccess](C:\opt\src\DedgePsh\DevTools\WebSites\IIS-DeployApp\docs\Public-Access-AllowAnonymousAccess.md)

---

## Problem Statement

Today, every DedgeAuth-integrated consumer app requires a registered user to access the UI. The middleware pipeline (`DedgeAuthRedirectMiddleware`) redirects all unauthenticated requests to the login page. There is no way to mark an app as "publicly accessible" — even read-only access requires a full login.

Some apps like **DocView** are primarily document viewers where public read access would be useful, while still preserving the option for authenticated users to get enhanced features (personalization, visit tracking, write operations).

---

## Current Architecture (Two Auth Layers)

### Layer 1: IIS (Windows Authentication)

| Setting | Effect |
|---------|--------|
| `AllowAnonymousAccess: false` (default) | Requires Windows domain credentials to reach the app |
| `AllowAnonymousAccess: true` | Bypasses Windows Auth; anyone can reach the app |

This is controlled per-app in the `.deploy.json` template and applied by `IIS-Handler` during Step 6b of deployment. It only governs the network/IIS layer — it has nothing to do with DedgeAuth.

### Layer 2: DedgeAuth (Application Authentication)

The DedgeAuth.Client middleware pipeline runs inside the ASP.NET Core app:

```
Request
  │
  ▼
DedgeAuthTokenExtractionMiddleware    ← extracts JWT from cookie/code/token
  │
  ▼
UseAuthentication()                ← validates JWT
  │
  ▼
UseAuthorization()                 ← evaluates policies
  │
  ▼
DedgeAuthSessionValidationMiddleware  ← validates session with DedgeAuth server
  │
  ▼
DedgeAuthRedirectMiddleware           ← redirects unauthenticated to login ◄── THIS BLOCKS PUBLIC ACCESS
  │
  ▼
Static files / Controllers
```

For public access, the redirect middleware must **not** redirect unauthenticated users to login.

### Current Workarounds

| Mechanism | Scope | Limitation |
|-----------|-------|------------|
| `DedgeAuth:Enabled = false` | Entire app | Disables ALL auth — no user menu, no visit tracking, no roles |
| `SkipPathPrefixes` | Path-based | Only skips specific URL prefixes; the SPA shell (`/`, `/index.html`) is still blocked |

Neither provides a "public with optional auth" mode.

---

## Proposed Solution: Public Access Mode

### New Concept: `AllowPublicAccess`

Add a per-app configuration that allows unauthenticated users to access the app while still supporting authenticated users who happen to be logged in.

### Behavior Matrix

| Scenario | Current | With `AllowPublicAccess` |
|----------|---------|--------------------------|
| Unauthenticated user visits app | → Redirect to login | → Serve the page (no redirect) |
| Authenticated user visits app | → Serve the page with user menu | → Serve the page with user menu |
| Unauthenticated user calls API | → Depends on `SkipPathPrefixes` | → Depends on controller attributes |
| Visit tracking | → Only authenticated users | → Only authenticated users |
| Tenant CSS / branding | → Injected by `DedgeAuth-user.js` | → Still injected (uses default tenant for anonymous) |
| User menu | → Shows user info + app switcher | → Shows "Sign in" link for anonymous, full menu for authenticated |

### Changes Required

#### 1. DedgeAuthOptions — New Property

```csharp
public class DedgeAuthOptions
{
    // ... existing properties ...

    /// <summary>
    /// When true, unauthenticated users can access the app without being redirected to login.
    /// Authenticated users still get full features (user menu, visit tracking, role-based access).
    /// </summary>
    public bool AllowPublicAccess { get; set; } = false;
}
```

Configuration in `appsettings.json`:

```json
{
  "DedgeAuth": {
    "Enabled": true,
    "AllowPublicAccess": true,
    "AuthServerUrl": "http://dedge-server/DedgeAuth",
    "AppId": "DocView"
  }
}
```

#### 2. DedgeAuthRedirectMiddleware — Skip Redirect

The redirect middleware currently redirects all unauthenticated requests (except `SkipPathPrefixes`). With `AllowPublicAccess = true`, it should **not redirect** — just pass through:

```csharp
// In DedgeAuthRedirectMiddleware.InvokeAsync:
if (_options.AllowPublicAccess)
{
    await _next(context);
    return;
}
// ... existing redirect logic ...
```

#### 3. DedgeAuthSessionValidationMiddleware — Skip for Anonymous

Session validation calls `GET /api/auth/validate` which requires a token. For anonymous users with `AllowPublicAccess`, the middleware should skip validation:

```csharp
// Already skips when user is not authenticated — no change needed
if (!context.User.Identity?.IsAuthenticated == true)
{
    await _next(context);
    return;
}
```

#### 4. DedgeAuth-user.js — Anonymous-Aware User Menu

The client-side `DedgeAuth-user.js` currently expects an authenticated user. For public access mode, it should:

- Attempt to fetch `/api/DedgeAuth/me` — if it returns 401, the user is anonymous
- For anonymous users: render a "Sign in" link instead of the full user menu
- Still load tenant CSS and branding (use a separate endpoint that doesn't require auth)
- Still inject favicon and logo from the default tenant

#### 5. Controller-Level Authorization (Per-Endpoint)

With `AllowPublicAccess`, the app shell is public but individual endpoints can still require authentication:

```csharp
// Public endpoint — anyone can read documents
[HttpGet("structure")]
public IActionResult GetStructure() { ... }

// Protected endpoint — only authenticated users
[Authorize]
[HttpPost("favorite")]
public IActionResult AddFavorite() { ... }

// Role-restricted endpoint — only admins
[RequireAppPermission(AppRoles.Admin)]
[HttpPost("refresh-cache")]
public IActionResult RefreshCache() { ... }
```

#### 6. Database — App Registration

Add an `allow_public_access` column to the `apps` table:

```sql
ALTER TABLE apps ADD COLUMN allow_public_access BOOLEAN NOT NULL DEFAULT false;
```

This allows the admin panel to control which apps support public access. The DedgeAuth server can expose this in the app metadata, and consumer apps can read it during startup (or it can be purely configuration-driven via `appsettings.json`).

---

## Access Level / Role Summary

With this change, the effective access hierarchy becomes:

| Level | Name | Requires Login | Capabilities |
|-------|------|:-:|---|
| — | **Public** (anonymous) | No | View public content; no user menu; no visit tracking |
| 0 | **ReadOnly** | Yes | View all content; user menu visible; visit tracking active |
| 1 | **User** | Yes | Read + basic write operations |
| 2 | **PowerUser** | Yes | User + advanced features |
| 3 | **Admin** | Yes | Full app administration |
| 5 | **TenantAdmin** | Yes | Cross-app tenant administration |

**Public** is not an access level in the database — it means "no user record exists." The distinction is handled entirely by the middleware and controller attributes.

---

## IIS + DedgeAuth Interaction

Both layers must be configured for full public access:

| IIS `AllowAnonymousAccess` | DedgeAuth `AllowPublicAccess` | Result |
|:-:|:-:|---|
| `false` | `false` | Windows Auth required, then DedgeAuth login required |
| `true` | `false` | No Windows Auth, but DedgeAuth login still required |
| `false` | `true` | Windows Auth blocks access before DedgeAuth is reached |
| `true` | `true` | Fully public — no login at any layer |

For apps like DocView to be publicly accessible, **both** flags must be `true`.

Deploy template example:

```json
{
  "SiteName": "DocView",
  "PhysicalPath": "$env:OptPath\\DedgeWinApps\\DocView",
  "AppType": "AspNetCore",
  "DotNetDll": "DocView.dll",
  "InstallSource": "WinApp",
  "InstallAppName": "DocView",
  "VirtualPath": "/DocView",
  "ParentSite": "Default Web Site",
  "AllowAnonymousAccess": true,
  "ApiPort": 8282,
  "DedgeAuth": {
    "AppId": "DocView",
    "BaseUrl": "http://$HOSTNAME$/DocView"
  }
}
```

And in the app's `appsettings.json`:

```json
{
  "DedgeAuth": {
    "Enabled": true,
    "AllowPublicAccess": true,
    "AuthServerUrl": "http://dedge-server/DedgeAuth",
    "AppId": "DocView"
  }
}
```

---

## DocView Example

DocView is a natural candidate for public access:

| Feature | Public Users | Authenticated Users |
|---------|:-:|:-:|
| Browse document tree | Yes | Yes |
| View document content | Yes | Yes |
| Search documents | Yes | Yes |
| See FK branding / tenant CSS | Yes | Yes |
| User menu with app switcher | No ("Sign in" link) | Yes |
| Visit tracking | No | Yes |
| Refresh cache | No | Yes (Admin only) |
| AI summary generation | No | Yes (requires API key) |

### Implementation Steps for DocView

1. Set `AllowPublicAccess: true` in `appsettings.json`
2. Set `AllowAnonymousAccess: true` in `DocView_WinApp.deploy.json`
3. Add `[Authorize]` to endpoints that should require login (e.g., `RefreshCache`, `GenerateSummary`)
4. Leave read-only endpoints without attributes (public by default)
5. Rebuild and redeploy

---

## Security Considerations

| Risk | Mitigation |
|------|------------|
| API abuse (scraping, DoS) | Rate limiting at IIS/reverse proxy level; existing Windows firewall rules |
| Sensitive documents exposed | DocView already serves from a controlled content directory; no user data exposed |
| Privilege escalation | Controller-level `[Authorize]` and `[RequireAppPermission]` still enforce role checks for protected actions |
| Session fixation | No session exists for anonymous users; JWT validation unchanged for authenticated users |
| Tenant data leakage | Default tenant branding is intentionally public (logo, CSS); no sensitive tenant data exposed |

---

## Apps Assessment

Which existing apps could benefit from public access:

| App | Public Access Candidate | Rationale |
|-----|:-:|---|
| **DocView** | Yes | Read-only document viewer; public access is natural |
| **AutoDoc** | Yes | Already a static site with no auth |
| **AutoDocJson** | Maybe | Documentation tool; read access could be public, editing protected |
| **GenericLogHandler** | No | Log data is internal/sensitive |
| **ServerMonitorDashboard** | No | Server metrics are internal/sensitive |
| **AgriNxt.GrainDryingDeduction** | Maybe | Pricing data may be useful publicly; calculations could be open |
| **DedgeAuth Admin** | No | User/app management must be protected |

---

## Implementation Phases

### Phase 1: DedgeAuth.Client Changes

- Add `AllowPublicAccess` to `DedgeAuthOptions`
- Modify `DedgeAuthRedirectMiddleware` to skip redirect when enabled
- Update `DedgeAuth-user.js` to handle anonymous users gracefully
- Add `allow_public_access` column to `apps` table (optional, for admin UI)

### Phase 2: DocView Pilot

- Enable `AllowPublicAccess` in DocView configuration
- Add `[Authorize]` to write/admin endpoints
- Set `AllowAnonymousAccess: true` in deploy template
- Test public and authenticated flows end-to-end

### Phase 3: Admin UI

- Show `AllowPublicAccess` toggle in DedgeAuth admin app management
- Display public/private status in app list

---

## Impact

- **DedgeAuth.Client**: Requires rebuild of ALL consumer apps (new option in `DedgeAuthOptions`)
- **DedgeAuth server**: Optional `apps` table column; `DedgeAuth-user.js` update
- **Consumer apps**: Opt-in per app via `appsettings.json`; no code changes unless endpoint-level auth is needed
- **IIS templates**: Opt-in per app via `AllowAnonymousAccess` in deploy template
