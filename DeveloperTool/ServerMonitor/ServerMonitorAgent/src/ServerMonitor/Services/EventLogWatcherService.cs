using System.Diagnostics.Eventing.Reader;
using System.Text.RegularExpressions;
using Microsoft.Extensions.Hosting;
using Microsoft.Extensions.Logging;
using Microsoft.Extensions.Options;
using ServerMonitor.Core.Configuration;
using ServerMonitor.Core.Models;
using ServerMonitor.Core.Services;

namespace ServerMonitor.Services;

/// <summary>
/// Real-time event log monitoring using EventLogWatcher.
/// Subscribes to Windows Event Log and receives push notifications when events occur.
/// This replaces the polling-based EventLogMonitor for better performance and immediate detection.
/// 
/// Uses AlertAccumulator to prevent alert flooding:
/// - Tracks occurrences per event ID in a sliding time window
/// - Only alerts when count > MaxOccurrences AND cooldown has expired
/// - After alerting, clears the accumulator and starts cooldown period
/// </summary>
public class EventLogWatcherService : IHostedService, IDisposable
{
    private readonly ILogger<EventLogWatcherService> _logger;
    private readonly IOptionsMonitor<SurveillanceConfiguration> _config;
    private readonly AlertManager _alertManager;
    private readonly GlobalSnapshotService _snapshotService;
    private readonly IAlertAccumulator _alertAccumulator;
    
    private readonly List<EventLogWatcher> _watchers = new();
    private readonly Dictionary<string, EventOccurrenceTracker> _eventTrackers = new();
    private readonly object _lockObject = new();
    private bool _disposed = false;

    // Task Scheduler event IDs that should be filtered by ScheduledTaskMonitoring criteria
    private static readonly HashSet<int> TaskSchedulerEventIds = new() { 103, 201, 411 };
    
    // Regex patterns to extract task name from Task Scheduler event messages
    // Pattern: Matches common Task Scheduler message formats like:
    //   - 'Task "\TaskPath\TaskName"' or 'task "\TaskPath\TaskName"'
    //   - 'Task Scheduler successfully completed task "\TaskPath\TaskName"'
    private static readonly Regex TaskNamePattern = new(
        @"[Tt]ask\s+[""']?\\([^""'\r\n]+)[""']?",
        RegexOptions.Compiled);

    public EventLogWatcherService(
        ILogger<EventLogWatcherService> logger,
        IOptionsMonitor<SurveillanceConfiguration> config,
        AlertManager alertManager,
        GlobalSnapshotService snapshotService,
        IAlertAccumulator alertAccumulator)
    {
        _logger = logger;
        _config = config;
        _alertManager = alertManager;
        _snapshotService = snapshotService;
        _alertAccumulator = alertAccumulator;
    }

    public Task StartAsync(CancellationToken cancellationToken)
    {
        try
        {
            var eventMonitoring = _config.CurrentValue?.EventMonitoring;
            if (eventMonitoring == null)
            {
                _logger.LogWarning("EventMonitoring configuration is null - EventLogWatcher not started");
                return Task.CompletedTask;
            }
            
            if (!eventMonitoring.Enabled)
            {
                _logger.LogDebug("Event monitoring is disabled - EventLogWatcher not started");
                return Task.CompletedTask;
            }

            // Filter to only enabled events (with null safety)
            var eventsToMonitor = eventMonitoring.EventsToMonitor ?? new List<EventToMonitor>();
            var enabledEvents = eventsToMonitor.Where(e => e.Enabled).ToList();
            
            if (!enabledEvents.Any())
            {
                _logger.LogDebug("No events configured for monitoring");
                return Task.CompletedTask;
            }

            _logger.LogInformation("🎯 Starting EventLogWatcher for {Count} events (real-time monitoring)", enabledEvents.Count);

            // Group events by LogName for efficiency
            var eventsByLog = enabledEvents.GroupBy(e => e.LogName);

            foreach (var logGroup in eventsByLog)
            {
                var logName = logGroup.Key;
                var eventsInLog = logGroup.ToList();

                try
                {
                    // Build XPath query for all events in this log
                    var xpathQuery = BuildXPathQuery(eventsInLog);
                    
                    _logger.LogDebug("Creating EventLogWatcher for log '{LogName}' with {Count} event types", 
                        logName, eventsInLog.Count);
                    _logger.LogTrace("XPath query: {Query}", xpathQuery);

                    var query = new EventLogQuery(logName, PathType.LogName, xpathQuery);
                    var watcher = new EventLogWatcher(query);
                    
                    // Capture eventsInLog for the closure
                    var eventConfigs = eventsInLog;
                    watcher.EventRecordWritten += (sender, args) => OnEventRecordWritten(args, eventConfigs);
                    
                    // Enable watcher - this can throw if we don't have permission
                    watcher.Enabled = true;
                    _watchers.Add(watcher);

                    // Initialize trackers for each event
                    foreach (var eventConfig in eventsInLog)
                    {
                        var key = GetTrackerKey(eventConfig);
                        _eventTrackers[key] = new EventOccurrenceTracker
                        {
                            EventConfig = eventConfig,
                            Occurrences = new List<DateTime>()
                        };
                    }

                    _logger.LogInformation("✅ EventLogWatcher active for '{LogName}': {Events}", 
                        logName, 
                        string.Join(", ", eventsInLog.Select(e => $"EventID {e.EventId}")));
                }
                catch (EventLogNotFoundException)
                {
                    _logger.LogDebug("Event log '{LogName}' does not exist on this system. Skipping.", logName);
                }
                catch (EventLogReadingException ex)
                {
                    _logger.LogWarning("Cannot read event log '{LogName}': {Message}. Skipping.", logName, ex.Message);
                }
                catch (UnauthorizedAccessException)
                {
                    _logger.LogWarning("Access denied to event log '{LogName}'. Run as administrator to monitor this log. Skipping.", logName);
                }
                catch (Exception ex)
                {
                    // Log but don't crash - skip this log and continue with others
                    _logger.LogWarning(ex, "Failed to create EventLogWatcher for log '{LogName}'. Skipping.", logName);
                }
            }

            _logger.LogInformation("📡 EventLogWatcher service started with {Count} active watchers", _watchers.Count);
        }
        catch (Exception ex)
        {
            _logger.LogError(ex, "Failed to start EventLogWatcher service");
        }

        return Task.CompletedTask;
    }

    private string BuildXPathQuery(List<EventToMonitor> events)
    {
        // Build XPath query to match any of the specified event IDs
        // Example: *[System[(EventID=4625) or (EventID=4740) or (EventID=1001)]]
        var eventIdConditions = events.Select(e => $"(EventID={e.EventId})");
        var combinedCondition = string.Join(" or ", eventIdConditions);
        return $"*[System[{combinedCondition}]]";
    }

    private string GetTrackerKey(EventToMonitor eventConfig)
    {
        return $"{eventConfig.LogName}:{eventConfig.EventId}:{eventConfig.Source}";
    }

    private void OnEventRecordWritten(EventRecordWrittenEventArgs args, List<EventToMonitor> eventConfigs)
    {
        if (args.EventRecord == null)
        {
            if (args.EventException != null)
            {
                _logger.LogWarning(args.EventException, "Error in EventLogWatcher callback");
            }
            return;
        }

        try
        {
            var record = args.EventRecord;
            var eventId = record.Id;
            var source = record.ProviderName ?? string.Empty;
            var logName = record.LogName ?? string.Empty;
            var timeCreated = record.TimeCreated ?? DateTime.Now;
            
            // Find matching event config
            var matchingConfig = eventConfigs.FirstOrDefault(e => 
                e.EventId == eventId && 
                (string.IsNullOrEmpty(e.Source) || e.Source.Equals(source, StringComparison.OrdinalIgnoreCase)));

            if (matchingConfig == null)
            {
                // Event ID matches but source doesn't - could be a different provider
                _logger.LogTrace("Event {EventId} from {Source} doesn't match any configured source filter", eventId, source);
                return;
            }

            var trackerKey = GetTrackerKey(matchingConfig);
            
            // Build alert key for the accumulator
            var alertKey = $"EventLog:{eventId}:{matchingConfig.Source}";
            
            lock (_lockObject)
            {
                if (!_eventTrackers.TryGetValue(trackerKey, out var tracker))
                {
                    // Create tracker if it doesn't exist (for snapshot data)
                    tracker = new EventOccurrenceTracker
                    {
                        EventConfig = matchingConfig,
                        Occurrences = new List<DateTime>()
                    };
                    _eventTrackers[trackerKey] = tracker;
                }

                // Record this occurrence in local tracker (for snapshot data)
                tracker.Occurrences.Add(timeCreated);
                tracker.LastMessage = GetEventMessage(record);
                tracker.LastOccurrence = timeCreated;

                // Clean up old occurrences outside the time window
                var windowStart = DateTime.Now.AddMinutes(-matchingConfig.TimeWindowMinutes);
                tracker.Occurrences.RemoveAll(t => t < windowStart);

                // Record occurrence in the AlertAccumulator
                _alertAccumulator.RecordOccurrence(alertKey, timeCreated.ToUniversalTime(), matchingConfig.TimeWindowMinutes);
                
                // Get count from accumulator
                var count = _alertAccumulator.GetOccurrenceCount(alertKey, matchingConfig.TimeWindowMinutes);
                
                var eventMessage = tracker.LastMessage ?? "(no message)";
                _logger.LogInformation("[EventAccum] EventID={EventId} Source={Source} Count={Count}/{Max} Window={Window}min Msg={Message}",
                    eventId, source, count, matchingConfig.MaxOccurrences, matchingConfig.TimeWindowMinutes, eventMessage);

                // Check if we should alert (using accumulator for proper deduplication)
                bool shouldAlert = false;
                AlertSeverity severity = AlertSeverity.Warning;
                string alertMessage = string.Empty;
                string alertDetails = string.Empty;

                // Check if accumulator says we should alert
                if (_alertAccumulator.ShouldAlert(alertKey, matchingConfig.MaxOccurrences, matchingConfig.TimeWindowMinutes))
                {
                    shouldAlert = true;
                    severity = matchingConfig.Level.Equals("Critical", StringComparison.OrdinalIgnoreCase)
                        ? AlertSeverity.Critical
                        : AlertSeverity.Warning;
                    
                    alertMessage = $"Event {eventId} occurred {count} times";
                    alertDetails = $"{matchingConfig.Description}: Occurred {count} times in the last {matchingConfig.TimeWindowMinutes} minutes (threshold: {matchingConfig.MaxOccurrences})";
                }
                else if (matchingConfig.Level.Equals("Critical", StringComparison.OrdinalIgnoreCase) && 
                         matchingConfig.MaxOccurrences == 0 && matchingConfig.TimeWindowMinutes == 0)
                {
                    // Legacy mode: Always alert on critical events with MaxOccurrences=0 and TimeWindowMinutes=0
                    shouldAlert = true;
                    severity = AlertSeverity.Critical;
                    alertMessage = $"Critical event {eventId} detected";
                    alertDetails = matchingConfig.Description;
                }

                if (shouldAlert)
                {
                    // For Task Scheduler events, check if task matches ScheduledTaskMonitoring criteria
                    string? taskName = null;
                    string? taskPath = null;
                    
                    if (TaskSchedulerEventIds.Contains(eventId))
                    {
                        // Extract task name from event message
                        taskPath = ExtractTaskPath(tracker.LastMessage);
                        if (!string.IsNullOrEmpty(taskPath))
                        {
                            taskName = GetTaskNameFromPath(taskPath);
                            
                            // Check if task matches ScheduledTaskMonitoring criteria
                            if (!ShouldAlertForTask(taskPath))
                            {
                                _logger.LogDebug("⏭️ Task Scheduler event for '{TaskPath}' skipped - doesn't match ScheduledTaskMonitoring criteria", taskPath);
                                // Still update snapshot but don't alert
                                UpdateSnapshotEventData(tracker);
                                return;
                            }
                            
                            _logger.LogDebug("✅ Task Scheduler event for '{TaskPath}' matches ScheduledTaskMonitoring criteria", taskPath);
                        }
                    }
                    
                    if (!string.IsNullOrEmpty(tracker.LastMessage))
                    {
                        alertDetails += $"\nEvent Message: {tracker.LastMessage}";
                    }

                    var metadata = new Dictionary<string, object>
                    {
                        ["EventId"] = eventId,
                        ["Source"] = source,
                        ["LogName"] = logName,
                        ["OccurrenceCount"] = count,
                        ["TimeWindowMinutes"] = matchingConfig.TimeWindowMinutes,
                        ["DetectionMethod"] = "EventLogWatcher"
                    };
                    
                    // Add task info to metadata if available
                    if (!string.IsNullOrEmpty(taskName))
                    {
                        metadata["TaskName"] = taskName;
                    }
                    if (!string.IsNullOrEmpty(taskPath))
                    {
                        metadata["TaskPath"] = taskPath;
                    }

                    var alert = new Alert
                    {
                        Id = Guid.NewGuid(),
                        Severity = severity,
                        Category = "EventLog",
                        Message = alertMessage,
                        Details = alertDetails,
                        Timestamp = DateTime.UtcNow,
                        ServerName = Environment.MachineName,
                        SuppressedChannels = matchingConfig.SuppressedChannels ?? new List<string>(),
                        Metadata = metadata
                    };

                    _logger.LogInformation("[EventAlarm] ALERT GENERATED: EventID={EventId} Severity={Severity} Count={Count} Threshold={Max} Window={Window}min Description={Description}",
                        eventId, severity, count, matchingConfig.MaxOccurrences, matchingConfig.TimeWindowMinutes, matchingConfig.Description);
                    _logger.LogWarning("🚨 Event alert triggered: {Message}", alertMessage);
                    
                    // Clear accumulator BEFORE processing alert to start cooldown immediately
                    _alertAccumulator.ClearAfterAlert(alertKey, matchingConfig.TimeWindowMinutes);
                    
                    // Process alert asynchronously (fire and forget, but log errors)
                    Task.Run(() =>
                    {
                        try
                        {
                            _alertManager.ProcessAlertsSync(new[] { alert });
                        }
                        catch (Exception ex)
                        {
                            _logger.LogError(ex, "Failed to process event alert");
                        }
                    });

                    // Update snapshot with event data
                    UpdateSnapshotEventData(tracker);
                }
            }
        }
        catch (Exception ex)
        {
            _logger.LogError(ex, "Error processing event record");
        }
    }

    private string GetEventMessage(EventRecord record)
    {
        try
        {
            var message = record.FormatDescription() ?? string.Empty;
            // Truncate if too long
            if (message.Length > 200)
            {
                message = message.Substring(0, 200) + "...";
            }
            return message;
        }
        catch
        {
            // FormatDescription can throw if event message template is not found
            return string.Empty;
        }
    }

    private void UpdateSnapshotEventData(EventOccurrenceTracker tracker)
    {
        try
        {
            var eventData = new EventData
            {
                EventId = tracker.EventConfig.EventId,
                Source = tracker.EventConfig.Source,
                Level = tracker.EventConfig.Level,
                Count = tracker.Occurrences.Count,
                LastOccurrence = tracker.LastOccurrence,
                Message = tracker.LastMessage ?? string.Empty
            };

            // Add to snapshot's event log data
            _snapshotService.UpdateEventData(tracker.EventConfig.EventId, eventData);
        }
        catch (Exception ex)
        {
            _logger.LogWarning(ex, "Failed to update snapshot with event data");
        }
    }

    /// <summary>
    /// Extracts the task path from a Task Scheduler event message.
    /// </summary>
    private string? ExtractTaskPath(string? message)
    {
        if (string.IsNullOrEmpty(message)) return null;
        
        // Try to extract task path using regex
        // Common formats:
        // - Task Scheduler successfully completed task "\FolderPath\TaskName"
        // - Task "\FolderPath\TaskName" , instance "{GUID}"
        var match = TaskNamePattern.Match(message);
        if (match.Success && match.Groups.Count > 1)
        {
            var path = match.Groups[1].Value.Trim();
            // Ensure it starts with backslash
            if (!path.StartsWith("\\"))
            {
                path = "\\" + path;
            }
            return path;
        }
        
        // Alternative: look for pattern with quotes
        // Pattern: "\TaskPath\TaskName"
        var quoteMatch = Regex.Match(message, @"""\\([^""]+)""");
        if (quoteMatch.Success && quoteMatch.Groups.Count > 1)
        {
            var path = quoteMatch.Groups[1].Value.Trim();
            if (!path.StartsWith("\\"))
            {
                path = "\\" + path;
            }
            return path;
        }
        
        return null;
    }

    /// <summary>
    /// Gets just the task name from a full task path.
    /// </summary>
    private static string GetTaskNameFromPath(string taskPath)
    {
        var lastSlash = taskPath.LastIndexOf('\\');
        return lastSlash >= 0 && lastSlash < taskPath.Length - 1
            ? taskPath.Substring(lastSlash + 1)
            : taskPath.TrimStart('\\');
    }

    /// <summary>
    /// Checks if a task path matches the ScheduledTaskMonitoring criteria.
    /// Returns true if the task should trigger an alert, false if it should be filtered out.
    /// </summary>
    private bool ShouldAlertForTask(string taskPath)
    {
        var scheduledTaskConfig = _config.CurrentValue?.ScheduledTaskMonitoring;
        
        // If ScheduledTaskMonitoring is disabled or not configured, allow all tasks
        if (scheduledTaskConfig == null || !scheduledTaskConfig.Enabled)
        {
            _logger.LogDebug("ScheduledTaskMonitoring disabled - allowing all task events");
            return true;
        }
        
        var tasksToMonitor = scheduledTaskConfig.TasksToMonitor;
        if (tasksToMonitor == null || !tasksToMonitor.Any())
        {
            _logger.LogDebug("No TasksToMonitor configured - allowing all task events");
            return true;
        }
        
        // Check each monitoring rule
        foreach (var rule in tasksToMonitor)
        {
            if (TaskMatchesRule(taskPath, rule))
            {
                return true;
            }
        }
        
        // No rules matched - filter out this task
        return false;
    }

    /// <summary>
    /// Checks if a task path matches a specific monitoring rule.
    /// </summary>
    private bool TaskMatchesRule(string taskPath, TaskToMonitor rule)
    {
        // Check IgnoreStrings first (if task path contains any ignore string, skip it)
        if (rule.IgnoreStrings != null && rule.IgnoreStrings.Any())
        {
            foreach (var ignoreString in rule.IgnoreStrings)
            {
                if (taskPath.Contains(ignoreString, StringComparison.OrdinalIgnoreCase))
                {
                    _logger.LogTrace("Task '{TaskPath}' ignored due to IgnoreString '{IgnoreString}'", taskPath, ignoreString);
                    return false;
                }
            }
        }
        
        // Check TaskPath pattern
        var ruleTaskPath = rule.TaskPath ?? "\\**";
        
        // Normalize paths for comparison
        var normalizedTaskPath = taskPath.Replace("/", "\\").TrimEnd('\\');
        var normalizedRulePath = ruleTaskPath.Replace("/", "\\").TrimEnd('\\');
        
        bool pathMatches = false;
        
        if (normalizedRulePath == "\\**")
        {
            // Match all tasks
            pathMatches = true;
        }
        else if (normalizedRulePath.EndsWith("\\*"))
        {
            // Wildcard match: \Folder\* matches tasks directly in \Folder\
            var folderPath = normalizedRulePath.Substring(0, normalizedRulePath.Length - 2);
            var taskFolder = GetTaskFolder(normalizedTaskPath);
            pathMatches = taskFolder.Equals(folderPath, StringComparison.OrdinalIgnoreCase);
        }
        else if (normalizedRulePath.EndsWith("\\**"))
        {
            // Recursive match: \Folder\** matches tasks in \Folder\ and subfolders
            var folderPath = normalizedRulePath.Substring(0, normalizedRulePath.Length - 3);
            pathMatches = normalizedTaskPath.StartsWith(folderPath, StringComparison.OrdinalIgnoreCase);
        }
        else
        {
            // Exact match
            pathMatches = normalizedTaskPath.Equals(normalizedRulePath, StringComparison.OrdinalIgnoreCase);
        }
        
        if (!pathMatches)
        {
            return false;
        }
        
        // Note: FilterByUser check would require querying the task's RunAs user,
        // which is expensive for event-based filtering. We skip this for event filtering
        // and rely on the ScheduledTaskMonitor to handle user filtering for task status checks.
        // For events, if the path matches and isn't ignored, we allow the alert.
        
        return true;
    }

    /// <summary>
    /// Gets the folder portion of a task path.
    /// </summary>
    private static string GetTaskFolder(string taskPath)
    {
        var lastSlash = taskPath.LastIndexOf('\\');
        return lastSlash > 0 ? taskPath.Substring(0, lastSlash) : "\\";
    }

    public Task StopAsync(CancellationToken cancellationToken)
    {
        _logger.LogInformation("Stopping EventLogWatcher service...");

        foreach (var watcher in _watchers)
        {
            try
            {
                watcher.Enabled = false;
                watcher.Dispose();
            }
            catch (Exception ex)
            {
                _logger.LogWarning(ex, "Error disposing EventLogWatcher");
            }
        }
        _watchers.Clear();

        _logger.LogDebug("EventLogWatcher service stopped");
        return Task.CompletedTask;
    }

    public void Dispose()
    {
        Dispose(true);
        GC.SuppressFinalize(this);
    }

    protected virtual void Dispose(bool disposing)
    {
        if (_disposed) return;

        if (disposing)
        {
            foreach (var watcher in _watchers)
            {
                try
                {
                    watcher.Dispose();
                }
                catch { }
            }
            _watchers.Clear();
        }

        _disposed = true;
    }

    /// <summary>
    /// Tracks occurrences of a specific event within its time window
    /// </summary>
    private class EventOccurrenceTracker
    {
        public EventToMonitor EventConfig { get; set; } = null!;
        public List<DateTime> Occurrences { get; set; } = new();
        public DateTime? LastOccurrence { get; set; }
        public string? LastMessage { get; set; }
    }
}
