using System.Diagnostics;
using Microsoft.Extensions.Logging;
using Microsoft.Extensions.Options;
using ServerMonitor.Core.Configuration;
using ServerMonitor.Core.Interfaces;
using ServerMonitor.Core.Models;
using ServerMonitor.Core.Services;

namespace ServerMonitor.Core.Monitors;

/// <summary>
/// Monitors disk I/O and space usage.
/// Uses AlertAccumulator for deduplication and cooldown management.
/// </summary>
public class DiskMonitor : IMonitor
{
    private readonly ILogger<DiskMonitor> _logger;
    private readonly IOptionsMonitor<SurveillanceConfiguration> _config;
    private readonly IAlertAccumulator _alertAccumulator;
    // Rolling window of disk measurements for average calculation (per disk)
    private readonly Dictionary<string, List<(DateTime timestamp, double queueLength, double responseTime)>> _diskMeasurements = new();
    private readonly object _measurementsLock = new object();
    private MonitorResult? _currentState;

    public string Category => "Disk";
    public bool IsEnabled => _config.CurrentValue.DiskUsageMonitoring.Enabled || 
                             _config.CurrentValue.DiskSpaceMonitoring.Enabled;
    public MonitorResult? CurrentState => _currentState;

    public DiskMonitor(
        ILogger<DiskMonitor> logger,
        IOptionsMonitor<SurveillanceConfiguration> config,
        IAlertAccumulator alertAccumulator)
    {
        _logger = logger;
        _config = config;
        _alertAccumulator = alertAccumulator;
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

            var usageData = new List<DiskUsageData>();
            var spaceData = new List<DiskSpaceData>();

            // Collect disk space data
            if (_config.CurrentValue.DiskSpaceMonitoring.Enabled)
            {
                var spaceSettings = _config.CurrentValue.DiskSpaceMonitoring;
                var (data, spaceAlerts) = CollectDiskSpaceData(spaceSettings);
                spaceData = data;
                alerts.AddRange(spaceAlerts);
            }

            // Collect disk I/O data
            if (_config.CurrentValue.DiskUsageMonitoring.Enabled)
            {
                var usageSettings = _config.CurrentValue.DiskUsageMonitoring;
                var (data, usageAlerts) = await CollectDiskUsageDataAsync(usageSettings, cancellationToken);
                usageData = data;
                alerts.AddRange(usageAlerts);
            }

            // Clean up old measurements (older than SustainedDurationSeconds from disk usage settings)
            // Note: Disk space monitoring doesn't use sustained duration - it's immediate alerts
            var sustainedDuration = _config.CurrentValue.DiskUsageMonitoring?.Thresholds?.SustainedDurationSeconds ?? 0;
            
            if (sustainedDuration > 0)
            {
                var cutoffTime = DateTime.UtcNow.AddSeconds(-sustainedDuration);
                lock (_measurementsLock)
                {
                    foreach (var key in _diskMeasurements.Keys.ToList())
                    {
                        _diskMeasurements[key].RemoveAll(m => m.timestamp < cutoffTime);
                        if (_diskMeasurements[key].Count == 0)
                        {
                            _diskMeasurements.Remove(key);
                        }
                    }
                }
            }

            var diskData = new DiskData
            {
                Usage = usageData,
                Space = spaceData
            };

            stopwatch.Stop();

            var result = new MonitorResult
            {
                Category = Category,
                Success = true,
                Data = diskData,
                Alerts = alerts,
                CollectionDurationMs = stopwatch.ElapsedMilliseconds
            };

            _currentState = result;
            return result;
        }
        catch (Exception ex)
        {
            _logger.LogError(ex, "Error collecting disk metrics");
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

    private (List<DiskSpaceData> data, List<Alert> alerts) CollectDiskSpaceData(DiskSpaceMonitoringSettings settings)
    {
        var data = new List<DiskSpaceData>();
        var alerts = new List<Alert>();

        try
        {
            // Get drives to monitor
            List<DriveInfo> drives;
            
            // Check for special "*" value ANYWHERE in the array to monitor all local drives
            // Also trigger auto-detect when array is null or empty
            bool monitorAllDrives = settings.DisksToMonitor == null || 
                                   settings.DisksToMonitor.Count == 0 ||
                                   settings.DisksToMonitor.Any(d => d == "*");
            
            if (monitorAllDrives)
            {
                _logger.LogDebug("Auto-detecting all local drives (DisksToMonitor contains '*' or is empty)");
                
                // Get ALL drives from the system
                var allDrives = DriveInfo.GetDrives().ToList();
                _logger.LogInformation("System reports {Count} total drives", allDrives.Count);
                
                // Log all drives for debugging
                foreach (var d in allDrives)
                {
                    try
                    {
                        if (d.IsReady)
                        {
                            _logger.LogDebug("Drive found: {Name}, Type: {Type}, Size: {Size:F1} GB, Label: '{Label}'",
                                d.Name, d.DriveType, d.TotalSize / 1024.0 / 1024.0 / 1024.0, d.VolumeLabel ?? "");
                        }
                        else
                        {
                            _logger.LogDebug("Drive found: {Name}, Type: {Type}, NOT READY", d.Name, d.DriveType);
                        }
                    }
                    catch (Exception ex)
                    {
                        _logger.LogDebug("Drive found: {Name}, Error reading properties: {Error}", d.Name, ex.Message);
                    }
                }
                
                // Include Fixed AND Ram drives (for temp storage like Azure VMs)
                // Exclude: CDRom, Network, NoRootDirectory, Unknown, Removable
                drives = allDrives
                    .Where(d =>
                    {
                        try
                        {
                            if (!d.IsReady)
                            {
                                _logger.LogTrace("Drive {Name} excluded: Not ready", d.Name);
                                return false;
                            }
                            
                            // Include Fixed drives (normal HDDs/SSDs) and Ram drives (temp storage)
                            var includeTypes = new[] { DriveType.Fixed, DriveType.Ram };
                            if (!includeTypes.Contains(d.DriveType))
                            {
                                _logger.LogTrace("Drive {Name} excluded: Type {Type} not in [Fixed, Ram]", d.Name, d.DriveType);
                                return false;
                            }
                            
                            if (d.TotalSize <= 0)
                            {
                                _logger.LogTrace("Drive {Name} excluded: Zero size", d.Name);
                                return false;
                            }
                            
                            _logger.LogDebug("Drive {Name} INCLUDED: Type={Type}, Size={Size:F1} GB", 
                                d.Name, d.DriveType, d.TotalSize / 1024.0 / 1024.0 / 1024.0);
                            return true;
                        }
                        catch (Exception ex)
                        {
                            _logger.LogDebug("Drive {Name} excluded: Error - {Error}", d.Name, ex.Message);
                            return false;
                        }
                    })
                    .ToList();
                
                if (drives.Count > 0)
                {
                    var driveNames = string.Join(", ", drives.Select(d => d.Name.TrimEnd('\\')));
                    _logger.LogInformation("Monitoring {Count} drive(s): {Drives}", drives.Count, driveNames);
                }
                else
                {
                    _logger.LogWarning("No drives found for monitoring! Check drive types and permissions.");
                }
            }
            else
            {
                // Use specific configured drives only
                _logger.LogDebug("Using specific drives from config: {Drives}", string.Join(", ", settings.DisksToMonitor ?? new List<string>()));
                drives = DriveInfo.GetDrives()
                    .Where(d => d.IsReady && 
                               (settings.DisksToMonitor?.Contains(d.Name.TrimEnd('\\')) ?? false))
                    .ToList();
            }

            foreach (var drive in drives)
            {
                var totalGB = (double)drive.TotalSize / 1024 / 1024 / 1024;
                var availableGB = (double)drive.AvailableFreeSpace / 1024 / 1024 / 1024;
                var usedPercent = ((totalGB - availableGB) / totalGB) * 100;

                data.Add(new DiskSpaceData
                {
                    Drive = drive.Name.TrimEnd('\\'),
                    TotalGB = totalGB,
                    AvailableGB = availableGB,
                    UsedPercent = usedPercent,
                    FileSystem = drive.DriveFormat
                });

                // Check for alerts (using accumulator for deduplication/cooldown)
                var maxOccurrences = settings.Alerts.MaxOccurrences;
                var timeWindowMinutes = settings.Alerts.TimeWindowMinutes;
                var driveLetter = drive.Name.TrimEnd('\\');
                
                if (usedPercent >= settings.Thresholds.CriticalPercent)
                {
                    var alertKey = $"Disk:Space:{driveLetter}:Critical";
                    
                    // Record occurrence in accumulator
                    _alertAccumulator.RecordOccurrence(alertKey, DateTime.UtcNow, timeWindowMinutes);
                    
                    // Check if we should alert
                    if (_alertAccumulator.ShouldAlert(alertKey, maxOccurrences, timeWindowMinutes))
                    {
                        alerts.Add(new Alert
                        {
                            Severity = ParseAlertSeverity(settings.Alerts.CriticalAlertSeverity, AlertSeverity.Critical),
                            Category = Category,
                            Message = $"Disk {driveLetter} space critical: {usedPercent:F1}%",
                            Details = $"Drive {driveLetter} usage at {usedPercent:F1}%, only {availableGB:F2} GB available",
                            SuppressedChannels = settings.SuppressedChannels ?? new List<string>()
                        });
                        
                        // Clear accumulator after alert to start cooldown
                        _alertAccumulator.ClearAfterAlert(alertKey, timeWindowMinutes);
                    }
                }
                else if (usedPercent >= settings.Thresholds.WarningPercent)
                {
                    var alertKey = $"Disk:Space:{driveLetter}:Warning";
                    
                    // Record occurrence in accumulator
                    _alertAccumulator.RecordOccurrence(alertKey, DateTime.UtcNow, timeWindowMinutes);
                    
                    // Check if we should alert
                    if (_alertAccumulator.ShouldAlert(alertKey, maxOccurrences, timeWindowMinutes))
                    {
                        alerts.Add(new Alert
                        {
                            Severity = ParseAlertSeverity(settings.Alerts.WarningAlertSeverity, AlertSeverity.Warning),
                            Category = Category,
                            Message = $"Disk {driveLetter} space warning: {usedPercent:F1}%",
                            Details = $"Drive {driveLetter} usage at {usedPercent:F1}%, {availableGB:F2} GB available",
                            SuppressedChannels = settings.SuppressedChannels ?? new List<string>()
                        });
                        
                        // Clear accumulator after alert to start cooldown
                        _alertAccumulator.ClearAfterAlert(alertKey, timeWindowMinutes);
                    }
                }

                if (availableGB < settings.Thresholds.MinimumFreeSpaceGB)
                {
                    var alertKey = $"Disk:Space:{driveLetter}:MinFree";
                    
                    // Record occurrence in accumulator
                    _alertAccumulator.RecordOccurrence(alertKey, DateTime.UtcNow, timeWindowMinutes);
                    
                    // Check if we should alert
                    if (_alertAccumulator.ShouldAlert(alertKey, maxOccurrences, timeWindowMinutes))
                    {
                        alerts.Add(new Alert
                        {
                            Severity = ParseAlertSeverity(settings.Alerts.CriticalAlertSeverity, AlertSeverity.Critical),
                            Category = Category,
                            Message = $"Disk {driveLetter} free space below minimum",
                            Details = $"Drive {driveLetter} has only {availableGB:F2} GB free, below minimum of {settings.Thresholds.MinimumFreeSpaceGB} GB",
                            SuppressedChannels = settings.SuppressedChannels ?? new List<string>()
                        });
                        
                        // Clear accumulator after alert to start cooldown
                        _alertAccumulator.ClearAfterAlert(alertKey, timeWindowMinutes);
                    }
                }
            }
        }
        catch (Exception ex)
        {
            _logger.LogWarning(ex, "Failed to collect disk space data");
        }

        return (data, alerts);
    }

    private async Task<(List<DiskUsageData> data, List<Alert> alerts)> CollectDiskUsageDataAsync(
        DiskUsageMonitoringSettings settings, 
        CancellationToken cancellationToken)
    {
        var data = new List<DiskUsageData>();
        var alerts = new List<Alert>();

        try
        {
            var disksToMonitor = settings.DisksToMonitor.Select(d => d.TrimEnd(':').ToUpper()).ToList();

            foreach (var diskLetter in disksToMonitor)
            {
                try
                {
                    // Get disk queue length
                    using var queueCounter = new PerformanceCounter(
                        "PhysicalDisk", 
                        "Avg. Disk Queue Length", 
                        $"{diskLetter}:");
                    
                    // Get disk response time
                    using var responseCounter = new PerformanceCounter(
                        "PhysicalDisk", 
                        "Avg. Disk sec/Transfer", 
                        $"{diskLetter}:");

                    await Task.Delay(100, cancellationToken);

                    var queueLength = queueCounter.NextValue();
                    var responseTime = responseCounter.NextValue() * 1000; // Convert to ms

                    // Store current measurement with timestamp
                    var key = $"disk_{diskLetter}";
                    var now = DateTime.UtcNow;
                    lock (_measurementsLock)
                    {
                        if (!_diskMeasurements.ContainsKey(key))
                        {
                            _diskMeasurements[key] = new List<(DateTime, double, double)>();
                        }
                        
                        _diskMeasurements[key].Add((now, queueLength, responseTime));
                        
                        // Remove measurements older than SustainedDurationSeconds
                        var cutoffTime = now.AddSeconds(-settings.Thresholds.SustainedDurationSeconds);
                        _diskMeasurements[key].RemoveAll(m => m.timestamp < cutoffTime);
                    }

                    // Calculate averages over the sustained duration period
                    double averageQueueLength;
                    double averageResponseTime;
                    int measurementCount;
                    lock (_measurementsLock)
                    {
                        if (!_diskMeasurements.ContainsKey(key) || _diskMeasurements[key].Count == 0)
                        {
                            averageQueueLength = queueLength;
                            averageResponseTime = responseTime;
                            measurementCount = 1;
                        }
                        else
                        {
                            var measurements = _diskMeasurements[key];
                            averageQueueLength = measurements.Average(m => m.queueLength);
                            averageResponseTime = measurements.Average(m => m.responseTime);
                            measurementCount = measurements.Count;
                        }
                    }
                    
                    _logger.LogTrace("Disk {Disk}: Current Queue={CurrentQueue:F1}, Avg Queue={AvgQueue:F1}, Current Response={CurrentResponse:F1}ms, Avg Response={AvgResponse:F1}ms ({Count} measurements)", 
                        diskLetter, queueLength, averageQueueLength, responseTime, averageResponseTime, measurementCount);

                    // Check for alerts - only trigger if average over sustained duration exceeds threshold
                    // Need at least SustainedDurationSeconds worth of measurements
                    var requiredMeasurements = (int)Math.Ceiling(settings.Thresholds.SustainedDurationSeconds / (double)settings.PollingIntervalSeconds);
                    
                    var maxOccurrences = settings.Alerts.MaxOccurrences;
                    var timeWindowMinutes = settings.Alerts.TimeWindowMinutes;
                    
                    // CRITICAL: Do not alert until we have enough measurements to cover the full SustainedDurationSeconds period
                    if (measurementCount < requiredMeasurements)
                    {
                        _logger.LogDebug("Skipping Disk {Disk} alert check: Only {Count} measurements available, need {Required} for {Duration}s sustained duration (PollingInterval: {Interval}s)", 
                            diskLetter, measurementCount, requiredMeasurements, settings.Thresholds.SustainedDurationSeconds, settings.PollingIntervalSeconds);
                    }
                    else if (measurementCount >= requiredMeasurements)
                    {
                        if (averageQueueLength > settings.Thresholds.MaxQueueLength)
                        {
                            var alertKey = $"Disk:IO:{diskLetter}:QueueLength";
                            
                            // Record occurrence in accumulator
                            _alertAccumulator.RecordOccurrence(alertKey, DateTime.UtcNow, timeWindowMinutes);
                            
                            // Check if we should alert
                            if (_alertAccumulator.ShouldAlert(alertKey, maxOccurrences, timeWindowMinutes))
                            {
                                alerts.Add(new Alert
                                {
                                    Severity = ParseAlertSeverity(settings.Alerts.AlertSeverity, AlertSeverity.Warning),
                                    Category = Category,
                                    Message = $"Disk {diskLetter}: sustained high queue length",
                                    Details = $"Disk queue average over {settings.Thresholds.SustainedDurationSeconds} seconds is {averageQueueLength:F1}, exceeding threshold of {settings.Thresholds.MaxQueueLength} (based on {measurementCount} measurements, current: {queueLength:F1})",
                                    SuppressedChannels = settings.SuppressedChannels ?? new List<string>()
                                });
                                
                                // Clear accumulator after alert to start cooldown
                                _alertAccumulator.ClearAfterAlert(alertKey, timeWindowMinutes);
                            }
                        }

                        if (averageResponseTime > settings.Thresholds.MaxResponseTimeMs)
                        {
                            var alertKey = $"Disk:IO:{diskLetter}:ResponseTime";
                            
                            // Record occurrence in accumulator
                            _alertAccumulator.RecordOccurrence(alertKey, DateTime.UtcNow, timeWindowMinutes);
                            
                            // Check if we should alert
                            if (_alertAccumulator.ShouldAlert(alertKey, maxOccurrences, timeWindowMinutes))
                            {
                                alerts.Add(new Alert
                                {
                                    Severity = ParseAlertSeverity(settings.Alerts.AlertSeverity, AlertSeverity.Warning),
                                    Category = Category,
                                    Message = $"Disk {diskLetter}: sustained slow response time",
                                    Details = $"Response time average over {settings.Thresholds.SustainedDurationSeconds} seconds is {averageResponseTime:F1}ms, exceeding threshold of {settings.Thresholds.MaxResponseTimeMs}ms (based on {measurementCount} measurements, current: {responseTime:F1}ms)",
                                    SuppressedChannels = settings.SuppressedChannels ?? new List<string>()
                                });
                                
                                // Clear accumulator after alert to start cooldown
                                _alertAccumulator.ClearAfterAlert(alertKey, timeWindowMinutes);
                            }
                        }
                    }

                    // Get history for export
                    List<MeasurementHistory> queueHistory;
                    List<MeasurementHistory> responseHistory;
                    lock (_measurementsLock)
                    {
                        if (_diskMeasurements.ContainsKey(key))
                        {
                            queueHistory = _diskMeasurements[key].Select(m => new MeasurementHistory
                            {
                                Timestamp = m.timestamp,
                                Value = m.queueLength
                            }).ToList();
                            responseHistory = _diskMeasurements[key].Select(m => new MeasurementHistory
                            {
                                Timestamp = m.timestamp,
                                Value = m.responseTime
                            }).ToList();
                        }
                        else
                        {
                            queueHistory = new List<MeasurementHistory>();
                            responseHistory = new List<MeasurementHistory>();
                        }
                    }

                    data.Add(new DiskUsageData
                    {
                        Drive = $"{diskLetter}:",
                        QueueLength = queueLength,
                        AvgResponseTimeMs = responseTime,
                        TimeAboveThresholdSeconds = measurementCount >= requiredMeasurements && 
                            (averageQueueLength > settings.Thresholds.MaxQueueLength || averageResponseTime > settings.Thresholds.MaxResponseTimeMs) 
                            ? settings.Thresholds.SustainedDurationSeconds : 0,
                        Iops = 0, // Would need additional counters
                        QueueLengthHistory = queueHistory,
                        ResponseTimeHistory = responseHistory
                    });
                }
                catch (Exception ex)
                {
                    _logger.LogWarning(ex, "Failed to collect disk usage for {Disk}", diskLetter);
                }
            }
        }
        catch (Exception ex)
        {
            _logger.LogWarning(ex, "Failed to collect disk usage data");
        }

        return (data, alerts);
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

