using Microsoft.Data.SqlClient;
using Newtonsoft.Json;
using NLog;
using System.Data;
using System.Dynamic;
using System.Reflection;
using System.Text;

namespace DedgeCommon
{
    /// <summary>
    /// Implements the IDbHandler interface for Microsoft SQL Server databases.
    /// Provides specific functionality for executing queries and managing connections
    /// to SQL Server databases within the Dedge system.
    /// </summary>
    /// <remarks>
    /// Features:
    /// - Executes SQL queries with error handling and logging
    /// - Supports transactions with automatic cleanup
    /// - Converts query results to various formats (JSON, XML, CSV, HTML)
    /// - Provides detailed SQL execution status information
    /// - Handles SQL Server-specific error codes and mappings
    /// - Supports asynchronous operations
    /// </remarks>
    /// <author>Geir Helge Starholm</author>
    internal class SqlServerHandler : IDbHandler
    {
        private string _ConnectionString;
        private static readonly DedgeNLog _Logger = new DedgeNLog();
        private static bool test = DedgeNLog.EnableDatabaseLogging();
        private DbSqlError _DbSqlCode = 0;
        private int _DbSqlRowCount = 0;
        private int _DbSqlRowsAffected = 0;
        private string _SqlStatement = "";
        private DedgeConnection.ConnectionKey? _ConnectionKey;

        public SqlInfo _SqlInfo { get; set; }

        // Add transaction-related fields
        private SqlConnection? _currentConnection;
        private SqlTransaction? _currentTransaction;
        private bool _isInTransaction = false;

        private bool _isDisposed = false;

        // Add new field to track if we need to auto-commit
#pragma warning disable CS0414 // Field is assigned but its value is never used
        private bool _isAutoTransaction = false;
#pragma warning restore CS0414

        // Recursion guard: Prevents infinite loop when logging database errors
        // If we're already in MapSqlServerErrorToDbSqlError and DedgeNLog tries to log to DB,
        // which creates a new handler that fails, we would get infinite recursion
        private bool _isLoggingToDatabase = false;

        // Primary constructor using ConnectionKey
        /// <summary>
        /// Initializes a new instance of the SqlServerHandler class with a connection key.
        /// </summary>
        /// <param name="connectionKey">The connection key containing environment and application info</param>
        /// <param name="overrideUID">Optional username to override configured credentials</param>
        /// <param name="overridePWD">Optional password to override configured credentials</param>
        /// <param name="logger">Optional logger instance</param>
        public SqlServerHandler(DedgeConnection.ConnectionKey connectionKey, string? overrideUID = null, string? overridePWD = null, Logger? logger = null)
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

                // Get connection info from DedgeConnection with optional credential override
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
                    DedgeNLog.Trace($"SQL Server connection created with override credentials - Database: {accessPoint.DatabaseName}, Catalog: {accessPoint.CatalogName}, User: {overrideUID ?? accessPoint.UID}");
                }
                else if (useKerberos)
                {
                    string currentUser = $"{Environment.UserDomainName}\\{Environment.UserName}";
                    DedgeNLog.Trace($"SQL Server connection created using current Windows user - Database: {accessPoint.DatabaseName}, Catalog: {accessPoint.CatalogName}, User: {currentUser} (Integrated Security)");
                }
                else
                {
                    DedgeNLog.Trace($"SQL Server connection created with configured credentials - Database: {accessPoint.DatabaseName}, Catalog: {accessPoint.CatalogName}, User: {accessPoint.UID}");
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
        /// <param name="logger">Optional logger instance</param>
        public SqlServerHandler(string connectionString, Logger? logger = null)
        {
            try
            {
                _ConnectionString = connectionString ?? throw new ArgumentNullException(nameof(connectionString));
                _SqlInfo = new SqlInfo();

                // Parse connection string to log database and authentication info
                var parts = connectionString.Split(';', StringSplitOptions.RemoveEmptyEntries);
                var databaseName = parts.FirstOrDefault(p => p.StartsWith("DatabaseName=", StringComparison.OrdinalIgnoreCase))?.Split('=')[1] ?? 
                                  parts.FirstOrDefault(p => p.StartsWith("Database=", StringComparison.OrdinalIgnoreCase))?.Split('=')[1] ?? "Unknown";
                var hasIntegratedSecurity = parts.Any(p => p.StartsWith("Integrated Security", StringComparison.OrdinalIgnoreCase));
                var hasUserId = parts.Any(p => p.StartsWith("User Id=", StringComparison.OrdinalIgnoreCase) || p.StartsWith("UID=", StringComparison.OrdinalIgnoreCase));
                var userId = parts.FirstOrDefault(p => p.StartsWith("User Id=", StringComparison.OrdinalIgnoreCase))?.Split('=')[1] ??
                            parts.FirstOrDefault(p => p.StartsWith("UID=", StringComparison.OrdinalIgnoreCase))?.Split('=')[1];
                
                if (hasIntegratedSecurity)
                {
                    string currentUser = $"{Environment.UserDomainName}\\{Environment.UserName}";
                    DedgeNLog.Trace($"SQL Server connection created using current Windows user - Database: {databaseName}, User: {currentUser} (Integrated Security)");
                }
                else if (hasUserId && !string.IsNullOrEmpty(userId))
                {
                    DedgeNLog.Trace($"SQL Server connection created with credentials - Database: {databaseName}, User: {userId}");
                }
                else
                {
                    DedgeNLog.Trace($"SQL Server connection created - Database: {databaseName}");
                }
            }
            catch (Exception)
            {
                throw;
            }
        }

        private DataTable ExecuteSqlMain(string sqlstring, bool throwException = false, bool externalTransactionHandling = false)
        {
            ThrowIfDisposed();
            DataTable dataTable = new DataTable();
            bool shouldHandleTransaction = !externalTransactionHandling && !_isInTransaction;

            DedgeNLog.Trace($"Executing SQL Main - SQL: {sqlstring}, ThrowException: {throwException}, ExternalTransactionHandling: {externalTransactionHandling}");

            try
            {
                if (!_isInTransaction)
                {
                    _currentConnection = new SqlConnection(_ConnectionString);
                    DedgeNLog.Trace($"Opening new SQL Server connection");
                    _currentConnection.Open();
                    DedgeNLog.Trace($"SQL Server connection opened successfully");
                }

                if (shouldHandleTransaction)
                {
                    DedgeNLog.Trace($"Beginning new transaction");
                    _currentTransaction = _currentConnection?.BeginTransaction();
                    _isInTransaction = true;
                    _isAutoTransaction = true;
                    DedgeNLog.Trace($"Transaction began successfully");
                }

                using (SqlCommand command = new SqlCommand(sqlstring, _currentConnection))
                {
                    if (_isInTransaction && _currentTransaction != null)
                    {
                        command.Transaction = _currentTransaction;
                    }

                    using (SqlDataAdapter adapter = new SqlDataAdapter(command))
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
                    DedgeNLog.Trace($"Closing SQL Server connection");
                    _currentConnection.Close();
                    DedgeNLog.Trace($"Disposing SQL Server connection");
                    _currentConnection.Dispose();
                    _currentConnection = null;
                    DedgeNLog.Trace($"SQL Server connection closed and disposed");
                }

                return dataTable;
            }
            catch (Exception ex)
            {
                if (shouldHandleTransaction)
                {
                    DedgeNLog.Trace($"Rolling back transaction due to error");
                    _currentTransaction?.Rollback();
                    _isInTransaction = false;
                    _isAutoTransaction = false;
                    DedgeNLog.Trace($"Transaction rolled back successfully");
                }

                if (!_isInTransaction && _currentConnection != null)
                {
                    DedgeNLog.Trace($"Closing SQL Server connection after error");
                    _currentConnection.Close();
                    DedgeNLog.Trace($"Disposing SQL Server connection after error");
                    _currentConnection.Dispose();
                    _currentConnection = null;
                    DedgeNLog.Trace($"SQL Server connection closed and disposed after error");
                }

                DedgeNLog.Error(ex, $"Error executing SQL");
                if (throwException)
                    throw;

                return dataTable;
            }
        }

        private DbSqlError MapSqlServerErrorToDbSqlError(int sqlErrorNumber)
        {
            // Prevent recursive logging if we are already in a logging context
            // This can happen when: MapSqlServerErrorToDbSqlError -> DedgeNLog.Warn -> RealDbLogging 
            // -> creates SqlServerHandler -> connection fails -> MapSqlServerErrorToDbSqlError (infinite loop)
            if (_isLoggingToDatabase)
            {
                return DbSqlError.UnknownError; // Return a generic error to break recursion
            }

            try
            {
                _isLoggingToDatabase = true; // Set flag to indicate we are in a logging context

                switch (sqlErrorNumber)
                {
                    case (int)SqlServerError.Success:
                        return DbSqlError.Success;
                    case (int)SqlServerError.DuplicateKey:
                    case (int)SqlServerError.UniqueConstraintViolation:
                        return DbSqlError.NotFound;
                    case (int)SqlServerError.ForeignKeyViolation:
                        return DbSqlError.NotFound;
                    case (int)SqlServerError.NullNotAllowed:
                        return DbSqlError.NotFound;
                    case (int)SqlServerError.InvalidObjectName:
                    case (int)SqlServerError.InvalidColumnName:
                        return DbSqlError.NotFound;
                    case (int)SqlServerError.LoginFailed:
                    case (int)SqlServerError.PermissionDenied:
                        return DbSqlError.NotFound;
                    case (int)SqlServerError.ConversionFailed:
                    case (int)SqlServerError.DataTypeError:
                        return DbSqlError.NotFound;
                    default:
                        DedgeNLog.Warn($"Unmapped SQL Server error code: {sqlErrorNumber}");
                        return DbSqlError.UnknownError;
                }
            }
            finally
            {
                _isLoggingToDatabase = false; // Reset flag
            }
        }

        // Implement all the ExecuteQuery methods with the same signatures as Db2Handler
        public DataTable ExecuteQueryAsDataTable(string sqlstring, bool throwException = false, bool externalTransactionHandling = false)
        {
            return ExecuteSqlMain(sqlstring, throwException, externalTransactionHandling);
        }

        public string ExecuteQueryAsHtml(string sqlstring, bool throwException = false, bool externalTransactionHandling = false)
        {
            return ConvertDataTableToHtmlTable(ExecuteSqlMain(sqlstring, throwException, externalTransactionHandling), throwException);
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

            DedgeNLog.Trace($"Executing SQL NonQuery - SQL: {sqlstring}, Parameters: {JsonConvert.SerializeObject(parameters)}, ExternalTransactionHandling: {externalTransactionHandling}");

            try
            {
                if (!_isInTransaction)
                {
                    _currentConnection = new SqlConnection(_ConnectionString);
                    DedgeNLog.Trace($"Opening new SQL Server connection");
                    _currentConnection.Open();
                    DedgeNLog.Trace($"SQL Server connection opened successfully");
                }

                if (shouldHandleTransaction)
                {
                    DedgeNLog.Trace($"Beginning new transaction");
                    _currentTransaction = _currentConnection?.BeginTransaction();
                    _isInTransaction = true;
                    _isAutoTransaction = true;
                    DedgeNLog.Trace($"Transaction began successfully");
                }

                using (SqlCommand command = new SqlCommand(sqlstring, _currentConnection))
                {
                    if (_isInTransaction && _currentTransaction != null)
                    {
                        command.Transaction = _currentTransaction;
                    }

                    foreach (var param in parameters)
                    {
                        command.Parameters.AddWithValue(param.Key, param.Value ?? DBNull.Value);
                    }

                    command.ExecuteNonQuery();

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
                        DedgeNLog.Trace($"Closing SQL Server connection");
                        _currentConnection.Close();
                        DedgeNLog.Trace($"Disposing SQL Server connection");
                        _currentConnection.Dispose();
                        _currentConnection = null;
                        DedgeNLog.Trace($"SQL Server connection closed and disposed");
                    }
                }
            }
            catch (Exception ex)
            {
                if (shouldHandleTransaction)
                {
                    DedgeNLog.Trace($"Rolling back transaction due to error");
                    _currentTransaction?.Rollback();
                    _isInTransaction = false;
                    _isAutoTransaction = false;
                    DedgeNLog.Trace($"Transaction rolled back successfully");
                }

                if (!_isInTransaction && _currentConnection != null)
                {
                    DedgeNLog.Trace($"Closing SQL Server connection after error");
                    _currentConnection.Close();
                    DedgeNLog.Trace($"Disposing SQL Server connection after error");
                    _currentConnection.Dispose();
                    _currentConnection = null;
                    DedgeNLog.Trace($"SQL Server connection closed and disposed after error");
                }

                DedgeNLog.Error(ex, $"Error executing non-query SQL");
                if (throwException)
                    throw;
            }
        }

        public T ExecuteScalar<T>(string sqlstring, Dictionary<string, object> parameters, bool throwException = false, bool externalTransactionHandling = false)
        {
            ThrowIfDisposed();
            bool shouldHandleTransaction = !externalTransactionHandling && !_isInTransaction;

            DedgeNLog.Trace($"Executing SQL Scalar<{typeof(T).Name}> - SQL: {sqlstring}, Parameters: {JsonConvert.SerializeObject(parameters)}, ExternalTransactionHandling: {externalTransactionHandling}");

            try
            {
                if (!_isInTransaction)
                {
                    _currentConnection = new SqlConnection(_ConnectionString);
                    DedgeNLog.Trace($"Opening new SQL Server connection");
                    _currentConnection.Open();
                    DedgeNLog.Trace($"SQL Server connection opened successfully");
                }

                if (shouldHandleTransaction)
                {
                    DedgeNLog.Trace($"Beginning new transaction");
                    _currentTransaction = _currentConnection?.BeginTransaction();
                    _isInTransaction = true;
                    _isAutoTransaction = true;
                    DedgeNLog.Trace($"Transaction began successfully");
                }

                using (SqlCommand command = new SqlCommand(sqlstring, _currentConnection))
                {
                    if (_isInTransaction && _currentTransaction != null)
                    {
                        command.Transaction = _currentTransaction;
                    }

                    foreach (var param in parameters)
                    {
                        command.Parameters.AddWithValue(param.Key, param.Value ?? DBNull.Value);
                    }

                    var result = command.ExecuteScalar();

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
                        DedgeNLog.Trace($"Closing SQL Server connection");
                        _currentConnection.Close();
                        DedgeNLog.Trace($"Disposing SQL Server connection");
                        _currentConnection.Dispose();
                        _currentConnection = null;
                        DedgeNLog.Trace($"SQL Server connection closed and disposed");
                    }

                    if (result == DBNull.Value)
                        return default(T)!;

                    return (T)Convert.ChangeType(result, typeof(T));
                }
            }
            catch (Exception ex)
            {
                if (shouldHandleTransaction)
                {
                    DedgeNLog.Trace($"Rolling back transaction due to error");
                    _currentTransaction?.Rollback();
                    _isInTransaction = false;
                    _isAutoTransaction = false;
                    DedgeNLog.Trace($"Transaction rolled back successfully");
                }

                if (!_isInTransaction && _currentConnection != null)
                {
                    DedgeNLog.Trace($"Closing SQL Server connection after error");
                    _currentConnection.Close();
                    DedgeNLog.Trace($"Disposing SQL Server connection after error");
                    _currentConnection.Dispose();
                    _currentConnection = null;
                    DedgeNLog.Trace($"SQL Server connection closed and disposed after error");
                }

                DedgeNLog.Error(ex, $"Error executing scalar SQL");
                if (throwException)
                    throw;

                return default(T)!;
            }
        }

        // Include all the conversion methods from Db2Handler
        public List<dynamic> ConvertDataTableToListDynamicObject(DataTable dataTable, bool throwException = false)
        {
            // Implementation same as Db2Handler
            List<dynamic> dynamicList = new List<dynamic>();
            try
            {
                if (dataTable == null)
                    throw new ArgumentNullException(nameof(dataTable), "Input DataTable cannot be null.");

                foreach (DataRow row in dataTable.Rows)
                {
                    dynamic dyn = new ExpandoObject();
                    var dic = (IDictionary<string, object>)dyn;

                    foreach (DataColumn column in dataTable.Columns)
                    {
                        dic[column.ColumnName] = row[column];
                    }

                    dynamicList.Add(dyn);
                }
            }
            catch (Exception)
            {
                if (throwException)
                    throw;
            }
            return dynamicList;
        }

        // Include other conversion methods (ConvertDataTableToHtmlTable, ConvertDataTableToJson, etc.)
        // Implementation would be the same as in Db2Handler

        // Add transaction handling methods
        public void BeginTransaction()
        {
            try
            {
                if (_isInTransaction)
                {
                    throw new InvalidOperationException("Transaction already in progress");
                }

                _currentConnection = new SqlConnection(_ConnectionString);
                _currentConnection.Open();
                _currentTransaction = _currentConnection.BeginTransaction();
                _isInTransaction = true;
            }
            catch (Exception ex)
            {
                DedgeNLog.Error(ex, $"Error beginning transaction");
                throw;
            }
        }

        public void CommitTransaction()
        {
            try
            {
                if (!_isInTransaction)
                {
                    throw new InvalidOperationException("No transaction in progress");
                }

                _currentTransaction?.Commit();
            }
            catch (Exception ex)
            {
                DedgeNLog.Error(ex, $"Error committing transaction");
                throw;
            }
            finally
            {
                CleanupTransaction();
            }
        }

        public void RollbackTransaction()
        {
            try
            {
                if (!_isInTransaction)
                {
                    throw new InvalidOperationException("No transaction in progress");
                }

                _currentTransaction?.Rollback();
            }
            catch (Exception ex)
            {
                DedgeNLog.Error(ex, $"Error rolling back transaction");
                throw;
            }
            finally
            {
                CleanupTransaction();
            }
        }

        private void CleanupTransaction()
        {
            if (_currentTransaction != null)
            {
                _currentTransaction.Dispose();
                _currentTransaction = null;
            }

            if (_currentConnection != null)
            {
                _currentConnection.Close();
                _currentConnection.Dispose();
                _currentConnection = null;
            }

            _isInTransaction = false;
            _isAutoTransaction = false;
        }

        // Add destructor to ensure cleanup
        ~SqlServerHandler()
        {
            Dispose(false);
        }

        // Update GetSqlStatus method to use only available error codes
        public SqlInfo GetSqlStatus(DataTable dataTable, SqlException? sqlException = null)
        {
            SqlInfo sqlInfo = new();
            sqlInfo.SqlCode = _DbSqlCode;
            sqlInfo.RowCount = _DbSqlRowCount;
            sqlInfo.SqlStatement = _SqlStatement;

            if (sqlException != null)
            {
                sqlInfo.ExeceptionMessage = sqlException.Message;
                sqlInfo.InnerExeceptionMessage = sqlException.InnerException?.Message;
            }

            // Use only the error codes available in DbSqlError
            switch (_DbSqlCode)
            {
                case DbSqlError.Success:
                    sqlInfo.SqlCodeShortDescription = "Success";
                    sqlInfo.SqlCodeDescription = "The operation completed successfully.";
                    break;
                case DbSqlError.NotFound:
                    sqlInfo.SqlCodeShortDescription = "Not Found";
                    sqlInfo.SqlCodeDescription = "No rows were found.";
                    break;
                case DbSqlError.UnknownError:
                default:
                    sqlInfo.SqlCodeShortDescription = sqlException?.Message ?? "Unknown Error";
                    sqlInfo.SqlCodeDescription = sqlException?.Message ?? "Unknown SQL Server Error";
                    break;
            }

            return sqlInfo;
        }

        public string ConvertDataTableToHtmlTable(DataTable dataTable, bool throwException = false)
        {
            string htmlTable = "";
            try
            {
                htmlTable = "<table border='1' cellpadding='5' cellspacing='0'><tr>";
                foreach (DataColumn column in dataTable.Columns)
                {
                    htmlTable += "<th>" + column.ColumnName + "</th>";
                }
                htmlTable += "</tr>";
                foreach (DataRow row in dataTable.Rows)
                {
                    htmlTable += "<tr>";
                    foreach (DataColumn column in dataTable.Columns)
                    {
                        htmlTable += "<td>" + row[column.ColumnName].ToString() + "</td>";
                    }
                    htmlTable += "</tr>";
                }
                htmlTable += "</table>";
            }
            catch (Exception)
            {
                if (throwException)
                    throw;
                DedgeNLog.Error($"Error when converting DataTable to HTML Table.");
            }
            return htmlTable;
        }

        public string ConvertDataTableToJson(DataTable dataTable, bool throwException = false, bool indented = true)
        {
            string json = "";
            try
            {
                if (indented)
                    json = JsonConvert.SerializeObject(dataTable, Formatting.Indented);
                else
                    json = JsonConvert.SerializeObject(dataTable);
            }
            catch (Exception)
            {
                if (throwException)
                    throw;
                DedgeNLog.Error($"Error when converting DataTable to JSON.");
            }
            return json;
        }

        public string ConvertDataTableToXml(DataTable dataTable, bool throwException = false)
        {
            string xml = "";
            try
            {
                using (StringWriter stringWriter = new StringWriter())
                {
                    dataTable.WriteXml(stringWriter);
                    xml = stringWriter.ToString();
                }
            }
            catch (Exception)
            {
                if (throwException)
                    throw;
                DedgeNLog.Error($"Error when converting DataTable to XML.");
            }
            return xml;
        }

        public string ConvertDataTableToCsv(DataTable dataTable, bool throwException = false)
        {
            string csv = "";
            try
            {
                StringBuilder sb = new StringBuilder();

                IEnumerable<string> columnNames = dataTable.Columns.Cast<DataColumn>().
                                                  Select(column => column.ColumnName);
                sb.AppendLine(string.Join(",", columnNames));

                foreach (DataRow row in dataTable.Rows)
                {
                    IEnumerable<string> fields = row.ItemArray.Select(field => field?.ToString() ?? string.Empty);
                    sb.AppendLine(string.Join(",", fields));
                }

                csv = sb.ToString();
            }
            catch (Exception)
            {
                if (throwException)
                    throw;
                DedgeNLog.Error($"Error when converting DataTable to CSV.");
            }
            return csv;
        }

        public void ExecuteNonQuery(string sqlstring, Dictionary<string, object> parameters, bool throwException = false)
        {
            ThrowIfDisposed();
            try
            {
                SqlConnection connectionToUse;
                SqlTransaction? transactionToUse = null;

                if (_isInTransaction)
                {
                    // Use existing transaction
                    connectionToUse = _currentConnection!;
                    transactionToUse = _currentTransaction;
                }
                else
                {
                    // Create new connection
                    connectionToUse = new SqlConnection(_ConnectionString);
                    connectionToUse.Open();
                }

                try
                {
                    using (SqlCommand command = new SqlCommand(sqlstring, connectionToUse))
                    {
                        if (transactionToUse != null)
                        {
                            command.Transaction = transactionToUse;
                        }

                        foreach (var param in parameters)
                        {
                            command.Parameters.AddWithValue(param.Key, param.Value ?? DBNull.Value);
                        }
                        command.ExecuteNonQuery();
                    }

                    // Only close connection if we created it
                    if (!_isInTransaction)
                    {
                        connectionToUse.Close();
                        connectionToUse.Dispose();
                    }
                }
                catch
                {
                    // Only dispose connection if we created it
                    if (!_isInTransaction)
                    {
                        connectionToUse.Dispose();
                    }
                    throw;
                }
            }
            catch (Exception ex)
            {
                DedgeNLog.Error(ex, $"Error executing non-query SQL with parameters");
                if (throwException)
                    throw;
            }
        }

        public T ExecuteScalar<T>(string sqlstring, Dictionary<string, object> parameters, bool throwException = false)
        {
            ThrowIfDisposed();
            try
            {
                SqlConnection connectionToUse;
                SqlTransaction? transactionToUse = null;

                if (_isInTransaction)
                {
                    // Use existing transaction
                    connectionToUse = _currentConnection!;
                    transactionToUse = _currentTransaction;
                }
                else
                {
                    // Create new connection
                    connectionToUse = new SqlConnection(_ConnectionString);
                    connectionToUse.Open();
                }

                try
                {
                    using (SqlCommand command = new SqlCommand(sqlstring, connectionToUse))
                    {
                        if (transactionToUse != null)
                        {
                            command.Transaction = transactionToUse;
                        }

                        foreach (var param in parameters)
                        {
                            command.Parameters.AddWithValue(param.Key, param.Value ?? DBNull.Value);
                        }
                        var result = command.ExecuteScalar();

                        // Only close connection if we created it
                        if (!_isInTransaction)
                        {
                            connectionToUse.Close();
                            connectionToUse.Dispose();
                        }

                        if (result == DBNull.Value || result == null)
                        {
                            return default(T)!;
                        }

                        return (T)Convert.ChangeType(result, typeof(T));
                    }
                }
                catch
                {
                    // Only dispose connection if we created it
                    if (!_isInTransaction)
                    {
                        connectionToUse.Dispose();
                    }
                    throw;
                }
            }
            catch (Exception ex)
            {
                DedgeNLog.Error(ex, $"Error executing scalar SQL with parameters");
                if (throwException)
                    throw;
                return default(T)!;
            }
        }

        public string ConvertDataTableToHtml(DataTable dataTable, bool throwException = false)
        {
            return ConvertDataTableToHtmlTable(dataTable, throwException);
        }

        public SqlInfo GetSqlStatus(DataTable dataTable)
        {
            return GetSqlStatus(dataTable, null);
        }

        // Add public property with setter
        public string ConnectionString
        {
            get => _ConnectionString;
            set => _ConnectionString = value ?? throw new ArgumentNullException(nameof(value));
        }

        public DedgeConnection.DatabaseProvider Provider => DedgeConnection.DatabaseProvider.SQLSERVER;

        // Add these methods to the SqlServerHandler class

        public async Task<DataTable> ExecuteQueryAsDataTableAsync(string sqlstring, bool throwException = false)
        {
            DataTable dataTable = new DataTable();
            SqlException? sqlException = null;
            try
            {
                _DbSqlCode = DbSqlError.Success;
                _DbSqlRowCount = 0;
                _DbSqlRowsAffected = 0;
                _SqlStatement = sqlstring;

                using (SqlConnection sqlConn = new SqlConnection(_ConnectionString))
                {
                    await sqlConn.OpenAsync();
                    using (SqlCommand sqlCommand = new SqlCommand(sqlstring, sqlConn))
                    {
                        sqlCommand.CommandTimeout = 600;

                        if (sqlstring.ToUpper().StartsWith("SELECT "))
                        {
                            using (SqlDataReader sqlReader = await sqlCommand.ExecuteReaderAsync())
                            {
                                dataTable.Load(sqlReader);
                                if (dataTable.Rows.Count == 0)
                                {
                                    _DbSqlCode = DbSqlError.NotFound;
                                }
                                _DbSqlRowCount = dataTable.Rows.Count;
                            }
                        }
                        else
                        {
                            _DbSqlRowsAffected = await sqlCommand.ExecuteNonQueryAsync();
                            if (_DbSqlRowsAffected == 0)
                            {
                                _DbSqlCode = DbSqlError.NotFound;
                            }
                        }

                        _SqlInfo = GetSqlStatus(dataTable);

                        SetTableName(dataTable, sqlstring);
                    }
                }
            }
            catch (SqlException ex)
            {
                sqlException = ex;
                HandleSqlException(ex, throwException);
            }
            finally
            {
                UpdateSqlInfo(dataTable, sqlException!);
            }

            return dataTable;
        }

        public async Task<int> ExecuteNonQueryAsync(string sqlstring, bool throwException = false)
        {
            var dataTable = await ExecuteQueryAsDataTableAsync(sqlstring, throwException);
            return _DbSqlRowsAffected;
        }

        public async Task<int> ExecuteNonQueryAsync(string sqlstring, Dictionary<string, object> parameters, bool throwException = false)
        {
            try
            {
                using (SqlConnection sqlConn = new SqlConnection(_ConnectionString))
                {
                    await sqlConn.OpenAsync();
                    using (var command = new SqlCommand(sqlstring, sqlConn))
                    {
                        foreach (var param in parameters)
                        {
                            command.Parameters.AddWithValue(param.Key, param.Value ?? DBNull.Value);
                        }
                        return await command.ExecuteNonQueryAsync();
                    }
                }
            }
            catch (Exception ex)
            {
                DedgeNLog.Error(ex, $"Error executing non-query SQL with parameters");
                if (throwException)
                    throw;
                return -1;
            }
        }

        public async Task<T> ExecuteScalarAsync<T>(string sqlstring, bool throwException = false)
        {
            try
            {
                using (SqlConnection sqlConn = new SqlConnection(_ConnectionString))
                {
                    await sqlConn.OpenAsync();
                    using (var command = new SqlCommand(sqlstring, sqlConn))
                    {
                        var result = await command.ExecuteScalarAsync();
                        return (T)Convert.ChangeType(result!, typeof(T));
                    }
                }
            }
            catch (Exception ex)
            {
                DedgeNLog.Error(ex, $"Error executing scalar SQL");
                if (throwException)
                    throw;
                return default(T)!;
            }
        }

        public async Task<T> ExecuteScalarAsync<T>(string sqlstring, Dictionary<string, object> parameters, bool throwException = false)
        {
            try
            {
                using (SqlConnection sqlConn = new SqlConnection(_ConnectionString))
                {
                    await sqlConn.OpenAsync();
                    using (var command = new SqlCommand(sqlstring, sqlConn))
                    {
                        foreach (var param in parameters)
                        {
                            command.Parameters.AddWithValue(param.Key, param.Value ?? DBNull.Value);
                        }
                        var result = await command.ExecuteScalarAsync();
                        return (T)Convert.ChangeType(result!, typeof(T));
                    }
                }
            }
            catch (Exception ex)
            {
                DedgeNLog.Error(ex, $"Error executing scalar SQL with parameters");
                if (throwException)
                    throw;
                return default(T)!;
            }
        }

        public async Task<DataTable> ExecuteReaderAsync(string sqlstring, bool throwException = false)
        {
            return await ExecuteQueryAsDataTableAsync(sqlstring, throwException);
        }

        // Implement IDisposable
        public void Dispose()
        {
            Dispose(true);
            GC.SuppressFinalize(this);
        }

        protected virtual void Dispose(bool disposing)
        {
            if (!_isDisposed)
            {
                if (disposing)
                {
                    // Clean up managed resources
                    if (_isInTransaction)
                    {
                        try
                        {
                            RollbackTransaction();
                        }
                        catch (Exception ex)
                        {
                            DedgeNLog.Error(ex, "Error rolling back transaction during disposal");
                        }
                    }

                    if (_currentTransaction != null)
                    {
                        _currentTransaction.Dispose();
                        _currentTransaction = null;
                    }

                    if (_currentConnection != null)
                    {
                        _currentConnection.Dispose();
                        _currentConnection = null;
                    }
                }

                _isDisposed = true;
            }
        }

        private void ThrowIfDisposed()
        {
            if (_isDisposed)
            {
                throw new ObjectDisposedException(nameof(SqlServerHandler));
            }
        }

        private void SetTableName(DataTable dataTable, string sqlstring)
        {
            try
            {
                if (sqlstring.ToUpper().StartsWith("SELECT "))
                {
                    string[] sqlParts = sqlstring.Split("FROM ");
                    if (sqlParts.Length > 1)
                    {
                        string[] tableParts = sqlParts[1].Split(" ");
                        if (tableParts.Length > 1)
                        {
                            dataTable.TableName = tableParts[0];
                        }
                    }
                }
                else
                    dataTable.TableName = "Result";
            }
            catch
            {
                dataTable.TableName = "Result";
            }
        }

        private void HandleSqlException(SqlException ex, bool throwException)
        {
            _DbSqlRowsAffected = -1;
            _DbSqlCode = MapSqlServerErrorToDbSqlError(ex.Number);
            DedgeNLog.Error(ex, $"Error executing SQL. Error Number: {ex.Number}");
            if (throwException)
                throw ex;
        }

        private void UpdateSqlInfo(DataTable dataTable, SqlException sqlException)
        {
            if (sqlException == null)
                _SqlInfo = GetSqlStatus(dataTable);
            else
                _SqlInfo = GetSqlStatus(dataTable, sqlException);

            if (_DbSqlCode < DbSqlError.Success)
            {
                DedgeNLog.Warn($"Error executing SQL. SqlInfo: {_SqlInfo.SqlCode + " - " + _SqlInfo.SqlCodeShortDescription}");
            }
        }

        public string GetDatabaseName()
        {
            return _ConnectionKey != null ? DedgeConnection.GetDatabaseName(_ConnectionKey) : string.Empty;
        }

        public void ExecuteAtomicNonQuery(string sqlstring, Dictionary<string, object> parameters, bool throwException = false, bool externalTransactionHandling = false)
        {
            ThrowIfDisposed();
            bool shouldHandleTransaction = !externalTransactionHandling && !_isInTransaction;

            DedgeNLog.Trace($"Executing Atomic NonQuery - SQL: {sqlstring}, Parameters: {JsonConvert.SerializeObject(parameters)}, ExternalTransactionHandling: {externalTransactionHandling}");

            try
            {
                if (!_isInTransaction)
                {
                    _currentConnection = new SqlConnection(_ConnectionString);
                    DedgeNLog.Trace($"Opening new SQL Server connection");
                    _currentConnection.Open();
                    DedgeNLog.Trace($"SQL Server connection opened successfully");
                }

                if (shouldHandleTransaction)
                {
                    DedgeNLog.Trace($"Beginning new transaction");
                    _currentTransaction = _currentConnection?.BeginTransaction();
                    _isInTransaction = true;
                    _isAutoTransaction = true;
                    DedgeNLog.Trace($"Transaction began successfully");
                }

                using (SqlCommand command = new SqlCommand(sqlstring, _currentConnection))
                {
                    if (_isInTransaction && _currentTransaction != null)
                    {
                        command.Transaction = _currentTransaction;
                    }

                    foreach (var param in parameters)
                    {
                        command.Parameters.AddWithValue(param.Key, param.Value ?? DBNull.Value);
                    }

                    command.ExecuteNonQuery();

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
                        DedgeNLog.Trace($"Closing SQL Server connection");
                        _currentConnection.Close();
                        DedgeNLog.Trace($"Disposing SQL Server connection");
                        _currentConnection.Dispose();
                        _currentConnection = null;
                        DedgeNLog.Trace($"SQL Server connection closed and disposed");
                    }
                }
            }
            catch (Exception ex)
            {
                if (shouldHandleTransaction)
                {
                    DedgeNLog.Trace($"Rolling back transaction due to error");
                    _currentTransaction?.Rollback();
                    _isInTransaction = false;
                    _isAutoTransaction = false;
                    DedgeNLog.Trace($"Transaction rolled back successfully");
                }

                if (!_isInTransaction && _currentConnection != null)
                {
                    DedgeNLog.Trace($"Closing SQL Server connection after error");
                    _currentConnection.Close();
                    DedgeNLog.Trace($"Disposing SQL Server connection after error");
                    _currentConnection.Dispose();
                    _currentConnection = null;
                    DedgeNLog.Trace($"SQL Server connection closed and disposed after error");
                }

                DedgeNLog.Error(ex, $"Error executing atomic non-query SQL");
                if (throwException)
                    throw;
            }
        }

        public T ExecuteAtomicScalar<T>(string sqlstring, Dictionary<string, object> parameters, bool throwException = false, bool externalTransactionHandling = false)
        {
            ThrowIfDisposed();
            bool shouldHandleTransaction = !externalTransactionHandling && !_isInTransaction;

            DedgeNLog.Trace($"Executing Atomic Scalar<{typeof(T).Name}> - SQL: {sqlstring}, Parameters: {JsonConvert.SerializeObject(parameters)}, ExternalTransactionHandling: {externalTransactionHandling}");

            try
            {
                if (!_isInTransaction)
                {
                    _currentConnection = new SqlConnection(_ConnectionString);
                    DedgeNLog.Trace($"Opening new SQL Server connection");
                    _currentConnection.Open();
                    DedgeNLog.Trace($"SQL Server connection opened successfully");
                }

                if (shouldHandleTransaction)
                {
                    DedgeNLog.Trace($"Beginning new transaction");
                    _currentTransaction = _currentConnection?.BeginTransaction();
                    _isInTransaction = true;
                    _isAutoTransaction = true;
                    DedgeNLog.Trace($"Transaction began successfully");
                }

                using (SqlCommand command = new SqlCommand(sqlstring, _currentConnection))
                {
                    if (_isInTransaction && _currentTransaction != null)
                    {
                        command.Transaction = _currentTransaction;
                    }

                    foreach (var param in parameters)
                    {
                        command.Parameters.AddWithValue(param.Key, param.Value ?? DBNull.Value);
                    }

                    var result = command.ExecuteScalar();

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
                        DedgeNLog.Trace($"Closing SQL Server connection after error");
                        _currentConnection.Close();
                        DedgeNLog.Trace($"Disposing SQL Server connection after error");
                        _currentConnection.Dispose();
                        _currentConnection = null;
                        DedgeNLog.Trace($"SQL Server connection closed and disposed after error");
                    }

                    if (result == DBNull.Value)
                        return default(T)!;

                    return (T)Convert.ChangeType(result, typeof(T));
                }
            }
            catch (Exception ex)
            {
                if (shouldHandleTransaction)
                {
                    DedgeNLog.Trace($"Rolling back transaction due to error");
                    _currentTransaction?.Rollback();
                    _isInTransaction = false;
                    _isAutoTransaction = false;
                    DedgeNLog.Trace($"Transaction rolled back successfully");
                }

                if (!_isInTransaction && _currentConnection != null)
                {
                    DedgeNLog.Trace($"Closing SQL Server connection after error");
                    _currentConnection.Close();
                    DedgeNLog.Trace($"Disposing SQL Server connection after error");
                    _currentConnection.Dispose();
                    _currentConnection = null;
                    DedgeNLog.Trace($"SQL Server connection closed and disposed after error");
                }

                DedgeNLog.Error(ex, $"Error executing atomic scalar SQL");
                if (throwException)
                    throw;

                return default(T)!;
            }
        }

        // Add SQL Server-specific error codes
        private enum SqlServerError
        {
            // Success codes
            Success = DbSqlError.Success,
            NotFound = DbSqlError.NotFound,

            // SQL Server-specific error codes
            DuplicateKey = 2601,
            UniqueConstraintViolation = 2627,
            ForeignKeyViolation = 547,
            NullNotAllowed = 515,
            InvalidObjectName = 208,
            InvalidColumnName = 207,
            LoginFailed = 18456,
            PermissionDenied = 229,
            ConversionFailed = 245,
            DataTypeError = 8114,

            UnknownError = DbSqlError.UnknownError
        }
    }
}