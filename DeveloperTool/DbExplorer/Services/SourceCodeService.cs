using System;
using System.Collections.Generic;
using System.Data;
using System.IO;
using System.Linq;
using System.Text;
using System.Threading.Tasks;
using NLog;
using DbExplorer.Data;

namespace DbExplorer.Services;

/// <summary>
/// Model for database source code object
/// </summary>
public class SourceCodeObject
{
    public string ObjectType { get; set; } = string.Empty; // PROCEDURE, FUNCTION, VIEW, TRIGGER
    public string Schema { get; set; } = string.Empty;
    public string Name { get; set; } = string.Empty;
    public string? SourceCode { get; set; }
    public DateTime? CreatedTime { get; set; }
    public DateTime? LastRegenTime { get; set; }
    public string? Language { get; set; }
    
    public bool HasSource => !string.IsNullOrWhiteSpace(SourceCode);
    public string DisplayName => $"{Schema?.Trim()}.{Name?.Trim()}";
}

/// <summary>
/// Service for browsing and extracting database source code
/// </summary>
public class SourceCodeService
{
    private static readonly Logger Logger = LogManager.GetCurrentClassLogger();
    private readonly MetadataHandler _metadataHandler;
    
    public SourceCodeService(MetadataHandler? metadataHandler = null)
    {
        // Ensure we always have a metadata handler (avoid nullable dereference warnings)
        _metadataHandler = metadataHandler ?? App.MetadataHandler ?? new MetadataHandler();
    }
    
    /// <summary>
    /// Get all procedures in a schema
    /// </summary>
    public async Task<List<SourceCodeObject>> GetProceduresAsync(
        IConnectionManager connectionManager,
        string schema)
    {
        Logger.Info("Getting procedures for schema: {Schema}", schema);
        
        try
        {
            var sqlTemplate = _metadataHandler.GetQuery("DB2", "12.1", "GetProceduresSourceCode");
            var sql = sqlTemplate.Replace("?", $"'{schema}'");
            
            Logger.Debug("Using query: SERVICE_GetProceduresSourceCode");
            var result = await connectionManager.ExecuteQueryAsync(sql);
            Logger.Info("Found {Count} procedures in schema {Schema}", result.Rows.Count, schema);
            
            return ConvertToSourceCodeObjects(result);
        }
        catch (Exception ex)
        {
            Logger.Error(ex, "Failed to get procedures for schema {Schema}", schema);
            throw;
        }
    }
    
    /// <summary>
    /// Get all functions in a schema
    /// </summary>
    public async Task<List<SourceCodeObject>> GetFunctionsAsync(
        IConnectionManager connectionManager,
        string schema)
    {
        Logger.Info("Getting functions for schema: {Schema}", schema);
        
        try
        {
            var sqlTemplate = _metadataHandler.GetQuery("DB2", "12.1", "GetFunctionsSourceCode");
            var sql = sqlTemplate.Replace("?", $"'{schema}'");
            
            Logger.Debug("Using query: SERVICE_GetFunctionsSourceCode");
            var result = await connectionManager.ExecuteQueryAsync(sql);
            Logger.Info("Found {Count} functions in schema {Schema}", result.Rows.Count, schema);
            
            return ConvertToSourceCodeObjects(result);
        }
        catch (Exception ex)
        {
            Logger.Error(ex, "Failed to get functions for schema {Schema}", schema);
            throw;
        }
    }
    
    /// <summary>
    /// Get all views in a schema
    /// </summary>
    public async Task<List<SourceCodeObject>> GetViewsAsync(
        IConnectionManager connectionManager,
        string schema)
    {
        Logger.Info("Getting views for schema: {Schema}", schema);
        
        try
        {
            var sqlTemplate = _metadataHandler.GetQuery("DB2", "12.1", "GetViewSourceCode");
            var sql = sqlTemplate.Replace("?", $"'{schema}'");
            
            Logger.Debug("Using query: SERVICE_GetViewSourceCode");
            var result = await connectionManager.ExecuteQueryAsync(sql);
            Logger.Info("Found {Count} views in schema {Schema}", result.Rows.Count, schema);
            
            return ConvertToSourceCodeObjects(result);
        }
        catch (Exception ex)
        {
            Logger.Error(ex, "Failed to get views for schema {Schema}", schema);
            throw;
        }
    }
    
    /// <summary>
    /// Get all triggers for a table
    /// </summary>
    public async Task<List<SourceCodeObject>> GetTriggersAsync(
        IConnectionManager connectionManager,
        string schema,
        string tableName)
    {
        Logger.Info("Getting triggers for {Schema}.{Table}", schema, tableName);
        
        try
        {
            var sqlTemplate = _metadataHandler.GetQuery("DB2", "12.1", "GetTriggerSourceCode");
            var sql = sqlTemplate.Replace("?", $"'{schema}'").Replace("?", $"'{tableName}'");
            
            Logger.Debug("Using query: SERVICE_GetTriggerSourceCode");
            var result = await connectionManager.ExecuteQueryAsync(sql);
            Logger.Info("Found {Count} triggers for {Schema}.{Table}", result.Rows.Count, schema, tableName);
            
            return ConvertToSourceCodeObjects(result);
        }
        catch (Exception ex)
        {
            Logger.Error(ex, "Failed to get triggers for {Schema}.{Table}", schema, tableName);
            throw;
        }
    }
    
    /// <summary>
    /// Convert DataTable to list of SourceCodeObject
    /// </summary>
    private List<SourceCodeObject> ConvertToSourceCodeObjects(DataTable dataTable)
    {
        var objects = new List<SourceCodeObject>();
        
        foreach (DataRow row in dataTable.Rows)
        {
            try
            {
                var obj = new SourceCodeObject
                {
                    ObjectType = row["OBJECT_TYPE"]?.ToString() ?? string.Empty,
                    Schema = row["SCHEMA"]?.ToString() ?? string.Empty,
                    Name = row["NAME"]?.ToString() ?? string.Empty,
                    SourceCode = row["SOURCE_CODE"] == DBNull.Value ? null : row["SOURCE_CODE"]?.ToString(),
                    CreatedTime = row["CREATE_TIME"] == DBNull.Value ? null : Convert.ToDateTime(row["CREATE_TIME"]),
                    LastRegenTime = row["LAST_REGEN_TIME"] == DBNull.Value ? null : Convert.ToDateTime(row["LAST_REGEN_TIME"]),
                    Language = row["LANGUAGE"] == DBNull.Value ? null : row["LANGUAGE"]?.ToString()
                };
                
                objects.Add(obj);
            }
            catch (Exception ex)
            {
                Logger.Warn(ex, "Failed to convert row to SourceCodeObject");
            }
        }
        
        return objects;
    }
    
    /// <summary>
    /// Export source code to files
    /// </summary>
    public async Task ExportSourceToFilesAsync(
        List<SourceCodeObject> objects,
        string outputDirectory)
    {
        Logger.Info("Exporting {Count} source code objects to {Directory}", objects.Count, outputDirectory);
        
        if (!Directory.Exists(outputDirectory))
        {
            Directory.CreateDirectory(outputDirectory);
            Logger.Debug("Created output directory: {Directory}", outputDirectory);
        }
        
        foreach (var obj in objects.Where(o => o.HasSource))
        {
            try
            {
                var schema = obj.Schema?.Trim() ?? "";
                var name = obj.Name?.Trim() ?? "";
                var fileName = $"{schema}.{name}.{obj.ObjectType}.sql";
                var filePath = Path.Combine(outputDirectory, fileName);
                
                await File.WriteAllTextAsync(filePath, obj.SourceCode ?? string.Empty);
                Logger.Debug("Exported: {File}", fileName);
            }
            catch (Exception ex)
            {
                Logger.Warn(ex, "Failed to export {Schema}.{Name}", obj.Schema?.Trim(), obj.Name?.Trim());
            }
        }
        
        Logger.Info("Source code export completed");
    }
}


