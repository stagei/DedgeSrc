using SystemAnalyzer2.Core.Models;

namespace SystemAnalyzer2.Batch.Models;

public sealed class AnalysisRunRequest
{
    public string Alias { get; set; } = string.Empty;
    public string AllJsonPath { get; set; } = string.Empty;
    public bool SkipClassification { get; set; }
    public bool SkipNaming { get; set; }
    public bool SkipCatalog { get; set; }
    public bool RefreshCatalogs { get; set; }
    public bool GenerateStats { get; set; }

    /// <summary>
    /// When true (default), removes published outputs under each results root for this alias (root-level *.json/*.md, autodoc/)
    /// and clears AnalysisCommon2/Databases/*.json before a run. Preserves _History.
    /// </summary>
    public bool CleanBeforeRun { get; set; } = true;

    public List<int> SkipPhases { get; set; } = [];
    public SystemAnalyzerOptions Options { get; set; } = new();
}
