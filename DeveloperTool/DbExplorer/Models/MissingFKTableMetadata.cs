using System.Collections.Generic;

namespace DbExplorer.Models;

/// <summary>
/// Complete table metadata for Missing FK Discovery input JSON.
/// </summary>
public class MissingFKTableMetadata
{
    public string Schema { get; set; } = string.Empty;
    public string Name { get; set; } = string.Empty;
    public long RowCount { get; set; }
    public List<MissingFKColumnInfo> Columns { get; set; } = new();
    public List<string> PrimaryKey { get; set; } = new();
    public List<List<string>> UniqueKeys { get; set; } = new();
    public List<MissingFKForeignKeyInfo> ForeignKeys { get; set; } = new();
}
