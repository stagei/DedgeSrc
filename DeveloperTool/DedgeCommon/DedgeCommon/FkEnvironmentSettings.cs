using System.Runtime.InteropServices;

namespace DedgeCommon
{
    /// <summary>
    /// Provides centralized management of Dedge environment settings including COBOL paths,
    /// database configuration, and runtime environment detection.
    /// This class replaces the PowerShell Get-GlobalEnvironmentSettings function.
    /// </summary>
    /// <remarks>
    /// Features:
    /// - Automatic environment detection (server vs workstation)
    /// - COBOL version and path management (MF/VC)
    /// - Database configuration based on environment
    /// - COBOL executable path detection
    /// - Caching for performance
    /// </remarks>
    public class FkEnvironmentSettings
    {
        // Constants
        private const int MinimumIntFilesForLocalCobFolder = 100;
        
        private static FkEnvironmentSettings? _instance;
        private static readonly object _lock = new object();

        // Core properties
        public string DedgePshAppsPath { get; set; } = string.Empty;
        public string Database { get; set; } = string.Empty;
        public string CobolObjectPath { get; set; } = string.Empty;
        public string Version { get; set; } = "MF";  // MF or VC
        public bool IsServer { get; set; }
        public string Application { get; set; } = string.Empty;
        public string Environment { get; set; } = string.Empty;
        public string ScriptPath { get; set; } = string.Empty;

        // Database properties
        public string DatabaseInternalName { get; set; } = string.Empty;
        public string DatabaseNorwegianDescription { get; set; } = string.Empty;
        public string DatabaseEnglishDescription { get; set; } = string.Empty;
        public string DatabaseServerName { get; set; } = string.Empty;
        public string DatabaseProvider { get; set; } = string.Empty;
        public string DatabaseApplication { get; set; } = string.Empty;
        public string DatabaseEnvironment { get; set; } = string.Empty;

        // COBOL executable paths
        public string? CobolCompilerExecutable { get; set; }
        public string? CobolDsWinExecutable { get; set; }
        public string? CobolRuntimeExecutable { get; set; }
        public string? CobolWindowsRuntimeExecutable { get; set; }

        // Additional paths
        public string EdiStandardPath { get; set; } = @"\\DEDGE.fk.no\ERPdata\EDI";
        public string D365Path { get; set; } = string.Empty;

        // Access point from configuration
        public DedgeConnection.FkDatabaseAccessPoint? AccessPoint { get; set; }

        /// <summary>
        /// Gets the singleton instance of FkEnvironmentSettings with caching.
        /// </summary>
        /// <param name="force">Forces recreation of settings even if cached</param>
        /// <param name="overrideVersion">Override the COBOL version (MF or VC)</param>
        /// <param name="overrideDatabase">Override the database name</param>
        /// <param name="overrideCobolObjectPath">Override the COBOL object path</param>
        /// <returns>The current environment settings</returns>
        public static FkEnvironmentSettings GetSettings(
            bool force = false,
            string? overrideVersion = null,
            string? overrideDatabase = null,
            string? overrideCobolObjectPath = null)
        {
            if (_instance != null && !force && 
                string.IsNullOrEmpty(overrideVersion) && 
                string.IsNullOrEmpty(overrideDatabase) && 
                string.IsNullOrEmpty(overrideCobolObjectPath))
            {
                return _instance;
            }

            lock (_lock)
            {
                if (_instance != null && !force && 
                    string.IsNullOrEmpty(overrideVersion) && 
                    string.IsNullOrEmpty(overrideDatabase) && 
                    string.IsNullOrEmpty(overrideCobolObjectPath))
                {
                    return _instance;
                }

                _instance = CreateSettings(overrideVersion, overrideDatabase, overrideCobolObjectPath);
                return _instance;
            }
        }

        /// <summary>
        /// Clears the cached settings, forcing recreation on next GetSettings call.
        /// </summary>
        public static void ClearCache()
        {
            lock (_lock)
            {
                _instance = null;
            }
        }

        private static FkEnvironmentSettings CreateSettings(
            string? overrideVersion,
            string? overrideDatabase,
            string? overrideCobolObjectPath)
        {
            var settings = new FkEnvironmentSettings();

            // Determine COBOL version
            settings.Version = DetermineVersion(overrideVersion);
            DedgeNLog.Debug($"Using COBOL version: {settings.Version}");

            // Determine COBOL object path
            settings.CobolObjectPath = DetermineCobolObjectPath(overrideCobolObjectPath);
            DedgeNLog.Debug($"Using COBOL object path: {settings.CobolObjectPath}");

            // Detect if running on server
            settings.IsServer = IsServerEnvironment();
            DedgeNLog.Debug($"IsServer: {settings.IsServer}");

            // Get current script/application path
            settings.ScriptPath = System.IO.Path.GetDirectoryName(System.Reflection.Assembly.GetEntryAssembly()?.Location) ?? string.Empty;

            // Detect executable paths for the selected version
            DetectCobolExecutables(settings);

            // Set DedgePshAppsPath
            string optPath = System.Environment.GetEnvironmentVariable("OptPath") ?? @"C:\opt";
            settings.DedgePshAppsPath = System.IO.Path.Combine(optPath, "DedgePshApps") + "\\";

            // Determine database and access point
            DetermineDatabaseConfiguration(settings, overrideDatabase);

            // Set environment-specific paths
            SetEnvironmentSpecificPaths(settings);

            // Log the final configuration
            DedgeNLog.Info($"Environment Settings Created: App={settings.Application}, Env={settings.Environment}, Database={settings.Database}, Version={settings.Version}, IsServer={settings.IsServer}");

            return settings;
        }

        private static string DetermineVersion(string? overrideVersion)
        {
            if (!string.IsNullOrEmpty(overrideVersion) && (overrideVersion.ToUpper() == "MF" || overrideVersion.ToUpper() == "VC"))
            {
                return overrideVersion.ToUpper();
            }

            // Check environment variable
            string? envVersion = System.Environment.GetEnvironmentVariable("CobolVersion");
            if (!string.IsNullOrEmpty(envVersion) && (envVersion.ToUpper() == "MF" || envVersion.ToUpper() == "VC"))
            {
                return envVersion.ToUpper();
            }

            // Default to MF
            return "MF";
        }

        private static string DetermineCobolObjectPath(string? overrideCobolObjectPath)
        {
            if (!string.IsNullOrEmpty(overrideCobolObjectPath))
            {
                return overrideCobolObjectPath;
            }

            // Check environment variable
            string? envPath = System.Environment.GetEnvironmentVariable("CobolObjectPath");
            if (!string.IsNullOrEmpty(envPath))
            {
                return envPath;
            }

            // Default path
            return @"\\DEDGE.fk.no\erpprog\cobnt\";
        }

        private static bool IsServerEnvironment()
        {
            string computerName = System.Environment.MachineName;
            
            // Server pattern: *-no*-app or *-no*-db
            return computerName.Contains("-no") && 
                   (computerName.EndsWith("-app", StringComparison.OrdinalIgnoreCase) ||
                    computerName.EndsWith("-db", StringComparison.OrdinalIgnoreCase));
        }

        private static void DetectCobolExecutables(FkEnvironmentSettings settings)
        {
            var executableFinder = new CobolExecutableFinder();
            var executables = executableFinder.FindExecutables(settings.Version, settings.IsServer);

            settings.CobolCompilerExecutable = executables.CobolExe;
            settings.CobolDsWinExecutable = executables.DsWinExe;
            settings.CobolRuntimeExecutable = executables.RunExe;
            settings.CobolWindowsRuntimeExecutable = executables.RunwExe;

            if (!string.IsNullOrEmpty(settings.CobolRuntimeExecutable))
            {
                DedgeNLog.Debug($"Found COBOL runtime: {settings.CobolRuntimeExecutable}");
            }
        }

        private static void DetermineDatabaseConfiguration(FkEnvironmentSettings settings, string? overrideDatabase)
        {
            try
            {
                DedgeConnection.FkDatabaseAccessPoint? accessPoint = null;

                // Priority 1: OverrideDatabase
                if (!string.IsNullOrEmpty(overrideDatabase))
                {
                    try
                    {
                        accessPoint = DedgeConnection.GetAccessPointByDatabaseName(overrideDatabase);
                        DedgeNLog.Info($"Using override database: {overrideDatabase}");
                    }
                    catch (Exception ex)
                    {
                        DedgeNLog.Warn($"Override database '{overrideDatabase}' not found: {ex.Message}");
                    }
                }

                // Priority 2: Detect from server name
                if (accessPoint == null && settings.IsServer)
                {
                    string computerName = System.Environment.MachineName.ToUpper();
                    
                    // FSP servers - extract from path
                    if (computerName.Contains("FSP"))
                    {
                        // TODO: Implement path-based database detection for FSP servers
                        DedgeNLog.Debug("FSP server detected - using default database");
                    }
                    else
                    {
                        // Extract database from server name pattern: p-no1fkmtst-app → FKMTST
                        string? databaseName = ExtractDatabaseFromServerName(computerName);
                        if (!string.IsNullOrEmpty(databaseName))
                        {
                            try
                            {
                                accessPoint = DedgeConnection.GetAccessPointByDatabaseName(databaseName);
                                DedgeNLog.Info($"Detected database from server name: {databaseName}");
                            }
                            catch (Exception ex)
                            {
                                DedgeNLog.Warn($"Could not load database from server name '{databaseName}': {ex.Message}");
                            }
                        }
                    }
                }

                // Priority 3: Default to FKMPRD
                if (accessPoint == null)
                {
                    try
                    {
                        accessPoint = DedgeConnection.GetAccessPointByDatabaseName("FKMPRD");
                        DedgeNLog.Info("Using default database: FKMPRD");
                    }
                    catch (Exception ex)
                    {
                        DedgeNLog.Error($"Could not load default database FKMPRD: {ex.Message}");
                        throw;
                    }
                }

                // Set all database-related properties
                if (accessPoint != null)
                {
                    settings.AccessPoint = accessPoint;
                    settings.Database = accessPoint.CatalogName;
                    settings.DatabaseInternalName = accessPoint.DatabaseName;
                    settings.DatabaseNorwegianDescription = accessPoint.NorwegianDescription;
                    settings.DatabaseEnglishDescription = accessPoint.Description;
                    settings.DatabaseServerName = accessPoint.ServerName;
                    settings.DatabaseProvider = accessPoint.Provider;
                    settings.DatabaseApplication = accessPoint.FkApplication;
                    settings.DatabaseEnvironment = accessPoint.Environment;
                    settings.Application = accessPoint.FkApplication;
                    settings.Environment = accessPoint.Environment;

                    // Set COBOL object path based on database
                    settings.CobolObjectPath = GetCobolObjectPathForDatabase(settings.Database);
                }
            }
            catch (Exception ex)
            {
                DedgeNLog.Error(ex, "Failed to determine database configuration");
                throw;
            }
        }

        private static string? ExtractDatabaseFromServerName(string computerName)
        {
            // Pattern: p-no1fkmtst-app → FKMTST
            //          t-no1inldev-db → INLDEV
            
            var parts = computerName.Split('-');
            if (parts.Length >= 3)
            {
                // Take the 3rd part (fkmtst, inldev, etc.) and uppercase it
                return parts[2].ToUpper();
            }

            return null;
        }

        private static string GetCobolObjectPathForDatabase(string catalogName)
        {
            // Map catalog names to COBOL object paths
            return catalogName.ToUpper() switch
            {
                "FKAVDNT" => @"\\DEDGE.fk.no\erputv\Utvikling\fkavd\nt\",
                "BASISTST" => @"\\DEDGE.fk.no\erpprog\cobtst\",
                "BASISVFT" => @"\\DEDGE.fk.no\erpprog\cobtst\cobvft\",
                "BASISVFK" => @"\\DEDGE.fk.no\erpprog\cobtst\cobvfk\",
                "BASISMIG" => @"\\DEDGE.fk.no\erpprog\cobtst\cobmig\",
                "BASISSIT" => @"\\DEDGE.fk.no\erpprog\cobtst\cobsit\",
                "BASISPER" => @"\\DEDGE.fk.no\erpprog\cobtst\cobper\",
                "BASISFUT" => @"\\DEDGE.fk.no\erpprog\cobtst\cobfut\",
                "BASISKAT" => @"\\DEDGE.fk.no\erpprog\cobtst\cobkat\",
                "BASISRAP" => @"\\DEDGE.fk.no\erpprog\cobtst\cobrap\",
                "BASISPRO" => @"\\DEDGE.fk.no\erpprog\cobnt\",
                "FKKTOTST" => @"\\DEDGE.fk.no\erpprog\cobtst\",
                "FKKTOPRD" => @"\\DEDGE.fk.no\erpprog\cobprd\",
                "FKKONTO" => @"\\DEDGE.fk.no\erpprog\cobnt\",
                "FKKTODEV" => @"\\DEDGE.fk.no\erputv\Utvikling\fkavd\nt\",
                _ => @"\\DEDGE.fk.no\erpprog\cobnt\"
            };
        }

        private static void SetEnvironmentSpecificPaths(FkEnvironmentSettings settings)
        {
            // Set D365 path based on environment (FKM only)
            if (settings.Application == "FKM")
            {
                settings.D365Path = settings.Environment.ToUpper() switch
                {
                    "DEV" => @"C:\TempFk\d365\DEV",
                    "TST" => @"C:\TempFk\d365\TST",
                    "PRD" => @"C:\TempFk\d365\PRD",
                    _ => string.Empty
                };

                // Create D365 directory if it doesn't exist
                if (!string.IsNullOrEmpty(settings.D365Path) && !Directory.Exists(settings.D365Path))
                {
                    try
                    {
                        Directory.CreateDirectory(settings.D365Path);
                        DedgeNLog.Debug($"Created D365 path: {settings.D365Path}");
                    }
                    catch (Exception ex)
                    {
                        DedgeNLog.Warn($"Failed to create D365 path {settings.D365Path}: {ex.Message}");
                    }
                }
            }

            // Override COBOL object path if on app server with specific environment
            if (settings.IsServer && 
                System.Environment.MachineName.ToUpper().EndsWith("-APP") && 
                settings.Environment.Length == 3)
            {
                string findFolderName = $"COB{settings.Environment}";
                DedgeNLog.Debug($"App server detected - searching for folder: {findFolderName}");
                
                // Search for COB folder on all valid drives
                string? foundFolderPath = FindCobFolder(findFolderName);
                
                if (!string.IsNullOrEmpty(foundFolderPath))
                {
                    DedgeNLog.Debug($"Found COB folder: {foundFolderPath}");
                    
                    // Ensure path ends with backslash
                    if (!foundFolderPath.EndsWith("\\"))
                    {
                        foundFolderPath += "\\";
                    }
                    
                    settings.CobolObjectPath = foundFolderPath;
                    DedgeNLog.Info($"Using app-server specific COBOL path: {foundFolderPath}");
                }
                else
                {
                    DedgeNLog.Debug($"COB folder '{findFolderName}' not found on app server, using default path");
                }
            }
        }
        
        /// <summary>
        /// Searches for a COB folder across all valid drives.
        /// NEVER creates the folder - only searches for existing ones.
        /// Only accepts folder if it contains at least MinimumIntFilesForLocalCobFolder .int files.
        /// Mimics the PowerShell Find-ExistingFolder function behavior.
        /// </summary>
        private static string? FindCobFolder(string folderName)
        {
            try
            {
                // Get all fixed drives (C:, D:, E:, etc.) - exclude network and removable drives
                var validDrives = DriveInfo.GetDrives()
                    .Where(d => d.DriveType == DriveType.Fixed && d.IsReady)
                    .OrderBy(d => d.Name) // C: first, then D:, E:, etc.
                    .ToList();
                
                // Search each drive for the folder
                foreach (var drive in validDrives)
                {
                    string testPath = Path.Combine(drive.RootDirectory.FullName, folderName);
                    
                    // CRITICAL: Only search for folder, NEVER create it!
                    if (Directory.Exists(testPath))
                    {
                        // Validate that this is a real COBOL folder by checking for .int files
                        try
                        {
                            int intFileCount = Directory.GetFiles(testPath, "*.int", SearchOption.TopDirectoryOnly).Length;
                            
                            if (intFileCount >= MinimumIntFilesForLocalCobFolder)
                            {
                                DedgeNLog.Debug($"Found valid COB folder on {drive.Name}: {testPath}");
                                DedgeNLog.Debug($"  Contains {intFileCount} .int files (minimum: {MinimumIntFilesForLocalCobFolder})");
                                return testPath;
                            }
                            else
                            {
                                DedgeNLog.Debug($"Found COB folder on {drive.Name} but insufficient .int files: {testPath}");
                                DedgeNLog.Debug($"  Contains {intFileCount} .int files (minimum required: {MinimumIntFilesForLocalCobFolder})");
                                DedgeNLog.Debug($"  Skipping this folder and continuing search");
                            }
                        }
                        catch (Exception ex)
                        {
                            DedgeNLog.Warn($"Error counting .int files in {testPath}: {ex.Message}");
                            // Continue searching other drives
                        }
                    }
                }
                
                DedgeNLog.Debug($"COB folder '{folderName}' not found on any drive (or found but didn't meet validation criteria)");
                return null;
            }
            catch (Exception ex)
            {
                DedgeNLog.Warn($"Error searching for COB folder '{folderName}': {ex.Message}");
                return null;
            }
        }

        /// <summary>
        /// Gets a human-readable summary of current environment settings.
        /// </summary>
        public override string ToString()
        {
            return $"Environment Settings:\n" +
                   $"  Application: {Application}\n" +
                   $"  Environment: {Environment}\n" +
                   $"  Database: {Database} ({DatabaseInternalName})\n" +
                   $"  Version: {Version}\n" +
                   $"  IsServer: {IsServer}\n" +
                   $"  CobolObjectPath: {CobolObjectPath}\n" +
                   $"  CobolRuntime: {CobolRuntimeExecutable ?? "Not found"}";
        }
    }

    /// <summary>
    /// Finds COBOL executables in standard Micro Focus installation paths.
    /// </summary>
    internal class CobolExecutableFinder
    {
        public class CobolExecutables
        {
            public string? CobolExe { get; set; }
            public string? DsWinExe { get; set; }
            public string? RunExe { get; set; }
            public string? RunwExe { get; set; }
        }

        private static readonly string[] ProgramFilesPaths = new[]
        {
            @"C:\Program Files",
            @"C:\Program Files (x86)"
        };

        private static readonly Dictionary<string, string[]> PotentialPaths = new()
        {
            // Visual COBOL
            { "VC_Base", new[] { @"Micro Focus\Visual COBOL\Base\bin", @"Micro Focus\Visual COBOL\Base\bin64" } },
            { "VC_DS", new[] { @"Micro Focus\Visual COBOL\DialogSystem\bin", @"Micro Focus\Visual COBOL\DialogSystem\bin64" } },
            
            // Enterprise Developer
            { "MF_ED_Base", new[] { @"Micro Focus\Enterprise Developer\Base\bin", @"Micro Focus\Enterprise Developer\Base\bin64" } },
            { "MF_ED_DS", new[] { @"Micro Focus\Enterprise Developer\DialogSystem\bin", @"Micro Focus\Enterprise Developer\DialogSystem\bin64" } },
            
            // Net Express
            { "MF_NE_Base", new[] { @"Micro Focus\Net Express 5.1\Base\bin", @"Micro Focus\Net Express 5.1\Base\bin64" } },
            { "MF_NE_DS", new[] { @"Micro Focus\Net Express 5.1\DialogSystem\bin", @"Micro Focus\Net Express 5.1\DialogSystem\bin64" } },
            
            // Enterprise Server
            { "MF_ES", new[] { @"Micro Focus\Enterprise Server\Bin" } },
            { "MF_Server", new[] { @"Micro Focus\Server 5.1\Bin" } }
        };

        public CobolExecutables FindExecutables(string version, bool forceServer = false)
        {
            var executables = new CobolExecutables();

            // Search for executables
            foreach (var programFilesPath in ProgramFilesPaths)
            {
                foreach (var pathSet in PotentialPaths)
                {
                    // Filter by version
                    if (version == "VC" && !pathSet.Key.StartsWith("VC"))
                        continue;
                    if (version == "MF" && pathSet.Key.StartsWith("VC"))
                        continue;

                    foreach (var relativePath in pathSet.Value)
                    {
                        string fullPath = Path.Combine(programFilesPath, relativePath);
                        
                        if (Directory.Exists(fullPath))
                        {
                            // Check for each executable
                            if (executables.CobolExe == null)
                            {
                                string cobolPath = Path.Combine(fullPath, "cobol.exe");
                                if (File.Exists(cobolPath))
                                {
                                    executables.CobolExe = cobolPath;
                                    DedgeNLog.Debug($"Found cobol.exe: {cobolPath}");
                                }
                            }

                            if (executables.DsWinExe == null && pathSet.Key.Contains("_DS"))
                            {
                                string dswinPath = Path.Combine(fullPath, "dswin.exe");
                                if (File.Exists(dswinPath))
                                {
                                    executables.DsWinExe = dswinPath;
                                    DedgeNLog.Debug($"Found dswin.exe: {dswinPath}");
                                }
                            }

                            if (executables.RunExe == null)
                            {
                                string runPath = Path.Combine(fullPath, "run.exe");
                                if (File.Exists(runPath))
                                {
                                    executables.RunExe = runPath;
                                    DedgeNLog.Debug($"Found run.exe: {runPath}");
                                }
                            }

                            if (executables.RunwExe == null)
                            {
                                string runwPath = Path.Combine(fullPath, "runw.exe");
                                if (File.Exists(runwPath))
                                {
                                    executables.RunwExe = runwPath;
                                    DedgeNLog.Debug($"Found runw.exe: {runwPath}");
                                }
                            }
                        }
                    }
                }
            }

            // Check BIN_FOLDER environment variable as fallback
            string? binFolder = System.Environment.GetEnvironmentVariable("BIN_FOLDER");
            if (!string.IsNullOrEmpty(binFolder) && Directory.Exists(binFolder))
            {
                if (executables.RunExe == null)
                {
                    string runPath = Path.Combine(binFolder, "run.exe");
                    if (File.Exists(runPath))
                    {
                        executables.RunExe = runPath;
                        DedgeNLog.Info($"Found run.exe from BIN_FOLDER: {runPath}");
                    }
                }

                if (executables.RunwExe == null)
                {
                    string runwPath = Path.Combine(binFolder, "runw.exe");
                    if (File.Exists(runwPath))
                    {
                        executables.RunwExe = runwPath;
                        DedgeNLog.Info($"Found runw.exe from BIN_FOLDER: {runwPath}");
                    }
                }
            }

            return executables;
        }
    }
}
