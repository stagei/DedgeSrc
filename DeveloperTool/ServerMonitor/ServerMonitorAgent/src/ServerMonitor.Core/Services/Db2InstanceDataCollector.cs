using System.Data;
using System.Diagnostics;
using System.Management;
using System.Text;
using IBM.Data.Db2;
using Microsoft.Extensions.Logging;
using Microsoft.Extensions.Options;
using ServerMonitor.Core.Configuration;
using ServerMonitor.Core.Models;

namespace ServerMonitor.Core.Services;

/// <summary>
/// Collects DB2 instance data (sessions, long-running queries, blocking sessions) using db2cmd.
/// </summary>
public class Db2InstanceDataCollector
{
    private readonly ILogger<Db2InstanceDataCollector> _logger;
    private readonly IOptionsMonitor<SurveillanceConfiguration> _config;
    private Db2InstanceMonitoringSettings _settings => _config.CurrentValue.Db2InstanceMonitoring;
    private readonly string? _db2CmdPath;
    
    // Known databases from diag log (injected externally)
    private HashSet<(string Instance, string Database)> _knownDatabases = new();
    
    public Db2InstanceDataCollector(
        ILogger<Db2InstanceDataCollector> logger,
        IOptionsMonitor<SurveillanceConfiguration> config)
    {
        _logger = logger;
        _config = config;
        _db2CmdPath = FindDb2CmdPath();
    }
    
    /// <summary>
    /// Sets known databases from the Db2DiagMonitor.
    /// </summary>
    public void SetKnownDatabases(IEnumerable<(string Instance, string Database)> databases)
    {
        _knownDatabases = new HashSet<(string, string)>(databases);
        _logger.LogDebug("Db2InstanceDataCollector received {Count} known databases from diag monitor", _knownDatabases.Count);
    }
    
    /// <summary>
    /// Gets list of DB2 instances on this machine using db2ilist command.
    /// </summary>
    public async Task<List<string>> GetInstanceListAsync(CancellationToken cancellationToken = default)
    {
        var instances = new List<string>();
        
        // Find db2ilist.exe
        var db2ilistPath = FindDb2ilistPath();
        if (string.IsNullOrEmpty(db2ilistPath))
        {
            _logger.LogDebug("db2ilist.exe not found - cannot auto-detect instances");
            return instances;
        }
        
        try
        {
            var process = new Process
            {
                StartInfo = new ProcessStartInfo
                {
                    FileName = db2ilistPath,
                    UseShellExecute = false,
                    CreateNoWindow = true,
                    RedirectStandardOutput = true,
                    RedirectStandardError = true
                }
            };
            
            process.Start();
            var output = await process.StandardOutput.ReadToEndAsync(cancellationToken);
            await process.WaitForExitAsync(cancellationToken);
            
            // Parse output - each line is an instance name
            foreach (var line in output.Split('\n'))
            {
                var trimmed = line.Trim();
                if (!string.IsNullOrEmpty(trimmed))
                {
                    instances.Add(trimmed);
                }
            }
            
            _logger.LogDebug("db2ilist found {Count} instances: {Instances}", 
                instances.Count, string.Join(", ", instances));
        }
        catch (Exception ex)
        {
            _logger.LogWarning(ex, "Failed to run db2ilist");
        }
        
        return instances;
    }
    
    private string? FindDb2ilistPath()
    {
        var candidates = new[]
        {
            @"C:\DbInst\BIN\db2ilist.exe",
            @"C:\Program Files\IBM\SQLLIB\BIN\db2ilist.exe",
            Environment.ExpandEnvironmentVariables(@"%DB2PATH%\BIN\db2ilist.exe")
        };
        
        return candidates.FirstOrDefault(File.Exists);
    }
    
    /// <summary>
    /// Checks if the DB2 service for an instance is running using WMI.
    /// DB2 services have DisplayName containing "db2" but Name NOT containing "DB2COPY".
    /// Primary instance "DB2" maps to service name "DB2-0", others use instance name directly.
    /// </summary>
    public bool IsInstanceServiceRunning(string instanceName)
    {
        try
        {
            // Get all DB2 services using WMI (excluding DB2COPY infrastructure services)
            var db2Services = GetDb2InstanceServices();
            
            // The primary "DB2" instance is named "DB2-0" as a service
            // Other instances use their name directly (e.g., DB2FED, DB2HST, DB2HFED)
            var expectedServiceName = instanceName.Equals("DB2", StringComparison.OrdinalIgnoreCase) 
                ? "DB2-0" 
                : instanceName;
            
            var matchingService = db2Services.FirstOrDefault(s => 
                s.Name.Equals(expectedServiceName, StringComparison.OrdinalIgnoreCase));
            
            if (matchingService != null)
            {
                var isRunning = matchingService.State.Equals("Running", StringComparison.OrdinalIgnoreCase);
                _logger.LogDebug("DB2 service '{ServiceName}' state: {State}", 
                    matchingService.Name, matchingService.State);
                return isRunning;
            }
            
            _logger.LogDebug("No DB2 service found for instance {Instance} (expected service name: {Expected})", 
                instanceName, expectedServiceName);
            return true; // Assume running if service not found
        }
        catch (Exception ex)
        {
            _logger.LogWarning(ex, "Failed to check DB2 service status for instance {Instance}", instanceName);
            return true; // Assume running on error
        }
    }
    
    /// <summary>
    /// Gets all DB2 instance services using WMI, excluding infrastructure services (DB2COPY).
    /// </summary>
    private List<Db2ServiceInfo> GetDb2InstanceServices()
    {
        var services = new List<Db2ServiceInfo>();
        
        try
        {
            var computerName = Environment.MachineName;
            
            // Query Win32_Service for all services
            using var searcher = new ManagementObjectSearcher("SELECT Name, DisplayName, State, StartMode FROM Win32_Service");
            
            foreach (ManagementObject service in searcher.Get())
            {
                var displayName = service["DisplayName"]?.ToString() ?? "";
                var name = service["Name"]?.ToString() ?? "";
                
                // Filter: DisplayName must contain "db2"
                if (!displayName.Contains("db2", StringComparison.OrdinalIgnoreCase))
                    continue;
                
                // Exclude infrastructure services (those containing "DB2COPY" in name)
                if (name.Contains("DB2COPY", StringComparison.OrdinalIgnoreCase))
                    continue;
                
                services.Add(new Db2ServiceInfo
                {
                    Name = name,
                    DisplayName = displayName,
                    State = service["State"]?.ToString() ?? "Unknown",
                    StartMode = service["StartMode"]?.ToString() ?? "Unknown"
                });
            }
            
            _logger.LogDebug("Found {Count} DB2 instance services: {Names}", 
                services.Count, string.Join(", ", services.Select(s => $"{s.Name}={s.State}")));
        }
        catch (Exception ex)
        {
            _logger.LogWarning(ex, "Failed to query DB2 services via WMI");
        }
        
        return services;
    }
    
    /// <summary>
    /// Information about a DB2 Windows service.
    /// </summary>
    private record Db2ServiceInfo
    {
        public string Name { get; init; } = "";
        public string DisplayName { get; init; } = "";
        public string State { get; init; } = "";
        public string StartMode { get; init; } = "";
    }
    
    /// <summary>
    /// Collects instance data for all configured databases.
    /// </summary>
    public async Task<Db2InstanceSnapshot> CollectAsync(string instanceName, CancellationToken cancellationToken = default)
    {
        // Check if instance service is running
        var isInstanceRunning = IsInstanceServiceRunning(instanceName);
        
        var snapshot = new Db2InstanceSnapshot
        {
            InstanceName = instanceName,
            CollectedAt = DateTime.UtcNow,
            IsInstanceRunning = isInstanceRunning
        };
        
        if (!isInstanceRunning)
        {
            _logger.LogWarning("🔴 DB2 instance {Instance} service is not running", instanceName);
            return snapshot with { Error = $"DB2 instance '{instanceName}' service is not running" };
        }
        
        if (string.IsNullOrEmpty(_db2CmdPath))
        {
            _logger.LogWarning("db2cmd.exe not found - DB2 instance monitoring unavailable");
            return snapshot with { Error = "db2cmd.exe not found" };
        }
        
        try
        {
            // Get list of active databases
            var activeDatabases = await GetActiveDatabasesAsync(instanceName, cancellationToken);
            
            if (activeDatabases.Count == 0)
            {
                _logger.LogDebug("No active databases found for instance {Instance}", instanceName);
                return snapshot with { Databases = new List<Db2DatabaseInstanceData>() };
            }
            
            var databases = new List<Db2DatabaseInstanceData>();
            
            foreach (var dbName in activeDatabases)
            {
                try
                {
                    var dbData = await CollectDatabaseDataAsync(instanceName, dbName, cancellationToken);
                    // Set IsActive based on instance running status
                    databases.Add(dbData with { IsActive = isInstanceRunning });
                }
                catch (Exception ex)
                {
                    _logger.LogWarning(ex, "Failed to collect data for database {Database}", dbName);
                    databases.Add(new Db2DatabaseInstanceData
                    {
                        DatabaseName = dbName,
                        InstanceName = instanceName,
                        IsActive = isInstanceRunning
                    });
                }
            }
            
            return snapshot with { Databases = databases };
        }
        catch (Exception ex)
        {
            _logger.LogError(ex, "Failed to collect DB2 instance data for {Instance}", instanceName);
            return snapshot with { Error = ex.Message };
        }
    }
    
    private async Task<List<string>> GetActiveDatabasesAsync(string instanceName, CancellationToken cancellationToken)
    {
        // Try multiple approaches to find databases
        
        // 1. First try "db2 list active databases" (only shows databases with active connections)
        var result = await ExecuteDb2CommandAsync(instanceName, "db2 list active databases", cancellationToken);
        var databases = ParseDatabaseList(result.Output, "Database name");
        
        if (databases.Count > 0)
        {
            _logger.LogDebug("Found {Count} active databases for instance {Instance}", databases.Count, instanceName);
            return databases;
        }
        
        // 2. Fallback: try "db2 list database directory" (shows all cataloged databases)
        result = await ExecuteDb2CommandAsync(instanceName, "db2 list db directory", cancellationToken);
        databases = ParseDatabaseList(result.Output, "Database alias");
        
        if (databases.Count > 0)
        {
            _logger.LogDebug("Found {Count} cataloged databases for instance {Instance}", databases.Count, instanceName);
            return databases;
        }
        
        // 3. Final fallback: use known databases from diag log
        if (_knownDatabases.Count > 0)
        {
            databases = _knownDatabases
                .Where(kv => kv.Instance.Equals(instanceName, StringComparison.OrdinalIgnoreCase))
                .Select(kv => kv.Database)
                .Distinct()
                .ToList();
            
            if (databases.Count > 0)
            {
                _logger.LogDebug("Using {Count} known databases from diag log for instance {Instance}", databases.Count, instanceName);
                return databases;
            }
        }
        
        _logger.LogWarning("No databases found for instance {Instance}", instanceName);
        return new List<string>();
    }
    
    private List<string> ParseDatabaseList(string output, string prefix)
    {
        var databases = new List<string>();
        if (string.IsNullOrEmpty(output)) return databases;
        
        // Handle both English and Norwegian DB2 output
        // English: "Database name", "Database alias"
        // Norwegian: "Databasenavn", "Databasealias"
        var prefixes = new[]
        {
            prefix,
            prefix.Replace(" ", ""),  // "Database name" -> "Databasename"
            "Databasealias",          // Norwegian
            "Databasenavn"            // Norwegian
        }.Distinct(StringComparer.OrdinalIgnoreCase).ToArray();
        
        foreach (var line in output.Split('\n'))
        {
            var trimmed = line.Trim();
            
            // Check if line starts with any of our prefixes
            var matchedPrefix = prefixes.FirstOrDefault(p => 
                trimmed.StartsWith(p, StringComparison.OrdinalIgnoreCase));
            
            if (matchedPrefix != null)
            {
                var parts = trimmed.Split('=');
                if (parts.Length >= 2)
                {
                    var dbName = parts[1].Trim();
                    if (!string.IsNullOrEmpty(dbName) && !databases.Contains(dbName, StringComparer.OrdinalIgnoreCase))
                    {
                        databases.Add(dbName);
                    }
                }
            }
        }
        
        return databases;
    }
    
    private async Task<Db2DatabaseInstanceData> CollectDatabaseDataAsync(
        string instanceName, 
        string databaseName, 
        CancellationToken cancellationToken)
    {
        var data = new Db2DatabaseInstanceData
        {
            DatabaseName = databaseName,
            InstanceName = instanceName,
            IsActive = true
        };
        
        // Collect session counts
        if (_settings.CollectSessionCounts)
        {
            var sessionData = await CollectSessionCountsAsync(instanceName, databaseName, cancellationToken);
            data = data with
            {
                TotalSessions = sessionData.TotalSessions,
                UniqueUsers = sessionData.UniqueUsers,
                ExecutingSessions = sessionData.ExecutingSessions,
                WaitingSessions = sessionData.WaitingSessions,
                IdleSessions = sessionData.IdleSessions,
                UserSessions = sessionData.UserSessions,
                SystemSessions = sessionData.SystemSessions
            };
        }
        
        // Collect long-running queries
        if (_settings.CollectLongRunningQueries)
        {
            var queries = await CollectLongRunningQueriesAsync(instanceName, databaseName, cancellationToken);
            data = data with { LongRunningQueries = queries };
        }
        
        // Collect blocking sessions
        if (_settings.CollectBlockingSessions)
        {
            var blockingSessions = await CollectBlockingSessionsAsync(instanceName, databaseName, cancellationToken);
            data = data with { BlockingSessions = blockingSessions };
        }
        
        // Collect buffer pool hit ratio
        if (_settings.CollectBufferPoolStats)
        {
            var bpHitRatio = await CollectBufferPoolHitRatioAsync(instanceName, databaseName, cancellationToken);
            data = data with { BufferPoolHitRatio = bpHitRatio };
        }
        
        // Collect database size
        if (_settings.CollectBufferPoolStats)
        {
            var dbSize = await CollectDatabaseSizeAsync(instanceName, databaseName, cancellationToken);
            data = data with { DatabaseSizeGb = dbSize };
        }

        // Collect database health counters (deadlocks, lock timeouts, sort overflows, etc.)
        if (_settings.CollectDatabaseHealth)
        {
            var health = await CollectDatabaseHealthAsync(instanceName, databaseName, cancellationToken);
            data = data with { HealthCounters = health };
        }

        // Collect transaction log utilization
        if (_settings.CollectTransactionLog)
        {
            var logInfo = await CollectTransactionLogAsync(instanceName, databaseName, cancellationToken);
            data = data with { TransactionLog = logInfo };
        }

        // Collect memory pool usage
        if (_settings.CollectMemoryPools)
        {
            var pools = await CollectMemoryPoolsAsync(instanceName, databaseName, cancellationToken);
            data = data with { MemoryPools = pools };
        }

        // Collect top SQL by CPU
        if (_settings.CollectTopSql)
        {
            var topSql = await CollectTopSqlAsync(instanceName, databaseName, cancellationToken);
            data = data with { TopSql = topSql };
        }

        // Collect per-tablespace detail
        if (_settings.CollectTablespaceDetail)
        {
            var tablespaces = await CollectTablespaceDetailAsync(instanceName, databaseName, cancellationToken);
            data = data with { Tablespaces = tablespaces };
        }

        return data;
    }
    
    private async Task<(int TotalSessions, int UniqueUsers, int ExecutingSessions, int WaitingSessions, int IdleSessions, int UserSessions, int SystemSessions)> 
        CollectSessionCountsAsync(string instanceName, string databaseName, CancellationToken cancellationToken)
    {
        // Cross-reference MON_GET_CONNECTION with MON_GET_ACTIVITY to determine session state.
        // Connections with an active entry in MON_GET_ACTIVITY (ACTIVITY_STATE='EXECUTING') are executing;
        // remaining user connections are idle. DB2 12.1 does not expose CONNECTION_STATE directly.
        var sql = @"
SELECT 
    COUNT(*) AS TOTAL_SESSIONS,
    COUNT(DISTINCT C.SESSION_AUTH_ID) AS UNIQUE_USERS,
    SUM(CASE WHEN C.SESSION_AUTH_ID NOT LIKE 'DB2%' AND C.SESSION_AUTH_ID NOT LIKE 'SYSIBM%' THEN 1 ELSE 0 END) AS USER_SESSIONS,
    SUM(CASE WHEN C.SESSION_AUTH_ID LIKE 'DB2%' OR C.SESSION_AUTH_ID LIKE 'SYSIBM%' THEN 1 ELSE 0 END) AS SYSTEM_SESSIONS,
    SUM(CASE WHEN A.APPLICATION_HANDLE IS NOT NULL THEN 1 ELSE 0 END) AS EXECUTING,
    0 AS WAITING,
    SUM(CASE WHEN A.APPLICATION_HANDLE IS NULL AND C.SESSION_AUTH_ID NOT LIKE 'DB2%' AND C.SESSION_AUTH_ID NOT LIKE 'SYSIBM%' THEN 1 ELSE 0 END) AS IDLE
FROM TABLE(MON_GET_CONNECTION(NULL, -2)) AS C
LEFT JOIN (SELECT DISTINCT APPLICATION_HANDLE FROM TABLE(MON_GET_ACTIVITY(NULL, -2)) WHERE ACTIVITY_STATE = 'EXECUTING') AS A
    ON C.APPLICATION_HANDLE = A.APPLICATION_HANDLE
WHERE C.MEMBER = CURRENT MEMBER
";
        
        var dataTable = await ExecuteSqlQueryAsync(instanceName, databaseName, sql, cancellationToken);
        
        if (dataTable == null || dataTable.Rows.Count == 0)
        {
            _logger.LogDebug("No session data returned for {Instance}/{Database}", instanceName, databaseName);
            return (0, 0, 0, 0, 0, 0, 0);
        }
        
        try
        {
            var row = dataTable.Rows[0];
            
            // Log all column names and values for debugging
            var columns = string.Join(", ", dataTable.Columns.Cast<DataColumn>().Select(c => c.ColumnName));
            var values = string.Join(", ", dataTable.Columns.Cast<DataColumn>().Select(c => 
                row[c] == DBNull.Value ? "NULL" : row[c]?.ToString() ?? "null"));
            _logger.LogDebug("Session DataTable columns: [{Columns}], values: [{Values}]", columns, values);
            
            var total = GetIntValue(row, "TOTAL_SESSIONS");
            var unique = GetIntValue(row, "UNIQUE_USERS");
            var userSessions = GetIntValue(row, "USER_SESSIONS");
            var systemSessions = GetIntValue(row, "SYSTEM_SESSIONS");
            var executing = GetIntValue(row, "EXECUTING");
            var waiting = GetIntValue(row, "WAITING");
            var idle = GetIntValue(row, "IDLE");
            
            _logger.LogDebug("Session counts for {Instance}/{Database}: Total={Total}, Users={Users}, UserSessions={UserSessions}, SystemSessions={SystemSessions}", 
                instanceName, databaseName, total, unique, userSessions, systemSessions);
            
            return (total, unique, executing, waiting, idle, userSessions, systemSessions);
        }
        catch (Exception ex)
        {
            _logger.LogWarning(ex, "Failed to parse session counts for {Instance}/{Database}", instanceName, databaseName);
            return (0, 0, 0, 0, 0, 0, 0);
        }
    }
    
    private async Task<List<Db2LongRunningQuery>> CollectLongRunningQueriesAsync(
        string instanceName, 
        string databaseName, 
        CancellationToken cancellationToken)
    {
        var threshold = _settings.Thresholds.LongRunningQueryThresholdSeconds;
        var limit = _settings.Thresholds.MaxLongRunningQueriesToShow;
        
        var sql = $@"
SELECT 
    A.APPLICATION_HANDLE,
    A.SESSION_AUTH_ID AS USER_ID,
    TIMESTAMPDIFF(2, CURRENT_TIMESTAMP - A.LOCAL_START_TIME) AS ELAPSED_SECONDS,
    SUBSTR(COALESCE(A.STMT_TEXT, ''), 1, 500) AS SQL_TEXT,
    A.ROWS_READ,
    A.ROWS_RETURNED,
    A.TOTAL_CPU_TIME / 1000 AS CPU_TIME_MS,
    COALESCE(C.CLIENT_HOSTNAME, '') AS CLIENT_HOSTNAME,
    COALESCE(C.APPLICATION_NAME, '') AS APPLICATION_NAME,
    A.LOCAL_START_TIME
FROM TABLE(MON_GET_ACTIVITY(NULL, -2)) AS A
LEFT JOIN TABLE(MON_GET_CONNECTION(NULL, -2)) AS C
    ON A.APPLICATION_HANDLE = C.APPLICATION_HANDLE
WHERE A.ACTIVITY_STATE = 'EXECUTING'
  AND TIMESTAMPDIFF(2, CURRENT_TIMESTAMP - A.LOCAL_START_TIME) > {threshold}
ORDER BY ELAPSED_SECONDS DESC
FETCH FIRST {limit} ROWS ONLY
";
        
        var dataTable = await ExecuteSqlQueryAsync(instanceName, databaseName, sql, cancellationToken);
        var queries = new List<Db2LongRunningQuery>();
        
        if (dataTable == null || dataTable.Rows.Count == 0)
        {
            return queries;
        }
        
        try
        {
            foreach (DataRow row in dataTable.Rows)
            {
                var elapsed = Convert.ToInt32(row["ELAPSED_SECONDS"]);
                queries.Add(new Db2LongRunningQuery
                {
                    ApplicationHandle = Convert.ToInt64(row["APPLICATION_HANDLE"]),
                    UserId = row["USER_ID"]?.ToString() ?? "",
                    ElapsedSeconds = elapsed,
                    SqlText = row["SQL_TEXT"]?.ToString(),
                    RowsRead = row["ROWS_READ"] != DBNull.Value ? Convert.ToInt64(row["ROWS_READ"]) : null,
                    RowsReturned = row["ROWS_RETURNED"] != DBNull.Value ? Convert.ToInt64(row["ROWS_RETURNED"]) : null,
                    CpuTimeMs = row["CPU_TIME_MS"] != DBNull.Value ? Convert.ToInt64(row["CPU_TIME_MS"]) : null,
                    ClientHostname = row["CLIENT_HOSTNAME"]?.ToString(),
                    ApplicationName = row["APPLICATION_NAME"]?.ToString(),
                    StartTime = DateTime.UtcNow.AddSeconds(-elapsed)
                });
            }
            
            if (queries.Count > 0)
            {
                _logger.LogDebug("Found {Count} long-running queries for {Instance}/{Database}", 
                    queries.Count, instanceName, databaseName);
            }
        }
        catch (Exception ex)
        {
            _logger.LogWarning(ex, "Failed to parse long-running queries for {Instance}/{Database}", instanceName, databaseName);
        }
        
        return queries;
    }
    
    private async Task<List<Db2BlockingSession>> CollectBlockingSessionsAsync(
        string instanceName, 
        string databaseName, 
        CancellationToken cancellationToken)
    {
        var limit = _settings.Thresholds.MaxBlockingSessionsToShow;
        
        // Note: Some columns like TABSCHEMA, TABNAME don't exist in MON_GET_APPL_LOCKWAIT in DB2 12.1
        var sql = $@"
SELECT 
    L.REQ_APPLICATION_HANDLE AS BLOCKED_HANDLE,
    L.HLD_APPLICATION_HANDLE AS BLOCKER_HANDLE,
    COALESCE(L.LOCK_MODE, '') AS LOCK_MODE,
    '' AS TABSCHEMA,
    '' AS TABNAME,
    TIMESTAMPDIFF(2, CURRENT_TIMESTAMP - L.LOCK_WAIT_START_TIME) AS WAIT_TIME_SECONDS,
    COALESCE(REQ.SESSION_AUTH_ID, '') AS BLOCKED_USER,
    COALESCE(REQ.CLIENT_HOSTNAME, '') AS BLOCKED_HOST,
    COALESCE(HLD.SESSION_AUTH_ID, '') AS BLOCKER_USER,
    COALESCE(HLD.CLIENT_HOSTNAME, '') AS BLOCKER_HOST,
    COALESCE(HLD.APPLICATION_NAME, '') AS BLOCKER_APP
FROM TABLE(MON_GET_APPL_LOCKWAIT(NULL, -2)) AS L
INNER JOIN TABLE(MON_GET_CONNECTION(NULL, -2)) AS REQ
    ON L.REQ_APPLICATION_HANDLE = REQ.APPLICATION_HANDLE
INNER JOIN TABLE(MON_GET_CONNECTION(NULL, -2)) AS HLD
    ON L.HLD_APPLICATION_HANDLE = HLD.APPLICATION_HANDLE
ORDER BY WAIT_TIME_SECONDS DESC
FETCH FIRST {limit} ROWS ONLY
";
        
        var dataTable = await ExecuteSqlQueryAsync(instanceName, databaseName, sql, cancellationToken);
        var sessions = new List<Db2BlockingSession>();
        
        if (dataTable == null || dataTable.Rows.Count == 0)
        {
            return sessions;
        }
        
        try
        {
            foreach (DataRow row in dataTable.Rows)
            {
                var waitTime = Convert.ToInt32(row["WAIT_TIME_SECONDS"]);
                sessions.Add(new Db2BlockingSession
                {
                    BlockedHandle = Convert.ToInt64(row["BLOCKED_HANDLE"]),
                    BlockerHandle = Convert.ToInt64(row["BLOCKER_HANDLE"]),
                    LockMode = row["LOCK_MODE"]?.ToString(),
                    TableSchema = row["TABSCHEMA"]?.ToString(),
                    TableName = row["TABNAME"]?.ToString(),
                    WaitTimeSeconds = waitTime,
                    BlockedUser = row["BLOCKED_USER"]?.ToString() ?? "",
                    BlockedHost = row["BLOCKED_HOST"]?.ToString(),
                    BlockerUser = row["BLOCKER_USER"]?.ToString() ?? "",
                    BlockerHost = row["BLOCKER_HOST"]?.ToString(),
                    BlockerApp = row["BLOCKER_APP"]?.ToString(),
                    LockWaitStartTime = DateTime.UtcNow.AddSeconds(-waitTime)
                });
            }
            
            if (sessions.Count > 0)
            {
                _logger.LogWarning("Found {Count} blocking sessions for {Instance}/{Database}", 
                    sessions.Count, instanceName, databaseName);
            }
        }
        catch (Exception ex)
        {
            _logger.LogWarning(ex, "Failed to parse blocking sessions for {Instance}/{Database}", instanceName, databaseName);
        }
        
        return sessions;
    }
    
    private async Task<decimal?> CollectBufferPoolHitRatioAsync(
        string instanceName,
        string databaseName,
        CancellationToken cancellationToken)
    {
        // Buffer Pool Hit Ratio: (logical reads - physical reads) / logical reads * 100
        var sql = @"
SELECT 
    CASE WHEN (SUM(POOL_DATA_L_READS) + SUM(POOL_INDEX_L_READS)) > 0
         THEN DECIMAL(
              ((SUM(POOL_DATA_L_READS) + SUM(POOL_INDEX_L_READS) 
                - SUM(POOL_DATA_P_READS) - SUM(POOL_INDEX_P_READS)) * 100.0) 
              / (SUM(POOL_DATA_L_READS) + SUM(POOL_INDEX_L_READS)), 5, 2)
         ELSE 100.00
    END AS HIT_RATIO
FROM TABLE(MON_GET_BUFFERPOOL('', -2)) AS BP
WHERE BP_NAME NOT LIKE 'IBMSYS%'
";
        
        var dataTable = await ExecuteSqlQueryAsync(instanceName, databaseName, sql, cancellationToken);
        
        if (dataTable == null || dataTable.Rows.Count == 0)
        {
            return null;
        }
        
        try
        {
            var value = dataTable.Rows[0]["HIT_RATIO"];
            if (value != DBNull.Value)
            {
                var hitRatio = Convert.ToDecimal(value);
                _logger.LogDebug("Buffer pool hit ratio for {Instance}/{Database}: {Ratio}%", 
                    instanceName, databaseName, hitRatio);
                return hitRatio;
            }
        }
        catch (Exception ex)
        {
            _logger.LogWarning(ex, "Failed to parse buffer pool hit ratio for {Instance}/{Database}", instanceName, databaseName);
        }
        
        return null;
    }
    
    private async Task<decimal?> CollectDatabaseSizeAsync(
        string instanceName,
        string databaseName,
        CancellationToken cancellationToken)
    {
        // Database size from tablespace usage
        var sql = @"
SELECT 
    DECIMAL(SUM(TBSP_USED_SIZE_KB) / 1024.0 / 1024.0, 10, 2) AS SIZE_GB
FROM TABLE(MON_GET_TABLESPACE('', -2)) AS TS
";
        
        var dataTable = await ExecuteSqlQueryAsync(instanceName, databaseName, sql, cancellationToken);
        
        if (dataTable == null || dataTable.Rows.Count == 0)
        {
            return null;
        }
        
        try
        {
            var value = dataTable.Rows[0]["SIZE_GB"];
            if (value != DBNull.Value)
            {
                var sizeGb = Convert.ToDecimal(value);
                _logger.LogDebug("Database size for {Instance}/{Database}: {Size} GB", 
                    instanceName, databaseName, sizeGb);
                return sizeGb;
            }
        }
        catch (Exception ex)
        {
            _logger.LogWarning(ex, "Failed to parse database size for {Instance}/{Database}", instanceName, databaseName);
        }
        
        return null;
    }
    
    private async Task<Db2DatabaseHealthCounters?> CollectDatabaseHealthAsync(
        string instanceName, string databaseName, CancellationToken cancellationToken)
    {
        var sql = @"
SELECT DEADLOCKS, LOCK_TIMEOUTS, LOCK_ESCALS, LOCK_WAIT_TIME,
       TOTAL_SORTS, SORT_OVERFLOWS, ROWS_READ, ROWS_RETURNED,
       TOTAL_CPU_TIME
FROM TABLE(MON_GET_DATABASE(NULL)) AS DB
FETCH FIRST 1 ROWS ONLY
";
        var dt = await ExecuteSqlQueryAsync(instanceName, databaseName, sql, cancellationToken);
        if (dt == null || dt.Rows.Count == 0) return null;

        try
        {
            var row = dt.Rows[0];
            return new Db2DatabaseHealthCounters
            {
                Deadlocks = GetLongValueOrNull(row, "DEADLOCKS") ?? 0,
                LockTimeouts = GetLongValueOrNull(row, "LOCK_TIMEOUTS") ?? 0,
                LockEscalations = GetLongValueOrNull(row, "LOCK_ESCALS") ?? 0,
                LockWaitTimeMs = GetLongValueOrNull(row, "LOCK_WAIT_TIME") ?? 0,
                TotalSorts = GetLongValueOrNull(row, "TOTAL_SORTS") ?? 0,
                SortOverflows = GetLongValueOrNull(row, "SORT_OVERFLOWS") ?? 0,
                RowsRead = GetLongValueOrNull(row, "ROWS_READ") ?? 0,
                RowsReturned = GetLongValueOrNull(row, "ROWS_RETURNED") ?? 0,
                TotalCpuTimeMs = (GetLongValueOrNull(row, "TOTAL_CPU_TIME") ?? 0) / 1000
            };
        }
        catch (Exception ex)
        {
            _logger.LogWarning(ex, "Failed to parse database health for {Instance}/{Database}", instanceName, databaseName);
            return null;
        }
    }

    private async Task<Db2TransactionLogInfo?> CollectTransactionLogAsync(
        string instanceName, string databaseName, CancellationToken cancellationToken)
    {
        var sql = @"
SELECT TOTAL_LOG_USED_KB, TOTAL_LOG_AVAILABLE_KB, LOG_READS, LOG_WRITES
FROM TABLE(MON_GET_TRANSACTION_LOG(NULL)) AS TL
FETCH FIRST 1 ROWS ONLY
";
        var dt = await ExecuteSqlQueryAsync(instanceName, databaseName, sql, cancellationToken);
        if (dt == null || dt.Rows.Count == 0) return null;

        try
        {
            var row = dt.Rows[0];
            var used = GetLongValueOrNull(row, "TOTAL_LOG_USED_KB") ?? 0;
            var available = GetLongValueOrNull(row, "TOTAL_LOG_AVAILABLE_KB") ?? 0;
            var total = used + available;
            var pct = total > 0 ? Math.Round((decimal)used / total * 100, 2) : 0m;

            return new Db2TransactionLogInfo
            {
                TotalLogUsedKb = used,
                TotalLogAvailableKb = available,
                LogUtilizationPercent = pct,
                LogReads = GetLongValueOrNull(row, "LOG_READS") ?? 0,
                LogWrites = GetLongValueOrNull(row, "LOG_WRITES") ?? 0
            };
        }
        catch (Exception ex)
        {
            _logger.LogWarning(ex, "Failed to parse transaction log for {Instance}/{Database}", instanceName, databaseName);
            return null;
        }
    }

    private async Task<List<Db2MemoryPoolInfo>> CollectMemoryPoolsAsync(
        string instanceName, string databaseName, CancellationToken cancellationToken)
    {
        var sql = @"
SELECT MEMORY_SET_TYPE, MEMORY_POOL_TYPE, MEMORY_POOL_USED, MEMORY_POOL_USED_HWM
FROM TABLE(MON_GET_MEMORY_POOL(NULL, NULL, NULL)) AS MP
WHERE MEMORY_SET_TYPE = 'DATABASE'
ORDER BY MEMORY_POOL_USED DESC
FETCH FIRST 15 ROWS ONLY
";
        var dt = await ExecuteSqlQueryAsync(instanceName, databaseName, sql, cancellationToken);
        var pools = new List<Db2MemoryPoolInfo>();
        if (dt == null || dt.Rows.Count == 0) return pools;

        try
        {
            foreach (DataRow row in dt.Rows)
            {
                pools.Add(new Db2MemoryPoolInfo
                {
                    MemorySetType = row["MEMORY_SET_TYPE"]?.ToString() ?? "",
                    PoolType = row["MEMORY_POOL_TYPE"]?.ToString() ?? "",
                    UsedKb = GetLongValueOrNull(row, "MEMORY_POOL_USED") ?? 0,
                    HighWatermarkKb = GetLongValueOrNull(row, "MEMORY_POOL_USED_HWM") ?? 0
                });
            }
        }
        catch (Exception ex)
        {
            _logger.LogWarning(ex, "Failed to parse memory pools for {Instance}/{Database}", instanceName, databaseName);
        }

        return pools;
    }

    private async Task<List<Db2TopSqlEntry>> CollectTopSqlAsync(
        string instanceName, string databaseName, CancellationToken cancellationToken)
    {
        var limit = _settings.Thresholds.MaxTopSqlToShow;
        var sql = $@"
SELECT SUBSTR(STMT_TEXT, 1, 200) AS SQL_TEXT,
       NUM_EXECUTIONS, TOTAL_ACT_TIME / NULLIF(NUM_EXECUTIONS, 0) AS AVG_EXEC_TIME_MS,
       ROWS_READ, ROWS_RETURNED,
       TOTAL_CPU_TIME / 1000 AS TOTAL_CPU_MS
FROM TABLE(MON_GET_PKG_CACHE_STMT(NULL, NULL, NULL, NULL)) AS PS
WHERE NUM_EXECUTIONS > 0
ORDER BY TOTAL_CPU_TIME DESC
FETCH FIRST {limit} ROWS ONLY
";
        var dt = await ExecuteSqlQueryAsync(instanceName, databaseName, sql, cancellationToken);
        var entries = new List<Db2TopSqlEntry>();
        if (dt == null || dt.Rows.Count == 0) return entries;

        try
        {
            foreach (DataRow row in dt.Rows)
            {
                entries.Add(new Db2TopSqlEntry
                {
                    SqlText = row["SQL_TEXT"]?.ToString() ?? "",
                    NumExecutions = GetLongValueOrNull(row, "NUM_EXECUTIONS") ?? 0,
                    AvgExecTimeMs = GetLongValueOrNull(row, "AVG_EXEC_TIME_MS") ?? 0,
                    RowsRead = GetLongValueOrNull(row, "ROWS_READ") ?? 0,
                    RowsReturned = GetLongValueOrNull(row, "ROWS_RETURNED") ?? 0,
                    TotalCpuMs = GetLongValueOrNull(row, "TOTAL_CPU_MS") ?? 0
                });
            }
        }
        catch (Exception ex)
        {
            _logger.LogWarning(ex, "Failed to parse top SQL for {Instance}/{Database}", instanceName, databaseName);
        }

        return entries;
    }

    private async Task<List<Db2TablespaceInfo>> CollectTablespaceDetailAsync(
        string instanceName, string databaseName, CancellationToken cancellationToken)
    {
        var sql = @"
SELECT TBSP_NAME, TBSP_TYPE, TBSP_TOTAL_SIZE_KB,
       TBSP_USED_SIZE_KB, TBSP_FREE_SIZE_KB,
       TBSP_UTILIZATION_PERCENT, TBSP_PAGE_SIZE
FROM TABLE(MON_GET_TABLESPACE('', -2)) AS TS
ORDER BY TBSP_USED_SIZE_KB DESC
FETCH FIRST 20 ROWS ONLY
";
        var dt = await ExecuteSqlQueryAsync(instanceName, databaseName, sql, cancellationToken);
        var list = new List<Db2TablespaceInfo>();
        if (dt == null || dt.Rows.Count == 0) return list;

        try
        {
            foreach (DataRow row in dt.Rows)
            {
                list.Add(new Db2TablespaceInfo
                {
                    Name = row["TBSP_NAME"]?.ToString() ?? "",
                    Type = row["TBSP_TYPE"]?.ToString() ?? "",
                    TotalSizeKb = GetLongValueOrNull(row, "TBSP_TOTAL_SIZE_KB") ?? 0,
                    UsedSizeKb = GetLongValueOrNull(row, "TBSP_USED_SIZE_KB") ?? 0,
                    FreeSizeKb = GetLongValueOrNull(row, "TBSP_FREE_SIZE_KB") ?? 0,
                    UtilizationPercent = GetDecimalValueOrNull(row, "TBSP_UTILIZATION_PERCENT") ?? 0,
                    PageSize = GetIntValue(row, "TBSP_PAGE_SIZE")
                });
            }
        }
        catch (Exception ex)
        {
            _logger.LogWarning(ex, "Failed to parse tablespace detail for {Instance}/{Database}", instanceName, databaseName);
        }

        return list;
    }

    /// <summary>
    /// Executes a SQL query using db2cmd CLI (fallback from ADO.NET due to authentication issues).
    /// Returns a DataTable with the results, or null on failure.
    /// </summary>
    private async Task<DataTable?> ExecuteSqlQueryAsync(
        string instanceName,
        string databaseName,
        string sql,
        CancellationToken cancellationToken)
    {
        // Use the CLI-based approach because the ADO.NET driver has authentication issues
        // (SQL30082N reason 17 - UNSUPPORTED FUNCTION) when running as a Windows service
        var result = await ExecuteDb2SqlViaCliAsync(instanceName, databaseName, sql, cancellationToken);
        
        if (!result.Success)
        {
            _logger.LogWarning("DB2 CLI SQL failed on {Instance}/{Database}: ExitCode={ExitCode}, Error={Error}", 
                instanceName, databaseName, result.ExitCode, 
                string.IsNullOrEmpty(result.ErrorOutput) ? "(no error output)" : result.ErrorOutput);
            
            if (!string.IsNullOrEmpty(result.Output))
            {
                _logger.LogDebug("DB2 CLI output (even though failed): {Output}", 
                    result.Output.Length > 500 ? result.Output[..500] + "..." : result.Output);
            }
            return null;
        }
        
        // Parse the CLI output into a DataTable
        return ParseDb2CliOutput(result.Output, sql);
    }
    
    /// <summary>
    /// Safely gets an integer value from a DataRow column, returning 0 for DBNull or invalid values.
    /// </summary>
    private static int GetIntValue(DataRow row, string columnName)
    {
        if (!row.Table.Columns.Contains(columnName))
            return 0;
        
        var value = row[columnName];
        if (value == DBNull.Value || value == null)
            return 0;
        
        if (int.TryParse(value.ToString(), out var result))
            return result;
        
        return 0;
    }
    
    /// <summary>
    /// Safely gets a long value from a DataRow column, returning null for DBNull or invalid values.
    /// </summary>
    private static long? GetLongValueOrNull(DataRow row, string columnName)
    {
        if (!row.Table.Columns.Contains(columnName))
            return null;
        
        var value = row[columnName];
        if (value == DBNull.Value || value == null)
            return null;
        
        if (long.TryParse(value.ToString(), out var result))
            return result;
        
        return null;
    }
    
    /// <summary>
    /// Safely gets a decimal value from a DataRow column, returning null for DBNull or invalid values.
    /// </summary>
    private static decimal? GetDecimalValueOrNull(DataRow row, string columnName)
    {
        if (!row.Table.Columns.Contains(columnName))
            return null;
        
        var value = row[columnName];
        if (value == DBNull.Value || value == null)
            return null;
        
        if (decimal.TryParse(value.ToString(), out var result))
            return result;
        
        return null;
    }
    
    /// <summary>
    /// Parses DB2 CLI output into a DataTable.
    /// </summary>
    private DataTable? ParseDb2CliOutput(string output, string sql)
    {
        if (string.IsNullOrEmpty(output))
        {
            _logger.LogDebug("Empty output from DB2 CLI");
            return null;
        }
        
        var dataTable = new DataTable();
        var lines = output.Split('\n').Select(l => l.Trim()).Where(l => !string.IsNullOrEmpty(l)).ToList();
        
        // Find the header line and data lines
        var headerLineIndex = -1;
        var separatorLineIndex = -1;
        
        for (int i = 0; i < lines.Count; i++)
        {
            var line = lines[i];
            
            // Look for separator line (dashes)
            if (line.StartsWith("-") && line.Contains("---"))
            {
                separatorLineIndex = i;
                headerLineIndex = i - 1;
                break;
            }
        }
        
        if (headerLineIndex < 0 || separatorLineIndex < 0)
        {
            _logger.LogDebug("Could not find header in DB2 CLI output. Output sample: {Sample}", 
                output.Length > 200 ? output[..200] : output);
            return null;
        }
        
        // Parse header to get column names
        var headerLine = lines[headerLineIndex];
        var separatorLine = lines[separatorLineIndex];
        
        // Use separator line to determine column widths
        var columnPositions = new List<(int Start, int End)>();
        int start = 0;
        bool inDashes = false;
        
        for (int i = 0; i <= separatorLine.Length; i++)
        {
            char c = i < separatorLine.Length ? separatorLine[i] : ' ';
            if (c == '-' && !inDashes)
            {
                start = i;
                inDashes = true;
            }
            else if (c != '-' && inDashes)
            {
                columnPositions.Add((start, i));
                inDashes = false;
            }
        }
        
        // Create columns
        foreach (var pos in columnPositions)
        {
            var colName = headerLine.Length > pos.Start 
                ? headerLine.Substring(pos.Start, Math.Min(pos.End - pos.Start, headerLine.Length - pos.Start)).Trim()
                : $"Col{dataTable.Columns.Count}";
            dataTable.Columns.Add(colName);
        }
        
        if (dataTable.Columns.Count == 0)
        {
            _logger.LogDebug("No columns found in DB2 CLI output");
            return null;
        }
        
        // Parse data rows using whitespace-based tokenization
        // This is more robust than fixed positions for DB2 CLI output with varying column widths
        for (int i = separatorLineIndex + 1; i < lines.Count; i++)
        {
            var line = lines[i];
            
            // Skip empty lines and record count lines
            if (string.IsNullOrEmpty(line) || line.Contains("record(s) selected") || 
                line.Contains("record selected") || line.Contains("(norwegian)") ||
                line.Contains("post(er)") || line.Contains("post valgt"))
                continue;
            
            // Split by whitespace - works better for numeric aggregate data
            var tokens = line.Split(new[] { ' ', '\t' }, StringSplitOptions.RemoveEmptyEntries);
            
            var row = dataTable.NewRow();
            
            // Map tokens to columns (handle case where there are fewer tokens than columns)
            for (int col = 0; col < dataTable.Columns.Count && col < tokens.Length; col++)
            {
                var value = tokens[col].Trim();
                row[col] = string.IsNullOrEmpty(value) || value == "-" ? DBNull.Value : value;
            }
            
            // Fill remaining columns with DBNull
            for (int col = tokens.Length; col < dataTable.Columns.Count; col++)
            {
                row[col] = DBNull.Value;
            }
            
            dataTable.Rows.Add(row);
        }
        
        _logger.LogDebug("Parsed {RowCount} rows from DB2 CLI output", dataTable.Rows.Count);
        return dataTable;
    }
    
    /// <summary>
    /// Builds a DB2 connection string for local instance connection.
    /// Uses Windows authentication (current process identity).
    /// </summary>
    private string BuildConnectionString(string instanceName, string databaseName)
    {
        // For local DB2 instances on Windows, we need to:
        // 1. Use the cataloged database alias directly
        // 2. Omit UID/PWD for Windows authentication (trusted connection)
        // 3. Set connection timeout
        // 
        // The DB2 .NET provider will use the DB2INSTANCE environment variable
        // or the local node catalog to find the database.
        
        // Simple connection string for local cataloged database
        // DB2 will use the current Windows credentials
        var connectionString = $"Database={databaseName};";
        
        _logger.LogDebug("Built connection string for {Instance}/{Database}: {ConnStr}", 
            instanceName, databaseName, connectionString);
        
        return connectionString;
    }
    
    /// <summary>
    /// Legacy method for db2cmd execution (kept for non-SQL commands like db2ilist, list db directory)
    /// </summary>
    private async Task<Db2CommandResult> ExecuteDb2SqlViaCliAsync(
        string instanceName, 
        string databaseName, 
        string sql, 
        CancellationToken cancellationToken)
    {
        // Build command: connect, run query, disconnect
        // The command must be passed to db2cmd as a batch file, not inline, because
        // db2cmd doesn't properly handle && chaining when passed as arguments
        return await ExecuteDb2SqlViaBatchFileAsync(instanceName, databaseName, sql, cancellationToken);
    }
    
    /// <summary>
    /// Executes a SQL query using a batch file to ensure proper command chaining.
    /// </summary>
    private async Task<Db2CommandResult> ExecuteDb2SqlViaBatchFileAsync(
        string instanceName, 
        string databaseName, 
        string sql, 
        CancellationToken cancellationToken)
    {
        if (string.IsNullOrEmpty(_db2CmdPath))
        {
            _logger.LogWarning("db2cmd.exe not found");
            return new Db2CommandResult { Success = false, ErrorOutput = "db2cmd.exe not found" };
        }
        
        var tempBatFile = Path.GetTempFileName() + ".bat";
        
        try
        {
            // Build batch content with proper command chaining
            // Use call db2 to ensure each command runs in sequence
            // CRITICAL: SQL must be on a single line - newlines break the batch file!
            var singleLineSql = sql.Replace("\r\n", " ").Replace("\n", " ").Replace("\r", " ");
            // Collapse multiple spaces
            while (singleLineSql.Contains("  "))
            {
                singleLineSql = singleLineSql.Replace("  ", " ");
            }
            
            var batContent = $@"@echo off
call db2 connect to {databaseName}
if errorlevel 1 exit /b 1
call db2 ""{singleLineSql}""
call db2 connect reset
";
            await File.WriteAllTextAsync(tempBatFile, batContent, cancellationToken);
            
            _logger.LogDebug("DB2 SQL execution: Instance={Instance}, Database={Database}, TempBat={Bat}", 
                instanceName, databaseName, tempBatFile);
            
            // Execute via db2cmd with the batch file
            var process = new Process
            {
                StartInfo = new ProcessStartInfo
                {
                    FileName = _db2CmdPath,
                    Arguments = $"/c /w /i \"{tempBatFile}\"",
                    UseShellExecute = false,
                    CreateNoWindow = true,
                    RedirectStandardOutput = true,
                    RedirectStandardError = true,
                    StandardOutputEncoding = Encoding.GetEncoding(1252),
                    StandardErrorEncoding = Encoding.GetEncoding(1252)
                }
            };
            
            // Set the DB2INSTANCE environment variable
            process.StartInfo.Environment["DB2INSTANCE"] = instanceName;
            
            var outputBuilder = new StringBuilder();
            var errorBuilder = new StringBuilder();
            
            process.OutputDataReceived += (sender, e) =>
            {
                if (e.Data != null)
                    outputBuilder.AppendLine(e.Data);
            };
            
            process.ErrorDataReceived += (sender, e) =>
            {
                if (e.Data != null)
                    errorBuilder.AppendLine(e.Data);
            };
            
            process.Start();
            process.BeginOutputReadLine();
            process.BeginErrorReadLine();
            
            // Wait with timeout
            using var cts = CancellationTokenSource.CreateLinkedTokenSource(cancellationToken);
            cts.CancelAfter(TimeSpan.FromSeconds(60));
            
            try
            {
                await process.WaitForExitAsync(cts.Token);
            }
            catch (OperationCanceledException)
            {
                try { process.Kill(); } catch { }
                _logger.LogWarning("DB2 SQL command timed out after 60 seconds");
                return new Db2CommandResult { Success = false, ErrorOutput = "Command timed out" };
            }
            
            var output = outputBuilder.ToString();
            var errorOutput = errorBuilder.ToString();
            
            _logger.LogDebug("DB2 SQL command completed: ExitCode={ExitCode}, OutputLen={OutLen}, ErrorLen={ErrLen}", 
                process.ExitCode, output.Length, errorOutput.Length);
            
            if (output.Length > 0)
            {
                _logger.LogDebug("DB2 SQL output sample: {Output}", 
                    output.Length > 300 ? output[..300] + "..." : output);
            }
            
            // DB2 often outputs SQL results to stderr, so combine both for parsing
            var combinedOutput = output;
            if (!string.IsNullOrEmpty(errorOutput))
            {
                combinedOutput = output + "\n" + errorOutput;
                _logger.LogDebug("DB2 stderr sample: {Stderr}", 
                    errorOutput.Length > 300 ? errorOutput[..300] + "..." : errorOutput);
            }
            
            return new Db2CommandResult
            {
                Success = process.ExitCode == 0 && !HasSqlError(combinedOutput),
                Output = combinedOutput,  // Use combined output for parsing
                ErrorOutput = errorOutput,
                ExitCode = process.ExitCode
            };
        }
        catch (Exception ex)
        {
            _logger.LogError(ex, "Failed to execute DB2 SQL via batch for instance {Instance}", instanceName);
            return new Db2CommandResult { Success = false, ErrorOutput = ex.Message };
        }
        finally
        {
            TryDeleteFile(tempBatFile);
        }
    }
    
    private async Task<Db2CommandResult> ExecuteDb2CommandAsync(
        string instanceName, 
        string command, 
        CancellationToken cancellationToken)
    {
        if (string.IsNullOrEmpty(_db2CmdPath))
        {
            _logger.LogWarning("db2cmd.exe not found");
            return new Db2CommandResult { Success = false, ErrorOutput = "db2cmd.exe not found" };
        }
        
        _logger.LogDebug("DB2 command execution: Instance={Instance}, Command={Cmd}", 
            instanceName, command.Length > 100 ? command[..100] + "..." : command);
        
        try
        {
            // Set environment variable for the process
            var envVars = new Dictionary<string, string?>
            {
                ["DB2INSTANCE"] = instanceName
            };
            
            // Use db2cmd to run the db2 command directly
            // The /c flag closes on exit, /w waits, /i inherits environment
            // Pass the command inline: db2cmd /c /w /i "db2 connect to DB && db2 \"SELECT...\" && db2 connect reset"
            var arguments = $"/c /w /i {command}";
            
            var process = new Process
            {
                StartInfo = new ProcessStartInfo
                {
                    FileName = _db2CmdPath,
                    Arguments = arguments,
                    UseShellExecute = false,
                    CreateNoWindow = true,
                    RedirectStandardOutput = true,
                    RedirectStandardError = true,
                    StandardOutputEncoding = Encoding.GetEncoding(1252),
                    StandardErrorEncoding = Encoding.GetEncoding(1252)
                }
            };
            
            // Set the DB2INSTANCE environment variable
            process.StartInfo.Environment["DB2INSTANCE"] = instanceName;
            
            var outputBuilder = new StringBuilder();
            var errorBuilder = new StringBuilder();
            
            process.OutputDataReceived += (sender, e) =>
            {
                if (e.Data != null)
                    outputBuilder.AppendLine(e.Data);
            };
            
            process.ErrorDataReceived += (sender, e) =>
            {
                if (e.Data != null)
                    errorBuilder.AppendLine(e.Data);
            };
            
            process.Start();
            process.BeginOutputReadLine();
            process.BeginErrorReadLine();
            
            // Wait with timeout
            using var cts = CancellationTokenSource.CreateLinkedTokenSource(cancellationToken);
            cts.CancelAfter(TimeSpan.FromSeconds(60));
            
            try
            {
                await process.WaitForExitAsync(cts.Token);
            }
            catch (OperationCanceledException)
            {
                try { process.Kill(); } catch { }
                _logger.LogWarning("DB2 command timed out after 60 seconds");
                return new Db2CommandResult { Success = false, ErrorOutput = "Command timed out" };
            }
            
            var output = outputBuilder.ToString();
            var errorOutput = errorBuilder.ToString();
            
            _logger.LogDebug("DB2 command completed: ExitCode={ExitCode}, OutputLen={OutLen}, ErrorLen={ErrLen}", 
                process.ExitCode, output.Length, errorOutput.Length);
            
            if (output.Length > 0)
            {
                _logger.LogDebug("DB2 command output sample: {Output}", 
                    output.Length > 300 ? output[..300] + "..." : output);
            }
            
            // Combine stdout and stderr - DB2 sometimes outputs to stderr
            var combinedOutput = output + "\n" + errorOutput;
            
            return new Db2CommandResult
            {
                Success = process.ExitCode == 0 && !HasSqlError(combinedOutput),
                Output = combinedOutput,
                ErrorOutput = errorOutput,
                ExitCode = process.ExitCode
            };
        }
        catch (Exception ex)
        {
            _logger.LogError(ex, "Failed to execute db2cmd for instance {Instance}", instanceName);
            return new Db2CommandResult { Success = false, ErrorOutput = ex.Message };
        }
    }
    
    private string? FindDb2CmdPath()
    {
        var candidates = new[]
        {
            @"C:\DbInst\BIN\db2cmd.exe",
            @"C:\Program Files\IBM\SQLLIB\BIN\db2cmd.exe",
            Environment.ExpandEnvironmentVariables(@"%DB2PATH%\BIN\db2cmd.exe")
        };
        
        return candidates.FirstOrDefault(File.Exists);
    }
    
    private bool HasSqlError(string output)
    {
        // Check for SQL error codes: SQLxxxx with severity indicator (N, W, C, E)
        if (string.IsNullOrEmpty(output)) return false;
        
        // SQL0000W is success, don't treat as error
        if (output.Contains("SQL0000W")) return false;
        
        // Look for error patterns
        return System.Text.RegularExpressions.Regex.IsMatch(output, @"SQL\d{4,5}[NCE]");
    }
    
    private void TryDeleteFile(string path)
    {
        try
        {
            if (File.Exists(path))
                File.Delete(path);
        }
        catch { }
    }
}

/// <summary>
/// Result from a DB2 command execution.
/// </summary>
public class Db2CommandResult
{
    public bool Success { get; init; }
    public string Output { get; init; } = string.Empty;
    public string ErrorOutput { get; init; } = string.Empty;
    public int ExitCode { get; init; }
}
