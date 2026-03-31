using SystemAnalyzer2.Core.Models;

namespace SystemAnalyzer2.Batch.Services.Analyzers.Cobol;

public sealed class GnuCobolAnalyzer : CobolAnalyzerBase
{
    public override string VendorId => "gnu";
    public override string ProductId => "gnucobol";

    public override bool CanHandle(TechSectionConfig config) =>
        MatchesTechnology(config, "cobol") &&
        MatchesVendorProduct(config, "gnu", "gnucobol");

    public override Task<TechAnalysisResult> AnalyzeAsync(TechAnalysisRequest request, CancellationToken ct = default) =>
        throw new NotImplementedException("GnuCOBOL analyzer is not implemented yet.");
}
