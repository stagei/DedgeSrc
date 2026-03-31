using System;
using System.IO;
using System.Text.Json;
using NLog;
using DbExplorer.Models;

namespace DbExplorer.Services
{
    /// <summary>
    /// Service for managing user preferences stored in preferences.json
    /// </summary>
    public class PreferencesService
    {
        private static readonly Logger Logger = LogManager.GetCurrentClassLogger();
        private const string PreferencesFileName = "preferences.json";
        private string _preferencesFilePath;

        public UserPreferences Preferences { get; private set; } = new UserPreferences();

        public PreferencesService()
        {
            Logger.Debug("PreferencesService initialized");
            
            // Bootstrap: Determine preferences file path
            // 1. Check new default location (Documents\DbExplorer)
            // 2. Check old AppData location for migration
            _preferencesFilePath = DeterminePreferencesFilePath();
            
            Logger.Debug("Preferences file path: {Path}", _preferencesFilePath);
            
            LoadPreferences();
            
            // Set the UserDataFolderHelper cache with the loaded preferences
            UserDataFolderHelper.SetUserDataFolder(Preferences.UserDataFolder);
        }
        
        /// <summary>
        /// Determines the correct preferences file path.
        /// </summary>
        private string DeterminePreferencesFilePath()
        {
            var defaultFolder = UserPreferences.GetDefaultUserDataFolder();
            var defaultPath = Path.Combine(defaultFolder, PreferencesFileName);
            
            // Ensure folder exists
            if (!Directory.Exists(defaultFolder))
            {
                Directory.CreateDirectory(defaultFolder);
            }
            
            Logger.Debug("Using preferences path: {Path}", defaultPath);
            return defaultPath;
        }
        
        /// <summary>
        /// Updates the preferences file path when user changes the user data folder.
        /// </summary>
        public void UpdateUserDataFolder(string newFolder)
        {
            Logger.Info("Updating user data folder from {Old} to {New}", 
                Preferences.UserDataFolder, newFolder);
            
            var oldPath = _preferencesFilePath;
            
            // Update the preference
            Preferences.UserDataFolder = newFolder;
            
            // Ensure new folder exists
            if (!Directory.Exists(newFolder))
            {
                Directory.CreateDirectory(newFolder);
            }
            
            // Update file path
            _preferencesFilePath = Path.Combine(newFolder, PreferencesFileName);
            
            // Save to new location
            SavePreferences();
            
            // Update the cache
            UserDataFolderHelper.SetUserDataFolder(newFolder);
            
            Logger.Info("User data folder updated, new preferences path: {Path}", _preferencesFilePath);
        }

        /// <summary>
        /// Load preferences from JSON file, or create default if not exists
        /// </summary>
        public void LoadPreferences()
        {
            Logger.Debug("Loading preferences from file");
            
            try
            {
                if (File.Exists(_preferencesFilePath))
                {
                    Logger.Debug("Preferences file found, reading contents");
                    
                    var json = File.ReadAllText(_preferencesFilePath);
                    Preferences = JsonSerializer.Deserialize<UserPreferences>(json, new JsonSerializerOptions
                    {
                        WriteIndented = true,
                        PropertyNameCaseInsensitive = true
                    }) ?? new UserPreferences();
                    
                    Logger.Info("Preferences loaded successfully - MaxRows: {MaxRows}", Preferences.MaxRowsPerQuery);
                }
                else
                {
                    Logger.Info("Preferences file not found, creating default preferences");
                    Preferences = new UserPreferences();
                    SavePreferences();
                }
            }
            catch (Exception ex)
            {
                Logger.Error(ex, "Error loading preferences, using defaults");
                Preferences = new UserPreferences();
            }
        }

        /// <summary>
        /// Save current preferences to JSON file
        /// </summary>
        public void SavePreferences()
        {
            Logger.Debug("Saving preferences to file");
            
            try
            {
                var json = JsonSerializer.Serialize(Preferences, new JsonSerializerOptions
                {
                    WriteIndented = true
                });
                
                File.WriteAllText(_preferencesFilePath, json);
                
                Logger.Info("Preferences saved successfully");
                Logger.Debug("Saved preferences: {Json}", json);
            }
            catch (Exception ex)
            {
                Logger.Error(ex, "Error saving preferences");
            }
        }

        /// <summary>
        /// Update a specific preference and save
        /// </summary>
        public void UpdateMaxRowsPerQuery(int maxRows)
        {
            Logger.Debug("Updating MaxRowsPerQuery from {Old} to {New}", Preferences.MaxRowsPerQuery, maxRows);
            
            Preferences.MaxRowsPerQuery = maxRows;
            SavePreferences();
        }
        
        /// <summary>
        /// Reload preferences from file
        /// </summary>
        public void Reload()
        {
            LoadPreferences();
        }
        
        /// <summary>
        /// Increase all font sizes by 1 and save (UI, Grid, Editor)
        /// Also scales grid cell height proportionally
        /// </summary>
        public void IncreaseFontSize()
        {
            if (Preferences.UIFontSize < 24)
            {
                Preferences.UIFontSize++;
                Preferences.GridFontSize = Math.Min(36, Preferences.GridFontSize + 1);
                Preferences.FontSize = Math.Min(36, Preferences.FontSize + 1);
                
                // Scale grid cell height proportionally (formula: FontSize * 2 + 1)
                // This ensures row height accommodates the new font size
                Preferences.GridCellHeight = Math.Min(50, Preferences.GridFontSize * 2 + 1);
                
                SavePreferences();
                Logger.Info("All font sizes increased - UI: {UI}, Grid: {Grid}, Editor: {Editor}, CellHeight: {CellHeight}", 
                    Preferences.UIFontSize, Preferences.GridFontSize, Preferences.FontSize, Preferences.GridCellHeight);
            }
        }
        
        /// <summary>
        /// Decrease all font sizes by 1 and save (UI, Grid, Editor)
        /// Also scales grid cell height proportionally
        /// </summary>
        public void DecreaseFontSize()
        {
            if (Preferences.UIFontSize > 8)
            {
                Preferences.UIFontSize--;
                Preferences.GridFontSize = Math.Max(8, Preferences.GridFontSize - 1);
                Preferences.FontSize = Math.Max(8, Preferences.FontSize - 1);
                
                // Scale grid cell height proportionally (formula: FontSize * 2 + 1)
                // Minimum height of 17 (for font size 8)
                Preferences.GridCellHeight = Math.Max(17, Preferences.GridFontSize * 2 + 1);
                
                SavePreferences();
                Logger.Info("All font sizes decreased - UI: {UI}, Grid: {Grid}, Editor: {Editor}, CellHeight: {CellHeight}", 
                    Preferences.UIFontSize, Preferences.GridFontSize, Preferences.FontSize, Preferences.GridCellHeight);
            }
        }
        
        /// <summary>
        /// Increase TreeView item spacing by 1 and save
        /// </summary>
        public void IncreaseTreeViewSpacing()
        {
            if (Preferences.TreeViewItemSpacing < 20)
            {
                Preferences.TreeViewItemSpacing++;
                SavePreferences();
                Logger.Info("TreeView spacing increased to {Spacing}", Preferences.TreeViewItemSpacing);
            }
        }
        
        /// <summary>
        /// Decrease TreeView item spacing by 1 and save
        /// </summary>
        public void DecreaseTreeViewSpacing()
        {
            if (Preferences.TreeViewItemSpacing > 0)
            {
                Preferences.TreeViewItemSpacing--;
                SavePreferences();
                Logger.Info("TreeView spacing decreased to {Spacing}", Preferences.TreeViewItemSpacing);
            }
        }
    }
}

