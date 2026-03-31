using NLog;
using System.Text;
using System.Threading.Tasks;
using DbExplorer.Data;
using DbExplorer.Services.Interfaces;

namespace DbExplorer.Services.AI.ContextBuilders;

/// <summary>
/// Builds AI-friendly context for a stored procedure.
/// PROVIDER-AGNOSTIC: Uses IMetadataProvider for all queries.
/// </summary>
public class ProcedureContextBuilder
{
    private static readonly Logger Logger = LogManager.GetCurrentClassLogger();
    private readonly IConnectionManager _connectionManager;
    private readonly IMetadataProvider _metadataProvider;
    
    public ProcedureContextBuilder(IConnectionManager connectionManager, IMetadataProvider metadataProvider)
    {
        _connectionManager = connectionManager;
        _metadataProvider = metadataProvider;
    }
    
    /// <summary>
    /// Build comprehensive context for AI analysis of a procedure.
    /// </summary>
    public async Task<string> BuildContextAsync(string schema, string procedureName)
    {
        Logger.Info("Building AI context for procedure: {Schema}.{Procedure}", schema, procedureName);
        
        var context = new StringBuilder();
        
        // Header
        context.AppendLine($"# Procedure: {schema}.{procedureName}");
        context.AppendLine();
        
        // Procedure metadata
        var metadata = await GetProcedureMetadataAsync(schema, procedureName);
        if (metadata != null)
        {
            context.AppendLine("## Metadata");
            context.AppendLine();
            context.AppendLine($"- **Language**: {metadata.Language}");
            context.AppendLine($"- **Deterministic**: {metadata.Deterministic}");
            context.AppendLine($"- **SQL Access**: {metadata.SqlAccess}");
            if (!string.IsNullOrWhiteSpace(metadata.Remarks))
            {
                context.AppendLine($"- **Description**: {metadata.Remarks}");
            }
            context.AppendLine();
        }
        
        // Parameters
        var parameters = await GetProcedureParametersAsync(schema, procedureName);
        if (parameters.Count > 0)
        {
            context.AppendLine("## Parameters");
            context.AppendLine();
            context.AppendLine("| Name | Type | Mode | Description |");
            context.AppendLine("|------|------|------|-------------|");
            
            foreach (var param in parameters)
            {
                context.AppendLine($"| {param.Name} | {param.DataType} | {param.Mode} | {param.Remarks ?? "-"} |");
            }
            
            context.AppendLine();
        }
        
        // Source code
        var source = await GetProcedureSourceAsync(schema, procedureName);
        if (!string.IsNullOrWhiteSpace(source))
        {
            context.AppendLine("## Source Code");
            context.AppendLine();
            context.AppendLine("```sql");
            context.AppendLine(source);
            context.AppendLine("```");
            context.AppendLine();
        }
        
        // Dependencies
        var dependencies = await GetProcedureDependenciesAsync(schema, procedureName);
        if (dependencies.Count > 0)
        {
            context.AppendLine("## Dependencies");
            context.AppendLine();
            context.AppendLine("This procedure uses:");
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
    
    private async Task<ProcedureMetadata?> GetProcedureMetadataAsync(string schema, string procedureName)
    {
        var dataTable = await _metadataProvider.ExecuteMetadataQueryAsync("GetProcedureMetadata",
            new Dictionary<string, object>
            {
                { "PROCSCHEMA", schema },
                { "PROCNAME", procedureName }
            });
        
        if (dataTable.Rows.Count > 0)
        {
            var row = dataTable.Rows[0];
            return new ProcedureMetadata
            {
                Language = row["LANGUAGE"].ToString() ?? string.Empty,
                Deterministic = row["DETERMINISTIC"].ToString() == "Y" ? "Yes" : "No",
                SqlAccess = row["SQL_DATA_ACCESS"].ToString() ?? string.Empty,
                Remarks = row["REMARKS"]?.ToString()
            };
        }
        
        return null;
    }
    
    private async Task<List<ParameterInfo>> GetProcedureParametersAsync(string schema, string procedureName)
    {
        var parameters = new List<ParameterInfo>();
        
        var dataTable = await _metadataProvider.ExecuteMetadataQueryAsync("GetProcedureParameters",
            new Dictionary<string, object>
            {
                { "PROCSCHEMA", schema },
                { "PROCNAME", procedureName }
            });
        
        foreach (System.Data.DataRow row in dataTable.Rows)
        {
            parameters.Add(new ParameterInfo
            {
                Name = row["PARMNAME"].ToString() ?? string.Empty,
                DataType = row["TYPENAME"].ToString() ?? string.Empty,
                Mode = row["PARM_MODE"].ToString() ?? string.Empty,
                Remarks = row["REMARKS"]?.ToString()
            });
        }
        
        return parameters;
    }
    
    private async Task<string> GetProcedureSourceAsync(string schema, string procedureName)
    {
        var result = await _metadataProvider.ExecuteScalarAsync("GetProcedureSource",
            new Dictionary<string, object>
            {
                { "PROCSCHEMA", schema },
                { "PROCNAME", procedureName }
            });
        
        return result?.ToString() ?? string.Empty;
    }
    
    private async Task<List<string>> GetProcedureDependenciesAsync(string schema, string procedureName)
    {
        var dependencies = new List<string>();
        
        try
        {
            var dataTable = await _metadataProvider.ExecuteMetadataQueryAsync("GetProcedureDependencies",
                new Dictionary<string, object>
                {
                    { "ROUTINESCHEMA", schema },
                    { "ROUTINENAME", procedureName }
                });
            
            foreach (System.Data.DataRow row in dataTable.Rows)
            {
                dependencies.Add(row["DEPENDENCY"].ToString() ?? string.Empty);
            }
        }
        catch (Exception ex)
        {
            Logger.Warn(ex, "Failed to fetch procedure dependencies");
        }
        
        return dependencies;
    }
}

public class ProcedureMetadata
{
    public string Language { get; set; } = string.Empty;
    public string Deterministic { get; set; } = string.Empty;
    public string SqlAccess { get; set; } = string.Empty;
    public string? Remarks { get; set; }
}

public class ParameterInfo
{
    public string Name { get; set; } = string.Empty;
    public string DataType { get; set; } = string.Empty;
    public string Mode { get; set; } = string.Empty; // IN, OUT, INOUT
    public string? Remarks { get; set; }
}

