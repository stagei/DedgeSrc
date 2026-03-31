namespace DbExplorer.Models;

/// <summary>
/// Summary statistics for Missing FK Discovery results.
/// </summary>
public class MissingFKSummary
{
    /// <summary>
    /// Total number of tables scanned.
    /// </summary>
    public int TablesScanned { get; set; }
    
    /// <summary>
    /// Total number of candidates found (STRONG + POSSIBLE).
    /// </summary>
    public int CandidatesFound { get; set; }
    
    /// <summary>
    /// Number of candidates with STRONG confidence.
    /// </summary>
    public int StrongCandidates { get; set; }
    
    /// <summary>
    /// Number of tables without primary keys or unique constraints.
    /// </summary>
    public int TablesWithoutKeys { get; set; }
}
