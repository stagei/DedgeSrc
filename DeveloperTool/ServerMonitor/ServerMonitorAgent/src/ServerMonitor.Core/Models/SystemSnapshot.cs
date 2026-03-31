namespace ServerMonitor.Core.Models;

/// <summary>
/// Complete point-in-time snapshot of system state
/// </summary>
public class SystemSnapshot
{
    public SnapshotMetadata Metadata { get; set; } = new();
    public ProcessorData? Processor { get; set; }
    public MemoryData? Memory { get; set; }
    public VirtualMemoryData? VirtualMemory { get; set; }
    public DiskData? Disks { get; set; }
    public List<NetworkHostData> Network { get; set; } = new();
    public UptimeData? Uptime { get; set; }
    public WindowsUpdateData? WindowsUpdates { get; set; }
    public List<EventData> Events { get; set; } = new();
    public List<ServiceData> Services { get; set; } = new();
    public List<ScheduledTaskData> ScheduledTasks { get; set; } = new();
    public Db2DiagData? Db2Diagnostics { get; set; }
    public Db2InstanceSnapshot? Db2Instance { get; set; }
    public IisSnapshot? Iis { get; set; }
    public List<Alert> Alerts { get; set; } = new();
    public List<ExternalEvent> ExternalEvents { get; set; } = new();
}

public class SnapshotMetadata
{
    public string ServerName { get; set; } = Environment.MachineName;
    public DateTime Timestamp { get; set; } = DateTime.UtcNow;
    public Guid SnapshotId { get; set; } = Guid.NewGuid();
    public long CollectionDurationMs { get; set; }
    public string ToolVersion { get; set; } = "1.0.0";
    
    /// <summary>
    /// Configuration context including thresholds, paths, and other settings used for monitoring
    /// </summary>
    public ConfigurationContext? Configuration { get; set; }
    
    /// <summary>
    /// When this snapshot was persisted to disk (if applicable)
    /// </summary>
    public DateTime? PersistedAt { get; set; }
    
    /// <summary>
    /// True if this snapshot was restored from a persisted file on startup
    /// </summary>
    public bool RestoredFromPersistence { get; set; }
    
    /// <summary>
    /// ServerMonitor.exe process memory usage in MB (self-monitoring)
    /// </summary>
    public double ProcessMemoryMB { get; set; }
    
    /// <summary>
    /// Estimated size of in-memory snapshot data in MB
    /// </summary>
    public double SnapshotSizeMB { get; set; }
    
    /// <summary>
    /// UNC path to the current log file for remote access
    /// </summary>
    public string? LogFileUncPath { get; set; }
}

public class ConfigurationContext
{
    /// <summary>
    /// Log file directory path
    /// </summary>
    public string LogDirectory { get; init; } = string.Empty;
    /// <summary>
    /// Log file directory path (UNC version)
    /// </summary>
    public string LogDirectoryUnc { get; init; } = string.Empty;
    /// <summary>
    /// Application name used in log file names
    /// </summary>
    public string AppName { get; init; } = string.Empty;
    /// <summary>
    /// Snapshot export output directories
    /// </summary>
    public List<string> SnapshotOutputDirectories { get; init; } = new();
    /// <summary>
    /// Snapshot export output directories (UNC versions)
    /// </summary>
    public List<string> SnapshotOutputDirectoriesUnc { get; init; } = new();
    /// <summary>
    /// Snapshot export file name pattern
    /// </summary>
    public string SnapshotFileNamePattern { get; init; } = string.Empty;
    /// <summary>
    /// Alert log file path
    /// </summary>
    public string AlertLogPath { get; init; } = string.Empty;
    /// <summary>
    /// Alert log file path (UNC version)
    /// </summary>
    public string AlertLogPathUnc { get; init; } = string.Empty;
    /// <summary>
    /// Processor monitoring configuration
    /// </summary>
    public MonitorConfigContext? ProcessorMonitoring { get; init; }
    /// <summary>
    /// Memory monitoring configuration
    /// </summary>
    public MonitorConfigContext? MemoryMonitoring { get; init; }
    /// <summary>
    /// Virtual memory monitoring configuration
    /// </summary>
    public VirtualMemoryConfigContext? VirtualMemoryMonitoring { get; init; }
    /// <summary>
    /// Disk space monitoring configuration
    /// </summary>
    public DiskSpaceConfigContext? DiskSpaceMonitoring { get; init; }
    /// <summary>
    /// Disk usage (I/O) monitoring configuration
    /// </summary>
    public DiskUsageConfigContext? DiskUsageMonitoring { get; init; }
    /// <summary>
    /// Windows Update monitoring configuration
    /// </summary>
    public WindowsUpdateConfigContext? WindowsUpdateMonitoring { get; init; }
    /// <summary>
    /// Export settings
    /// </summary>
    public ExportConfigContext? ExportSettings { get; init; }
    /// <summary>
    /// Alerting settings
    /// </summary>
    public AlertingConfigContext? Alerting { get; init; }
    /// <summary>
    /// REST API settings
    /// </summary>
    public RestApiConfigContext? RestApi { get; init; }
}

public class MonitorConfigContext
{
    public bool Enabled { get; init; }
    public int PollingIntervalSeconds { get; init; }
    public double WarningPercent { get; init; }
    public double CriticalPercent { get; init; }
    public int SustainedDurationSeconds { get; init; }
    public int TrackTopProcesses { get; init; }
    public int ProcessCacheRefreshSeconds { get; init; }
    public int ServiceMapRefreshMinutes { get; init; }
    public bool EnhancedProcessMetadata { get; init; }
}

public class VirtualMemoryConfigContext
{
    public bool Enabled { get; init; }
    public int PollingIntervalSeconds { get; init; }
    public double WarningPercent { get; init; }
    public double CriticalPercent { get; init; }
    public int SustainedDurationSeconds { get; init; }
    public double ExcessivePagingRate { get; init; }
}

public class DiskSpaceConfigContext
{
    public bool Enabled { get; init; }
    public int PollingIntervalSeconds { get; init; }
    public List<string> DisksToMonitor { get; init; } = new();
    public double WarningPercent { get; init; }
    public double CriticalPercent { get; init; }
    public double MinimumFreeSpaceGB { get; init; }
}

public class DiskUsageConfigContext
{
    public bool Enabled { get; init; }
    public int PollingIntervalSeconds { get; init; }
    public List<string> DisksToMonitor { get; init; } = new();
    public double MaxQueueLength { get; init; }
    public double MaxResponseTimeMs { get; init; }
    public int SustainedDurationSeconds { get; init; }
}

public class WindowsUpdateConfigContext
{
    public bool Enabled { get; init; }
    public int PollingIntervalSeconds { get; init; }
    public int MaxPendingSecurityUpdates { get; init; }
    public int MaxPendingCriticalUpdates { get; init; }
    public int MaxDaysSinceLastUpdate { get; init; }
    public bool AlertOnPendingSecurityUpdates { get; init; }
}

public class ExportConfigContext
{
    public bool Enabled { get; init; }
    public int? IntervalMinutes { get; init; }
    public bool OnAlertTrigger { get; init; }
    public bool OnDemand { get; init; }
    public int MaxAgeHours { get; init; }
    public int MaxFileCount { get; init; }
    public bool CompressionEnabled { get; init; }
}

public class AlertingConfigContext
{
    public bool Enabled { get; init; }
    public int MaxAlertsPerHour { get; init; }
    public int WarningSuppressionMinutes { get; init; }
    public int ErrorSuppressionMinutes { get; init; }
    public int InformationalSuppressionMinutes { get; init; }
    public List<string> EnabledChannels { get; init; } = new();
}

public class RestApiConfigContext
{
    public bool Enabled { get; init; }
    public int Port { get; init; }
    public bool EnableSwagger { get; init; }
}

public class ProcessorData
{
    public double OverallUsagePercent { get; init; }
    public List<double> PerCoreUsage { get; init; } = new();
    public ProcessorAverages Averages { get; init; } = new();
    public long TimeAboveThresholdSeconds { get; init; }
    public List<TopProcess> TopProcesses { get; init; } = new();
    /// <summary>
    /// History of CPU usage measurements over the last SustainedDurationSeconds period
    /// </summary>
    public List<MeasurementHistory> CpuUsageHistory { get; init; } = new();
}

public class ProcessorAverages
{
    public double OneMinute { get; init; }
    public double FiveMinute { get; init; }
    public double FifteenMinute { get; init; }
}

public class TopProcess
{
    public string Name { get; init; } = string.Empty;
    public int Pid { get; init; }
    /// <summary>
    /// Full path to the executable file (e.g., "C:\Program Files\App\app.exe")
    /// </summary>
    public string ExecutablePath { get; init; } = string.Empty;
    /// <summary>
    /// Complete original command line including executable path and all parameters
    /// Example: "C:\Program Files\App\app.exe" --param1 value1 --param2
    /// Retrieved from WMI Win32_Process.CommandLine property
    /// </summary>
    public string CommandLine { get; init; } = string.Empty;
    public string UserName { get; init; } = string.Empty;
    public DateTime StartTime { get; init; }
    
    // CPU Metrics
    public double CpuPercent { get; init; }
    public TimeSpan TotalCpuTime { get; init; }
    public TimeSpan UserCpuTime { get; init; }
    public TimeSpan KernelCpuTime { get; init; }
    
    // Memory Metrics
    public long MemoryMB { get; init; }
    public long PrivateMemoryMB { get; init; }
    public long VirtualMemoryMB { get; init; }
    
    // Disk I/O Metrics (in MB)
    public double DiskReadMB { get; init; }
    public double DiskWriteMB { get; init; }
    
    // Process Info
    public int ThreadCount { get; init; }
    public int HandleCount { get; init; }
    public long PageFaults { get; init; }
    
    // Service Association
    public string? ServiceName { get; init; }
    public string? ServiceDisplayName { get; init; }
    public string? ServiceStatus { get; init; }
}

public class MemoryData
{
    public double TotalGB { get; init; }
    public double AvailableGB { get; init; }
    public double UsedPercent { get; init; }
    public long TimeAboveThresholdSeconds { get; init; }
    public List<TopProcess> TopProcesses { get; init; } = new();
    /// <summary>
    /// History of memory usage measurements over the last SustainedDurationSeconds period
    /// </summary>
    public List<MeasurementHistory> MemoryUsageHistory { get; init; } = new();
}

public class VirtualMemoryData
{
    public double TotalGB { get; init; }
    public double AvailableGB { get; init; }
    public double UsedPercent { get; init; }
    public long TimeAboveThresholdSeconds { get; init; }
    public double PagingRatePerSec { get; init; }
    /// <summary>
    /// History of virtual memory usage measurements over the last SustainedDurationSeconds period
    /// </summary>
    public List<MeasurementHistory> VirtualMemoryUsageHistory { get; init; } = new();
}

public class DiskData
{
    public List<DiskUsageData> Usage { get; init; } = new();
    public List<DiskSpaceData> Space { get; init; } = new();
}

public class DiskUsageData
{
    public string Drive { get; init; } = string.Empty;
    public double QueueLength { get; init; }
    public double AvgResponseTimeMs { get; init; }
    public long TimeAboveThresholdSeconds { get; init; }
    public double Iops { get; init; }
    /// <summary>
    /// History of disk queue length measurements over the last SustainedDurationSeconds period
    /// </summary>
    public List<MeasurementHistory> QueueLengthHistory { get; init; } = new();
    /// <summary>
    /// History of disk response time measurements over the last SustainedDurationSeconds period
    /// </summary>
    public List<MeasurementHistory> ResponseTimeHistory { get; init; } = new();
}

public class DiskSpaceData
{
    public string Drive { get; init; } = string.Empty;
    public double TotalGB { get; init; }
    public double AvailableGB { get; init; }
    public double UsedPercent { get; init; }
    public string FileSystem { get; init; } = string.Empty;
}

public class NetworkHostData
{
    public string Hostname { get; set; } = string.Empty;
    public double? PingMs { get; set; }
    public double PacketLossPercent { get; set; }
    public double? DnsResolutionMs { get; set; }
    public Dictionary<int, string> PortStatus { get; set; } = new();
    public int ConsecutiveFailures { get; set; }
}

public class UptimeData
{
    public DateTime LastBootTime { get; init; }
    public double CurrentUptimeDays { get; init; }
    public bool UnexpectedReboot { get; init; }
}

public class WindowsUpdateData
{
    public int PendingCount { get; init; }
    public int SecurityUpdates { get; init; }
    public int CriticalUpdates { get; init; }
    public DateTime? LastInstallDate { get; init; }
    public int FailedUpdates { get; init; }
    /// <summary>
    /// List of pending update titles/names
    /// </summary>
    public List<string> PendingUpdateNames { get; init; } = new();
}

public class EventData
{
    public int EventId { get; init; }
    public string Source { get; init; } = string.Empty;
    public string Level { get; init; } = string.Empty;
    public int Count { get; init; }
    public DateTime? LastOccurrence { get; init; }
    public string Message { get; init; } = string.Empty;
}

public class ServiceData
{
    public string ServiceName { get; init; } = string.Empty;
    public string Status { get; init; } = string.Empty;
    public string StartType { get; init; } = string.Empty;
}

/// <summary>
/// Represents a single measurement with timestamp and value
/// </summary>
public class MeasurementHistory
{
    public DateTime Timestamp { get; init; }
    public double Value { get; init; }
}

/// <summary>
/// Represents an external event submitted via REST API
/// </summary>
public class ExternalEvent
{
    /// <summary>
    /// Unique identifier for the event
    /// </summary>
    public Guid Id { get; init; } = Guid.NewGuid();

    /// <summary>
    /// External event code (unique identifier for this type of event)
    /// </summary>
    public string ExternalEventCode { get; init; } = string.Empty;

    /// <summary>
    /// Severity level of the event
    /// </summary>
    public AlertSeverity Severity { get; init; }

    /// <summary>
    /// Event category
    /// </summary>
    public string Category { get; init; } = string.Empty;

    /// <summary>
    /// Event message
    /// </summary>
    public string Message { get; init; } = string.Empty;

    /// <summary>
    /// Timestamp when the alert/event actually occurred (from the event source, e.g., log file timestamp)
    /// This is the original timestamp from the source system
    /// </summary>
    public DateTime AlertTimestamp { get; init; } = DateTime.UtcNow;

    /// <summary>
    /// Timestamp when event was registered/added to the ServerMonitor system
    /// Used for all logic operations (cleanup, throttling, etc.)
    /// </summary>
    public DateTime RegisteredTimestamp { get; init; } = DateTime.UtcNow;

    /// <summary>
    /// Server name where event originated (from request)
    /// </summary>
    public string ServerName { get; init; } = string.Empty;

    /// <summary>
    /// Source system or script that generated the event
    /// </summary>
    public string? Source { get; init; }

    /// <summary>
    /// Additional metadata key-value pairs
    /// </summary>
    public Dictionary<string, object> Metadata { get; init; } = new();

    /// <summary>
    /// Surveillance settings for this external event code
    /// </summary>
    public ExternalEventSurveillance Surveillance { get; init; } = new();
}

/// <summary>
/// Surveillance configuration for external events (per externalEventCode)
/// </summary>
public class ExternalEventSurveillance
{
    /// <summary>
    /// Maximum occurrences before alerting (0 = alert on any occurrence)
    /// </summary>
    public int MaxOccurrences { get; init; } = 1;

    /// <summary>
    /// Time window in minutes to look back for occurrences
    /// </summary>
    public int TimeWindowMinutes { get; init; } = 1;

    /// <summary>
    /// List of channel types to suppress for alerts from this event code
    /// </summary>
    public List<string> SuppressedChannels { get; init; } = new();
}

/// <summary>
/// Snapshot size information for API response
/// </summary>
public class SnapshotSizeInfo
{
    /// <summary>
    /// Estimated size of snapshot data in MB
    /// </summary>
    public double EstimatedSizeMB { get; set; }
    
    /// <summary>
    /// Number of alerts in memory
    /// </summary>
    public int AlertCount { get; set; }
    
    /// <summary>
    /// Number of external events in memory
    /// </summary>
    public int EventCount { get; set; }
    
    /// <summary>
    /// Number of DB2 diag entries in memory
    /// </summary>
    public int Db2DiagEntryCount { get; set; }
}

