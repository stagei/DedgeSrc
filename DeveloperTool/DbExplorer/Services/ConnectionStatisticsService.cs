using System;
using System.Collections.Generic;
using System.IO;
using System.Linq;
using System.Text.Json;
using System.Threading.Tasks;
using NLog;

namespace DbExplorer.Services;

/// <summary>
/// Tracks connection statistics (min, max, median times) for progress estimation
/// </summary>
public class ConnectionStatisticsService
{
    private static readonly Logger Logger = LogManager.GetCurrentClassLogger();
    private readonly string _statisticsFilePath;

    public ConnectionStatisticsService()
    {
        _statisticsFilePath = UserDataFolderHelper.GetFilePath("connection_statistics.json");
        var folder = Path.GetDirectoryName(_statisticsFilePath);
        if (!string.IsNullOrEmpty(folder) && !Directory.Exists(folder))
        {
            Directory.CreateDirectory(folder);
        }
        MigrateFromAppDataIfNeeded();
        Logger.Debug("Connection statistics file: {Path}", _statisticsFilePath);
    }

    private void MigrateFromAppDataIfNeeded()
    {
        if (File.Exists(_statisticsFilePath)) return;
        var oldPath = Path.Combine(
            Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData),
            "DbExplorer", "connection_statistics.json");
        if (!File.Exists(oldPath)) return;
        try
        {
            File.Copy(oldPath, _statisticsFilePath);
            Logger.Info("Migrated connection_statistics.json from AppData to user data folder");
        }
        catch (Exception ex)
        {
            Logger.Warn(ex, "Could not migrate connection_statistics.json from AppData");
        }
    }

    /// <summary>
    /// Record a successful connection time
    /// </summary>
    public async Task RecordConnectionTimeAsync(string serverHost, int durationMs)
    {
        try
        {
            Logger.Debug("Recording connection time: {Server} - {Duration}ms", serverHost, durationMs);
            
            var stats = await LoadStatisticsAsync();
            
            if (!stats.ServerStatistics.ContainsKey(serverHost))
            {
                stats.ServerStatistics[serverHost] = new ServerConnectionStats
                {
                    ServerHost = serverHost,
                    ConnectionTimes = new List<int>()
                };
            }
            
            var serverStats = stats.ServerStatistics[serverHost];
            serverStats.ConnectionTimes.Add(durationMs);
            serverStats.LastConnectionTime = DateTime.UtcNow;
            serverStats.TotalConnections++;
            
            // Keep only last 50 connection times to avoid file bloat
            if (serverStats.ConnectionTimes.Count > 50)
            {
                serverStats.ConnectionTimes = serverStats.ConnectionTimes
                    .Skip(serverStats.ConnectionTimes.Count - 50)
                    .ToList();
            }
            
            // Recalculate statistics
            serverStats.MinTime = serverStats.ConnectionTimes.Min();
            serverStats.MaxTime = serverStats.ConnectionTimes.Max();
            serverStats.MedianTime = CalculateMedian(serverStats.ConnectionTimes);
            serverStats.AverageTime = (int)serverStats.ConnectionTimes.Average();
            
            await SaveStatisticsAsync(stats);
            
            Logger.Info("Connection stats updated for {Server}: Min={Min}ms, Median={Median}ms, Max={Max}ms", 
                serverHost, serverStats.MinTime, serverStats.MedianTime, serverStats.MaxTime);
        }
        catch (Exception ex)
        {
            Logger.Error(ex, "Failed to record connection time");
        }
    }

    /// <summary>
    /// Get expected connection time for a server (returns median, or default if no history)
    /// </summary>
    public async Task<ConnectionExpectation> GetExpectedConnectionTimeAsync(string serverHost)
    {
        try
        {
            var stats = await LoadStatisticsAsync();
            
            if (stats.ServerStatistics.TryGetValue(serverHost, out var serverStats) && 
                serverStats.ConnectionTimes.Count > 0)
            {
                Logger.Debug("Found connection history for {Server}: {Count} connections, Median={Median}ms", 
                    serverHost, serverStats.ConnectionTimes.Count, serverStats.MedianTime);
                
                return new ConnectionExpectation
                {
                    HasHistory = true,
                    ExpectedTimeMs = serverStats.MedianTime,
                    MinTimeMs = serverStats.MinTime,
                    MaxTimeMs = serverStats.MaxTime,
                    TotalConnections = serverStats.TotalConnections
                };
            }
            
            Logger.Debug("No connection history for {Server}, using default expectation", serverHost);
            return new ConnectionExpectation
            {
                HasHistory = false,
                ExpectedTimeMs = 3000, // Default: 3 seconds
                MinTimeMs = 1000,
                MaxTimeMs = 10000,
                TotalConnections = 0
            };
        }
        catch (Exception ex)
        {
            Logger.Error(ex, "Failed to get expected connection time");
            return new ConnectionExpectation
            {
                HasHistory = false,
                ExpectedTimeMs = 3000,
                MinTimeMs = 1000,
                MaxTimeMs = 10000,
                TotalConnections = 0
            };
        }
    }

    private async Task<ConnectionStatistics> LoadStatisticsAsync()
    {
        if (!File.Exists(_statisticsFilePath))
        {
            Logger.Debug("Statistics file does not exist, creating new");
            return new ConnectionStatistics
            {
                ServerStatistics = new Dictionary<string, ServerConnectionStats>()
            };
        }

        try
        {
            var json = await File.ReadAllTextAsync(_statisticsFilePath);
            var stats = JsonSerializer.Deserialize<ConnectionStatistics>(json);
            return stats ?? new ConnectionStatistics
            {
                ServerStatistics = new Dictionary<string, ServerConnectionStats>()
            };
        }
        catch (Exception ex)
        {
            Logger.Error(ex, "Failed to load statistics, creating new");
            return new ConnectionStatistics
            {
                ServerStatistics = new Dictionary<string, ServerConnectionStats>()
            };
        }
    }

    private async Task SaveStatisticsAsync(ConnectionStatistics stats)
    {
        try
        {
            var options = new JsonSerializerOptions
            {
                WriteIndented = true
            };
            var json = JsonSerializer.Serialize(stats, options);
            await File.WriteAllTextAsync(_statisticsFilePath, json);
            Logger.Debug("Statistics saved successfully");
        }
        catch (Exception ex)
        {
            Logger.Error(ex, "Failed to save statistics");
        }
    }

    private int CalculateMedian(List<int> values)
    {
        if (values.Count == 0) return 0;
        
        var sorted = values.OrderBy(v => v).ToList();
        int mid = sorted.Count / 2;
        
        if (sorted.Count % 2 == 0)
        {
            return (sorted[mid - 1] + sorted[mid]) / 2;
        }
        else
        {
            return sorted[mid];
        }
    }
}

public class ConnectionStatistics
{
    public Dictionary<string, ServerConnectionStats> ServerStatistics { get; set; } = new();
}

public class ServerConnectionStats
{
    public string ServerHost { get; set; } = string.Empty;
    public List<int> ConnectionTimes { get; set; } = new();
    public int MinTime { get; set; }
    public int MaxTime { get; set; }
    public int MedianTime { get; set; }
    public int AverageTime { get; set; }
    public int TotalConnections { get; set; }
    public DateTime LastConnectionTime { get; set; }
}

public class ConnectionExpectation
{
    public bool HasHistory { get; set; }
    public int ExpectedTimeMs { get; set; }
    public int MinTimeMs { get; set; }
    public int MaxTimeMs { get; set; }
    public int TotalConnections { get; set; }
}

