# Metadata Service Architecture

## Overview

The DbExplorer application uses a layered metadata architecture designed to support multiple database providers while currently focusing on DB2.

---

## Architecture Layers

```
┌─────────────────────────────────────────────────────────────────┐
│                    Application Layer                            │
│         (ConnectionTabControl, Dialogs, Controls)               │
└─────────────────────────────────────────────────────────────────┘
                              │
                              ▼
┌─────────────────────────────────────────────────────────────────┐
│                  Provider-Specific Services                      │
│                                                                  │
│   ┌─────────────────────┐  ┌─────────────────────┐              │
│   │ DB2MetadataService  │  │  (Future Services)  │              │
│   │   - SYSCAT tables   │  │  - OracleMetadata   │              │
│   │   - DB2 version     │  │  - PostgreSQLMeta   │              │
│   │   - Relationships   │  │  - SQLServerMeta    │              │
│   └─────────────────────┘  └─────────────────────┘              │
└─────────────────────────────────────────────────────────────────┘
                              │
                              ▼
┌─────────────────────────────────────────────────────────────────┐
│                     MetadataHandler                              │
│              (Provider-Agnostic Core Layer)                      │
│                                                                  │
│   • Implements IMetadataProvider interface                       │
│   • Loads SQL statements per provider/version                    │
│   • Manages text translations per language                       │
│   • Routes queries to correct provider configuration             │
└─────────────────────────────────────────────────────────────────┘
                              │
                              ▼
┌─────────────────────────────────────────────────────────────────┐
│                      ConfigFiles                                 │
│                   (JSON Configuration)                           │
│                                                                  │
│   supported_providers.json                                       │
│   ├── db2_12.1_sql_statements.json                              │
│   ├── db2_11.5_sql_statements.json                              │
│   ├── db2_12.1_texts_en-US.json                                 │
│   ├── oracle_19c_sql_statements.json  (future)                  │
│   └── postgresql_16_sql_statements.json  (future)               │
└─────────────────────────────────────────────────────────────────┘
```

---

## Current Components

### 1. DB2MetadataService (`Services/DB2MetadataService.cs`)

**Purpose:** DB2-specific metadata collection and caching

**Scope:** DB2 ONLY

**Key Functions:**
- Collects SYSCAT table metadata
- Detects DB2 version from database
- Builds relationship documentation between system tables
- Caches metadata to local JSON files
- Generates query patterns for common operations

**DB2-Specific Tables Used:**
```sql
-- Version detection
SELECT PROD_RELEASE FROM SYSIBMADM.ENV_PROD_INFO

-- System catalog tables
SYSCAT.TABLES
SYSCAT.COLUMNS
SYSCAT.INDEXES
SYSCAT.VIEWS
SYSCAT.ROUTINES
SYSCAT.TRIGGERS
SYSIBMADM.SNAPAPPL_INFO
```

### 2. MetadataHandler (`Services/MetadataHandler.cs`)

**Purpose:** Provider-agnostic metadata management

**Scope:** Multi-provider design

**Key Functions:**
- Loads `supported_providers.json`
- Caches SQL statements per provider/version
- Provides translation support via text files
- Implements `IMetadataProvider` interface

**Usage Pattern:**
```csharp
// Get SQL for specific provider
var sql = _metadataHandler.GetQuery("DB2", "12.1", "GetTablesForSchema");

// Get translated text
var text = _metadataHandler.GetText("DB2", "12.1", "ui.menu.file");

// Get all providers
var providers = _metadataHandler.GetSupportedProviders();
```

### 3. IMetadataProvider (`Services/Interfaces/IMetadataProvider.cs`)

**Purpose:** Interface for provider-agnostic operations

**Methods:**
```csharp
public interface IMetadataProvider
{
    void SetConnectionManager(DB2ConnectionManager connectionManager);
    string GetStatement(string statementName);
    string GetStatement(string statementName, string provider, string version);
    string GetText(string key);
    string GetCurrentProvider();
    string GetCurrentVersion();
    List<string> GetSupportedProviders();
}
```

---

## Configuration Files

### supported_providers.json

Defines all supported database providers:

```json
{
  "providers": [
    {
      "provider_code": "DB2",
      "display_name": "IBM Db2",
      "default_port": 50000,
      "supported_versions": ["12.1", "11.5", "11.1"]
    },
    {
      "provider_code": "ORACLE",
      "display_name": "Oracle Database",
      "default_port": 1521,
      "supported_versions": ["19c", "21c", "23c"]
    },
    {
      "provider_code": "POSTGRESQL",
      "display_name": "PostgreSQL",
      "default_port": 5432,
      "supported_versions": ["16", "15", "14"]
    }
  ]
}
```

### SQL Statements Files

Named pattern: `{provider}_{version}_sql_statements.json`

Example: `db2_12.1_sql_statements.json`
```json
{
  "statements": {
    "GetTablesForSchema": "SELECT TABNAME FROM SYSCAT.TABLES WHERE TABSCHEMA = ?",
    "GetColumns": "SELECT COLNAME, TYPENAME FROM SYSCAT.COLUMNS WHERE TABSCHEMA = ? AND TABNAME = ?",
    "GetIndexes": "SELECT INDNAME FROM SYSCAT.INDEXES WHERE TABSCHEMA = ? AND TABNAME = ?"
  }
}
```

---

## Adding Support for a New Database Provider

### Step 1: Add Provider Configuration

Update `ConfigFiles/supported_providers.json`:
```json
{
  "provider_code": "POSTGRESQL",
  "display_name": "PostgreSQL",
  "default_port": 5432,
  "supported_versions": ["16", "15"]
}
```

### Step 2: Create SQL Statements File

Create `ConfigFiles/postgresql_16_sql_statements.json`:
```json
{
  "statements": {
    "GetTablesForSchema": "SELECT tablename FROM pg_tables WHERE schemaname = $1",
    "GetColumns": "SELECT column_name, data_type FROM information_schema.columns WHERE table_schema = $1 AND table_name = $2"
  }
}
```

### Step 3: Create Provider-Specific Metadata Service (Optional)

Create `Services/PostgreSQLMetadataService.cs`:
```csharp
public class PostgreSQLMetadataService
{
    public async Task CollectMetadataAsync(ConnectionManager cm, string profile)
    {
        // Collect pg_catalog metadata
        // Build relationship documentation
        // Cache to local files
    }
}
```

### Step 4: Create Connection Manager

Create `Data/PostgreSQLConnectionManager.cs` or extend base class:
```csharp
public class PostgreSQLConnectionManager : IDbConnectionManager
{
    // PostgreSQL-specific connection logic
}
```

---

## Design Decisions

### Why Separate DB2MetadataService?

| Reason | Explanation |
|--------|-------------|
| **Specificity** | DB2 SYSCAT tables have unique structures and relationships |
| **Optimization** | DB2-specific query patterns and caching strategies |
| **Maintenance** | Easier to maintain DB2-specific logic in isolation |
| **Testing** | Can unit test DB2 functionality independently |

### Why Provider-Agnostic MetadataHandler?

| Reason | Explanation |
|--------|-------------|
| **Extensibility** | Easy to add new providers without modifying core logic |
| **Configuration-Driven** | SQL statements in JSON, not hardcoded |
| **Localization** | Text translations per provider/version/language |
| **Consistency** | Single API for all providers |

---

## Future Enhancements

### Planned Improvements

1. **Abstract Base Class**
   ```csharp
   public abstract class DatabaseMetadataService
   {
       public abstract Task CollectMetadataAsync(IConnectionManager cm);
       public abstract Task<string> GetVersionAsync();
       protected abstract string GetSystemCatalogQuery();
   }
   ```

2. **Provider Factory**
   ```csharp
   public class MetadataServiceFactory
   {
       public IMetadataService Create(string providerCode)
       {
           return providerCode switch
           {
               "DB2" => new DB2MetadataService(),
               "ORACLE" => new OracleMetadataService(),
               "POSTGRESQL" => new PostgreSQLMetadataService(),
               _ => throw new NotSupportedException()
           };
       }
   }
   ```

3. **Connection Manager Interface**
   ```csharp
   public interface IDbConnectionManager
   {
       Task<DataTable> ExecuteQueryAsync(string sql);
       Task<int> ExecuteNonQueryAsync(string sql);
       Task<bool> TestConnectionAsync();
   }
   ```

---

## Related Files

| File | Purpose |
|------|---------|
| `Services/DB2MetadataService.cs` | DB2-specific metadata collection |
| `Services/MetadataHandler.cs` | Provider-agnostic metadata management |
| `Services/Interfaces/IMetadataProvider.cs` | Provider interface |
| `Data/DB2ConnectionManager.cs` | DB2 connection management |
| `ConfigFiles/supported_providers.json` | Provider definitions |
| `ConfigFiles/db2_*.json` | DB2 SQL statements and texts |

---

*Last Updated: December 2024*
