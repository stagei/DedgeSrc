namespace DbExplorer.Models;

/// <summary>
/// Database-agnostic interface for connection information.
/// Supports DB2, PostgreSQL, SQL Server, Oracle, MySQL, etc.
/// </summary>
public interface IConnectionInfo
{
    /// <summary>Unique identifier for this connection</summary>
    string Id { get; set; }
    
    /// <summary>User-friendly name for this connection</summary>
    string Name { get; set; }
    
    /// <summary>Database server hostname or IP</summary>
    string Server { get; set; }
    
    /// <summary>Database server port</summary>
    int Port { get; set; }
    
    /// <summary>Database/catalog name</summary>
    string Database { get; set; }
    
    /// <summary>Username for authentication</summary>
    string Username { get; set; }
    
    /// <summary>Password for authentication</summary>
    string Password { get; set; }
    
    /// <summary>Whether to persist password</summary>
    bool SavePassword { get; set; }
    
    /// <summary>Connection timeout in seconds</summary>
    int ConnectionTimeout { get; set; }
    
    /// <summary>Whether this connection is read-only</summary>
    bool IsReadOnly { get; set; }
    
    /// <summary>Whether to auto-commit transactions</summary>
    bool AutoCommit { get; set; }
    
    /// <summary>Database provider type (db2, postgresql, sqlserver, oracle, mysql)</summary>
    string ProviderType { get; set; }
    
    /// <summary>User's permission level (determined after connection)</summary>
    UserPermissions? Permissions { get; set; }
    
    /// <summary>Whether access level has been determined</summary>
    bool IsAccessLevelDetermined { get; }
    
    /// <summary>Get the provider-specific connection string</summary>
    string GetConnectionString(bool maskPassword = false);
    
    /// <summary>Get display name for UI</summary>
    string GetDisplayName();
    
    /// <summary>Validate connection information</summary>
    bool IsValid();
}
