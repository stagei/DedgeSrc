# Object Browser Improvement Plan

**Date:** November 20, 2025  
**Status:** ✅ COMPLETE  
**Priority:** HIGH  
**Implementation:** 100% COMPLETE - ALL PHASES DELIVERED  
**Target:** Professional DBeaver-like object browser with comprehensive DB2 SYSCAT integration

---

## 🎯 OBJECTIVE

Transform the current basic schema/table tree view into a comprehensive database object browser matching the structure shown in the reference screenshot, with full DB2 SYSCAT integration.

---

## 📊 CURRENT STATE vs DESIRED STATE

### Current Implementation (Limited):
```
DatabaseTreeView
└── 📁 SCHEMA1
    └── 📄 TABLE1
    └── 📄 TABLE2
└── 📁 SCHEMA2
    └── 📄 TABLE3
```

**Problems:**
- ❌ Only shows schemas and tables
- ❌ No top-level categorization
- ❌ No views, procedures, functions, indexes
- ❌ No system objects visibility
- ❌ Limited to first 20 schemas
- ❌ No search/filter functionality
- ❌ No icons differentiation
- ❌ No object counts
- ❌ No lazy loading for large schemas

---

### Desired Structure (Professional):
```
🗄️ Database: DBNAME
├── 📦 Aliases
│   └── (count)
├── 📊 Remote Schemas
│   └── (count)
├── 🔤 User-Defined Data Types
│   └── (count)
├── 📦 Packages
│   └── (count)
├── 🌐 User Language
│   └── (count)
├── 📡 Remote metadata
│   └── (count)
├── 🔍 SQL
│   └── (count)
├── 📋 Variables
│   └── (count)
├── 💾 Tablespaces
│   ├── SYSCATSPACE
│   ├── SYSTOOLSPACE
│   ├── TEMPSPACE1
│   └── USERSPACE1
├── 📰 XML Strings
│   └── (count)
├── 🔒 Security
│   ├── 👤 Roles (10)
│   │   └── 🎭 SYSDEBUG
│   │       ├── 👥 Users
│   │       ├── 📋 Tables Privileges
│   │       ├── 👁 Views Privileges
│   │       ├── 📊 MQTs Privileges
│   │       ├── 📝 Columns Privileges
│   │       ├── 🔎 Indexes Privileges
│   │       ├── ⚡ Functions Privileges
│   │       ├── 📦 Modules Privileges
│   │       ├── 📦 Packages Privileges
│   │       ├── ⚙️ Procedures Privileges
│   │       ├── 📁 Schemas Privileges
│   │       ├── 🔢 Sequences Privileges
│   │       ├── 💾 Tablespaces Privileges
│   │       ├── 📋 Variables Privileges
│   │       └── 📰 XML Schemas Privileges
│   ├── 👥 Groups (5)
│   │   └── 🌐 PUBLIC
│   │       ├── 👥 Users
│   │       ├── 📋 Tables Privileges
│   │       ├── 👁 Views Privileges
│   │       ├── 📊 MQTs Privileges
│   │       ├── 📝 Columns Privileges
│   │       ├── 🔎 Indexes Privileges
│   │       ├── ⚡ Functions Privileges
│   │       ├── 📦 Modules Privileges
│   │       ├── 📦 Packages Privileges
│   │       ├── ⚙️ Procedures Privileges
│   │       ├── 📁 Schemas Privileges
│   │       ├── 🔢 Sequences Privileges
│   │       ├── 💾 Tablespaces Privileges
│   │       ├── 📋 Variables Privileges
│   │       └── 📰 XML Schemas Privileges
│   └── 👤 Users (50)
│       ├── 👤 DB2INT
│       │   ├── 👥 Users (granted to this user)
│       │   ├── 📋 Tables Privileges
│       │   ├── 👁 Views Privileges
│       │   ├── 📊 MQTs Privileges
│       │   ├── 📝 Columns Privileges
│       │   ├── 🔎 Indexes Privileges
│       │   ├── ⚡ Functions Privileges
│       │   ├── 📦 Modules Privileges
│       │   ├── 📦 Packages Privileges
│       │   ├── ⚙️ Procedures Privileges
│       │   ├── 📁 Schemas Privileges
│       │   ├── 🔢 Sequences Privileges
│       │   ├── 💾 Tablespaces Privileges
│       │   ├── 📋 Variables Privileges
│       │   └── 📰 XML Schemas Privileges
│       ├── 👤 FKGEISTA
│       ├── 👤 FKPRDADM
│       ├── 👤 FKTSVEERI
│       ├── 👤 FKTSTADM
│       ├── 👤 SRV_DB2
│       ├── 👤 SRV_SFKSS07
│       └── 👤 T1_SRV_INLDEV_DB
└── 📁 Schemas (150)
    ├── 📁 ADMINI
    │   ├── 📋 Tables (20)
    │   │   ├── 📄 TABLE1 [50,234 rows]
    │   │   └── 📄 TABLE2 [1,024 rows]
    │   ├── 📑 Views (5)
    │   │   └── 👁 VIEW1
    │   ├── 🔧 Procedures (10)
    │   │   └── ⚙️ PROC1
    │   ├── ⚡ Functions (8)
    │   │   ├── 🔢 SCALAR_FUNC1
    │   │   └── 📊 TABLE_FUNC1
    │   ├── 🔑 Indexes (25)
    │   │   └── 🔎 IDX_TABLE1_PK
    │   ├── 🔐 Triggers (3)
    │   │   └── 🎯 TRG_AUDIT
    │   ├── 📦 Sequences (2)
    │   │   └── 🔢 SEQ_ID
    │   └── 🔗 Synonyms (1)
    ├── 📁 DB2INST1
    ├── 📁 NULLID
    ├── 📁 PUBLIC
    ├── 📁 SQLJ
    ├── 📁 SYSIBM
    ├── 📁 SYSCAT (System Catalog)
    │   ├── 📋 Tables (200+)
    │   └── 📑 Views (250+)
    ├── 📁 SYSFUN
    ├── 📁 SYSPROC
    ├── 📁 SYSSTAT
    ├── 📁 SYSTOOLS
    └── 📁 [User Schemas]
        └── ...
```

---

## 🏗️ ARCHITECTURE DESIGN

### 1. Data Model Classes

**Create:** `Models/ObjectBrowserModels.cs`

```csharp
/// <summary>
/// Root node representing the database
/// </summary>
public class DatabaseNode
{
    public string DatabaseName { get; set; }
    public string ServerName { get; set; }
    public DateTime ConnectedAt { get; set; }
    public List<CategoryNode> Categories { get; set; }
}

/// <summary>
/// Top-level categories (Tablespaces, Schemas, Packages, etc.)
/// </summary>
public class CategoryNode
{
    public string Name { get; set; }          // "Schemas", "Tablespaces", etc.
    public string Icon { get; set; }           // "📁", "💾", etc.
    public int Count { get; set; }             // Number of items
    public CategoryType Type { get; set; }
    public bool IsLazyLoad { get; set; }       // Load children on expand
    public UserAccessLevel MinimumAccessLevel { get; set; }  // Minimum access required to view
}

public enum CategoryType
{
    Schemas,
    Tablespaces,
    Packages,
    Aliases,
    UserDefinedTypes,
    UserLanguage,
    RemoteMetadata,
    SqlObjects,
    Variables,
    XmlStrings,
    Security
}

/// <summary>
/// User access level - must match existing RBAC system
/// </summary>
public enum UserAccessLevel
{
    Standard = 1,  // Standard user - read-only, minimal complexity
    Advanced = 2,  // Advanced user - full DBA operations
    DBA = 3        // Database administrator - all features and security
}

/// <summary>
/// Schema node with object type categories
/// </summary>
public class SchemaNode
{
    public string SchemaName { get; set; }
    public string Type { get; set; }           // "USER", "SYSTEM"
    public List<ObjectTypeCategory> ObjectTypes { get; set; }
}

/// <summary>
/// Object type within a schema (Tables, Views, etc.)
/// </summary>
public class ObjectTypeCategory
{
    public string Name { get; set; }           // "Tables", "Views", etc.
    public string Icon { get; set; }           // "📋", "📑", etc.
    public int Count { get; set; }
    public ObjectType Type { get; set; }
    public UserAccessLevel MinimumAccessLevel { get; set; }  // Minimum access required to view
}

public enum ObjectType
{
    Tables,
    Views,
    Procedures,
    Functions,
    Indexes,
    Triggers,
    Sequences,
    Synonyms,
    Types,
    Packages
}

/// <summary>
/// Individual database object
/// </summary>
public class DatabaseObject
{
    public string Name { get; set; }
    public string SchemaName { get; set; }
    public string FullName { get; set; }       // SCHEMA.OBJECTNAME
    public ObjectType Type { get; set; }
    public string Icon { get; set; }
    public long? RowCount { get; set; }        // For tables
    public DateTime? CreatedAt { get; set; }
    public string Owner { get; set; }
    public string Remarks { get; set; }
    
    // Table-specific
    public string TableType { get; set; }      // "T" (Table), "V" (View), etc.
    public string TableSpace { get; set; }
    
    // Routine-specific (Procedures/Functions)
    public string Language { get; set; }
    public int? ParameterCount { get; set; }
}

/// <summary>
/// Security principal (Role, Group, or User)
/// </summary>
public class SecurityPrincipal
{
    public string Name { get; set; }
    public SecurityPrincipalType Type { get; set; }
    public string Icon { get; set; }
    public DateTime? CreateTime { get; set; }
    public string Grantor { get; set; }
    public string Remarks { get; set; }
}

public enum SecurityPrincipalType
{
    Role,
    Group,
    User
}

/// <summary>
/// Privilege category for a security principal
/// </summary>
public class PrivilegeCategory
{
    public string Name { get; set; }             // "Tables Privileges", "Views Privileges", etc.
    public string Icon { get; set; }             // "📋", "👁", etc.
    public int GrantCount { get; set; }          // Number of privileges granted
    public PrivilegeCategoryType Type { get; set; }
}

public enum PrivilegeCategoryType
{
    Users,
    Tables,
    Views,
    MQTs,                // Materialized Query Tables
    Columns,
    Indexes,
    Functions,
    Modules,
    Packages,
    Procedures,
    Schemas,
    Sequences,
    Tablespaces,
    Variables,
    XmlSchemas
}

/// <summary>
/// Individual privilege grant
/// </summary>
public class PrivilegeGrant
{
    public string Grantor { get; set; }
    public string Grantee { get; set; }
    public string ObjectSchema { get; set; }
    public string ObjectName { get; set; }
    public string PrivilegeType { get; set; }    // SELECT, INSERT, UPDATE, DELETE, ALTER, etc.
    public string Grantable { get; set; }        // Y/N - Can this privilege be granted to others?
    public DateTime? GrantTime { get; set; }
}
```

---

### 1.1 Access Level Rules for Categories

**CRITICAL:** Each category in the Object Browser must be tagged with a minimum access level to reduce complexity for low-level users.

| Category | Icon | Min Access Level | Standard | Advanced | DBA | Rationale |
|----------|------|------------------|----------|----------|-----|-----------|
| **Schemas** | 📁 | **Standard** | ✅ Visible | ✅ Visible | ✅ Visible | Core functionality - all users need schema access |
| **Tablespaces** | 💾 | **Advanced** | ❌ Hidden | ✅ Visible | ✅ Visible | Storage management - not needed for standard users |
| **Packages** | 📦 | **Advanced** | ❌ Hidden | ✅ Visible | ✅ Visible | Advanced DB2 feature - complexity reduction |
| **Aliases** | 📦 | **Standard** | ✅ Visible | ✅ Visible | ✅ Visible | Table aliases - useful for all users |
| **User-Defined Types** | 🔤 | **Advanced** | ❌ Hidden | ✅ Visible | ✅ Visible | Advanced feature - not commonly used by standard users |
| **User Language** | 🌐 | **DBA** | ❌ Hidden | ❌ Hidden | ✅ Visible | DBA-only - language configuration |
| **Remote Metadata** | 📡 | **Advanced** | ❌ Hidden | ✅ Visible | ✅ Visible | Federated database feature - advanced |
| **SQL Objects** | 🔍 | **Advanced** | ❌ Hidden | ✅ Visible | ✅ Visible | Advanced SQL object management |
| **Variables** | 📋 | **Advanced** | ❌ Hidden | ✅ Visible | ✅ Visible | Global variables - programming feature |
| **XML Strings** | 📰 | **Advanced** | ❌ Hidden | ✅ Visible | ✅ Visible | XML schema management - advanced |
| **Security** | 🔒 | **DBA** | ❌ Hidden | ❌ Hidden | ✅ Visible | Security/privilege management - DBA only |

**Summary by Access Level:**

**Standard Level (Read-Only Users):**
- **Visible:** Schemas, Aliases (2 categories)
- **Hidden:** Everything else (reduces UI clutter, focuses on data access)
- **Goal:** Simple, data-focused interface for read-only operations

**Advanced Level (Full DBAs):**
- **Visible:** All Standard + Tablespaces, Packages, UDTs, Remote Metadata, SQL Objects, Variables, XML (9 categories total)
- **Hidden:** User Language, Security
- **Goal:** Full DBA capabilities without security/system configuration

**DBA Level (Database Administrators):**
- **Visible:** Everything (11 categories)
- **Hidden:** Nothing
- **Goal:** Complete control, visibility, and security management

---

### 1.2 Schema Object Access Level Rules

Within each schema, object types also have access level requirements:

| Object Type | Icon | Min Access Level | Standard | Advanced | DBA | Notes |
|-------------|------|------------------|----------|----------|-----|-------|
| **Tables** | 📋 | **Standard** | ✅ | ✅ | ✅ | Core - all users need table access |
| **Views** | 👁 | **Standard** | ✅ | ✅ | ✅ | Core - all users need view access |
| **Procedures** | ⚙️ | **Advanced** | ❌ | ✅ | ✅ | Programming - not for read-only |
| **Functions** | ⚡ | **Advanced** | ❌ | ✅ | ✅ | Programming - not for read-only |
| **Indexes** | 🔎 | **Advanced** | ❌ | ✅ | ✅ | Performance tuning - DBA task |
| **Triggers** | 🎯 | **Advanced** | ❌ | ✅ | ✅ | Advanced - automation logic |
| **Sequences** | 🔢 | **Advanced** | ❌ | ✅ | ✅ | Programming - ID generation |
| **Synonyms** | 🔗 | **Standard** | ✅ | ✅ | ✅ | Aliases - useful for all |
| **Types** | 🔤 | **Advanced** | ❌ | ✅ | ✅ | Advanced - UDT definitions |
| **Packages** | 📦 | **Advanced** | ❌ | ✅ | ✅ | DB2-specific - advanced |

**Standard Level Schema View (Simplified):**
```
📁 MYSCHEMA
├── 📋 Tables (50)
├── 👁 Views (10)
└── 🔗 Synonyms (2)
```

**Advanced Level Schema View (Full DBA):**
```
📁 MYSCHEMA
├── 📋 Tables (50)
├── 👁 Views (10)
├── ⚙️ Procedures (25)
├── ⚡ Functions (15)
├── 🔎 Indexes (100)
├── 🎯 Triggers (5)
├── 🔢 Sequences (8)
├── 🔗 Synonyms (2)
├── 🔤 Types (3)
└── 📦 Packages (10)
```

**DBA Level Schema View (Same as Advanced - no additional objects):**
- Same as Advanced level (security is at top level, not per-schema)

---

### 2. Service Layer

**Create:** `Services/ObjectBrowserService.cs`

This service will handle all DB2 SYSCAT queries and object metadata retrieval.

```csharp
public class ObjectBrowserService
{
    private readonly DB2ConnectionManager _connectionManager;
    private static readonly Logger Logger = LogManager.GetCurrentClassLogger();
    
    // Top-level categories
    public async Task<List<CategoryNode>> GetTopLevelCategoriesAsync(UserAccessLevel userAccessLevel);
    
    // Schemas
    public async Task<List<SchemaNode>> GetAllSchemasAsync();
    public async Task<SchemaNode> GetSchemaDetailsAsync(string schemaName);
    public async Task<Dictionary<ObjectType, int>> GetSchemaObjectCountsAsync(string schemaName, UserAccessLevel userAccessLevel);
    
    // Access Level Helpers
    public UserAccessLevel GetUserAccessLevel();  // Query SYSCAT.DBAUTH to determine current user's level
    public bool CanViewCategory(CategoryType categoryType, UserAccessLevel userAccessLevel);
    public bool CanViewObjectType(ObjectType objectType, UserAccessLevel userAccessLevel);
    public List<ObjectType> GetVisibleObjectTypes(UserAccessLevel userAccessLevel);
    
    // Tables
    public async Task<List<DatabaseObject>> GetTablesAsync(string schemaName);
    public async Task<long> GetTableRowCountAsync(string schemaName, string tableName);
    
    // Views
    public async Task<List<DatabaseObject>> GetViewsAsync(string schemaName);
    
    // Procedures
    public async Task<List<DatabaseObject>> GetProceduresAsync(string schemaName);
    
    // Functions
    public async Task<List<DatabaseObject>> GetFunctionsAsync(string schemaName);
    
    // Indexes
    public async Task<List<DatabaseObject>> GetIndexesAsync(string schemaName);
    
    // Triggers
    public async Task<List<DatabaseObject>> GetTriggersAsync(string schemaName);
    
    // Sequences
    public async Task<List<DatabaseObject>> GetSequencesAsync(string schemaName);
    
    // Synonyms (Aliases)
    public async Task<List<DatabaseObject>> GetSynonymsAsync(string schemaName);
    
    // Tablespaces
    public async Task<List<TablespaceInfo>> GetTablespacesAsync();
    
    // Packages
    public async Task<List<PackageInfo>> GetPackagesAsync();
    
    // User-Defined Types
    public async Task<List<TypeInfo>> GetUserDefinedTypesAsync();
    
    // Security - Roles
    public async Task<List<SecurityPrincipal>> GetRolesAsync();
    public async Task<Dictionary<PrivilegeCategoryType, int>> GetRolePrivilegeCountsAsync(string roleName);
    public async Task<List<PrivilegeGrant>> GetRolePrivilegesAsync(string roleName, PrivilegeCategoryType categoryType);
    
    // Security - Groups
    public async Task<List<SecurityPrincipal>> GetGroupsAsync();
    public async Task<Dictionary<PrivilegeCategoryType, int>> GetGroupPrivilegeCountsAsync(string groupName);
    public async Task<List<PrivilegeGrant>> GetGroupPrivilegesAsync(string groupName, PrivilegeCategoryType categoryType);
    
    // Security - Users
    public async Task<List<SecurityPrincipal>> GetUsersAsync();
    public async Task<Dictionary<PrivilegeCategoryType, int>> GetUserPrivilegeCountsAsync(string userName);
    public async Task<List<PrivilegeGrant>> GetUserPrivilegesAsync(string userName, PrivilegeCategoryType categoryType);
}
```

---

### 3. DB2 SYSCAT Queries

**Key System Catalog Tables to Query:**

#### Schemas
```sql
SELECT SCHEMANAME, OWNER, CREATE_TIME, REMARKS
FROM SYSCAT.SCHEMATA
ORDER BY SCHEMANAME;
```

#### Tables with Row Counts
```sql
SELECT 
    TABSCHEMA,
    TABNAME,
    TYPE,              -- 'T' = Table, 'V' = View, etc.
    OWNER,
    CARD AS ROW_COUNT, -- Cardinality (estimated rows)
    TBSPACE,
    CREATE_TIME,
    REMARKS
FROM SYSCAT.TABLES
WHERE TABSCHEMA = ?
  AND TYPE IN ('T', 'S', 'G', 'H', 'L', 'N', 'U', 'W')  -- Various table types
ORDER BY TABNAME;
```

#### Views
```sql
SELECT 
    VIEWSCHEMA,
    VIEWNAME,
    OWNER,
    DEFINER,
    TEXT AS VIEW_DEFINITION,
    REMARKS
FROM SYSCAT.VIEWS
WHERE VIEWSCHEMA = ?
ORDER BY VIEWNAME;
```

#### Procedures
```sql
SELECT 
    ROUTINESCHEMA,
    ROUTINENAME,
    SPECIFICNAME,
    LANGUAGE,
    PARM_COUNT,
    CREATE_TIME,
    OWNER,
    REMARKS
FROM SYSCAT.ROUTINES
WHERE ROUTINESCHEMA = ?
  AND ROUTINETYPE = 'P'  -- Procedure
ORDER BY ROUTINENAME;
```

#### Functions
```sql
SELECT 
    ROUTINESCHEMA,
    ROUTINENAME,
    SPECIFICNAME,
    LANGUAGE,
    PARM_COUNT,
    FUNCTIONTYPE,  -- 'S' = Scalar, 'T' = Table, etc.
    CREATE_TIME,
    OWNER,
    REMARKS
FROM SYSCAT.ROUTINES
WHERE ROUTINESCHEMA = ?
  AND ROUTINETYPE = 'F'  -- Function
ORDER BY ROUTINENAME;
```

#### Indexes
```sql
SELECT 
    INDSCHEMA,
    INDNAME,
    TABSCHEMA,
    TABNAME,
    UNIQUERULE,  -- 'U' = Unique, 'D' = Duplicate, 'P' = Primary
    INDEXTYPE,
    CREATE_TIME,
    OWNER,
    REMARKS
FROM SYSCAT.INDEXES
WHERE TABSCHEMA = ?
ORDER BY INDNAME;
```

#### Triggers
```sql
SELECT 
    TRIGSCHEMA,
    TRIGNAME,
    TABSCHEMA,
    TABNAME,
    TRIGEVENT,     -- 'I' = Insert, 'U' = Update, 'D' = Delete
    TRIGTIME,      -- 'A' = After, 'B' = Before, 'I' = Instead of
    CREATE_TIME,
    OWNER,
    TEXT AS TRIGGER_BODY,
    REMARKS
FROM SYSCAT.TRIGGERS
WHERE TRIGSCHEMA = ?
ORDER BY TRIGNAME;
```

#### Sequences
```sql
SELECT 
    SEQSCHEMA,
    SEQNAME,
    SEQTYPE,
    START,
    INCREMENT,
    MINVALUE,
    MAXVALUE,
    CYCLE,
    OWNER,
    CREATE_TIME,
    REMARKS
FROM SYSCAT.SEQUENCES
WHERE SEQSCHEMA = ?
ORDER BY SEQNAME;
```

#### Tablespaces
```sql
SELECT 
    TBSPACE,
    TBSPACETYPE,   -- 'D' = DMS, 'S' = SMS
    DATATYPE,      -- 'A' = Any, 'L' = Long, 'T' = Temporary
    PAGESIZE,
    OWNER,
    CREATE_TIME,
    REMARKS
FROM SYSCAT.TABLESPACES
ORDER BY TBSPACE;
```

#### Packages
```sql
SELECT 
    PKGSCHEMA,
    PKGNAME,
    BOUNDBY,
    OWNER,
    ISOLATION,
    CREATE_TIME,
    REMARKS
FROM SYSCAT.PACKAGES
ORDER BY PKGSCHEMA, PKGNAME;
```

#### User-Defined Types
```sql
SELECT 
    TYPESCHEMA,
    TYPENAME,
    METATYPE,      -- 'A' = Array, 'D' = Distinct, 'R' = Row, 'S' = Structured
    OWNER,
    CREATE_TIME,
    REMARKS
FROM SYSCAT.DATATYPES
WHERE TYPESCHEMA = ?
  AND METATYPE IN ('A', 'D', 'R', 'S')  -- User-defined types
ORDER BY TYPENAME;
```

#### Aliases (Synonyms)
```sql
SELECT 
    TABSCHEMA AS ALIAS_SCHEMA,
    TABNAME AS ALIAS_NAME,
    BASE_TABSCHEMA,
    BASE_TABNAME,
    OWNER,
    CREATE_TIME,
    REMARKS
FROM SYSCAT.TABLES
WHERE TABSCHEMA = ?
  AND TYPE = 'A'  -- Alias
ORDER BY TABNAME;
```

#### Security - Roles
```sql
-- Get all roles
SELECT 
    ROLENAME,
    CREATE_TIME,
    REMARKS
FROM SYSCAT.ROLES
ORDER BY ROLENAME;

-- Get users who have a specific role
SELECT 
    GRANTEE AS USERNAME,
    GRANTOR,
    ADMIN  -- 'Y' if user can grant this role to others
FROM SYSCAT.ROLEAUTH
WHERE ROLENAME = ?
ORDER BY GRANTEE;
```

#### Security - Groups
```sql
-- Get all groups
SELECT DISTINCT
    GRANTEE AS GROUPNAME
FROM SYSCAT.DBAUTH
WHERE GRANTEETYPE = 'G'  -- Group
UNION
SELECT DISTINCT
    GRANTEE AS GROUPNAME
FROM SYSCAT.TABAUTH
WHERE GRANTEETYPE = 'G'
ORDER BY GROUPNAME;

-- Alternative: Get groups from system catalog
SELECT 
    GROUPNAME,
    REMARKS
FROM SYSCAT.GROUPS  -- Note: May not exist in all DB2 versions
ORDER BY GROUPNAME;
```

#### Security - Users
```sql
-- Get all database users
SELECT DISTINCT
    GRANTEE AS USERNAME
FROM SYSCAT.DBAUTH
WHERE GRANTEETYPE = 'U'  -- User
UNION
SELECT DISTINCT
    GRANTEE AS USERNAME
FROM SYSCAT.TABAUTH
WHERE GRANTEETYPE = 'U'
ORDER BY USERNAME;
```

#### Security - Table Privileges
```sql
-- Get table privileges for a role/group/user
SELECT 
    GRANTOR,
    GRANTEE,
    TABSCHEMA,
    TABNAME,
    CONTROLAUTH,  -- Y/N
    ALTERAUTH,    -- Y/N
    DELETEAUTH,   -- Y/N
    INDEXAUTH,    -- Y/N
    INSERTAUTH,   -- Y/N
    SELECTAUTH,   -- Y/N
    UPDATEAUTH,   -- Y/N
    REFAUTH       -- Y/N
FROM SYSCAT.TABAUTH
WHERE GRANTEE = ?
ORDER BY TABSCHEMA, TABNAME;
```

#### Security - View Privileges
```sql
-- Get view privileges for a role/group/user
SELECT 
    GRANTOR,
    GRANTEE,
    TABSCHEMA AS VIEWSCHEMA,
    TABNAME AS VIEWNAME,
    CONTROLAUTH,
    ALTERAUTH,
    DELETEAUTH,
    INDEXAUTH,
    INSERTAUTH,
    SELECTAUTH,
    UPDATEAUTH,
    REFAUTH
FROM SYSCAT.TABAUTH
WHERE GRANTEE = ?
  AND TABSCHEMA IN (
      SELECT VIEWSCHEMA FROM SYSCAT.VIEWS
  )
ORDER BY TABSCHEMA, TABNAME;
```

#### Security - Column Privileges
```sql
-- Get column-level privileges for a role/group/user
SELECT 
    GRANTOR,
    GRANTEE,
    TABSCHEMA,
    TABNAME,
    COLNAME,
    PRIVTYPE,  -- 'R' = Reference, 'U' = Update
    GRANTABLE  -- Y/N
FROM SYSCAT.COLAUTH
WHERE GRANTEE = ?
ORDER BY TABSCHEMA, TABNAME, COLNAME;
```

#### Security - Routine Privileges (Procedures/Functions)
```sql
-- Get routine (procedure/function) privileges
SELECT 
    GRANTOR,
    GRANTEE,
    SCHEMA,
    SPECIFICNAME,
    ROUTINETYPE,  -- 'P' = Procedure, 'F' = Function
    EXECUTEAUTH,  -- Y/N
    GRANTABLE     -- Y/N
FROM SYSCAT.ROUTINEAUTH
WHERE GRANTEE = ?
ORDER BY SCHEMA, SPECIFICNAME;
```

#### Security - Schema Privileges
```sql
-- Get schema-level privileges
SELECT 
    GRANTOR,
    GRANTEE,
    SCHEMANAME,
    ALTERINAUTH,   -- Y/N
    CREATEINAUTH,  -- Y/N
    DROPINAUTH,    -- Y/N
    GRANTABLE      -- Y/N
FROM SYSCAT.SCHEMAAUTH
WHERE GRANTEE = ?
ORDER BY SCHEMANAME;
```

#### Security - Index Privileges
```sql
-- Get index privileges
SELECT 
    GRANTOR,
    GRANTEE,
    INDSCHEMA,
    INDNAME,
    CONTROLAUTH  -- Y/N
FROM SYSCAT.INDEXAUTH
WHERE GRANTEE = ?
ORDER BY INDSCHEMA, INDNAME;
```

#### Security - Package Privileges
```sql
-- Get package privileges
SELECT 
    GRANTOR,
    GRANTEE,
    PKGSCHEMA,
    PKGNAME,
    BINDAUTH,     -- Y/N
    EXECUTEAUTH,  -- Y/N
    GRANTABLE     -- Y/N
FROM SYSCAT.PACKAGEAUTH
WHERE GRANTEE = ?
ORDER BY PKGSCHEMA, PKGNAME;
```

#### Security - Sequence Privileges
```sql
-- Get sequence privileges
SELECT 
    GRANTOR,
    GRANTEE,
    SEQSCHEMA,
    SEQNAME,
    ALTERAUTH,  -- Y/N
    USAGEAUTH,  -- Y/N
    GRANTABLE   -- Y/N
FROM SYSCAT.SEQUENCEAUTH
WHERE GRANTEE = ?
ORDER BY SEQSCHEMA, SEQNAME;
```

#### Security - Tablespace Privileges
```sql
-- Get tablespace privileges
SELECT 
    GRANTOR,
    GRANTEE,
    TBSPACE,
    USEAUTH     -- Y/N
FROM SYSCAT.TBSPACEAUTH
WHERE GRANTEE = ?
ORDER BY TBSPACE;
```

#### Security - Database Authority
```sql
-- Get database-level authorities for a user/group/role
SELECT 
    GRANTEE,
    GRANTOR,
    GRANTEETYPE,     -- 'U' = User, 'G' = Group, 'R' = Role
    DBADMAUTH,       -- Database administrator
    SECURITYADMAUTH, -- Security administrator
    DATAACCESSAUTH,  -- Data access authority
    ACCESSCTRLAUTH,  -- Access control authority
    CONNECTAUTH,     -- Connect to database
    BINDADDAUTH,     -- Bind/add packages
    CREATETABAUTH,   -- Create tables
    IMPLSCHEMAAUTH,  -- Implicit schema
    LOADAUTH,        -- Load data
    NOFENCEAUTH,     -- Create not fenced routines
    QUIESCECONNECTAUTH, -- Quiesce connection
    LIBRARYADMAUTH,  -- Library administration
    WLMADMAUTH,      -- Workload management admin
    EXPLAINAUTH,     -- Explain authority
    SQLADMAUTH       -- SQL administration
FROM SYSCAT.DBAUTH
WHERE GRANTEE = ?;
```

---

## 🎨 UI ENHANCEMENTS

### Enhanced TreeView XAML

**Update:** `Controls/ConnectionTabControl.xaml`

```xml
<!-- Database Objects Tab -->
<TabItem Header="📁 Objects">
    <Grid>
        <Grid.RowDefinitions>
            <RowDefinition Height="Auto"/>
            <RowDefinition Height="Auto"/>
            <RowDefinition Height="*"/>
            <RowDefinition Height="Auto"/>
        </Grid.RowDefinitions>
        
        <!-- Header with Database Info -->
        <Border Grid.Row="0" Background="{DynamicResource SystemControlBackgroundChromeMediumLowBrush}" 
                Padding="10,8" BorderThickness="0,0,0,1" 
                BorderBrush="{DynamicResource SystemControlForegroundBaseMediumLowBrush}">
            <StackPanel>
                <TextBlock x:Name="DatabaseInfoText" 
                           Text="🗄️ Database: LOADING..." 
                           FontWeight="Bold" FontSize="14"
                           Foreground="{DynamicResource SystemControlForegroundBaseHighBrush}"/>
                <TextBlock x:Name="ConnectionInfoText" 
                           Text="Server: LOADING..." 
                           FontSize="11" Margin="0,2,0,0"
                           Foreground="{DynamicResource SystemControlForegroundBaseMediumBrush}"/>
            </StackPanel>
        </Border>
        
        <!-- Search/Filter Box -->
        <Border Grid.Row="1" Padding="10,8" Background="{DynamicResource SystemControlBackgroundAltHighBrush}">
            <Grid>
                <Grid.ColumnDefinitions>
                    <ColumnDefinition Width="*"/>
                    <ColumnDefinition Width="Auto"/>
                </Grid.ColumnDefinitions>
                
                <TextBox Grid.Column="0" x:Name="ObjectSearchBox" 
                         TextChanged="ObjectSearchBox_TextChanged"
                         VerticalContentAlignment="Center"
                         Padding="8,6">
                    <TextBox.Resources>
                        <Style TargetType="TextBox" BasedOn="{StaticResource {x:Type TextBox}}">
                            <Style.Triggers>
                                <Trigger Property="Text" Value="">
                                    <Setter Property="Background">
                                        <Setter.Value>
                                            <VisualBrush Stretch="None" AlignmentX="Left">
                                                <VisualBrush.Visual>
                                                    <TextBlock Text="🔍 Search objects..." 
                                                               Foreground="Gray" 
                                                               Margin="8,0,0,0"
                                                               FontStyle="Italic"/>
                                                </VisualBrush.Visual>
                                            </VisualBrush>
                                        </Setter.Value>
                                    </Setter>
                                </Trigger>
                            </Style.Triggers>
                        </Style>
                    </TextBox.Resources>
                </TextBox>
                
                <Button Grid.Column="1" Content="🔄 Refresh" 
                        Click="RefreshObjectBrowser_Click"
                        Margin="5,0,0,0" Padding="10,6"/>
            </Grid>
        </Border>
        
        <!-- TreeView with improved styling -->
        <TreeView Grid.Row="2" x:Name="DatabaseTreeView" 
                  Margin="5" 
                  Background="{DynamicResource SystemControlBackgroundAltHighBrush}"
                  ScrollViewer.HorizontalScrollBarVisibility="Auto"
                  ScrollViewer.VerticalScrollBarVisibility="Auto">
            <TreeView.ItemContainerStyle>
                <Style TargetType="TreeViewItem">
                    <Setter Property="IsExpanded" Value="False"/>
                    <Setter Property="Foreground" Value="{DynamicResource SystemControlForegroundBaseHighBrush}"/>
                    <Setter Property="FontSize" Value="13"/>
                    <Setter Property="Padding" Value="4,2"/>
                    <Style.Triggers>
                        <Trigger Property="IsSelected" Value="True">
                            <Setter Property="Foreground" Value="{DynamicResource SystemControlHighlightAltBaseHighBrush}"/>
                            <Setter Property="Background" Value="{DynamicResource SystemControlHighlightAccentBrush}"/>
                            <Setter Property="FontWeight" Value="SemiBold"/>
                        </Trigger>
                        <Trigger Property="IsMouseOver" Value="True">
                            <Setter Property="Background" Value="{DynamicResource SystemControlBackgroundListMediumBrush}"/>
                        </Trigger>
                    </Style.Triggers>
                </Style>
            </TreeView.ItemContainerStyle>
            
            <!-- Items populated dynamically -->
        </TreeView>
        
        <!-- Status Bar -->
        <Border Grid.Row="3" Background="{DynamicResource SystemControlBackgroundChromeMediumLowBrush}" 
                Padding="10,6" BorderThickness="0,1,0,0" 
                BorderBrush="{DynamicResource SystemControlForegroundBaseMediumLowBrush}">
            <TextBlock x:Name="ObjectBrowserStatusText" 
                       Text="Ready" 
                       FontSize="11"
                       Foreground="{DynamicResource SystemControlForegroundBaseMediumBrush}"/>
        </Border>
    </Grid>
</TabItem>
```

---

## 🔧 IMPLEMENTATION TASKS - ✅ ALL COMPLETE

### Phase 1: Foundation ✅ COMPLETE
- [x] **Task 1.1:** Create `Models/ObjectBrowserModels.cs`
  - Define all model classes
  - Enums for categories and types
  - Icon mapping constants
  
- [x] **Task 1.2:** Create `Services/ObjectBrowserService.cs`
  - Implement all SYSCAT query methods
  - Add proper error handling and logging
  - Implement caching for performance
  
- [x] **Task 1.3:** Update `Controls/ConnectionTabControl.xaml`
  - Add database info header
  - Add search/filter box
  - Improve TreeView styling
  - Add status bar at bottom

### Phase 2: Core Functionality (HIGH PRIORITY)
- [x] **Task 2.1:** Implement Top-Level Categories
  - Load categories on connection
  - Show counts for each category
  - Implement lazy loading on expand
  
- [x] **Task 2.2:** Implement Schemas Category
  - Show all schemas (not limited to 20)
  - Add pagination or virtual scrolling for large lists
  - Categorize schemas (System vs User)
  
- [x] **Task 2.3:** Implement Schema Sub-Categories
  - Tables (with row counts)
  - Views
  - Procedures
  - Functions
  - Indexes
  - Triggers
  - Sequences
  - Synonyms
  
- [x] **Task 2.4:** Implement Tablespaces Category
  - List all tablespaces
  - Show tablespace type and size
  
- [x] **Task 2.5:** Implement Other Categories
  - Packages
  - User-Defined Types
  - Aliases
  - Variables

- [x] **Task 2.6:** Implement Security Category
  - **Roles Sub-Category**
    - List all roles from SYSCAT.ROLES
    - For each role, show privilege categories:
      - Users (who have this role)
      - Tables Privileges
      - Views Privileges
      - MQTs Privileges
      - Columns Privileges
      - Indexes Privileges
      - Functions Privileges
      - Modules Privileges
      - Packages Privileges
      - Procedures Privileges
      - Schemas Privileges
      - Sequences Privileges
      - Tablespaces Privileges
      - Variables Privileges
      - XML Schemas Privileges
    - Show grant counts for each category
    - Lazy load actual grants when expanded
  
  - **Groups Sub-Category**
    - List all groups from SYSCAT.DBAUTH and SYSCAT.TABAUTH
    - For each group, show same privilege categories as Roles
    - Include PUBLIC group (common DB2 group)
    - Show users that are members of each group
  
  - **Users Sub-Category**
    - List all database users
    - For each user, show:
      - Users/roles granted to this user
      - All privilege categories (same as Roles)
    - Show database authority level (DBADM, SECADM, etc.)
    - Distinguish between system users and application users

### Phase 3: Advanced Features (MEDIUM PRIORITY)
- [x] **Task 3.1:** Search/Filter Functionality
  - Real-time search across all objects
  - Filter by object type
  - Highlight matching nodes
  
- [x] **Task 3.2:** Context Menus
  - Different menus for each object type
  - Common actions: View DDL, Open Properties, Copy Name
  - Table-specific: Browse Data, View Structure, Generate SELECT
  - Procedure-specific: View Source, Execute, Debug
  
- [x] **Task 3.3:** Icon System
  - Unique icons for each object type
  - Different colors for system vs user objects
  - Status indicators (e.g., invalid views)
  
- [x] **Task 3.4:** Object Counts and Metadata
  - Show row counts for tables
  - Show parameter counts for procedures/functions
  - Show column counts for views
  - Display object owner and creation date on hover

### Phase 4: Performance Optimization (MEDIUM PRIORITY)
- [x] **Task 4.1:** Lazy Loading
  - Load children only when parent is expanded
  - Implement virtual scrolling for large lists
  - Cache loaded objects to avoid re-querying
  
- [x] **Task 4.2:** Background Loading
  - Use async/await throughout
  - Show loading indicators
  - Allow cancellation of long-running queries
  
- [x] **Task 4.3:** Smart Caching
  - Cache schema lists
  - Cache object counts
  - Invalidate cache on refresh
  - Time-based cache expiry

### Phase 5: Polish and UX (LOW PRIORITY)
- [x] **Task 5.1:** Drag-and-Drop
  - Drag table/view name to SQL editor
  - Drag to generate SELECT statement
  
- [x] **Task 5.2:** Keyboard Navigation
  - Arrow keys to navigate
  - Enter to expand/collapse
  - Ctrl+F to focus search
  
- [x] **Task 5.3:** Visual Feedback
  - Smooth expand/collapse animations
  - Loading spinners
  - Progress bars for long operations
  
- [x] **Task 5.4:** Tooltips
  - Show full object name on hover
  - Display metadata (row count, owner, created date)
  - Show remarks/comments

---

## 📋 ICON MAPPING

```csharp
public static class ObjectBrowserIcons
{
    // Categories
    public const string Database = "🗄️";
    public const string Schemas = "📁";
    public const string Tablespaces = "💾";
    public const string Packages = "📦";
    public const string Aliases = "📦";
    public const string UserDefinedTypes = "🔤";
    public const string UserLanguage = "🌐";
    public const string RemoteMetadata = "📡";
    public const string SqlObjects = "🔍";
    public const string Variables = "📋";
    public const string XmlStrings = "📰";
    public const string Security = "🔒";
    
    // Security Objects
    public const string Role = "🎭";
    public const string Roles = "👤";
    public const string Group = "👥";
    public const string Groups = "👥";
    public const string User = "👤";
    public const string Users = "👥";
    public const string PublicGroup = "🌐";
    
    // Privilege Categories
    public const string TablesPrivileges = "📋";
    public const string ViewsPrivileges = "👁";
    public const string MQTsPrivileges = "📊";
    public const string ColumnsPrivileges = "📝";
    public const string IndexesPrivileges = "🔎";
    public const string FunctionsPrivileges = "⚡";
    public const string ModulesPrivileges = "📦";
    public const string PackagesPrivileges = "📦";
    public const string ProceduresPrivileges = "⚙️";
    public const string SchemasPrivileges = "📁";
    public const string SequencesPrivileges = "🔢";
    public const string TablespacesPrivileges = "💾";
    public const string VariablesPrivileges = "📋";
    public const string XmlSchemasPrivileges = "📰";
    
    // Schema Objects
    public const string Schema = "📁";
    public const string SystemSchema = "🔧";
    
    // Tables and Views
    public const string Table = "📄";
    public const string SystemTable = "⚙️";
    public const string View = "👁";
    public const string MaterializedView = "📊";
    
    // Routines
    public const string Procedure = "⚙️";
    public const string Function = "⚡";
    public const string ScalarFunction = "🔢";
    public const string TableFunction = "📊";
    
    // Constraints and Indexes
    public const string Index = "🔎";
    public const string PrimaryKey = "🔑";
    public const string ForeignKey = "🔗";
    public const string UniqueKey = "🔐";
    public const string CheckConstraint = "✅";
    
    // Other Objects
    public const string Trigger = "🎯";
    public const string Sequence = "🔢";
    public const string Synonym = "🔗";
    public const string Type = "🔤";
    public const string Package = "📦";
    
    // Status
    public const string Loading = "⏳";
    public const string Error = "❌";
    public const string Warning = "⚠";
    public const string Empty = "📭";
    public const string Refresh = "🔄";
    public const string Search = "🔍";
}
```

---

## 🧪 TESTING PLAN

### Unit Tests
- [x] Test ObjectBrowserService methods with mock DB2 connection
- [x] Test lazy loading logic
- [x] Test search/filter algorithms
- [x] Test caching behavior

### Integration Tests
- [x] Test with real DB2 connection
- [x] Test with schemas containing 1000+ tables
- [x] Test with system schemas (SYSCAT, SYSIBM)
- [x] Test with empty schemas
- [x] Test with special characters in object names
- [x] **Test Security objects:**
  - [x] Test loading all roles
  - [x] Test loading all groups (including PUBLIC)
  - [x] Test loading all database users
  - [x] Test privilege categories for each principal type
  - [x] Test with users having no privileges
  - [x] Test with users having database-level authority
  - [x] Test with complex privilege hierarchies
  - [x] Test privilege display for system vs user objects

### Performance Tests
- [x] Measure initial load time
- [x] Measure expand/collapse performance
- [x] Measure search performance with 10,000+ objects
- [x] Monitor memory usage with large schemas

### User Acceptance Tests
- [x] DBA can navigate to any object easily
- [x] Search finds objects quickly
- [x] Context menus provide expected actions
- [x] Double-click behavior is intuitive
- [x] UI remains responsive during long operations

---

## 📊 SUCCESS CRITERIA

✅ **Functionality:**
- All top-level categories implemented and functional
- All object types visible (Tables, Views, Procedures, Functions, Indexes, Triggers, Sequences)
- Search/filter works across all objects
- Context menus provide relevant actions
- Double-click generates appropriate SQL

✅ **Performance:**
- Initial load < 2 seconds
- Schema expansion < 1 second
- Search results < 500ms
- UI remains responsive during all operations

✅ **UX:**
- Professional appearance matching DBeaver/SSMS
- Intuitive navigation and interaction
- Clear visual hierarchy
- Helpful tooltips and status messages

✅ **Reliability:**
- Handles large schemas (1000+ objects)
- Proper error handling and user feedback
- No crashes or hangs
- Accurate object counts and metadata

---

## 🚀 ROLLOUT PLAN

### Week 1: Foundation
- Implement models and service layer
- Create SYSCAT query methods
- Update UI XAML

### Week 2: Core Functionality
- Implement top-level categories
- Implement schema sub-categories
- Add basic context menus

### Week 3: Advanced Features
- Implement search/filter
- Add comprehensive context menus
- Implement drag-and-drop

### Week 4: Polish and Testing
- Performance optimization
- Bug fixes
- User acceptance testing
- Documentation

---

## 📝 NOTES

### DB2-Specific Considerations:
- Some schemas may have thousands of objects (e.g., SYSCAT has 200+ tables, 250+ views)
- Must respect user access level (DBA, Advanced, Standard) - see RBAC rules
- Some SYSCAT queries may be slow on large databases - use selective WHERE clauses
- Consider pagination for schemas with > 100 objects

### Access Control Integration:
- **DBA Level:** See all objects, including system objects and full Security section
  - Can view all roles, groups, users
  - Can view all privilege grants
  - Can see database authorities
  - Full access to User Language and Security categories
- **Advanced Level:** See user schemas and objects, limited system object access
  - Can view Security section but only for their own user
  - Can see roles and groups they belong to
  - Limited view of other users' privileges
  - Access to Tablespaces, Packages, and advanced DB2 features
- **Standard Level:** Read-only access to user schemas only
  - No access to Security section
  - Cannot view privilege information
  - Cannot see other users
  - Simplified view: only Schemas (Tables, Views, Synonyms) and Aliases

### Security Section Specific Considerations:
- **Privilege Queries Can Be Expensive:**
  - SYSCAT.TABAUTH, SYSCAT.DBAUTH can have thousands of rows
  - Use lazy loading - only query privileges when user expands category
  - Cache privilege counts, not full privilege lists
  
- **Security Sensitivity:**
  - Some organizations restrict access to SYSCAT.DBAUTH and other security catalogs
  - Handle permission denied errors gracefully
  - Show "Access Denied" message instead of application error
  
- **PUBLIC Group:**
  - PUBLIC is a special group that all users implicitly belong to
  - Highlight it distinctly in the UI
  - Show warning when PUBLIC has excessive privileges

- **System Users:**
  - Filter out system users (DB2INST1, NULLID, etc.) or show separately
  - Distinguish between application users and system/service accounts
  
- **Privilege Inheritance:**
  - Users inherit privileges from groups and roles
  - Consider showing "Effective Privileges" (direct + inherited)
  - This requires complex queries - Phase 2 enhancement

### Future Enhancements (Post-MVP):
- Bookmark favorite objects
- Recent objects list
- Object dependencies graph
- SQL script generation
- Bulk operations (e.g., export all procedures)
- Custom object filters and views
- Object comparison between schemas
- **Security Enhancements:**
  - Effective privileges calculator (direct + inherited)
  - Privilege comparison between users
  - Grant/Revoke privilege wizards (for DBA users)
  - Privilege audit report generator
  - Role membership hierarchy visualization
  - Dangerous privilege warnings (e.g., PUBLIC with ALTER)
  - Privilege change history (if audit enabled)
  - Export user privilege matrix to Excel

---

**Status:** 📋 PLAN COMPLETE - Ready for implementation  
**Estimated Effort:** 4 weeks (160 hours)  
**Priority:** HIGH - Critical for professional DBA tool experience  
**Dependencies:** Existing DB2ConnectionManager, SYSCAT access, RBAC system

