# DedgeAuth V2 Setup Guide

Step-by-step instructions for integrating a .NET web application with DedgeAuth.

## Step 1: Add Project Reference

Add to your `.csproj`:

```xml
<ItemGroup>
  <ProjectReference Include="..\..\DedgeAuth\src\DedgeAuth.Client\DedgeAuth.Client.csproj" />
</ItemGroup>
```

Adjust the relative path to match your project's location relative to the DedgeAuth source.

## Step 2: Configure appsettings.json

Add the `DedgeAuth` section:

```json
{
  "DedgeAuth": {
    "Enabled": true,
    "AuthServerUrl": "http://localhost/DedgeAuth",
    "JwtSecret": "D3yK1/CuC08lHhYDZBFv8SYYXqX+ZGWZlyZRthGPyRDBdqI7G5ooX2TL8n5cd8TIlFjK2uuuk97ukVKynOX/WA==",
    "JwtIssuer": "DedgeAuth",
    "JwtAudience": "FKApps",
    "AppId": "YourAppId"
  }
}
```

> **Server-agnostic AuthServerUrl:** Always use `http://localhost/DedgeAuth` — never a server-specific hostname. The middleware calls DedgeAuth over localhost (server-to-server), and browser-facing URLs (login redirects, etc.) are derived dynamically from the HTTP request by `DedgeAuthOptions.GetClientFacingAuthUrl()`. This makes the config portable across all servers without changes.

Required properties: `Enabled`, `AuthServerUrl`, `JwtSecret`, `JwtIssuer`, `JwtAudience`, `AppId`.

See [Configuration Reference](configuration-reference.md) for all properties and defaults.

## Step 3: Configure Program.cs

Add these using statements:

```csharp
using DedgeAuth.Client.Extensions;
using DedgeAuth.Client.Endpoints;
```

Register services:

```csharp
builder.Services.AddDedgeAuth(builder.Configuration);
```

Add middleware and endpoints (order matters):

```csharp
app.UseDedgeAuth();         // handles token extraction, auth, session validation, redirect
app.UseDefaultFiles();
app.UseStaticFiles();
app.MapControllers();
app.MapDedgeAuthProxy();    // registers /api/DedgeAuth/me, /api/DedgeAuth/logout, and /api/DedgeAuth/ui/{path} proxy
```

> **Note:** `app.UseRouting()` is called implicitly by the ASP.NET Core 6+ minimal hosting model. You do NOT need to call it explicitly. If you use the older `Startup.cs` pattern (pre-.NET 6), add `app.UseRouting()` before `app.UseDedgeAuth()`.

### Important: Middleware Order

`UseDedgeAuth()` internally calls these in order:
1. `UseMiddleware<DedgeAuthTokenExtractionMiddleware>()` — extracts `?code=` (exchanges for JWT) or `?token=` from query string, reads cookies
2. `UseAuthentication()` — JWT validation
3. `UseAuthorization()` — policy evaluation
4. `UseMiddleware<DedgeAuthSessionValidationMiddleware>()` — validates session with DedgeAuth, records user visits
5. `UseMiddleware<DedgeAuthRedirectMiddleware>()` — redirects unauthenticated users

Do NOT call `UseAuthentication()` or `UseAuthorization()` separately — `UseDedgeAuth()` handles them.

### Standalone Mode (Enabled = false)

If `Enabled` is false in config, DedgeAuth enters **standalone mode** — the app works exactly as before DedgeAuth was added. All requests are auto-allowed: the `AppRoleAuthorizationHandler` auto-succeeds, and the default authorization policy is set to `RequireAssertion(_ => true)`. `UseDedgeAuth()` only calls `UseAuthentication()` and `UseAuthorization()` (no token extraction, redirect, or session validation). This is useful as a fallback if DedgeAuth is causing issues.

### IIS maxQueryString

After login, DedgeAuth redirects back to the consumer app with `?token=<jwt>` in the query string. IIS's default `maxQueryString` of 2048 bytes is too small for JWT tokens. The `IIS-Handler` module now **automatically patches `web.config`** to set `maxQueryString="8192"` for all AspNetCore apps during deployment — no manual configuration is needed.

## Step 4: Add DedgeAuth UI to HTML Pages

DedgeAuth assets are loaded through a **local proxy** provided by `MapDedgeAuthProxy()`. Do NOT hardcode server URLs and do NOT copy files locally.

> **CRITICAL — IIS Virtual Application Paths:** All FK web apps run as IIS virtual applications under a sub-path (e.g. `/GenericLogHandler`, `/DocView`). **ALL** asset references in HTML — both DedgeAuth assets and your app's own CSS/JS — **must use relative paths** (no leading `/`). If you use absolute paths like `/css/app.css`, the browser resolves them from the site root (`http://server/css/app.css`) instead of the virtual app root (`http://server/YourApp/css/app.css`), and they will 404 in production.

In the `<head>`:

```html
<!-- 1. Local App CSS (loaded first) — relative path, no leading / -->
<link rel="stylesheet" href="css/app.css">

<!-- 2. DedgeAuth Common CSS (enforces consistent theming) — via local proxy -->
<link rel="stylesheet" href="api/DedgeAuth/ui/common.css">

<!-- 3. Tenant-specific CSS (injected dynamically by user.js) -->
<style id="DedgeAuth-tenant-css"></style>

<!-- 4. DedgeAuth User menu styles (loaded last for proper cascade) — via local proxy -->
<link rel="stylesheet" href="api/DedgeAuth/ui/user.css">
```

In the page header area:

```html
<div id="DedgeAuthUserMenu"></div>
```

Before `</body>`:

```html
<!-- DedgeAuth user menu JS — via local proxy -->
<script src="api/DedgeAuth/ui/user.js"></script>

<!-- Your app's own JS — relative paths, no leading / -->
<script src="js/api.js"></script>
<script src="js/app.js"></script>
```

The proxy routes `api/DedgeAuth/ui/{asset}` to the DedgeAuth server configured in `AuthServerUrl`, with 1-hour caching. This ensures apps work on **any server** without changing HTML. See [Frontend Assets](frontend-assets.md) for details.

### Why relative paths matter

| Reference | Deployed at `/MyApp` | Resolves to |
|-----------|---------------------|-------------|
| `href="css/app.css"` | `http://server/MyApp/css/app.css` | Correct |
| `href="/css/app.css"` | `http://server/css/app.css` | **WRONG — 404** |
| `href="api/DedgeAuth/ui/common.css"` | `http://server/MyApp/api/DedgeAuth/ui/common.css` | Correct |

## Step 5: Register Your App in DedgeAuth

Your app must be registered in DedgeAuth's database. Options:

1. **IIS-DeployApp deploy template (recommended)** — Add a `DedgeAuth` block to your app's `.deploy.json` template in `IIS-DeployApp\templates\`. When you run `IIS-DeployApp.ps1 -SiteName YourApp`, it will register the app in the DedgeAuth database automatically. See [Publish and Deploy Guide](publish-and-deploy-guide.md).
2. **Admin Dashboard**: Navigate to `http://dedge-server/DedgeAuth/admin.html`, add your app
3. **API**: `POST /api/apps` with GlobalAdmin credentials
4. **Database Seeder**: Add to `DatabaseSeeder.SeedDefaultAppsAsync()` in DedgeAuth.Services

Required fields:

```json
{
  "appId": "YourAppId",
  "displayName": "Your Application Name",
  "description": "What your app does",
  "baseUrl": "http://your-app-url",
  "availableRoles": ["ReadOnly", "User", "Admin"]
}
```

## Step 6: Configure Tenant App Routing

Add your app to tenant routing so it appears in the user menu's app switcher:

```json
{
  "appRouting": {
    "YourAppId": "http://your-app-url"
  }
}
```

Via API: `PUT /api/tenants/{id}` with the `appRouting` object.

## Step 7: Protect Endpoints (Optional)

Use the `[RequireAppPermission]` attribute for role-based access:

```csharp
[RequireAppPermission("Admin")]
[HttpDelete("items/{id}")]
public IActionResult DeleteItem(int id) { ... }

[RequireAppPermission("User", "Admin")]
[HttpPost("items")]
public IActionResult CreateItem(ItemDto item) { ... }
```

Or use standard `[Authorize]` for any-authenticated-user protection.

## Step 8: Add DedgeSign Code Signing

All projects using DedgeAuth integration **must** include DedgeSign code signing in their `.csproj` file. This ensures the published executables are digitally signed.

Add the following block to your `.csproj` (replace `YourApp.exe` with your actual executable name):

```xml
<!-- Code Signing Configuration -->
<PropertyGroup>
  <ShouldSign>false</ShouldSign>
  <ShouldSign Condition="'$(Configuration)' == 'Release'">true</ShouldSign>
</PropertyGroup>

<Target Name="EchoConfiguration" BeforeTargets="PostBuild">
  <Message Importance="high" Text="Current Configuration: $(Configuration)" />
  <Message Importance="high" Text="Should Sign: $(ShouldSign)" />
</Target>

<Target Name="PostBuild" AfterTargets="PostBuildEvent" Condition="'$(ShouldSign)' == 'true'">
  <Exec Command="pwsh.exe -ExecutionPolicy Bypass -File &quot;dedge-server.DEDGE.fk.no\DedgeCommon\Software\DedgePshApps\DedgeSign\DedgeSign.ps1&quot; -Path &quot;$(TargetPath)&quot; -Action Add -NoConfirm -Parallel" />
</Target>

<Target Name="PostPublishSign" AfterTargets="Publish" Condition="'$(ShouldSign)' == 'true' AND '$(PublishDir)' != ''">
  <PropertyGroup>
    <PublishExePath>$(PublishDir)YourApp.exe</PublishExePath>
  </PropertyGroup>
  <Exec Command="pwsh.exe -ExecutionPolicy Bypass -File &quot;dedge-server.DEDGE.fk.no\DedgeCommon\Software\DedgePshApps\DedgeSign\DedgeSign.ps1&quot; -Path &quot;$(PublishExePath)&quot; -Action Add -NoConfirm -Parallel" Condition="Exists('$(PublishExePath)')" />
</Target>
```

### Key Points

- **Only signs in Release configuration** — Debug builds are not signed, keeping the inner dev loop fast.
- **Signs both build output and published executable** — The `PostBuild` target signs the assembly after compilation; the `PostPublishSign` target signs the exe in the publish output directory.
- **Uses DedgeSign.ps1 from the network share** — The signing script lives at `dedge-server.DEDGE.fk.no\DedgeCommon\Software\DedgePshApps\DedgeSign\DedgeSign.ps1` and is always up to date.
- **Replace `YourApp.exe`** — In the `PostPublishSign` target, update the `PublishExePath` property to match your project's output executable name (e.g., `DocView.exe`, `GenericLogHandler.WebApi.exe`).

## Step 9: Add Cursor Rule (Recommended)

Copy the DedgeAuth cursor rule into your project so Cursor AI automatically understands the integration when editing `Program.cs`, `.csproj`, HTML files, or `appsettings.json`.

```
Copy: C:\opt\src\DedgeAuth\docs\integration\cursor-rules\DedgeAuth-integration.mdc
  To: YourProject\.cursor\rules\DedgeAuth-integration.mdc
```

This rule provides the AI with:
- The correct middleware pipeline order (`AddDedgeAuth` / `UseDedgeAuth` / `MapDedgeAuthProxy`)
- HTML asset URLs (served from DedgeAuth API, never local copies)
- Route prefix casing (`/api/DedgeAuth`, not `/api/DedgeAuth`)
- DedgeSign code signing requirement
- Pointers to full integration documentation

Without this rule, the AI may not know about DedgeAuth conventions and could introduce incorrect patterns.

## OpenAPI / Scalar Integration

If your app uses `Microsoft.AspNetCore.OpenApi` + `Scalar.AspNetCore` for API documentation, add the endpoints **after** `MapDedgeAuthProxy()`:

```csharp
app.MapControllers();
app.MapDedgeAuthProxy();

// OpenAPI + Scalar (after DedgeAuth proxy)
app.MapOpenApi();
app.MapScalarApiReference();
```

Also add `/openapi` to `SkipPathPrefixes` in `appsettings.json` so the OpenAPI JSON document and Scalar UI are accessible without authentication:

```json
{
  "DedgeAuth": {
    "SkipPathPrefixes": ["/api/", "/scalar", "/openapi", "/health"]
  }
}
```

Without `/openapi` in the skip list, the Scalar UI page loads (since `/scalar` is skipped) but it cannot fetch the OpenAPI spec at `/openapi/v1.json` for unauthenticated users.

## Complete Program.cs Example

```csharp
using DedgeAuth.Client.Extensions;
using DedgeAuth.Client.Endpoints;

var builder = WebApplication.CreateBuilder(args);

// Services
builder.Services.AddControllers();
builder.Services.AddDedgeAuth(builder.Configuration);

var app = builder.Build();

// Middleware pipeline (UseRouting is implicit in .NET 6+)
app.UseDedgeAuth();
app.UseDefaultFiles();
app.UseStaticFiles();
app.MapControllers();
app.MapDedgeAuthProxy();
app.MapHealthChecks("/health");
// Do NOT add MapFallbackToFile — it prevents IIS trailing-slash redirects
// and breaks all relative CSS/JS paths under virtual applications.

app.Run();
```

> **Warning:** Never use `MapFallbackToFile("index.html")` in multi-page apps deployed as
> IIS virtual applications. It intercepts the root request before IIS can redirect
> `/MyApp` → `/MyApp/`, causing all relative CSS/JS paths to resolve incorrectly.
> `UseDefaultFiles()` + `UseStaticFiles()` is sufficient for serving `index.html` at `/`.

---

*Last updated: 2026-02-19*
