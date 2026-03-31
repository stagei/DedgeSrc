using System.Data;
using System.Data.Common;
using DbExplorer.Models;

namespace DbExplorer.Data;

/// <summary>
/// Database-agnostic interface for connection management.
/// Implementations exist for DB2, PostgreSQL, SQL Server, etc.
/// </summary>
public interface IConnectionManager : IDisposable
{
    /// <summary>Gets the connection information used to create this manager</summary>
    IConnectionInfo ConnectionInfo { get; }
    
    /// <summary>Whether the connection is currently open</summary>
    bool IsConnected { get; }
    
    /// <summary>Test if the database is reachable</summary>
    Task<bool> TestConnectionAsync();
    
    /// <summary>Open the database connection</summary>
    Task OpenAsync(CancellationToken cancellationToken = default);
    
    /// <summary>Close the database connection</summary>
    Task CloseAsync();
    
    /// <summary>Reconnect to the database</summary>
    Task<bool> ReconnectAsync();
    
    /// <summary>Ensure connection is open, reconnecting if needed</summary>
    Task<bool> EnsureConnectedAsync();
    
    /// <summary>Execute a query and return results as DataTable</summary>
    Task<DataTable> ExecuteQueryAsync(string sql, int? maxRows = null, int offset = 0, bool handleDecimalErrors = true);
    
    /// <summary>Execute a query and return a single scalar value</summary>
    Task<object?> ExecuteScalarAsync(string sql);
    
    /// <summary>Execute a non-query command (INSERT, UPDATE, DELETE, DDL)</summary>
    Task<int> ExecuteNonQueryAsync(string sql);
    
    /// <summary>Begin a transaction</summary>
    Task BeginTransactionAsync();
    
    /// <summary>Commit the current transaction</summary>
    Task CommitAsync();
    
    /// <summary>Rollback the current transaction</summary>
    Task RollbackAsync();
    
    /// <summary>Cancel any running query</summary>
    void CancelQuery();
    
    #region Factory Methods (Database-Agnostic Object Creation)
    
    /// <summary>
    /// Create a database command for the current connection.
    /// Returns the provider-agnostic DbCommand base class.
    /// </summary>
    /// <param name="sql">SQL statement to execute</param>
    /// <returns>A DbCommand configured for this connection</returns>
    DbCommand CreateCommand(string sql);
    
    /// <summary>
    /// Create a database parameter with the specified name and value.
    /// Returns the provider-agnostic DbParameter base class.
    /// </summary>
    /// <param name="name">Parameter name (with or without @ prefix)</param>
    /// <param name="value">Parameter value</param>
    /// <returns>A DbParameter configured for this provider</returns>
    DbParameter CreateParameter(string name, object? value);
    
    /// <summary>
    /// Create a data adapter for the specified command.
    /// Returns the provider-agnostic DbDataAdapter base class.
    /// </summary>
    /// <param name="command">The command to create an adapter for</param>
    /// <returns>A DbDataAdapter configured for this provider</returns>
    DbDataAdapter CreateDataAdapter(DbCommand command);
    
    /// <summary>
    /// Get the underlying database connection.
    /// Returns the provider-agnostic DbConnection base class.
    /// </summary>
    /// <returns>The underlying DbConnection</returns>
    DbConnection GetUnderlyingConnection();
    
    #endregion
}
