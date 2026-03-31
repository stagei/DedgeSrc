# DedgeAuth Frontend Assets

DedgeAuth serves JS and CSS assets from its API server. Consumer apps load these through a **local proxy** provided by `MapDedgeAuthProxy()` — do NOT copy them locally and do NOT hardcode server URLs.

## Asset Proxy

The `MapDedgeAuthProxy()` call in `Program.cs` registers a UI asset proxy at `{ProxyRoutePrefix}/ui/{path}` (default: `/api/DedgeAuth/ui/{path}`). This proxy fetches assets from the DedgeAuth API server (configured in `AuthServerUrl`) and caches them for 1 hour.

| Asset | Proxy Path (relative) | DedgeAuth Server Path |
|-------|----------------------|-------------------|
| Common CSS | `api/DedgeAuth/ui/common.css` | `/api/ui/common.css` |
| User Menu CSS | `api/DedgeAuth/ui/user.css` | `/api/ui/user.css` |
| User Menu JS | `api/DedgeAuth/ui/user.js` | `/api/ui/user.js` |
| Theme JS | `api/DedgeAuth/ui/theme.js` | `/api/ui/theme.js` |
| Tenant fallback CSS | `api/DedgeAuth/ui/tenant-fallback.css` | `/api/ui/tenant-fallback.css` |
| i18n Loader JS | `api/DedgeAuth/ui/i18n.js` | `/api/ui/i18n.js` |
| Shared translations | `api/DedgeAuth/ui/i18n/{lang}.json` | `/api/ui/i18n/{lang}.json` |

**CRITICAL — Relative Paths for ALL Assets:** All FK web apps run as IIS virtual applications (e.g. at `/GenericLogHandler`). **ALL** `href` and `src` references in HTML must use **relative paths** (no leading `/`) — this applies to DedgeAuth proxy assets AND your app's own CSS/JS files. An absolute path like `/css/app.css` resolves from the site root and will 404 when the app is at a sub-path. Use `css/app.css` instead.

## HTML Integration

### Minimal HTML Template

```html
<!DOCTYPE html>
<html lang="en">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>Your App</title>

    <!-- Your app's own CSS first -->
    <link rel="stylesheet" href="css/app.css">

    <!-- DedgeAuth common theme (CSS variables, components) — via local proxy -->
    <link rel="stylesheet" href="api/DedgeAuth/ui/common.css">

    <!-- Tenant-specific CSS (injected dynamically by DedgeAuth-user.js) -->
    <style id="DedgeAuth-tenant-css"></style>

    <!-- DedgeAuth user menu styles (loaded last for proper cascade) — via local proxy -->
    <link rel="stylesheet" href="api/DedgeAuth/ui/user.css">
</head>
<body>
    <header>
        <h1>Your App</h1>
        <div class="header-actions">
            <!-- User menu renders here automatically -->
            <div id="DedgeAuthUserMenu"></div>
        </div>
    </header>

    <main>
        <!-- Your app content -->
    </main>

    <!-- DedgeAuth user menu JS (auto-initializes on DOMContentLoaded) — via local proxy -->
    <script src="api/DedgeAuth/ui/user.js"></script>

    <!-- DedgeAuth i18n loader (applies translations from wwwroot/i18n/{lang}.json) — via local proxy -->
    <script src="api/DedgeAuth/ui/i18n.js"></script>

    <!-- Your app's own JS — also relative paths, no leading / -->
    <script src="js/api.js"></script>
    <script src="js/app.js"></script>
</body>
</html>
```

### CSS Loading Order

Order matters for proper style cascade:

1. **Your app CSS** — loaded first (app-specific component styles and layout)
2. **DedgeAuth common CSS** — provides CSS variables and shared component styles via proxy
3. **Optional: Tenant fallback CSS** — `<link rel="stylesheet" href="api/DedgeAuth/ui/tenant-fallback.css">` for immediate default branding when tenant theme is not yet loaded or fails (see [CSS Fallback Plan](css-fallback-plan.md))
4. **Tenant CSS** — injected dynamically via `<style id="DedgeAuth-tenant-css"></style>` (tenant override from API, or DedgeAuth default injected by `DedgeAuth-user.js` when empty/failed)
5. **DedgeAuth user menu CSS** — loaded last for user menu styles

This ordering ensures tenant CSS can override common CSS variables (colors, shadows, borders) while leaving your app-specific component styles untouched. When tenant theme is empty or unreachable, `DedgeAuth-user.js` injects the DedgeAuth default fallback into `#DedgeAuth-tenant-css`; an optional link to `tenant-fallback.css` can reduce flash of unstyled content.

### Required HTML Elements

| Element | Required | Purpose |
|---------|----------|---------|
| `<div id="DedgeAuthUserMenu"></div>` | Yes | Container for the user menu component |
| `<style id="DedgeAuth-tenant-css"></style>` | Recommended | Target for tenant-specific CSS injection |

### Tenant CSS Injection Flow

The `DedgeAuth-user.js` script handles tenant CSS injection automatically:

1. On `DOMContentLoaded`, the script calls `/api/DedgeAuth/me` to get the authenticated user's tenant domain
2. It then fetches `{DedgeAuthUrl}/tenants/{domain}/theme.css` (served by `TenantsController`)
3. The CSS content is read from the `tenants.css_overrides` column in the database
4. The CSS is injected into the `<style id="DedgeAuth-tenant-css"></style>` element on the page

Tenant CSS typically overrides **common CSS variables** (brand colors, shadows, border styles) without touching app-specific component styles. This means all apps under a tenant get consistent branding while retaining their own layout and component styling.

When the tenant theme is **empty** or the theme.css **fetch fails**, `DedgeAuth-user.js` automatically injects DedgeAuth default fallback styles (same as `tenant-fallback.css`) into `#DedgeAuth-tenant-css`. See [CSS Fallback Plan](css-fallback-plan.md) for details.

> **Important:** The `<style id="DedgeAuth-tenant-css"></style>` element must be present in the HTML and positioned **after** the DedgeAuth common CSS link and **before** the user menu CSS link. If the element is missing, tenant CSS overrides will not be applied.

## User Menu Behavior

The `DedgeAuth-user.js` script auto-initializes on `DOMContentLoaded`:

1. Checks for `?token=` in URL query string
2. If found, stores token in `sessionStorage` as `gk_accessToken` and removes it from URL
3. Fetches `/api/DedgeAuth/me` to get user info
4. If authenticated, renders the user menu into `#DedgeAuthUserMenu`
5. If tenant has CSS overrides, injects them into `#DedgeAuth-tenant-css`

### User Menu Features

- User avatar (initials)
- User name, email, role, tenant
- Language selector (flag buttons for supported languages)
- App switcher (links to other apps from tenant routing, passes token via SSO)
- Link to DedgeAuth Portal (if user is authenticated)
- Link to DedgeAuth Admin Dashboard (if user is GlobalAdmin)
- Logout button

### JavaScript Helpers

The user menu JS exposes static helpers for use in your app code:

```javascript
// Get the current access token
const token = DedgeAuthUserMenu.getAccessToken();

// Get Authorization headers for fetch calls
const headers = DedgeAuthUserMenu.getAuthHeaders();
// Returns: { "Authorization": "Bearer <token>" }

// Use in fetch (relative path — no leading / for IIS virtual app compatibility)
const response = await fetch('api/data', {
    headers: DedgeAuthUserMenu.getAuthHeaders()
});
```

## Multi-Language (i18n)

DedgeAuth provides a distributed i18n system. The user's preferred language is stored in DedgeAuth and distributed via JWT claims and the `/me` endpoint. Each app owns its own translation files.

### Quick Start

1. Create `wwwroot/i18n/nb.json` and `wwwroot/i18n/en.json` with all translatable strings
2. Add `<script src="api/DedgeAuth/ui/i18n.js"></script>` before `</body>`
3. Add `data-i18n="key"` attributes to static text elements
4. Use `DedgeAuth.t('key', 'fallback')` in JavaScript for dynamic content

See [i18n Integration Guide](i18n-guide.md) for full documentation.

## Theme Toggle

If your app includes a theme toggle, the DedgeAuth common CSS provides CSS variables for both light and dark themes via the `[data-theme="dark"]` attribute on `<html>`.

To add theme toggle support:

1. Include `common.css` from DedgeAuth API
2. Include `theme.js` from DedgeAuth API (optional, for the toggle component)
3. Or implement your own toggle that sets `document.documentElement.setAttribute('data-theme', 'dark')`

## Server Portability

Because HTML files reference assets through the local proxy (`api/DedgeAuth/ui/...`) and `AuthServerUrl` is always `http://localhost/DedgeAuth`, **no configuration changes are needed when deploying to a new server**:

1. `AuthServerUrl` stays as `http://localhost/DedgeAuth` on all servers (server-to-server calls go over localhost)
2. Browser-facing URLs (login redirects, asset URLs) are derived dynamically from the HTTP request by `DedgeAuthOptions.GetClientFacingAuthUrl()`
3. No HTML, JavaScript, or `appsettings.json` changes needed

## Assets Discovery Endpoint

The DedgeAuth API provides an assets discovery endpoint (useful for debugging, not needed for normal integration):

```
GET {DedgeAuthUrl}/api/ui/assets
```

Response (URLs are environment-specific):

```json
{
  "DedgeAuthUrl": "{AuthServerUrl}",
  "scripts": {
    "theme": "{AuthServerUrl}/api/ui/theme.js",
    "user": "{AuthServerUrl}/api/ui/user.js"
  },
  "styles": {
    "common": "{AuthServerUrl}/api/ui/common.css",
    "user": "{AuthServerUrl}/api/ui/user.css"
  }
}
```

---

*Last updated: 2026-02-18*
