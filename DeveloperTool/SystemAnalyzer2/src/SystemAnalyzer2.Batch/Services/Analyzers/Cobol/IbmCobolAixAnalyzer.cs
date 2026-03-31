using SystemAnalyzer2.Core.Models;

namespace SystemAnalyzer2.Batch.Services.Analyzers.Cobol;

public sealed class IbmCobolAixAnalyzer : CobolAnalyzerBase
{
    public override string VendorId => "ibm";
    public override string ProductId => "cobol-aix";

    public override bool CanHandle(TechSectionConfig config) =>
        MatchesTechnology(config, "cobol") &&
        MatchesVendorProduct(config, "ibm", "cobol-aix");

    public override Task<TechAnalysisResult> AnalyzeAsync(TechAnalysisRequest request, CancellationToken ct = default) =>
        throw new NotImplementedException(
            "IBM COBOL for AIX analyzer requires RAG database. See IBM COBOL Documentation Download Plan.");
}
