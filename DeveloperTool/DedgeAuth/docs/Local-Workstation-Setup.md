# Running DedgeAuth Ecosystem Locally on Workstation

> **Machine:** `30237-FK` (Windows 11) | **User:** `FKGEISTA` (AD-enrolled in `DEDGE`) | **Date:** 2026-02-17

This document covers everything needed to run DedgeAuth and all consumer apps on a local development workstation, including build, publish, IIS deployment, and verification.

---

## Table of Contents

- [Ecosystem Overview](#ecosystem-overview)
- [Workstation Status](#workstation-status)
- [Prerequisites](#prerequisites)
- [IIS Setup](#iis-setup)
- [Build-And-Publish-ALL.ps1 Analysis](#build-and-publish-allps1-analysis)
- [Individual Build Scripts](#individual-build-scripts)
- [Build Flow Equivalence Verification](#build-flow-equivalence-verification)
- [Configuration — All Apps](#configuration--all-apps)
- [IIS Deploy Profiles](#iis-deploy-profiles)
- [Post-Deploy Verification](#post-deploy-verification)
- [Known Blockers and Resolutions](#known-blockers-and-resolutions)
- [Quick Reference Commands](#quick-reference-commands)

---

## Ecosystem Overview

```
Browser (http://localhost)
  │
  ▼
IIS (port 80, Default Web Site)
  │
  ├── /DedgeAuth               → DedgeAuth.Api        (auth server, login UI, JWT)
  ├── /DocView               → DocView            (document viewer)
  ├── /GenericLogHandler      → GenericLogHandler  (log aggregation)
  ├── /ServerMonitorDashboard → ServerMonitorDashboard (server monitoring)
  ├── /AutoDocJson            → AutoDocJson.Web    (documentation browser)
  ├── /AutoDoc                → Static HTML        (legacy docs, directory browsing)
  └── /                       → DefaultWebSite     (root redirect page)
```

### Applications

| App | Source Path | Build Script | AppId | API Port | IIS Virtual Path |
|-----|------------|-------------|-------|---------|-----------------|
| **DedgeAuth** | `C:\opt\src\DedgeAuth` | `.\Build-And-Publish.ps1` | — (server) | 8100 | `/DedgeAuth` |
| **DocView** | `C:\opt\src\DocView` | `.\Build-And-Publish.ps1` | `DocView` | 8282 | `/DocView` |
| **AutoDocJson** | `C:\opt\src\AutoDocJson` | `.\Build-And-Publish.ps1` | `AutoDocJson` | 5280 | `/AutoDocJson` |
| **GenericLogHandler** | `C:\opt\src\GenericLogHandler` | `.\Build-And-Publish.ps1` | `GenericLogHandler` | 8110 | `/GenericLogHandler` |
| **ServerMonitorDashboard** | `C:\opt\src\ServerMonitor` | `.\Build-And-Publish.ps1` | `ServerMonitorDashboard` | 8998 | `/ServerMonitorDashboard` |
| **AutoDoc** | (static content) | — | — | — | `/AutoDoc` |

### Authentication Flow (Auth Code Exchange)

1. User visits consumer app (e.g. `http://localhost/DocView/`)
2. `DedgeAuthRedirectMiddleware` detects no token → redirects to `http://localhost/DedgeAuth/login.html?returnUrl=...`
3. User logs in at DedgeAuth → DedgeAuth redirects back with `?code=<authCode>` (short-lived authorization code)
4. `DedgeAuthTokenExtractionMiddleware` intercepts `?code=`, exchanges it server-side via `POST /api/auth/exchange` for a JWT token
5. Token is set as a cookie and the middleware redirects the user to the clean URL
6. `DedgeAuthSessionValidationMiddleware` validates the token and records a user visit (fire-and-forget to `/api/visits/record`)
7. `DedgeAuth-user.js` fetches `/api/DedgeAuth/me` for user info and renders the DedgeAuth user menu
8. Subsequent API calls use `Authorization: Bearer <jwt>`

All consumer apps share the same JWT secret, issuer, and audience — configured in each app's `appsettings.json` under the `DedgeAuth` section.

---

## Workstation Status

### What's Ready

| Component | Status | Details |
|-----------|--------|---------|
| **.NET 10 SDK** | Installed | `10.0.103` |
| **.NET 10 ASP.NET Core Runtime** | Installed | `10.0.2`, `10.0.3` |
| **IIS** (W3SVC) | Running | Service is active |
| **ANCM V2** (AspNetCoreModuleV2) | Registered | Module loaded in IIS, DLL version `20.0.26026.3` |
| **IIS Features** | Enabled | WebServer, WebServerRole, ASP.NET 4.5, NetFxExtensibility |
| **PostgreSQL** | Accessible | `t-no1fkxtst-db:8432` reachable from this machine |
| **UNC Staging Share** | Accessible | `C:\opt\src\DedgeSrc\DedgeSystemTools\Folders\DedgeCommon\Software\DedgeWinApps` — accessible with AD credentials |
| **DedgeSign** (code signing) | Accessible | `dedge-server.DEDGE.fk.no\DedgeCommon\Software\DedgePshApps\DedgeSign\DedgeSign.ps1` |
| **AD Domain** | Connected | `DEDGE\FKGEISTA` — all UNC paths, SMTP, and domain resources work |
| **PowerShell Modules** | Available | `GlobalFunctions`, `IIS-Handler`, `Deploy-Handler` on PSModulePath |
| **Local DedgeWinApps** | Exists | `C:\opt\DedgeWinApps\` with app folders present |
| **Local Webs** | Exists | `C:\opt\Webs\` (AutoDoc, etc.) |
| **`$env:OptPath`** | Set | `C:\opt` |

### Previously Missing (Now Resolved)

These items were set up on 2026-02-17 (see `Local-Setup-Execution-Report.md`):

| Component | Status | Notes |
|-----------|--------|-------|
| **IIS Default Web Site** | CREATED | Created by `IIS-RedeployAll.ps1` from templates |
| **IIS Virtual Applications** | ALL DEPLOYED | DedgeAuth, DocView, AutoDocJson, GenericLogHandler, ServerMonitorDashboard, AutoDoc |
| **IIS App Pools (per app)** | ALL CREATED | Each app has a dedicated pool (prevents 500.34/500.35) |
| **ANCM InProcess DLL** | WORKING | .NET 10 loads it from `dotnet\shared\Microsoft.AspNetCore.App\10.0.x\` |

To rebuild IIS from scratch, run `IIS-RedeployAll.ps1` (see [IIS Setup](#iis-setup)).

### ASP.NET Core Hosting Bundle

The registry shows hosting bundle entries for v8.0 and v9.0 only. However, the .NET 10 runtime (`Microsoft.AspNetCore.App 10.0.2/10.0.3`) IS installed and ANCM V2 (`20.0.26026.3`) is registered. IIS InProcess hosting for .NET 10 apps should work because ANCM V2 loads the in-process handler from the runtime's shared framework directory.

**If .NET 10 apps fail to start under IIS**, install the .NET 10 ASP.NET Core Hosting Bundle:

```powershell
# Download and install from:
# https://dotnet.microsoft.com/en-us/download/dotnet/10.0
# Look for: "Hosting Bundle" under Windows → Installers
```

---

## Prerequisites

### Required (all present on this workstation)

| Prerequisite | Check Command |
|---|---|
| .NET 10 SDK | `dotnet --version` → `10.0.x` |
| IIS enabled | `(Get-Service W3SVC).Status` → `Running` |
| ANCM V2 | `appcmd list module AspNetCoreModuleV2` → found |
| PostgreSQL reachable | `Test-NetConnection t-no1fkxtst-db -Port 8432` |
| `$env:OptPath` set | `$env:OptPath` → `C:\opt` |
| GlobalFunctions module | `Get-Module -ListAvailable GlobalFunctions` |
| IIS-Handler module | `Get-Module -ListAvailable IIS-Handler` |
| UNC share access | `Test-Path C:\opt\src\DedgeSrc\DedgeSystemTools\Folders\DedgeCommon\Software\DedgeWinApps` → `True` |

### IIS Features Required

All are currently **Enabled** on this workstation:

- `IIS-WebServer`
- `IIS-WebServerRole`
- `IIS-ASPNET45`
- `IIS-NetFxExtensibility45`

---

## IIS Setup

IIS has been configured on this workstation (see `Local-Setup-Execution-Report.md`). To rebuild or redeploy from scratch:

### Option A: Full IIS Deploy (Recommended)

```powershell
# 1. Publish all apps to staging share first
pwsh.exe -NoProfile -File "C:\opt\src\DedgeAuth\Build-And-Publish-ALL.ps1"

# 2. Deploy all apps to local IIS from staging
#    This creates Default Web Site, all app pools, all virtual apps, web.configs, and permissions
pwsh.exe -NoProfile -File "C:\opt\src\DedgePsh\DevTools\WebSites\IIS-DeployApp\IIS-RedeployAll.ps1"
```

`IIS-RedeployAll.ps1` processes all `.deploy.json` templates from `C:\opt\src\DedgePsh\DevTools\WebSites\IIS-DeployApp\templates\` in this order:

1. **Phase 1 — Uninstall**: Tears down existing apps (safe if none exist)
2. **Phase 2 — IIS Reset**: Runs `iisreset`, waits for W3SVC
3. **Phase 3 — Redeploy**: Deploys `DefaultWebSite` first (root site), then all app profiles alphabetically

### Option B: Deploy Individual App

```powershell
# Deploy a single app by name
pwsh.exe -NoProfile -File "C:\opt\src\DedgePsh\DevTools\WebSites\IIS-DeployApp\IIS-DeployApp.ps1" -SiteName "DedgeAuth"
```

### What IIS-DeployApp Does Per App

For each `AspNetCore` app (DedgeAuth, DocView, GenericLogHandler, ServerMonitorDashboard, AutoDocJson):

1. **Install files**: Copies from staging share (`C:\opt\src\DedgeSrc\DedgeSystemTools\Folders\DedgeCommon\Software\DedgeWinApps\<App>`) to local install path (`C:\opt\DedgeWinApps\<App>`)
2. **Create app pool**: Named after the app, no managed code, `ApplicationPoolIdentity`
3. **Create virtual app**: Under `Default Web Site` at `/<AppName>`
4. **Generate web.config**: Sets `hostingModel="InProcess"`, `processPath="dotnet"`, `arguments=".\<AppDll>"`
5. **Set permissions**: `IIS AppPool\<AppName>` gets read/execute on the physical path
6. **Start app pool**
7. **Health check**: Hits the health endpoint to verify (where configured)

For `Static` apps (AutoDoc, DefaultWebSite):

1. **Create app pool** and **virtual app** pointing to existing content folder
2. **Enable directory browsing** (AutoDoc only)

---

## Build-And-Publish-ALL.ps1 Analysis

### Discovery Logic

`Build-And-Publish-ALL.ps1` in `C:\opt\src\DedgeAuth\` automatically discovers consumer apps:

1. Scans `C:\opt\src\` (i.e. `$env:OptPath\src`) recursively for `.csproj` files
2. Reads each `.csproj` content looking for `DedgeAuth\.Client` reference
3. Skips any `.csproj` under `C:\opt\src\DedgeAuth\` (DedgeAuth's own projects)
4. Walks up the directory tree from each matching `.csproj` to find `Build-And-Publish.ps1`
5. Deduplicates by build script path (multiple `.csproj` in same solution share one script)

### Currently Discovered Projects

| # | .csproj | Resolves to Build Script |
|---|---------|------------------------|
| 1 | `AutoDocJson\AutoDocJson.Web\AutoDocJson.Web.csproj` | `AutoDocJson\Build-And-Publish.ps1` |
| 2 | `DocView\DocView.csproj` | `DocView\Build-And-Publish.ps1` |
| 3 | `GenericLogHandler\src\GenericLogHandler.WebApi\GenericLogHandler.WebApi.csproj` | `GenericLogHandler\Build-And-Publish.ps1` |
| 4 | `ServerMonitor\ServerMonitorDashboard\src\ServerMonitorDashboard\ServerMonitorDashboard.csproj` | `ServerMonitor\Build-And-Publish.ps1` |

### Build Order

```
Build-And-Publish-ALL.ps1
  │
  ├── 1. DedgeAuth              (auth server — always first)
  ├── 2. AutoDocJson          (consumer)
  ├── 3. DocView              (consumer)
  ├── 4. GenericLogHandler    (consumer)
  └── 5. ServerMonitor        (consumer — includes Dashboard + Agent + TrayIcon)
```

Each consumer build is invoked as:

```powershell
& pwsh.exe -File $build.BuildScript
```

This spawns a new `pwsh.exe` process per build — each script runs in isolation with its own `$ErrorActionPreference = 'Stop'`.

---

## Individual Build Scripts

### DedgeAuth (`C:\opt\src\DedgeAuth\Build-And-Publish.ps1`)

| Step | Action |
|------|--------|
| 1 | Stop any running DedgeAuth processes (by name + port 8100 + dotnet.exe with DedgeAuth) |
| 2 | Version bump (Patch by default) on `DedgeAuth.Api.csproj` |
| 3 | `dotnet publish` with `/p:PublishProfile=WebApp-FileSystem` |
| 4 | Clean staging folder before publish |
| 5 | Publish to `C:\opt\src\DedgeSrc\DedgeSystemTools\Folders\DedgeCommon\Software\DedgeWinApps\DedgeAuth` |
| 6 | Deploy DedgePsh scripts: `DedgeAuth-DatabaseSetup\_deploy.ps1` and `IIS-DeployApp\_deploy.ps1` |

**Note:** DedgeAuth's build also deploys the IIS-DeployApp scripts and templates to the server. This is important — it ensures the deploy profiles on the server stay in sync.

### DocView (`C:\opt\src\DocView\Build-And-Publish.ps1`)

| Step | Action |
|------|--------|
| 1 | `dotnet publish` with `/p:PublishProfile=WebApp-FileSystem` |
| 2 | Publish to `C:\opt\src\DedgeSrc\DedgeSystemTools\Folders\DedgeCommon\Software\DedgeWinApps\DocView` |
| 3 | Optional: start locally on port 8282, open browser |

Default: `$SkipStart = $true` — only publishes, does not start.

### AutoDocJson (`C:\opt\src\AutoDocJson\Build-And-Publish.ps1`)

| Step | Action |
|------|--------|
| 1 | `dotnet publish` of `AutoDocJson.Web\AutoDocJson.Web.csproj` with `/p:PublishProfile=WebApp-FileSystem` |
| 2 | Publish to `C:\opt\src\DedgeSrc\DedgeSystemTools\Folders\DedgeCommon\Software\DedgeWinApps\AutoDocJson` |

Simplest build script (80 lines). No version management, no process stop, no start.

### GenericLogHandler (`C:\opt\src\GenericLogHandler\Build-And-Publish.ps1`)

| Step | Action |
|------|--------|
| 1 | Stop running GenericLogHandler processes |
| 2 | Version bump (Patch) on WebApi (primary), sync to ImportService and AlertAgent |
| 3 | Publish **three** sub-projects: ImportService, WebApi, AlertAgent |
| 4 | Publish to staging: WebApi → `GenericLogHandler-WebApi`, ImportService → `GenericLogHandler-ImportService`, AlertAgent → `GenericLogHandler-AlertAgent` |
| 5 | Copy config files if missing at destination |
| 6 | Optional: start apps locally with background health-check job |

**Important:** This publishes three separate apps, not just the WebApi. Only the WebApi is an IIS virtual app; the other two are standalone services.

### ServerMonitor (`C:\opt\src\ServerMonitor\Build-And-Publish.ps1`)

| Step | Action |
|------|--------|
| 1 | Stop running ServerMonitor processes |
| 2 | Version bump (Patch) on Agent (primary), sync to Dashboard, TrayIcon, Dashboard.Tray |
| 3 | Publish **four** sub-projects: Agent, TrayIcon, Dashboard, Dashboard.Tray |
| 4 | Publish to staging share |
| 5 | DedgeSign code signing on executables |
| 6 | Verify published versions match |
| 7 | Create reinstall trigger file (for FileSystemWatcher-based auto-update) |
| 8 | Run `ServerMonitorDashboard.ps1` from DedgePsh |

**Important:** The build script is at the repo root (`ServerMonitor\Build-And-Publish.ps1`), NOT in the Dashboard subfolder.

---

## Build Flow Equivalence Verification

### Does `Build-And-Publish-ALL.ps1` produce the same result as running each script individually?

**YES** — with one important caveat.

#### What's identical

| Aspect | Equivalent? | Notes |
|--------|------------|-------|
| Discovery | ✅ | Finds all 4 consumer projects via `.csproj` scan |
| Build isolation | ✅ | Each build runs in a separate `pwsh.exe` process |
| Build order | ✅ | DedgeAuth always builds first; consumers follow alphabetically |
| Publish profile | ✅ | Each script uses its own `WebApp-FileSystem.pubxml` |
| Version bumping | ✅ | Each script handles its own versioning independently |
| Publish destination | ✅ | Same UNC paths as individual runs |
| Exit code propagation | ✅ | Non-zero exit from any build is captured; overall fails if any fail |

#### The Caveat: DedgePsh Script Deployment

When running `Build-And-Publish.ps1` for DedgeAuth **individually**, it deploys DedgePsh scripts:

```
DedgeAuth-DatabaseSetup\_deploy.ps1 → pushes to *fkxtst-db
IIS-DeployApp\_deploy.ps1       → pushes to *fkxtst-app
```

When running via `Build-And-Publish-ALL.ps1`, this **still happens** because it calls the same DedgeAuth script. The only difference is that GenericLogHandler and ServerMonitor also run their own `_deploy.ps1` scripts (if they have them) — which they do individually too.

#### What Build-And-Publish-ALL.ps1 adds

- **Summary report**: Shows success/failure for each project with timing
- **Deduplication**: If multiple `.csproj` in the same solution reference DedgeAuth.Client, only runs the build script once
- **Atomic failure reporting**: Reports overall pass/fail with `exit 1` if any build failed

#### What Build-And-Publish-ALL.ps1 does NOT add

- **No IIS deployment**: It only publishes to staging. You must separately run `IIS-RedeployAll.ps1`
- **No health checks**: It doesn't verify apps start correctly (individual scripts optionally do)
- **No browser opening**: It doesn't open any URLs

### Publish Destinations (all scripts)

| App | Publish Profile | Staging Share | Local Install Path |
|-----|----------------|--------------|-------------------|
| DedgeAuth | `WebApp-FileSystem` | `C:\opt\src\DedgeSrc\DedgeSystemTools\Folders\DedgeCommon\Software\DedgeWinApps\DedgeAuth` | `C:\opt\DedgeWinApps\DedgeAuth` |
| DocView | `WebApp-FileSystem` | `C:\opt\src\DedgeSrc\DedgeSystemTools\Folders\DedgeCommon\Software\DedgeWinApps\DocView` | `C:\opt\DedgeWinApps\DocView` |
| AutoDocJson | `WebApp-FileSystem` | `C:\opt\src\DedgeSrc\DedgeSystemTools\Folders\DedgeCommon\Software\DedgeWinApps\AutoDocJson` | `C:\opt\DedgeWinApps\AutoDocJson` |
| GenericLogHandler | `WebApp-FileSystem` | `C:\opt\src\DedgeSrc\DedgeSystemTools\Folders\DedgeCommon\Software\DedgeWinApps\GenericLogHandler-WebApi` | `C:\opt\DedgeWinApps\GenericLogHandler-WebApi` |
| ServerMonitorDashboard | `WebApp-FileSystem` | `C:\opt\src\DedgeSrc\DedgeSystemTools\Folders\DedgeCommon\Software\DedgeWinApps\ServerMonitorDashboard` | `C:\opt\DedgeWinApps\ServerMonitorDashboard` |

**Flow:** `dotnet publish` → Staging Share → `IIS-DeployApp` copies to Local Install Path → IIS serves from Local Install Path.

---

## Configuration — All Apps

### Shared Settings (identical across all consumer apps)

```json
{
  "DedgeAuth": {
    "Enabled": true,
    "AuthServerUrl": "http://localhost/DedgeAuth",
    "JwtSecret": "D3yK1/CuC08lHhYDZBFv8SYYXqX+ZGWZlyZRthGPyRDBdqI7G5ooX2TL8n5cd8TIlFjK2uuuk97ukVKynOX/WA==",
    "JwtIssuer": "DedgeAuth",
    "JwtAudience": "FKApps"
  }
}
```

- `AuthServerUrl` points to `http://localhost/DedgeAuth` — correct for local IIS
- JWT secret, issuer, and audience must match the DedgeAuth server config

### DedgeAuth Server (`appsettings.json`)

| Setting | Value | Notes |
|---------|-------|-------|
| `ConnectionStrings:AuthDb` | `Host=t-no1fkxtst-db;Port=8432;Database=DedgeAuth;Username=postgres;Password=postgres` | Remote PostgreSQL — works from workstation |
| `AuthConfiguration:ServerBaseUrl` | `http://dedge-server` | Used for building redirect URLs — may need to be `http://localhost` for local testing |
| `SmtpConfiguration:Host` | `smtp.DEDGE.fk.no` | Email sending — works with AD credentials |
| `Cors:AllowedOrigins` | `http://localhost`, `http://dedge-server`, `https://portal.Dedge.no` | `http://localhost` is already included |

### Per-App Settings

| App | AppId | Kestrel Port | DB Connection | SkipPathPrefixes |
|-----|-------|-------------|---------------|-----------------|
| DocView | `DocView` | (none in config) | (none) | `/api/`, `/scalar`, `/openapi`, `/swagger`, `/health` |
| AutoDocJson | `AutoDocJson` | (none in config) | (none) | (none configured) |
| GenericLogHandler | `GenericLogHandler` | (none in config) | `Host=t-no1fkxtst-db;Port=8432;Database=GenericLogHandler` | (none configured) |
| ServerMonitorDashboard | `ServerMonitorDashboard` | `0.0.0.0:8998` | (none — reads from agent APIs) | `/api/`, `/scalar`, `/openapi`, `/health` |

### ServerMonitorDashboard — UNC Path Dependencies

ServerMonitorDashboard's `appsettings.json` contains UNC paths for runtime data:

```json
{
  "Dashboard": {
    "ComputerInfoPath": "\\dedge-server\\DedgeCommon\\Configfiles\\ComputerInfo.json",
    "ServerMonitorExePath": "\\dedge-server\\DedgeCommon\\Software\\DedgeWinApps\\ServerMonitor\\ServerMonitor.exe",
    "ReinstallTriggerPath": "\\dedge-server\\DedgeCommon\\Software\\Config\\ServerMonitor\\ReinstallServerMonitor.txt"
  }
}
```

These are **runtime** UNC paths. They work because `FKGEISTA` has AD credentials, but the IIS app pool (`ApplicationPoolIdentity`) does **not** have domain credentials. This means:

- Under IIS, the app runs as `IIS AppPool\ServerMonitorDashboard` which has **no** UNC access
- **Impact:** Dashboard may fail to read `ComputerInfo.json` or trigger reinstalls
- **Workaround:** Either set the app pool to run as a domain user, or copy `ComputerInfo.json` locally

---

## IIS Deploy Profiles

All profiles are stored in `C:\opt\src\DedgePsh\DevTools\WebSites\IIS-DeployApp\templates\`:

| Profile File | SiteName | AppType | InstallSource | Port | Health | Special |
|-------------|----------|---------|---------------|------|--------|---------|
| `DefaultWebSite_None.deploy.json` | DefaultWebSite | Static | None | — | — | Root site (`/`), `IsRootSiteProfile: true` |
| `DedgeAuth_WinApp.deploy.json` | DedgeAuth | AspNetCore | WinApp | 8100 | `/health` | — |
| `DocView_WinApp.deploy.json` | DocView | AspNetCore | WinApp | 8282 | — | DedgeAuth DB registration |
| `GenericLogHandler_WinApp.deploy.json` | GenericLogHandler | AspNetCore | WinApp | 8110 | `/health` | `AdditionalWinApps` (Agent, BatchImport) |
| `ServerMonitorDashboard_WinApp.deploy.json` | ServerMonitorDashboard | AspNetCore | WinApp | 8998 | `/api/IsAlive` | `AdditionalPorts` (8997, 8999) |
| `AutoDocJson_WinApp.deploy.json` | AutoDocJson | AspNetCore | WinApp | 5280 | `/health` | — |
| `AutoDoc_None.deploy.json` | AutoDoc | Static | None | — | — | `EnableDirectoryBrowsing: true` |

### Deploy Profile Flow

```
.deploy.json template
  │
  ▼
IIS-DeployApp.ps1 (or IIS-RedeployAll.ps1)
  │
  ├── For WinApp InstallSource:
  │     Install-OurWinApp copies from staging share to $env:OptPath\DedgeWinApps\<App>
  │
  ├── For None InstallSource:
  │     Uses PhysicalPath as-is (content must already exist)
  │
  ├── Creates IIS app pool (No Managed Code, Integrated Pipeline)
  ├── Creates virtual application under Default Web Site
  ├── Generates web.config (AspNetCore → hostingModel InProcess)
  ├── Sets file permissions for IIS AppPool identity
  ├── Starts app pool
  └── Runs health check (if HealthEndpoint configured)
```

---

## Post-Deploy Verification

### Full Verification Sequence

```powershell
# 1. Build and publish everything
pwsh.exe -NoProfile -File "C:\opt\src\DedgeAuth\Build-And-Publish-ALL.ps1"

# 2. Deploy to local IIS
pwsh.exe -NoProfile -File "C:\opt\src\DedgePsh\DevTools\WebSites\IIS-DeployApp\IIS-RedeployAll.ps1"

# 3. Verify with screenshots + email + SMS
pwsh.exe -NoProfile -File "C:\opt\src\GrabScreenShot\Invoke-GrabScreenShot.ps1"
```

### Manual Verification URLs

| App | URL | Expected |
|-----|-----|----------|
| DedgeAuth Login | `http://localhost/DedgeAuth/login.html` | FK Green themed login form |
| DedgeAuth Admin | `http://localhost/DedgeAuth/admin.html` | Admin panel (requires login) |
| DocView | `http://localhost/DocView/` | Redirect to login, then document viewer |
| GenericLogHandler | `http://localhost/GenericLogHandler/` | Redirect to login, then log dashboard |
| ServerMonitorDashboard | `http://localhost/ServerMonitorDashboard/` | Redirect to login, then monitoring dashboard |
| AutoDocJson | `http://localhost/AutoDocJson/` | Redirect to login, then documentation browser |
| AutoDoc | `http://localhost/AutoDoc/` | Static directory listing |

### Test Credentials

```
Email:    test.service@Dedge.no
Password: TestPass123!
```

### IIS Diagnostic Tool

```powershell
# Diagnose a specific app
pwsh.exe -NoProfile -File "C:\opt\src\DedgePsh\DevTools\WebSites\IIS-DeployApp\Test-IISSite.ps1" -SiteName "DedgeAuth"
```

---

## Known Blockers and Resolutions

### Blocker 1: No IIS Default Web Site (and Stale Site from Other Server)

**Status:** Default Web Site does not exist on `30237-FK`. On the test server (`dedge-server`) there has been an existing Default Web Site that has caused issues during redeployments.

**Impact:** All virtual apps require a parent site. Without it, nothing deploys. A stale or misconfigured Default Web Site can also block all app deployments.

**Resolution — Recommended Order:**

1. **First, tear down any existing Default Web Site** (even if it looks clean — start fresh):

```powershell
# Deploy ONLY the DefaultWebSite profile to clean-create the root site
pwsh.exe -NoProfile -File "C:\opt\src\DedgePsh\DevTools\WebSites\IIS-DeployApp\IIS-DeployApp.ps1" -SiteName "DefaultWebSite"
```

This uses the `DefaultWebSite_None.deploy.json` template which:
- Has `"IsRootSiteProfile": true` and `"VirtualPath": "/"`
- Does a full teardown of any existing Default Web Site before recreating it
- Creates the physical path at `C:\opt\Webs\DefaultWebSite`
- Sets `"AppType": "Static"` and `"InstallSource": "None"` (no file copy, just creates the structure)
- Binds to port 80

2. **Then deploy all apps on top of it:**

```powershell
# Or use IIS-RedeployAll.ps1 which does both (root site first, then all apps)
pwsh.exe -NoProfile -File "C:\opt\src\DedgePsh\DevTools\WebSites\IIS-DeployApp\IIS-RedeployAll.ps1"
```

`IIS-RedeployAll.ps1` handles the full sequence:
- **Phase 1 — UNINSTALL**: Uninstalls all apps in reverse alphabetical order, then the root site. Root site uninstall errors are non-fatal (Phase 3 handles teardown anyway).
- **Phase 2 — IIS RESET**: Runs `iisreset`, waits 3 seconds for W3SVC.
- **Phase 3 — REDEPLOY**: Deploys `DefaultWebSite` first (root site), then all app profiles alphabetically. **If the root site deploy fails, all app deployment is aborted** — fix the root site first.

**Both scripts require Administrator elevation** (IIS config and iisreset need it).

### Blocker 2: HTTP Error 500.34 — ANCM Mixed Hosting Models (Recurring Issue)

**Status:** This error has occurred **multiple times** in this ecosystem and must be actively prevented.

**What it is:** HTTP 500.34 means the ASP.NET Core Module (ANCM) detected that a single IIS application pool is trying to run apps with **different hosting models** (some InProcess, some OutOfProcess). ANCM does not allow this — all apps in a worker process must use the same model.

**Why it keeps happening:**
- All apps in this ecosystem use `hostingModel="inprocess"` (set by `IIS-Handler.psm1` during deploy)
- If even one app in a shared pool uses OutOfProcess (or has no `hostingModel` specified — which defaults to OutOfProcess), **every app in that pool gets 500.34**
- Manual IIS changes, leftover web.configs, or a failed deploy can leave a mismatched `hostingModel`

**How the deploy scripts prevent it:**

The `IIS-Handler.psm1` module has built-in guards:

1. **Dedicated app pool per app** — `IIS-DeployApp.ps1` creates a unique app pool named after each app (`DedgeAuth`, `DocView`, etc.). This isolates hosting models.

2. **Shared pool detection** — Before deploying, `Deploy-IISSite` checks if the target app pool already has other apps. If it does, deployment is **blocked** with an error (prevents HTTP 500.35, which is the related "multiple InProcess apps in one pool" error).

3. **web.config generation** — The deploy script always generates a fresh `web.config` with `hostingModel="inprocess"` explicitly set. It never relies on defaults.

**If you hit 500.34 despite this:**

```powershell
# 1. Check which apps share a pool
& "$env:SystemRoot\System32\inetsrv\appcmd.exe" list app /apppool.name:"DefaultAppPool"

# 2. Check web.config hosting model for each app
Get-ChildItem "C:\opt\DedgeWinApps" -Recurse -Filter "web.config" | ForEach-Object {
    [xml]$wc = Get-Content $_.FullName
    $hm = $wc.SelectSingleNode("//aspNetCore")?.GetAttribute("hostingModel")
    Write-Output "$($_.Directory.Name): hostingModel=$hm"
}

# 3. Nuclear fix — tear down everything and redeploy from templates
pwsh.exe -NoProfile -File "C:\opt\src\DedgePsh\DevTools\WebSites\IIS-DeployApp\IIS-RedeployAll.ps1"

# 4. Diagnose a specific app
pwsh.exe -NoProfile -File "C:\opt\src\DedgePsh\DevTools\WebSites\IIS-DeployApp\Test-IISSite.ps1" -SiteName "DedgeAuth"
```

**Related errors:**
| Error | Meaning | Cause |
|-------|---------|-------|
| 500.34 | Mixed hosting models | InProcess + OutOfProcess in same pool |
| 500.35 | Multiple InProcess apps | Two or more InProcess apps sharing one pool |
| 500.30 | InProcess start failure | App DLL crash on startup (missing config, bad connection string, missing dependency) |
| 500.31 | Failed to find native DLL | ANCM can't find `aspnetcorev2_inprocess.dll` — install hosting bundle |

### Blocker 3: ANCM InProcess DLL Location

**Status:** `aspnetcorev2_inprocess.dll` is NOT in `C:\Program Files\IIS\Asp.Net Core Module\V2\`.

**Impact:** None expected. In .NET 10, the in-process handler DLL lives in the shared framework folder (`C:\Program Files\dotnet\shared\Microsoft.AspNetCore.App\10.0.x\`). ANCM V2 loads it from there automatically.

**Resolution:** If IIS returns 500 errors with `ANCM In-Process Handler Load Failure`, install the .NET 10 Hosting Bundle.

### Blocker 4: ServerMonitorDashboard UNC Paths Under IIS

**Status:** `appsettings.json` references UNC paths (`dedge-server\...`) for `ComputerInfoPath`, `ServerMonitorExePath`, etc.

**Impact:** IIS app pool identity (`IIS AppPool\ServerMonitorDashboard`) has no domain credentials. UNC access will fail.

**Resolution Options:**
1. Change app pool to run as a domain user (e.g. `DEDGE\FKGEISTA`)
2. Copy `ComputerInfo.json` to a local path and update `appsettings.json`
3. Accept that this feature degrades locally (dashboard still works for monitoring, just can't trigger remote reinstalls)

### Blocker 5: GenericLogHandler Negotiate Package

**Status:** `GenericLogHandler.WebApi.csproj` references `Microsoft.AspNetCore.Authentication.Negotiate` (v10.0.0).

**Impact:** None. The package is included but **no Negotiate middleware is registered** in `Program.cs`. The app uses DedgeAuth JWT auth only.

**Resolution:** Can be removed if desired, but won't cause issues.

### Blocker 6: ServerMonitorDashboard TFM

**Status:** `ServerMonitorDashboard.csproj` targets `net10.0-windows` (not plain `net10.0`).

**Impact:** None for running locally on Windows. Would only matter if trying to publish for Linux.

**Resolution:** No action needed.

### Blocker 7: Port 80 Conflict

**Status:** IIS needs port 80. If another service (e.g. a dev server) is using port 80, IIS won't start.

**Resolution:**

```powershell
# Check what's using port 80
Get-NetTCPConnection -LocalPort 80 -State Listen -ErrorAction SilentlyContinue |
  ForEach-Object { Get-Process -Id $_.OwningProcess -ErrorAction SilentlyContinue } |
  Select-Object Id, ProcessName, Path
```

### Non-Blocker: DedgeAuth ServerBaseUrl

**Status:** DedgeAuth's `appsettings.json` has `"ServerBaseUrl": "http://dedge-server"`.

**Impact:** This is used for building absolute redirect URLs. When running locally, redirects might point to `dedge-server` instead of `localhost`.

**Resolution:** If redirects break, update to `"ServerBaseUrl": "http://localhost"` in the **deployed** `appsettings.json` (at `C:\opt\DedgeWinApps\DedgeAuth\appsettings.json`), not the source.

---

## Quick Reference Commands

### Full Build + Deploy + Verify

```powershell
# Complete sequence
pwsh.exe -NoProfile -File "C:\opt\src\DedgeAuth\Build-And-Publish-ALL.ps1"
pwsh.exe -NoProfile -File "C:\opt\src\DedgePsh\DevTools\WebSites\IIS-DeployApp\IIS-RedeployAll.ps1"
pwsh.exe -NoProfile -File "C:\opt\src\GrabScreenShot\Invoke-GrabScreenShot.ps1"
```

### Build Only (no deploy)

```powershell
# All apps
pwsh.exe -NoProfile -File "C:\opt\src\DedgeAuth\Build-And-Publish-ALL.ps1"

# DedgeAuth only
pwsh.exe -NoProfile -File "C:\opt\src\DedgeAuth\Build-And-Publish.ps1"

# Consumer apps only (skip DedgeAuth)
pwsh.exe -NoProfile -File "C:\opt\src\DedgeAuth\Build-And-Publish-ALL.ps1" -SkipDedgeAuth
```

### Dry Run (see what would be built)

```powershell
pwsh.exe -NoProfile -File "C:\opt\src\DedgeAuth\Build-And-Publish-ALL.ps1" -DryRun
```

### IIS Operations

```powershell
# Deploy all apps from staging to IIS
pwsh.exe -NoProfile -File "C:\opt\src\DedgePsh\DevTools\WebSites\IIS-DeployApp\IIS-RedeployAll.ps1"

# Deploy single app
pwsh.exe -NoProfile -File "C:\opt\src\DedgePsh\DevTools\WebSites\IIS-DeployApp\IIS-DeployApp.ps1" -SiteName "DedgeAuth"

# Diagnose app
pwsh.exe -NoProfile -File "C:\opt\src\DedgePsh\DevTools\WebSites\IIS-DeployApp\Test-IISSite.ps1" -SiteName "DedgeAuth"

# Check IIS status
& "$env:SystemRoot\System32\inetsrv\appcmd.exe" list site
& "$env:SystemRoot\System32\inetsrv\appcmd.exe" list app
& "$env:SystemRoot\System32\inetsrv\appcmd.exe" list apppool
```

### Log Locations

| Log | Path |
|-----|------|
| DedgeAuth app logs | `C:\opt\data\DedgeAuth\Logs\DedgeAuth-YYYYMMDD.log` |
| IIS deploy logs | `C:\opt\data\IIS-DeployApp\FkLog_YYYYMMDD.log` |
| IIS request logs | `C:\inetpub\logs\LogFiles\W3SVC1\` |
| PowerShell logs | `C:\opt\data\AllPwshLog\FkLog_YYYYMMDD.log` |

---

## Operational Rules

### Database Server

The database server for **all** projects remains `t-no1fkxtst-db` on port `8432`. No local PostgreSQL is needed. All apps connect to the shared remote database using username/password auth (not Windows auth).

| App | Database | Connection String Host |
|-----|----------|----------------------|
| DedgeAuth | `DedgeAuth` | `Host=t-no1fkxtst-db;Port=8432` |
| GenericLogHandler | `GenericLogHandler` | `Host=t-no1fkxtst-db;Port=8432` |
| DocView | (none) | — |
| AutoDocJson | (none) | — |
| ServerMonitorDashboard | (none — reads from agent APIs) | — |

### IIS Server — localhost Only

IIS runs on **this local workstation** (`30237-FK`). All URLs must use `http://localhost/...` — **never** the machine name.

- **Use:** `http://localhost/DedgeAuth/login.html`
- **Do NOT use:** `http://30237-FK/DedgeAuth/login.html`

All consumer apps already have `"AuthServerUrl": "http://localhost/DedgeAuth"` in their `appsettings.json` — this is correct and requires no changes.

### DedgeAuth Fallback — Enabled Toggle

All consumer apps have a `DedgeAuth:Enabled` setting. If DedgeAuth integration cannot be made to work by morning, set this to `false` in each app's `appsettings.json` so the apps still function without authentication:

| App | appsettings.json Path | Current Value |
|-----|----------------------|---------------|
| DocView | `C:\opt\src\DocView\appsettings.json` | `"Enabled": true` |
| AutoDocJson | `C:\opt\src\AutoDocJson\AutoDocJson.Web\appsettings.json` | `"Enabled": true` |
| GenericLogHandler (WebApi) | `C:\opt\src\GenericLogHandler\src\GenericLogHandler.WebApi\appsettings.json` | `"Enabled": true` |
| ServerMonitorDashboard | `C:\opt\src\ServerMonitor\ServerMonitorDashboard\src\ServerMonitorDashboard\appsettings.json` | `"Enabled": true` |

**Fallback action** (only if DedgeAuth cannot work by morning):

```json
"DedgeAuth": {
  "Enabled": false
}
```

> **Note:** AutoDocJson also has `appsettings.Development.json` with `"Enabled": false` — this already disables DedgeAuth in development mode.

### Primary Problem App: ServerMonitorDashboard

ServerMonitorDashboard is the consumer app that has caused the most issues historically, including the recurring **IIS HTTP 500.34** error. It should receive extra attention during overnight work:

- It targets `net10.0-windows` (not plain `net10.0`)
- Its `appsettings.json` contains UNC paths that the IIS app pool identity cannot access
- It was the app where the mixed hosting model error (500.34) was previously triggered
- It has the most complex build script (builds Agent, TrayIcon, Dashboard, Dashboard.Tray)

### Manual Fixes vs. Permanent Fixes

Manual commands to attempt local fixes are **allowed** during troubleshooting — but any fix that works must **ultimately be implemented in the related script or app as code or config**. Temporary hacks (e.g. running `appcmd` manually to fix a web.config) are acceptable for diagnostics, but the root cause must be fixed in the source so that the next `Build-And-Publish-ALL.ps1` + `IIS-RedeployAll.ps1` cycle produces the same correct result.

**Rule:** If a manual IIS/config fix works, trace it back to the responsible script (`IIS-Handler.psm1`, `IIS-DeployApp.ps1`, `Build-And-Publish.ps1`, `appsettings.json`, `.csproj`, or `web.config` template) and make the fix permanent there.

### Deployment of Fixes — Mandatory Flow

Verification of any permanent fix must **only** occur through the standard deployment pipeline:

1. Make the code/config change in the source repo
2. **Build and publish**: `Build-And-Publish-ALL.ps1`
3. **Deploy to local IIS** — either:
   - `IIS-RedeployAll.ps1` (tears down all apps, resets IIS, reinstalls everything from staging) — preferred for full verification
   - `IIS-DeployApp.ps1 -SiteName "<AppName>"` for a single app — acceptable for iterating on one app

**Do NOT** verify a fix by manually copying files to `C:\opt\DedgeWinApps\` or editing deployed `web.config` files in place. The deployment scripts must reproduce the correct state from source.

### Debug Logging — Enable at Process Start

Before beginning overnight work, **set all apps and scripts to DEBUG level** so that every diagnostic detail is captured in the logs. If during troubleshooting you discover that an app or script is missing log output you need, **add the missing log statements at level DEBUG** in the source code, then rebuild and redeploy.

#### Current Log Levels (appsettings.json → Logging:LogLevel:Default)

| App | Current Level | Needs Change? |
|-----|--------------|---------------|
| DedgeAuth | `Debug` | No — already at Debug |
| DocView | `Information` | **YES → set to `Debug`** |
| AutoDocJson | `Information` | **YES → set to `Debug`** |
| GenericLogHandler (WebApi) | `Information` | **YES → set to `Debug`** |
| ServerMonitorDashboard | `Information` | **YES → set to `Debug`** |

#### How to Enable Debug Logging

Set the `Default` log level to `Debug` in each app's `appsettings.json` **before** running `Build-And-Publish-ALL.ps1`:

```json
"Logging": {
  "LogLevel": {
    "Default": "Debug",
    "Microsoft.AspNetCore": "Warning"
  }
}
```

Keep `Microsoft.AspNetCore` at `Warning` to avoid flooding logs with framework noise — only the app's own code needs Debug output.

#### Files to Edit

```
C:\opt\src\DocView\appsettings.json
C:\opt\src\AutoDocJson\AutoDocJson.Web\appsettings.json
C:\opt\src\GenericLogHandler\src\GenericLogHandler.WebApi\appsettings.json
C:\opt\src\ServerMonitor\ServerMonitorDashboard\src\ServerMonitorDashboard\appsettings.json
```

#### Adding Missing Log Statements

If during troubleshooting a log file doesn't contain the information needed to diagnose an issue:

1. Add `_logger.LogDebug("...")` (C#) or `Write-LogMessage "..." -Level DEBUG` (PowerShell) at the relevant code points
2. Rebuild via `Build-And-Publish-ALL.ps1`
3. Redeploy via `IIS-RedeployAll.ps1`
4. Check the logs again

This ensures all diagnostic additions flow through the standard build/deploy pipeline and are permanently available for future troubleshooting.

### Manual Fix → Permanent Fix Rule (Strict)

**Never accept a test result based on a manual fix alone.** The process is:

1. **Discover the issue** — check logs, IIS config, browser errors
2. **Apply a manual fix** to diagnose — e.g. run `appcmd`, edit a deployed `web.config`, tweak a config value in `C:\opt\DedgeWinApps\`
3. **Verify the manual fix works** — browser test, health check, log review
4. **Implement the fix permanently** — edit the source code, script, config, or template that should produce this result
5. **Full rebuild and redeploy** — `Build-And-Publish-ALL.ps1` → `IIS-RedeployAll.ps1`
6. **Re-verify from the clean deploy** — only this result counts as PASS

If the manual fix works but the rebuild/redeploy does NOT reproduce it, the fix is **not done**. Find what the deployment pipeline is doing differently and fix that.

### Autonomous Overnight Operation

Cursor AI should work **tirelessly through the night** — fixing, checking, and retrying until all apps work or the deadline is reached.

**Hard deadline:** `09:00 AM CET (Norwegian time)` the next morning. **Do NOT stop working before that** unless every single app is verified working from a clean rebuild/redeploy.

#### Work Loop

1. **Enable Debug logging** in all apps (edit `appsettings.json` files above)
2. **Build all apps** via `Build-And-Publish-ALL.ps1`
3. **Deploy to local IIS** via `IIS-RedeployAll.ps1`
4. **Check every log file** (see complete list below) for errors
5. **Fix any issues found** — configuration, IIS setup, missing dependencies
6. **Implement fixes in source** — never leave a fix as manual-only
7. **Re-deploy and re-check** via `Build-And-Publish-ALL.ps1` + `IIS-RedeployAll.ps1` — repeat until all apps pass health checks and browser verification
8. **Add DEBUG log statements** wherever diagnostic information is missing, rebuild, redeploy
9. **No arbitrary retry limits** — keep working until success or 09:00 AM CET
10. **If all else fails by 09:00 AM**: set `DedgeAuth:Enabled` to `false` in all consumer apps so they run without auth

#### Hourly SMS Progress Updates

Send an SMS **every hour** with a progress update. This is mandatory regardless of whether progress is being made or the agent is stuck.

```powershell
Import-Module GlobalFunctions -Force
Send-Sms -Receiver "+4797188358" -Message "HH:MM - Status: X/6 apps OK. Working on: <current issue>. Next: <plan>."
```

**SMS content rules:**
- Under 1024 characters
- Include: timestamp, how many apps are passing, what is currently being worked on
- If stuck on the same issue for >1 hour, say so explicitly
- If all apps pass, send the final success SMS (after email with screenshots)

**Example hourly SMS messages:**

```
23:00 - 1/6 apps OK (DedgeAuth). Working on: ServerMonitorDashboard 500.34. Rebuilding with fix.
00:00 - 3/6 apps OK. Fixed SMD hosting model. Working on: GenericLogHandler startup error.
01:00 - 5/6 apps OK. AutoDocJson health check failing. Investigating logs.
02:00 - 6/6 apps OK! Running full browser verification. Email with screenshots next.
02:15 - DONE. All 6 apps verified. Screenshots emailed. Clean rebuild confirmed.
```

#### Rule Re-Read Cadence

**Every 15 minutes**, re-read all workspace rules (`.cursor/rules/*.mdc`) and this document to refresh context. Long-running sessions cause context drift — re-reading prevents:

- Forgetting the mandatory rebuild/redeploy verification cycle
- Skipping the email-before-SMS ordering
- Using `powershell.exe` instead of `pwsh.exe`
- Adding Co-authored-by or Cursor attribution to commits
- Using machine name instead of `localhost` in URLs
- Accepting manual fixes as final without a clean redeploy

**Rules to re-read every 15 minutes:**

```
.cursor/rules/deploy-publish.mdc
.cursor/rules/browser-test-verification-report.mdc
.cursor/rules/web-testing-methodology.mdc
.cursor/rules/ecosystem-consumer-apps.mdc
.cursor/rules/architecture-and-technology.mdc
.cursor/rules/autonomous-task-completion.mdc
.cursor/rules/agent-notifications.mdc
.cursor/rules/git-no-attribution.mdc
.cursor/rules/git-commit-powershell.mdc
.cursor/rules/prohibited-content.mdc
.cursor/rules/documentation-placement.mdc
.cursor/rules/consumer-app-visual-reference.mdc
docs/Local-Workstation-Setup.md  (this document)
```

#### Timeline

```
Evening:   Enable debug logging → Build → Deploy → First verification pass
Night:     Fix issues → Rebuild → Redeploy → Re-verify (loop)
Every 15m: Re-read all rules and this document
Hourly:    SMS progress update to +4797188358
Success:   Browser verify all apps → Screenshot → Email → Final SMS
09:00 AM:  HARD STOP — if not done, set DedgeAuth:Enabled=false in all apps as fallback
```

### Final Verification and Notification

When all apps are working — after a **clean rebuild and redeploy** (not a manual fix) — perform a full visual verification and send a report:

#### Step 1: Full Browser Verification

Open **every** app in the browser and test **all** visual components:

| App | URL | What to Test |
|-----|-----|-------------|
| DedgeAuth Login | `http://localhost/DedgeAuth/login.html` | Login form, email/password fields, magic link tab, FK Green theme |
| DedgeAuth Admin | `http://localhost/DedgeAuth/admin.html` | Sidebar nav (Apps, Users, Tenants), data tables, URL mismatch banner |
| DocView | `http://localhost/DocView/` | Auth redirect, document tree, preview pane, header, user menu |
| GenericLogHandler | `http://localhost/GenericLogHandler/` | Auth redirect, date filters, log level filters, log table, search |
| ServerMonitorDashboard | `http://localhost/ServerMonitorDashboard/` | Auth redirect, server status cards, charts, alert indicators |
| AutoDocJson | `http://localhost/AutoDocJson/` | Auth redirect, dashboard cards, tabbed file lists, theme toggle |

For every page:
- **Click all buttons and switches** — verify they respond correctly
- **Test navigation links** — verify sub-pages load styled
- **Check DedgeAuth user menu** — dropdown opens, shows user info, app switcher works, logout works
- **Verify tenant CSS** — FK Green header gradient, Dedge logo visible
- **Test dark/light theme toggle** (where present)
- **Take a screenshot** of every verified page

#### Step 2: Send Email with Screenshots

Use the GrabScreenShot tool (preferred) or `Send-Email` from GlobalFunctions:

```powershell
# Preferred: GrabScreenShot captures all apps, emails, and sends SMS in one command
pwsh.exe -NoProfile -File "C:\opt\src\GrabScreenShot\Invoke-GrabScreenShot.ps1"
```

If GrabScreenShot is not suitable (e.g. only testing a subset), use `Send-Email` directly:

```powershell
Import-Module GlobalFunctions -Force
Send-Email -To "geir.helge.starholm@Dedge.no" `
           -Subject "DedgeAuth Local Workstation Setup - All Apps Verified $(Get-Date -Format 'yyyy-MM-dd HH:mm')" `
           -Body $reportBody `
           -Attachments $screenshotFiles
```

The email must include:
- Full URL of every page tested (plain text)
- PASS/FAIL status for each page
- Screenshots attached as PNG files
- Note that this was verified from a **clean `Build-And-Publish-ALL.ps1` + `IIS-RedeployAll.ps1` deployment**, not a manual fix

#### Step 3: Send SMS Notification

After the email with screenshots is sent:

```powershell
Import-Module GlobalFunctions -Force
Send-Sms -Receiver "+4797188358" -Message "Local workstation setup done. X apps verified PASS. Email with screenshots sent."
```

**SMS rules:**
- Under 1024 characters
- Include: number of apps tested, overall pass/fail, confirmation that email was sent
- **Do NOT send SMS claiming success before email with screenshots is sent**
- **Do NOT send SMS claiming success if verification was based on a manual fix** — only after a clean rebuild/redeploy cycle

#### Notification Flow Summary

```
All apps working (after clean rebuild + redeploy)
  │
  ├── 1. Browser: open every app, test all buttons/switches/visual components
  ├── 2. Screenshot: capture every verified page as PNG
  ├── 3. Email: send report + screenshots to geir.helge.starholm@Dedge.no
  └── 4. SMS: send completion notification to +4797188358
```

---

## Complete Log File Reference

Every log file location across the entire ecosystem. Use these to diagnose issues during overnight work.

### Application Logs (Serilog / NLog)

| App | Framework | Log Path | Filename Pattern | Retention |
|-----|-----------|----------|-----------------|-----------|
| **DedgeAuth** | Serilog | `C:\opt\data\DedgeAuth\Logs\` | `DedgeAuth-YYYYMMDD.log` | 31 days |
| **GenericLogHandler** | Serilog | via config (console + file) | Configured in `Serilog.WriteTo` section | — |
| **ServerMonitorAgent** | NLog | `%LOG_DIRECTORY%` (env var) | `{appName}_{machinename}_{shortdate}.log` | Daily rolling, archived |
| **AutoDocJson** (Core) | Custom | `C:\opt\data\AutoDocJson\` | `{shortdate}.log` | 30 days |
| **AutoDocJson** (Core) | Custom | `C:\opt\data\AllPwshLog\` | (global log) | 30 days |

### PowerShell Script Logs (GlobalFunctions Write-LogMessage)

GlobalFunctions writes to **multiple log files simultaneously** on every `Write-LogMessage` call:

| Log Target | Path | Filename Pattern | Notes |
|------------|------|-----------------|-------|
| **Script-specific log** | `C:\opt\data\{ScriptName}\` | `FkLog_YYYYMMDD.log` | Derived from calling script name |
| **Global PowerShell log** | `C:\opt\data\AllPwshLog\` | `FkLog_YYYYMMDD.log` | All scripts write here |
| **Override folder** (if set) | Varies per script | `FkLog_YYYYMMDD.log` | Set via `Set-OverrideAppDataFolder` |

### IIS Deployment Logs

| Script | Log Path | Filename Pattern |
|--------|----------|-----------------|
| **IIS-DeployApp.ps1** | `C:\opt\data\IIS-DeployApp\` | `FkLog_YYYYMMDD.log` |
| **IIS-RedeployAll.ps1** | `C:\opt\data\IIS-DeployApp\` | `FkLog_YYYYMMDD.log` |
| **Test-IISSite.ps1** | `C:\opt\data\IIS-DeployApp\` | `FkLog_YYYYMMDD.log` |

All IIS-DeployApp scripts use `Set-OverrideAppDataFolder -Path $(Join-Path $env:OptPath "data" "IIS-DeployApp")`.

### IIS System Logs

| Log | Path | Notes |
|-----|------|-------|
| **IIS request logs** | `C:\inetpub\logs\LogFiles\W3SVC1\` | HTTP request logs per site |
| **IIS stdout logs** | `C:\opt\DedgeWinApps\{App}\logs\` | Only if `stdoutLogEnabled="true"` in web.config |
| **Windows Event Log** | Event Viewer → Application | Source: `IIS AspNetCore Module V2` for ANCM errors |

### ServerMonitor Alert Logs

| Log Type | Path | Pattern |
|----------|------|---------|
| **Alert file log** | `C:\opt\data\ServerMonitor\` | `ServerMonitor_Alerts_{Date}.log` |
| **SQL error log** | `C:\opt\src\DedgeSrc\DedgeSystemTools\Folders\Commonlogging\Server\ServerMonitor\` | `{ServerName}_{Date}_{Database}_sqlerrors.log` |
| **NLog archive** | `%LOG_DIRECTORY%\archive\` | `{appName}_{machinename}_{date}.log` |

### GenericLogHandler Import Error Log

| Log | Path |
|-----|------|
| **Import errors** | `C:\opt\logs\import_errors.log` |

### Build Script Logs

Build scripts use `Write-LogMessage` (GlobalFunctions) and write to:

| Script | Log Path |
|--------|----------|
| `Build-And-Publish.ps1` (any) | `C:\opt\data\AllPwshLog\FkLog_YYYYMMDD.log` |
| `Build-And-Publish-ALL.ps1` | `C:\opt\data\AllPwshLog\FkLog_YYYYMMDD.log` (plus console output) |

### Quick Log Check Commands

```powershell
# Today's date suffix
$today = Get-Date -Format 'yyyyMMdd'

# === Application Logs ===
# DedgeAuth app log
Get-Content "C:\opt\data\DedgeAuth\Logs\DedgeAuth-$(Get-Date -Format 'yyyyMMdd').log" -Tail 50

# === PowerShell / Build Logs ===
# Global PowerShell log (all scripts)
Get-Content "C:\opt\data\AllPwshLog\FkLog_$($today).log" -Tail 50

# IIS deployment log
Get-Content "C:\opt\data\IIS-DeployApp\FkLog_$($today).log" -Tail 50

# === IIS Logs ===
# Most recent IIS request log
Get-ChildItem "C:\inetpub\logs\LogFiles\W3SVC1\" -Filter "*.log" | Sort-Object LastWriteTime -Descending | Select-Object -First 1 | Get-Content -Tail 30

# === Windows Event Log (ANCM / IIS errors) ===
Get-WinEvent -FilterHashtable @{LogName='Application'; ProviderName='IIS AspNetCore Module V2'; StartTime=(Get-Date).AddHours(-4)} -MaxEvents 20 -ErrorAction SilentlyContinue | Format-List TimeCreated, Message

# === Search all logs for errors ===
# Find ERROR lines across all today's logs
Get-ChildItem "C:\opt\data" -Recurse -Filter "*$($today)*" | ForEach-Object {
    $errors = Select-String -Path $_.FullName -Pattern "ERROR|FATAL|Exception" -ErrorAction SilentlyContinue
    if ($errors) { Write-Output "--- $($_.FullName) ---"; $errors | Select-Object -Last 10 }
}
```
