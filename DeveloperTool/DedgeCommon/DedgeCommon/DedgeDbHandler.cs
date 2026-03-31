namespace DedgeCommon
{
    /// <summary>
    /// Factory class for creating appropriate database handlers based on connection configuration.
    /// Provides a unified interface for database operations while abstracting the underlying
    /// database provider implementation.
    /// </summary>
    public static class DedgeDbHandler
    {
        private static readonly DedgeNLog _Logger = new DedgeNLog();

        /// <summary>
        /// Creates a database handler using a ConnectionKey.
        /// </summary>
        public static IDbHandler Create(DedgeConnection.ConnectionKey connectionKey,bool logCreation = true)
        {
            try
            {
                var accessPoint = DedgeConnection.GetConnectionStringInfo(connectionKey);
                if (logCreation)
                    LogHandlerCreation(accessPoint);
                return CreateFromProvider(connectionKey);
            }
            catch (Exception ex)
            {
                if (logCreation)
                    DedgeNLog.Error(ex, $"Error creating database handler");
                throw;
            }
        }

        /// <summary>
        /// Creates a database handler using environment and application information.
        /// </summary>
        public static IDbHandler Create(
            DedgeConnection.FkEnvironment environment,
            DedgeConnection.FkApplication application = DedgeConnection.FkApplication.FKM,
            string version = "2.0",
            string instanceName = "DB2")
        {
            var connectionKey = new DedgeConnection.ConnectionKey(application, environment, version, instanceName);
            return Create(connectionKey);
        }

        /// <summary>
        /// Creates a database handler directly from a database name.
        /// This method finds the specific access point and creates the handler without intermediate ConnectionKey lookup.
        /// </summary>
        public static IDbHandler CreateByDatabaseName(string databaseName, bool logCreation = true)
        {
            try
            {
                var accessPoint = DedgeConnection.GetAccessPointByDatabaseName(databaseName);
                if (logCreation)
                    LogHandlerCreation(accessPoint);
                
                var connectionString = DedgeConnection.GenerateConnectionString(accessPoint);
                return accessPoint.ProviderEnum switch
                {
                    DedgeConnection.DatabaseProvider.DB2 => new Db2Handler(connectionString),
                    DedgeConnection.DatabaseProvider.SQLSERVER => new SqlServerHandler(connectionString),
                    DedgeConnection.DatabaseProvider.POSTGRESQL => new PostgresHandler(connectionString),
                    _ => throw new ArgumentException($"Unsupported database provider: {accessPoint.ProviderEnum}")
                };
            }
            catch (Exception ex)
            {
                if (logCreation)
                    DedgeNLog.Error(ex, $"Error creating database handler for database name: {databaseName}");
                throw;
            }
        }

        /// <summary>
        /// Creates a database handler using a connection string and provider.
        /// </summary>
        public static IDbHandler Create(string connectionString, DedgeConnection.DatabaseProvider provider)
        {
            try
            {
                return provider switch
                {
                    DedgeConnection.DatabaseProvider.DB2 => new Db2Handler(connectionString),
                    DedgeConnection.DatabaseProvider.SQLSERVER => new SqlServerHandler(connectionString),
                    DedgeConnection.DatabaseProvider.POSTGRESQL => new PostgresHandler(connectionString),
                    _ => throw new ArgumentException($"Unsupported database provider: {provider}")
                };
            }
            catch (Exception ex)
            {
                DedgeNLog.Error(ex, $"Error creating database handler with connection string");
                throw;
            }
        }

        private static IDbHandler CreateFromProvider(DedgeConnection.ConnectionKey connectionKey)
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

        private static void LogHandlerCreation(DedgeConnection.FkDatabaseAccessPoint accessPoint)
        {
            DedgeNLog.Info($"Creating database handler - FkApplication: {accessPoint.ApplicationEnum}, " +
                        $"Environment: {accessPoint.EnvironmentEnum}, " +
                        $"Version: {accessPoint.Version}, " +
                        $"DatabaseName: {accessPoint.DatabaseName}, " +
                        $"Server: {accessPoint.Server}, " +
                        $"Provider: {accessPoint.ProviderEnum}, " +
                        $"Instance: {accessPoint.InstanceName}");
        }
    }
}