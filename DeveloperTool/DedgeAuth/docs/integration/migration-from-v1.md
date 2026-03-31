# Migration from V1 (Manual Integration) to V2

Instructions for migrating existing apps from the manual DedgeAuth integration pattern to the V2 ready-to-use components.

## Overview

V1 required ~800-1,800 lines of boilerplate per consumer app:
- Inline middleware in Program.cs (~120-140 lines)
- DedgeAuthController.cs (~177 lines)
- Local copies of DedgeAuth-user.js, DedgeAuth-user.css, DedgeAuth-common.css (~600-1,300 lines)

V2 replaces all of this with 3 lines in Program.cs and URL references to DedgeAuth API assets.

## Step 1: Delete Boilerplate Files

Delete these files from your project (they are now provided by DedgeAuth.Client or served from DedgeAuth API):

```
Controllers/DedgeAuthController.cs          ← replaced by MapDedgeAuthProxy()
wwwroot/js/DedgeAuth-user.js               ← served from DedgeAuth API /api/ui/user.js
wwwroot/js/DedgeAuth-user.js               ← served from DedgeAuth API /api/ui/user.js
wwwroot/css/DedgeAuth-user.css             ← served from DedgeAuth API /api/ui/user.css
wwwroot/css/DedgeAuth-user.css             ← served from DedgeAuth API /api/ui/user.css
wwwroot/css/DedgeAuth-common.css           ← served from DedgeAuth API /api/ui/common.css
wwwroot/css/DedgeAuth-common.css           ← served from DedgeAuth API /api/ui/common.css
```

Do NOT delete app-specific files like `role-permissions.js` — those contain custom logic.

## Step 2: Update Program.cs

### Before (V1)

```csharp
using DedgeAuth.Client.Extensions;

var builder = WebApplication.CreateBuilder(args);
builder.Services.AddDedgeAuth(builder.Configuration, "DedgeAuth");
builder.Services.AddHttpClient();

var app = builder.Build();

var DedgeAuthEnabled = builder.Configuration.GetValue<bool>("DedgeAuth:Enabled", false);
var DedgeAuthUrl = builder.Configuration["DedgeAuth:AuthServerUrl"] ?? "http://localhost:8100";

app.UseRouting();

if (DedgeAuthEnabled)
{
    app.Use(async (context, next) =>
    {
        var token = context.Request.Query["token"].FirstOrDefault();
        if (!string.IsNullOrEmpty(token))
        {
            context.Request.Headers["Authorization"] = $"Bearer {token}";
        }
        await next();
    });
}

app.UseAuthentication();
app.UseAuthorization();

if (DedgeAuthEnabled)
{
    var sessionCache = new ConcurrentDictionary<string, DateTime>();
    // ... 70+ lines of session validation and redirect middleware ...
}

app.UseDefaultFiles();
app.UseStaticFiles();
app.MapControllers();
app.Run();
```

### After (V2)

```csharp
using DedgeAuth.Client.Extensions;
using DedgeAuth.Client.Endpoints;

var builder = WebApplication.CreateBuilder(args);
builder.Services.AddDedgeAuth(builder.Configuration);
builder.Services.AddControllers();

var app = builder.Build();

app.UseRouting();
app.UseDedgeAuth();
app.UseDefaultFiles();
app.UseStaticFiles();
app.MapControllers();
app.MapDedgeAuthProxy();
app.Run();
```

### Key Changes

1. Remove `using System.Collections.Concurrent;` and other middleware-related usings
2. Remove `builder.Services.AddHttpClient();` — `AddDedgeAuth()` registers it
3. Remove the `DedgeAuthEnabled` / `DedgeAuthUrl` local variables — handled by middleware
4. Remove ALL inline `app.Use(async (context, next) => { ... })` blocks for token extraction, redirect, and session validation
5. Remove `app.UseAuthentication()` and `app.UseAuthorization()` — `UseDedgeAuth()` calls them
6. Add `using DedgeAuth.Client.Endpoints;`
7. Add `app.UseDedgeAuth();` (after `app.UseRouting()` if you call it explicitly; in .NET 6+ minimal hosting, `UseRouting()` is implicit)
8. Add `app.MapDedgeAuthProxy();` after `app.MapControllers();`
9. Keep any app-specific authorization policies — those are not replaced

## Step 3: Update HTML Files

### Before (V1 — local file references)

```html
<link rel="stylesheet" href="/css/DedgeAuth-common.css">
<style id="DedgeAuth-tenant-css"></style>
<link rel="stylesheet" href="/css/DedgeAuth-user.css">
<!-- ... -->
<script src="/js/DedgeAuth-user.js"></script>
```

### After (V2 — relative proxy paths)

```html
<link rel="stylesheet" href="api/DedgeAuth/ui/common.css">
<style id="DedgeAuth-tenant-css"></style>
<link rel="stylesheet" href="api/DedgeAuth/ui/user.css">
<!-- ... -->
<script src="api/DedgeAuth/ui/user.js"></script>
```

Assets are served through the local proxy registered by `MapDedgeAuthProxy()`. The proxy fetches from the `AuthServerUrl` configured in `appsettings.json` and caches for 1 hour.

### HTML Search-and-Replace Patterns

Apply these replacements across all HTML files:

| Find | Replace |
|------|---------|
| `href="/css/DedgeAuth-common.css"` | `href="api/DedgeAuth/ui/common.css"` |
| `href="/css/DedgeAuth-common.css"` | `href="api/DedgeAuth/ui/common.css"` |
| `href="/css/DedgeAuth-user.css"` | `href="api/DedgeAuth/ui/user.css"` |
| `href="/css/DedgeAuth-user.css"` | `href="api/DedgeAuth/ui/user.css"` |
| `src="/js/DedgeAuth-user.js"` | `src="api/DedgeAuth/ui/user.js"` |
| `src="/js/DedgeAuth-user.js"` | `src="api/DedgeAuth/ui/user.js"` |
| `href="http://.../DedgeAuth/api/ui/common.css"` | `href="api/DedgeAuth/ui/common.css"` |
| `href="http://.../DedgeAuth/api/ui/user.css"` | `href="api/DedgeAuth/ui/user.css"` |
| `src="http://.../DedgeAuth/api/ui/user.js"` | `src="api/DedgeAuth/ui/user.js"` |

**CRITICAL:** Use relative paths (no leading `/`) so URLs resolve correctly under IIS virtual application paths (e.g. `/GenericLogHandler`).

Keep:
- `<div id="DedgeAuthUserMenu"></div>` — unchanged
- `<style id="DedgeAuth-tenant-css"></style>` — unchanged

### Also fix your app's own asset paths

While migrating DedgeAuth assets, also convert your app's own CSS/JS references from absolute to relative paths. This is required for IIS virtual application compatibility:

| Find (absolute) | Replace (relative) |
|-----------------|-------------------|
| `href="/css/app.css"` | `href="css/app.css"` |
| `src="/js/app.js"` | `src="js/app.js"` |
| `href="/css/dashboard.css"` | `href="css/dashboard.css"` |
| `src="/js/api.js"` | `src="js/api.js"` |

This applies to ALL `href` and `src` attributes in your HTML. Any path starting with `/` resolves from the site root, not the virtual application root, and will 404 when the app is deployed under a sub-path.

## Step 4: Update appsettings.json (if needed)

No changes required if you already have the standard `DedgeAuth` section. New optional properties:

```json
{
  "DedgeAuth": {
    "SessionValidationCacheTtlSeconds": 30,
    "ProxyRoutePrefix": "/api/DedgeAuth",
    "SkipPathPrefixes": ["/api/", "/scalar", "/health"]
  }
}
```

These have sensible defaults and do not need to be specified unless you want to override them.

## Step 5: Build and Verify

```bash
dotnet build --configuration Release
```

Verify:
- App compiles without errors
- `/api/DedgeAuth/me` returns user info when authenticated
- `/api/DedgeAuth/logout` revokes session and returns redirect URL
- User menu renders in the browser
- Unauthenticated users are redirected to DedgeAuth login
- Token from `?token=` query string is extracted correctly

## Checklist

- [ ] Deleted `DedgeAuthController.cs`
- [ ] Deleted local `DedgeAuth-user.js` / `DedgeAuth-user.js`
- [ ] Deleted local `DedgeAuth-user.css` / `DedgeAuth-user.css`
- [ ] Deleted local `DedgeAuth-common.css` / `DedgeAuth-common.css`
- [ ] Replaced inline middleware with `UseDedgeAuth()`
- [ ] Added `MapDedgeAuthProxy()` call
- [ ] Updated all HTML files to reference DedgeAuth API asset URLs (relative paths)
- [ ] Converted ALL HTML asset references to relative paths (no leading `/`)
- [ ] Kept app-specific files (role-permissions.js, custom policies, etc.)
- [ ] Build succeeds
- [ ] Manual testing passes

---

*Last updated: 2026-02-13*
