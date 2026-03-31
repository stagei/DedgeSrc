using System.Diagnostics;
using System.Reflection;
using System.Text;

namespace DedgeCommon
{
    /// <summary>
    /// Manages the execution of COBOL programs from .NET applications.
    /// Provides integration with Micro Focus COBOL runtime environment
    /// and handles program execution and monitoring.
    /// Enhanced version based on PowerShell Cobol-Handler module.
    /// </summary>
    /// <remarks>
    /// Features:
    /// - COBOL program execution management with environment auto-configuration
    /// - Runtime environment detection with version support (MF/VC)
    /// - Process monitoring and logging with transcript files
    /// - Return code validation and error handling
    /// - Output capture and processing
    /// - Integration with FkEnvironmentSettings for automatic configuration
    /// - Support for both batch (run.exe) and GUI (runw.exe) execution modes
    /// </remarks>
    /// <author>Geir Helge Starholm</author>
    public static class RunCblProgram
    {
        private static FkEnvironmentSettings? _environmentSettings;
        private static FkFolders? _fkFolders;

        public enum ExecutionMode
        {
            Batch,  // Uses run.exe
            Gui     // Uses runw.exe
        }

        /// <summary>
        /// Initializes or refreshes the COBOL environment settings.
        /// Uses FkEnvironmentSettings for automatic configuration.
        /// </summary>
        /// <param name="overrideDatabase">Optional database name to override auto-detection</param>
        /// <param name="force">Force recreation of environment settings</param>
        private static void EnsureInitialized(string? overrideDatabase = null, bool force = false)
        {
            if (_environmentSettings == null || force || 
                (!string.IsNullOrEmpty(overrideDatabase) && _environmentSettings.Database != overrideDatabase))
            {
                _environmentSettings = FkEnvironmentSettings.GetSettings(
                    force: force,
                    overrideDatabase: overrideDatabase);

                _fkFolders = new FkFolders();

                DedgeNLog.Info($"COBOL environment initialized: Database={_environmentSettings.Database}, Version={_environmentSettings.Version}");
                DedgeNLog.Debug($"COBOL Object Path: {_environmentSettings.CobolObjectPath}");
                DedgeNLog.Debug($"COBOL Runtime: {_environmentSettings.CobolRuntimeExecutable ?? "Not found"}");

                // Register code pages for COBOL encoding
                Encoding.RegisterProvider(CodePagesEncodingProvider.Instance);
            }
        }

        /// <summary>
        /// Checks and processes the COBOL program return code file.
        /// </summary>
        /// <param name="programName">The name of the COBOL program</param>
        private static void CheckProcessLog(string programName)
        {
            if (_environmentSettings == null || _fkFolders == null)
            {
                throw new InvalidOperationException("Environment not initialized");
            }

            string cobolIntFolder = _fkFolders.GetCobolIntFolderByDatabaseName(_environmentSettings.Database);
            string rcFile = Path.Combine(cobolIntFolder, $"{programName}.rc");

            if (File.Exists(rcFile))
            {
                string rcContent = File.ReadAllText(rcFile, Encoding.ASCII);
                
                if (rcContent.Length >= 4)
                {
                    string code = rcContent.Substring(0, 4);
                    
                    if (code != "0000")
                    {
                        string message = rcContent.Length > 4 ? rcContent.Substring(4) : "No message";
                        string wkmon = $"{DateTime.Now:yyyyMMddHHmmss} {programName} {code} {Environment.MachineName}: {message}";
                        DedgeNLog.Warn($"COBOL program {programName} returned code {code}: {message}");

                        // Write to monitor file (pass database name for environment detection)
                        WriteMonitorFile(wkmon, _environmentSettings.Database);
                    }
                    else
                    {
                        DedgeNLog.Info($"COBOL program {programName} completed successfully: {rcContent}");
                    }
                }
                else
                {
                    DedgeNLog.Warn($"RC file for {programName} has invalid format (too short): {rcContent}");
                }
            }
            else
            {
                string message = $"RC-file for {programName} not found!";
                string code = "0016";
                string wkmon = $"{DateTime.Now:yyyyMMddHHmmss} {programName} {code} {Environment.MachineName}: {message}";
                DedgeNLog.Error(wkmon);

                // Write to monitor file (pass database name for environment detection)
                WriteMonitorFile(wkmon, _environmentSettings.Database);
            }
        }

        /// <summary>
        /// Writes a monitor file for COBOL program execution tracking.
        /// Monitor files are always written to network location based on environment.
        /// </summary>
        private static void WriteMonitorFile(string content, string databaseName)
        {
            try
            {
                // Get environment settings to determine correct network path
                var settings = FkEnvironmentSettings.GetSettings(overrideDatabase: databaseName);
                
                // Monitor files always go to network location, not local COBOL Object Path
                string monitorPath;
                if (settings.Environment.Equals("PRD", StringComparison.OrdinalIgnoreCase))
                {
                    monitorPath = @"\\DEDGE.fk.no\erpprog\cobnt\monitor";
                }
                else
                {
                    // TST, UTB, DEV, etc. all use cobtst
                    monitorPath = @"\\DEDGE.fk.no\erpprog\cobtst\monitor";
                }
                
                DedgeNLog.Debug($"Monitor file path: {monitorPath}");
                
                if (!Directory.Exists(monitorPath))
                {
                    DedgeNLog.Warn($"Monitor directory does not exist (unusual): {monitorPath}");
                    Directory.CreateDirectory(monitorPath);
                }

                string monitorFilename = Path.Combine(monitorPath, $"{Environment.MachineName}{DateTime.Now:yyyyMMddHHmmss}.MON");
                File.WriteAllText(monitorFilename, content, Encoding.ASCII);
                DedgeNLog.Debug($"Monitor file written: {monitorFilename}");
            }
            catch (Exception ex)
            {
                DedgeNLog.Warn($"Failed to write monitor file: {ex.Message}");
            }
        }

        /// <summary>
        /// Gets the return code from a COBOL program's RC file.
        /// </summary>
        /// <param name="programName">The name of the COBOL program</param>
        /// <returns>Return code as 4-character string, or error code if file not found</returns>
        private static string GetReturnCode(string programName)
        {
            if (_environmentSettings == null || _fkFolders == null)
            {
                throw new InvalidOperationException("Environment not initialized");
            }

            string cobolIntFolder = _fkFolders.GetCobolIntFolderByDatabaseName(_environmentSettings.Database);
            string rcFile = Path.Combine(cobolIntFolder, $"{programName}.rc");

            if (File.Exists(rcFile))
            {
                string rcContent = File.ReadAllText(rcFile, Encoding.ASCII);
                return rcContent.Length >= 4 ? rcContent.Substring(0, 4) : "9998";
            }

            return "9999";  // File not found
        }

        /// <summary>
        /// Tests if a COBOL program completed successfully (return code 0000).
        /// </summary>
        /// <param name="programName">The name of the COBOL program</param>
        /// <returns>True if return code is 0000</returns>
        public static bool TestReturnCode(string programName)
        {
            string returnCode = GetReturnCode(programName);
            return returnCode == "0000";
        }

        /// <summary>
        /// Runs a COBOL program with automatic environment configuration.
        /// This is the main entry point matching the PowerShell CBLRun function.
        /// </summary>
        /// <param name="programName">The name of the COBOL program to run (without extension)</param>
        /// <param name="databaseName">The database name (catalog name like BASISTST, BASISPRO, etc.)</param>
        /// <param name="cblParams">Additional parameters to pass to the COBOL program</param>
        /// <param name="mode">The execution mode (Batch or GUI). Defaults to Batch.</param>
        /// <returns>True if the program executed successfully (return code 0000), false otherwise</returns>
        public static bool CblRun(
            string programName, 
            string databaseName, 
            string[]? cblParams = null,
            ExecutionMode mode = ExecutionMode.Batch)
        {
            try
            {
                DedgeNLog.Info($"=== COBOL Program Execution Start ===");
                DedgeNLog.Info($"Program Name: {programName}");
                DedgeNLog.Info($"Database Name: {databaseName}");
                DedgeNLog.Info($"Parameters: {(cblParams != null && cblParams.Length > 0 ? string.Join(", ", cblParams) : "(none)")}");
                DedgeNLog.Info($"Execution Mode: {mode}");
                
                // Initialize environment (will use database to auto-configure paths)
                DedgeNLog.Info($"Initializing COBOL environment for database: {databaseName}");
                EnsureInitialized(overrideDatabase: databaseName);

                if (_environmentSettings == null || _fkFolders == null)
                {
                    DedgeNLog.Error($"FATAL: Failed to initialize COBOL environment - settings or folders are null");
                    DedgeNLog.Error($"  _environmentSettings: {(_environmentSettings == null ? "NULL" : "OK")}");
                    DedgeNLog.Error($"  _fkFolders: {(_fkFolders == null ? "NULL" : "OK")}");
                    throw new InvalidOperationException("Failed to initialize COBOL environment");
                }

                DedgeNLog.Info($"Environment initialized successfully:");
                DedgeNLog.Info($"  Application: {_environmentSettings.Application}");
                DedgeNLog.Info($"  Environment: {_environmentSettings.Environment}");
                DedgeNLog.Info($"  Database: {_environmentSettings.Database}");
                DedgeNLog.Info($"  COBOL Version: {_environmentSettings.Version}");
                DedgeNLog.Info($"  Is Server: {_environmentSettings.IsServer}");
                DedgeNLog.Info($"  COBOL Object Path: {_environmentSettings.CobolObjectPath}");

                // Verify runtime executable exists
                string? runtimeExe = mode == ExecutionMode.Batch 
                    ? _environmentSettings.CobolRuntimeExecutable 
                    : _environmentSettings.CobolWindowsRuntimeExecutable;

                DedgeNLog.Info($"COBOL Runtime Executable:");
                DedgeNLog.Info($"  Path: {runtimeExe ?? "NULL"}");
                DedgeNLog.Info($"  Exists: {(!string.IsNullOrEmpty(runtimeExe) && File.Exists(runtimeExe))}");

                if (string.IsNullOrEmpty(runtimeExe) || !File.Exists(runtimeExe))
                {
                    DedgeNLog.Error($"FATAL: COBOL runtime executable not found!");
                    DedgeNLog.Error($"  Mode: {mode}");
                    DedgeNLog.Error($"  Expected path: {runtimeExe ?? "null"}");
                    DedgeNLog.Error($"  Batch exe: {_environmentSettings.CobolRuntimeExecutable ?? "null"}");
                    DedgeNLog.Error($"  GUI exe: {_environmentSettings.CobolWindowsRuntimeExecutable ?? "null"}");
                    throw new FileNotFoundException(
                        $"COBOL runtime executable not found for mode {mode}. " +
                        $"Expected: {runtimeExe ?? "null"}. " +
                        "Please ensure Micro Focus COBOL is installed.");
                }

                // Get COBOL working directory (use database name directly)
                DedgeNLog.Info($"Getting COBOL INT folder for database: {databaseName}");
                string cobolIntFolder = _fkFolders.GetCobolIntFolderByDatabaseName(databaseName);
                DedgeNLog.Info($"  COBOL INT Folder: {cobolIntFolder}");
                DedgeNLog.Info($"  Folder Exists: {Directory.Exists(cobolIntFolder)}");
                
                // CRITICAL: NEVER create COBOL INT folder - it must exist!
                // Local COB folders (E:\COBPRD, E:\COBTST, etc.) are pre-created on app servers
                // Network paths (\\DEDGE.fk.no\erpprog\cobnt\, etc.) are always available
                if (!Directory.Exists(cobolIntFolder))
                {
                    DedgeNLog.Error($"FATAL: COBOL INT folder does not exist: {cobolIntFolder}");
                    DedgeNLog.Error($"  Database: {databaseName}");
                    DedgeNLog.Error($"  Environment: {_environmentSettings.Environment}");
                    DedgeNLog.Error($"  Expected locations:");
                    DedgeNLog.Error($"    - Local COB folder (app servers only): E:\\COB{_environmentSettings.Environment}\\");
                    DedgeNLog.Error($"    - Network share (workstations): \\\\DEDGE.fk.no\\erpprog\\cobnt\\ or cobtst\\");
                    DedgeNLog.Error($"");
                    DedgeNLog.Error($"  COBOL INT folders are NEVER created automatically!");
                    DedgeNLog.Error($"  They must be pre-configured by system administrators.");
                    throw new DirectoryNotFoundException(
                        $"COBOL INT folder does not exist: {cobolIntFolder}. " +
                        $"This folder must exist before COBOL programs can run. " +
                        $"Contact system administrator to verify COBOL environment configuration.");
                }
                
                DedgeNLog.Debug($"COBOL INT folder exists: {cobolIntFolder}");
                
                string programFilePath = Path.Combine(_environmentSettings.CobolObjectPath, programName);
                DedgeNLog.Info($"Program File Path: {programFilePath}");
                DedgeNLog.Info($"  Exists: {File.Exists(programFilePath)}");

                // Prepare parameters
                string parameters = cblParams != null && cblParams.Length > 0 
                    ? string.Join(" ", cblParams) 
                    : string.Empty;

                // Log complete execution details
                DedgeNLog.Info($"COBOL Execution Command:");
                DedgeNLog.Info($"  Executable: {runtimeExe}");
                DedgeNLog.Info($"  Arguments: {programName} {databaseName} {parameters}");
                DedgeNLog.Info($"  Working Dir: {cobolIntFolder}");
                DedgeNLog.Info($"  Redirect Output: {mode == ExecutionMode.Batch}");
                DedgeNLog.Info($"  Redirect Error: true");
                DedgeNLog.Info($"  Use Shell Execute: false");
                DedgeNLog.Info($"  Create No Window: {mode == ExecutionMode.Batch}");

                // Create transcript file for output
                string transcriptFile = Path.Combine(cobolIntFolder, $"{programName}.mfout");
                
                using (StreamWriter writer = new StreamWriter(transcriptFile, append: true, Encoding.ASCII))
                {
                    writer.WriteLine($"\n=== Execution started at {DateTime.Now:yyyy-MM-dd HH:mm:ss} ===");
                    writer.WriteLine($"Program: {programName}");
                    writer.WriteLine($"Database: {databaseName}");
                    writer.WriteLine($"Parameters: {parameters}");
                    writer.WriteLine($"Runtime: {runtimeExe}");
                    writer.WriteLine("========================================\n");

                    // Set working directory to COBOL INT folder
                    string originalDirectory = Directory.GetCurrentDirectory();
                    Directory.SetCurrentDirectory(cobolIntFolder);

                    try
                    {
                        // Start COBOL program
                        Process process = new Process
                        {
                            StartInfo = new ProcessStartInfo
                            {
                                FileName = runtimeExe,
                                Arguments = $"{programName} {databaseName} {parameters}",
                                WorkingDirectory = cobolIntFolder,
                                RedirectStandardOutput = mode == ExecutionMode.Batch,
                                RedirectStandardError = true,
                                UseShellExecute = false,
                                CreateNoWindow = mode == ExecutionMode.Batch
                            }
                        };

                        process.Start();
                        DedgeNLog.Debug($"COBOL process started with PID: {process.Id}");

                        // Capture output for batch mode
                        if (mode == ExecutionMode.Batch)
                        {
                            string output = process.StandardOutput.ReadToEnd();
                            string errors = process.StandardError.ReadToEnd();

                            if (!string.IsNullOrEmpty(output))
                            {
                                writer.Write(output);
                            }

                            if (!string.IsNullOrEmpty(errors))
                            {
                                writer.WriteLine("\n=== STDERR ===");
                                writer.Write(errors);
                                DedgeNLog.Warn($"COBOL program produced error output: {errors}");
                            }
                        }

                        process.WaitForExit();
                        
                        writer.WriteLine($"\n=== Execution completed at {DateTime.Now:yyyy-MM-dd HH:mm:ss} ===");
                        writer.WriteLine($"Exit Code: {process.ExitCode}");
                    }
                    finally
                    {
                        // Restore original directory
                        Directory.SetCurrentDirectory(originalDirectory);
                    }
                }

                // Check return code
                string returnCode = GetReturnCode(programName);
                bool success = returnCode == "0000";
                
                DedgeNLog.Info($"COBOL program execution completed:");
                DedgeNLog.Info($"  Program: {programName}");
                DedgeNLog.Info($"  Return Code: {returnCode}");
                DedgeNLog.Info($"  Success: {success}");
                
                if (success)
                {
                    DedgeNLog.Info($"COBOL program {programName} completed successfully");
                    CheckProcessLog(programName);
                }
                else
                {
                    DedgeNLog.Error($"=== COBOL PROGRAM FAILED ===");
                    DedgeNLog.Error($"Program: {programName}");
                    DedgeNLog.Error($"Return Code: {returnCode}");
                    DedgeNLog.Error($"Database: {databaseName}");
                    DedgeNLog.Error($"COBOL INT Folder: {cobolIntFolder}");
                    DedgeNLog.Error($"Program File: {programFilePath}");
                    DedgeNLog.Error($"Runtime: {runtimeExe}");
                    DedgeNLog.Error($"Parameters: {parameters}");
                    DedgeNLog.Error($"RC File: {Path.Combine(cobolIntFolder, $"{programName}.rc")}");
                    DedgeNLog.Error($"Transcript File: {Path.Combine(cobolIntFolder, $"{programName}.mfout")}");
                    DedgeNLog.Error($"Check these files for details");
                    CheckProcessLog(programName);
                }
                
                DedgeNLog.Info($"=== COBOL Program Execution End ===");

                return success;
            }
            catch (Exception ex)
            {
                DedgeNLog.Error($"=== COBOL PROGRAM EXCEPTION ===");
                DedgeNLog.Error($"Program: {programName}");
                DedgeNLog.Error($"Database: {databaseName}");
                DedgeNLog.Error($"Exception Type: {ex.GetType().Name}");
                DedgeNLog.Error($"Exception Message: {ex.Message}");
                DedgeNLog.Error($"Stack Trace:");
                DedgeNLog.Error(ex.StackTrace ?? "(no stack trace)");
                
                // Log environment state if available
                if (_environmentSettings != null)
                {
                    DedgeNLog.Error($"Environment Settings:");
                    DedgeNLog.Error($"  Database: {_environmentSettings.Database}");
                    DedgeNLog.Error($"  COBOL Path: {_environmentSettings.CobolObjectPath}");
                    DedgeNLog.Error($"  Runtime Exe: {_environmentSettings.CobolRuntimeExecutable ?? "null"}");
                }
                else
                {
                    DedgeNLog.Error($"Environment Settings: NULL (not initialized)");
                }
                
                if (_fkFolders != null && !string.IsNullOrEmpty(databaseName))
                {
                    try
                    {
                        string cobolIntFolder = _fkFolders.GetCobolIntFolderByDatabaseName(databaseName);
                        DedgeNLog.Error($"  COBOL INT Folder: {cobolIntFolder}");
                        DedgeNLog.Error($"  Folder Exists: {Directory.Exists(cobolIntFolder)}");
                    }
                    catch
                    {
                        DedgeNLog.Error($"  Could not determine COBOL INT folder");
                    }
                }
                
                DedgeNLog.Error($"=== END COBOL EXCEPTION ===");
                throw;
            }
        }

        /// <summary>
        /// Simplified overload using ConnectionKey for database lookup.
        /// </summary>
        public static bool CblRun(
            DedgeConnection.ConnectionKey connectionKey,
            string programName,
            string[]? cblParams = null,
            ExecutionMode mode = ExecutionMode.Batch)
        {
            var accessPoint = DedgeConnection.GetConnectionStringInfo(connectionKey);
            return CblRun(programName, accessPoint.CatalogName, cblParams, mode);
        }

        /// <summary>
        /// Gets the COBOL object path for the current environment.
        /// </summary>
        public static string GetCobolObjectPath()
        {
            EnsureInitialized();
            return _environmentSettings?.CobolObjectPath ?? string.Empty;
        }

        /// <summary>
        /// Gets the current COBOL version (MF or VC).
        /// </summary>
        public static string GetCobolVersion()
        {
            EnsureInitialized();
            return _environmentSettings?.Version ?? "MF";
        }

        /// <summary>
        /// Gets the current environment settings.
        /// </summary>
        public static FkEnvironmentSettings GetEnvironmentSettings()
        {
            EnsureInitialized();
            return _environmentSettings ?? throw new InvalidOperationException("Environment not initialized");
        }

        /// <summary>
        /// Clears cached environment settings, forcing re-initialization on next run.
        /// </summary>
        public static void ClearCache()
        {
            _environmentSettings = null;
            _fkFolders = null;
            FkEnvironmentSettings.ClearCache();
            DedgeNLog.Debug("COBOL environment cache cleared");
        }
    }
}


