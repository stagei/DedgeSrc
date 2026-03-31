using ServerMonitor.Core.Models;

namespace ServerMonitor.Core.Interfaces;

/// <summary>
/// Result from a monitoring operation
/// </summary>
public class MonitorResult
{
    /// <summary>
    /// Category of monitoring
    /// </summary>
    public string Category { get; init; } = string.Empty;

    /// <summary>
    /// Timestamp when data was collected
    /// </summary>
    public DateTime Timestamp { get; init; } = DateTime.UtcNow;

    /// <summary>
    /// Whether collection was successful
    /// </summary>
    public bool Success { get; init; } = true;

    /// <summary>
    /// Error message if collection failed
    /// </summary>
    public string? ErrorMessage { get; init; }

    /// <summary>
    /// Collected data (varies by monitor type)
    /// </summary>
    public object? Data { get; init; }

    /// <summary>
    /// Alerts generated during collection
    /// </summary>
    public List<Alert> Alerts { get; init; } = new();

    /// <summary>
    /// Collection duration in milliseconds
    /// </summary>
    public long CollectionDurationMs { get; init; }
}

