namespace GenericLogHandler.Core.Models;

/// <summary>
/// Computer log count summary
/// </summary>
public class ComputerLogCount
{
    public string ComputerName { get; set; } = string.Empty;
    public long TotalLogs { get; set; }
    public long ErrorCount { get; set; }
    public long WarningCount { get; set; }
    public int UniqueUsers { get; set; }
    public DateTime? LastActivity { get; set; }
}
