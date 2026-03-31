using System.Diagnostics;
using Microsoft.Extensions.Logging;
using Microsoft.Extensions.Options;
using ServerMonitor.Core.Configuration;
using ServerMonitor.Core.Interfaces;
using ServerMonitor.Core.Models;
using ServerMonitor.Core.Services;

namespace ServerMonitor.Core.Monitors;

/// <summary>
/// Monitor for DB2 instance metrics: sessions, long-running queries, blocking sessions, diag summary.
/// Uses MON_GET_* table functions via db2cmd.
/// </summary>
public class Db2InstanceMonitor : IMonitor
{
    private readonly ILogger<Db2InstanceMonitor> _logger;
    private readonly IOptionsMonitor<SurveillanceConfiguration> _config;
    private readonly Db2InstanceDataCollector _dataCollector;
    private readonly Db2DiagMonitor? _diagMonitor;
    private MonitorResult? _currentState;
    private Db2InstanceSnapshot? _lastSnapshot;
    private DateTime _lastCollection = DateTime.MinValue;

    public string Category => "Db2Instance";
    
    public bool IsEnabled
    {
        get
        {
            var settings = _config.CurrentValue.Db2InstanceMonitoring;
            if (settings == null || !settings.Enabled) return false;
            
            var serverName = Environment.MachineName;
            return settings.IsServerNameMatch(serverName);
        }
    }

    public Db2InstanceMonitor(
        ILogger<Db2InstanceMonitor> logger,
        IOptionsMonitor<SurveillanceConfiguration> config,
        Db2InstanceDataCollector dataCollector,
        Db2DiagMonitor? diagMonitor = null)
    {
        _logger = logger;
        _config = config;
        _dataCollector = dataCollector;
        _diagMonitor = diagMonitor;
    }

    public async Task<MonitorResult> CollectAsync(CancellationToken cancellationToken = default)
    {
        var settings = _config.CurrentValue.Db2InstanceMonitoring;
        var alerts = new List<Alert>();
        var stopwatch = Stopwatch.StartNew();
        
        if (settings == null || !IsEnabled)
        {
            return CreateResult(null, alerts, stopwatch);
        }
        
        try
        {
            _logger.LogDebug("🗄️ DB2 Instance Monitor starting...");
            
            // Check if we need to refresh (based on RefreshIntervalSeconds)
            var timeSinceLastCollection = DateTime.UtcNow - _lastCollection;
            if (_lastSnapshot != null && timeSinceLastCollection.TotalSeconds < settings.RefreshIntervalSeconds)
            {
                _logger.LogDebug("🗄️ Using cached snapshot (age: {Age}s, refresh every: {Interval}s)",
                    (int)timeSinceLastCollection.TotalSeconds, settings.RefreshIntervalSeconds);
                
                // Return cached result without generating new alerts
                return CreateResult(_lastSnapshot, new List<Alert>(), stopwatch);
            }
            
            // Determine instance names
            var instanceNames = settings.InstanceNames.Count > 0 
                ? settings.InstanceNames 
                : await DetectInstanceNamesAsync(cancellationToken);
            
            if (instanceNames.Count == 0)
            {
                _logger.LogDebug("🗄️ No DB2 instances found");
                return CreateResult(null, alerts, stopwatch);
            }
            
            // Pass known databases from diag monitor as fallback
            if (_diagMonitor != null)
            {
                var knownDatabases = _diagMonitor.GetKnownDatabases();
                _dataCollector.SetKnownDatabases(knownDatabases);
            }
            
            // Collect data for ALL instances and merge databases
            var allDatabases = new List<Db2DatabaseInstanceData>();
            string? lastError = null;
            
            foreach (var instanceName in instanceNames)
            {
                var instanceSnapshot = await _dataCollector.CollectAsync(instanceName, cancellationToken);
                
                if (!string.IsNullOrEmpty(instanceSnapshot.Error))
                {
                    lastError = instanceSnapshot.Error;
                    _logger.LogWarning("🗄️ DB2 Instance {Instance} error: {Error}", instanceName, instanceSnapshot.Error);
                }
                
                // Add databases from this instance with per-database diag summary and log file size
                foreach (var dbData in instanceSnapshot.Databases)
                {
                    var dbWithExtras = dbData;
                    
                    if (_diagMonitor != null)
                    {
                        if (settings.CollectDiagSummary)
                        {
                            var perDbDiagSummary = _diagMonitor.GetTodaysDiagSummary(dbData.DatabaseName);
                            dbWithExtras = dbWithExtras with { DiagSummary = perDbDiagSummary };
                        }
                        
                        var logSizeBytes = _diagMonitor.GetDiagLogFileSizeBytes(instanceName);
                        if (logSizeBytes.HasValue)
                        {
                            dbWithExtras = dbWithExtras with 
                            { 
                                Db2DiagLogSizeMb = Math.Round((decimal)logSizeBytes.Value / (1024m * 1024m), 1) 
                            };
                        }
                    }
                    
                    allDatabases.Add(dbWithExtras);
                }
            }
            
            // Create merged snapshot with all databases
            var snapshot = new Db2InstanceSnapshot
            {
                InstanceName = string.Join(", ", instanceNames),
                CollectedAt = DateTime.UtcNow,
                Databases = allDatabases,
                Error = lastError
            };
            
            // Add today's global diag summary from Db2DiagMonitor if available
            if (settings.CollectDiagSummary && _diagMonitor != null)
            {
                var diagSummary = _diagMonitor.GetTodaysDiagSummary();
                snapshot = snapshot with { DiagSummary = diagSummary };
            }
            
            // Generate alerts based on thresholds
            alerts.AddRange(GenerateAlerts(snapshot, settings));
            
            _lastSnapshot = snapshot;
            _lastCollection = DateTime.UtcNow;
            
            _logger.LogInformation(
                "🗄️ DB2 Instance Monitor: {Ms}ms | Databases: {DbCount} | Sessions: {Sessions} | Users: {Users} | LongQueries: {LongQ} | Blocking: {Block}",
                stopwatch.ElapsedMilliseconds, 
                snapshot?.Databases.Count ?? 0,
                snapshot?.TotalSessions ?? 0,
                snapshot?.TotalUniqueUsers ?? 0,
                snapshot?.TotalLongRunningQueries ?? 0,
                snapshot?.TotalBlockingSessions ?? 0);
            
            return CreateResult(snapshot, alerts, stopwatch);
        }
        catch (Exception ex)
        {
            _logger.LogError(ex, "DB2 Instance Monitor failed");
            return CreateResult(null, alerts, stopwatch);
        }
    }

    public MonitorResult? CurrentState => _currentState;
    
    /// <summary>
    /// Gets the most recent snapshot (for dashboard/API access).
    /// </summary>
    public Db2InstanceSnapshot? GetLastSnapshot() => _lastSnapshot;

    private List<Alert> GenerateAlerts(Db2InstanceSnapshot snapshot, Db2InstanceMonitoringSettings settings)
    {
        var alerts = new List<Alert>();
        var thresholds = settings.Thresholds;
        var alertSettings = settings.Alerts;
        
        // Check for critical long-running queries
        foreach (var db in snapshot.Databases)
        {
            foreach (var query in db.LongRunningQueries)
            {
                if (query.ElapsedSeconds >= thresholds.LongRunningQueryCriticalSeconds)
                {
                    alerts.Add(new Alert
                    {
                        Timestamp = DateTime.UtcNow,
                        Severity = ParseSeverity(alertSettings.LongRunningQueryCriticalSeverity),
                        Category = "Db2Instance",
                        Message = $"[{db.DatabaseName}] Query by {query.UserId} running for {query.ElapsedSeconds / 60}+ minutes",
                        Details = $"Handle: {query.ApplicationHandle}, SQL: {query.SqlText?.Substring(0, Math.Min(100, query.SqlText?.Length ?? 0))}...",
                        SuppressedChannels = settings.SuppressedChannels
                    });
                }
                else if (query.ElapsedSeconds >= thresholds.LongRunningQueryWarningSeconds)
                {
                    alerts.Add(new Alert
                    {
                        Timestamp = DateTime.UtcNow,
                        Severity = ParseSeverity(alertSettings.LongRunningQueryWarningSeverity),
                        Category = "Db2Instance",
                        Message = $"[{db.DatabaseName}] Long query by {query.UserId}: {query.ElapsedSeconds}s",
                        Details = $"Handle: {query.ApplicationHandle}, Rows read: {query.RowsRead:N0}",
                        SuppressedChannels = settings.SuppressedChannels
                    });
                }
            }
            
            // Check for critical lock waits
            foreach (var block in db.BlockingSessions)
            {
                if (block.WaitTimeSeconds >= thresholds.LockWaitCriticalSeconds)
                {
                    alerts.Add(new Alert
                    {
                        Timestamp = DateTime.UtcNow,
                        Severity = ParseSeverity(alertSettings.LockWaitCriticalSeverity),
                        Category = "Db2Instance",
                        Message = $"[{db.DatabaseName}] {block.BlockedUser} blocked for {block.WaitTimeSeconds / 60}+ min by {block.BlockerUser}",
                        Details = $"Table: {block.TableSchema}.{block.TableName}, Mode: {block.LockMode}",
                        SuppressedChannels = settings.SuppressedChannels
                    });
                }
                else if (block.WaitTimeSeconds >= thresholds.LockWaitWarningSeconds)
                {
                    alerts.Add(new Alert
                    {
                        Timestamp = DateTime.UtcNow,
                        Severity = ParseSeverity(alertSettings.LockWaitWarningSeverity),
                        Category = "Db2Instance",
                        Message = $"[{db.DatabaseName}] Lock wait: {block.BlockedUser} → {block.BlockerUser} ({block.WaitTimeSeconds}s)",
                        Details = $"Table: {block.TableSchema}.{block.TableName}",
                        SuppressedChannels = settings.SuppressedChannels
                    });
                }
            }
            
            // Check session count
            if (db.TotalSessions >= thresholds.SessionCountWarningThreshold)
            {
                alerts.Add(new Alert
                {
                    Timestamp = DateTime.UtcNow,
                    Severity = ParseSeverity(alertSettings.SessionCountWarningSeverity),
                    Category = "Db2Instance",
                    Message = $"[{db.DatabaseName}] High session count: {db.TotalSessions} ({db.UniqueUsers} unique users)",
                    Details = $"Executing: {db.ExecutingSessions}, Waiting: {db.WaitingSessions}",
                    SuppressedChannels = settings.SuppressedChannels
                });
            }
        }
        
        // Check diag errors today
        if (snapshot.DiagSummary != null && snapshot.DiagSummary.ErrorCount >= thresholds.DiagErrorsTodayWarningThreshold)
        {
            alerts.Add(new Alert
            {
                Timestamp = DateTime.UtcNow,
                Severity = ParseSeverity(alertSettings.DiagErrorsWarningSeverity),
                Category = "Db2Instance",
                Message = $"DB2 diag log has {snapshot.DiagSummary.ErrorCount} errors today",
                Details = $"Critical: {snapshot.DiagSummary.CriticalCount}, Severe: {snapshot.DiagSummary.SevereCount}, Warnings: {snapshot.DiagSummary.WarningCount}",
                SuppressedChannels = settings.SuppressedChannels
            });
        }
        
        return alerts;
    }
    
    private static AlertSeverity ParseSeverity(string severity)
    {
        return severity?.ToLowerInvariant() switch
        {
            "critical" => AlertSeverity.Critical,
            "warning" => AlertSeverity.Warning,
            "informational" => AlertSeverity.Informational,
            _ => AlertSeverity.Warning
        };
    }

    private async Task<List<string>> DetectInstanceNamesAsync(CancellationToken cancellationToken)
    {
        // Use db2ilist to get all instances on this machine
        var instances = await _dataCollector.GetInstanceListAsync(cancellationToken);
        if (instances.Count > 0)
        {
            _logger.LogDebug("🗄️ Detected {Count} DB2 instances via db2ilist: {Instances}", 
                instances.Count, string.Join(", ", instances));
            return instances;
        }
        
        // Fallback: Try to detect from environment variable
        var db2Instance = Environment.GetEnvironmentVariable("DB2INSTANCE");
        if (!string.IsNullOrEmpty(db2Instance))
        {
            _logger.LogDebug("🗄️ Using DB2INSTANCE env var: {Instance}", db2Instance);
            return new List<string> { db2Instance };
        }
        
        // Default to "DB2" which is common on Windows
        _logger.LogDebug("🗄️ Defaulting to DB2 instance name");
        return new List<string> { "DB2" };
    }

    private MonitorResult CreateResult(Db2InstanceSnapshot? snapshot, List<Alert> alerts, Stopwatch stopwatch)
    {
        _currentState = new MonitorResult
        {
            Category = Category,
            Timestamp = DateTime.UtcNow,
            CollectionDurationMs = stopwatch.ElapsedMilliseconds,
            Alerts = alerts,
            Data = snapshot != null ? new Dictionary<string, object>
            {
                ["Snapshot"] = snapshot,
                ["TotalSessions"] = snapshot.TotalSessions,
                ["TotalUniqueUsers"] = snapshot.TotalUniqueUsers,
                ["TotalLongRunningQueries"] = snapshot.TotalLongRunningQueries,
                ["TotalBlockingSessions"] = snapshot.TotalBlockingSessions
            } : new Dictionary<string, object>()
        };
        
        return _currentState;
    }
}
