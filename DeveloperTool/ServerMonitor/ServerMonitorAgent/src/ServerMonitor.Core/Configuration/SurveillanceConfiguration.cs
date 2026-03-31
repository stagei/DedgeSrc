namespace ServerMonitor.Core.Configuration;

/// <summary>
/// Root configuration for the surveillance tool
/// </summary>
public class SurveillanceConfiguration
{
    public GeneralSettings General { get; init; } = new();
    public LoggingSettings Logging { get; init; } = new();
    public RuntimeSettings Runtime { get; init; } = new();
    public SelfMonitoringSettings SelfMonitoring { get; init; } = new();
    public ProcessorMonitoringSettings ProcessorMonitoring { get; init; } = new();
    public MemoryMonitoringSettings MemoryMonitoring { get; init; } = new();
    public VirtualMemoryMonitoringSettings VirtualMemoryMonitoring { get; init; } = new();
    public DiskUsageMonitoringSettings DiskUsageMonitoring { get; init; } = new();
    public DiskSpaceMonitoringSettings DiskSpaceMonitoring { get; init; } = new();
    public NetworkMonitoringSettings NetworkMonitoring { get; init; } = new();
    public UptimeMonitoringSettings UptimeMonitoring { get; init; } = new();
    public WindowsUpdateMonitoringSettings WindowsUpdateMonitoring { get; init; } = new();
    public EventMonitoringSettings EventMonitoring { get; init; } = new();
    public ScheduledTaskMonitoringSettings ScheduledTaskMonitoring { get; init; } = new();
    public Db2DiagMonitoringSettings Db2DiagMonitoring { get; init; } = new();
    public Db2InstanceMonitoringSettings Db2InstanceMonitoring { get; init; } = new();
    public IisMonitoringSettings IisMonitoring { get; init; } = new();
    public ExportSettings ExportSettings { get; init; } = new();
    public AlertingSettings Alerting { get; init; } = new();
    public RestApiSettings? RestApi { get; init; }
    public PerformanceScalingSettings PerformanceScaling { get; init; } = new();
}

public class RestApiSettings
{
    public bool Enabled { get; init; } = true;
    public int Port { get; init; } = 5000;
    public bool EnableSwagger { get; init; } = true;
    public bool AutoConfigureFirewall { get; init; } = true;
}

public class GeneralSettings
{
    public string ServerName { get; init; } = Environment.MachineName;
    public bool MonitoringEnabled { get; init; } = true;
    public int DataRetentionHours { get; init; } = 720; // 30 days
    
    /// <summary>
    /// Memory management settings for in-memory data cleanup
    /// </summary>
    public MemoryManagementSettings MemoryManagement { get; init; } = new();
}

/// <summary>
/// Configuration for automatic memory cleanup of in-memory collections
/// </summary>
public class MemoryManagementSettings
{
    /// <summary>
    /// Maximum age in hours for in-memory data before automatic cleanup.
    /// Applies to: Alerts, ExternalEvents, ProcessCpuTracker measurements, AlertManager tracking dictionaries.
    /// Cleanup runs hourly. Default: 24 hours.
    /// </summary>
    public int CleanupAgeHours { get; init; } = 24;
    
    /// <summary>
    /// Maximum number of alerts to keep in memory. Oldest alerts are removed first.
    /// Default: 1000. Set to 0 for unlimited (not recommended).
    /// </summary>
    public int MaxAlertsInMemory { get; init; } = 1000;
    
    /// <summary>
    /// How often to run memory cleanup (in minutes).
    /// Default: 60 (every hour).
    /// </summary>
    public int CleanupIntervalMinutes { get; init; } = 60;
}

public class LoggingSettings
{
    /// <summary>
    /// Directory where log files will be stored.
    /// Default: C:\opt\data\ServerMonitor
    /// </summary>
    public string LogDirectory { get; init; } = @"C:\opt\data\ServerMonitor";
    
    /// <summary>
    /// Application name used in log file names.
    /// Log files will be named: {AppName}_{date}.log
    /// Default: ServerMonitor
    /// </summary>
    public string AppName { get; init; } = "ServerMonitor";
}

public class RuntimeSettings
{
    /// <summary>
    /// Auto-shutdown time in HH:mm format (e.g., "23:30"). Leave null/empty for indefinite runtime.
    /// Service will automatically restart if configured as Windows Service.
    /// </summary>
    public string? AutoShutdownTime { get; init; }
    
    /// <summary>
    /// Maximum runtime in hours. Leave null/0 for indefinite runtime.
    /// </summary>
    public int? MaxRuntimeHours { get; init; }
    
    /// <summary>
    /// Test timeout in seconds. Application will exit after this many seconds. Leave null for no timeout.
    /// Useful for testing to prevent hanging. Default: null (no timeout).
    /// </summary>
    public int? TestTimeoutSeconds { get; init; }
    
    /// <summary>
    /// Configuration reload interval in minutes. The application will reload appsettings.json
    /// at this interval to pick up changes without restart. Default: 5 minutes.
    /// Set to 0 or null to disable periodic reload.
    /// </summary>
    public int? ConfigReloadIntervalMinutes { get; init; }
    
    /// <summary>
    /// Path to common appsettings.json file (typically on UNC share).
    /// If set, the application will check this file after initial load and sync it to local appsettings.json
    /// if the file hash differs. If UNC path is unreachable, falls back to local appsettings.json.
    /// </summary>
    public string? CommonAppsettingsFile { get; init; }
    
    /// <summary>
    /// Development mode flag. When true, skips syncing CommonAppsettingsFile from UNC path.
    /// Useful for local development/testing where UNC paths may not be accessible.
    /// Default: false (sync enabled in production).
    /// </summary>
    public bool DevMode { get; init; } = false;
    
    /// <summary>
    /// Number of hours after agent startup to flush all accumulated alert data.
    /// When set, the agent will clear all alert accumulators X hours after startup.
    /// Set to null to disable time-based flushing.
    /// Example: 12 means flush 12 hours after startup.
    /// </summary>
    public int? FlushAccumulatorAfterHours { get; init; }
    
    /// <summary>
    /// Time of day (HH:mm format) to flush all accumulated alert data.
    /// When set, the agent will clear all alert accumulators at this time each day.
    /// Set to null to disable scheduled flushing.
    /// Example: "23:59" means flush at 11:59 PM daily.
    /// </summary>
    public string? FlushAccumulatorAtTime { get; init; }
}

public class ProcessorMonitoringSettings
{
    public bool Enabled { get; init; } = true;
    public int PollingIntervalSeconds { get; init; } = 5;
    public ThresholdSettings Thresholds { get; init; } = new();
    public ProcessorAlerts Alerts { get; init; } = new();
    public bool PerCoreMonitoring { get; init; } = true;
    public int TrackTopProcesses { get; init; } = 5;
    
    /// <summary>
    /// Process cache refresh interval in seconds. Full process list is refreshed at this interval.
    /// Default: 120 seconds (2 minutes). Lower values = more accurate but higher CPU usage.
    /// </summary>
    public int ProcessCacheRefreshSeconds { get; init; } = 120;
    
    /// <summary>
    /// Service mapping cache refresh interval in minutes. Service-to-process mapping is refreshed at this interval.
    /// Default: 10 minutes. Lower values = more accurate but higher CPU usage.
    /// </summary>
    public int ServiceMapRefreshMinutes { get; init; } = 10;
    
    /// <summary>
    /// Enable enhanced process metadata collection (executable path, command line, service association, etc.).
    /// Default: true. Set to false to use basic process info only (faster, less CPU usage).
    /// </summary>
    public bool EnhancedProcessMetadata { get; init; } = true;
    
    /// <summary>
    /// List of channel types to suppress for alerts generated by this monitor (e.g., ["SMS", "Email"]).
    /// Channel types must match the Type in Alerting.Channels (SMS, Email, EventLog, File, WKMonitor).
    /// If empty, all enabled channels will be used (default behavior).
    /// </summary>
    public List<string> SuppressedChannels { get; init; } = new();
}

public class ProcessorAlerts
{
    public string WarningAlertSeverity { get; init; } = "Warning";
    public string CriticalAlertSeverity { get; init; } = "Critical";
    
    /// <summary>
    /// Maximum occurrences before triggering an alert. Default: 0 (immediate alert when threshold exceeded).
    /// When set to 0, the first occurrence of threshold exceeded triggers an alert.
    /// When set > 0, the count of threshold-exceeded events must exceed this value.
    /// </summary>
    public int MaxOccurrences { get; init; } = 0;
    
    /// <summary>
    /// Time window in minutes for counting occurrences AND cooldown after alerting.
    /// Default: 5 minutes. After an alert is sent, no new alerts for this category
    /// will be sent for this many minutes (cooldown period).
    /// </summary>
    public int TimeWindowMinutes { get; init; } = 5;
}

public class ThresholdSettings
{
    public double WarningPercent { get; init; } = 80;
    public double CriticalPercent { get; init; } = 95;
    public int SustainedDurationSeconds { get; init; } = 300;
}

public class MemoryMonitoringSettings
{
    public bool Enabled { get; init; } = true;
    public int PollingIntervalSeconds { get; init; } = 10;
    public ThresholdSettings Thresholds { get; init; } = new();
    public MemoryAlerts Alerts { get; init; } = new();
    public int TrackTopProcesses { get; init; } = 5;
    
    /// <summary>
    /// Process cache refresh interval in seconds. Full process list is refreshed at this interval.
    /// Default: 120 seconds (2 minutes). Lower values = more accurate but higher CPU usage.
    /// </summary>
    public int ProcessCacheRefreshSeconds { get; init; } = 120;
    
    /// <summary>
    /// Service mapping cache refresh interval in minutes. Service-to-process mapping is refreshed at this interval.
    /// Default: 10 minutes. Lower values = more accurate but higher CPU usage.
    /// </summary>
    public int ServiceMapRefreshMinutes { get; init; } = 10;
    
    /// <summary>
    /// Enable enhanced process metadata collection (executable path, command line, service association, etc.).
    /// Default: true. Set to false to use basic process info only (faster, less CPU usage).
    /// </summary>
    public bool EnhancedProcessMetadata { get; init; } = true;
    
    /// <summary>
    /// List of channel types to suppress for alerts generated by this monitor (e.g., ["SMS", "Email"]).
    /// Channel types must match the Type in Alerting.Channels (SMS, Email, EventLog, File, WKMonitor).
    /// If empty, all enabled channels will be used (default behavior).
    /// </summary>
    public List<string> SuppressedChannels { get; init; } = new();
}

public class MemoryAlerts
{
    public string WarningAlertSeverity { get; init; } = "Warning";
    public string CriticalAlertSeverity { get; init; } = "Critical";
    
    /// <summary>
    /// Maximum occurrences before triggering an alert. Default: 0 (immediate alert when threshold exceeded).
    /// </summary>
    public int MaxOccurrences { get; init; } = 0;
    
    /// <summary>
    /// Time window in minutes for counting occurrences AND cooldown after alerting. Default: 5 minutes.
    /// </summary>
    public int TimeWindowMinutes { get; init; } = 5;
}

public class VirtualMemoryMonitoringSettings
{
    public bool Enabled { get; init; } = true;
    public int PollingIntervalSeconds { get; init; } = 10;
    public VirtualMemoryThresholds Thresholds { get; init; } = new();
    public VirtualMemoryAlerts Alerts { get; init; } = new();
    
    /// <summary>
    /// List of channel types to suppress for alerts generated by this monitor (e.g., ["SMS", "Email"]).
    /// Channel types must match the Type in Alerting.Channels (SMS, Email, EventLog, File, WKMonitor).
    /// If empty, all enabled channels will be used (default behavior).
    /// </summary>
    public List<string> SuppressedChannels { get; init; } = new();
}

public class VirtualMemoryAlerts
{
    public string WarningAlertSeverity { get; init; } = "Warning";
    public string CriticalAlertSeverity { get; init; } = "Critical";
    
    /// <summary>
    /// Maximum occurrences before triggering an alert. Default: 0 (immediate alert when threshold exceeded).
    /// </summary>
    public int MaxOccurrences { get; init; } = 0;
    
    /// <summary>
    /// Time window in minutes for counting occurrences AND cooldown after alerting. Default: 5 minutes.
    /// </summary>
    public int TimeWindowMinutes { get; init; } = 5;
}

public class VirtualMemoryThresholds
{
    public double WarningPercent { get; init; } = 80;
    public double CriticalPercent { get; init; } = 90;
    public int SustainedDurationSeconds { get; init; } = 300;
    public double ExcessivePagingRate { get; init; } = 1000;
}

public class DiskUsageMonitoringSettings
{
    public bool Enabled { get; init; } = true;
    public int PollingIntervalSeconds { get; init; } = 15;
    public List<string> DisksToMonitor { get; init; } = new() { "C:" };
    public DiskUsageThresholds Thresholds { get; init; } = new();
    public DiskUsageAlerts Alerts { get; init; } = new();
    
    /// <summary>
    /// List of channel types to suppress for alerts generated by this monitor (e.g., ["SMS", "Email"]).
    /// Channel types must match the Type in Alerting.Channels (SMS, Email, EventLog, File, WKMonitor).
    /// If empty, all enabled channels will be used (default behavior).
    /// </summary>
    public List<string> SuppressedChannels { get; init; } = new();
}

public class DiskUsageAlerts
{
    public string AlertSeverity { get; init; } = "Warning";
    
    /// <summary>
    /// Maximum occurrences before triggering an alert. Default: 0 (immediate alert when threshold exceeded).
    /// </summary>
    public int MaxOccurrences { get; init; } = 0;
    
    /// <summary>
    /// Time window in minutes for counting occurrences AND cooldown after alerting. Default: 5 minutes.
    /// </summary>
    public int TimeWindowMinutes { get; init; } = 5;
}

public class DiskUsageThresholds
{
    public double MaxQueueLength { get; init; } = 10;
    public double MaxResponseTimeMs { get; init; } = 50;
    public int SustainedDurationSeconds { get; init; } = 180;
}

public class DiskSpaceMonitoringSettings
{
    public bool Enabled { get; init; } = true;
    public int PollingIntervalSeconds { get; init; } = 300;
    public List<string> DisksToMonitor { get; init; } = new() { "C:" };
    public DiskSpaceThresholds Thresholds { get; init; } = new();
    public DiskSpaceAlerts Alerts { get; init; } = new();
    
    /// <summary>
    /// List of channel types to suppress for alerts generated by this monitor (e.g., ["SMS", "Email"]).
    /// Channel types must match the Type in Alerting.Channels (SMS, Email, EventLog, File, WKMonitor).
    /// If empty, all enabled channels will be used (default behavior).
    /// </summary>
    public List<string> SuppressedChannels { get; init; } = new();
}

public class DiskSpaceAlerts
{
    public string WarningAlertSeverity { get; init; } = "Warning";
    public string CriticalAlertSeverity { get; init; } = "Critical";
    
    /// <summary>
    /// Maximum occurrences before triggering an alert. Default: 0 (immediate alert when threshold exceeded).
    /// </summary>
    public int MaxOccurrences { get; init; } = 0;
    
    /// <summary>
    /// Time window in minutes for counting occurrences AND cooldown after alerting. Default: 60 minutes.
    /// </summary>
    public int TimeWindowMinutes { get; init; } = 60;
}

public class DiskSpaceThresholds
{
    public double WarningPercent { get; init; } = 85;
    public double CriticalPercent { get; init; } = 95;
    public double MinimumFreeSpaceGB { get; init; } = 10;
}

public class NetworkMonitoringSettings
{
    public bool Enabled { get; init; } = true;
    public int PollingIntervalSeconds { get; init; } = 30;
    public NetworkAlerts Alerts { get; init; } = new();
    public List<BaselineHost> BaselineHosts { get; init; } = new();
    
    /// <summary>
    /// List of channel types to suppress for alerts generated by this monitor (e.g., ["SMS", "Email"]).
    /// Channel types must match the Type in Alerting.Channels (SMS, Email, EventLog, File, WKMonitor).
    /// If empty, all enabled channels will be used (default behavior).
    /// </summary>
    public List<string> SuppressedChannels { get; init; } = new();
}

public class NetworkAlerts
{
    public string ConnectivityLostSeverity { get; init; } = "Critical";
    public string HighLatencySeverity { get; init; } = "Warning";
    public string PacketLossSeverity { get; init; } = "Warning";
    public string PortUnreachableSeverity { get; init; } = "Critical";
    
    /// <summary>
    /// Maximum occurrences before triggering an alert. Default: 0 (immediate alert when threshold exceeded).
    /// </summary>
    public int MaxOccurrences { get; init; } = 0;
    
    /// <summary>
    /// Time window in minutes for counting occurrences AND cooldown after alerting. Default: 5 minutes.
    /// </summary>
    public int TimeWindowMinutes { get; init; } = 5;
}

public class BaselineHost
{
    public string Hostname { get; init; } = string.Empty;
    public string? IpAddress { get; init; }
    public string Description { get; init; } = string.Empty;
    public bool CheckPing { get; init; } = true;
    public bool CheckDns { get; init; } = true;
    public List<int> PortsToCheck { get; init; } = new();
    public NetworkThresholds Thresholds { get; init; } = new();
}

public class NetworkThresholds
{
    public double MaxPingMs { get; init; } = 50;
    public double MaxPacketLossPercent { get; init; } = 5;
    public int ConsecutiveFailuresBeforeAlert { get; init; } = 3;
}

public class UptimeMonitoringSettings
{
    public bool Enabled { get; init; } = true;
    public int PollingIntervalSeconds { get; init; } = 60;
    public UptimeAlerts Alerts { get; init; } = new();
    
    /// <summary>
    /// List of channel types to suppress for alerts generated by this monitor (e.g., ["SMS", "Email"]).
    /// Channel types must match the Type in Alerting.Channels (SMS, Email, EventLog, File, WKMonitor).
    /// If empty, all enabled channels will be used (default behavior).
    /// </summary>
    public List<string> SuppressedChannels { get; init; } = new();
}

public class UptimeAlerts
{
    public bool UnexpectedRebootAlert { get; init; } = true;
    public int MinimumUptimeDaysWarning { get; init; } = 90;
    public int MaximumUptimeDaysWarning { get; init; } = 365;
    public string UnexpectedRebootSeverity { get; init; } = "Critical";
    public string ExcessiveUptimeSeverity { get; init; } = "Warning";
    public string DirtyShutdownSeverity { get; init; } = "Warning";
    
    /// <summary>
    /// Maximum occurrences before triggering an alert. Default: 0 (immediate alert on reboot).
    /// </summary>
    public int MaxOccurrences { get; init; } = 0;
    
    /// <summary>
    /// Time window in minutes for counting occurrences AND cooldown after alerting. Default: 60 minutes.
    /// </summary>
    public int TimeWindowMinutes { get; init; } = 60;
}

public class WindowsUpdateMonitoringSettings
{
    public bool Enabled { get; init; } = true;
    public int PollingIntervalSeconds { get; init; } = 3600;
    public WindowsUpdateThresholds Thresholds { get; init; } = new();
    public WindowsUpdateAlerts Alerts { get; init; } = new();
    
    /// <summary>
    /// List of channel types to suppress for alerts generated by this monitor (e.g., ["SMS", "Email"]).
    /// Channel types must match the Type in Alerting.Channels (SMS, Email, EventLog, File, WKMonitor).
    /// If empty, all enabled channels will be used (default behavior).
    /// </summary>
    public List<string> SuppressedChannels { get; init; } = new();
}

public class WindowsUpdateThresholds
{
    public int MaxPendingSecurityUpdates { get; init; } = 0;
    public int MaxPendingCriticalUpdates { get; init; } = 0;
    public int MaxDaysSinceLastUpdate { get; init; } = 30;
}

public class WindowsUpdateAlerts
{
    public bool AlertOnPendingSecurityUpdates { get; init; } = true;
    public bool AlertOnFailedInstallations { get; init; } = true;
    
    /// <summary>
    /// Alert severity level for pending security updates.
    /// Valid values: "Informational", "Warning", "Critical". Default: "Warning".
    /// </summary>
    public string SecurityUpdateAlertSeverity { get; init; } = "Warning";
    
    /// <summary>
    /// Alert severity level for pending critical updates.
    /// Valid values: "Informational", "Warning", "Critical". Default: "Warning".
    /// </summary>
    public string CriticalUpdateAlertSeverity { get; init; } = "Warning";
    
    /// <summary>
    /// Alert severity level for days since last update exceeded.
    /// Valid values: "Informational", "Warning", "Critical". Default: "Warning".
    /// </summary>
    public string DaysSinceLastUpdateSeverity { get; init; } = "Warning";
    
    /// <summary>
    /// Maximum occurrences before triggering an alert. Default: 0 (immediate alert).
    /// </summary>
    public int MaxOccurrences { get; init; } = 0;
    
    /// <summary>
    /// Time window in minutes for counting occurrences AND cooldown after alerting. Default: 1440 (24 hours).
    /// </summary>
    public int TimeWindowMinutes { get; init; } = 1440;
}

public class EventMonitoringSettings
{
    public bool Enabled { get; init; } = true;
    public int PollingIntervalSeconds { get; init; } = 60;
    public List<EventToMonitor> EventsToMonitor { get; init; } = new();
}

public class EventToMonitor
{
    /// <summary>
    /// If false, this specific event will be skipped during monitoring.
    /// Default: true
    /// </summary>
    public bool Enabled { get; init; } = true;
    
    public int EventId { get; init; }
    public string Description { get; init; } = string.Empty;
    public string Source { get; init; } = string.Empty;
    public string LogName { get; init; } = string.Empty;
    public string Level { get; init; } = string.Empty;
    public int MaxOccurrences { get; init; } = 5;
    public int TimeWindowMinutes { get; init; } = 15;
    
    /// <summary>
    /// If true, uses real-time system hooks (e.g., SystemEvents.SessionEnding) instead of polling.
    /// This is more reliable for critical events like shutdown (Event ID 1074) that occur
    /// when the service is stopping. Only applicable to specific system events.
    /// Default: false (uses polling)
    /// </summary>
    public bool UseRealTimeHooks { get; init; } = false;
    
    /// <summary>
    /// List of channel types to suppress for alerts generated from this event configuration (e.g., ["SMS", "Email"]).
    /// Channel types must match the Type in Alerting.Channels (SMS, Email, EventLog, File, WKMonitor).
    /// If empty, all enabled channels will be used (default behavior).
    /// </summary>
    public List<string> SuppressedChannels { get; init; } = new();
}

public class ExportSettings
{
    public bool Enabled { get; init; } = true;
    
    /// <summary>
    /// Single output directory (for backward compatibility).
    /// If OutputDirectories is specified, this is ignored.
    /// </summary>
    public string? OutputDirectory { get; init; }
    
    /// <summary>
    /// List of output directories to write snapshots to.
    /// Supports both local paths (e.g., "C:\opt\data\Snapshots") and UNC paths (e.g., "\\server\share\Snapshots").
    /// Files are written to all specified directories.
    /// If empty and OutputDirectory is set, OutputDirectory is used.
    /// </summary>
    public List<string> OutputDirectories { get; init; } = new();
    
    public string FileNamePattern { get; init; } = "{ServerName}_{Timestamp:yyyyMMdd_HHmmss}.json";
    public ExportIntervals ExportIntervals { get; init; } = new();
    public RetentionSettings Retention { get; init; } = new();
}

public class ExportIntervals
{
    /// <summary>
    /// Export interval in minutes (e.g., 30 = every 30 minutes)
    /// If null or 0, uses ScheduleMinutes instead
    /// </summary>
    public int? IntervalMinutes { get; init; } = 30;
    
    /// <summary>
    /// Specific minutes of the hour to export (legacy, use IntervalMinutes instead)
    /// Only used if IntervalMinutes is null or 0
    /// </summary>
    public List<int>? ScheduleMinutes { get; init; }
    
    public bool OnAlertTrigger { get; init; } = true;
    public bool OnDemand { get; init; } = true;
}

public class RetentionSettings
{
    public int MaxAgeHours { get; init; } = 720;
    public int MaxFileCount { get; init; } = 1000;
    public bool CompressionEnabled { get; init; } = true;
}

public class AlertingSettings
{
    public bool Enabled { get; init; } = true;
    public List<AlertChannelConfig> Channels { get; set; } = new();  // Changed to 'set' for config binding
    public ThrottlingSettings Throttling { get; init; } = new();
    
    /// <summary>
    /// Global list of channel types to suppress for all alerts (e.g., ["SMS", "Email"]).
    /// Channel types must match the Type in Channels (SMS, Email, EventLog, File, WKMonitor).
    /// If empty, no global suppression is applied. Alert-specific SuppressedChannels will be merged with this list.
    /// </summary>
    public List<string> SuppressedChannels { get; init; } = new();
    
    /// <summary>
    /// Per-category channel suppression. Key is alert category (e.g., "Processor", "Memory"), value is list of channel types to suppress.
    /// Example: { "Processor": ["SMS"], "Memory": ["Email", "SMS"] }
    /// </summary>
    public Dictionary<string, List<string>> CategorySuppressions { get; init; } = new();
}

public class AlertChannelConfig
{
    public string Type { get; init; } = string.Empty;
    public bool Enabled { get; init; } = true;
    public string MinSeverity { get; init; } = "Warning";
    public Dictionary<string, object> Settings { get; init; } = new();
}

public class ThrottlingSettings
{
    public bool Enabled { get; init; } = true;
    public int MaxAlertsPerHour { get; init; } = 50;
    
    /// <summary>
    /// Suppression interval for Warning alerts (in minutes)
    /// </summary>
    public int WarningSuppressionMinutes { get; init; } = 60;
    
    /// <summary>
    /// Suppression interval for Error/Critical alerts (in minutes)
    /// </summary>
    public int ErrorSuppressionMinutes { get; init; } = 15;
    
    /// <summary>
    /// Suppression interval for Informational alerts (in minutes)
    /// </summary>
    public int InformationalSuppressionMinutes { get; init; } = 120;
    
    /// <summary>
    /// Legacy setting - kept for backward compatibility, not used
    /// </summary>
    [Obsolete("Use severity-specific suppression settings instead")]
    public int DuplicateSuppressionMinutes { get; init; } = 15;
}

/// <summary>
/// Self-monitoring settings for ServerMonitor.exe process health
/// </summary>
public class SelfMonitoringSettings
{
    /// <summary>
    /// Enable self-monitoring of ServerMonitor.exe memory usage.
    /// Default: true.
    /// </summary>
    public bool Enabled { get; init; } = true;
    
    /// <summary>
    /// Memory usage threshold in MB. If ServerMonitor.exe exceeds this, a warning alert is generated
    /// and the process will gracefully shutdown after ShutdownDelaySeconds.
    /// Default: 3072 MB (3 GB).
    /// </summary>
    public int MemoryThresholdMB { get; init; } = 3072;
    
    /// <summary>
    /// Delay in seconds before shutdown after memory threshold is exceeded.
    /// Allows time for alert to be sent and snapshot to be saved.
    /// Default: 10 seconds.
    /// </summary>
    public int ShutdownDelaySeconds { get; init; } = 10;
    
    /// <summary>
    /// How often to check memory usage (in seconds).
    /// Default: 30 seconds.
    /// </summary>
    public int CheckIntervalSeconds { get; init; } = 30;
    
    /// <summary>
    /// Alert severity when memory threshold is exceeded.
    /// Default: Warning.
    /// </summary>
    public string MemoryAlertSeverity { get; init; } = "Warning";
}

