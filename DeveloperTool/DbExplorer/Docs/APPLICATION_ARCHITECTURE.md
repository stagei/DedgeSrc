# DbExplorer - Application Architecture

## Overview

DbExplorer is a **provider-agnostic database editor** for Windows, built with WPF/.NET 10. The architecture emphasizes:
- **Provider Independence**: Support for multiple databases (DB2, PostgreSQL, Oracle, SQL Server)
- **Factory Pattern**: All provider-specific code isolated to factories
- **Configuration-Driven**: SQL statements and metadata in JSON files
- **Modular Design**: Clear separation between UI, Services, and Data layers

## High-Level Architecture

```mermaid
graph TB
    subgraph "Presentation Layer"
        MW[MainWindow]
        TABS[ConnectionTabControl]
        DIALOGS[Dialogs]
        TREE[Object Browser]
    end
    
    subgraph "Service Layer"
        META[MetadataHandler]
        PREFS[PreferencesService]
        CONN_STOR[ConnectionStorageService]
        SQL_TRANS[SqlTranslationServices]
        EXPORT[ExportService]
        HISTORY[QueryHistoryService]
    end
    
    subgraph "Data Layer"
        FACTORY[ConnectionManagerFactory]
        ICONN[IConnectionManager]
        DB2[DB2ConnectionManager]
        PG[PostgreSQLConnectionManager]
        ORA[OracleConnectionManager]
    end
    
    subgraph "Configuration"
        JSON_SQL[*_sql_statements.json]
        JSON_CONN[connections.json]
        JSON_PREF[preferences.json]
        JSON_META[*_system_metadata.json]
    end
    
    subgraph "Database"
        DB[(Database Server)]
    end
    
    MW --> TABS
    MW --> DIALOGS
    TABS --> TREE
    
    TABS --> META
    DIALOGS --> META
    META --> JSON_SQL
    META --> JSON_META
    
    TABS --> FACTORY
    DIALOGS --> FACTORY
    FACTORY --> ICONN
    ICONN --> DB2
    ICONN --> PG
    ICONN --> ORA
    
    DB2 --> DB
    PG --> DB
    ORA --> DB
    
    CONN_STOR --> JSON_CONN
    PREFS --> JSON_PREF
```

## Core Design Patterns

### Factory Pattern (MANDATORY)

```mermaid
graph LR
    subgraph "UI/Services (Provider-Agnostic)"
        DIALOG[Any Dialog/Service]
        INTERFACE[IConnectionManager]
    end
    
    subgraph "Factory (ONLY Provider-Aware)"
        FACTORY[ConnectionManagerFactory]
    end
    
    subgraph "Provider Implementations"
        DB2[DB2ConnectionManager]
        PG[PostgreSQLConnectionManager]
        ORA[OracleConnectionManager]
        MSSQL[SqlServerConnectionManager]
    end
    
    DIALOG -->|"Uses interface"| INTERFACE
    DIALOG -->|"CreateConnectionManager()"| FACTORY
    FACTORY -->|"switch provider"| DB2
    FACTORY -->|"switch provider"| PG
    FACTORY -->|"switch provider"| ORA
    FACTORY -->|"switch provider"| MSSQL
    
    DB2 -.->|implements| INTERFACE
    PG -.->|implements| INTERFACE
    ORA -.->|implements| INTERFACE
    MSSQL -.->|implements| INTERFACE
```

### SQL Abstraction Pattern

```mermaid
graph TB
    subgraph "Application Code"
        SVC[Any Service]
        CODE["GetStatement('GetTableColumns')"]
    end
    
    subgraph "MetadataHandler"
        MH[MetadataHandler]
        CACHE[Statement Cache]
    end
    
    subgraph "JSON Configuration"
        DB2_SQL[db2_12.1_sql_statements.json]
        PG_SQL[postgresql_16.0_sql_statements.json]
        ORA_SQL[oracle_19c_sql_statements.json]
    end
    
    SVC --> CODE
    CODE --> MH
    MH --> CACHE
    MH -->|"provider=DB2"| DB2_SQL
    MH -->|"provider=PostgreSQL"| PG_SQL
    MH -->|"provider=Oracle"| ORA_SQL
    
    DB2_SQL -->|"SYSCAT.COLUMNS"| RESULT[SQL Statement]
    PG_SQL -->|"information_schema.columns"| RESULT
    ORA_SQL -->|"ALL_TAB_COLUMNS"| RESULT
```

## Folder Structure

```mermaid
graph TB
    ROOT[DbExplorer/]
    
    subgraph "UI Layer"
        CONTROLS[Controls/]
        DIALOGS[Dialogs/]
        MAIN[MainWindow.xaml]
    end
    
    subgraph "Business Logic"
        SERVICES[Services/]
        UTILS[Utils/]
    end
    
    subgraph "Data Access"
        DATA[Data/]
        PROVIDERS[Data/Providers/]
    end
    
    subgraph "Models"
        MODELS[Models/]
    end
    
    subgraph "Configuration"
        CONFIG[ConfigFiles/]
        RESOURCES[Resources/]
    end
    
    subgraph "Companion Apps"
        TRAY[DbExplorerTray/]
    end
    
    ROOT --> CONTROLS
    ROOT --> DIALOGS
    ROOT --> MAIN
    ROOT --> SERVICES
    ROOT --> UTILS
    ROOT --> DATA
    DATA --> PROVIDERS
    ROOT --> MODELS
    ROOT --> CONFIG
    ROOT --> RESOURCES
    ROOT --> TRAY
```

## Connection Flow

```mermaid
sequenceDiagram
    participant User
    participant Dialog as ConnectionDialog
    participant Storage as ConnectionStorageService
    participant Factory as ConnectionManagerFactory
    participant ConnMgr as IConnectionManager
    participant DB as Database
    
    User->>Dialog: Enter connection details
    Dialog->>Storage: SaveConnection(profile)
    Storage->>Storage: Write to connections.json
    
    User->>Dialog: Click "Connect"
    Dialog->>Factory: CreateConnectionManager(profile)
    Factory->>Factory: Switch on ProviderType
    Factory-->>ConnMgr: Return DB2/PG/Oracle ConnectionManager
    
    Dialog->>ConnMgr: ConnectAsync()
    ConnMgr->>DB: Open connection
    DB-->>ConnMgr: Connected
    ConnMgr-->>Dialog: Success
    
    Dialog->>User: Show connected tab
```

## Query Execution Flow

```mermaid
sequenceDiagram
    participant User
    participant Editor as SQL Editor
    participant Tab as ConnectionTabControl
    participant ConnMgr as IConnectionManager
    participant History as QueryHistoryService
    participant DB as Database
    
    User->>Editor: Type SQL query
    User->>Editor: Press F5 (Execute)
    
    Editor->>Tab: ExecuteQueryAsync(sql)
    Tab->>History: SaveQuery(sql)
    Tab->>ConnMgr: ExecuteQueryAsync(sql)
    
    ConnMgr->>DB: Execute SQL
    DB-->>ConnMgr: DataTable results
    
    ConnMgr-->>Tab: Results
    Tab->>Editor: Display in DataGrid
    Tab->>User: Show row count, timing
```

## Object Browser Architecture

```mermaid
graph TB
    subgraph "Object Browser Tree"
        ROOT[Database Root]
        SCHEMAS[Schemas Node]
        TABLES[Tables Node]
        VIEWS[Views Node]
        PROCS[Procedures Node]
        FUNCS[Functions Node]
    end
    
    subgraph "Lazy Loading"
        EXPAND[On Node Expand]
        LOAD[Load Children]
        META[MetadataHandler]
    end
    
    subgraph "Context Actions"
        CTX[Right-Click Menu]
        PROPS[View Properties]
        DDL[Generate DDL]
        SAMPLE[Sample Data]
        EXPORT[Export]
    end
    
    ROOT --> SCHEMAS
    SCHEMAS --> TABLES
    SCHEMAS --> VIEWS
    SCHEMAS --> PROCS
    SCHEMAS --> FUNCS
    
    EXPAND --> LOAD
    LOAD --> META
    META --> |SQL Query| DB[(Database)]
    
    TABLES --> CTX
    VIEWS --> CTX
    CTX --> PROPS
    CTX --> DDL
    CTX --> SAMPLE
    CTX --> EXPORT
```

## Tray Application Architecture

```mermaid
graph TB
    subgraph "Main Application"
        MAIN[DbExplorer.exe]
        STARTUP[App.xaml.cs OnStartup]
    end
    
    subgraph "Tray Application"
        TRAY[DbExplorerTray.exe]
        ICON[System Tray Icon]
        MENU[Context Menu]
        WATCH[NotificationFolderWatcher]
    end
    
    subgraph "Communication"
        FOLDER[Notifications Folder]
        PROFILES[connections.json]
    end
    
    subgraph "User Actions"
        CONNECT[Quick Connect to Profile]
        OPEN[Open Main App]
        EXIT[Exit Tray]
    end
    
    STARTUP -->|"Process.Start()"| TRAY
    TRAY --> ICON
    ICON --> MENU
    
    MENU --> CONNECT
    MENU --> OPEN
    MENU --> EXIT
    
    TRAY --> WATCH
    WATCH --> FOLDER
    TRAY -->|"Read profiles"| PROFILES
    
    CONNECT -->|"Launch with -profile"| MAIN
```

## CLI Architecture

```mermaid
graph TB
    subgraph "CLI Entry"
        ARGS[Command Line Arguments]
        PARSER[CliArgumentParser]
    end
    
    subgraph "Command Handler"
        CLI[CliCommandHandlerService]
        DISPATCH[Command Dispatcher]
    end
    
    subgraph "Commands (119+)"
        SCHEMA[Schema Commands]
        TABLE[Table Commands]
        VIEW[View Commands]
        PROC[Procedure Commands]
        EXPORT[Export Commands]
        AI[AI Commands]
        MERMAID[Mermaid Commands]
    end
    
    subgraph "Output"
        JSON[JSON Output]
        CSV[CSV Output]
        TSV[TSV Output]
    end
    
    ARGS --> PARSER
    PARSER --> CLI
    CLI --> DISPATCH
    
    DISPATCH --> SCHEMA
    DISPATCH --> TABLE
    DISPATCH --> VIEW
    DISPATCH --> PROC
    DISPATCH --> EXPORT
    DISPATCH --> AI
    DISPATCH --> MERMAID
    
    SCHEMA --> JSON
    TABLE --> JSON
    TABLE --> CSV
    EXPORT --> TSV
```

## Configuration Files Architecture

The application uses a **configuration-driven** approach where SQL queries, UI text, IntelliSense data, and provider metadata are all stored in JSON files. This enables:
- Adding new database providers without code changes
- Multi-language support (localization)
- Version-specific SQL for different database versions
- Easy updates and customization

### Configuration File Flow

```mermaid
graph TB
    subgraph "Application Code"
        SVC[Services]
        UI[UI Components]
        INTELLI[IntelliSense Engine]
    end
    
    subgraph "Core Services"
        META[MetadataHandler]
        LOCALE[LocalizationService]
        KEYWORDS[KeywordService]
    end
    
    subgraph "ConfigFiles/"
        PROVIDERS[supported_providers.json]
        
        subgraph "Per-Provider Files"
            SQL[db2_12.1_sql_statements.json]
            SYSMETA[db2_12.1_system_metadata.json]
            INTEL_JSON[db2_12.1_intellisense.json]
            KW[db2_12.1_keywords.json]
            EN[db2_12.1_en-US_texts.json]
            NO[db2_12.1_no-NO_texts.json]
            SNIP[db2_snippets.json]
        end
    end
    
    SVC --> META
    META -->|"GetStatement()"| SQL
    META -->|"Load provider"| PROVIDERS
    
    UI --> LOCALE
    LOCALE -->|"GetText()"| EN
    LOCALE -->|"GetText()"| NO
    
    INTELLI --> KEYWORDS
    KEYWORDS --> INTEL_JSON
    KEYWORDS --> KW
    KEYWORDS --> SNIP
    
    META -.->|"Reference only"| SYSMETA
```

### ConfigFiles/ Directory Structure

```
ConfigFiles/
├── supported_providers.json           # Master list of database providers
│
├── db2_12.1_sql_statements.json       # All SQL queries for DB2 12.1
├── db2_12.1_sql_statements.json.backup # Backup before major changes
├── db2_12.1_sql_statements.json.temp   # Temp file during updates
│
├── db2_12.1_system_metadata.json      # DB2 catalog reference (dev only)
├── db2_12.1_intellisense.json         # IntelliSense: keywords, types, functions
├── db2_12.1_keywords.json             # SQL keywords for syntax highlighting
│
├── db2_12.1_en-US_texts.json          # English UI translations
├── db2_12.1_no-NO_texts.json          # Norwegian UI translations
│
└── db2_snippets.json                  # Code snippet templates
```

### Detailed File Descriptions

#### 1. `supported_providers.json` - Provider Registry

**Purpose**: Master list of all supported database providers with connection details.

**Used by**: `ConnectionManagerFactory`, `ConnectionDialog`, `MetadataHandler`

```json
{
  "providers": [
    {
      "provider_code": "DB2",
      "display_name": "IBM DB2 Database",
      "supported_versions": ["12.1", "11.5", "11.1"],
      "default_port": 50000,
      "connection_string_template": "Server={host}:{port};Database={database};...",
      "system_catalog_schema": "SYSCAT"
    }
  ]
}
```

**How it links**: When connecting, the app reads this file to determine which connection manager to create and what default settings to use.

---

#### 2. `db2_12.1_sql_statements.json` - SQL Query Repository

**Purpose**: ALL SQL queries used by the application for DB2 12.1. No hardcoded SQL in C# code.

**Used by**: `MetadataHandler.GetStatement()` → All services

```json
{
  "statements": {
    "GetTablesForSchema": {
      "sql": "SELECT TRIM(TABNAME) AS TABNAME... FROM SYSCAT.TABLES WHERE TRIM(TABSCHEMA) = ?",
      "description": "Get all tables in a schema",
      "parameters": ["TABSCHEMA"]
    }
  }
}
```

**How it links**:
```mermaid
graph LR
    SVC[ObjectBrowserService] -->|"GetStatement('GetTablesForSchema')"| META[MetadataHandler]
    META -->|"Load & cache"| JSON[db2_12.1_sql_statements.json]
    META -->|"Return SQL"| SVC
    SVC -->|"Execute"| DB[(Database)]
```

---

#### 3. `db2_12.1_system_metadata.json` - Developer Reference

**Purpose**: Documentation of DB2 system catalog structure. **NOT loaded at runtime** - used by developers/AI to understand the database schema when writing SQL statements.

**Used by**: Developers, AI assistants (reference only)

```json
{
  "purpose": "Reference file for building SQL statements - NOT loaded by app",
  "catalog_tables": {
    "SYSCAT.TABLES": {
      "columns": {
        "TABSCHEMA": { "type": "VARCHAR(128)", "description": "Schema name" },
        "TABNAME": { "type": "VARCHAR(128)", "description": "Table name" }
      }
    }
  }
}
```

**How it links**: When creating new SQL in `db2_12.1_sql_statements.json`, developers consult this file to verify column names and data types.

---

#### 4. `db2_12.1_intellisense.json` - IntelliSense Data

**Purpose**: Comprehensive keyword/function/datatype information for IntelliSense autocomplete.

**Used by**: `IntelliSenseService`, `CompletionProvider`

```json
{
  "keywords": {
    "statements": ["SELECT", "INSERT", "UPDATE", "DELETE"],
    "clauses": ["FROM", "WHERE", "GROUP BY", "ORDER BY"],
    "operators": ["AND", "OR", "NOT", "IN", "EXISTS"]
  },
  "dataTypes": {
    "numeric": ["INTEGER", "SMALLINT", "DECIMAL"],
    "string": ["VARCHAR", "CHAR", "CLOB"]
  },
  "functions": {
    "aggregate": ["COUNT", "SUM", "AVG", "MIN", "MAX"],
    "string": ["SUBSTR", "TRIM", "UPPER", "LOWER"]
  }
}
```

**How it links**:
```mermaid
graph LR
    EDITOR[SQL Editor] -->|"User types"| COMP[CompletionProvider]
    COMP -->|"Get suggestions"| INTEL[IntelliSenseService]
    INTEL -->|"Load"| JSON[db2_12.1_intellisense.json]
    JSON -->|"Keywords, functions"| INTEL
    INTEL -->|"Filtered list"| COMP
    COMP -->|"Show dropdown"| EDITOR
```

---

#### 5. `db2_12.1_keywords.json` - Syntax Highlighting

**Purpose**: SQL keywords for syntax highlighting in the editor.

**Used by**: `DB2SQL.xshd` (AvalonEdit syntax definition), `KeywordService`

```json
{
  "keywords": {
    "statements": ["SELECT", "INSERT", "UPDATE", "DELETE"],
    "datatypes": ["INTEGER", "VARCHAR", "TIMESTAMP"],
    "functions": ["COUNT", "SUM", "SUBSTR", "TRIM"]
  }
}
```

**How it links**: The syntax highlighter uses these keywords to color SQL code appropriately.

---

#### 6. `db2_12.1_en-US_texts.json` - English Localization

**Purpose**: All UI text in English for internationalization support.

**Used by**: `LocalizationService.GetText()`

```json
{
  "language": "en-US",
  "texts": {
    "ui.menu.file": "File",
    "ui.menu.file.new_connection": "New Connection...",
    "ui.toolbar.execute_tooltip": "Execute query (F5)",
    "errors.connection_failed": "Connection failed: {0}"
  }
}
```

---

#### 7. `db2_12.1_no-NO_texts.json` - Norwegian Localization

**Purpose**: Norwegian translation of all UI text.

**Used by**: `LocalizationService.GetText()` when language is set to Norwegian

```json
{
  "language": "no-NO",
  "ui": {
    "common": {
      "ok": "OK",
      "cancel": "Avbryt",
      "connect": "Koble til",
      "execute": "Kjør"
    }
  }
}
```

**How it links**:
```mermaid
graph LR
    UI[UI Component] -->|"GetText('ui.menu.file')"| LOC[LocalizationService]
    LOC -->|"Check preference"| PREF[User Language Setting]
    PREF -->|"no-NO"| NO[db2_12.1_no-NO_texts.json]
    PREF -->|"en-US"| EN[db2_12.1_en-US_texts.json]
    NO -->|"'Fil'"| LOC
    EN -->|"'File'"| LOC
    LOC -->|"Translated text"| UI
```

---

#### 8. `db2_snippets.json` - Code Snippets

**Purpose**: SQL snippet templates for quick code insertion.

**Used by**: `SnippetService`, SQL Editor

```json
{
  "snippets": [
    {
      "trigger": "seltop",
      "name": "SELECT TOP N",
      "template": "SELECT * FROM ${1:table} FETCH FIRST ${2:100} ROWS ONLY",
      "description": "Select top N rows from table"
    },
    {
      "trigger": "cte",
      "name": "Common Table Expression",
      "template": "WITH ${1:cte_name} AS (\n\tSELECT ${2:*}\n\tFROM ${3:table}\n)\nSELECT * FROM ${1:cte_name}"
    }
  ]
}
```

**How it links**: When user types a trigger (e.g., "seltop" + Tab), the snippet expands to the full template.

---

### File Naming Convention

```
<provider>_<version>_<type>.json
```

| Component | Values | Example |
|-----------|--------|---------|
| provider | `db2`, `postgresql`, `oracle`, `sqlserver` | `db2` |
| version | `12.1`, `16.0`, `19c`, `2022` | `12.1` |
| type | `sql_statements`, `system_metadata`, `intellisense`, `keywords`, `<lang>_texts` | `sql_statements` |

**Examples**:
- `db2_12.1_sql_statements.json`
- `postgresql_16.0_sql_statements.json`
- `oracle_19c_en-US_texts.json`

---

### Adding a New Database Provider

To add PostgreSQL support, create these files:

1. `postgresql_16.0_sql_statements.json` - All SQL queries
2. `postgresql_16.0_system_metadata.json` - Catalog reference
3. `postgresql_16.0_intellisense.json` - IntelliSense data
4. `postgresql_16.0_keywords.json` - Syntax highlighting
5. `postgresql_16.0_en-US_texts.json` - Localized text
6. Update `supported_providers.json` with new provider entry

**No C# code changes required** - the application automatically picks up new providers from configuration.

---

### User Data Files (Separate from ConfigFiles/)

All user-specific files live under the **user data folder** (default: `Documents\DbExplorer`; configurable in **View → Settings**).

| File / Folder | Purpose |
|---------------|---------|
| `connections.json` | Saved connection profiles |
| `preferences.json` | User preferences (theme, fonts, language) |
| `query-history.json` | Recent query history |
| `connection_profiles.json` | Connection profile cache |
| `connection_statistics.json` | Connection timing stats |
| `missing-fk-search-history.json` | Missing FK search history |
| `missing-fk-ignore-history.json` | Missing FK ignore history |
| `Themes\` | User custom themes |
| `Notifications\` | Notification payloads (tray) |
| `metadata\` | Metadata cache (DB2, etc.) |

Logging configuration (`nlog.config`) and application settings (`appsettings.json`) remain in the application directory.

## User Data Folder Structure

```
C:\Users\<user>\Documents\DbExplorer\
├── connections.json              (saved profiles)
├── preferences.json              (user settings)
├── query-history.json            (query history)
├── connection_profiles.json      (profile cache)
├── connection_statistics.json    (connection timing)
├── missing-fk-search-history.json
├── missing-fk-ignore-history.json
├── Themes\                       (user custom themes)
├── Notifications\                (tray notifications)
├── metadata\                     (metadata cache)
└── MissingFK\
    ├── running_job.json          (PID tracking)
    ├── IgnorePatterns\           (ignore pattern files)
    │   └── *.json
    └── Projects\                 (job outputs)
        └── 20260129_143052_SCHEMA_TABLE1_TABLE2\
            ├── missing_fk_input.json
            ├── missing_fk_results.json
            └── job_*.log
```

## Key Interfaces

### IConnectionManager

```csharp
public interface IConnectionManager
{
    // Connection
    Task<bool> ConnectAsync();
    Task DisconnectAsync();
    bool IsConnected { get; }
    
    // Query Execution
    Task<DataTable> ExecuteQueryAsync(string sql, params object[] parameters);
    Task<int> ExecuteNonQueryAsync(string sql, params object[] parameters);
    Task<object?> ExecuteScalarAsync(string sql, params object[] parameters);
    
    // Connection Info
    IConnectionInfo ConnectionInfo { get; }
}
```

### IConnectionInfo

```csharp
public interface IConnectionInfo
{
    string? Server { get; }
    int Port { get; }
    string? Database { get; }
    string? Username { get; }
    string? ProviderType { get; }
    string ProfileName { get; }
}
```

## Provider Support Matrix

| Feature | DB2 12.1 | PostgreSQL | Oracle | SQL Server |
|---------|----------|------------|--------|------------|
| Connection | ✅ | 🔲 Planned | 🔲 Planned | 🔲 Planned |
| Object Browser | ✅ | 🔲 | 🔲 | 🔲 |
| Query Execution | ✅ | 🔲 | 🔲 | 🔲 |
| DDL Generation | ✅ | 🔲 | 🔲 | 🔲 |
| IntelliSense | ✅ | 🔲 | 🔲 | 🔲 |
| Export (CSV/JSON) | ✅ | 🔲 | 🔲 | 🔲 |
| Mermaid ERD | ✅ | 🔲 | 🔲 | 🔲 |
| Missing FK Discovery | ✅ | 🔲 | 🔲 | 🔲 |

## Adding a New Database Provider

To add support for a new database (e.g., PostgreSQL):

1. **Create Connection Manager**: `Data/Providers/PostgreSQL/PostgreSQLConnectionManager.cs`
2. **Create SQL Statements**: `ConfigFiles/postgresql_16.0_sql_statements.json`
3. **Create System Metadata**: `ConfigFiles/postgresql_16.0_system_metadata.json`
4. **Create Syntax Highlighting**: `Resources/SyntaxHighlighting/PostgreSQLSQL.xshd`
5. **Update Factory**: Add case in `ConnectionManagerFactory.cs`
6. **Update Supported Providers**: Add to `supported_providers.json`

**No changes needed to**: UI code, dialogs, services, or other components.

## Technology Stack

| Component | Technology |
|-----------|------------|
| Framework | .NET 10 (net10.0-windows) |
| UI Framework | WPF |
| Theme | ModernWpfUI |
| SQL Editor | AvalonEdit |
| SQL Formatter | PoorMansTSqlFormatter |
| DB2 Driver | IBM.Data.Db2 (9.0.0.400) |
| Logging | NLog |
| Serialization | System.Text.Json |

## Summary

The DbExplorer architecture is designed for:

1. **Extensibility**: Add new database providers via configuration
2. **Maintainability**: Single source of truth for SQL and UI text
3. **Testability**: Interface-based design enables mocking
4. **User Experience**: Professional UI with dark/light themes
5. **Automation**: Full CLI support for scripting
