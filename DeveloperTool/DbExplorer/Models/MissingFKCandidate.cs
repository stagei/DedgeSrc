using System.Collections.Generic;

namespace DbExplorer.Models;

/// <summary>
/// A candidate missing foreign key relationship.
/// </summary>
public class MissingFKCandidate
{
    public TableReference ChildTable { get; set; } = new();
    public List<string> ChildColumns { get; set; } = new();
    public TableReference ParentTable { get; set; } = new();
    public List<string> ParentColumns { get; set; } = new();
    
    /// <summary>
    /// Match ratio: child values present in parent / total child values.
    /// Range: 0.0 to 1.0
    /// </summary>
    public double MatchRatio { get; set; }
    
    /// <summary>
    /// Ratio of NULL values in child column.
    /// Range: 0.0 to 1.0
    /// </summary>
    public double NullRatio { get; set; }
    
    public MissingFKEvidence Evidence { get; set; } = new();
    
    /// <summary>
    /// Confidence level: "STRONG" or "POSSIBLE".
    /// STRONG if matchRatio >= strongMatchRatio.
    /// POSSIBLE if matchRatio >= minMatchRatio.
    /// </summary>
    public string Confidence { get; set; } = string.Empty;
    
    /// <summary>
    /// Recommendation: "ADD_FK" or "REVIEW".
    /// </summary>
    public string Recommendation { get; set; } = string.Empty;
}
