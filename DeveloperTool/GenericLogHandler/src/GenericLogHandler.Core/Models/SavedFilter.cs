using System.ComponentModel.DataAnnotations;
using System.ComponentModel.DataAnnotations.Schema;

namespace GenericLogHandler.Core.Models;

/// <summary>
/// Represents a saved search filter that can be reused and optionally trigger alerts
/// </summary>
[Table("saved_filters")]
public class SavedFilter
{
    /// <summary>
    /// Unique identifier for the saved filter
    /// </summary>
    [Key]
    [Column("id")]
    public Guid Id { get; set; } = Guid.NewGuid();

    /// <summary>
    /// Display name for the filter
    /// </summary>
    [Required]
    [Column("name")]
    [MaxLength(200)]
    public string Name { get; set; } = string.Empty;

    /// <summary>
    /// Optional description of what this filter searches for
    /// </summary>
    [Column("description")]
    [MaxLength(1000)]
    public string? Description { get; set; }

    /// <summary>
    /// JSON-serialized LogSearchCriteria
    /// </summary>
    [Required]
    [Column("filter_json")]
    public string FilterJson { get; set; } = "{}";

    /// <summary>
    /// User who created this filter
    /// </summary>
    [Required]
    [Column("created_by")]
    [MaxLength(200)]
    public string CreatedBy { get; set; } = string.Empty;

    /// <summary>
    /// When the filter was created
    /// </summary>
    [Column("created_at")]
    public DateTime CreatedAt { get; set; } = DateTime.UtcNow;

    /// <summary>
    /// When the filter was last modified
    /// </summary>
    [Column("updated_at")]
    public DateTime? UpdatedAt { get; set; }

    /// <summary>
    /// Whether this filter is used by the alert agent
    /// </summary>
    [Column("is_alert_enabled")]
    public bool IsAlertEnabled { get; set; } = false;

    /// <summary>
    /// JSON-serialized AlertConfig for triggered actions
    /// </summary>
    [Column("alert_config")]
    public string? AlertConfig { get; set; }

    /// <summary>
    /// Last time the alert was evaluated
    /// </summary>
    [Column("last_evaluated_at")]
    public DateTime? LastEvaluatedAt { get; set; }

    /// <summary>
    /// Last time the alert was triggered
    /// </summary>
    [Column("last_triggered_at")]
    public DateTime? LastTriggeredAt { get; set; }

    /// <summary>
    /// Whether this filter is shared with all users or private
    /// </summary>
    [Column("is_shared")]
    public bool IsShared { get; set; } = false;

    /// <summary>
    /// Category or tag for organizing filters
    /// </summary>
    [Column("category")]
    [MaxLength(100)]
    public string? Category { get; set; }
}
