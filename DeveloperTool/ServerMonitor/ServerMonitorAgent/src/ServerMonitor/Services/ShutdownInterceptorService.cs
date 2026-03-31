using Microsoft.Extensions.Hosting;
using Microsoft.Extensions.Logging;
using Microsoft.Extensions.Options;
using ServerMonitor.Core.Configuration;
using ServerMonitor.Core.Models;
using ServerMonitor.Core.Services;

namespace ServerMonitor.Services;

/// <summary>
/// Intercepts system shutdown events using real-time hooks (SystemEvents.SessionEnding)
/// This fires BEFORE Event ID 1074 is logged, making it more reliable than polling.
/// </summary>
public class ShutdownInterceptorService : IHostedService
{
    private readonly ILogger<ShutdownInterceptorService> _logger;
    private readonly IOptionsMonitor<SurveillanceConfiguration> _config;
    private readonly AlertManager _alertManager;
    private bool _shutdownDetected = false;
    private readonly object _lockObject = new object();

    public ShutdownInterceptorService(
        ILogger<ShutdownInterceptorService> logger,
        IOptionsMonitor<SurveillanceConfiguration> config,
        AlertManager alertManager)
    {
        _logger = logger;
        _config = config;
        _alertManager = alertManager;
    }

    public Task StartAsync(CancellationToken cancellationToken)
    {
        try
        {
            // Check if any events are configured to use real-time hooks
            var eventMonitoring = _config.CurrentValue.EventMonitoring;
            if (!eventMonitoring.Enabled)
            {
                _logger.LogDebug("Event monitoring is disabled - shutdown interceptor not started");
                return Task.CompletedTask;
            }

            var eventsWithHooks = eventMonitoring.EventsToMonitor
                .Where(e => e.UseRealTimeHooks && e.EventId == 1074) // Only Event ID 1074 for now
                .ToList();

            if (!eventsWithHooks.Any())
            {
                _logger.LogDebug("No events configured for real-time shutdown hooks");
                return Task.CompletedTask;
            }

            // Register for system shutdown events
            Microsoft.Win32.SystemEvents.SessionEnding += OnSessionEnding;
            _logger.LogInformation("✅ Shutdown interceptor registered for Event ID 1074 (System shutdown/restart)");
        }
        catch (Exception ex)
        {
            _logger.LogError(ex, "Failed to register shutdown interceptor");
        }

        return Task.CompletedTask;
    }

    private void OnSessionEnding(object? sender, Microsoft.Win32.SessionEndingEventArgs e)
    {
        // Prevent multiple invocations
        lock (_lockObject)
        {
            if (_shutdownDetected)
            {
                return;
            }
            _shutdownDetected = true;
        }

        try
        {
            var eventConfig = _config.CurrentValue.EventMonitoring.EventsToMonitor
                .FirstOrDefault(e => e.EventId == 1074 && e.UseRealTimeHooks);

            if (eventConfig == null)
            {
                return;
            }

            var reason = e.Reason.ToString();
            _logger.LogCritical("🛑 SYSTEM SHUTDOWN DETECTED via real-time hook: {Reason}", reason);
            _logger.LogInformation("This fires BEFORE Event ID 1074 is logged in the Event Log");

            // Create critical alert immediately
            var alert = new Alert
            {
                Id = Guid.NewGuid(),
                Severity = AlertSeverity.Critical,
                Category = "EventLog",
                Message = $"System shutdown/restart initiated: {reason}",
                Details = $"Shutdown reason: {reason}\n" +
                         $"Event ID: 1074\n" +
                         $"Detected via: SystemEvents.SessionEnding (real-time hook)\n" +
                         $"Time: {DateTime.UtcNow:yyyy-MM-dd HH:mm:ss} UTC\n" +
                         $"Server: {Environment.MachineName}",
                Timestamp = DateTime.UtcNow,
                ServerName = Environment.MachineName,
                SuppressedChannels = eventConfig.SuppressedChannels ?? new List<string>(),
                Metadata = new Dictionary<string, object>
                {
                    ["EventId"] = 1074,
                    ["Source"] = eventConfig.Source,
                    ["LogName"] = eventConfig.LogName,
                    ["ShutdownReason"] = reason,
                    ["DetectionMethod"] = "RealTimeHook"
                }
            };

            // Send alert synchronously - don't await async operations during shutdown
            _logger.LogInformation("Sending shutdown alert to all configured channels...");
            _alertManager.ProcessAlertsSync(new[] { alert });

            _logger.LogInformation("✅ Shutdown alert logged and distributed successfully");
        }
        catch (Exception ex)
        {
            _logger.LogError(ex, "Error processing shutdown event");
        }
    }

    public Task StopAsync(CancellationToken cancellationToken)
    {
        try
        {
            Microsoft.Win32.SystemEvents.SessionEnding -= OnSessionEnding;
            _logger.LogDebug("Shutdown interceptor unregistered");
        }
        catch (Exception ex)
        {
            _logger.LogWarning(ex, "Error unregistering shutdown interceptor");
        }

        return Task.CompletedTask;
    }
}

