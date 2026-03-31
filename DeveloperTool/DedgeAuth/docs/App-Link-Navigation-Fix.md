# App Link Navigation Fix

**Date:** 2026-03-22  
**Version:** 1.0.164  
**Issue:** Clicking app buttons on DedgeAuth login page redirected to a new DedgeAuth login page instead of opening the target app.

## Root Cause Analysis

### Problem
When a user logged in via Windows SSO (Kerberos) on the DedgeAuth login page and clicked an app link (e.g. DocView, GenericLogHandler), a new DedgeAuth login page opened instead of the target application.

### Investigation Findings

1. **Deployed code was stale:** The `Build-And-Publish.ps1` script correctly pushed files to the staging share (`C:\opt\src\DedgeSrc\DedgeSystemTools\Folders\DedgeCommon\Software\DedgeWinApps\DedgeAuth`), but `IIS-DeployApp.ps1` was not run afterward, leaving the IIS install path (`opt\DedgeWinApps\DedgeAuth`) with old code.

2. **Cookie path issue:** `SetRefreshTokenCookie` in `AuthController.cs` did not explicitly set the `Path` attribute, causing the browser to default to the API endpoint path (`/DedgeAuth/api/auth`). Subsequent requests to other paths under `/DedgeAuth/` did not include the cookie.

3. **Refresh token rotation problem:** The `AuthService.RefreshTokenAsync` method rotates (revokes old, creates new) refresh tokens. When the redirect endpoint used this for multi-click app navigation, the first click consumed the token and subsequent clicks failed.

4. **Cross-tab cookie issues:** The original `navigateWithFreshCode` approach opened a new tab via `window.open(url, '_blank')`. Cookies set in the original tab were not reliably sent with requests in the new tab, especially in non-standard browser environments.

5. **Async onclick handler:** The `async function navigateWithFreshCode` returned a Promise from `onclick="return ..."`, but `event.preventDefault()` was correctly called synchronously. However, the `window.open('about:blank', '_blank')` + `newTab.location.href = URL` pattern did not work reliably across all browsers.

## Changes Made

### `AuthController.cs`

- **`SetRefreshTokenCookie`:** Explicitly set `Path = Request.PathBase.Value` (resolves to `/DedgeAuth` under IIS virtual app) and changed `SameSite` from `Strict` to `Lax` for better cross-tab compatibility.
- **`Response.Cookies.Delete("refreshToken")`:** Added explicit `Path` to match the cookie being deleted.
- **`POST /api/auth/create-code`:** Existing endpoint (added in v1.0.157) that creates a single-use auth code from a valid JWT. Used by the new `openApp` function.
- **`GET /api/auth/redirect`:** Added `[AllowAnonymous]` server-side redirect endpoint that authenticates via cookies (`DedgeAuth_jwt` or `refreshToken`) and 302-redirects to the consumer app with `?code=CODE`. Falls back to login page if no valid auth found.

### `AuthService.cs`

- **`ValidateRefreshTokenUserAsync`:** New method that validates a refresh token and returns the user ID WITHOUT revoking or rotating the token. Used by the redirect endpoint for non-destructive multi-click support.

### `login.html`

- **`storeAccessToken(token)`:** New function that stores the JWT in both `localStorage` and a non-HttpOnly cookie (`DedgeAuth_jwt`) with `path=/DedgeAuth` and `max-age=1800`. The cookie enables the server-side redirect endpoint to authenticate without requiring an `Authorization` header.
- **`clearAccessToken()`:** Companion function that removes the JWT from both storage locations.
- **`openApp(event, targetUrl)`:** Replaced `navigateWithFreshCode`. Generates a fresh auth code via `POST /api/auth/create-code` using the JWT from `localStorage`, then navigates the current tab to `targetUrl?code=CODE`. Falls back to the server-side redirect endpoint if code creation fails.
- **`renderAppLink`:** Changed from `<a href="URL" target="_blank" onclick="return navigateWithFreshCode(...)">` to `<a href="javascript:void(0)" onclick="openApp(...)">`. Same-tab navigation eliminates cross-tab cookie issues and popup blocker interference.
- **`tryLocalTokenRedirect`:** Added auto-redirect when the login page loads with a `returnUrl` and a valid JWT exists in `localStorage`. Seamlessly forwards the user to the consumer app without showing the login form.
- **`tryAutoKerberos` enhancement:** Checks if the existing JWT in `localStorage` is expired before skipping SSO. If expired, clears the token to allow Windows SSO to re-authenticate.

## Authentication Flow for App Links

```
User clicks app link on DedgeAuth login page
    │
    ▼
openApp() reads JWT from localStorage
    │
    ├─ JWT exists → POST /api/auth/create-code (Bearer JWT)
    │                  │
    │                  ├─ 200 OK → window.location.href = AppUrl?code=CODE
    │                  │             └─ Consumer app exchanges code → authenticated
    │                  │
    │                  └─ 401 → fallback to server-side redirect
    │                             └─ GET /DedgeAuth/api/auth/redirect?returnUrl=AppUrl
    │                                  └─ Authenticates via cookies → 302 to AppUrl?code=CODE
    │
    └─ No JWT → fallback to server-side redirect
                  └─ If no cookies either → redirects to login page
                       └─ tryLocalTokenRedirect or tryAutoKerberos → auto-login → redirect
```

## Deployment Notes

- `Build-And-Publish.ps1` publishes to staging share but does NOT deploy to IIS.
- `IIS-DeployApp.ps1 -SiteName DedgeAuth` must be run AFTER to copy from staging to IIS install path.
- The `login.html` file can be updated via UNC without stopping the app pool (it's static content, not a locked DLL).
- DLL updates require stopping the app pool first (done automatically by `IIS-DeployApp.ps1`).

## Testing

- **API test:** `create-code` endpoint returns valid auth codes on both localhost and `dedge-server`.
- **Browser test (localhost):** Clicking GenericLogHandler link navigated directly to the app dashboard without any DedgeAuth login redirect. Full FK Green styling, user menu, and log entries visible.
- **Server test (dedge-server):** `login.html` updated via UNC. `create-code` → DocView code exchange → 302 to clean URL confirmed via PowerShell.
