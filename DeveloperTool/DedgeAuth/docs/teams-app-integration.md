# Microsoft Teams App Integration Evaluation

This document evaluates how the FK consumer web apps (DocView, GenericLogHandler, ServerMonitorDashboard, AutoDocJson) could be installed as Microsoft Teams apps, and what impact this has on DedgeAuth authorization.

> **Status:** Future planning document. Not yet implemented.

---

## 1. Teams App Types

Microsoft Teams supports several app integration models:

| Type | Description | Relevance |
|------|-------------|-----------|
| **Personal Tab** | Web page embedded as an iframe in the Teams left sidebar | High -- best fit for our web apps |
| **Channel Tab** | Web page pinned to a Teams channel | Medium -- possible for shared dashboards |
| **Bot** | Conversational interface | Low -- our apps are UI-driven, not chat-driven |
| **Message Extension** | Search/action from compose box | Low -- not applicable |
| **Connector** | Incoming webhooks to channels | Low -- could be useful for alerts only |

**Recommendation**: Personal tabs are the natural fit. Each consumer app would appear as a tab in the user's Teams sidebar, loading the existing web UI inside an iframe.

---

## 2. What's Required for Teams Tab Integration

### 2.1 Teams App Manifest

Each app needs a manifest package (`.zip`) containing:

```
AppName.zip
├── manifest.json      ← App definition, tab URLs, permissions
├── color.png          ← 192x192 app icon
└── outline.png        ← 32x32 outline icon
```

Example `manifest.json` for GenericLogHandler:

```json
{
  "$schema": "https://developer.microsoft.com/json-schemas/teams/v1.25/MicrosoftTeams.schema.json",
  "manifestVersion": "1.25",
  "version": "1.0.0",
  "id": "<GUID>",
  "developer": {
    "name": "Dedge",
    "websiteUrl": "http://dedge-server/GenericLogHandler",
    "privacyUrl": "http://dedge-server/GenericLogHandler",
    "termsOfUseUrl": "http://dedge-server/GenericLogHandler"
  },
  "name": { "short": "Log Handler", "full": "Generic Log Handler" },
  "description": {
    "short": "Log aggregation and analysis",
    "full": "Centralized log aggregation, search, and analysis tool"
  },
  "icons": { "color": "color.png", "outline": "outline.png" },
  "staticTabs": [
    {
      "entityId": "logHandler",
      "name": "Log Handler",
      "contentUrl": "https://dedge-server/GenericLogHandler/index.html",
      "websiteUrl": "https://dedge-server/GenericLogHandler",
      "scopes": ["personal"]
    }
  ],
  "permissions": ["identity"],
  "validDomains": ["dedge-server"]
}
```

### 2.2 HTTPS Requirement

**Teams requires all tab content to be served over HTTPS.** Currently, all FK apps are served over HTTP (`http://dedge-server/...`).

| Requirement | Current State | Action Needed |
|-------------|--------------|---------------|
| HTTPS | HTTP only | Configure TLS certificate on IIS, or use a reverse proxy with TLS termination |

This is a **hard blocker** -- Teams will refuse to load HTTP content in tabs.

### 2.3 iframe Headers

The app server must allow Teams to embed pages in iframes by setting HTTP response headers:

```
Content-Security-Policy: frame-ancestors teams.microsoft.com *.teams.microsoft.com *.cloud.microsoft *.microsoft365.com *.office.com
X-Frame-Options: ALLOW-FROM https://teams.microsoft.com/
```

Currently, DedgeAuth and the consumer apps do **not** set these headers. ASP.NET Core's default behavior varies, but typically does not restrict iframe embedding.

**Action**: Add middleware or IIS configuration to set `Content-Security-Policy: frame-ancestors` headers on all consumer apps.

### 2.4 TeamsJS SDK

Each app's HTML pages would need the Microsoft Teams JavaScript SDK:

```html
<script src="https://res.cdn.office.net/teams-js/2.19.0/js/MicrosoftTeams.min.js"></script>
<script>
  microsoftTeams.app.initialize();
</script>
```

This is required for Teams to recognize the tab as a valid Teams app and to enable SSO.

---

## 3. Authentication: The Core Challenge

This is the most significant design decision. There are three possible approaches:

### Option A: Keep DedgeAuth As-Is (Popup Auth Flow)

Teams tabs support an authentication popup flow where the tab opens a popup window for login, then receives a token back.

**How it would work**:
1. User opens the tab in Teams
2. Tab detects no DedgeAuth token in `sessionStorage`
3. Tab calls `microsoftTeams.authentication.authenticate()` to open a popup
4. Popup navigates to `https://<server>/DedgeAuth/login.html`
5. User logs in with DedgeAuth credentials (email/password)
6. DedgeAuth issues JWT, popup sends token back to the tab via `notifySuccess(token)`
7. Tab stores token in `sessionStorage`, proceeds as normal

**Pros**:
- DedgeAuth authorization model stays unchanged
- Per-app roles, tenant routing, and all existing features work
- No dependency on Azure AD / Microsoft Entra ID
- Users authenticate with the same DedgeAuth credentials

**Cons**:
- Users must log in separately to DedgeAuth (no SSO with their Teams/Microsoft 365 account)
- Requires modifying `DedgeAuth-user.js` to detect Teams context and use popup flow instead of redirect
- Popup flow can feel clunky compared to seamless SSO
- DedgeAuth's redirect-based flow (`?token=` in URL) will NOT work inside an iframe -- **redirect auth is blocked by Teams**

**Changes required**:
- Modify `DedgeAuth-user.js` to detect Teams context (`microsoftTeams.app.getContext()`)
- Implement popup-based auth flow as alternative to redirect flow
- Modify `DedgeAuthRedirectMiddleware` to return 401 instead of redirect when Teams context is detected
- Add `frame-ancestors` headers

### Option B: Teams SSO with DedgeAuth Token Exchange

Use Microsoft Entra ID SSO to get the user's identity from Teams, then exchange it for a DedgeAuth JWT token.

**How it would work**:
1. User opens the tab in Teams
2. Tab calls `microsoftTeams.authentication.getAuthToken()` to get an Entra ID token silently (no popup)
3. Tab sends the Entra ID token to a new DedgeAuth endpoint: `POST /api/auth/teams-sso`
4. DedgeAuth validates the Entra ID token, looks up the user by email
5. If the user exists in DedgeAuth, issues a standard DedgeAuth JWT token
6. Tab proceeds as normal with the DedgeAuth token

**Pros**:
- Seamless SSO -- no login prompt, no popup
- DedgeAuth authorization model stays intact (roles, tenants, permissions all work)
- User identity comes from their corporate Microsoft 365 account
- Best user experience

**Cons**:
- Requires Azure App Registration (Entra ID) for the Teams app
- Requires a new endpoint in DedgeAuth API (`/api/auth/teams-sso`)
- Users must exist in DedgeAuth database -- if a Teams user hasn't been provisioned in DedgeAuth, they can't access apps
- Adds dependency on Microsoft identity platform
- More complex implementation

**Changes required**:
- Register app in Microsoft Entra ID (Azure Portal)
- New `TeamsAuthController` endpoint in DedgeAuth.Api that validates Entra ID tokens and issues DedgeAuth JWTs
- Modify `DedgeAuth-user.js` to detect Teams context and use SSO flow
- Configure CORS to allow Teams domains
- Add `frame-ancestors` headers

### Option C: Replace DedgeAuth with Entra ID Entirely

Remove DedgeAuth from the authentication chain and use Azure AD / Entra ID directly.

**Pros**:
- Native Teams SSO with zero friction
- Standard Microsoft identity platform
- No custom auth server to maintain

**Cons**:
- **Loses all DedgeAuth features**: per-app roles, tenant branding, app routing, admin dashboard, centralized user management
- Requires rewriting authorization in every consumer app
- Would need to migrate user data and permissions to Entra ID groups/app roles
- Massive effort, defeats the purpose of DedgeAuth

**Verdict**: Not recommended. DedgeAuth exists specifically because Entra ID doesn't provide the per-app role management and multi-tenant routing that these apps need.

---

## 4. Recommendation

### Option B (Teams SSO + DedgeAuth Token Exchange) is the best path

It provides the best user experience while preserving the full DedgeAuth authorization model.

### Implementation roadmap:

| Phase | Task | Effort |
|-------|------|--------|
| **1. Prerequisites** | Configure HTTPS on IIS for all apps | Medium |
| **2. Azure Registration** | Register Teams app in Entra ID, configure API permissions | Small |
| **3. DedgeAuth API** | Add `POST /api/auth/teams-sso` endpoint (validate Entra token, lookup user, issue DedgeAuth JWT) | Medium |
| **4. Client Detection** | Update `DedgeAuth-user.js` to detect Teams context and use SSO flow | Medium |
| **5. HTTP Headers** | Add `frame-ancestors` CSP headers to all consumer apps | Small |
| **6. App Manifest** | Create Teams app packages for each consumer app | Small |
| **7. Deployment** | Sideload or publish to Teams admin center | Small |

### Fallback for non-SSO scenarios

Even with Option B, the popup flow (Option A) should be implemented as a fallback:
- If SSO fails (token expired, consent needed)
- If the app is accessed outside Teams (normal browser flow still uses redirect)
- If Entra ID is not configured (graceful degradation)

---

## 5. Impact on DedgeAuth Authorization

### What stays the same (regardless of option chosen)

| Feature | Impact |
|---------|--------|
| Per-app roles (`[RequireAppPermission]`) | No change -- JWT token still contains `appPermissions` claim |
| Tenant routing / app switcher | No change -- `/api/DedgeAuth/me` response is the same |
| Tenant CSS branding | No change -- `DedgeAuth-user.js` still injects tenant CSS |
| Admin dashboard | No change -- accessed in browser, not in Teams |
| Session validation | No change -- `DedgeAuthSessionValidationMiddleware` validates the same JWT |
| UI asset proxy | No change -- `api/DedgeAuth/ui/{path}` proxy works the same in iframe |
| Token revocation / logout | Minor change -- logout inside Teams tab should close the tab or clear the token, not redirect to login.html |

### What changes

| Feature | Change |
|---------|--------|
| **Login flow** | New SSO/popup path alongside existing redirect flow |
| **User provisioning** | Users must exist in DedgeAuth before they can SSO. Could add auto-provisioning from Entra ID token claims |
| **CORS configuration** | Must add Teams domains to allowed origins |
| **HTTP headers** | Must add `frame-ancestors` for Teams embedding |
| **Logout behavior** | Cannot redirect to `/DedgeAuth/login.html` inside Teams -- must clear session and show "signed out" state |

### Key conclusion

**DedgeAuth's authorization model is fully compatible with Teams integration.** The JWT-based approach means that once a user has a valid DedgeAuth token (regardless of how they obtained it -- password login, redirect, popup, or SSO exchange), all downstream authorization works identically. The `appPermissions`, `tenant`, and `globalAccessLevel` claims in the JWT are the same no matter how the token was issued.

The only significant new requirement is a **token issuance pathway** that works inside Teams (SSO or popup), since the current redirect-based flow is blocked in iframes.

---

## 6. Open Questions

1. **Is HTTPS available or planned?** Teams tabs require HTTPS. Without it, none of these options work.
2. **Is an Azure App Registration feasible?** Option B requires registering the app in Microsoft Entra ID. Does the organization have access to the Azure portal?
3. **Auto-provisioning**: Should users who exist in Entra ID but not in DedgeAuth be automatically created on first SSO login? Or must they be pre-provisioned by an admin?
4. **Which apps need Teams integration?** All three, or just specific ones (e.g., ServerMonitorDashboard for on-call monitoring)?
5. **Teams admin center access**: Can custom apps be sideloaded, or must they be published through the organization's Teams app catalog?

---

*Last updated: 2026-02-12*
