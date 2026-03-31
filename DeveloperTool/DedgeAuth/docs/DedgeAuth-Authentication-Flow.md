# DedgeAuth Authentication Flow

**Generated**: 2026-03-22

Complete flowchart of all authentication methods, middleware pipeline, and database table interactions.

---

## 1. High-Level Overview

```mermaid
flowchart TB
    subgraph Browser["Browser"]
        User((User))
    end

    subgraph ConsumerApp["Consumer App (e.g. DocView, GenericLogHandler)"]
        MW1[DedgeAuthTokenExtractionMiddleware]
        MW2[UseAuthentication - JWT]
        MW3[UseAuthorization]
        MW4[DedgeAuthSessionValidationMiddleware]
        MW5[DedgeAuthRedirectMiddleware]
        AppPage[App Page / API]
    end

    subgraph DedgeAuthServer["DedgeAuth Server"]
        LoginPage[login.html]
        AuthAPI[AuthController API]
        AuthSvc[AuthService]
        JwtSvc[JwtTokenService]
        EmailSvc[EmailService]
    end

    subgraph DB["PostgreSQL (DedgeAuth)"]
        users[(users)]
        tenants[(tenants)]
        apps[(apps)]
        app_permissions[(app_permissions)]
        login_tokens[(login_tokens)]
        refresh_tokens[(refresh_tokens)]
        user_visits[(user_visits)]
    end

    User -->|1. Visit app| MW1
    MW1 -->|?code= or cookie| MW2
    MW2 --> MW3
    MW3 --> MW4
    MW4 -->|validate session| AuthAPI
    MW5 -->|no token → redirect| LoginPage
    MW4 -->|valid| AppPage
    MW4 -->|record visit| user_visits

    LoginPage -->|login| AuthAPI
    AuthAPI --> AuthSvc
    AuthSvc --> users
    AuthSvc --> tenants
    AuthSvc --> login_tokens
    AuthSvc --> refresh_tokens
    AuthSvc --> app_permissions
    AuthSvc --> JwtSvc
    JwtSvc -->|JWT with claims| AuthAPI
    AuthAPI -->|token + authCode| LoginPage
    LoginPage -->|redirect ?code=| MW1
    MW1 -->|exchange code| AuthAPI
```

---

## 2. Consumer App Middleware Pipeline

Order registered by `app.UseDedgeAuth()`:

```mermaid
flowchart TD
    Request([HTTP Request])

    Request --> TE{DedgeAuthTokenExtraction\nMiddleware}

    TE -->|"?code=X"| Exchange[POST /api/auth/exchange\nto DedgeAuth server]
    Exchange -->|JWT returned| SetCookie1[Set DedgeAuth_access_token\ncookie]
    SetCookie1 --> Redirect1[302 Redirect to clean URL]

    TE -->|"?token=X"| SetCookie2[Set DedgeAuth_access_token\ncookie]
    SetCookie2 --> Redirect2[302 Redirect to clean URL]

    TE -->|cookie exists| SetHeader[Set Authorization:\nBearer JWT header]
    TE -->|no token at all| PassThrough[Continue pipeline]

    SetHeader --> Auth[UseAuthentication\nJWT Bearer validation]
    PassThrough --> Auth

    Auth --> Authz[UseAuthorization\nPolicy evaluation]

    Authz --> SV{DedgeAuthSession\nValidation\nMiddleware}
    SV -->|cached valid| RecordVisit[Fire-and-forget:\nPOST /api/visits/record]
    RecordVisit --> App([App Page])
    SV -->|cache miss| Validate[GET /api/auth/validate\non DedgeAuth server]
    Validate -->|valid=true| CacheResult[Cache 30s + record visit]
    CacheResult --> App
    Validate -->|valid=false| ClearCookie[Delete cookie]
    ClearCookie --> Redir

    SV -->|not authenticated| Redir

    Authz -->|not authenticated| RM{DedgeAuthRedirect\nMiddleware}
    RM -->|API path /api/| Return401([401 Unauthorized])
    RM -->|Page request| Redir[302 Redirect to\n/DedgeAuth/login.html\n?returnUrl=...]

    style Exchange fill:#e0f2fe
    style Validate fill:#e0f2fe
    style RecordVisit fill:#fef3c7
```

**Database interactions:**

| Step | Table | Operation |
|---|---|---|
| Exchange auth code | `login_tokens` | READ + UPDATE (mark used) |
| Exchange auth code | `users`, `tenants` | READ (load user + tenant) |
| Exchange auth code | `app_permissions` | READ (get roles) |
| Exchange auth code | `refresh_tokens` | INSERT (new refresh token) |
| Validate session | `refresh_tokens` | READ (check active sessions) |
| Record visit | `user_visits` | INSERT |

---

## 3. Password Login Flow

```mermaid
flowchart TD
    Start([User enters email + password\non login.html])
    Start --> PostLogin[POST /api/auth/login]
    PostLogin --> LookupUser{Lookup user\nby email}

    LookupUser -->|"found"| CheckActive{user.is_active?}
    LookupUser -->|"not found"| CheckDomain{Domain allowed?}

    CheckDomain -->|no| Fail1([401: Invalid email\nor password])
    CheckDomain -->|yes| ValidatePw{Password meets\nrequirements?}
    ValidatePw -->|no| FailWeak([400: Password\ntoo weak])
    ValidatePw -->|yes| AutoProvision[Auto-provision user]

    AutoProvision -->|"INSERT users\n(EmailVerified=false)"| NewUser[New user created]
    NewUser --> GenTokens

    CheckActive -->|no| Fail2([401: Account\ninactive])
    CheckActive -->|yes| CheckLockout{user.is_locked_out?}

    CheckLockout -->|yes| Fail3([401: Invalid email\nor password])
    CheckLockout -->|no| CheckHash{password_hash\nis null?}

    CheckHash -->|null| Fail4([401: Use\nmagic link])
    CheckHash -->|set| VerifyBcrypt{BCrypt.Verify\npassword}

    VerifyBcrypt -->|invalid| IncFailed[failed_login_count++]
    IncFailed --> CheckMaxFailed{">= max\nattempts?"}
    CheckMaxFailed -->|yes| Lockout[Set lockout_until\nSend lockout email]
    Lockout --> Fail5([401: Invalid email\nor password])
    CheckMaxFailed -->|no| Fail5

    VerifyBcrypt -->|valid| ResetCounters[failed_login_count = 0\nlockout_until = null\nlast_login_at = now]
    ResetCounters --> GenTokens

    GenTokens[Generate tokens]
    GenTokens --> GetRoles[Get app roles]
    GetRoles --> GenJWT[JwtTokenService:\nGenerate access token]
    GenJWT --> CreateRefresh[Create refresh token]
    CreateRefresh --> CreateAuthCode[Create auth code\n60s expiry]

    CreateAuthCode --> Response([200: accessToken\nauthCode, user info\nisNewUser])

    Response --> StoreLocal[login.html:\nlocalStorage.set token]
    StoreLocal --> CheckReturn{returnUrl\nexists?}
    CheckReturn -->|yes| RedirectApp[Redirect to app\nwith ?code=authCode]
    CheckReturn -->|no| ShowLoggedIn[Show logged-in state\nwith app links]

    style AutoProvision fill:#dcfce7
    style Lockout fill:#fee2e2
    style GenTokens fill:#e0f2fe
```

**Database interactions:**

| Step | Table | Operation |
|---|---|---|
| Lookup user | `users` + `tenants` | SELECT (join) |
| Auto-provision | `users` | INSERT |
| Auto-provision | `tenants` | SELECT (resolve from domain) |
| Failed login | `users` | UPDATE (increment counter) |
| Lockout | `users` | UPDATE (set lockout_until) |
| Successful login | `users` | UPDATE (reset counters, last_login) |
| Get app roles | `app_permissions` + `apps` | SELECT (join) |
| Generate JWT | - | In-memory (claims from user/tenant/roles) |
| Create refresh token | `refresh_tokens` | INSERT |
| Create auth code | `login_tokens` | INSERT (type=AuthCode, 60s expiry) |

---

## 4. Magic Link Login Flow

```mermaid
flowchart TD
    Start([User enters email\non Magic Link tab])
    Start --> PostRequest[POST /api/auth/request-login]
    PostRequest --> LookupUser{Lookup user\nby email}

    LookupUser -->|"not found"| CheckDomain{Domain allowed?}
    CheckDomain -->|no| GenericMsg([200: If registered\nyou will receive link])
    CheckDomain -->|yes| AutoProvision[Auto-provision user\nEmailVerified=false\nno password]
    AutoProvision --> SendLink

    LookupUser -->|"found"| CheckActive{is_active?}
    CheckActive -->|no| GenericMsg
    CheckActive -->|yes| CheckLocked{is_locked_out?}
    CheckLocked -->|yes| FailLocked([400: Account locked])
    CheckLocked -->|no| SendLink

    SendLink[Create login token\n15min expiry]
    SendLink --> Email[Send magic link email\nwith /api/auth/verify?token=X]
    Email --> GenericMsg

    subgraph "User clicks email link"
        ClickLink([GET /api/auth/verify?token=X])
        ClickLink --> FindToken{Find login_token\ntype=Login}
        FindToken -->|not found| ErrorPage([Redirect to\nlogin.html?error=...])
        FindToken -->|expired/used| ErrorPage
        FindToken -->|valid| MarkUsed[Mark token used\nis_used=true, used_at=now]
        MarkUsed --> UpdateUser[last_login_at = now\nfailed_login_count = 0]
        UpdateUser --> GenTokens[Generate JWT\n+ refresh token\n+ auth code]
    end

    GenTokens --> CheckReturnUrl{returnUrl\nin query?}
    CheckReturnUrl -->|yes| RedirectApp[302 Redirect to app\nwith ?code=authCode]
    CheckReturnUrl -->|no| RedirectLogin[302 Redirect to\nlogin.html?success=true\n&token=JWT]

    style AutoProvision fill:#dcfce7
    style SendLink fill:#e0f2fe
    style Email fill:#fef3c7
```

**Database interactions:**

| Step | Table | Operation |
|---|---|---|
| Lookup user | `users` + `tenants` | SELECT |
| Auto-provision | `users` | INSERT |
| Create login token | `login_tokens` | INSERT (type=Login, 15min) |
| Verify token | `login_tokens` + `users` + `tenants` | SELECT (join) |
| Mark used | `login_tokens` | UPDATE (is_used, used_at, used_ip) |
| Update user | `users` | UPDATE (last_login_at) |
| Get app roles | `app_permissions` + `apps` | SELECT |
| Create refresh token | `refresh_tokens` | INSERT |
| Create auth code | `login_tokens` | INSERT (type=AuthCode) |

---

## 5. Windows/Kerberos SSO Flow

```mermaid
flowchart TD
    Start([Page loads login.html])
    Start --> AutoProbe[Silent GET /api/auth/windows-probe\nAllowAnonymous + credentials:include]

    AutoProbe --> CheckIdentity{IIS passed\nKerberos ticket?}
    CheckIdentity -->|no| ShowForm([Show login form\ndim Windows button])

    CheckIdentity -->|yes| HandleCore[HandleWindowsLoginCoreAsync]

    HandleCore --> ExtractName[Extract sAMAccountName\nfrom DOMAIN\\user]
    ExtractName --> LdapLookup[LDAP DirectorySearcher\non DEDGE.fk.no]
    LdapLookup --> GetAdInfo["Get: mail, displayName,\nuserPrincipalName, memberOf"]
    GetAdInfo --> CollectGroups[Collect AD group\nmemberships from\nKerberos claims + LDAP memberOf]

    CollectGroups --> CallService[AuthService.LoginWithWindowsAsync]

    CallService --> ResolveTenant{Resolve tenant\nfrom email domain}
    ResolveTenant -->|"not found or\nSSO disabled"| SsoDisabled([Return ssoDisabled\n→ redirect to register.html])

    ResolveTenant -->|"SSO enabled"| FindUser{Find user\nby email}

    FindUser -->|"not found"| CreateUser["Auto-create user\nIsActive=true\nEmailVerified=true\nAuthMethod=windows"]
    CreateUser --> WelcomeEmail[Fire-and-forget:\nSend welcome email]

    FindUser -->|"found"| CheckInactive{is_active?}
    CheckInactive -->|no| FailInactive([401: Account\ninactive])
    CheckInactive -->|yes| UpdateUser[Update display name\nAuthMethod=windows\nlast_login_at=now]

    CreateUser --> GetRoles
    UpdateUser --> GetRoles

    GetRoles[Get app roles\n+ implicit minimum access]
    GetRoles --> GenJWT["Generate JWT with:\n- user claims\n- appPermissions\n- adGroups\n- tenant info"]
    GenJWT --> CreateRefresh[Create refresh token]
    CreateRefresh --> CreateCode[Create auth code]
    CreateCode --> Response([200: accessToken\nauthCode, isNewUser])

    Response --> ClientStore[login.html:\nlocalStorage.set token]
    ClientStore --> CheckReturn{returnUrl?}
    CheckReturn -->|yes| RedirectApp[Redirect to app\nwith ?code=authCode]
    CheckReturn -->|no| ShowApps[Show logged-in state\nwith app links]

    subgraph "Manual Windows Login (button click)"
        WinBtn([Click 'Sign in with Windows'])
        WinBtn --> GetWinLogin[GET /api/auth/windows-login\nAuthorize Policy=WindowsAuth]
        GetWinLogin --> Challenge401[IIS returns 401\nNegotiate challenge]
        Challenge401 --> BrowserNego[Browser sends\nKerberos ticket]
        BrowserNego --> HandleCore
    end

    style CreateUser fill:#dcfce7
    style WelcomeEmail fill:#fef3c7
    style GetRoles fill:#e0f2fe
```

**Database interactions:**

| Step | Table | Operation |
|---|---|---|
| Resolve tenant | `tenants` | SELECT (by domain, check WindowsSsoEnabled) |
| Find user | `users` + `tenants` | SELECT |
| Orphan cleanup | `users`, `app_permissions`, `user_visits`, `login_tokens`, `refresh_tokens`, `access_requests` | DELETE |
| Auto-create user | `users` | INSERT (EmailVerified=true) |
| Update user | `users` | UPDATE (display name, auth_method, last_login) |
| Get app roles | `app_permissions` + `apps` | SELECT |
| Implicit min access | `apps` | SELECT (all active apps, assign lowest role) |
| Create refresh token | `refresh_tokens` | INSERT |
| Create auth code | `login_tokens` | INSERT (type=AuthCode) |

---

## 6. Auth Code Exchange Flow (Consumer App ↔ DedgeAuth)

```mermaid
sequenceDiagram
    participant Browser
    participant ConsumerApp as Consumer App<br/>(e.g. DocView)
    participant DedgeAuth as DedgeAuth Server
    participant DB as PostgreSQL

    Note over Browser,DedgeAuth: User completed login on DedgeAuth

    DedgeAuth->>Browser: 302 Redirect to /DocView/?code=ABC123

    Browser->>ConsumerApp: GET /DocView/?code=ABC123

    Note over ConsumerApp: DedgeAuthTokenExtractionMiddleware<br/>detects ?code= parameter

    ConsumerApp->>DedgeAuth: POST /api/auth/exchange<br/>{ "code": "ABC123" }

    DedgeAuth->>DB: SELECT login_tokens WHERE token='ABC123'<br/>AND type='AuthCode'
    DB-->>DedgeAuth: Token record (user_id, expires_at, is_used)

    alt Token valid (not used, not expired)
        DedgeAuth->>DB: UPDATE login_tokens SET is_used=true
        DedgeAuth->>DB: SELECT users + tenants (by user_id)
        DedgeAuth->>DB: SELECT app_permissions + apps (by user_id)
        DedgeAuth->>DB: INSERT refresh_tokens (new session)
        DedgeAuth-->>ConsumerApp: 200: { accessToken, user }
        ConsumerApp->>Browser: Set-Cookie: DedgeAuth_access_token=JWT
        ConsumerApp->>Browser: 302 Redirect to /DocView/
        Browser->>ConsumerApp: GET /DocView/ (with cookie)
        Note over ConsumerApp: Cookie → Authorization header<br/>JWT validated → page served
    else Token invalid/expired/used
        DedgeAuth-->>ConsumerApp: 401: Invalid auth code
        ConsumerApp->>Browser: Redirect to /DedgeAuth/login.html
    end
```

---

## 7. Token Refresh Flow

```mermaid
sequenceDiagram
    participant Browser
    participant LoginPage as login.html
    participant DedgeAuth as DedgeAuth API
    participant DB as PostgreSQL

    Note over Browser: User visits login.html<br/>with ?returnUrl=/SomeApp/

    Browser->>LoginPage: GET /DedgeAuth/login.html?returnUrl=...

    Note over LoginPage: tryAutoRefresh() checks<br/>for refreshToken cookie

    LoginPage->>DedgeAuth: POST /api/auth/refresh<br/>(credentials: include → sends cookie)

    DedgeAuth->>DB: SELECT refresh_tokens<br/>WHERE token = cookie_value
    DB-->>DedgeAuth: Token + user + tenant

    alt Refresh token active (not revoked, not expired)
        DedgeAuth->>DB: UPDATE refresh_tokens<br/>SET is_revoked=true (old token)
        DedgeAuth->>DB: INSERT refresh_tokens (new token)
        DedgeAuth->>DB: SELECT app_permissions + apps
        DedgeAuth->>DB: INSERT login_tokens (auth code)
        DedgeAuth-->>LoginPage: 200: { accessToken, authCode }
        LoginPage->>Browser: Set-Cookie: refreshToken=NEW
        LoginPage->>Browser: Redirect to /SomeApp/?code=authCode
    else Refresh token invalid
        DedgeAuth-->>LoginPage: 401: Invalid refresh token
        Note over LoginPage: Show login form
    end
```

**Database interactions:**

| Step | Table | Operation |
|---|---|---|
| Find refresh token | `refresh_tokens` + `users` + `tenants` | SELECT (join) |
| Revoke old token | `refresh_tokens` | UPDATE (is_revoked, revoked_at, replaced_by_token) |
| Create new refresh token | `refresh_tokens` | INSERT |
| Get app roles | `app_permissions` + `apps` | SELECT |
| Create auth code | `login_tokens` | INSERT |

---

## 8. Per-App-Click Fresh Auth Code Flow

```mermaid
sequenceDiagram
    participant User
    participant LoginPage as login.html<br/>(logged in state)
    participant DedgeAuth as DedgeAuth API
    participant DB as PostgreSQL
    participant App as Consumer App

    Note over LoginPage: User sees app links<br/>after successful login

    User->>LoginPage: Click "DocView" link
    Note over LoginPage: navigateWithFreshCode()<br/>prevents default link

    LoginPage->>DedgeAuth: POST /api/auth/create-code<br/>Authorization: Bearer JWT

    DedgeAuth->>DB: INSERT login_tokens<br/>(type=AuthCode, 60s expiry)
    DB-->>DedgeAuth: code = "XYZ789"
    DedgeAuth-->>LoginPage: 200: { code: "XYZ789" }

    LoginPage->>App: window.open(/DocView/?code=XYZ789)

    Note over App: DedgeAuthTokenExtractionMiddleware<br/>exchanges code for JWT (see flow 6)
```

---

## 9. Registration + Access Request Flow

```mermaid
flowchart TD
    Start([User visits register.html])
    Start --> FillForm[Enter email, name,\npassword, select apps]
    FillForm --> PostRegister[POST /api/auth/register]

    PostRegister --> CheckDomain{Domain\nallowed?}
    CheckDomain -->|no| Reject([400: Domain\nnot allowed])
    CheckDomain -->|yes| CheckExists{User\nexists?}
    CheckExists -->|yes| Reject2([400: Account\nalready exists])
    CheckExists -->|no| CreateUser["INSERT users\nEmailVerified=false\n(pending admin approval)"]

    CreateUser --> CheckAppReqs{App access\nrequests?}
    CheckAppReqs -->|yes| CreateRequests["INSERT access_requests\nfor each app\nstatus=Pending"]
    CheckAppReqs -->|no| Done

    CreateRequests --> Done([200: Registration\nsuccessful])

    subgraph "Admin Approval"
        AdminView([Admin opens\nadmin.html → Pending])
        AdminView --> SeePending[Sees user in\nPending Approvals]
        SeePending --> ApproveUser["POST /users/{id}/approve\nSets EmailVerified=true\nIsActive=true"]
        ApproveUser --> SeeRequests[Sees access\nrequests below]
        SeeRequests --> ApproveAccess["POST /access-requests/{id}/approve\nINSERT app_permissions\nwith chosen role"]
    end

    style CreateUser fill:#dcfce7
    style CreateRequests fill:#fef3c7
    style ApproveUser fill:#e0f2fe
    style ApproveAccess fill:#e0f2fe
```

**Database interactions:**

| Step | Table | Operation |
|---|---|---|
| Check domain | config | In-memory (AllowedDomain) |
| Check existing | `users` | SELECT |
| Create user | `users` | INSERT |
| Resolve tenant | `tenants` | SELECT (by email domain) |
| Create access requests | `access_requests` + `apps` | SELECT app + INSERT request |
| Approve user | `users` | UPDATE (email_verified, is_active) |
| Approve access request | `access_requests` | UPDATE (status=Approved) |
| Grant permission | `app_permissions` | INSERT or UPDATE |

---

## 10. Complete Database Interaction Map

Summary of which tables are touched by each authentication operation:

| Operation | users | tenants | apps | app_permissions | login_tokens | refresh_tokens | user_visits | access_requests |
|---|---|---|---|---|---|---|---|---|
| **Register** | INSERT | READ | READ | - | - | - | - | INSERT |
| **Password Login** | READ/UPDATE | READ | READ | READ | INSERT | INSERT | - | - |
| **Password Login (new)** | INSERT | READ | READ | READ | INSERT | INSERT | - | - |
| **Magic Link Request** | READ | READ | - | - | INSERT | - | - | - |
| **Magic Link Request (new)** | INSERT | READ | - | - | INSERT | - | - | - |
| **Magic Link Verify** | UPDATE | READ | READ | READ | UPDATE | INSERT | - | - |
| **Windows SSO** | READ/INSERT | READ | READ | READ | INSERT | INSERT | - | - |
| **Auth Code Exchange** | READ | READ | READ | READ | UPDATE | INSERT | - | - |
| **Token Refresh** | READ | READ | READ | READ | INSERT | INSERT/UPDATE | - | - |
| **Create Code** | - | - | - | - | INSERT | - | - | - |
| **Session Validate** | - | - | - | - | - | READ | INSERT | - |
| **Logout** | - | - | - | - | - | UPDATE | - | - |
| **Approve User** | UPDATE | - | - | - | - | - | - | - |
| **Approve Request** | - | - | - | INSERT | - | - | - | UPDATE |

---

## 11. JWT Token Claims Structure

Every JWT issued by DedgeAuth contains these claims:

```json
{
  "sub": "user-guid",
  "email": "user@Dedge.no",
  "name": "Display Name",
  "globalAccessLevel": "3",
  "globalAccessLevelName": "Admin",
  "language": "nb",
  "department": "IT",
  "appPermissions": "{\"DocView\":\"Admin\",\"GenericLogHandler\":\"Admin\"}",
  "adGroups": "[\"DEDGE\\\\ACL_AppHub_RW\",\"DEDGE\\\\Domain Users\"]",
  "tenant": "{\"id\":\"...\",\"domain\":\"Dedge.no\",\"displayName\":\"Dedge\",\"primaryColor\":\"#008942\",\"appRouting\":{...},\"supportedLanguages\":[\"nb\",\"en\"]}",
  "iss": "DedgeAuth",
  "aud": "FKApps",
  "exp": 1742650800
}
```

| Claim | Source | Used By |
|---|---|---|
| `sub` | `users.id` | All authorization checks |
| `email` | `users.email` | Display, audit |
| `name` | `users.display_name` | User menu |
| `globalAccessLevel` | `users.global_access_level` | Admin access policies |
| `language` | `users.preferred_language` | i18n loader |
| `department` | `users.department` | Display |
| `appPermissions` | `app_permissions` JOIN `apps` | Consumer app `[RequireAppPermission]` |
| `adGroups` | Kerberos claims + LDAP memberOf | `app_groups.acl_groups_json` visibility |
| `tenant` | `tenants` (id, domain, colors, routing) | Theme CSS, app switcher, logo |

---

## 12. Auto-Provisioning Decision Matrix

```mermaid
flowchart LR
    Login{Login\nMethod}

    Login -->|Password| PW{User\nexists?}
    PW -->|yes| PWLogin[Normal password\nverification]
    PW -->|no + domain OK| PWAuto["Auto-create\nEmailVerified=false\nSet password\n→ Pending approval"]
    PW -->|no + domain bad| PWFail[Reject]

    Login -->|Magic Link| ML{User\nexists?}
    ML -->|yes| MLSend[Send magic link]
    ML -->|no + domain OK| MLAuto["Auto-create\nEmailVerified=false\nNo password\n→ Send link"]
    ML -->|no + domain bad| MLSilent[Silent no-op]

    Login -->|Windows SSO| WIN{User\nexists?}
    WIN -->|yes| WINLogin[Login with\nminimum access]
    WIN -->|no + SSO on| WINAuto["Auto-create\nEmailVerified=true\nMinimum access\n→ Immediate"]
    WIN -->|no + SSO off| WINReg[Redirect to\nregister.html]

    style PWAuto fill:#fef3c7
    style MLAuto fill:#fef3c7
    style WINAuto fill:#dcfce7
```

| Method | Auto-provision | EmailVerified | Needs Admin Confirmation | Immediate Access |
|---|---|---|---|---|
| Password (new user) | Yes, if domain allowed | `false` | Yes (appears in pending) | Yes (limited) |
| Magic Link (new user) | Yes, if domain allowed | `false` | Yes (appears in pending) | Yes (after clicking link) |
| Windows/Kerberos (new user) | Yes, if tenant SSO enabled | `true` | No | Yes (minimum access to all apps) |
| Registration page | Yes, if domain allowed | `false` | Yes (appears in pending) | After admin approval |
