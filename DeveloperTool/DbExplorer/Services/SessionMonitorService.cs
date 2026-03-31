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
/// Service for monitoring active database sessions
/// </summary>
public class SessionMonitorService
{
    private static readonly Logger Logger = LogManager.GetCurrentClassLogger();
    
    /// <summary>
    /// Get active database sessions
    /// </summary>
    public async Task<List<SessionInfo>> GetActiveSessionsAsync(
        IConnectionManager connectionManager,
        SessionMonitorFilter filter)
    {
        Logger.Info("Getting active sessions - User: {User}, Application: {App}",
            filter.UserFilter, filter.ApplicationFilter);
        
        try
        {
            var sql = BuildSessionQuery(filter);
            Logger.Debug("Executing session query");
            Logger.Debug("SQL: {SQL}", sql);
            
            var startTime = System.Diagnostics.Stopwatch.StartNew();
            var resultTable = await connectionManager.ExecuteQueryAsync(sql);
            startTime.Stop();
            
            Logger.Info("Session query completed in {Ms}ms, returned {Count} rows",
                startTime.ElapsedMilliseconds, resultTable.Rows.Count);
            
            var sessions = ConvertToSessionInfo(resultTable);
            Logger.Info("Converted to {Count} session entries", sessions.Count);
            
            return sessions;
        }
        catch (Exception ex)
        {
            Logger.Error(ex, "Failed to get active sessions");
            throw;
        }
    }
    
    /// <summary>
    /// Build session monitoring query
    /// </summary>
    private string BuildSessionQuery(SessionMonitorFilter filter)
    {
        var sql = new StringBuilder();
        sql.AppendLine("SELECT");
        sql.AppendLine("    AGENT_ID,");
        sql.AppendLine("    DB_NAME,");
        sql.AppendLine("    PRIMARY_AUTH_ID,");
        sql.AppendLine("    CLIENT_NNAME,");
        sql.AppendLine("    APPL_NAME,");
        sql.AppendLine("    APPL_ID,");
        sql.AppendLine("    APPL_STATUS");
        sql.AppendLine("FROM SYSIBMADM.SNAPAPPL_INFO");
        sql.AppendLine("WHERE 1=1");
        
        // User filter
        if (!string.IsNullOrEmpty(filter.UserFilter) && filter.UserFilter != "*")
        {
            sql.AppendLine($"  AND PRIMARY_AUTH_ID = '{filter.UserFilter}'");
        }
        
        // Application filter
        if (!string.IsNullOrEmpty(filter.ApplicationFilter) && filter.ApplicationFilter != "*")
        {
            sql.AppendLine($"  AND APPL_NAME LIKE '%{filter.ApplicationFilter}%'");
        }
        
        sql.AppendLine("ORDER BY PRIMARY_AUTH_ID, DB_NAME");
        
        return sql.ToString();
    }
    
    /// <summary>
    /// Convert DataTable to list of SessionInfo
    /// </summary>
    private List<SessionInfo> ConvertToSessionInfo(DataTable dataTable)
    {
        var sessions = new List<SessionInfo>();
        
        foreach (DataRow row in dataTable.Rows)
        {
            try
            {
                var session = new SessionInfo
                {
                    AgentId = ConvertToInt(row["AGENT_ID"]),
                    DatabaseName = row["DB_NAME"]?.ToString() ?? string.Empty,
                    AuthorizationId = row["PRIMARY_AUTH_ID"]?.ToString() ?? string.Empty,
                    ClientName = row["CLIENT_NNAME"]?.ToString() ?? string.Empty,
                    ApplicationName = row["APPL_NAME"]?.ToString() ?? string.Empty,
                    ApplicationId = row["APPL_ID"]?.ToString() ?? string.Empty,
                    // Note: AGENT_STATE_LAST_UPDATE_TIME is not available in SYSIBMADM.SNAPAPPL_INFO for all DB2 versions
                    // ConnectTime will be null, and DurationText will show "N/A"
                    ConnectTime = null,
                    Status = row["APPL_STATUS"]?.ToString() ?? string.Empty
                };
                
                sessions.Add(session);
                
                Logger.Debug("Session: Agent {AgentId}, User: {User}, App: {App}, Duration: {Duration}",
                    session.AgentId, session.AuthorizationId, session.ApplicationName, session.DurationText);
            }
            catch (Exception ex)
            {
                Logger.Warn(ex, "Failed to convert row to SessionInfo");
            }
        }
        
        return sessions;
    }
    
    /// <summary>
    /// Generate FORCE APPLICATION script for selected sessions
    /// </summary>
    public string GenerateForceApplicationScript(List<SessionInfo> sessions)
    {
        Logger.Info("Generating FORCE APPLICATION script for {Count} sessions", sessions.Count);
        
        var script = new StringBuilder();
        script.AppendLine("-- Generated FORCE APPLICATION Script");
        script.AppendLine($"-- Generated: {DateTime.Now}");
        script.AppendLine($"-- Sessions: {sessions.Count}");
        script.AppendLine($"-- WARNING: This will terminate database connections!");
        script.AppendLine();
        
        foreach (var session in sessions)
        {
            script.AppendLine($"-- Agent ID: {session.AgentId}");
            script.AppendLine($"-- User: {session.AuthorizationId}");
            script.AppendLine($"-- Application: {session.ApplicationName}");
            script.AppendLine($"-- Client: {session.ClientName}");
            script.AppendLine($"-- Duration: {session.DurationText}");
            script.AppendLine($"FORCE APPLICATION ({session.AgentId});");
            script.AppendLine();
        }
        
        Logger.Info("Generated script for {Count} sessions", sessions.Count);
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

