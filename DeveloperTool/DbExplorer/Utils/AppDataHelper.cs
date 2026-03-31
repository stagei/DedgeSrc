using System;
using System.IO;
using NLog;

namespace DbExplorer.Services
{
    /// <summary>
    /// Helper class for managing application data folder in user's AppData
    /// </summary>
    public static class AppDataHelper
    {
        private static readonly Logger Logger = LogManager.GetCurrentClassLogger();
        private const string AppFolderName = "DbExplorer";

        /// <summary>
        /// Gets the application data folder path in %LOCALAPPDATA%
        /// Creates the folder if it doesn't exist
        /// </summary>
        public static string GetAppDataFolder()
        {
            try
            {
                // Use LocalApplicationData for non-roaming user data
                var localAppData = Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData);
                var appDataFolder = Path.Combine(localAppData, AppFolderName);

                Logger.Debug("AppData folder path: {Path}", appDataFolder);

                // Create folder if it doesn't exist
                if (!Directory.Exists(appDataFolder))
                {
                    Directory.CreateDirectory(appDataFolder);
                    Logger.Info("Created application data folder: {Path}", appDataFolder);
                }

                return appDataFolder;
            }
            catch (Exception ex)
            {
                Logger.Error(ex, "Error getting/creating AppData folder");
                
                // Fallback to application directory if AppData is not accessible
                var fallbackPath = AppDomain.CurrentDomain.BaseDirectory;
                Logger.Warn("Falling back to application directory: {Path}", fallbackPath);
                return fallbackPath;
            }
        }

        /// <summary>
        /// Gets the full path for a data file in the application data folder
        /// </summary>
        public static string GetDataFilePath(string fileName)
        {
            var folder = GetAppDataFolder();
            var filePath = Path.Combine(folder, fileName);
            Logger.Debug("Data file path for {FileName}: {Path}", fileName, filePath);
            return filePath;
        }

        /// <summary>
        /// Ensures a subdirectory exists within the application data folder
        /// </summary>
        public static string EnsureSubDirectory(string subDirectoryName)
        {
            try
            {
                var appDataFolder = GetAppDataFolder();
                var subDirectory = Path.Combine(appDataFolder, subDirectoryName);

                if (!Directory.Exists(subDirectory))
                {
                    Directory.CreateDirectory(subDirectory);
                    Logger.Info("Created subdirectory: {Path}", subDirectory);
                }

                return subDirectory;
            }
            catch (Exception ex)
            {
                Logger.Error(ex, "Error creating subdirectory: {SubDirectory}", subDirectoryName);
                throw;
            }
        }
    }
}

