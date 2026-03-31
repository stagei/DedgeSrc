using System.Text.RegularExpressions;
using Microsoft.Extensions.Logging;
using Microsoft.Extensions.Options;
using ServerMonitor.Core.Configuration;

namespace ServerMonitor.Core.Services;

/// <summary>
/// Service that manages performance scaling for low-capacity servers.
/// Provides scaled intervals based on server name pattern matching.
/// </summary>
public class PerformanceScalingService
{
    private readonly ILogger<PerformanceScalingService> _logger;
    private readonly IOptionsMonitor<SurveillanceConfiguration> _config;
    private readonly string _machineName;
    private bool? _isLowCapacityServer;
    private string? _lastPattern;

    public PerformanceScalingService(
        ILogger<PerformanceScalingService> logger,
        IOptionsMonitor<SurveillanceConfiguration> config)
    {
        _logger = logger;
        _config = config;
        _machineName = Environment.MachineName;
    }

    /// <summary>
    /// Gets whether the current server is considered a low-capacity server
    /// </summary>
    public bool IsLowCapacityServer
    {
        get
        {
            var settings = _config.CurrentValue.PerformanceScaling;
            
            // Re-evaluate if pattern changed
            if (_lastPattern != settings.LowCapacityServerPattern)
            {
                _isLowCapacityServer = null;
                _lastPattern = settings.LowCapacityServerPattern;
            }

            if (_isLowCapacityServer.HasValue)
                return _isLowCapacityServer.Value;

            if (!settings.Enabled || string.IsNullOrWhiteSpace(settings.LowCapacityServerPattern))
            {
                _isLowCapacityServer = false;
                return false;
            }

            try
            {
                var regex = new Regex(settings.LowCapacityServerPattern, RegexOptions.IgnoreCase);
                _isLowCapacityServer = regex.IsMatch(_machineName);
                
                if (_isLowCapacityServer.Value)
                {
                    _logger.LogInformation(
                        "🐢 Low-capacity server detected: '{MachineName}' matches pattern '{Pattern}'. " +
                        "Intervals will be multiplied by {Multiplier}x",
                        _machineName, settings.LowCapacityServerPattern, settings.IntervalMultiplier);
                }
                else
                {
                    _logger.LogDebug(
                        "Server '{MachineName}' does not match low-capacity pattern '{Pattern}'. Normal intervals will be used.",
                        _machineName, settings.LowCapacityServerPattern);
                }
            }
            catch (Exception ex)
            {
                _logger.LogWarning(ex, "Invalid regex pattern '{Pattern}' for low-capacity server detection. Disabling scaling.",
                    settings.LowCapacityServerPattern);
                _isLowCapacityServer = false;
            }

            return _isLowCapacityServer.Value;
        }
    }

    /// <summary>
    /// Gets the current interval multiplier (1.0 if not a low-capacity server)
    /// </summary>
    public double IntervalMultiplier
    {
        get
        {
            var settings = _config.CurrentValue.PerformanceScaling;
            return (settings.Enabled && IsLowCapacityServer) ? settings.IntervalMultiplier : 1.0;
        }
    }

    /// <summary>
    /// Gets the current startup delay multiplier (1.0 if not a low-capacity server)
    /// </summary>
    public double StartupDelayMultiplier
    {
        get
        {
            var settings = _config.CurrentValue.PerformanceScaling;
            return (settings.Enabled && IsLowCapacityServer) ? settings.StartupDelayMultiplier : 1.0;
        }
    }

    /// <summary>
    /// Scales an interval in seconds, applying min/max limits
    /// </summary>
    public int ScaleIntervalSeconds(int baseIntervalSeconds)
    {
        if (!IsLowCapacityServer)
            return baseIntervalSeconds;

        var settings = _config.CurrentValue.PerformanceScaling;
        var scaled = (int)(baseIntervalSeconds * settings.IntervalMultiplier);
        
        // Apply min/max limits
        scaled = Math.Max(settings.MinimumIntervalSeconds, scaled);
        scaled = Math.Min(settings.MaximumIntervalSeconds, scaled);
        
        return scaled;
    }

    /// <summary>
    /// Scales an interval in minutes, applying min/max limits
    /// </summary>
    public int ScaleIntervalMinutes(int baseIntervalMinutes)
    {
        if (!IsLowCapacityServer)
            return baseIntervalMinutes;

        var settings = _config.CurrentValue.PerformanceScaling;
        var scaledSeconds = (int)(baseIntervalMinutes * 60 * settings.IntervalMultiplier);
        
        // Apply min/max limits
        scaledSeconds = Math.Max(settings.MinimumIntervalSeconds, scaledSeconds);
        scaledSeconds = Math.Min(settings.MaximumIntervalSeconds, scaledSeconds);
        
        // Convert back to minutes (round up to avoid zero)
        return Math.Max(1, (int)Math.Ceiling(scaledSeconds / 60.0));
    }

    /// <summary>
    /// Scales a TimeSpan delay (for startup delays)
    /// </summary>
    public TimeSpan ScaleStartupDelay(TimeSpan baseDelay)
    {
        if (!IsLowCapacityServer)
            return baseDelay;

        var settings = _config.CurrentValue.PerformanceScaling;
        return TimeSpan.FromTicks((long)(baseDelay.Ticks * settings.StartupDelayMultiplier));
    }

    /// <summary>
    /// Gets a summary of the current scaling status for logging/display
    /// </summary>
    public string GetScalingSummary()
    {
        var settings = _config.CurrentValue.PerformanceScaling;
        
        if (!settings.Enabled)
            return "Performance scaling is disabled";

        if (!IsLowCapacityServer)
            return $"Normal performance mode ('{_machineName}' does not match pattern '{settings.LowCapacityServerPattern}')";

        return $"Low-capacity mode active for '{_machineName}' (pattern: '{settings.LowCapacityServerPattern}'): " +
               $"Intervals x{settings.IntervalMultiplier}, Startup delays x{settings.StartupDelayMultiplier}";
    }
}
