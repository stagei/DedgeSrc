using System;
using System.Collections.Generic;
using System.IO;
using System.Linq;
using System.Text.Json;
using NLog;
using DbExplorer.Models;

namespace DbExplorer.Services;

/// <summary>
/// Manages connection history and last used timestamps
/// </summary>
public class ConnectionHistoryService
{
    private static readonly Logger Logger = LogManager.GetCurrentClassLogger();
    private readonly string _historyFilePath;
    private Dictionary<string, ConnectionHistoryEntry> _history;
    
    public ConnectionHistoryService()
    {
        var appDataPath = Path.Combine(
            Environment.GetFolderPath(Environment.SpecialFolder.ApplicationData),
            "DbExplorer");
        
        Directory.CreateDirectory(appDataPath);
        _historyFilePath = Path.Combine(appDataPath, "connection_history.json");
        _history = new Dictionary<string, ConnectionHistoryEntry>();
        
        LoadHistory();
    }
    
    /// <summary>
    /// Record that a connection was used
    /// </summary>
    public void RecordConnectionUsed(string profileName)
    {
        Logger.Debug("Recording connection usage: {ProfileName}", profileName);
        
        if (_history.ContainsKey(profileName))
        {
            _history[profileName].LastUsed = DateTime.Now;
            _history[profileName].UseCount++;
        }
        else
        {
            _history[profileName] = new ConnectionHistoryEntry
            {
                ProfileName = profileName,
                FirstUsed = DateTime.Now,
                LastUsed = DateTime.Now,
                UseCount = 1
            };
        }
        
        SaveHistory();
    }
    
    /// <summary>
    /// Get recent connections ordered by last used date
    /// </summary>
    public List<ConnectionHistoryEntry> GetRecentConnections(int maxCount = 10)
    {
        Logger.Debug("Getting recent connections (max: {MaxCount})", maxCount);
        
        return _history.Values
            .OrderByDescending(h => h.LastUsed)
            .Take(maxCount)
            .ToList();
    }
    
    /// <summary>
    /// Get history entry for a specific connection
    /// </summary>
    public ConnectionHistoryEntry? GetHistoryEntry(string profileName)
    {
        return _history.TryGetValue(profileName, out var entry) ? entry : null;
    }
    
    /// <summary>
    /// Remove a connection from history
    /// </summary>
    public void RemoveConnection(string profileName)
    {
        Logger.Info("Removing connection from history: {ProfileName}", profileName);
        
        if (_history.Remove(profileName))
        {
            SaveHistory();
        }
    }
    
    /// <summary>
    /// Clear all history
    /// </summary>
    public void ClearHistory()
    {
        Logger.Info("Clearing all connection history");
        _history.Clear();
        SaveHistory();
    }
    
    private void LoadHistory()
    {
        try
        {
            if (!File.Exists(_historyFilePath))
            {
                Logger.Debug("No history file found, starting fresh");
                return;
            }
            
            var json = File.ReadAllText(_historyFilePath);
            var entries = JsonSerializer.Deserialize<List<ConnectionHistoryEntry>>(json);
            
            if (entries != null)
            {
                _history = entries.ToDictionary(e => e.ProfileName);
                Logger.Info("Loaded {Count} connection history entries", _history.Count);
            }
        }
        catch (Exception ex)
        {
            Logger.Error(ex, "Failed to load connection history");
            _history = new Dictionary<string, ConnectionHistoryEntry>();
        }
    }
    
    private void SaveHistory()
    {
        try
        {
            var entries = _history.Values.ToList();
            var json = JsonSerializer.Serialize(entries, new JsonSerializerOptions
            {
                WriteIndented = true
            });
            
            File.WriteAllText(_historyFilePath, json);
            Logger.Debug("Saved {Count} connection history entries", entries.Count);
        }
        catch (Exception ex)
        {
            Logger.Error(ex, "Failed to save connection history");
        }
    }
}

/// <summary>
/// Represents connection usage history
/// </summary>
public class ConnectionHistoryEntry
{
    public string ProfileName { get; set; } = string.Empty;
    public DateTime FirstUsed { get; set; }
    public DateTime LastUsed { get; set; }
    public int UseCount { get; set; }
    
    public string LastUsedDisplay => LastUsed.ToString("yyyy-MM-dd HH:mm");
    public string LastUsedRelative => GetRelativeTime(LastUsed);
    
    private string GetRelativeTime(DateTime dateTime)
    {
        var timeSpan = DateTime.Now - dateTime;
        
        if (timeSpan.TotalMinutes < 1)
            return "Just now";
        if (timeSpan.TotalMinutes < 60)
            return $"{(int)timeSpan.TotalMinutes} minutes ago";
        if (timeSpan.TotalHours < 24)
            return $"{(int)timeSpan.TotalHours} hours ago";
        if (timeSpan.TotalDays < 7)
            return $"{(int)timeSpan.TotalDays} days ago";
        if (timeSpan.TotalDays < 30)
            return $"{(int)(timeSpan.TotalDays / 7)} weeks ago";
        if (timeSpan.TotalDays < 365)
            return $"{(int)(timeSpan.TotalDays / 30)} months ago";
        
        return $"{(int)(timeSpan.TotalDays / 365)} years ago";
    }
}

