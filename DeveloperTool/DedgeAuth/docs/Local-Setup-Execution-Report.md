# Local Workstation Setup — Execution Report

> **Machine:** `30237-FK` (Windows 11) | **User:** `FKGEISTA` (DEDGE AD) | **Date:** 2026-02-17  
> **Start:** 19:10 | **Finish:** 20:35 | **Total Duration:** ~85 minutes  
> **Result:** ALL 6 APPS PASS

---

## Objective

Run the entire DedgeAuth ecosystem (DedgeAuth + 5 consumer apps) locally on workstation `30237-FK` under IIS, with all apps healthy, visually verified, and fully functional via `http://localhost`.

---

## Apps in Scope

| # | App | Source | Type | IIS Path | Port |
|---|-----|--------|------|----------|------|
| 1 | **DedgeAuth** | `C:\opt\src\DedgeAuth` | Auth server | `/DedgeAuth` | 8100 |
| 2 | **DocView** | `C:\opt\src\DocView` | Document viewer | `/DocView` | 8282 |
| 3 | **AutoDocJson** | `C:\opt\src\AutoDocJson` | Documentation tool | `/AutoDocJson` | — |
| 4 | **GenericLogHandler** | `C:\opt\src\GenericLogHandler` | Log aggregation | `/GenericLogHandler` | 8110 |
| 5 | **ServerMonitorDashboard** | `C:\opt\src\ServerMonitor` | Server monitoring | `/ServerMonitorDashboard` | 8998 |
| 6 | **AutoDoc** | (static content) | Static docs site | `/AutoDoc` | — |

Database: Remote PostgreSQL on `t-no1fkxtst-db:8432` (unchanged).

---

## Step-by-Step Execution

### Phase 0 — Load Context (19:10)

- Read all `.cursor/rules/*.mdc` files to understand deployment, testing, and notification rules.
- Read `docs/Local-Workstation-Setup.md` for the full plan created in the previous session.
- Confirmed the 27-task plan from the todo list.

### Phase 1 — Enable Debug Logging (19:11)

Changed `Logging:LogLevel:Default` from `"Information"` to `"Debug"` in all 4 consumer apps:

| File | Change |
|------|--------|
| `C:\opt\src\DocView\appsettings.json` | `Information` → `Debug` |
| `C:\opt\src\AutoDocJson\AutoDocJson.Web\appsettings.json` | `Information` → `Debug` |
| `C:\opt\src\GenericLogHandler\src\GenericLogHandler.WebApi\appsettings.json` | `Information` → `Debug` |
| `C:\opt\src\ServerMonitor\ServerMonitorDashboard\src\ServerMonitorDashboard\appsettings.json` | `Information` → `Debug` |

DedgeAuth itself was already at `Debug`.

### Phase 2 — Build All Projects (19:11 – 19:17)

Ran `Build-And-Publish-ALL.ps1` from `C:\opt\src\DedgeAuth`.

**Result: 5/5 SUCCESS**

| Project | Duration | Status |
|---------|----------|--------|
| DedgeAuth | 90.0s | SUCCESS |
| AutoDocJson | 24.5s | SUCCESS |
| DocView | 24.8s | SUCCESS |
| GenericLogHandler | 58.6s | SUCCESS |
| ServerMonitor | 176.9s | SUCCESS |
E
Ran `IIS-RedeployAll.ps1` to tear down all IIS apps, perform `iisreset`, and redeploy from staging.

**Result: FAILED — 6 failures**

The script completed all deployment steps (create app pools, virtual apps, web.config, permissions, firewall rules) but every health check failed with:

```
No connection could be made because the target machine actively refused it. (localhost:80)
```

**Root cause identified:** The `Default Web Site` went into `Unknown` state after the initial creation. Port 80 was not accepting connections.

### Phase 3.1 — Root Cause Investigation (19:31 – 19:33)

Diagnostic commands revealed:

```
SITE "Default Web Site" (id:1, bindings:http/*:80:, state:Unknown)
```

All 6 app pools were `Started`. All 6 virtual apps were correctly configured. The root "/" application was **missing** from the Default Web Site — it had been deleted during the DocView deployment.

**The bug:** In `IIS-Handler.psm1`, the `Deploy-IISSite` function's teardown step (Step 1b) queries `appcmd list app /app.name:"Default Web Site/DocView"` to check if DocView's virtual app exists before deleting it. However, **`appcmd.exe` performs prefix matching** — when DocView's app doesn't exist yet (fresh deployment), the query returns `APP "Default Web Site/"` (the root app) because it starts with "Default Web Site/". The code then deleted this root "/" app, causing the entire site to go into `Unknown` state.

Verified with manual test:
```
C:\> appcmd list app /app.name:"Default Web Site/NonExistentApp"
APP "Default Web Site/" (applicationPool:DefaultWebSite)
```

### Phase 3.2 — Manual Fix (19:33)

Re-added the root application and started the site:

```
appcmd add app /site.name:"Default Web Site" /path:"/" /physicalPath:"C:\opt\Webs\DefaultWebSite" /applicationPool:"DefaultWebSite"
appcmd start site "Default Web Site"
```

**Result:** All 6 apps immediately became accessible:

| App | URL | Result |
|-----|-----|--------|
| DedgeAuth | `http://localhost/DedgeAuth/health` | 200 OK |
| DocView | `http://localhost/DocView/` | 302 → login (expected) |
| AutoDocJson | `http://localhost/AutoDocJson/` | 302 → login (expected) |
| GenericLogHandler | `http://localhost/GenericLogHandler/` | 200 OK |
| ServerMonitorDashboard | `http://localhost/ServerMonitorDashboard/api/IsAlive` | 200 OK |
| AutoDoc | `http://localhost/AutoDoc/` | 200 OK |

### Phase 3.3 — Permanent Fix in Source (19:33 – 19:35)

Per the rules: manual fixes must be implemented as permanent code changes and verified by full rebuild/redeploy.

**Fixed in:** `C:\opt\src\DedgePsh\_Modules\IIS-Handler\IIS-Handler.psm1` (line ~2729)

**The fix:** After extracting the app ID from `appcmd` output, compare it against the intended target. If they don't match (i.e., appcmd prefix-matched the root "/" app instead of the requested sub-app), skip the deletion and log a warning.

```powershell
# Guard: appcmd prefix-matches, so verify the result is our actual target
# and not the root "/" app or a different app entirely
$normalizedExact = $exactAppId.TrimEnd('/')
$normalizedTarget = $appIdentifier.TrimEnd('/')
if ($normalizedExact -eq $normalizedTarget) {
    # Safe to delete — exact match
    ...
} else {
    Write-LogMessage "appcmd prefix-matched '$exactAppId' instead of '$appIdentifier' -- skipping delete to protect root app" -Level WARN
}
```

### Phase 3.4 — Clean Redeploy with Fix (19:35 – 19:41)

Ran `IIS-RedeployAll.ps1` again to verify the fix.

**Result: 7/7 SUCCESS (exit code 0)**

The fix triggered correctly for all 6 virtual apps:

```
[WARN] appcmd prefix-matched 'Default Web Site/' instead of 'Default Web Site/AutoDoc' -- skipping delete to protect root app
[WARN] appcmd prefix-matched 'Default Web Site/' instead of 'Default Web Site/AutoDocJson' -- skipping delete to protect root app
[WARN] appcmd prefix-matched 'Default Web Site/' instead of 'Default Web Site/DocView' -- skipping delete to protect root app
[WARN] appcmd prefix-matched 'Default Web Site/' instead of 'Default Web Site/DedgeAuth' -- skipping delete to protect root app
[WARN] appcmd prefix-matched 'Default Web Site/' instead of 'Default Web Site/GenericLogHandler' -- skipping delete to protect root app
[WARN] appcmd prefix-matched 'Default Web Site/' instead of 'Default Web Site/ServerMonitorDashboard' -- skipping delete to protect root app
```

Default Web Site stayed `Started` throughout. All health checks passed. ServerMonitorDashboard — the primary problem app — reported `ALL CHECKS PASSED` with no 500.34 error.

### Phase 4 — Health Verification (19:41)

All 6 apps confirmed healthy via HTTP:

| App | Endpoint | Status |
|-----|----------|--------|
| DedgeAuth | `/DedgeAuth/health` | 200 |
| DocView | `/DocView/` | 302 → login |
| AutoDocJson | `/AutoDocJson/` | 302 → login |
| GenericLogHandler | `/GenericLogHandler/` | 200 |
| ServerMonitorDashboard | `/ServerMonitorDashboard/api/IsAlive` | 200 |
| AutoDoc | `/AutoDoc/` | 200 |

### Phase 5 — Browser Visual Verification (19:41 – 19:43)

Used cursor-ide-browser MCP tools to visually verify each app:

| App | URL | Tenant CSS | User Menu | Status |
|-----|-----|------------|-----------|--------|
| DedgeAuth Login | `/DedgeAuth/login.html` | N/A | N/A | PASS |
| DedgeAuth Admin | `/DedgeAuth/admin.html` | N/A | N/A | PASS |
| DocView | `/DocView/` | YES | YES | PASS |
| GenericLogHandler | `/GenericLogHandler/` | YES | — | PASS |
| ServerMonitorDashboard | `/ServerMonitorDashboard/` | YES | YES | PASS |
| AutoDocJson | `/AutoDocJson/` | YES | YES | PASS |

### Phase 6 — GrabScreenShot Verification (19:43 – 19:45)

Ran `Invoke-GrabScreenShot.ps1`:

- 6 screenshots captured to `C:\temp\screenshots\`
- Report generated at `C:\temp\screenshots\REPORT.txt`
- Email sent to `geir.helge.starholm@Dedge.no` with all screenshots attached
- SMS sent to `+4797188358`: "GrabScreenShot: 6 apps, ALL PASS. 68,8s. Email sent."

**Result: ALL PASS**

### Phase 7 — Fix Tenant Logo and Favicon (20:00 – 20:30)

User reported broken logo image and missing favicon on the login page.

**Root cause:** The `login.html` and `admin.html` used absolute paths like `/tenants/Dedge.no/logo` for the tenant logo endpoint. Under the IIS virtual app `/DedgeAuth/`, these resolve to `http://localhost/tenants/...` (non-existent) instead of `http://localhost/DedgeAuth/tenants/...`.

**Fixes applied in `login.html`:**

| Location | Before | After |
|----------|--------|-------|
| Tenant CSS href (line 663) | `` `/tenants/${domain}/theme.css` `` | `` `${basePath}/tenants/${domain}/theme.css` `` |
| Tenant logo URL (line 668) | `` `/tenants/${domain}/logo` `` | `` `${basePath}/tenants/${domain}/logo` `` |
| Success page logo (line 1027) | `` '/tenants/Dedge.no/logo' `` | `` basePath + '/tenants/Dedge.no/logo' `` |
| Branding logo (line 1432) | `` `/tenants/${domain}/logo` `` | `` `${basePath}/tenants/${domain}/logo` `` |
| Branding CSS (line 1442) | `` `/tenants/${domain}/theme.css` `` | `` `${basePath}/tenants/${domain}/theme.css` `` |

**Favicon added:**
- Added `<link id="tenant-favicon" rel="icon" type="image/png" href="">` in `<head>` of both `login.html` and `admin.html`
- Added JS to set `tenant-favicon.href = effectiveLogoUrl` when tenant config loads

**Verified:** Full rebuild via `Build-And-Publish-ALL.ps1` + `IIS-RedeployAll.ps1` → logo displays correctly, favicon appears in browser tab.

### Phase 8 — Commit and Push (20:30 – 20:35)

Committed and pushed all 6 projects:

| Project | Commit | Message |
|---------|--------|---------|
| **DedgeAuth** | `9398e4f` | Fix tenant logo and favicon for IIS virtual app hosting |
| **DedgePsh** | `5c4efdb2` | Fix IIS-Handler appcmd prefix-match bug that deleted root app |
| **DocView** | `171fdad` | Enable Debug logging for local workstation troubleshooting |
| **AutoDocJson** | `8c43fdb` | Enable Debug logging for local workstation troubleshooting |
| **GenericLogHandler** | `af8c386` | Enable Debug logging for local workstation troubleshooting |
| **ServerMonitor** | `5a13ed6` | Enable Debug logging for local workstation troubleshooting |

All pushed to `main` branch on Azure DevOps (and GitHub for AutoDocJson).

---

## Bugs Found and Fixed

### Bug 1: IIS-Handler `appcmd` Prefix-Match Root App Deletion

| Field | Detail |
|-------|--------|
| **Severity** | Critical — causes all apps to be unreachable |
| **File** | `C:\opt\src\DedgePsh\_Modules\IIS-Handler\IIS-Handler.psm1` |
| **Function** | `Deploy-IISSite`, Step 1b teardown |
| **Symptom** | `IIS-RedeployAll.ps1` completes but all health checks fail with "connection refused on port 80". Default Web Site shows state `Unknown`. |
| **Root cause** | `appcmd list app /app.name:"Default Web Site/DocView"` performs prefix matching. When DocView's virtual app doesn't exist yet (fresh deployment), it returns `APP "Default Web Site/"` — the root app. The code deleted this, removing the "/" application and corrupting the site. |
| **Fix** | Added comparison guard: after extracting the matched app ID, verify it equals the intended target before deleting. If it's a prefix match (e.g., root "/" matched instead of "/DocView"), skip the deletion and log a warning. |
| **Verification** | Clean `IIS-RedeployAll.ps1` run shows 6 WARN messages (prefix-match skipped) and all 7 apps deploy successfully. |

### Bug 2: Tenant Logo Broken Under IIS Virtual App

| Field | Detail |
|-------|--------|
| **Severity** | Medium — logo not displayed, favicon missing |
| **Files** | `login.html`, `admin.html` in `DedgeAuth.Api/wwwroot/` |
| **Symptom** | Logo shows alt text "Dedge Logo" instead of the image. Browser tab shows generic globe icon. |
| **Root cause** | Absolute paths like `/tenants/Dedge.no/logo` resolve to the wrong URL under IIS virtual app `/DedgeAuth/`. Should be `/DedgeAuth/tenants/...`. The `basePath` variable was already computed correctly but wasn't being used for tenant endpoint URLs. |
| **Fix** | Prefixed all `/tenants/...` URLs with `${basePath}`. Added `<link id="tenant-favicon">` and JS to set it from the tenant logo endpoint. |
| **Verification** | Browser test confirmed logo loads correctly from database, favicon appears in browser tab. |

---

## Notifications Sent

| Time | Type | Recipient | Message |
|------|------|-----------|---------|
| 19:33 | SMS | +4797188358 | "DedgeAuth local setup: Build ALL 5/5 OK. IIS deploy done. 6/6 apps responding. Fixing IIS-Handler root app bug. Next: browser test." |
| 19:43 | SMS | +4797188358 | Browser verification complete (via browser-use agent) |
| 19:45 | Email | geir.helge.starholm@Dedge.no | Full verification report with 6 screenshots |
| 19:45 | SMS | +4797188358 | "GrabScreenShot: 6 apps, ALL PASS. 68,8s. Email sent." |

---

## Final State

```
IIS (port 80, Default Web Site) — STARTED
  ├── /DedgeAuth                  → DedgeAuth.Api          [HEALTHY] App pool: DedgeAuth
  ├── /DocView                 → DocView             [HEALTHY] App pool: DocView
  ├── /AutoDocJson             → AutoDocJson         [HEALTHY] App pool: AutoDocJson
  ├── /GenericLogHandler       → GenericLogHandler   [HEALTHY] App pool: GenericLogHandler
  ├── /ServerMonitorDashboard  → ServerMonitorDashboard [HEALTHY] App pool: ServerMonitorDashboard
  └── /AutoDoc                 → AutoDoc (static)    [HEALTHY] App pool: AutoDoc
```

- All app pools running as `DEDGE\FKGEISTA` (AD-enrolled user with UNC share access)
- Each ASP.NET Core app has its own dedicated app pool (prevents 500.34/500.35)
- Database: `t-no1fkxtst-db:8432` (remote PostgreSQL, unchanged)
- Authentication: JWT via DedgeAuth, working for all consumer apps
- Tenant CSS: Injected dynamically from database
- Tenant logo: Served from database, displayed on login page and as favicon
- Debug logging: Enabled in all 4 consumer apps

---

## Files Changed

| File | Project | Change |
|------|---------|--------|
| `src/DedgeAuth.Api/wwwroot/login.html` | DedgeAuth | Fix logo/tenant URLs to use basePath, add favicon |
| `src/DedgeAuth.Api/wwwroot/admin.html` | DedgeAuth | Fix logo preview URL, add favicon |
| `docs/Local-Workstation-Setup.md` | DedgeAuth | New — full local setup documentation |
| `_Modules/IIS-Handler/IIS-Handler.psm1` | DedgePsh | Fix appcmd prefix-match root app deletion bug |
| `appsettings.json` | DocView | LogLevel → Debug |
| `AutoDocJson.Web/appsettings.json` | AutoDocJson | LogLevel → Debug |
| `src/GenericLogHandler.WebApi/appsettings.json` | GenericLogHandler | LogLevel → Debug |
| `ServerMonitorDashboard/src/ServerMonitorDashboard/appsettings.json` | ServerMonitor | LogLevel → Debug |
