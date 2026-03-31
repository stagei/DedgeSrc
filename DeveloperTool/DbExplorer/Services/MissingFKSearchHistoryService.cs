using System;
using System.Collections.Generic;
using System.IO;
using System.Linq;
using System.Text.Json;
using NLog;

namespace DbExplorer.Services;

/// <summary>
/// Service for managing saved search patterns for Missing FK Discovery.
/// Stores search patterns (table name or column name) with pattern type (standard or regex).
/// </summary>
public class MissingFKSearchHistoryService
{
    private static readonly Logger Logger = LogManager.GetCurrentClassLogger();
    private readonly string _historyFilePath;
    private List<MissingFKSearchHistoryItem> _history;
    private readonly int _maxHistoryItems;

    public MissingFKSearchHistoryService(int maxHistoryItems = 50)
    {
        Logger.Debug("MissingFKSearchHistoryService initializing");

        _maxHistoryItems = maxHistoryItems;
        _historyFilePath = DetermineFilePath("missing-fk-search-history.json");

        _history = new List<MissingFKSearchHistoryItem>();
        LoadHistory();

        Logger.Info($"MissingFKSearchHistoryService initialized with max {_maxHistoryItems} items");
    }
    
    /// <summary>
    /// Determines the file path.
    /// </summary>
    private static string DetermineFilePath(string fileName)
    {
        return UserDataFolderHelper.GetFilePath(fileName);
    }

    /// <summary>
    /// Save search pattern to history.
    /// </summary>
    public void SaveSearchPattern(string pattern, string searchType, string patternType, string? schema = null, string? name = null)
    {
        Logger.Debug("Saving search pattern to history: {Pattern}, Type: {SearchType}, PatternType: {PatternType}, Schema: {Schema}",
            pattern, searchType, patternType, schema ?? "(none)");

        try
        {
            var item = new MissingFKSearchHistoryItem
            {
                Name = name ?? $"Search_{DateTime.Now:yyyy-MM-dd_HH-mm-ss}",
                Pattern = pattern,
                SearchType = searchType, // "TableName" or "ColumnName"
                PatternType = patternType, // "Standard" or "Regex"
                Schema = schema ?? string.Empty,
                SavedAt = DateTime.Now
            };

            // Remove existing pattern with same values (avoid duplicates)
            _history.RemoveAll(h =>
                h.Pattern == pattern &&
                h.SearchType == searchType &&
                h.PatternType == patternType &&
                (h.Schema ?? string.Empty) == (schema ?? string.Empty));

            _history.Insert(0, item);

            // Keep only max items
            if (_history.Count > _maxHistoryItems)
            {
                _history = _history.Take(_maxHistoryItems).ToList();
            }

            SaveHistory();
            Logger.Info("Search pattern saved to history: {Name}", item.Name);
        }
        catch (Exception ex)
        {
            Logger.Error(ex, "Failed to save search pattern to history");
            throw;
        }
    }

    /// <summary>
    /// Get all search history items.
    /// </summary>
    public List<MissingFKSearchHistoryItem> GetHistory()
    {
        return new List<MissingFKSearchHistoryItem>(_history);
    }

    /// <summary>
    /// Delete a search pattern from history.
    /// </summary>
    public void DeleteSearchPattern(string name)
    {
        Logger.Debug("Deleting search pattern from history: {Name}", name);

        try
        {
            _history.RemoveAll(h => h.Name.Equals(name, StringComparison.OrdinalIgnoreCase));
            SaveHistory();
            Logger.Info("Search pattern deleted from history: {Name}", name);
        }
        catch (Exception ex)
        {
            Logger.Error(ex, "Failed to delete search pattern from history");
            throw;
        }
    }

    private void LoadHistory()
    {
        try
        {
            if (File.Exists(_historyFilePath))
            {
                var json = File.ReadAllText(_historyFilePath);
                var items = JsonSerializer.Deserialize<List<MissingFKSearchHistoryItem>>(json);
                if (items != null)
                {
                    _history = items.OrderByDescending(h => h.SavedAt).ToList();
                    Logger.Debug("Loaded {Count} search patterns from history", _history.Count);
                }
            }
        }
        catch (Exception ex)
        {
            Logger.Error(ex, "Failed to load search history");
            _history = new List<MissingFKSearchHistoryItem>();
        }
    }

    private void SaveHistory()
    {
        try
        {
            var json = JsonSerializer.Serialize(_history, new JsonSerializerOptions
            {
                WriteIndented = true
            });
            File.WriteAllText(_historyFilePath, json);
            Logger.Debug("Saved {Count} search patterns to history", _history.Count);
        }
        catch (Exception ex)
        {
            Logger.Error(ex, "Failed to save search history");
            throw;
        }
    }
}

/// <summary>
/// Represents a saved search pattern in history.
/// </summary>
public class MissingFKSearchHistoryItem
{
    public string Name { get; set; } = string.Empty;
    public string Pattern { get; set; } = string.Empty;
    public string SearchType { get; set; } = "TableName"; // "TableName" or "ColumnName"
    public string PatternType { get; set; } = "Standard"; // "Standard" or "Regex"
    /// <summary>Schema name when the pattern was saved (optional).</summary>
    public string? Schema { get; set; }
    public DateTime SavedAt { get; set; }
}
