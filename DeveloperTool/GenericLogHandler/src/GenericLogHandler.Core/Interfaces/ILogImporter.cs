using GenericLogHandler.Core.Models;
using GenericLogHandler.Core.Models.Configuration;

namespace GenericLogHandler.Core.Interfaces;

/// <summary>
/// Interface for log import implementations
/// </summary>
public interface ILogImporter
{
    /// <summary>
    /// Gets the name of this importer
    /// </summary>
    string Name { get; }

    /// <summary>
    /// Gets the supported source types for this importer
    /// </summary>
    IEnumerable<string> SupportedSourceTypes { get; }

    /// <summary>
    /// Initializes the importer with configuration
    /// </summary>
    Task InitializeAsync(ImportSource source, CancellationToken cancellationToken = default);

    /// <summary>
    /// Imports log entries from the configured source
    /// </summary>
    Task<ImportResult> ImportAsync(CancellationToken cancellationToken = default);

    /// <summary>
    /// Tests the connection/configuration without importing data
    /// </summary>
    Task<bool> TestConnectionAsync(CancellationToken cancellationToken = default);

    /// <summary>
    /// Gets the current status of the importer
    /// </summary>
    ImportStatus GetStatus();

    /// <summary>
    /// Cleans up resources
    /// </summary>
    Task DisposeAsync();
}

/// <summary>
/// Result of an import operation
/// </summary>
public class ImportResult
{
    public bool Success { get; set; }
    public long RecordsProcessed { get; set; }
    public long RecordsFailed { get; set; }
    public TimeSpan Duration { get; set; }
    public string ErrorMessage { get; set; } = string.Empty;
    public List<LogEntry> ImportedEntries { get; set; } = new();
    public Dictionary<string, object> Metadata { get; set; } = new();

    public double GetProcessingRate()
    {
        if (Duration.TotalSeconds <= 0) return 0;
        return RecordsProcessed / Duration.TotalSeconds;
    }

    public double GetErrorRate()
    {
        var totalRecords = RecordsProcessed + RecordsFailed;
        if (totalRecords <= 0) return 0;
        return (double)RecordsFailed / totalRecords * 100;
    }
}
