namespace ServerMonitor.Core.Configuration;

/// <summary>
/// Configuration for performance scaling on low-capacity servers.
/// When server name matches the pattern, all intervals are multiplied by the configured factor.
/// </summary>
public class PerformanceScalingSettings
{
    /// <summary>
    /// Enable/disable performance scaling feature
    /// </summary>
    public bool Enabled { get; init; } = true;

    /// <summary>
    /// Regex pattern to match low-capacity server names (e.g., "-app$" matches servers ending with "-app")
    /// </summary>
    public string LowCapacityServerPattern { get; init; } = "-app$";

    /// <summary>
    /// Documentation examples for pattern syntax
    /// </summary>
    public string? LowCapacityServerPatternExamples { get; init; }

    /// <summary>
    /// Multiplier for all PollingIntervalSeconds and IntervalMinutes values (default: 4)
    /// Example: 5 minute interval becomes 20 minutes with multiplier of 4
    /// </summary>
    public double IntervalMultiplier { get; init; } = 4.0;

    /// <summary>
    /// Multiplier for startup delays between service initialization (default: 4)
    /// </summary>
    public double StartupDelayMultiplier { get; init; } = 4.0;

    /// <summary>
    /// Whether to apply scaling to export intervals
    /// </summary>
    public bool ApplyToExportIntervals { get; init; } = true;

    /// <summary>
    /// Whether to apply scaling to cleanup intervals
    /// </summary>
    public bool ApplyToCleanupIntervals { get; init; } = true;

    /// <summary>
    /// Minimum interval in seconds after scaling (prevents too-short intervals)
    /// </summary>
    public int MinimumIntervalSeconds { get; init; } = 30;

    /// <summary>
    /// Maximum interval in seconds after scaling (prevents excessively long intervals)
    /// </summary>
    public int MaximumIntervalSeconds { get; init; } = 86400; // 24 hours
}
