using System.Diagnostics;
using Microsoft.Extensions.Logging;
using Microsoft.Extensions.Options;
using ServerMonitor.Core.Configuration;
using ServerMonitor.Core.Interfaces;
using ServerMonitor.Core.Models;
using ServerMonitor.Core.Services;

namespace ServerMonitor.Core.Monitors;

/// <summary>
/// Monitors IIS sites, application pools, and worker processes.
/// Generates alerts for stopped pools/sites and excessive worker process memory.
/// </summary>
public class IisMonitor : IMonitor
{
    private readonly ILogger<IisMonitor> _logger;
    private readonly IOptionsMonitor<SurveillanceConfiguration> _config;
    private readonly IAlertAccumulator _alertAccumulator;
    private readonly IisDataCollector _collector;
    private MonitorResult? _currentState;

    public string Category => "IIS";
    public bool IsEnabled => _config.CurrentValue.IisMonitoring.Enabled;
    public MonitorResult? CurrentState => _currentState;

    public IisMonitor(
        ILogger<IisMonitor> logger,
        IOptionsMonitor<SurveillanceConfiguration> config,
        IAlertAccumulator alertAccumulator,
        IisDataCollector collector)
    {
        _logger = logger;
        _config = config;
        _alertAccumulator = alertAccumulator;
        _collector = collector;
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

            var settings = _config.CurrentValue.IisMonitoring;
            var computerName = Environment.MachineName;

            if (!settings.IsServerNameMatch(computerName))
            {
                var snapshot = new IisSnapshot
                {
                    IsActive = false,
                    InactiveReason = $"Server name '{computerName}' does not match pattern '{settings.ServerNamePattern}'"
                };

                _currentState = new MonitorResult
                {
                    Category = Category,
                    Success = true,
                    Data = snapshot,
                    CollectionDurationMs = stopwatch.ElapsedMilliseconds
                };
                return _currentState;
            }

            var iisSnapshot = await Task.Run(() => _collector.Collect(), cancellationToken);

            if (iisSnapshot.IsActive)
            {
                alerts.AddRange(GenerateAlerts(iisSnapshot, settings));
            }

            stopwatch.Stop();

            _currentState = new MonitorResult
            {
                Category = Category,
                Success = true,
                Data = iisSnapshot,
                Alerts = alerts,
                CollectionDurationMs = stopwatch.ElapsedMilliseconds
            };

            _logger.LogDebug(
                "IIS collection complete: {Sites} sites, {Pools} pools, {Workers} workers, {Alerts} alerts in {Duration}ms",
                iisSnapshot.TotalSites, iisSnapshot.TotalAppPools, iisSnapshot.TotalWorkerProcesses,
                alerts.Count, stopwatch.ElapsedMilliseconds);

            return _currentState;
        }
        catch (Exception ex)
        {
            _logger.LogError(ex, "IIS monitoring collection failed");
            stopwatch.Stop();

            _currentState = new MonitorResult
            {
                Category = Category,
                Success = false,
                ErrorMessage = ex.Message,
                Alerts = alerts,
                CollectionDurationMs = stopwatch.ElapsedMilliseconds
            };
            return _currentState;
        }
    }

    private List<Alert> GenerateAlerts(IisSnapshot snapshot, IisMonitoringSettings settings)
    {
        var alerts = new List<Alert>();
        var alertSettings = settings.Alerts;

        // Check for stopped application pools that should be running
        if (settings.AlertOnStoppedAppPools)
        {
            foreach (var pool in snapshot.AppPools.Where(p => p.AutoStart && p.State != "Started"))
            {
                var alertKey = $"IIS:AppPool:{pool.Name}:Stopped";
                _alertAccumulator.RecordOccurrence(alertKey, DateTime.UtcNow, alertSettings.TimeWindowMinutes);

                if (_alertAccumulator.ShouldAlert(alertKey, alertSettings.MaxOccurrences, alertSettings.TimeWindowMinutes))
                {
                    var severity = Enum.TryParse<AlertSeverity>(alertSettings.StoppedAppPoolSeverity, true, out var s)
                        ? s : AlertSeverity.Critical;

                    alerts.Add(new Alert
                    {
                        Severity = severity,
                        Category = Category,
                        Message = $"IIS Application Pool '{pool.Name}' is {pool.State} (expected: Started)",
                        Details = $"Pool '{pool.Name}' is configured for AutoStart but current state is {pool.State}. " +
                                  $"Identity: {pool.IdentityType}, Pipeline: {pool.PipelineMode}, Runtime: {(string.IsNullOrEmpty(pool.ManagedRuntimeVersion) ? "No Managed Code" : pool.ManagedRuntimeVersion)}",
                        Metadata = new Dictionary<string, object>
                        {
                            ["AppPoolName"] = pool.Name,
                            ["State"] = pool.State,
                            ["IdentityType"] = pool.IdentityType,
                            ["Component"] = "AppPool"
                        },
                        SuppressedChannels = settings.SuppressedChannels
                    });

                    _alertAccumulator.ClearAfterAlert(alertKey, alertSettings.TimeWindowMinutes);
                }
            }
        }

        // Check for stopped sites
        if (settings.AlertOnStoppedSites)
        {
            foreach (var site in snapshot.Sites.Where(s => s.State != "Started"))
            {
                var alertKey = $"IIS:Site:{site.Name}:Stopped";
                _alertAccumulator.RecordOccurrence(alertKey, DateTime.UtcNow, alertSettings.TimeWindowMinutes);

                if (_alertAccumulator.ShouldAlert(alertKey, alertSettings.MaxOccurrences, alertSettings.TimeWindowMinutes))
                {
                    var severity = Enum.TryParse<AlertSeverity>(alertSettings.StoppedSiteSeverity, true, out var s)
                        ? s : AlertSeverity.Critical;

                    var bindingsSummary = string.Join(", ", site.Bindings.Select(b => b.ToString()));

                    alerts.Add(new Alert
                    {
                        Severity = severity,
                        Category = Category,
                        Message = $"IIS Site '{site.Name}' is {site.State}",
                        Details = $"Site '{site.Name}' (ID: {site.Id}) is {site.State}. " +
                                  $"Bindings: {bindingsSummary}. " +
                                  $"App Pool: {site.AppPoolName}. " +
                                  $"Virtual Apps: {site.VirtualApps.Count}",
                        Metadata = new Dictionary<string, object>
                        {
                            ["SiteName"] = site.Name,
                            ["SiteId"] = site.Id,
                            ["State"] = site.State,
                            ["AppPoolName"] = site.AppPoolName,
                            ["Component"] = "Site"
                        },
                        SuppressedChannels = settings.SuppressedChannels
                    });

                    _alertAccumulator.ClearAfterAlert(alertKey, alertSettings.TimeWindowMinutes);
                }
            }
        }

        // Check worker process memory
        if (settings.WorkerProcessMemoryThresholdMB > 0)
        {
            foreach (var pool in snapshot.AppPools)
            {
                foreach (var wp in pool.WorkerProcesses.Where(w => w.PrivateMemoryMB > settings.WorkerProcessMemoryThresholdMB))
                {
                    var alertKey = $"IIS:WorkerProcess:{wp.ProcessId}:Memory";
                    _alertAccumulator.RecordOccurrence(alertKey, DateTime.UtcNow, alertSettings.TimeWindowMinutes);

                    if (_alertAccumulator.ShouldAlert(alertKey, alertSettings.MaxOccurrences, alertSettings.TimeWindowMinutes))
                    {
                        var severity = Enum.TryParse<AlertSeverity>(alertSettings.WorkerProcessMemorySeverity, true, out var s)
                            ? s : AlertSeverity.Warning;

                        alerts.Add(new Alert
                        {
                            Severity = severity,
                            Category = Category,
                            Message = $"IIS Worker Process (PID {wp.ProcessId}) for pool '{pool.Name}' using {wp.PrivateMemoryMB:N0} MB (threshold: {settings.WorkerProcessMemoryThresholdMB} MB)",
                            Details = $"Worker process PID {wp.ProcessId} in app pool '{pool.Name}' is consuming {wp.PrivateMemoryMB:N0} MB private memory, " +
                                      $"exceeding the threshold of {settings.WorkerProcessMemoryThresholdMB} MB.",
                            Metadata = new Dictionary<string, object>
                            {
                                ["AppPoolName"] = pool.Name,
                                ["ProcessId"] = wp.ProcessId,
                                ["MemoryMB"] = wp.PrivateMemoryMB,
                                ["ThresholdMB"] = settings.WorkerProcessMemoryThresholdMB,
                                ["Component"] = "WorkerProcess"
                            },
                            SuppressedChannels = settings.SuppressedChannels
                        });

                        _alertAccumulator.ClearAfterAlert(alertKey, alertSettings.TimeWindowMinutes);
                    }
                }
            }
        }

        return alerts;
    }
}
