using System.Linq;
using System.Text.Json;
using Microsoft.Extensions.Logging;
using Microsoft.Extensions.Options;
using ServerMonitor.Core.Configuration;
using ServerMonitor.Core.Interfaces;
using ServerMonitor.Core.Models;

namespace ServerMonitor.Core.Services;

/// <summary>
/// Manages alert distribution with throttling and deduplication
/// </summary>
public class AlertManager
{
    private readonly ILogger<AlertManager> _logger;
    private readonly IOptionsMonitor<SurveillanceConfiguration> _config;
    private readonly IEnumerable<IAlertChannel> _channels;
    private readonly GlobalSnapshotService _globalSnapshot;
    private readonly NotificationRecipientService _recipientService;
    private readonly Dictionary<string, DateTime> _recentAlerts = new();
    private readonly Queue<DateTime> _alertTimestamps = new();
    private readonly Dictionary<string, DateTime> _lastExternalEventAlert = new(); // Track last alert time per external event code
    private readonly Dictionary<string, int> _externalEventTimeWindows = new(); // Store time window per event code for consistency
    private readonly object _lock = new();

    public AlertManager(
        ILogger<AlertManager> logger,
        IOptionsMonitor<SurveillanceConfiguration> config,
        IEnumerable<IAlertChannel> channels,
        GlobalSnapshotService globalSnapshot,
        NotificationRecipientService recipientService)
    {
        _logger = logger;
        _config = config;
        _channels = channels;
        _globalSnapshot = globalSnapshot;
        _recipientService = recipientService;
        
        // Log loaded channels and environment
        var channelList = channels.ToList();
        var currentEnv = _recipientService.GetCurrentEnvironment();
        var envChannels = _recipientService.GetCurrentEnvironmentChannelConfig();
        
        _logger.LogInformation("AlertManager initialized with {Count} channels (Environment: {Env})", 
            channelList.Count, currentEnv);
        
        foreach (var channel in channelList)
        {
            var envEnabled = _recipientService.IsChannelEnabledForEnvironment(channel.ChannelType);
            var effectiveEnabled = channel.IsEnabled && envEnabled;
            
            _logger.LogInformation("Channel: {Type} | Config: {ConfigEnabled} | Env ({EnvName}): {EnvEnabled} | Effective: {Effective}",
                channel.ChannelType, 
                channel.IsEnabled ? "enabled" : "disabled",
                currentEnv,
                envEnabled ? "enabled" : "disabled",
                effectiveEnabled ? "ENABLED" : "DISABLED");
        }
    }

    /// <summary>
    /// Processes external events: checks throttling per externalEventCode, generates alerts if needed
    /// Called synchronously from REST API to avoid async complexity
    /// </summary>
    public void ProcessExternalEventSync(ExternalEvent externalEvent)
    {
        _logger.LogDebug("ProcessExternalEventSync called for event code: {EventCode}", externalEvent.ExternalEventCode);
        
        var settings = _config.CurrentValue.Alerting;

        if (!settings.Enabled)
        {
            _logger.LogDebug("Alerting is disabled");
            return;
        }

        // Use consistent time window per event code (store first one seen, reuse for consistency)
        var eventCodeKey = externalEvent.ExternalEventCode;
        int timeWindowMinutes;
        
        lock (_lock)
        {
            if (!_externalEventTimeWindows.TryGetValue(eventCodeKey, out timeWindowMinutes))
            {
                // First time seeing this event code - store its time window
                timeWindowMinutes = externalEvent.Surveillance.TimeWindowMinutes;
                _externalEventTimeWindows[eventCodeKey] = timeWindowMinutes;
                _logger.LogDebug("Stored time window {TimeWindow} minutes for event code {EventCode}", 
                    timeWindowMinutes, eventCodeKey);
            }
            // Use stored time window for consistency (prevents issues when same event code submitted with different windows)
        }

        // Check throttling per externalEventCode (similar to event monitoring)
        var snapshot = _globalSnapshot.GetCurrentSnapshot();
        var timeWindow = DateTime.UtcNow.AddMinutes(-timeWindowMinutes);
        
        // Count occurrences of this externalEventCode within the time window
        // Use RegisteredTimestamp for throttling logic (when event was added to system)
        // Note: This includes the current event that was just added
        var occurrences = snapshot.ExternalEvents
            .Where(e => e.ExternalEventCode == externalEvent.ExternalEventCode && 
                       e.RegisteredTimestamp >= timeWindow)
            .Count();

        _logger.LogDebug("External event {EventCode}: {Occurrences} occurrences in last {TimeWindow} minutes (threshold: {MaxOccurrences})",
            externalEvent.ExternalEventCode, occurrences, timeWindowMinutes, externalEvent.Surveillance.MaxOccurrences);

        // Check if we should generate an alert
        // MaxOccurrences = 0 means alert on any occurrence (if count > 0)
        // MaxOccurrences > 0 means alert when count >= MaxOccurrences (alert on the Nth occurrence)
        // Example: maxOccurrences=3 means alert on 3rd occurrence (when occurrences >= 3)
        bool shouldAlert = externalEvent.Surveillance.MaxOccurrences == 0 
            ? occurrences > 0 
            : occurrences >= externalEvent.Surveillance.MaxOccurrences;

        if (shouldAlert)
        {
            // Check if we already alerted for this event code within the time window (prevent alert storm)
            lock (_lock)
            {
                if (_lastExternalEventAlert.TryGetValue(eventCodeKey, out var lastAlertTime))
                {
                    // If we already alerted within this time window, suppress
                    if (lastAlertTime >= timeWindow)
                    {
                        _logger.LogDebug("External event {EventCode} already alerted within time window - suppressing duplicate alert (last alert: {LastAlert}, time window start: {TimeWindowStart})", 
                            externalEvent.ExternalEventCode, lastAlertTime, timeWindow);
                        return;
                    }
                }
                
                // Update last alert time
                _lastExternalEventAlert[eventCodeKey] = DateTime.UtcNow;
            }

            // Create alert from external event
            var alert = new Alert
            {
                Id = Guid.NewGuid(),
                Severity = externalEvent.Severity,
                Category = externalEvent.Category,
                Message = externalEvent.Message,
                Details = $"External event {externalEvent.ExternalEventCode}: Occurred {occurrences} times in the last {timeWindowMinutes} minutes (threshold: {externalEvent.Surveillance.MaxOccurrences})",
                Timestamp = DateTime.UtcNow,
                ServerName = externalEvent.ServerName,
                Metadata = externalEvent.Metadata,
                SuppressedChannels = externalEvent.Surveillance.SuppressedChannels ?? new List<string>()
            };

            _logger.LogInformation("Alert generated from external event {EventCode}: [{Severity}] {Category}: {Message}",
                externalEvent.ExternalEventCode, alert.Severity, alert.Category, alert.Message);

            // Add alert to global snapshot and distribute
            // Skip global throttling for external events (they have their own per-event throttling)
            _globalSnapshot.AddAlert(alert);
            DistributeAlertSync(alert, skipGlobalThrottling: true);
        }
        else
        {
            _logger.LogDebug("External event {EventCode} within threshold - no alert generated", externalEvent.ExternalEventCode);
        }
    }

    /// <summary>
    /// Processes alerts: adds to global snapshot, then distributes sequentially
    /// Called synchronously from monitor cycles to avoid async complexity
    /// </summary>
    public void ProcessAlertsSync(IEnumerable<Alert> alerts)
    {
        var alertCount = alerts.Count();
        _logger.LogDebug("ProcessAlertsSync called with {AlertCount} alerts", alertCount);
        
        var settings = _config.CurrentValue.Alerting;

        if (!settings.Enabled)
        {
            _logger.LogDebug("Alerting is disabled");
            return;
        }

        foreach (var alert in alerts)
        {
            _logger.LogDebug("Processing alert: {Message} (Severity: {Severity})", alert.Message, alert.Severity);
            
            // 1. Add to global snapshot first
            _globalSnapshot.AddAlert(alert);
            
            // 2. Then distribute sequentially (no async, no events, no locks)
            DistributeAlertSync(alert);
        }
    }

    /// <summary>
    /// Gets suppressed channels for an alert.
    /// Uses alert-specific SuppressedChannels (from config items like EventToMonitor, TaskToMonitor).
    /// Falls back to global/category suppression if alert-specific is empty.
    /// Validates channel names against actual available channels.
    /// </summary>
    private List<string> GetSuppressedChannels(Alert alert, AlertingSettings settings)
    {
        // Get valid channel types for validation
        var validChannelTypes = _channels.Select(c => c.ChannelType).ToList();
        
        // Primary: Use alert-specific suppression from config (EventToMonitor, TaskToMonitor, etc.)
        if (alert.SuppressedChannels != null && alert.SuppressedChannels.Count > 0)
        {
            // Validate and normalize channel names
            var validated = alert.SuppressedChannels
                .Where(ch => validChannelTypes.Contains(ch, StringComparer.OrdinalIgnoreCase))
                .Select(ch => validChannelTypes.First(v => v.Equals(ch, StringComparison.OrdinalIgnoreCase)))
                .Distinct()
                .ToList();
            
            if (validated.Count != alert.SuppressedChannels.Count)
            {
                var invalid = alert.SuppressedChannels
                    .Except(validated, StringComparer.OrdinalIgnoreCase)
                    .ToList();
                _logger.LogWarning("Invalid suppressed channel names in alert: {InvalidChannels}. Valid channels: {ValidChannels}", 
                    string.Join(", ", invalid), string.Join(", ", validChannelTypes));
            }
            
            return validated;
        }
        
        // Fallback: Merge global and category-specific suppression
        var suppressed = new HashSet<string>(StringComparer.OrdinalIgnoreCase);
        
        // Add global suppression
        if (settings.SuppressedChannels != null)
        {
            foreach (var channel in settings.SuppressedChannels)
            {
                suppressed.Add(channel);
            }
        }
        
        // Add category-specific suppression
        if (settings.CategorySuppressions != null && 
            settings.CategorySuppressions.TryGetValue(alert.Category, out var categorySuppression))
        {
            foreach (var channel in categorySuppression)
            {
                suppressed.Add(channel);
            }
        }
        
        // Validate and normalize all suppressed channels
        var validatedSuppressed = suppressed
            .Where(ch => validChannelTypes.Contains(ch, StringComparer.OrdinalIgnoreCase))
            .Select(ch => validChannelTypes.First(v => v.Equals(ch, StringComparison.OrdinalIgnoreCase)))
            .Distinct()
            .ToList();
        
        if (validatedSuppressed.Count != suppressed.Count)
        {
            var invalid = suppressed
                .Except(validatedSuppressed, StringComparer.OrdinalIgnoreCase)
                .ToList();
            _logger.LogWarning("Invalid suppressed channel names in config: {InvalidChannels}. Valid channels: {ValidChannels}", 
                string.Join(", ", invalid), string.Join(", ", validChannelTypes));
        }
        
        return validatedSuppressed;
    }

    /// <summary>
    /// Distributes an alert to all configured channels with throttling and deduplication
    /// Synchronous to avoid async/lock complexity
    /// </summary>
    /// <param name="alert">The alert to distribute</param>
    /// <param name="skipGlobalThrottling">If true, skip global throttling (used for external events with their own throttling)</param>
    private void DistributeAlertSync(Alert alert, bool skipGlobalThrottling = false)
    {
        var settings = _config.CurrentValue.Alerting;

        // Check throttling (skip for external events that have their own throttling)
        if (!skipGlobalThrottling && settings.Throttling.Enabled && IsThrottled())
        {
            _logger.LogWarning("Alert throttled due to rate limit: {Message}", alert.Message);
            return;
        }

        // Check for duplicate suppression (severity-based intervals)
        if (settings.Throttling.Enabled && IsDuplicate(alert, settings.Throttling))
        {
            _logger.LogDebug("Alert suppressed as duplicate: {Message}", alert.Message);
            return;
        }

        // Get suppressed channels (alert-specific from config takes precedence)
        var suppressedChannels = GetSuppressedChannels(alert, settings);
        
        // Log alert-level suppression info for debugging
        if (alert.SuppressedChannels != null && alert.SuppressedChannels.Count > 0)
        {
            _logger.LogDebug("Alert has SuppressedChannels from source: [{Channels}]", 
                string.Join(", ", alert.SuppressedChannels));
        }
        
        // Send to all enabled channels SEQUENTIALLY (simple, no locks, no deadlocks)
        // Filter out suppressed channels and apply environment-based channel settings
        var allEnabledChannels = _channels
            .Where(c => c.IsEnabled && alert.Severity >= c.MinimumSeverity)
            .Where(c => _recipientService.IsChannelEnabledForEnvironment(c.ChannelType))
            .ToList();
            
        var enabledChannels = allEnabledChannels
            .Where(c => suppressedChannels.Count == 0 || 
                       !suppressedChannels.Contains(c.ChannelType, StringComparer.OrdinalIgnoreCase))
            .ToList();
        
        _logger.LogDebug("Found {ChannelCount} enabled channels for severity {Severity}", enabledChannels.Count, alert.Severity);
        if (suppressedChannels.Count > 0)
        {
            var skippedChannels = allEnabledChannels
                .Where(c => suppressedChannels.Contains(c.ChannelType, StringComparer.OrdinalIgnoreCase))
                .Select(c => c.ChannelType)
                .ToList();
            _logger.LogDebug("Suppressed channels: [{SuppressedChannels}] | Skipped: [{SkippedChannels}]", 
                string.Join(", ", suppressedChannels),
                string.Join(", ", skippedChannels));
        }
        
        // Track success to only mark alert as sent if at least one channel succeeded
        bool anySuccess = false;
        foreach (var channel in enabledChannels)
        {
            _logger.LogDebug("Sending to channel: {ChannelType}", channel.ChannelType);
            if (SendToChannelSync(channel, alert))
            {
                anySuccess = true;
            }
        }

        // Only track alert for throttling and deduplication if at least one channel succeeded
        // This prevents failed alerts from being marked as "sent", allowing retries
        if (anySuccess)
        {
            TrackAlert(alert);
        }
        else if (enabledChannels.Count > 0)
        {
            _logger.LogWarning("Alert distribution failed for all {Count} channels: {Message}", 
                enabledChannels.Count, alert.Message);
        }
    }

    /// <summary>
    /// Sends alert to channel synchronously and records distribution
    /// </summary>
    /// <returns>True if the alert was successfully sent, false otherwise</returns>
    private bool SendToChannelSync(IAlertChannel channel, Alert alert)
    {
        _logger.LogDebug("SendToChannelSync: {ChannelType}", channel.ChannelType);
        string? destination = null;
        bool success = false;
        string? errorMessage = null;

        try
        {
            // Call channel synchronously (channels should handle their own async internally)
            _logger.LogDebug("Calling {ChannelType}.SendAlertAsync", channel.ChannelType);
            channel.SendAlertAsync(alert, CancellationToken.None).GetAwaiter().GetResult();
            
            // Extract destination based on channel type
            destination = GetChannelDestination(channel, alert);
            success = true;
            
            _logger.LogDebug("✅ Alert sent to {ChannelType}: {Message}", 
                channel.ChannelType, alert.Message);
        }
        catch (Exception ex)
        {
            destination = GetChannelDestination(channel, alert);
            errorMessage = ex.Message;
            
            _logger.LogError(ex, "❌ Failed to send alert to {ChannelType}: {Message}",
                channel.ChannelType, alert.Message);
        }
        finally
        {
            // Record distribution in global snapshot
            if (destination != null)
            {
                _globalSnapshot.RecordAlertDistribution(
                    alertId: alert.Id,
                    channelType: channel.ChannelType,
                    destination: destination,
                    success: success,
                    errorMessage: errorMessage
                );
            }
        }

        return success;
    }

    /// <summary>
    /// Gets the destination address/path for a channel (for tracking)
    /// </summary>
    private string GetChannelDestination(IAlertChannel channel, Alert alert)
    {
        var settings = _config.CurrentValue.Alerting;
        var channelConfig = settings.Channels.FirstOrDefault(c => c.Type == channel.ChannelType);
        
        if (channelConfig == null)
            return $"{channel.ChannelType} (config not found)";

        try
        {
            return channel.ChannelType switch
            {
                "SMS" => GetSmsDestination(channelConfig),
                "Email" => GetEmailDestination(channelConfig),
                "WKMonitor" => GetWkMonitorDestination(channelConfig, alert),
                "EventLog" => "Windows Event Log (Application)",
                "File" => GetFileDestination(channelConfig),
                _ => channel.ChannelType
            };
        }
        catch (Exception ex)
        {
            _logger.LogWarning(ex, "Failed to extract destination for {ChannelType}", channel.ChannelType);
            return channel.ChannelType;
        }
    }

    private string GetSmsDestination(AlertChannelConfig config)
    {
        if (config.Settings.TryGetValue("Receivers", out var receivers))
        {
            var receiversStr = receivers?.ToString() ?? "";
            // Return comma-separated list of phone numbers
            return string.IsNullOrWhiteSpace(receiversStr) ? "SMS (no receivers)" : receiversStr;
        }
        return "SMS (receivers not configured)";
    }

    private string GetEmailDestination(AlertChannelConfig config)
    {
        if (config.Settings.TryGetValue("To", out var to))
        {
            // Handle both string and JsonElement array formats
            if (to is System.Text.Json.JsonElement jsonElement)
            {
                if (jsonElement.ValueKind == System.Text.Json.JsonValueKind.Array)
                {
                    var emails = jsonElement.EnumerateArray()
                        .Select(e => e.GetString())
                        .Where(e => !string.IsNullOrWhiteSpace(e))
                        .ToList();
                    return emails.Any() ? string.Join(", ", emails) : "Email (no recipients)";
                }
                else if (jsonElement.ValueKind == System.Text.Json.JsonValueKind.String)
                {
                    return jsonElement.GetString() ?? "Email (no recipients)";
                }
            }
            
            var toStr = to?.ToString() ?? "";
            return string.IsNullOrWhiteSpace(toStr) ? "Email (no recipients)" : toStr;
        }
        return "Email (recipients not configured)";
    }

    private string GetWkMonitorDestination(AlertChannelConfig config, Alert alert)
    {
        var computerName = Environment.MachineName;
        var timestamp = DateTime.Now.ToString("yyyyMMddHHmmssfff");
        var fileName = $"{computerName}{timestamp}.MON";
        
        // Try to get the path from config
        var isProduction = Environment.GetEnvironmentVariable("ASPNETCORE_ENVIRONMENT")?.Equals("Production", StringComparison.OrdinalIgnoreCase) ?? false;
        var pathKey = isProduction ? "ProductionPath" : "TestPath";
        
        if (config.Settings.TryGetValue(pathKey, out var path))
        {
            var pathStr = path?.ToString() ?? "";
            return string.IsNullOrWhiteSpace(pathStr) ? fileName : System.IO.Path.Combine(pathStr, fileName);
        }
        
        return fileName;
    }

    private string GetFileDestination(AlertChannelConfig config)
    {
        if (config.Settings.TryGetValue("LogPath", out var logPath))
        {
            var logPathStr = logPath?.ToString() ?? "";
            if (!string.IsNullOrWhiteSpace(logPathStr))
            {
                // Replace {Date} placeholder if present
                return logPathStr.Replace("{Date}", DateTime.Now.ToString("yyyyMMdd"));
            }
        }
        return "Alert log file";
    }

    private bool IsThrottled()
    {
        lock (_lock)
        {
            var settings = _config.CurrentValue.Alerting.Throttling;
            var oneHourAgo = DateTime.UtcNow.AddHours(-1);

            // Remove old timestamps
            while (_alertTimestamps.Count > 0 && _alertTimestamps.Peek() < oneHourAgo)
            {
                _alertTimestamps.Dequeue();
            }

            return _alertTimestamps.Count >= settings.MaxAlertsPerHour;
        }
    }

    /// <summary>
    /// Generates a normalized deduplication key for an alert
    /// Strips numeric values so "CPU at 25.4%" and "CPU at 19.4%" are treated as the same alert
    /// Includes server name and resource context to prevent false positives (e.g., "Disk C: 90%" vs "Disk D: 90%")
    /// </summary>
    private string GetAlertKey(Alert alert)
    {
        // Replace all numbers with # placeholder to normalize messages with varying values
        var normalizedMessage = System.Text.RegularExpressions.Regex.Replace(
            alert.Message, 
            @"\d+\.?\d*", 
            "#"
        );
        
        // Extract resource context from metadata (e.g., disk drive, service name, network interface)
        // This prevents false positives like "Disk C: 90%" and "Disk D: 90%" being treated as duplicates
        var context = "";
        if (alert.Metadata != null)
        {
            // Try common resource identifiers
            var resourceKeys = new[] { "Resource", "Drive", "ServiceName", "Interface", "Path", "TaskName", "EventId" };
            foreach (var key in resourceKeys)
            {
                if (alert.Metadata.TryGetValue(key, out var resourceValue))
                {
                    context = resourceValue?.ToString() ?? "";
                    break;
                }
            }
            
            // If no standard key found, use first metadata value as context
            if (string.IsNullOrEmpty(context) && alert.Metadata.Count > 0)
            {
                context = alert.Metadata.Values.FirstOrDefault()?.ToString() ?? "";
            }
        }
        
        // Include server name, category, severity, context, and normalized message
        // This ensures alerts for different resources on the same server are not treated as duplicates
        return $"{alert.ServerName}_{alert.Category}_{alert.Severity}_{context}_{normalizedMessage}";
    }

    private bool IsDuplicate(Alert alert, ThrottlingSettings throttling)
    {
        lock (_lock)
        {
            var key = GetAlertKey(alert);
            var normalizedMessage = System.Text.RegularExpressions.Regex.Replace(alert.Message, @"\d+\.?\d*", "#");
            
            // Determine suppression interval based on severity
            var suppressionMinutes = alert.Severity switch
            {
                AlertSeverity.Critical => throttling.ErrorSuppressionMinutes,
                AlertSeverity.Warning => throttling.WarningSuppressionMinutes,
                AlertSeverity.Informational => throttling.InformationalSuppressionMinutes,
                _ => throttling.WarningSuppressionMinutes
            };
            
            if (_recentAlerts.TryGetValue(key, out var lastTime))
            {
                var age = DateTime.UtcNow - lastTime;
                
                if (age.TotalMinutes < suppressionMinutes)
                {
                    _logger.LogInformation("🚫 ALERT SUPPRESSED: [{Severity}] {Message} | Last sent {Age:F1}min ago | Suppression window: {Suppression}min | Key: {Key}",
                        alert.Severity, alert.Message, age.TotalMinutes, suppressionMinutes, normalizedMessage);
                    return true;
                }
                else
                {
                    _logger.LogInformation("✅ ALERT ALLOWED: [{Severity}] {Message} | Last sent {Age:F1}min ago | Suppression window: {Suppression}min",
                        alert.Severity, alert.Message, age.TotalMinutes, suppressionMinutes);
                }
            }
            else
            {
                _logger.LogInformation("🆕 NEW ALERT: [{Severity}] {Message} | No previous record | Key: {Key}",
                    alert.Severity, alert.Message, normalizedMessage);
            }

            return false;
        }
    }

    private void TrackAlert(Alert alert)
    {
        lock (_lock)
        {
            var key = GetAlertKey(alert); // Use normalized key
            _recentAlerts[key] = DateTime.UtcNow;
            _alertTimestamps.Enqueue(DateTime.UtcNow);

            // Get cleanup age from config
            var cleanupAgeHours = _config.CurrentValue.General.MemoryManagement.CleanupAgeHours;
            var cutoffTime = DateTime.UtcNow.AddHours(-cleanupAgeHours);
            
            // Clean up old recent alerts
            var keysToRemove = _recentAlerts
                .Where(kvp => kvp.Value < cutoffTime)
                .Select(kvp => kvp.Key)
                .ToList();

            foreach (var keyToRemove in keysToRemove)
            {
                _recentAlerts.Remove(keyToRemove);
            }
            
            // Also cleanup external event tracking dictionaries
            CleanupExternalEventTracking(cutoffTime);
        }
    }
    
    /// <summary>
    /// Cleans up stale entries from external event tracking dictionaries.
    /// Called during TrackAlert() and can be called periodically.
    /// </summary>
    private void CleanupExternalEventTracking(DateTime cutoffTime)
    {
        // Clean up old external event alert times
        var staleCodes = _lastExternalEventAlert
            .Where(kvp => kvp.Value < cutoffTime)
            .Select(kvp => kvp.Key)
            .ToList();
        
        foreach (var code in staleCodes)
        {
            _lastExternalEventAlert.Remove(code);
            _externalEventTimeWindows.Remove(code); // Also remove corresponding time window
        }
        
        if (staleCodes.Count > 0)
        {
            _logger.LogDebug("Cleaned up {Count} stale external event tracking entries", staleCodes.Count);
        }
    }
    
    /// <summary>
    /// Runs periodic cleanup of all in-memory tracking collections.
    /// Should be called on a timer (e.g., every hour).
    /// </summary>
    public void RunPeriodicCleanup()
    {
        lock (_lock)
        {
            var cleanupAgeHours = _config.CurrentValue.General.MemoryManagement.CleanupAgeHours;
            var cutoffTime = DateTime.UtcNow.AddHours(-cleanupAgeHours);
            
            // Cleanup recent alerts
            var recentRemoved = 0;
            var keysToRemove = _recentAlerts
                .Where(kvp => kvp.Value < cutoffTime)
                .Select(kvp => kvp.Key)
                .ToList();
            
            foreach (var key in keysToRemove)
            {
                _recentAlerts.Remove(key);
                recentRemoved++;
            }
            
            // Cleanup external event tracking
            var externalRemoved = _lastExternalEventAlert.Count;
            CleanupExternalEventTracking(cutoffTime);
            externalRemoved = externalRemoved - _lastExternalEventAlert.Count;
            
            // Cleanup alert timestamps queue
            var timestampsRemoved = 0;
            while (_alertTimestamps.Count > 0 && _alertTimestamps.Peek() < cutoffTime)
            {
                _alertTimestamps.Dequeue();
                timestampsRemoved++;
            }
            
            if (recentRemoved > 0 || externalRemoved > 0 || timestampsRemoved > 0)
            {
                _logger.LogInformation("AlertManager periodic cleanup: {Recent} recent alerts, {External} external event codes, {Timestamps} timestamps removed",
                    recentRemoved, externalRemoved, timestampsRemoved);
            }
            
            // Memory tracking - log current collection sizes
            _logger.LogDebug("AlertManager collection sizes: RecentAlerts={Recent}, ExternalEventAlerts={External}, TimeWindows={Windows}, Timestamps={Timestamps}",
                _recentAlerts.Count, _lastExternalEventAlert.Count, _externalEventTimeWindows.Count, _alertTimestamps.Count);
        }
    }
    
    /// <summary>
    /// Gets current memory diagnostic information for the AlertManager.
    /// </summary>
    public (int RecentAlerts, int ExternalEventAlerts, int TimeWindows, int Timestamps) GetMemoryDiagnostics()
    {
        lock (_lock)
        {
            return (_recentAlerts.Count, _lastExternalEventAlert.Count, _externalEventTimeWindows.Count, _alertTimestamps.Count);
        }
    }
}

