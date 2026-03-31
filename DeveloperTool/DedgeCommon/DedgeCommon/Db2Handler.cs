using IBM.Data.Db2;
using Namotion.Reflection;
using Newtonsoft.Json;
using System.Data;
using System.Dynamic;
using System.Reflection;
using System.Text;
using System.Transactions;
namespace DedgeCommon
{
    /// <summary>
    /// Implements the IDbHandler interface for IBM DB2 databases.
    /// Provides specific functionality for executing queries and managing connections
    /// to DB2 databases within the Dedge system.
    /// </summary>
    /// <remarks>
    /// Features:
    /// - Executes SQL queries with error handling and logging
    /// - Supports transactions with automatic cleanup
    /// - Converts query results to various formats (JSON, XML, CSV, HTML)
    /// - Provides detailed SQL execution status information
    /// - Handles DB2-specific error codes and mappings
    /// </remarks>
    /// <author>Geir Helge Starholm</author>
    internal class Db2Handler : IDbHandler
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
        private DB2Connection? _currentConnection;
        private DB2Transaction? _currentTransaction;
        private bool _isInTransaction = false;
#pragma warning disable CS0414 // Field is assigned but its value is never used
        private bool _isAutoTransaction = false;
#pragma warning restore CS0414

        // Add DB2-specific error codes
        private enum Db2SqlError
        {
            // Success codes
            Success = DbSqlError.Success,
            NotFound = DbSqlError.NotFound,

            // DB2-specific error codes
            DuplicateKey = -803,
            ForeignKeyViolation = -530,
            DeleteRuleViolation = -532,
            UpdateRuleViolation = -533,
            NullNotAllowed = -407,
            ObjectNotFound = -204,
            ColumnNotFound = -206,
            ColumnAmbiguous = -205,
            NoPrivilege = -551,
            NoAuthorization = -552,
            NoConnectPrivilege = -553,

            UnknownError = DbSqlError.UnknownError
        }
        public SqlInfo _SqlInfo { get; set; }

        public DedgeConnection.DatabaseProvider Provider => DedgeConnection.DatabaseProvider.DB2;

        // Add public property with setter
        public string ConnectionString
        {
            get => _ConnectionString;
            set => _ConnectionString = value ?? throw new ArgumentNullException(nameof(value));
        }

        // Add constructors
        /// <summary>
        /// Initializes a new instance of the Db2Handler class with a connection key.
        /// </summary>
        /// <param name="connectionKey">The connection key containing environment and application info</param>
        /// <param name="overrideUID">Optional username to override configured credentials</param>
        /// <param name="overridePWD">Optional password to override configured credentials</param>
        public Db2Handler(DedgeConnection.ConnectionKey connectionKey, string? overrideUID = null, string? overridePWD = null)
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
                    DedgeNLog.Trace($"DB2 connection created with override credentials - Database: {accessPoint.DatabaseName}, Catalog: {accessPoint.CatalogName}, User: {overrideUID ?? accessPoint.UID}");
                }
                else if (useKerberos)
                {
                    string currentUser = $"{Environment.UserDomainName}\\{Environment.UserName}";
                    DedgeNLog.Trace($"DB2 connection created using current Windows user - Database: {accessPoint.DatabaseName}, Catalog: {accessPoint.CatalogName}, User: {currentUser} (Kerberos/SSO)");
                }
                else
                {
                    DedgeNLog.Trace($"DB2 connection created with configured credentials - Database: {accessPoint.DatabaseName}, Catalog: {accessPoint.CatalogName}, User: {accessPoint.UID}");
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
        public Db2Handler(string connectionString)
        {
            try
            {
                _ConnectionString = connectionString ?? throw new ArgumentNullException(nameof(connectionString));
                _SqlInfo = new SqlInfo();

                // Parse connection string to log database and authentication info
                var parts = connectionString.Split(';', StringSplitOptions.RemoveEmptyEntries);
                var database = parts.FirstOrDefault(p => p.StartsWith("Database=", StringComparison.OrdinalIgnoreCase))?.Split('=')[1] ?? "Unknown";
                var hasUID = parts.Any(p => p.StartsWith("UID=", StringComparison.OrdinalIgnoreCase));
                var hasKerberos = parts.Any(p => p.StartsWith("Authentication=Kerberos", StringComparison.OrdinalIgnoreCase));
                var uid = parts.FirstOrDefault(p => p.StartsWith("UID=", StringComparison.OrdinalIgnoreCase))?.Split('=')[1];
                
                if (hasKerberos)
                {
                    string currentUser = $"{Environment.UserDomainName}\\{Environment.UserName}";
                    DedgeNLog.Trace($"DB2 connection created using current Windows user - Catalog: {database}, User: {currentUser} (Kerberos/SSO)");
                }
                else if (hasUID && !string.IsNullOrEmpty(uid))
                {
                    DedgeNLog.Trace($"DB2 connection created with credentials - Catalog: {database}, User: {uid}");
                }
                else
                {
                    DedgeNLog.Trace($"DB2 connection created - Catalog: {database}");
                }
            }
            catch (Exception)
            {
                throw;
            }
        }

        /// <summary>
        /// Initializes a new instance using environment and application information
        /// </summary>
        public Db2Handler(
            DedgeConnection.FkEnvironment environment,
            DedgeConnection.FkApplication application = DedgeConnection.FkApplication.FKM,
            string version = "2.0",
            string instanceName = "DB2")
            : this(new DedgeConnection.ConnectionKey(application, environment, version, instanceName))
        {
        }

        // Implement all interface methods
        // ... copy implementations from SqlServerHandler, replacing SqlConnection with DB2Connection etc.

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

            DedgeNLog.Trace($"Executing SQL NonQuery - SQL: {sqlstring}, Parameters: {JsonConvert.SerializeObject(parameters)}, ExternalTransactionHandling: {externalTransactionHandling}");

            try
            {
                if (!_isInTransaction)
                {
                    _currentConnection = new DB2Connection(_ConnectionString);
                    DedgeNLog.Trace($"Opening new DB2 connection");
                    _currentConnection.Open();
                    DedgeNLog.Trace($"DB2 connection opened successfully");
                }

                if (shouldHandleTransaction)
                {
                    DedgeNLog.Trace($"Beginning new transaction");
                    _currentTransaction = _currentConnection?.BeginTransaction();
                    _isInTransaction = true;
                    _isAutoTransaction = true;
                    DedgeNLog.Trace($"Transaction began successfully");
                }

                using (DB2Command command = new DB2Command(sqlstring, _currentConnection))
                {
                    if (_isInTransaction && _currentTransaction != null)
                    {
                        command.Transaction = _currentTransaction;
                    }

                    // Set command timeout to 1200 seconds (20 minutes)
                    command.CommandTimeout = 1200;

                    foreach (var param in parameters)
                    {
                        command.Parameters.Add(new DB2Parameter(param.Key, param.Value ?? DBNull.Value));
                    }
                    ExecuteNonQueryCommand(command);

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
                        DedgeNLog.Trace($"Closing DB2 connection");
                        _currentConnection.Close();
                        DedgeNLog.Trace($"Disposing DB2 connection");
                        _currentConnection.Dispose();
                        _currentConnection = null;
                        DedgeNLog.Trace($"DB2 connection closed and disposed");
                    }
                }
            }
            catch (DB2Exception ex)
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
                    DedgeNLog.Trace($"Closing DB2 connection after error");
                    _currentConnection.Close();
                    DedgeNLog.Trace($"Disposing DB2 connection after error");
                    _currentConnection.Dispose();
                    _currentConnection = null;
                    DedgeNLog.Trace($"DB2 connection closed and disposed after error");
                }

                DedgeNLog.Error(ex, $"Error executing non-query SQL");
                if (throwException)
                    throw;
            }
        }

        public T? ExecuteScalar<T>(string sqlstring, Dictionary<string, object> parameters, bool throwException = false, bool externalTransactionHandling = false)
        {
            ThrowIfDisposed();
            bool shouldHandleTransaction = !externalTransactionHandling && !_isInTransaction;

            DedgeNLog.Trace($"Executing SQL Scalar<{typeof(T).Name}> - SQL: {sqlstring}, Parameters: {JsonConvert.SerializeObject(parameters)}, ExternalTransactionHandling: {externalTransactionHandling}");

            try
            {
                if (!_isInTransaction)
                {
                    _currentConnection = new DB2Connection(_ConnectionString);
                    DedgeNLog.Trace($"Opening new DB2 connection");
                    _currentConnection.Open();
                    DedgeNLog.Trace($"DB2 connection opened successfully");
                }

                if (shouldHandleTransaction)
                {
                    DedgeNLog.Trace($"Beginning new transaction");
                    _currentTransaction = _currentConnection?.BeginTransaction();
                    _isInTransaction = true;
                    _isAutoTransaction = true;
                    DedgeNLog.Trace($"Transaction began successfully");
                }

                using (DB2Command command = new DB2Command(sqlstring, _currentConnection))
                {
                    if (_isInTransaction && _currentTransaction != null)
                    {
                        command.Transaction = _currentTransaction;
                    }

                    // Set command timeout to 1200 seconds (20 minutes)
                    command.CommandTimeout = 1200;

                    foreach (var param in parameters)
                    {
                        command.Parameters.Add(new DB2Parameter(param.Key, param.Value ?? DBNull.Value));
                    }

                    ExecuteNonQueryCommand(command);

                    command.CommandText = "SELECT IDENTITY_VAL_LOCAL() FROM SYSIBM.SYSDUMMY1";
                    var result = command.ExecuteScalar();

                    var type = typeof(T);
                    if (type == typeof(int))
                    {
                        result = Convert.ToInt32(result);
                    }
                    else
                    {
                        result = Convert.ToInt64(result);
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
                        DedgeNLog.Trace($"Closing DB2 connection");
                        _currentConnection.Close();
                        DedgeNLog.Trace($"Disposing DB2 connection");
                        _currentConnection.Dispose();
                        _currentConnection = null;
                        DedgeNLog.Trace($"DB2 connection closed and disposed");
                    }

                    if (result == DBNull.Value)
                        return default(T)!;

                    return (T)Convert.ChangeType(result, typeof(T));
                }
            }
            catch (DB2Exception ex)
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
                    DedgeNLog.Trace($"Closing DB2 connection after error");
                    _currentConnection.Close();
                    DedgeNLog.Trace($"Disposing DB2 connection after error");
                    _currentConnection.Dispose();
                    _currentConnection = null;
                    DedgeNLog.Trace($"DB2 connection closed and disposed after error");
                }

                DedgeNLog.Error(ex, $"Error executing scalar SQL");
                if (throwException)
                    throw;

                return default(T)!;
            }
        }

        public void BeginTransaction()
        {
            ThrowIfDisposed();

            if (_isInTransaction)
            {
                throw new InvalidOperationException("Transaction already in progress");
            }

            try
            {
                _currentConnection = new DB2Connection(_ConnectionString);
                _currentConnection.Open();
                _currentTransaction = _currentConnection.BeginTransaction();
                _isInTransaction = true;
            }
            catch (Exception ex)
            {
                DedgeNLog.Error(ex, "Error beginning transaction");
                throw;
            }
        }

        public void CommitTransaction()
        {
            ThrowIfDisposed();

            if (!_isInTransaction)
            {
                throw new InvalidOperationException("No transaction in progress");
            }

            try
            {
                _currentTransaction?.Commit();
            }
            finally
            {
                CleanupTransaction();
            }
        }

        public void RollbackTransaction()
        {
            ThrowIfDisposed();

            if (!_isInTransaction)
            {
                throw new InvalidOperationException("No transaction in progress");
            }

            try
            {
                _currentTransaction?.Rollback();
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

        public List<dynamic> ConvertDataTableToListDynamicObject(DataTable dataTable, bool throwException = false)
        {
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

        public string ConvertDataTableToHtml(DataTable dataTable, bool throwException = false)
        {
            return ConvertDataTableToHtmlTable(dataTable, throwException);
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
                    if (dataTable.TableName == string.Empty)
                        dataTable.TableName = "Table"; // Set default table name (required for XML serialization
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
                    IEnumerable<string> fields = row.ItemArray.Select(field =>
                        field switch
                        {
                            null => string.Empty,
                            DBNull value => string.Empty,
                            _ => field.ToString() ?? string.Empty
                        });
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

        public SqlInfo GetSqlStatus(DataTable dataTable)
        {
            return GetSqlStatus(dataTable, null);
        }
        public SqlInfo GetSqlStatus()
        {
            return GetSqlStatus(null, null);
        }

        public string GetDatabaseName()
        {
            return _ConnectionKey != null ? DedgeConnection.GetDatabaseName(_ConnectionKey) : string.Empty;
        }

        // Add this method to Db2Handler class
        private DataTable ExecuteSqlMain(string sqlstring, bool throwException = false, bool externalTransactionHandling = false)
        {
            _DbSqlCode = DbSqlError.Success;
            _SqlStatement = sqlstring;
            _DbSqlRowsAffected = 0;
            _DbSqlRowCount = 0;


            ThrowIfDisposed();
            DataTable dataTable = new DataTable();
            bool shouldHandleTransaction = !externalTransactionHandling && !_isInTransaction;

            DedgeNLog.Trace($"Executing SQL Main - SQL: {sqlstring}, ThrowException: {throwException}, ExternalTransactionHandling: {externalTransactionHandling}");

            try
            {
                if (!_isInTransaction)
                {
                    _currentConnection = new DB2Connection(_ConnectionString);
                    DedgeNLog.Trace($"Opening new DB2 connection");
                    _currentConnection.Open();
                    DedgeNLog.Trace($"DB2 connection opened successfully");
                }

                if (shouldHandleTransaction)
                {
                    DedgeNLog.Trace($"Beginning new transaction");
                    _currentTransaction = _currentConnection?.BeginTransaction();
                    _isInTransaction = true;
                    _isAutoTransaction = true;
                    DedgeNLog.Trace($"Transaction began successfully");
                }

                using (DB2Command command = new DB2Command(sqlstring, _currentConnection))
                {
                    if (_isInTransaction && _currentTransaction != null)
                    {
                        command.Transaction = _currentTransaction;
                    }

                    // Set command timeout to 1200 seconds (20 minutes)
                    command.CommandTimeout = 1200;

                    // Execute the command and get the number of affected rows
                    if (sqlstring.ToUpper().StartsWith("SELECT", StringComparison.OrdinalIgnoreCase))
                    {
                        using (DB2DataAdapter adapter = new DB2DataAdapter(command))
                        {
                            adapter.Fill(dataTable);
                            _DbSqlRowCount = dataTable.Rows.Count;
                        }
                        if (_DbSqlRowCount == 0)
                        {
                            _DbSqlCode = DbSqlError.NotFound;
                        }
                    }
                    else
                    {
                        ExecuteNonQueryCommand(command);
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
                    DedgeNLog.Trace($"Closing DB2 connection");
                    _currentConnection.Close();
                    DedgeNLog.Trace($"Disposing DB2 connection");
                    _currentConnection.Dispose();
                    _currentConnection = null;
                    DedgeNLog.Trace($"DB2 connection closed and disposed");
                }
                _SqlInfo = GetSqlStatus(dataTable);
                dataTable.TableName = _SqlInfo.PrimaryTableName;
                return dataTable;
            }
            catch (DB2Exception ex)
            {
                dataTable.TableName = _SqlInfo.PrimaryTableName;
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
                    DedgeNLog.Trace($"Closing DB2 connection after error");
                    _currentConnection.Close();
                    DedgeNLog.Trace($"Disposing DB2 connection after error");
                    _currentConnection.Dispose();
                    _currentConnection = null;
                    DedgeNLog.Trace($"DB2 connection closed and disposed after error");
                }

                DedgeNLog.Error(ex, $"Error executing SQL");
                if (throwException)
                    throw;

                return dataTable;
            }
        }

        private void ExecuteNonQueryCommand(DB2Command command)
        {
            try
            {
                _DbSqlCode = DbSqlError.Success;
                _DbSqlRowCount = 0;
                _SqlStatement = command.CommandText;
                _DbSqlRowsAffected = command.ExecuteNonQuery();
                if (_DbSqlRowsAffected == 0)
                {
                    _DbSqlCode = DbSqlError.NotFound;
                }
                _SqlInfo = GetSqlStatus();

            }
            catch (DB2Exception ex)
            {
                _DbSqlCode = MapDb2ErrorToDbSqlError(ex.ErrorCode);
                _SqlInfo = GetSqlStatus(null, ex);
                throw;
            }        }

        // Add this method to handle GetSqlStatus with DB2Exception
        public SqlInfo GetSqlStatus(DataTable? dataTable = null, DB2Exception? db2Exception = null)
        {
            SqlInfo sqlInfo = new();
            sqlInfo.SqlCode = _DbSqlCode;
            sqlInfo.RowCount = _DbSqlRowCount;
            sqlInfo.SqlStatement = _SqlStatement;

            if (db2Exception != null)
            {
                sqlInfo.ExeceptionMessage = db2Exception.Message;
                sqlInfo.InnerExeceptionMessage = db2Exception.InnerException?.Message;
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
                    sqlInfo.SqlCodeShortDescription = db2Exception?.Message ?? "Unknown Error";
                    sqlInfo.SqlCodeDescription = db2Exception?.Message ?? "Unknown DB2 Error";
                    break;
            }
            if (dataTable != null)
            {
                sqlInfo.RowCount = dataTable.Rows.Count;
                sqlInfo.PrimaryTableName = dataTable.TableName;
                if (sqlInfo.PrimaryTableName == "")
                {
                    sqlInfo.PrimaryTableName = sqlInfo.SqlStatement;
                }
            }
            else
            {
                sqlInfo.PrimaryTableName = "Result";
            }
            // if (sqlInfo.PrimaryTableName == "")
            // {
            //     // if sqlstatement start with create.*View in regex 
            //     if (Regex.IsMatch(sqlInfo.SqlStatement, @"^CREATE\s+\w+\s+VIEW\s+", RegexOptions.IgnoreCase))
            //     {
            //         sqlInfo.PrimaryTableName = "Result";
            //     }
            //     // find first operation in sqlstring

            //     string[] sqlParts = sqlInfo.SqlStatement.Split(" ");
            //     // depending on operation, set primary table name
            //     if (sqlParts.Length > 1)
            //     {
            //         string operation = "";
            //         foreach (string part in sqlParts)
            //         {
            //             if (operation != "")
            //             {
            //                 break;
            //             }
            //             switch (part)
            //             {
            //                 case "INSERT":
            //                     operation = "INSERT";
            //                     break;
            //                 case "UPDATE":
            //                     operation = "UPDATE";
            //                     break;
            //                 case "DELETE":
            //                     operation = "DELETE";
            //                     break;
            //                 case "SELECT":
            //                     operation = "SELECT";
            //                     break;
            //                 case "MERGE":
            //                     // ignoring this to find first statment in merge statement
            //                     operation = "";
            //                     break;
            //                 case "CREATE":
            //                     // ignoring this to find first statment in potential view or summary view
            //                     operation = "";
            //                     break;
            //                 case "ALTER":
            //                     operation = "ALTER";
            //                     break;
            //                 case "DROP":
            //                     operation = "DROP";
            //                     break;
            //                 case "GRANT":
            //                     operation = "GRANT";
            //                     break;
            //                 case "REVOKE":
            //                     operation = "REVOKE";
            //                     break;
            //                 default:
            //                     operation = "";
            //                     break;
            //             }
            //             // check if operation is ALTER DROP GRANT OR REVOKE set primary table name to Result and exit loop
            //             if (operation == "ALTER" || operation == "DROP" || operation == "GRANT" || operation == "REVOKE")
            //             {
            //                 sqlInfo.PrimaryTableName = "Result";
            //                 break;
            //             }

            //             switch (operation)
            //             {
            //                 case "INSERT":
            //                     // get first keyword after INSERT
            //                     sqlInfo.PrimaryTableName
            //                     break;
            //             }
            //         }

            return sqlInfo;
        }

        // Add this enhanced method to map DB2 errors to DbSqlError enum
        // Note: This method must NOT call DedgeNLog methods that trigger database logging
        // to avoid infinite recursion when the database connection itself is failing
        private DbSqlError MapDb2ErrorToDbSqlError(int db2ErrorNumber)
        {
            switch (db2ErrorNumber)
            {
                case (int)Db2SqlError.Success:
                    return DbSqlError.Success;
                case (int)Db2SqlError.DuplicateKey:
                    return DbSqlError.NotFound;
                case (int)Db2SqlError.ForeignKeyViolation:
                case (int)Db2SqlError.DeleteRuleViolation:
                case (int)Db2SqlError.UpdateRuleViolation:
                    return DbSqlError.NotFound;
                case (int)Db2SqlError.NullNotAllowed:
                    return DbSqlError.NotFound;
                case (int)Db2SqlError.ObjectNotFound:
                case (int)Db2SqlError.ColumnNotFound:
                case (int)Db2SqlError.ColumnAmbiguous:
                    return DbSqlError.NotFound;
                case (int)Db2SqlError.NoPrivilege:
                case (int)Db2SqlError.NoAuthorization:
                case (int)Db2SqlError.NoConnectPrivilege:
                    return DbSqlError.NotFound;
                // Security/authentication errors - common causes of connection failures
                case -30082: // Security processing failed
                case -30081: // Communication errors
                case -1060:  // Connection refused
                case -1024:  // Database connection error
                    // Use Console.WriteLine to avoid triggering database logging which would cause infinite recursion
                    Console.WriteLine($"DB2 connection/security error: {db2ErrorNumber}");
                    return DbSqlError.UnknownError;
                default:
                    // Use Console.WriteLine instead of DedgeNLog.Warn to prevent infinite recursion
                    // when database logging itself is failing
                    Console.WriteLine($"Unmapped DB2 error code: {db2ErrorNumber}");
                    return DbSqlError.UnknownError;
            }
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

                // Clean up unmanaged resources (if any)

                _isDisposed = true;
            }
        }

        ~Db2Handler()
        {
            Dispose(false);
        }

        private void ThrowIfDisposed()
        {
            if (_isDisposed)
            {
                throw new ObjectDisposedException(nameof(Db2Handler));
            }
        }

        public void ExecuteAtomicNonQuery(string sqlstring, Dictionary<string, object> parameters, bool throwException = false, bool externalTransactionHandling = false)
        {
            _DbSqlCode = DbSqlError.Success;
            _SqlStatement = sqlstring;
            _DbSqlRowsAffected = 0;
            _DbSqlRowCount = 0;

            ThrowIfDisposed();
            bool shouldHandleTransaction = !externalTransactionHandling && !_isInTransaction;

            try
            {
                if (!_isInTransaction)
                {
                    _currentConnection = new DB2Connection(_ConnectionString);
                    _currentConnection.Open();
                }

                if (shouldHandleTransaction)
                {
                    _currentTransaction = _currentConnection?.BeginTransaction();
                    _isInTransaction = true;
                    _isAutoTransaction = true;
                }

                using (DB2Command command = new DB2Command(sqlstring, _currentConnection))
                {
                    if (_isInTransaction && _currentTransaction != null)
                    {
                        command.Transaction = _currentTransaction;
                    }

                    // Set command timeout to 1200 seconds (20 minutes)
                    command.CommandTimeout = 1200;

                    foreach (var param in parameters)
                    {
                        command.Parameters.Add(new DB2Parameter(param.Key, param.Value ?? DBNull.Value));
                    }

                    _DbSqlRowsAffected = command.ExecuteNonQuery();
                    _SqlInfo = GetSqlStatus();

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
                }
            }
            catch (DB2Exception ex)
            {
                _DbSqlCode = ex.Errors[0].NativeError == 0 ? DbSqlError.UnknownError : MapDb2ErrorToDbSqlError(ex.Errors[0].NativeError);
                _SqlInfo = GetSqlStatus(null, ex);

                if (shouldHandleTransaction)
                {
                    _currentTransaction?.Rollback();
                    _isInTransaction = false;
                    _isAutoTransaction = false;
                }

                if (!_isInTransaction && _currentConnection != null)
                {
                    _currentConnection.Close();
                    _currentConnection.Dispose();
                    _currentConnection = null;
                }

                throw;
            }
        }

        public T ExecuteAtomicScalar<T>(string sqlstring, Dictionary<string, object> parameters, bool throwException = false, bool externalTransactionHandling = false)
        {
            _DbSqlCode = DbSqlError.Success;
            _SqlStatement = sqlstring;
            _DbSqlRowsAffected = 0;
            _DbSqlRowCount = 0;


            ThrowIfDisposed();
            bool shouldHandleTransaction = !externalTransactionHandling && !_isInTransaction;

            DedgeNLog.Trace($"Executing Atomic Scalar<{typeof(T).Name}> - SQL: {sqlstring}, Parameters: {JsonConvert.SerializeObject(parameters)}, ExternalTransactionHandling: {externalTransactionHandling}");

            try
            {
                if (!_isInTransaction)
                {
                    _currentConnection = new DB2Connection(_ConnectionString);
                    DedgeNLog.Trace($"Opening new DB2 connection");
                    _currentConnection.Open();
                    DedgeNLog.Trace($"DB2 connection opened successfully");
                }

                if (shouldHandleTransaction)
                {
                    DedgeNLog.Trace($"Beginning new transaction");
                    _currentTransaction = _currentConnection?.BeginTransaction();
                    _isInTransaction = true;
                    _isAutoTransaction = true;
                    DedgeNLog.Trace($"Transaction began successfully");
                }

                using (DB2Command command = new DB2Command(sqlstring, _currentConnection))
                {
                    if (_isInTransaction && _currentTransaction != null)
                    {
                        command.Transaction = _currentTransaction;
                    }

                    // Set command timeout to 1200 seconds (20 minutes)
                    command.CommandTimeout = 1200;

                    foreach (var param in parameters)
                    {
                        command.Parameters.Add(new DB2Parameter(param.Key, param.Value ?? DBNull.Value));
                    }
                    _DbSqlRowsAffected =                    command.ExecuteNonQuery();
                    _SqlInfo = GetSqlStatus();

                    command.CommandText = "SELECT IDENTITY_VAL_LOCAL() FROM SYSIBM.SYSDUMMY1";
                    var result = command.ExecuteScalar();

                    var type = typeof(T);
                    if (type == typeof(int))
                    {
                        result = Convert.ToInt32(result);
                    }
                    else
                    {
                        result = Convert.ToInt64(result);
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
                        DedgeNLog.Trace($"Closing DB2 connection");
                        _currentConnection.Close();
                        DedgeNLog.Trace($"Disposing DB2 connection");
                        _currentConnection.Dispose();
                        _currentConnection = null;
                        DedgeNLog.Trace($"DB2 connection closed and disposed");
                    }

                    if (result == DBNull.Value)
                        return default(T)!;

                    return (T)Convert.ChangeType(result, typeof(T));
                }
            }
            catch (DB2Exception ex)
            {
                _DbSqlCode = ex.Errors[0].NativeError == 0 ? DbSqlError.UnknownError : MapDb2ErrorToDbSqlError(ex.Errors[0].NativeError);
                _SqlInfo = GetSqlStatus(null, ex);

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
                    DedgeNLog.Trace($"Closing DB2 connection after error");
                    _currentConnection.Close();
                    DedgeNLog.Trace($"Disposing DB2 connection after error");
                    _currentConnection.Dispose();
                    _currentConnection = null;
                    DedgeNLog.Trace($"DB2 connection closed and disposed after error");
                }

                DedgeNLog.Error(ex, $"Error executing atomic scalar SQL");
                if (throwException)
                    throw;

                return default(T)!;
            }
        }

        // Add this method to handle DB2 exceptions
        private void HandleDb2Exception(DB2Exception ex, bool throwException)
        {
            _DbSqlRowsAffected = -1;
            _DbSqlCode = MapDb2ErrorToDbSqlError(ex.Errors[0].NativeError);

            DedgeNLog.Error(ex, $"Error executing SQL. Error Number: {ex.Errors[0].NativeError}");

            if (throwException)
                throw ex;
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
    }
}