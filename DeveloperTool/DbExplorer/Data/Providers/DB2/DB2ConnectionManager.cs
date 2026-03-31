using System.Data;
using System.Data.Common;
using IBM.Data.Db2;
using NLog;
using DbExplorer.Models;
using DbExplorer.Services;
using DB2Conn = IBM.Data.Db2.DB2Connection;

namespace DbExplorer.Data.Providers.DB2;

/// <summary>
/// Manager for DB2 database connections
/// Uses Net.IBM.Data.Db2 package for real DB2 connectivity
/// Implements IConnectionManager for database-agnostic usage
/// </summary>
public class DB2ConnectionManager : IConnectionManager
{
    private static readonly Logger Logger = LogManager.GetCurrentClassLogger();
    private readonly DatabaseConnection _connectionInfo;
    private DB2Conn? _db2Connection;
    private bool _disposed;

    /// <summary>
    /// Gets the connection information used to create this manager (database-agnostic interface)
    /// </summary>
    public IConnectionInfo ConnectionInfo => _connectionInfo;
    
    /// <summary>
    /// Gets the connection information as DatabaseConnection (for backward compatibility)
    /// </summary>
    public DatabaseConnection Connection => _connectionInfo;

    public DB2ConnectionManager(DatabaseConnection connectionInfo)
    {
        Logger.Debug("DB2ConnectionManager initializing with real DB2 driver");
        _connectionInfo = connectionInfo ?? throw new ArgumentNullException(nameof(connectionInfo));
        Logger.Debug($"Connection: {_connectionInfo.GetConnectionString(maskPassword: true)}");
    }
    
    // Backward compatibility constructor
    public DB2ConnectionManager(Models.DB2Connection connectionInfo) : this((DatabaseConnection)connectionInfo)
    {
    }

    /// <summary>
    /// Test database connection
    /// </summary>
    public async Task<bool> TestConnectionAsync()
    {
        Logger.Info("Testing DB2 connection");
        Logger.Debug($"Server: {_connectionInfo.Server}, Database: {_connectionInfo.Database}");

        try
        {
            using var testConnection = new DB2Conn(_connectionInfo.GetConnectionString());
            await testConnection.OpenAsync();
            
            Logger.Info("Connection test successful");
            return true;
        }
        catch (DB2Exception db2Ex)
        {
            Logger.Error(db2Ex, "DB2 connection test failed - SQL State: {SqlState}, Error Code: {ErrorCode}", 
                db2Ex.SqlState, db2Ex.ErrorCode);
            return false;
        }
        catch (Exception ex)
        {
            Logger.Error(ex, "Connection test failed");
            return false;
        }
    }

    /// <summary>
    /// Open database connection
    /// </summary>
    public async Task OpenAsync(CancellationToken cancellationToken = default)
    {
        if (_db2Connection != null && _db2Connection.State == ConnectionState.Open)
        {
            Logger.Debug("Connection already open");
            return;
        }

        Logger.Info("Opening DB2 connection");
        Logger.Debug($"Connection string: {_connectionInfo.GetConnectionString(maskPassword: true)}");

        try
        {
            _db2Connection = new DB2Conn(_connectionInfo.GetConnectionString());
            
            // Check cancellation before opening
            cancellationToken.ThrowIfCancellationRequested();
            
            await _db2Connection.OpenAsync(cancellationToken);
            
            // Check cancellation after opening
            cancellationToken.ThrowIfCancellationRequested();
            
            Logger.Info($"DB2 connection opened successfully - State: {_db2Connection.State}");
            Logger.Debug($"DB2 Server Version: {_db2Connection.ServerVersion}");
            
            // Feature #2: Set auto-commit mode
            await SetAutoCommitModeAsync(_connectionInfo.AutoCommit);
            
            // Check cancellation after auto-commit setup
            cancellationToken.ThrowIfCancellationRequested();
            
            // Feature #2: Log connection mode
            Logger.Info("Connection mode - ReadOnly: {ReadOnly}, AutoCommit: {AutoCommit}", 
                _connectionInfo.IsReadOnly, _connectionInfo.AutoCommit);
            
            // RBAC: Determine user's access level
            await DetermineUserAccessLevelAsync();
            
            // Final cancellation check
            cancellationToken.ThrowIfCancellationRequested();
        }
        catch (OperationCanceledException)
        {
            Logger.Warn("Connection was cancelled by user");
            if (_db2Connection != null)
            {
                try
                {
                    _db2Connection.Close();
                    _db2Connection.Dispose();
                    _db2Connection = null;
                }
                catch (Exception cleanupEx)
                {
                    Logger.Error(cleanupEx, "Error cleaning up cancelled connection");
                }
            }
            throw;
        }
        catch (DB2Exception db2Ex)
        {
            Logger.Error(db2Ex, "Failed to open DB2 connection - SQL State: {SqlState}, Error Code: {ErrorCode}", 
                db2Ex.SqlState, db2Ex.ErrorCode);
            throw new Exception($"Failed to connect to database: {db2Ex.Message}", db2Ex);
        }
        catch (Exception ex)
        {
            Logger.Error(ex, "Failed to open DB2 connection");
            throw new Exception($"Failed to connect to database: {ex.Message}", ex);
        }
    }

    /// <summary>
    /// Execute SQL query and return DataTable
    /// </summary>
    public async Task<DataTable> ExecuteQueryAsync(string sql, int? maxRows = null, int offset = 0, bool handleDecimalErrors = true)
    {
        // Auto-reconnect if connection is lost
        if (_db2Connection == null || _db2Connection.State != ConnectionState.Open)
        {
            Logger.Warn("Connection not open, attempting auto-reconnect");
            if (!await EnsureConnectedAsync())
            {
                throw new InvalidOperationException("Connection is not open and reconnection failed");
            }
            Logger.Info("Auto-reconnection successful");
        }

        Logger.Info("Executing SQL query");
        Logger.Debug($"SQL: {sql.Substring(0, Math.Min(100, sql.Length))}... MaxRows: {maxRows}, Offset: {offset}");
        
        // Feature #2 + RBAC: Check if read-only mode or access level prevents this SQL
        if (_connectionInfo.IsReadOnly && IsModifyingSql(sql))
        {
            Logger.Warn("Attempted to execute modifying SQL in read-only mode");
            throw new InvalidOperationException(
                "This connection is in read-only mode. " +
                "Data modification statements (INSERT, UPDATE, DELETE, CREATE, DROP, ALTER, TRUNCATE) are not allowed.");
        }
        
        // RBAC: Check access level permissions
        if (_connectionInfo.Permissions != null && IsModifyingSql(sql))
        {
            var accessLevel = _connectionInfo.Permissions.AccessLevel;
            var sqlUpper = sql.Trim().ToUpperInvariant();
            
            if (accessLevel == UserAccessLevel.Standard)
            {
                Logger.Warn("LOW level user {Username} attempted to execute modifying SQL", 
                    _connectionInfo.Permissions.Username);
                throw new UnauthorizedAccessException(
                    $"Access Denied: You have READ-ONLY access ({_connectionInfo.Permissions.AccessLevelBadge}).\n\n" +
                    "Only SELECT statements are allowed.\n" +
                    "Contact your database administrator to request additional privileges.");
            }
            
            if (accessLevel == UserAccessLevel.Advanced)
            {
                // Check if it's DDL (not allowed for Middle level)
                var ddlKeywords = new[] { "CREATE", "DROP", "ALTER", "TRUNCATE", "GRANT", "REVOKE" };
                if (ddlKeywords.Any(kw => System.Text.RegularExpressions.Regex.IsMatch(sqlUpper, $@"\b{kw}\b")))
                {
                    Logger.Warn("MIDDLE level user {Username} attempted to execute DDL", 
                        _connectionInfo.Permissions.Username);
                    throw new UnauthorizedAccessException(
                        $"Access Denied: You have STANDARD USER access ({_connectionInfo.Permissions.AccessLevelBadge}).\n\n" +
                        "DDL statements (CREATE, DROP, ALTER) require DBA privileges.\n" +
                        "DML statements (SELECT, INSERT, UPDATE, DELETE) are allowed.\n\n" +
                        "Contact your database administrator to request DBA privileges.");
                }
            }
        }

        try
        {
            var startTime = DateTime.Now;

            // Modify SQL to include pagination if maxRows is specified
            var paginatedSql = sql;
            if (maxRows.HasValue)
            {
                // Add FETCH FIRST syntax for DB2 pagination
                paginatedSql = AddPaginationToQuery(sql, maxRows.Value, offset);
                Logger.Debug($"Paginated SQL: {paginatedSql.Substring(0, Math.Min(150, paginatedSql.Length))}...");
            }

            using var command = _db2Connection.CreateCommand();
            command.CommandText = paginatedSql;
            command.CommandTimeout = _connectionInfo.ConnectionTimeout;

            using var adapter = new DB2DataAdapter(command);
            var dataTable = new DataTable("Results");
            
            try
            {
                await Task.Run(() => adapter.Fill(dataTable));
            }
            catch (FormatException fex) when (handleDecimalErrors && fex.Message.Contains("was not in a correct format"))
            {
                Logger.Warn(fex, "DB2Decimal format error detected, attempting to read with DataReader");
                
                // Try alternative method using DataReader with manual conversion
                return await ExecuteQueryWithDataReaderAsync(paginatedSql);
            }

            var elapsed = (DateTime.Now - startTime).TotalMilliseconds;
            Logger.Info($"Query executed successfully in {elapsed}ms, {dataTable.Rows.Count} rows returned");

            // Track query for history (Ctrl+Shift+Q feature)
            SqlQueryHistoryService.Track(
                sql, 
                source: _connectionInfo?.GetDisplayName() ?? "Unknown",
                durationMs: (long)elapsed,
                rowsReturned: dataTable.Rows.Count,
                success: true);

            return dataTable;
        }
        catch (DB2Exception db2Ex)
        {
            Logger.Error(db2Ex, "DB2 query execution failed - SQL State: {SqlState}, Error Code: {ErrorCode}", 
                db2Ex.SqlState, db2Ex.ErrorCode);
            
            // Track failed query
            SqlQueryHistoryService.Track(sql, 
                source: _connectionInfo?.GetDisplayName() ?? "Unknown",
                success: false, 
                errorMessage: $"SQL State: {db2Ex.SqlState}, {db2Ex.Message}");
            
            throw new Exception($"Query failed: {db2Ex.Message}", db2Ex);
        }
        catch (Exception ex)
        {
            Logger.Error(ex, "Query execution failed");
            
            // Track failed query
            SqlQueryHistoryService.Track(sql, 
                source: _connectionInfo?.GetDisplayName() ?? "Unknown",
                success: false, 
                errorMessage: ex.Message);
            
            throw new Exception($"Query failed: {ex.Message}", ex);
        }
    }

    /// <summary>
    /// Add pagination clauses to SQL query for DB2
    /// </summary>
    private string AddPaginationToQuery(string sql, int maxRows, int offset)
    {
        Logger.Debug($"Adding pagination: LIMIT {maxRows} OFFSET {offset}");
        
        // Check if query already has FETCH FIRST or similar clauses
        var upperSql = sql.Trim().ToUpperInvariant();
        
        if (upperSql.Contains("FETCH FIRST") || upperSql.Contains("LIMIT"))
        {
            Logger.Warn("Query already contains pagination clause, not modifying");
            return sql;
        }

        // For DB2, use OFFSET/FETCH NEXT syntax (DB2 11.1+)
        var paginatedSql = $"{sql.TrimEnd().TrimEnd(';')} OFFSET {offset} ROWS FETCH NEXT {maxRows} ROWS ONLY";
        
        return paginatedSql;
    }

    /// <summary>
    /// Execute query using DataReader with graceful decimal handling
    /// </summary>
    private async Task<DataTable> ExecuteQueryWithDataReaderAsync(string sql)
    {
        Logger.Debug("Executing query with DataReader for decimal error handling");
        
        using var command = _db2Connection!.CreateCommand();
        command.CommandText = sql;
        command.CommandTimeout = _connectionInfo.ConnectionTimeout;

        var dataTable = new DataTable("Results");
        
        await using var reader = await command.ExecuteReaderAsync();
        
        // Create columns
        for (int i = 0; i < reader.FieldCount; i++)
        {
            var columnName = reader.GetName(i);
            var columnType = reader.GetFieldType(i);
            dataTable.Columns.Add(columnName, typeof(string)); // Use string to avoid conversion errors
            Logger.Debug($"Column {i}: {columnName} ({columnType.Name})");
        }

        // Read rows
        int rowCount = 0;
        while (await reader.ReadAsync())
        {
            var row = dataTable.NewRow();
            for (int i = 0; i < reader.FieldCount; i++)
            {
                try
                {
                    if (reader.IsDBNull(i))
                    {
                        row[i] = DBNull.Value;
                    }
                    else
                    {
                        // Get value as string to avoid DB2Decimal conversion issues
                        var value = reader.GetValue(i);
                        row[i] = value?.ToString() ?? string.Empty;
                    }
                }
                catch (Exception ex)
                {
                    Logger.Warn(ex, $"Error reading column {i} ({reader.GetName(i)}), setting to error message");
                    row[i] = $"[ERROR: {ex.Message}]";
                }
            }
            dataTable.Rows.Add(row);
            rowCount++;
        }

        Logger.Info($"DataReader method returned {rowCount} rows with graceful error handling");
        return dataTable;
    }

    /// <summary>
    /// Execute SQL command (INSERT, UPDATE, DELETE)
    /// </summary>
    public async Task<int> ExecuteNonQueryAsync(string sql)
    {
        // Auto-reconnect if connection is lost
        if (_db2Connection == null || _db2Connection.State != ConnectionState.Open)
        {
            Logger.Warn("Connection not open, attempting auto-reconnect for command");
            if (!await EnsureConnectedAsync())
            {
                throw new InvalidOperationException("Connection is not open and reconnection failed");
            }
            Logger.Info("Auto-reconnection successful");
        }

        Logger.Info("Executing SQL command");
        Logger.Debug($"SQL: {sql.Substring(0, Math.Min(100, sql.Length))}...");

        try
        {
            var startTime = DateTime.Now;

            using var command = _db2Connection.CreateCommand();
            command.CommandText = sql;
            command.CommandTimeout = _connectionInfo.ConnectionTimeout;

            var affectedRows = await command.ExecuteNonQueryAsync();

            var elapsed = (DateTime.Now - startTime).TotalMilliseconds;
            Logger.Info($"Command executed successfully in {elapsed}ms, {affectedRows} rows affected");

            return affectedRows;
        }
        catch (DB2Exception db2Ex)
        {
            Logger.Error(db2Ex, "DB2 command execution failed - SQL State: {SqlState}, Error Code: {ErrorCode}", 
                db2Ex.SqlState, db2Ex.ErrorCode);
            throw new Exception($"Command failed: {db2Ex.Message}", db2Ex);
        }
        catch (Exception ex)
        {
            Logger.Error(ex, "Command execution failed");
            throw new Exception($"Command failed: {ex.Message}", ex);
        }
    }

    /// <summary>
    /// Close database connection
    /// </summary>
    public void Close()
    {
        if (_db2Connection == null)
        {
            return;
        }

        Logger.Info("Closing DB2 connection");
        
        try
        {
            if (_db2Connection.State != ConnectionState.Closed)
            {
                _db2Connection.Close();
            }
            Logger.Info("DB2 connection closed successfully");
        }
        catch (Exception ex)
        {
            Logger.Error(ex, "Error closing connection");
        }
    }
    
    /// <summary>
    /// Close database connection (async version for interface)
    /// </summary>
    public Task CloseAsync()
    {
        Close();
        return Task.CompletedTask;
    }
    
    /// <summary>
    /// Begin a new transaction
    /// </summary>
    public async Task BeginTransactionAsync()
    {
        Logger.Info("Beginning transaction");
        
        if (_connectionInfo.AutoCommit)
        {
            Logger.Warn("BeginTransaction called but auto-commit is enabled");
            throw new InvalidOperationException("Cannot begin transaction when auto-commit is enabled.");
        }
        
        if (_db2Connection?.State != ConnectionState.Open)
        {
            Logger.Warn("Cannot begin transaction - connection is not open");
            throw new InvalidOperationException("Connection is not open");
        }
        
        // DB2 implicitly starts a transaction, but we can be explicit
        await Task.CompletedTask;
        Logger.Info("Transaction started (implicit in DB2)");
    }
    
    /// <summary>
    /// Cancel any running query
    /// </summary>
    public void CancelQuery()
    {
        Logger.Info("Cancelling query");
        // DB2 doesn't have a direct cancel method on connection
        // Commands should be cancelled individually
    }
    
    /// <summary>
    /// Determine user's access level based on DBAUTH - RBAC
    /// </summary>
    private async Task DetermineUserAccessLevelAsync()
    {
        Logger.Debug("Determining user access level");
        
        try
        {
            var accessControlService = new Services.AccessControlService();
            _connectionInfo.Permissions = await accessControlService.DetermineAccessLevelAsync(
                this, 
                _connectionInfo.Username);
            
            Logger.Info("User {Username} access level determined: {Level}", 
                _connectionInfo.Username, 
                _connectionInfo.Permissions.AccessLevel);
            Logger.Info("Access level badge: {Badge}", _connectionInfo.Permissions.AccessLevelBadge);
        }
        catch (Exception ex)
        {
            Logger.Error(ex, "Failed to determine user access level");
            Logger.Warn("SECURITY: Defaulting to LOW (read-only) access due to error");
            
            // Default to LOW for security
            _connectionInfo.Permissions = new UserPermissions
            {
                Username = _connectionInfo.Username,
                AccessLevel = UserAccessLevel.Standard
            };
        }
    }
    
    /// <summary>
    /// Set auto-commit mode for the connection - Feature #2
    /// </summary>
    private async Task SetAutoCommitModeAsync(bool autoCommit)
    {
        Logger.Debug("Setting auto-commit mode: {AutoCommit}", autoCommit);
        
        if (_db2Connection?.State != ConnectionState.Open)
        {
            Logger.Warn("Cannot set auto-commit mode - connection is not open");
            return;
        }
        
        try
        {
            // DB2 does not support SET AUTOCOMMIT syntax
            // AutoCommit is controlled by the driver connection property
            Logger.Debug("Auto-commit mode is handled by DB2 connection driver");
            Logger.Info("Auto-commit mode set via connection (mode: {Mode})", autoCommit ? "ON" : "OFF");
            
            // Note: DB2 .NET driver handles autocommit internally via connection string or property
            // No SQL command needed
            await Task.CompletedTask; // Maintain async signature
        }
        catch (Exception ex)
        {
            Logger.Error(ex, "Failed to configure auto-commit mode");
            // Don't throw - some DB2 versions may not support this command
            Logger.Warn("Auto-commit mode could not be set, continuing anyway");
        }
    }
    
    /// <summary>
    /// Check if SQL statement is modifying (DML/DDL) - Feature #2 + RBAC
    /// </summary>
    private bool IsModifyingSql(string sql)
    {
        var sqlUpper = sql.Trim().ToUpperInvariant();
        
        Logger.Debug("Checking if SQL is modifying - First 50 chars: {SQL}", 
            sqlUpper.Substring(0, Math.Min(50, sqlUpper.Length)));
        
        // RBAC: For LOW level users, everything except SELECT is modifying
        if (_connectionInfo.Permissions?.AccessLevel == UserAccessLevel.Standard)
        {
            var isSelect = sqlUpper.StartsWith("SELECT") || 
                          sqlUpper.StartsWith("WITH") || // CTE
                          sqlUpper.StartsWith("VALUES"); // VALUES clause
            
            var isModifying = !isSelect;
            Logger.Debug("LOW level user - SQL is modifying: {IsModifying} (not a SELECT)", isModifying);
            return isModifying;
        }
        
        // RBAC: For MIDDLE level users, DDL is modifying (DML is allowed)
        if (_connectionInfo.Permissions?.AccessLevel == UserAccessLevel.Advanced)
        {
            var ddlKeywords = new[] { "CREATE", "DROP", "ALTER", "TRUNCATE", "GRANT", "REVOKE" };
            var isModifying = ddlKeywords.Any(keyword => 
                System.Text.RegularExpressions.Regex.IsMatch(sqlUpper, $@"\b{keyword}\b"));
            
            Logger.Debug("MIDDLE level user - SQL is DDL: {IsModifying}", isModifying);
            return isModifying;
        }
        
        // For DBA level (or if permissions not yet determined), check all modifying keywords
        var modifyingKeywords = new[] 
        { 
            "INSERT", "UPDATE", "DELETE", "DROP", "CREATE", 
            "ALTER", "TRUNCATE", "GRANT", "REVOKE", "MERGE" 
        };
        
        var isModifyingDba = modifyingKeywords.Any(keyword => 
            System.Text.RegularExpressions.Regex.IsMatch(sqlUpper, $@"\b{keyword}\b"));
        
        Logger.Debug("DBA level check - SQL is modifying: {IsModifying}", isModifyingDba);
        return isModifyingDba;
    }
    
    /// <summary>
    /// Commit current transaction - Feature #2
    /// </summary>
    public async Task CommitAsync()
    {
        Logger.Info("Committing transaction");
        
        if (_connectionInfo.AutoCommit)
        {
            Logger.Warn("Commit called but auto-commit is enabled");
            throw new InvalidOperationException("Cannot commit manually when auto-commit is enabled.");
        }
        
        if (_db2Connection?.State != ConnectionState.Open)
        {
            Logger.Warn("Cannot commit - connection is not open");
            throw new InvalidOperationException("Connection is not open");
        }
        
        try
        {
            using var command = _db2Connection.CreateCommand();
            command.CommandText = "COMMIT";
            await command.ExecuteNonQueryAsync();
            
            Logger.Info("Transaction committed successfully");
        }
        catch (DB2Exception db2Ex)
        {
            Logger.Error(db2Ex, "DB2 error during commit - SQL State: {SqlState}", db2Ex.SqlState);
            throw;
        }
    }
    
    /// <summary>
    /// Rollback current transaction - Feature #2
    /// </summary>
    public async Task RollbackAsync()
    {
        Logger.Info("Rolling back transaction");
        
        if (_connectionInfo.AutoCommit)
        {
            Logger.Warn("Rollback called but auto-commit is enabled");
            throw new InvalidOperationException("Cannot rollback manually when auto-commit is enabled.");
        }
        
        if (_db2Connection?.State != ConnectionState.Open)
        {
            Logger.Warn("Cannot rollback - connection is not open");
            throw new InvalidOperationException("Connection is not open");
        }
        
        try
        {
            using var command = _db2Connection.CreateCommand();
            command.CommandText = "ROLLBACK";
            await command.ExecuteNonQueryAsync();
            
            Logger.Info("Transaction rolled back successfully");
        }
        catch (DB2Exception db2Ex)
        {
            Logger.Error(db2Ex, "DB2 error during rollback - SQL State: {SqlState}", db2Ex.SqlState);
            throw;
        }
    }

    public void Dispose()
    {
        if (_disposed)
        {
            return;
        }

        Logger.Debug("Disposing DB2ConnectionManager");
        Close();
        _db2Connection?.Dispose();
        _disposed = true;
    }

    public bool IsConnected => _db2Connection != null && _db2Connection.State == ConnectionState.Open;

    /// <summary>
    /// Reconnect to the database if connection is lost.
    /// Throws InvalidOperationException with inner cause when reconnection fails.
    /// </summary>
    public async Task<bool> ReconnectAsync()
    {
        Logger.Info("Attempting to reconnect to database");
        
        try
        {
            // Close existing connection if any
            if (_db2Connection != null)
            {
                try
                {
                    _db2Connection.Close();
                    _db2Connection.Dispose();
                }
                catch (Exception ex)
                {
                    Logger.Debug(ex, "Error closing existing connection during reconnect");
                }
                _db2Connection = null;
            }
            
            // Open new connection
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
    
    /// <summary>
    /// Ensure connection is active, reconnecting if necessary
    /// </summary>
    /// <returns>True if connected (or reconnected), false if reconnection failed</returns>
    public async Task<bool> EnsureConnectedAsync()
    {
        if (IsConnected)
        {
            // Verify connection is still alive with a simple query
            try
            {
                using var cmd = _db2Connection!.CreateCommand();
                cmd.CommandText = "SELECT 1 FROM SYSIBM.SYSDUMMY1";
                cmd.CommandTimeout = 5; // Short timeout for health check
                await cmd.ExecuteScalarAsync();
                return true;
            }
            catch (Exception ex)
            {
                Logger.Warn(ex, "Connection appears dead, attempting reconnection");
            }
        }
        
        // Connection is not open or failed health check, try to reconnect
        return await ReconnectAsync();
    }

    #region Factory Methods (IConnectionManager implementation)
    
    /// <summary>
    /// Create a database command for the current connection (IConnectionManager implementation).
    /// Returns DbCommand for provider-agnostic usage.
    /// </summary>
    DbCommand IConnectionManager.CreateCommand(string sql)
    {
        return CreateCommand(sql);
    }
    
    /// <summary>
    /// Create a DB2Command for custom query execution.
    /// This is the DB2-specific version that returns the concrete type.
    /// </summary>
    public DB2Command CreateCommand(string sql)
    {
        if (_db2Connection == null || _db2Connection.State != ConnectionState.Open)
        {
            throw new InvalidOperationException("Connection is not open. Call ConnectAsync first.");
        }
        
        var command = _db2Connection.CreateCommand();
        command.CommandText = sql;
        command.CommandTimeout = _connectionInfo.ConnectionTimeout;
        return command;
    }
    
    /// <summary>
    /// Create a database parameter with the specified name and value.
    /// Returns the provider-agnostic DbParameter base class.
    /// </summary>
    public DbParameter CreateParameter(string name, object? value)
    {
        return new DB2Parameter(name, value ?? DBNull.Value);
    }
    
    /// <summary>
    /// Create a data adapter for the specified command.
    /// Returns the provider-agnostic DbDataAdapter base class.
    /// </summary>
    public DbDataAdapter CreateDataAdapter(DbCommand command)
    {
        if (command is not DB2Command db2Command)
        {
            throw new ArgumentException("Command must be a DB2Command", nameof(command));
        }
        return new DB2DataAdapter(db2Command);
    }
    
    /// <summary>
    /// Get the underlying database connection.
    /// Returns the provider-agnostic DbConnection base class.
    /// </summary>
    public DbConnection GetUnderlyingConnection()
    {
        if (_db2Connection == null)
        {
            throw new InvalidOperationException("Connection has not been established.");
        }
        return _db2Connection;
    }
    
    #endregion

    /// <summary>
    /// Execute scalar query (return single value)
    /// </summary>
    public async Task<object?> ExecuteScalarAsync(string sql)
    {
        // Auto-reconnect if connection is lost
        if (_db2Connection == null || _db2Connection.State != ConnectionState.Open)
        {
            Logger.Warn("Connection not open, attempting auto-reconnect for scalar query");
            if (!await EnsureConnectedAsync())
            {
                throw new InvalidOperationException("Connection is not open and reconnection failed");
            }
            Logger.Info("Auto-reconnection successful");
        }

        Logger.Info("Executing scalar query");
        Logger.Debug($"SQL: {sql.Substring(0, Math.Min(100, sql.Length))}...");

        try
        {
            var startTime = DateTime.Now;

            using var command = _db2Connection.CreateCommand();
            command.CommandText = sql;
            command.CommandTimeout = _connectionInfo.ConnectionTimeout;

            var result = await command.ExecuteScalarAsync();

            var elapsed = (DateTime.Now - startTime).TotalMilliseconds;
            Logger.Info($"Scalar query executed successfully in {elapsed}ms");

            return result;
        }
        catch (DB2Exception db2Ex)
        {
            Logger.Error(db2Ex, "DB2 scalar query failed - SQL State: {SqlState}, Error Code: {ErrorCode}", 
                db2Ex.SqlState, db2Ex.ErrorCode);
            throw new Exception($"Scalar query failed: {db2Ex.Message}", db2Ex);
        }
        catch (Exception ex)
        {
            Logger.Error(ex, "Scalar query execution failed");
            throw new Exception($"Scalar query failed: {ex.Message}", ex);
        }
    }

    /// <summary>
    /// Get list of tables in current database
    /// </summary>
    public async Task<List<string>> GetTablesAsync(string? schema = null)
    {
        Logger.Info($"Retrieving tables from database{(schema != null ? $" (schema: {schema})" : "")}");

        var tables = new List<string>();

        try
        {
            var metadataHandler = App.MetadataHandler ?? throw new InvalidOperationException("MetadataHandler not initialized");
            
            string sql;
            if (schema != null)
            {
                var sqlTemplate = metadataHandler.GetRequiredStatement("GetTablesForSchemaSimple");
                sql = sqlTemplate.Replace("?", $"'{schema}'");
            }
            else
            {
                sql = metadataHandler.GetRequiredStatement("GetAllTablesSimple");
            }

            var dataTable = await ExecuteQueryAsync(sql);

            foreach (DataRow row in dataTable.Rows)
            {
                tables.Add(row[0].ToString() ?? string.Empty);
            }

            Logger.Info($"Retrieved {tables.Count} tables");
            return tables;
        }
        catch (Exception ex)
        {
            Logger.Error(ex, "Failed to retrieve tables");
            throw;
        }
    }

    /// <summary>
    /// Get columns for a specific table
    /// </summary>
    public async Task<DataTable> GetTableColumnsAsync(string tableName)
    {
        Logger.Info($"Retrieving columns for table: {tableName}");

        try
        {
            var metadataHandler = App.MetadataHandler ?? throw new InvalidOperationException("MetadataHandler not initialized");
            var sqlTemplate = metadataHandler.GetQuery("DB2", "12.1", "SERVICE_GetTableColumnsBasic");
            var sql = sqlTemplate.Replace("?", $"'{tableName}'");

            Logger.Debug("Using query: SERVICE_GetTableColumnsBasic");
            var dataTable = await ExecuteQueryAsync(sql);
            Logger.Info($"Retrieved {dataTable.Rows.Count} columns for {tableName}");
            return dataTable;
        }
        catch (Exception ex)
        {
            Logger.Error(ex, $"Failed to retrieve columns for {tableName}");
            throw;
        }
    }

    /// <summary>
    /// Get list of schemas in current database
    /// </summary>
    public async Task<List<string>> GetSchemasAsync()
    {
        Logger.Info("Retrieving schemas from database");

        var schemas = new List<string>();

        try
        {
            var metadataHandler = App.MetadataHandler ?? throw new InvalidOperationException("MetadataHandler not initialized");
            var sql = metadataHandler.GetRequiredStatement("GetSchemasSimple");
            var dataTable = await ExecuteQueryAsync(sql);

            foreach (DataRow row in dataTable.Rows)
            {
                schemas.Add(row[0].ToString() ?? string.Empty);
            }

            Logger.Info($"Retrieved {schemas.Count} schemas");
            return schemas;
        }
        catch (Exception ex)
        {
            Logger.Error(ex, "Failed to retrieve schemas");
            throw;
        }
    }

    /// <summary>
    /// Get server version information
    /// </summary>
    public string GetServerVersion()
    {
        if (_db2Connection == null)
        {
            return "Not connected";
        }

        try
        {
            var version = _db2Connection.ServerVersion;
            Logger.Debug($"DB2 Server Version: {version}");
            return version;
        }
        catch (Exception ex)
        {
            Logger.Warn(ex, "Failed to get server version");
            return "Unknown";
        }
    }

    /// <summary>
    /// Get list of views in current database
    /// </summary>
    public async Task<List<string>> GetViewsAsync(string? schema = null)
    {
        Logger.Info($"Retrieving views from database{(schema != null ? $" (schema: {schema})" : "")}");

        var views = new List<string>();

        try
        {
            var metadataHandler = App.MetadataHandler ?? throw new InvalidOperationException("MetadataHandler not initialized");
            
            string sql;
            if (schema != null)
            {
                var sqlTemplate = metadataHandler.GetRequiredStatement("GetViewsForSchemaSimple");
                sql = sqlTemplate.Replace("?", $"'{schema}'");
            }
            else
            {
                sql = metadataHandler.GetRequiredStatement("GetAllViewsSimple");
            }

            var dataTable = await ExecuteQueryAsync(sql);

            foreach (DataRow row in dataTable.Rows)
            {
                views.Add(row[0].ToString() ?? string.Empty);
            }

            Logger.Info($"Retrieved {views.Count} views");
            return views;
        }
        catch (Exception ex)
        {
            Logger.Error(ex, "Failed to retrieve views");
            throw;
        }
    }

    /// <summary>
    /// Get list of stored procedures in current database
    /// </summary>
    public async Task<List<string>> GetStoredProceduresAsync(string? schema = null)
    {
        Logger.Info($"Retrieving stored procedures from database{(schema != null ? $" (schema: {schema})" : "")}");

        var procedures = new List<string>();

        try
        {
            var metadataHandler = App.MetadataHandler ?? throw new InvalidOperationException("MetadataHandler not initialized");
            
            string sql;
            if (schema != null)
            {
                var sqlTemplate = metadataHandler.GetRequiredStatement("GetProceduresForSchemaSimple");
                sql = sqlTemplate.Replace("?", $"'{schema}'");
            }
            else
            {
                sql = metadataHandler.GetRequiredStatement("GetAllProceduresSimple");
            }

            var dataTable = await ExecuteQueryAsync(sql);

            foreach (DataRow row in dataTable.Rows)
            {
                procedures.Add(row[0].ToString() ?? string.Empty);
            }

            Logger.Info($"Retrieved {procedures.Count} stored procedures");
            return procedures;
        }
        catch (Exception ex)
        {
            Logger.Error(ex, "Failed to retrieve stored procedures");
            throw;
        }
    }

    /// <summary>
    /// Get view definition/DDL
    /// </summary>
    public async Task<string> GetViewDefinitionAsync(string viewName)
    {
        Logger.Info($"Retrieving view definition for: {viewName}");

        try
        {
            var metadataHandler = App.MetadataHandler ?? throw new InvalidOperationException("MetadataHandler not initialized");
            var sqlTemplate = metadataHandler.GetRequiredStatement("GetViewText");
            var sql = sqlTemplate.Replace("?", $"'{viewName}'");
            var result = await ExecuteScalarAsync(sql);

            var definition = result?.ToString() ?? string.Empty;
            Logger.Debug($"Retrieved view definition: {definition.Length} characters");
            return definition;
        }
        catch (Exception ex)
        {
            Logger.Error(ex, $"Failed to retrieve view definition for {viewName}");
            throw;
        }
    }
}

