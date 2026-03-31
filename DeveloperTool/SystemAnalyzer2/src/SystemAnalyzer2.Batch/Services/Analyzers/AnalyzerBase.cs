using SystemAnalyzer2.Core.Models;

namespace SystemAnalyzer2.Batch.Services.Analyzers;

public abstract class AnalyzerBase : ITechnologyAnalyzer
{
    public abstract string TechnologyId { get; }
    public abstract string VendorId { get; }
    public abstract string ProductId { get; }
    public abstract bool CanHandle(TechSectionConfig config);

    public abstract Task<TechAnalysisResult> AnalyzeAsync(TechAnalysisRequest request, CancellationToken ct = default);

    protected static bool MatchesVendorProduct(TechSectionConfig config, string vendorId, string productId) =>
        string.Equals(config.Vendor, vendorId, StringComparison.OrdinalIgnoreCase) &&
        string.Equals(config.Product, productId, StringComparison.OrdinalIgnoreCase);

    protected static bool MatchesTechnology(TechSectionConfig config, string techId) =>
        string.Equals(config.TechnologyId, techId, StringComparison.OrdinalIgnoreCase);
}
