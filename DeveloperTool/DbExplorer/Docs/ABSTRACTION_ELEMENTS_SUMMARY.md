# Complete List of Elements to Abstract to JSON Configuration

**Document Purpose:** Comprehensive inventory of all hardcoded elements that should be moved to JSON configuration files for provider/version abstraction.

**Date:** November 20, 2025  
**Target:** DbExplorer Metadata Abstraction Architecture

---

## 📊 SUMMARY TABLE

| Category | Current State | Files Affected | Priority | Benefit |
|----------|---------------|----------------|----------|---------|
| **SQL Queries** | Hardcoded in 10+ files | ObjectBrowserService, DdlGeneratorService, TableDetailsDialog | 🔴 CRITICAL | Version-specific queries, proven patterns |
| **Icons & Emojis** | ObjectBrowserIcons class | ObjectBrowserModels.cs | 🟡 HIGH | Provider-specific icons, theme support |
| **Error Messages** | 202 MessageBox.Show() calls | 34 files | 🟡 HIGH | Multi-language support, consistency |
| **UI Layout** | 448 XAML hardcoded values | 23 XAML files | 🟢 MEDIUM | DPI scaling, consistent sizing |
| **Timeouts** | Scattered settings | DB2Connection, appsettings.json | 🟢 MEDIUM | Tunable performance |
| **Keyboard Shortcuts** | Code-behind handlers | MainWindow, ConnectionTabControl | 🟢 MEDIUM | User customization |
| **Context Menus** | XAML/Code-behind | ConnectionTabControl | 🟡 HIGH | Dynamic menus, RBAC |
| **SQL Templates** | Hardcoded snippets | Various | 🟢 MEDIUM | Provider-specific syntax |
| **Intellisense Config** | N/A (not implemented) | N/A | 🟡 HIGH | Context-aware completion |

---

## 1. SQL QUERIES (CRITICAL)

### Current State
- **50+ queries** in `Services/ObjectBrowserService.cs`
- **20+ queries** in `Services/DdlGeneratorService.cs`
- **10+ queries** in `Dialogs/TableDetailsDialog.xaml.cs`
- **Scattered** across property dialogs

### Target JSON File: `sql_statements.json`
```json
{
  "provider": "DB2",
  "version": "12.1",
  "queries": {
    "get_views_for_schema": {
      "sql": "SELECT...",
      "parameters": ["TABSCHEMA"],
      "source": "Db2CreateDBQA_NonRelated.sql:544-558"
    }
  }
}
```

### Migration Steps
1. Extract all SQL from services into JSON
2. Verify against proven patterns (`Db2CreateDBQA_NonRelated.sql`)
3. Add parameter descriptions and notes
4. Update services to use `GetQuery(provider, version, key)`

---

## 2. ICONS & EMOJIS (HIGH)

### Current State
- **30+ icons** hardcoded in `ObjectBrowserIcons` class
- Located in: `Models/ObjectBrowserModels.cs` (lines 213-291)

### Target JSON File: `ui_icons.json`
```json
{
  "provider": "DB2",
  "version": "12.1",
  "icons": {
    "categories": {"database": "🗄️", "schemas": "📁", ...},
    "objects": {"table": "📄", "view": "👁", ...},
    "security": {"role": "🎭", "user": "👤", ...},
    "status": {"loading": "⏳", "error": "❌", ...}
  }
}
```

### Migration Steps
1. Move `ObjectBrowserIcons` constants to JSON
2. Create `IconProvider` class to load from JSON
3. Update all references to use `IconProvider.GetIcon(key)`

---

## 3. ERROR MESSAGES & USER PROMPTS (HIGH)

### Current State
- **202 MessageBox.Show()** calls across **34 files**
- Inconsistent wording, no localization support
- Provider-specific error handling missing

### Files with Most MessageBox Calls
1. `Controls/ConnectionTabControl.xaml.cs` - 40 calls
2. `MainWindow.xaml.cs` - 29 calls
3. `Dialogs/ObjectDetailsDialog.xaml.cs` - 11 calls
4. `Dialogs/MermaidDesignerWindow.xaml.cs` - 11 calls

### Target JSON File: `ui_messages.json`
```json
{
  "provider": "DB2",
  "version": "12.1",
  "language": "en-US",
  "messages": {
    "connection_errors": {...},
    "query_errors": {...},
    "warnings": {...},
    "confirmations": {...},
    "success": {...},
    "info": {...}
  }
}
```

### Migration Steps
1. Audit all MessageBox.Show() calls
2. Categorize messages (error, warning, info, confirm)
3. Extract to JSON with placeholders: `{database}`, `{timeout}`
4. Create `MessageProvider` class with `ShowError(key, params)`

---

## 4. UI LAYOUT & SIZING (MEDIUM)

### Current State
- **448 instances** of `MinHeight`, `MinWidth`, `Height`, `Width`, `Padding`, `Margin` across **23 XAML files**

### Most Affected Files
1. `Controls/ConnectionTabControl.xaml` - 99 instances
2. `Controls/LockMonitorPanel.xaml` - 35 instances
3. `Controls/WelcomePanel.xaml` - 31 instances

### Target JSON File: `ui_layout.json`
```json
{
  "provider": "DB2",
  "version": "12.1",
  "layout": {
    "toolbar": {"min_height": 48, "button_height": 32, ...},
    "statusbar": {"min_height": 28, "font_size": 12, ...},
    "sql_editor": {"font_family": "Consolas", "font_size": 14, ...},
    "object_browser": {"initial_width": 250, ...},
    "data_grid": {"row_height": 24, ...}
  }
}
```

### Migration Steps
1. Identify common UI sizing patterns
2. Extract to JSON with logical grouping
3. Create `LayoutProvider` with DPI-aware calculations
4. Update XAML to use `{DynamicResource ToolbarHeight}`

---

## 5. TIMEOUT & PERFORMANCE SETTINGS (MEDIUM)

### Current State
- Scattered across:
  - `Models/DB2Connection.cs` - ConnectionTimeout (default 30)
  - `appsettings.json` - DefaultCommandTimeout, MaxConnectionPoolSize
  - `Models/UserPreferences.cs` - MaxRowsPerQuery

### Target JSON File: `performance_config.json`
```json
{
  "provider": "DB2",
  "version": "12.1",
  "performance": {
    "connection": {
      "timeout_seconds": 30,
      "retry_attempts": 3,
      "keepalive_interval_seconds": 60
    },
    "query_execution": {
      "default_timeout_seconds": 30,
      "max_result_rows": 10000,
      "pagination_page_size": 1000
    },
    "metadata_collection": {
      "cache_duration_seconds": 300,
      "background_refresh": true
    }
  }
}
```

### Migration Steps
1. Consolidate timeout settings from multiple sources
2. Add provider-specific optimizations
3. Create `PerformanceConfig` class
4. Update connection and query logic

---

## 6. KEYBOARD SHORTCUTS (MEDIUM)

### Current State
- Hardcoded in:
  - `MainWindow.xaml.cs` - Window-level shortcuts
  - `Controls/ConnectionTabControl.xaml.cs` - Tab-level shortcuts

### Shortcuts Currently Defined
- F5 - Execute query
- Ctrl+Enter - Execute current statement
- Ctrl+Shift+F - Format SQL
- Ctrl+N - New connection
- Ctrl+W - Close tab
- Ctrl+D - Toggle dark mode
- Ctrl+F - Find
- Ctrl+H - Replace

### Target JSON File: `keyboard_shortcuts.json`
```json
{
  "provider": "DB2",
  "version": "12.1",
  "shortcuts": {
    "editor": {
      "execute_query": "F5",
      "execute_current_statement": "Ctrl+Enter",
      "format_sql": "Ctrl+Shift+F"
    },
    "tabs": {
      "new_connection": "Ctrl+N",
      "close_tab": "Ctrl+W"
    }
  }
}
```

### Migration Steps
1. Extract all KeyGesture bindings to JSON
2. Create `ShortcutManager` to load and register shortcuts
3. Allow user customization via Settings dialog

---

## 7. CONTEXT MENU ACTIONS (HIGH)

### Current State
- Hardcoded in `Controls/ConnectionTabControl.xaml.cs`
- `CreateObjectContextMenu()` method dynamically builds menus

### Current Context Menu Items
- Tables: Browse Data, Count Rows, Generate SELECT, Properties
- Views: View Source Code, Properties
- Procedures/Functions: View Source Code, Properties

### Target JSON File: `context_menus.json`
```json
{
  "provider": "DB2",
  "version": "12.1",
  "context_menus": {
    "table": {
      "actions": [
        {
          "id": "browse_data",
          "label": "📊 Browse Data (Top 1000)",
          "min_access_level": "Standard",
          "query_key": "get_top_n_rows"
        }
      ]
    }
  }
}
```

### Migration Steps
1. Extract menu definitions to JSON
2. Create `ContextMenuBuilder` class
3. Load menus dynamically based on object type and RBAC

---

## 8. SQL TEMPLATES (MEDIUM)

### Current State
- Hardcoded snippets for common operations
- Used in context menus and intellisense

### Target JSON File: `sql_templates.json`
```json
{
  "provider": "DB2",
  "version": "12.1",
  "templates": {
    "select_top_n": "SELECT * FROM {schema}.{table} FETCH FIRST {n} ROWS ONLY",
    "count_rows": "SELECT COUNT(*) FROM {schema}.{table}",
    "describe_table": "SELECT * FROM SYSCAT.COLUMNS WHERE TABSCHEMA = '{schema}' AND TABNAME = '{table}' ORDER BY COLNO"
  }
}
```

### Migration Steps
1. Extract common SQL patterns
2. Add placeholders for schema, table, column names
3. Support provider-specific syntax (FETCH FIRST vs TOP vs LIMIT)

---

## 9. INTELLISENSE CONFIGURATION (HIGH)

### Current State
- **NOT IMPLEMENTED** (Bug-6)
- AvalonEdit supports intellisense but not configured

### Target JSON File: `intellisense_config.json`
```json
{
  "provider": "DB2",
  "version": "12.1",
  "features": {
    "keyword_completion": {"enabled": true, "case_style": "UPPERCASE"},
    "table_completion": {"enabled": true, "include_schema": true},
    "column_completion": {"enabled": true, "show_data_types": true},
    "function_completion": {"enabled": true, "show_parameters": true}
  },
  "context_aware_suggestions": {
    "after_select": ["column_names", "functions", "DISTINCT", "TOP", "*"],
    "after_from": ["table_names", "schema.table", "subquery"],
    "after_where": ["column_names", "operators", "functions"]
  },
  "snippet_templates": [
    {
      "trigger": "sel",
      "template": "SELECT * FROM ${1:table_name} WHERE ${2:condition}",
      "description": "SELECT all columns with WHERE clause"
    }
  ]
}
```

### Migration Steps
1. Implement AvalonEdit intellisense integration
2. Load keywords and functions from JSON
3. Query metadata service for table/column names
4. Implement context-aware suggestions

---

## 📈 IMPLEMENTATION PRIORITY

### Phase 1 (CRITICAL)
1. **SQL Queries** - Essential for version/provider abstraction
2. **Object Browser Config** - Defines UI capabilities

### Phase 2 (HIGH)
3. **Icons & Emojis** - Provider theming
4. **Error Messages** - Localization foundation
5. **Context Menus** - Dynamic UI generation
6. **Intellisense Config** - Fix Bug-6

### Phase 3 (MEDIUM)
7. **UI Layout** - DPI scaling improvements
8. **Keyboard Shortcuts** - User customization
9. **SQL Templates** - Intellisense snippets
10. **Performance Settings** - Tunable optimizations

---

## 🎯 EXPECTED OUTCOMES

After completing this abstraction:

✅ **Zero Hardcoded SQL** in application code  
✅ **Provider Agnostic** - Easy to add SQL Server, PostgreSQL  
✅ **Version Aware** - Different features per DB version  
✅ **Localization Ready** - Multi-language support  
✅ **User Customizable** - Keyboard shortcuts, themes, sizing  
✅ **Maintainable** - All queries in one place with documentation  
✅ **Testable** - JSON validation, query verification  
✅ **Professional** - Industry-standard metadata-driven architecture  

---

## 📝 NOTES

- All JSON files should be validated against JSON schema
- Include `source` field for proven patterns (line numbers from `Db2CreateDBQA_NonRelated.sql`)
- Use descriptive keys: `get_views_for_schema` not `query_47`
- Document RBAC levels for each feature/query
- Test backwards compatibility during migration

---

**Next Steps:** See `METADATA_ABSTRACTION_ARCHITECTURE_PLAN.md` for detailed implementation plan and task list.

