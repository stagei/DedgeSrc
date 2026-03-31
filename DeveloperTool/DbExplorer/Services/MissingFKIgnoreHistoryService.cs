using System;
using System.Collections.Generic;
using System.IO;
using System.Linq;
using System.Text.Json;
using NLog;
using DbExplorer.Models;

namespace DbExplorer.Services;

/// <summary>
/// Service for managing saved ignore configurations for Missing FK Discovery.
/// Similar pattern to QueryHistoryService, but stores ignore JSON configurations.
/// </summary>
public class MissingFKIgnoreHistoryService
{
    private static readonly Logger Logger = LogManager.GetCurrentClassLogger();
    private readonly string _historyFilePath;
    private List<MissingFKIgnoreHistoryItem> _history;
    private readonly int _maxHistoryItems;

    public MissingFKIgnoreHistoryService(int maxHistoryItems = 50)
    {
        Logger.Debug("MissingFKIgnoreHistoryService initializing");

        _maxHistoryItems = maxHistoryItems;
        _historyFilePath = DetermineFilePath("missing-fk-ignore-history.json");

        _history = new List<MissingFKIgnoreHistoryItem>();
        LoadHistory();

        Logger.Info($"MissingFKIgnoreHistoryService initialized with max {_maxHistoryItems} items");
    }
    
    /// <summary>
    /// Determines the file path.
    /// </summary>
    private static string DetermineFilePath(string fileName)
    {
        return UserDataFolderHelper.GetFilePath(fileName);
    }

    /// <summary>
    /// Save ignore configuration to history with a name.
    /// </summary>
    public void SaveIgnoreConfig(MissingFKIgnoreModel model, string name)
    {
        Logger.Debug("Saving ignore config to history: {Name}", name);

        try
        {
            // Remove existing config with same name
            _history.RemoveAll(h => h.Name.Equals(name, StringComparison.OrdinalIgnoreCase));

            var item = new MissingFKIgnoreHistoryItem
            {
                Name = name,
                SavedAt = DateTime.Now,
                IgnoreModel = model
            };

            _history.Insert(0, item); // Add to beginning

            // Trim history to max items
            if (_history.Count > _maxHistoryItems)
            {
                _history = _history.Take(_maxHistoryItems).ToList();
                Logger.Debug($"Trimmed history to {_maxHistoryItems} items");
            }

            SaveHistory();
            Logger.Info($"Ignore config saved to history: {name} (total: {_history.Count})");
        }
        catch (Exception ex)
        {
            Logger.Error(ex, "Failed to save ignore config to history: {Name}", name);
            throw;
        }
    }

    /// <summary>
    /// Load ignore configuration from history by name.
    /// </summary>
    public MissingFKIgnoreModel? LoadIgnoreConfig(string name)
    {
        Logger.Debug("Loading ignore config from history: {Name}", name);

        try
        {
            var item = _history.FirstOrDefault(h => h.Name.Equals(name, StringComparison.OrdinalIgnoreCase));
            if (item == null)
            {
                Logger.Warn("Ignore config not found in history: {Name}", name);
                return null;
            }

            Logger.Info("Loaded ignore config from history: {Name}", name);
            return item.IgnoreModel;
        }
        catch (Exception ex)
        {
            Logger.Error(ex, "Failed to load ignore config from history: {Name}", name);
            return null;
        }
    }

    /// <summary>
    /// Get all history items (names and timestamps).
    /// </summary>
    public List<MissingFKIgnoreHistoryItem> GetHistory()
    {
        return _history;
    }

    /// <summary>
    /// Delete ignore configuration from history by name.
    /// </summary>
    public void DeleteIgnoreConfig(string name)
    {
        Logger.Info("Deleting ignore config from history: {Name}", name);

        try
        {
            var removed = _history.RemoveAll(h => h.Name.Equals(name, StringComparison.OrdinalIgnoreCase));
            if (removed > 0)
            {
                SaveHistory();
                Logger.Info("Deleted ignore config from history: {Name}", name);
            }
            else
            {
                Logger.Warn("Ignore config not found for deletion: {Name}", name);
            }
        }
        catch (Exception ex)
        {
            Logger.Error(ex, "Failed to delete ignore config from history: {Name}", name);
            throw;
        }
    }

    /// <summary>
    /// Load history from file.
    /// </summary>
    private void LoadHistory()
    {
        try
        {
            if (!File.Exists(_historyFilePath))
            {
                Logger.Debug($"History file not found: {_historyFilePath}");
                return;
            }

            var json = File.ReadAllText(_historyFilePath);
            _history = JsonSerializer.Deserialize<List<MissingFKIgnoreHistoryItem>>(json) ?? new List<MissingFKIgnoreHistoryItem>();

            Logger.Info($"Loaded {_history.Count} ignore configs from history");
        }
        catch (Exception ex)
        {
            Logger.Error(ex, "Failed to load ignore history");
            _history = new List<MissingFKIgnoreHistoryItem>();
        }
    }

    /// <summary>
    /// Save history to file.
    /// </summary>
    private void SaveHistory()
    {
        try
        {
            var directory = Path.GetDirectoryName(_historyFilePath);
            if (directory != null && !Directory.Exists(directory))
            {
                Directory.CreateDirectory(directory);
                Logger.Debug($"Created history directory: {directory}");
            }

            var json = JsonSerializer.Serialize(_history, new JsonSerializerOptions
            {
                WriteIndented = true
            });

            File.WriteAllText(_historyFilePath, json);
            Logger.Debug($"Saved {_history.Count} ignore configs to history file");
        }
        catch (Exception ex)
        {
            Logger.Error(ex, "Failed to save ignore history");
            throw;
        }
    }
}

/// <summary>
/// Model for ignore history item.
/// </summary>
public class MissingFKIgnoreHistoryItem
{
    public string Name { get; set; } = string.Empty;
    public DateTime SavedAt { get; set; }
    public MissingFKIgnoreModel IgnoreModel { get; set; } = new();
}
