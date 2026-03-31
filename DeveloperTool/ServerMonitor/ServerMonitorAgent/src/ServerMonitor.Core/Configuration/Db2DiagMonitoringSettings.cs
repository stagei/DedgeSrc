using System.Text.Json.Serialization;
using System.Text.RegularExpressions;

namespace ServerMonitor.Core.Configuration;

/// <summary>
/// Action to take when a DB2 diagnostic pattern matches.
/// </summary>
public enum Db2PatternAction
{
    /// <summary>Keep original DB2 level, create alert normally.</summary>
    Keep,
    /// <summary>Skip completely - no alert, no logging.</summary>
    Skip,
    /// <summary>Skip alert but log to SqlErrorLogPath file.</summary>
    LogOnly,
    /// <summary>Change severity level to the configured Level.</summary>
    Remap,
    /// <summary>Promote to higher severity (same as Remap, semantic difference).</summary>
    Escalate
}

/// <summary>
/// Pattern definition for DB2 diagnostic log filtering and remapping.
/// Similar to EventMonitoring's EventsToMonitor structure.
/// </summary>
public class Db2DiagPattern
{
    /// <summary>
    /// Unique identifier for this pattern.
    /// </summary>
    public string PatternId { get; init; } = string.Empty;
    
    /// <summary>
    /// Human-readable description of what this pattern matches.
    /// </summary>
    public string Description { get; init; } = string.Empty;
    
    /// <summary>
    /// Regex pattern to match against the raw log block.
    /// </summary>
    public string Regex { get; init; } = string.Empty;
    
    /// <summary>
    /// Enable/disable this pattern.
    /// </summary>
    public bool Enabled { get; init; } = true;
    
    /// <summary>
    /// Action to take when pattern matches.
    /// </summary>
    [JsonConverter(typeof(JsonStringEnumConverter))]
    public Db2PatternAction Action { get; init; } = Db2PatternAction.Keep;
    
    /// <summary>
    /// Target severity level (for Remap/Escalate actions).
    /// Valid values: Critical, Warning, Informational.
    /// </summary>
    public string Level { get; init; } = "Warning";
    
    /// <summary>
    /// Custom message template with placeholders.
    /// Supported: {Database}, {Instance}, {Function}, {AuthId}, {Hostname}, {AppId}, {SqlCode}, {RetCode}, {Message}
    /// </summary>
    public string? MessageTemplate { get; init; }
    
    /// <summary>
    /// Priority order (lower = evaluated first). Default: 100.
    /// </summary>
    public int Priority { get; init; } = 100;
    
    /// <summary>
    /// Alert after N occurrences in TimeWindowMinutes (0 = every occurrence).
    /// </summary>
    public int MaxOccurrences { get; init; } = 0;
    
    /// <summary>
    /// Time window in minutes for MaxOccurrences counting.
    /// </summary>
    public int TimeWindowMinutes { get; init; } = 60;
    
    /// <summary>
    /// Suppress specific alert channels for this pattern.
    /// </summary>
    public List<string> SuppressedChannels { get; init; } = new();
    
    /// <summary>
    /// Also log to SqlErrorLogPath file, even when creating alerts (Remap/Escalate actions).
    /// Default: false. When true, ALL occurrences are logged to the SQL error file,
    /// and alerts are generated based on MaxOccurrences/TimeWindowMinutes thresholds.
    /// </summary>
    public bool AlsoLogToFile { get; init; } = false;
    
    /// <summary>
    /// Compiled regex pattern (populated at runtime).
    /// </summary>
    [JsonIgnore]
    public Regex? CompiledRegex { get; set; }
}

/// <summary>
/// Configuration for IBM DB2 diagnostic log monitoring.
/// Only active on servers matching the ServerNamePattern regex.
/// </summary>
public class Db2DiagMonitoringSettings
{
    /// <summary>
    /// Enable/disable DB2 diagnostic log monitoring.
    /// Will only run if enabled AND server name matches ServerNamePattern.
    /// </summary>
    public bool Enabled { get; init; } = true;
    
    /// <summary>
    /// Regex pattern to match server names where DB2 monitoring should be active.
    /// Default: "-db$" (servers ending with "-db").
    /// Examples: "-db$" for suffix match, "^db-" for prefix, ".*db.*" for contains.
    /// </summary>
    public string ServerNamePattern { get; init; } = "-db$";
    
    /// <summary>
    /// Check if the given computer name matches the ServerNamePattern.
    /// </summary>
    public bool IsServerNameMatch(string computerName)
    {
        if (string.IsNullOrEmpty(ServerNamePattern)) return true;
        try
        {
            return Regex.IsMatch(computerName, ServerNamePattern, RegexOptions.IgnoreCase);
        }
        catch
        {
            // Invalid regex, fall back to suffix match for backwards compatibility
            return computerName.EndsWith("-db", StringComparison.OrdinalIgnoreCase);
        }
    }
    
    /// <summary>
    /// Polling interval in seconds. Default: 300 (5 minutes).
    /// </summary>
    public int PollingIntervalSeconds { get; init; } = 300;
    
    /// <summary>
    /// Search directory for db2diag.log files. If empty, auto-detects via db2set DB2INSTPROF.
    /// </summary>
    public string? SearchDirectory { get; init; }
    
    /// <summary>
    /// Prefix for user environment variables storing last processed line per instance.
    /// Full variable name: {Prefix}{InstanceName}
    /// State format: file_creation_datetime;last_line
    /// </summary>
    public string StateVariablePrefix { get; init; } = "DB2DIAG_LASTLINE_";
    
    /// <summary>
    /// Minimum DB2 log level to read from db2diag.log. 
    /// DB2 levels: Critical (0), Severe (1), Error (2), Warning (3), Info (4).
    /// Default: Error (reads Critical, Severe, Error entries from DB2 log).
    /// </summary>
    public string Db2MinimumLogLevel { get; init; } = "Error";
    
    /// <summary>
    /// Minimum agent alert severity to generate (applied AFTER pattern remapping).
    /// Agent severities: Critical, Warning, Informational.
    /// Default: Warning (suppresses Informational alerts even if DB2 entry was processed).
    /// </summary>
    public string MinimumAlertSeverity { get; init; } = "Warning";
    
    /// <summary>
    /// File encoding for db2diag.log files. Default: Windows1252 (ANSI).
    /// </summary>
    public string FileEncoding { get; init; } = "Windows1252";
    
    /// <summary>
    /// Maximum entries to process per cycle (0 = unlimited).
    /// </summary>
    public int MaxEntriesPerCycle { get; init; } = 100;
    
    /// <summary>
    /// Maximum log file size in bytes. Files larger than this will be skipped with a warning alert.
    /// Default: 314572800 (300 MB). Set to 0 to disable size limit.
    /// This prevents out-of-memory issues from processing very large archived log files.
    /// </summary>
    public long MaxLogFileSizeBytes { get; init; } = 314572800; // 300 MB
    
    /// <summary>
    /// Days to retain local snapshot files. Default: 7.
    /// </summary>
    public int SnapshotRetentionDays { get; init; } = 7;
    
    /// <summary>
    /// Suppress alert channels for this monitor.
    /// </summary>
    public List<string> SuppressedChannels { get; init; } = new();
    
    /// <summary>
    /// Keep all DB2 diagnostic entries in memory until process ends.
    /// Enables full export to JSON/HTML snapshots. Default: true.
    /// </summary>
    public bool KeepAllEntriesInMemory { get; init; } = true;
    
    /// <summary>
    /// Maximum entries to keep in memory (0 = unlimited). Default: 10000.
    /// Only applies when KeepAllEntriesInMemory is true.
    /// </summary>
    public int MaxEntriesInMemory { get; init; } = 10000;
    
    /// <summary>
    /// Path template for SQL error log file (used by LogOnly action).
    /// Placeholders: {Date} = yyyyMMdd, {Database} = database name.
    /// </summary>
    public string SqlErrorLogPath { get; init; } = string.Empty;
    
    /// <summary>
    /// Throttling settings for DB2 alerts.
    /// </summary>
    public Db2DiagThrottling Throttling { get; init; } = new();
    
    /// <summary>
    /// Pattern definitions for filtering, remapping, and logging.
    /// Patterns are evaluated in Priority order (lower = first match).
    /// </summary>
    public List<Db2DiagPattern> PatternsToMonitor { get; init; } = new();
}

/// <summary>
/// Throttling configuration for DB2 diagnostic alerts.
/// </summary>
public class Db2DiagThrottling
{
    /// <summary>
    /// Maximum alerts per instance per hour. Default: 50.
    /// </summary>
    public int MaxAlertsPerInstancePerHour { get; init; } = 50;
    
    /// <summary>
    /// Suppress duplicate alerts for this many minutes. Default: 15.
    /// </summary>
    public int DuplicateSuppressionMinutes { get; init; } = 15;
}
