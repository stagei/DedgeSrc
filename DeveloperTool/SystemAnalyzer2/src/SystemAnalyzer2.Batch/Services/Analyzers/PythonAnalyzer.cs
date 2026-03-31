using SystemAnalyzer2.Core.Models;

namespace SystemAnalyzer2.Batch.Services.Analyzers;

public sealed class PythonAnalyzer : AnalyzerBase
{
    public override string TechnologyId => "python";
    public override string VendorId => "python";
    public override string ProductId => "cpython";

    public override bool CanHandle(TechSectionConfig config) => MatchesTechnology(config, "python");

    public override Task<TechAnalysisResult> AnalyzeAsync(TechAnalysisRequest request, CancellationToken ct = default) =>
        throw new NotImplementedException("PythonAnalyzer is a placeholder for future implementation.");
}
