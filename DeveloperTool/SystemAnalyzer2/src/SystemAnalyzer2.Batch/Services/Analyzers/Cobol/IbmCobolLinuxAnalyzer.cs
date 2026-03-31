using SystemAnalyzer2.Core.Models;

namespace SystemAnalyzer2.Batch.Services.Analyzers.Cobol;

public sealed class IbmCobolLinuxAnalyzer : CobolAnalyzerBase
{
    public override string VendorId => "ibm";
    public override string ProductId => "cobol-linux-x86";

    public override bool CanHandle(TechSectionConfig config) =>
        MatchesTechnology(config, "cobol") &&
        MatchesVendorProduct(config, "ibm", "cobol-linux-x86");

    public override Task<TechAnalysisResult> AnalyzeAsync(TechAnalysisRequest request, CancellationToken ct = default) =>
        throw new NotImplementedException(
            "IBM COBOL for Linux on x86 analyzer requires RAG database. See IBM COBOL Documentation Download Plan.");
}
