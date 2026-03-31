using SystemAnalyzer2.Core.Models;

namespace SystemAnalyzer2.Batch.Services.Analyzers;

public interface ITechnologyAnalyzer
{
    string TechnologyId { get; }
    string VendorId { get; }
    string ProductId { get; }

    Task<TechAnalysisResult> AnalyzeAsync(TechAnalysisRequest request, CancellationToken ct = default);

    bool CanHandle(TechSectionConfig config);
}
