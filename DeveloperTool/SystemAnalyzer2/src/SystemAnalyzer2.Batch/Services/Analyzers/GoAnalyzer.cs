using SystemAnalyzer2.Core.Models;

namespace SystemAnalyzer2.Batch.Services.Analyzers;

public sealed class GoAnalyzer : AnalyzerBase
{
    public override string TechnologyId => "go";
    public override string VendorId => "google";
    public override string ProductId => "go";

    public override bool CanHandle(TechSectionConfig config) => MatchesTechnology(config, "go");

    public override Task<TechAnalysisResult> AnalyzeAsync(TechAnalysisRequest request, CancellationToken ct = default) =>
        throw new NotImplementedException("GoAnalyzer is a placeholder for future implementation.");
}
