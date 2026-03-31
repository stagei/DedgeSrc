using System;
using System.Diagnostics;
using System.IO;
using Microsoft.Extensions.Configuration;
using NLog;
using NLog.Config;
using NLog.Targets;

namespace SystemAnalyzer2.Batch.AutoDoc;

/// <summary>
/// Logger class using NLog - refactored from custom logging implementation
/// Provides backward-compatible API while leveraging NLog for robust logging
/// Author: Geir Helge Starholm, www.dEdge.no
/// </summary>
public static class AutoDocLogger
{
    private static NLog.Logger _nlog = null!;
    private static LogLevel _currentLogLevel = LogLevel.INFO;
    private static bool _isInitialized = false;
    private static readonly object _initLock = new object();
    private static string _logPath = string.Empty;
    private static string _globalLogPath = string.Empty;

    /// <summary>
    /// Static constructor to initialize NLog
    /// </summary>
    static AutoDocLogger()
    {
        Initialize();
    }

    /// <summary>
    /// Initialize NLog with configuration from appsettings.json
    /// </summary>
    public static void Initialize(string? configPath = null)
    {
        lock (_initLock)
        {
            if (_isInitialized) return;

            try
            {
                // Load configuration from appsettings.json
                var configBuilder = new ConfigurationBuilder();
                
                // Try multiple paths for appsettings.json
                string[] possiblePaths = new[]
                {
                    configPath ?? "",
                    Path.Combine(AppDomain.CurrentDomain.BaseDirectory, "appsettings.json"),
                    Path.Combine(Directory.GetCurrentDirectory(), "appsettings.json"),
                    Path.Combine(Path.GetDirectoryName(typeof(AutoDocLogger).Assembly.Location) ?? "", "appsettings.json")
                };

                string? foundPath = null;
                foreach (var path in possiblePaths)
                {
                    if (!string.IsNullOrEmpty(path) && File.Exists(path))
                    {
                        foundPath = path;
                        break;
                    }
                }

                string optPath = Environment.GetEnvironmentVariable("OptPath") ?? "C:\\opt";
                string defaultLogPath = Path.Combine(optPath, "data", "AutoDocJson");
                string defaultGlobalLogPath = Path.Combine(optPath, "data", "AllPwshLog");

                IConfiguration? config = null;
                if (foundPath != null)
                {
                    config = configBuilder
                        .AddJsonFile(foundPath, optional: true, reloadOnChange: true)
                        .Build();

                    _logPath = config["Logging:LogPath"] ?? defaultLogPath;
                    _globalLogPath = config["Logging:GlobalLogPath"] ?? defaultGlobalLogPath;
                    
                    var configLevel = config["Logging:LogLevel"]?.ToUpper() ?? "INFO";
                    _currentLogLevel = Enum.TryParse<LogLevel>(configLevel, out var level) ? level : LogLevel.INFO;

                    Console.WriteLine($"[Logger] Loaded config from: {foundPath}");
                    Console.WriteLine($"[Logger] LogPath: {_logPath}");
                    Console.WriteLine($"[Logger] GlobalLogPath: {_globalLogPath}");
                    Console.WriteLine($"[Logger] LogLevel: {_currentLogLevel}");
                }
                else
                {
                    _logPath = defaultLogPath;
                    _globalLogPath = defaultGlobalLogPath;
                    Console.WriteLine("[Logger] No appsettings.json found, using default paths");
                }

                // Ensure directories exist
                EnsureDirectoryExists(_logPath);
                EnsureDirectoryExists(_globalLogPath);

                // Configure NLog programmatically
                ConfigureNLog();

                _nlog = NLog.LogManager.GetCurrentClassLogger();
                _isInitialized = true;

                // Log initialization trace
                _nlog.Trace($"Logger initialized. LogPath={_logPath}, GlobalLogPath={_globalLogPath}, LogLevel={_currentLogLevel}");
            }
            catch (Exception ex)
            {
                Console.WriteLine($"[Logger] Failed to initialize NLog: {ex.Message}");
                // Create a fallback logger
                _nlog = NLog.LogManager.CreateNullLogger();
                _isInitialized = true;
            }
        }
    }

    /// <summary>
    /// Configure NLog programmatically with file and console targets
    /// </summary>
    private static void ConfigureNLog()
    {
        var config = new LoggingConfiguration();

        // Layout matching the original format: timestamp|machine|level|origin|pid|location|function|line|user|message
        var fileLayout = "${longdate}|${machinename}|${level:uppercase=true}|CSharp|${processid}|${logger}|${callsite:className=false:methodName=true}|${callsite-linenumber}|${windows-identity}|${message}${onexception:inner=| Exception at ${callsite-linenumber}\\: ${exception:format=type} - ${exception:format=message} | InnerException\\: ${exception:format=innerexception} | StackTrace\\: ${exception:format=stacktrace}}";

        // Console layout matching the original PowerShell format
        var consoleLayout = "[${time}] [${processid}] [${logger}.${callsite:className=false:methodName=true}.${callsite-linenumber}] [${level:uppercase=true}] ${message}";

        // Application-specific log file (in LogPath folder)
        // Use yyyyMMdd format to match PowerShell log file naming convention
        var appLogFile = new FileTarget("appLogFile")
        {
            FileName = Path.Combine(_logPath, $"FkLog_${{date:format=yyyyMMdd}}.log"),
            Layout = fileLayout,
            ArchiveEvery = FileArchivePeriod.Day,
            ArchiveNumbering = ArchiveNumberingMode.Date,
            MaxArchiveFiles = 30,
            ConcurrentWrites = true,
            KeepFileOpen = false
        };
        config.AddTarget(appLogFile);

        // Global log file (in GlobalLogPath folder) - matches PowerShell AllPwshLog
        // Use yyyyMMdd format to match PowerShell log file naming convention
        var globalLogFile = new FileTarget("globalLogFile")
        {
            FileName = Path.Combine(_globalLogPath, $"FkLog_${{date:format=yyyyMMdd}}.log"),
            Layout = fileLayout,
            ArchiveEvery = FileArchivePeriod.Day,
            ArchiveNumbering = ArchiveNumberingMode.Date,
            MaxArchiveFiles = 30,
            ConcurrentWrites = true,
            KeepFileOpen = false
        };
        config.AddTarget(globalLogFile);

        // Colored console output
        var consoleTarget = new ColoredConsoleTarget("console")
        {
            Layout = consoleLayout,
            UseDefaultRowHighlightingRules = false
        };

        // Add color rules matching original implementation
        consoleTarget.RowHighlightingRules.Add(new ConsoleRowHighlightingRule
        {
            Condition = "level == LogLevel.Trace",
            ForegroundColor = ConsoleOutputColor.DarkGray
        });
        consoleTarget.RowHighlightingRules.Add(new ConsoleRowHighlightingRule
        {
            Condition = "level == LogLevel.Debug",
            ForegroundColor = ConsoleOutputColor.Gray
        });
        consoleTarget.RowHighlightingRules.Add(new ConsoleRowHighlightingRule
        {
            Condition = "level == LogLevel.Info",
            ForegroundColor = ConsoleOutputColor.White
        });
        consoleTarget.RowHighlightingRules.Add(new ConsoleRowHighlightingRule
        {
            Condition = "level == LogLevel.Warn",
            ForegroundColor = ConsoleOutputColor.Yellow
        });
        consoleTarget.RowHighlightingRules.Add(new ConsoleRowHighlightingRule
        {
            Condition = "level == LogLevel.Error",
            ForegroundColor = ConsoleOutputColor.Red
        });
        consoleTarget.RowHighlightingRules.Add(new ConsoleRowHighlightingRule
        {
            Condition = "level == LogLevel.Fatal",
            ForegroundColor = ConsoleOutputColor.Red,
            BackgroundColor = ConsoleOutputColor.White
        });
        config.AddTarget(consoleTarget);

        // Map our LogLevel to NLog levels
        var nlogLevel = _currentLogLevel switch
        {
            LogLevel.TRACE => NLog.LogLevel.Trace,
            LogLevel.DEBUG => NLog.LogLevel.Debug,
            LogLevel.INFO => NLog.LogLevel.Info,
            LogLevel.WARN => NLog.LogLevel.Warn,
            LogLevel.ERROR => NLog.LogLevel.Error,
            LogLevel.FATAL => NLog.LogLevel.Fatal,
            _ => NLog.LogLevel.Info
        };

        // Add rules - log to all targets
        config.AddRule(nlogLevel, NLog.LogLevel.Fatal, appLogFile);
        config.AddRule(nlogLevel, NLog.LogLevel.Fatal, globalLogFile);
        config.AddRule(nlogLevel, NLog.LogLevel.Fatal, consoleTarget);

        NLog.LogManager.Configuration = config;
    }

    /// <summary>
    /// Ensure a directory exists
    /// </summary>
    private static void EnsureDirectoryExists(string path)
    {
        try
        {
            if (!Directory.Exists(path))
            {
                Directory.CreateDirectory(path);
            }
        }
        catch (Exception ex)
        {
            Console.WriteLine($"[Logger] Failed to create directory {path}: {ex.Message}");
        }
    }

    /// <summary>
    /// Get the configured log path
    /// </summary>
    public static string GetLogPath() => _logPath;

    /// <summary>
    /// Get the configured global log path
    /// </summary>
    public static string GetGlobalLogPath() => _globalLogPath;

    /// <summary>
    /// Get current log level
    /// </summary>
    public static LogLevel GetLogLevel() => _currentLogLevel;

    /// <summary>
    /// Set log level dynamically
    /// </summary>
    public static void SetLogLevel(LogLevel logLevel)
    {
        var oldLevel = _currentLogLevel;
        _currentLogLevel = logLevel;
        
        // Reconfigure NLog with new level
        ConfigureNLog();
        
        _nlog.Info($"LogLevel changed from {oldLevel} to {logLevel}");
    }

    /// <summary>
    /// Reset log level to INFO
    /// </summary>
    public static void ResetLogLevel()
    {
        SetLogLevel(LogLevel.INFO);
    }

    /// <summary>
    /// Write log message - main logging function (backward compatible API)
    /// </summary>
    public static void LogMessage(
        string message = null!,
        LogLevel level = LogLevel.INFO,
        Exception? exception = null,
        ConsoleColor? foregroundColor = null,
        bool noNewline = false,
        string batOriginScriptFileName = "",
        bool quietMode = false,
        LogOriginType logOriginType = LogOriginType.Powershell)
    {
        if (string.IsNullOrEmpty(message))
        {
            Console.WriteLine();
            return;
        }

        if (quietMode)
        {
            return;
        }

        try
        {
            // Get caller information for enhanced logging
            var stackFrame = GetCallingStackFrame();
            string callerInfo = "";
            if (stackFrame != null)
            {
                var method = stackFrame.GetMethod();
                string methodName = method?.Name ?? "Unknown";
                string fileName = Path.GetFileNameWithoutExtension(stackFrame.GetFileName() ?? "Unknown");
                int lineNumber = stackFrame.GetFileLineNumber();
                callerInfo = $"[{fileName}.{methodName}.{lineNumber}]";
            }

            // Log using NLog with appropriate level
            switch (level)
            {
                case LogLevel.TRACE:
                    if (exception != null)
                        _nlog.Trace(exception, message);
                    else
                        _nlog.Trace(message);
                    break;

                case LogLevel.DEBUG:
                    if (exception != null)
                        _nlog.Debug(exception, message);
                    else
                        _nlog.Debug(message);
                    break;

                case LogLevel.INFO:
                case LogLevel.JOB_STARTED:
                case LogLevel.JOB_COMPLETED:
                    if (exception != null)
                        _nlog.Info(exception, message);
                    else
                        _nlog.Info(message);
                    break;

                case LogLevel.WARN:
                    if (exception != null)
                        _nlog.Warn(exception, message);
                    else
                        _nlog.Warn(message);
                    break;

                case LogLevel.ERROR:
                case LogLevel.JOB_FAILED:
                    if (exception != null)
                        _nlog.Error(exception, message);
                    else
                        _nlog.Error(message);
                    break;

                case LogLevel.FATAL:
                    if (exception != null)
                        _nlog.Fatal(exception, message);
                    else
                        _nlog.Fatal(message);
                    break;

                default:
                    if (exception != null)
                        _nlog.Info(exception, message);
                    else
                        _nlog.Info(message);
                    break;
            }
        }
        catch (Exception ex)
        {
            Console.WriteLine($"[Logger] Error logging message: {ex.Message}");
        }
    }

    /// <summary>
    /// Get calling stack frame
    /// </summary>
    private static StackFrame? GetCallingStackFrame()
    {
        var stackTrace = new StackTrace(true);
        for (int i = 0; i < stackTrace.FrameCount; i++)
        {
            var frame = stackTrace.GetFrame(i);
            if (frame != null)
            {
                var method = frame.GetMethod();
                if (method != null && method.DeclaringType != typeof(AutoDocLogger))
                {
                    return frame;
                }
            }
        }
        return stackTrace.GetFrame(0);
    }

    #region Convenience Methods

    /// <summary>
    /// Log trace message
    /// </summary>
    public static void Trace(string message) => LogMessage(message, LogLevel.TRACE);

    /// <summary>
    /// Log debug message
    /// </summary>
    public static void Debug(string message) => LogMessage(message, LogLevel.DEBUG);

    /// <summary>
    /// Log info message
    /// </summary>
    public static void Info(string message) => LogMessage(message, LogLevel.INFO);

    /// <summary>
    /// Log warning message
    /// </summary>
    public static void Warn(string message) => LogMessage(message, LogLevel.WARN);

    /// <summary>
    /// Log warning message with exception
    /// </summary>
    public static void Warn(string message, Exception ex) => LogMessage(message, LogLevel.WARN, ex);

    /// <summary>
    /// Log error message
    /// </summary>
    public static void Error(string message) => LogMessage(message, LogLevel.ERROR);

    /// <summary>
    /// Log error message with exception
    /// </summary>
    public static void Error(string message, Exception ex) => LogMessage(message, LogLevel.ERROR, ex);

    /// <summary>
    /// Log fatal message
    /// </summary>
    public static void Fatal(string message) => LogMessage(message, LogLevel.FATAL);

    /// <summary>
    /// Log fatal message with exception
    /// </summary>
    public static void Fatal(string message, Exception ex) => LogMessage(message, LogLevel.FATAL, ex);

    #endregion

    /// <summary>
    /// Flush all pending log entries and shutdown NLog
    /// </summary>
    public static void Shutdown()
    {
        NLog.LogManager.Shutdown();
    }
}
