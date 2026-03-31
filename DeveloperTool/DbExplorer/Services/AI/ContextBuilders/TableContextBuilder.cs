using NLog;
using System.Text;
using System.Threading.Tasks;
using DbExplorer.Data;

namespace DbExplorer.Services.AI.ContextBuilders;

/// <summary>
/// Builds AI-friendly context for a table, including structure, relationships, and data insights.
/// PROVIDER-AGNOSTIC: Uses DeepAnalysisService (which uses IMetadataProvider).
/// </summary>
public class TableContextBuilder
{
    private static readonly Logger Logger = LogManager.GetCurrentClassLogger();
    private readonly DeepAnalysisService _deepAnalysisService;
    
    public TableContextBuilder(DeepAnalysisService deepAnalysisService)
    {
        _deepAnalysisService = deepAnalysisService;
    }
    
    /// <summary>
    /// Build comprehensive context for AI analysis.
    /// </summary>
    public async Task<string> BuildContextAsync(string schema, string tableName, bool includeDataSamples = true)
    {
        Logger.Info("Building AI context for table: {Schema}.{Table}", schema, tableName);
        
        var analysis = await _deepAnalysisService.AnalyzeTableAsync(schema, tableName, includeDataSamples ? 50 : 0);
        
        var context = new StringBuilder();
        
        // Header
        context.AppendLine($"# Table: {schema}.{tableName}");
        context.AppendLine();
        
        // Table comment/description
        if (!string.IsNullOrWhiteSpace(analysis.TableComment))
        {
            context.AppendLine("## Description");
            context.AppendLine(analysis.TableComment);
            context.AppendLine();
        }
        
        // Column definitions
        context.AppendLine("## Columns");
        context.AppendLine();
        context.AppendLine("| Column | Type | Nullable | Description |");
        context.AppendLine("|--------|------|----------|-------------|");
        
        foreach (var col in analysis.Columns)
        {
            var comment = analysis.ColumnComments.TryGetValue(col.Name, out var c) ? c : "-";
            var nullable = col.IsNullable ? "Yes" : "No";
            var dataType = $"{col.DataType}({col.Length})";
            
            context.AppendLine($"| {col.Name} | {dataType} | {nullable} | {comment} |");
        }
        
        context.AppendLine();
        
        // Column statistics
        if (analysis.ColumnProfiles.Count > 0)
        {
            context.AppendLine("## Data Profile");
            context.AppendLine();
            context.AppendLine("| Column | Total Rows | Distinct Values | Null % | Uniqueness % |");
            context.AppendLine("|--------|------------|-----------------|--------|--------------|");
            
            foreach (var profile in analysis.ColumnProfiles.Values)
            {
                context.AppendLine($"| {profile.ColumnName} | {profile.TotalCount:N0} | {profile.DistinctCount:N0} | {profile.NullPercentage:F1}% | {profile.UniquenessPercentage:F1}% |");
            }
            
            context.AppendLine();
        }
        
        // Relationships
        if (analysis.Relationships.Count > 0)
        {
            context.AppendLine("## Relationships");
            context.AppendLine();
            
            foreach (var rel in analysis.Relationships)
            {
                var direction = rel.FromTable == tableName ? "→" : "←";
                var otherTable = rel.FromTable == tableName ? $"{rel.ToSchema}.{rel.ToTable}" : $"{rel.FromSchema}.{rel.FromTable}";
                var columns = string.Join(", ", rel.Columns);
                
                context.AppendLine($"- {direction} **{otherTable}** via `{columns}` ({rel.ConstraintName})");
            }
            
            context.AppendLine();
        }
        
        // Sample data
        if (includeDataSamples && analysis.DataSample.Rows.Count > 0)
        {
            context.AppendLine("## Sample Data (First 5 Rows)");
            context.AppendLine();
            context.AppendLine("```");
            
            // Table header
            var colNames = analysis.DataSample.Columns.Cast<System.Data.DataColumn>().Select(c => c.ColumnName).ToArray();
            context.AppendLine(string.Join(" | ", colNames));
            context.AppendLine(new string('-', colNames.Sum(n => n.Length + 3)));
            
            // Data rows (limit to 5)
            var rowCount = System.Math.Min(5, analysis.DataSample.Rows.Count);
            for (int i = 0; i < rowCount; i++)
            {
                var row = analysis.DataSample.Rows[i];
                var values = row.ItemArray.Select(v => v?.ToString() ?? "NULL");
                context.AppendLine(string.Join(" | ", values));
            }
            
            context.AppendLine("```");
            context.AppendLine();
        }
        
        Logger.Info("Context built: {Length} characters", context.Length);
        return context.ToString();
    }
    
    /// <summary>
    /// Build compact context (no data samples).
    /// </summary>
    public async Task<string> BuildCompactContextAsync(string schema, string tableName)
    {
        return await BuildContextAsync(schema, tableName, includeDataSamples: false);
    }
}

