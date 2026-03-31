using Npgsql;
using Newtonsoft.Json;
using System.Data;
using System.Dynamic;
using System.Reflection;
using System.Text;

namespace DedgeCommon
{
    /// <summary>
    /// Implements the IDbHandler interface for PostgreSQL databases.
    /// Provides specific functionality for executing queries and managing connections
    /// to PostgreSQL databases within the Dedge system.
    /// </summary>
    /// <remarks>
    /// Features:
    /// - Executes SQL queries with error handling and logging
    /// - Supports transactions with automatic cleanup
    /// - Converts query results to various formats (JSON, XML, CSV, HTML)
    /// - Provides detailed SQL execution status information
    /// - Handles PostgreSQL-specific error codes and mappings
    /// - Supports GSSAPI/Kerberos authentication
    /// </remarks>
    /// <author>Geir Helge Starholm</author>
    internal class PostgresHandler : IDbHandler
    {
        private string _ConnectionString;
        private static readonly DedgeNLog _Logger = new DedgeNLog();
        private static bool test = DedgeNLog.EnableDatabaseLogging();
        private DbSqlError _DbSqlCode = 0;
        private int _DbSqlRowCount = 0;
        private int _DbSqlRowsAffected = 0;
        private string _SqlStatement = "";
        private DedgeConnection.ConnectionKey? _ConnectionKey;
        private bool _isDisposed = false;
        private NpgsqlConnection? _currentConnection;
        private NpgsqlTransaction? _currentTransaction;
        private bool _isInTransaction = false;
#pragma warning disable CS0414
        private bool _isAutoTransaction = false;
#pragma warning restore CS0414

        public string ConnectionString
        {
            get => _ConnectionString;
            set => _ConnectionString = value ?? throw new ArgumentNullException(nameof(value));
        }

        /// <summary>
        /// Initializes a new instance of the PostgresHandler class with a connection key.
        /// </summary>
        /// <param name="connectionKey">The connection key containing environment and application info</param>
        /// <param name="overrideUID">Optional username to override configured credentials</param>
        /// <param name="overridePWD">Optional password to override configured credentials</param>
        public PostgresHandler(DedgeConnection.ConnectionKey connectionKey, string? overrideUID = null, string? overridePWD = null)
        {
            try
            {
                _ConnectionKey = connectionKey;
                _SqlInfo = new SqlInfo();

                // Get access point info for logging
                var accessPoint = DedgeConnection.GetConnectionStringInfo(
                    connectionKey.Environment,
                    connectionKey.Application,
                    connectionKey.Version,
                    connectionKey.InstanceName);

                // Get connection string with optional credential override
                _ConnectionString = DedgeConnection.GetConnectionString(
                    connectionKey.Environment,
                    connectionKey.Application,
                    connectionKey.Version,
                    connectionKey.InstanceName,
                    overrideUID,
                    overridePWD);

                if (string.IsNullOrEmpty(_ConnectionString))
                {
                    throw new ArgumentNullException(nameof(_ConnectionString), "Connection string cannot be null or empty.");
                }

                // Log authentication details
                bool hasOverride = !string.IsNullOrEmpty(overrideUID) || !string.IsNullOrEmpty(overridePWD);
                bool useKerberos = accessPoint.AuthenticationType.Equals("Kerberos", StringComparison.OrdinalIgnoreCase);
                
                if (hasOverride)
                {
                    DedgeNLog.Trace($"PostgreSQL connection created with override credentials - Database: {accessPoint.DatabaseName}, Catalog: {accessPoint.CatalogName}, User: {overrideUID ?? accessPoint.UID}");
                }
                else if (useKerberos)
                {
                    string currentUser = $"{Environment.UserDomainName}\\{Environment.UserName}";
                    DedgeNLog.Trace($"PostgreSQL connection created using current Windows user - Database: {accessPoint.DatabaseName}, Catalog: {accessPoint.CatalogName}, User: {currentUser} (GSSAPI/Kerberos)");
                }
                else
                {
                    DedgeNLog.Trace($"PostgreSQL connection created with configured credentials - Database: {accessPoint.DatabaseName}, Catalog: {accessPoint.CatalogName}, User: {accessPoint.UID}");
                }
            }
            catch (Exception)
            {
                throw;
            }
        }

        /// <summary>
        /// Initializes a new instance using a direct connection string.
        /// </summary>
        /// <param name="connectionString">The connection string to use</param>
        public PostgresHandler(string connectionString)
        {
            try
            {
                _ConnectionString = connectionString ?? throw new ArgumentNullException(nameof(connectionString));
                _SqlInfo = new SqlInfo();

                // Parse connection string to log database and authentication info
                var parts = connectionString.Split(';', StringSplitOptions.RemoveEmptyEntries);
                var database = parts.FirstOrDefault(p => p.StartsWith("Database=", StringComparison.OrdinalIgnoreCase))?.Split('=')[1] ?? "Unknown";
                var hasIntegratedSecurity = parts.Any(p => p.StartsWith("Integrated Security", StringComparison.OrdinalIgnoreCase));
                var hasUsername = parts.Any(p => p.StartsWith("Username=", StringComparison.OrdinalIgnoreCase) || p.StartsWith("User Id=", StringComparison.OrdinalIgnoreCase));
                var username = parts.FirstOrDefault(p => p.StartsWith("Username=", StringComparison.OrdinalIgnoreCase))?.Split('=')[1] ??
                              parts.FirstOrDefault(p => p.StartsWith("User Id=", StringComparison.OrdinalIgnoreCase))?.Split('=')[1];
                
                if (hasIntegratedSecurity)
                {
                    string currentUser = $"{Environment.UserDomainName}\\{Environment.UserName}";
                    DedgeNLog.Trace($"PostgreSQL connection created using current Windows user - Database: {database}, User: {currentUser} (GSSAPI/Kerberos)");
                }
                else if (hasUsername && !string.IsNullOrEmpty(username))
                {
                    DedgeNLog.Trace($"PostgreSQL connection created with credentials - Database: {database}, User: {username}");
                }
                else
                {
                    DedgeNLog.Trace($"PostgreSQL connection created - Database: {database}");
                }
            }
            catch (Exception)
            {
                throw;
            }
        }

        public SqlInfo _SqlInfo { get; set; }

        public DedgeConnection.DatabaseProvider Provider => DedgeConnection.DatabaseProvider.POSTGRESQL;

        private DataTable ExecuteSqlMain(string sqlstring, bool throwException = false, bool externalTransactionHandling = false)
        {
            ThrowIfDisposed();
            DataTable dataTable = new DataTable();
            bool shouldHandleTransaction = !externalTransactionHandling && !_isInTransaction;

            DedgeNLog.Trace($"Executing PostgreSQL SQL Main - SQL: {sqlstring}, ThrowException: {throwException}, ExternalTransactionHandling: {externalTransactionHandling}");

            try
            {
                if (!_isInTransaction)
                {
                    _currentConnection = new NpgsqlConnection(_ConnectionString);
                    DedgeNLog.Trace($"Opening new PostgreSQL connection");
                    _currentConnection.Open();
                    DedgeNLog.Trace($"PostgreSQL connection opened successfully");
                }

                if (shouldHandleTransaction)
                {
                    DedgeNLog.Trace($"Beginning new transaction");
                    _currentTransaction = _currentConnection?.BeginTransaction();
                    _isInTransaction = true;
                    _isAutoTransaction = true;
                    DedgeNLog.Trace($"Transaction began successfully");
                }

                using (NpgsqlCommand command = new NpgsqlCommand(sqlstring, _currentConnection))
                {
                    if (_isInTransaction && _currentTransaction != null)
                    {
                        command.Transaction = _currentTransaction;
                    }

                    using (NpgsqlDataAdapter adapter = new NpgsqlDataAdapter(command))
                    {
                        adapter.Fill(dataTable);
                    }
                }

                if (shouldHandleTransaction)
                {
                    DedgeNLog.Trace($"Committing transaction");
                    _currentTransaction?.Commit();
                    _isInTransaction = false;
                    _isAutoTransaction = false;
                    DedgeNLog.Trace($"Transaction committed successfully");
                }

                if (!_isInTransaction && _currentConnection != null)
                {
                    DedgeNLog.Trace($"Closing connection");
                    _currentConnection.Close();
                    _currentConnection.Dispose();
                    _currentConnection = null;
                }

                _DbSqlCode = DbSqlError.Success;
                _DbSqlRowCount = dataTable.Rows.Count;
                _SqlStatement = sqlstring;

                UpdateSqlInfo();
                return dataTable;
            }
            catch (NpgsqlException ex)
            {
                _DbSqlCode = MapPostgresErrorToDbSqlError(ex);
                _SqlStatement = sqlstring;
                UpdateSqlInfo();

                DedgeNLog.Error(ex, $"PostgreSQL error executing SQL: {ex.Message}");

                if (shouldHandleTransaction && _currentTransaction != null)
                {
                    try
                    {
                        _currentTransaction.Rollback();
                        _isInTransaction = false;
                        _isAutoTransaction = false;
                    }
                    catch (Exception rollbackEx)
                    {
                        DedgeNLog.Error(rollbackEx, "Error during transaction rollback");
                    }
                }

                if (throwException)
                    throw;

                return dataTable;
            }
            catch (Exception ex)
            {
                _DbSqlCode = DbSqlError.UnknownError;
                _SqlStatement = sqlstring;
                UpdateSqlInfo();

                DedgeNLog.Error(ex, $"Error executing PostgreSQL SQL: {ex.Message}");

                if (shouldHandleTransaction && _currentTransaction != null)
                {
                    try
                    {
                        _currentTransaction.Rollback();
                        _isInTransaction = false;
                        _isAutoTransaction = false;
                    }
                    catch (Exception rollbackEx)
                    {
                        DedgeNLog.Error(rollbackEx, "Error during transaction rollback");
                    }
                }

                if (throwException)
                    throw;

                return dataTable;
            }
        }

        private DbSqlError MapPostgresErrorToDbSqlError(NpgsqlException ex)
        {
            // Map PostgreSQL error codes to DbSqlError
            // PostgreSQL error codes: https://www.postgresql.org/docs/current/errcodes-appendix.html
            
            string? sqlState = ex.SqlState;
            
            if (string.IsNullOrEmpty(sqlState))
            {
                return DbSqlError.UnknownError;
            }

            // Map common PostgreSQL error codes to available DbSqlError values
            return sqlState switch
            {
                "00000" => DbSqlError.Success,
                "02000" => DbSqlError.NotFound,  // no_data
                _ => DbSqlError.UnknownError  // All other errors mapped to UnknownError
            };
        }

        private void UpdateSqlInfo()
        {
            _SqlInfo.SqlCode = _DbSqlCode;
            _SqlInfo.RowCount = _DbSqlRowCount;
            _SqlInfo.RowsAffected = _DbSqlRowsAffected;
            _SqlInfo.SqlStatement = _SqlStatement;
        }

        public DataTable ExecuteQueryAsDataTable(string sqlstring, bool throwException = false, bool externalTransactionHandling = false)
        {
            return ExecuteSqlMain(sqlstring, throwException, externalTransactionHandling);
        }

        public string ExecuteQueryAsHtml(string sqlstring, bool throwException = false, bool externalTransactionHandling = false)
        {
            return ConvertDataTableToHtml(ExecuteSqlMain(sqlstring, throwException, externalTransactionHandling), throwException);
        }

        public string ExecuteQueryAsJson(string sqlstring, bool throwException = false, bool indented = true, bool externalTransactionHandling = false)
        {
            return ConvertDataTableToJson(ExecuteSqlMain(sqlstring, throwException, externalTransactionHandling), throwException, indented);
        }

        public string ExecuteQueryAsXml(string sqlstring, bool throwException = false, bool externalTransactionHandling = false)
        {
            return ConvertDataTableToXml(ExecuteSqlMain(sqlstring, throwException, externalTransactionHandling), throwException);
        }

        public string ExecuteQueryAsCsv(string sqlstring, string delimiter = ";", bool throwException = false, bool externalTransactionHandling = false)
        {
            return ConvertDataTableToCsv(ExecuteSqlMain(sqlstring, throwException, externalTransactionHandling), throwException);
        }

        public List<dynamic> ExecuteQueryAsDynamicList(string sqlstring, bool throwException = false, bool externalTransactionHandling = false)
        {
            return ConvertDataTableToListDynamicObject(ExecuteSqlMain(sqlstring, throwException, externalTransactionHandling), throwException);
        }

        public List<T> ExecuteQueryAsList<T>(string sqlstring, bool throwException = false, bool externalTransactionHandling = false)
        {
            var dataTable = ExecuteSqlMain(sqlstring, throwException, externalTransactionHandling);
            var list = new List<T>();

            foreach (DataRow row in dataTable.Rows)
            {
                if (row[0] != DBNull.Value)
                {
                    list.Add((T)Convert.ChangeType(row[0], typeof(T)));
                }
            }

            return list;
        }

        public void ExecuteNonQueryVoid(string sqlstring, bool throwException = false, bool externalTransactionHandling = false)
        {
            ExecuteSqlMain(sqlstring, throwException, externalTransactionHandling);
        }

        public int ExecuteNonQuery(string sqlstring, bool throwException = false, bool externalTransactionHandling = false)
        {
            DataTable dataTable = ExecuteSqlMain(sqlstring, throwException, externalTransactionHandling);
            return _DbSqlRowsAffected;
        }

        public void ExecuteNonQuery(string sqlstring, Dictionary<string, object> parameters, bool throwException = false, bool externalTransactionHandling = false)
        {
            ThrowIfDisposed();
            bool shouldHandleTransaction = !externalTransactionHandling && !_isInTransaction;

            DedgeNLog.Trace($"Executing PostgreSQL NonQuery - SQL: {sqlstring}, Parameters: {JsonConvert.SerializeObject(parameters)}");

            try
            {
                if (!_isInTransaction)
                {
                    _currentConnection = new NpgsqlConnection(_ConnectionString);
                    _currentConnection.Open();
                }

                if (shouldHandleTransaction)
                {
                    _currentTransaction = _currentConnection?.BeginTransaction();
                    _isInTransaction = true;
                    _isAutoTransaction = true;
                }

                using (NpgsqlCommand command = new NpgsqlCommand(sqlstring, _currentConnection))
                {
                    if (_isInTransaction && _currentTransaction != null)
                    {
                        command.Transaction = _currentTransaction;
                    }

                    foreach (var param in parameters)
                    {
                        command.Parameters.AddWithValue(param.Key, param.Value ?? DBNull.Value);
                    }

                    _DbSqlRowsAffected = command.ExecuteNonQuery();
                }

                if (shouldHandleTransaction)
                {
                    _currentTransaction?.Commit();
                    _isInTransaction = false;
                    _isAutoTransaction = false;
                }

                if (!_isInTransaction && _currentConnection != null)
                {
                    _currentConnection.Close();
                    _currentConnection.Dispose();
                    _currentConnection = null;
                }

                _DbSqlCode = DbSqlError.Success;
                _SqlStatement = sqlstring;
                UpdateSqlInfo();
            }
            catch (NpgsqlException ex)
            {
                _DbSqlCode = MapPostgresErrorToDbSqlError(ex);
                _SqlStatement = sqlstring;
                UpdateSqlInfo();

                DedgeNLog.Error(ex, $"PostgreSQL error executing NonQuery");

                if (shouldHandleTransaction && _currentTransaction != null)
                {
                    try
                    {
                        _currentTransaction.Rollback();
                        _isInTransaction = false;
                    }
                    catch { }
                }

                if (throwException)
                    throw;
            }
        }

        public T ExecuteScalar<T>(string sqlstring, Dictionary<string, object> parameters, bool throwException = false, bool externalTransactionHandling = false)
        {
            ThrowIfDisposed();
            T result = default!;

            try
            {
                bool shouldHandleConnection = !_isInTransaction;

                if (shouldHandleConnection)
                {
                    _currentConnection = new NpgsqlConnection(_ConnectionString);
                    _currentConnection.Open();
                }

                using (NpgsqlCommand command = new NpgsqlCommand(sqlstring, _currentConnection))
                {
                    if (_isInTransaction && _currentTransaction != null)
                    {
                        command.Transaction = _currentTransaction;
                    }

                    foreach (var param in parameters)
                    {
                        command.Parameters.AddWithValue(param.Key, param.Value ?? DBNull.Value);
                    }

                    object? scalarResult = command.ExecuteScalar();
                    
                    if (scalarResult != null && scalarResult != DBNull.Value)
                    {
                        result = (T)Convert.ChangeType(scalarResult, typeof(T));
                    }
                }

                if (shouldHandleConnection && _currentConnection != null)
                {
                    _currentConnection.Close();
                    _currentConnection.Dispose();
                    _currentConnection = null;
                }

                _DbSqlCode = DbSqlError.Success;
                _DbSqlRowCount = 1;
                UpdateSqlInfo();
            }
            catch (NpgsqlException ex)
            {
                _DbSqlCode = MapPostgresErrorToDbSqlError(ex);
                UpdateSqlInfo();
                DedgeNLog.Error(ex, "PostgreSQL error executing scalar query");

                if (throwException)
                    throw;
            }

            return result;
        }

        public void BeginTransaction()
        {
            ThrowIfDisposed();

            if (_isInTransaction)
            {
                DedgeNLog.Warn("Transaction already in progress");
                return;
            }

            try
            {
                if (_currentConnection == null)
                {
                    _currentConnection = new NpgsqlConnection(_ConnectionString);
                    _currentConnection.Open();
                }

                _currentTransaction = _currentConnection.BeginTransaction();
                _isInTransaction = true;
                _isAutoTransaction = false;
                DedgeNLog.Trace("PostgreSQL transaction started");
            }
            catch (Exception ex)
            {
                DedgeNLog.Error(ex, "Failed to begin PostgreSQL transaction");
                throw;
            }
        }

        public void CommitTransaction()
        {
            ThrowIfDisposed();

            if (!_isInTransaction)
            {
                DedgeNLog.Warn("No active transaction to commit");
                return;
            }

            try
            {
                _currentTransaction?.Commit();
                _isInTransaction = false;
                DedgeNLog.Trace("PostgreSQL transaction committed");

                if (_currentConnection != null)
                {
                    _currentConnection.Close();
                    _currentConnection.Dispose();
                    _currentConnection = null;
                }
            }
            catch (Exception ex)
            {
                DedgeNLog.Error(ex, "Failed to commit PostgreSQL transaction");
                throw;
            }
        }

        public void RollbackTransaction()
        {
            ThrowIfDisposed();

            if (!_isInTransaction)
            {
                DedgeNLog.Warn("No active transaction to rollback");
                return;
            }

            try
            {
                _currentTransaction?.Rollback();
                _isInTransaction = false;
                DedgeNLog.Trace("PostgreSQL transaction rolled back");

                if (_currentConnection != null)
                {
                    _currentConnection.Close();
                    _currentConnection.Dispose();
                    _currentConnection = null;
                }
            }
            catch (Exception ex)
            {
                DedgeNLog.Error(ex, "Failed to rollback PostgreSQL transaction");
                throw;
            }
        }

        // Conversion methods (must be public to implement interface)
        public string ConvertDataTableToJson(DataTable dataTable, bool throwException, bool indented = true)
        {
            try
            {
                var rows = new List<Dictionary<string, object>>();
                foreach (DataRow row in dataTable.Rows)
                {
                    var rowDict = new Dictionary<string, object>();
                    foreach (DataColumn col in dataTable.Columns)
                    {
                        rowDict[col.ColumnName] = row[col] == DBNull.Value ? null! : row[col];
                    }
                    rows.Add(rowDict);
                }

                return JsonConvert.SerializeObject(rows, indented ? Formatting.Indented : Formatting.None);
            }
            catch (Exception ex)
            {
                DedgeNLog.Error(ex, "Failed to convert DataTable to JSON");
                if (throwException) throw;
                return "{}";
            }
        }

        public string ConvertDataTableToXml(DataTable dataTable, bool throwException)
        {
            try
            {
                using var stringWriter = new StringWriter();
                dataTable.WriteXml(stringWriter);
                return stringWriter.ToString();
            }
            catch (Exception ex)
            {
                DedgeNLog.Error(ex, "Failed to convert DataTable to XML");
                if (throwException) throw;
                return "<root></root>";
            }
        }

        public string ConvertDataTableToCsv(DataTable dataTable, bool throwException)
        {
            try
            {
                var sb = new StringBuilder();
                string delimiter = ";";  // Default CSV delimiter
                
                // Header
                sb.AppendLine(string.Join(delimiter, dataTable.Columns.Cast<DataColumn>().Select(c => c.ColumnName)));
                
                // Rows
                foreach (DataRow row in dataTable.Rows)
                {
                    sb.AppendLine(string.Join(delimiter, row.ItemArray.Select(o => o?.ToString() ?? "")));
                }
                
                return sb.ToString();
            }
            catch (Exception ex)
            {
                DedgeNLog.Error(ex, "Failed to convert DataTable to CSV");
                if (throwException) throw;
                return "";
            }
        }

        public string ConvertDataTableToHtml(DataTable dataTable, bool throwException)
        {
            try
            {
                var sb = new StringBuilder();
                sb.AppendLine("<table border='1'>");
                sb.AppendLine("<tr>");
                foreach (DataColumn col in dataTable.Columns)
                {
                    sb.AppendLine($"<th>{col.ColumnName}</th>");
                }
                sb.AppendLine("</tr>");

                foreach (DataRow row in dataTable.Rows)
                {
                    sb.AppendLine("<tr>");
                    foreach (var item in row.ItemArray)
                    {
                        sb.AppendLine($"<td>{item}</td>");
                    }
                    sb.AppendLine("</tr>");
                }
                sb.AppendLine("</table>");

                return sb.ToString();
            }
            catch (Exception ex)
            {
                DedgeNLog.Error(ex, "Failed to convert DataTable to HTML");
                if (throwException) throw;
                return "<table></table>";
            }
        }

        public List<dynamic> ConvertDataTableToListDynamicObject(DataTable dataTable, bool throwException)
        {
            try
            {
                var list = new List<dynamic>();
                foreach (DataRow row in dataTable.Rows)
                {
                    dynamic obj = new ExpandoObject();
                    var dict = (IDictionary<string, object>)obj;
                    
                    foreach (DataColumn col in dataTable.Columns)
                    {
                        dict[col.ColumnName] = row[col] == DBNull.Value ? null! : row[col];
                    }
                    
                    list.Add(obj);
                }
                return list;
            }
            catch (Exception ex)
            {
                DedgeNLog.Error(ex, "Failed to convert DataTable to dynamic list");
                if (throwException) throw;
                return new List<dynamic>();
            }
        }

        public SqlInfo GetSqlStatus(DataTable dataTable)
        {
            _DbSqlRowCount = dataTable.Rows.Count;
            UpdateSqlInfo();
            return _SqlInfo;
        }

        public string GetDatabaseName()
        {
            if (_ConnectionKey != null)
            {
                return DedgeConnection.GetDatabaseName(_ConnectionKey);
            }

            // Parse from connection string
            var parts = _ConnectionString.Split(';');
            var database = parts.FirstOrDefault(p => p.StartsWith("Database=", StringComparison.OrdinalIgnoreCase))?.Split('=')[1];
            return database ?? "Unknown";
        }

        public void ExecuteAtomicNonQuery(string sqlstring, Dictionary<string, object> parameters, bool throwException = false, bool externalTransactionHandling = false)
        {
            BeginTransaction();
            try
            {
                ExecuteNonQuery(sqlstring, parameters, throwException, externalTransactionHandling: true);
                CommitTransaction();
            }
            catch
            {
                RollbackTransaction();
                throw;
            }
        }

        public T ExecuteAtomicScalar<T>(string sqlstring, Dictionary<string, object> parameters, bool throwException = false, bool externalTransactionHandling = false)
        {
            BeginTransaction();
            try
            {
                var result = ExecuteScalar<T>(sqlstring, parameters, throwException, externalTransactionHandling: true);
                CommitTransaction();
                return result;
            }
            catch
            {
                RollbackTransaction();
                throw;
            }
        }

        private void ThrowIfDisposed()
        {
            if (_isDisposed)
            {
                throw new ObjectDisposedException(nameof(PostgresHandler));
            }
        }

        public void Dispose()
        {
            if (_isDisposed)
                return;

            try
            {
                if (_currentTransaction != null)
                {
                    _currentTransaction.Rollback();
                    _currentTransaction.Dispose();
                    _currentTransaction = null;
                }

                if (_currentConnection != null)
                {
                    _currentConnection.Close();
                    _currentConnection.Dispose();
                    _currentConnection = null;
                }
            }
            catch (Exception ex)
            {
                DedgeNLog.Error(ex, "Error disposing PostgresHandler");
            }
            finally
            {
                _isDisposed = true;
            }
        }
    }
}
