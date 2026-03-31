using System.Diagnostics;
using Microsoft.Extensions.Logging;
using Microsoft.Extensions.Options;
using ServerMonitor.Core.Configuration;
using ServerMonitor.Core.Interfaces;
using ServerMonitor.Core.Models;

namespace ServerMonitor.Core.Monitors;

/// <summary>
/// Monitors Windows Event Logs for specific events
/// 
/// NOTE: This polling-based monitor has been replaced by EventLogWatcherService
/// which uses real-time EventLogWatcher for immediate event detection.
/// The polling code is commented out but preserved for reference/fallback.
/// </summary>
public class EventLogMonitor : IMonitor
{
    private readonly ILogger<EventLogMonitor> _logger;
    private readonly IOptionsMonitor<SurveillanceConfiguration> _config;
    private MonitorResult? _currentState;

    public string Category => "EventLog";
    
    // DISABLED: Event monitoring is now handled by EventLogWatcherService (real-time)
    // Returning false here prevents the SurveillanceWorker from calling CollectAsync
    public bool IsEnabled => false; // Was: _config.CurrentValue.EventMonitoring.Enabled;
    
    public MonitorResult? CurrentState => _currentState;

    public EventLogMonitor(
        ILogger<EventLogMonitor> logger,
        IOptionsMonitor<SurveillanceConfiguration> config)
    {
        _logger = logger;
        _config = config;
        
        _logger.LogInformation("EventLogMonitor: Polling-based monitoring disabled. Using EventLogWatcherService for real-time monitoring.");
    }

    public async Task<MonitorResult> CollectAsync(CancellationToken cancellationToken = default)
    {
        // NOTE: This method is now disabled (IsEnabled = false) because event monitoring
        // is handled by EventLogWatcherService using real-time EventLogWatcher.
        // The code below is preserved for reference and potential fallback.

        var stopwatch = Stopwatch.StartNew();
        stopwatch.Stop();

        var result = new MonitorResult
        {
            Category = Category,
            Success = true,
            ErrorMessage = "Polling disabled - using EventLogWatcherService for real-time monitoring",
            CollectionDurationMs = stopwatch.ElapsedMilliseconds
        };

        _currentState = result;
        return await Task.FromResult(result);

        #region OLD POLLING CODE - PRESERVED FOR REFERENCE
        /*
        var alerts = new List<Alert>();
        var eventData = new List<EventData>();

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

            var settings = _config.CurrentValue.EventMonitoring;

            // Filter to only enabled events
            var enabledEvents = settings.EventsToMonitor.Where(e => e.Enabled).ToList();
            
            _logger.LogDebug("Event monitoring: {EnabledCount} of {TotalCount} events enabled",
                enabledEvents.Count, settings.EventsToMonitor.Count);

            foreach (var eventConfig in enabledEvents)
            {
                var eventResult = await CheckEventAsync(eventConfig, cancellationToken).ConfigureAwait(false);
                if (eventResult.data != null)
                {
                    eventData.Add(eventResult.data);
                }
                alerts.AddRange(eventResult.alerts);
            }

            stopwatch.Stop();

            var result = new MonitorResult
            {
                Category = Category,
                Success = true,
                Data = eventData,
                Alerts = alerts,
                CollectionDurationMs = stopwatch.ElapsedMilliseconds
            };

            _currentState = result;
            return result;
        }
        catch (Exception ex)
        {
            _logger.LogError(ex, "Error collecting event log metrics");
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
        */
        #endregion
    }

    #region OLD POLLING CODE - PRESERVED FOR REFERENCE
    /*
    private async System.Threading.Tasks.Task<(EventData? data, List<Alert> alerts)> CheckEventAsync(
        EventToMonitor eventConfig,
        CancellationToken cancellationToken)
    {
        return await Task.Run(() =>
        {
            var alerts = new List<Alert>();

            try
            {
                // Check if the event log exists before trying to access it
                if (!EventLog.Exists(eventConfig.LogName))
                {
                    _logger.LogDebug("Event log '{LogName}' does not exist on this system. Skipping event {EventId}.", 
                        eventConfig.LogName, eventConfig.EventId);
                    return ((EventData?)null, alerts);
                }

                using var eventLog = new EventLog(eventConfig.LogName);
                
                var timeWindow = DateTime.Now.AddMinutes(-eventConfig.TimeWindowMinutes);
                
                var matchingEntries = eventLog.Entries.Cast<EventLogEntry>()
                    .Where(e => e.InstanceId == eventConfig.EventId &&
                               e.TimeGenerated >= timeWindow &&
                               (string.IsNullOrEmpty(eventConfig.Source) || e.Source == eventConfig.Source))
                    .OrderByDescending(e => e.TimeGenerated)
                    .ToList();

                var count = matchingEntries.Count;
                var lastOccurrence = matchingEntries.FirstOrDefault()?.TimeGenerated;
                var message = matchingEntries.FirstOrDefault()?.Message ?? string.Empty;

                // Truncate message if too long
                if (message.Length > 200)
                {
                    message = message.Substring(0, 200) + "...";
                }

                var data = new EventData
                {
                    EventId = eventConfig.EventId,
                    Source = eventConfig.Source,
                    Level = eventConfig.Level,
                    Count = count,
                    LastOccurrence = lastOccurrence,
                    Message = message
                };

                // Check for alerts
                if (count > eventConfig.MaxOccurrences)
                {
                    var severity = eventConfig.Level.Equals("Critical", StringComparison.OrdinalIgnoreCase) 
                        ? AlertSeverity.Critical 
                        : AlertSeverity.Warning;

                    var details = $"{eventConfig.Description}: Occurred {count} times in the last {eventConfig.TimeWindowMinutes} minutes (threshold: {eventConfig.MaxOccurrences})";
                    if (!string.IsNullOrEmpty(message))
                    {
                        details += $"\nEvent Message: {message}";
                    }

                    alerts.Add(new Alert
                    {
                        Severity = severity,
                        Category = Category,
                        Message = $"Event {eventConfig.EventId} occurred {count} times",
                        Details = details,
                        SuppressedChannels = eventConfig.SuppressedChannels ?? new List<string>()
                    });
                }
                else if (eventConfig.Level.Equals("Critical", StringComparison.OrdinalIgnoreCase) && count > 0)
                {
                    // Always alert on critical events
                    var details = $"{eventConfig.Description}";
                    if (!string.IsNullOrEmpty(message))
                    {
                        details += $"\nEvent Message: {message}";
                    }

                    alerts.Add(new Alert
                    {
                        Severity = AlertSeverity.Critical,
                        Category = Category,
                        Message = $"Critical event {eventConfig.EventId} detected",
                        Details = details,
                        SuppressedChannels = eventConfig.SuppressedChannels ?? new List<string>()
                    });
                }

                return (data, alerts);
            }
            catch (Exception ex)
            {
                // If it's a "log does not exist" error, log at Debug level instead of Warning
                if (ex.Message.Contains("does not exist", StringComparison.OrdinalIgnoreCase))
                {
                    _logger.LogDebug("Event log '{LogName}' is not available on this system. Event {EventId} will not be monitored.", 
                        eventConfig.LogName, eventConfig.EventId);
                }
                else
                {
                    _logger.LogWarning(ex, "Failed to check event {EventId} in log {LogName}", 
                        eventConfig.EventId, eventConfig.LogName);
                }
                return ((EventData?)null, alerts);
            }
        }, cancellationToken);
    }
    */
    #endregion
}

