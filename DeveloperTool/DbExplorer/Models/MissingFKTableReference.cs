namespace DbExplorer.Models;

/// <summary>
/// Simple table reference with schema and name.
/// </summary>
public class TableReference
{
    public string Schema { get; set; } = string.Empty;
    public string Name { get; set; } = string.Empty;
    
    public string FullName => $"{Schema}.{Name}";
}
