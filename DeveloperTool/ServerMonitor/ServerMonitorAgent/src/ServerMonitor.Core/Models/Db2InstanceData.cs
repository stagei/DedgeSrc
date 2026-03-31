using System.Text.Json.Serialization;

namespace ServerMonitor.Core.Models;

/// <summary>
/// DB2 instance monitoring data for a single database.
/// </summary>
public record Db2DatabaseInstanceData
{
    /// <summary>
    /// Database name.
    /// </summary>
    public string DatabaseName { get; init; } = string.Empty;
    
    /// <summary>
    /// Whether the database is currently active.
    /// </summary>
    public bool IsActive { get; init; }
    
    /// <summary>
    /// Total number of connected sessions.
    /// </summary>
    public int TotalSessions { get; init; }
    
    /// <summary>
    /// Number of unique authenticated users.
    /// </summary>
    public int UniqueUsers { get; init; }
    
    /// <summary>
    /// Number of sessions currently executing.
    /// </summary>
    public int ExecutingSessions { get; init; }
    
    /// <summary>
    /// Number of sessions waiting (e.g., for locks).
    /// </summary>
    public int WaitingSessions { get; init; }
    
    /// <summary>
    /// Number of idle sessions (connected but not executing).
    /// </summary>
    public int IdleSessions { get; init; }
    
    /// <summary>
    /// Number of user sessions (excludes DB2 internal system connections).
    /// </summary>
    public int UserSessions { get; init; }
    
    /// <summary>
    /// Number of system sessions (DB2 internal connections like DB2%, SYSIBM%).
    /// </summary>
    public int SystemSessions { get; init; }
    
    /// <summary>
    /// List of long-running queries (above threshold).
    /// </summary>
    public List<Db2LongRunningQuery> LongRunningQueries { get; init; } = new();
    
    /// <summary>
    /// List of blocking sessions / lock waits.
    /// </summary>
    public List<Db2BlockingSession> BlockingSessions { get; init; } = new();
    
    /// <summary>
    /// Buffer pool hit ratio percentage (0-100). Higher is better.
    /// </summary>
    public decimal? BufferPoolHitRatio { get; init; }
    
    /// <summary>
    /// Database size in gigabytes.
    /// </summary>
    public decimal? DatabaseSizeGb { get; init; }
    
    /// <summary>
    /// Instance name this database belongs to.
    /// </summary>
    public string InstanceName { get; init; } = string.Empty;
    
    /// <summary>
    /// Today's diagnostic log summary for this specific database.
    /// </summary>
    public Db2DiagSummary? DiagSummary { get; init; }
    
    /// <summary>
    /// Size of the db2diag.log file for this database's instance, in megabytes.
    /// </summary>
    public decimal? Db2DiagLogSizeMb { get; init; }
    
    /// <summary>
    /// Database health counters from MON_GET_DATABASE (deadlocks, lock timeouts, etc.).
    /// </summary>
    public Db2DatabaseHealthCounters? HealthCounters { get; init; }

    /// <summary>
    /// Transaction log utilization from MON_GET_TRANSACTION_LOG.
    /// </summary>
    public Db2TransactionLogInfo? TransactionLog { get; init; }

    /// <summary>
    /// DB2 memory pool usage from MON_GET_MEMORY_POOL.
    /// </summary>
    public List<Db2MemoryPoolInfo> MemoryPools { get; init; } = new();

    /// <summary>
    /// Top SQL statements by CPU from MON_GET_PKG_CACHE_STMT.
    /// </summary>
    public List<Db2TopSqlEntry> TopSql { get; init; } = new();

    /// <summary>
    /// Per-tablespace utilization from MON_GET_TABLESPACE.
    /// </summary>
    public List<Db2TablespaceInfo> Tablespaces { get; init; } = new();

    /// <summary>
    /// Error message if data collection failed.
    /// </summary>
    public string? Error { get; init; }
}

/// <summary>
/// Database health counters from MON_GET_DATABASE.
/// Values are cumulative since database activation; the agent computes deltas.
/// </summary>
public record Db2DatabaseHealthCounters
{
    public long Deadlocks { get; init; }
    public long LockTimeouts { get; init; }
    public long LockEscalations { get; init; }
    public long LockWaitTimeMs { get; init; }
    public long TotalSorts { get; init; }
    public long SortOverflows { get; init; }
    public long RowsRead { get; init; }
    public long RowsReturned { get; init; }
    public long TotalCpuTimeMs { get; init; }
}

/// <summary>
/// Transaction log utilization from MON_GET_TRANSACTION_LOG.
/// </summary>
public record Db2TransactionLogInfo
{
    public long TotalLogUsedKb { get; init; }
    public long TotalLogAvailableKb { get; init; }
    public decimal LogUtilizationPercent { get; init; }
    public long LogReads { get; init; }
    public long LogWrites { get; init; }
}

/// <summary>
/// Memory pool usage from MON_GET_MEMORY_POOL.
/// </summary>
public record Db2MemoryPoolInfo
{
    public string MemorySetType { get; init; } = string.Empty;
    public string PoolType { get; init; } = string.Empty;
    public long UsedKb { get; init; }
    public long HighWatermarkKb { get; init; }
}

/// <summary>
/// Top SQL entry from MON_GET_PKG_CACHE_STMT.
/// </summary>
public record Db2TopSqlEntry
{
    public string SqlText { get; init; } = string.Empty;
    public long NumExecutions { get; init; }
    public long AvgExecTimeMs { get; init; }
    public long RowsRead { get; init; }
    public long RowsReturned { get; init; }
    public long TotalCpuMs { get; init; }
}

/// <summary>
/// Tablespace utilization from MON_GET_TABLESPACE.
/// </summary>
public record Db2TablespaceInfo
{
    public string Name { get; init; } = string.Empty;
    public string Type { get; init; } = string.Empty;
    public long TotalSizeKb { get; init; }
    public long UsedSizeKb { get; init; }
    public long FreeSizeKb { get; init; }
    public decimal UtilizationPercent { get; init; }
    public int PageSize { get; init; }
}

/// <summary>
/// Long-running SQL query information.
/// </summary>
public record Db2LongRunningQuery
{
    /// <summary>
    /// Application handle.
    /// </summary>
    public long ApplicationHandle { get; init; }
    
    /// <summary>
    /// User ID executing the query.
    /// </summary>
    public string UserId { get; init; } = string.Empty;
    
    /// <summary>
    /// Client hostname.
    /// </summary>
    public string? ClientHostname { get; init; }
    
    /// <summary>
    /// Application name.
    /// </summary>
    public string? ApplicationName { get; init; }
    
    /// <summary>
    /// Query start time.
    /// </summary>
    public DateTime StartTime { get; init; }
    
    /// <summary>
    /// Elapsed time in seconds.
    /// </summary>
    public int ElapsedSeconds { get; init; }
    
    /// <summary>
    /// SQL text (truncated to 500 chars).
    /// </summary>
    public string? SqlText { get; init; }
    
    /// <summary>
    /// Rows read so far.
    /// </summary>
    public long? RowsRead { get; init; }
    
    /// <summary>
    /// Rows returned so far.
    /// </summary>
    public long? RowsReturned { get; init; }
    
    /// <summary>
    /// CPU time in milliseconds.
    /// </summary>
    public long? CpuTimeMs { get; init; }
}

/// <summary>
/// Blocking session / lock wait information.
/// </summary>
public record Db2BlockingSession
{
    // Blocked session info
    
    /// <summary>
    /// Application handle of the blocked session.
    /// </summary>
    public long BlockedHandle { get; init; }
    
    /// <summary>
    /// User ID of the blocked session.
    /// </summary>
    public string BlockedUser { get; init; } = string.Empty;
    
    /// <summary>
    /// Client hostname of the blocked session.
    /// </summary>
    public string? BlockedHost { get; init; }
    
    /// <summary>
    /// Application name of the blocked session.
    /// </summary>
    public string? BlockedApp { get; init; }
    
    // Blocker session info
    
    /// <summary>
    /// Application handle of the blocking session.
    /// </summary>
    public long BlockerHandle { get; init; }
    
    /// <summary>
    /// User ID of the blocking session.
    /// </summary>
    public string BlockerUser { get; init; } = string.Empty;
    
    /// <summary>
    /// Client hostname of the blocking session.
    /// </summary>
    public string? BlockerHost { get; init; }
    
    /// <summary>
    /// Application name of the blocking session.
    /// </summary>
    public string? BlockerApp { get; init; }
    
    /// <summary>
    /// When the blocker's unit of work started.
    /// </summary>
    public DateTime? BlockerUowStart { get; init; }
    
    // Lock details
    
    /// <summary>
    /// Lock mode requested.
    /// </summary>
    public string? LockMode { get; init; }
    
    /// <summary>
    /// Lock object type.
    /// </summary>
    public string? LockObjectType { get; init; }
    
    /// <summary>
    /// Schema of the locked table.
    /// </summary>
    public string? TableSchema { get; init; }
    
    /// <summary>
    /// Name of the locked table.
    /// </summary>
    public string? TableName { get; init; }
    
    /// <summary>
    /// When the lock wait started.
    /// </summary>
    public DateTime LockWaitStartTime { get; init; }
    
    /// <summary>
    /// How long the session has been waiting in seconds.
    /// </summary>
    public int WaitTimeSeconds { get; init; }
}

/// <summary>
/// Today's diagnostic log summary by severity.
/// </summary>
public record Db2DiagSummary
{
    /// <summary>
    /// Date of the summary.
    /// </summary>
    public DateTime Date { get; init; }
    
    /// <summary>
    /// Total events today.
    /// </summary>
    public int TotalEvents { get; init; }
    
    /// <summary>
    /// Count of Critical level entries.
    /// </summary>
    public int CriticalCount { get; init; }
    
    /// <summary>
    /// Count of Severe level entries.
    /// </summary>
    public int SevereCount { get; init; }
    
    /// <summary>
    /// Count of Error level entries.
    /// </summary>
    public int ErrorCount { get; init; }
    
    /// <summary>
    /// Count of Warning level entries.
    /// </summary>
    public int WarningCount { get; init; }
    
    /// <summary>
    /// Count of Event level entries.
    /// </summary>
    public int EventCount { get; init; }
    
    /// <summary>
    /// Count of Info level entries.
    /// </summary>
    public int InfoCount { get; init; }
}

/// <summary>
/// Complete DB2 instance monitoring snapshot.
/// </summary>
public record Db2InstanceSnapshot
{
    /// <summary>
    /// Instance name.
    /// </summary>
    public string InstanceName { get; init; } = string.Empty;
    
    /// <summary>
    /// Timestamp of data collection.
    /// </summary>
    public DateTime CollectedAt { get; init; }
    
    /// <summary>
    /// Whether the DB2 instance Windows service is running.
    /// </summary>
    public bool IsInstanceRunning { get; init; } = true;
    
    /// <summary>
    /// Today's diagnostic log summary.
    /// </summary>
    public Db2DiagSummary? DiagSummary { get; init; }
    
    /// <summary>
    /// Per-database metrics.
    /// </summary>
    public List<Db2DatabaseInstanceData> Databases { get; init; } = new();
    
    /// <summary>
    /// Total sessions across all databases.
    /// </summary>
    public int TotalSessions => Databases.Sum(d => d.TotalSessions);
    
    /// <summary>
    /// Total unique users across all databases.
    /// </summary>
    public int TotalUniqueUsers => Databases.Sum(d => d.UniqueUsers);
    
    /// <summary>
    /// Total long-running queries across all databases.
    /// </summary>
    public int TotalLongRunningQueries => Databases.Sum(d => d.LongRunningQueries.Count);
    
    /// <summary>
    /// Total blocking sessions across all databases.
    /// </summary>
    public int TotalBlockingSessions => Databases.Sum(d => d.BlockingSessions.Count);
    
    /// <summary>
    /// Error message if collection failed.
    /// </summary>
    public string? Error { get; init; }
}
