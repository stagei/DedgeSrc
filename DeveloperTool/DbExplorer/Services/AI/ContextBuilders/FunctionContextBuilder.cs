using NLog;
using System.Text;
using System.Threading.Tasks;
using DbExplorer.Data;
using DbExplorer.Services.Interfaces;

namespace DbExplorer.Services.AI.ContextBuilders;

/// <summary>
/// Builds AI-friendly context for a user-defined function.
/// PROVIDER-AGNOSTIC: Uses IMetadataProvider for all queries.
/// </summary>
public class FunctionContextBuilder
{
    private static readonly Logger Logger = LogManager.GetCurrentClassLogger();
    private readonly IConnectionManager _connectionManager;
    private readonly IMetadataProvider _metadataProvider;
    
    public FunctionContextBuilder(IConnectionManager connectionManager, IMetadataProvider metadataProvider)
    {
        _connectionManager = connectionManager;
        _metadataProvider = metadataProvider;
    }
    
    /// <summary>
    /// Build comprehensive context for AI analysis of a function.
    /// </summary>
    public async Task<string> BuildContextAsync(string schema, string functionName)
    {
        Logger.Info("Building AI context for function: {Schema}.{Function}", schema, functionName);
        
        var context = new StringBuilder();
        
        // Header
        context.AppendLine($"# Function: {schema}.{functionName}");
        context.AppendLine();
        
        // Function metadata
        var metadata = await GetFunctionMetadataAsync(schema, functionName);
        if (metadata != null)
        {
            context.AppendLine("## Metadata");
            context.AppendLine();
            context.AppendLine($"- **Return Type**: {metadata.ReturnType}");
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
        var parameters = await GetFunctionParametersAsync(schema, functionName);
        if (parameters.Count > 0)
        {
            context.AppendLine("## Parameters");
            context.AppendLine();
            context.AppendLine("| Name | Type | Mode |");
            context.AppendLine("|------|------|------|");
            
            foreach (var param in parameters)
            {
                context.AppendLine($"| {param.Name} | {param.DataType} | {param.Mode} |");
            }
            
            context.AppendLine();
        }
        
        // Source code
        var source = await GetFunctionSourceAsync(schema, functionName);
        if (!string.IsNullOrWhiteSpace(source))
        {
            context.AppendLine("## Source Code");
            context.AppendLine();
            context.AppendLine("```sql");
            context.AppendLine(source);
            context.AppendLine("```");
            context.AppendLine();
        }
        
        Logger.Info("Context built: {Length} characters", context.Length);
        return context.ToString();
    }
    
    private async Task<FunctionMetadata?> GetFunctionMetadataAsync(string schema, string functionName)
    {
        var dataTable = await _metadataProvider.ExecuteMetadataQueryAsync("GetFunctionMetadata",
            new Dictionary<string, object>
            {
                { "FUNCSCHEMA", schema },
                { "FUNCNAME", functionName }
            });
        
        if (dataTable.Rows.Count > 0)
        {
            var row = dataTable.Rows[0];
            return new FunctionMetadata
            {
                ReturnType = row["RETURN_TYPE"].ToString() ?? string.Empty,
                Language = row["LANGUAGE"].ToString() ?? string.Empty,
                Deterministic = row["DETERMINISTIC"].ToString() == "Y" ? "Yes" : "No",
                SqlAccess = row["SQL_DATA_ACCESS"].ToString() ?? string.Empty,
                Remarks = row["REMARKS"]?.ToString()
            };
        }
        
        return null;
    }
    
    private async Task<List<ParameterInfo>> GetFunctionParametersAsync(string schema, string functionName)
    {
        var parameters = new List<ParameterInfo>();
        
        var dataTable = await _metadataProvider.ExecuteMetadataQueryAsync("GetFunctionParameters",
            new Dictionary<string, object>
            {
                { "FUNCSCHEMA", schema },
                { "FUNCNAME", functionName }
            });
        
        foreach (System.Data.DataRow row in dataTable.Rows)
        {
            parameters.Add(new ParameterInfo
            {
                Name = row["PARMNAME"].ToString() ?? string.Empty,
                DataType = row["TYPENAME"].ToString() ?? string.Empty,
                Mode = row["PARM_MODE"].ToString() ?? string.Empty
            });
        }
        
        return parameters;
    }
    
    private async Task<string> GetFunctionSourceAsync(string schema, string functionName)
    {
        var result = await _metadataProvider.ExecuteScalarAsync("GetFunctionSource",
            new Dictionary<string, object>
            {
                { "FUNCSCHEMA", schema },
                { "FUNCNAME", functionName }
            });
        
        return result?.ToString() ?? string.Empty;
    }
}

public class FunctionMetadata
{
    public string ReturnType { get; set; } = string.Empty;
    public string Language { get; set; } = string.Empty;
    public string Deterministic { get; set; } = string.Empty;
    public string SqlAccess { get; set; } = string.Empty;
    public string? Remarks { get; set; }
}

