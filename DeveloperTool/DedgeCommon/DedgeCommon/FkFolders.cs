namespace DedgeCommon
{
    /// <summary>
    /// Manages application folder structures and file system operations.
    /// Provides standardized access to application directories, log files,
    /// and data storage locations across different environments.
    /// </summary>
    /// <remarks>
    /// Features:
    /// - Standardized folder structure management
    /// - Environment-specific path resolution
    /// - Automatic folder creation and validation
    /// - COBOL integration folder handling
    /// - Cross-platform path compatibility
    /// - Logging directory management
    /// </remarks>
    /// <author>Geir Helge Starholm</author>
    public class FkFolders
    {
        public class DatabasePath
        {
            public string? Description { get; set; }
            public string? CobolIntFolder { get; set; }
        }

        public Dictionary<string, DatabasePath> databasePaths = new Dictionary<string, DatabasePath>
        {
           { "BASISPRO", new DatabasePath { Description = "BASISPRO", CobolIntFolder = @"\\DEDGE.fk.no\erpprog\cobnt" } },
           { "BASISTST", new DatabasePath { Description = "BASISTST", CobolIntFolder = @"\\DEDGE.fk.no\erpprog\cobtst" } },
           { "BASISRAP", new DatabasePath { Description = "BASISRAP", CobolIntFolder = @"\\DEDGE.fk.no\erpprog\cobnt" } },
           { "FKAVDNT",  new DatabasePath { Description = "FKAVDNT",  CobolIntFolder = @"\\DEDGE.fk.no\erputv\Utvikling\fkavd\nt" } },
           { "BASISMIG", new DatabasePath { Description = "BASISMIG", CobolIntFolder = @"\\DEDGE.fk.no\erpprog\cobtst\COBMIG" } },
           { "BASISSIT", new DatabasePath { Description = "BASISSIT", CobolIntFolder = @"\\DEDGE.fk.no\erpprog\cobtst\COBSIT" } },
           { "BASISVFT", new DatabasePath { Description = "BASISVFT", CobolIntFolder = @"\\DEDGE.fk.no\erpprog\cobtst\COBVFT" } },
           { "BASISVFK", new DatabasePath { Description = "BASISVFK", CobolIntFolder = @"\\DEDGE.fk.no\erpprog\cobtst\COBVFK" } }
        };

        private string _OptPath = "";
        private string _FolderNamespace = "";
        public string? _FolderNamespacePath { get; private set; }

        public FkFolders(string? namespaceAndClassOverride = "", string? basePath = "")
        {
            _OptPath = "";
            if (string.IsNullOrEmpty(basePath))
                _OptPath = Environment.GetEnvironmentVariable("OPTPATH") ?? @"C:\opt";
            else
                _OptPath = basePath;
            if (!string.IsNullOrEmpty(namespaceAndClassOverride))
                _FolderNamespace = namespaceAndClassOverride;
            else
                _FolderNamespace = GlobalFunctions.GetNamespaceClassName();
            if (_FolderNamespace.ToUpper().Trim().Contains(".PROGRAM"))
            {
                _FolderNamespacePath = _FolderNamespace.Substring(0, _FolderNamespace.ToUpper().Trim().IndexOf(".PROGRAM")).Replace(".", @"\");
            }
            else
            {
                _FolderNamespacePath = _FolderNamespace.Replace(".", @"\");
            }
        }
       

        /// <summary>
        /// Gets the base opt path configured for the application.
        /// </summary>
        /// <returns>The configured opt path</returns>
        public string GetOptPath()
        {
            return _OptPath;
        }

        /// <summary>
        /// Gets the UNC path for the opt directory.
        /// </summary>
        /// <returns>The UNC path for the opt directory</returns>
        public string GetOptUncPath()
        {
            string uncPath = "";
            try
            {
                uncPath = Environment.GetEnvironmentVariable("OptUncPath") ?? "";
                string optPath = Environment.GetEnvironmentVariable("OptPath") ?? "";
                if (!string.IsNullOrEmpty(uncPath))
                {
                    return uncPath;
                }

                uncPath = GlobalFunctions.GetUncPath(_OptPath);
                if (!Directory.Exists(uncPath))
                {
                    DedgeNLog.Warn($"The UNC path does not exist: " + uncPath + ". Using the default path: {_OptPath}");
                    return _OptPath;
                }
            }
            catch (Exception ex)
            {
                DedgeNLog.Warn(ex, $"An error occurred while getting the UNC path. Using the default path: {_OptPath}");
                return _OptPath;
            }
            return uncPath;
        }

        /// <summary>
        /// Gets the data folder path for the current namespace.
        /// </summary>
        /// <returns>The full path to the data folder</returns>
        public string GetDataFolder()
        {
            try
            {
                string folder = $@"{_OptPath}\data\{_FolderNamespacePath}";
                if (!Directory.Exists(folder))
                {
                    Directory.CreateDirectory(folder);
                }
                return folder;
            }
            catch (Exception ex)
            {
                DedgeNLog.Error(ex, "An error occurred while getting the data folder path");
                throw;
            }
        }

        /// <summary>
        /// Gets the tools folder path.
        /// </summary>
        /// <returns>The full path to the tools folder</returns>
        public string GetToolsFolder()
        {
            try
            {
                string folder = $@"{_OptPath}\Tools";

                return folder;
            }
            catch (Exception ex)
            {
                DedgeNLog.Error(ex, "An error occurred while getting the tools folder path");
                throw;
            }
        }

        /// <summary>
        /// Gets the log folder path for the current namespace.
        /// </summary>
        /// <returns>The full path to the log folder</returns>
        public string GetLogFolder()
        {
            try
            {
                string folder = $@"{_OptPath}\data\{_FolderNamespacePath}";
                if (!Directory.Exists(folder))
                {
                    Directory.CreateDirectory(folder);
                }
                return folder;
            }
            catch (Exception ex)
            {
                DedgeNLog.Error(ex, "An error occurred while getting the log folder path");
                throw;
            }
        }

        /// <summary>
        /// Gets the application folder path for the current namespace.
        /// </summary>
        /// <returns>The full path to the application folder</returns>
        public string GetAppFolder()
        {
            try
            {
                string folder = $@"{_OptPath}\apps\{_FolderNamespacePath}";
                if (!Directory.Exists(folder))
                {
                    Directory.CreateDirectory(folder);
                }
                return folder;
            }
            catch
            {
                throw;
            }
        }

        /// <summary>
        /// Gets the COBOL integration folder path for the specified connection.
        /// </summary>
        /// <param name="connectionString">The database connection string</param>
        /// <returns>The path to the COBOL integration folder</returns>
        public string GetCobolIntFolder(string connectionString)
        {
            string databaseName = ExtractDatabaseName(connectionString);
            try
            {
                string folder = "";
                DatabasePath databasePath = databasePaths[databaseName];
                folder = databasePath.CobolIntFolder ?? string.Empty;
                return folder;
            }
            catch (Exception)
            {
                throw;
            }
        }
        public string GetCobolIntFolder(DedgeConnection.ConnectionKey connectionKey)
        {
            // Get database name and use the new method that accepts database name directly
            string databaseName = DedgeConnection.GetDatabaseName(connectionKey);
            return GetCobolIntFolderByDatabaseName(databaseName);
        }
        
        // ══════════════════════════════════════════════════════════
        // Proxy Methods to GlobalFunctions (for logical API consistency)
        // ══════════════════════════════════════════════════════════
        // Users should use FkFolders as the primary entry point for all folder operations
        
        /// <summary>
        /// Gets the DedgeCommon shared folder path.
        /// Proxy to GlobalFunctions.GetCommonPath()
        /// </summary>
        public static string GetCommonPath() => GlobalFunctions.GetCommonPath();

        /// <summary>
        /// Gets the CommonLog folder path.
        /// Proxy to GlobalFunctions.GetCommonLogPath()
        /// </summary>
        public static string GetCommonLogPath() => GlobalFunctions.GetCommonLogPath();

        /// <summary>
        /// Gets the DevTools web folder path.
        /// Proxy to GlobalFunctions.GetDevToolsWebPath()
        /// </summary>
        public static string GetDevToolsWebPath() => GlobalFunctions.GetDevToolsWebPath();

        /// <summary>
        /// Gets the DevTools web content folder path (where HTML files are deployed).
        /// Proxy to GlobalFunctions.GetDevToolsWebContent()
        /// </summary>
        public static string GetDevToolsWebContent() => GlobalFunctions.GetDevToolsWebContent();

        /// <summary>
        /// Gets the TempFk folder path.
        /// Proxy to GlobalFunctions.GetTempFkPath()
        /// </summary>
        public static string GetTempFkPath() => GlobalFunctions.GetTempFkPath();

        /// <summary>
        /// Gets the config files folder path.
        /// Proxy to GlobalFunctions.GetConfigFilesPath()
        /// </summary>
        public static string GetConfigFilesPath() => GlobalFunctions.GetConfigFilesPath();

        /// <summary>
        /// Gets the config files resources folder path.
        /// Proxy to GlobalFunctions.GetConfigFilesResourcesPath()
        /// </summary>
        public static string GetConfigFilesResourcesPath() => GlobalFunctions.GetConfigFilesResourcesPath();

        /// <summary>
        /// Gets the software folder path.
        /// Proxy to GlobalFunctions.GetSoftwarePath()
        /// </summary>
        public static string GetSoftwarePath() => GlobalFunctions.GetSoftwarePath();

        /// <summary>
        /// Gets the PowerShell apps folder path.
        /// Proxy to GlobalFunctions.GetPowerShellAppsPath()
        /// </summary>
        public static string GetPowerShellAppsPath() => GlobalFunctions.GetPowerShellAppsPath();

        /// <summary>
        /// Gets the logfiles folder path.
        /// Proxy to GlobalFunctions.GetLogfilesPath()
        /// </summary>
        public static string GetLogfilesPath() => GlobalFunctions.GetLogfilesPath();

        // ══════════════════════════════════════════════════════════
        // COBOL Folder Methods (FkFolders-specific functionality)
        // ══════════════════════════════════════════════════════════

        /// <summary>
        /// Gets the COBOL INT folder path for a given database name (catalog name).
        /// This overload accepts just the database name without needing a full connection string.
        /// COBOL INT Folder = COBOL Object Path (they are the same location!)
        /// </summary>
        /// <param name="databaseName">The database catalog name (e.g., BASISPRO, BASISTST)</param>
        /// <returns>Path to COBOL INT folder (same as COBOL Object Path)</returns>
        public string GetCobolIntFolderByDatabaseName(string databaseName)
        {
            if (string.IsNullOrWhiteSpace(databaseName))
            {
                throw new ArgumentNullException(nameof(databaseName), "Database name cannot be null or empty");
            }
            
            // CRITICAL: COBOL INT Folder = COBOL Object Path
            // Use FkEnvironmentSettings to get the correct path (includes app server COB folder detection)
            var settings = FkEnvironmentSettings.GetSettings(overrideDatabase: databaseName);
            
            // Return the COBOL Object Path - this is where .rc, .mfout, and .int files all live
            return settings.CobolObjectPath;
        }

        private static string ExtractDatabaseName(string connectionString)
        {
            string databaseName = "";
            if (string.IsNullOrEmpty(connectionString))
            {
                throw new ArgumentNullException(nameof(connectionString) + " is null or empty. DatabaseName connection string is required.");
            }
            var splitConnectionString = connectionString.Split(';');
            foreach (var item in splitConnectionString)
            {
                if (item.Contains("DatabaseName"))
                {
                    databaseName = item.Split('=')[1];
                    break;
                }
            }

            if (string.IsNullOrEmpty(databaseName))
            {
                throw new ArgumentNullException(nameof(connectionString) + " is null or empty. Connection string does not contain database name.");
            }

            return databaseName;
        }
    }
}
