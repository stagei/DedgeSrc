namespace GenericLogHandler.Core.Models;

/// <summary>
/// DTO for the anonymous log ingest API. Supports both minimal (message + level + source)
/// and full (all LogEntry fields) submissions. Missing fields get sensible defaults
/// when the ImportService converts queue entries to LogEntry records.
/// </summary>
public class IngestLogRequest
{
    public string Message { get; set; } = string.Empty;
    public string? Level { get; set; }
    public string? Source { get; set; }
    public DateTime? Timestamp { get; set; }
    public string? ComputerName { get; set; }
    public string? UserName { get; set; }
    public string? JobName { get; set; }
    public string? JobStatus { get; set; }
    public string? ErrorId { get; set; }
    public string? ExceptionType { get; set; }
    public string? StackTrace { get; set; }
    public string? FunctionName { get; set; }
    public string? Location { get; set; }
}
