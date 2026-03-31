using System.Diagnostics;
using System.Runtime.InteropServices;
using Microsoft.Extensions.Logging;
using Microsoft.Extensions.Options;
using ServerMonitor.Core.Configuration;
using ServerMonitor.Core.Interfaces;
using ServerMonitor.Core.Models;
using ServerMonitor.Core.Services;

namespace ServerMonitor.Core.Monitors;

/// <summary>
/// Monitors Windows Update status.
/// Uses AlertAccumulator for deduplication and cooldown management.
/// </summary>
public class WindowsUpdateMonitor : IMonitor
{
    private readonly ILogger<WindowsUpdateMonitor> _logger;
    private readonly IOptionsMonitor<SurveillanceConfiguration> _config;
    private readonly IAlertAccumulator _alertAccumulator;
    private MonitorResult? _currentState;

    public string Category => "WindowsUpdate";
    public bool IsEnabled => _config.CurrentValue.WindowsUpdateMonitoring.Enabled;
    public MonitorResult? CurrentState => _currentState;

    public WindowsUpdateMonitor(
        ILogger<WindowsUpdateMonitor> logger,
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

            var settings = _config.CurrentValue.WindowsUpdateMonitoring;

            var (updateData, updateAlerts) = await GetWindowsUpdateDataAsync(settings, _alertAccumulator, cancellationToken);
            alerts.AddRange(updateAlerts);

            stopwatch.Stop();

            var result = new MonitorResult
            {
                Category = Category,
                Success = true,
                Data = updateData,
                Alerts = alerts,
                CollectionDurationMs = stopwatch.ElapsedMilliseconds
            };

            _currentState = result;
            return result;
        }
        catch (Exception ex)
        {
            _logger.LogError(ex, "Error collecting Windows Update metrics");
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

    private async Task<(WindowsUpdateData data, List<Alert> alerts)> GetWindowsUpdateDataAsync(
        WindowsUpdateMonitoringSettings settings,
        IAlertAccumulator alertAccumulator,
        CancellationToken cancellationToken)
    {
        return await Task.Run(() =>
        {
            var alerts = new List<Alert>();
            var maxOccurrences = settings.Alerts.MaxOccurrences;
            var timeWindowMinutes = settings.Alerts.TimeWindowMinutes;
            
            try
            {
                // Use dynamic COM interop for Windows Update API
                Type? updateSessionType = Type.GetTypeFromProgID("Microsoft.Update.Session");
                if (updateSessionType == null)
                {
                    _logger.LogWarning("Windows Update API not available");
                    return (new WindowsUpdateData { PendingCount = -1 }, alerts);
                }

                dynamic updateSession = Activator.CreateInstance(updateSessionType)!;
                dynamic updateSearcher = updateSession.CreateUpdateSearcher();

                // Search for pending updates
                dynamic searchResult = updateSearcher.Search("IsInstalled=0 and IsHidden=0");

                var pendingCount = (int)searchResult.Updates.Count;
                var securityUpdates = 0;
                var criticalUpdates = 0;
                var pendingUpdateNames = new List<string>();

                foreach (dynamic update in searchResult.Updates)
                {
                    try
                    {
                        // Get update title/name
                        string? updateTitle = update.Title;
                        if (!string.IsNullOrEmpty(updateTitle))
                        {
                            pendingUpdateNames.Add(updateTitle);
                        }

                        foreach (dynamic category in update.Categories)
                        {
                            string categoryName = category.Name;
                            if (categoryName.Contains("Security", StringComparison.OrdinalIgnoreCase))
                            {
                                securityUpdates++;
                                break;
                            }
                        }

                        string? severity = update.MsrcSeverity;
                        if (severity != null && severity.Equals("Critical", StringComparison.OrdinalIgnoreCase))
                        {
                            criticalUpdates++;
                        }
                    }
                    catch
                    {
                        // Skip updates we can't parse
                    }
                }

                // Get last installation date
                DateTime? lastInstallDate = null;
                try
                {
                    dynamic installedSearchResult = updateSearcher.Search("IsInstalled=1");
                    if (installedSearchResult.Updates.Count > 0)
                    {
                        DateTime? latestDate = null;
                        foreach (dynamic update in installedSearchResult.Updates)
                        {
                            try
                            {
                                DateTime? deployTime = update.LastDeploymentChangeTime;
                                if (deployTime.HasValue && (!latestDate.HasValue || deployTime.Value > latestDate.Value))
                                {
                                    latestDate = deployTime.Value;
                                }
                            }
                            catch
                            {
                                // Skip if can't get date
                            }
                        }
                        lastInstallDate = latestDate;
                    }
                }
                catch (Exception ex)
                {
                    _logger.LogWarning(ex, "Failed to get last update install date");
                }

                // Release COM objects
                if (updateSession != null) Marshal.ReleaseComObject(updateSession);
                if (updateSearcher != null) Marshal.ReleaseComObject(updateSearcher);

                // Get failed updates count
                var failedUpdates = 0;
                try
                {
                    using var eventLog = new EventLog("System");
                    failedUpdates = eventLog.Entries.Cast<EventLogEntry>()
                        .Count(e => e.Source == "Microsoft-Windows-WindowsUpdateClient" && 
                                   e.InstanceId == 20 && 
                                   e.TimeGenerated > DateTime.Now.AddDays(-30));
                }
                catch (Exception ex)
                {
                    _logger.LogWarning(ex, "Failed to get failed updates count");
                }

                var data = new WindowsUpdateData
                {
                    PendingCount = pendingCount,
                    SecurityUpdates = securityUpdates,
                    CriticalUpdates = criticalUpdates,
                    LastInstallDate = lastInstallDate,
                    FailedUpdates = failedUpdates,
                    PendingUpdateNames = pendingUpdateNames
                };

                // Check for alerts (using accumulator for deduplication/cooldown)
                if (settings.Alerts.AlertOnPendingSecurityUpdates && 
                    securityUpdates > settings.Thresholds.MaxPendingSecurityUpdates)
                {
                    const string alertKey = "WindowsUpdate:SecurityUpdates";
                    
                    // Record occurrence in accumulator
                    alertAccumulator.RecordOccurrence(alertKey, DateTime.UtcNow, timeWindowMinutes);
                    
                    // Check if we should alert
                    if (alertAccumulator.ShouldAlert(alertKey, maxOccurrences, timeWindowMinutes))
                    {
                        // Parse severity from settings, default to Warning
                        var securitySeverity = ParseAlertSeverity(settings.Alerts.SecurityUpdateAlertSeverity, AlertSeverity.Warning);
                        
                        alerts.Add(new Alert
                        {
                            Severity = securitySeverity,
                            Category = Category,
                            Message = $"{securityUpdates} pending security update(s)",
                            Details = "Security updates should be installed as soon as possible",
                            SuppressedChannels = settings.SuppressedChannels ?? new List<string>()
                        });
                        
                        alertAccumulator.ClearAfterAlert(alertKey, timeWindowMinutes);
                    }
                }

                if (criticalUpdates > settings.Thresholds.MaxPendingCriticalUpdates)
                {
                    const string alertKey = "WindowsUpdate:CriticalUpdates";
                    
                    // Record occurrence in accumulator
                    alertAccumulator.RecordOccurrence(alertKey, DateTime.UtcNow, timeWindowMinutes);
                    
                    // Check if we should alert
                    if (alertAccumulator.ShouldAlert(alertKey, maxOccurrences, timeWindowMinutes))
                    {
                        // Parse severity from settings, default to Warning
                        var criticalSeverity = ParseAlertSeverity(settings.Alerts.CriticalUpdateAlertSeverity, AlertSeverity.Warning);
                        
                        alerts.Add(new Alert
                        {
                            Severity = criticalSeverity,
                            Category = Category,
                            Message = $"{criticalUpdates} pending critical update(s)",
                            Details = "Critical updates should be installed immediately",
                            SuppressedChannels = settings.SuppressedChannels ?? new List<string>()
                        });
                        
                        alertAccumulator.ClearAfterAlert(alertKey, timeWindowMinutes);
                    }
                }

                if (lastInstallDate.HasValue)
                {
                    var daysSinceUpdate = (DateTime.Now - lastInstallDate.Value).TotalDays;
                    if (daysSinceUpdate > settings.Thresholds.MaxDaysSinceLastUpdate)
                    {
                        const string alertKey = "WindowsUpdate:DaysSinceLastUpdate";
                        
                        // Record occurrence in accumulator
                        alertAccumulator.RecordOccurrence(alertKey, DateTime.UtcNow, timeWindowMinutes);
                        
                        // Check if we should alert
                        if (alertAccumulator.ShouldAlert(alertKey, maxOccurrences, timeWindowMinutes))
                        {
                            alerts.Add(new Alert
                            {
                                Severity = ParseAlertSeverity(settings.Alerts.DaysSinceLastUpdateSeverity, AlertSeverity.Warning),
                                Category = Category,
                                Message = $"No updates installed in {daysSinceUpdate:F0} days",
                                Details = $"Last update was installed on {lastInstallDate.Value:yyyy-MM-dd}",
                                SuppressedChannels = settings.SuppressedChannels ?? new List<string>()
                            });
                            
                            alertAccumulator.ClearAfterAlert(alertKey, timeWindowMinutes);
                        }
                    }
                }

                // Note: AlertOnFailedInstallations is kept for backward compatibility but not used
                // We only alert on pending updates, not historical failures
                // Failed updates are tracked in data but don't generate alerts

                return (data, alerts);
            }
            catch (Exception ex)
            {
                _logger.LogError(ex, "Error querying Windows Update");
                
                var data = new WindowsUpdateData
                {
                    PendingCount = -1, // Indicate error
                    SecurityUpdates = 0,
                    CriticalUpdates = 0,
                    FailedUpdates = 0
                };

                return (data, alerts);
            }
        }, cancellationToken);
    }
    
    /// <summary>
    /// Parse alert severity from string configuration value.
    /// </summary>
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

