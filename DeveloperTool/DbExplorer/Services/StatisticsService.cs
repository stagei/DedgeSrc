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
/// Service for managing table statistics
/// </summary>
public class StatisticsService
{
    private static readonly Logger Logger = LogManager.GetCurrentClassLogger();
    private readonly MetadataHandler? _metadataHandler;
    
    public StatisticsService(MetadataHandler? metadataHandler = null)
    {
        _metadataHandler = metadataHandler ?? App.MetadataHandler;
        Logger.Debug("StatisticsService initialized with MetadataHandler: {HasHandler}", _metadataHandler != null);
    }
    
    /// <summary>
    /// Get table statistics information
    /// </summary>
    public async Task<List<TableStatistics>> GetTableStatisticsAsync(
        IConnectionManager connectionManager,
        StatisticsFilter filter)
    {
        Logger.Info("Getting table statistics - Schema: {Schema}", filter.SchemaFilter);
        
        try
        {
            var sql = BuildStatisticsQuery(filter);
            Logger.Debug("Executing statistics query");
            Logger.Debug("SQL: {SQL}", sql);
            
            var startTime = System.Diagnostics.Stopwatch.StartNew();
            var resultTable = await connectionManager.ExecuteQueryAsync(sql);
            startTime.Stop();
            
            Logger.Info("Statistics query completed in {Ms}ms, returned {Count} rows",
                startTime.ElapsedMilliseconds, resultTable.Rows.Count);
            
            var statistics = ConvertToStatistics(resultTable);
            Logger.Info("Converted to {Count} statistics entries", statistics.Count);
            
            return statistics;
        }
        catch (Exception ex)
        {
            Logger.Error(ex, "Failed to get table statistics");
            throw;
        }
    }
    
    /// <summary>
    /// Build statistics query
    /// </summary>
    private string BuildStatisticsQuery(StatisticsFilter filter)
    {
        var sql = new StringBuilder();
        sql.AppendLine("SELECT");
        sql.AppendLine("    TABSCHEMA,");
        sql.AppendLine("    TABNAME,");
        sql.AppendLine("    STATS_TIME,");
        sql.AppendLine("    TBSPACE,");
        sql.AppendLine("    CARD");
        sql.AppendLine("FROM SYSCAT.TABLES");
        sql.AppendLine("WHERE TYPE = 'T'");
        
        // Schema filter
        if (!string.IsNullOrEmpty(filter.SchemaFilter) && filter.SchemaFilter != "*")
        {
            sql.AppendLine($"  AND TABSCHEMA = '{filter.SchemaFilter}'");
        }
        else
        {
            // Exclude system schemas
            sql.AppendLine("  AND TABSCHEMA NOT IN (");
            sql.AppendLine("    'SYSIBM', 'SYSIBMADM', 'SYSCAT', 'SYSPROC',");
            sql.AppendLine("    'SYSPUBLIC', 'SYSSTAT', 'SYSTOOLS', 'SYSFUN'");
            sql.AppendLine("  )");
        }
        
        // Show only outdated
        if (filter.ShowOnlyOutdated)
        {
            sql.AppendLine($"  AND (STATS_TIME IS NULL OR STATS_TIME < CURRENT DATE - {filter.OutdatedThresholdDays} DAYS)");
        }
        
        sql.AppendLine("ORDER BY TABSCHEMA, TABNAME");
        
        return sql.ToString();
    }
    
    /// <summary>
    /// Convert DataTable to list of TableStatistics
    /// </summary>
    private List<TableStatistics> ConvertToStatistics(DataTable dataTable)
    {
        var statistics = new List<TableStatistics>();
        
        foreach (DataRow row in dataTable.Rows)
        {
            try
            {
                var stat = new TableStatistics
                {
                    SchemaName = row["TABSCHEMA"]?.ToString() ?? string.Empty,
                    TableName = row["TABNAME"]?.ToString() ?? string.Empty,
                    StatsTime = row["STATS_TIME"] == DBNull.Value ? null : Convert.ToDateTime(row["STATS_TIME"]),
                    TablespaceName = row["TBSPACE"]?.ToString() ?? string.Empty,
                    CardinalityEstimate = row["CARD"] == DBNull.Value ? null : Convert.ToInt64(row["CARD"])
                };
                
                statistics.Add(stat);
                
                Logger.Debug("Statistics: {Schema}.{Table} - Last updated: {StatsTime}, Status: {Status}",
                    stat.SchemaName, stat.TableName, stat.StatsTime, stat.StatsStatus);
            }
            catch (Exception ex)
            {
                Logger.Warn(ex, "Failed to convert row to TableStatistics");
            }
        }
        
        return statistics;
    }
    
    /// <summary>
    /// Generate RUNSTATS script for selected tables
    /// </summary>
    public string GenerateRunstatsScript(List<TableStatistics> tables, bool withDistribution = true, bool detailedIndexes = true)
    {
        Logger.Info("Generating RUNSTATS script for {Count} tables", tables.Count);
        
        var script = new StringBuilder();
        script.AppendLine("-- Generated RUNSTATS Script");
        script.AppendLine($"-- Generated: {DateTime.Now}");
        script.AppendLine($"-- Tables: {tables.Count}");
        script.AppendLine();
        
        foreach (var table in tables)
        {
            var schema = table.SchemaName?.Trim() ?? "";
            var tableName = table.TableName?.Trim() ?? "";
            
            script.AppendLine($"-- Update statistics for {schema}.{tableName}");
            script.AppendLine($"-- Last update: {table.StatsTime?.ToString("yyyy-MM-dd HH:mm:ss") ?? "NEVER"}");
            script.AppendLine($"-- Days since update: {table.DaysSinceUpdate?.ToString() ?? "N/A"}");
            
            script.Append($"CALL SYSPROC.ADMIN_CMD('RUNSTATS ON TABLE {schema}.{tableName}");
            
            if (withDistribution)
            {
                script.Append(" WITH DISTRIBUTION");
            }
            
            if (detailedIndexes)
            {
                script.Append(" AND DETAILED INDEXES ALL");
            }
            
            script.AppendLine("');");
            script.AppendLine();
        }
        
        Logger.Info("Generated RUNSTATS script for {Count} tables", tables.Count);
        return script.ToString();
    }
    
    /// <summary>
    /// Execute RUNSTATS for a table
    /// </summary>
    public async Task ExecuteRunstatsAsync(
        IConnectionManager connectionManager,
        string schema,
        string tableName,
        bool withDistribution = true,
        bool detailedIndexes = true)
    {
        Logger.Info("Executing RUNSTATS for {Schema}.{Table}", schema, tableName);
        
        try
        {
            var sql = $"CALL SYSPROC.ADMIN_CMD('RUNSTATS ON TABLE {schema}.{tableName}";
            
            if (withDistribution)
            {
                sql += " WITH DISTRIBUTION";
            }
            
            if (detailedIndexes)
            {
                sql += " AND DETAILED INDEXES ALL";
            }
            
            sql += "')";
            
            Logger.Debug("Executing RUNSTATS: {SQL}", sql);
            await connectionManager.ExecuteQueryAsync(sql);
            
            Logger.Info("RUNSTATS completed successfully for {Schema}.{Table}", schema, tableName);
        }
        catch (Exception ex)
        {
            Logger.Error(ex, "Failed to execute RUNSTATS for {Schema}.{Table}", schema, tableName);
            throw;
        }
    }
}

