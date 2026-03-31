using System.Diagnostics;
using System.Management;
using Microsoft.Extensions.Logging;
using Microsoft.Extensions.Options;
using ServerMonitor.Core.Configuration;
using ServerMonitor.Core.Interfaces;
using ServerMonitor.Core.Models;
using ServerMonitor.Core.Services;

namespace ServerMonitor.Core.Monitors;

/// <summary>
/// Monitors system uptime and boot events.
/// Uses AlertAccumulator for deduplication and cooldown management.
/// </summary>
public class UptimeMonitor : IMonitor
{
    private readonly ILogger<UptimeMonitor> _logger;
    private readonly IOptionsMonitor<SurveillanceConfiguration> _config;
    private readonly IAlertAccumulator _alertAccumulator;
    private DateTime? _lastKnownBootTime;
    private MonitorResult? _currentState;

    public string Category => "Uptime";
    public bool IsEnabled => _config.CurrentValue.UptimeMonitoring.Enabled;
    public MonitorResult? CurrentState => _currentState;

    public UptimeMonitor(
        ILogger<UptimeMonitor> logger,
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

            var settings = _config.CurrentValue.UptimeMonitoring;

            // Get last boot time using WMI
            var lastBootTime = await GetLastBootTimeAsync(cancellationToken);
            var currentUptime = DateTime.UtcNow - lastBootTime;
            var uptimeDays = currentUptime.TotalDays;

            var maxOccurrences = settings.Alerts.MaxOccurrences;
            var timeWindowMinutes = settings.Alerts.TimeWindowMinutes;
            
            // Check for unexpected reboot
            var unexpectedReboot = false;
            if (_lastKnownBootTime.HasValue && _lastKnownBootTime.Value != lastBootTime)
            {
                unexpectedReboot = true;
                
                if (settings.Alerts.UnexpectedRebootAlert)
                {
                    const string alertKey = "Uptime:UnexpectedReboot";
                    
                    // Record occurrence in accumulator
                    _alertAccumulator.RecordOccurrence(alertKey, DateTime.UtcNow, timeWindowMinutes);
                    
                    // Check if we should alert
                    if (_alertAccumulator.ShouldAlert(alertKey, maxOccurrences, timeWindowMinutes))
                    {
                        alerts.Add(new Alert
                        {
                            Severity = ParseAlertSeverity(settings.Alerts.UnexpectedRebootSeverity, AlertSeverity.Critical),
                            Category = Category,
                            Message = "Unexpected system reboot detected",
                            Details = $"System rebooted at {lastBootTime:yyyy-MM-dd HH:mm:ss}. Previous boot was {_lastKnownBootTime.Value:yyyy-MM-dd HH:mm:ss}",
                            SuppressedChannels = settings.SuppressedChannels ?? new List<string>()
                        });
                        
                        _alertAccumulator.ClearAfterAlert(alertKey, timeWindowMinutes);
                    }
                }
            }

            _lastKnownBootTime = lastBootTime;

            // Check uptime thresholds
            if (uptimeDays > settings.Alerts.MaximumUptimeDaysWarning)
            {
                const string alertKey = "Uptime:ExcessiveUptime";
                
                // Record occurrence in accumulator
                _alertAccumulator.RecordOccurrence(alertKey, DateTime.UtcNow, timeWindowMinutes);
                
                // Check if we should alert
                if (_alertAccumulator.ShouldAlert(alertKey, maxOccurrences, timeWindowMinutes))
                {
                    alerts.Add(new Alert
                    {
                        Severity = ParseAlertSeverity(settings.Alerts.ExcessiveUptimeSeverity, AlertSeverity.Warning),
                        Category = Category,
                        Message = $"System uptime excessive: {uptimeDays:F1} days",
                        Details = $"System has been running for {uptimeDays:F1} days without restart. Consider rebooting for pending updates.",
                        SuppressedChannels = settings.SuppressedChannels ?? new List<string>()
                    });
                    
                    _alertAccumulator.ClearAfterAlert(alertKey, timeWindowMinutes);
                }
            }

            // Check for dirty shutdown
            var dirtyShutdown = await CheckForDirtyShutdownAsync(cancellationToken);
            if (dirtyShutdown)
            {
                const string alertKey = "Uptime:DirtyShutdown";
                
                // Record occurrence in accumulator
                _alertAccumulator.RecordOccurrence(alertKey, DateTime.UtcNow, timeWindowMinutes);
                
                // Check if we should alert
                if (_alertAccumulator.ShouldAlert(alertKey, maxOccurrences, timeWindowMinutes))
                {
                    alerts.Add(new Alert
                    {
                        Severity = ParseAlertSeverity(settings.Alerts.DirtyShutdownSeverity, AlertSeverity.Warning),
                        Category = Category,
                        Message = "Dirty shutdown detected",
                        Details = "Last shutdown was not clean. Check event logs for details.",
                        SuppressedChannels = settings.SuppressedChannels ?? new List<string>()
                    });
                    
                    _alertAccumulator.ClearAfterAlert(alertKey, timeWindowMinutes);
                }
            }

            var data = new UptimeData
            {
                LastBootTime = lastBootTime,
                CurrentUptimeDays = uptimeDays,
                UnexpectedReboot = unexpectedReboot
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
            _logger.LogError(ex, "Error collecting uptime metrics");
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

    private async Task<DateTime> GetLastBootTimeAsync(CancellationToken cancellationToken)
    {
        return await Task.Run(() =>
        {
            // NOTE: This WMI query could generate Event 5858 if it fails
            const string wmiQuery = "SELECT LastBootUpTime FROM Win32_OperatingSystem";
            try
            {
                _logger.LogTrace("🔍 WMI Query: {Query} (namespace: root\\cimv2)", wmiQuery);
                var wmiStart = System.Diagnostics.Stopwatch.StartNew();
                
                using var searcher = new ManagementObjectSearcher(wmiQuery);
                using var collection = searcher.Get();
                
                foreach (ManagementObject mo in collection)
                {
                    var bootTimeStr = mo["LastBootUpTime"]?.ToString();
                    if (bootTimeStr != null)
                    {
                        wmiStart.Stop();
                        _logger.LogTrace("✅ WMI Query completed in {Ms}ms: Win32_OperatingSystem (Uptime)", wmiStart.ElapsedMilliseconds);
                        return ManagementDateTimeConverter.ToDateTime(bootTimeStr).ToUniversalTime();
                    }
                }
            }
            catch (System.Management.ManagementException wmiEx)
            {
                _logger.LogWarning("⚠️ WMI Query FAILED (may cause Event 5858): {Query} | Error: {Error} | Code: {Code}", 
                    wmiQuery, wmiEx.Message, wmiEx.ErrorCode);
            }
            catch (Exception ex)
            {
                _logger.LogWarning(ex, "Failed to get boot time from WMI, using uptime");
            }

            // Fallback to Environment.TickCount (less accurate)
            var uptimeMs = Environment.TickCount64;
            return DateTime.UtcNow.AddMilliseconds(-uptimeMs);
        }, cancellationToken);
    }

    private async Task<bool> CheckForDirtyShutdownAsync(CancellationToken cancellationToken)
    {
        return await Task.Run(() =>
        {
            try
            {
                // Check for Event ID 6008 (unexpected shutdown)
                using var eventLog = new EventLog("System");
                var entries = eventLog.Entries.Cast<EventLogEntry>()
                    .Where(e => e.InstanceId == 6008 && 
                               e.TimeGenerated > DateTime.Now.AddDays(-7))
                    .OrderByDescending(e => e.TimeGenerated)
                    .Take(1)
                    .ToList();

                return entries.Count > 0;
            }
            catch (Exception ex)
            {
                _logger.LogWarning(ex, "Failed to check for dirty shutdown");
                return false;
            }
        }, cancellationToken);
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

