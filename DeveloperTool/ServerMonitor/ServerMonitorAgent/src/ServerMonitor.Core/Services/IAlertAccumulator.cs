using ServerMonitor.Core.Models;

namespace ServerMonitor.Core.Services;

/// <summary>
/// Interface for the alert accumulator service that tracks alert occurrences
/// and prevents alert flooding through configurable thresholds and cooldowns.
/// </summary>
public interface IAlertAccumulator
{
    /// <summary>
    /// Records a new occurrence for the specified alert key.
    /// Automatically sanitizes old entries and tracks the latest processed timestamp.
    /// </summary>
    /// <param name="alertKey">Unique key for this alert type (e.g., "EventLog:201", "Processor:HighCpu")</param>
    /// <param name="timestamp">Timestamp of the occurrence</param>
    /// <param name="timeWindowMinutes">Time window for counting occurrences</param>
    void RecordOccurrence(string alertKey, DateTime timestamp, int timeWindowMinutes);

    /// <summary>
    /// Records multiple occurrences for the specified alert key.
    /// Only adds occurrences newer than the last processed timestamp.
    /// </summary>
    /// <param name="alertKey">Unique key for this alert type</param>
    /// <param name="timestamps">Collection of occurrence timestamps</param>
    /// <param name="timeWindowMinutes">Time window for counting occurrences</param>
    void RecordOccurrences(string alertKey, IEnumerable<DateTime> timestamps, int timeWindowMinutes);

    /// <summary>
    /// Checks if an alert should be triggered based on the current accumulation state.
    /// </summary>
    /// <param name="alertKey">Unique key for this alert type</param>
    /// <param name="maxOccurrences">Maximum allowed occurrences before alerting</param>
    /// <param name="timeWindowMinutes">Time window for counting occurrences</param>
    /// <returns>True if count > maxOccurrences and cooldown has expired</returns>
    bool ShouldAlert(string alertKey, int maxOccurrences, int timeWindowMinutes);

    /// <summary>
    /// Gets the current occurrence count for the specified alert key within the time window.
    /// </summary>
    /// <param name="alertKey">Unique key for this alert type</param>
    /// <param name="timeWindowMinutes">Time window for counting occurrences</param>
    /// <returns>Number of occurrences within the time window</returns>
    int GetOccurrenceCount(string alertKey, int timeWindowMinutes);

    /// <summary>
    /// Clears the accumulator after an alert has been distributed.
    /// Keeps the last processed timestamp to prevent re-alerting on same events.
    /// </summary>
    /// <param name="alertKey">Unique key for this alert type</param>
    /// <param name="timeWindowMinutes">Time window for cooldown</param>
    void ClearAfterAlert(string alertKey, int timeWindowMinutes);

    /// <summary>
    /// Gets information about the current accumulator state for an alert key.
    /// </summary>
    /// <param name="alertKey">Unique key for this alert type</param>
    /// <returns>Accumulator state including count, oldest/newest occurrence</returns>
    AccumulatorState? GetAccumulatorState(string alertKey);

    /// <summary>
    /// Gets all current accumulator keys (for diagnostics/monitoring).
    /// </summary>
    IEnumerable<string> GetActiveKeys();

    /// <summary>
    /// Clears all accumulated data (occurrences, timestamps, cooldowns) for all alert keys.
    /// Used for scheduled flushing of historical data.
    /// </summary>
    void ClearAll();
}

/// <summary>
/// Represents the current state of an alert accumulator
/// </summary>
public class AccumulatorState
{
    /// <summary>
    /// Number of occurrences currently tracked
    /// </summary>
    public int OccurrenceCount { get; init; }

    /// <summary>
    /// Timestamp of the oldest occurrence in the accumulator
    /// </summary>
    public DateTime? OldestOccurrence { get; init; }

    /// <summary>
    /// Timestamp of the newest occurrence in the accumulator
    /// </summary>
    public DateTime? NewestOccurrence { get; init; }

    /// <summary>
    /// Last time an alert was distributed for this key
    /// </summary>
    public DateTime? LastAlertTime { get; init; }

    /// <summary>
    /// Time remaining in cooldown (if any)
    /// </summary>
    public TimeSpan? CooldownRemaining { get; init; }
}
