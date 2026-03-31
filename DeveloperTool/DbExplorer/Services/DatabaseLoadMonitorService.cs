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
/// Service for monitoring database load and table activity
/// </summary>
public class DatabaseLoadMonitorService
{
    private static readonly Logger Logger = LogManager.GetCurrentClassLogger();
    private readonly MetadataHandler? _metadataHandler;
    
    /// <summary>
    /// Initializes the DatabaseLoadMonitorService
    /// </summary>
    public DatabaseLoadMonitorService()
    {
        _metadataHandler = App.MetadataHandler;
    }
    
    /// <summary>
    /// Get current database load metrics with optional filtering
    /// </summary>
    public async Task<List<TableActivityMetrics>> GetTableActivityAsync(
        IConnectionManager connectionManager,
        LoadMonitorFilter filter)
    {
        // Provider-agnostic - uses IConnectionManager
        Logger.Info("Getting table activity metrics - Schema: {Schema}, Table: {Table}, ExcludeSystem: {ExcludeSystem}",
            filter.SelectedSchema, filter.SelectedTable, filter.ExcludeSystemSchemas);
        
        try
        {
            var sql = BuildActivityQuery(filter);
            Logger.Debug("Executing MON_GET_TABLE query");
            Logger.Debug("SQL: {SQL}", sql);
            
            var startTime = System.Diagnostics.Stopwatch.StartNew();
            var resultTable = await connectionManager.ExecuteQueryAsync(sql);
            startTime.Stop();
            
            Logger.Info("Query completed in {Ms}ms, returned {Count} rows", 
                startTime.ElapsedMilliseconds, resultTable.Rows.Count);
            
            var metrics = ConvertToMetrics(resultTable);
            Logger.Info("Converted to {Count} activity metrics", metrics.Count);
            
            return metrics;
        }
        catch (Exception ex)
        {
            Logger.Error(ex, "Failed to get table activity metrics");
            throw;
        }
    }
    
    /// <summary>
    /// Build the MON_GET_TABLE query with filters - includes tablespace info
    /// Uses required statements from db2_12.1_sql_statements.json
    /// </summary>
    private string BuildActivityQuery(LoadMonitorFilter filter)
    {
        var schemaFilter = filter.SelectedSchema == "*" ? "" : filter.SelectedSchema ?? "";
        var tableFilter = filter.SelectedTable == "*" ? "" : filter.SelectedTable ?? "";
        
        Logger.Debug("Building query - Schema filter: '{Schema}', Table filter: '{Table}'",
            schemaFilter, tableFilter);
        
        // Get required statement from JSON config
        if (_metadataHandler == null)
        {
            throw new InvalidOperationException("MetadataHandler not initialized");
        }
        
        var sqlTemplate = _metadataHandler.GetRequiredStatement("GetDatabaseLoadMonitor");
        
        // Build WHERE clause for system schema exclusion
        var whereClause = "";
        if (filter.ExcludeSystemSchemas)
        {
            whereClause = _metadataHandler.GetRequiredStatement("GetDatabaseLoadMonitor_SystemSchemaExclusion");
        }
        
        // Format the template with placeholders: {0}=schema, {1}=table, {2}=where clause
        var sql = string.Format(sqlTemplate, schemaFilter, tableFilter, whereClause);
        Logger.Debug("Using required statement from JSON config");
        return sql;
    }
    
    /// <summary>
    /// Convert DataTable to list of TableActivityMetrics
    /// </summary>
    private List<TableActivityMetrics> ConvertToMetrics(DataTable dataTable)
    {
        var metrics = new List<TableActivityMetrics>();
        
        foreach (DataRow row in dataTable.Rows)
        {
            try
            {
                var metric = new TableActivityMetrics
                {
                    SchemaName = row["SchemaName"]?.ToString()?.Trim() ?? string.Empty,
                    TableName = row["TableName"]?.ToString()?.Trim() ?? string.Empty,
                    TablespaceName = row["TablespaceName"]?.ToString()?.Trim() ?? string.Empty,
                    TotalRowsRead = ConvertToLong(row["TotalRowsRead"]),
                    TotalRowsInserted = ConvertToLong(row["TotalRowsInserted"]),
                    TotalRowsUpdated = ConvertToLong(row["TotalRowsUpdated"]),
                    TotalRowsDeleted = ConvertToLong(row["TotalRowsDeleted"])
                };
                
                metrics.Add(metric);
                
                Logger.Debug("Metric: {Schema}.{Table} ({Tablespace}) - Reads: {Reads}, Inserts: {Inserts}, Updates: {Updates}, Deletes: {Deletes}",
                    metric.SchemaName, metric.TableName, metric.TablespaceName, metric.TotalRowsRead, metric.TotalRowsInserted,
                    metric.TotalRowsUpdated, metric.TotalRowsDeleted);
            }
            catch (Exception ex)
            {
                Logger.Warn(ex, "Failed to convert row to metric");
            }
        }
        
        return metrics;
    }
    
    /// <summary>
    /// Safely convert database value to long
    /// </summary>
    private long ConvertToLong(object? value)
    {
        if (value == null || value == DBNull.Value)
            return 0;
            
        if (long.TryParse(value.ToString(), out var result))
            return result;
            
        return 0;
    }
    
    /// <summary>
    /// Get list of all available schemas (for dropdown filter)
    /// </summary>
    public async Task<List<string>> GetAvailableSchemasAsync(
        IConnectionManager connectionManager,
        bool excludeSystem = true)
    {
        // Provider-agnostic - uses IConnectionManager
        Logger.Debug("Getting available schemas - ExcludeSystem: {ExcludeSystem}", excludeSystem);
        
        try
        {
            var sql = new StringBuilder();
            sql.AppendLine("SELECT DISTINCT schemaname");
            sql.AppendLine("FROM SYSCAT.SCHEMATA");
            
            if (excludeSystem)
            {
                sql.AppendLine("WHERE schemaname NOT IN (");
                var systemSchemas = LoadMonitorFilter.SystemSchemas
                    .Select(s => $"    '{s}'")
                    .ToList();
                sql.AppendLine(string.Join(",\n", systemSchemas));
                sql.AppendLine(")");
            }
            
            sql.AppendLine("ORDER BY schemaname");
            
            var resultTable = await connectionManager.ExecuteQueryAsync(sql.ToString());
            
            var schemas = new List<string> { "*" }; // Add wildcard option
            
            foreach (DataRow row in resultTable.Rows)
            {
                var schemaName = row["SCHEMANAME"]?.ToString();
                if (!string.IsNullOrEmpty(schemaName))
                {
                    schemas.Add(schemaName);
                }
            }
            
            Logger.Info("Found {Count} schemas", schemas.Count - 1); // Exclude wildcard from count
            return schemas;
        }
        catch (Exception ex)
        {
            Logger.Error(ex, "Failed to get available schemas");
            return new List<string> { "*" }; // Return wildcard on error
        }
    }
    
    /// <summary>
    /// Get list of tables for a specific schema (for dropdown filter)
    /// </summary>
    public async Task<List<string>> GetTablesForSchemaAsync(
        IConnectionManager connectionManager,
        string schema)
    {
        // Provider-agnostic - uses IConnectionManager
        Logger.Debug("Getting tables for schema: {Schema}", schema);
        
        if (schema == "*")
        {
            return new List<string> { "*" }; // Only wildcard for all schemas
        }
        
        try
        {
            var sql = $@"
                SELECT DISTINCT tabname
                FROM SYSCAT.TABLES
                WHERE tabschema = '{schema}'
                  AND TYPE = 'T'
                ORDER BY tabname
            ";
            
            var resultTable = await connectionManager.ExecuteQueryAsync(sql);
            
            var tables = new List<string> { "*" }; // Add wildcard option
            
            foreach (DataRow row in resultTable.Rows)
            {
                var tableName = row["TABNAME"]?.ToString();
                if (!string.IsNullOrEmpty(tableName))
                {
                    tables.Add(tableName);
                }
            }
            
            Logger.Info("Found {Count} tables in schema {Schema}", tables.Count - 1, schema);
            return tables;
        }
        catch (Exception ex)
        {
            Logger.Error(ex, "Failed to get tables for schema: {Schema}", schema);
            return new List<string> { "*" }; // Return wildcard on error
        }
    }
    
    /// <summary>
    /// Calculate delta between two snapshots
    /// </summary>
    public List<TableActivityDelta> CalculateDelta(
        ActivitySnapshot currentSnapshot,
        ActivitySnapshot previousSnapshot,
        TimeSpan intervalDuration)
    {
        Logger.Debug("Calculating delta between snapshots - Current: {Current}, Previous: {Previous}, Interval: {Interval}s",
            currentSnapshot.SnapshotTime, previousSnapshot.SnapshotTime, intervalDuration.TotalSeconds);
        
        var deltas = new List<TableActivityDelta>();
        var intervalSeconds = intervalDuration.TotalSeconds;
        
        foreach (var current in currentSnapshot.Metrics)
        {
            // Find matching table in previous snapshot
            var previous = previousSnapshot.Metrics.FirstOrDefault(p => 
                p.SchemaName == current.SchemaName && p.TableName == current.TableName);
            
            if (previous == null)
            {
                // Table didn't exist in previous snapshot (newly created)
                Logger.Debug("Table {Schema}.{Table} not found in previous snapshot (new table)",
                    current.SchemaName, current.TableName);
                continue;
            }
            
            var delta = new TableActivityDelta
            {
                SchemaName = current.SchemaName,
                TableName = current.TableName,
                CurrentRowsRead = current.TotalRowsRead,
                CurrentRowsInserted = current.TotalRowsInserted,
                CurrentRowsUpdated = current.TotalRowsUpdated,
                CurrentRowsDeleted = current.TotalRowsDeleted,
                PreviousRowsRead = previous.TotalRowsRead,
                PreviousRowsInserted = previous.TotalRowsInserted,
                PreviousRowsUpdated = previous.TotalRowsUpdated,
                PreviousRowsDeleted = previous.TotalRowsDeleted
            };
            
            // Calculate activity rate (operations per second)
            if (intervalSeconds > 0)
            {
                delta.DeltaActivityRate = delta.TotalDeltaActivity / intervalSeconds;
            }
            
            deltas.Add(delta);
            
            Logger.Debug("Delta calculated for {Schema}.{Table} - Total: {Total}, Rate: {Rate}/s",
                delta.SchemaName, delta.TableName, delta.TotalDeltaActivity, delta.DeltaActivityRate);
        }
        
        Logger.Info("Calculated {Count} deltas", deltas.Count);
        return deltas;
    }
}

