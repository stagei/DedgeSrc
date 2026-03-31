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
/// Service for managing Change Data Capture (CDC)
/// </summary>
public class DataCaptureService
{
    private static readonly Logger Logger = LogManager.GetCurrentClassLogger();
    
    /// <summary>
    /// Get data capture information for tables
    /// </summary>
    public async Task<List<DataCaptureInfo>> GetDataCaptureInfoAsync(
        IConnectionManager connectionManager,
        CdcMonitorFilter filter)
    {
        Logger.Info("Getting data capture info - Schema: {Schema}", filter.SchemaFilter);
        
        try
        {
            var sql = BuildCdcQuery(filter);
            Logger.Debug("Executing CDC query");
            Logger.Debug("SQL: {SQL}", sql);
            
            var startTime = System.Diagnostics.Stopwatch.StartNew();
            var resultTable = await connectionManager.ExecuteQueryAsync(sql);
            startTime.Stop();
            
            Logger.Info("CDC query completed in {Ms}ms, returned {Count} rows",
                startTime.ElapsedMilliseconds, resultTable.Rows.Count);
            
            var cdcInfo = ConvertToCdcInfo(resultTable);
            Logger.Info("Converted to {Count} CDC entries", cdcInfo.Count);
            
            return cdcInfo;
        }
        catch (Exception ex)
        {
            Logger.Error(ex, "Failed to get data capture info");
            throw;
        }
    }
    
    /// <summary>
    /// Build CDC query
    /// </summary>
    private string BuildCdcQuery(CdcMonitorFilter filter)
    {
        var sql = new StringBuilder();
        sql.AppendLine("SELECT");
        sql.AppendLine("    TABSCHEMA,");
        sql.AppendLine("    TABNAME,");
        sql.AppendLine("    DATACAPTURE,");
        sql.AppendLine("    TBSPACE,");
        sql.AppendLine("    TYPE");
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
        
        // Show only disabled
        if (filter.ShowOnlyDisabled)
        {
            sql.AppendLine("  AND DATACAPTURE = 'N'");
        }
        
        sql.AppendLine("ORDER BY TABSCHEMA, TABNAME");
        
        return sql.ToString();
    }
    
    /// <summary>
    /// Convert DataTable to list of DataCaptureInfo
    /// </summary>
    private List<DataCaptureInfo> ConvertToCdcInfo(DataTable dataTable)
    {
        var cdcInfoList = new List<DataCaptureInfo>();
        
        foreach (DataRow row in dataTable.Rows)
        {
            try
            {
                var cdcInfo = new DataCaptureInfo
                {
                    SchemaName = row["TABSCHEMA"]?.ToString() ?? string.Empty,
                    TableName = row["TABNAME"]?.ToString() ?? string.Empty,
                    DataCapture = row["DATACAPTURE"]?.ToString() ?? "N",
                    TablespaceName = row["TBSPACE"]?.ToString() ?? string.Empty,
                    TableType = row["TYPE"]?.ToString() ?? string.Empty
                };
                
                cdcInfoList.Add(cdcInfo);
                
                Logger.Debug("CDC: {Schema}.{Table} - DataCapture: {DataCapture}, Status: {Status}",
                    cdcInfo.SchemaName, cdcInfo.TableName, cdcInfo.DataCapture, cdcInfo.CdcStatus);
            }
            catch (Exception ex)
            {
                Logger.Warn(ex, "Failed to convert row to DataCaptureInfo");
            }
        }
        
        return cdcInfoList;
    }
    
    /// <summary>
    /// Generate ALTER TABLE script to enable CDC
    /// </summary>
    public string GenerateEnableCdcScript(List<DataCaptureInfo> tables)
    {
        Logger.Info("Generating ENABLE CDC script for {Count} tables", tables.Count);
        
        var script = new StringBuilder();
        script.AppendLine("-- Generated ENABLE CDC Script");
        script.AppendLine($"-- Generated: {DateTime.Now}");
        script.AppendLine($"-- Tables: {tables.Count}");
        script.AppendLine("-- WARNING: Enabling CDC may impact performance!");
        script.AppendLine();
        
        foreach (var table in tables.Where(t => !t.IsCdcEnabled))
        {
            var schema = table.SchemaName?.Trim() ?? "";
            var tableName = table.TableName?.Trim() ?? "";
            
            script.AppendLine($"-- Enable CDC for {schema}.{tableName}");
            script.AppendLine($"-- Current status: {table.CdcStatus}");
            script.AppendLine($"ALTER TABLE {schema}.{tableName} DATA CAPTURE CHANGES;");
            script.AppendLine();
        }
        
        Logger.Info("Generated ENABLE CDC script for {Count} tables", tables.Count(t => !t.IsCdcEnabled));
        return script.ToString();
    }
    
    /// <summary>
    /// Generate ALTER TABLE script to disable CDC
    /// </summary>
    public string GenerateDisableCdcScript(List<DataCaptureInfo> tables)
    {
        Logger.Info("Generating DISABLE CDC script for {Count} tables", tables.Count);
        
        var script = new StringBuilder();
        script.AppendLine("-- Generated DISABLE CDC Script");
        script.AppendLine($"-- Generated: {DateTime.Now}");
        script.AppendLine($"-- Tables: {tables.Count}");
        script.AppendLine();
        
        foreach (var table in tables.Where(t => t.IsCdcEnabled))
        {
            var schema = table.SchemaName?.Trim() ?? "";
            var tableName = table.TableName?.Trim() ?? "";
            
            script.AppendLine($"-- Disable CDC for {schema}.{tableName}");
            script.AppendLine($"-- Current status: {table.CdcStatus}");
            script.AppendLine($"ALTER TABLE {schema}.{tableName} DATA CAPTURE NONE;");
            script.AppendLine();
        }
        
        Logger.Info("Generated DISABLE CDC script for {Count} tables", tables.Count(t => t.IsCdcEnabled));
        return script.ToString();
    }
    
    /// <summary>
    /// Enable CDC for a table
    /// </summary>
    public async Task EnableCdcAsync(
        IConnectionManager connectionManager,
        string schema,
        string tableName)
    {
        Logger.Info("Enabling CDC for {Schema}.{Table}", schema, tableName);
        
        try
        {
            var sql = $"ALTER TABLE {schema}.{tableName} DATA CAPTURE CHANGES";
            Logger.Debug("Executing: {SQL}", sql);
            
            await connectionManager.ExecuteQueryAsync(sql);
            
            Logger.Info("CDC enabled successfully for {Schema}.{Table}", schema, tableName);
        }
        catch (Exception ex)
        {
            Logger.Error(ex, "Failed to enable CDC for {Schema}.{Table}", schema, tableName);
            throw;
        }
    }
    
    /// <summary>
    /// Disable CDC for a table
    /// </summary>
    public async Task DisableCdcAsync(
        IConnectionManager connectionManager,
        string schema,
        string tableName)
    {
        Logger.Info("Disabling CDC for {Schema}.{Table}", schema, tableName);
        
        try
        {
            var sql = $"ALTER TABLE {schema}.{tableName} DATA CAPTURE NONE";
            Logger.Debug("Executing: {SQL}", sql);
            
            await connectionManager.ExecuteQueryAsync(sql);
            
            Logger.Info("CDC disabled successfully for {Schema}.{Table}", schema, tableName);
        }
        catch (Exception ex)
        {
            Logger.Error(ex, "Failed to disable CDC for {Schema}.{Table}", schema, tableName);
            throw;
        }
    }
}

