using System.Collections.Generic;

namespace DbExplorer.Models;

/// <summary>
/// Represents a foreign key relationship between tables.
/// </summary>
public class ForeignKeyInfo
{
    public string FromSchema { get; set; } = string.Empty;
    public string FromTable { get; set; } = string.Empty;
    public string ToSchema { get; set; } = string.Empty;
    public string ToTable { get; set; } = string.Empty;
    public string ConstraintName { get; set; } = string.Empty;
    public List<string> FromColumns { get; set; } = new();
    public List<string> ToColumns { get; set; } = new();
    public string DeleteRule { get; set; } = string.Empty;
    public string UpdateRule { get; set; } = string.Empty;
    
    public string ToTableFullName => $"{ToSchema}.{ToTable}";
    public string FromTableFullName => $"{FromSchema}.{FromTable}";
}
