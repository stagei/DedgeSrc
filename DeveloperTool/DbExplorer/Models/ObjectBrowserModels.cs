using System;
using System.Collections.Generic;

namespace DbExplorer.Models;

/// <summary>
/// Root node representing the database
/// </summary>
public class DatabaseNode
{
    public string DatabaseName { get; set; } = string.Empty;
    public string ServerName { get; set; } = string.Empty;
    public DateTime ConnectedAt { get; set; }
    public List<CategoryNode> Categories { get; set; } = new();
}

/// <summary>
/// Top-level categories (Tablespaces, Schemas, Packages, etc.)
/// </summary>
public class CategoryNode
{
    public string Name { get; set; } = string.Empty;
    public string Icon { get; set; } = string.Empty;
    public int Count { get; set; }
    public CategoryType Type { get; set; }
    public bool IsLazyLoad { get; set; }
    public UserAccessLevel MinimumAccessLevel { get; set; }
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
/// Schema node with object type categories
/// </summary>
public class SchemaNode
{
    public string SchemaName { get; set; } = string.Empty;
    public string Type { get; set; } = string.Empty;  // "USER", "SYSTEM"
    public List<ObjectTypeCategory> ObjectTypes { get; set; } = new();
}

/// <summary>
/// Object type within a schema (Tables, Views, etc.)
/// </summary>
public class ObjectTypeCategory
{
    public string Name { get; set; } = string.Empty;
    public string Icon { get; set; } = string.Empty;
    public int Count { get; set; }
    public ObjectType Type { get; set; }
    public UserAccessLevel MinimumAccessLevel { get; set; }
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
    public string Name { get; set; } = string.Empty;
    public string SchemaName { get; set; } = string.Empty;
    public string FullName { get; set; } = string.Empty;
    public ObjectType Type { get; set; }
    public string Icon { get; set; } = string.Empty;
    public long? RowCount { get; set; }
    public DateTime? CreatedAt { get; set; }
    public string Owner { get; set; } = string.Empty;
    public string Remarks { get; set; } = string.Empty;
    
    // Table-specific
    public string? TableType { get; set; }
    public string? TableSpace { get; set; }
    
    // Routine-specific (Procedures/Functions)
    public string? Language { get; set; }
    public int? ParameterCount { get; set; }
}

/// <summary>
/// Security principal (Role, Group, or User)
/// </summary>
public class SecurityPrincipal
{
    public string Name { get; set; } = string.Empty;
    public SecurityPrincipalType Type { get; set; }
    public string Icon { get; set; } = string.Empty;
    public DateTime? CreateTime { get; set; }
    public string Grantor { get; set; } = string.Empty;
    public string Remarks { get; set; } = string.Empty;
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
    public string Name { get; set; } = string.Empty;
    public string Icon { get; set; } = string.Empty;
    public int GrantCount { get; set; }
    public PrivilegeCategoryType Type { get; set; }
}

public enum PrivilegeCategoryType
{
    Users,
    Tables,
    Views,
    MQTs,
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
    public string Grantor { get; set; } = string.Empty;
    public string Grantee { get; set; } = string.Empty;
    public string ObjectSchema { get; set; } = string.Empty;
    public string ObjectName { get; set; } = string.Empty;
    public string PrivilegeType { get; set; } = string.Empty;
    public string Grantable { get; set; } = string.Empty;
    public DateTime? GrantTime { get; set; }
}

/// <summary>
/// Tablespace information
/// </summary>
public class TablespaceInfo
{
    public string TablespaceName { get; set; } = string.Empty;
    public string TablespaceType { get; set; } = string.Empty;
    public string DataType { get; set; } = string.Empty;
    public int? PageSize { get; set; }
    public string Owner { get; set; } = string.Empty;
    public DateTime? CreateTime { get; set; }
    public string Remarks { get; set; } = string.Empty;
}

/// <summary>
/// Package information
/// </summary>
public class PackageInfo
{
    public string PackageSchema { get; set; } = string.Empty;
    public string PackageName { get; set; } = string.Empty;
    public string BoundBy { get; set; } = string.Empty;
    public string Owner { get; set; } = string.Empty;
    public string Isolation { get; set; } = string.Empty;
    public DateTime? CreateTime { get; set; }
    public string Remarks { get; set; } = string.Empty;
}

/// <summary>
/// User-defined type information
/// </summary>
public class TypeInfo
{
    public string TypeSchema { get; set; } = string.Empty;
    public string TypeName { get; set; } = string.Empty;
    public string MetaType { get; set; } = string.Empty;
    public string Owner { get; set; } = string.Empty;
    public DateTime? CreateTime { get; set; }
    public string Remarks { get; set; } = string.Empty;
}

/// <summary>
/// Icon constants for object browser
/// </summary>
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

