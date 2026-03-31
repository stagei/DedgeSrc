# Windows Authentication Discovery Log

This document is an append-only log of discoveries, issues, and decisions related to Windows/Kerberos authentication in DedgeAuth. New entries are added at the end — existing entries are never modified.

---

## 2026-03-22 22:30 — Initial Discovery: Daily Windows Security Dialog

**Reporter**: FKGEISTA (Geir Helge Starholm)

**Symptom**: Every day when visiting `http://dedge-server/DedgeAuth/login.html` and clicking "Sign in with Windows", a Windows Security dialog appears asking for Email address and Password. The dialog cannot save credentials, requiring manual entry every session.

**Screenshot**: `assets/image-ab7a961e-8319-4cbc-a360-46fac6655f06.png`

---

## 2026-03-22 22:35 — Root Cause: PC Not Domain-Joined

**Finding**: The developer PC (30237-FK) is **not joined to the DEDGE domain**. This means:

- No Kerberos TGT (Ticket Granting Ticket) is ever issued automatically
- The `klist` command confirms: `[WARN] No Kerberos TGT found`
- Browser Kerberos policies are correctly configured (AuthServerAllowlist set for Chrome, Edge, Chromium)
- DNS resolves correctly: `dedge-server -> 10.33.103.137`

**Registry policies verified (all OK)**:

| Browser | Registry Path | AuthServerAllowlist |
|---------|--------------|---------------------|
| Chrome | `HKLM:\SOFTWARE\Policies\Google\Chrome` | `dedge-server,*.DEDGE.fk.no` |
| Edge | `HKLM:\SOFTWARE\Policies\Microsoft\Edge` | `dedge-server,*.DEDGE.fk.no` |
| Chromium | `HKLM:\SOFTWARE\Policies\Chromium` | `dedge-server,*.DEDGE.fk.no` |

**Intranet zone**: `http://dedge-server` added to Local Intranet (zone 1)

**Conclusion**: The policies are irrelevant without a Kerberos ticket to send. The PC will never have a TGT because it's not domain-joined.

---

## 2026-03-22 22:40 — How the Two Windows Auth Endpoints Work

DedgeAuth has two distinct Windows authentication endpoints with different behaviors:

### 1. Silent Probe: `GET /api/auth/windows-probe`

- **Attribute**: `[AllowAnonymous]` — server never sends a 401 challenge
- **Called**: Automatically on page load by `tryAutoKerberos()` in `login.html`
- **Behavior**: If the browser has a valid Kerberos ticket, IIS passes it through and login succeeds silently. If not, returns `{ success: false, windowsAuthAvailable: false }` and the login form is shown normally.
- **Dialog**: Never triggers a Windows Security dialog
- **Purpose**: Seamless auto-login for domain-joined PCs

### 2. Manual Login: `GET /api/auth/windows-login`

- **Attribute**: `[Authorize(Policy = "WindowsAuth")]` — forces a 401 Negotiate challenge
- **Called**: When user clicks the "Sign in with Windows" button
- **Behavior**: IIS responds with 401 + `WWW-Authenticate: Negotiate`. Browser attempts Kerberos first; if no TGT available, falls back to showing the Windows Security credential dialog for manual NTLM entry.
- **Dialog**: Triggers the Windows Security dialog on non-domain PCs
- **Purpose**: Fallback for manual Windows credential entry

### Flow on a non-domain PC:

```
Page load
  → tryAutoKerberos() calls /windows-probe
  → No Kerberos ticket → returns windowsAuthAvailable: false
  → Login form shown, Windows button slightly dimmed

User clicks "Sign in with Windows"
  → Calls /windows-login
  → IIS sends 401 Negotiate challenge
  → Browser has no Kerberos ticket
  → Falls back to showing Windows Security dialog
  → User enters DEDGE\username + password manually
  → NTLM authentication succeeds
  → DedgeAuth resolves real AD email via LDAP
  → User logged in
```

### Flow on a domain-joined PC (intended seamless experience):

```
Page load
  → tryAutoKerberos() calls /windows-probe
  → Browser has valid Kerberos TGT
  → IIS passes ticket through (AllowAnonymous, no challenge)
  → DedgeAuth authenticates, resolves AD email
  → User auto-logged in — login form never shown
```

---

## 2026-03-22 22:45 — Why the Dialog Cannot Save Credentials

The "Windows Security" dialog is a **browser-level HTTP authentication prompt** (Negotiate/NTLM), not a web form. Key differences:

- Web forms (`<input type="password">`) can be saved by browser password managers
- HTTP auth prompts (401 Negotiate challenges) are handled by the browser's networking layer, outside the password manager's reach
- Edge/Chrome intentionally do not persist Negotiate/NTLM credentials across sessions for security reasons
- Each new browser session starts without cached NTLM credentials

This is by design in Chromium-based browsers and cannot be changed by DedgeAuth code.

---

## 2026-03-22 22:50 — Available Workarounds for Non-Domain PCs

| Option | Description | Daily Effort | Implementation |
|--------|-------------|-------------|----------------|
| **Email/password login** | Use existing DedgeAuth email + password instead of Windows button | Type email + password once per session | Already works, no changes needed |
| **Remember Me (long-lived refresh token)** | Extend refresh token cookie lifetime (e.g., 30 days). `tryAutoRefresh()` on page load would silently re-authenticate | None after first login (auto-refresh) | Requires code change in AuthService + login.html |
| **`runas /netonly`** | Run `runas /netonly /user:DEDGE\FKGEISTA cmd` then launch Edge from that session | Run runas command once per session | No code changes, but inconvenient |
| **Hide Windows button** | When `windowsAuthAvailable: false`, completely hide the "Sign in with Windows" button | N/A (button removed) | Minor JS change in login.html |

---

## 2026-03-22 22:55 — Relevant Source Files

| File | Role |
|------|------|
| `src/DedgeAuth.Api/Controllers/AuthController.cs` | `WindowsProbe()` (line 134) and `WindowsLogin()` (line 260) endpoints |
| `src/DedgeAuth.Api/wwwroot/login.html` | `tryAutoKerberos()` (line 1207), Windows button click handler (line 1253) |
| `src/DedgeAuth.Services/AuthService.cs` | `LoginWithWindowsAsync()` — AD lookup, user creation/update |
| `scripts/Enable-KerberosForBrowser.ps1` | Registry policy configuration for Chrome/Edge/Chromium |
| `docs/Windows-Kerberos-Auto-Login-Plan.md` | Full design document for Windows SSO feature |
| `docs/DedgeAuth-Authentication-Flow.md` | Mermaid diagrams for all auth flows including Windows/Kerberos |

---

## 2026-03-22 22:55 — IIS Configuration on dedge-server

From the latest deploy log (IIS-DeployApp at 22:03):

- **App Pool Identity**: `DEDGE\t1_srv_fkxtst_app` (domain service account)
- **Windows Authentication**: Enabled with `useAppPoolCredentials: true`
- **Anonymous Authentication**: Also enabled (required for the `[AllowAnonymous]` probe endpoint)
- **Health check**: `http://localhost/DedgeAuth/health` → HTTP 200

The `useAppPoolCredentials: true` setting was added to fix a `SEC_E_WRONG_PRINCIPAL` Kerberos error. It instructs HTTP.sys to pass Kerberos tickets to the app pool process for decryption using the domain service account's credentials, rather than the machine account.

---

## 2026-03-22 22:55 — Tenant SSO Configuration

From `Windows-Kerberos-Auto-Login-Plan.md`:

- `Dedge.no` tenant has `windows_sso_enabled = true`
- Windows/Kerberos users on this tenant are auto-registered, auto-approved, get implicit minimum app access
- Other tenants default to `windows_sso_enabled = false` — Windows identity recognized but user redirected to registration

---

## 2026-03-22 23:00 — Confirmed: Developer PC Not Domain-Joined

**Finding**: Developer PC (30237-FK) is confirmed **not domain-joined**. This means:

- Kerberos TGT will never be issued automatically by the OS
- The `Enable-KerberosForBrowser.ps1` registry policies are correctly set but have no effect without a ticket
- The silent `tryAutoKerberos()` probe on page load will always return `windowsAuthAvailable: false`
- Clicking "Sign in with Windows" will always trigger the manual NTLM credential dialog
- This is the expected and permanent behavior for this machine

---

## 2026-03-22 23:05 — Token Lifetimes and Local Storage Locations

### Token Lifetimes (defaults from `AuthConfiguration.cs`)

| Token Type | Lifetime | Default | Config Key |
|------------|----------|---------|------------|
| **JWT Access Token** | Minutes | **30 minutes** | `AccessTokenExpirationMinutes` |
| **Refresh Token** | Days | **7 days** | `RefreshTokenExpirationDays` |
| **Auth Code** | Seconds | **60 seconds** | Hardcoded in `AuthService.CreateAuthCodeAsync()` |
| **Magic Link** | Minutes | **15 minutes** | `MagicLinkExpirationMinutes` |
| **Password Reset** | Hours | (see config) | `PasswordResetExpirationHours` |

JWT validation allows a **5-minute clock skew** (`ClockSkew = TimeSpan.FromMinutes(5)` in `JwtTokenService.cs`).

### Where Tokens Are Stored on the Client PC

#### On DedgeAuth login page (`login.html`):

| Storage | Key | Content | Lifetime |
|---------|-----|---------|----------|
| `localStorage` | `accessToken` | Full JWT string | Persists until logout or manual clear |
| `localStorage` | `user` | JSON user object (email, name, accessLevel) | Persists until logout |
| `localStorage` | `DedgeAuth_appview` | Selected tab view preference (1-5) | Permanent |
| `localStorage` | `theme` | `dark` or `light` | Permanent |
| `localStorage` | `DedgeAuth_language` | Language code (`nb` or `en`) | Permanent |
| Cookie | `DedgeAuth_jwt` | Full JWT string | **30 minutes** (`max-age=1800`) |
| Cookie | `refreshToken` | Refresh token string | **7 days** (`HttpOnly`, not readable by JS) |

#### On consumer apps (DocView, GenericLogHandler, etc.):

| Storage | Key | Content | Lifetime |
|---------|-----|---------|----------|
| Cookie | `DedgeAuth_access_token` | Full JWT string | Set by `DedgeAuthTokenExtractionMiddleware` after auth code exchange |
| `sessionStorage` | `gk_accessToken` | JWT copied from cookie by `DedgeAuth-user.js` | Browser session only |

### Storage Locations on Disk

**localStorage** is stored by Chromium-based browsers at:

```
%LOCALAPPDATA%\Microsoft\Edge\User Data\Default\Local Storage\leveldb\
%LOCALAPPDATA%\Google\Chrome\User Data\Default\Local Storage\leveldb\
```

These are LevelDB databases, not plain text files. Each origin (e.g., `http://dedge-server`) has its own key-value pairs.

**Cookies** are stored at:

```
%LOCALAPPDATA%\Microsoft\Edge\User Data\Default\Network\Cookies
%LOCALAPPDATA%\Google\Chrome\User Data\Default\Network\Cookies
```

These are SQLite databases.

### Why You Must Re-Authenticate Daily

The **refresh token cookie** lasts 7 days and is `HttpOnly` (secure, not accessible to JavaScript). When you visit `login.html`, the `tryAutoRefresh()` function attempts `POST /api/auth/refresh` with `credentials: 'include'`, which sends the refresh token cookie. If the refresh token is still valid (not expired, not revoked), a new JWT and new refresh token are issued — **no login required**.

However, this only works if:
1. The refresh token cookie exists (not cleared by browser)
2. The refresh token hasn't been revoked (e.g., by logout)
3. The cookie path matches the request path

If any of these fail, the login form appears. Possible reasons for daily re-authentication:
- **Logout** clears the refresh token cookie and revokes the token in the database
- **Browser cookie cleanup** (Edge may clear cookies on exit depending on settings)
- **Private/InPrivate mode** discards all cookies on close
- **Cookie path mismatch** if the `refreshToken` cookie path doesn't match the login page path

---

## 2026-03-23 11:30 — Critical Finding: Windows Kerberos TGT DOES Exist

### Earlier diagnosis was wrong

The `Enable-KerberosForBrowser.ps1` script reported `[WARN] No Kerberos TGT found` — but this was **misleading**. The script runs `klist` which, on this machine, resolves to the **Java JDK klist** at `C:\Program Files\Eclipse Adoptium\jdk-21.0.10.7-hotspot\bin\klist.exe`, not the Windows built-in `klist.exe`.

| `klist` found first in PATH | Location | Credential store | Result |
|-----|-----|-----|-----|
| **Java JDK `klist`** | `C:\Program Files\Eclipse Adoptium\jdk-21.0.10.7-hotspot\bin\` | MIT-style file cache (`krb5cc_FKGEISTA`) | **Not found** — file doesn't exist |
| **Windows `klist.exe`** | `C:\Windows\system32\` | Windows SSPI credential cache (LSASS) | **TGT found and valid** |

### Actual Kerberos ticket status (Windows SSPI)

```
Client:  FKGEISTA @ DEDGE.FK.NO
Server:  krbtgt/DEDGE.FK.NO @ DEDGE.FK.NO
Encryption: AES-256-CTS-HMAC-SHA1-96
Start:   2026-03-23 11:14:04
End:     2026-03-23 21:14:04 (10-hour validity)
Renew:   2026-03-30 11:14:04 (7-day renewal window)
KDC:     p-no1dc-vm02.DEDGE.fk.no
```

The PC **does have a valid Kerberos TGT** for `DEDGE.FK.NO`, obtained from the domain controller `p-no1dc-vm02.DEDGE.fk.no`.

### Machine identity: Azure AD Hybrid Join, not traditional domain join

The `klist sessions` output reveals the authentication topology:

```
DEDGE\FKGEISTA   CloudAP:Interactive    ← Azure AD / Entra joined, not traditional domain
WORKGROUP\30237-FK$  Negotiate:Service   ← Machine account is in WORKGROUP, not DEDGE domain
```

The PC is **Azure AD (Entra ID) joined** with Cloud Authentication Provider (CloudAP). It is **not** traditionally domain-joined (the machine account is `WORKGROUP\30237-FK$`, not `DEDGE\30237-FK$`). However, CloudAP still obtains Kerberos TGTs from the on-premises domain controller for SSO to on-prem resources.

---

## 2026-03-23 11:35 — DB2 Kerberos vs IIS Kerberos: Why One Works and the Other Doesn't

### How DB2 Kerberos authentication works

DB2 client on this machine is configured for Kerberos:

```
db2 catalog database <DB> at node <NODE> AUTHENTICATION KERBEROS TARGET PRINCIPAL db2/<server>
db2 update cli cfg for section COMMON using CLNT_KRB_PLUGIN IBMkrb5
db2 update cli cfg for section COMMON using AUTHENTICATION KERBEROS_SSPI
```

Key: **`KERBEROS_SSPI`** tells the IBM DB2 .NET driver to use the **Windows SSPI** (Security Support Provider Interface) to obtain Kerberos service tickets. SSPI directly calls into Windows LSASS, which holds the TGT obtained by CloudAP. This works because:

1. CloudAP obtains a TGT from `DEDGE.FK.NO` domain controller
2. DB2 client calls SSPI → SSPI requests a service ticket for `db2/<servername>` from the KDC
3. KDC returns the service ticket (encrypted for the DB2 server's SPN)
4. DB2 client sends the service ticket to the DB2 server
5. DB2 server validates the ticket → connection authenticated

**No password prompt. No credential dialog. Fully automatic.**

The MCP server (`CursorDb2McpServer`) runs on `dedge-server` as an IIS application and uses **username/password** authentication via `appsettings.json` (`Db2:Username` / `Db2:Password`), not Kerberos. But when developers run DB2 queries from their workstations (via `db2` CLI, DBeaver, or ODBC), they use `KERBEROS_SSPI` which leverages the Windows SSPI credential cache.

### How IIS/Browser Kerberos authentication works (DedgeAuth)

When Edge visits `http://dedge-server/DedgeAuth/api/auth/windows-login`:

1. IIS returns `401` with `WWW-Authenticate: Negotiate`
2. Edge must decide: send a Kerberos ticket, or show a credential dialog
3. Edge checks its **AuthServerAllowlist** policy → `dedge-server` is listed ✓
4. Edge calls Windows SSPI to get a service ticket for `HTTP/dedge-server`
5. **This step should work** — the TGT exists, SSPI should be able to request the service ticket

### The real question: Why does Edge still show the dialog?

Given that:
- ✓ The Windows Kerberos TGT **exists** (verified with `C:\Windows\system32\klist.exe`)
- ✓ The `AuthServerAllowlist` policy is **correctly set** for Edge
- ✓ The site is in the **Local Intranet zone**
- ✓ The IIS server has **Windows Authentication enabled** with `useAppPoolCredentials: true`
- ✓ The SPN issue was fixed (no more `SEC_E_WRONG_PRINCIPAL`)

Possible remaining causes:

| Hypothesis | Explanation |
|------------|-------------|
| **Edge not restarted after policy change** | Registry policies require a full browser restart (all Edge windows/processes closed and reopened) |
| **SPN not registered for HTTP** | The SPN `HTTP/dedge-server` may not be registered in AD for the service account `DEDGE\t1_srv_fkxtst_app` |
| **CloudAP Kerberos limitations** | Azure AD-joined PCs may have restrictions on which SPNs CloudAP can request service tickets for. Some organizations require the resource to be published through Azure AD or have specific Kerberos configuration |
| **Negotiate falling back to NTLM** | If the Kerberos service ticket request fails silently, Negotiate falls back to NTLM, which requires the credential prompt |
| **`windows-probe` endpoint behavior** | The silent probe endpoint (`[AllowAnonymous]`) may not trigger SSPI negotiation because the server never sends a 401 challenge |

### The fundamental difference

| Aspect | DB2 Kerberos (works) | IIS/Browser Kerberos (prompt) |
|--------|---------------------|-------------------------------|
| **Client** | IBM DB2 .NET driver with `KERBEROS_SSPI` | Edge browser with Negotiate |
| **SSPI usage** | Direct API call — always uses SSPI | Browser decides based on zone, policy, and challenge |
| **Ticket request** | `db2/<servername>` — initiated by client code | `HTTP/<servername>` — initiated only after 401 challenge |
| **Server challenge** | DB2 wire protocol (DRDA) | HTTP 401 + WWW-Authenticate: Negotiate |
| **Fallback** | Fail or use password from config | Show Windows Security dialog (NTLM fallback) |
| **Policy gate** | None — DB2 client always tries Kerberos if configured | `AuthServerAllowlist` + Intranet zone must be set |
| **Identity** | OS user via SSPI (always available) | Browser-mediated (may not send if policy/zone wrong) |

### Key insight

DB2 Kerberos works because the **DB2 client directly calls SSPI** with no intermediary policy layer. It doesn't ask "should I send credentials?" — it just does it.

Browser Kerberos has **multiple policy gates** (AuthServerAllowlist, Intranet zone, browser restart after policy change, correct 401 challenge response) that must all pass before the browser will automatically send credentials. If any one fails, the browser falls back to showing the manual credential dialog.

### Action items for investigation

1. **Verify SPN registration**: Check if `HTTP/dedge-server` is registered in AD for `DEDGE\t1_srv_fkxtst_app`
2. **Test with `curl.exe --negotiate`**: `curl.exe --negotiate -u : http://dedge-server/DedgeAuth/api/auth/windows-probe` — if this works, the SPN is fine and the issue is browser-specific
3. **Check Edge Negotiate logs**: `edge://net-internals/#events` can show whether Edge attempted SPNEGO and what error it got
4. **Verify Edge was restarted**: All Edge processes must be closed and reopened after registry policy changes

---

## 2026-03-23 11:50 — Options to Improve Auto-Login for Entra-Joined PCs

### Why the silent Kerberos probe (`/windows-probe`) can never work

The `windows-probe` endpoint uses `[AllowAnonymous]`. When IIS has **both** Anonymous Authentication and Windows Authentication enabled, IIS authenticates the request as **Anonymous first** (higher priority). It never sends a `401 Negotiate` challenge. Without the challenge, the browser **never sends the Kerberos ticket** — browsers only transmit credentials in response to a server challenge, never proactively.

This means the silent probe will **always** see an anonymous identity and return `windowsAuthAvailable: false`, regardless of whether the browser has a valid Kerberos ticket. The probe was designed with the assumption that IIS would "pass through" credentials opportunistically, but that's not how HTTP Negotiate works.

### The email/password form CAN be saved by browser password managers

The login form already has the correct structure for password manager integration:

```html
<form id="password-form">
  <input type="email" id="email" name="email">
  <input type="password" id="password" name="password">
  <button type="submit">Sign In</button>
</form>
```

Edge and Chrome **should** offer to save these credentials. If they don't, it may be because:
- The form uses `e.preventDefault()` and submits via `fetch()` instead of a native form POST
- The page URL changes (redirect) before the browser has time to prompt "Save password?"
- No `autocomplete` attributes are set on the form/inputs

### Improvement options ranked by effort and impact

#### Option 1: Fix password manager integration (LOW effort, HIGH impact)

Add `autocomplete` attributes to help browsers recognize the login form:

```html
<form id="password-form" autocomplete="on">
  <input type="email" id="email" name="email" autocomplete="username">
  <input type="password" id="password" name="password" autocomplete="current-password">
</form>
```

This tells Edge/Chrome "this is a login form — offer to save credentials." After the first manual login, the browser saves email+password and auto-fills next time. The user just clicks "Sign In" — no typing.

**Pros**: Zero backend changes, works immediately, browser-native UX
**Cons**: Still requires one click to submit, doesn't solve the Windows dialog issue

#### Option 2: Extend refresh token lifetime + "Remember Me" checkbox (LOW effort, HIGH impact)

Add a "Remember Me" checkbox to the login form. When checked, set the refresh token cookie to **30 days** instead of 7 days. The existing `tryAutoRefresh()` already handles silent re-authentication on page load.

Changes needed:
- Add checkbox to `login.html`
- Pass `rememberMe: true` in the login API request
- In `AuthController.SetRefreshTokenCookie()`, use 30 days if `rememberMe` is true
- In `AuthService`, create refresh token with 30-day expiry if `rememberMe`

**Pros**: After first login, user never sees login page for 30 days. Works for all login methods (password, magic link, Windows). No complex infrastructure.
**Cons**: Security trade-off (longer token = longer exposure if stolen). Cookie must survive browser restarts (check Edge cookie settings).

#### Option 3: Microsoft Entra ID / OIDC integration (HIGH effort, BEST long-term)

Add OpenID Connect (OIDC) authentication with Azure AD / Entra ID as an identity provider. This would add a "Sign in with Microsoft" button that redirects to Microsoft's login page.

On Azure AD-joined PCs, Microsoft's login page uses the **Primary Refresh Token (PRT)** — a device-level credential that enables true silent SSO. The user would never see a login prompt.

Changes needed:
- Register DedgeAuth as an Azure AD application in Entra ID
- Add `Microsoft.Identity.Web` NuGet package
- Add OIDC authentication scheme in `Program.cs`
- Add "Sign in with Microsoft" button in `login.html`
- Map Entra ID claims to DedgeAuth user model
- Handle first-time user provisioning from Entra token

**Pros**: True silent SSO for all Entra-joined PCs (no dialog, no click, no typing). Industry standard. Supports MFA, Conditional Access, device compliance.
**Cons**: Requires Azure AD app registration (needs Azure admin). Significant code changes. External dependency on Microsoft identity platform. Must handle token refresh with Entra separately.

#### Option 4: Fix the silent Kerberos probe to actually work (MEDIUM effort, MEDIUM impact)

Create a **dedicated IIS virtual path** for Windows auth that has Anonymous disabled:

```
/DedgeAuth/api/auth/windows-probe  → Anonymous enabled (current, broken)
/DedgeAuth/api/auth/windows-check  → Anonymous DISABLED, Windows Auth ONLY
```

The `windows-check` endpoint would force IIS to send a 401 Negotiate challenge. The browser, with `AuthServerAllowlist` configured, would silently send the Kerberos ticket. No dialog.

Changes needed:
- New controller endpoint with Windows Auth only (no Anonymous)
- IIS `<location>` config to disable Anonymous for that specific path
- Update `login.html` to call `/windows-check` first, fall back to probe
- Update `IIS-Handler.psm1` deploy template for the location-specific auth

**Pros**: True silent Kerberos — works for domain-joined AND Entra-joined PCs (since TGT exists). No external dependencies.
**Cons**: Requires IIS-level path configuration. May not work on all browsers/configurations. The 401 challenge is "all or nothing" — if the browser can't negotiate, it shows the dialog (no silent fallback).

### Recommendation

**Combine Options 1 + 2 for immediate improvement:**

1. Add `autocomplete` attributes → browser saves email/password → next login is just a click
2. Add "Remember Me" with 30-day refresh token → after first login, no login page for a month

**Consider Option 3 (Entra OIDC) as a future project** — it's the proper long-term solution for Azure AD-joined environments, but requires Azure admin involvement and significant implementation effort.

**Consider Option 4 if Kerberos must work silently** — it's the most targeted fix for the current architecture, but has edge cases.

---

## 2026-03-23 12:00 — klist PATH Issue: Impact on DedgeAuth C# Code

### Question

The `Enable-KerberosForBrowser.ps1` script had a bug where it called bare `klist` which resolved to the Java JDK version (`C:\Program Files\Eclipse Adoptium\jdk-21.0.10.7-hotspot\bin\klist.exe`) instead of the Windows version (`C:\Windows\System32\klist.exe`). This caused false "No TGT found" warnings. Could the same issue affect the DedgeAuth C# application code?

### Analysis

**No — the DedgeAuth C# code is NOT affected by the klist PATH issue.**

The C# codebase was searched for all references to `klist`, `Process.Start`, `SSPI`, `kerberos`, `negotiate`, `WindowsIdentity`, and related terms. Results:

| File | What it does | Uses klist? | Affected? |
|---|---|---|---|
| `AuthController.cs` | Reads `HttpContext.User.Identity` (set by IIS/Kestrel, not klist) | No | No |
| `Program.cs` | Configures `AddNegotiate()` or IIS Windows Auth scheme | No | No |
| `AuthService.cs` | Processes user data after authentication | No | No |
| `login.html` (JS) | Calls `/windows-probe` and `/windows-login` via `fetch()` | No | No |

The DedgeAuth C# code relies entirely on **ASP.NET Core's authentication middleware** and **IIS integration** for Kerberos/Negotiate. The authentication flow is:

1. IIS receives HTTP request with `Authorization: Negotiate <token>` header
2. IIS decrypts the Kerberos ticket using Windows SSPI (kernel/app pool level)
3. IIS sets `HttpContext.User.Identity` as a `WindowsIdentity` with claims
4. DedgeAuth C# code reads `HttpContext.User.Identity.Name` and `HttpContext.User.Claims`

**No external process is invoked.** The C# code never calls `klist`, never shells out to check Kerberos tickets, and never reads the credential cache directly. All Kerberos handling is delegated to IIS + Windows SSPI.

### Where the klist issue WAS confined

| Component | Calls klist? | Was affected? | Fixed? |
|---|---|---|---|
| `Enable-KerberosForBrowser.ps1` | Yes (bare `klist`) | Yes — Java klist reported "not found" | Yes — now uses `$env:WINDIR\System32\klist.exe` |
| `Get-DedgeAuthDiagnostics.ps1` | No | No | N/A |
| DedgeAuth C# application | No | No | N/A |
| `IIS-Handler.psm1` | No | No | N/A |

### Related concern: LDAP lookup hardcoded domain

One item of note in the C# code — the LDAP lookup in `HandleWindowsLoginCoreAsync()` uses a **hardcoded domain name**:

```csharp
using var entry = new DirectoryEntry("LDAP://DEDGE.fk.no");
```

This is fine for the current environment (all users are in DEDGE domain), but would break if:
- The app were deployed to a server in a different domain
- Users from a trusted domain or child domain attempted Kerberos login

This is not a bug today but is worth noting for future portability. It could be made configurable via `appsettings.json`.

---

## 2026-03-23 13:20 — Implemented 30-Day Login Persistence + Kerberos Probe Fix (v1.0.170)

### Changes deployed

**1. Password Manager Support** — Added `autocomplete="username"` and `autocomplete="current-password"` to the login form inputs, plus `autocomplete="on"` on the form element. Edge/Chrome will now offer to save email and password after first successful login.

**2. "Remember Me" Checkbox** — Added a checkbox between the password field and the forgot-password link. When checked, the refresh token cookie and database expiry are set to **30 days** instead of the default **7 days**. The `rememberMe` flag is passed through:
- `login.html` JS → `LoginRequest` body → `AuthController.Login()` → `AuthService.LoginWithPasswordAsync()` → `CreateRefreshTokenAsync(overrideDays: 30)` → `SetRefreshTokenCookie(rememberMe: true)`

**3. Kerberos Probe Fix** — Changed `tryAutoKerberos()` from calling `/api/auth/windows-probe` (AllowAnonymous, which could NEVER work) to `/api/auth/windows-login` (Authorize with Negotiate). The `fetch()` API handles the 401 Negotiate challenge silently when `AuthServerAllowlist` is configured. If negotiation fails, `fetch()` returns 401 with **no dialog** — the login form is shown as fallback.

**4. Cookie Expiry Bug Fix** — `SetRefreshTokenCookie` previously hardcoded `AddDays(7)`, ignoring `_config.RefreshTokenExpirationDays`. Now reads from config (with override for Remember Me).

### Browser verification

- Deployed to `dedge-server` as v1.0.170 via `--autocur`
- Health check: HTTP 200
- Login page: Remember Me checkbox visible, autocomplete attributes present
- Kerberos silent login: **working** — page auto-authenticated with Windows identity on first load
- Password login with Remember Me: **working** — signed out, filled form, checked Remember Me, signed in successfully
- Dashboard: all app links visible, tabbed views functional

### Files modified

| File | Change |
|---|---|
| `login.html` | `autocomplete` attributes, Remember Me checkbox, Kerberos probe endpoint change |
| `AuthController.cs` | Injected `AuthConfiguration`, updated `SetRefreshTokenCookie` to use config + rememberMe, added `RememberMe` to `LoginRequest` |
| `AuthService.cs` | Added `rememberMe` param to `LoginWithPasswordAsync`, `overrideDays` param to `CreateRefreshTokenAsync` |

---

## 2026-03-23 12:10 — Will "Remember Me" 30-Day Refresh Token Hit URL Size Limits?

### Previous issue context

There was a previous issue where a token was too large for URL transport (query string `?token=...`). This happened because the **JWT access token** was passed directly in the URL. JWTs contain Base64-encoded header, payload (with all claims, app roles, AD groups), and signature — easily reaching 800-1500+ characters.

### Answer: No — the 30-day refresh token will NOT cause URL size issues

The "Remember Me" feature only changes the **lifetime** of the refresh token, not its size or transport mechanism. Here's why:

#### How tokens are transported today

| Token | Size | Transport | In URL? |
|---|---|---|---|
| **Refresh token** | ~43 chars | `HttpOnly` cookie (`refreshToken`) | **Never** |
| **Auth code** | ~43 chars | URL query string (`?code=...`) | Yes, but tiny |
| **JWT access token** | ~800-1500 chars | `localStorage` + `Authorization` header | **Never** (old bug was passing this in URL) |

#### Refresh token generation — always 43 chars

```csharp
// AuthService.cs line 1012
private static string GenerateSecureToken()
{
    var bytes = new byte[32];
    using var rng = RandomNumberGenerator.Create();
    rng.GetBytes(bytes);
    return Convert.ToBase64String(bytes).Replace("+", "-").Replace("/", "_").TrimEnd('=');
}
```

This produces a **32-byte random value** encoded as URL-safe Base64 = exactly **43 characters**. The same function generates refresh tokens, auth codes, and magic link tokens. Changing the expiry from 7 days to 30 days changes **nothing about the token string** — it only changes the `expires_at` column in the database.

#### Cookie transport — not affected by token size

```csharp
// AuthController.cs line 793
private void SetRefreshTokenCookie(string token)
{
    var cookieOptions = new CookieOptions
    {
        HttpOnly = true,
        Expires = DateTime.UtcNow.AddDays(7), // Would change to 30 for "Remember Me"
        SameSite = SameSiteMode.Lax,
        Secure = Request.IsHttps,
        Path = Request.PathBase.HasValue ? Request.PathBase.Value : "/"
    };
    Response.Cookies.Append("refreshToken", token, cookieOptions);
}
```

The refresh token is stored as an **HttpOnly cookie**, not passed in the URL. Cookie size limit is ~4KB per cookie — a 43-character token is nowhere near that.

#### The auth code flow protects against URL bloat

The previous "too big for URL" issue was fixed by introducing the **auth code exchange** pattern:

1. Login succeeds → server creates a **short auth code** (~43 chars) + refresh token cookie
2. Redirect URL uses `?code=<43-char-code>` instead of `?token=<800-char-JWT>`
3. Consumer app exchanges the code server-to-server for the full JWT via `POST /api/auth/exchange`

This pattern is **already in place** and would not change with "Remember Me".

### What "Remember Me" would actually change

| What changes | From | To |
|---|---|---|
| `RefreshToken.ExpiresAt` in database | 7 days | 30 days |
| `SetRefreshTokenCookie` cookie `Expires` | 7 days | 30 days |
| Token string itself | 43-char random | 43-char random (identical) |
| URL query string | `?code=<43 chars>` | `?code=<43 chars>` (identical) |

**Conclusion**: The 30-day "Remember Me" refresh token is safe. It changes only the expiration timestamp, not the token value or transport mechanism. The URL size issue cannot recur because the URL only ever carries the 43-character auth code, never the JWT or refresh token.

---
