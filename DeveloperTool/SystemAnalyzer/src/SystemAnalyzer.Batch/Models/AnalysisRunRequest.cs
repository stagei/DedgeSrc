using SystemAnalyzer.Core.Models;

namespace SystemAnalyzer.Batch.Models;

public sealed class AnalysisRunRequest
{
    public string Alias { get; set; } = string.Empty;
    public string AllJsonPath { get; set; } = string.Empty;
    public bool SkipClassification { get; set; }
    public bool SkipNaming { get; set; }
    public bool SkipCatalog { get; set; }
    public bool RefreshCatalogs { get; set; }
    public bool GenerateStats { get; set; }
    public List<int> SkipPhases { get; set; } = [];
    public SystemAnalyzerOptions Options { get; set; } = new();
}
