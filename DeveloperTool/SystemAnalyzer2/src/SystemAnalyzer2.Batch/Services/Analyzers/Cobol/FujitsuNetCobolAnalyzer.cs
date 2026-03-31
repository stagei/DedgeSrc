using SystemAnalyzer2.Core.Models;

namespace SystemAnalyzer2.Batch.Services.Analyzers.Cobol;

public sealed class FujitsuNetCobolAnalyzer : CobolAnalyzerBase
{
    public override string VendorId => "fujitsu";
    public override string ProductId => "netcobol-windows";

    public override bool CanHandle(TechSectionConfig config) =>
        MatchesTechnology(config, "cobol") &&
        (MatchesVendorProduct(config, "fujitsu", "netcobol-windows") ||
         MatchesVendorProduct(config, "fujitsu", "netcobol-dotnet") ||
         MatchesVendorProduct(config, "fujitsu", "netcobol-linux"));

    public override Task<TechAnalysisResult> AnalyzeAsync(TechAnalysisRequest request, CancellationToken ct = default) =>
        throw new NotImplementedException("Fujitsu NetCOBOL analyzer is not implemented yet.");
}
