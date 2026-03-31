using System.ComponentModel.DataAnnotations;
using System.ComponentModel.DataAnnotations.Schema;

namespace DedgeAuth.Core.Models;

/// <summary>
/// User permission for a specific application
/// </summary>
[Table("app_permissions")]
public class AppPermission
{
    [Key]
    [Column("id")]
    public Guid Id { get; set; } = Guid.NewGuid();

    /// <summary>
    /// User ID
    /// </summary>
    [Required]
    [Column("user_id")]
    public Guid UserId { get; set; }

    /// <summary>
    /// Associated user
    /// </summary>
    [ForeignKey(nameof(UserId))]
    public User? User { get; set; }

    /// <summary>
    /// App ID
    /// </summary>
    [Required]
    [Column("app_id")]
    public Guid AppId { get; set; }

    /// <summary>
    /// Associated app
    /// </summary>
    [ForeignKey(nameof(AppId))]
    public App? App { get; set; }

    /// <summary>
    /// Role assigned to the user for this app (e.g., "Admin", "Operator", "Viewer")
    /// </summary>
    [Required]
    [Column("role")]
    [MaxLength(100)]
    public string Role { get; set; } = string.Empty;

    /// <summary>
    /// When the permission was granted
    /// </summary>
    [Column("granted_at")]
    public DateTime GrantedAt { get; set; } = DateTime.UtcNow;

    /// <summary>
    /// Who granted this permission (email or system)
    /// </summary>
    [Column("granted_by")]
    [MaxLength(255)]
    public string? GrantedBy { get; set; }
}
