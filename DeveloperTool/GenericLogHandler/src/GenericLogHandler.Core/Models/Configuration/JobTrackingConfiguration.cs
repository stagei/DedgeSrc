namespace GenericLogHandler.Core.Models.Configuration;

/// <summary>
/// Configuration for job tracking and correlation features
/// </summary>
public class JobTrackingConfiguration
{
    /// <summary>
    /// Whether job correlation is enabled (linking start/complete events)
    /// </summary>
    public bool EnableJobCorrelation { get; set; } = true;

    /// <summary>
    /// Hours after which a "Started" job without completion is marked as "TimedOut"
    /// </summary>
    public int OrphanTimeoutHours { get; set; } = 24;

    /// <summary>
    /// How often to check for orphaned jobs (in minutes)
    /// </summary>
    public int CheckIntervalMinutes { get; set; } = 15;

    /// <summary>
    /// Whether to automatically mark orphaned jobs as timed out
    /// </summary>
    public bool AutoMarkOrphanedJobs { get; set; } = true;

    /// <summary>
    /// Maximum number of recent executions to keep per job name (0 = unlimited)
    /// </summary>
    public int MaxExecutionsPerJob { get; set; } = 0;

    /// <summary>
    /// Days to keep job execution history (0 = unlimited)
    /// </summary>
    public int RetentionDays { get; set; } = 90;
}
