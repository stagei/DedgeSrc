using System.Text.Json.Serialization;

namespace ServerMonitor.Core.Models;

/// <summary>
/// Represents a parsed DB2 diagnostic log entry.
/// </summary>
public class Db2DiagEntry
{
    /// <summary>
    /// Original DB2 timestamp (e.g., "2025-11-17-08.12.29.807000+060").
    /// </summary>
    public string Timestamp { get; set; } = string.Empty;
    
    /// <summary>
    /// Parsed timestamp in local time.
    /// </summary>
    public DateTime? TimestampParsed { get; set; }
    
    /// <summary>
    /// Unique record ID from the log.
    /// </summary>
    public string RecordId { get; set; } = string.Empty;
    
    /// <summary>
    /// Severity level (Critical, Severe, Error, Warning, Info, Event).
    /// </summary>
    public string Level { get; set; } = string.Empty;
    
    /// <summary>
    /// Level priority (0=Critical, 1=Severe, 2=Error, 3=Warning, 4=Info).
    /// </summary>
    public int? LevelPriority { get; set; }
    
    /// <summary>
    /// Source line number in the log file.
    /// </summary>
    public int SourceLineNumber { get; set; }
    
    /// <summary>
    /// DB2 instance name (e.g., DB2FED, DB2HST).
    /// </summary>
    public string InstanceName { get; set; } = string.Empty;
    
    /// <summary>
    /// Database name (if available).
    /// </summary>
    public string? DatabaseName { get; set; }
    
    /// <summary>
    /// Process ID.
    /// </summary>
    public string? ProcessId { get; set; }
    
    /// <summary>
    /// Thread ID.
    /// </summary>
    public string? ThreadId { get; set; }
    
    /// <summary>
    /// Process name.
    /// </summary>
    public string? ProcessName { get; set; }
    
    /// <summary>
    /// Application handle.
    /// </summary>
    public string? ApplicationHandle { get; set; }
    
    /// <summary>
    /// Application ID.
    /// </summary>
    public string? ApplicationId { get; set; }
    
    /// <summary>
    /// Authorization ID.
    /// </summary>
    public string? AuthorizationId { get; set; }
    
    /// <summary>
    /// Hostname.
    /// </summary>
    public string? HostName { get; set; }
    
    /// <summary>
    /// Unit of Work ID (UOWID).
    /// </summary>
    public string? UnitOfWorkId { get; set; }
    
    /// <summary>
    /// Activity ID (ACTID).
    /// </summary>
    public string? ActivityId { get; set; }
    
    /// <summary>
    /// Partition/Node number (NODE).
    /// </summary>
    public string? PartitionNumber { get; set; }
    
    /// <summary>
    /// Engine Dispatchable Unit ID (EDUID).
    /// </summary>
    public string? EduId { get; set; }
    
    /// <summary>
    /// Engine Dispatchable Unit Name (EDUNAME).
    /// </summary>
    public string? EduName { get; set; }
    
    /// <summary>
    /// Function and probe information.
    /// </summary>
    public string? Function { get; set; }
    
    /// <summary>
    /// Message text (can be multi-line).
    /// </summary>
    public string? Message { get; set; }
    
    /// <summary>
    /// Return code (may contain ZRC code).
    /// </summary>
    public string? ReturnCode { get; set; }
    
    /// <summary>
    /// Called function.
    /// </summary>
    public string? CalledFunction { get; set; }
    
    /// <summary>
    /// Call stack frames (if present).
    /// </summary>
    public List<string>? CallStack { get; set; }
    
    /// <summary>
    /// Data sections from the log entry.
    /// </summary>
    public List<Db2DataSection>? DataSections { get; set; }
    
    /// <summary>
    /// Description information from message map.
    /// </summary>
    public Db2DiagDescription? Description { get; set; }
    
    /// <summary>
    /// End line number of the log block.
    /// </summary>
    public int EndLineNumber { get; set; }
    
    /// <summary>
    /// The complete raw log block text.
    /// </summary>
    public string? RawBlock { get; set; }
}

/// <summary>
/// Represents a DATA section from a DB2 diagnostic log entry.
/// </summary>
public class Db2DataSection
{
    /// <summary>
    /// The data section number (e.g., 1 for "DATA #1").
    /// </summary>
    public int Number { get; set; }
    
    /// <summary>
    /// The data type description (e.g., "String, 8 bytes").
    /// </summary>
    public string Type { get; set; } = string.Empty;
    
    /// <summary>
    /// The data value.
    /// </summary>
    public string Value { get; set; } = string.Empty;
}

/// <summary>
/// Description information looked up from the message map.
/// </summary>
public class Db2DiagDescription
{
    public Db2ZrcInfo? ZrcCode { get; set; }
    public Db2ProbeInfo? ProbeCode { get; set; }
    public Db2MessageInfo? MessageInfo { get; set; }
    public Db2LevelInfo? LevelInfo { get; set; }
}

/// <summary>
/// ZRC code description.
/// </summary>
public class Db2ZrcInfo
{
    [JsonPropertyName("description")]
    public string? Description { get; set; }
    
    [JsonPropertyName("category")]
    public string? Category { get; set; }
    
    [JsonPropertyName("sqlState")]
    public string? SqlState { get; set; }
    
    [JsonPropertyName("severity")]
    public string? Severity { get; set; }
}

/// <summary>
/// Probe code description.
/// </summary>
public class Db2ProbeInfo
{
    [JsonPropertyName("description")]
    public string? Description { get; set; }
    
    [JsonPropertyName("category")]
    public string? Category { get; set; }
    
    [JsonPropertyName("component")]
    public string? Component { get; set; }
    
    [JsonPropertyName("severity")]
    public string? Severity { get; set; }
}

/// <summary>
/// Message pattern description.
/// </summary>
public class Db2MessageInfo
{
    [JsonPropertyName("description")]
    public string? Description { get; set; }
    
    [JsonPropertyName("category")]
    public string? Category { get; set; }
    
    [JsonPropertyName("recommendation")]
    public string? Recommendation { get; set; }
}

/// <summary>
/// Level description.
/// </summary>
public class Db2LevelInfo
{
    [JsonPropertyName("priority")]
    public int Priority { get; set; }
    
    [JsonPropertyName("description")]
    public string? Description { get; set; }
    
    [JsonPropertyName("action")]
    public string? Action { get; set; }
}

/// <summary>
/// DB2 diagnostic message map structure.
/// </summary>
public class Db2DiagMessageMap
{
    [JsonPropertyName("zrcCodes")]
    public Dictionary<string, Db2ZrcInfo>? ZrcCodes { get; set; }
    
    [JsonPropertyName("probeCodes")]
    public Dictionary<string, Db2ProbeInfo>? ProbeCodes { get; set; }
    
    [JsonPropertyName("messagePatterns")]
    public Dictionary<string, Db2MessageInfo>? MessagePatterns { get; set; }
    
    [JsonPropertyName("levelDescriptions")]
    public Dictionary<string, Db2LevelInfo>? LevelDescriptions { get; set; }
}

/// <summary>
/// State tracking for a DB2 instance.
/// </summary>
public class Db2DiagInstanceState
{
    public string InstanceName { get; set; } = string.Empty;
    public string FileCreationTime { get; set; } = string.Empty;
    public int LastProcessedLine { get; set; } = 1;
}

/// <summary>
/// Summary of DB2 diagnostic monitoring data for snapshot.
/// </summary>
public class Db2DiagData
{
    /// <summary>
    /// Whether the monitor is active (server is a DB server).
    /// </summary>
    public bool IsActive { get; set; }
    
    /// <summary>
    /// Reason if not active.
    /// </summary>
    public string? InactiveReason { get; set; }
    
    /// <summary>
    /// Last check timestamp.
    /// </summary>
    public DateTime LastCheck { get; set; }
    
    /// <summary>
    /// Number of DB2 instances being monitored.
    /// </summary>
    public int InstanceCount { get; set; }
    
    /// <summary>
    /// Instance names being monitored.
    /// </summary>
    public List<string> Instances { get; set; } = new();
    
    /// <summary>
    /// Total entries processed in last cycle.
    /// </summary>
    public int EntriesProcessedLastCycle { get; set; }
    
    /// <summary>
    /// Total alerts generated in last cycle.
    /// </summary>
    public int AlertsGeneratedLastCycle { get; set; }
    
    /// <summary>
    /// Total entries kept in memory since process start.
    /// </summary>
    public int TotalEntriesInMemory { get; set; }
    
    /// <summary>
    /// Recent entries (last 10).
    /// </summary>
    public List<Db2DiagEntry> RecentEntries { get; set; } = new();
    
    /// <summary>
    /// All entries stored in memory (when KeepAllEntriesInMemory is enabled).
    /// Contains full metadata for JSON/HTML export.
    /// </summary>
    public List<Db2DiagEntry> AllEntries { get; set; } = new();
}
