using System.Collections.Generic;

namespace DbExplorer.Models;

/// <summary>
/// Foreign key information for Missing FK Discovery input JSON.
/// </summary>
public class MissingFKForeignKeyInfo
{
    public string Name { get; set; } = string.Empty;
    public List<string> Columns { get; set; } = new();
    public string RefSchema { get; set; } = string.Empty;
    public string RefTable { get; set; } = string.Empty;
    public List<string> RefColumns { get; set; } = new();
}
