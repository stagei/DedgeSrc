using System.ComponentModel.DataAnnotations;
using System.ComponentModel.DataAnnotations.Schema;
using System.Text.RegularExpressions;

namespace GenericLogHandler.Core.Models;

/// <summary>
/// Represents a single log entry in the system
/// </summary>
[Table("log_entries")]
public class LogEntry
{
    /// <summary>
    /// Unique identifier for the log entry
    /// </summary>
    [Key]
    [Column("id")]
    public Guid Id { get; set; } = Guid.NewGuid();

    /// <summary>
    /// Auto-incrementing internal ID for bulk operations
    /// </summary>
    [Column("internal_id")]
    [DatabaseGenerated(DatabaseGeneratedOption.Identity)]
    public long InternalId { get; set; }

    /// <summary>
    /// Timestamp when the log entry was created
    /// </summary>
    [Required]
    [Column("timestamp")]
    public DateTime Timestamp { get; set; }

    /// <summary>
    /// Severity level of the log entry
    /// </summary>
    [Required]
    [Column("level")]
    [MaxLength(10)]
    public LogLevel Level { get; set; }

    /// <summary>
    /// ID of the PowerShell process executing the code
    /// </summary>
    [Column("process_id")]
    public int ProcessId { get; set; }

    /// <summary>
    /// Script or module location where the log was generated
    /// </summary>
    [Column("location")]
    [MaxLength(500)]
    public string Location { get; set; } = string.Empty;

    /// <summary>
    /// Name of the function generating the log
    /// </summary>
    [Column("function_name")]
    [MaxLength(200)]
    public string FunctionName { get; set; } = string.Empty;

    /// <summary>
    /// Line number in the script where the log was generated
    /// </summary>
    [Column("line_number")]
    public int LineNumber { get; set; }

    /// <summary>
    /// Name of the computer executing the code
    /// </summary>
    [Required]
    [Column("computer_name")]
    [MaxLength(100)]
    public string ComputerName { get; set; } = string.Empty;

    /// <summary>
    /// Domain and username of the account running the script
    /// </summary>
    [Column("user_name")]
    [MaxLength(200)]
    public string UserName { get; set; } = string.Empty;

    /// <summary>
    /// Main log message content
    /// </summary>
    [Required]
    [Column("message")]
    [MaxLength(8000)]
    public string Message { get; set; } = string.Empty;

    /// <summary>
    /// Concatenated search string for regex operations
    /// </summary>
    [Column("concatenated_search_string")]
    public string ConcatenatedSearchString { get; set; } = string.Empty;

    /// <summary>
    /// Unique identifier of the error (if applicable)
    /// </summary>
    [Column("error_id")]
    [MaxLength(100)]
    public string? ErrorId { get; set; }

    /// <summary>
    /// Alert identifier extracted from message content
    /// </summary>
    [Column("alert_id")]
    [MaxLength(100)]
    public string? AlertId { get; set; }

    /// <summary>
    /// Order number (ordrenr/ordrenummer/orderno) extracted from message content
    /// </summary>
    [Column("ordrenr")]
    [MaxLength(50)]
    public string? Ordrenr { get; set; }

    /// <summary>
    /// Department number (avdnr) extracted from message content
    /// </summary>
    [Column("avdnr")]
    [MaxLength(50)]
    public string? Avdnr { get; set; }

    /// <summary>
    /// Job or module name for the log entry
    /// </summary>
    [Column("job_name")]
    [MaxLength(200)]
    public string? JobName { get; set; }

    /// <summary>
    /// Status of the job (Started, Completed, Failed, Running, etc.)
    /// </summary>
    [Column("job_status")]
    [MaxLength(50)]
    public string? JobStatus { get; set; }

    /// <summary>
    /// .NET type of the exception object (if applicable)
    /// </summary>
    [Column("exception_type")]
    [MaxLength(500)]
    public string? ExceptionType { get; set; }

    /// <summary>
    /// Stack trace showing where the error occurred (if applicable)
    /// </summary>
    [Column("stack_trace")]
    public string? StackTrace { get; set; }

    /// <summary>
    /// Details of any nested exception (if applicable)
    /// </summary>
    [Column("inner_exception")]
    public string? InnerException { get; set; }

    /// <summary>
    /// PowerShell command that caused the error (if applicable)
    /// </summary>
    [Column("command_invocation")]
    [MaxLength(1000)]
    public string? CommandInvocation { get; set; }

    /// <summary>
    /// Line number where the error occurred (if applicable)
    /// </summary>
    [Column("script_line_number")]
    public int? ScriptLineNumber { get; set; }

    /// <summary>
    /// Name of the script containing the error (if applicable)
    /// </summary>
    [Column("script_name")]
    [MaxLength(500)]
    public string? ScriptName { get; set; }

    /// <summary>
    /// Character position in the line where the error occurred (if applicable)
    /// </summary>
    [Column("position")]
    public int? Position { get; set; }

    /// <summary>
    /// Source file or system that generated this log entry
    /// </summary>
    [Column("source_file")]
    [MaxLength(500)]
    public string SourceFile { get; set; } = string.Empty;

    /// <summary>
    /// Type of source (file, database, eventlog, etc.)
    /// </summary>
    [Column("source_type")]
    [MaxLength(50)]
    public string SourceType { get; set; } = string.Empty;

    /// <summary>
    /// Timestamp when this entry was imported into the system
    /// </summary>
    [Column("import_timestamp")]
    public DateTime ImportTimestamp { get; set; } = DateTime.UtcNow;

    /// <summary>
    /// Batch ID for tracking related imports
    /// </summary>
    [Column("import_batch_id")]
    [MaxLength(50)]
    public string ImportBatchId { get; set; } = string.Empty;

    /// <summary>
    /// If true, this entry is protected from automatic cleanup/sanitation.
    /// Protected entries can only be deleted manually via SQL.
    /// </summary>
    [Column("protected")]
    public bool Protected { get; set; } = false;

    /// <summary>
    /// Reason why this entry is protected (optional, for documentation)
    /// </summary>
    [Column("protection_reason")]
    [MaxLength(500)]
    public string? ProtectionReason { get; set; }

    /// <summary>
    /// Trims leading/trailing whitespace and collapses multiple spaces (including tabs/newlines) to a single space.
    /// Use for all message and text fields before storage so the job log and search stay consistent.
    /// </summary>
    public static string TrimMultiSpace(string? value)
    {
        if (string.IsNullOrEmpty(value)) return value ?? string.Empty;
        var trimmed = value.Trim();
        if (trimmed.Length == 0) return string.Empty;
        return Regex.Replace(trimmed, @"\s+", " ");
    }

    /// <summary>
    /// Generates the concatenated search string from all relevant fields
    /// </summary>
    public void GenerateConcatenatedSearchString()
    {
        var parts = new List<string>
        {
            ComputerName,
            UserName,
            FunctionName,
            Message,
            ErrorId ?? string.Empty,
            ExceptionType ?? string.Empty,
            Location,
            AlertId ?? string.Empty,
            Ordrenr ?? string.Empty,
            Avdnr ?? string.Empty,
            JobName ?? string.Empty,
            JobStatus ?? string.Empty
        };

        ConcatenatedSearchString = string.Join(" ", parts.Where(p => !string.IsNullOrWhiteSpace(p)));
    }
}

/// <summary>
/// Log severity levels
/// </summary>
public enum LogLevel
{
    TRACE = 1,
    DEBUG = 2,
    INFO = 3,
    WARN = 4,
    ERROR = 5,
    FATAL = 6
}
