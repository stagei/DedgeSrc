# Metadata Abstraction Architecture Plan

## 🎯 VISION

Transform DbExplorer into a **provider-agnostic, version-aware database editor** where:
- **ALL SQL statements** are stored in JSON files (not hardcoded)
- **UI capabilities** are defined by JSON configuration per provider/version
- **Easy extensibility** to other database providers (SQL Server, PostgreSQL, Oracle)
- **Version-specific features** automatically enabled/disabled based on DB version
- **Syntax highlighting** driven by JSON keyword lists

---

## 🏗️ ARCHITECTURE OVERVIEW

### Current State (Problems)
```
❌ SQL statements scattered across:
   - Services/ObjectBrowserService.cs (50+ queries)
   - Dialogs/TableDetailsDialog.xaml.cs (10+ queries)
   - Services/DdlGeneratorService.cs (20+ queries)
   - Various other files

❌ UI capabilities hardcoded:
   - Object Browser categories hardcoded in code
   - Property windows manually implemented
   - No version awareness for features

❌ No provider abstraction:
   - Tightly coupled to DB2
   - Cannot support other databases
```

### Target State (Solution)
```
✅ Centralized metadata in JSON files:
   /Metadata/
   ├── DB2/
   │   ├── 12.1/
   │   │   ├── sql_statements.json          (ALL SQL queries)
   │   │   ├── object_browser_config.json   (Object Browser structure)
   │   │   ├── property_windows_config.json (Property window definitions)
   │   │   ├── ui_features_config.json      (Feature flags)
   │   │   └── syntax_keywords.json         (Reserved words)
   │   ├── 11.5/
   │   │   └── ... (same structure)
   │   └── 9.7/
   │       └── ... (same structure)
   └── SQLSERVER/  (Future)
       └── 2022/
           └── ... (same structure)

✅ DB2MetadataService as abstraction layer:
   - Loads ALL JSON files on startup
   - Provides query dictionary: GetQuery(provider, version, key)
   - Provides UI config: GetObjectBrowserConfig(provider, version)
   - Provides feature flags: IsFeatureEnabled(provider, version, feature)

✅ Application code uses keys, not SQL:
   var sql = _metadataService.GetQuery("DB2", "12.1", "get_views_for_schema");
   var isEnabled = _metadataService.IsObjectTypeEnabled("DB2", "12.1", "Packages");
```

---

## 📋 KEY CONCEPTS

### 1. The Universal Key Format

**Format:** `{provider}.{version}.{category}.{key}`

**Examples:**
- SQL Query: `DB2.12.1.queries.get_views_for_schema`
- Object Type: `DB2.12.1.objects.packages.enabled`
- Property Window: `DB2.12.1.properties.table_details.enabled`
- Syntax Keyword: `DB2.12.1.syntax.reserved_words`

### 2. JSON File Structure

#### A. `sql_statements.json`
```json
{
  "provider": "DB2",
  "version": "12.1",
  "description": "All SQL statements for DB2 v12.1",
  "queries": {
    "get_views_for_schema": {
      "description": "Get all views in a schema (PROVEN PATTERN: Line 544-558)",
      "sql": "SELECT... FROM SYSCAT.TABLES T JOIN SYSCAT.VIEWS V...",
      "parameters": ["TABSCHEMA"],
      "returns": "List of views with metadata",
      "source": "Db2CreateDBQA_NonRelated.sql:544-558",
      "notes": [
        "CRITICAL: Start from SYSCAT.TABLES (not SYSCAT.VIEWS)",
        "Filter by T.TYPE = 'V'"
      ]
    },
    "get_tables_for_schema": { ... },
    "get_primary_key_ddl": { ... }
  }
}
```

#### B. `object_browser_config.json`
```json
{
  "provider": "DB2",
  "version": "12.1",
  "description": "Object Browser structure and capabilities",
  "top_level_categories": [
    {
      "key": "schemas",
      "name": "Schemas",
      "icon": "📁",
      "enabled": true,
      "min_access_level": "Standard",
      "lazy_load": true,
      "query_key": "get_all_schemas"
    },
    {
      "key": "tablespaces",
      "name": "Tablespaces",
      "icon": "💾",
      "enabled": true,
      "min_access_level": "Advanced",
      "lazy_load": true,
      "query_key": "get_tablespaces"
    },
    {
      "key": "security",
      "name": "Security",
      "icon": "🔒",
      "enabled": true,
      "min_access_level": "DBA",
      "lazy_load": true,
      "sub_categories": [
        {
          "key": "roles",
          "name": "Roles",
          "icon": "🎭",
          "query_key": "get_roles",
          "privilege_categories": [
            {
              "key": "table_privileges",
              "name": "Tables Privileges",
              "icon": "📋",
              "query_key": "get_role_table_privileges"
            }
          ]
        }
      ]
    }
  ],
  "schema_object_types": [
    {
      "key": "tables",
      "name": "Tables",
      "icon": "📋",
      "enabled": true,
      "min_access_level": "Standard",
      "query_key": "get_tables_for_schema",
      "property_window_key": "table_details"
    },
    {
      "key": "packages",
      "name": "Packages",
      "icon": "📦",
      "enabled": true,
      "min_access_level": "Advanced",
      "query_key": "get_packages_for_schema",
      "property_window_key": "package_details"
    }
  ]
}
```

#### C. `property_windows_config.json`
```json
{
  "provider": "DB2",
  "version": "12.1",
  "description": "Property window definitions",
  "property_windows": {
    "table_details": {
      "enabled": true,
      "title": "Table Details",
      "dialog_class": "TableDetailsDialog",
      "tabs": [
        {
          "key": "properties",
          "name": "Properties",
          "icon": "📋",
          "enabled": true,
          "query_key": "get_table_properties"
        },
        {
          "key": "columns",
          "name": "Columns",
          "icon": "📝",
          "enabled": true,
          "query_key": "get_table_columns"
        },
        {
          "key": "indexes",
          "name": "Indexes",
          "icon": "🔎",
          "enabled": true,
          "query_key": "get_table_indexes"
        },
        {
          "key": "foreign_keys",
          "name": "Foreign Keys",
          "icon": "🔗",
          "enabled": true,
          "query_key": "get_table_foreign_keys"
        },
        {
          "key": "statistics",
          "name": "Statistics",
          "icon": "📊",
          "enabled": true,
          "query_key": "get_table_statistics"
        },
        {
          "key": "create_ddl",
          "name": "CREATE DDL",
          "icon": "📝",
          "enabled": true,
          "min_access_level": "Advanced",
          "query_key": "generate_table_create_ddl"
        },
        {
          "key": "drop_ddl",
          "name": "DROP DDL",
          "icon": "🗑️",
          "enabled": true,
          "min_access_level": "Advanced",
          "query_key": "generate_table_drop_ddl"
        }
      ]
    },
    "package_details": {
      "enabled": true,
      "title": "Package Details",
      "dialog_class": "PackageDetailsDialog",
      "tabs": [
        {
          "key": "properties",
          "name": "Properties",
          "enabled": true,
          "query_key": "get_package_properties"
        },
        {
          "key": "statements",
          "name": "SQL Statements",
          "enabled": true,
          "query_key": "get_package_statements"
        }
      ]
    }
  }
}
```

#### D. `ui_features_config.json`
```json
{
  "provider": "DB2",
  "version": "12.1",
  "description": "UI feature flags",
  "features": {
    "mermaid_designer": {
      "enabled": true,
      "min_access_level": "Advanced",
      "menu_path": "View > Mermaid Visual Designer"
    },
    "lock_monitor": {
      "enabled": true,
      "min_access_level": "DBA",
      "menu_path": "Tools > Lock Monitor"
    },
    "export_to_json": {
      "enabled": true,
      "min_access_level": "Standard"
    },
    "ddl_generation": {
      "enabled": true,
      "min_access_level": "Advanced"
    },
    "sql_formatting": {
      "enabled": true,
      "min_access_level": "Standard",
      "formatter": "PoorMansTSqlFormatter"
    }
  }
}
```

#### E. `syntax_keywords.json`
```json
{
  "provider": "DB2",
  "version": "12.1",
  "description": "SQL syntax keywords for highlighting and intellisense",
  "reserved_words": [
    "SELECT", "FROM", "WHERE", "INSERT", "UPDATE", "DELETE",
    "CREATE", "DROP", "ALTER", "TABLE", "VIEW", "INDEX",
    "PROCEDURE", "FUNCTION", "TRIGGER", "SEQUENCE",
    "JOIN", "INNER", "LEFT", "RIGHT", "OUTER", "ON",
    "GROUP", "BY", "ORDER", "HAVING", "UNION", "DISTINCT",
    "AS", "CASE", "WHEN", "THEN", "ELSE", "END",
    "AND", "OR", "NOT", "IN", "EXISTS", "BETWEEN", "LIKE",
    "IS", "NULL", "VALUES", "INTO", "SET"
  ],
  "data_types": [
    "INTEGER", "SMALLINT", "BIGINT", "DECIMAL", "NUMERIC",
    "REAL", "DOUBLE", "FLOAT", "CHAR", "VARCHAR", "CLOB",
    "DATE", "TIME", "TIMESTAMP", "BLOB", "XML"
  ],
  "functions": [
    "COUNT", "SUM", "AVG", "MIN", "MAX", "TRIM", "UPPER",
    "LOWER", "SUBSTRING", "CONCAT", "LISTAGG", "COALESCE",
    "CAST", "CURRENT_DATE", "CURRENT_TIME", "CURRENT_TIMESTAMP"
  ],
  "system_schemas": [
    "SYSCAT", "SYSIBM", "SYSFUN", "SYSPROC", "SYSSTAT",
    "SYSTOOLS", "SYSIBMADM", "SYSIBMTS", "SYSPUBLIC", "NULLID"
  ]
}
```

#### F. `intellisense_config.json`
```json
{
  "provider": "DB2",
  "version": "12.1",
  "description": "Intellisense/autocomplete configuration",
  "enabled": true,
  "features": {
    "keyword_completion": {
      "enabled": true,
      "trigger_characters": ["SELECT", "FROM", "WHERE"],
      "case_style": "UPPERCASE"
    },
    "table_completion": {
      "enabled": true,
      "trigger_characters": ["FROM", "JOIN", "UPDATE", "INSERT INTO"],
      "include_schema": true,
      "cache_duration_seconds": 300
    },
    "column_completion": {
      "enabled": true,
      "trigger_characters": ["SELECT", "WHERE", "ORDER BY", "GROUP BY"],
      "show_data_types": true,
      "query_key": "get_table_columns"
    },
    "function_completion": {
      "enabled": true,
      "trigger_characters": ["("],
      "show_parameters": true,
      "show_return_type": true
    },
    "schema_completion": {
      "enabled": true,
      "trigger_characters": ["."],
      "include_system_schemas": true,
      "query_key": "get_all_schemas"
    },
    "snippet_templates": [
      {
        "key": "select_all",
        "trigger": "sel",
        "template": "SELECT * FROM ${1:table_name} WHERE ${2:condition}",
        "description": "SELECT all columns with WHERE clause"
      },
      {
        "key": "select_columns",
        "trigger": "selc",
        "template": "SELECT ${1:column_list} FROM ${2:table_name}",
        "description": "SELECT specific columns"
      },
      {
        "key": "insert_values",
        "trigger": "ins",
        "template": "INSERT INTO ${1:table_name} (${2:columns}) VALUES (${3:values})",
        "description": "INSERT with values"
      },
      {
        "key": "update_where",
        "trigger": "upd",
        "template": "UPDATE ${1:table_name} SET ${2:column} = ${3:value} WHERE ${4:condition}",
        "description": "UPDATE with WHERE clause"
      },
      {
        "key": "create_table",
        "trigger": "crt",
        "template": "CREATE TABLE ${1:schema}.${2:table_name} (\n    ${3:column_name} ${4:data_type} NOT NULL,\n    PRIMARY KEY (${5:pk_column})\n) IN ${6:USERSPACE1}",
        "description": "CREATE TABLE with primary key"
      }
    ]
  },
  "context_aware_suggestions": {
    "after_select": ["column_names", "functions", "DISTINCT", "TOP", "*"],
    "after_from": ["table_names", "schema.table", "subquery"],
    "after_where": ["column_names", "operators", "functions"],
    "after_join": ["table_names", "ON", "USING"],
    "after_on": ["join_conditions", "column_names"],
    "after_group_by": ["column_names"],
    "after_order_by": ["column_names", "ASC", "DESC"]
  },
  "operator_suggestions": [
    "=", "<>", "!=", ">", "<", ">=", "<=",
    "LIKE", "NOT LIKE", "IN", "NOT IN",
    "BETWEEN", "NOT BETWEEN", "IS NULL", "IS NOT NULL",
    "EXISTS", "NOT EXISTS"
  ]
}
```

---

## 🔧 IMPLEMENTATION PHASES

### Phase 1: Core Metadata Service (Week 1)
**Goal:** Create the foundation - metadata loading and query abstraction

**Tasks:**
1. Create `Metadata/` folder structure in project
2. Create JSON schema definitions
3. Refactor `DB2MetadataService.cs` to load all JSON files on startup
4. Implement query dictionary with provider/version/key lookup
5. Create `MetadataModels.cs` for JSON deserialization

### Phase 2: SQL Statement Migration (Week 2)
**Goal:** Move all SQL statements from code to JSON

**Tasks:**
1. Extract all SQL from `ObjectBrowserService.cs` → `sql_statements.json`
2. Extract all SQL from property dialogs → `sql_statements.json`
3. Extract all SQL from `DdlGeneratorService.cs` → `sql_statements.json`
4. Verify each statement against `Db2CreateDBQA_NonRelated.sql`
5. Update all calling code to use `GetQuery()` instead of inline SQL

### Phase 3: Object Browser Configuration (Week 3)
**Goal:** Externalize Object Browser structure

**Tasks:**
1. Create `object_browser_config.json` for DB2 v12.1
2. Update `ObjectBrowserService.cs` to build tree from JSON config
3. Implement dynamic object type enabling/disabling
4. Test Object Browser with different access levels

### Phase 4: Property Window Configuration (Week 4)
**Goal:** Make property windows configurable

**Tasks:**
1. Create `property_windows_config.json` for DB2 v12.1
2. Update property dialogs to load tab configuration from JSON
3. Implement dynamic tab enabling/disabling
4. Test all property windows with JSON-driven tabs

### Phase 5: UI Features & Syntax (Week 5)
**Goal:** Complete the abstraction

**Tasks:**
1. Create `ui_features_config.json`
2. Create `syntax_keywords.json`
3. Create `intellisense_config.json`
4. Update syntax highlighter to use JSON keyword lists
5. Implement feature flag checks throughout UI
6. Implement JSON-driven intellisense/autocomplete
7. Test menu item visibility based on feature flags

**Note on Intellisense:** 
- Current implementation (Bug-6) is not working
- JSON-driven approach will provide:
  - Context-aware suggestions (after SELECT, FROM, WHERE, etc.)
  - Dynamic table/column completion from current database
  - Snippet templates for common patterns
  - Provider-specific keywords and functions
  - Version-specific SQL syntax support

### Phase 6: Multi-Version Support (Week 6)
**Goal:** Add support for DB2 v11.5 and v9.7

**Tasks:**
1. Create JSON files for DB2 v11.5
2. Create JSON files for DB2 v9.7
3. Implement version detection and automatic JSON selection
4. Test application against different DB2 versions

---

## 📝 DETAILED TASK LIST

### Foundation Tasks
- [ ] **TASK-META-001:** Create `Metadata/` folder structure
- [ ] **TASK-META-002:** Create JSON schema definitions
- [ ] **TASK-META-003:** Create `Models/MetadataModels.cs` for JSON models
- [ ] **TASK-META-004:** Refactor `DB2MetadataService.cs` - add JSON loading
- [ ] **TASK-META-005:** Implement `GetQuery(provider, version, key)` method
- [ ] **TASK-META-006:** Implement `GetObjectBrowserConfig(provider, version)` method
- [ ] **TASK-META-007:** Implement `GetPropertyWindowConfig(provider, version)` method
- [ ] **TASK-META-008:** Implement `IsFeatureEnabled(provider, version, feature)` method

### SQL Statement Extraction Tasks
- [ ] **TASK-SQL-001:** Extract ObjectBrowserService queries to JSON
- [ ] **TASK-SQL-002:** Extract TableDetailsDialog queries to JSON
- [ ] **TASK-SQL-003:** Extract PackageDetailsDialog queries to JSON
- [ ] **TASK-SQL-004:** Extract UserDetailsDialog queries to JSON
- [ ] **TASK-SQL-005:** Extract ObjectDetailsDialog queries to JSON
- [ ] **TASK-SQL-006:** Extract DdlGeneratorService queries to JSON
- [ ] **TASK-SQL-007:** Extract all other scattered SQL queries
- [ ] **TASK-SQL-008:** Verify all queries against proven patterns
- [ ] **TASK-SQL-009:** Update ObjectBrowserService to use GetQuery()
- [ ] **TASK-SQL-010:** Update all dialogs to use GetQuery()
- [ ] **TASK-SQL-011:** Update all services to use GetQuery()

### Configuration Tasks
- [ ] **TASK-CFG-001:** Create object_browser_config.json for DB2 v12.1
- [ ] **TASK-CFG-002:** Create property_windows_config.json for DB2 v12.1
- [ ] **TASK-CFG-003:** Create ui_features_config.json for DB2 v12.1
- [ ] **TASK-CFG-004:** Create syntax_keywords.json for DB2 v12.1
- [ ] **TASK-CFG-005:** Implement dynamic Object Browser from JSON
- [ ] **TASK-CFG-006:** Implement dynamic property windows from JSON
- [ ] **TASK-CFG-007:** Implement feature flag checking
- [ ] **TASK-CFG-008:** Update syntax highlighter to use JSON keywords

### Multi-Version Tasks
- [ ] **TASK-VER-001:** Create all JSON files for DB2 v11.5
- [ ] **TASK-VER-002:** Create all JSON files for DB2 v9.7
- [ ] **TASK-VER-003:** Implement automatic version detection
- [ ] **TASK-VER-004:** Implement fallback to lower versions if query missing
- [ ] **TASK-VER-005:** Test against DB2 v12.1
- [ ] **TASK-VER-006:** Test against DB2 v11.5
- [ ] **TASK-VER-007:** Test against DB2 v9.7

### Documentation Tasks
- [ ] **TASK-DOC-001:** Document JSON file formats
- [ ] **TASK-DOC-002:** Create migration guide for developers
- [ ] **TASK-DOC-003:** Document how to add new providers
- [ ] **TASK-DOC-004:** Document how to add new versions
- [ ] **TASK-DOC-005:** Create JSON validation tool

---

## 🎨 EXAMPLE: Before & After

### Before (Current)
```csharp
// In ObjectBrowserService.cs - HARDCODED SQL
public async Task<List<DatabaseObject>> GetViewsAsync(string schemaName)
{
    var sql = @"
        SELECT 
            TRIM(V.VIEWNAME) AS VIEWNAME,
            TRIM(T.DEFINER) AS OWNER,
            TRIM(T.REMARKS) AS REMARKS
        FROM SYSCAT.TABLES T
        JOIN SYSCAT.VIEWS V ON T.TABSCHEMA = V.VIEWSCHEMA 
            AND T.TABNAME = V.VIEWNAME
        WHERE T.TYPE = 'V' AND T.TABSCHEMA = ?
        ORDER BY V.VIEWNAME";
    
    // Execute query...
}
```

### After (Target)
```csharp
// In ObjectBrowserService.cs - JSON-DRIVEN
public async Task<List<DatabaseObject>> GetViewsAsync(string schemaName)
{
    var sql = _metadataService.GetQuery(
        provider: "DB2",
        version: _connectionManager.GetDbVersion(),
        key: "get_views_for_schema"
    );
    
    // Execute query...
}
```

---

## 🚀 MIGRATION STRATEGY

### Step 1: Parallel Implementation
- Keep existing hardcoded SQL working
- Add JSON-based queries alongside
- Gradually migrate service by service

### Step 2: Validation Phase
- Test both old and new approaches side-by-side
- Verify JSON queries return identical results
- Performance testing

### Step 3: Switchover
- Remove hardcoded SQL
- Full JSON-driven implementation
- Update documentation

---

## 🎯 ADDITIONAL ELEMENTS TO ABSTRACT

Beyond SQL queries, these elements should also be moved to JSON configuration:

### 1. **Icons & Emojis** (`ui_icons.json`)
**Current State:** Hardcoded in `ObjectBrowserIcons` class (Models/ObjectBrowserModels.cs)

**Target JSON Structure:**
```json
{
  "provider": "DB2",
  "version": "12.1",
  "icons": {
    "categories": {
      "database": "🗄️",
      "schemas": "📁",
      "tablespaces": "💾",
      "packages": "📦",
      "security": "🔒"
    },
    "objects": {
      "table": "📄",
      "system_table": "⚙️",
      "view": "👁",
      "materialized_view": "📊",
      "procedure": "⚙️",
      "function": "⚡",
      "scalar_function": "🔢",
      "table_function": "📊",
      "index": "🔎",
      "primary_key": "🔑",
      "foreign_key": "🔗",
      "trigger": "🎯",
      "sequence": "🔢",
      "synonym": "🔗",
      "type": "🔤",
      "package": "📦"
    },
    "security": {
      "role": "🎭",
      "group": "👥",
      "user": "👤"
    },
    "status": {
      "loading": "⏳",
      "error": "❌",
      "warning": "⚠",
      "success": "✅",
      "empty": "📭",
      "refresh": "🔄",
      "search": "🔍"
    }
  }
}
```

**Benefit:** Provider-specific icon sets, theme customization, Unicode vs font icons

---

### 2. **Error Messages & User Prompts** (`ui_messages.json`)
**Current State:** Scattered across 202 `MessageBox.Show()` calls

**Target JSON Structure:**
```json
{
  "provider": "DB2",
  "version": "12.1",
  "language": "en-US",
  "messages": {
    "connection_errors": {
      "failed_to_connect": "Failed to connect to {database}.\n\nPlease check your connection settings and try again.",
      "connection_timeout": "Connection timed out after {timeout} seconds.",
      "connection_lost": "Connection to {database} was lost. Would you like to reconnect?",
      "invalid_credentials": "Authentication failed. Please check your username and password."
    },
    "query_errors": {
      "syntax_error": "SQL syntax error:\n\n{error}",
      "execution_failed": "Query execution failed:\n\n{error}",
      "timeout": "Query timed out after {timeout} seconds."
    },
    "warnings": {
      "delete_without_where": "⚠️ WARNING: DELETE without WHERE clause detected!\n\nThis will delete ALL rows from the table.\n\nAre you sure you want to continue?",
      "update_without_where": "⚠️ WARNING: UPDATE without WHERE clause detected!\n\nThis will update ALL rows in the table.\n\nAre you sure you want to continue?",
      "drop_object": "⚠️ WARNING: You are about to DROP {object_type} {object_name}.\n\nThis operation cannot be undone.\n\nAre you sure?"
    },
    "confirmations": {
      "close_tab_with_unsaved": "You have unsaved SQL in this tab. Close anyway?",
      "disconnect_active_connection": "Close connection to {database}?",
      "overwrite_file": "File already exists. Overwrite?"
    },
    "success": {
      "query_executed": "Query completed successfully. {rows} rows affected.",
      "export_complete": "Data exported successfully to {filename}.",
      "ddl_generated": "DDL generated successfully."
    },
    "info": {
      "no_active_connection": "Please open a database connection first.",
      "no_data_to_export": "No data available to export.",
      "feature_requires_dba": "This feature requires DBA privileges."
    }
  }
}
```

**Benefit:** Multi-language support, consistent messaging, easier maintenance, provider-specific errors

---

### 3. **UI Layout & Sizing** (`ui_layout.json`)
**Current State:** Hardcoded in XAML files (448 instances of MinHeight/Width/Padding/Margin)

**Target JSON Structure:**
```json
{
  "provider": "DB2",
  "version": "12.1",
  "layout": {
    "main_window": {
      "min_width": 1024,
      "min_height": 768,
      "default_width": 1280,
      "default_height": 900
    },
    "toolbar": {
      "min_height": 48,
      "button_height": 32,
      "button_width": 120,
      "icon_size": 16,
      "padding": 5
    },
    "statusbar": {
      "min_height": 28,
      "font_size": 12,
      "padding": 5
    },
    "sql_editor": {
      "font_family": "Consolas",
      "font_size": 14,
      "line_height": 20,
      "show_line_numbers": true,
      "tab_size": 4
    },
    "object_browser": {
      "initial_width": 250,
      "min_width": 150,
      "max_width": 800,
      "auto_grow_width": true,
      "tree_item_height": 24,
      "icon_size": 16,
      "font_size": 12
    },
    "data_grid": {
      "row_height": 24,
      "header_height": 30,
      "font_size": 11,
      "alternating_row_background": true
    },
    "dialogs": {
      "connection_dialog": {"width": 500, "height": 600},
      "table_details": {"width": 900, "height": 700},
      "settings_dialog": {"width": 700, "height": 600}
    }
  }
}
```

**Benefit:** DPI-aware scaling, consistent sizing, theme customization, provider-specific UI

---

### 4. **Timeout & Performance Settings** (`performance_config.json`)
**Current State:** Scattered across multiple files (DB2Connection, appsettings.json, UserPreferences)

**Target JSON Structure:**
```json
{
  "provider": "DB2",
  "version": "12.1",
  "performance": {
    "connection": {
      "timeout_seconds": 30,
      "retry_attempts": 3,
      "retry_delay_ms": 1000,
      "keepalive_interval_seconds": 60
    },
    "query_execution": {
      "default_timeout_seconds": 30,
      "long_query_threshold_seconds": 10,
      "warning_threshold_seconds": 300,
      "max_result_rows": 10000,
      "pagination_page_size": 1000
    },
    "metadata_collection": {
      "cache_duration_seconds": 300,
      "background_refresh": true,
      "batch_size": 100
    },
    "ui_responsiveness": {
      "tree_load_batch_size": 100,
      "search_debounce_ms": 300,
      "progress_update_interval_ms": 500
    }
  }
}
```

**Benefit:** Tunable performance, environment-specific settings, provider-specific optimizations

---

### 5. **Keyboard Shortcuts** (`keyboard_shortcuts.json`)
**Current State:** Hardcoded in code-behind event handlers

**Target JSON Structure:**
```json
{
  "provider": "DB2",
  "version": "12.1",
  "shortcuts": {
    "editor": {
      "execute_query": "F5",
      "execute_current_statement": "Ctrl+Enter",
      "format_sql": "Ctrl+Shift+F",
      "comment_selection": "Ctrl+K, Ctrl+C",
      "uncomment_selection": "Ctrl+K, Ctrl+U",
      "find": "Ctrl+F",
      "replace": "Ctrl+H",
      "go_to_line": "Ctrl+G"
    },
    "tabs": {
      "new_connection": "Ctrl+N",
      "close_tab": "Ctrl+W",
      "next_tab": "Ctrl+Tab",
      "previous_tab": "Ctrl+Shift+Tab"
    },
    "file": {
      "save_script": "Ctrl+S",
      "open_script": "Ctrl+O",
      "save_as": "Ctrl+Shift+S"
    },
    "view": {
      "toggle_dark_mode": "Ctrl+D",
      "toggle_object_browser": "Ctrl+B",
      "focus_object_browser_search": "Ctrl+Shift+O"
    }
  }
}
```

**Benefit:** User customization, provider-specific defaults, accessibility

---

### 6. **Context Menu Actions** (`context_menus.json`)
**Current State:** Hardcoded in XAML and code-behind

**Target JSON Structure:**
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
          "icon": "📊",
          "min_access_level": "Standard",
          "query_key": "get_top_n_rows"
        },
        {
          "id": "count_rows",
          "label": "🔢 Count Rows",
          "icon": "🔢",
          "min_access_level": "Standard",
          "query_key": "get_row_count"
        },
        {
          "id": "view_properties",
          "label": "📋 Table Properties...",
          "icon": "📋",
          "min_access_level": "Standard",
          "opens_dialog": "table_properties"
        },
        {
          "id": "generate_ddl",
          "label": "📝 Generate CREATE DDL",
          "icon": "📝",
          "min_access_level": "Advanced",
          "query_key": "get_create_table_ddl"
        }
      ]
    },
    "view": {
      "actions": [
        {
          "id": "view_source",
          "label": "👁 View Source Code",
          "icon": "👁",
          "min_access_level": "Standard",
          "query_key": "get_view_definition"
        }
      ]
    }
  }
}
```

**Benefit:** Dynamic menus, version-specific actions, RBAC-aware

---

### 7. **SQL Templates** (`sql_templates.json`)
**Current State:** Hardcoded for intellisense snippets

**Target JSON Structure:**
```json
{
  "provider": "DB2",
  "version": "12.1",
  "templates": {
    "select_top_n": "SELECT * FROM {schema}.{table} FETCH FIRST {n} ROWS ONLY",
    "count_rows": "SELECT COUNT(*) FROM {schema}.{table}",
    "describe_table": "SELECT * FROM SYSCAT.COLUMNS WHERE TABSCHEMA = '{schema}' AND TABNAME = '{table}' ORDER BY COLNO",
    "list_indexes": "SELECT * FROM SYSCAT.INDEXES WHERE TABSCHEMA = '{schema}' AND TABNAME = '{table}'",
    "find_foreign_keys": "SELECT * FROM SYSCAT.REFERENCES WHERE TABSCHEMA = '{schema}' AND TABNAME = '{table}'",
    "check_table_stats": "SELECT * FROM SYSCAT.TABLES WHERE TABSCHEMA = '{schema}' AND TABNAME = '{table}'"
  }
}
```

**Benefit:** Provider-specific SQL syntax (FETCH FIRST vs TOP vs LIMIT), version-specific features

---

### 8. **Intellisense Configuration** (Already Added)
See `intellisense_config.json` in Phase 5.

---

---

## 🌍 LOCALIZATION INTEGRATION

This metadata abstraction plan integrates with the **Localization Architecture** for complete internationalization:

### UI Text Keys Reference
All UI text is stored in language-specific JSON files and referenced by keys:

```json
// In Metadata/DB2/12.1/ui_features_config.json
{
  "features": {
    "packages": {
      "enabled": true,
      "name_key": "ui.object_browser.categories.packages",
      "description_key": "ui.object_browser.tooltips.packages"
    }
  }
}

// In Localization/en-US.json
{
  "ui": {
    "object_browser": {
      "categories": {
        "packages": "Packages"
      },
      "tooltips": {
        "packages": "DB2 packages containing SQL statements"
      }
    }
  }
}

// In Localization/fr-FR.json
{
  "ui": {
    "object_browser": {
      "categories": {
        "packages": "Paquets"
      },
      "tooltips": {
        "packages": "Paquets DB2 contenant des instructions SQL"
      }
    }
  }
}
```

### Combined Architecture
```
/Metadata/
├── DB2/12.1/
│   ├── sql_statements.json         # SQL queries
│   ├── ui_features_config.json     # References to text keys
│   └── ui_text_keys.json           # Mapping of UI elements to text keys
└── ...

/Localization/
├── en-US.json                      # English translations
├── fr-FR.json                      # French translations
├── no-NO.json                      # Norwegian translations
└── ...
```

**See:** `LOCALIZATION_ARCHITECTURE_PLAN.md` for complete details on multi-language support.

---

## 📊 SUCCESS CRITERIA

✅ **Zero hardcoded SQL** in application code  
✅ **All queries** retrievable via `GetQuery(provider, version, key)`  
✅ **Object Browser** fully configurable via JSON  
✅ **Property windows** dynamically generated from JSON  
✅ **UI features** controlled by JSON flags  
✅ **Syntax highlighting** driven by JSON keyword lists  
✅ **Multi-version support** (12.1, 11.5, 9.7)  
✅ **Provider abstraction** ready for SQL Server extension  
✅ **Build succeeds** with zero compilation errors  
✅ **All tests pass** with JSON-driven queries  

---

## 🔮 FUTURE EXTENSIBILITY

### Adding SQL Server Support (Future)
```
/Metadata/
├── DB2/...
└── SQLSERVER/
    └── 2022/
        ├── sql_statements.json
        ├── object_browser_config.json
        ├── property_windows_config.json
        ├── ui_features_config.json
        └── syntax_keywords.json
```

**Application code stays the same:**
```csharp
var sql = _metadataService.GetQuery(
    provider: "SQLSERVER",  // Changed from "DB2"
    version: "2022",
    key: "get_views_for_schema"
);
```

---

## 📋 NEXT STEPS

1. ✅ **Review this plan** with team/user
2. ✅ **Get approval** for architectural direction
3. 🔄 **Start Phase 1** - Create metadata service foundation
4. 🔄 **Verify first query** from JSON works end-to-end
5. 🔄 **Migrate incrementally** - one service at a time

---

**Estimated Total Effort:** 6 weeks (240 hours)  
**Priority:** HIGH - Foundational architecture improvement  
**Benefits:**  
- Database provider agnostic
- Version-aware feature support
- Easy maintenance (no code changes for SQL tweaks)
- Extensible to other databases
- JSON-driven configuration
- Professional architecture


