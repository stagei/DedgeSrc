using NLog;

namespace DbExplorer.Services;

/// <summary>
/// Service for managing application logging using NLog.
/// Supports runtime log level changes and all standard NLog levels:
/// Trace, Debug, Info, Warn, Error, Fatal
/// </summary>
public static class LoggingService
{
    private static readonly Logger Logger = LogManager.GetCurrentClassLogger();
    private static string _currentLogLevel = "Info";

    /// <summary>
    /// Initialize NLog from configuration file
    /// </summary>
    public static void Initialize()
    {
        try
        {
            LogManager.Setup().LoadConfigurationFromFile("nlog.config");
            Logger.Info("Application logging initialized");
            Logger.Debug("NLog configuration loaded from nlog.config");
        }
        catch (Exception ex)
        {
            // If NLog fails, we need to handle it gracefully
            Console.WriteLine($"Failed to initialize logging: {ex.Message}");
            throw;
        }
    }

    /// <summary>
    /// Set the minimum log level for all logging rules at runtime.
    /// Valid levels: Trace, Debug, Info, Warn, Error, Fatal
    /// </summary>
    /// <param name="level">The minimum log level to set (e.g., "Debug", "Info", "Trace")</param>
    public static void SetLogLevel(string level)
    {
        try
        {
            if (string.IsNullOrWhiteSpace(level))
            {
                Logger.Warn("SetLogLevel called with empty level, defaulting to Info");
                level = "Info";
            }

            var logLevel = LogLevel.FromString(level);
            var config = LogManager.Configuration;

            if (config == null)
            {
                Logger.Error("NLog configuration is null, cannot change log level");
                return;
            }

            Logger.Debug("Changing log level from {OldLevel} to {NewLevel}", _currentLogLevel, level);

            // Update all logging rules to use the new minimum level
            foreach (var rule in config.LoggingRules)
            {
                // Skip rules that are specifically for Microsoft.* (we want to keep those filtered)
                if (rule.LoggerNamePattern == "Microsoft.*")
                    continue;

                // Set the logging levels from the specified level up to Fatal
                rule.SetLoggingLevels(logLevel, LogLevel.Fatal);
            }

            // Reconfigure existing loggers to pick up the changes
            LogManager.ReconfigExistingLoggers();

            _currentLogLevel = level;
            Logger.Info("Log level changed to: {Level}", level);
        }
        catch (Exception ex)
        {
            Logger.Error(ex, "Failed to set log level to: {Level}", level);
        }
    }

    /// <summary>
    /// Get the current minimum log level
    /// </summary>
    /// <returns>The current log level as a string (e.g., "Info", "Debug")</returns>
    public static string GetCurrentLogLevel()
    {
        return _currentLogLevel;
    }

    /// <summary>
    /// Get all available log levels for UI dropdown
    /// </summary>
    /// <returns>Array of log level names in order from most verbose to least</returns>
    public static string[] GetAvailableLogLevels()
    {
        return new[] { "Trace", "Debug", "Info", "Warn", "Error", "Fatal" };
    }

    /// <summary>
    /// Get description for a log level (for UI tooltips)
    /// </summary>
    public static string GetLogLevelDescription(string level)
    {
        return level?.ToUpperInvariant() switch
        {
            "TRACE" => "Most verbose - includes every detail for deep troubleshooting",
            "DEBUG" => "Detailed diagnostic information for developers",
            "INFO" => "General operational events (recommended default)",
            "WARN" => "Unexpected but recoverable situations",
            "ERROR" => "Error events that might still allow the app to continue",
            "FATAL" => "Only critical errors that prevent the app from continuing",
            _ => "Unknown log level"
        };
    }

    /// <summary>
    /// Log informational message
    /// </summary>
    public static void LogInfo(string message)
    {
        Logger.Info(message);
    }

    /// <summary>
    /// Log debug message with context
    /// </summary>
    public static void LogDebug(string message, params object[] args)
    {
        Logger.Debug(message, args);
    }

    /// <summary>
    /// Log warning message
    /// </summary>
    public static void LogWarning(string message)
    {
        Logger.Warn(message);
    }

    /// <summary>
    /// Log error message with optional exception
    /// </summary>
    public static void LogError(string message, Exception? ex = null)
    {
        if (ex != null)
        {
            Logger.Error(ex, message);
        }
        else
        {
            Logger.Error(message);
        }
    }

    /// <summary>
    /// Log fatal error
    /// </summary>
    public static void LogFatal(string message, Exception? ex = null)
    {
        if (ex != null)
        {
            Logger.Fatal(ex, message);
        }
        else
        {
            Logger.Fatal(message);
        }
    }

    /// <summary>
    /// Shutdown NLog and flush logs
    /// </summary>
    public static void Shutdown()
    {
        Logger.Info("Application logging shutting down");
        LogManager.Shutdown();
    }
}

