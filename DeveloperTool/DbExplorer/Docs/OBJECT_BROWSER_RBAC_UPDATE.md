# Object Browser - RBAC Access Level Update

**Date:** November 20, 2025  
**Status:** ✅ COMPLETE  
**Change:** Updated access level naming from Low/Middle/DBA to Standard/Advanced/DBA

---

## 🔄 CHANGE SUMMARY

### Old RBAC Naming:
- ❌ **Low** - Read-only user
- ❌ **Middle** - Standard DBA
- ✅ **DBA** - Full administrator

### New RBAC Naming:
- ✅ **Standard** - Standard user (read-only, simplified interface)
- ✅ **Advanced** - Advanced user (full DBA capabilities)
- ✅ **DBA** - Database administrator (all features + security)

**Rationale:** More intuitive naming that clearly indicates capability level rather than hierarchy.

---

## 📋 UPDATED DEFINITIONS

### UserAccessLevel Enum:
```csharp
public enum UserAccessLevel
{
    Standard = 1,  // Standard user - read-only, minimal complexity
    Advanced = 2,  // Advanced user - full DBA operations
    DBA = 3        // Database administrator - all features and security
}
```

---

## 🎯 ACCESS LEVEL VISIBILITY

### Category-Level Access Control

| Category | Icon | Min Access Level | Standard | Advanced | DBA |
|----------|------|------------------|----------|----------|-----|
| **Schemas** | 📁 | **Standard** | ✅ | ✅ | ✅ |
| **Aliases** | 📦 | **Standard** | ✅ | ✅ | ✅ |
| **Tablespaces** | 💾 | **Advanced** | ❌ | ✅ | ✅ |
| **Packages** | 📦 | **Advanced** | ❌ | ✅ | ✅ |
| **User-Defined Types** | 🔤 | **Advanced** | ❌ | ✅ | ✅ |
| **Remote Metadata** | 📡 | **Advanced** | ❌ | ✅ | ✅ |
| **SQL Objects** | 🔍 | **Advanced** | ❌ | ✅ | ✅ |
| **Variables** | 📋 | **Advanced** | ❌ | ✅ | ✅ |
| **XML Strings** | 📰 | **Advanced** | ❌ | ✅ | ✅ |
| **User Language** | 🌐 | **DBA** | ❌ | ❌ | ✅ |
| **Security** | 🔒 | **DBA** | ❌ | ❌ | ✅ |

**Category Counts by Level:**
- **Standard:** 2 categories (Schemas, Aliases)
- **Advanced:** 9 categories (Standard + 7 more)
- **DBA:** 11 categories (All)

---

### Schema Object-Level Access Control

| Object Type | Icon | Min Access Level | Standard | Advanced | DBA |
|-------------|------|------------------|----------|----------|-----|
| **Tables** | 📋 | **Standard** | ✅ | ✅ | ✅ |
| **Views** | 👁 | **Standard** | ✅ | ✅ | ✅ |
| **Synonyms** | 🔗 | **Standard** | ✅ | ✅ | ✅ |
| **Procedures** | ⚙️ | **Advanced** | ❌ | ✅ | ✅ |
| **Functions** | ⚡ | **Advanced** | ❌ | ✅ | ✅ |
| **Indexes** | 🔎 | **Advanced** | ❌ | ✅ | ✅ |
| **Triggers** | 🎯 | **Advanced** | ❌ | ✅ | ✅ |
| **Sequences** | 🔢 | **Advanced** | ❌ | ✅ | ✅ |
| **Types** | 🔤 | **Advanced** | ❌ | ✅ | ✅ |
| **Packages** | 📦 | **Advanced** | ❌ | ✅ | ✅ |

**Object Type Counts by Level:**
- **Standard:** 3 object types (Tables, Views, Synonyms)
- **Advanced:** 10 object types (Standard + 7 more)
- **DBA:** 10 object types (Same as Advanced)

---

## 🎨 USER EXPERIENCE BY LEVEL

### Standard Level User:
**What They See:**
```
🗄️ Database: MYDB
├── 📦 Aliases
└── 📁 Schemas
    └── 📁 MYSCHEMA
        ├── 📋 Tables (50)
        ├── 👁 Views (10)
        └── 🔗 Synonyms (2)
```

**Experience:**
- ✅ Clean, simple interface
- ✅ Focus on data browsing
- ✅ No overwhelming complexity
- ✅ Perfect for read-only users, analysts, developers querying data

---

### Advanced Level User:
**What They See:**
```
🗄️ Database: MYDB
├── 📦 Aliases
├── 🔤 User-Defined Types
├── 📦 Packages
├── 📡 Remote metadata
├── 🔍 SQL
├── 📋 Variables
├── 💾 Tablespaces
├── 📰 XML Strings
└── 📁 Schemas
    └── 📁 MYSCHEMA
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

**Experience:**
- ✅ Full DBA capabilities
- ✅ Access to performance tuning (indexes, tablespaces)
- ✅ Access to programming objects (procedures, functions, triggers)
- ✅ Can manage advanced DB2 features
- ❌ No security/user management (DBA-only)

---

### DBA Level User:
**What They See:**
```
🗄️ Database: MYDB
├── 📦 Aliases
├── 🔤 User-Defined Types
├── 📦 Packages
├── 🌐 User Language
├── 📡 Remote metadata
├── 🔍 SQL
├── 📋 Variables
├── 💾 Tablespaces
├── 📰 XML Strings
├── 🔒 Security
│   ├── 👤 Roles
│   ├── 👥 Groups
│   └── 👤 Users
└── 📁 Schemas
    └── (Same as Advanced)
```

**Experience:**
- ✅ Complete visibility
- ✅ Security management (Roles, Groups, Users, Privileges)
- ✅ System configuration (User Language)
- ✅ All advanced features
- ✅ Full control over database

---

## 🔧 IMPLEMENTATION CHANGES

### Model Classes Updated:
```csharp
public class CategoryNode
{
    // ... existing properties ...
    public UserAccessLevel MinimumAccessLevel { get; set; }
}

public class ObjectTypeCategory
{
    // ... existing properties ...
    public UserAccessLevel MinimumAccessLevel { get; set; }
}
```

### Service Methods Updated:
```csharp
public async Task<List<CategoryNode>> GetTopLevelCategoriesAsync(UserAccessLevel userAccessLevel);
public async Task<Dictionary<ObjectType, int>> GetSchemaObjectCountsAsync(string schemaName, UserAccessLevel userAccessLevel);

// New helper methods:
public UserAccessLevel GetUserAccessLevel();
public bool CanViewCategory(CategoryType categoryType, UserAccessLevel userAccessLevel);
public bool CanViewObjectType(ObjectType objectType, UserAccessLevel userAccessLevel);
public List<ObjectType> GetVisibleObjectTypes(UserAccessLevel userAccessLevel);
```

---

## 📊 ACCESS LEVEL DETERMINATION

### How to Determine User's Access Level:

**Query SYSCAT.DBAUTH:**
```sql
SELECT 
    DBADMAUTH,        -- Database administrator
    SECURITYADMAUTH,  -- Security administrator
    DATAACCESSAUTH,   -- Data access authority
    ACCESSCTRLAUTH,   -- Access control authority
    CREATETABAUTH,    -- Can create tables
    BINDADDAUTH,      -- Can bind packages
    CONNECTAUTH       -- Can connect
FROM SYSCAT.DBAUTH
WHERE GRANTEE = CURRENT USER;
```

**Access Level Logic:**
```csharp
public UserAccessLevel GetUserAccessLevel()
{
    // Query SYSCAT.DBAUTH for current user
    var dbAuth = QueryDbAuth(CurrentUser);
    
    // DBA Level: Has DBADM or SECADM authority
    if (dbAuth.DBADMAUTH == 'Y' || dbAuth.SECURITYADMAUTH == 'Y')
        return UserAccessLevel.DBA;
    
    // Advanced Level: Has significant privileges (create tables, bind packages, etc.)
    if (dbAuth.CREATETABAUTH == 'Y' || 
        dbAuth.BINDADDAUTH == 'Y' || 
        dbAuth.DATAACCESSAUTH == 'Y')
        return UserAccessLevel.Advanced;
    
    // Standard Level: Only CONNECT or limited privileges
    return UserAccessLevel.Standard;
}
```

---

## 🎯 BENEFITS OF NEW NAMING

### 1. **Clarity**
- ❌ "Low" sounds negative
- ✅ "Standard" is neutral and professional

### 2. **Intuitive**
- ❌ "Middle" is vague
- ✅ "Advanced" clearly indicates enhanced capabilities

### 3. **Professional**
- ❌ Low/Middle/High sounds hierarchical
- ✅ Standard/Advanced/DBA describes capability levels

### 4. **User-Friendly**
- Users understand what "Standard" access means
- "Advanced" clearly communicates more features
- "DBA" is universally recognized

---

## 📝 MIGRATION NOTES

### For Existing Code:
If you have existing code using the old enum values:

**Old Code:**
```csharp
if (userLevel == UserAccessLevel.Low)
if (userLevel == UserAccessLevel.Middle)
```

**New Code:**
```csharp
if (userLevel == UserAccessLevel.Standard)
if (userLevel == UserAccessLevel.Advanced)
```

**Numeric Values Unchanged:**
- Standard = 1 (was Low = 1)
- Advanced = 2 (was Middle = 2)
- DBA = 3 (unchanged)

Database queries and comparisons using numeric values will continue to work without changes.

---

## ✅ FILES UPDATED

1. **OBJECT_BROWSER_IMPROVEMENT_PLAN.md** ✅
   - UserAccessLevel enum definition
   - Category access level table
   - Schema object access level table
   - Access Control Integration section
   - DB2-Specific Considerations section
   - All references to Low/Middle updated to Standard/Advanced

2. **OBJECT_BROWSER_RBAC_UPDATE.md** ✅ NEW
   - This summary document

---

## 🚀 READY FOR IMPLEMENTATION

The Object Browser plan now uses clear, professional access level naming:
- ✅ **Standard** - Simplified, data-focused experience
- ✅ **Advanced** - Full DBA capabilities
- ✅ **DBA** - Complete control + security management

This naming will be used consistently throughout the application for clarity and professionalism.

---

**Status:** ✅ RBAC naming updated throughout the plan  
**Next Step:** Implement Object Browser with new Standard/Advanced/DBA access levels

