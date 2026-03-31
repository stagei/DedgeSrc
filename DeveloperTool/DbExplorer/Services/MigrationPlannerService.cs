using System;
using System.Collections.Generic;
using System.Data;
using System.Linq;
using System.Text;
using System.Threading.Tasks;
using NLog;
using DbExplorer.Data;

namespace DbExplorer.Services;

/// <summary>
/// Model for migration candidate
/// </summary>
public class MigrationCandidate
{
    public string Schema { get; set; } = string.Empty;
    public string TableName { get; set; } = string.Empty;
    public DateTime? LastUsed { get; set; }
    public long? RowCount { get; set; }
    public bool IsActive { get; set; }
    public string MigrationStatus { get; set; } = "Pending";
}

/// <summary>
/// Service for planning schema migrations
/// </summary>
public class MigrationPlannerService
{
    private static readonly Logger Logger = LogManager.GetCurrentClassLogger();
    
    /// <summary>
    /// Identify tables for migration based on usage
    /// </summary>
    public async Task<List<MigrationCandidate>> IdentifyMigrationCandidatesAsync(
        IConnectionManager connectionManager,
        string schema,
        int activeThresholdYears = 3)
    {
        Logger.Info("Identifying migration candidates for schema: {Schema}, Threshold: {Years} years",
            schema, activeThresholdYears);
        
        try
        {
            var sql = $@"
                SELECT
                    TABSCHEMA AS SCHEMA,
                    TABNAME AS TABLE_NAME,
                    LASTUSED,
                    CARD AS ROW_COUNT,
                    CASE 
                        WHEN LASTUSED >= CURRENT DATE - {activeThresholdYears} YEARS THEN 1
                        ELSE 0
                    END AS IS_ACTIVE
                FROM SYSCAT.TABLES
                WHERE TABSCHEMA = '{schema}'
                  AND TYPE = 'T'
                ORDER BY IS_ACTIVE DESC, LASTUSED DESC
            ";
            
            var result = await connectionManager.ExecuteQueryAsync(sql);
            Logger.Info("Found {Count} migration candidates", result.Rows.Count);
            
            var candidates = new List<MigrationCandidate>();
            
            foreach (DataRow row in result.Rows)
            {
                candidates.Add(new MigrationCandidate
                {
                    Schema = row["SCHEMA"]?.ToString() ?? string.Empty,
                    TableName = row["TABLE_NAME"]?.ToString() ?? string.Empty,
                    LastUsed = row["LASTUSED"] == DBNull.Value ? null : Convert.ToDateTime(row["LASTUSED"]),
                    RowCount = row["ROW_COUNT"] == DBNull.Value ? null : Convert.ToInt64(row["ROW_COUNT"]),
                    IsActive = Convert.ToInt32(row["IS_ACTIVE"]) == 1,
                    MigrationStatus = Convert.ToInt32(row["IS_ACTIVE"]) == 1 ? "Migrate" : "Archive"
                });
            }
            
            Logger.Info("Active tables: {Active}, Archive candidates: {Archive}",
                candidates.Count(c => c.IsActive),
                candidates.Count(c => !c.IsActive));
            
            return candidates;
        }
        catch (Exception ex)
        {
            Logger.Error(ex, "Failed to identify migration candidates for schema {Schema}", schema);
            throw;
        }
    }
    
    /// <summary>
    /// Generate migration script
    /// </summary>
    public async Task<string> GenerateMigrationScriptAsync(
        IConnectionManager connectionManager,
        List<MigrationCandidate> candidates)
    {
        Logger.Info("Generating migration script for {Count} tables", candidates.Count);
        
        var script = new StringBuilder();
        script.AppendLine("-- Migration Script");
        script.AppendLine($"-- Generated: {DateTime.Now}");
        script.AppendLine($"-- Total tables: {candidates.Count}");
        script.AppendLine($"-- Active tables: {candidates.Count(c => c.IsActive)}");
        script.AppendLine($"-- Archive candidates: {candidates.Count(c => !c.IsActive)}");
        script.AppendLine();
        
        // Group by migration status
        foreach (var group in candidates.GroupBy(c => c.MigrationStatus))
        {
            script.AppendLine($"-- {group.Key} ({group.Count()} tables)");
            script.AppendLine("-- " + new string('-', 70));
            
            foreach (var candidate in group)
            {
                script.AppendLine($"-- Table: {candidate.Schema}.{candidate.TableName}");
                script.AppendLine($"-- Last used: {candidate.LastUsed?.ToString("yyyy-MM-dd") ?? "NEVER"}");
                script.AppendLine($"-- Rows: {candidate.RowCount?.ToString("N0") ?? "Unknown"}");
            }
            
            script.AppendLine();
        }
        
        return script.ToString();
    }
}

