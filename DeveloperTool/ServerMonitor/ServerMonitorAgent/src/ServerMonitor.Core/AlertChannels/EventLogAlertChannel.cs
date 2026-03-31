using System.Diagnostics;
using Microsoft.Extensions.Logging;
using Microsoft.Extensions.Options;
using ServerMonitor.Core.Configuration;
using ServerMonitor.Core.Interfaces;
using ServerMonitor.Core.Models;

namespace ServerMonitor.Core.AlertChannels;

/// <summary>
/// Sends alerts to Windows Event Log
/// </summary>
public class EventLogAlertChannel : IAlertChannel
{
    private readonly ILogger<EventLogAlertChannel> _logger;
    private readonly IOptionsMonitor<SurveillanceConfiguration> _config;
    private const string EventLogSource = "ServerMonitor";
    private const string EventLogName = "Application";

    public string ChannelType => "EventLog";
    public bool IsEnabled { get; private set; }
    public AlertSeverity MinimumSeverity { get; private set; }

    public EventLogAlertChannel(
        ILogger<EventLogAlertChannel> logger,
        IOptionsMonitor<SurveillanceConfiguration> config)
    {
        _logger = logger;
        _config = config;

        UpdateConfiguration(config.CurrentValue);
        config.OnChange(UpdateConfiguration);

        // Ensure event source exists
        EnsureEventSourceExists();
    }

    private void UpdateConfiguration(SurveillanceConfiguration config)
    {
        var channelConfig = config.Alerting.Channels
            .FirstOrDefault(c => c.Type.Equals("EventLog", StringComparison.OrdinalIgnoreCase));

        if (channelConfig != null)
        {
            IsEnabled = channelConfig.Enabled;
            MinimumSeverity = Enum.TryParse<AlertSeverity>(channelConfig.MinSeverity, out var severity)
                ? severity
                : AlertSeverity.Warning;
        }
        else
        {
            IsEnabled = false;
            MinimumSeverity = AlertSeverity.Warning;
        }
    }

    public Task SendAlertAsync(Alert alert, CancellationToken cancellationToken = default)
    {
        try
        {
            if (!IsEnabled)
            {
                return Task.CompletedTask;
            }

            var eventType = alert.Severity switch
            {
                AlertSeverity.Critical => EventLogEntryType.Error,
                AlertSeverity.Warning => EventLogEntryType.Warning,
                _ => EventLogEntryType.Information
            };

            var message = $"[{alert.Category}] {alert.Message}";
            message += $"\n\nAlert ID: {alert.Id}";
            if (!string.IsNullOrEmpty(alert.Details))
            {
                message += $"\nDetails: {alert.Details}";
            }

            using var eventLog = new EventLog(EventLogName);
            eventLog.Source = EventLogSource;
            eventLog.WriteEntry(message, eventType, (int)alert.Severity + 1000);

            _logger.LogDebug("Alert written to Event Log: {Message}", alert.Message);

            return Task.CompletedTask;
        }
        catch (Exception ex)
        {
            _logger.LogError(ex, "Failed to write alert to Event Log");
            throw;
        }
    }

    private void EnsureEventSourceExists()
    {
        try
        {
            if (!EventLog.SourceExists(EventLogSource))
            {
                EventLog.CreateEventSource(EventLogSource, EventLogName);
                _logger.LogInformation("Created Event Log source: {Source}", EventLogSource);
            }
        }
        catch (Exception ex)
        {
            _logger.LogWarning(ex, "Failed to create Event Log source (may require elevated privileges)");
        }
    }
}

