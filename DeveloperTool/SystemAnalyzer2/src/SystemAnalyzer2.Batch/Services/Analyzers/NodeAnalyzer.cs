using SystemAnalyzer2.Core.Models;

namespace SystemAnalyzer2.Batch.Services.Analyzers;

public sealed class NodeAnalyzer : AnalyzerBase
{
    public override string TechnologyId => "node";
    public override string VendorId => "openjs";
    public override string ProductId => "nodejs";

    public override bool CanHandle(TechSectionConfig config) => MatchesTechnology(config, "node");

    public override Task<TechAnalysisResult> AnalyzeAsync(TechAnalysisRequest request, CancellationToken ct = default) =>
        throw new NotImplementedException("NodeAnalyzer is a placeholder for future implementation.");
}
