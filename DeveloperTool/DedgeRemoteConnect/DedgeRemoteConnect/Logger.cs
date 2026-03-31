using NLog;
using NLog.Config;
using NLog.Targets;

namespace DedgeRemoteConnect
{
    public static class Logger
    {
        private static readonly NLog.Logger _logger;

        static Logger()
        {
            // Configure NLog programmatically
            var config = new LoggingConfiguration();

            // Create targets
            var fileTarget = new FileTarget("file")
            {
                FileName = Path.Combine(
                    Environment.GetFolderPath(Environment.SpecialFolder.ApplicationData),
                    "DedgeRemoteConnect", 
                    "DedgeRemoteConnect.log"),
                Layout = "${longdate}|${level:uppercase=true}|${message}",
                ArchiveFileName = Path.Combine(
                    Environment.GetFolderPath(Environment.SpecialFolder.ApplicationData),
                    "DedgeRemoteConnect",
                    "archives", 
                    "DedgeRemoteConnect.{#}.log"),
                ArchiveNumbering = ArchiveNumberingMode.Date,
                ArchiveEvery = FileArchivePeriod.Day,
                MaxArchiveFiles = 7,
                CreateDirs = true
            };

            var consoleTarget = new ConsoleTarget("console")
            {
                Layout = "${longdate}|${level:uppercase=true}|${message}"
            };

            // Add targets to configuration
            config.AddTarget(fileTarget);
            config.AddTarget(consoleTarget);

            // Define rules
            config.AddRule(LogLevel.Debug, LogLevel.Fatal, fileTarget);
            config.AddRule(LogLevel.Info, LogLevel.Fatal, consoleTarget);

            // Apply config
            LogManager.Configuration = config;

            // Get logger
            _logger = LogManager.GetCurrentClassLogger();
            _logger.Info("=== Logging initialized ===");
        }

        public static void Debug(string message)
        {
            _logger.Debug(message);
        }

        public static void Info(string message)
        {
            _logger.Info(message);
        }

        public static void Warning(string message)
        {
            _logger.Warn(message);
        }

        public static void Error(string message)
        {
            _logger.Error(message);
        }

        public static void Error(Exception ex, string message = "")
        {
            _logger.Error(ex, message);
        }

        // For compatibility with existing code
        public static void Log(string message)
        {
            _logger.Info(message);
        }
    }
} 