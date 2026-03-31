# DedgeAuth Tenant CSS Integration Check – AutoDocJson

**Reference:** `C:\opt\src\GenericLogHandler\Docs\DedgeAuth-Tenant-CSS-Integration-Guide.md`  
**Date:** 2025-02-18  
**Scope:** AutoDocJson.Web (DedgeAuth consumer) and its app CSS.

---

## 1. CSS load order in HTML

**Required order:** DedgeAuth common → DedgeAuth user → app CSS → `<style id="DedgeAuth-tenant-css"></style>`.

**Status: FIXED**

- **_Layout.cshtml** (only place CSS is loaded for Web app pages) was loading app CSS before DedgeAuth and tenant `<style>` between common and user.
- **Change:** Order is now:
  1. DedgeAuth common.css, DedgeAuth user.css  
  2. App CSS (Bootstrap, fonts, autodoc-shared.css, site.css)  
  3. `tenant-fallback.css` (local defaults when tenant API is unavailable)  
  4. `<style id="DedgeAuth-tenant-css"></style>` (tenant injects here; overrides fallback)  
- All asset paths use `~/` (app-relative); no leading `/` for DedgeAuth or app assets.

---

## 2. Duplicate theme variables in app CSS

**Guide:** Remove duplicate `:root` and `[data-theme="dark"]` from app CSS when they only repeat DedgeAuth/tenant variables.

**Status: PARTIAL (by design)**

- **autodoc-shared.css** still defines full `:root` and `[data-theme="dark"]` because the same file is inlined into **generated doc HTML** (via `[css]` in templates). Those pages do not load DedgeAuth and need their own theme variables.
- **Change:** Added a top-of-file comment that in the Web app, theme variables come from DedgeAuth common + tenant API; the blocks are kept for standalone generated doc pages.
- **site.css** never contained `:root` / `[data-theme="dark"]`; it only uses `var(--...)`. Added the same DedgeAuth/tenant comment at the top.

For full guide compliance (no duplicate vars in app CSS), you could split: one “theme vars only” file for generated docs and one “layout only” autodoc-shared for the Web app. Not done here to avoid breaking existing doc generation.

---

## 3. Hardcoded colours replaced with variables

**Status: FIXED where applicable**

**site.css:**

- `.type-badge.type-sql/cbl/bat/ps1/rex/csharp`: hex backgrounds replaced with `var(--success-color)`, `var(--accent-color)`, `var(--warning-color)`, `var(--info-color)`, `var(--error-color)` and fallbacks.
- `.btn-remove-filter:hover`: `#ef4444` → `var(--error-color)`.

**autodoc-shared.css:**

- `.badge-success`, `.badge-danger`: `#fff` → `var(--bg-primary)`.
- `.badge-warning`: `#000` → `var(--text-primary)`.

**Left as-is (intentional):**

- **autodoc-shared.css:** `.type-varchar`, `.type-integer`, etc. and their `[data-theme="dark"]` overrides use fixed hex for SQL type semantics (blue/green/amber etc.). Could be moved to vars later if DedgeAuth/tenant expose them.
- **autodoc-shared.css:** Mermaid dark-mode overrides (`#64b5f6`, `#f5f5f5`, `#2d2d4a`, etc.) are kept for diagram visibility and are app-specific, not provided by DedgeAuth.
- **site.css:** `rgba(0,0,0,0.15)` and similar in box-shadow left as-is (neutral shadows).

---

## 4. DedgeAuth common for shared components

**Status: N/A**

- App uses Bootstrap 5 and custom classes (e.g. `.dashboard-cardtab`, `.search-dropdown`). No duplicate redefinition of DedgeAuth’s `.btn`, `.panel`, `.modal`, etc. Where app styles use theme, they use `var(--...)`.

---

## 5. Checklist summary

| Item | Status |
|------|--------|
| **HTML (all pages)** – Order: DedgeAuth common → user → app CSS → `#DedgeAuth-tenant-css` | Done |
| **HTML** – Relative paths (no leading `/`) | Done (`~/`) |
| **App CSS** – Comment: theme from DedgeAuth common + tenant | Done (site.css, autodoc-shared.css) |
| **App CSS** – Duplicate `:root` / `[data-theme="dark"]` | Kept in autodoc-shared for generated docs only; documented |
| **Colours** – Brand/primary/status hex → `var(--primary-color)`, `var(--error-color)`, etc. | Done in site.css and badge rules in autodoc-shared |
| **Verify** – Theme toggle, tenant overrides, no duplicate vars in “app-only” CSS | To be verified in browser |

---

## 6. Tenant CSS: Dedge override + DedgeAuth default fallback

**Priority:** (1) Use styles from the current tenant override (e.g. Dedge) when the API returns them; (2) if that response is empty or the fetch fails, use DedgeAuth default fallback styles.

- **Current tenant override (Dedge)** – DedgeAuth user.js fetches `GET /tenants/{domain}/theme.css` (e.g. Dedge.no) and injects the response into `#DedgeAuth-tenant-css`. That content is the tenant’s custom CSS from DedgeAuth (e.g. Dedge theme from DatabaseSeeder). When the fetch succeeds, this overrides the local fallback.
- **DedgeAuth default fallback** – When the tenant has no custom CSS, the API returns `Theming.SystemDefaultCss` from DedgeAuth appsettings. When the fetch fails (network, DedgeAuth down), nothing is injected and **`wwwroot/css/tenant-fallback.css`** applies. It contains the same minimal defaults as DedgeAuth’s SystemDefaultCss (`--primary-color`, `--primary-hover` for light and dark). Load order: fallback link then `<style id="DedgeAuth-tenant-css">`, so injected tenant CSS always wins.

---

## 7. Files touched

- `AutoDocJson.Web/Pages/Shared/_Layout.cshtml` – CSS load order; link to tenant-fallback.css.
- `AutoDocJson.Web/wwwroot/css/tenant-fallback.css` – New local fallback when tenant API is unavailable.
- `AutoDocJson.Web/wwwroot/css/site.css` – Comment + type-badge and btn-remove-filter colours.
- `AutoDocJson.Web/wwwroot/css/autodoc-shared.css` – Comment + badge-success/warning/danger colours.

---

## 8. Suggested verification

1. Run the Web app under DedgeAuth (IIS virtual app or Kestrel with DedgeAuth).
2. Confirm theme toggle (light/dark) works and tenant branding applies.
3. Confirm no duplicate variable definitions in DevTools for the Web app (DedgeAuth common first, then app, then tenant).
4. Optionally run GrabScreenShot after deploy and check dashboard + search + one doc page.
