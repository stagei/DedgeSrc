using System.Text.Json;
using Microsoft.Extensions.Options;
using ServerMonitorDashboard.Models;

namespace ServerMonitorDashboard.Services;

/// <summary>
/// Loads and caches server list from ComputerInfo.json
/// </summary>
public class ComputerInfoService
{
    private readonly ILogger<ComputerInfoService> _logger;
    private readonly DashboardConfig _config;
    private readonly JsonSerializerOptions _jsonOptions;
    private List<ComputerInfo>? _cachedServers;
    private DateTime _lastLoad = DateTime.MinValue;
    private readonly TimeSpan _cacheExpiry = TimeSpan.FromMinutes(5);

    public ComputerInfoService(
        ILogger<ComputerInfoService> logger,
        IOptions<DashboardConfig> config)
    {
        _logger = logger;
        _config = config.Value;
        _jsonOptions = new JsonSerializerOptions
        {
            PropertyNameCaseInsensitive = true
        };
    }

    /// <summary>
    /// Gets all servers (type contains "Server") from ComputerInfo.json
    /// </summary>
    public async Task<List<ComputerInfo>> GetServersAsync()
    {
        // Use cache if still valid
        if (_cachedServers != null && DateTime.UtcNow - _lastLoad < _cacheExpiry)
        {
            return _cachedServers;
        }

        try
        {
            if (!File.Exists(_config.ComputerInfoPath))
            {
                _logger.LogWarning("ComputerInfo.json not found at {Path}", _config.ComputerInfoPath);
                return new List<ComputerInfo>();
            }

            var json = await File.ReadAllTextAsync(_config.ComputerInfoPath);
            var allComputers = JsonSerializer.Deserialize<List<ComputerInfo>>(json, _jsonOptions) ?? new List<ComputerInfo>();

            // Filter to only active servers
            _cachedServers = allComputers
                .Where(c => c.Type?.Contains("Server", StringComparison.OrdinalIgnoreCase) == true)
                .Where(c => !string.IsNullOrEmpty(c.Name))
                .Where(c => c.IsActive)  // Only include active servers
                .ToList();

            _lastLoad = DateTime.UtcNow;
            _logger.LogInformation("Loaded {Count} servers from ComputerInfo.json", _cachedServers.Count);

            return _cachedServers;
        }
        catch (Exception ex)
        {
            _logger.LogError(ex, "Error loading ComputerInfo.json from {Path}", _config.ComputerInfoPath);
            return _cachedServers ?? new List<ComputerInfo>();
        }
    }

    /// <summary>
    /// Forces a refresh of the server list cache
    /// </summary>
    public void InvalidateCache()
    {
        _cachedServers = null;
        _lastLoad = DateTime.MinValue;
    }
}
