using System.Diagnostics;
using Microsoft.Extensions.Options;
using ServerMonitorDashboard.Models;

namespace ServerMonitorDashboard.Services;

/// <summary>
/// Detects the current ServerMonitor agent version from the deployment path
/// </summary>
public class VersionService
{
    private readonly ILogger<VersionService> _logger;
    private readonly DashboardConfig _config;
    private string? _cachedVersion;
    private DateTime _lastCheck = DateTime.MinValue;
    private readonly TimeSpan _cacheExpiry = TimeSpan.FromMinutes(5);

    public VersionService(
        ILogger<VersionService> logger,
        IOptions<DashboardConfig> config)
    {
        _logger = logger;
        _config = config.Value;
    }

    /// <summary>
    /// Gets the current version of ServerMonitor.exe from the deployment path
    /// </summary>
    public string GetCurrentVersion()
    {
        // Use cache if still valid
        if (_cachedVersion != null && DateTime.UtcNow - _lastCheck < _cacheExpiry)
        {
            return _cachedVersion;
        }

        try
        {
            if (!File.Exists(_config.ServerMonitorExePath))
            {
                _logger.LogWarning("ServerMonitor.exe not found at {Path}", _config.ServerMonitorExePath);
                return "Unknown";
            }

            var versionInfo = FileVersionInfo.GetVersionInfo(_config.ServerMonitorExePath);
            _cachedVersion = versionInfo.FileVersion ?? "Unknown";
            _lastCheck = DateTime.UtcNow;

            _logger.LogInformation("Detected ServerMonitor version: {Version}", _cachedVersion);
            return _cachedVersion;
        }
        catch (Exception ex)
        {
            _logger.LogError(ex, "Error getting version from {Path}", _config.ServerMonitorExePath);
            return "Unknown";
        }
    }

    /// <summary>
    /// Gets the path to the ServerMonitor.exe
    /// </summary>
    public string GetExePath() => _config.ServerMonitorExePath;
}
