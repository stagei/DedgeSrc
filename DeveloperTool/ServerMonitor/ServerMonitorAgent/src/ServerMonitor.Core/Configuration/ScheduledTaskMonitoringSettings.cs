namespace ServerMonitor.Core.Configuration;

/// <summary>
/// Configuration for scheduled task monitoring
/// </summary>
public class ScheduledTaskMonitoringSettings
{
    public bool Enabled { get; init; } = true;
    public int PollingIntervalSeconds { get; init; } = 300;
    public ScheduledTaskAlerts Alerts { get; init; } = new();
    public List<TaskToMonitor> TasksToMonitor { get; init; } = new();
}

public class ScheduledTaskAlerts
{
    public string DisabledTaskSeverity { get; init; } = "Warning";
    public string FailedTaskSeverity { get; init; } = "Critical";
    public string MissedRunSeverity { get; init; } = "Warning";
    public string OverdueTaskSeverity { get; init; } = "Warning";
    
    /// <summary>
    /// Maximum occurrences before triggering an alert. Default: 0 (immediate alert).
    /// </summary>
    public int MaxOccurrences { get; init; } = 0;
    
    /// <summary>
    /// Time window in minutes for counting occurrences AND cooldown after alerting. Default: 60 minutes.
    /// </summary>
    public int TimeWindowMinutes { get; init; } = 60;
}

public class TaskToMonitor
{
    /// <summary>
    /// Task path with wildcard support
    /// Examples:
    ///   "\Microsoft\Windows\Backup\Windows Backup Monitor" (specific task)
    ///   "\Microsoft\Windows\Backup\*" (all tasks in Backup folder only, not subfolders)
    ///   "\MyCompany\*" (all tasks in MyCompany folder only, not subfolders)
    ///   "\*" (all tasks in root folder only)
    ///   "\**" (all tasks in all folders recursively - use with FilterByUser for best results)
    /// </summary>
    public string TaskPath { get; init; } = string.Empty;
    
    /// <summary>
    /// Friendly description of the task or task group
    /// </summary>
    public string Description { get; init; } = string.Empty;
    
    /// <summary>
    /// Monitor only tasks created by/running as specific user
    /// Examples:
    ///   "DOMAIN\\username" (specific user)
    ///   "{CurrentUser}" (same user as the surveillance tool)
    ///   null or empty (all users)
    /// </summary>
    public string? FilterByUser { get; init; }
    
    /// <summary>
    /// Alert if task last run result was a failure
    /// </summary>
    public bool AlertOnFailure { get; init; } = true;
    
    /// <summary>
    /// Alert if task hasn't run within expected timeframe
    /// </summary>
    public bool AlertOnMissedRun { get; init; } = true;
    
    /// <summary>
    /// Maximum minutes since last successful run before alerting
    /// </summary>
    public int MaxMinutesSinceLastRun { get; init; } = 1440; // 24 hours
    
    /// <summary>
    /// Alert if task is disabled
    /// </summary>
    public bool AlertIfDisabled { get; init; } = true;
    
    /// <summary>
    /// Array of strings to ignore. Tasks or task folders containing any of these strings (case-insensitive) will be excluded from monitoring.
    /// Examples: ["Windows", "Microsoft", "System"]
    /// </summary>
    public List<string> IgnoreStrings { get; init; } = new();
    
    /// <summary>
    /// List of channel types to suppress for alerts generated from this task configuration (e.g., ["SMS", "Email"]).
    /// Channel types must match the Type in Alerting.Channels (SMS, Email, EventLog, File, WKMonitor).
    /// If empty, all enabled channels will be used (default behavior).
    /// </summary>
    public List<string> SuppressedChannels { get; init; } = new();
}

