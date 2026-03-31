using Microsoft.AspNetCore.Mvc;
using Microsoft.Extensions.Options;
using ServerMonitor.Core.Configuration;
using ServerMonitor.Core.Models;
using ServerMonitor.Core.Services;
using ServerMonitor.Core.Monitors;

namespace ServerMonitor.Controllers;

/// <summary>
/// REST API for DB2 database-specific details (used by pop-out windows)
/// </summary>
[ApiController]
[Route("api/db2")]
[Produces("application/json")]
public class Db2DetailController : ControllerBase
{
    private readonly GlobalSnapshotService _globalSnapshot;
    private readonly Db2DiagMonitor? _diagMonitor;
    private readonly IOptionsMonitor<SurveillanceConfiguration> _config;
    private readonly ILogger<Db2DetailController> _logger;

    public Db2DetailController(
        GlobalSnapshotService globalSnapshot,
        IOptionsMonitor<SurveillanceConfiguration> config,
        ILogger<Db2DetailController> logger,
        Db2DiagMonitor? diagMonitor = null)
    {
        _globalSnapshot = globalSnapshot;
        _config = config;
        _diagMonitor = diagMonitor;
        _logger = logger;
    }

    /// <summary>
    /// Get DB2 dashboard configuration (e.g., whether pop-out is enabled)
    /// </summary>
    /// <returns>Dashboard configuration settings</returns>
    [HttpGet("config")]
    [ProducesResponseType(typeof(Db2DashboardConfig), 200)]
    public IActionResult GetDashboardConfig()
    {
        var settings = _config.CurrentValue.Db2InstanceMonitoring;
        return Ok(new Db2DashboardConfig
        {
            EnablePopout = settings.EnableDashboardPopout
        });
    }

    /// <summary>
    /// Get alerts filtered for a specific DB2 database
    /// </summary>
    /// <param name="instanceName">DB2 instance name (e.g., DB2, DB2FED)</param>
    /// <param name="databaseName">Database name (e.g., FKMPRD, XFKMPRD)</param>
    /// <param name="hoursBack">Hours to look back (default 24)</param>
    /// <returns>List of alerts filtered for this database</returns>
    [HttpGet("{instanceName}/{databaseName}/alerts")]
    [ProducesResponseType(typeof(List<Alert>), 200)]
    public IActionResult GetDatabaseAlerts(
        string instanceName, 
        string databaseName,
        [FromQuery] int hoursBack = 24)
    {
        var cutoff = DateTime.UtcNow.AddHours(-hoursBack);
        var snapshot = _globalSnapshot.GetCurrentSnapshot();
        var allAlerts = snapshot.Alerts ?? new List<Alert>();

        var filteredAlerts = allAlerts
            .Where(a => a.Timestamp >= cutoff)
            .Where(a => MatchesDatabaseContext(a, instanceName, databaseName))
            .OrderByDescending(a => a.Timestamp)
            .Take(100)
            .ToList();

        _logger.LogDebug("Found {Count} alerts for {Instance}/{Database}", 
            filteredAlerts.Count, instanceName, databaseName);

        return Ok(filteredAlerts);
    }

    /// <summary>
    /// Get diagnostic summary for a specific database
    /// </summary>
    /// <param name="instanceName">DB2 instance name</param>
    /// <param name="databaseName">Database name</param>
    /// <returns>Diagnostic summary for today</returns>
    [HttpGet("{instanceName}/{databaseName}/diag-summary")]
    [ProducesResponseType(typeof(Db2DiagSummary), 200)]
    public IActionResult GetDatabaseDiagSummary(string instanceName, string databaseName)
    {
        if (_diagMonitor == null)
        {
            return Ok(new Db2DiagSummary());
        }

        var summary = _diagMonitor.GetTodaysDiagSummary(databaseName);
        return Ok(summary);
    }

    /// <summary>
    /// Get recent diagnostic entries for a specific database
    /// </summary>
    /// <param name="instanceName">DB2 instance name</param>
    /// <param name="databaseName">Database name</param>
    /// <param name="count">Number of entries to return (default 50)</param>
    /// <returns>Recent diagnostic entries</returns>
    [HttpGet("{instanceName}/{databaseName}/diag-entries")]
    [ProducesResponseType(typeof(List<Db2DiagEntry>), 200)]
    public IActionResult GetDatabaseDiagEntries(
        string instanceName, 
        string databaseName,
        [FromQuery] int count = 50)
    {
        if (_diagMonitor == null)
        {
            return Ok(new List<Db2DiagEntry>());
        }

        // Get today's entries filtered by database, limited to count
        var entries = _diagMonitor.GetTodaysEntries(databaseName)
            .Take(count)
            .ToList();

        return Ok(entries);
    }

    /// <summary>
    /// Get database state from snapshot for a specific database
    /// </summary>
    /// <param name="instanceName">DB2 instance name</param>
    /// <param name="databaseName">Database name</param>
    /// <returns>Database state including sessions, performance, etc.</returns>
    [HttpGet("{instanceName}/{databaseName}/state")]
    [ProducesResponseType(typeof(Db2DatabaseStateResponse), 200)]
    public IActionResult GetDatabaseState(string instanceName, string databaseName)
    {
        var snapshot = _globalSnapshot.GetCurrentSnapshot();
        var db2Snapshot = snapshot.Db2Instance;
        
        if (db2Snapshot == null)
        {
            return Ok(new Db2DatabaseStateResponse
            {
                InstanceName = instanceName,
                DatabaseName = databaseName,
                IsInstanceRunning = false,
                Error = "DB2 monitoring not available"
            });
        }

        // Find the database in the snapshot
        var dbData = db2Snapshot.Databases
            .FirstOrDefault(d => d.InstanceName.Equals(instanceName, StringComparison.OrdinalIgnoreCase) &&
                                  d.DatabaseName.Equals(databaseName, StringComparison.OrdinalIgnoreCase));

        if (dbData == null)
        {
            return Ok(new Db2DatabaseStateResponse
            {
                InstanceName = instanceName,
                DatabaseName = databaseName,
                IsInstanceRunning = db2Snapshot.IsInstanceRunning,
                Error = $"Database {databaseName} not found in instance {instanceName}"
            });
        }

        // Get filtered alerts and diag summary
        var alerts = GetFilteredAlerts(instanceName, databaseName);
        var diagSummary = _diagMonitor?.GetTodaysDiagSummary(databaseName);

        return Ok(new Db2DatabaseStateResponse
        {
            InstanceName = instanceName,
            DatabaseName = databaseName,
            CollectedAt = db2Snapshot.CollectedAt,
            IsInstanceRunning = db2Snapshot.IsInstanceRunning,
            IsActive = dbData.IsActive,
            
            // Session metrics
            TotalSessions = dbData.TotalSessions,
            UniqueUsers = dbData.UniqueUsers,
            ExecutingSessions = dbData.ExecutingSessions,
            IdleSessions = dbData.IdleSessions,
            WaitingSessions = dbData.WaitingSessions,
            UserSessions = dbData.UserSessions,
            SystemSessions = dbData.SystemSessions,
            
            // Performance metrics
            BufferPoolHitRatio = dbData.BufferPoolHitRatio,
            DatabaseSizeGb = dbData.DatabaseSizeGb,
            
            // Diagnostic log
            Db2DiagLogSizeMb = dbData.Db2DiagLogSizeMb,
            
            // Health counters
            HealthCounters = dbData.HealthCounters,
            
            // Transaction log
            TransactionLog = dbData.TransactionLog,
            
            // Memory pools
            MemoryPools = dbData.MemoryPools,
            
            // Top SQL
            TopSql = dbData.TopSql,
            
            // Tablespace detail
            Tablespaces = dbData.Tablespaces,
            
            // Issues
            BlockingSessions = dbData.BlockingSessions,
            LongRunningQueries = dbData.LongRunningQueries,
            
            // Diagnostics
            DiagSummary = diagSummary,
            
            // Alerts
            RecentAlerts = alerts,
            
            // Errors
            Error = dbData.Error
        });
    }

    /// <summary>
    /// Matches an alert to a specific database context
    /// </summary>
    private bool MatchesDatabaseContext(Alert alert, string instanceName, string databaseName)
    {
        var meta = alert.Metadata;
        if (meta == null) return false;

        // Check Db2DiagMonitor alerts - match by DatabaseName_DB property
        // Categories can be: "Db2Diag", "Database", or "Database/{databaseName}"
        var category = alert.Category ?? "";
        var isDbDiagAlert = category == "Db2Diag" || 
                            category == "Database" || 
                            category.StartsWith("Database/", StringComparison.OrdinalIgnoreCase);
        
        if (isDbDiagAlert)
        {
            // Check DatabaseName_DB property (format: "XFKMPRD" or similar)
            if (meta.TryGetValue("DatabaseName_DB", out var dbNameDb))
            {
                var dbNameStr = dbNameDb?.ToString();
                if (!string.IsNullOrEmpty(dbNameStr) &&
                    dbNameStr.Equals(databaseName, StringComparison.OrdinalIgnoreCase))
                {
                    // Also check instance if present
                    if (meta.TryGetValue("Instance", out var inst))
                    {
                        var instStr = inst?.ToString();
                        if (!string.IsNullOrEmpty(instStr) &&
                            instStr.Equals(instanceName, StringComparison.OrdinalIgnoreCase))
                        {
                            return true;
                        }
                    }
                    else
                    {
                        // No instance specified, match by database name only
                        return true;
                    }
                }
            }

            // Fallback: check Database property
            if (meta.TryGetValue("Database", out var db))
            {
                var dbStr = db?.ToString();
                if (!string.IsNullOrEmpty(dbStr) &&
                    dbStr.Equals(databaseName, StringComparison.OrdinalIgnoreCase))
                {
                    return true;
                }
            }
        }

        // Check Db2InstanceMonitor alerts - match by instance + database metadata
        if (alert.Category == "Db2Instance")
        {
            var matchesInstance = meta.TryGetValue("Instance", out var inst) &&
                inst?.ToString()?.Equals(instanceName, StringComparison.OrdinalIgnoreCase) == true;
            var matchesDb = meta.TryGetValue("Database", out var dbName) &&
                dbName?.ToString()?.Equals(databaseName, StringComparison.OrdinalIgnoreCase) == true;
            
            if (matchesInstance && matchesDb)
            {
                return true;
            }
        }

        return false;
    }

    private List<Alert> GetFilteredAlerts(string instanceName, string databaseName)
    {
        var cutoff = DateTime.UtcNow.AddHours(-24);
        var snapshot = _globalSnapshot.GetCurrentSnapshot();
        var allAlerts = snapshot.Alerts ?? new List<Alert>();

        return allAlerts
            .Where(a => a.Timestamp >= cutoff)
            .Where(a => MatchesDatabaseContext(a, instanceName, databaseName))
            .OrderByDescending(a => a.Timestamp)
            .Take(50)
            .ToList();
    }
}

/// <summary>
/// Response model for database state
/// </summary>
public record Db2DatabaseStateResponse
{
    public string InstanceName { get; init; } = string.Empty;
    public string DatabaseName { get; init; } = string.Empty;
    public DateTime CollectedAt { get; init; }
    public bool IsInstanceRunning { get; init; }
    public bool IsActive { get; init; }
    
    // Session metrics
    public int TotalSessions { get; init; }
    public int UniqueUsers { get; init; }
    public int ExecutingSessions { get; init; }
    public int IdleSessions { get; init; }
    public int WaitingSessions { get; init; }
    public int UserSessions { get; init; }
    public int SystemSessions { get; init; }
    
    // Performance metrics
    public decimal? BufferPoolHitRatio { get; init; }
    public decimal? DatabaseSizeGb { get; init; }
    
    // Diagnostic log
    public decimal? Db2DiagLogSizeMb { get; init; }
    
    // Health counters
    public Db2DatabaseHealthCounters? HealthCounters { get; init; }
    
    // Transaction log
    public Db2TransactionLogInfo? TransactionLog { get; init; }
    
    // Memory pools
    public List<Db2MemoryPoolInfo> MemoryPools { get; init; } = new();
    
    // Top SQL
    public List<Db2TopSqlEntry> TopSql { get; init; } = new();
    
    // Tablespace detail
    public List<Db2TablespaceInfo> Tablespaces { get; init; } = new();
    
    // Issues
    public List<Db2BlockingSession> BlockingSessions { get; init; } = new();
    public List<Db2LongRunningQuery> LongRunningQueries { get; init; } = new();
    
    // Diagnostics
    public Db2DiagSummary? DiagSummary { get; init; }
    
    // Alerts (last 24h)
    public List<Alert> RecentAlerts { get; init; } = new();
    
    // Error message if any
    public string? Error { get; init; }
}

/// <summary>
/// Dashboard configuration for DB2 features
/// </summary>
public record Db2DashboardConfig
{
    /// <summary>
    /// Whether the "Pop Out" button should be shown in the dashboard
    /// </summary>
    public bool EnablePopout { get; init; } = true;
}
