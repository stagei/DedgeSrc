# CSS Fallback Plan

This document describes how DedgeAuth and consumer apps apply tenant branding with a reliable fallback when the tenant theme is empty or unreachable.

## Goals

1. **Prefer tenant override**: Use the current Dedge (or other tenant) CSS from the database when available (`tenants.css_overrides` via `/tenants/{domain}/theme.css`).
2. **Fallback when empty or unreachable**: When tenant theme is empty or the theme endpoint is unavailable, use DedgeAuth default fallback styles so the app still shows consistent branding (FK Green, variables, dark/light theme).

## Flow Overview

| Condition | Result |
|-----------|--------|
| Tenant has custom CSS in DB | Injected from `GET /tenants/{domain}/theme.css` into `#DedgeAuth-tenant-css` |
| Tenant has no custom CSS (empty) | Server returns `Theming:SystemDefaultCss` from appsettings; if that is minimal, client falls back to DedgeAuth default theme |
| theme.css fetch fails (network, 5xx) | `DedgeAuth-user.js` injects DedgeAuth default fallback from `api/DedgeAuth/ui/tenant-fallback.css` |
| Default tenant fetch fails (unauthenticated) | `DedgeAuth-user.js` injects DedgeAuth default fallback |

## Server-Side Fallback (DedgeAuth API)

- **TenantsController** `GetTenantThemeCss` uses `GetEffectiveCss(tenant?.CssOverrides)`.
- When `tenant.CssOverrides` is null or whitespace, the API returns `Theming:SystemDefaultCss` from `appsettings.json` (minimal variables).
- So the `/tenants/{domain}/theme.css` endpoint never returns an empty body; it always returns at least the system default.

## Client-Side Fallback (DedgeAuth-user.js)

When the **theme.css** fetch fails (network error, 4xx/5xx) or returns empty/whitespace content, the script:

1. Fetches `api/DedgeAuth/ui/tenant-fallback.css` via the consumer app’s existing DedgeAuth proxy (relative URL, same origin).
2. Injects the response into `#DedgeAuth-tenant-css`.

When the **default tenant** fetch fails (e.g. unauthenticated and DedgeAuth API unavailable), the script injects the same fallback CSS so the page still has default branding.

## DedgeAuth Default Fallback Asset

| Asset | Path (via proxy) | Purpose |
|-------|------------------|--------|
| Tenant fallback CSS | `api/DedgeAuth/ui/tenant-fallback.css` | DedgeAuth default theme (FK Green, light/dark variables). Same content as Dedge seeder theme. |

- **DedgeAuth server**: File lives at `wwwroot/css/tenant-fallback.css` and is served by `UIController` at `GET /api/ui/tenant-fallback.css`.
- **Consumer apps**: Load via proxy `api/DedgeAuth/ui/tenant-fallback.css` (no leading `/`). The proxy forwards to the DedgeAuth server.

## Optional: Local Fallback Link in HTML

For faster first paint or when you want fallback without waiting for JS, you can add a **link** to the fallback CSS before the tenant injection point. When tenant CSS is later injected into `#DedgeAuth-tenant-css`, it overrides the fallback; when it is not, the link provides the styles.

Recommended order:

1. App CSS  
2. DedgeAuth common CSS (`api/DedgeAuth/ui/common.css`)  
3. **Optional:** `<link rel="stylesheet" href="api/DedgeAuth/ui/tenant-fallback.css">`  
4. `<style id="DedgeAuth-tenant-css"></style>`  
5. DedgeAuth user CSS (`api/DedgeAuth/ui/user.css`)  

If you omit the optional link, `DedgeAuth-user.js` still injects the fallback when theme.css is empty or fails.

## DedgeAuth (login and admin) Pages

- **login.html** and **admin.html** load tenant theme via a dynamic `<link id="tenant-css" href="...">` or similar. If the theme endpoint fails or returns empty, those pages can:
  - Rely on the same fallback behaviour if they use `DedgeAuth-user.js` and `#DedgeAuth-tenant-css`, or  
  - Include a local fallback link to the same DedgeAuth default (e.g. relative `css/tenant-fallback.css` from DedgeAuth’s own wwwroot when served from DedgeAuth).

## Summary

- **Primary**: Use styles from the current tenant override (`/tenants/{domain}/theme.css` → `#DedgeAuth-tenant-css`).  
- **Fallback**: If that response is empty or the request fails, use DedgeAuth default fallback styles (`tenant-fallback.css`), either by JS injection or by an optional `<link>` in the document.

This keeps branding consistent across DedgeAuth and all consumer apps even when the tenant API is unavailable or the tenant has no custom CSS.

---

*Last updated: 2026-02-18*
