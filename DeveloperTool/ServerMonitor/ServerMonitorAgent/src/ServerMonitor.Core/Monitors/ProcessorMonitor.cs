using System.Diagnostics;
using System.Management;
using Microsoft.Extensions.Logging;
using Microsoft.Extensions.Options;
using ServerMonitor.Core.Configuration;
using ServerMonitor.Core.Interfaces;
using ServerMonitor.Core.Models;
using ServerMonitor.Core.Services;
using ServerMonitor.Core.Utilities;

namespace ServerMonitor.Core.Monitors;

/// <summary>
/// Monitors CPU/Processor usage.
/// Uses AlertAccumulator for deduplication and cooldown management.
/// </summary>
public class ProcessorMonitor : IMonitor, IDisposable
{
    private bool _disposed;
    private readonly ILogger<ProcessorMonitor> _logger;
    private readonly IOptionsMonitor<SurveillanceConfiguration> _config;
    private readonly IAlertAccumulator _alertAccumulator;
    private readonly PerformanceCounter _cpuCounter;
    private readonly List<PerformanceCounter> _perCoreCounters = new();
    // Rolling window of CPU measurements for average calculation
    private readonly List<(DateTime timestamp, double value)> _cpuMeasurements = new();
    private readonly object _measurementsLock = new object();
    private MonitorResult? _currentState;
    
    // Process monitoring caches (Option 2: Cached + Periodic)
    private readonly ProcessCache _processCache;
    private readonly ServiceMappingCache _serviceMappingCache;
    private readonly ProcessCpuTracker _cpuTracker;

    public string Category => "Processor";
    public bool IsEnabled => _config.CurrentValue.ProcessorMonitoring.Enabled;
    public MonitorResult? CurrentState => _currentState;

    public ProcessorMonitor(
        ILogger<ProcessorMonitor> logger,
        ILoggerFactory loggerFactory,
        IOptionsMonitor<SurveillanceConfiguration> config,
        IAlertAccumulator alertAccumulator)
    {
        _logger = logger;
        _config = config;
        _alertAccumulator = alertAccumulator;

        // Initialize performance counters
        _cpuCounter = new PerformanceCounter("Processor", "% Processor Time", "_Total");

        // Initialize per-core counters if enabled
        if (config.CurrentValue.ProcessorMonitoring.PerCoreMonitoring)
        {
            var coreCount = Environment.ProcessorCount;
            for (int i = 0; i < coreCount; i++)
            {
                _perCoreCounters.Add(new PerformanceCounter("Processor", "% Processor Time", i.ToString()));
            }
        }

        // First call returns 0, so call it once to prime
        _cpuCounter.NextValue();
        foreach (var counter in _perCoreCounters)
        {
            counter.NextValue();
        }

        // Initialize process monitoring caches
        var settings = config.CurrentValue.ProcessorMonitoring;
        _processCache = new ProcessCache(loggerFactory.CreateLogger<ProcessCache>(), settings.ProcessCacheRefreshSeconds);
        _serviceMappingCache = new ServiceMappingCache(loggerFactory.CreateLogger<ServiceMappingCache>(), settings.ServiceMapRefreshMinutes);
        _cpuTracker = new ProcessCpuTracker(loggerFactory.CreateLogger<ProcessCpuTracker>());
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

            var settings = _config.CurrentValue.ProcessorMonitoring;

            // Small delay to get accurate reading
            await Task.Delay(100, cancellationToken);

            // Get overall CPU usage
            var overallCpu = _cpuCounter.NextValue();

            // Get per-core usage
            var perCoreUsage = new List<double>();
            foreach (var counter in _perCoreCounters)
            {
                perCoreUsage.Add(counter.NextValue());
            }

            // Store current measurement with timestamp
            var now = DateTime.UtcNow;
            lock (_measurementsLock)
            {
                _cpuMeasurements.Add((now, overallCpu));
                
                // Remove measurements older than SustainedDurationSeconds
                var cutoffTime = now.AddSeconds(-settings.Thresholds.SustainedDurationSeconds);
                _cpuMeasurements.RemoveAll(m => m.timestamp < cutoffTime);
            }

            // Calculate average over the sustained duration period
            double averageCpu;
            int measurementCount;
            lock (_measurementsLock)
            {
                measurementCount = _cpuMeasurements.Count;
                if (measurementCount == 0)
                {
                    // No measurements yet - use current value but don't alert
                    averageCpu = overallCpu;
                }
                else
                {
                    averageCpu = _cpuMeasurements.Average(m => m.value);
                }
            }
            
            _logger.LogTrace("CPU: Current={Current:F1}%, Average over {Duration}s={Average:F1}% ({Count} measurements)", 
                overallCpu, settings.Thresholds.SustainedDurationSeconds, averageCpu, measurementCount);

            // Get top CPU consuming processes
            var topProcesses = GetTopCpuProcesses(settings.TrackTopProcesses);

            // Check for alerts - only trigger if average over sustained duration exceeds threshold
            // Need at least SustainedDurationSeconds worth of measurements
            var requiredMeasurements = (int)Math.Ceiling(settings.Thresholds.SustainedDurationSeconds / (double)settings.PollingIntervalSeconds);
            
            // CRITICAL: Do not alert until we have enough measurements to cover the full SustainedDurationSeconds period
            if (measurementCount < requiredMeasurements)
            {
                _logger.LogDebug("Skipping CPU alert check: Only {Count} measurements available, need {Required} for {Duration}s sustained duration (PollingInterval: {Interval}s)", 
                    measurementCount, requiredMeasurements, settings.Thresholds.SustainedDurationSeconds, settings.PollingIntervalSeconds);
            }
            else if (measurementCount >= requiredMeasurements)
            {
                var maxOccurrences = settings.Alerts.MaxOccurrences;
                var timeWindowMinutes = settings.Alerts.TimeWindowMinutes;
                
                if (averageCpu >= settings.Thresholds.CriticalPercent)
                {
                    const string alertKey = "Processor:Critical";
                    
                    // Record occurrence in accumulator
                    _alertAccumulator.RecordOccurrence(alertKey, DateTime.UtcNow, timeWindowMinutes);
                    
                    // Check if we should alert (using accumulator for deduplication/cooldown)
                    if (_alertAccumulator.ShouldAlert(alertKey, maxOccurrences, timeWindowMinutes))
                    {
                        var count = _alertAccumulator.GetOccurrenceCount(alertKey, timeWindowMinutes);
                        alerts.Add(new Alert
                        {
                            Severity = ParseAlertSeverity(settings.Alerts.CriticalAlertSeverity, AlertSeverity.Critical),
                            Category = Category,
                            Message = $"CPU usage critical: {averageCpu:F1}% (average)",
                            Details = $"CPU usage average over {settings.Thresholds.SustainedDurationSeconds} seconds is {averageCpu:F1}%, exceeding critical threshold of {settings.Thresholds.CriticalPercent}% (based on {measurementCount} measurements, current: {overallCpu:F1}%). Occurred {count} times in the last {timeWindowMinutes} minutes.",
                            SuppressedChannels = settings.SuppressedChannels ?? new List<string>()
                        });
                        
                        // Clear accumulator after alert to start cooldown
                        _alertAccumulator.ClearAfterAlert(alertKey, timeWindowMinutes);
                    }
                }
                else if (averageCpu >= settings.Thresholds.WarningPercent)
                {
                    const string alertKey = "Processor:Warning";
                    
                    // Record occurrence in accumulator
                    _alertAccumulator.RecordOccurrence(alertKey, DateTime.UtcNow, timeWindowMinutes);
                    
                    // Check if we should alert (using accumulator for deduplication/cooldown)
                    if (_alertAccumulator.ShouldAlert(alertKey, maxOccurrences, timeWindowMinutes))
                    {
                        var count = _alertAccumulator.GetOccurrenceCount(alertKey, timeWindowMinutes);
                        alerts.Add(new Alert
                        {
                            Severity = ParseAlertSeverity(settings.Alerts.WarningAlertSeverity, AlertSeverity.Warning),
                            Category = Category,
                            Message = $"CPU usage sustained above warning level: {averageCpu:F1}% (average)",
                            Details = $"CPU usage average over {settings.Thresholds.SustainedDurationSeconds} seconds is {averageCpu:F1}%, exceeding warning threshold of {settings.Thresholds.WarningPercent}% (based on {measurementCount} measurements, current: {overallCpu:F1}%). Occurred {count} times in the last {timeWindowMinutes} minutes.",
                            SuppressedChannels = settings.SuppressedChannels ?? new List<string>()
                        });
                        
                        // Clear accumulator after alert to start cooldown
                        _alertAccumulator.ClearAfterAlert(alertKey, timeWindowMinutes);
                    }
                }
            }

            // Check for any core at 100% - but only after we have enough measurements
            // This prevents false alerts during startup when cores may spike temporarily
            if (measurementCount >= requiredMeasurements)
            {
                var maxOccurrences = settings.Alerts.MaxOccurrences;
                var timeWindowMinutes = settings.Alerts.TimeWindowMinutes;
                
                for (int i = 0; i < perCoreUsage.Count; i++)
                {
                    if (perCoreUsage[i] >= 99.0)
                    {
                        var alertKey = $"Processor:Core{i}:MaxUtil";
                        
                        // Record occurrence in accumulator
                        _alertAccumulator.RecordOccurrence(alertKey, DateTime.UtcNow, timeWindowMinutes);
                        
                        // Check if we should alert (using accumulator for deduplication/cooldown)
                        if (_alertAccumulator.ShouldAlert(alertKey, maxOccurrences, timeWindowMinutes))
                        {
                            alerts.Add(new Alert
                            {
                                Severity = ParseAlertSeverity(settings.Alerts.WarningAlertSeverity, AlertSeverity.Warning),
                                Category = Category,
                                Message = $"CPU Core {i} at maximum utilization",
                                Details = $"Core {i} is at {perCoreUsage[i]:F1}% utilization",
                                SuppressedChannels = settings.SuppressedChannels ?? new List<string>()
                            });
                            
                            // Clear accumulator after alert to start cooldown
                            _alertAccumulator.ClearAfterAlert(alertKey, timeWindowMinutes);
                        }
                    }
                }
            }

            // Get history for export
            List<MeasurementHistory> cpuHistory;
            lock (_measurementsLock)
            {
                cpuHistory = _cpuMeasurements.Select(m => new MeasurementHistory
                {
                    Timestamp = m.timestamp,
                    Value = m.value
                }).ToList();
            }

            // Calculate real 1/5/15 minute averages from history
            double oneMinuteAvg = overallCpu;
            double fiveMinuteAvg = overallCpu;
            double fifteenMinuteAvg = overallCpu;
            
            lock (_measurementsLock)
            {
                var oneMinuteCutoff = now.AddMinutes(-1);
                var fiveMinuteCutoff = now.AddMinutes(-5);
                var fifteenMinuteCutoff = now.AddMinutes(-15);
                
                var oneMinuteMeasurements = _cpuMeasurements.Where(m => m.timestamp >= oneMinuteCutoff).ToList();
                var fiveMinuteMeasurements = _cpuMeasurements.Where(m => m.timestamp >= fiveMinuteCutoff).ToList();
                var fifteenMinuteMeasurements = _cpuMeasurements.Where(m => m.timestamp >= fifteenMinuteCutoff).ToList();
                
                if (oneMinuteMeasurements.Count > 0)
                {
                    oneMinuteAvg = oneMinuteMeasurements.Average(m => m.value);
                }
                if (fiveMinuteMeasurements.Count > 0)
                {
                    fiveMinuteAvg = fiveMinuteMeasurements.Average(m => m.value);
                }
                if (fifteenMinuteMeasurements.Count > 0)
                {
                    fifteenMinuteAvg = fifteenMinuteMeasurements.Average(m => m.value);
                }
            }

            var data = new ProcessorData
            {
                OverallUsagePercent = overallCpu,
                PerCoreUsage = perCoreUsage,
                TimeAboveThresholdSeconds = measurementCount >= requiredMeasurements && averageCpu >= settings.Thresholds.WarningPercent ? settings.Thresholds.SustainedDurationSeconds : 0, // Keep for backward compatibility
                TopProcesses = topProcesses,
                Averages = new ProcessorAverages
                {
                    OneMinute = oneMinuteAvg,
                    FiveMinute = fiveMinuteAvg,
                    FifteenMinute = fifteenMinuteAvg
                },
                CpuUsageHistory = cpuHistory
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
            _logger.LogError(ex, "Error collecting processor metrics");
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

    private List<TopProcess> GetTopCpuProcesses(int count)
    {
        try
        {
            var settings = _config.CurrentValue.ProcessorMonitoring;
            var processes = _processCache.GetProcesses();
            
            // First pass: Get basic metrics (fast) - get more candidates than needed
            // Wrap in try-catch to handle "Access is denied" for protected processes
            var processMetrics = processes
                .Select(p =>
                {
                    try
                    {
                        if (p.HasExited) return null;
                        
                        // These properties may throw "Access is denied" for protected processes
                        long memoryBytes = 0;
                        double cpuPercent = 0;
                        
                        try
                        {
                            memoryBytes = p.WorkingSet64;
                            cpuPercent = _cpuTracker.CalculateCpuPercent(p, TimeSpan.FromSeconds(settings.PollingIntervalSeconds));
                        }
                        catch (System.ComponentModel.Win32Exception ex) when (ex.NativeErrorCode == 5) // Access Denied - silently ignore
                        {
                            // Skip protected processes that we can't access
                            return null;
                        }
                        catch (InvalidOperationException)
                        {
                            // Process may have exited
                            return null;
                        }
                        
                        var memoryMB = memoryBytes / 1024 / 1024;
                        
                        return new
                        {
                            Process = p,
                            MemoryMB = memoryMB,
                            CpuPercent = cpuPercent,
                            CombinedScore = memoryMB + (cpuPercent * 10) // Combined metric for ranking
                        };
                    }
                    catch (System.ComponentModel.Win32Exception ex) when (ex.NativeErrorCode == 5) // Access Denied - silently ignore
                    {
                        // Skip protected processes
                        return null;
                    }
                    catch (InvalidOperationException)
                    {
                        // Process may have exited
                        return null;
                    }
                    catch
                    {
                        // Unexpected error - skip this process silently
                        return null;
                    }
                })
                .Where(p => p != null)
                .OrderByDescending(p => p!.CombinedScore)
                .Take(count * 2) // Get more candidates for metadata extraction
                .ToList();

            // Second pass: Get detailed metadata only for top candidates (slower)
            var serviceMap = settings.EnhancedProcessMetadata ? _serviceMappingCache.GetServiceMap() : null;
            var topProcesses = processMetrics
                .Select(p => settings.EnhancedProcessMetadata 
                    ? GetProcessMetadata(p!.Process, serviceMap!)
                    : GetBasicProcessInfo(p!.Process))
                .Where(p => p != null)
                .OrderByDescending(p => p!.MemoryMB + (p!.CpuPercent * 10))
                .Take(count)
                .ToList();

            // Cleanup stale CPU tracker entries
            var activePids = new HashSet<int>(processes.Where(p => !p.HasExited).Select(p => p.Id));
            _cpuTracker.CleanupStaleProcesses(activePids);

            return topProcesses!;
        }
        catch (System.ComponentModel.Win32Exception ex) when (ex.NativeErrorCode == 5) // Access Denied - silently ignore
        {
            // Protected processes may be inaccessible even with admin rights - return empty list
            return new List<TopProcess>();
        }
        catch
        {
            // Unexpected error - return empty list silently
            return new List<TopProcess>();
        }
    }

    private TopProcess? GetBasicProcessInfo(Process process)
    {
        try
        {
            if (process.HasExited) return null;
            
            var cpuPercent = _cpuTracker.CalculateCpuPercent(process, TimeSpan.FromSeconds(_config.CurrentValue.ProcessorMonitoring.PollingIntervalSeconds));
            
            return new TopProcess
            {
                Name = process.ProcessName,
                Pid = process.Id,
                CpuPercent = cpuPercent,
                MemoryMB = process.WorkingSet64 / 1024 / 1024,
                ExecutablePath = string.Empty,
                CommandLine = string.Empty,
                UserName = string.Empty,
                StartTime = DateTime.MinValue,
                TotalCpuTime = TimeSpan.Zero,
                UserCpuTime = TimeSpan.Zero,
                KernelCpuTime = TimeSpan.Zero,
                PrivateMemoryMB = 0,
                VirtualMemoryMB = 0,
                DiskReadMB = 0,
                DiskWriteMB = 0,
                ThreadCount = 0,
                HandleCount = 0,
                PageFaults = 0
            };
        }
        catch
        {
            return null;
        }
    }

    private TopProcess? GetProcessMetadata(Process process, Dictionary<int, ServiceMappingCache.ServiceInfo> serviceMap)
    {
        try
        {
            if (process.HasExited) return null;

            var pid = process.Id;
            var name = process.ProcessName;
            
            // Basic info (fast) - wrap each access in try-catch as some processes are protected
            var cpuPercent = _cpuTracker.CalculateCpuPercent(process, TimeSpan.FromSeconds(_config.CurrentValue.ProcessorMonitoring.PollingIntervalSeconds));
            
            // CPU times (may throw Access Denied for protected processes)
            TimeSpan cpuTime = TimeSpan.Zero;
            TimeSpan userTime = TimeSpan.Zero;
            TimeSpan kernelTime = TimeSpan.Zero;
            try
            {
                cpuTime = process.TotalProcessorTime;
                userTime = process.UserProcessorTime;
                kernelTime = process.PrivilegedProcessorTime;
            }
            catch (System.ComponentModel.Win32Exception ex) when (ex.NativeErrorCode == 5) // Access Denied - silently ignore
            {
                // Protected process - skip silently
            }
            catch (InvalidOperationException)
            {
                // Process may have exited
            }
            
            var memoryMB = process.WorkingSet64 / 1024 / 1024;
            var privateMemoryMB = process.PrivateMemorySize64 / 1024 / 1024;
            var virtualMemoryMB = process.VirtualMemorySize64 / 1024 / 1024;
            
            // Thread and handle counts (may throw Access Denied)
            int threadCount = 0;
            int handleCount = 0;
            try
            {
                threadCount = process.Threads.Count;
                handleCount = process.HandleCount;
            }
            catch (System.ComponentModel.Win32Exception ex) when (ex.NativeErrorCode == 5) // Access Denied - silently ignore
            {
                // Protected process - skip silently
            }
            catch (InvalidOperationException)
            {
                // Process may have exited
            }
            
            // Start time (may throw Access Denied)
            DateTime startTime = DateTime.MinValue;
            try
            {
                startTime = process.StartTime;
            }
            catch (System.ComponentModel.Win32Exception ex) when (ex.NativeErrorCode == 5) // Access Denied - silently ignore
            {
                // Protected process - skip silently
            }
            catch (InvalidOperationException)
            {
                // Process may have exited
            }

            // Executable path (slow - ~5-10ms, may throw)
            string executablePath = string.Empty;
            try
            {
                executablePath = process.MainModule?.FileName ?? string.Empty;
            }
            catch { } // Access denied for some processes

            // User name (slow - ~10-20ms, may throw)
            string userName = string.Empty;
            try
            {
                userName = GetProcessOwner(pid);
            }
            catch { }

            // WMI for advanced metrics (slow - ~50-100ms per process)
            long diskReadBytes = 0;
            long diskWriteBytes = 0;
            long pageFaults = 0;
            // CommandLine from WMI includes full command: executable path + all parameters
            // Example: "C:\Program Files\App\app.exe" --param1 value1 --param2
            // NOTE: This WMI query could generate Event 5858 if it fails
            string commandLine = string.Empty;

            try
            {
                _logger.LogTrace("🔍 WMI Query: Win32_Process (CPU) PID={Pid}", pid);
                using (var searcher = new ManagementObjectSearcher(
                    $"SELECT CommandLine, ReadTransferCount, WriteTransferCount, PageFaults FROM Win32_Process WHERE ProcessId = {pid}"))
                {
                    foreach (ManagementObject obj in searcher.Get())
                    {
                        // CommandLine contains the full original command line (exe + all parameters)
                        commandLine = obj["CommandLine"]?.ToString() ?? string.Empty;
                        diskReadBytes = Convert.ToInt64(obj["ReadTransferCount"] ?? 0);
                        diskWriteBytes = Convert.ToInt64(obj["WriteTransferCount"] ?? 0);
                        pageFaults = Convert.ToInt64(obj["PageFaults"] ?? 0);
                    }
                }
            }
            catch (System.Management.ManagementException wmiEx)
            {
                _logger.LogTrace("⚠️ WMI Query FAILED for PID {Pid} (may cause Event 5858): {Error} | Code: {Code}", 
                    pid, wmiEx.Message, wmiEx.ErrorCode);
            }
            catch
            {
                // WMI access denied or other error - skip silently
            }

            // Service association (fast - from cache)
            ServiceMappingCache.ServiceInfo? serviceInfo = null;
            if (serviceMap != null)
            {
                if (serviceMap.TryGetValue(pid, out var service))
                {
                    serviceInfo = service;
                }
                else if (!string.IsNullOrEmpty(executablePath))
                {
                    // Try to match by executable path
                    serviceInfo = serviceMap.Values
                        .FirstOrDefault(s => s.ExecutablePath.Equals(executablePath, StringComparison.OrdinalIgnoreCase));
                }
            }

            return new TopProcess
            {
                Name = name,
                Pid = pid,
                ExecutablePath = executablePath,
                CommandLine = commandLine,
                UserName = userName,
                StartTime = startTime,
                CpuPercent = cpuPercent,
                TotalCpuTime = cpuTime,
                UserCpuTime = userTime,
                KernelCpuTime = kernelTime,
                MemoryMB = memoryMB,
                PrivateMemoryMB = privateMemoryMB,
                VirtualMemoryMB = virtualMemoryMB,
                DiskReadMB = diskReadBytes / 1024.0 / 1024.0, // Convert bytes to MB
                DiskWriteMB = diskWriteBytes / 1024.0 / 1024.0, // Convert bytes to MB
                ThreadCount = threadCount,
                HandleCount = handleCount,
                PageFaults = pageFaults,
                ServiceName = serviceInfo?.ServiceName,
                ServiceDisplayName = serviceInfo?.DisplayName,
                ServiceStatus = serviceInfo?.Status
            };
        }
        catch
        {
            // Access denied or other error for this process - skip silently
            return null;
        }
    }

    private string GetProcessOwner(int processId)
    {
        // NOTE: This WMI query + method invocation could generate Event 5858 if it fails
        try
        {
            _logger.LogTrace("🔍 WMI Query: Win32_Process.GetOwner (CPU) PID={Pid}", processId);
            using (var searcher = new ManagementObjectSearcher(
                $"SELECT * FROM Win32_Process WHERE ProcessId = {processId}"))
            {
                foreach (ManagementObject obj in searcher.Get())
                {
                    var ownerInfo = new string[2];
                    obj.InvokeMethod("GetOwner", ownerInfo);
                    if (!string.IsNullOrEmpty(ownerInfo[0]))
                    {
                        var domain = ownerInfo[1];
                        var user = ownerInfo[0];
                        return string.IsNullOrEmpty(domain) ? user : $"{domain}\\{user}";
                    }
                }
            }
        }
        catch (System.Management.ManagementException wmiEx)
        {
            _logger.LogTrace("⚠️ WMI GetOwner FAILED for PID {Pid} (may cause Event 5858): {Error} | Code: {Code}", 
                processId, wmiEx.Message, wmiEx.ErrorCode);
        }
        catch { }
        
        return string.Empty;
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
            // Dispose PerformanceCounters
            _cpuCounter?.Dispose();
            
            foreach (var counter in _perCoreCounters)
            {
                counter?.Dispose();
            }
            _perCoreCounters.Clear();
            
            _logger.LogDebug("ProcessorMonitor disposed - PerformanceCounters released");
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

