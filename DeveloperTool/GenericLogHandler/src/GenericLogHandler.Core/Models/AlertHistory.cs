using System.ComponentModel.DataAnnotations;
using System.ComponentModel.DataAnnotations.Schema;

namespace GenericLogHandler.Core.Models;

/// <summary>
/// Tracks the history of triggered alerts
/// </summary>
[Table("alert_history")]
public class AlertHistory
{
    /// <summary>
    /// Unique identifier for the alert history entry
    /// </summary>
    [Key]
    [Column("id")]
    public Guid Id { get; set; } = Guid.NewGuid();

    /// <summary>
    /// Reference to the saved filter that triggered this alert
    /// </summary>
    [Required]
    [Column("filter_id")]
    public Guid FilterId { get; set; }

    /// <summary>
    /// Name of the filter at the time of triggering (for historical reference)
    /// </summary>
    [Required]
    [Column("filter_name")]
    [MaxLength(200)]
    public string FilterName { get; set; } = string.Empty;

    /// <summary>
    /// When the alert was triggered
    /// </summary>
    [Required]
    [Column("triggered_at")]
    public DateTime TriggeredAt { get; set; } = DateTime.UtcNow;

    /// <summary>
    /// Number of log entries that matched the filter criteria
    /// </summary>
    [Column("match_count")]
    public int MatchCount { get; set; }

    /// <summary>
    /// Type of action taken (webhook, script, servermonitor, email)
    /// </summary>
    [Required]
    [Column("action_type")]
    [MaxLength(50)]
    public string ActionType { get; set; } = string.Empty;

    /// <summary>
    /// Description of the action taken
    /// </summary>
    [Column("action_taken")]
    [MaxLength(2000)]
    public string? ActionTaken { get; set; }

    /// <summary>
    /// Whether the action was successful
    /// </summary>
    [Column("success")]
    public bool Success { get; set; }

    /// <summary>
    /// Error message if the action failed
    /// </summary>
    [Column("error_message")]
    public string? ErrorMessage { get; set; }

    /// <summary>
    /// Response from the action (e.g. HTTP response body)
    /// </summary>
    [Column("action_response")]
    public string? ActionResponse { get; set; }

    /// <summary>
    /// Duration of the action execution in milliseconds
    /// </summary>
    [Column("execution_duration_ms")]
    public long ExecutionDurationMs { get; set; }

    /// <summary>
    /// JSON array of sample log entry IDs that triggered the alert
    /// </summary>
    [Column("sample_entry_ids")]
    public string? SampleEntryIds { get; set; }

    /// <summary>
    /// Navigation property to the saved filter
    /// </summary>
    [ForeignKey(nameof(FilterId))]
    public SavedFilter? Filter { get; set; }
}
