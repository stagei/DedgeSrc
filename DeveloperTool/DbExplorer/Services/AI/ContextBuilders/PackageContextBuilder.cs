using NLog;
using System.Text;
using System.Threading.Tasks;
using DbExplorer.Data;
using DbExplorer.Services;
using DbExplorer.Services.Interfaces;

namespace DbExplorer.Services.AI.ContextBuilders;

/// <summary>
/// Builds AI-friendly context for a DB2 package.
/// PROVIDER-AGNOSTIC: Uses IMetadataProvider for all queries.
/// </summary>
public class PackageContextBuilder
{
    private static readonly Logger Logger = LogManager.GetCurrentClassLogger();
    private readonly IConnectionManager _connectionManager;
    private readonly IMetadataProvider _metadataProvider;
    private readonly PackageDependencyAnalyzer _dependencyAnalyzer;
    
    public PackageContextBuilder(IConnectionManager connectionManager, IMetadataProvider metadataProvider, PackageDependencyAnalyzer dependencyAnalyzer)
    {
        _connectionManager = connectionManager;
        _metadataProvider = metadataProvider;
        _dependencyAnalyzer = dependencyAnalyzer;
    }
    
    /// <summary>
    /// Build comprehensive context for AI analysis of a package.
    /// </summary>
    public async Task<string> BuildContextAsync(string schema, string packageName)
    {
        Logger.Info("Building AI context for package: {Schema}.{Package}", schema, packageName);
        
        var context = new StringBuilder();
        
        // Header
        context.AppendLine($"# Package: {schema}.{packageName}");
        context.AppendLine();
        
        // Package metadata
        var metadata = await GetPackageMetadataAsync(schema, packageName);
        if (metadata != null)
        {
            context.AppendLine("## Metadata");
            context.AppendLine();
            context.AppendLine($"- **Type**: {metadata.PackageType}");
            context.AppendLine($"- **Isolation Level**: {metadata.IsolationLevel}");
            context.AppendLine($"- **Created**: {metadata.CreateTime}");
            context.AppendLine($"- **Last Used**: {metadata.LastUsed}");
            context.AppendLine();
        }
        
        // SQL Statements
        var statements = await GetPackageStatementsAsync(schema, packageName);
        if (statements.Count > 0)
        {
            context.AppendLine("## SQL Statements");
            context.AppendLine();
            context.AppendLine($"This package contains **{statements.Count}** SQL statement(s):");
            context.AppendLine();
            
            for (int i = 0; i < Math.Min(10, statements.Count); i++)
            {
                context.AppendLine($"### Statement {i + 1}");
                context.AppendLine();
                context.AppendLine("```sql");
                context.AppendLine(statements[i]);
                context.AppendLine("```");
                context.AppendLine();
            }
            
            if (statements.Count > 10)
            {
                context.AppendLine($"_(showing first 10 of {statements.Count} statements)_");
                context.AppendLine();
            }
        }
        
        // Dependencies (tables, views, procedures used)
        var dependencies = await GetPackageDependenciesAsync(schema, packageName, statements);
        if (dependencies.Count > 0)
        {
            context.AppendLine("## Dependencies");
            context.AppendLine();
            context.AppendLine("This package uses:");
            context.AppendLine();
            
            foreach (var dep in dependencies)
            {
                context.AppendLine($"- {dep}");
            }
            
            context.AppendLine();
        }
        
        Logger.Info("Context built: {Length} characters", context.Length);
        return context.ToString();
    }
    
    private async Task<PackageMetadata?> GetPackageMetadataAsync(string schema, string packageName)
    {
        var dataTable = await _metadataProvider.ExecuteMetadataQueryAsync("GetPackageMetadata",
            new Dictionary<string, object>
            {
                { "PKGSCHEMA", schema },
                { "PKGNAME", packageName }
            });
        
        if (dataTable.Rows.Count > 0)
        {
            var row = dataTable.Rows[0];
            return new PackageMetadata
            {
                PackageType = row["PKGTYPE"].ToString() ?? string.Empty,
                IsolationLevel = row["ISOLATION"].ToString() ?? string.Empty,
                CreateTime = row["CREATE_TIME"].ToString() ?? string.Empty,
                LastUsed = row["LAST_BIND_TIME"].ToString() ?? string.Empty
            };
        }
        
        return null;
    }
    
    private async Task<List<string>> GetPackageStatementsAsync(string schema, string packageName)
    {
        var sql = $@"
SELECT STMTTEXT
FROM SYSCAT.STATEMENTS
WHERE PKGSCHEMA = '{schema}' AND PKGNAME = '{packageName}'
ORDER BY STMTNO";
        
        var statements = new List<string>();
        
        try
        {
            var dataTable = await _connectionManager.ExecuteQueryAsync(sql);
            
            foreach (System.Data.DataRow row in dataTable.Rows)
            {
                var text = row["STMTTEXT"].ToString() ?? string.Empty;
                if (!string.IsNullOrWhiteSpace(text))
                {
                    statements.Add(text.Trim());
                }
            }
        }
        catch (Exception ex)
        {
            Logger.Warn(ex, "Failed to fetch package statements");
        }
        
        return statements;
    }
    
    private async Task<List<string>> GetPackageDependenciesAsync(string schema, string packageName, List<string> statements)
    {
        var dependencySet = new HashSet<string>();
        
        try
        {
            // Use the public API to analyze package dependencies (DB2-specific)
            // Provider-agnostic - uses IConnectionManager
            var deps = await _dependencyAnalyzer.AnalyzeDependenciesAsync(_connectionManager, schema, packageName);
            
            foreach (var table in deps.TablesUsed)
            {
                dependencySet.Add($"Table: {table}");
            }
            
            foreach (var view in deps.ViewsUsed)
            {
                dependencySet.Add($"View: {view}");
            }
            
            foreach (var proc in deps.ProceduresCalled)
            {
                dependencySet.Add($"Procedure: {proc}");
            }
            
            foreach (var func in deps.FunctionsCalled)
            {
                dependencySet.Add($"Function: {func}");
            }
        }
        catch (Exception ex)
        {
            Logger.Warn(ex, "Failed to analyze package dependencies");
        }
        
        return dependencySet.OrderBy(d => d).ToList();
    }
}

public class PackageMetadata
{
    public string PackageType { get; set; } = string.Empty;
    public string IsolationLevel { get; set; } = string.Empty;
    public string CreateTime { get; set; } = string.Empty;
    public string LastUsed { get; set; } = string.Empty;
}

