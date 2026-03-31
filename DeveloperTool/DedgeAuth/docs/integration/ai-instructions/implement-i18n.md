# AI Agent Instructions: Implement i18n in FK App

## Context

DedgeAuth provides a distributed multi-language system. Each FK app owns its own translation files. DedgeAuth handles user language preference, the language selector UI (in the user menu), and the client-side translation loader.

**Languages:** Norwegian Bokmål (`nb`, default) and English (`en`).

**Reference implementation:** DedgeAuth's own `admin.html` and `login.html` in `C:\opt\src\DedgeAuth\src\DedgeAuth.Api\wwwroot\`.

## Prerequisites

- App must reference `DedgeAuth.Client` and call `MapDedgeAuthProxy()` in `Program.cs`
- App must already load `api/DedgeAuth/ui/user.js` in its HTML

## Step-by-Step Instructions

### 1. Create Translation Files

Create `wwwroot/i18n/nb.json` (Norwegian) and `wwwroot/i18n/en.json` (English).

Scan **every HTML page and JavaScript file** in the app for visible text strings. Extract ALL of them into translation keys.

```json
{
  "nav.dashboard": "Oversikt",
  "nav.logs": "Logger",
  "page.title": "Loggvisning",
  "table.timestamp": "Tidspunkt",
  "table.level": "Nivå",
  "table.message": "Melding",
  "button.search": "Søk",
  "button.clear": "Tøm",
  "placeholder.search": "Søk i logger...",
  "message.noResults": "Ingen resultater funnet",
  "message.loading": "Laster..."
}
```

**Both files must have the exact same set of keys.** Norwegian is the primary language.

### 2. Add `DedgeAuth-i18n.js` Script to HTML Pages

In every HTML page, add before the closing `</body>` tag, AFTER `user.js`:

```html
<script src="api/DedgeAuth/ui/user.js"></script>
<script src="api/DedgeAuth/ui/i18n.js"></script>
</body>
```

For Razor Pages (`.cshtml`), add in the `@section Scripts` or at the bottom of the layout:

```html
<script src="~/api/DedgeAuth/ui/i18n.js"></script>
```

### 3. Add `data-i18n` Attributes to All Static Text

Go through every HTML element that contains user-visible text and add `data-i18n="key"`:

```html
<!-- Navigation -->
<a data-i18n="nav.dashboard">Dashboard</a>
<a data-i18n="nav.logs">Logs</a>

<!-- Page titles -->
<h1 data-i18n="page.title">Log Viewer</h1>

<!-- Table headers -->
<th data-i18n="table.timestamp">Timestamp</th>
<th data-i18n="table.level">Level</th>

<!-- Buttons -->
<button data-i18n="button.search">Search</button>

<!-- Form labels -->
<label data-i18n="label.dateRange">Date Range</label>
```

### 4. Add `data-i18n-placeholder` for Input Placeholders

```html
<input data-i18n-placeholder="placeholder.search" placeholder="Search...">
```

### 5. Replace Hardcoded Strings in JavaScript

Find all hardcoded user-facing strings in JavaScript and replace with `DedgeAuth.t()`:

```javascript
// BEFORE
cell.textContent = 'Loading...';
alert('No results found');

// AFTER
cell.textContent = DedgeAuth.t('message.loading', 'Loading...');
alert(DedgeAuth.t('message.noResults', 'No results found'));
```

With parameter substitution:

```javascript
const msg = DedgeAuth.t('message.recordCount', { count: records.length });
```

### 6. For Razor Pages (.cshtml)

Add `data-i18n` on static elements. For server-rendered dynamic content, the `data-i18n` attribute still works — the client-side loader replaces the text after page load.

```html
<h1 data-i18n="page.title">@Model.Title</h1>
```

## Key Naming Standard

| Prefix | Usage | Examples |
|---|---|---|
| `nav.*` | Navigation items | `nav.dashboard`, `nav.settings`, `nav.logs` |
| `page.*` | Page titles | `page.title`, `page.subtitle` |
| `table.*` | Table headers | `table.email`, `table.name`, `table.status`, `table.actions` |
| `button.*` | Button labels | `button.save`, `button.cancel`, `button.search`, `button.delete` |
| `label.*` | Form labels | `label.email`, `label.password`, `label.dateRange` |
| `placeholder.*` | Input placeholders | `placeholder.search`, `placeholder.email` |
| `message.*` | User messages | `message.success`, `message.error`, `message.noData` |
| `dialog.*` | Modal/dialog text | `dialog.confirm`, `dialog.deleteTitle` |

## Translation Quality Rules

- Norwegian translations must be natural, professional Norwegian Bokmål
- Do NOT use Google Translate style — use proper domain terminology
- IT/technical terms commonly used in English can stay in English (e.g., "Dashboard" is acceptable but "Oversikt" is preferred)
- Keep translations concise — buttons and nav items should be short
- Use consistent terminology across all translation files

### Common Norwegian IT Terms

| English | Norwegian |
|---|---|
| Dashboard | Oversikt |
| Settings | Innstillinger |
| Users | Brukere |
| Search | Søk |
| Save | Lagre |
| Cancel | Avbryt |
| Delete | Slett |
| Edit | Rediger |
| Loading... | Laster... |
| No data found | Ingen data funnet |
| Email | E-post |
| Password | Passord |
| Sign In | Logg inn |
| Sign Out | Logg ut |
| Error | Feil |
| Success | Vellykket |
| Name | Navn |
| Status | Status |
| Actions | Handlinger |
| Applications | Applikasjoner |

## Verification Checklist

After implementation, verify:

- [ ] `wwwroot/i18n/nb.json` exists with all keys
- [ ] `wwwroot/i18n/en.json` exists with the same keys
- [ ] Every visible text element in every HTML page has a `data-i18n` attribute
- [ ] Every input placeholder has a `data-i18n-placeholder` attribute
- [ ] No hardcoded user-facing strings remain in JavaScript without `DedgeAuth.t()` wrapper
- [ ] `<script src="api/DedgeAuth/ui/i18n.js"></script>` is in every HTML page before `</body>`
- [ ] Norwegian translations are natural and professional (not machine-translated)
- [ ] Both JSON files are valid JSON (no trailing commas, no syntax errors)
- [ ] Language selector in user menu switches the page language without reload
- [ ] Default language (`nb`) renders Norwegian text throughout

## Per-App Specifics

| App | Source Path | HTML Files | Notes |
|---|---|---|---|
| **DocView** | `C:\opt\src\DocView` | `wwwroot/index.html` | Static HTML app |
| **GenericLogHandler** | `C:\opt\src\GenericLogHandler` | `wwwroot/index.html` | Static HTML with JS dashboard |
| **ServerMonitorDashboard** | `C:\opt\src\ServerMonitor` | `wwwroot/index.html` | Static HTML with metric panels |
| **AutoDocJson** | `C:\opt\src\AutoDocJson` | `Pages/*.cshtml` | Razor Pages app — use `data-i18n` on static elements |
| **GrainPriceList** | `C:\opt\src\GrainPriceList` | `wwwroot/index.html`, `Pages/*.cshtml` | Mixed static + Razor |

## No `Program.cs` Changes Needed

`DedgeAuth.Client` automatically registers the `/api/i18n/languages` and `/api/i18n/{lang}` endpoints when `MapDedgeAuthProxy()` is called. These endpoints serve JSON files from `wwwroot/i18n/` in your app.
