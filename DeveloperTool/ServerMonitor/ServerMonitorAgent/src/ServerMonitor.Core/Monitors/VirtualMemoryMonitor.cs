using System.Diagnostics;
using Microsoft.Extensions.Logging;
using Microsoft.Extensions.Options;
using ServerMonitor.Core.Configuration;
using ServerMonitor.Core.Interfaces;
using ServerMonitor.Core.Models;
using ServerMonitor.Core.Services;

namespace ServerMonitor.Core.Monitors;

/// <summary>
/// Monitors virtual memory (page file) usage.
/// Uses AlertAccumulator for deduplication and cooldown management.
/// </summary>
public class VirtualMemoryMonitor : IMonitor, IDisposable
{
    private bool _disposed;
    private readonly ILogger<VirtualMemoryMonitor> _logger;
    private readonly IOptionsMonitor<SurveillanceConfiguration> _config;
    private readonly IAlertAccumulator _alertAccumulator;
    private readonly PerformanceCounter _pagesPerSecCounter;
    // Rolling window of virtual memory measurements for average calculation
    private readonly List<(DateTime timestamp, double value)> _virtualMemoryMeasurements = new();
    private readonly object _measurementsLock = new object();
    private MonitorResult? _currentState;

    public string Category => "VirtualMemory";
    public bool IsEnabled => _config.CurrentValue.VirtualMemoryMonitoring.Enabled;
    public MonitorResult? CurrentState => _currentState;

    public VirtualMemoryMonitor(
        ILogger<VirtualMemoryMonitor> logger,
        IOptionsMonitor<SurveillanceConfiguration> config,
        IAlertAccumulator alertAccumulator)
    {
        _logger = logger;
        _config = config;
        _alertAccumulator = alertAccumulator;

        _pagesPerSecCounter = new PerformanceCounter("Memory", "Pages/sec");
        _pagesPerSecCounter.NextValue(); // Prime the counter
    }

    public async Task<MonitorResult> CollectAsync(CancellationToken cancellationToken = default)
    {
        var stopwatch = Stopwatch.StartNew();
        var alerts = new List<Alert>();

        try
        {
            if (!IsEnabled)
            {
                return new MonitorResult
                {
                    Category = Category,
                    Success = true,
                    ErrorMessage = "Monitor is disabled"
                };
            }

            var settings = _config.CurrentValue.VirtualMemoryMonitoring;

            await Task.Delay(100, cancellationToken);

            // Get virtual memory info using WMI
            // NOTE: This WMI query could generate Event 5858 if it fails
            double totalVirtualMemory = 0;
            double availableVirtualMemory = 0;
            const string wmiQueryVirtMem = "SELECT SizeStoredInPagingFiles, FreeSpaceInPagingFiles FROM Win32_OperatingSystem";

            try
            {
                _logger.LogTrace("🔍 WMI Query: {Query} (namespace: root\\cimv2)", wmiQueryVirtMem);
                var wmiStart = System.Diagnostics.Stopwatch.StartNew();
                
                using (var searcher = new System.Management.ManagementObjectSearcher(wmiQueryVirtMem))
                {
                    foreach (System.Management.ManagementObject obj in searcher.Get())
                    {
                        totalVirtualMemory = Convert.ToDouble(obj["SizeStoredInPagingFiles"]) / 1024 / 1024; // GB
                        availableVirtualMemory = Convert.ToDouble(obj["FreeSpaceInPagingFiles"]) / 1024 / 1024; // GB
                    }
                }
                
                wmiStart.Stop();
                _logger.LogTrace("✅ WMI Query completed in {Ms}ms: Win32_OperatingSystem (VirtualMemory)", wmiStart.ElapsedMilliseconds);
            }
            catch (System.Management.ManagementException wmiEx)
            {
                _logger.LogWarning("⚠️ WMI Query FAILED (may cause Event 5858): {Query} | Error: {Error} | Code: {Code}", 
                    wmiQueryVirtMem, wmiEx.Message, wmiEx.ErrorCode);
            }
            catch (Exception ex)
            {
                _logger.LogWarning(ex, "⚠️ WMI Query FAILED: {Query}", wmiQueryVirtMem);
            }

            var usedPercent = totalVirtualMemory > 0 ? ((totalVirtualMemory - availableVirtualMemory) / totalVirtualMemory) * 100 : 0;

            // Get paging rate
            var pagingRate = _pagesPerSecCounter.NextValue();

            // Store current measurement with timestamp
            var now = DateTime.UtcNow;
            lock (_measurementsLock)
            {
                _virtualMemoryMeasurements.Add((now, usedPercent));
                
                // Remove measurements older than SustainedDurationSeconds
                var cutoffTime = now.AddSeconds(-settings.Thresholds.SustainedDurationSeconds);
                _virtualMemoryMeasurements.RemoveAll(m => m.timestamp < cutoffTime);
            }

            // Calculate average over the sustained duration period
            double averageUsedPercent;
            int measurementCount;
            lock (_measurementsLock)
            {
                if (_virtualMemoryMeasurements.Count == 0)
                {
                    averageUsedPercent = usedPercent;
                    measurementCount = 1;
                }
                else
                {
                    averageUsedPercent = _virtualMemoryMeasurements.Average(m => m.value);
                    measurementCount = _virtualMemoryMeasurements.Count;
                }
            }
            
            _logger.LogTrace("VirtualMemory: Current={Current:F1}%, Average over {Duration}s={Average:F1}% ({Count} measurements)", 
                usedPercent, settings.Thresholds.SustainedDurationSeconds, averageUsedPercent, measurementCount);

            var maxOccurrences = settings.Alerts.MaxOccurrences;
            var timeWindowMinutes = settings.Alerts.TimeWindowMinutes;
            
            // Check for alerts - only trigger if average over sustained duration exceeds threshold
            // Need at least SustainedDurationSeconds worth of measurements
            var requiredMeasurements = (int)Math.Ceiling(settings.Thresholds.SustainedDurationSeconds / (double)settings.PollingIntervalSeconds);
            
            // CRITICAL: Do not alert until we have enough measurements to cover the full SustainedDurationSeconds period
            if (measurementCount < requiredMeasurements)
            {
                _logger.LogDebug("Skipping VirtualMemory alert check: Only {Count} measurements available, need {Required} for {Duration}s sustained duration (PollingInterval: {Interval}s)", 
                    measurementCount, requiredMeasurements, settings.Thresholds.SustainedDurationSeconds, settings.PollingIntervalSeconds);
            }
            else if (measurementCount >= requiredMeasurements)
            {
                if (averageUsedPercent >= settings.Thresholds.CriticalPercent)
                {
                    const string alertKey = "VirtualMemory:Critical";
                    
                    // Record occurrence in accumulator
                    _alertAccumulator.RecordOccurrence(alertKey, DateTime.UtcNow, timeWindowMinutes);
                    
                    // Check if we should alert
                    if (_alertAccumulator.ShouldAlert(alertKey, maxOccurrences, timeWindowMinutes))
                    {
                        alerts.Add(new Alert
                        {
                            Severity = ParseAlertSeverity(settings.Alerts.CriticalAlertSeverity, AlertSeverity.Critical),
                            Category = Category,
                            Message = $"Virtual memory usage critical: {averageUsedPercent:F1}% (average)",
                            Details = $"Virtual memory usage average over {settings.Thresholds.SustainedDurationSeconds} seconds is {averageUsedPercent:F1}%, exceeding critical threshold of {settings.Thresholds.CriticalPercent}% (based on {measurementCount} measurements, current: {usedPercent:F1}%)",
                            SuppressedChannels = settings.SuppressedChannels ?? new List<string>()
                        });
                        
                        _alertAccumulator.ClearAfterAlert(alertKey, timeWindowMinutes);
                    }
                }
                else if (averageUsedPercent >= settings.Thresholds.WarningPercent)
                {
                    const string alertKey = "VirtualMemory:Warning";
                    
                    // Record occurrence in accumulator
                    _alertAccumulator.RecordOccurrence(alertKey, DateTime.UtcNow, timeWindowMinutes);
                    
                    // Check if we should alert
                    if (_alertAccumulator.ShouldAlert(alertKey, maxOccurrences, timeWindowMinutes))
                    {
                        alerts.Add(new Alert
                        {
                            Severity = ParseAlertSeverity(settings.Alerts.WarningAlertSeverity, AlertSeverity.Warning),
                            Category = Category,
                            Message = $"Virtual memory usage sustained above warning level: {averageUsedPercent:F1}% (average)",
                            Details = $"Virtual memory usage average over {settings.Thresholds.SustainedDurationSeconds} seconds is {averageUsedPercent:F1}%, exceeding warning threshold of {settings.Thresholds.WarningPercent}% (based on {measurementCount} measurements, current: {usedPercent:F1}%)",
                            SuppressedChannels = settings.SuppressedChannels ?? new List<string>()
                        });
                        
                        _alertAccumulator.ClearAfterAlert(alertKey, timeWindowMinutes);
                    }
                }
            }

            // Check for excessive paging
            if (pagingRate > settings.Thresholds.ExcessivePagingRate)
            {
                const string alertKey = "VirtualMemory:ExcessivePaging";
                
                // Record occurrence in accumulator
                _alertAccumulator.RecordOccurrence(alertKey, DateTime.UtcNow, timeWindowMinutes);
                
                // Check if we should alert
                if (_alertAccumulator.ShouldAlert(alertKey, maxOccurrences, timeWindowMinutes))
                {
                    alerts.Add(new Alert
                    {
                        Severity = ParseAlertSeverity(settings.Alerts.WarningAlertSeverity, AlertSeverity.Warning),
                        Category = Category,
                        Message = $"Excessive paging detected: {pagingRate:F0} pages/sec",
                        Details = $"Paging rate of {pagingRate:F0} pages/sec exceeds threshold of {settings.Thresholds.ExcessivePagingRate}",
                        SuppressedChannels = settings.SuppressedChannels ?? new List<string>()
                    });
                    
                    _alertAccumulator.ClearAfterAlert(alertKey, timeWindowMinutes);
                }
            }

            // Get history for export
            List<MeasurementHistory> virtualMemoryHistory;
            lock (_measurementsLock)
            {
                virtualMemoryHistory = _virtualMemoryMeasurements.Select(m => new MeasurementHistory
                {
                    Timestamp = m.timestamp,
                    Value = m.value
                }).ToList();
            }

            var data = new VirtualMemoryData
            {
                TotalGB = totalVirtualMemory,
                AvailableGB = availableVirtualMemory,
                UsedPercent = usedPercent,
                TimeAboveThresholdSeconds = measurementCount >= requiredMeasurements && averageUsedPercent >= settings.Thresholds.WarningPercent ? settings.Thresholds.SustainedDurationSeconds : 0,
                PagingRatePerSec = pagingRate,
                VirtualMemoryUsageHistory = virtualMemoryHistory
            };

            stopwatch.Stop();

            var result = new MonitorResult
            {
                Category = Category,
                Success = true,
                Data = data,
                Alerts = alerts,
                CollectionDurationMs = stopwatch.ElapsedMilliseconds
            };

            _currentState = result;
            return result;
        }
        catch (Exception ex)
        {
            _logger.LogError(ex, "Error collecting virtual memory metrics");
            stopwatch.Stop();

            var result = new MonitorResult
            {
                Category = Category,
                Success = false,
                ErrorMessage = ex.Message,
                CollectionDurationMs = stopwatch.ElapsedMilliseconds
            };

            _currentState = result;
            return result;
        }
    }
    
    /// <summary>
    /// Disposes PerformanceCounter resources when the service is shutting down.
    /// Note: Counters are NOT disposed during normal operation - only on shutdown.
    /// </summary>
    public void Dispose()
    {
        Dispose(true);
        GC.SuppressFinalize(this);
    }
    
    protected virtual void Dispose(bool disposing)
    {
        if (_disposed)
            return;
        
        if (disposing)
        {
            _pagesPerSecCounter?.Dispose();
            _logger.LogDebug("VirtualMemoryMonitor disposed - PerformanceCounter released");
        }
        
        _disposed = true;
    }
    
    private static AlertSeverity ParseAlertSeverity(string? severityString, AlertSeverity defaultValue)
    {
        if (string.IsNullOrWhiteSpace(severityString))
            return defaultValue;
            
        return severityString.ToLowerInvariant() switch
        {
            "informational" => AlertSeverity.Informational,
            "warning" => AlertSeverity.Warning,
            "critical" => AlertSeverity.Critical,
            _ => defaultValue
        };
    }
}

