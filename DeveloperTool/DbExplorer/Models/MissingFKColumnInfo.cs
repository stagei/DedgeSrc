namespace DbExplorer.Models;

/// <summary>
/// Column information for Missing FK Discovery.
/// </summary>
public class MissingFKColumnInfo
{
    public string Name { get; set; } = string.Empty;
    public string DataType { get; set; } = string.Empty;
    public int? Length { get; set; }
    public int? Scale { get; set; }
    public bool Nullable { get; set; }
}
