using System;
using System.Collections.Generic;
using System.IO;
using System.Linq;
using System.Text.RegularExpressions;
using NLog;
using DbExplorer.Models;

namespace DbExplorer.Services;

/// <summary>
/// Helper class for managing user data folder paths.
/// All user-specific files (connections, preferences, history, Missing FK projects) 
/// are stored in a configurable folder (default: Documents\DbExplorer).
/// </summary>
public static class UserDataFolderHelper
{
    private static readonly Logger Logger = LogManager.GetCurrentClassLogger();
    
    /// <summary>
    /// Cached user data folder path from preferences
    /// </summary>
    private static string? _cachedUserDataFolder;
    
    /// <summary>
    /// Gets the user data folder path from preferences, or default if not set.
    /// Creates the folder if it doesn't exist.
    /// </summary>
    public static string GetUserDataFolder()
    {
        try
        {
            // Use cached value if available
            if (!string.IsNullOrEmpty(_cachedUserDataFolder) && Directory.Exists(_cachedUserDataFolder))
            {
                return _cachedUserDataFolder;
            }
            
            // Get from preferences if PreferencesService is available
            var preferencesService = App.PreferencesService;
            if (preferencesService != null && !string.IsNullOrEmpty(preferencesService.Preferences.UserDataFolder))
            {
                _cachedUserDataFolder = preferencesService.Preferences.UserDataFolder;
            }
            else
            {
                // Use default
                _cachedUserDataFolder = UserPreferences.GetDefaultUserDataFolder();
            }
            
            // Ensure folder exists
            if (!Directory.Exists(_cachedUserDataFolder))
            {
                Directory.CreateDirectory(_cachedUserDataFolder);
                Logger.Info("Created user data folder: {Path}", _cachedUserDataFolder);
            }
            
            Logger.Debug("User data folder: {Path}", _cachedUserDataFolder);
            return _cachedUserDataFolder;
        }
        catch (Exception ex)
        {
            Logger.Error(ex, "Error getting user data folder, using default");
            var defaultFolder = UserPreferences.GetDefaultUserDataFolder();
            if (!Directory.Exists(defaultFolder))
            {
                Directory.CreateDirectory(defaultFolder);
            }
            return defaultFolder;
        }
    }
    
    /// <summary>
    /// Clears the cached folder path, forcing a reload from preferences on next access.
    /// Call this when user changes the folder in settings.
    /// </summary>
    public static void ClearCache()
    {
        _cachedUserDataFolder = null;
        Logger.Debug("User data folder cache cleared");
    }
    
    /// <summary>
    /// Sets the user data folder path directly (used during preferences load bootstrap).
    /// </summary>
    public static void SetUserDataFolder(string path)
    {
        _cachedUserDataFolder = path;
        Logger.Debug("User data folder set to: {Path}", path);
    }
    
    /// <summary>
    /// Gets the full path for a data file in the user data folder.
    /// </summary>
    /// <param name="fileName">The file name (e.g., "connections.json")</param>
    /// <returns>Full path to the file</returns>
    public static string GetFilePath(string fileName)
    {
        var folder = GetUserDataFolder();
        var filePath = Path.Combine(folder, fileName);
        Logger.Debug("Data file path for {FileName}: {Path}", fileName, filePath);
        return filePath;
    }
    
    /// <summary>
    /// Ensures a subfolder exists within the user data folder.
    /// </summary>
    /// <param name="subPath">The subfolder path (e.g., "MissingFK\Projects")</param>
    /// <returns>Full path to the subfolder</returns>
    public static string EnsureSubFolder(string subPath)
    {
        try
        {
            var baseFolder = GetUserDataFolder();
            var subFolder = Path.Combine(baseFolder, subPath);
            
            if (!Directory.Exists(subFolder))
            {
                Directory.CreateDirectory(subFolder);
                Logger.Info("Created subfolder: {Path}", subFolder);
            }
            
            return subFolder;
        }
        catch (Exception ex)
        {
            Logger.Error(ex, "Error creating subfolder: {SubPath}", subPath);
            throw;
        }
    }
    
    /// <summary>
    /// Gets the Missing FK base folder (for status/trigger files).
    /// </summary>
    public static string GetMissingFKBaseFolder()
    {
        return EnsureSubFolder("MissingFK");
    }
    
    /// <summary>
    /// Gets the Missing FK projects base folder.
    /// </summary>
    public static string GetMissingFKProjectsFolder()
    {
        return EnsureSubFolder(Path.Combine("MissingFK", "Projects"));
    }
    
    /// <summary>
    /// Gets the Missing FK ignore patterns folder.
    /// </summary>
    public static string GetMissingFKIgnorePatternsFolder()
    {
        return EnsureSubFolder(Path.Combine("MissingFK", "IgnorePatterns"));
    }
    
    /// <summary>
    /// Generates a unique project folder name with timestamp and table list.
    /// Format: yyyyMMdd_HHmmss_Schema_Table1_Table2_plusN
    /// </summary>
    /// <param name="schema">The database schema</param>
    /// <param name="tableNames">List of table names</param>
    /// <returns>Sanitized folder name</returns>
    public static string GenerateProjectFolderName(string schema, IEnumerable<string> tableNames)
    {
        var timestamp = DateTime.Now.ToString("yyyyMMdd_HHmmss");
        var sanitizedSchema = SanitizeFolderName(schema);
        
        var tables = tableNames.ToList();
        var tableNamesForFolder = tables.Take(3)
            .Select(SanitizeFolderName)
            .ToList();
        
        var suffix = tables.Count > 3 ? $"_plus{tables.Count - 3}" : "";
        
        var folderName = $"{timestamp}_{sanitizedSchema}_{string.Join("_", tableNamesForFolder)}{suffix}";
        
        // Ensure total length doesn't exceed reasonable limit (100 chars)
        if (folderName.Length > 100)
        {
            folderName = folderName.Substring(0, 100);
        }
        
        Logger.Debug("Generated project folder name: {FolderName}", folderName);
        return folderName;
    }
    
    /// <summary>
    /// Creates a new project folder for Missing FK discovery.
    /// </summary>
    /// <param name="schema">The database schema</param>
    /// <param name="tableNames">List of table names</param>
    /// <returns>Full path to the created project folder</returns>
    public static string CreateProjectFolder(string schema, IEnumerable<string> tableNames)
    {
        var projectsFolder = GetMissingFKProjectsFolder();
        var projectName = GenerateProjectFolderName(schema, tableNames);
        var projectPath = Path.Combine(projectsFolder, projectName);
        
        if (!Directory.Exists(projectPath))
        {
            Directory.CreateDirectory(projectPath);
            Logger.Info("Created project folder: {Path}", projectPath);
        }
        
        return projectPath;
    }
    
    /// <summary>
    /// Sanitizes a string for use in folder names.
    /// Removes special characters and limits length.
    /// </summary>
    private static string SanitizeFolderName(string name)
    {
        if (string.IsNullOrEmpty(name))
            return "UNKNOWN";
        
        /*
         * Regex Pattern Explanation:
         * [^\w] - Matches any character that is NOT a word character
         *         Word characters include: a-z, A-Z, 0-9, and underscore
         * 
         * This replaces all special characters (spaces, dots, slashes, etc.)
         * with empty string, keeping only alphanumeric and underscore.
         */
        var sanitized = Regex.Replace(name, @"[^\w]", "");
        
        // Limit to 20 characters
        if (sanitized.Length > 20)
        {
            sanitized = sanitized.Substring(0, 20);
        }
        
        return string.IsNullOrEmpty(sanitized) ? "UNKNOWN" : sanitized;
    }
}
