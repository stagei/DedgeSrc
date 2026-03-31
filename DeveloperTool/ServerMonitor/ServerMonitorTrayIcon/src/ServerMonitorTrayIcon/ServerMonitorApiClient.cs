using System.Diagnostics;
using System.Net.Http;
using System.Text.Json;
using System.Text.Json.Serialization;

namespace ServerMonitorTrayIcon;

/// <summary>
/// HTTP client for communicating with the ServerMonitor REST API
/// </summary>
public class ServerMonitorApiClient : IDisposable
{
    private readonly HttpClient _httpClient;
    private readonly string _baseUrl;
    private readonly JsonSerializerOptions _jsonOptions;
    private bool _disposed;

    public ServerMonitorApiClient(string baseUrl)
    {
        _baseUrl = baseUrl.TrimEnd('/');
        _httpClient = new HttpClient
        {
            Timeout = TimeSpan.FromSeconds(10)
        };
        
        _jsonOptions = new JsonSerializerOptions
        {
            PropertyNameCaseInsensitive = true,
            PropertyNamingPolicy = JsonNamingPolicy.CamelCase
        };
    }
    
    public void Dispose()
    {
        Dispose(true);
        GC.SuppressFinalize(this);
    }
    
    protected virtual void Dispose(bool disposing)
    {
        if (!_disposed)
        {
            if (disposing)
            {
                _httpClient?.Dispose();
            }
            _disposed = true;
        }
    }

    /// <summary>
    /// Gets the current system snapshot from the API
    /// </summary>
    public async Task<SnapshotResponse?> GetCurrentSnapshotAsync()
    {
        try
        {
            var response = await _httpClient.GetAsync($"{_baseUrl}/api/snapshot");
            
            if (!response.IsSuccessStatusCode)
            {
                Debug.WriteLine($"API returned {response.StatusCode}");
                return null;
            }
            
            var content = await response.Content.ReadAsStringAsync();
            return JsonSerializer.Deserialize<SnapshotResponse>(content, _jsonOptions);
        }
        catch (Exception ex)
        {
            Debug.WriteLine($"Error getting snapshot: {ex.Message}");
            return null;
        }
    }

    /// <summary>
    /// Gets snapshot configuration info (output directories)
    /// </summary>
    public async Task<SnapshotInfoResponse?> GetSnapshotInfoAsync()
    {
        try
        {
            // Try to get from the snapshot metadata which includes configuration context
            var snapshot = await GetCurrentSnapshotAsync();
            
            if (snapshot?.Metadata?.Configuration != null)
            {
                var config = snapshot.Metadata.Configuration;
                var outputDirs = new List<string>();
                
                // Prefer UNC paths, fall back to regular paths
                if (config.SnapshotOutputDirectoriesUnc != null && config.SnapshotOutputDirectoriesUnc.Any())
                {
                    outputDirs.AddRange(config.SnapshotOutputDirectoriesUnc);
                }
                else if (config.SnapshotOutputDirectories != null && config.SnapshotOutputDirectories.Any())
                {
                    outputDirs.AddRange(config.SnapshotOutputDirectories);
                }
                
                return new SnapshotInfoResponse
                {
                    OutputDirectories = outputDirs,
                    OutputDirectoriesUnc = config.SnapshotOutputDirectoriesUnc ?? new List<string>()
                };
            }
            
            return null;
        }
        catch (Exception ex)
        {
            Debug.WriteLine($"Error getting snapshot info: {ex.Message}");
            return null;
        }
    }

    /// <summary>
    /// Gets the path to the last exported HTML file
    /// </summary>
    public async Task<string?> GetLastExportedHtmlPathAsync()
    {
        return await GetLastExportedFilePathAsync(".html");
    }

    /// <summary>
    /// Gets the path to the last exported JSON file
    /// </summary>
    public async Task<string?> GetLastExportedJsonPathAsync()
    {
        return await GetLastExportedFilePathAsync(".json");
    }

    private async Task<string?> GetLastExportedFilePathAsync(string extension)
    {
        try
        {
            var snapshotInfo = await GetSnapshotInfoAsync();
            
            // Check configured output directories
            if (snapshotInfo?.OutputDirectories != null && snapshotInfo.OutputDirectories.Any())
            {
                foreach (var dir in snapshotInfo.OutputDirectories)
                {
                    var path = FindLatestFileInDirectory(dir, extension);
                    if (!string.IsNullOrEmpty(path))
                        return path;
                }
            }
            
            // Fallback directories
            var fallbackDirs = new[]
            {
                @"C:\opt\src\DedgeSrc\DedgeSystemTools\Folders\Commonlogging\Server\ServerMonitor",
                @"C:\opt\data\ServerMonitor\Snapshots",
                @"C:\opt\data\ServerMonitor"
            };
            
            foreach (var dir in fallbackDirs)
            {
                var path = FindLatestFileInDirectory(dir, extension);
                if (!string.IsNullOrEmpty(path))
                    return path;
            }
        }
        catch (Exception ex)
        {
            Debug.WriteLine($"Error finding exported file: {ex.Message}");
        }
        
        return null;
    }

    private string? FindLatestFileInDirectory(string directory, string extension)
    {
        try
        {
            if (!Directory.Exists(directory))
                return null;
            
            // Get the current computer name to filter files
            var computerName = Environment.MachineName;
            
            // First try to find files that contain the computer name (most specific)
            var computerFiles = Directory.GetFiles(directory, $"*{extension}")
                .Where(f => Path.GetFileName(f).Contains(computerName, StringComparison.OrdinalIgnoreCase))
                .OrderByDescending(f => File.GetLastWriteTime(f))
                .FirstOrDefault();
            
            if (!string.IsNullOrEmpty(computerFiles))
                return computerFiles;
            
            // Fallback: return the most recent file if no computer-specific file found
            return Directory.GetFiles(directory, $"*{extension}")
                .OrderByDescending(f => File.GetLastWriteTime(f))
                .FirstOrDefault();
        }
        catch (Exception ex)
        {
            Debug.WriteLine($"Error accessing directory {directory}: {ex.Message}");
            return null;
        }
    }

    /// <summary>
    /// Checks if the API is reachable using the lightweight /api/Health/IsAlive endpoint
    /// </summary>
    public async Task<bool> IsApiAvailableAsync()
    {
        try
        {
            var response = await _httpClient.GetAsync($"{_baseUrl}/api/Health/IsAlive");
            return response.IsSuccessStatusCode;
        }
        catch
        {
            return false;
        }
    }
    
    /// <summary>
    /// Gets the current version of the ServerMonitor agent from the API
    /// </summary>
    /// <returns>Version info or null if API is unavailable</returns>
    public async Task<AgentVersionInfo?> GetCurrentVersionAsync()
    {
        try
        {
            var response = await _httpClient.GetAsync($"{_baseUrl}/api/Health/CurrentVersion");
            
            if (!response.IsSuccessStatusCode)
            {
                Debug.WriteLine($"GetCurrentVersion API returned {response.StatusCode}");
                return null;
            }
            
            var content = await response.Content.ReadAsStringAsync();
            return JsonSerializer.Deserialize<AgentVersionInfo>(content, _jsonOptions);
        }
        catch (Exception ex)
        {
            Debug.WriteLine($"Error getting current version: {ex.Message}");
            return null;
        }
    }
    
    /// <summary>
    /// Gets recent alerts from the ServerMonitor API
    /// </summary>
    /// <param name="count">Number of recent alerts to fetch (default: 10)</param>
    /// <returns>List of recent alerts, or null if API is unavailable</returns>
    public async Task<List<AlertInfo>?> GetRecentAlertsAsync(int count = 10)
    {
        try
        {
            var response = await _httpClient.GetAsync($"{_baseUrl}/api/snapshot/alerts/recent?count={count}");
            
            if (!response.IsSuccessStatusCode)
            {
                Debug.WriteLine($"GetRecentAlerts API returned {response.StatusCode}");
                return null;
            }
            
            var content = await response.Content.ReadAsStringAsync();
            return JsonSerializer.Deserialize<List<AlertInfo>>(content, _jsonOptions);
        }
        catch (Exception ex)
        {
            Debug.WriteLine($"Error getting recent alerts: {ex.Message}");
            return null;
        }
    }
}

#region API Response Models

/// <summary>
/// Version information from the ServerMonitor agent API
/// </summary>
public class AgentVersionInfo
{
    public string Version { get; set; } = "unknown";
    public string ProductName { get; set; } = "ServerMonitor";
    public string MachineName { get; set; } = "";
}

public class SnapshotResponse
{
    public SnapshotMetadata? Metadata { get; set; }
}

public class SnapshotMetadata
{
    public string? ServerName { get; set; }
    public DateTime Timestamp { get; set; }
    public ConfigurationContext? Configuration { get; set; }
}

public class ConfigurationContext
{
    public string? LogDirectory { get; set; }
    public string? LogDirectoryUnc { get; set; }
    public string? AppName { get; set; }
    public List<string>? SnapshotOutputDirectories { get; set; }
    public List<string>? SnapshotOutputDirectoriesUnc { get; set; }
    public string? SnapshotFileNamePattern { get; set; }
    public string? AlertLogPath { get; set; }
    public string? AlertLogPathUnc { get; set; }
}

public class SnapshotInfoResponse
{
    public List<string> OutputDirectories { get; set; } = new();
    public List<string> OutputDirectoriesUnc { get; set; } = new();
}

/// <summary>
/// Represents an alert from the ServerMonitor API
/// </summary>
public class AlertInfo
{
    public Guid Id { get; set; }
    public string Severity { get; set; } = string.Empty;
    public string Category { get; set; } = string.Empty;
    public string Message { get; set; } = string.Empty;
    public string? Details { get; set; }
    public DateTime Timestamp { get; set; }
    public string ServerName { get; set; } = string.Empty;
    
    /// <summary>
    /// Gets the severity as ToolTipIcon for balloon notifications
    /// </summary>
    public ToolTipIcon GetBalloonIcon()
    {
        return Severity?.ToLowerInvariant() switch
        {
            "critical" => ToolTipIcon.Error,
            "warning" => ToolTipIcon.Warning,
            "informational" or "info" => ToolTipIcon.Info,
            _ => ToolTipIcon.None
        };
    }
    
    /// <summary>
    /// Gets severity rank for sorting (higher = more severe)
    /// </summary>
    public int GetSeverityRank()
    {
        return Severity?.ToLowerInvariant() switch
        {
            "critical" => 3,
            "warning" => 2,
            "informational" or "info" => 1,
            _ => 0
        };
    }
}

#endregion
