using NLog;
using System.Text;
using System.Threading.Tasks;
using DbExplorer.Data;

namespace DbExplorer.Services.AI.ContextBuilders;

/// <summary>
/// Builds AI-friendly context for Mermaid ERD diagrams.
/// Explains relationships and table purposes.
/// </summary>
public class MermaidContextBuilder
{
    private static readonly Logger Logger = LogManager.GetCurrentClassLogger();
    private readonly DeepAnalysisService _deepAnalysisService;
    
    public MermaidContextBuilder(DeepAnalysisService deepAnalysisService)
    {
        _deepAnalysisService = deepAnalysisService;
    }
    
    /// <summary>
    /// Build context explaining relationships in a Mermaid diagram.
    /// </summary>
    public async Task<string> BuildRelationshipContextAsync(List<(string schema, string table)> tables, string mermaidDiagram)
    {
        Logger.Info("Building AI context for Mermaid diagram with {Count} tables", tables.Count);
        
        var context = new StringBuilder();
        
        // Header
        context.AppendLine("# Entity Relationship Diagram Analysis");
        context.AppendLine();
        
        // Mermaid diagram
        context.AppendLine("## Diagram");
        context.AppendLine();
        context.AppendLine("```mermaid");
        context.AppendLine(mermaidDiagram);
        context.AppendLine("```");
        context.AppendLine();
        
        // Table summaries
        context.AppendLine("## Tables");
        context.AppendLine();
        
        foreach (var (schema, table) in tables)
        {
            var analysis = await _deepAnalysisService.AnalyzeTableAsync(schema, table, sampleSize: 20);
            
            context.AppendLine($"### {schema}.{table}");
            context.AppendLine();
            
            if (!string.IsNullOrWhiteSpace(analysis.TableComment))
            {
                context.AppendLine($"**Purpose**: {analysis.TableComment}");
                context.AppendLine();
            }
            
            context.AppendLine($"**Columns**: {analysis.Columns.Count}");
            
            if (analysis.ColumnProfiles.Count > 0)
            {
                var totalRows = analysis.ColumnProfiles.Values.FirstOrDefault()?.TotalCount ?? 0;
                context.AppendLine($"**Row Count**: {totalRows:N0}");
            }
            
            if (analysis.Relationships.Count > 0)
            {
                context.AppendLine($"**Relationships**: {analysis.Relationships.Count}");
            }
            
            context.AppendLine();
        }
        
        // Relationships explanation
        var allRelationships = new List<TableRelationship>();
        foreach (var (schema, table) in tables)
        {
            var analysis = await _deepAnalysisService.AnalyzeTableAsync(schema, table, sampleSize: 0);
            allRelationships.AddRange(analysis.Relationships);
        }
        
        // Deduplicate relationships
        var uniqueRelationships = allRelationships
            .GroupBy(r => r.ConstraintName)
            .Select(g => g.First())
            .ToList();
        
        if (uniqueRelationships.Count > 0)
        {
            context.AppendLine("## Relationships Explained");
            context.AppendLine();
            
            foreach (var rel in uniqueRelationships)
            {
                var from = $"{rel.FromSchema}.{rel.FromTable}";
                var to = $"{rel.ToSchema}.{rel.ToTable}";
                var columns = string.Join(", ", rel.Columns);
                
                context.AppendLine($"- **{from}** → **{to}** (via `{columns}`)");
                context.AppendLine($"  - Foreign Key: `{rel.ConstraintName}`");
                context.AppendLine($"  - This relationship indicates that {rel.FromTable} references {rel.ToTable}");
                context.AppendLine();
            }
        }
        
        context.AppendLine("## AI Prompt");
        context.AppendLine();
        context.AppendLine("Please analyze this ERD and explain:");
        context.AppendLine("1. What is the overall purpose of this group of tables?");
        context.AppendLine("2. How do these tables relate to each other?");
        context.AppendLine("3. What business domain or process do they represent?");
        context.AppendLine("4. Are there any unusual or noteworthy patterns?");
        context.AppendLine();
        
        Logger.Info("Context built: {Length} characters", context.Length);
        return context.ToString();
    }
    
    /// <summary>
    /// Build context for explaining a single relationship.
    /// </summary>
    public async Task<string> BuildSingleRelationshipContextAsync(string fromSchema, string fromTable, string toSchema, string toTable)
    {
        Logger.Info("Building AI context for relationship: {FromSchema}.{FromTable} → {ToSchema}.{ToTable}", 
            fromSchema, fromTable, toSchema, toTable);
        
        var context = new StringBuilder();
        
        // Header
        context.AppendLine($"# Relationship: {fromSchema}.{fromTable} → {toSchema}.{toTable}");
        context.AppendLine();
        
        // Get both table analyses
        var fromAnalysis = await _deepAnalysisService.AnalyzeTableAsync(fromSchema, fromTable, sampleSize: 10);
        var toAnalysis = await _deepAnalysisService.AnalyzeTableAsync(toSchema, toTable, sampleSize: 10);
        
        // From table
        context.AppendLine($"## Source Table: {fromSchema}.{fromTable}");
        context.AppendLine();
        if (!string.IsNullOrWhiteSpace(fromAnalysis.TableComment))
        {
            context.AppendLine($"**Purpose**: {fromAnalysis.TableComment}");
        }
        context.AppendLine($"**Columns**: {fromAnalysis.Columns.Count}");
        context.AppendLine();
        
        // To table
        context.AppendLine($"## Target Table: {toSchema}.{toTable}");
        context.AppendLine();
        if (!string.IsNullOrWhiteSpace(toAnalysis.TableComment))
        {
            context.AppendLine($"**Purpose**: {toAnalysis.TableComment}");
        }
        context.AppendLine($"**Columns**: {toAnalysis.Columns.Count}");
        context.AppendLine();
        
        // Find the specific foreign key
        var relationship = fromAnalysis.Relationships
            .FirstOrDefault(r => r.ToTable == toTable && r.ToSchema == toSchema);
        
        if (relationship != null)
        {
            context.AppendLine("## Foreign Key Details");
            context.AppendLine();
            context.AppendLine($"- **Constraint**: {relationship.ConstraintName}");
            context.AppendLine($"- **Columns**: {string.Join(", ", relationship.Columns)}");
            context.AppendLine();
        }
        
        context.AppendLine("## AI Prompt");
        context.AppendLine();
        context.AppendLine("Please explain:");
        context.AppendLine($"1. Why does {fromTable} reference {toTable}?");
        context.AppendLine("2. What business rule does this relationship enforce?");
        context.AppendLine("3. What happens when a record in the referenced table is deleted?");
        context.AppendLine();
        
        Logger.Info("Context built: {Length} characters", context.Length);
        return context.ToString();
    }
}

