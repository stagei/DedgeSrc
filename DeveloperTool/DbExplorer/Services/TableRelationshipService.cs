using System;
using System.Collections.Generic;
using System.Data;
using System.Linq;
using System.Threading.Tasks;
using NLog;
using DbExplorer.Data;

namespace DbExplorer.Services;

/// <summary>
/// Model for incoming foreign key reference
/// </summary>
public class IncomingForeignKey
{
    public string ReferencingSchema { get; set; } = string.Empty;
    public string ReferencingTable { get; set; } = string.Empty;
    public string ConstraintName { get; set; } = string.Empty;
    public string FkColumns { get; set; } = string.Empty;
    public string PkColumns { get; set; } = string.Empty;
    public string DeleteRule { get; set; } = string.Empty;
    public string UpdateRule { get; set; } = string.Empty;
}

/// <summary>
/// Model for referencing object (package, view, procedure, function)
/// </summary>
public class ReferencingObject
{
    public string ObjectType { get; set; } = string.Empty; // PACKAGE, VIEW, PROCEDURE, FUNCTION
    public string Schema { get; set; } = string.Empty;
    public string Name { get; set; } = string.Empty;
    public DateTime? LastUsed { get; set; }
}

/// <summary>
/// Service for analyzing table relationships and dependencies
/// </summary>
public class TableRelationshipService
{
    private static readonly Logger Logger = LogManager.GetCurrentClassLogger();
    private readonly MetadataHandler _metadataHandler;
    
    public TableRelationshipService()
    {
        _metadataHandler = App.MetadataHandler ?? throw new InvalidOperationException("MetadataHandler not initialized");
    }
    
    /// <summary>
    /// Get tables that have foreign keys pointing to this table
    /// </summary>
    public async Task<List<IncomingForeignKey>> GetIncomingForeignKeysAsync(
        IConnectionManager connectionManager,
        string schema,
        string tableName)
    {
        Logger.Info("Getting incoming foreign keys for {Schema}.{Table}", schema, tableName);
        
        try
        {
            var sqlTemplate = _metadataHandler.GetQuery("DB2", "12.1", "GetIncomingForeignKeys");
            var sql = sqlTemplate.Replace("?", $"'{schema}'").Replace("?", $"'{tableName}'");
            
            Logger.Debug("Using query: SERVICE_GetIncomingForeignKeys");
            var result = await connectionManager.ExecuteQueryAsync(sql);
            
            var foreignKeys = new List<IncomingForeignKey>();
            
            foreach (DataRow row in result.Rows)
            {
                foreignKeys.Add(new IncomingForeignKey
                {
                    ReferencingSchema = row["REFERENCING_SCHEMA"]?.ToString() ?? string.Empty,
                    ReferencingTable = row["REFERENCING_TABLE"]?.ToString() ?? string.Empty,
                    ConstraintName = row["CONSTNAME"]?.ToString() ?? string.Empty,
                    FkColumns = row["FK_COLNAMES"]?.ToString() ?? string.Empty,
                    PkColumns = row["PK_COLNAMES"]?.ToString() ?? string.Empty,
                    DeleteRule = row["DELETERULE"]?.ToString() ?? string.Empty,
                    UpdateRule = row["UPDATERULE"]?.ToString() ?? string.Empty
                });
            }
            
            Logger.Info("Found {Count} incoming foreign keys for {Schema}.{Table}", 
                foreignKeys.Count, schema, tableName);
            
            return foreignKeys;
        }
        catch (Exception ex)
        {
            Logger.Error(ex, "Failed to get incoming foreign keys for {Schema}.{Table}", schema, tableName);
            throw;
        }
    }
    
    /// <summary>
    /// Get packages that reference this table
    /// </summary>
    public async Task<List<ReferencingObject>> GetReferencingPackagesAsync(
        IConnectionManager connectionManager,
        string schema,
        string tableName)
    {
        Logger.Info("Getting packages that reference {Schema}.{Table}", schema, tableName);
        
        try
        {
            var sqlTemplate = _metadataHandler.GetQuery("DB2", "12.1", "GetReferencingPackages");
            var sql = sqlTemplate.Replace("?", $"'{schema}'").Replace("?", $"'{tableName}'");
            
            Logger.Debug("Using query: SERVICE_GetReferencingPackages");
            var result = await connectionManager.ExecuteQueryAsync(sql);
            
            var packages = ConvertToReferencingObjects(result);
            
            Logger.Info("Found {Count} packages referencing {Schema}.{Table}", 
                packages.Count, schema, tableName);
            
            return packages;
        }
        catch (Exception ex)
        {
            Logger.Error(ex, "Failed to get referencing packages for {Schema}.{Table}", schema, tableName);
            return new List<ReferencingObject>(); // Return empty list on error
        }
    }
    
    /// <summary>
    /// Get views that reference this table
    /// </summary>
    public async Task<List<ReferencingObject>> GetReferencingViewsAsync(
        IConnectionManager connectionManager,
        string schema,
        string tableName)
    {
        Logger.Info("Getting views that reference {Schema}.{Table}", schema, tableName);
        
        try
        {
            var sqlTemplate = _metadataHandler.GetQuery("DB2", "12.1", "GetReferencingViews");
            var sql = sqlTemplate.Replace("?", $"'{schema}'").Replace("?", $"'{tableName}'");
            
            Logger.Debug("Using query: SERVICE_GetReferencingViews");
            var result = await connectionManager.ExecuteQueryAsync(sql);
            
            var views = ConvertToReferencingObjects(result);
            
            Logger.Info("Found {Count} views referencing {Schema}.{Table}", 
                views.Count, schema, tableName);
            
            return views;
        }
        catch (Exception ex)
        {
            Logger.Error(ex, "Failed to get referencing views for {Schema}.{Table}", schema, tableName);
            return new List<ReferencingObject>();
        }
    }
    
    /// <summary>
    /// Get procedures and functions that reference this table
    /// </summary>
    public async Task<List<ReferencingObject>> GetReferencingRoutinesAsync(
        IConnectionManager connectionManager,
        string schema,
        string tableName)
    {
        Logger.Info("Getting procedures/functions that reference {Schema}.{Table}", schema, tableName);
        
        try
        {
            var sqlTemplate = _metadataHandler.GetQuery("DB2", "12.1", "GetReferencingRoutines");
            var sql = sqlTemplate.Replace("?", $"'{schema}'").Replace("?", $"'{tableName}'");
            
            Logger.Debug("Using query: SERVICE_GetReferencingRoutines");
            var result = await connectionManager.ExecuteQueryAsync(sql);
            
            var routines = ConvertToReferencingObjects(result);
            
            Logger.Info("Found {Count} procedures/functions referencing {Schema}.{Table}", 
                routines.Count, schema, tableName);
            
            return routines;
        }
        catch (Exception ex)
        {
            Logger.Error(ex, "Failed to get referencing routines for {Schema}.{Table}", schema, tableName);
            return new List<ReferencingObject>();
        }
    }
    
    /// <summary>
    /// Convert DataTable to list of ReferencingObject
    /// </summary>
    private List<ReferencingObject> ConvertToReferencingObjects(DataTable dataTable)
    {
        var objects = new List<ReferencingObject>();
        
        foreach (DataRow row in dataTable.Rows)
        {
            try
            {
                objects.Add(new ReferencingObject
                {
                    ObjectType = row["OBJECT_TYPE"]?.ToString() ?? string.Empty,
                    Schema = row["SCHEMA"]?.ToString() ?? string.Empty,
                    Name = row["NAME"]?.ToString() ?? string.Empty,
                    LastUsed = row["LASTUSED"] == DBNull.Value ? null : Convert.ToDateTime(row["LASTUSED"])
                });
            }
            catch (Exception ex)
            {
                Logger.Warn(ex, "Failed to convert row to ReferencingObject");
            }
        }
        
        return objects;
    }
}



