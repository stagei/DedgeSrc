namespace SystemAnalyzer2.Core.Models;

public sealed class SystemAnalyzerOptions
{
    public string DataRoot { get; set; } = @"C:\opt\src\DedgeSrc\DedgeSystemTools\Folders\Opt\data\SystemAnalyzer";
    private string? _analysisResultsRoot;
    public string AnalysisResultsRoot
    {
        get => _analysisResultsRoot ?? Path.Combine(DataRoot, "AnalysisResults");
        set => _analysisResultsRoot = string.IsNullOrWhiteSpace(value) ? null : value;
    }
    public string BatchRoot { get; set; } = "";
    public string AnalysisServerName { get; set; } = "dedge-server";
    public string RagUrl { get; set; } = "http://dedge-server:8486/query";
    public string VisualCobolRagUrl { get; set; } = "http://dedge-server:8485";
    public string SourceRoot { get; set; } = @"C:\opt\data\VisualCobol\Sources";
    public string Db2Dsn { get; set; } = "BASISTST";
    public string DefaultFilePath { get; set; } = @"N:\COBNT";
    public string OllamaUrl { get; set; } = "http://localhost:11434";
    public string OllamaModel { get; set; } = "qwen2.5:7b";
    public int MaxCallIterations { get; set; } = 5;
    public int RagResults { get; set; } = 8;
    public int RagTableResults { get; set; } = 5;
    public string AutoDocJsonPath { get; set; } = @"C:\opt\src\DedgeSrc\DedgeSystemTools\Folders\Opt\Webs\AutoDocJson";
    public string AutoDocJsonApiUrl { get; set; } = "http://dedge-server/AutoDocJson";
    /// <summary>"direct" = serve files from AutoDocJsonPath via controller; "api" = proxy to external AutoDocJson API (future).</summary>
    public string AutoDocMode { get; set; } = "direct";
    public string AnalysisCommonPath { get; set; } = @"C:\opt\src\SystemAnalyzer\AnalysisCommon";

    /// <summary>Shared multi-DB catalog exports (<c>Databases/*.json</c>) for all profiles; empty disables second export.</summary>
    public string AnalysisCommon2Path { get; set; } =
        @"C:\opt\src\DedgeSrc\DeveloperTool\SystemAnalyzer2\AnalysisCommon2";

    public string AnalysisOverridePath { get; set; } = @"C:\opt\src\SystemAnalyzer\AnalysisOverride";
    public string CobdokCsvPath { get; set; } = @"C:\opt\data\AutoDocJson\tmp\cobdok\modul.csv";

    /// <summary>
    /// When true (default), embedded AutoDoc parsers run locally and write JSON under the analysis output folder.
    /// When false, pre-generated JSON is fetched via <see cref="ResolveAutoDocFetchBaseUrl"/>.
    /// </summary>
    public bool GenerateLocally { get; set; } = true;

    /// <summary>
    /// Optional override for remote AutoDoc JSON fetch. When unset or left at the placeholder default,
    /// <see cref="ResolveAutoDocFetchBaseUrl"/> uses <see cref="AutoDocJsonApiUrl"/> (e.g. from appsettings).
    /// </summary>
    public string AutoDocApiUrl { get; set; } = "https://autodocjson.internal/api";

    /// <summary>
    /// Base URL for GET <c>docs/{PROG}.CBL.json</c> when <see cref="GenerateLocally"/> is false.
    /// Uses <see cref="AutoDocApiUrl"/> when explicitly set; otherwise <see cref="AutoDocJsonApiUrl"/>.
    /// </summary>
    public string ResolveAutoDocFetchBaseUrl()
    {
        const string placeholderDefault = "https://autodocjson.internal/api";
        var primary = (AutoDocApiUrl ?? "").TrimEnd('/');
        if (!string.IsNullOrEmpty(primary) &&
            !string.Equals(primary, placeholderDefault, StringComparison.OrdinalIgnoreCase))
            return primary;
        return (AutoDocJsonApiUrl ?? "").TrimEnd('/');
    }
}
