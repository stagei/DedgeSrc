using ServerMonitor.Core.Models;

namespace ServerMonitor.Core.Interfaces;

/// <summary>
/// Interface for alert delivery channels
/// </summary>
public interface IAlertChannel
{
    /// <summary>
    /// Gets the channel type name
    /// </summary>
    string ChannelType { get; }

    /// <summary>
    /// Gets whether the channel is enabled
    /// </summary>
    bool IsEnabled { get; }

    /// <summary>
    /// Gets the minimum severity level for alerts on this channel
    /// </summary>
    AlertSeverity MinimumSeverity { get; }

    /// <summary>
    /// Sends an alert through this channel
    /// </summary>
    /// <param name="alert">Alert to send</param>
    /// <param name="cancellationToken">Cancellation token</param>
    Task SendAlertAsync(Alert alert, CancellationToken cancellationToken = default);
}

