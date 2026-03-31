using System.Collections.Concurrent;
using Microsoft.Extensions.Logging;

namespace ServerMonitor.Core.Services;

/// <summary>
/// Tracks alert occurrences and prevents alert flooding through configurable
/// thresholds and cooldowns.
/// 
/// Key behaviors:
/// - Tracks occurrences per alert key in a sliding time window
/// - Only alerts when count > MaxOccurrences AND cooldown has expired
/// - After alerting, clears the accumulator but keeps LastProcessedTimestamp
///   to prevent re-alerting on the same events
/// - TimeWindowMinutes acts as both the counting window AND the cooldown period
/// </summary>
public class AlertAccumulator : IAlertAccumulator
{
    private readonly ILogger<AlertAccumulator> _logger;
    
    // Stores occurrence timestamps per alert key
    private readonly ConcurrentDictionary<string, List<DateTime>> _occurrences = new();
    
    // Tracks the last processed timestamp per alert key to avoid re-counting old events
    private readonly ConcurrentDictionary<string, DateTime> _lastProcessedTimestamp = new();
    
    // Tracks when the last alert was sent per alert key (for cooldown)
    private readonly ConcurrentDictionary<string, DateTime> _lastAlertTime = new();
    
    // Lock objects per key for thread safety
    private readonly ConcurrentDictionary<string, object> _locks = new();

    public AlertAccumulator(ILogger<AlertAccumulator> logger)
    {
        _logger = logger;
    }

    /// <inheritdoc />
    public void RecordOccurrence(string alertKey, DateTime timestamp, int timeWindowMinutes)
    {
        var lockObj = _locks.GetOrAdd(alertKey, _ => new object());
        
        lock (lockObj)
        {
            // Initialize list if needed
            var occurrences = _occurrences.GetOrAdd(alertKey, _ => new List<DateTime>());
            
            // Check if this occurrence is newer than last processed
            if (_lastProcessedTimestamp.TryGetValue(alertKey, out var lastProcessed) && timestamp <= lastProcessed)
            {
                _logger.LogTrace("Skipping occurrence for {Key} - timestamp {Timestamp} <= last processed {LastProcessed}",
                    alertKey, timestamp, lastProcessed);
                return;
            }
            
            // Sanitize old entries first
            var cutoff = DateTime.UtcNow.AddMinutes(-timeWindowMinutes);
            occurrences.RemoveAll(t => t < cutoff);
            
            // Add new occurrence
            occurrences.Add(timestamp);
            
            // Update last processed timestamp
            _lastProcessedTimestamp[alertKey] = timestamp;
            
            _logger.LogTrace("Recorded occurrence for {Key}: count now {Count} in {Window}min window",
                alertKey, occurrences.Count, timeWindowMinutes);
        }
    }

    /// <inheritdoc />
    public void RecordOccurrences(string alertKey, IEnumerable<DateTime> timestamps, int timeWindowMinutes)
    {
        var lockObj = _locks.GetOrAdd(alertKey, _ => new object());
        
        lock (lockObj)
        {
            // Initialize list if needed
            var occurrences = _occurrences.GetOrAdd(alertKey, _ => new List<DateTime>());
            
            // Get last processed timestamp
            _lastProcessedTimestamp.TryGetValue(alertKey, out var lastProcessed);
            
            // Sanitize old entries first
            var cutoff = DateTime.UtcNow.AddMinutes(-timeWindowMinutes);
            occurrences.RemoveAll(t => t < cutoff);
            
            // Add only new occurrences (newer than lastProcessed)
            var newTimestamps = timestamps
                .Where(t => t > lastProcessed && t >= cutoff)
                .OrderBy(t => t)
                .ToList();
            
            if (newTimestamps.Count == 0)
            {
                _logger.LogTrace("No new occurrences for {Key} - all {Total} timestamps <= last processed or outside window",
                    alertKey, timestamps.Count());
                return;
            }
            
            occurrences.AddRange(newTimestamps);
            
            // Update last processed timestamp to the newest
            _lastProcessedTimestamp[alertKey] = newTimestamps.Max();
            
            _logger.LogTrace("Recorded {NewCount} new occurrences for {Key}: count now {Count} in {Window}min window",
                newTimestamps.Count, alertKey, occurrences.Count, timeWindowMinutes);
        }
    }

    /// <inheritdoc />
    public bool ShouldAlert(string alertKey, int maxOccurrences, int timeWindowMinutes)
    {
        var lockObj = _locks.GetOrAdd(alertKey, _ => new object());
        
        lock (lockObj)
        {
            // Special case: MaxOccurrences = 0 AND TimeWindowMinutes = 0 means "alert on every occurrence"
            if (maxOccurrences == 0 && timeWindowMinutes == 0)
            {
                var occurrences = _occurrences.GetOrAdd(alertKey, _ => new List<DateTime>());
                return occurrences.Count > 0;
            }
            
            // Check cooldown
            if (_lastAlertTime.TryGetValue(alertKey, out var lastAlert))
            {
                var cooldownEnd = lastAlert.AddMinutes(timeWindowMinutes);
                if (DateTime.UtcNow < cooldownEnd)
                {
                    _logger.LogTrace("Alert {Key} still in cooldown until {CooldownEnd}",
                        alertKey, cooldownEnd);
                    return false;
                }
            }
            
            // Get current count
            var count = GetOccurrenceCountInternal(alertKey, timeWindowMinutes);
            
            // Alert if count exceeds threshold
            var shouldAlert = count > maxOccurrences;
            
            if (shouldAlert)
            {
                _logger.LogDebug("Alert {Key}: count {Count} > threshold {Max} - SHOULD ALERT",
                    alertKey, count, maxOccurrences);
            }
            
            return shouldAlert;
        }
    }

    /// <inheritdoc />
    public int GetOccurrenceCount(string alertKey, int timeWindowMinutes)
    {
        var lockObj = _locks.GetOrAdd(alertKey, _ => new object());
        
        lock (lockObj)
        {
            return GetOccurrenceCountInternal(alertKey, timeWindowMinutes);
        }
    }

    private int GetOccurrenceCountInternal(string alertKey, int timeWindowMinutes)
    {
        if (!_occurrences.TryGetValue(alertKey, out var occurrences))
        {
            return 0;
        }
        
        // Sanitize old entries
        var cutoff = DateTime.UtcNow.AddMinutes(-timeWindowMinutes);
        occurrences.RemoveAll(t => t < cutoff);
        
        return occurrences.Count;
    }

    /// <inheritdoc />
    public void ClearAfterAlert(string alertKey, int timeWindowMinutes)
    {
        var lockObj = _locks.GetOrAdd(alertKey, _ => new object());
        
        lock (lockObj)
        {
            // Record the alert time
            _lastAlertTime[alertKey] = DateTime.UtcNow;
            
            // Clear the occurrences list (but keep _lastProcessedTimestamp!)
            if (_occurrences.TryGetValue(alertKey, out var occurrences))
            {
                var count = occurrences.Count;
                occurrences.Clear();
                
                _logger.LogDebug("Cleared accumulator for {Key} after alert: {Count} occurrences cleared, cooldown {Window}min started",
                    alertKey, count, timeWindowMinutes);
            }
        }
    }

    /// <inheritdoc />
    public AccumulatorState? GetAccumulatorState(string alertKey)
    {
        var lockObj = _locks.GetOrAdd(alertKey, _ => new object());
        
        lock (lockObj)
        {
            if (!_occurrences.TryGetValue(alertKey, out var occurrences) || occurrences.Count == 0)
            {
                // Check if we have last alert time
                if (_lastAlertTime.TryGetValue(alertKey, out var lastAlert))
                {
                    return new AccumulatorState
                    {
                        OccurrenceCount = 0,
                        LastAlertTime = lastAlert
                    };
                }
                return null;
            }
            
            _lastAlertTime.TryGetValue(alertKey, out var alertTime);
            
            TimeSpan? cooldownRemaining = null;
            if (alertTime != default)
            {
                // Assuming a default 60-minute window for state reporting
                var remaining = alertTime.AddMinutes(60) - DateTime.UtcNow;
                if (remaining > TimeSpan.Zero)
                {
                    cooldownRemaining = remaining;
                }
            }
            
            return new AccumulatorState
            {
                OccurrenceCount = occurrences.Count,
                OldestOccurrence = occurrences.Min(),
                NewestOccurrence = occurrences.Max(),
                LastAlertTime = alertTime == default ? null : alertTime,
                CooldownRemaining = cooldownRemaining
            };
        }
    }

    /// <inheritdoc />
    public IEnumerable<string> GetActiveKeys()
    {
        return _occurrences.Keys.ToList();
    }

    /// <inheritdoc />
    public void ClearAll()
    {
        var keyCount = _occurrences.Count;
        var totalOccurrences = _occurrences.Values.Sum(list => list.Count);
        
        _occurrences.Clear();
        _lastProcessedTimestamp.Clear();
        _lastAlertTime.Clear();
        _locks.Clear();
        
        _logger.LogInformation("🔄 Alert accumulator flushed: cleared {KeyCount} alert keys with {OccurrenceCount} total occurrences",
            keyCount, totalOccurrences);
    }
}
