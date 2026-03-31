# Bug Fixes - Task List

**Goal:** Fix existing bugs before continuing with new features  
**Priority:** 🔴 CRITICAL

---

## Status Summary
- **Total Tasks:** 2
- **Completed:** 2 ✅
- **In Progress:** 0
- **Pending:** 0

---

## Tasks

### Bug-5: Fix System Theme Settings (Light Mode Not Working)

#### Task Details
When user selects "Use System Theme" in settings, the application does not properly detect or apply the Windows system theme. Light mode specifically is not working.

#### Subtasks
- [x] Read current theme detection logic in SettingsDialog or MainWindow
- [x] Investigate `ModernWpf.ThemeManager` system theme detection
- [x] Add DEBUG logging for theme detection
- [x] Test system theme detection on Windows 11
- [x] Fix light mode application
- [x] Test theme switching manually
- [x] Test "Use System Theme" option
- [x] Verify CLI execution still works after fix

#### Fix Applied:
1. Removed hardcoded `RequestedTheme="Dark"` from `App.xaml`
2. Added theme initialization in `App.xaml.cs` OnStartup
3. Enhanced DEBUG logging in `ThemeService.cs`
4. Theme now properly detected from Windows registry
5. System theme, Light mode, and Dark mode all working

**Status:** ✅ COMPLETE

---

### Bug-6: Implement SQL Editor Intellisense/Autocomplete

#### Task Details
AvalonEdit SQL editor currently has no intellisense or autocomplete. This should be driven by JSON configuration files.

#### Subtasks
- [x] Research AvalonEdit completion window API
- [x] Design intellisense JSON structure in ConfigFiles
- [x] Create `db2_12.1_keywords.json` (100+ keywords)
  - [x] Add SQL keywords (SELECT, FROM, WHERE, etc.)
  - [x] Add DB2 functions (TRIM, SUBSTR, etc.)
  - [x] Add system tables (SYSCAT.TABLES, etc.)
- [x] Implement ICompletionData for SQL items (`SqlCompletionData`)
- [x] Implement CompletionWindow trigger (Ctrl+Space + auto-trigger)
- [x] Filter completions based on current context
- [x] Add priority-based ranking
- [x] Load intellisense data from JSON at startup
- [x] Test intellisense with basic queries
- [x] Test with schema.table completion
- [x] Verify CLI execution still works

#### Implementation:
1. Created `ConfigFiles/db2_12.1_keywords.json` - 100+ keywords in 7 categories
2. Created `Services/IntellisenseService.cs` - JSON-driven provider
3. Created `Controls/SqlCompletionData.cs` - AvalonEdit adapter
4. Integrated in `ConnectionTabControl` - TextArea events
5. Auto-trigger: Space, Dot, 2+ characters
6. Manual trigger: Ctrl+Space
7. Full documentation in `INTELLISENSE_COMPLETE_WITH_UI.md`

**Status:** ✅ COMPLETE (PRODUCTION READY)

---

**Last Updated:** 2025-11-20

