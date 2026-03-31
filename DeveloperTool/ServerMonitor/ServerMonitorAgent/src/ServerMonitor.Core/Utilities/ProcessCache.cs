using System.Diagnostics;
using Microsoft.Extensions.Logging;

namespace ServerMonitor.Core.Utilities;

/// <summary>
/// Caches the process list to reduce CPU overhead from frequent Process.GetProcesses() calls
/// </summary>
public class ProcessCache
{
    private readonly ILogger<ProcessCache> _logger;
    private readonly int _refreshIntervalSeconds;
    private DateTime _lastRefresh = DateTime.MinValue;
    private List<Process> _cachedProcesses = new();
    private readonly object _lock = new();

    public ProcessCache(ILogger<ProcessCache> logger, int refreshIntervalSeconds = 120)
    {
        _logger = logger;
        _refreshIntervalSeconds = refreshIntervalSeconds;
    }

    /// <summary>
    /// Gets the cached process list, refreshing if needed
    /// </summary>
    public List<Process> GetProcesses(bool forceRefresh = false)
    {
        lock (_lock)
        {
            var now = DateTime.UtcNow;
            var timeSinceRefresh = (now - _lastRefresh).TotalSeconds;

            if (forceRefresh || timeSinceRefresh >= _refreshIntervalSeconds)
            {
                _logger.LogDebug("Refreshing process cache (force: {Force}, age: {Age:F1}s)", 
                    forceRefresh, timeSinceRefresh);
                
                try
                {
                    // Dispose old processes
                    foreach (var process in _cachedProcesses)
                    {
                        try { process.Dispose(); } catch { }
                    }
                    
                    _cachedProcesses = Process.GetProcesses().ToList();
                    _lastRefresh = now;
                    
                    _logger.LogDebug("Process cache refreshed: {Count} processes", _cachedProcesses.Count);
                }
                catch (Exception ex)
                {
                    _logger.LogWarning(ex, "Failed to refresh process cache");
                }
            }
            
            return _cachedProcesses;
        }
    }

    /// <summary>
    /// Gets the age of the cache in seconds
    /// </summary>
    public double GetCacheAgeSeconds()
    {
        lock (_lock)
        {
            return (DateTime.UtcNow - _lastRefresh).TotalSeconds;
        }
    }
}

