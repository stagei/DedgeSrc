using System.Data;

namespace DedgeCommon
{
    /// <summary>
    /// Defines the contract for database handlers in the Dedge system.
    /// Provides a standardized interface for database operations regardless
    /// of the underlying database provider.
    /// </summary>
    /// <remarks>
    /// Features:
    /// - Common database operation definitions
    /// - Transaction management
    /// - Query result format conversion
    /// - Error handling and status reporting
    /// - Resource cleanup through IDisposable
    /// - Async operation support
    /// </remarks>
    /// <author>Geir Helge Starholm</author>
    public interface IDbHandler : IDisposable
    {
        /// <summary>
        /// Gets or sets the connection string for the database
        /// </summary>
        string ConnectionString { get; set; }

        /// <summary>
        /// Gets the SQL execution status information
        /// </summary>
        SqlInfo _SqlInfo { get; set; }

        /// <summary>
        /// Executes a SQL query and returns results as a DataTable
        /// </summary>
        DataTable ExecuteQueryAsDataTable(string sqlstring, bool throwException = false, bool externalTransactionHandling = false);

        /// <summary>
        /// Executes a SQL query and returns results as HTML
        /// </summary>
        string ExecuteQueryAsHtml(string sqlstring, bool throwException = false, bool externalTransactionHandling = false);

        /// <summary>
        /// Executes a SQL query and returns results as JSON
        /// </summary>
        string ExecuteQueryAsJson(string sqlstring, bool throwException = false, bool indented = true, bool externalTransactionHandling = false);

        /// <summary>
        /// Executes a SQL query and returns results as XML
        /// </summary>
        string ExecuteQueryAsXml(string sqlstring, bool throwException = false, bool externalTransactionHandling = false);

        /// <summary>
        /// Executes a SQL query and returns results as CSV
        /// </summary>
        string ExecuteQueryAsCsv(string sqlstring, string delimiter = ";", bool throwException = false, bool externalTransactionHandling = false);

        /// <summary>
        /// Executes a SQL query and returns results as a list of dynamic objects
        /// </summary>
        List<dynamic> ExecuteQueryAsDynamicList(string sqlstring, bool throwException = false, bool externalTransactionHandling = false);

        /// <summary>
        /// Executes a SQL query and returns results as a strongly typed list
        /// </summary>
        List<T> ExecuteQueryAsList<T>(string sqlstring, bool throwException = false, bool externalTransactionHandling = false);

        /// <summary>
        /// Executes a SQL statement without returning results
        /// </summary>
        void ExecuteNonQueryVoid(string sqlstring, bool throwException = false, bool externalTransactionHandling = false);

        /// <summary>
        /// Executes a SQL statement and returns the number of rows affected
        /// </summary>
        int ExecuteNonQuery(string sqlstring, bool throwException = false, bool externalTransactionHandling = false);

        /// <summary>
        /// Executes a SQL statement with parameters and returns the number of rows affected
        /// </summary>
        void ExecuteNonQuery(string sqlstring, Dictionary<string, object> parameters, bool throwException = false, bool externalTransactionHandling = false);

        /// <summary>
        /// Executes a SQL query and returns a scalar value
        /// </summary>
        T? ExecuteScalar<T>(string sqlstring, Dictionary<string, object> parameters, bool throwException = false, bool externalTransactionHandling = false);

        /// <summary>
        /// Begins a database transaction
        /// </summary>
        void BeginTransaction();

        /// <summary>
        /// Commits the current transaction
        /// </summary>
        void CommitTransaction();

        /// <summary>
        /// Rolls back the current transaction
        /// </summary>
        void RollbackTransaction();

        /// <summary>
        /// Converts a DataTable to a list of dynamic objects
        /// </summary>
        List<dynamic> ConvertDataTableToListDynamicObject(DataTable dataTable, bool throwException = false);

        /// <summary>
        /// Converts a DataTable to HTML format
        /// </summary>
        string ConvertDataTableToHtml(DataTable dataTable, bool throwException = false);

        /// <summary>
        /// Converts a DataTable to JSON format
        /// </summary>
        string ConvertDataTableToJson(DataTable dataTable, bool throwException = false, bool indented = true);

        /// <summary>
        /// Converts a DataTable to XML format
        /// </summary>
        string ConvertDataTableToXml(DataTable dataTable, bool throwException = false);

        /// <summary>
        /// Converts a DataTable to CSV format
        /// </summary>
        string ConvertDataTableToCsv(DataTable dataTable, bool throwException = false);

        /// <summary>
        /// Gets the SQL execution status information for a DataTable
        /// </summary>
        SqlInfo GetSqlStatus(DataTable dataTable);

        /// <summary>
        /// Gets the database provider for the database handler
        /// </summary>
        DedgeConnection.DatabaseProvider Provider { get; }

        // Explicitly implementing IDisposable
        new void Dispose();
        string GetDatabaseName();

        void ExecuteAtomicNonQuery(string sqlstring, Dictionary<string, object> parameters, bool throwException = false, bool externalTransactionHandling = false);
        T ExecuteAtomicScalar<T>(string sqlstring, Dictionary<string, object> parameters, bool throwException = false, bool externalTransactionHandling = false);

        // Add static factory methods
        public static IDbHandler Create(string connectionString, DedgeConnection.DatabaseProvider provider)
        {
            return provider switch
            {
                DedgeConnection.DatabaseProvider.DB2 => new Db2Handler(connectionString),
                DedgeConnection.DatabaseProvider.SQLSERVER => new SqlServerHandler(connectionString),
                DedgeConnection.DatabaseProvider.POSTGRESQL => new PostgresHandler(connectionString),
                _ => throw new ArgumentException($"Unsupported database provider: {provider}")
            };
        }

        /// <summary>
        /// Creates a database handler using a ConnectionKey.
        /// </summary>
        public static IDbHandler Create(DedgeConnection.ConnectionKey connectionKey)
        {
            var accessPoint = DedgeConnection.GetConnectionStringInfo(connectionKey);
            return accessPoint.ProviderEnum switch
            {
                DedgeConnection.DatabaseProvider.DB2 => new Db2Handler(connectionKey),
                DedgeConnection.DatabaseProvider.SQLSERVER => new SqlServerHandler(connectionKey),
                DedgeConnection.DatabaseProvider.POSTGRESQL => new PostgresHandler(connectionKey),
                _ => throw new ArgumentException($"Unsupported database provider: {accessPoint.ProviderEnum}")
            };
        }
    }
}