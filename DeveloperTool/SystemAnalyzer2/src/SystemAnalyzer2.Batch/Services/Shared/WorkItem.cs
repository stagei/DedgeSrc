namespace SystemAnalyzer2.Batch.Services.Shared;

/// <summary>
/// Represents a single item in the batch processing work queue.
/// Used for both file-based (CBL, REX, BAT, PS1, PSM1) and table-based (SQL) work items.
/// Converted from the PS unified queue item structure (lines 2619-2723).
/// </summary>
public class WorkItem
{
    /// <summary>Parser type: CBL, REX, BAT, PS1, PSM1, SQL.</summary>
    public string ParserType { get; set; } = "";

    /// <summary>Full path to source file (null for SQL).</summary>
    public string? FilePath { get; set; }

    /// <summary>Source file name only (null for SQL).</summary>
    public string? FileName { get; set; }

    /// <summary>SQL table name "SCHEMA.TABLE" (null for file items).</summary>
    public string? TableName { get; set; }

    /// <summary>Alter time string from tables.csv (SQL only, for regen check).</summary>
    public string? AlterTime { get; set; }
}
