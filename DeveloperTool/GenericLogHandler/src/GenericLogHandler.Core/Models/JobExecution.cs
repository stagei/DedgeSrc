using System.ComponentModel.DataAnnotations;
using System.ComponentModel.DataAnnotations.Schema;

namespace GenericLogHandler.Core.Models;

/// <summary>
/// Tracks job execution lifecycle from start to completion/failure.
/// Correlates start and end events for the same job.
/// </summary>
[Table("job_executions")]
public class JobExecution
{
    /// <summary>
    /// Unique identifier for the job execution
    /// </summary>
    [Key]
    [Column("id")]
    public Guid Id { get; set; } = Guid.NewGuid();

    /// <summary>
    /// Name of the job
    /// </summary>
    [Required]
    [Column("job_name")]
    [MaxLength(500)]
    public string JobName { get; set; } = string.Empty;

    /// <summary>
    /// When the job started
    /// </summary>
    [Required]
    [Column("started_at")]
    public DateTime StartedAt { get; set; }

    /// <summary>
    /// When the job completed (null if still running)
    /// </summary>
    [Column("completed_at")]
    public DateTime? CompletedAt { get; set; }

    /// <summary>
    /// Current status: Started, Completed, Failed, TimedOut
    /// </summary>
    [Required]
    [Column("status")]
    [MaxLength(50)]
    public string Status { get; set; } = "Started";

    /// <summary>
    /// Computer where the job ran
    /// </summary>
    [Column("computer_name")]
    [MaxLength(100)]
    public string? ComputerName { get; set; }

    /// <summary>
    /// Process ID of the job
    /// </summary>
    [Column("process_id")]
    public int? ProcessId { get; set; }

    /// <summary>
    /// ID of the log entry that indicates job start
    /// </summary>
    [Column("start_log_entry_id")]
    public Guid? StartLogEntryId { get; set; }

    /// <summary>
    /// ID of the log entry that indicates job end
    /// </summary>
    [Column("end_log_entry_id")]
    public Guid? EndLogEntryId { get; set; }

    /// <summary>
    /// Error message if the job failed
    /// </summary>
    [Column("error_message")]
    [MaxLength(4000)]
    public string? ErrorMessage { get; set; }

    /// <summary>
    /// Duration of the job execution
    /// </summary>
    [Column("duration_seconds")]
    public double? DurationSeconds { get; set; }

    /// <summary>
    /// Source file that contained the job logs
    /// </summary>
    [Column("source_file")]
    [MaxLength(1000)]
    public string? SourceFile { get; set; }

    /// <summary>
    /// When this record was created
    /// </summary>
    [Column("created_at")]
    public DateTime CreatedAt { get; set; } = DateTime.UtcNow;

    /// <summary>
    /// When this record was last updated
    /// </summary>
    [Column("updated_at")]
    public DateTime UpdatedAt { get; set; } = DateTime.UtcNow;

    /// <summary>
    /// Calculated duration as TimeSpan
    /// </summary>
    [NotMapped]
    public TimeSpan? Duration => DurationSeconds.HasValue 
        ? TimeSpan.FromSeconds(DurationSeconds.Value) 
        : null;

    /// <summary>
    /// Whether this job has timed out (started but never completed)
    /// </summary>
    [NotMapped]
    public bool IsTimedOut => Status == "TimedOut";

    /// <summary>
    /// Whether this job is still running (started but not completed)
    /// </summary>
    [NotMapped]
    public bool IsRunning => Status == "Started" && !CompletedAt.HasValue;
}
