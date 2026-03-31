# IIS Incident Analysis — 2026-03-18

**Author:** Geir Helge Starholm, www.dEdge.no
**Date:** 2026-03-18
**Server:** dedge-server
**Triggered by:** Agent investigation after user reported IIS/DedgeAuth failures

---

## Summary

DedgeAuth and all consumer apps were affected by two distinct issues: a **masking bug** in the health check function that silently treated HTTP 500 as success, and a **Windows Authentication conflict** in the DedgeAuth application that caused it to crash after every `iisreset`.

The previous IIS-RedeployAll run (22:09) falsely reported "All 11 site(s)/app(s) redeployed successfully" while DedgeAuth was returning HTTP 500. After fixes were deployed, the system now correctly reports failures, and DedgeAuth was restored to HTTP 200.

---

## Timeline

| Time | Event |
|------|-------|
| 14:11 | Single DedgeAuth deploy via orchestrator — health check HTTP 200 (OK) |
| 21:43 | IIS-RedeployAll run — DedgeAuth service failed to start, health returned HTTP 500 |
| 22:05 | DedgeAuth health check HTTP 500, but old `Test-HealthUrl` reported it as `[OK]` |
| 22:09 | RedeployAll falsely reported "All 11 redeployed successfully" (exit 0) |
| 23:19 | Agent ran RedeployAll with fixed `Test-HealthUrl` — correctly reported 2 failures (exit 2) |
| 23:28 | DedgeAuth deploy correctly failed — `[FAIL] Health: HTTP 500 (server error)` |
| 23:38 | RedeployAll completed — 9/11 apps deployed, 2 failures (DedgeAuth, CursorDb2McpServer) |
| 23:42 | Agent fixed DedgeAuth: enabled Windows Auth on virtual app, disabled conflicting service |
| 23:43 | DedgeAuth health check returned HTTP 200 — **FIXED** |

---

## Root Cause 1: `Test-HealthUrl` masking bug (pre-existing)

**File:** `_Modules/IIS-Handler/IIS-Handler.psm1`, function `Test-HealthUrl`

The health check function treated ANY non-404 HTTP response as success:

```powershell
# OLD (broken) — returned $true for HTTP 500, 503, etc.
return ($statusCode -ne 404)
```

This meant HTTP 500 (Internal Server Error) was logged as `[OK]` and counted as a pass, completely masking broken applications.

**Fix applied:**

```powershell
# NEW (fixed) — 5xx = FAIL, 404 = FAIL, 4xx = conditional
if ($statusCode -ge 500) {
    Write-LogMessage "[FAIL] ... HTTP $statusCode (server error)" -Level ERROR
    return $false
}
elseif ($statusCode -eq 404) {
    Write-LogMessage "[WARN] ... HTTP 404 (not found)" -Level WARN
    return $false
}
else {
    return ($statusCode -lt 400)
}
```

---

## Root Cause 2: DedgeAuth Negotiate Authentication crash

**Error:** `System.InvalidOperationException: The Negotiate Authentication handler cannot be used on a server that directly supports Windows Authentication.`

**Mechanism:** The DedgeAuth ASP.NET Core app uses `.AddNegotiate()` for Windows authentication. When running under IIS in-process mode, IIS must have Windows Authentication **enabled** on the virtual app, so the Negotiate handler can defer to IIS. After `iisreset` (run by IIS-RedeployAll Phase 2), IIS authentication settings reset to defaults. The Deploy-IISSite function recreates the virtual app but does **not** configure Windows Authentication, leaving it in the default (disabled) state. The DedgeAuth app then crashes on startup because Negotiate cannot work without IIS Windows Auth.

**Fix applied (immediate):**

```powershell
appcmd set config "Default Web Site/DedgeAuth" `
    /section:system.webServer/security/authentication/windowsAuthentication `
    /enabled:true /commit:apphost
```

**Permanent fix needed:** The `DedgeAuth_WinApp.deploy.json` template should declare a `"WindowsAuthentication": true` property, and `Deploy-IISSite` should configure it during Step 4 or Step 6b.

---

## Monday Changes Analysis (commits `0ed701fb` and `b715bf38`, 2026-03-16)

Two commits by FKMISTA introduced changes to IIS-RedeployAll.ps1 and IIS-Handler.psm1:

| Change | Assessment |
|--------|------------|
| `Invoke-ChildScript` pattern (spawns child pwsh.exe per deploy) | **Valid** — prevents child `exit 1` from killing parent script |
| Team user detection for staging server | **Valid** — correctly routes to test server for team users |
| `SkipInstall` / `DeployTray` parameters | **Valid** — adds flexibility |
| Template-not-found changed from WARN to throw | **Valid but stricter** — prevents silent fallback to broken defaults |
| AutoDocJson port 5280→8283, AgriNxt port 5123→8500 | **Neutral** — port reassignment |
| `try/finally` wrapper for `Reset-OverrideAppDataFolder` | **Valid** — ensures cleanup on error |

**Conclusion:** The Monday changes did NOT cause the DedgeAuth failure. The root causes were pre-existing (Test-HealthUrl) and environmental (Windows Auth not configured after iisreset).

---

## Final App Status — dedge-server (2026-03-18 23:43)

| App | Status | Health | Notes |
|-----|--------|--------|-------|
| DefaultWebSite | DEPLOYED | N/A (static redirect) | Root site redirect to /DedgeAuth/ |
| AgriNxt.GrainDryingDeduction | DEPLOYED | HTTP 200 | Port 8500 |
| AiDocNew | DEPLOYED | OK | New template |
| AutoDocJson | DEPLOYED | HTTP 200 | Port 8283 (changed from 5280) |
| CursorDb2McpServer | **FAILED** | HTTP 406/404 | MCP SSE server — no standard health endpoints |
| DocView | DEPLOYED | HTTP 200 | Port 8282 |
| **DedgeAuth** | **FIXED** | **HTTP 200** | Windows Auth enabled post-deploy, service disabled |
| GenericLogHandler | DEPLOYED | HTTP 200 | Port 8110 |
| GitHist | DEPLOYED | OK | Static site |
| ServerMonitorDashboard | DEPLOYED | HTTP 200 | Port 8998 |
| SystemAnalyzer | DEPLOYED | HTTP 200 | Port 8790 |

---

## How to Prevent This in the Future

### 1. Never treat HTTP 5xx as success

The `Test-HealthUrl` fix is now deployed. Any HTTP 500+ response correctly reports `[FAIL]` and causes the deploy to fail. This ensures broken apps are never silently accepted.

### 2. DedgeAuth template must declare authentication requirements

Add `"WindowsAuthentication": true` to `DedgeAuth_WinApp.deploy.json` and implement the corresponding appcmd call in `Deploy-IISSite` Step 6b. This ensures Windows Auth is re-enabled after every `iisreset` + redeploy cycle.

### 3. Always verify health after RedeployAll

After running `IIS-RedeployAll.ps1`, check the exit code. Non-zero means at least one app failed. Read the log file for `[FAIL]` and `[ERROR]` entries to identify which apps need attention.

### 4. Test changes on single app before full redeploy

Use `IIS-DeployApp.ps1 -SiteName <name>` to test a single app deploy before running `IIS-RedeployAll.ps1`. This isolates failures to the specific app being changed.

### 5. Run GrabScreenShot after every deploy

The browser verification report (`Invoke-GrabScreenShot.ps1`) catches visual failures that health checks alone miss. Always run it as the final step.

---

## Open Items

- [x] Add `"WindowsAuthentication": true` to `DedgeAuth_WinApp.deploy.json` — **DONE 2026-03-18**
- [x] Implement Windows Auth configuration in `Deploy-IISSite` Step 6c — **DONE 2026-03-18**
- [x] Set `"AllowAnonymousAccess": false` in DedgeAuth template to prevent Step 6b from disabling Windows Auth — **DONE 2026-03-18**
- [ ] Investigate CursorDb2McpServer health check approach (MCP SSE servers don't expose `/health`)
- [ ] Consider adding DedgeAuth service mode detection to skip Negotiate when not under IIS
