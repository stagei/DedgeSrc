# DedgeAuth i18n — Multi-Language Integration Guide

## Overview

DedgeAuth provides a distributed i18n system where:

- **DedgeAuth** stores each user's preferred language and distributes it via JWT claims and the `/me` endpoint
- **DedgeAuth** provides the language selector UI (in the user menu dropdown), the client-side translation loader (`DedgeAuth-i18n.js`), and standard API endpoints in `DedgeAuth.Client`
- **Each consumer app** owns and manages its own translation files locally in `wwwroot/i18n/`

Norwegian Bokmål (`nb`) is the default language. English (`en`) is the secondary language.

## Architecture

```
User Menu (DedgeAuth-user.js)
  ├── Reads language from /me response or localStorage
  ├── Renders language flag buttons in dropdown
  └── On change:
      ├── PUT api/DedgeAuth/language → persists to DB
      ├── localStorage.setItem('DedgeAuth_language', lang)
      └── dispatches 'DedgeAuth:language-changed' event

DedgeAuth-i18n.js (loaded by consumer apps)
  ├── Listens for 'DedgeAuth:language-changed'
  ├── Reads initial language from localStorage
  ├── Fetches GET /api/i18n/{lang} (app-local translations)
  ├── Falls back to GET api/DedgeAuth/ui/i18n/{lang}.json (shared translations)
  └── Applies translations to data-i18n elements

Consumer App
  ├── wwwroot/i18n/nb.json  ← Norwegian translations
  ├── wwwroot/i18n/en.json  ← English translations
  └── HTML pages with data-i18n attributes
```

## Data Flow

1. User logs in → DedgeAuth generates JWT with `language` claim (from `users.preferred_language`)
2. Consumer app calls `GET /api/DedgeAuth/me` → response includes `language` and `supportedLanguages`
3. `DedgeAuth-user.js` reads `language` from `/me`, stores in `localStorage`, loads shared translations
4. `DedgeAuth-i18n.js` reads `localStorage('DedgeAuth_language')`, fetches app-local translations, applies to DOM
5. User clicks language flag in dropdown → `DedgeAuth-user.js`:
   - Calls `PUT /api/DedgeAuth/language` (proxied to DedgeAuth server)
   - Updates `localStorage`
   - Dispatches `DedgeAuth:language-changed` event
6. `DedgeAuth-i18n.js` catches the event → fetches new translations → re-applies to DOM

## Step-by-Step: Adding i18n to a Consumer App

### Step 1: Create Translation Files

Create `wwwroot/i18n/nb.json` and `wwwroot/i18n/en.json` in your app:

```json
{
  "nav.dashboard": "Oversikt",
  "nav.settings": "Innstillinger",
  "page.title": "Min applikasjon",
  "table.email": "E-post",
  "table.name": "Navn",
  "button.save": "Lagre",
  "button.cancel": "Avbryt",
  "placeholder.search": "Søk...",
  "message.success": "Lagret"
}
```

Both files must have the **exact same set of keys**.

### Step 2: Add `DedgeAuth-i18n.js` to Your HTML

Add before the closing `</body>` tag, after all other DedgeAuth scripts:

```html
<link rel="stylesheet" href="api/DedgeAuth/ui/common.css">
<style id="DedgeAuth-tenant-css"></style>
<link rel="stylesheet" href="api/DedgeAuth/ui/user.css">

<!-- ... page content ... -->

<div id="DedgeAuthUserMenu"></div>
<script src="api/DedgeAuth/ui/user.js"></script>
<script src="api/DedgeAuth/ui/i18n.js"></script>
</body>
```

### Step 3: Add `data-i18n` Attributes to HTML

Add `data-i18n="key"` to static text elements:

```html
<h1 data-i18n="page.title">My Application</h1>
<th data-i18n="table.email">Email</th>
<button data-i18n="button.save">Save</button>
```

For input placeholders:

```html
<input data-i18n-placeholder="placeholder.search" placeholder="Search...">
```

For elements containing HTML entities:

```html
<a data-i18n-html="nav.backToLogin">&#8592; Back to login</a>
```

### Step 4: Use `DedgeAuth.t()` in JavaScript

For dynamically generated content:

```javascript
const header = document.createElement('th');
header.textContent = DedgeAuth.t('table.email', 'Email');

// With parameter substitution
const msg = DedgeAuth.t('message.itemCount', { count: items.length });
```

### Step 5: No `Program.cs` Changes Needed

`DedgeAuth.Client` automatically registers the `/api/i18n/languages` and `/api/i18n/{lang}` endpoints when you call `MapDedgeAuthProxy()`. These endpoints serve files from your app's `wwwroot/i18n/` folder.

## Translation File Format

### File Location

```
wwwroot/
  i18n/
    nb.json    ← Norwegian Bokmål (default)
    en.json    ← English
```

### Key Naming Convention

| Prefix | Usage | Examples |
|---|---|---|
| `nav.*` | Navigation items | `nav.dashboard`, `nav.settings`, `nav.logs` |
| `page.*` | Page titles | `page.title`, `page.subtitle` |
| `table.*` | Table headers | `table.email`, `table.name`, `table.status` |
| `button.*` | Button labels | `button.save`, `button.cancel`, `button.search` |
| `label.*` | Form labels | `label.email`, `label.password` |
| `placeholder.*` | Input placeholders | `placeholder.search`, `placeholder.email` |
| `message.*` | User messages | `message.success`, `message.error`, `message.noData` |
| `dialog.*` | Modal/dialog text | `dialog.confirm`, `dialog.deleteTitle` |

### Parameter Substitution

Use `{paramName}` in translation values:

```json
{
  "message.itemCount": "{count} elementer funnet",
  "message.welcome": "Velkommen, {name}!"
}
```

```javascript
DedgeAuth.t('message.itemCount', { count: 42 });
// → "42 elementer funnet"
```

## API Endpoints

### Provided by DedgeAuth.Client (in consumer apps)

| Endpoint | Method | Description |
|---|---|---|
| `GET /api/i18n/languages` | GET | Returns array of available language codes |
| `GET /api/i18n/{lang}` | GET | Returns translation JSON for a language |
| `PUT /api/DedgeAuth/language` | PUT | Updates user's preferred language (proxied to DedgeAuth) |

### Provided by DedgeAuth Server

| Endpoint | Method | Description |
|---|---|---|
| `GET /api/ui/i18n.js` | GET | Serves the i18n loader script |
| `GET /api/ui/i18n/{lang}.json` | GET | Serves DedgeAuth shared translation files |
| `PUT /api/auth/language` | PUT | Updates `users.preferred_language` in database |

## `/me` Response

The `/me` endpoint now includes language information:

```json
{
  "authenticated": true,
  "language": "nb",
  "supportedLanguages": ["nb", "en"],
  "user": { ... },
  "applications": [ ... ],
  "DedgeAuthUrl": "http://server/DedgeAuth"
}
```

## DedgeAuth as Reference Implementation

DedgeAuth's own `admin.html` and `login.html` use the same i18n system:

- Translation files: `wwwroot/i18n/nb.json` and `en.json`
- All static text elements have `data-i18n` attributes
- Inline i18n script loads translations from local `/i18n/{lang}.json`
- Listens for `DedgeAuth:language-changed` event for live language switching

## Database Schema

```sql
-- users table
ALTER TABLE users ADD COLUMN preferred_language VARCHAR(10) NOT NULL DEFAULT 'nb';

-- tenants table
ALTER TABLE tenants ADD COLUMN supported_languages_json VARCHAR(500) DEFAULT '["nb","en"]';
```

## JWT Claims

The JWT now includes a `language` claim:

```json
{
  "sub": "user-id",
  "email": "user@example.com",
  "language": "nb",
  "tenant": {
    "supportedLanguages": ["nb", "en"],
    ...
  }
}
```
