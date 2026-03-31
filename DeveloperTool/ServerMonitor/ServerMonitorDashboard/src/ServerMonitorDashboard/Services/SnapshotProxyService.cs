using System.Text.Json;
using Microsoft.Extensions.Options;
using ServerMonitorDashboard.Models;

namespace ServerMonitorDashboard.Services;

/// <summary>
/// Proxies snapshot requests to individual ServerMonitor agents
/// </summary>
public class SnapshotProxyService
{
    private readonly ILogger<SnapshotProxyService> _logger;
    private readonly DashboardConfig _config;
    private readonly IHttpClientFactory _httpClientFactory;
    private readonly JsonSerializerOptions _jsonOptions;

    public SnapshotProxyService(
        ILogger<SnapshotProxyService> logger,
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
    /// Gets a live snapshot from a specific server
    /// </summary>
    /// <param name="serverName">Target server name</param>
    /// <returns>Snapshot JSON as dynamic object</returns>
    public async Task<object?> GetSnapshotAsync(string serverName)
    {
        try
        {
            var client = _httpClientFactory.CreateClient("ServerMonitor");
            client.Timeout = TimeSpan.FromSeconds(_config.SnapshotTimeoutSeconds);

            var url = $"http://{serverName}:{_config.ServerMonitorPort}/api/snapshot";

            _logger.LogDebug("Fetching snapshot from {Url}", url);

            var response = await client.GetAsync(url);
            
            if (!response.IsSuccessStatusCode)
            {
                _logger.LogWarning("Failed to get snapshot from {Server}: {Status}", 
                    serverName, response.StatusCode);
                return null;
            }

            var json = await response.Content.ReadAsStringAsync();
            var snapshot = JsonSerializer.Deserialize<JsonElement>(json, _jsonOptions);

            _logger.LogInformation("Retrieved live snapshot from {Server}", serverName);

            return snapshot;
        }
        catch (TaskCanceledException)
        {
            _logger.LogWarning("Timeout getting snapshot from {Server}", serverName);
            return null;
        }
        catch (Exception ex)
        {
            _logger.LogError(ex, "Error getting snapshot from {Server}", serverName);
            return null;
        }
    }

    /// <summary>
    /// Clears the snapshot on a specific server's agent (resets in-memory + deletes persisted file)
    /// </summary>
    public async Task<(bool success, string message, JsonElement? data)> ClearSnapshotAsync(string serverName)
    {
        try
        {
            var client = _httpClientFactory.CreateClient("ServerMonitor");
            client.Timeout = TimeSpan.FromSeconds(_config.SnapshotTimeoutSeconds);

            var url = $"http://{serverName}:{_config.ServerMonitorPort}/api/snapshot/clear";

            _logger.LogWarning("Sending snapshot clear request to {Url}", url);

            var response = await client.PostAsync(url, null);

            if (!response.IsSuccessStatusCode)
            {
                _logger.LogWarning("Failed to clear snapshot on {Server}: {Status}", 
                    serverName, response.StatusCode);
                return (false, $"Agent returned {response.StatusCode}", null);
            }

            var json = await response.Content.ReadAsStringAsync();
            var result = JsonSerializer.Deserialize<JsonElement>(json, _jsonOptions);

            _logger.LogWarning("Snapshot cleared on {Server}", serverName);

            return (true, "Snapshot cleared successfully", result);
        }
        catch (TaskCanceledException)
        {
            _logger.LogWarning("Timeout clearing snapshot on {Server}", serverName);
            return (false, "Request timed out", null);
        }
        catch (Exception ex)
        {
            _logger.LogError(ex, "Error clearing snapshot on {Server}", serverName);
            return (false, ex.Message, null);
        }
    }
}
