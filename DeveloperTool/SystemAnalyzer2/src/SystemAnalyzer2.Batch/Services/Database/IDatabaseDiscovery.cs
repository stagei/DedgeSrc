namespace SystemAnalyzer2.Batch.Services.Database;

public interface IDatabaseDiscovery
{
    string DatabaseKind { get; }
    Task ExportCatalogAsync(string outputDir, CancellationToken ct = default);
}
