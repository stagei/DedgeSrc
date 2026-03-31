using System.Diagnostics;
using Microsoft.Extensions.Logging;

namespace ServerMonitor.Core.Utilities;

/// <summary>
/// Tracks CPU usage per process over time to calculate accurate CPU percentages
/// </summary>
public class ProcessCpuTracker
{
    private readonly ILogger<ProcessCpuTracker> _logger;
    private readonly Dictionary<int, (DateTime timestamp, TimeSpan cpuTime)> _lastMeasurements = new();
    private readonly object _lock = new();
    private DateTime _lastCleanupTime = DateTime.UtcNow;

    public ProcessCpuTracker(ILogger<ProcessCpuTracker> logger)
    {
        _logger = logger;
    }

    /// <summary>
    /// Calculates CPU percent for a process based on time delta since last measurement
    /// </summary>
    public double CalculateCpuPercent(Process process, TimeSpan? interval = null)
    {
        if (process == null || process.HasExited)
            return 0;

        try
        {
            var pid = process.Id;
            var currentCpuTime = process.TotalProcessorTime;
            var currentTime = DateTime.UtcNow;
            
            lock (_lock)
            {
                if (_lastMeasurements.TryGetValue(pid, out var last))
                {
                    var cpuDelta = (currentCpuTime - last.cpuTime).TotalMilliseconds;
                    var timeDelta = interval?.TotalMilliseconds ?? (currentTime - last.timestamp).TotalMilliseconds;
                    
                    if (timeDelta > 0 && cpuDelta >= 0)
                    {
                        // CPU percent = (CPU time delta / real time delta) * 100 / processor count
                        var cpuPercent = (cpuDelta / timeDelta) * 100.0 / Environment.ProcessorCount;
                        _lastMeasurements[pid] = (currentTime, currentCpuTime);
                        return Math.Max(0, Math.Min(100, cpuPercent)); // Clamp to 0-100%
                    }
                }
                
                // First measurement or invalid delta - store and return 0
                _lastMeasurements[pid] = (currentTime, currentCpuTime);
                return 0;
            }
        }
        catch (Exception ex)
        {
            _logger.LogTrace(ex, "Failed to calculate CPU percent for process {Pid}", process.Id);
            return 0;
        }
    }

    /// <summary>
    /// Cleans up measurements for processes that no longer exist
    /// </summary>
    public void CleanupStaleProcesses(HashSet<int> activePids)
    {
        lock (_lock)
        {
            var stalePids = _lastMeasurements.Keys.Where(pid => !activePids.Contains(pid)).ToList();
            foreach (var pid in stalePids)
            {
                _lastMeasurements.Remove(pid);
            }
            
            if (stalePids.Count > 0)
            {
                _logger.LogDebug("Cleaned up {Count} stale process CPU measurements", stalePids.Count);
            }
        }
    }
    
    /// <summary>
    /// Cleans up measurements older than the specified age.
    /// Also removes entries for processes that haven't been seen recently.
    /// </summary>
    /// <param name="maxAgeHours">Maximum age in hours for measurements to keep</param>
    public void CleanupOldMeasurements(int maxAgeHours)
    {
        lock (_lock)
        {
            var cutoffTime = DateTime.UtcNow.AddHours(-maxAgeHours);
            
            var staleEntries = _lastMeasurements
                .Where(kvp => kvp.Value.timestamp < cutoffTime)
                .Select(kvp => kvp.Key)
                .ToList();
            
            foreach (var pid in staleEntries)
            {
                _lastMeasurements.Remove(pid);
            }
            
            if (staleEntries.Count > 0)
            {
                _logger.LogDebug("Cleaned up {Count} old process CPU measurements (older than {Hours}h)", 
                    staleEntries.Count, maxAgeHours);
            }
            
            _lastCleanupTime = DateTime.UtcNow;
        }
    }
    
    /// <summary>
    /// Runs periodic cleanup if enough time has passed since last cleanup.
    /// Should be called periodically (e.g., every monitoring cycle).
    /// </summary>
    /// <param name="maxAgeHours">Maximum age in hours for measurements to keep</param>
    /// <param name="cleanupIntervalMinutes">Minimum minutes between cleanup runs</param>
    public void RunPeriodicCleanupIfNeeded(int maxAgeHours, int cleanupIntervalMinutes = 60)
    {
        var timeSinceLastCleanup = DateTime.UtcNow - _lastCleanupTime;
        
        if (timeSinceLastCleanup.TotalMinutes >= cleanupIntervalMinutes)
        {
            CleanupOldMeasurements(maxAgeHours);
        }
    }
}

