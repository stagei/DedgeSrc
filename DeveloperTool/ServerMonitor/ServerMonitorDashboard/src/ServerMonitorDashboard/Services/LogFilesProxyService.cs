using System.Text.Json;
using Microsoft.Extensions.Options;
using ServerMonitorDashboard.Models;

namespace ServerMonitorDashboard.Services;

/// <summary>
/// Proxies log file requests to individual ServerMonitor agents
/// </summary>
public class LogFilesProxyService
{
    private readonly ILogger<LogFilesProxyService> _logger;
    private readonly DashboardConfig _config;
    private readonly IHttpClientFactory _httpClientFactory;
    private readonly JsonSerializerOptions _jsonOptions;

    public LogFilesProxyService(
        ILogger<LogFilesProxyService> logger,
        IOptions<DashboardConfig> config,
        IHttpClientFactory httpClientFactory)
    {
        _logger = logger;
        _config = config.Value;
        _httpClientFactory = httpClientFactory;
        _jsonOptions = new JsonSerializerOptions
        {
            PropertyNameCaseInsensitive = true,
            PropertyNamingPolicy = JsonNamingPolicy.CamelCase
        };
    }

    /// <summary>
    /// Gets list of SQL error log files from a specific server
    /// </summary>
    /// <param name="serverName">Target server name</param>
    /// <returns>List of log file info</returns>
    public async Task<List<LogFileInfo>?> GetSqlErrorLogFilesAsync(string serverName)
    {
        try
        {
            var client = _httpClientFactory.CreateClient("ServerMonitor");
            client.Timeout = TimeSpan.FromSeconds(_config.SnapshotTimeoutSeconds);

            var url = $"http://{serverName}:{_config.ServerMonitorPort}/api/logfiles/sqlerrors";

            _logger.LogDebug("Fetching SQL error log files from {Url}", url);

            var response = await client.GetAsync(url);
            
            if (!response.IsSuccessStatusCode)
            {
                _logger.LogWarning("Failed to get SQL error log files from {Server}: {Status}", 
                    serverName, response.StatusCode);
                return null;
            }

            var json = await response.Content.ReadAsStringAsync();
            var files = JsonSerializer.Deserialize<List<LogFileInfo>>(json, _jsonOptions);

            _logger.LogDebug("Retrieved {Count} SQL error log files from {Server}", files?.Count ?? 0, serverName);

            return files;
        }
        catch (TaskCanceledException)
        {
            _logger.LogWarning("Timeout getting SQL error log files from {Server}", serverName);
            return null;
        }
        catch (Exception ex)
        {
            _logger.LogError(ex, "Error getting SQL error log files from {Server}", serverName);
            return null;
        }
    }

    /// <summary>
    /// Gets the contents of a specific SQL error log file from a server
    /// </summary>
    /// <param name="serverName">Target server name</param>
    /// <param name="fileName">Log file name</param>
    /// <returns>File contents as string</returns>
    public async Task<string?> GetSqlErrorLogContentAsync(string serverName, string fileName)
    {
        try
        {
            var client = _httpClientFactory.CreateClient("ServerMonitor");
            client.Timeout = TimeSpan.FromSeconds(_config.SnapshotTimeoutSeconds * 2); // More time for larger files

            var url = $"http://{serverName}:{_config.ServerMonitorPort}/api/logfiles/sqlerrors/{Uri.EscapeDataString(fileName)}";

            _logger.LogDebug("Fetching SQL error log content from {Url}", url);

            var response = await client.GetAsync(url);
            
            if (!response.IsSuccessStatusCode)
            {
                _logger.LogWarning("Failed to get SQL error log content from {Server}: {Status}", 
                    serverName, response.StatusCode);
                return null;
            }

            var content = await response.Content.ReadAsStringAsync();

            _logger.LogDebug("Retrieved SQL error log content from {Server}: {Length} bytes", serverName, content.Length);

            return content;
        }
        catch (TaskCanceledException)
        {
            _logger.LogWarning("Timeout getting SQL error log content from {Server}", serverName);
            return null;
        }
        catch (Exception ex)
        {
            _logger.LogError(ex, "Error getting SQL error log content from {Server}", serverName);
            return null;
        }
    }
}

/// <summary>
/// Information about a log file
/// </summary>
public class LogFileInfo
{
    /// <summary>File name only</summary>
    public string FileName { get; set; } = string.Empty;
    
    /// <summary>Full path to the file</summary>
    public string FullPath { get; set; } = string.Empty;
    
    /// <summary>File size in bytes</summary>
    public long SizeBytes { get; set; }
    
    /// <summary>Last modified timestamp (UTC)</summary>
    public DateTime LastModified { get; set; }
    
    /// <summary>Approximate number of lines in the file</summary>
    public int LineCount { get; set; }
}
