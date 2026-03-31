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
/// Model for unused object information
/// </summary>
public class UnusedObjectInfo
{
    public string ObjectType { get; set; } = string.Empty;
    public string Schema { get; set; } = string.Empty;
    public string Name { get; set; } = string.Empty;
    public DateTime? LastUsed { get; set; }
    public int? DaysUnused { get; set; }
    
    public string UnusedStatus
    {
        get
        {
            if (!LastUsed.HasValue) return "Never Used";
            if (DaysUnused >= 1095) return "Critical (3+ years)";
            if (DaysUnused >= 730) return "Warning (2+ years)";
            if (DaysUnused >= 365) return "Caution (1+ year)";
            return "Recent";
        }
    }
}

/// <summary>
/// Service for detecting unused database objects
/// </summary>
public class UnusedObjectDetectorService
{
    private static readonly Logger Logger = LogManager.GetCurrentClassLogger();
    
    /// <summary>
    /// Find unused tables
    /// </summary>
    public async Task<List<UnusedObjectInfo>> FindUnusedTablesAsync(
        IConnectionManager connectionManager,
        int unusedThresholdDays = 365)
    {
        Logger.Info("Finding unused tables - Threshold: {Days} days", unusedThresholdDays);
        
        try
        {
            var sql = $@"
                SELECT 
                    'TABLE' AS OBJECT_TYPE,
                    TABSCHEMA AS SCHEMA,
                    TABNAME AS NAME,
                    LASTUSED,
                    DAYS(CURRENT DATE) - DAYS(COALESCE(LASTUSED, '1900-01-01')) AS DAYS_UNUSED
                FROM SYSCAT.TABLES
                WHERE TYPE = 'T'
                  AND TABSCHEMA NOT IN ('SYSIBM', 'SYSIBMADM', 'SYSCAT', 'SYSPROC', 'SYSTOOLS')
                  AND (LASTUSED < CURRENT DATE - {unusedThresholdDays} DAYS OR LASTUSED IS NULL)
                ORDER BY DAYS_UNUSED DESC
            ";
            
            var result = await connectionManager.ExecuteQueryAsync(sql);
            Logger.Info("Found {Count} unused tables", result.Rows.Count);
            
            return ConvertToUnusedObjects(result);
        }
        catch (Exception ex)
        {
            Logger.Error(ex, "Failed to find unused tables");
            throw;
        }
    }
    
    /// <summary>
    /// Find unused packages
    /// </summary>
    public async Task<List<UnusedObjectInfo>> FindUnusedPackagesAsync(
        IConnectionManager connectionManager,
        int unusedThresholdDays = 365)
    {
        Logger.Info("Finding unused packages - Threshold: {Days} days", unusedThresholdDays);
        
        try
        {
            var sql = $@"
                SELECT 
                    'PACKAGE' AS OBJECT_TYPE,
                    PKGSCHEMA AS SCHEMA,
                    PKGNAME AS NAME,
                    LASTUSED,
                    DAYS(CURRENT DATE) - DAYS(COALESCE(LASTUSED, '1900-01-01')) AS DAYS_UNUSED
                FROM SYSCAT.PACKAGES
                WHERE (LASTUSED < CURRENT DATE - {unusedThresholdDays} DAYS OR LASTUSED IS NULL)
                ORDER BY DAYS_UNUSED DESC
            ";
            
            var result = await connectionManager.ExecuteQueryAsync(sql);
            Logger.Info("Found {Count} unused packages", result.Rows.Count);
            
            return ConvertToUnusedObjects(result);
        }
        catch (Exception ex)
        {
            Logger.Error(ex, "Failed to find unused packages");
            throw;
        }
    }
    
    /// <summary>
    /// Convert DataTable to list of UnusedObjectInfo
    /// </summary>
    private List<UnusedObjectInfo> ConvertToUnusedObjects(DataTable dataTable)
    {
        var objects = new List<UnusedObjectInfo>();
        
        foreach (DataRow row in dataTable.Rows)
        {
            try
            {
                var obj = new UnusedObjectInfo
                {
                    ObjectType = row["OBJECT_TYPE"]?.ToString() ?? string.Empty,
                    Schema = row["SCHEMA"]?.ToString() ?? string.Empty,
                    Name = row["NAME"]?.ToString() ?? string.Empty,
                    LastUsed = row["LASTUSED"] == DBNull.Value ? null : Convert.ToDateTime(row["LASTUSED"]),
                    DaysUnused = row["DAYS_UNUSED"] == DBNull.Value ? null : Convert.ToInt32(row["DAYS_UNUSED"])
                };
                
                objects.Add(obj);
                
                Logger.Debug("Unused object: {Type} {Schema}.{Name} - Days unused: {Days}",
                    obj.ObjectType, obj.Schema, obj.Name, obj.DaysUnused);
            }
            catch (Exception ex)
            {
                Logger.Warn(ex, "Failed to convert row to UnusedObjectInfo");
            }
        }
        
        return objects;
    }
    
    /// <summary>
    /// Generate DROP script for unused objects
    /// </summary>
    public string GenerateDropScript(List<UnusedObjectInfo> objects, bool includeComments = true)
    {
        Logger.Info("Generating DROP script for {Count} unused objects", objects.Count);
        
        var script = new StringBuilder();
        script.AppendLine("-- Generated DROP Script for Unused Objects");
        script.AppendLine($"-- Generated: {DateTime.Now}");
        script.AppendLine($"-- Objects: {objects.Count}");
        script.AppendLine("-- WARNING: Review carefully before executing!");
        script.AppendLine("-- RECOMMENDATION: Archive data before dropping tables!");
        script.AppendLine();
        
        foreach (var obj in objects.OrderBy(o => o.ObjectType).ThenBy(o => o.Schema).ThenBy(o => o.Name))
        {
            if (includeComments)
            {
                script.AppendLine($"-- {obj.ObjectType}: {obj.Schema}.{obj.Name}");
                script.AppendLine($"-- Last used: {obj.LastUsed?.ToString("yyyy-MM-dd") ?? "NEVER"}");
                script.AppendLine($"-- Days unused: {obj.DaysUnused?.ToString() ?? "N/A"}");
                script.AppendLine($"-- Status: {obj.UnusedStatus}");
            }
            
            script.AppendLine($"DROP {obj.ObjectType} {obj.Schema}.{obj.Name};");
            script.AppendLine();
        }
        
        Logger.Info("Generated DROP script for {Count} objects", objects.Count);
        return script.ToString();
    }
}

