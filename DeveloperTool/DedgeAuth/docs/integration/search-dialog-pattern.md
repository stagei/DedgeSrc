# Search Dialog Pattern

This document describes the standard pattern for **search dialogs** and **modal dialogs** used across DedgeAuth consumer apps (GenericLogHandler, DocView, ServerMonitorDashboard, AutoDocJson). The pattern is derived from GenericLogHandler’s Log Search and Advanced Search UI.

## Purpose

- **Consistent UX**: Same modal and search-dropdown behaviour and look across apps.
- **Tenant theming**: Styles use CSS variables from tenant/fallback theme (e.g. `--bg-card`, `--border-color`, `--radius`), so branding stays consistent.
- **Reuse**: One HTML/JS pattern; styling lives in DedgeAuth tenant CSS and fallback so apps don’t duplicate it.

## Modal Dialog (detail / confirm / form)

Use for: log entry detail, confirmations, small forms, “Save filter” dialogs.

### HTML structure

```html
<div id="myModal" class="modal-overlay hidden" role="dialog" aria-modal="true">
    <div class="modal-container modal-md">
        <div class="modal-header">
            <h2 class="modal-title">Dialog title</h2>
            <button type="button" class="modal-close" aria-label="Close">&times;</button>
        </div>
        <div class="modal-body">
            <!-- Content -->
        </div>
        <div class="modal-footer">
            <button type="button" class="btn btn-outline">Cancel</button>
            <button type="button" class="btn btn-primary">OK</button>
        </div>
    </div>
</div>
```

- **Visibility**: Toggle by adding/removing the `hidden` class on `.modal-overlay`, or use a class like `active` / `show` that sets `display: flex` (see your app’s convention).
- **Sizes**: Use one of `modal-sm`, `modal-md`, `modal-lg`, `modal-fullscreen` on `.modal-container` (default `modal-md` if omitted).

### CSS classes (provided by tenant / fallback)

| Class | Purpose |
|-------|--------|
| `.modal-overlay` | Full-screen backdrop; flexbox to center the dialog; high z-index |
| `.modal-container` | Dialog panel (card bg, border-radius, shadow, max-height) |
| `.modal-header` | Title row with border-bottom; contains `.modal-title` and `.modal-close` |
| `.modal-title` | Heading text in header |
| `.modal-close` | Close button (×); no border, hover state |
| `.modal-body` | Scrollable content area |
| `.modal-footer` | Optional action buttons row |
| `.modal-sm` | max-width 400px |
| `.modal-md` | max-width 600px |
| `.modal-lg` | max-width 900px |
| `.modal-fullscreen` | Nearly full viewport |

All use `var(--bg-card)`, `var(--border-color)`, `var(--radius)`, etc., so they follow tenant/fallback theme.

### JavaScript behaviour

- **Open**: Remove `hidden` (or add `active`/`show`) on the overlay; optionally set `body` overflow hidden.
- **Close**: Add `hidden` (or remove `active`/`show`); restore body scroll.
- **Close on**: Close button click, overlay click (when `e.target === overlay`), Escape key.
- **Focus**: Trap focus inside the dialog while open; focus first focusable element on open.

GenericLogHandler provides a reusable `Modal` component in `js/components/modal.js` that creates overlays with this structure and behaviour. Other apps can use the same structure and class names so tenant/fallback CSS applies.

## Search history dropdown

Use for: “Recent searches” or similar lists next to a search/filter bar.

### HTML structure

```html
<div class="search-history-container">
    <button type="button" class="btn btn-outline" id="searchHistoryBtn">Recent</button>
    <div id="searchHistoryDropdown" class="search-history-dropdown hidden">
        <div class="search-history-empty">No recent searches</div>
        <!-- Or list of: -->
        <div class="search-history-item" data-index="0">
            <span class="search-history-text">Description of search</span>
            <span class="search-history-time">2m ago</span>
        </div>
        <div class="search-history-clear" id="clearSearchHistory">Clear history</div>
    </div>
</div>
```

- **Visibility**: Toggle `hidden` on `.search-history-dropdown` (or equivalent class).
- **Click outside**: Close dropdown when the user clicks outside `.search-history-container`.

### CSS classes (provided by tenant / fallback)

| Class | Purpose |
|-------|--------|
| `.search-history-container` | `position: relative` wrapper for the trigger and dropdown |
| `.search-history-dropdown` | Absolutely positioned panel; card style, shadow, max-height, scroll |
| `.search-history-empty` | Centered message when list is empty |
| `.search-history-item` | Row for one recent search; clickable; hover background |
| `.search-history-text` | Main label (ellipsis if long) |
| `.search-history-time` | Secondary label (e.g. “2m ago”) |
| `.search-history-clear` | “Clear history” row; distinct colour (e.g. error); hover state |

These also use theme variables so they match the rest of the app.

## Where the styles come from

- **Tenant theme**: If the tenant has custom CSS (e.g. Dedge), modal and search-dialog styles are included there and injected into `#DedgeAuth-tenant-css`.
- **Fallback**: If tenant theme is empty or unreachable, the same styles are in DedgeAuth default fallback (`api/DedgeAuth/ui/tenant-fallback.css`), which is injected by `DedgeAuth-user.js` or loaded via an optional `<link>`.

Apps only need to use the class names above; they do not need to duplicate this CSS in app-specific stylesheets.

## Reference implementation

- **GenericLogHandler**  
  - `wwwroot/log-search.html`: Log detail modal (`.modal-overlay`, `.modal-container`, `.modal-header`, `.modal-body`, etc.).  
  - `wwwroot/js/components/modal.js`: Programmatic modal API (overlay + container + header/body/footer, Escape, overlay click).  
  - Search history: “Recent” button + `.search-history-dropdown` in `log-search.html` and `log-search.js`.

When adding a new search or detail dialog in any consumer app, follow the same structure and class names so styling stays consistent and tenant/fallback CSS applies.

---

*Last updated: 2026-02-18*
