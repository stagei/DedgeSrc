using ServerMonitor.Core.Models;

namespace ServerMonitor.Core.Interfaces;

/// <summary>
/// Interface for snapshot export functionality
/// </summary>
public interface ISnapshotExporter
{
    /// <summary>
    /// Exports a snapshot to persistent storage
    /// </summary>
    /// <param name="snapshot">Snapshot to export</param>
    /// <param name="cancellationToken">Cancellation token</param>
    Task ExportAsync(SystemSnapshot snapshot, CancellationToken cancellationToken = default);

    /// <summary>
    /// Cleans up old snapshots based on retention policy
    /// </summary>
    /// <param name="cancellationToken">Cancellation token</param>
    Task CleanupOldSnapshotsAsync(CancellationToken cancellationToken = default);

    /// <summary>
    /// Gets the last exported snapshot (cached in memory for fast access)
    /// </summary>
    /// <returns>The last exported snapshot, or null if no snapshot has been exported yet</returns>
    SystemSnapshot? GetLastExportedSnapshot();
}

