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
/// Model for package analysis information
/// </summary>
public class PackageAnalysisInfo
{
    public string Schema { get; set; } = string.Empty;
    public string Name { get; set; } = string.Empty;
    public DateTime? LastUsed { get; set; }
    public string? Definer { get; set; }
    public List<string> SqlStatements { get; set; } = new();
    
    public int StatementCount => SqlStatements.Count;
    public bool IsUnused => !LastUsed.HasValue || LastUsed < DateTime.Now.AddYears(-1);
}

/// <summary>
/// Service for analyzing DB2 packages and SQL statements
/// </summary>
public class PackageAnalyzerService
{
    private static readonly Logger Logger = LogManager.GetCurrentClassLogger();
    private readonly MetadataHandler _metadataHandler;
    
    public PackageAnalyzerService()
    {
        _metadataHandler = App.MetadataHandler ?? throw new InvalidOperationException("MetadataHandler not initialized");
    }
    
    /// <summary>
    /// Get all packages in a schema
    /// </summary>
    public async Task<List<PackageAnalysisInfo>> GetPackagesAsync(
        IConnectionManager connectionManager,
        string schema)
    {
        Logger.Info("Getting packages for schema: {Schema}", schema);
        
        try
        {
            var sqlTemplate = _metadataHandler.GetQuery("DB2", "12.1", "GetPackageList");
            var sql = sqlTemplate.Replace("?", $"'{schema}'");
            
            Logger.Debug("Using query: SERVICE_GetPackageList");
            var result = await connectionManager.ExecuteQueryAsync(sql);
            Logger.Info("Found {Count} packages in schema {Schema}", result.Rows.Count, schema);
            
            var packages = new List<PackageAnalysisInfo>();
            
            foreach (DataRow row in result.Rows)
            {
                packages.Add(new PackageAnalysisInfo
                {
                    Schema = row["PKGSCHEMA"]?.ToString() ?? string.Empty,
                    Name = row["PKGNAME"]?.ToString() ?? string.Empty,
                    LastUsed = row["LASTUSED"] == DBNull.Value ? null : Convert.ToDateTime(row["LASTUSED"]),
                    Definer = row["DEFINER"]?.ToString()
                });
            }
            
            return packages;
        }
        catch (Exception ex)
        {
            Logger.Error(ex, "Failed to get packages for schema {Schema}", schema);
            throw;
        }
    }
    
    /// <summary>
    /// Get SQL statements within a package
    /// </summary>
    public async Task<List<string>> GetPackageStatementsAsync(
        IConnectionManager connectionManager,
        string schema,
        string packageName)
    {
        Logger.Info("Getting SQL statements for package: {Schema}.{Package}", schema, packageName);
        
        try
        {
            var sqlTemplate = _metadataHandler.GetQuery("DB2", "12.1", "GetPackageStatements");
            var sql = sqlTemplate.Replace("?", $"'{schema}'").Replace("?", $"'{packageName}'");
            
            Logger.Debug("Using query: SERVICE_GetPackageStatements");
            var result = await connectionManager.ExecuteQueryAsync(sql);
            Logger.Info("Found {Count} statements in package {Schema}.{Package}", 
                result.Rows.Count, schema, packageName);
            
            var statements = new List<string>();
            foreach (DataRow row in result.Rows)
            {
                var text = row["TEXT"]?.ToString();
                if (!string.IsNullOrWhiteSpace(text))
                {
                    statements.Add(text);
                }
            }
            
            return statements;
        }
        catch (Exception ex)
        {
            Logger.Error(ex, "Failed to get statements for package {Schema}.{Package}", schema, packageName);
            throw;
        }
    }
}


