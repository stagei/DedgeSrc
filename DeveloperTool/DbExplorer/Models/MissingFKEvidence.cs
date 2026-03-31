namespace DbExplorer.Models;

/// <summary>
/// Evidence data for a missing FK candidate.
/// Contains statistics about the relationship match.
/// </summary>
public class MissingFKEvidence
{
    /// <summary>
    /// Number of distinct values in child column.
    /// </summary>
    public long ChildDistinct { get; set; }
    
    /// <summary>
    /// Number of distinct values in parent column.
    /// </summary>
    public long ParentDistinct { get; set; }
    
    /// <summary>
    /// Number of child values not found in parent (orphaned values).
    /// </summary>
    public long MissingInParent { get; set; }
}
