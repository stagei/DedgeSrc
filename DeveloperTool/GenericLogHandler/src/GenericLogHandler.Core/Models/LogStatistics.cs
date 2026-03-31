namespace GenericLogHandler.Core.Models;

/// <summary>
/// Log statistics summary
/// </summary>
public class LogStatistics
{
    public long TotalEntries { get; set; }
    public long ErrorEntries { get; set; }
    public long WarningEntries { get; set; }
    public long InfoEntries { get; set; }
    public int UniqueComputers { get; set; }
    public int UniqueUsers { get; set; }
    public DateTime? FirstEntry { get; set; }
    public DateTime? LastEntry { get; set; }
    public Dictionary<string, long> TopSources { get; set; } = new();
    public Dictionary<string, long> TopErrorTypes { get; set; } = new();
}
