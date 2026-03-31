# DedgeAuth Integration Guide (V2)

Instructions for integrating any .NET web application with DedgeAuth using the ready-to-use client components.

## Key Concepts

- **Server-agnostic config:** `AuthServerUrl` is always `http://localhost/DedgeAuth` — browser-facing URLs are derived dynamically from the HTTP request. No config changes needed when moving between servers.
- **Standalone mode:** Set `DedgeAuth:Enabled` to `false` and the app works exactly as before DedgeAuth was added — all requests are auto-allowed, no authentication required. Useful as a fallback if DedgeAuth is causing issues.

## Quick-Start Checklist

1. Add project reference to `DedgeAuth.Client`
2. Add `DedgeAuth` section to `appsettings.json` (use `"AuthServerUrl": "http://localhost/DedgeAuth"`)
3. Call `AddDedgeAuth()` and `UseDedgeAuth()` in `Program.cs`
4. Call `MapDedgeAuthProxy()` for user info, logout, and UI asset proxy endpoints
5. Reference DedgeAuth UI assets (JS/CSS) in HTML files using **relative paths** (no leading `/`)
6. Ensure **all** HTML asset references (including your app's own CSS/JS) use relative paths for IIS virtual app compatibility
7. Add `<div id="DedgeAuthUserMenu"></div>` to your page header
8. Register your app in DedgeAuth (IIS-DeployApp deploy template DedgeAuth block — recommended; or admin dashboard, API, or seeder)

## Documents

| Document | Purpose |
|----------|---------|
| [Setup Guide](setup-guide.md) | Step-by-step integration from scratch |
| [Configuration Reference](configuration-reference.md) | All DedgeAuthOptions properties with defaults |
| [API Endpoints](api-endpoints.md) | JSON schemas for /api/DedgeAuth/me, /logout, visits, and UI proxy |
| [Frontend Assets](frontend-assets.md) | How to reference JS/CSS from DedgeAuth API |
| [CSS Fallback Plan](css-fallback-plan.md) | Tenant override vs DedgeAuth default fallback when theme is empty or unreachable |
| [Search Dialog Pattern](search-dialog-pattern.md) | Modal and search-history dialog pattern (from GenericLogHandler) |
| [Publish and Deploy Guide](publish-and-deploy-guide.md) | Publish profiles, IIS-DeployApp, deploy templates |
| [Migration from V1](migration-from-v1.md) | Migrate from manual integration to V2 components |

## Architecture

```
Consumer App (Program.cs)
  │
  ├── builder.Services.AddDedgeAuth(config)    ← JWT + services
  ├── app.UseDedgeAuth()                       ← all middleware
  └── app.MapDedgeAuthProxy()                  ← /me + /logout
         │
         ▼
DedgeAuth.Client Library
  ├── TokenExtractionMiddleware   ← ?code= exchange or ?token= → cookie → Authorization header
  ├── SessionValidationMiddleware ← validates with DedgeAuth API, records user visits
  ├── RedirectMiddleware          ← unauthenticated → login page
  └── DedgeAuthEndpoints             ← /api/DedgeAuth/me, /api/DedgeAuth/logout, /api/DedgeAuth/ui/{path}
         │
         ▼
DedgeAuth API Server (dedge-server)
  ├── /api/auth/validate          ← session validation
  ├── /api/auth/logout            ← token revocation
  └── /api/ui/*                   ← JS, CSS, theme assets
```

## Minimal Program.cs Example

```csharp
using DedgeAuth.Client.Extensions;
using DedgeAuth.Client.Endpoints;

var builder = WebApplication.CreateBuilder(args);
builder.Services.AddDedgeAuth(builder.Configuration);
builder.Services.AddControllers();

var app = builder.Build();

// UseRouting() is implicit in .NET 6+ minimal hosting
app.UseDedgeAuth();         // token/code extraction + auth + session validation + visit tracking + redirect
app.UseDefaultFiles();
app.UseStaticFiles();
app.MapControllers();
app.MapDedgeAuthProxy();    // /api/DedgeAuth/me, /api/DedgeAuth/logout, and /api/DedgeAuth/ui/{path} proxy

app.Run();
```

## DedgeAuth.Client Source

The library source is at `C:\opt\src\DedgeAuth\src\DedgeAuth.Client\`:

- `Options/DedgeAuthOptions.cs` — all configuration properties
- `Extensions/DedgeAuthExtensions.cs` — `AddDedgeAuth()` service registration
- `Extensions/DedgeAuthAppExtensions.cs` — `UseDedgeAuth()` middleware pipeline
- `Endpoints/DedgeAuthEndpoints.cs` — `MapDedgeAuthProxy()` minimal API endpoints
- `Middleware/` — token extraction, redirect, session validation middleware
- `Authorization/` — `[RequireAppPermission]` attribute and handlers

---

*Last updated: 2026-02-18*
