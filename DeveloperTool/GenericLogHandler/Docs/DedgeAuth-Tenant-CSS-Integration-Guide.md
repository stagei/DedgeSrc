# DedgeAuth Tenant CSS Integration Guide

Reusable guide to integrate an app with DedgeAuth shared and tenant CSS so that:

- **Theme variables** come from DedgeAuth common CSS and the tenant API (no duplication).
- **Tenant-specific CSS** overrides matching local config when the tenant API injects styles.
- **Local app CSS** only contains layout and app-specific overrides, using `var(--...)` so tenant can override.

Use this in any DedgeAuth consumer app (e.g. GenericLogHandler, DocView, ServerMonitorDashboard).

---

## 1. CSS load order in HTML

Use this order in every page `<head>`:

1. **DedgeAuth (shared)** – common and user menu styles.
2. **App CSS** – your theme and layout (dashboard, app-specific).
3. **Tenant CSS** – empty `<style>` block; DedgeAuth injects tenant overrides here so they win.

```html
<!-- 1. DedgeAuth (shared) -->
<link rel="stylesheet" href="api/DedgeAuth/ui/common.css">
<link rel="stylesheet" href="api/DedgeAuth/ui/user.css">

<!-- 2. App CSS (theme and layout) -->
<link rel="stylesheet" href="css/dashboard.css">
<!-- other app CSS, e.g. config-editor.css -->

<!-- 3. Tenant CSS (injected via API; overrides matching local config) -->
<style id="DedgeAuth-tenant-css"></style>
```

- Use **relative** paths (no leading `/`) so the app works as an IIS virtual application.
- Do **not** load app CSS before DedgeAuth, or DedgeAuth will override your theme.
- Do **not** load tenant CSS before app CSS, or tenant overrides will not apply.

---

## 2. Remove duplicate theme variables from app CSS

DedgeAuth **common.css** and the **tenant API** already define:

- `:root` and `[data-theme="dark"]` with variables such as:
  - `--bg-primary`, `--bg-secondary`, `--bg-tertiary`, `--bg-card`
  - `--text-primary`, `--text-secondary`, `--text-muted`
  - `--border-color`, `--accent-color`, `--accent-hover`
  - `--primary-color`, `--primary-hover` (brand)
  - `--success-color`, `--warning-color`, `--error-color`, `--info-color`
  - `--shadow`, `--shadow-lg`, `--radius`, `--font-mono`
  - (tenant may add e.g. `--danger-color`, `--critical-color`, `--bg-hover`, `--border-focus`)

**In your app CSS:**

1. **Delete** the entire `:root { ... }` block if it only sets these same variables.
2. **Delete** the entire `[data-theme="dark"] { ... }` block if it only overrides the same variables.
3. Add a short comment at the top that theme variables come from DedgeAuth common and tenant API.

Example comment:

```css
/* App Name - [Page/Component] Styles
   Theme variables come from DedgeAuth common.css and the tenant API
   (#DedgeAuth-tenant-css). This file contains only app-specific layout and overrides. */
```

Keep any **app-only** variables or `[data-theme="dark"]` rules that are not provided by DedgeAuth/tenant (e.g. a custom `.row-selected` in dark mode).

---

## 3. Replace hardcoded colours with tenant/common variables

Search your app CSS for hex (or fixed) colours that represent:

- **Brand / primary** (e.g. FK green `#008942`) → `var(--primary-color, #008942)`
- **Accent / links** → `var(--accent-color)` or `var(--accent-hover)`
- **Success** (e.g. green) → `var(--success-color)`
- **Error / danger** (e.g. red) → `var(--error-color)` or `var(--danger-color)`
- **Warning** (e.g. amber) → `var(--warning-color)`
- **Info** (e.g. blue) → `var(--info-color)`

Use a fallback in `var(--name, #hex)` only when the variable might be missing (e.g. before tenant is loaded).

**Examples:**

| Use case              | Before              | After                                      |
|------------------------|---------------------|--------------------------------------------|
| Header / nav brand     | `#008942`           | `var(--primary-color, #008942)`            |
| Active nav link       | `color: #008942`    | `color: var(--primary-color, #008942)`     |
| Success badge         | `#22c55e`           | `var(--success-color)`                     |
| Error badge / toggle   | `#dc2626` / `#ef4444` | `var(--error-color)`                    |
| Accent badge          | `#3b82f6`           | `var(--accent-color)`                      |
| Badge background      | `rgba(34,197,94,0.2)` | `color-mix(in srgb, var(--success-color) 20%, transparent)` |
| Toggle on (brand)     | `#008942`           | `var(--primary-color, #008942)`            |
| Toggle off (danger)   | `#dc2626`           | `var(--error-color)`                       |

Use `color-mix(in srgb, var(--x) 20%, transparent)` for tinted backgrounds when you want them to follow the theme.

---

## 4. Rely on DedgeAuth common for shared components (optional)

DedgeAuth **common.css** already defines base styles for:

- Buttons: `.btn`, `.btn-primary`, `.btn-outline`, `.btn-sm`, `.btn-icon`, etc.
- Panels: `.panel`, `.panel-header`, `.panel-body`, `.panel-footer`
- Modals: `.modal`, `.modal-overlay`, `.modal-header`, `.modal-body`, `.modal-close`
- Forms: `input`, `textarea`, `select` (with focus and dark theme)
- Tables: `.table`
- Badges: `.badge`, `.badge-success`, `.badge-warning`, `.badge-danger`, `.badge-primary`
- Theme toggle: `.theme-toggle`, `.theme-toggle__input`, etc.

If your app uses the same class names, you can **omit** redefining these in app CSS and only add app-specific overrides (e.g. `.header`, `.nav-links`, `.data-table`). If you keep your own `.btn` / `.panel` etc., ensure they use `var(--...)` so tenant overrides still apply.

---

## 5. Checklist for a new project

- [ ] **HTML (all pages)**  
  - Order: DedgeAuth common → DedgeAuth user → app CSS → `<style id="DedgeAuth-tenant-css"></style>`.
  - All asset paths relative (no leading `/`).

- [ ] **App CSS**  
  - Removed duplicate `:root` and `[data-theme="dark"]` variable blocks (or kept only app-only vars).
  - Top-of-file comment: theme variables from DedgeAuth common + tenant API.

- [ ] **Colours**  
  - Replaced brand/primary hex with `var(--primary-color, #008942)` (or your default).
  - Replaced status/accent hex with `var(--success-color)`, `var(--error-color)`, `var(--accent-color)`, etc.
  - Optional: use `color-mix(in srgb, var(--x) 20%, transparent)` for tinted backgrounds.

- [ ] **Verify**  
  - Theme toggle (dark/light) works; tenant API can override variables; no duplicate variable definitions in app CSS.

---

## 6. Reference: where styles come from

| Source              | Role |
|---------------------|------|
| **DedgeAuth common.css** | Shared theme variables (`:root`, `[data-theme="dark"]`) and component base styles. |
| **DedgeAuth user.css**   | User menu / dropdown (e.g. `.gk-user-menu`, `.gk-dropdown`). |
| **Tenant API**        | Injected into `#DedgeAuth-tenant-css`; overrides variables and any matching selectors. |
| **App CSS**           | Layout, app-specific components, overrides; should only use `var(--...)` for theme. |

Tenant API CSS is loaded **last**, so it overrides matching variables and rules from both DedgeAuth common and your app.
