using NLog;
using System.Text;
using System.Threading.Tasks;
using DbExplorer.Data;
using DbExplorer.Services.Interfaces;

namespace DbExplorer.Services.AI.ContextBuilders;

/// <summary>
/// Builds AI-friendly context for a database view.
/// PROVIDER-AGNOSTIC: Uses IMetadataProvider for all queries.
/// </summary>
public class ViewContextBuilder
{
    private static readonly Logger Logger = LogManager.GetCurrentClassLogger();
    private readonly IConnectionManager _connectionManager;
    private readonly IMetadataProvider _metadataProvider;
    
    public ViewContextBuilder(IConnectionManager connectionManager, IMetadataProvider metadataProvider)
    {
        _connectionManager = connectionManager;
        _metadataProvider = metadataProvider;
    }
    
    /// <summary>
    /// Build comprehensive context for AI analysis of a view.
    /// </summary>
    public async Task<string> BuildContextAsync(string schema, string viewName)
    {
        Logger.Info("Building AI context for view: {Schema}.{View}", schema, viewName);
        
        var context = new StringBuilder();
        
        // Header
        context.AppendLine($"# View: {schema}.{viewName}");
        context.AppendLine();
        
        // View definition/SQL
        var viewSql = await GetViewDefinitionAsync(schema, viewName);
        if (!string.IsNullOrWhiteSpace(viewSql))
        {
            context.AppendLine("## Definition");
            context.AppendLine();
            context.AppendLine("```sql");
            context.AppendLine(viewSql);
            context.AppendLine("```");
            context.AppendLine();
        }
        
        // Columns
        var columns = await GetViewColumnsAsync(schema, viewName);
        if (columns.Count > 0)
        {
            context.AppendLine("## Columns");
            context.AppendLine();
            context.AppendLine("| Column | Type | Nullable |");
            context.AppendLine("|--------|------|----------|");
            
            foreach (var col in columns)
            {
                context.AppendLine($"| {col.Name} | {col.DataType} | {(col.IsNullable ? "Yes" : "No")} |");
            }
            
            context.AppendLine();
        }
        
        // Dependencies (tables used by the view)
        var dependencies = await GetViewDependenciesAsync(schema, viewName);
        if (dependencies.Count > 0)
        {
            context.AppendLine("## Dependencies");
            context.AppendLine();
            context.AppendLine("This view uses the following tables:");
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
    
    private async Task<string> GetViewDefinitionAsync(string schema, string viewName)
    {
        var result = await _metadataProvider.ExecuteScalarAsync("GetViewDefinition",
            new Dictionary<string, object>
            {
                { "VIEWSCHEMA", schema },
                { "VIEWNAME", viewName }
            });
        
        return result?.ToString() ?? string.Empty;
    }
    
    private async Task<List<ColumnMetadata>> GetViewColumnsAsync(string schema, string viewName)
    {
        var columns = new List<ColumnMetadata>();
        
        var dataTable = await _metadataProvider.ExecuteMetadataQueryAsync("GetViewColumns",
            new Dictionary<string, object>
            {
                { "TABSCHEMA", schema },
                { "TABNAME", viewName }
            });
        
        foreach (System.Data.DataRow row in dataTable.Rows)
        {
            columns.Add(new ColumnMetadata
            {
                Name = row["COLNAME"].ToString() ?? string.Empty,
                DataType = row["TYPENAME"].ToString() ?? string.Empty,
                Length = System.Convert.ToInt32(row["LENGTH"]),
                IsNullable = row["NULLS"].ToString() == "Y"
            });
        }
        
        return columns;
    }
    
    private async Task<List<string>> GetViewDependenciesAsync(string schema, string viewName)
    {
        var dependencies = new List<string>();
        
        var dataTable = await _metadataProvider.ExecuteMetadataQueryAsync("GetViewDependencies",
            new Dictionary<string, object>
            {
                { "VIEWSCHEMA", schema },
                { "VIEWNAME", viewName }
            });
        
        foreach (System.Data.DataRow row in dataTable.Rows)
        {
            dependencies.Add(row["DEPENDENCY"].ToString() ?? string.Empty);
        }
        
        return dependencies;
    }
}

