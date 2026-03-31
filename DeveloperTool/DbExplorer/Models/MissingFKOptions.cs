namespace DbExplorer.Models;

/// <summary>
/// Options and thresholds for Missing FK Discovery batch job.
/// </summary>
public class MissingFKOptions
{
    /// <summary>
    /// Minimum row count for a table to be analyzed (default: 100).
    /// </summary>
    public int MinRowCount { get; set; } = 100;
    
    /// <summary>
    /// Minimum match ratio to consider a candidate (default: 0.95).
    /// Match ratio = child values present in parent / total child values.
    /// </summary>
    public double MinMatchRatio { get; set; } = 0.95;
    
    /// <summary>
    /// Match ratio threshold for STRONG confidence (default: 0.99).
    /// </summary>
    public double StrongMatchRatio { get; set; } = 0.99;
    
    /// <summary>
    /// Maximum number of tables to export in parallel (default: 4).
    /// </summary>
    public int MaxParallelTables { get; set; } = 4;
    
    /// <summary>
    /// Export format for table data (default: "csv").
    /// </summary>
    public string ExportFormat { get; set; } = "csv";
    
    /// <summary>
    /// Whether to include NULL values in match calculations (default: false).
    /// </summary>
    public bool IncludeNullsInMatch { get; set; } = false;
}
