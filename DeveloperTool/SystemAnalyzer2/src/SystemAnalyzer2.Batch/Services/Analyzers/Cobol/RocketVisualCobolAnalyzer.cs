using System.Text.Json.Nodes;
using SystemAnalyzer2.Core.Models;

namespace SystemAnalyzer2.Batch.Services.Analyzers.Cobol;

/// <summary>Rocket Visual COBOL (and Enterprise Developer / COBOL Server). COBOL phases run in <see cref="FullAnalysisPipeline"/>; this type participates in registry validation and future split.</summary>
public sealed class RocketVisualCobolAnalyzer : CobolAnalyzerBase
{
    public override string VendorId => "rocket";
    public override string ProductId => "visual-cobol";

    public override bool CanHandle(TechSectionConfig config) =>
        MatchesTechnology(config, "cobol") && (
            MatchesVendorProduct(config, "rocket", "visual-cobol") ||
            MatchesVendorProduct(config, "rocket", "enterprise-developer") ||
            MatchesVendorProduct(config, "rocket", "cobol-server"));

    public override Task<TechAnalysisResult> AnalyzeAsync(TechAnalysisRequest request, CancellationToken ct = default) =>
        Task.FromResult(new TechAnalysisResult(
            TechnologyId: "cobol",
            VendorId: VendorId,
            ProductId: ProductId,
            ProgramCount: 0,
            SqlTableCount: 0,
            CallTargetCount: 0,
            Programs: new List<JsonObject>()));
}
