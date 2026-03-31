using System.Text.RegularExpressions;

namespace ServerMonitor.Core.Configuration;

/// <summary>
/// Configuration for IBM DB2 instance and database monitoring via MON_GET_* functions.
/// Provides session counts, long-running queries, blocking sessions, and diag log summaries.
/// </summary>
public class Db2InstanceMonitoringSettings
{
    /// <summary>
    /// Enable/disable DB2 instance monitoring.
    /// </summary>
    public bool Enabled { get; init; } = false;
    
    /// <summary>
    /// Regex pattern to match server names where DB2 instance monitoring should be active.
    /// Default: "-db$" (servers ending with "-db").
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
            return computerName.EndsWith("-db", StringComparison.OrdinalIgnoreCase);
        }
    }
    
    /// <summary>
    /// Collection/refresh interval in seconds. Default: 1200 (20 minutes).
    /// </summary>
    public int RefreshIntervalSeconds { get; init; } = 1200;
    
    /// <summary>
    /// DB2 instance names to monitor. Empty array means auto-detect from system.
    /// </summary>
    public List<string> InstanceNames { get; init; } = new();
    
    /// <summary>
    /// Collect long-running SQL statements.
    /// </summary>
    public bool CollectLongRunningQueries { get; init; } = true;
    
    /// <summary>
    /// Collect blocking sessions / lock waits.
    /// </summary>
    public bool CollectBlockingSessions { get; init; } = true;
    
    /// <summary>
    /// Collect session and user counts.
    /// </summary>
    public bool CollectSessionCounts { get; init; } = true;
    
    /// <summary>
    /// Collect today's diagnostic log summary (from Db2DiagMonitor).
    /// </summary>
    public bool CollectDiagSummary { get; init; } = true;
    
    /// <summary>
    /// Collect buffer pool stats (hit ratio) and database size.
    /// </summary>
    public bool CollectBufferPoolStats { get; init; } = true;

    /// <summary>
    /// Collect database health counters (deadlocks, lock timeouts, lock escalations, sort overflows)
    /// from MON_GET_DATABASE.
    /// </summary>
    public bool CollectDatabaseHealth { get; init; } = true;

    /// <summary>
    /// Collect transaction log utilization from MON_GET_TRANSACTION_LOG.
    /// </summary>
    public bool CollectTransactionLog { get; init; } = true;

    /// <summary>
    /// Collect DB2 memory pool usage from MON_GET_MEMORY_POOL.
    /// </summary>
    public bool CollectMemoryPools { get; init; } = true;

    /// <summary>
    /// Collect top SQL statements by CPU from MON_GET_PKG_CACHE_STMT.
    /// </summary>
    public bool CollectTopSql { get; init; } = true;

    /// <summary>
    /// Collect per-tablespace utilization breakdown from MON_GET_TABLESPACE.
    /// </summary>
    public bool CollectTablespaceDetail { get; init; } = true;

    /// <summary>
    /// Threshold settings for alerts.
    /// </summary>
    public Db2InstanceThresholds Thresholds { get; init; } = new();
    
    /// <summary>
    /// Alert settings for DB2 instance monitoring.
    /// </summary>
    public Db2InstanceAlerts Alerts { get; init; } = new();
    
    /// <summary>
    /// Suppressed alert channels.
    /// </summary>
    public List<string> SuppressedChannels { get; init; } = new();
    
    /// <summary>
    /// Enable the "Pop Out" button in the dashboard for detailed DB2 database views.
    /// When disabled, the pop-out buttons will not be shown in the dashboard UI.
    /// Default: true (enabled).
    /// </summary>
    public bool EnableDashboardPopout { get; init; } = true;
}

/// <summary>
/// Threshold settings for DB2 instance monitoring alerts.
/// </summary>
public class Db2InstanceThresholds
{
    /// <summary>
    /// Minimum elapsed seconds to consider a query "long-running" for display. Default: 5.
    /// </summary>
    public int LongRunningQueryThresholdSeconds { get; init; } = 5;
    
    /// <summary>
    /// Elapsed seconds before generating a Warning alert for long-running query. Default: 300 (5 min).
    /// </summary>
    public int LongRunningQueryWarningSeconds { get; init; } = 300;
    
    /// <summary>
    /// Elapsed seconds before generating a Critical alert for long-running query. Default: 1800 (30 min).
    /// </summary>
    public int LongRunningQueryCriticalSeconds { get; init; } = 1800;
    
    /// <summary>
    /// Maximum long-running queries to return. Default: 20.
    /// </summary>
    public int MaxLongRunningQueriesToShow { get; init; } = 20;
    
    /// <summary>
    /// Elapsed seconds before generating a Warning alert for lock wait. Default: 30.
    /// </summary>
    public int LockWaitWarningSeconds { get; init; } = 30;
    
    /// <summary>
    /// Elapsed seconds before generating a Critical alert for lock wait. Default: 300 (5 min).
    /// </summary>
    public int LockWaitCriticalSeconds { get; init; } = 300;
    
    /// <summary>
    /// Maximum blocking sessions to return. Default: 20.
    /// </summary>
    public int MaxBlockingSessionsToShow { get; init; } = 20;
    
    /// <summary>
    /// Session count threshold for Warning alert. Default: 50.
    /// </summary>
    public int SessionCountWarningThreshold { get; init; } = 50;
    
    /// <summary>
    /// Diag log errors today threshold for Warning alert. Default: 10.
    /// </summary>
    public int DiagErrorsTodayWarningThreshold { get; init; } = 10;
    
    /// <summary>
    /// Buffer pool hit ratio (%) below which to generate Warning. Default: 95.
    /// </summary>
    public decimal BufferPoolHitRatioWarning { get; init; } = 95.0m;
    
    /// <summary>
    /// Buffer pool hit ratio (%) below which to generate Critical. Default: 90.
    /// </summary>
    public decimal BufferPoolHitRatioCritical { get; init; } = 90.0m;

    /// <summary>
    /// Transaction log utilization (%) at which to generate Warning. Default: 70.
    /// </summary>
    public decimal LogUtilizationWarningPercent { get; init; } = 70.0m;

    /// <summary>
    /// Transaction log utilization (%) at which to generate Critical. Default: 90.
    /// </summary>
    public decimal LogUtilizationCriticalPercent { get; init; } = 90.0m;

    /// <summary>
    /// Maximum top SQL entries to return. Default: 10.
    /// </summary>
    public int MaxTopSqlToShow { get; init; } = 10;
}

/// <summary>
/// Alert settings for DB2 instance monitoring.
/// </summary>
public class Db2InstanceAlerts
{
    /// <summary>
    /// Alert severity for long-running query Warning threshold.
    /// </summary>
    public string LongRunningQueryWarningSeverity { get; init; } = "Warning";
    
    /// <summary>
    /// Alert severity for long-running query Critical threshold.
    /// </summary>
    public string LongRunningQueryCriticalSeverity { get; init; } = "Critical";
    
    /// <summary>
    /// Alert severity for lock wait Warning threshold.
    /// </summary>
    public string LockWaitWarningSeverity { get; init; } = "Warning";
    
    /// <summary>
    /// Alert severity for lock wait Critical threshold.
    /// </summary>
    public string LockWaitCriticalSeverity { get; init; } = "Critical";
    
    /// <summary>
    /// Alert severity for high session count.
    /// </summary>
    public string SessionCountWarningSeverity { get; init; } = "Warning";
    
    /// <summary>
    /// Alert severity for high diag error count today.
    /// </summary>
    public string DiagErrorsWarningSeverity { get; init; } = "Warning";
    
    /// <summary>
    /// Maximum alert occurrences before throttling. 0 = alert on every occurrence.
    /// </summary>
    public int MaxOccurrences { get; init; } = 1;
    
    /// <summary>
    /// Time window in minutes for MaxOccurrences counting.
    /// </summary>
    public int TimeWindowMinutes { get; init; } = 60;
}
