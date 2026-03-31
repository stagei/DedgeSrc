using System.Management;
using Microsoft.Extensions.Logging;

namespace ServerMonitor.Core.Utilities;

/// <summary>
/// Caches service-to-process mapping to reduce WMI query overhead
/// </summary>
public class ServiceMappingCache
{
    private readonly ILogger<ServiceMappingCache> _logger;
    private readonly int _refreshIntervalMinutes;
    private DateTime _lastRefresh = DateTime.MinValue;
    private Dictionary<int, ServiceInfo> _serviceMap = new();
    private readonly object _lock = new();

    public ServiceMappingCache(ILogger<ServiceMappingCache> logger, int refreshIntervalMinutes = 10)
    {
        _logger = logger;
        _refreshIntervalMinutes = refreshIntervalMinutes;
    }

    public class ServiceInfo
    {
        public string ServiceName { get; init; } = string.Empty;
        public string DisplayName { get; init; } = string.Empty;
        public string ExecutablePath { get; init; } = string.Empty;
        public string Status { get; init; } = string.Empty;
        public int? ProcessId { get; init; }
    }

    /// <summary>
    /// Gets the service map, refreshing if needed
    /// </summary>
    public Dictionary<int, ServiceInfo> GetServiceMap(bool forceRefresh = false)
    {
        lock (_lock)
        {
            var now = DateTime.UtcNow;
            var timeSinceRefresh = (now - _lastRefresh).TotalMinutes;

            if (forceRefresh || timeSinceRefresh >= _refreshIntervalMinutes)
            {
                _logger.LogDebug("Refreshing service mapping cache (force: {Force}, age: {Age:F1}m)", 
                    forceRefresh, timeSinceRefresh);
                
                try
                {
                    _serviceMap = BuildServiceMap();
                    _lastRefresh = now;
                    
                    _logger.LogDebug("Service mapping cache refreshed: {Count} services", _serviceMap.Count);
                }
                catch (Exception ex)
                {
                    _logger.LogWarning(ex, "Failed to refresh service mapping cache");
                }
            }
            
            return _serviceMap;
        }
    }

    private Dictionary<int, ServiceInfo> BuildServiceMap()
    {
        var serviceMap = new Dictionary<int, ServiceInfo>();
        // NOTE: This WMI query could generate Event 5858 if it fails
        const string wmiQuery = "SELECT * FROM Win32_Service";
        
        try
        {
            _logger.LogTrace("🔍 WMI Query: {Query} (namespace: root\\cimv2)", wmiQuery);
            var wmiStart = System.Diagnostics.Stopwatch.StartNew();
            
            using (var searcher = new ManagementObjectSearcher(wmiQuery))
            {
                foreach (ManagementObject service in searcher.Get())
                {
                    try
                    {
                        var serviceName = service["Name"]?.ToString() ?? string.Empty;
                        var pathName = service["PathName"]?.ToString() ?? string.Empty;
                        var processId = service["ProcessId"] != null ? 
                            Convert.ToInt32(service["ProcessId"]) : (int?)null;
                        
                        if (processId.HasValue)
                        {
                            serviceMap[processId.Value] = new ServiceInfo
                            {
                                ServiceName = serviceName,
                                DisplayName = service["DisplayName"]?.ToString() ?? string.Empty,
                                ExecutablePath = ExtractExecutablePath(pathName),
                                Status = service["State"]?.ToString() ?? string.Empty,
                                ProcessId = processId
                            };
                        }
                    }
                    catch (Exception ex)
                    {
                        _logger.LogTrace(ex, "Failed to process service entry");
                    }
                }
            }
            
            wmiStart.Stop();
            _logger.LogTrace("✅ WMI Query completed in {Ms}ms: Win32_Service ({Count} services)", 
                wmiStart.ElapsedMilliseconds, serviceMap.Count);
        }
        catch (ManagementException wmiEx)
        {
            _logger.LogWarning("⚠️ WMI Query FAILED (may cause Event 5858): {Query} | Error: {Error} | Code: {Code}", 
                wmiQuery, wmiEx.Message, wmiEx.ErrorCode);
        }
        catch (Exception ex)
        {
            _logger.LogWarning(ex, "Failed to build service map");
        }
        
        return serviceMap;
    }

    private static string ExtractExecutablePath(string pathName)
    {
        if (string.IsNullOrWhiteSpace(pathName))
            return string.Empty;

        // PathName from WMI may include arguments, e.g., "C:\Program Files\App\app.exe" -arg1
        // Extract just the executable path
        var trimmed = pathName.Trim();
        
        // If it starts with a quote, find the closing quote
        if (trimmed.StartsWith("\""))
        {
            var endQuote = trimmed.IndexOf('"', 1);
            if (endQuote > 0)
                return trimmed.Substring(1, endQuote - 1);
        }
        
        // Otherwise, take everything up to the first space (likely arguments)
        var firstSpace = trimmed.IndexOf(' ');
        if (firstSpace > 0)
            return trimmed.Substring(0, firstSpace);
        
        return trimmed;
    }
}

