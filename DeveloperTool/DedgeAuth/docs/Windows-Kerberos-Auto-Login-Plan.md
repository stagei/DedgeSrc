# Windows Kerberos Seamless Auto-Login — Full Plan & Revert Instructions

**Date**: 2026-03-17
**Pre-change commit**: `d6dbf435adfe41bf13e7317ce613521268fde59f`
**Change markers**: `// 20260317 GHS Test Ad/Entra Start -->` / `// <--20260317 GHS Test Ad/Entra End` (C#) and `<!-- 20260317 GHS Test Ad/Entra Start -->` / `<!-- 20260317 GHS Test Ad/Entra End -->` (HTML)

---

## Revert Instructions

### Option 1: Git revert (recommended — preserves history)

```bash
git revert --no-commit d6dbf43..HEAD
git commit -m "Revert Windows/Kerberos auto-login changes"
```

### Option 2: Hard reset (destructive — discards all commits after this point)

```bash
git reset --hard d6dbf435adfe41bf13e7317ce613521268fde59f
```

### Option 3: Revert database migration

If the EF migration for `auth_method` was applied, roll it back:

```bash
cd src\DedgeAuth.Api
dotnet ef database update <PreviousMigrationName> --project ..\DedgeAuth.Data
```

Or manually:

```sql
ALTER TABLE users DROP COLUMN IF EXISTS auth_method;
```

### IIS cleanup

After reverting code, remove the Windows Authentication override on the server:

```powershell
& $env:windir\system32\inetsrv\appcmd.exe set config "Default Web Site/DedgeAuth" `
    /section:system.webServer/security/authentication/windowsAuthentication `
    /enabled:false /commit:apphost
```

Or simply run `IIS-RedeployAll.ps1` which resets all IIS auth config from templates.

### Post-revert rebuild

```powershell
pwsh.exe -NoProfile -File "C:\opt\src\DedgeAuth\Build-And-Publish.ps1"
pwsh.exe -NoProfile -File "C:\opt\src\DedgePsh\DevTools\WebSites\IIS-DeployApp\IIS-RedeployAll.ps1"
```

---

## Problem Statement

Currently, domain users with valid Kerberos tickets must manually click "Sign in with Windows" on the login page. The `LoginWithWindowsAsync` method constructs an email from the username (e.g., `fkgeista@Dedge.no`) instead of looking up the real email from Active Directory (e.g., `geir.helge.starholm@Dedge.no`). Users who log in via Windows still get an internal password-based profile, which is misleading.

---

## Design Decisions

### 1. Auto-attempt Kerberos on page load (no button click required)

When `login.html` loads, JavaScript will **silently attempt** `GET /api/auth/windows-login` with `credentials: 'include'` **before** rendering the login form.

- **Kerberos succeeds** (domain PC, tickets, browser configured): user is logged in immediately, redirected to `returnUrl` or shown logged-in state. The login form is never shown.
- **Kerberos fails** (401/403, non-domain PC, no tickets): fall through silently and show the normal login form with the "Sign in with Windows" button still available as a manual option.

Flow:

```
Page load -> silent Kerberos attempt -> success? redirect : show login form
```

Windows login is **optional**. Users can always choose to log in via email/password or magic link instead. The manual "Sign in with Windows" button remains available on the login form as a fallback.

### 2. Tenant-level Windows SSO switch

New boolean column `windows_sso_enabled` on the `tenants` table (default `false`). Controls whether Windows/Kerberos auto-registration and implicit access apply for users of that tenant.

| Tenant | `windows_sso_enabled` | Effect |
|---|---|---|
| `Dedge.no` | `true` | Windows/Kerberos users auto-register, auto-approve, get implicit minimum app access |
| Any other tenant | `false` (default) | Windows/Kerberos identity is recognized but NOT auto-approved. User is redirected to standard DedgeAuth registration to set a password. Requires admin approval. No implicit app access. |

**Flow when `windows_sso_enabled = false`**:

1. User's browser sends Kerberos auth to `/api/auth/windows-login`
2. Server authenticates Windows identity, looks up AD email
3. Server determines tenant from email domain
4. Tenant has `windows_sso_enabled = false`
5. Server returns `{ success: false, ssoDisabled: true, email: "user@otherdomain.com", displayName: "User Name" }` (HTTP 200, not 401)
6. Frontend detects `ssoDisabled` and redirects to `register.html?email=user@otherdomain.com&name=User+Name` with pre-filled fields
7. User sets a DedgeAuth password, submits registration, awaits admin approval
8. No implicit minimum app access — standard email/password user rules apply

### 3. Two user registration paths

| Path | Registration | Approval | Password | App Access |
|---|---|---|---|---|
| **Windows/Kerberos** | Auto-created from AD | Auto-approved (`IsActive = true`, `EmailVerified = true`) | None (`PasswordHash = null`) | Implicit minimum access to safe-level apps; must request elevated access |
| **Email/password** | Self-register or admin-created | Requires admin approval (existing behavior) | Set by user | Must request per-app access (admin approves) |

Both paths produce a normal DedgeAuth user record. The only difference is **how** the user is registered and approved.

### 4. Existing users keep their profiles

The AD lookup returns the real email (e.g., `geir.helge.starholm@Dedge.no`). `LoginWithWindowsAsync` searches for this email in the DedgeAuth database. If found, it uses the **existing** profile with all its app permissions, roles, tenant assignment, etc.

If an existing user who registered via email/password later logs in via Windows/Kerberos:

- Their existing password is **kept** (they can still use either method from non-domain PCs)
- `auth_method` is updated to `"windows"` to record their last login method

### 5. Welcome email for auto-registered Kerberos users

When a Windows/Kerberos user is auto-registered (new user, not existing), send a branded informational email:

- Subject: "Welcome to DedgeAuth - Automatic Registration"
- Body: "You were automatically registered via Windows/Kerberos authentication. Your account is active. To request access to apps, click the button below."
- Includes a direct link/button to the profile page (`{baseUrl}/profile.html`) where the user can request app access
- Uses existing `EmailService` + `BuildEmailTemplate` pattern with tenant branding
- Sent fire-and-forget (non-blocking, logged on failure) — same pattern as lockout notification
- **Not** sent for existing users who log in via Windows (they already know they have an account)

### 6. Tag auth method on user record

Add a new column `auth_method` to the `users` table:

| Value | Meaning |
|---|---|
| `null` or `"internal"` | Traditional DedgeAuth login (password/magic link) |
| `"windows"` | Last logged in via Windows/Kerberos |

This is informational only. It does **not** restrict which login method a user can use. A user tagged `"windows"` can still log in via email/password if they have one set. The field simply records how they last authenticated.

### 7. Implicit minimum app access for Windows/Kerberos users

Windows/Kerberos users (`auth_method = "windows"`) get **implicit minimum access** to all active apps — no `app_permissions` rows needed for default access.

**How it works**: In `GetUserAppRolesAsync`, after fetching explicit `app_permissions` rows, check if the user has `auth_method = "windows"`. If so, for every active app where the user has **no explicit permission**, determine the lowest role from **that specific app's** `available_roles_json`. Each app is evaluated independently — different apps can have different role sets. If that app's lowest role is a **safe** level, include it implicitly in the returned dictionary.

**Role hierarchy** (lowest to highest):

```
ReadOnly < Viewer < User < Operator < PowerUser < Admin
```

**Safe auto-grant levels** (no approval needed): `ReadOnly`, `Viewer`, `User`
**Requires explicit approval**: `Operator`, `PowerUser`, `Admin`

**Per-app evaluation** (each app's `available_roles_json` is checked independently):

| App example | `available_roles_json` | Lowest role | Auto-grant? |
|---|---|---|---|
| GenericLogHandler | `["ReadOnly", "User", "PowerUser", "Admin"]` | `ReadOnly` | Yes, gets `ReadOnly` |
| DocView | `["ReadOnly", "User", "PowerUser", "Admin"]` | `ReadOnly` | Yes, gets `ReadOnly` |
| SomeRestrictedApp | `["Operator", "Admin"]` | `Operator` | No, requires approval |
| SingleRoleApp | `["User"]` | `User` | Yes, gets `User` |
| AdminOnlyApp | `["Admin"]` | `Admin` | No, requires approval |

**Rules**:

- Each app is evaluated based on **its own** `available_roles_json`, not a global setting
- If an app's lowest available role is `ReadOnly`, `Viewer`, or `User` then the Windows/Kerberos user gets it automatically (implicit, no DB row)
- If an app's lowest available role is `Operator`, `PowerUser`, or `Admin` then no implicit access; user must request and be approved
- If a user has an **explicit** `app_permissions` row (e.g., admin granted them `PowerUser`), that always takes precedence over the implicit minimum
- Implicit roles are baked into the JWT `appPermissions` claim at token generation time, so **no changes needed in DedgeAuth.Client or consumer apps**
- When new apps are registered, Windows/Kerberos users automatically get minimum access on their next login (next JWT generation)

### 8. Preserve all standard DedgeAuth functionality (non-Windows users)

All existing authentication and authorization flows remain fully operational and unchanged:

| Feature | Status |
|---|---|
| Email/password login | Unchanged. Works exactly as before. |
| Magic link login | Unchanged. Works exactly as before. |
| Self-registration | Unchanged. Users register, await admin approval. |
| Admin-created users | Unchanged. Admin can still create users manually. |
| Password reset | Unchanged. Email-based reset flow. |
| Email verification | Unchanged. Required for non-Windows registrations. |
| App access requests | Unchanged. Users request access, admin approves. |
| Per-app role assignment | Unchanged. Admin grants specific roles per app. |
| Account lockout | Unchanged. Failed password attempts trigger lockout. |
| Admin panel (apps, users, tenants) | Unchanged. Full admin management. |
| JWT tokens, refresh tokens, auth codes | Unchanged. Same token lifecycle. |
| Tenant CSS/logo/branding | Unchanged. Tenant system untouched. |
| DedgeAuth.Client middleware in consumer apps | Unchanged. No rebuild needed. |

**Key guarantees**:

- External users (non-domain) can register and log in via email/password or magic link as always
- Users who prefer email/password over Windows login can do so — the auto-Kerberos attempt silently fails and shows the normal form
- Non-Windows users still require explicit `app_permissions` rows for every app. Admin must approve. No implicit access.
- The `auth_method` field is informational only. A user tagged `"windows"` can still log in via email/password if they have a password set.
- No existing API endpoints, middleware, or database schemas are removed or broken

---

## Files Affected

| File | Change |
|---|---|
| `src/DedgeAuth.Core/Models/Tenant.cs` | Add `WindowsSsoEnabled` property (`bool`, column `windows_sso_enabled`, default `false`) |
| `src/DedgeAuth.Core/Models/User.cs` | Add `AuthMethod` property (`string?`, column `auth_method`, max 50) |
| `src/DedgeAuth.Data/` (EF migration) | Single migration for both `tenants.windows_sso_enabled` and `users.auth_method` |
| `src/DedgeAuth.Services/DatabaseSeeder.cs` | Set `WindowsSsoEnabled = true` for `Dedge.no` tenant |
| `src/DedgeAuth.Services/AuthService.cs` | Update `LoginWithWindowsAsync` to check tenant `WindowsSsoEnabled`; return `ssoDisabled` if false; set `AuthMethod`, `PasswordHash = null` for new SSO users; update `GetUserAppRolesAsync` for implicit minimum roles |
| `src/DedgeAuth.Services/EmailService.cs` | Add `SendWindowsWelcomeEmailAsync` with tenant branding and profile page link |
| `src/DedgeAuth.Api/Controllers/AuthController.cs` | AD lookup for real email/display name; include `authMethod` in `/me` response; handle `ssoDisabled` response; fire-and-forget welcome email for new users |
| `src/DedgeAuth.Api/DedgeAuth.Api.csproj` | `System.DirectoryServices.AccountManagement` package (already added) |
| `src/DedgeAuth.Api/wwwroot/login.html` | Silent auto-Kerberos attempt on page load; handle `ssoDisabled` by redirecting to `register.html` with pre-filled email/name |

---

## Implementation Todos

1. Add `WindowsSsoEnabled` property to `Tenant.cs` (bool, default false)
2. Add `AuthMethod` property to `User.cs` (string?, nullable)
3. Create single EF migration for both `tenants.windows_sso_enabled` and `users.auth_method`
4. Update `DatabaseSeeder` to set `WindowsSsoEnabled = true` for `Dedge.no` tenant
5. Update `LoginWithWindowsAsync` to check tenant `WindowsSsoEnabled`; if false return `ssoDisabled` with email/name; if true auto-register/login with `AuthMethod = "windows"`, `PasswordHash = null`, return `isNewUser` flag
6. Modify `GetUserAppRolesAsync` to add implicit minimum app roles for Windows/Kerberos users (safe levels only: ReadOnly, Viewer, User — no DB rows)
7. Add `SendWindowsWelcomeEmailAsync` to `EmailService` with tenant branding and profile page link
8. Include `authMethod` in `/api/auth/me` response; handle `ssoDisabled` in controller; fire-and-forget welcome email for new Windows users
9. Add silent auto-Kerberos attempt on page load; handle `ssoDisabled` by redirecting to `register.html?email=...&name=...`
10. Build, publish, deploy DedgeAuth, apply EF migration, verify

---

## Previous Changes (already committed)

These changes were made prior to this plan and are included in the commit history:

| Commit | Description |
|---|---|
| `4e0083b` | Base commit before any AD/Entra changes |
| Subsequent commits | Added `Microsoft.AspNetCore.Authentication.Negotiate`, `.AddNegotiate()` in `Program.cs`, `WindowsLogin` endpoint in `AuthController.cs`, `LoginWithWindowsAsync` in `AuthService.cs`, Windows Login button in `login.html` |
| `d6dbf43` | Current HEAD before this plan's implementation |
