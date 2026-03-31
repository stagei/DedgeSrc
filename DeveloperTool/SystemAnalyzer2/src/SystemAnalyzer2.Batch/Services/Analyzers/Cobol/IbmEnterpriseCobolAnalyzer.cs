using SystemAnalyzer2.Core.Models;

namespace SystemAnalyzer2.Batch.Services.Analyzers.Cobol;

public sealed class IbmEnterpriseCobolAnalyzer : CobolAnalyzerBase
{
    public override string VendorId => "ibm";
    public override string ProductId => "enterprise-cobol-zos";

    public override bool CanHandle(TechSectionConfig config) =>
        MatchesTechnology(config, "cobol") &&
        (MatchesVendorProduct(config, "ibm", "enterprise-cobol-zos") ||
         MatchesVendorProduct(config, "ibm", "cobol-os390-vm"));

    public override Task<TechAnalysisResult> AnalyzeAsync(TechAnalysisRequest request, CancellationToken ct = default) =>
        throw new NotImplementedException(
            "IBM Enterprise COBOL analyzer requires RAG database. See IBM COBOL Documentation Download Plan.");
}
