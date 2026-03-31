# IIS-DeployApp Log Analysis – 2026-02-17

**Log file:** `dedge-server.DEDGE.fk.no\opt\data\IIS-DeployApp\FkLog_20260217.log`  
**Server:** dedge-server  
**User:** DEDGE\FKTSTADM  

---

## Summary

IIS-RedeployAll and IIS-DeployApp ran multiple times on 2026-02-17. **Redeploy completed with 1 failure** each time: **AutoDocJson** deploy failed because the API did not respond after deployment, and post-deploy checks reported failures. Additional issues observed: app pool delete warnings, **DefaultWebSite** uninstall not found, and repeated **“Must use exact identifier for APP object with verb DELETE”** during teardown.

---

## 1. Primary failure: AutoDocJson deploy

| Time       | Severity | Component     | Message |
|-----------|----------|---------------|--------|
| 10:00:38  | ERROR    | Deploy-IISSite | API did not respond on any endpoint. Check logs at: E:\opt\DedgeWinApps\AutoDocJson\logs |
| 10:00:39  | ERROR    | Deploy-IISSite | Result: SOME CHECKS FAILED -- review errors above |
| 10:00:40  | FATAL    | IIS-Handler   | DEPLOY FAILED: Deployment completed with errors |
| 10:00:40  | JOB_FAILED | IIS-DeployApp | IIS-DeployApp.ps1 |

**What went wrong**

- After deploying AutoDocJson (files, app pool, virtual app, web.config), the post-deploy health check failed: the API did not respond on any of the expected endpoints.
- Test-IISSite then reported: **30 error/warning event(s) for AutoDocJson** in the Event Log and **stdout logging – Disabled** (startup errors not visible in stdout).
- Outcome: Deploy is treated as failed, so IIS-RedeployAll reports “Redeploy completed with 1 failure(s)” and JOB_FAILED.

**Recommended actions**

1. On **dedge-server**, check application logs: **E:\opt\DedgeWinApps\AutoDocJson\logs**.
2. In **Event Viewer**, filter by source/application for **AutoDocJson** (or the app pool name) and review the 30 error/warning events.
3. Enable **stdout logging** for the AutoDocJson app pool or the app’s `web.config` so startup exceptions are written to a log file and easier to diagnose.
4. Confirm the app runs locally (e.g. run the published app from a command prompt and hit the same URLs/ports used by the health check).

---

## 2. “Must use exact identifier for APP object with verb DELETE”

| Time       | Severity | Component     | Message |
|-----------|----------|---------------|--------|
| 10:00:14, 10:00:26, 10:01:47, … | WARN | Deploy-IISSite (line 2271) | Delete virtual app failed: ERROR ( message:Must use exact identifer for APP object with verb DELETE. ) |

**What went wrong**

- During the **teardown** step of Deploy-IISSite (before recreating the virtual app), `appcmd delete app` failed with “Must use exact identifer for APP object with verb DELETE”.
- The handler builds the app identifier as `$ParentSite$VirtualPath` (e.g. `Default Web Site/AutoDocJson`). If the string passed to `appcmd` does not match the exact app name as reported by `appcmd list app`, DELETE fails with this error.

**Recommended actions**

1. On the server, run:  
   `%SystemRoot%\System32\inetsrv\appcmd list app`  
   and note the **exact** APP names (e.g. `Default Web Site/AutoDocJson`).
2. Ensure the deploy template uses **ParentSite** and **VirtualPath** so that `ParentSite + VirtualPath` matches that exact app name (including spaces and slashes). For the root app it must be `Default Web Site/` (with trailing slash).
3. In IIS-Handler, consider normalizing or validating the app identifier (e.g. trim, single slash between site and path) before calling `appcmd delete app`.

---

## 3. DefaultWebSite uninstall: “No site or virtual app matching 'DefaultWebSite' found”

| Time     | Severity | Component      | Message |
|----------|----------|----------------|--------|
| 09:59:44, 10:32:35, 12:43:58 | ERROR | Uninstall-IISApp (line 1215) | No site or virtual app matching 'DefaultWebSite' found. |

**What went wrong**

- IIS-RedeployAll uninstalls the **DefaultWebSite** profile by calling IIS-UninstallApp with **SiteName = DefaultWebSite**.
- In IIS, the site name is **“Default Web Site”** (with a space), and the root application is **“Default Web Site/”**. Uninstall-IISApp looks up by the profile name **DefaultWebSite** (no space), so it does not find the site or the app and logs ERROR.

**Recommended actions**

1. In **IIS-UninstallApp** / **Get-IISEntries** (or equivalent): when resolving the target for the DefaultWebSite profile, map **SiteName = DefaultWebSite** to the actual IIS site name **“Default Web Site”** and the app **“Default Web Site/”** so uninstall finds and removes the correct object (or skip uninstall of the root site if that is the intended design).
2. Alternatively, document that the DefaultWebSite profile is not uninstalled by RedeployAll and only apps under the site are uninstalled.

---

## 4. App pool delete: “Cannot find APPPOOL object with identifier 'ServerMonitorDashboard'”

| Time     | Severity | Component     | Message |
|----------|----------|---------------|--------|
| 09:59:01 | WARN     | Remove-AppPool (line 1283) | App pool delete result: ERROR ( message:Cannot find APPPOOL object with identifier "ServerMonitorDashboard". ) |

**What went wrong**

- After removing the virtual app **Default Web Site/ServerMonitorDashboard**, the script tried to delete the app pool **ServerMonitorDashboard**.
- By the time `appcmd delete apppool` ran, the pool no longer existed (e.g. already deleted or named differently), so appcmd returned “Cannot find APPPOOL object”.

**Impact**

- Non-fatal: virtual app and firewall rules were removed; only the pool delete failed. Redeploy can create a new pool.

**Recommended actions**

1. Treat “Cannot find APPPOOL” after a successful app removal as **non-fatal** (e.g. log as INFO or WARN and continue), since the desired state (pool removed) is already satisfied.
2. Optionally check that the pool exists before calling `appcmd delete apppool`, to avoid the ERROR message.

---

## 5. Timeline (simplified)

| Time       | Event |
|------------|--------|
| 09:58:43   | IIS-RedeployAll started (Phase 1: Uninstall). |
| 09:58:44–09:59:44 | Uninstall of apps (ServerMonitorDashboard, GenericLogHandler, …). ServerMonitorDashboard app pool already missing when delete attempted. |
| 09:59:44   | Uninstall DefaultWebSite: ERROR – no site/virtual app matching 'DefaultWebSite'. |
| 10:00:05   | Phase 3: Redeploy – DefaultWebSite, AutoDoc, then AutoDocJson. |
| 10:00:14–10:01:47 | Multiple “Delete virtual app failed: Must use exact identifier” during deploy teardowns. |
| 10:00:38   | AutoDocJson: API did not respond; SOME CHECKS FAILED; DEPLOY FAILED. |
| 10:00:40   | IIS-DeployApp JOB_FAILED. |
| 10:00:49   | Test-IISSite for AutoDocJson: 20 passed, 7 warnings, 1 failed; “Failed to deploy AutoDocJson: Diagnostics completed with 1 failure(s)”. |
| 10:02:01   | IIS-RedeployAll JOB_FAILED – “Redeploy completed with 1 failure(s)”. |
| 10:31:41, 12:43:58 | Later runs: same DefaultWebSite uninstall error and AutoDocJson deploy/health-check failure pattern. |

---

## 6. Recommended next steps (priority)

1. **Fix AutoDocJson on dedge-server**  
   - Inspect **E:\opt\DedgeWinApps\AutoDocJson\logs** and Event Log.  
   - Enable stdout/logging to capture startup errors.  
   - Fix configuration or runtime issue so the API responds on the expected endpoints.

2. **Fix app delete identifier**  
   - Ensure deploy/teardown uses the exact app name from `appcmd list app` when calling `appcmd delete app` (align ParentSite + VirtualPath with IIS).

3. **DefaultWebSite uninstall**  
   - Map profile name **DefaultWebSite** to IIS site **“Default Web Site”** (and app **“Default Web Site/”**) in uninstall logic, or document that root site is not uninstalled.

4. **App pool delete**  
   - Treat “Cannot find APPPOOL” after successful app removal as non-fatal or check for pool existence before delete.

---

*Generated from FkLog_20260217.log.*
