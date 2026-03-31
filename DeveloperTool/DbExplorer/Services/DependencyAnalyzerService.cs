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
/// Model for dependency information
/// </summary>
public class DependencyNode
{
    public string Schema { get; set; } = string.Empty;
    public string Name { get; set; } = string.Empty;
    public string Type { get; set; } = string.Empty;
    public string DependsOnSchema { get; set; } = string.Empty;
    public string DependsOnName { get; set; } = string.Empty;
    public string DependsOnType { get; set; } = string.Empty;
    public string Direction { get; set; } = string.Empty; // INCOMING, OUTGOING
}

/// <summary>
/// Service for analyzing table and object dependencies
/// </summary>
public class DependencyAnalyzerService
{
    private static readonly Logger Logger = LogManager.GetCurrentClassLogger();
    
    /// <summary>
    /// Get dependencies for a table (both incoming and outgoing)
    /// </summary>
    public async Task<List<DependencyNode>> GetTableDependenciesAsync(
        IConnectionManager connectionManager,
        string schema,
        string tableName)
    {
        Logger.Info("Getting dependencies for table: {Schema}.{Table}", schema, tableName);
        
        try
        {
            var sql = $@"
                -- Outgoing dependencies (what this table depends on)
                SELECT 
                    TABSCHEMA AS SCHEMA,
                    TABNAME AS NAME,
                    DTYPE AS TYPE,
                    BSCHEMA AS DEPENDS_ON_SCHEMA,
                    BNAME AS DEPENDS_ON_NAME,
                    BTYPE AS DEPENDS_ON_TYPE,
                    'OUTGOING' AS DIRECTION
                FROM SYSCAT.TABDEP
                WHERE TABSCHEMA = '{schema}' AND TABNAME = '{tableName}'
                
                UNION
                
                -- Incoming dependencies (what depends on this table)
                SELECT 
                    BSCHEMA AS SCHEMA,
                    BNAME AS NAME,
                    BTYPE AS TYPE,
                    TABSCHEMA AS DEPENDS_ON_SCHEMA,
                    TABNAME AS DEPENDS_ON_NAME,
                    DTYPE AS DEPENDS_ON_TYPE,
                    'INCOMING' AS DIRECTION
                FROM SYSCAT.TABDEP
                WHERE BSCHEMA = '{schema}' AND BNAME = '{tableName}'
                
                ORDER BY DIRECTION, DEPENDS_ON_SCHEMA, DEPENDS_ON_NAME
            ";
            
            var result = await connectionManager.ExecuteQueryAsync(sql);
            Logger.Info("Found {Count} dependencies for {Schema}.{Table}", result.Rows.Count, schema, tableName);
            
            return ConvertToDependencyNodes(result);
        }
        catch (Exception ex)
        {
            Logger.Error(ex, "Failed to get dependencies for {Schema}.{Table}", schema, tableName);
            throw;
        }
    }
    
    /// <summary>
    /// Convert DataTable to list of DependencyNode
    /// </summary>
    private List<DependencyNode> ConvertToDependencyNodes(DataTable dataTable)
    {
        var nodes = new List<DependencyNode>();
        
        foreach (DataRow row in dataTable.Rows)
        {
            try
            {
                nodes.Add(new DependencyNode
                {
                    Schema = row["SCHEMA"]?.ToString() ?? string.Empty,
                    Name = row["NAME"]?.ToString() ?? string.Empty,
                    Type = row["TYPE"]?.ToString() ?? string.Empty,
                    DependsOnSchema = row["DEPENDS_ON_SCHEMA"]?.ToString() ?? string.Empty,
                    DependsOnName = row["DEPENDS_ON_NAME"]?.ToString() ?? string.Empty,
                    DependsOnType = row["DEPENDS_ON_TYPE"]?.ToString() ?? string.Empty,
                    Direction = row["DIRECTION"]?.ToString() ?? string.Empty
                });
            }
            catch (Exception ex)
            {
                Logger.Warn(ex, "Failed to convert row to DependencyNode");
            }
        }
        
        return nodes;
    }
    
    /// <summary>
    /// Generate DROP script in dependency order
    /// </summary>
    public string GenerateDependencyOrderedDropScript(List<DependencyNode> dependencies)
    {
        Logger.Info("Generating dependency-ordered DROP script");
        
        var script = new StringBuilder();
        script.AppendLine("-- Dependency-Ordered DROP Script");
        script.AppendLine($"-- Generated: {DateTime.Now}");
        script.AppendLine("-- WARNING: Review carefully before executing!");
        script.AppendLine();
        
        // Group by object and sort by dependency level
        var grouped = dependencies
            .GroupBy(d => $"{d.Schema}.{d.Name}")
            .OrderByDescending(g => g.Count(d => d.Direction == "INCOMING"));
        
        foreach (var group in grouped)
        {
            var first = group.First();
            script.AppendLine($"-- Object: {first.Schema}.{first.Name} (Type: {first.Type})");
            script.AppendLine($"-- Dependencies: {group.Count()}");
            script.AppendLine($"DROP {first.Type} {first.Schema}.{first.Name};");
            script.AppendLine();
        }
        
        return script.ToString();
    }
}

