using System.ComponentModel.DataAnnotations;
using System.ComponentModel.DataAnnotations.Schema;

namespace DedgeAuth.Core.Models;

/// <summary>
/// A user's request for app access, role change, or global access level change.
/// Requires admin approval before taking effect.
/// </summary>
[Table("access_requests")]
public class AccessRequest
{
    public const string TypeAppAccess = "AppAccess";
    public const string TypeRoleChange = "RoleChange";
    public const string TypeAccessLevelChange = "AccessLevelChange";

    public const string StatusPending = "Pending";
    public const string StatusApproved = "Approved";
    public const string StatusRejected = "Rejected";

    [Key]
    [Column("id")]
    public Guid Id { get; set; } = Guid.NewGuid();

    [Required]
    [Column("user_id")]
    public Guid UserId { get; set; }

    [ForeignKey(nameof(UserId))]
    public User? User { get; set; }

    /// <summary>
    /// Target app (null when requesting a global access level change only)
    /// </summary>
    [Column("app_id")]
    public Guid? AppId { get; set; }

    [ForeignKey(nameof(AppId))]
    public App? App { get; set; }

    /// <summary>
    /// "AppAccess", "RoleChange", or "AccessLevelChange"
    /// </summary>
    [Required]
    [Column("request_type")]
    [MaxLength(50)]
    public string RequestType { get; set; } = TypeAppAccess;

    /// <summary>
    /// Desired app role (from the app's available_roles_json)
    /// </summary>
    [Column("requested_role")]
    [MaxLength(100)]
    public string? RequestedRole { get; set; }

    /// <summary>
    /// Desired global access level (0-5)
    /// </summary>
    [Column("requested_access_level")]
    public int? RequestedAccessLevel { get; set; }

    /// <summary>
    /// User's justification or message
    /// </summary>
    [Column("reason")]
    [MaxLength(1000)]
    public string? Reason { get; set; }

    /// <summary>
    /// "Pending", "Approved", or "Rejected"
    /// </summary>
    [Required]
    [Column("status")]
    [MaxLength(20)]
    public string Status { get; set; } = StatusPending;

    /// <summary>
    /// Admin email who reviewed the request
    /// </summary>
    [Column("reviewed_by")]
    [MaxLength(255)]
    public string? ReviewedBy { get; set; }

    /// <summary>
    /// Admin's note when approving or rejecting
    /// </summary>
    [Column("review_note")]
    [MaxLength(1000)]
    public string? ReviewNote { get; set; }

    [Column("created_at")]
    public DateTime CreatedAt { get; set; } = DateTime.UtcNow;

    [Column("reviewed_at")]
    public DateTime? ReviewedAt { get; set; }
}
