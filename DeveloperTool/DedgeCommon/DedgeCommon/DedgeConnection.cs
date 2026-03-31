using static System.Net.Mime.MediaTypeNames;
using System.Text.Json;

namespace DedgeCommon
{
    /// <summary>
    /// Represents a database configuration loaded from JSON.
    /// </summary>
    public class FkDatabaseConfig
    {
        public string Database { get; set; } = string.Empty;
        public string Provider { get; set; } = string.Empty;
        public string Application { get; set; } = string.Empty;
        public string Environment { get; set; } = string.Empty;
        public string Version { get; set; } = string.Empty;
        public string PrimaryCatalogName { get; set; } = string.Empty;
        public bool IsActive { get; set; }
        public string ServerName { get; set; } = string.Empty;
        public string Description { get; set; } = string.Empty;
        public string NorwegianDescription { get; set; } = string.Empty;
        public List<AccessPoint> AccessPoints { get; set; } = new List<AccessPoint>();
    }

    /// <summary>
    /// Represents an access point configuration for a database.
    /// </summary>
    public class AccessPoint
    {
        public string InstanceName { get; set; } = string.Empty;
        public string CatalogName { get; set; } = string.Empty;
        public string AccessPointType { get; set; } = string.Empty;
        public string Port { get; set; } = string.Empty;
        public string ServiceName { get; set; } = string.Empty;
        public string NodeName { get; set; } = string.Empty;
        public string AuthenticationType { get; set; } = string.Empty;
        public string UID { get; set; } = string.Empty;
        public string PWD { get; set; } = string.Empty;
        public bool IsActive { get; set; }
    }



    /// <summary>
    /// Provides centralized management of database connections across different environments.
    /// This class handles connection string generation, environment configuration, and
    /// connection information retrieval for all Dedge database systems.
    /// </summary>
    /// <remarks>
    /// Features:
    /// - Supports multiple database providers (DB2, SQL Server)
    /// - Environment-specific connection management (DEV, TST, PRD, etc.)
    /// - Version-aware connection handling
    /// - Secure credential management with Kerberos/SSO support
    /// - Connection string validation and formatting
    /// - Detailed logging of connection activities
    /// 
    /// Access Point Types:
    /// - Alias: Application access point (e.g., BASISTST on port 3711) - THIS IS WHAT APPLICATIONS USE
    /// - PrimaryDb: Administrative/direct database access (e.g., FKMTST on port 50000) - ONLY for finding the real database, NOT for connections
    /// - PrimaryCatalogName: Points to the Alias that applications should use
    /// 
    /// IMPORTANT: Application connections ALWAYS use the Alias named in PrimaryCatalogName, NEVER the PrimaryDb.
    /// 
    /// Authentication:
    /// - When AuthenticationType is "Kerberos", Windows integrated authentication (SSO) is used by default
    /// - UID/PWD from configuration are ignored for Kerberos authentication (unless explicitly overridden)
    /// - Override credentials can be provided to all connection string methods when needed
    /// - For SQL Server with Kerberos, "Integrated Security=SSPI" is used in the connection string
    /// </remarks>
    /// <author>Geir Helge Starholm</author>
    public static class DedgeConnection
    {

        /// <summary>
        /// Represents the supported database providers.
        /// </summary>
        public enum DatabaseProvider
        {
            /// <summary>IBM DB2 Database</summary>
            DB2,
            /// <summary>Microsoft SQL Server</summary>
            SQLSERVER,
            /// <summary>PostgreSQL Database</summary>
            POSTGRESQL
        }

        /// <summary>
        /// Represents the available database environments in the Dedge system.
        /// </summary>
        /// 
        public enum FkEnvironment
        {
            /// <summary>Development environment</summary>
            DEV,
            /// <summary>Test environment</summary>
            TST,
            /// <summary>Production environment</summary>
            PRD,
            /// <summary>Migration environment</summary>
            MIG,
            /// <summary>System Integration Test environment</summary>
            SIT,
            /// <summary>Verification Test environment</summary>
            VFT,
            /// <summary>Verification acceptance environment</summary>
            VFK,
            /// <summary>Dedge Functional test for forsprang environment</summary>
            KAT,
            /// <summary>Dedge functional test environment</summary>
            FUT,
            /// <summary>Dedge history environment</summary>
            HST,
            /// <summary>Dedge report environment</summary>
            RAP,
            /// <summary>Performance test environment</summary>
            PER,
        }

        /// <summary>
        /// Represents the different applications in the Dedge system.
        /// </summary>
        public enum FkApplication
        {
            /// <summary>FK Meny application</summary>
            FKM,

            /// <summary>Innlån application</summary>
            INL,

            /// <summary>Dedge History application</summary>
            HST,

            /// <summary>Visma accounting application</summary>
            VIS,

            /// <summary>Vareregister application</summary>
            VAR,

            /// <summary>Agriprod application</summary>
            AGP,

            /// <summary>Agrikorn application</summary>
            AGK,

            /// <summary>DBQA application</summary>
            DBQA,

            /// <summary>FKX application</summary>
            FKX,

            /// <summary>COBDOK application</summary>
            DOC
        }


        /// <summary>
        /// Represents a flattened database access point with all database properties included.
        /// This is the main object used for lookups and operations.
        /// </summary>
        public class FkDatabaseAccessPoint
        {
            // Main database properties
            public string PossibleKey { get; set; } = string.Empty;
            public string FkApplication { get; set; } = string.Empty;
            public string Environment { get; set; } = string.Empty;
            public string Version { get; set; } = string.Empty;
            public string InstanceName { get; set; } = string.Empty;
            public string Provider { get; set; } = string.Empty;
            public int PriorityIndex { get; set; }


            public string DatabaseName { get; set; } = string.Empty;
            public string DatabaseGroupName { get; set; } = string.Empty;
            public string PrimaryCatalogName { get; set; } = string.Empty;
            public bool IsDatabaseActive { get; set; }
            public string ServerName { get; set; } = string.Empty;
            public string Description { get; set; } = string.Empty;
            public string NorwegianDescription { get; set; } = string.Empty;

            public string CatalogName { get; set; } = string.Empty;
            public string AccessPointType { get; set; } = string.Empty;
            public string Port { get; set; } = string.Empty;
            public string ServiceName { get; set; } = string.Empty;
            public string NodeName { get; set; } = string.Empty;
            public string AuthenticationType { get; set; } = string.Empty;
            public string UID { get; set; } = string.Empty;
            public string PWD { get; set; } = string.Empty;
            public bool IsActive { get; set; }

            /// <summary>
            /// Gets the full server address with port.
            /// </summary>
            public string Server => $"{ServerName}:{Port}";

            /// <summary>
            /// Gets the parsed application enum.
            /// </summary>
            public FkApplication ApplicationEnum => ParseApplication(FkApplication);

            /// <summary>
            /// Gets the parsed environment enum.
            /// </summary>
            public FkEnvironment EnvironmentEnum => ParseEnvironment(Environment);

            /// <summary>
            /// Gets the parsed provider enum.
            /// </summary>
            public DatabaseProvider ProviderEnum => ParseProvider(Provider);
        }

        /// <summary>
        /// Represents a composite key for connection string lookup.
        /// </summary>
        public class ConnectionKey
        {
            public FkApplication Application { get; set; } = FkApplication.FKM;
            public FkEnvironment Environment { get; set; }
            public string Version { get; set; } = "2.0";
            public string InstanceName { get; set; } = "DB2";

            public ConnectionKey(FkApplication application, FkEnvironment environment, string version = "2.0", string instanceName = "DB2")
            {
                Application = application;
                Environment = environment;
                Version = string.IsNullOrEmpty(version) ? "2.0" : version;
                InstanceName = string.IsNullOrEmpty(instanceName) ? "DB2" : instanceName;
            }

            public override bool Equals(object? obj)
            {
                if (obj is not ConnectionKey other) return false;
                return Application == other.Application &&
                       Environment == other.Environment &&
                       Version == other.Version &&
                       InstanceName == other.InstanceName;
            }

            public override int GetHashCode()
            {
                return HashCode.Combine(Application, Environment, Version, InstanceName);
            }
        }

        /// <summary>
        /// Represents a composite key for access point connection string lookup.
        /// Includes InstanceName to distinguish between different access points.
        /// </summary>
        public class AccessPointConnectionKey
        {
            public FkApplication Application { get; set; }
            public FkEnvironment Environment { get; set; }
            public string InstanceName { get; set; } = string.Empty;
            public string Version { get; set; } = "2.0";

            public AccessPointConnectionKey(FkApplication application, FkEnvironment environment, string instanceName, string version = "2.0")
            {
                Application = application;
                Environment = environment;
                InstanceName = instanceName ?? string.Empty;
                Version = string.IsNullOrEmpty(version) ? "2.0" : version;
            }

            public override bool Equals(object? obj)
            {
                if (obj is not AccessPointConnectionKey other) return false;
                return Application == other.Application &&
                       Environment == other.Environment &&
                       InstanceName == other.InstanceName &&
                       Version == other.Version;
            }

            public override int GetHashCode()
            {
                return HashCode.Combine(Application, Environment, Version, InstanceName);
            }
        }

        /// <summary>
        /// Represents current version information for an application and environment combination.
        /// Includes instance name to distinguish between different access points.
        /// </summary>
        public class CurrentVersionInfo
        {
            public FkApplication Application { get; set; }
            public FkEnvironment Environment { get; set; }
            public string Version { get; set; } = string.Empty;
            public string InstanceName { get; set; } = string.Empty;
            public string Provider { get; set; } = string.Empty;
            public bool IsDatabaseActive { get; set; }

            public CurrentVersionInfo(FkApplication application, FkEnvironment environment, string version, string instanceName = "DB2", string provider = "DB2")
            {
                Application = application;
                Environment = environment;
                Version = version;
                InstanceName = instanceName;
                Provider = provider;
            }
        }

        /// <summary>
        /// Manages loading and caching of JSON configuration data.
        /// </summary>
        public static class FkConfigurationManager
        {
            private static readonly string ConfigFilePath = @"C:\opt\src\DedgeSrc\DedgeSystemTools\Folders\DedgeCommon\Configfiles\DatabasesV2.json";
            private static List<FkDatabaseConfig>? _configurations;
            private static List<FkDatabaseAccessPoint>? _accessPoints;
            private static DateTime _lastLoadTime;
            private static readonly TimeSpan CacheExpiry = TimeSpan.FromMinutes(5);
            private static readonly object _lockObject = new object();

            public static List<FkDatabaseConfig> GetConfigurations()
            {
                if (_configurations == null || DateTime.Now - _lastLoadTime > CacheExpiry)
                {
                    lock (_lockObject)
                    {
                        if (_configurations == null || DateTime.Now - _lastLoadTime > CacheExpiry)
                        {
                            LoadConfigurations();
                        }
                    }
                }
                return _configurations ?? new List<FkDatabaseConfig>();
            }

            /// <summary>
            /// Gets the flattened access points array with all database properties included.
            /// </summary>
            public static List<FkDatabaseAccessPoint> GetAccessPoints()
            {
                if (_accessPoints == null || DateTime.Now - _lastLoadTime > CacheExpiry)
                {
                    lock (_lockObject)
                    {
                        if (_accessPoints == null || DateTime.Now - _lastLoadTime > CacheExpiry)
                        {
                            LoadAccessPoints();
                        }
                    }
                }
                return _accessPoints ?? new List<FkDatabaseAccessPoint>();
            }

            private static void LoadConfigurations()
            {
                try
                {
                    var json = File.ReadAllText(ConfigFilePath);
                    _configurations = JsonSerializer.Deserialize<List<FkDatabaseConfig>>(json);
                    _configurations = _configurations?.Where(c => c.IsActive).ToList();
                    _lastLoadTime = DateTime.Now;
                    DedgeNLog.Info($"Successfully loaded {_configurations?.Count ?? 0} database configurations from {ConfigFilePath}");
                }
                catch (FileNotFoundException)
                {
                    DedgeNLog.Error($"Configuration file not found: {ConfigFilePath}");
                    throw new InvalidOperationException("DatabaseName configuration file not found");
                }
                catch (JsonException ex)
                {
                    DedgeNLog.Error($"Invalid JSON in configuration file: {ex.Message}");
                    throw new InvalidOperationException("Invalid configuration file format");
                }
                catch (Exception ex)
                {
                    DedgeNLog.Error($"Failed to load configuration from {ConfigFilePath}: {ex.Message}");
                    throw;
                }
            }

            private static void LoadAccessPoints()
            {
                try
                {
                    var configurations = GetConfigurations();
                    _accessPoints = new List<FkDatabaseAccessPoint>();

                    foreach (var config in configurations)
                    {

                        int priorityCounter = 1;

                        // Load in priority order: PrimaryCatalogName first (for applications), then Aliases, then PrimaryDb (administrative/direct connections)
                        var primaryCatalogAccessPoints = config.AccessPoints?.Where(ap => ap.CatalogName == config.PrimaryCatalogName).ToList() ??
                                                  new List<AccessPoint>();
                        foreach (var accessPoint in primaryCatalogAccessPoints)
                        {
                            var flattenedAccessPoint = new FkDatabaseAccessPoint
                            {
                                DatabaseName = config.Database,
                                DatabaseGroupName = config.Database,
                                Provider = config.Provider,
                                FkApplication = config.Application,
                                Environment = config.Environment,
                                Version = config.Version,
                                IsDatabaseActive = config.IsActive, // Renamed from IsActive to IsDatabaseActive
                                ServerName = config.ServerName,
                                Description = config.Description,
                                NorwegianDescription = config.NorwegianDescription,
                                PriorityIndex = priorityCounter,
                                // Access point specific properties
                                InstanceName = accessPoint.InstanceName,
                                CatalogName = accessPoint.CatalogName,
                                AccessPointType = accessPoint.AccessPointType,
                                Port = accessPoint.Port,
                                ServiceName = accessPoint.ServiceName,
                                NodeName = accessPoint.NodeName,
                                AuthenticationType = accessPoint.AuthenticationType,
                                UID = accessPoint.UID,
                                PWD = accessPoint.PWD,
                                IsActive = accessPoint.IsActive,
                                PossibleKey = $"{config.Environment}-{config.Application}-{config.Version}-{accessPoint.InstanceName}-{priorityCounter}"
                            };
                            priorityCounter += 1;

                            _accessPoints.Add(flattenedAccessPoint);
                        }

                        var aliasAccessPoints = config.AccessPoints?.Where(ap => ap.AccessPointType == "Alias" && ap.CatalogName != config.PrimaryCatalogName).ToList() ??
                                                  new List<AccessPoint>();
                        foreach (var accessPoint in aliasAccessPoints)
                        {
                            var flattenedAccessPoint = new FkDatabaseAccessPoint
                            {
                                DatabaseName = config.Database,
                                DatabaseGroupName = config.Database,
                                Provider = config.Provider,
                                FkApplication = config.Application,
                                Environment = config.Environment,
                                Version = config.Version,
                                IsDatabaseActive = config.IsActive, // Renamed from IsActive to IsDatabaseActive
                                ServerName = config.ServerName,
                                Description = config.Description,
                                NorwegianDescription = config.NorwegianDescription,
                                PriorityIndex = priorityCounter,
                                // Access point specific properties
                                InstanceName = accessPoint.InstanceName,
                                CatalogName = accessPoint.CatalogName,
                                AccessPointType = accessPoint.AccessPointType,
                                Port = accessPoint.Port,
                                ServiceName = accessPoint.ServiceName,
                                NodeName = accessPoint.NodeName,
                                AuthenticationType = accessPoint.AuthenticationType,
                                UID = accessPoint.UID,
                                PWD = accessPoint.PWD,
                                IsActive = accessPoint.IsActive,
                                PossibleKey = $"{config.Environment}-{config.Application}-{config.Version}-{accessPoint.InstanceName}-{priorityCounter}"
                            };
                            priorityCounter += 1;

                            _accessPoints.Add(flattenedAccessPoint);
                        }

                        var primaryDbAccessPoints = config.AccessPoints?.Where(ap => ap.AccessPointType == "PrimaryDb").ToList() ??
                                                  new List<AccessPoint>();
                        foreach (var accessPoint in primaryDbAccessPoints)
                        {
                            var flattenedAccessPoint = new FkDatabaseAccessPoint
                            {
                                DatabaseName = config.Database,
                                DatabaseGroupName = config.Database,
                                Provider = config.Provider,
                                FkApplication = config.Application,
                                Environment = config.Environment,
                                Version = config.Version,
                                IsDatabaseActive = config.IsActive, // Renamed from IsActive to IsDatabaseActive
                                ServerName = config.ServerName,
                                Description = config.Description,
                                NorwegianDescription = config.NorwegianDescription,
                                PriorityIndex = priorityCounter,
                                // Access point specific properties
                                InstanceName = accessPoint.InstanceName,
                                CatalogName = accessPoint.CatalogName,
                                AccessPointType = accessPoint.AccessPointType,
                                Port = accessPoint.Port,
                                ServiceName = accessPoint.ServiceName,
                                NodeName = accessPoint.NodeName,
                                AuthenticationType = accessPoint.AuthenticationType,
                                UID = accessPoint.UID,
                                PWD = accessPoint.PWD,
                                IsActive = accessPoint.IsActive,
                                PossibleKey = $"{config.Environment}-{config.Application}-{config.Version}-{accessPoint.InstanceName}-{priorityCounter}"
                            };
                            priorityCounter += 1;

                            _accessPoints.Add(flattenedAccessPoint);
                        }

                        

                    }

                    DedgeNLog.Info($"Successfully loaded {_accessPoints.Count} flattened access points from {ConfigFilePath}");
                    // Verify that no duplicates exit for DatabaseName
                    var duplicateDatabaseNames = _accessPoints
                        .GroupBy(ap => ap.DatabaseName)
                        .Where(g => g.Count() > 1)
                        .SelectMany(g => g)
                        .ToList();

                    if (duplicateDatabaseNames.Any())
                    {
                        DedgeNLog.Warn($"Duplicate database names found (this is expected when multiple access points exist for the same database): {string.Join(", ", duplicateDatabaseNames.Select(ap => ap.DatabaseName).Distinct())}. " +
                                   $"The lookup will prioritize PrimaryCatalogName (lowest PriorityIndex) > Other Aliases > PrimaryDb.");
                        
                        // Log detailed information about each duplicate profile
                        var duplicateGroups = _accessPoints
                            .GroupBy(ap => ap.DatabaseName)
                            .Where(g => g.Count() > 1)
                            .ToList();

                        foreach (var group in duplicateGroups)
                        {
                            DedgeNLog.Info($"Database '{group.Key}' has {group.Count()} access points:");
                            foreach (var ap in group.OrderBy(x => x.PriorityIndex))
                            {
                                DedgeNLog.Info($"  - App: {ap.FkApplication}, Env: {ap.Environment}, Ver: {ap.Version}, Instance: {ap.InstanceName}, " +
                                          $"CatalogName: {ap.CatalogName}, Type: {ap.AccessPointType}, Priority: {ap.PriorityIndex}, " +
                                          $"Server: {ap.ServerName}:{ap.Port}");
                            }
                        }
                        
                        // Export only the duplicate elements to json file for reference
                        File.WriteAllText("duplicateDatabaseNames.json", JsonSerializer.Serialize(duplicateDatabaseNames));
                    }

                    // Verify that no duplicates exist for Application, Environment, Version, InstanceName (PossibleKey)
                    var duplicateApplicationEnvironmentVersionInstanceName = _accessPoints
                        .GroupBy(ap => ap.PossibleKey)
                        .Where(g => g.Count() > 1)
                        .SelectMany(g => g)
                        .ToList();

                    if (duplicateApplicationEnvironmentVersionInstanceName.Any())
                    {
                        DedgeNLog.Error($"Duplicate application, environment, version, instance name found: {string.Join(", ", duplicateApplicationEnvironmentVersionInstanceName.Select(ap => ap.PossibleKey).Distinct())}");
                        // Export only the duplicate elements to json file
                        File.WriteAllText("duplicateApplicationEnvironmentVersionInstanceName.json", JsonSerializer.Serialize(duplicateApplicationEnvironmentVersionInstanceName));
                        // Open the file in vscode, but try to find the correct path to vscode first
                        var vscodePath = Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.ProgramFiles), "Microsoft VS Code", "bin", "code.cmd");
                        if (!File.Exists(vscodePath))
                        {
                            vscodePath = Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.ProgramFiles), "Microsoft VS Code", "bin", "code.cmd");
                        }
                        System.Diagnostics.Process.Start(vscodePath, "duplicateApplicationEnvironmentVersionInstanceName.json");
                        throw new InvalidOperationException("Duplicate application, environment, version, instance name found");
                    }
                }
                catch (Exception ex)
                {
                    DedgeNLog.Error($"Failed to load access points from {ConfigFilePath}: {ex.Message}");
                    throw;
                }
            }

            public static void ClearCache()
            {
                lock (_lockObject)
                {
                    _configurations = null;
                    _accessPoints = null;
                    DedgeNLog.Info("Configuration cache cleared");
                }
            }
        }
        /// <summary>
        /// Contains connection information for a specific database environment.
        /// Encapsulates all necessary details required to establish a database connection,
        /// including server information, credentials, and environment-specific settings.
        /// </summary>
        /// <remarks>
        /// This class stores both the connection parameters (database, server, credentials)
        /// and metadata about the connection (application, environment, version).
        /// It supports multiple database providers and includes version tracking capabilities.
        /// </remarks>
        public class ConnectionInfo
        {
            /// <summary>Gets or sets the database name.</summary>
            public string? Database { get; set; }

            /// <summary>
            /// Alias for Database property, named DatabaseName for compatibility.
            /// </summary>
            public string? DatabaseName
            {
                get => Database;
                set => Database = value;
            }

            /// <summary>Gets or sets the database provider type.</summary>
            public DatabaseProvider Provider { get; set; } = DatabaseProvider.DB2;  // Default to DB2

            /// <summary>Gets or sets the server address and port.</summary>
            public string? Server { get; set; }

            /// <summary>
            /// Alias for Server property, named ServerName for compatibility.
            /// </summary>
            public string? ServerName
            {
                get => Server;
                set => Server = value;
            }

            /// <summary>Gets or sets the user ID for database connection.</summary>
            public string? UID { get; set; }

            /// <summary>Gets or sets the password for database connection.</summary>
            public string? PWD { get; set; }

            /// <summary>Gets or sets the application this connection is for.</summary>
            public FkApplication Application { get; set; }

            /// <summary>Gets or sets the environment this connection is for.</summary>
            public FkEnvironment Environment { get; set; }

            /// <summary>Gets or sets the version of the application.</summary>
            public string Version { get; set; } = "2.0";

            /// <summary>Gets or sets the instance name of the connection.</summary>
            public string? InstanceName { get; set; } = "DB2";

            /// <summary>Gets or sets the Norwegian description of this connection.</summary>
            /// <remarks>Provides a localized description of the connection's purpose and usage.</remarks>
            public string? NorwegianDescription { get; set; }

            /// <summary>Gets or sets the English description of this connection.</summary>
            /// <remarks>Provides a localized description of the connection's purpose and usage.</remarks>
            public string? EnglishDescription { get; set; }



        }

        /// <summary>
        /// Gets the flattened access points array with all database properties included.
        /// This replaces the old dictionary-based approach with a more flexible object array.
        /// </summary>
        public static List<FkDatabaseAccessPoint> AccessPoints
        {
            get
            {
                try
                {
                    return FkConfigurationManager.GetAccessPoints();
                }
                catch (Exception ex)
                {
                    DedgeNLog.Error($"Failed to load access points, using fallback: {ex.Message}");
                    return GetFallbackAccessPoints();
                }
            }
        }

        /// <summary>
        /// Gets fallback access points when the main configuration fails to load.
        /// </summary>
        private static List<FkDatabaseAccessPoint> GetFallbackAccessPoints()
        {
            return new List<FkDatabaseAccessPoint>
            {
                new FkDatabaseAccessPoint
                {
                    DatabaseName = "FKAVDNT",
                    Provider = "DB2",
                    FkApplication = "FKM",
                    Environment = "DEV",
                    Version = "2.0",
                    PrimaryCatalogName = "FKAVDNT",
                    IsDatabaseActive = true,
                    ServerName = "erp2db2.DEDGE.fk.no",
                    Description = "Development-database for FKM-application.",
                    NorwegianDescription = "Utviklings-database for FKM-applikasjonen.",
                    InstanceName = "DB2",
                    CatalogName = "FKAVDNT",
                    AccessPointType = "PrimaryDb",
                    Port = "3710",
                    ServiceName = "DB2C_2",
                    NodeName = "NODE2",
                    AuthenticationType = "Kerberos",
                    UID = "db2nt",
                    PWD = "ntdb2",
                    IsActive = true
                },
                new FkDatabaseAccessPoint
                {
                    DatabaseName = "BASISTST",
                    Provider = "DB2",
                    FkApplication = "FKM",
                    Environment = "TST",
                    Version = "2.0",
                    PrimaryCatalogName = "BASISTST",
                    IsDatabaseActive = true,
                    ServerName = "erp2db2.DEDGE.fk.no",
                    Description = "Test-database for FKM-application.",
                    NorwegianDescription = "Test-database for FKM-applikasjonen.",
                    InstanceName = "DB2",
                    CatalogName = "BASISTST",
                    AccessPointType = "PrimaryDb",
                    Port = "3701",
                    ServiceName = "DB2C_2",
                    NodeName = "NODE2",
                    AuthenticationType = "Kerberos",
                    UID = "db2nt",
                    PWD = "ntdb2",
                    IsActive = true
                },
                new FkDatabaseAccessPoint
                {
                    DatabaseName = "BASISPRO",
                    Provider = "DB2",
                    FkApplication = "FKM",
                    Environment = "PRD",
                    Version = "2.0",
                    PrimaryCatalogName = "BASISPRO",
                    IsDatabaseActive = true,
                    ServerName = "erp1db2.DEDGE.fk.no",
                    Description = "Production-database for FKM-application.",
                    NorwegianDescription = "Produksjons-database for FKM-applikasjonen.",
                    InstanceName = "DB2",
                    CatalogName = "BASISPRO",
                    AccessPointType = "PrimaryDb",
                    Port = "3700",
                    ServiceName = "DB2C_2",
                    NodeName = "NODE2",
                    AuthenticationType = "Kerberos",
                    UID = "db2nt",
                    PWD = "ntdb2",
                    IsActive = true
                }
            };
        }


        // Track current version per application/environment - now dynamically generated from JSON
        public static List<CurrentVersionInfo> GetCurrentVersions()
        {
            var accessPoints = AccessPoints;
            return accessPoints
                .Where(ap => ap.IsDatabaseActive)
                .GroupBy(ap => (ap.ApplicationEnum, ap.EnvironmentEnum))
                .SelectMany(g => g.OrderByDescending(ap => ap.Version)
                    .GroupBy(ap => ap.InstanceName)
                    .Select(instanceGroup => instanceGroup.First())
                    .Select(ap => new CurrentVersionInfo(
                        ap.ApplicationEnum,
                        ap.EnvironmentEnum,
                        ap.Version,
                        ap.InstanceName,
                        ap.Provider)))
                .ToList();
        }
        public static readonly Dictionary<FkApplication, (string Description, string NorwegianDescription)> ApplicationDescriptions = new()
        {
            { FkApplication.FKM, ("FK Meny application", "FK Meny-applikasjon") },
            { FkApplication.INL, ("Innlån application", "Innlån-applikasjon") },
            { FkApplication.HST, ("Dedge History application", "Dedge Historie-applikasjon") },
            { FkApplication.VAR, ("Vareregister application", "Vareregister-applikasjon") },
            { FkApplication.AGP, ("Agriprod application", "Agriprod-applikasjon") },
            { FkApplication.AGK, ("Agrikorn application", "Agrikorn-applikasjon") },
            { FkApplication.DBQA, ("DBQA application", "DBQA-applikasjon") },
            { FkApplication.DOC, ("COBDOK application", "COBDOK-applikasjon") },
            { FkApplication.VIS, ("Visma accounting application", "Visma regnskapsapplikasjon")   }
        };

        /// <summary>
        /// Parses a string application name to FkApplication enum.
        /// </summary>
        private static FkApplication ParseApplication(string application)
        {
            return application?.ToUpper() switch
            {
                "FKM" => FkApplication.FKM,
                "INL" => FkApplication.INL,
                "HST" => FkApplication.HST,
                "VIS" => FkApplication.VIS,
                "VAR" => FkApplication.VAR,
                "AGP" => FkApplication.AGP,
                "AGK" => FkApplication.AGK,
                "DBQA" => FkApplication.DBQA,
                "FKDBQA" => FkApplication.DBQA,  // Map FKDBQA to DBQA
                "DOC" => FkApplication.DOC,
                _ => throw new ArgumentException($"Unknown application: {application}")
            };
        }

        /// <summary>
        /// Parses a string environment name to FkEnvironment enum.
        /// </summary>
        private static FkEnvironment ParseEnvironment(string environment)
        {
            return environment?.ToUpper() switch
            {
                "DEV" => FkEnvironment.DEV,
                "TST" => FkEnvironment.TST,
                "PRD" => FkEnvironment.PRD,
                "MIG" => FkEnvironment.MIG,
                "SIT" => FkEnvironment.SIT,
                "VFT" => FkEnvironment.VFT,
                "VFK" => FkEnvironment.VFK,
                "KAT" => FkEnvironment.KAT,
                "FUT" => FkEnvironment.FUT,
                "HST" => FkEnvironment.HST,
                "RAP" => FkEnvironment.RAP,
                "PER" => FkEnvironment.PER,
                _ => throw new ArgumentException($"Unknown environment: {environment}")
            };
        }

        /// <summary>
        /// Parses a string provider name to DatabaseProvider enum.
        /// </summary>
        private static DatabaseProvider ParseProvider(string provider)
        {
            return provider?.ToUpper() switch
            {
                "DB2" => DatabaseProvider.DB2,
                "SQLSERVER" => DatabaseProvider.SQLSERVER,
                "POSTGRESQL" => DatabaseProvider.POSTGRESQL,
                "POSTGRES" => DatabaseProvider.POSTGRESQL,
                _ => throw new ArgumentException($"Unknown provider: {provider}")
            };
        }

        /// <summary>
        /// Refreshes the configuration cache and regenerates the access points array.
        /// </summary>
        public static void RefreshConfiguration()
        {
            FkConfigurationManager.ClearCache();
            DedgeNLog.Info("Configuration refreshed successfully");
        }

        /// <summary>
        /// Retrieves connection information for a specified application and environment.
        /// </summary>
        /// <param name="environment">The environment to get connection information for.</param>
        /// <param name="application">The application requesting the connection (defaults to FKM).</param>
        /// <param name="version">The version of the application (defaults to "2.0").</param>
        /// <param name="instanceName">Optional instance name to filter by specific access point.</param>
        /// <returns>Connection information for the specified application and environment.</returns>
        /// <exception cref="KeyNotFoundException">Thrown when the specified combination is not found.</exception>
        public static FkDatabaseAccessPoint GetConnectionStringInfo(
            FkEnvironment environment,
            FkApplication application = FkApplication.FKM,
            string? version = "2.0",
            string? instanceName = "DB2")
        {
            var accessPoint = AccessPoints.FirstOrDefault(ap =>
                ap.ApplicationEnum == application &&
                ap.EnvironmentEnum == environment &&
                ap.Version == version &&
                (string.IsNullOrEmpty(instanceName) || ap.InstanceName == instanceName) &&
                ap.IsActive);

            if (accessPoint == null)
            {
                throw new KeyNotFoundException(
                    $"No connection information found for FkApplication: {application}, Environment: {environment}, Version: {version}" +
                    (string.IsNullOrEmpty(instanceName) ? "" : $", InstanceName: {instanceName}"));
            }

            return accessPoint;
        }

        /// <summary>
        /// Retrieves connection information for a specified database name.
        /// </summary>
        /// <param name="databaseName">The name of the database to find connection information for.</param>
        /// <returns>Connection information for the specified database name.</returns>
        /// <exception cref="KeyNotFoundException">Thrown when the specified database name is not found.</exception>
        public static FkDatabaseAccessPoint GetConnectionStringInfo(string databaseName)
        {
            return GetAccessPointByDatabaseName(databaseName);
        }

        /// <summary>
        /// Retrieves all connection information for a specified application, environment, version and instance name.
        /// Any of the parameters can be null, in which case all access points are returned.
        /// Returns multiple access points if they exist.
        /// </summary>
        /// <param name="environment">The environment to get connection information for.</param>
        /// <param name="application">The application requesting the connection (defaults to FKM).</param>
        /// <param name="version">The version of the application (defaults to "2.0").</param>
        /// <param name="instanceName">Optional instance name to filter by specific access point.</param>
        /// <returns>List of connection information for the specified application and environment.</returns>
        /// <exception cref="KeyNotFoundException">Thrown when no connections are found.</exception>
        public static List<FkDatabaseAccessPoint> GetConnectionStringInfos(
            FkEnvironment? environment,
            FkApplication? application = FkApplication.FKM,
            string? version = "2.0",
            string? instanceName = "DB2")
        {


            var accessPoints = AccessPoints;
            if (application != null)
            {
                accessPoints = accessPoints.Where(ap => ap.ApplicationEnum == application).ToList();
            }
            if (environment != null)
            {
                accessPoints = accessPoints.Where(ap => ap.EnvironmentEnum == environment).ToList();
            }
            if (version != null)
            {
                accessPoints = accessPoints.Where(ap => ap.Version == version).ToList();
            }
            if (instanceName != null)
            {
                accessPoints = accessPoints.Where(ap => ap.InstanceName == instanceName).ToList();
            }

            if (accessPoints.Count == 0)
            {
                throw new KeyNotFoundException(
                    $"No connection information found for FkApplication: {application}, Environment: {environment}, Version: {version}, InstanceName: {instanceName}");
            }
            return accessPoints;
        }


        /// <summary>
        /// Gets the connection string information for a specified key.
        /// This method is deprecated. Use GetConnectionStringInfo with explicit parameters instead.
        /// If duplicate entries are found, returns the first one and logs a warning.
        /// </summary>
        /// <param name="key">The key to get connection information for.</param>
        /// <returns>A formatted connection string for the specified application and environment.</returns>
        /// <exception cref="KeyNotFoundException">Thrown when no connection information is found.</exception>
        public static FkDatabaseAccessPoint GetConnectionStringInfo(ConnectionKey key)
        {
            return GetConnectionStringInfo(key.Environment, key.Application, key.Version, key.InstanceName);
        }





        /// <summary>
        /// Generates a connection string for a specified application, environment, version and instance name.
        /// </summary>
        /// <param name="environment">The environment to generate a connection string for.</param>
        /// <param name="application">The application requesting the connection (defaults to FKM).</param>
        /// <param name="version">The version of the application (defaults to "2.0").</param>
        /// <param name="instanceName">Optional instance name to filter by specific access point.</param>
        /// <param name="overrideUID">Optional username to override configured credentials.</param>
        /// <param name="overridePWD">Optional password to override configured credentials.</param>
        /// <returns>A formatted connection string for the specified application and environment.</returns>
        public static string GetConnectionString(
            FkEnvironment environment,
            FkApplication application = FkApplication.FKM,
            string? version = "2.0",
            string? instanceName = "DB2",
            string? overrideUID = null,
            string? overridePWD = null)
        {
            var accessPoint = GetConnectionStringInfo(environment, application, version, instanceName);
            return GenerateConnectionString(accessPoint, overrideUID, overridePWD);
        }

        /// <summary>
        /// Generates connection strings for all matching access points.
        /// </summary>
        /// <param name="environment">The environment to generate connection strings for.</param>
        /// <param name="application">The application requesting the connection (defaults to FKM).</param>
        /// <param name="version">The version of the application (defaults to "2.0").</param>
        /// <param name="instanceName">Optional instance name to filter by specific access point.</param>
        /// <param name="overrideUID">Optional username to override configured credentials.</param>
        /// <param name="overridePWD">Optional password to override configured credentials.</param>
        /// <returns>List of formatted connection strings for the specified application and environment.</returns>
        public static List<string> GetConnectionStrings(
            FkEnvironment environment,
            FkApplication application = FkApplication.FKM,
            string? version = "2.0",
            string? instanceName = "DB2",
            string? overrideUID = null,
            string? overridePWD = null)
        {
            var accessPoints = GetConnectionStringInfos(environment, application, version, instanceName);
            return accessPoints.Select(ap => GenerateConnectionString(ap, overrideUID, overridePWD)).ToList();
        }

        /// <summary>
        /// Generates a connection string for a specified connection key.
        /// </summary>
        /// <param name="connectionKey">The connection key identifying the database.</param>
        /// <param name="overrideUID">Optional username to override configured credentials.</param>
        /// <param name="overridePWD">Optional password to override configured credentials.</param>
        /// <returns>A formatted connection string.</returns>
        public static string GetConnectionString(
            DedgeConnection.ConnectionKey connectionKey,
            string? overrideUID = null,
            string? overridePWD = null)
        {
            var accessPoint = GetConnectionStringInfo(connectionKey.Environment, connectionKey.Application, connectionKey.Version, connectionKey.InstanceName);
            return GenerateConnectionString(accessPoint, overrideUID, overridePWD);
        }

        /// <summary>
        /// Generates a connection string for a specified database name.
        /// </summary>
        /// <param name="databaseName">The database name to generate a connection string for.</param>
        /// <param name="overrideUID">Optional username to override configured credentials.</param>
        /// <param name="overridePWD">Optional password to override configured credentials.</param>
        /// <returns>A formatted connection string.</returns>
        public static string GetConnectionString(
            string databaseName,
            string? overrideUID = null,
            string? overridePWD = null)
        {
            var accessPoint = GetAccessPointByDatabaseName(databaseName);
            return GenerateConnectionString(accessPoint, overrideUID, overridePWD);
        }

        /// <summary>
        /// Generates a connection string from an access point.
        /// Automatically handles Kerberos/SSO authentication - when AuthenticationType is "Kerberos" and no override credentials are provided,
        /// UID/PWD are excluded from the connection string to allow Windows integrated authentication.
        /// </summary>
        /// <param name="accessPoint">The access point to generate a connection string for.</param>
        /// <param name="overrideUID">Optional username to override the configured UID. If null, uses configured behavior.</param>
        /// <param name="overridePWD">Optional password to override the configured PWD. If null, uses configured behavior.</param>
        /// <returns>A connection string with appropriate authentication parameters.</returns>
        public static string GenerateConnectionString(FkDatabaseAccessPoint accessPoint, string? overrideUID = null, string? overridePWD = null)
        {
            string connectionString = "";
            
            // Determine if we should include credentials
            bool useKerberos = accessPoint.AuthenticationType.Equals("Kerberos", StringComparison.OrdinalIgnoreCase);
            bool hasOverride = !string.IsNullOrEmpty(overrideUID) || !string.IsNullOrEmpty(overridePWD);
            
            // Use override credentials if provided, otherwise use configured credentials
            string uid = !string.IsNullOrEmpty(overrideUID) ? overrideUID : accessPoint.UID ?? "";
            string pwd = !string.IsNullOrEmpty(overridePWD) ? overridePWD : accessPoint.PWD ?? "";
            
            // Determine if we should include credentials:
            // 1. If Kerberos auth and no override: use SSO (no credentials)
            // 2. If override provided: always use override credentials
            // 3. If non-Kerberos auth: include credentials only if they're not empty
            bool includeCredentials = false;
            
            if (hasOverride)
            {
                // Override provided - use it
                includeCredentials = true;
                DedgeNLog.Debug($"Using override credentials for {accessPoint.DatabaseName}");
            }
            else if (useKerberos)
            {
                // Kerberos auth - use SSO, no credentials needed
                includeCredentials = false;
                DedgeNLog.Debug($"Using Kerberos/SSO authentication for {accessPoint.DatabaseName} (no UID/PWD in connection string)");
            }
            else
            {
                // Non-Kerberos auth - include credentials if they exist
                if (!string.IsNullOrEmpty(uid) && !string.IsNullOrEmpty(pwd))
                {
                    includeCredentials = true;
                    DedgeNLog.Debug($"Using configured credentials for {accessPoint.DatabaseName} (AuthType: {accessPoint.AuthenticationType})");
                }
                else
                {
                    // Non-Kerberos but no valid credentials - might cause connection failure
                    DedgeNLog.Warn($"Database {accessPoint.DatabaseName} has AuthenticationType '{accessPoint.AuthenticationType}' " +
                               $"but no valid UID/PWD configured. Connection may fail. Consider setting AuthenticationType to 'Kerberos' " +
                               $"or providing credentials via override parameters.");
                    includeCredentials = false;
                }
            }

            if (accessPoint.ProviderEnum == DatabaseProvider.DB2)
            {
                connectionString = $"Database={accessPoint.CatalogName};Server={accessPoint.ServerName}:{accessPoint.Port};";
                
                if (includeCredentials)
                {
                    connectionString += $"UID={uid};PWD={pwd};";
                }
                else if (useKerberos)
                {
                    // For DB2 Kerberos authentication, must explicitly specify Authentication=Kerberos
                    connectionString += "Authentication=Kerberos;";
                }
            }
            else if (accessPoint.ProviderEnum == DatabaseProvider.SQLSERVER)
            {
                connectionString = $"DatabaseName={accessPoint.CatalogName};Server={accessPoint.Server};";
                
                if (includeCredentials)
                {
                    connectionString += $"User Id={uid};Password={pwd};";
                }
                else
                {
                    connectionString += "Integrated Security=SSPI;";
                }
            }
            else if (accessPoint.ProviderEnum == DatabaseProvider.POSTGRESQL)
            {
                connectionString = $"Host={accessPoint.ServerName};Port={accessPoint.Port};Database={accessPoint.CatalogName};";
                
                if (includeCredentials)
                {
                    connectionString += $"Username={uid};Password={pwd};";
                }
                else if (useKerberos)
                {
                    // PostgreSQL with GSSAPI/Kerberos
                    connectionString += "Integrated Security=true;";
                }
                else
                {
                    // PostgreSQL peer authentication or trust
                    DedgeNLog.Debug($"PostgreSQL connection without explicit credentials (using peer/trust authentication)");
                }
            }
            
            return connectionString;
        }






        /// <summary>
        /// Gets the connection string information for the current version of an application in a specific environment.
        /// </summary>
        /// <param name="environment">The environment to get connection information for.</param>
        /// <param name="application">The application requesting the connection.</param>
        /// <param name="instanceName">Optional instance name to filter by specific access point.</param>
        /// <returns>Connection information for the current version of the specified application and environment.</returns>
        /// <exception cref="KeyNotFoundException">Thrown when no current version is found for the specified combination.</exception>
        public static FkDatabaseAccessPoint GetCurrentVersionConnectionInfo(
            FkEnvironment environment,
            FkApplication application,
            string? instanceName = "DB2")
        {
            var currentVersions = GetCurrentVersions();
            var currentVersionInfo = currentVersions.FirstOrDefault(cv =>
                cv.Application == application &&
                cv.Environment == environment &&
                (string.IsNullOrEmpty(instanceName) || cv.InstanceName == instanceName));

            if (currentVersionInfo == null)
            {
                throw new KeyNotFoundException(
                    $"No current version defined for FkApplication: {application}, Environment: {environment}" +
                    (string.IsNullOrEmpty(instanceName) ? "" : $", InstanceName: {instanceName}"));
            }

            var matchingConnections = AccessPoints
                .Where(ap => ap.ApplicationEnum == application &&
                            ap.EnvironmentEnum == environment &&
                            ap.Version == currentVersionInfo.Version &&
                            (string.IsNullOrEmpty(instanceName) || ap.InstanceName == instanceName) &&
                            ap.IsActive)
                .ToList();

            if (!matchingConnections.Any())
            {
                throw new KeyNotFoundException(
                    $"No connection information found for current version {currentVersionInfo.Version} of FkApplication: {application}, Environment: {environment}" +
                    (string.IsNullOrEmpty(instanceName) ? "" : $", InstanceName: {instanceName}"));
            }

            if (matchingConnections.Count > 1)
            {
                var duplicateKeys = string.Join(", ", matchingConnections.Select(ap =>
                    $"[App: {ap.FkApplication}, Env: {ap.Environment}, Ver: {ap.Version}, Instance: {ap.InstanceName}]"));

                DedgeNLog.Warn(
                    $"Multiple connection entries found for current version {currentVersionInfo.Version} of FkApplication: {application}, " +
                    $"Environment: {environment}" +
                    (string.IsNullOrEmpty(instanceName) ? "" : $", InstanceName: {instanceName}") +
                    $". Duplicate keys: {duplicateKeys}. Using first entry.");
            }

            return matchingConnections.First();
        }

        /// <summary>
        /// Generates a connection string for the current version of an application in a specific environment.
        /// </summary>
        /// <param name="environment">The environment to generate a connection string for.</param>
        /// <param name="application">The application requesting the connection.</param>
        /// <param name="instanceName">Optional instance name to filter by specific access point.</param>
        /// <param name="overrideUID">Optional username to override configured credentials.</param>
        /// <param name="overridePWD">Optional password to override configured credentials.</param>
        /// <returns>A formatted connection string for the current version of the specified application and environment.</returns>
        public static string GetCurrentVersionConnectionString(
            FkEnvironment environment,
            FkApplication application,
            string? instanceName = "DB2",
            string? overrideUID = null,
            string? overridePWD = null)
        {
            var accessPoint = GetCurrentVersionConnectionInfo(environment, application, instanceName);
            return GenerateConnectionString(accessPoint, overrideUID, overridePWD);
        }

        /// <summary>
        /// Gets an access point by database name or alias name (CatalogName).
        /// Supports lookup by both Database name (e.g., "FKMDEV") and alias name (e.g., "BASISTST").
        /// 
        /// Lookup flow:
        /// 1. First, try to find database by Database name
        /// 2. If not found, search for any database that has a matching CatalogName (alias)
        /// 3. Get the PrimaryCatalogName from that database
        /// 4. Find the access point where CatalogName matches PrimaryCatalogName
        /// 5. Verify both Database.IsActive and AccessPoint.IsActive are true
        /// 
        /// Note: If duplicate alias names exist across databases, the first match is returned.
        /// </summary>
        /// <param name="databaseName">The database name or alias name to search for (e.g., "FKMDEV" or "BASISTST").</param>
        /// <param name="provider">Optional provider filter (e.g., "DB2", "SQLSERVER"). If null, searches all providers.</param>
        /// <returns>The "Alias" type access point using PrimaryCatalogName.</returns>
        /// <exception cref="ArgumentException">Thrown when database or required alias access point is not found.</exception>
        public static FkDatabaseAccessPoint GetAccessPointByDatabaseName(string databaseName, string? provider = null)
        {
            // Input validation
            if (string.IsNullOrWhiteSpace(databaseName))
            {
                throw new ArgumentException("Database name cannot be null or empty", nameof(databaseName));
            }

            // Step 1: Filter by provider if specified
            var configurations = FkConfigurationManager.GetConfigurations();
            if (!string.IsNullOrEmpty(provider))
            {
                configurations = configurations.Where(c => c.Provider.Equals(provider, StringComparison.OrdinalIgnoreCase)).ToList();
            }

            // Step 2: Try to find database by Database name first
            var databaseConfiguration = configurations
                .FirstOrDefault(c => c.Database.Equals(databaseName, StringComparison.OrdinalIgnoreCase));

            // Step 3: If not found by Database name, search by CatalogName (alias name)
            if (databaseConfiguration == null)
            {
                // Find the first database that has an access point with matching CatalogName
                databaseConfiguration = configurations
                    .FirstOrDefault(c => c.AccessPoints.Any(ap => 
                        ap.CatalogName.Equals(databaseName, StringComparison.OrdinalIgnoreCase) && 
                        ap.IsActive));

                if (databaseConfiguration != null)
                {
                    DedgeNLog.Info($"Database found by alias name: '{databaseName}' maps to Database: '{databaseConfiguration.Database}'");
                }
            }

            if (databaseConfiguration == null)
            {
                throw new ArgumentException(
                    $"Database or alias '{databaseName}' does not exist in configuration" +
                    (string.IsNullOrEmpty(provider) ? "" : $" for Provider: {provider}"));
            }

            // Step 4: Verify Database.IsActive is true
            if (!databaseConfiguration.IsActive)
            {
                throw new ArgumentException(
                    $"Database '{databaseConfiguration.Database}' exists but is not active (IsActive = false)");
            }

            // Step 5: Use PrimaryCatalogName to find the correct access point
            var primaryCatalogName = databaseConfiguration.PrimaryCatalogName;
            if (string.IsNullOrEmpty(primaryCatalogName))
            {
                throw new ArgumentException(
                    $"Database '{databaseConfiguration.Database}' exists but has no PrimaryCatalogName configured");
            }

            // Step 6: Find access point where CatalogName = PrimaryCatalogName
            // IMPORTANT: PrimaryCatalogName should point to an "Alias" type, NOT "PrimaryDb"
            // PrimaryDb is for administrative/direct access only, NOT for application connections
            var accessPoint = AccessPoints
                .FirstOrDefault(ap => ap.DatabaseName.Equals(databaseConfiguration.Database, StringComparison.OrdinalIgnoreCase) &&
                                    ap.CatalogName.Equals(primaryCatalogName, StringComparison.OrdinalIgnoreCase) &&
                                    ap.IsActive);

            if (accessPoint == null)
            {
                throw new ArgumentException(
                    $"Database '{databaseConfiguration.Database}' exists with PrimaryCatalogName '{primaryCatalogName}', " +
                    $"but no active access point found with CatalogName matching PrimaryCatalogName");
            }

            // Step 7: ENFORCE that it's an Alias type (PrimaryDb should NEVER be returned for application use)
            if (!accessPoint.AccessPointType.Equals("Alias", StringComparison.OrdinalIgnoreCase))
            {
                string errorMessage = $"Configuration error: Database '{databaseConfiguration.Database}' PrimaryCatalogName '{primaryCatalogName}' " +
                                     $"points to access point type '{accessPoint.AccessPointType}' instead of 'Alias'. " +
                                     $"PrimaryDb is for administrative access only and should NOT be used for application connections. " +
                                     $"The PrimaryCatalogName must reference an 'Alias' type access point.";
                DedgeNLog.Error(errorMessage);
                throw new ArgumentException(errorMessage);
            }

            DedgeNLog.Info($"Retrieved access point for Database: {databaseConfiguration.Database}, PrimaryCatalogName: {primaryCatalogName}, " +
                       $"Type: {accessPoint.AccessPointType}, App: {accessPoint.FkApplication}, Env: {accessPoint.Environment}");

            return accessPoint;
        }

        /// <summary>
        /// Gets an access point by database name and specific CatalogName, matching the PowerShell retrieval logic.
        /// This is for special cases where you need a specific catalog name that's NOT the PrimaryCatalogName.
        /// 
        /// Use this when you want to access by specific CatalogName (e.g., "FKMDEV" PrimaryDb) 
        /// instead of using the PrimaryCatalogName.
        /// </summary>
        /// <param name="databaseName">The database name to search for (e.g., "FKMDEV").</param>
        /// <param name="catalogName">The specific catalog name to find (e.g., "FKMDEV" for PrimaryDb access).</param>
        /// <param name="databaseType">The access point type (e.g., "PrimaryDb", "Alias"). Must match exactly.</param>
        /// <param name="provider">Optional provider filter (e.g., "DB2", "SQLSERVER"). If null, searches all providers.</param>
        /// <returns>The first matching access point of the specified type.</returns>
        /// <exception cref="ArgumentException">Thrown when no matching access point is found.</exception>
        public static FkDatabaseAccessPoint GetAccessPointByCatalogName(string databaseName, string catalogName, string databaseType, string? provider = null)
        {
            // Input validation
            if (string.IsNullOrWhiteSpace(databaseName))
            {
                throw new ArgumentException("Database name cannot be null or empty", nameof(databaseName));
            }
            if (string.IsNullOrWhiteSpace(catalogName))
            {
                throw new ArgumentException("Catalog name cannot be null or empty", nameof(catalogName));
            }
            if (string.IsNullOrWhiteSpace(databaseType))
            {
                throw new ArgumentException("Database type cannot be null or empty", nameof(databaseType));
            }

            // Step 1: Find database by Database name
            var configurations = FkConfigurationManager.GetConfigurations();
            if (!string.IsNullOrEmpty(provider))
            {
                configurations = configurations.Where(c => c.Provider.Equals(provider, StringComparison.OrdinalIgnoreCase)).ToList();
            }

            var databaseConfiguration = configurations
                .FirstOrDefault(c => c.Database.Equals(databaseName, StringComparison.OrdinalIgnoreCase));

            if (databaseConfiguration == null)
            {
                throw new ArgumentException(
                    $"Database '{databaseName}' does not exist in configuration" +
                    (string.IsNullOrEmpty(provider) ? "" : $" for Provider: {provider}"));
            }

            // Step 2: Verify Database.IsActive is true
            if (!databaseConfiguration.IsActive)
            {
                throw new ArgumentException(
                    $"Database '{databaseName}' exists but is not active (IsActive = false)");
            }

            // Step 3: Find access point by specific CatalogName and AccessPointType
            var accessPoint = AccessPoints
                .FirstOrDefault(ap => ap.DatabaseName.Equals(databaseName, StringComparison.OrdinalIgnoreCase) &&
                                    ap.CatalogName.Equals(catalogName, StringComparison.OrdinalIgnoreCase) &&
                                    ap.AccessPointType.Equals(databaseType, StringComparison.OrdinalIgnoreCase) &&
                                    ap.IsActive);

            if (accessPoint == null)
            {
                // List available access points for this database
                var availableAccessPoints = AccessPoints
                    .Where(ap => ap.DatabaseName.Equals(databaseName, StringComparison.OrdinalIgnoreCase) && ap.IsActive)
                    .Select(ap => $"{ap.CatalogName} ({ap.AccessPointType})")
                    .ToList();

                string errorMessage = $"Database '{databaseName}' exists but no active access point found with " +
                                    $"CatalogName: '{catalogName}' and AccessPointType: '{databaseType}'";
                
                if (availableAccessPoints.Any())
                {
                    errorMessage += $". Available access points: {string.Join(", ", availableAccessPoints)}";
                }

                DedgeNLog.Warn(errorMessage);
                throw new ArgumentException(errorMessage);
            }

            DedgeNLog.Info($"Retrieved access point for Database: {databaseName}, CatalogName: {catalogName}, Type: {databaseType}, " +
                       $"App: {accessPoint.FkApplication}, Env: {accessPoint.Environment}");

            return accessPoint;
        }

        /// <summary>
        /// Gets a connection key by database name for backward compatibility.
        /// </summary>
        /// <param name="databaseName">The name of the database to find connection information for.</param>
        /// <returns>A connection key for the specified database.</returns>
        /// <exception cref="ArgumentException">Thrown when no connection information is found for the specified database name.</exception>
        public static ConnectionKey GetConnectionKeyByDatabaseName(string databaseName)
        {
            var accessPoint = GetAccessPointByDatabaseName(databaseName);
            return new ConnectionKey(accessPoint.ApplicationEnum, accessPoint.EnvironmentEnum, accessPoint.Version, accessPoint.InstanceName);
        }

        public static string GetDatabaseName(ConnectionKey connectionKey)
        {
            var accessPoint = GetConnectionStringInfo(connectionKey.Environment, connectionKey.Application, connectionKey.Version, connectionKey.InstanceName);
            return accessPoint.DatabaseName;
        }

        public static string GetDatabaseName(string databaseName)
        {
            var accessPoint = AccessPoints
                .FirstOrDefault(ap => ap.DatabaseName.Equals(databaseName, StringComparison.OrdinalIgnoreCase));
            if (accessPoint == null)
            {
                throw new ArgumentException($"No access point found for DatabaseName: {databaseName}");
            }
            return accessPoint.DatabaseName;
        }

        public static FkDatabaseAccessPoint GetAccessPointByDatabaseName(ConnectionKey connectionKey)
        {
            var accessPoint = GetConnectionStringInfo(connectionKey.Environment, connectionKey.Application, connectionKey.Version, connectionKey.InstanceName);
            return accessPoint;
        }

        public static FkDatabaseAccessPoint GetAccessPoint(string? environment = null, string? application = null, string? version = null, string? instanceName = null)
        {
            var query = AccessPoints.AsEnumerable();


            if (!string.IsNullOrEmpty(environment))
            {
                query = query.Where(ap => ap.Environment.Equals(environment, StringComparison.OrdinalIgnoreCase));
            }
            if (!string.IsNullOrEmpty(application))
            {
                query = query.Where(ap => ap.FkApplication.Equals(application, StringComparison.OrdinalIgnoreCase));
            }
            if (!string.IsNullOrEmpty(instanceName))
            {
                query = query.Where(ap => ap.InstanceName.Equals(instanceName, StringComparison.OrdinalIgnoreCase));
            }
            if (!string.IsNullOrEmpty(version))
            {
                query = query.Where(ap => ap.Version.Equals(version, StringComparison.OrdinalIgnoreCase));
            }
            var accessPoint = query.FirstOrDefault();
            if (accessPoint == null)
            {
                throw new ArgumentException($"No access point found for environment: {environment}, application: {application}, version: {version}, instanceName: {instanceName}");
            }
            return accessPoint;
        }

        public static FkDatabaseAccessPoint GetAccessPoint(string DatabaseName)
        {
            var query = AccessPoints.AsEnumerable();

            query = query.Where(ap => ap.DatabaseName.Equals(DatabaseName, StringComparison.OrdinalIgnoreCase));

            var accessPoint = query.FirstOrDefault();
            if (accessPoint == null)
            {
                throw new ArgumentException($"No access point found for DatabaseName: {DatabaseName}");
            }
            return accessPoint;
        }

        /// <summary>
        /// Represents detailed connection information for display and reporting purposes.
        /// </summary>
        public class ConnectionDetail
        {
            /// <summary>Gets or sets the connection key.</summary>
            public ConnectionKey? ConnectionKey { get; set; }

            /// <summary>Gets or sets the English description of the connection.</summary>
            public string Description { get; set; } = string.Empty;

            /// <summary>Gets or sets the Norwegian description of the connection.</summary>
            public string NorwegianDescription { get; set; } = string.Empty;

            /// <summary>Gets or sets the database name.</summary>
            public string DatabaseName { get; set; } = string.Empty;
        }

        /// <summary>
        /// Returns a list of all available connections with their details.
        /// </summary>
        /// <param name="application">Optional parameter to filter connections by application.</param>
        /// <returns>A list of ConnectionDetail objects containing information about available connections.</returns>
        public static List<ConnectionDetail> GetAllConnectionDetails(FkApplication? application = null)
        {
            var query = AccessPoints.AsEnumerable();

            if (application.HasValue)
            {
                query = query.Where(ap => ap.ApplicationEnum == application.Value);
            }

            return query
                .Select(ap => new ConnectionDetail
                {
                    ConnectionKey = new ConnectionKey(ap.ApplicationEnum, ap.EnvironmentEnum, ap.Version),
                    Description = $"{ap.Environment} environment connection for {ap.FkApplication} application" +
                                (ap.Version != "2.0" ? $" version {ap.Version}" : "2.0") +
                                $" instance {ap.InstanceName}",
                    NorwegianDescription = ap.NorwegianDescription ?? string.Empty,
                    DatabaseName = ap.DatabaseName ?? string.Empty
                })
                .OrderBy(x => x.ConnectionKey?.Application)
                .ThenBy(x => x.ConnectionKey?.Environment)
                .ThenBy(x => x.ConnectionKey?.Version)
                .ToList();
        }

        /// <summary>
        /// Returns a list of all available connections matching any of the specified applications.
        /// </summary>
        /// <param name="applications">List of applications to filter connections by.</param>
        /// <returns>A list of ConnectionDetail objects containing information about matching connections.</returns>
        public static List<ConnectionDetail> GetConnectionDetailsForApplications(List<FkApplication> applications)
        {
            return AccessPoints
                .Where(ap => applications.Contains(ap.ApplicationEnum))
                .Select(ap => new ConnectionDetail
                {
                    ConnectionKey = new ConnectionKey(ap.ApplicationEnum, ap.EnvironmentEnum, ap.Version),
                    Description = $"{ap.Environment} environment connection for {ap.FkApplication} application" +
                                 (ap.Version != "2.0" ? $" version {ap.Version}" : "2.0") +
                                 $" instance {ap.InstanceName}",
                    NorwegianDescription = ap.NorwegianDescription ?? string.Empty,
                    DatabaseName = ap.DatabaseName ?? string.Empty
                })
                .OrderBy(x => x.ConnectionKey?.Application)
                .ThenBy(x => x.ConnectionKey?.Environment)
                .ThenBy(x => x.ConnectionKey?.Version)
                .ToList();
        }

        /// <summary>
        /// Represents a combined connection information object containing both key and connection details.
        /// </summary>
        public class ConnectionInformation
        {
            /// <summary>Gets or sets the connection key.</summary>
            public ConnectionKey Key { get; set; }

            /// <summary>Gets or sets the connection string information.</summary>
            public ConnectionInfo ConnectionInfo { get; set; }

            public ConnectionInformation(ConnectionKey key, ConnectionInfo connectionInfo)
            {
                Key = key;
                ConnectionInfo = connectionInfo;
            }
        }

        /// <summary>
        /// Returns a list of connection information objects for specified applications.
        /// </summary>
        /// <param name="applications">List of applications to filter connections by.</param>
        /// <returns>A list of ConnectionInformation objects for matching applications.</returns>
        public static List<ConnectionInformation> GetConnectionsForApplications(List<FkApplication> applications)
        {
            return AccessPoints
                .Where(ap => applications.Contains(ap.ApplicationEnum))
                .Select(ap => new ConnectionInformation(
                    new ConnectionKey(ap.ApplicationEnum, ap.EnvironmentEnum, ap.Version, ap.InstanceName),
                    new ConnectionInfo
                    {
                        Database = ap.DatabaseName,
                        Provider = ap.ProviderEnum,
                        Server = ap.ServerName,
                        UID = ap.UID,
                        PWD = ap.PWD,
                        Application = ap.ApplicationEnum,
                        Environment = ap.EnvironmentEnum,
                        InstanceName = ap.InstanceName,
                        Version = ap.Version,
                        NorwegianDescription = ap.NorwegianDescription,
                        EnglishDescription = ap.Description
                    }))
                .OrderBy(x => x.Key.Application)
                .ThenBy(x => x.Key.Environment)
                .ThenBy(x => x.Key.Version)
                .ThenBy(x => x.Key.InstanceName)
                .ToList();
        }
    }
}
