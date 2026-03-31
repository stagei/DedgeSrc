using System.Collections.Generic;
using System.Data;
using System.Data.Common;
using System.Threading.Tasks;

namespace DbExplorer.Services.Interfaces;

/// <summary>
/// Provider-agnostic interface for database connections.
/// Abstracts away DB2/PostgreSQL/Oracle/SQL Server specific connection types.
/// </summary>
public interface IDatabaseConnection
{
    /// <summary>
    /// Provider name (DB2, PostgreSQL, Oracle, SQLServer).
    /// </summary>
    string ProviderName { get; }
    
    /// <summary>
    /// Provider version (12.1, 16.0, etc.).
    /// </summary>
    string ProviderVersion { get; }
    
    /// <summary>
    /// Is connection currently open?
    /// </summary>
    bool IsConnected { get; }
    
    /// <summary>
    /// Open connection to database.
    /// </summary>
    Task<bool> OpenAsync(string connectionString);
    
    /// <summary>
    /// Close connection.
    /// </summary>
    Task CloseAsync();
    
    /// <summary>
    /// Execute SQL query and return DataTable.
    /// </summary>
    Task<DataTable> ExecuteQueryAsync(string sql, int? maxRows = null);
    
    /// <summary>
    /// Execute SQL query and return single value (scalar).
    /// </summary>
    Task<object?> ExecuteScalarAsync(string sql);
    
    /// <summary>
    /// Execute SQL command (INSERT/UPDATE/DELETE) and return affected rows.
    /// </summary>
    Task<int> ExecuteNonQueryAsync(string sql);
    
    /// <summary>
    /// Create a database-specific command object.
    /// </summary>
    DbCommand CreateCommand(string sql);
    
    /// <summary>
    /// Test connection with timeout.
    /// </summary>
    Task<bool> TestConnectionAsync(int timeoutSeconds = 10);
    
    /// <summary>
    /// Get connection info (database name, server, user).
    /// </summary>
    ConnectionInfo GetConnectionInfo();
}

/// <summary>
/// Connection information (provider-agnostic).
/// </summary>
public class ConnectionInfo
{
    public string ServerHost { get; set; } = string.Empty;
    public int ServerPort { get; set; }
    public string DatabaseName { get; set; } = string.Empty;
    public string Username { get; set; } = string.Empty;
    public string ProviderName { get; set; } = string.Empty;
    public string ProviderVersion { get; set; } = string.Empty;
}

