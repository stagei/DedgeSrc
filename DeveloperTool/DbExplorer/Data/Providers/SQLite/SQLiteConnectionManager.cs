using System.Data;
using System.Data.Common;
using Microsoft.Data.Sqlite;
using NLog;
using DbExplorer.Models;
using DbExplorer.Services;

namespace DbExplorer.Data.Providers.SQLite;

/// <summary>
/// Manager for SQLite database connections (file-based, serverless).
/// Uses Microsoft.Data.Sqlite. Implements IConnectionManager for database-agnostic usage.
/// </summary>
public class SQLiteConnectionManager : IConnectionManager
{
    private static readonly Logger Logger = LogManager.GetCurrentClassLogger();
    private readonly DatabaseConnection _connectionInfo;
    private SqliteConnection? _connection;
    private bool _disposed;

    /// <summary>Gets the connection information used to create this manager.</summary>
    public IConnectionInfo ConnectionInfo => _connectionInfo;

    /// <summary>Gets the connection information as DatabaseConnection (for backward compatibility).</summary>
    public DatabaseConnection Connection => _connectionInfo;

    public SQLiteConnectionManager(DatabaseConnection connectionInfo)
    {
        Logger.Debug("SQLiteConnectionManager initializing with Microsoft.Data.Sqlite");
        _connectionInfo = connectionInfo ?? throw new ArgumentNullException(nameof(connectionInfo));
        Logger.Debug("Connection: {Connection}", _connectionInfo.GetConnectionString(maskPassword: true));
    }

    /// <summary>Test database connection.</summary>
    public async Task<bool> TestConnectionAsync()
    {
        Logger.Info("Testing SQLite connection");
        Logger.Debug("Data Source: {Database}", _connectionInfo.Database);

        try
        {
            await using var testConnection = new SqliteConnection(_connectionInfo.GetConnectionString());
            await testConnection.OpenAsync();
            Logger.Info("Connection test successful");
            return true;
        }
        catch (SqliteException sqlEx)
        {
            Logger.Error(sqlEx, "SQLite connection test failed - {Message}", sqlEx.Message);
            return false;
        }
        catch (Exception ex)
        {
            Logger.Error(ex, "Connection test failed");
            return false;
        }
    }

    /// <summary>Open database connection.</summary>
    public async Task OpenAsync(CancellationToken cancellationToken = default)
    {
        if (_connection != null && _connection.State == ConnectionState.Open)
        {
            Logger.Debug("Connection already open");
            return;
        }

        Logger.Info("Opening SQLite connection");
        Logger.Debug("Data Source: {Database}", _connectionInfo.Database);

        try
        {
            _connection = new SqliteConnection(_connectionInfo.GetConnectionString());
            cancellationToken.ThrowIfCancellationRequested();
            await _connection.OpenAsync(cancellationToken);
            cancellationToken.ThrowIfCancellationRequested();

            Logger.Info("SQLite connection opened successfully - State: {State}", _connection.State);

            await SetAutoCommitModeAsync(_connectionInfo.AutoCommit);
            cancellationToken.ThrowIfCancellationRequested();

            SetUserAccessLevelForSqlite();
        }
        catch (OperationCanceledException)
        {
            Logger.Warn("Connection was cancelled by user");
            if (_connection != null)
            {
                try
                {
                    await _connection.CloseAsync();
                    await _connection.DisposeAsync();
                    _connection = null;
                }
                catch (Exception cleanupEx)
                {
                    Logger.Error(cleanupEx, "Error cleaning up cancelled connection");
                }
            }
            throw;
        }
        catch (SqliteException sqlEx)
        {
            Logger.Error(sqlEx, "Failed to open SQLite connection");
            throw new Exception($"Failed to connect to database: {sqlEx.Message}", sqlEx);
        }
        catch (Exception ex)
        {
            Logger.Error(ex, "Failed to open SQLite connection");
            throw new Exception($"Failed to connect to database: {ex.Message}", ex);
        }
    }

    /// <summary>Execute SQL query and return DataTable.</summary>
    public async Task<DataTable> ExecuteQueryAsync(string sql, int? maxRows = null, int offset = 0, bool handleDecimalErrors = true)
    {
        if (_connection == null || _connection.State != ConnectionState.Open)
        {
            Logger.Warn("Connection not open, attempting auto-reconnect");
            if (!await EnsureConnectedAsync())
                throw new InvalidOperationException("Connection is not open and reconnection failed");
        }

        Logger.Debug("Executing SQL query. MaxRows: {MaxRows}, Offset: {Offset}", maxRows, offset);

        if (_connectionInfo.IsReadOnly && IsModifyingSql(sql))
        {
            Logger.Warn("Attempted to execute modifying SQL in read-only mode");
            throw new InvalidOperationException(
                "This connection is in read-only mode. Data modification statements are not allowed.");
        }

        try
        {
            var startTime = DateTime.UtcNow;
            var paginatedSql = sql;
            if (maxRows.HasValue)
                paginatedSql = AddPaginationToQuery(sql, maxRows.Value, offset);

            await using var command = _connection!.CreateCommand();
            command.CommandText = paginatedSql;
            command.CommandTimeout = _connectionInfo.ConnectionTimeout;

            await using var reader = await command.ExecuteReaderAsync();
            var dataTable = new DataTable("Results");
            dataTable.Load(reader);

            var elapsed = (DateTime.UtcNow - startTime).TotalMilliseconds;
            Logger.Info("Query executed successfully in {Elapsed}ms, {Rows} rows returned", elapsed, dataTable.Rows.Count);

            SqlQueryHistoryService.Track(sql, source: _connectionInfo?.GetDisplayName() ?? "Unknown",
                durationMs: (long)elapsed, rowsReturned: dataTable.Rows.Count, success: true);
            return dataTable;
        }
        catch (SqliteException sqlEx)
        {
            Logger.Error(sqlEx, "SQLite query execution failed");
            SqlQueryHistoryService.Track(sql, source: _connectionInfo?.GetDisplayName() ?? "Unknown",
                success: false, errorMessage: sqlEx.Message);
            throw new Exception($"Query failed: {sqlEx.Message}", sqlEx);
        }
        catch (Exception ex)
        {
            Logger.Error(ex, "Query execution failed");
            SqlQueryHistoryService.Track(sql, source: _connectionInfo?.GetDisplayName() ?? "Unknown",
                success: false, errorMessage: ex.Message);
            throw new Exception($"Query failed: {ex.Message}", ex);
        }
    }

    private string AddPaginationToQuery(string sql, int maxRows, int offset)
    {
        Logger.Debug("Adding pagination: LIMIT {MaxRows} OFFSET {Offset}", maxRows, offset);
        var upperSql = sql.Trim().ToUpperInvariant();
        if (upperSql.Contains("LIMIT") || upperSql.Contains("OFFSET"))
        {
            Logger.Warn("Query already contains pagination clause, not modifying");
            return sql;
        }
        return $"{sql.TrimEnd().TrimEnd(';')} LIMIT {maxRows} OFFSET {offset}";
    }

    /// <summary>Execute SQL command (INSERT, UPDATE, DELETE).</summary>
    public async Task<int> ExecuteNonQueryAsync(string sql)
    {
        if (_connection == null || _connection.State != ConnectionState.Open)
        {
            if (!await EnsureConnectedAsync())
                throw new InvalidOperationException("Connection is not open and reconnection failed");
        }

        Logger.Debug("Executing SQL command");

        try
        {
            await using var command = _connection!.CreateCommand();
            command.CommandText = sql;
            command.CommandTimeout = _connectionInfo.ConnectionTimeout;
            var affectedRows = await command.ExecuteNonQueryAsync();
            Logger.Info("Command executed successfully, {Rows} rows affected", affectedRows);
            return affectedRows;
        }
        catch (SqliteException sqlEx)
        {
            Logger.Error(sqlEx, "SQLite command execution failed");
            throw new Exception($"Command failed: {sqlEx.Message}", sqlEx);
        }
        catch (Exception ex)
        {
            Logger.Error(ex, "Command execution failed");
            throw new Exception($"Command failed: {ex.Message}", ex);
        }
    }

    /// <summary>Execute scalar query.</summary>
    public async Task<object?> ExecuteScalarAsync(string sql)
    {
        if (_connection == null || _connection.State != ConnectionState.Open)
        {
            if (!await EnsureConnectedAsync())
                throw new InvalidOperationException("Connection is not open and reconnection failed");
        }

        try
        {
            await using var command = _connection!.CreateCommand();
            command.CommandText = sql;
            command.CommandTimeout = _connectionInfo.ConnectionTimeout;
            return await command.ExecuteScalarAsync();
        }
        catch (SqliteException sqlEx)
        {
            Logger.Error(sqlEx, "SQLite scalar query failed");
            throw new Exception($"Scalar query failed: {sqlEx.Message}", sqlEx);
        }
    }

    /// <summary>Close database connection.</summary>
    public void Close()
    {
        if (_connection == null) return;
        Logger.Info("Closing SQLite connection");
        try
        {
            if (_connection.State != ConnectionState.Closed)
                _connection.Close();
            Logger.Info("SQLite connection closed successfully");
        }
        catch (Exception ex)
        {
            Logger.Error(ex, "Error closing connection");
        }
    }

    /// <summary>Close database connection (async).</summary>
    public Task CloseAsync()
    {
        Close();
        return Task.CompletedTask;
    }

    /// <summary>Begin a new transaction.</summary>
    public Task BeginTransactionAsync()
    {
        if (_connectionInfo.AutoCommit)
            throw new InvalidOperationException("Cannot begin transaction when auto-commit is enabled.");
        if (_connection?.State != ConnectionState.Open)
            throw new InvalidOperationException("Connection is not open");
        return Task.CompletedTask;
    }

    /// <summary>Cancel any running query.</summary>
    public void CancelQuery() { }

    private void SetUserAccessLevelForSqlite()
    {
        Logger.Debug("Setting access level for SQLite (file-based: full access)");
        _connectionInfo.Permissions = new UserPermissions
        {
            Username = _connectionInfo.Username ?? "sqlite",
            AccessLevel = UserAccessLevel.DBA
        };
    }

    private Task SetAutoCommitModeAsync(bool autoCommit)
    {
        Logger.Debug("Setting auto-commit mode: {AutoCommit}", autoCommit);
        return Task.CompletedTask;
    }

    private static bool IsModifyingSql(string sql)
    {
        var sqlUpper = sql.Trim().ToUpperInvariant();
        var isSelect = sqlUpper.StartsWith("SELECT") || sqlUpper.StartsWith("WITH") || sqlUpper.StartsWith("VALUES");
        if (!isSelect) return true;
        var ddlKeywords = new[] { "CREATE", "DROP", "ALTER", "TRUNCATE", "GRANT", "REVOKE" };
        return ddlKeywords.Any(kw => System.Text.RegularExpressions.Regex.IsMatch(sqlUpper, $@"\b{kw}\b"));
    }

    /// <summary>Commit current transaction.</summary>
    public async Task CommitAsync()
    {
        if (_connectionInfo.AutoCommit) throw new InvalidOperationException("Cannot commit when auto-commit is enabled.");
        if (_connection?.State != ConnectionState.Open) throw new InvalidOperationException("Connection is not open");
        await using var cmd = _connection!.CreateCommand();
        cmd.CommandText = "COMMIT";
        await cmd.ExecuteNonQueryAsync();
        Logger.Info("Transaction committed successfully");
    }

    /// <summary>Rollback current transaction.</summary>
    public async Task RollbackAsync()
    {
        if (_connectionInfo.AutoCommit) throw new InvalidOperationException("Cannot rollback when auto-commit is enabled.");
        if (_connection?.State != ConnectionState.Open) throw new InvalidOperationException("Connection is not open");
        await using var cmd = _connection!.CreateCommand();
        cmd.CommandText = "ROLLBACK";
        await cmd.ExecuteNonQueryAsync();
        Logger.Info("Transaction rolled back successfully");
    }

    /// <summary>Dispose connection.</summary>
    public void Dispose()
    {
        if (_disposed) return;
        Logger.Debug("Disposing SQLiteConnectionManager");
        Close();
        _connection?.Dispose();
        _disposed = true;
    }

    /// <summary>Whether the connection is open.</summary>
    public bool IsConnected => _connection != null && _connection.State == ConnectionState.Open;

    /// <summary>Reconnect to the database.</summary>
    public async Task<bool> ReconnectAsync()
    {
        Logger.Info("Attempting to reconnect to SQLite");
        try
        {
            if (_connection != null)
            {
                try { await _connection.CloseAsync(); _connection.Dispose(); } catch { /* ignore */ }
                _connection = null;
            }
            await OpenAsync();
            Logger.Info("Reconnection successful");
            return true;
        }
        catch (Exception ex)
        {
            Logger.Error(ex, "Reconnection failed");
            throw new InvalidOperationException("Connection is not open and reconnection failed: " + ex.Message, ex);
        }
    }

    /// <summary>Ensure connection is active, reconnecting if necessary.</summary>
    public async Task<bool> EnsureConnectedAsync()
    {
        if (IsConnected)
        {
            try
            {
                await using var cmd = _connection!.CreateCommand();
                cmd.CommandText = "SELECT 1";
                cmd.CommandTimeout = 5;
                await cmd.ExecuteScalarAsync();
                return true;
            }
            catch (Exception ex)
            {
                Logger.Warn(ex, "Connection appears dead, attempting reconnection");
            }
        }
        return await ReconnectAsync();
    }

    #region Factory Methods (IConnectionManager)

    DbCommand IConnectionManager.CreateCommand(string sql)
    {
        if (_connection == null || _connection.State != ConnectionState.Open)
            throw new InvalidOperationException("Connection is not open. Call OpenAsync first.");
        var command = _connection.CreateCommand();
        command.CommandText = sql;
        command.CommandTimeout = _connectionInfo.ConnectionTimeout;
        return command;
    }

    public DbParameter CreateParameter(string name, object? value)
    {
        var p = new SqliteParameter();
        var paramName = name?.StartsWith("@") == true ? name : "@" + name;
        p.ParameterName = paramName;
        p.Value = value ?? DBNull.Value;
        return p;
    }

    public DbDataAdapter CreateDataAdapter(DbCommand command)
    {
        if (command is not SqliteCommand sqliteCommand)
            throw new ArgumentException("Command must be SqliteCommand", nameof(command));
        return new SqliteDataAdapterWrapper(sqliteCommand);
    }

    public DbConnection GetUnderlyingConnection()
    {
        if (_connection == null)
            throw new InvalidOperationException("Connection has not been established.");
        return _connection;
    }

    #endregion

    #region Helper methods (use MetadataHandler – provider/version set by app)

    /// <summary>Get list of schemas (SQLite: main only).</summary>
    public async Task<List<string>> GetSchemasAsync()
    {
        var metadataHandler = App.MetadataHandler ?? throw new InvalidOperationException("MetadataHandler not initialized");
        var sql = metadataHandler.GetRequiredStatement("GetSchemasSimple");
        var dataTable = await ExecuteQueryAsync(sql);
        return dataTable.AsEnumerable().Select(row => row[0]?.ToString() ?? string.Empty).ToList();
    }

    /// <summary>Get list of tables (optionally for a schema).</summary>
    public async Task<List<string>> GetTablesAsync(string? schema = null)
    {
        var metadataHandler = App.MetadataHandler ?? throw new InvalidOperationException("MetadataHandler not initialized");
        string sql;
        if (schema != null)
            sql = metadataHandler.GetRequiredStatement("GetTablesForSchemaSimple").Replace("?", $"'{schema}'");
        else
            sql = metadataHandler.GetRequiredStatement("GetAllTablesSimple");
        var dataTable = await ExecuteQueryAsync(sql);
        return dataTable.AsEnumerable().Select(row => row[0]?.ToString() ?? string.Empty).ToList();
    }

    /// <summary>Get columns for a table.</summary>
    public async Task<DataTable> GetTableColumnsAsync(string tableName)
    {
        var metadataHandler = App.MetadataHandler ?? throw new InvalidOperationException("MetadataHandler not initialized");
        var sqlTemplate = metadataHandler.GetRequiredStatement("SERVICE_GetTableColumnsBasic");
        var sql = sqlTemplate.Replace("?", $"'{tableName}'");
        return await ExecuteQueryAsync(sql);
    }

    /// <summary>Get list of views.</summary>
    public async Task<List<string>> GetViewsAsync(string? schema = null)
    {
        var metadataHandler = App.MetadataHandler ?? throw new InvalidOperationException("MetadataHandler not initialized");
        string sql;
        if (schema != null)
            sql = metadataHandler.GetRequiredStatement("GetViewsForSchemaSimple").Replace("?", $"'{schema}'");
        else
            sql = metadataHandler.GetRequiredStatement("GetAllViewsSimple");
        var dataTable = await ExecuteQueryAsync(sql);
        return dataTable.AsEnumerable().Select(row => row[0]?.ToString() ?? string.Empty).ToList();
    }

    /// <summary>Get list of stored procedures (SQLite has none; return empty).</summary>
    public Task<List<string>> GetStoredProceduresAsync(string? schema = null) => Task.FromResult(new List<string>());

    /// <summary>Get view definition.</summary>
    public async Task<string> GetViewDefinitionAsync(string viewName)
    {
        var metadataHandler = App.MetadataHandler ?? throw new InvalidOperationException("MetadataHandler not initialized");
        var sqlTemplate = metadataHandler.GetRequiredStatement("GetViewText");
        var sql = sqlTemplate.Replace("?", $"'{viewName}'");
        var result = await ExecuteScalarAsync(sql);
        return result?.ToString() ?? string.Empty;
    }

    /// <summary>Get server/database version.</summary>
    public string GetServerVersion()
    {
        if (_connection == null) return "Not connected";
        try
        {
            return _connection.ServerVersion ?? "SQLite 3";
        }
        catch (Exception ex)
        {
            Logger.Warn(ex, "Failed to get server version");
            return "SQLite 3";
        }
    }

    #endregion
}
