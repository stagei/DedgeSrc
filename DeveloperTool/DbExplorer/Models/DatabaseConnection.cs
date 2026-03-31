namespace DbExplorer.Models;

/// <summary>
/// Database-agnostic model for connection information.
/// Supports DB2, PostgreSQL, SQL Server, Oracle, MySQL, etc.
/// </summary>
public class DatabaseConnection : IConnectionInfo
{
    public string Id { get; set; } = Guid.NewGuid().ToString();
    public string Name { get; set; } = string.Empty;
    public string Server { get; set; } = string.Empty;
    public int Port { get; set; } = 50000;
    public string Database { get; set; } = string.Empty;
    public string Username { get; set; } = string.Empty;
    public string Password { get; set; } = string.Empty;
    public bool SavePassword { get; set; } = false;
    public int ConnectionTimeout { get; set; } = 30;
    
    /// <summary>
    /// Database provider type: db2, postgresql, sqlserver, oracle, mysql
    /// Default is db2 for backward compatibility
    /// </summary>
    public string ProviderType { get; set; } = "db2";

    /// <summary>
    /// Provider version (e.g. 12.1 for DB2, 18 for PostgreSQL). Optional; defaults by provider when saving.
    /// </summary>
    public string? Version { get; set; }
    
    /// <summary>
    /// Whether this connection should be read-only (no DML/DDL allowed)
    /// </summary>
    public bool IsReadOnly { get; set; } = false;
    
    /// <summary>
    /// Auto-commit mode: true = auto-commit, false = manual commit
    /// </summary>
    public bool AutoCommit { get; set; } = true;
    
    /// <summary>
    /// User's permission level (determined after connection)
    /// </summary>
    public UserPermissions? Permissions { get; set; }
    
    /// <summary>
    /// Whether access level has been determined
    /// </summary>
    public bool IsAccessLevelDetermined => Permissions != null;

    /// <summary>
    /// Get connection string based on provider type
    /// </summary>
    public string GetConnectionString(bool maskPassword = false)
    {
        var pwd = maskPassword ? "***" : Password;
        
        return ProviderType?.ToLowerInvariant() switch
        {
            "postgresql" or "postgres" => 
                $"Host={Server};Port={Port};Database={Database};Username={Username};Password={pwd};Timeout={ConnectionTimeout};",
            "sqlite" => 
                $"Data Source={Database};Mode=ReadWriteCreate;Cache=Default;",
            "sqlserver" or "mssql" => 
                $"Server={Server},{Port};Database={Database};User Id={Username};Password={pwd};Connection Timeout={ConnectionTimeout};TrustServerCertificate=True;",
            "oracle" => 
                $"Data Source={Server}:{Port}/{Database};User Id={Username};Password={pwd};Connection Timeout={ConnectionTimeout};",
            "mysql" => 
                $"Server={Server};Port={Port};Database={Database};Uid={Username};Pwd={pwd};Connection Timeout={ConnectionTimeout};",
            _ => // Default to DB2; Security=0 avoids SQL30082N reason 36 (UNEXPECTED CLIENT ERROR) when server uses simple auth
                $"Server={Server}:{Port};Database={Database};UID={Username};PWD={pwd};ConnectTimeout={ConnectionTimeout};Security=0;"
        };
    }

    /// <summary>
    /// Get display name for the connection
    /// </summary>
    public string GetDisplayName()
    {
        var providerLabel = ProviderType?.ToUpperInvariant() switch
        {
            "POSTGRESQL" or "POSTGRES" => "PostgreSQL",
            "SQLITE" => "SQLite",
            "SQLSERVER" or "MSSQL" => "SQL Server",
            "ORACLE" => "Oracle",
            "MYSQL" => "MySQL",
            _ => "DB2"
        };
        
        return string.IsNullOrEmpty(Name) 
            ? $"{Database} @ {Server} ({providerLabel})" 
            : $"{Name} ({Database} @ {Server})";
    }

    /// <summary>
    /// Validate connection information
    /// </summary>
    public bool IsValid()
    {
        if (string.Equals(ProviderType, "SQLite", StringComparison.OrdinalIgnoreCase))
            return !string.IsNullOrWhiteSpace(Database); // Data Source path
        return !string.IsNullOrWhiteSpace(Server) &&
               !string.IsNullOrWhiteSpace(Database) &&
               !string.IsNullOrWhiteSpace(Username) &&
               Port > 0 && Port <= 65535;
    }
    
    /// <summary>
    /// Get default port for provider type
    /// </summary>
    public static int GetDefaultPort(string providerType)
    {
        return providerType?.ToLowerInvariant() switch
        {
            "postgresql" or "postgres" => 5432,
            "sqlite" => 0,
            "sqlserver" or "mssql" => 1433,
            "oracle" => 1521,
            "mysql" => 3306,
            _ => 50000 // DB2
        };
    }
}

// Type alias for backward compatibility during migration
// TODO: Remove this alias once all code is updated
public class DB2Connection : DatabaseConnection
{
    public DB2Connection()
    {
        ProviderType = "db2";
        Port = 50000;
    }
}
