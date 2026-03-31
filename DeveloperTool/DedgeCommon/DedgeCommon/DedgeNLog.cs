using NLog;
using NLog.Conditions;
using NLog.Config;
using NLog.Targets;
using System.Collections.Concurrent;
using System.Dynamic;
/// <summary>
/// Provides a comprehensive logging and operation tracking framework.
/// This class wraps NLog functionality with additional features for database logging,
/// operation progress tracking, and standardized log formatting.
/// </summary>
/// <remarks>
/// Key features:
/// - Console logging with color-coded output based on log levels
/// - File logging with automatic daily rotation and archiving
/// - Database logging support with configurable connection settings
/// - Operation tracking with progress visualization
/// - Stack-based operation management for nested operations
/// - Caller information tracking
/// 
/// Usage example:
/// <code>
/// DedgeNLog.StartOperation("Data Import", totalRecords);
/// foreach(var record in records) {
///     ProcessRecord(record);
///     DedgeNLog.OperationProgression(); // Shows progress bar
/// }
/// DedgeNLog.EndOperation();
/// </code>
/// </remarks>
/// <author>Geir Helge Starholm</author>
namespace DedgeCommon
{
    public static class LoggingConfigurationExtensions
    {
        public static void AddRule(this LoggingConfiguration config, DedgeNLog.LogLevel minLevel, DedgeNLog.LogLevel maxLevel, Target target)
        {
            config.AddRule(DedgeNLog.ToNLogLevel(minLevel), DedgeNLog.ToNLogLevel(maxLevel), target);
        }
    }

    //string severity, string message, Exception? exception = null




    public class DedgeNLog
    {
        private static readonly Logger Logger;
        private static bool _useDbLogging;
        private static DedgeConnection.ConnectionKey? _connectionKey;
        private static readonly ConcurrentStack<OperationInfo> _operationStack = new();
        private static string _logFilePath = "";
        private static readonly int _consoleWidth = 120;
        private static List<string> _otherLogFiles = [];
        private static LogLevel _minDbLevel = LogLevel.Info;
        private static LogLevel _maxDbLevel = LogLevel.Fatal;
        private class OperationInfo
        {
            public string Name { get; init; } = string.Empty;
            public int Goal { get; init; }
            public int Count { get; set; }
            public DateTime StartTime { get; init; }
            public string Prefix { get; init; } = string.Empty;
            public string LogFilePath { get; init; } = string.Empty;
        }
        public class LogEntry
        {
            public DateTime DateTime { get; set; }
            public string CallerInfo { get; set; }
            public string Severity { get; set; }
            public string Message { get; set; }
            public Exception? Exception { get; set; }

            public LogEntry(DateTime dateTime, string callerInfo, string severity, string message, Exception? exception = null)
            {
                DateTime = dateTime;
                CallerInfo = callerInfo;
                Severity = severity;
                Message = message;
                Exception = exception;
            }
        }

        // create an list of log entries
        private static List<LogEntry> _logEntries = new List<LogEntry>();

        /// <summary>
        /// Log levels available for logging configuration
        /// </summary>
        public enum LogLevel
        {
            Trace,
            Debug,
            Info,
            Warn,
            Error,
            Fatal
        }

        /// <summary>
        /// Converts DedgeNLog.LogLevel to NLog.LogLevel
        /// </summary>
        internal static NLog.LogLevel ToNLogLevel(LogLevel level)
        {
            return level switch
            {
                LogLevel.Trace => NLog.LogLevel.Trace,
                LogLevel.Debug => NLog.LogLevel.Debug,
                LogLevel.Info => NLog.LogLevel.Info,
                LogLevel.Warn => NLog.LogLevel.Warn,
                LogLevel.Error => NLog.LogLevel.Error,
                LogLevel.Fatal => NLog.LogLevel.Fatal,
                _ => NLog.LogLevel.Info
            };
        }

        static DedgeNLog()
        {
            // Set and store default console width
            try
            {
                Console.WindowWidth = _consoleWidth;
                //Resizing the console window to fit the screen
                Console.SetWindowSize(Console.LargestWindowWidth * 2 / 3, Console.LargestWindowHeight * 2 / 3);

            }
            catch
            {
                // If console width cannot be set, use default of 80
                _consoleWidth = 80;
            }

            // Register shutdown handler
            AppDomain.CurrentDomain.ProcessExit += (s, e) =>
            {
                LogShutdownInfo();
                SetConsoleLogLevels(LogLevel.Fatal, LogLevel.Fatal);
                InsertCachedLogging();
            };

            AppDomain.CurrentDomain.DomainUnload += (s, e) =>
            {
                LogShutdownInfo();
                SetConsoleLogLevels(LogLevel.Fatal, LogLevel.Fatal);
                InsertCachedLogging();
            };

            // Create NLog configuration
            var config = new LoggingConfiguration();

            // Create console target with colored output
            var consoleTarget = new ColoredConsoleTarget("console")
            {
                Layout = "${longdate}|${level:uppercase=true}|${event-properties:item=CallerInfo}|${message} ${exception:format=tostring}"
            };

            // Configure colors for different log levels
            consoleTarget.RowHighlightingRules.Add(new ConsoleRowHighlightingRule(
                condition: ConditionParser.ParseExpression("level == LogLevel.Error"),
                foregroundColor: ConsoleOutputColor.Red,
                backgroundColor: ConsoleOutputColor.NoChange));

            consoleTarget.RowHighlightingRules.Add(new ConsoleRowHighlightingRule(
                condition: ConditionParser.ParseExpression("level == LogLevel.Warn"),
                foregroundColor: ConsoleOutputColor.Yellow,
                backgroundColor: ConsoleOutputColor.NoChange));

            consoleTarget.RowHighlightingRules.Add(new ConsoleRowHighlightingRule(
                condition: ConditionParser.ParseExpression("level == LogLevel.Fatal"),
                foregroundColor: ConsoleOutputColor.Magenta,
                backgroundColor: ConsoleOutputColor.NoChange));

            // Add console target to configuration
            config.AddTarget(consoleTarget);

            // Clear any existing rules and add new rule for Info to Fatal
            config.LoggingRules.Clear();
            var rule = new LoggingRule("*", ToNLogLevel(LogLevel.Info), ToNLogLevel(LogLevel.Fatal), consoleTarget);
            rule.DisableLoggingForLevels(NLog.LogLevel.Trace, NLog.LogLevel.Debug);
            config.LoggingRules.Add(rule);

            // Apply initial configuration
            LogManager.Configuration = config;
            LogManager.ReconfigExistingLoggers();
            Logger = LogManager.GetLogger("*");

            string callingNamespaceClass = GlobalFunctions.GetNamespaceClassName();
            // Make callingNamespaceClass safe for folder creation
            callingNamespaceClass = callingNamespaceClass.Replace("<", "").Replace(">", "").Replace(":", "").Replace(" ", "_").Replace("$", "");
            _logFilePath = GetOrCreateLogFile(callingNamespaceClass);


            // Note: File target will be created on first use with the calling namespace
        }

        /// <summary>
        /// Logs shutdown information including log file locations and database logging status.
        /// Called automatically during application shutdown.
        /// </summary>
        private static void LogShutdownInfo()
        {
            try
            {
                var shutdownMessages = new List<string>
                {
                    "=== DedgeNLog Shutdown Summary ==="
                };

                // Log file information
                if (!string.IsNullOrEmpty(_logFilePath))
                {
                    shutdownMessages.Add($"Log File: {_logFilePath}");
                    
                    if (_otherLogFiles.Any())
                    {
                        shutdownMessages.Add($"Additional Log Files:");
                        foreach (var logFile in _otherLogFiles)
                        {
                            shutdownMessages.Add($"  - {logFile}");
                        }
                    }
                }

                // Database logging information
                if (_useDbLogging && _connectionKey != null)
                {
                    try
                    {
                        var accessPoint = DedgeConnection.GetConnectionStringInfo(_connectionKey);
                        shutdownMessages.Add($"Database Logging: Enabled");
                        shutdownMessages.Add($"  Database: {accessPoint.DatabaseName} (Catalog: {accessPoint.CatalogName})");
                        shutdownMessages.Add($"  Application: {accessPoint.FkApplication}");
                        shutdownMessages.Add($"  Environment: {accessPoint.Environment}");
                        shutdownMessages.Add($"  Server: {accessPoint.ServerName}:{accessPoint.Port}");
                    }
                    catch
                    {
                        shutdownMessages.Add($"Database Logging: Enabled (connection details unavailable)");
                    }
                }
                else
                {
                    shutdownMessages.Add($"Database Logging: Disabled");
                }

                shutdownMessages.Add("=== End DedgeNLog Shutdown Summary ===");

                // Log all shutdown messages
                foreach (var message in shutdownMessages)
                {
                    Info(message);
                }
            }
            catch
            {
                // Silently fail on shutdown - don't want to cause issues during application exit
            }
        }

        /// <summary>
        /// Enables database logging with specified application and environment settings.
        /// </summary>
        /// <param name="Application">The application identifier</param>
        /// <param name="Environment">The environment identifier</param>
        /// <returns>True if database logging was successfully enabled</returns>
        public static bool EnableDatabaseLogging(string Application, string Environment)
        {
            try
            {
                DedgeConnection.FkApplication applicationEnum;
                DedgeConnection.FkEnvironment environmentEnum;

                if (!Enum.TryParse(Application, out applicationEnum))
                {
                    throw new ArgumentException($"Invalid application value: {Application}. Valid values are: {string.Join(", ", Enum.GetNames(typeof(DedgeConnection.FkApplication)))}");
                }

                if (!Enum.TryParse(Environment, out environmentEnum))
                {
                    throw new ArgumentException($"Invalid environment value: {Environment}. Valid values are: {string.Join(", ", Enum.GetNames(typeof(DedgeConnection.FkEnvironment)))}");
                }

                return EnableDatabaseLogging(new DedgeConnection.ConnectionKey(applicationEnum, environmentEnum));
            }
            catch (Exception ex)
            {
                Error(ex, "Failed to enable database logging");
                _useDbLogging = false;
                _connectionKey = null;
                return _useDbLogging;
            }
        }
        /// <summary>
        /// Enables database logging with an optional connection key.
        /// </summary>
        /// <param name="connectionKey">Optional connection key. If null, uses default FKM PRD settings</param>
        /// <returns>True if database logging was successfully enabled</returns>
        public static bool EnableDatabaseLogging(DedgeConnection.ConnectionKey? connectionKey = null)
        {
            try
            {
                if (_useDbLogging && null == connectionKey)
                {
                    return _useDbLogging;
                }

                if (_useDbLogging && _connectionKey != connectionKey)
                {
                    DisableDatabaseLogging();
                }

                var accessPoint = DedgeConnection.GetConnectionStringInfo(connectionKey!);
                var connectionString = DedgeConnection.GenerateConnectionString(accessPoint);
                _connectionKey = connectionKey;
                _useDbLogging = true;
                return _useDbLogging;
            }
            catch (Exception ex)
            {
                Error(ex, "Failed to enable database logging");
                _useDbLogging = false;
                _connectionKey = null;
                return _useDbLogging;
            }
        }

        /// <summary>
        /// Enables database logging using a provided database handler.
        /// </summary>
        /// <param name="dbHandler">The database handler to use for logging</param>
        public static void EnableDatabaseLogging(IDbHandler dbHandler)
        {
            _useDbLogging = true;
            _connectionKey = null;
        }

        /// <summary>
        /// Disables database logging.
        /// </summary>
        public static void DisableDatabaseLogging()
        {
            _useDbLogging = false;
            _connectionKey = null;
        }

        /// <summary>
        /// Performs explicit shutdown logging and flushes all pending logs.
        /// This method is called automatically during application shutdown, but can also be called explicitly.
        /// Logs information about log file locations and database logging configuration.
        /// </summary>
        public static void Shutdown()
        {
            LogShutdownInfo();
            InsertCachedLogging();
            LogManager.Flush();
            LogManager.Shutdown();
        }

        private static void LogToDatabase(DateTime dateTime, string callerInfo, LogLevel severity, string message, Exception? exception = null)
        {
            if (!_useDbLogging)
                return;

            if (severity < _minDbLevel || severity > _maxDbLevel)
                return;

            LogEntry logEntry = new LogEntry(dateTime, callerInfo, severity.ToString().ToUpper().Trim(), message, exception);

            string callingNamespace = GlobalFunctions.GetNamespaceName(false);
            if (GlobalFunctions.excemptedNamespaces.Contains(GlobalFunctions.GetNamespaceName(false)))
            {
                // add to the list of log entries it not present
                if (_logEntries.Contains(logEntry))
                {
                    return;
                }
                else
                {
                    _logEntries.Add(logEntry);
                    return;
                }
            }

            _logEntries.Add(logEntry);

            InsertCachedLogging();

        }

        private static void InsertCachedLogging()
        {
            List<LogEntry> logEntries = _logEntries;
            _logEntries = new List<LogEntry>();
            foreach (var logEntryElement in logEntries)
            {
                RealDbLogging(logEntryElement.DateTime, logEntryElement.CallerInfo, logEntryElement.Severity, logEntryElement.Message, logEntryElement.Exception);
            }
            logEntries.Clear();
        }

        // Recursion guard to prevent infinite loops when database logging fails
        [ThreadStatic]
        private static bool _isInDbLogging;

        private static void RealDbLogging(DateTime dateTime, string callerInfo, string severity, string message, Exception? exception)
        {
            // Prevent recursive database logging - if we're already in a db logging call, skip
            if (_isInDbLogging)
            {
                // Suppress console output for recursive logging to avoid clutter
                // Console.WriteLine($"[DedgeNLog] Skipping recursive db logging: {severity} - {message}");
                return;
            }

            _isInDbLogging = true;
            IDbHandler? _db = null;

            try
            {
                _db = DedgeDbHandler.Create(_connectionKey!, false);
                //// Create a new database handler for logging to avoid recursive issues
                //if (_connectionKey != null && (_db == null || exception != null))
                //{
                //    _db = FkDatabaseHandler.Create(_connectionKey);
                //}
                // check if combination of hex values E2,96,88 is present in the message

                // Look for combination of hex values E2,96,88 and replace with "X"
                //message = message.Replace("\xE2\x96\x88", "X");
                //// Look for combination of hex values E2,96,91 and replace with "X"
                //message = message.Replace("\xE2\x96\x91", "X");

                if (message.Contains("\x2588"))
                {
                    message = message.Replace("\x5B\x2588", ".");
                    message = message.Replace("\x2591\x5D", "");
                    message = message.Replace("\x2588", ".");
                    message = message.Replace("\x2591", "");
                }

                string sql = @"INSERT INTO DBM.FK_LOG 
                    (TIDSPUNKT, SEVERITY, DATO, DB, MASKINNAVN, BRUKERID, CONTEXT, MELDING, AVDNR, ORDRENR) 
                    VALUES 
                    (@tidspunkt, @severity, CURRENT DATE, @db, @machine, @user, @context, @message, 9999999, 9999999)";

                string machineName = Environment.MachineName;
                string clientName = Environment.GetEnvironmentVariable("CLIENTNAME") ?? string.Empty;
                string combinedMachineName = machineName.Trim().ToUpper();
                if (!string.IsNullOrEmpty(clientName))
                {
                    combinedMachineName += $"/({clientName.Trim().ToUpper()})";
                }
                combinedMachineName = combinedMachineName.Length > 20 ? combinedMachineName.Substring(0, 20) : combinedMachineName;
                var parameters = new Dictionary<string, object>
                {
                    { "@tidspunkt", dateTime },
                    { "@severity", severity.Trim() },
                    { "@db", _db.GetDatabaseName().Trim() },
                    { "@machine",  combinedMachineName},
                    { "@user", Environment.UserName.Trim() },
                    { "@context", callerInfo },
                    { "@message", FormatLogMessage(message, exception) }
                };

                // Use atomic transaction for the insert
                _db.ExecuteAtomicNonQuery(sql, parameters, true);
            }
            catch (Exception ex)
            {
                // Log to console only to avoid recursive logging
                Console.WriteLine($"[DedgeNLog] Failed to log to database: {ex.Message}");
            }
            finally
            {
                _isInDbLogging = false;
                _db?.Dispose();
            }
        }

        // Add helper method to format log messages
        private static string FormatLogMessage(string message, Exception? exception)
        {
            if (exception == null)
                return message.Trim();

            var sb = new System.Text.StringBuilder();
            sb.AppendLine(message.Trim());
            sb.AppendLine("Exception Details:");
            sb.AppendLine($"Message: {exception.Message}");
            sb.AppendLine($"Type: {exception.GetType().FullName}");
            sb.AppendLine($"Stack Trace: {exception.StackTrace}");

            if (exception.InnerException != null)
            {
                sb.AppendLine("Inner Exception:");
                sb.AppendLine($"Message: {exception.InnerException.Message}");
                sb.AppendLine($"Type: {exception.InnerException.GetType().FullName}");
                sb.AppendLine($"Stack Trace: {exception.InnerException.StackTrace}");
            }

            return sb.ToString();
        }

        private static void Log(LogLevel level, string message, Exception? exception = null)
        {
            var logEvent = new LogEventInfo(ToNLogLevel(level), "", message);
            var frame = GlobalFunctions.GetStackFrame();
            if (frame == null)
            {
                frame = new System.Diagnostics.StackFrame(1, true);
            }
            var method = frame.GetMethod();
            var callerInfo = $"{method?.DeclaringType?.FullName ?? "Unknown"}.{method?.Name ?? "Unknown"}";
            logEvent.Properties["CallerInfo"] = callerInfo;

            if (exception != null)
            {
                logEvent.Exception = exception;
            }

            Logger.Log(logEvent);
            LogToDatabase(logEvent.TimeStamp, callerInfo, level, message, exception);
        }

        public static void Info(string message)
        {
            Log(LogLevel.Info, message);
        }

        public static void Debug(string message)
        {
            Log(LogLevel.Debug, message);
        }

        public static void Error(string message)
        {
            Log(LogLevel.Error, message);
        }

        public static void Error(Exception ex, string? message = null)
        {
            Log(LogLevel.Error, message ?? ex.Message, ex);
        }

        public static void Trace(string message)
        {
            Log(LogLevel.Trace, message);
        }

        public static void Warn(string message)
        {
            Log(LogLevel.Warn, message);
        }

        public static void Warn(Exception ex, string message)
        {
            Log(LogLevel.Warn, message, ex);
        }

        public static void Fatal(string message)
        {
            Log(LogLevel.Fatal, message);
        }

        public static void Fatal(Exception ex, string? message = null)
        {
            Log(LogLevel.Fatal, message ?? ex.Message, ex);
        }


        private static string GetOrCreateLogFile(string callingNamespaceClass)
        {
            var fileTarget = LogManager.Configuration?.AllTargets
                .FirstOrDefault(t => t is FileTarget) as FileTarget;

            if (fileTarget == null)
            {
                // Create base log directory using the calling namespace
                var folders = new FkFolders(callingNamespaceClass);
                var baseLogPath = folders.GetLogFolder();

                // Create new file target
                fileTarget = new FileTarget("file")
                {
                    FileName = Path.Combine(baseLogPath, "${shortdate}.log"),
                    Layout = "${longdate}|${level:uppercase=true}|${event-properties:item=CallerInfo}|${message} ${exception:format=tostring}",
                    ArchiveFileName = Path.Combine(baseLogPath, "archive", "{#}.log"),
                    ArchiveSuffixFormat = "{#}",
                    ArchiveEvery = FileArchivePeriod.Day,
                    MaxArchiveFiles = 30
                };

                // Add target to configuration
                LogManager.Configuration ??= new LoggingConfiguration();
                LogManager.Configuration.AddTarget(fileTarget);

                // Clear any existing rules for this target and add new rule for Info to Fatal
                foreach (var existingRule in LogManager.Configuration.LoggingRules.ToList())
                {
                    if (existingRule.Targets.Contains(fileTarget))
                    {
                        LogManager.Configuration.LoggingRules.Remove(existingRule);
                    }
                }

                var rule = new LoggingRule("*", ToNLogLevel(LogLevel.Info), ToNLogLevel(LogLevel.Fatal), fileTarget);
                //rule.DisableLoggingForLevels(NLog.LogLevel.Trace, NLog.LogLevel.Debug);
                LogManager.Configuration.LoggingRules.Add(rule);
                LogManager.ReconfigExistingLoggers();

                // Log the new file location
                var logFile = fileTarget.FileName.Render(new LogEventInfo());
                Console.WriteLine($"{DateTime.Now:yyyy-MM-dd HH:mm:ss.ffff}|INFO|{GlobalFunctions.GetNamespaceClassMethodName()}|Created Logfile:{logFile}");
                Info($"Added file logging to: {logFile} with loglevel from {rule.Levels.Min()} to {rule.Levels.Max()}");
            }

            return fileTarget.FileName.Render(new LogEventInfo());
        }



        /// <summary>
        /// Starts tracking a new operation with optional progress monitoring.
        /// </summary>
        /// <param name="operationName">Name of the operation to track</param>
        /// <param name="goal">Optional total number of items to process</param>
        public static void StartOperation(string operationName, int goal = 0)
        {
            string prefix = GlobalFunctions.GetNamespaceClassMethodName();

            var operation = new OperationInfo
            {
                Name = operationName,
                Goal = goal,
                Count = 0,
                StartTime = DateTime.Now,
                Prefix = prefix ?? new string('>', _operationStack.Count),
                LogFilePath = _logFilePath
            };

            _operationStack.Push(operation);

            Info($"Operation Started: {operationName}");
            Info($"Log File: {operation.LogFilePath}");
            if (goal > 0)
            {
                Info($"Total items to process: {goal}");
            }
        }
        /// <summary>
        /// Add other log file path to the list of log files
        /// </summary>
        /// <param name="otherLogFilePath">The path to the other log file</param>
        public static void AddOtherLogFilePath(string otherLogFilePath, bool createUncPath = true)
        {
            if (createUncPath)
            {
                otherLogFilePath = GlobalFunctions.GetUncPath(otherLogFilePath);
            }
            Info($"Related Log File Added: {otherLogFilePath}");

            _otherLogFiles.Add(otherLogFilePath);
        }


        /// <summary>
        /// Gets the current console width, capped at 120 characters
        /// </summary>
        private static int GetConsoleWidth()
        {
            try
            {
                return Math.Min(Console.WindowWidth, _consoleWidth);
            }
            catch
            {
                return _consoleWidth;
            }
        }

        /// <summary>
        /// Records progress for the current operation.
        /// </summary>
        public static void OperationProgression()
        {
            try
            {
                if (_operationStack.TryPeek(out var operation))
                {
                    operation.Count++;
                    if (operation.Goal > 0 && operation.Count <= operation.Goal)
                    {
                        double percentage = (double)operation.Count / operation.Goal * 100;
                        double previousPercentage = (double)(operation.Count - 1) / operation.Goal * 100;

                        // Log only when crossing a whole percentage threshold
                        if (Math.Floor(percentage) > Math.Floor(previousPercentage))
                        {
                            // Use the centralized console width method
                            int consoleWidth = GetConsoleWidth();
                            // Reserve space for the format: "Operation Name: [] 100% (100/100)"
                            int reservedSpace = operation.Name.Length + 2 + 4 + 6 + operation.Goal.ToString().Length * 2 + 3;
                            int totalBarLength = Math.Max(10, consoleWidth - reservedSpace);

                            int filledLength = (int)(percentage / 100 * totalBarLength);
                            string progressBar = new string('█', filledLength) + new string('░', totalBarLength - filledLength);

                            Info($"{operation.Name}: [{progressBar}] {percentage:F0}% ({operation.Count}/{operation.Goal})");
                        }
                    }
                }

            }
            catch (Exception)
            {
                // Ignore any exceptions
            }
        }

        /// <summary>
        /// Ends the current operation and optionally displays a summary.
        /// </summary>
        /// <param name="showSummary">Whether to show the operation summary</param>
        public static void EndOperation(bool showSummary = true)
        {
            if (_operationStack.TryPop(out var operation))
            {
                if (showSummary)
                {
                    TimeSpan duration = DateTime.Now - operation.StartTime;
                    Info($"Operation Completed: {operation.Name}");
                    Info($"Duration: {duration:hh\\:mm\\:ss}");
                    if (operation.Goal > 0)
                    {
                        Info($"Final Count: {operation.Count}/{operation.Goal}");
                    }
                }
            }
            InsertCachedLogging();
        }
        /// <summary>
        /// Aborts the current operation and optionally displays a summary.
        /// </summary>
        /// <param name="showSummary">Whether to show the operation summary</param>
        public static void AbortOperation(bool showSummary = true)
        {
            if (_operationStack.TryPop(out var operation))
            {
                if (showSummary)
                {
                    TimeSpan duration = DateTime.Now - operation.StartTime;
                    // set text color to red
                    Console.ForegroundColor = ConsoleColor.Red;
                    Info($"Operation Completed: {operation.Name}");
                    Info($"Duration: {duration:hh\\:mm\\:ss}");
                    if (operation.Goal > 0)
                    {
                        Info($"Final Count: {operation.Count}/{operation.Goal}");
                    }
                    // reset text color
                    Console.ResetColor();
                }
            }
            InsertCachedLogging();
        }

        /// <summary>
        /// Shuts down the logging framework and inserts any remaining log entries.
        /// </summary>
        private static (LogLevel min, LogLevel max) GetCurrentConsoleLevels()
        {
            var config = LogManager.Configuration;
            var consoleTarget = config?.AllTargets.FirstOrDefault(t => t is ColoredConsoleTarget) as ColoredConsoleTarget;

            if (consoleTarget != null)
            {
                var rule = config?.LoggingRules?.FirstOrDefault(r => r.Targets?.Contains(consoleTarget) == true);
                if (rule != null)
                {
                    var minNLogLevel = rule.Levels.Min();
                    var maxNLogLevel = rule.Levels.Max();

                    // Convert NLog levels back to our LogLevel enum
                    LogLevel minLevel = LogLevel.Info;
                    LogLevel maxLevel = LogLevel.Fatal;

                    if (minNLogLevel == NLog.LogLevel.Trace) minLevel = LogLevel.Trace;
                    else if (minNLogLevel == NLog.LogLevel.Debug) minLevel = LogLevel.Debug;
                    else if (minNLogLevel == NLog.LogLevel.Info) minLevel = LogLevel.Info;
                    else if (minNLogLevel == NLog.LogLevel.Warn) minLevel = LogLevel.Warn;
                    else if (minNLogLevel == NLog.LogLevel.Error) minLevel = LogLevel.Error;
                    else if (minNLogLevel == NLog.LogLevel.Fatal) minLevel = LogLevel.Fatal;

                    if (maxNLogLevel == NLog.LogLevel.Trace) maxLevel = LogLevel.Trace;
                    else if (maxNLogLevel == NLog.LogLevel.Debug) maxLevel = LogLevel.Debug;
                    else if (maxNLogLevel == NLog.LogLevel.Info) maxLevel = LogLevel.Info;
                    else if (maxNLogLevel == NLog.LogLevel.Warn) maxLevel = LogLevel.Warn;
                    else if (maxNLogLevel == NLog.LogLevel.Error) maxLevel = LogLevel.Error;
                    else if (maxNLogLevel == NLog.LogLevel.Fatal) maxLevel = LogLevel.Fatal;

                    return (minLevel, maxLevel);
                }
            }
            return (LogLevel.Info, LogLevel.Fatal); // Default to Info-Fatal if no rule found
        }


        /// <summary>
        /// Gets information about the current operation.
        /// </summary>
        /// <returns>A tuple containing the operation name, current count, and goal</returns>
        public static (string Name, int Count, int Goal) GetCurrentOperation()
        {
            if (_operationStack.TryPeek(out var operation))
            {
                return (operation.Name, operation.Count, operation.Goal);
            }
            return (string.Empty, 0, 0);
        }

        /// <summary>
        /// Sets the minimum and maximum log levels for the console target.
        /// </summary>
        /// <param name="minLevel">The minimum log level to display in console</param>
        /// <param name="maxLevel">The maximum log level to display in console</param>
        public static void SetConsoleLogLevels(LogLevel minLevel, LogLevel maxLevel)
        {
            var config = LogManager.Configuration ?? new LoggingConfiguration();
            var consoleTarget = config.AllTargets.FirstOrDefault(t => t is ColoredConsoleTarget) as ColoredConsoleTarget;

            if (consoleTarget != null)
            {
                // Remove existing console rules
                foreach (var rule in config.LoggingRules.ToList())
                {
                    if (rule.Targets.Contains(consoleTarget))
                    {
                        config.LoggingRules.Remove(rule);
                    }
                }

                // Add new rule with specified levels
                config.AddRule(ToNLogLevel(minLevel), ToNLogLevel(maxLevel), consoleTarget);
                LogManager.Configuration = config;
                LogManager.ReconfigExistingLoggers();
                if (minLevel != LogLevel.Fatal && maxLevel != LogLevel.Fatal)
                {
                    Info($"Console logging levels set to: Min={minLevel}, Max={maxLevel}");
                }
            }
        }

        /// <summary>
        /// Sets the minimum and maximum log levels for the file target.
        /// </summary>
        /// <param name="minLevel">The minimum log level to write to file</param>
        /// <param name="maxLevel">The maximum log level to write to file</param>
        public static void SetFileLogLevels(LogLevel minLevel, LogLevel maxLevel)
        {
            var config = LogManager.Configuration ?? new LoggingConfiguration();
            var fileTarget = config.AllTargets.FirstOrDefault(t => t is FileTarget) as FileTarget;

            if (fileTarget != null)
            {
                // Remove existing file rules
                foreach (var rule in config.LoggingRules.ToList())
                {
                    if (rule.Targets.Contains(fileTarget))
                    {
                        config.LoggingRules.Remove(rule);
                    }
                }

                // Add new rule with specified levels
                config.AddRule(ToNLogLevel(minLevel), ToNLogLevel(maxLevel), fileTarget);
                LogManager.Configuration = config;
                LogManager.ReconfigExistingLoggers();

                Info($"File logging levels set to: Min={minLevel}, Max={maxLevel}");
            }
        }
        public static void SetDbLogLevels(LogLevel minLevel, LogLevel maxLevel)
        {
            _minDbLevel = minLevel;
            _maxDbLevel = maxLevel;
        }


    }
}
