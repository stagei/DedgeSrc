namespace ServerMonitor.Core.Interfaces;

/// <summary>
/// Base interface for all monitoring modules
/// </summary>
public interface IMonitor
{
    /// <summary>
    /// Gets the name of the monitoring category
    /// </summary>
    string Category { get; }

    /// <summary>
    /// Gets whether the monitor is currently enabled
    /// </summary>
    bool IsEnabled { get; }

    /// <summary>
    /// Gets the current cached state from the last collection.
    /// Returns null if no data has been collected yet.
    /// </summary>
    MonitorResult? CurrentState { get; }

    /// <summary>
    /// Collects monitoring data asynchronously
    /// </summary>
    /// <param name="cancellationToken">Cancellation token</param>
    /// <returns>Monitoring result data</returns>
    Task<MonitorResult> CollectAsync(CancellationToken cancellationToken = default);
}

