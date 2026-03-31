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
/// Monitors physical memory usage.
/// Uses AlertAccumulator for deduplication and cooldown management.
/// </summary>
public class MemoryMonitor : IMonitor, IDisposable
{
    private bool _disposed;
    private readonly ILogger<MemoryMonitor> _logger;
    private readonly IOptionsMonitor<SurveillanceConfiguration> _config;
    private readonly IAlertAccumulator _alertAccumulator;
    private readonly PerformanceCounter _availableMemoryCounter;
    // Rolling window of memory measurements for average calculation
    private readonly List<(DateTime timestamp, double value)> _memoryMeasurements = new();
    private readonly object _measurementsLock = new object();
    private MonitorResult? _currentState;
    
    // Process monitoring caches (Option 2: Cached + Periodic)
    private readonly ProcessCache _processCache;
    private readonly ServiceMappingCache _serviceMappingCache;
    private readonly ProcessCpuTracker _cpuTracker;

    public string Category => "Memory";
    public bool IsEnabled => _config.CurrentValue.MemoryMonitoring.Enabled;
    public MonitorResult? CurrentState => _currentState;

    public MemoryMonitor(
        ILogger<MemoryMonitor> logger,
        ILoggerFactory loggerFactory,
        IOptionsMonitor<SurveillanceConfiguration> config,
        IAlertAccumulator alertAccumulator)
    {
        _logger = logger;
        _config = config;
        _alertAccumulator = alertAccumulator;

        // Initialize performance counter
        _availableMemoryCounter = new PerformanceCounter("Memory", "Available MBytes");
        _availableMemoryCounter.NextValue(); // Prime the counter

        // Initialize process monitoring caches
        var settings = config.CurrentValue.MemoryMonitoring;
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

            var settings = _config.CurrentValue.MemoryMonitoring;

            await Task.Delay(100, cancellationToken);

            // Get total memory using WMI
            // NOTE: This WMI query could generate Event 5858 if it fails
            double totalMemory = 0;
            const string wmiQueryTotalMem = "SELECT TotalPhysicalMemory FROM Win32_ComputerSystem";
            try
            {
                _logger.LogTrace("🔍 WMI Query: {Query} (namespace: root\\cimv2)", wmiQueryTotalMem);
                var wmiStart = System.Diagnostics.Stopwatch.StartNew();
                
                using (var searcher = new System.Management.ManagementObjectSearcher(wmiQueryTotalMem))
                {
                    foreach (System.Management.ManagementObject obj in searcher.Get())
                    {
                        totalMemory = Convert.ToDouble(obj["TotalPhysicalMemory"]) / 1024 / 1024 / 1024; // GB
                    }
                }
                
                wmiStart.Stop();
                _logger.LogTrace("✅ WMI Query completed in {Ms}ms: {Query}", wmiStart.ElapsedMilliseconds, wmiQueryTotalMem);
            }
            catch (System.Management.ManagementException wmiEx)
            {
                _logger.LogWarning("⚠️ WMI Query FAILED (may cause Event 5858): {Query} | Error: {Error} | Code: {Code}", 
                    wmiQueryTotalMem, wmiEx.Message, wmiEx.ErrorCode);
            }
            catch (Exception ex)
            {
                _logger.LogWarning(ex, "⚠️ WMI Query FAILED: {Query}", wmiQueryTotalMem);
            }

            // Get available memory
            var availableMemoryMB = _availableMemoryCounter.NextValue();
            var availableMemory = availableMemoryMB / 1024; // GB
            var usedPercent = ((totalMemory - availableMemory) / totalMemory) * 100;

            // Store current measurement with timestamp
            var now = DateTime.UtcNow;
            lock (_measurementsLock)
            {
                _memoryMeasurements.Add((now, usedPercent));
                
                // Remove measurements older than SustainedDurationSeconds
                var cutoffTime = now.AddSeconds(-settings.Thresholds.SustainedDurationSeconds);
                _memoryMeasurements.RemoveAll(m => m.timestamp < cutoffTime);
            }

            // Calculate average over the sustained duration period
            double averageUsedPercent;
            int measurementCount;
            lock (_measurementsLock)
            {
                if (_memoryMeasurements.Count == 0)
                {
                    averageUsedPercent = usedPercent;
                    measurementCount = 1;
                }
                else
                {
                    averageUsedPercent = _memoryMeasurements.Average(m => m.value);
                    measurementCount = _memoryMeasurements.Count;
                }
            }
            
            _logger.LogTrace("Memory: Current={Current:F1}%, Average over {Duration}s={Average:F1}% ({Count} measurements)", 
                usedPercent, settings.Thresholds.SustainedDurationSeconds, averageUsedPercent, measurementCount);

            // Get top memory consuming processes
            var topProcesses = GetTopMemoryProcesses(settings.TrackTopProcesses);

            // Check for alerts - only trigger if average over sustained duration exceeds threshold
            // Need at least SustainedDurationSeconds worth of measurements
            var requiredMeasurements = (int)Math.Ceiling(settings.Thresholds.SustainedDurationSeconds / (double)settings.PollingIntervalSeconds);
            
            var maxOccurrences = settings.Alerts.MaxOccurrences;
            var timeWindowMinutes = settings.Alerts.TimeWindowMinutes;
            
            // CRITICAL: Do not alert until we have enough measurements to cover the full SustainedDurationSeconds period
            if (measurementCount < requiredMeasurements)
            {
                _logger.LogDebug("Skipping Memory alert check: Only {Count} measurements available, need {Required} for {Duration}s sustained duration (PollingInterval: {Interval}s)", 
                    measurementCount, requiredMeasurements, settings.Thresholds.SustainedDurationSeconds, settings.PollingIntervalSeconds);
            }
            else if (measurementCount >= requiredMeasurements)
            {
                if (averageUsedPercent >= settings.Thresholds.CriticalPercent)
                {
                    const string alertKey = "Memory:Critical";
                    
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
                            Message = $"Memory usage critical: {averageUsedPercent:F1}% (average)",
                            Details = $"Memory usage average over {settings.Thresholds.SustainedDurationSeconds} seconds is {averageUsedPercent:F1}%, exceeding critical threshold of {settings.Thresholds.CriticalPercent}% (based on {measurementCount} measurements, current: {usedPercent:F1}%, available: {availableMemory:F2} GB). Occurred {count} times in the last {timeWindowMinutes} minutes.",
                            SuppressedChannels = settings.SuppressedChannels ?? new List<string>()
                        });
                        
                        // Clear accumulator after alert to start cooldown
                        _alertAccumulator.ClearAfterAlert(alertKey, timeWindowMinutes);
                    }
                }
                else if (averageUsedPercent >= settings.Thresholds.WarningPercent)
                {
                    const string alertKey = "Memory:Warning";
                    
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
                            Message = $"Memory usage sustained above warning level: {averageUsedPercent:F1}% (average)",
                            Details = $"Memory usage average over {settings.Thresholds.SustainedDurationSeconds} seconds is {averageUsedPercent:F1}%, exceeding warning threshold of {settings.Thresholds.WarningPercent}% (based on {measurementCount} measurements, current: {usedPercent:F1}%, available: {availableMemory:F2} GB). Occurred {count} times in the last {timeWindowMinutes} minutes.",
                            SuppressedChannels = settings.SuppressedChannels ?? new List<string>()
                        });
                        
                        // Clear accumulator after alert to start cooldown
                        _alertAccumulator.ClearAfterAlert(alertKey, timeWindowMinutes);
                    }
                }
            }

            // Alert if available memory is very low (< 500 MB)
            if (availableMemoryMB < 500)
            {
                const string alertKey = "Memory:CriticallyLow";
                
                // Record occurrence in accumulator
                _alertAccumulator.RecordOccurrence(alertKey, DateTime.UtcNow, timeWindowMinutes);
                
                // Check if we should alert (using accumulator for deduplication/cooldown)
                if (_alertAccumulator.ShouldAlert(alertKey, maxOccurrences, timeWindowMinutes))
                {
                    alerts.Add(new Alert
                    {
                        Severity = ParseAlertSeverity(settings.Alerts.CriticalAlertSeverity, AlertSeverity.Critical),
                        Category = Category,
                        Message = $"Available memory critically low: {availableMemoryMB:F0} MB",
                        Details = "System may experience severe performance degradation",
                        SuppressedChannels = settings.SuppressedChannels ?? new List<string>()
                    });
                    
                    // Clear accumulator after alert to start cooldown
                    _alertAccumulator.ClearAfterAlert(alertKey, timeWindowMinutes);
                }
            }

            // Get history for export
            List<MeasurementHistory> memoryHistory;
            lock (_measurementsLock)
            {
                memoryHistory = _memoryMeasurements.Select(m => new MeasurementHistory
                {
                    Timestamp = m.timestamp,
                    Value = m.value
                }).ToList();
            }

            var data = new MemoryData
            {
                TotalGB = totalMemory,
                AvailableGB = availableMemory,
                UsedPercent = usedPercent,
                TimeAboveThresholdSeconds = measurementCount >= requiredMeasurements && averageUsedPercent >= settings.Thresholds.WarningPercent ? settings.Thresholds.SustainedDurationSeconds : 0,
                TopProcesses = topProcesses,
                MemoryUsageHistory = memoryHistory
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
            _logger.LogError(ex, "Error collecting memory metrics");
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

    private List<TopProcess> GetTopMemoryProcesses(int count)
    {
        try
        {
            var settings = _config.CurrentValue.MemoryMonitoring;
            var processes = _processCache.GetProcesses();
            
            // First pass: Get basic metrics (fast) - get more candidates than needed
            var processMetrics = processes
                .Select(p =>
                {
                    try
                    {
                        if (p.HasExited) return null;
                        
                        var memoryMB = p.WorkingSet64 / 1024 / 1024;
                        
                        return new
                        {
                            Process = p,
                            MemoryMB = memoryMB
                        };
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
                    catch
                    {
                        // Unexpected error - skip this process silently
                        return null;
                    }
                })
                .Where(p => p != null)
                .OrderByDescending(p => p!.MemoryMB)
                .Take(count * 2) // Get more candidates for metadata extraction
                .ToList();

            // Second pass: Get detailed metadata only for top candidates (slower)
            var serviceMap = settings.EnhancedProcessMetadata ? _serviceMappingCache.GetServiceMap() : null;
            var topProcesses = processMetrics
                .Select(p => settings.EnhancedProcessMetadata 
                    ? GetProcessMetadata(p!.Process, serviceMap!)
                    : GetBasicProcessInfo(p!.Process))
                .Where(p => p != null)
                .OrderByDescending(p => p!.MemoryMB)
                .Take(count)
                .ToList();

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
            
            // Calculate CPU percent using the tracker (requires two measurements over time)
            var cpuPercent = _cpuTracker.CalculateCpuPercent(process, 
                TimeSpan.FromSeconds(_config.CurrentValue.MemoryMonitoring.PollingIntervalSeconds));
            
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
            var memoryMB = process.WorkingSet64 / 1024 / 1024;
            var privateMemoryMB = process.PrivateMemorySize64 / 1024 / 1024;
            var virtualMemoryMB = process.VirtualMemorySize64 / 1024 / 1024;
            
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

            // WMI for advanced metrics including command line (slow - ~50-100ms per process)
            // NOTE: This WMI query could generate Event 5858 if it fails
            long diskReadBytes = 0;
            long diskWriteBytes = 0;
            long pageFaults = 0;
            // CommandLine from WMI includes full command: executable path + all parameters
            // Example: "C:\Program Files\App\app.exe" --param1 value1 --param2
            string commandLine = string.Empty;
            var wmiQueryProcess = $"SELECT CommandLine, ReadTransferCount, WriteTransferCount, PageFaults FROM Win32_Process WHERE ProcessId = {pid}";

            try
            {
                _logger.LogTrace("🔍 WMI Query: Win32_Process PID={Pid}", pid);
                using (var searcher = new ManagementObjectSearcher(wmiQueryProcess))
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

            // Calculate CPU percent using the tracker (requires two measurements over time)
            var cpuPercent = _cpuTracker.CalculateCpuPercent(process, 
                TimeSpan.FromSeconds(_config.CurrentValue.MemoryMonitoring.PollingIntervalSeconds));

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
            _logger.LogTrace("🔍 WMI Query: Win32_Process.GetOwner for PID={Pid}", processId);
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
            _availableMemoryCounter?.Dispose();
            _logger.LogDebug("MemoryMonitor disposed - PerformanceCounter released");
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

