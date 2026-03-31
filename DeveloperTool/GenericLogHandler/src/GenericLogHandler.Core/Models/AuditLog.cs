using System.ComponentModel.DataAnnotations;
using System.ComponentModel.DataAnnotations.Schema;

namespace GenericLogHandler.Core.Models;

/// <summary>
/// Represents an audit log entry tracking user actions in the system
/// </summary>
[Table("audit_log")]
public class AuditLog
{
    /// <summary>
    /// Unique identifier for the audit entry
    /// </summary>
    [Key]
    [Column("id")]
    [DatabaseGenerated(DatabaseGeneratedOption.Identity)]
    public long Id { get; set; }

    /// <summary>
    /// Timestamp when the action occurred
    /// </summary>
    [Required]
    [Column("timestamp")]
    public DateTime Timestamp { get; set; } = DateTime.UtcNow;

    /// <summary>
    /// User ID or username who performed the action
    /// </summary>
    [Required]
    [Column("user_id")]
    [MaxLength(200)]
    public string UserId { get; set; } = string.Empty;

    /// <summary>
    /// IP address of the user
    /// </summary>
    [Column("ip_address")]
    [MaxLength(50)]
    public string? IpAddress { get; set; }

    /// <summary>
    /// Type of action performed
    /// </summary>
    [Required]
    [Column("action")]
    [MaxLength(50)]
    public string Action { get; set; } = string.Empty;

    /// <summary>
    /// Type of entity affected (e.g., "LogEntry", "SavedFilter", "Configuration")
    /// </summary>
    [Required]
    [Column("entity_type")]
    [MaxLength(100)]
    public string EntityType { get; set; } = string.Empty;

    /// <summary>
    /// ID of the affected entity (if applicable)
    /// </summary>
    [Column("entity_id")]
    [MaxLength(100)]
    public string? EntityId { get; set; }

    /// <summary>
    /// Additional details about the action (JSON or text)
    /// </summary>
    [Column("details")]
    public string? Details { get; set; }

    /// <summary>
    /// Whether the action succeeded
    /// </summary>
    [Column("success")]
    public bool Success { get; set; } = true;

    /// <summary>
    /// Error message if the action failed
    /// </summary>
    [Column("error_message")]
    [MaxLength(2000)]
    public string? ErrorMessage { get; set; }

    /// <summary>
    /// HTTP method used (if applicable)
    /// </summary>
    [Column("http_method")]
    [MaxLength(10)]
    public string? HttpMethod { get; set; }

    /// <summary>
    /// Request path (if applicable)
    /// </summary>
    [Column("request_path")]
    [MaxLength(500)]
    public string? RequestPath { get; set; }

    /// <summary>
    /// Duration of the action in milliseconds
    /// </summary>
    [Column("duration_ms")]
    public long? DurationMs { get; set; }
}

/// <summary>
/// Audit action types
/// </summary>
public static class AuditActions
{
    public const string Create = "CREATE";
    public const string Read = "READ";
    public const string Update = "UPDATE";
    public const string Delete = "DELETE";
    public const string Export = "EXPORT";
    public const string Import = "IMPORT";
    public const string Login = "LOGIN";
    public const string Logout = "LOGOUT";
    public const string ConfigChange = "CONFIG_CHANGE";
    public const string ServiceControl = "SERVICE_CONTROL";
    public const string BulkOperation = "BULK_OPERATION";
    public const string Maintenance = "MAINTENANCE";
    public const string Search = "SEARCH";
}

/// <summary>
/// Entity types for audit logging
/// </summary>
public static class AuditEntityTypes
{
    public const string LogEntry = "LogEntry";
    public const string SavedFilter = "SavedFilter";
    public const string ImportStatus = "ImportStatus";
    public const string Configuration = "Configuration";
    public const string Service = "Service";
    public const string Database = "Database";
    public const string User = "User";
}
