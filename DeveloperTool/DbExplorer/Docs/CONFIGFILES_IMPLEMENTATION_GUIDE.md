# ConfigFiles Implementation Guide

**Purpose:** Complete guide for implementing the ConfigFiles-based metadata system  
**Date:** November 20, 2025  
**Location:** All configuration files in `./ConfigFiles/` directory (part of project)

---

## 🎯 OVERVIEW

All metadata files are now **part of the project** in the `./ConfigFiles/` directory. This means:
- ✅ Version controlled (Git)
- ✅ Deployed with application
- ✅ No user AppData dependencies
- ✅ Manual curation by developers
- ✅ Reviewed and tested before deployment

---

## 📁 FILE NAMING CONVENTION

### Pattern Summary

| File Type | Pattern | Example |
|-----------|---------|---------|
| Providers Master List | `supported_providers.json` | `supported_providers.json` |
| System Metadata | `<provider>_<version>_system_metadata.json` | `db2_12.1_system_metadata.json` |
| SQL Statements | `<provider>_<version>_sql_statements.json` | `db2_12.1_sql_statements.json` |
| Texts/Translations | `<provider>_<version>_<language>_texts.json` | `db2_12.1_en-US_texts.json` |

### Naming Rules

1. **Provider Code**
   - UPPERCASE
   - No spaces
   - Examples: `DB2`, `POSTGRESQL`, `SQLSERVER`, `ORACLE`, `MYSQL`

2. **Version**
   - Dotted notation
   - Major.Minor format
   - Examples: `12.1`, `11.5`, `16.0`, `2022` (for SQL Server year-based)

3. **Language Code**
   - Standard locale format (ISO 639-1 + ISO 3166-1)
   - Examples: `en-US`, `fr-FR`, `no-NO`, `de-DE`, `ja-JP`, `zh-CN`

4. **File Naming**
   - All lowercase for file type descriptors (`system_metadata`, `sql_statements`, `texts`)
   - Underscores for readability
   - `.json` extension

---

## 📋 FILE TYPE 1: supported_providers.json

### Purpose
Master list of all supported database providers. The application loads this file first to determine which providers are available.

### Location
```
./ConfigFiles/supported_providers.json
```

### Structure
```json
{
  "version": "1.0",
  "last_updated": "2025-11-20",
  "providers": [
    {
      "provider_code": "DB2",
      "display_name": "IBM DB2 Database",
      "icon": "🗄️",
      "vendor": "IBM",
      "description": "IBM DB2 for Linux, UNIX, and Windows",
      "supported_versions": ["12.1", "11.5", "11.1", "10.5"],
      "default_port": 50000,
      "connection_string_template": "Server={host}:{port};Database={database};UID={username};PWD={password};",
      "requires_schema": true,
      "system_catalog_schema": "SYSCAT"
    },
    {
      "provider_code": "POSTGRESQL",
      "display_name": "PostgreSQL",
      "icon": "🐘",
      "vendor": "PostgreSQL Global Development Group",
      "description": "PostgreSQL: The World's Most Advanced Open Source Database",
      "supported_versions": ["16.0", "15.0", "14.0", "13.0"],
      "default_port": 5432,
      "connection_string_template": "Host={host};Port={port};Database={database};Username={username};Password={password};",
      "requires_schema": true,
      "system_catalog_schema": "information_schema"
    },
    {
      "provider_code": "SQLSERVER",
      "display_name": "Microsoft SQL Server",
      "icon": "💾",
      "vendor": "Microsoft Corporation",
      "description": "Microsoft SQL Server",
      "supported_versions": ["2022", "2019", "2017", "2016"],
      "default_port": 1433,
      "connection_string_template": "Server={host},{port};Database={database};User Id={username};Password={password};",
      "requires_schema": true,
      "system_catalog_schema": "sys"
    }
  ]
}
```

### Usage in Code
```csharp
// MetadataHandler loads this first
var supportedProviders = LoadSupportedProviders();

foreach (var provider in supportedProviders)
{
    // For each provider, attempt to load version-specific files
    foreach (var version in provider.SupportedVersions)
    {
        // Look for files matching pattern: {provider}_{version}_*
        LoadProviderVersionFiles(provider.ProviderCode, version);
    }
}
```

---

## 📋 FILE TYPE 2: System Metadata

### Purpose
Documents all system catalog tables, their columns, and relationships. This is the foundation for understanding how to query the provider's metadata.

### File Pattern
```
<provider>_<version>_system_metadata.json
```

### Examples
- `db2_12.1_system_metadata.json`
- `db2_11.5_system_metadata.json`
- `postgresql_16.0_system_metadata.json`
- `sqlserver_2022_system_metadata.json`

### Structure
```json
{
  "provider": "DB2",
  "version": "12.1",
  "collected_at": "2025-11-20T10:00:00Z",
  "description_text_key": "system_metadata.db2_12.1.description",
  
  "system_tables": [
    {
      "schema": "SYSCAT",
      "table_name": "TABLES",
      "description_text_key": "system_metadata.tables.syscat_tables",
      "key_columns": ["TABSCHEMA", "TABNAME"],
      "important_columns": [
        "TYPE",
        "OWNER",
        "CREATED",
        "ALTER_TIME",
        "DATACAPTURE",
        "TBSPACE",
        "CARD",
        "NPAGES",
        "REMARKS"
      ],
      "column_data_types": {
        "TABSCHEMA": "VARCHAR(128)",
        "TABNAME": "VARCHAR(128)",
        "TYPE": "CHAR(1)",
        "OWNER": "VARCHAR(128)",
        "CREATED": "TIMESTAMP",
        "ALTER_TIME": "TIMESTAMP",
        "DATACAPTURE": "CHAR(1)",
        "TBSPACE": "VARCHAR(128)",
        "CARD": "BIGINT",
        "NPAGES": "INTEGER",
        "REMARKS": "VARCHAR(254)"
      },
      "notes": "TYPE: T=Table, V=View, S=Materialized View"
    },
    {
      "schema": "SYSCAT",
      "table_name": "COLUMNS",
      "description_text_key": "system_metadata.tables.syscat_columns",
      "key_columns": ["TABSCHEMA", "TABNAME", "COLNAME"],
      "important_columns": [
        "COLNO",
        "TYPENAME",
        "LENGTH",
        "SCALE",
        "NULLS",
        "DEFAULT",
        "REMARKS"
      ],
      "column_data_types": {
        "TABSCHEMA": "VARCHAR(128)",
        "TABNAME": "VARCHAR(128)",
        "COLNAME": "VARCHAR(128)",
        "COLNO": "SMALLINT",
        "TYPENAME": "VARCHAR(18)",
        "LENGTH": "INTEGER",
        "SCALE": "SMALLINT",
        "NULLS": "CHAR(1)",
        "DEFAULT": "VARCHAR(254)",
        "REMARKS": "VARCHAR(254)"
      },
      "notes": "NULLS: Y=Nullable, N=Not Null. COLNO is 0-based."
    },
    {
      "schema": "SYSCAT",
      "table_name": "INDEXES",
      "description_text_key": "system_metadata.tables.syscat_indexes",
      "key_columns": ["INDSCHEMA", "INDNAME"],
      "important_columns": [
        "TABSCHEMA",
        "TABNAME",
        "UNIQUERULE",
        "INDEXTYPE",
        "COLNAMES",
        "CREATE_TIME",
        "REMARKS"
      ]
    },
    {
      "schema": "SYSCAT",
      "table_name": "VIEWS",
      "description_text_key": "system_metadata.tables.syscat_views",
      "key_columns": ["VIEWSCHEMA", "VIEWNAME"],
      "important_columns": [
        "DEFINER",
        "TEXT"
      ],
      "notes": "CRITICAL: Must join with SYSCAT.TABLES to get REMARKS and ALTER_TIME"
    },
    {
      "schema": "SYSCAT",
      "table_name": "PACKAGES",
      "description_text_key": "system_metadata.tables.syscat_packages",
      "key_columns": ["PKGSCHEMA", "PKGNAME"],
      "important_columns": [
        "BOUNDBY",
        "ISOLATION",
        "LASTUSED",
        "VALID"
      ]
    }
  ],
  
  "relationships": [
    {
      "relationship_id": "tables_to_columns",
      "from_table": "SYSCAT.TABLES",
      "to_table": "SYSCAT.COLUMNS",
      "join_condition": "TABLES.TABSCHEMA = COLUMNS.TABSCHEMA AND TABLES.TABNAME = COLUMNS.TABNAME",
      "cardinality": "1:N",
      "description_text_key": "system_metadata.relationships.tables_to_columns"
    },
    {
      "relationship_id": "tables_to_indexes",
      "from_table": "SYSCAT.TABLES",
      "to_table": "SYSCAT.INDEXES",
      "join_condition": "TABLES.TABSCHEMA = INDEXES.TABSCHEMA AND TABLES.TABNAME = INDEXES.TABNAME",
      "cardinality": "1:N",
      "description_text_key": "system_metadata.relationships.tables_to_indexes"
    },
    {
      "relationship_id": "tables_to_views",
      "from_table": "SYSCAT.TABLES",
      "to_table": "SYSCAT.VIEWS",
      "join_condition": "TABLES.TABSCHEMA = VIEWS.VIEWSCHEMA AND TABLES.TABNAME = VIEWS.VIEWNAME",
      "cardinality": "1:1",
      "description_text_key": "system_metadata.relationships.tables_to_views",
      "notes": "CRITICAL: Always join TABLES and VIEWS for complete view information"
    },
    {
      "relationship_id": "packages_to_statements",
      "from_table": "SYSCAT.PACKAGES",
      "to_table": "SYSCAT.STATEMENTS",
      "join_condition": "PACKAGES.PKGSCHEMA = STATEMENTS.PKGSCHEMA AND PACKAGES.PKGNAME = STATEMENTS.PKGNAME",
      "cardinality": "1:N",
      "description_text_key": "system_metadata.relationships.packages_to_statements"
    },
    {
      "relationship_id": "tables_to_references_fk",
      "from_table": "SYSCAT.TABLES",
      "to_table": "SYSCAT.REFERENCES",
      "join_condition": "TABLES.TABSCHEMA = REFERENCES.TABSCHEMA AND TABLES.TABNAME = REFERENCES.TABNAME",
      "cardinality": "1:N",
      "description_text_key": "system_metadata.relationships.tables_to_references_fk",
      "notes": "Foreign keys FROM this table (referencing other tables)"
    },
    {
      "relationship_id": "tables_to_references_pk",
      "from_table": "SYSCAT.TABLES",
      "to_table": "SYSCAT.REFERENCES",
      "join_condition": "TABLES.TABSCHEMA = REFERENCES.REFTABSCHEMA AND TABLES.TABNAME = REFERENCES.REFTABNAME",
      "cardinality": "1:N",
      "description_text_key": "system_metadata.relationships.tables_to_references_pk",
      "notes": "Foreign keys TO this table (referenced by other tables)"
    }
  ],
  
  "query_patterns": {
    "how_to_find_foreign_keys": {
      "description_text_key": "system_metadata.patterns.find_foreign_keys",
      "example_sql": "SELECT * FROM SYSCAT.REFERENCES WHERE TABSCHEMA = ? AND TABNAME = ?",
      "notes": "Use FK_COLNAMES and PK_COLNAMES for column lists"
    },
    "how_to_check_if_fk_is_indexed": {
      "description_text_key": "system_metadata.patterns.check_fk_indexed",
      "example_sql": "SELECT R.*, I.INDNAME FROM SYSCAT.REFERENCES R LEFT JOIN SYSCAT.INDEXES I ON R.TABSCHEMA = I.TABSCHEMA AND R.TABNAME = I.TABNAME WHERE R.TABSCHEMA = ?",
      "notes": "Check if foreign key columns have matching index for performance"
    },
    "how_to_determine_packages_using_table": {
      "description_text_key": "system_metadata.patterns.packages_using_table",
      "example_sql": "SELECT DISTINCT P.* FROM SYSCAT.PACKAGES P JOIN SYSCAT.PACKAGEDEP D ON P.PKGSCHEMA = D.PKGSCHEMA AND P.PKGNAME = D.PKGNAME WHERE D.BSCHEMA = ? AND D.BNAME = ? AND D.BTYPE = 'T'",
      "notes": "Find which packages depend on a specific table"
    }
  }
}
```

### Usage in Code
```csharp
// MetadataHandler loads system metadata for each provider/version
var systemMetadata = LoadSystemMetadata("DB2", "12.1");

// Access system tables
foreach (var table in systemMetadata.SystemTables)
{
    Console.WriteLine($"{table.Schema}.{table.TableName}: {table.KeyColumns}");
}

// Access relationships
foreach (var rel in systemMetadata.Relationships)
{
    Console.WriteLine($"{rel.FromTable} → {rel.ToTable} [{rel.Cardinality}]");
}
```

---

## 📋 FILE TYPE 3: SQL Statements

### Purpose
All SQL queries for a specific provider and version. These are the actual queries used by the application to retrieve metadata and data.

### File Pattern
```
<provider>_<version>_sql_statements.json
```

### Examples
- `db2_12.1_sql_statements.json`
- `postgresql_16.0_sql_statements.json`
- `sqlserver_2022_sql_statements.json`

### Structure
```json
{
  "provider": "DB2",
  "version": "12.1",
  "description_text_key": "sql_statements.db2_12.1.description",
  
  "statements": {
      "AllTablesStatement": {
        "sql": "SELECT TRIM(TABSCHEMA) AS TABSCHEMA, TRIM(TABNAME) AS TABNAME, TRIM(OWNER) AS OWNER, CREATED, CARD FROM SYSCAT.TABLES WHERE TYPE = 'T' ORDER BY TABSCHEMA, TABNAME",
        "description": "Retrieve all user tables in the database. Returns schema, table name, owner, creation date, and row count. TRIM() applied to all CHAR columns to remove padding.",
        "parameters": [],
        "returns": "List of all user tables with row counts",
        "source": "Manual",
        "notes": ["TRIM() applied to all CHAR columns to remove padding"]
      },
    
    "GetSchemasStatement": {
      "sql": "SELECT DISTINCT TRIM(TABSCHEMA) AS SCHEMANAME FROM SYSCAT.TABLES WHERE TYPE IN ('T', 'V') ORDER BY SCHEMANAME",
      "description": "Get all schemas containing tables or views. Returns distinct schema names sorted alphabetically.",
      "parameters": [],
      "returns": "List of all schemas containing tables or views"
    },
    
    "GetTablesForSchema": {
      "sql": "SELECT TRIM(TABNAME) AS TABNAME, TRIM(OWNER) AS OWNER, CREATED, CARD AS ROW_COUNT, TRIM(REMARKS) AS REMARKS FROM SYSCAT.TABLES WHERE TABSCHEMA = ? AND TYPE = 'T' ORDER BY TABNAME",
      "description": "Get all tables in a specific schema. Returns table name, owner, creation date, row count, and remarks. Filters by TYPE='T' for tables only.",
      "parameters": ["TABSCHEMA"],
      "returns": "List of tables in specified schema",
      "source": "Manual"
    },
    
    "GetViewsForSchema": {
      "sql": "SELECT TRIM(V.VIEWNAME) AS VIEWNAME, TRIM(V.DEFINER) AS DEFINER, TRIM(T.REMARKS) AS REMARKS, T.ALTER_TIME FROM SYSCAT.TABLES T JOIN SYSCAT.VIEWS V ON T.TABSCHEMA = V.VIEWSCHEMA AND T.TABNAME = V.VIEWNAME WHERE T.TYPE = 'V' AND T.TABSCHEMA = ? ORDER BY V.VIEWNAME",
      "description": "Get all views in a specific schema. CRITICAL: Start from SYSCAT.TABLES (not SYSCAT.VIEWS) and join to VIEWS. REMARKS comes from TABLES, not VIEWS. Filter by TYPE='V'.",
      "parameters": ["TABSCHEMA"],
      "returns": "List of views in specified schema",
      "source": "Db2CreateDBQA_NonRelated.sql:544-558",
      "notes": [
        "CRITICAL: Start from SYSCAT.TABLES (not SYSCAT.VIEWS)",
        "Filter by T.TYPE = 'V'",
        "REMARKS comes from SYSCAT.TABLES, not SYSCAT.VIEWS",
        "Use DEFINER (not OWNER) from TABLES for consistency"
      ]
    },
    
    "GetTableColumns": {
      "sql": "SELECT TRIM(COLNAME) AS COLNAME, COLNO, TRIM(TYPENAME) AS TYPENAME, LENGTH, SCALE, CASE WHEN NULLS = 'Y' THEN 'Yes' ELSE 'No' END AS NULLABLE, COALESCE(TRIM(DEFAULT), '-') AS DEFAULT_VALUE, COALESCE(TRIM(REMARKS), '') AS REMARKS FROM SYSCAT.COLUMNS WHERE TABSCHEMA = ? AND TABNAME = ? ORDER BY COLNO",
      "description": "Get all columns for a specific table. Returns column name, position (COLNO), data type, length, scale, nullable flag, default value, and remarks. Ordered by column position.",
      "parameters": ["TABSCHEMA", "TABNAME"],
      "returns": "List of columns for specified table"
    },
    
    "GetPackagesForSchema": {
      "sql": "SELECT TRIM(PKGNAME) AS PKGNAME, TRIM(BOUNDBY) AS BOUNDBY, TRIM(ISOLATION) AS ISOLATION, LASTUSED, VALID FROM SYSCAT.PACKAGES WHERE PKGSCHEMA = ? ORDER BY PKGNAME",
      "description": "Get all DB2 packages in a specific schema. Returns package name, bound by user, isolation level, last used date, and validity status.",
      "parameters": ["PKGSCHEMA"],
      "returns": "List of packages in specified schema"
    },
    
    "GetPackageStatements": {
      "sql": "SELECT TRIM(X.STMTNO) AS STMTNO, TRIM(X.SECTNO) AS SECTNO, TRIM(X.SEQNO) AS SEQNO, TRIM(X.TEXT) AS STATEMENT_TEXT FROM SYSCAT.STATEMENTS X JOIN SYSCAT.PACKAGES Z ON X.PKGSCHEMA = Z.PKGSCHEMA AND X.PKGNAME = Z.PKGNAME WHERE TRIM(X.PKGSCHEMA) = ? AND TRIM(X.PKGNAME) = ? ORDER BY X.STMTNO, X.SECTNO, X.SEQNO",
      "description": "Get all SQL statements in a DB2 package. CRITICAL: Must join SYSCAT.STATEMENTS to SYSCAT.PACKAGES on both PKGSCHEMA and PKGNAME. Returns statement number, section, sequence, and text. Order by STMTNO, SECTNO, SEQNO for proper sequence.",
      "parameters": ["PKGSCHEMA", "PKGNAME"],
      "returns": "List of SQL statements in a package",
      "source": "Db2CreateDBQA_NonRelated.sql:680-692",
      "notes": [
        "CRITICAL: Join SYSCAT.STATEMENTS to SYSCAT.PACKAGES",
        "Match on both PKGSCHEMA and PKGNAME",
        "Order by STMTNO, SECTNO, SEQNO for proper statement sequence"
      ]
    },
    
    "GetTopNRows": {
      "sql": "SELECT * FROM {schema}.{table} FETCH FIRST {n} ROWS ONLY",
      "description": "Get top N rows from a table using DB2 FETCH FIRST syntax. Use parameterized replacement for schema and table names (not query parameters).",
      "parameters": ["schema", "table", "n"],
      "returns": "First N rows from specified table",
      "notes": ["Use parameterized replacement for schema and table names"]
    },
    
    "CountRows": {
      "sql": "SELECT COUNT(*) AS ROW_COUNT FROM {schema}.{table}",
      "description": "Count total rows in a table. Use parameterized replacement for schema and table names.",
      "parameters": ["schema", "table"],
      "returns": "Row count for specified table"
    }
  }
}
```

### Usage in Code
```csharp
// MetadataHandler.GetQuery(provider, version, statementKey)
var sql = metadataHandler.GetQuery("DB2", "12.1", "GetViewsForSchema");
var parameters = new[] { "TV" };
var results = ExecuteQuery(sql, parameters);
```

---

## 📋 FILE TYPE 4: Texts/Translations

### Purpose
All translatable text for a specific provider, version, and language. This enables multi-language support with provider-specific and version-specific terminology.

### File Pattern
```
<provider>_<version>_<language>_texts.json
```

### Examples
- `db2_12.1_en-US_texts.json`
- `db2_12.1_fr-FR_texts.json`
- `db2_12.1_no-NO_texts.json`
- `postgresql_16.0_en-US_texts.json`
- `sqlserver_2022_de-DE_texts.json`

### Structure
```json
{
  "provider": "DB2",
  "version": "12.1",
  "language": "en-US",
  "language_name": "English (United States)",
  "translator": "Development Team",
  "last_updated": "2025-11-20",
  "completion_percentage": 100,
  
  "texts": {
    "MainFormTitle": "DB2 Database Editor",
    
    "ui.menu.file": "File",
    "ui.menu.file.new_connection": "New Connection...",
    "ui.menu.file.open_script": "Open SQL Script...",
    "ui.menu.file.save_script": "Save Script",
    "ui.menu.file.exit": "Exit",
    
    "ui.menu.edit": "Edit",
    "ui.menu.edit.undo": "Undo",
    "ui.menu.edit.redo": "Redo",
    "ui.menu.edit.find": "Find...",
    "ui.menu.edit.replace": "Replace...",
    
    "ui.menu.view": "View",
    "ui.menu.view.object_browser": "Object Browser",
    "ui.menu.view.dark_mode": "Toggle Dark Mode",
    
    "ui.toolbar.execute": "Execute",
    "ui.toolbar.execute_tooltip": "Execute query (F5)",
    "ui.toolbar.format": "Format SQL",
    "ui.toolbar.export": "Export",
    
    "ui.object_browser.categories.tables": "Tables",
    "ui.object_browser.categories.views": "Views",
    "ui.object_browser.categories.procedures": "Stored Procedures",
    "ui.object_browser.categories.functions": "Functions",
    "ui.object_browser.categories.indexes": "Indexes",
    "ui.object_browser.categories.triggers": "Triggers",
    "ui.object_browser.categories.sequences": "Sequences",
    "ui.object_browser.categories.packages": "Packages",
    "ui.object_browser.categories.types": "User-Defined Types",
    
    "ui.object_browser.tooltips.tables": "Database tables containing data",
    "ui.object_browser.tooltips.packages": "DB2 packages containing compiled SQL statements",
    
    "ui.context_menu.browse_data": "Browse Data (Top 1000)",
    "ui.context_menu.count_rows": "Count Rows",
    "ui.context_menu.view_properties": "Properties...",
    "ui.context_menu.view_source": "View Source Code",
    
    "sql.descriptions.all_tables": "Retrieve all user tables in the database",
    "sql.descriptions.get_schemas": "Get all schemas containing tables or views",
    "sql.descriptions.get_tables_for_schema": "Get all tables in a specific schema",
    "sql.descriptions.get_views_for_schema": "Get all views in a specific schema",
    "sql.descriptions.get_table_columns": "Get all columns for a specific table",
    "sql.descriptions.get_packages_for_schema": "Get all DB2 packages in a schema",
    "sql.descriptions.get_package_statements": "Get all SQL statements in a DB2 package",
    
    "system_metadata.db2_12.1.description": "DB2 v12.1 System Catalog Metadata",
    "system_metadata.tables.syscat_tables": "SYSCAT.TABLES - Catalog information for tables and views",
    "system_metadata.tables.syscat_columns": "SYSCAT.COLUMNS - Column information for all tables",
    "system_metadata.tables.syscat_packages": "SYSCAT.PACKAGES - Information about DB2 packages",
    "system_metadata.relationships.tables_to_columns": "Each table has multiple columns",
    "system_metadata.relationships.packages_to_statements": "Each package contains multiple SQL statements",
    
    "messages.errors.connection_failed": "Failed to connect to {database}.\n\nPlease check your connection settings and try again.",
    "messages.errors.query_syntax_error": "SQL Syntax Error:\n\n{error}",
    "messages.errors.query_execution_failed": "Query execution failed:\n\n{error}",
    "messages.errors.no_active_connection": "No active database connection.\n\nPlease connect to a database first.",
    
    "messages.warnings.delete_without_where": "⚠️ DELETE without WHERE clause detected!\n\nThis will delete ALL rows from the table.\n\nAre you sure you want to continue?",
    "messages.warnings.drop_object": "⚠️ You are about to DROP {type} '{name}'.\n\nThis operation cannot be undone.\n\nAre you sure?",
    
    "messages.success.query_executed": "Query executed successfully.\n\n{rows} rows affected.",
    "messages.success.connection_successful": "Connected to '{database}' successfully.",
    
    "common.buttons.ok": "OK",
    "common.buttons.cancel": "Cancel",
    "common.buttons.yes": "Yes",
    "common.buttons.no": "No",
    "common.buttons.apply": "Apply",
    "common.buttons.close": "Close"
  }
}
```

### French Translation Example (`db2_12.1_fr-FR_texts.json`)
```json
{
  "provider": "DB2",
  "version": "12.1",
  "language": "fr-FR",
  "language_name": "Français (France)",
  "translator": "Jean Dupont",
  "last_updated": "2025-11-20",
  "completion_percentage": 95,
  
  "texts": {
    "MainFormTitle": "Éditeur de Base de Données DB2",
    
    "ui.menu.file": "Fichier",
    "ui.menu.file.new_connection": "Nouvelle Connexion...",
    "ui.menu.file.open_script": "Ouvrir un Script SQL...",
    "ui.menu.file.save_script": "Enregistrer le Script",
    "ui.menu.file.exit": "Quitter",
    
    "ui.object_browser.categories.tables": "Tables",
    "ui.object_browser.categories.views": "Vues",
    "ui.object_browser.categories.packages": "Paquets",
    
    "sql.descriptions.get_packages_for_schema": "Obtenir tous les paquets DB2 dans un schéma",
    
    "messages.errors.connection_failed": "Échec de la connexion à {database}.\n\nVeuillez vérifier vos paramètres de connexion et réessayer."
  }
}
```

---

## 🔧 METADATA HANDLER IMPLEMENTATION

### MetadataHandler Class
```csharp
using System;
using System.Collections.Generic;
using System.IO;
using System.Linq;
using System.Text.Json;
using NLog;

namespace DbExplorer.Services;

/// <summary>
/// Centralized handler for all ConfigFiles-based metadata
/// </summary>
public class MetadataHandler
{
    private static readonly Logger Logger = LogManager.GetCurrentClassLogger();
    private readonly string _configFilesPath;
    
    private List<Provider> _providers = new();
    private Dictionary<string, SystemMetadata> _systemMetadataCache = new();
    private Dictionary<string, Dictionary<string, SqlStatement>> _sqlStatementsCache = new();
    private Dictionary<string, Dictionary<string, string>> _textsCache = new();
    
    private string _userLanguagePreference = "en-US"; // From user preferences
    
    public MetadataHandler()
    {
        _configFilesPath = Path.Combine(AppDomain.CurrentDomain.BaseDirectory, "ConfigFiles");
        Logger.Info("MetadataHandler initialized. ConfigFiles path: {Path}", _configFilesPath);
        
        LoadAllMetadata();
    }
    
    /// <summary>
    /// Load all metadata from ConfigFiles
    /// </summary>
    private void LoadAllMetadata()
    {
        Logger.Info("Loading all metadata from ConfigFiles");
        
        try
        {
            // Step 1: Load supported providers
            _providers = LoadSupportedProviders();
            Logger.Info("Loaded {Count} providers", _providers.Count);
            
            // Step 2: For each provider and version, load metadata
            foreach (var provider in _providers)
            {
                foreach (var version in provider.SupportedVersions)
                {
                    LoadProviderVersionMetadata(provider.ProviderCode, version);
                }
            }
            
            Logger.Info("All metadata loaded successfully");
        }
        catch (Exception ex)
        {
            Logger.Error(ex, "Failed to load metadata");
            throw;
        }
    }
    
    /// <summary>
    /// Load supported_providers.json
    /// </summary>
    private List<Provider> LoadSupportedProviders()
    {
        var filePath = Path.Combine(_configFilesPath, "supported_providers.json");
        
        if (!File.Exists(filePath))
        {
            Logger.Error("supported_providers.json not found at {Path}", filePath);
            throw new FileNotFoundException("supported_providers.json not found", filePath);
        }
        
        var json = File.ReadAllText(filePath);
        var data = JsonSerializer.Deserialize<SupportedProvidersFile>(json);
        
        return data?.Providers ?? new List<Provider>();
    }
    
    /// <summary>
    /// Load all metadata files for a specific provider and version
    /// </summary>
    private void LoadProviderVersionMetadata(string provider, string version)
    {
        Logger.Debug("Loading metadata for {Provider} {Version}", provider, version);
        
        var key = $"{provider}_{version}";
        
        // Load system metadata
        var systemMetadataFile = $"{provider.ToLower()}_{version}_system_metadata.json";
        var systemMetadataPath = Path.Combine(_configFilesPath, systemMetadataFile);
        if (File.Exists(systemMetadataPath))
        {
            var json = File.ReadAllText(systemMetadataPath);
            var metadata = JsonSerializer.Deserialize<SystemMetadata>(json);
            if (metadata != null)
            {
                _systemMetadataCache[key] = metadata;
                Logger.Debug("Loaded system metadata: {File}", systemMetadataFile);
            }
        }
        else
        {
            Logger.Warn("System metadata file not found: {File}", systemMetadataFile);
        }
        
        // Load SQL statements
        var sqlStatementsFile = $"{provider.ToLower()}_{version}_sql_statements.json";
        var sqlStatementsPath = Path.Combine(_configFilesPath, sqlStatementsFile);
        if (File.Exists(sqlStatementsPath))
        {
            var json = File.ReadAllText(sqlStatementsPath);
            var data = JsonSerializer.Deserialize<SqlStatementsFile>(json);
            if (data != null)
            {
                _sqlStatementsCache[key] = data.Statements;
                Logger.Debug("Loaded {Count} SQL statements: {File}", data.Statements.Count, sqlStatementsFile);
            }
        }
        else
        {
            Logger.Warn("SQL statements file not found: {File}", sqlStatementsFile);
        }
        
        // Load texts for user's preferred language
        LoadTextsForLanguage(provider, version, _userLanguagePreference);
        
        // Also load English as fallback
        if (_userLanguagePreference != "en-US")
        {
            LoadTextsForLanguage(provider, version, "en-US");
        }
    }
    
    /// <summary>
    /// Load texts for a specific language
    /// </summary>
    private void LoadTextsForLanguage(string provider, string version, string languageCode)
    {
        var textsFile = $"{provider.ToLower()}_{version}_{languageCode}_texts.json";
        var textsPath = Path.Combine(_configFilesPath, textsFile);
        
        if (File.Exists(textsPath))
        {
            var json = File.ReadAllText(textsPath);
            var data = JsonSerializer.Deserialize<TextsFile>(json);
            if (data != null)
            {
                var key = $"{provider}_{version}_{languageCode}";
                _textsCache[key] = data.Texts;
                Logger.Debug("Loaded {Count} texts: {File}", data.Texts.Count, textsFile);
            }
        }
        else
        {
            Logger.Warn("Texts file not found: {File}", textsFile);
        }
    }
    
    /// <summary>
    /// Get SQL query by statement key
    /// </summary>
    public string GetQuery(string provider, string version, string statementKey)
    {
        var key = $"{provider}_{version}";
        
        if (_sqlStatementsCache.TryGetValue(key, out var statements))
        {
            if (statements.TryGetValue(statementKey, out var statement))
            {
                Logger.Debug("Retrieved SQL: {Provider} {Version} {Key}", provider, version, statementKey);
                return statement.Sql;
            }
        }
        
        Logger.Error("SQL statement not found: {Provider} {Version} {Key}", provider, version, statementKey);
        throw new KeyNotFoundException($"SQL statement '{statementKey}' not found for {provider} {version}");
    }
    
    /// <summary>
    /// Get translated text by text key
    /// Attempts user's preferred language first, falls back to English
    /// </summary>
    public string GetText(string provider, string version, string textKey)
    {
        // Try user's preferred language
        var preferredKey = $"{provider}_{version}_{_userLanguagePreference}";
        if (_textsCache.TryGetValue(preferredKey, out var preferredTexts))
        {
            if (preferredTexts.TryGetValue(textKey, out var preferredText))
            {
                Logger.Debug("Retrieved text [{Language}]: {Key} = {Text}", 
                    _userLanguagePreference, textKey, preferredText.Substring(0, Math.Min(50, preferredText.Length)));
                return preferredText;
            }
        }
        
        // Fallback to English
        var fallbackKey = $"{provider}_{version}_en-US";
        if (_textsCache.TryGetValue(fallbackKey, out var fallbackTexts))
        {
            if (fallbackTexts.TryGetValue(textKey, out var fallbackText))
            {
                Logger.Warn("Text not found in {Language}, using English fallback: {Key}", 
                    _userLanguagePreference, textKey);
                return fallbackText;
            }
        }
        
        // Last resort: return key itself
        Logger.Error("Text not found in any language: {Provider} {Version} {Key}", provider, version, textKey);
        return $"[{textKey}]";
    }
    
    /// <summary>
    /// Get translated text with parameter replacement
    /// </summary>
    public string GetText(string provider, string version, string textKey, object parameters)
    {
        var text = GetText(provider, version, textKey);
        return FormatText(text, parameters);
    }
    
    /// <summary>
    /// Format text by replacing placeholders with values
    /// </summary>
    private string FormatText(string template, object parameters)
    {
        if (parameters == null) return template;
        
        var properties = parameters.GetType().GetProperties();
        foreach (var prop in properties)
        {
            var placeholder = $"{{{prop.Name}}}";
            var value = prop.GetValue(parameters)?.ToString() ?? string.Empty;
            template = template.Replace(placeholder, value);
        }
        
        return template;
    }
    
    /// <summary>
    /// Get system metadata for a provider/version
    /// </summary>
    public SystemMetadata? GetSystemMetadata(string provider, string version)
    {
        var key = $"{provider}_{version}";
        return _systemMetadataCache.GetValueOrDefault(key);
    }
    
    /// <summary>
    /// Get all available languages for a provider/version
    /// </summary>
    public List<string> GetAvailableLanguages(string provider, string version)
    {
        var prefix = $"{provider}_{version}_";
        return _textsCache.Keys
            .Where(k => k.StartsWith(prefix))
            .Select(k => k.Substring(prefix.Length))
            .ToList();
    }
    
    /// <summary>
    /// Get all distinct language codes across all providers and versions
    /// </summary>
    public List<string> GetAllDistinctLanguages()
    {
        var languages = new HashSet<string>();
        
        foreach (var key in _textsCache.Keys)
        {
            // Extract language code from key: "DB2_12.1_en-US" -> "en-US"
            var parts = key.Split('_');
            if (parts.Length >= 3)
            {
                var languageCode = string.Join("_", parts.Skip(2)); // Handle cases like "en-US" or "zh-CN"
                languages.Add(languageCode);
            }
        }
        
        return languages.OrderBy(l => l).ToList();
    }
    
    /// <summary>
    /// Change user's language preference and reload texts
    /// </summary>
    public void ChangeLanguage(string languageCode)
    {
        Logger.Info("Changing language from {Old} to {New}", _userLanguagePreference, languageCode);
        _userLanguagePreference = languageCode;
        
        // Reload texts for all providers and versions with new language
        foreach (var provider in _providers)
        {
            foreach (var version in provider.SupportedVersions)
            {
                LoadTextsForLanguage(provider.ProviderCode, version, languageCode);
            }
        }
    }
}

// Data models
public class SupportedProvidersFile
{
    public List<Provider> Providers { get; set; } = new();
}

public class Provider
{
    public string ProviderCode { get; set; } = string.Empty;
    public string DisplayName { get; set; } = string.Empty;
    public string Icon { get; set; } = string.Empty;
    public string Vendor { get; set; } = string.Empty;
    public List<string> SupportedVersions { get; set; } = new();
}

public class SystemMetadata
{
    public string Provider { get; set; } = string.Empty;
    public string Version { get; set; } = string.Empty;
    public List<SystemTable> SystemTables { get; set; } = new();
    public List<TableRelationship> Relationships { get; set; } = new();
}

public class SystemTable
{
    public string Schema { get; set; } = string.Empty;
    public string TableName { get; set; } = string.Empty;
    public List<string> KeyColumns { get; set; } = new();
}

public class TableRelationship
{
    public string FromTable { get; set; } = string.Empty;
    public string ToTable { get; set; } = string.Empty;
    public string JoinCondition { get; set; } = string.Empty;
    public string Cardinality { get; set; } = string.Empty;
}

public class SqlStatementsFile
{
    public string Provider { get; set; } = string.Empty;
    public string Version { get; set; } = string.Empty;
    public Dictionary<string, SqlStatement> Statements { get; set; } = new();
}

public class SqlStatement
{
    public string Sql { get; set; } = string.Empty;
    public string DescriptionTextKey { get; set; } = string.Empty;
    public List<string> Parameters { get; set; } = new();
}

public class TextsFile
{
    public string Provider { get; set; } = string.Empty;
    public string Version { get; set; } = string.Empty;
    public string Language { get; set; } = string.Empty;
    public Dictionary<string, string> Texts { get; set; } = new();
}
```

---

## 🎯 USER PREFERENCES: LANGUAGE SELECTION

### Updated UserPreferences Model
```csharp
public class UserPreferences
{
    // Existing preferences
    public int MaxRowsPerQuery { get; set; } = 1000;
    public string DefaultTheme { get; set; } = "Dark";
    public string FontFamily { get; set; } = "Consolas";
    public int FontSize { get; set; } = 14;
    
    // NEW: Language preference
    public string LanguageCode { get; set; } = "en-US";
    
    // Other preferences...
}
```

### Language Selector in Settings Dialog
```xml
<!-- SettingsDialog.xaml -->
<GroupBox Header="Language">
    <StackPanel>
        <Label Content="Application Language:"/>
        <ComboBox x:Name="LanguageComboBox" 
                  DisplayMemberPath="DisplayName"
                  SelectedValuePath="LanguageCode"/>
        
        <TextBlock Text="⚠️ Restart required for full effect" 
                   Foreground="Orange" 
                   Margin="0,10,0,0"/>
    </StackPanel>
</GroupBox>
```

```csharp
// SettingsDialog.xaml.cs
public partial class SettingsDialog : Window
{
    private readonly MetadataHandler _metadataHandler;
    
    public SettingsDialog(MetadataHandler metadataHandler)
    {
        InitializeComponent();
        _metadataHandler = metadataHandler;
        
        LoadLanguages();
    }
    
    private void LoadLanguages()
    {
        // Get all distinct languages across all providers and versions
        var languages = _metadataHandler.GetAllDistinctLanguages();
        
        var languageOptions = languages.Select(lang => new
        {
            LanguageCode = lang,
            DisplayName = GetLanguageDisplayName(lang)
        }).ToList();
        
        LanguageComboBox.ItemsSource = languageOptions;
        LanguageComboBox.SelectedValue = _preferences.LanguageCode;
    }
    
    private string GetLanguageDisplayName(string languageCode)
    {
        return languageCode switch
        {
            "en-US" => "English (United States)",
            "fr-FR" => "Français (France)",
            "no-NO" => "Norsk (Norge)",
            "de-DE" => "Deutsch (Deutschland)",
            "es-ES" => "Español (España)",
            "it-IT" => "Italiano (Italia)",
            "ja-JP" => "日本語 (日本)",
            "zh-CN" => "中文（简体）",
            _ => languageCode
        };
    }
}
```

---

## ✅ IMPLEMENTATION CHECKLIST

### Phase 1: Setup (Week 1)
- [ ] Create `ConfigFiles/` directory in project root
- [ ] Add `ConfigFiles/` to `.csproj` (CopyToOutputDirectory = Always)
- [ ] Create `supported_providers.json`
- [ ] Create `MetadataHandler` class
- [ ] Implement file loading logic
- [ ] Test with one provider/version

### Phase 2: DB2 12.1 Files (Week 2)
- [ ] Create `db2_12.1_system_metadata.json` (move from AppData)
- [ ] Create `db2_12.1_sql_statements.json` (80+ queries)
- [ ] Create `db2_12.1_en-US_texts.json` (472+ text keys)
- [ ] Test query retrieval
- [ ] Test text retrieval with fallback

### Phase 3: Additional Languages (Week 3)
- [ ] Create `db2_12.1_fr-FR_texts.json`
- [ ] Create `db2_12.1_no-NO_texts.json`
- [ ] Implement language switching in Settings
- [ ] Test language fallback (fr-FR → en-US)
- [ ] Update UserPreferences model

### Phase 4: Additional Versions (Week 4)
- [ ] Create `db2_11.5_system_metadata.json`
- [ ] Create `db2_11.5_sql_statements.json`
- [ ] Create `db2_11.5_en-US_texts.json`
- [ ] Test version-specific queries
- [ ] Document differences between versions

### Phase 5: Integration (Week 5)
- [ ] Update all services to use `MetadataHandler.GetQuery()`
- [ ] Update all UI to use `MetadataHandler.GetText()`
- [ ] Remove hardcoded SQL from services
- [ ] Remove hardcoded text from XAML
- [ ] Test with multiple providers/versions/languages

### Phase 6: Validation (Week 6)
- [ ] Create JSON schema validation
- [ ] Validate all foreign key references
- [ ] Log missing text keys
- [ ] Build verification tool
- [ ] Create deployment package

---

## 🎯 SUCCESS CRITERIA

✅ **All metadata in ConfigFiles/** - No AppData dependencies  
✅ **Version controlled** - All files in Git  
✅ **Zero hardcoded SQL** - All queries from JSON  
✅ **Zero hardcoded text** - All UI text from JSON  
✅ **Language fallback works** - fr-FR → en-US → [key]  
✅ **Multiple providers supported** - DB2, PostgreSQL, SQL Server  
✅ **System metadata documented** - All SYSCAT tables and relationships  
✅ **Build succeeds** - ConfigFiles copied to output  
✅ **Application runs** - Loads metadata successfully  

---

**Status:** 📋 IMPLEMENTATION GUIDE COMPLETE  
**Next Step:** Begin Phase 1 implementation  
**Estimated Effort:** 6 weeks for complete implementation

