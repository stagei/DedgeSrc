using System;
using System.Collections.Generic;
using System.Data;
using System.Linq;
using System.Text;
using System.Threading.Tasks;
using NLog;
using DbExplorer.Data;
using DbExplorer.Models;

namespace DbExplorer.Services;

/// <summary>
/// Service for monitoring database locks
/// </summary>
public class LockMonitorService
{
    private static readonly Logger Logger = LogManager.GetCurrentClassLogger();
    
    /// <summary>
    /// Get current database locks
    /// </summary>
    public async Task<List<LockInfo>> GetCurrentLocksAsync(
        IConnectionManager connectionManager,
        LockMonitorFilter filter)
    {
        Logger.Info("Getting current locks - Schema: {Schema}, Table: {Table}",
            filter.SchemaFilter, filter.TableFilter);
        
        try
        {
            var sql = BuildLockQuery(filter);
            Logger.Debug("Executing lock query");
            Logger.Debug("SQL: {SQL}", sql);
            
            var startTime = System.Diagnostics.Stopwatch.StartNew();
            var resultTable = await connectionManager.ExecuteQueryAsync(sql);
            startTime.Stop();
            
            Logger.Info("Lock query completed in {Ms}ms, returned {Count} rows",
                startTime.ElapsedMilliseconds, resultTable.Rows.Count);
            
            var locks = ConvertToLockInfo(resultTable);
            Logger.Info("Converted to {Count} lock entries", locks.Count);
            
            return locks;
        }
        catch (Exception ex)
        {
            Logger.Error(ex, "Failed to get current locks");
            throw;
        }
    }
    
    /// <summary>
    /// Build lock monitoring query
    /// </summary>
    private string BuildLockQuery(LockMonitorFilter filter)
    {
        var sql = new StringBuilder();
        sql.AppendLine("SELECT DISTINCT");
        sql.AppendLine("    l.TABSCHEMA,");
        sql.AppendLine("    l.TABNAME,");
        sql.AppendLine("    l.LOCK_STATUS,");
        sql.AppendLine("    l.LOCK_MODE,");
        sql.AppendLine("    appls.PRIMARY_AUTH_ID,");
        sql.AppendLine("    appls.CLIENT_NNAME,");
        sql.AppendLine("    appls.APPL_NAME,");
        sql.AppendLine("    l.AGENT_ID");
        sql.AppendLine("FROM SYSIBMADM.SNAPAPPL_INFO AS appls");
        sql.AppendLine("JOIN SYSIBMADM.SNAPLOCK l ON appls.AGENT_ID = l.AGENT_ID");
        sql.AppendLine("WHERE l.TABNAME <> ''");
        
        // Schema filter
        if (!string.IsNullOrEmpty(filter.SchemaFilter) && filter.SchemaFilter != "*")
        {
            sql.AppendLine($"  AND l.TABSCHEMA = '{filter.SchemaFilter}'");
        }
        
        // Table filter
        if (!string.IsNullOrEmpty(filter.TableFilter) && filter.TableFilter != "*")
        {
            sql.AppendLine($"  AND l.TABNAME = '{filter.TableFilter}'");
        }
        
        // Exclude system tables
        if (filter.ExcludeSystemTables)
        {
            sql.AppendLine("  AND l.TABSCHEMA NOT IN (");
            sql.AppendLine("    'SYSIBM', 'SYSIBMADM', 'SYSCAT', 'SYSPROC',");
            sql.AppendLine("    'SYSPUBLIC', 'SYSSTAT', 'SYSTOOLS', 'SYSFUN'");
            sql.AppendLine("  )");
        }
        
        // Show only blocked locks
        if (filter.ShowOnlyBlocked)
        {
            sql.AppendLine("  AND l.LOCK_STATUS = 'WAITING'");
        }
        
        sql.AppendLine("ORDER BY l.TABSCHEMA, l.TABNAME");
        
        return sql.ToString();
    }
    
    /// <summary>
    /// Convert DataTable to list of LockInfo
    /// </summary>
    private List<LockInfo> ConvertToLockInfo(DataTable dataTable)
    {
        var locks = new List<LockInfo>();
        
        foreach (DataRow row in dataTable.Rows)
        {
            try
            {
                var lockInfo = new LockInfo
                {
                    SchemaName = row["TABSCHEMA"]?.ToString() ?? string.Empty,
                    TableName = row["TABNAME"]?.ToString() ?? string.Empty,
                    LockStatus = row["LOCK_STATUS"]?.ToString() ?? string.Empty,
                    LockMode = row["LOCK_MODE"]?.ToString() ?? string.Empty,
                    AuthorizationId = row["PRIMARY_AUTH_ID"]?.ToString() ?? string.Empty,
                    ClientName = row["CLIENT_NNAME"]?.ToString() ?? string.Empty,
                    ApplicationName = row["APPL_NAME"]?.ToString() ?? string.Empty,
                    AgentId = ConvertToInt(row["AGENT_ID"])
                };
                
                locks.Add(lockInfo);
                
                Logger.Debug("Lock: {Schema}.{Table} - Mode: {Mode}, Status: {Status}, User: {User}",
                    lockInfo.SchemaName, lockInfo.TableName, lockInfo.LockMode, 
                    lockInfo.LockStatus, lockInfo.AuthorizationId);
            }
            catch (Exception ex)
            {
                Logger.Warn(ex, "Failed to convert row to LockInfo");
            }
        }
        
        return locks;
    }
    
    /// <summary>
    /// Generate FORCE APPLICATION script for selected locks
    /// </summary>
    public string GenerateForceApplicationScript(List<LockInfo> locks)
    {
        Logger.Info("Generating FORCE APPLICATION script for {Count} locks", locks.Count);
        
        var script = new StringBuilder();
        script.AppendLine("-- Generated FORCE APPLICATION Script");
        script.AppendLine($"-- Generated: {DateTime.Now}");
        script.AppendLine($"-- WARNING: This will terminate database connections!");
        script.AppendLine();
        
        var distinctAgents = locks.Select(l => l.AgentId).Distinct().ToList();
        
        foreach (var agentId in distinctAgents)
        {
            var agentLocks = locks.Where(l => l.AgentId == agentId).ToList();
            var firstLock = agentLocks.First();
            
            script.AppendLine($"-- Agent ID: {agentId}");
            script.AppendLine($"-- User: {firstLock.AuthorizationId}");
            script.AppendLine($"-- Application: {firstLock.ApplicationName}");
            script.AppendLine($"-- Client: {firstLock.ClientName}");
            script.AppendLine($"-- Locks: {string.Join(", ", agentLocks.Select(l => $"{l.SchemaName?.Trim()}.{l.TableName?.Trim()}"))}");
            script.AppendLine($"FORCE APPLICATION ({agentId});");
            script.AppendLine();
        }
        
        Logger.Info("Generated script for {Count} agents", distinctAgents.Count);
        return script.ToString();
    }
    
    /// <summary>
    /// Safely convert value to int
    /// </summary>
    private int ConvertToInt(object? value)
    {
        if (value == null || value == DBNull.Value)
            return 0;
            
        if (int.TryParse(value.ToString(), out var result))
            return result;
            
        return 0;
    }
}

