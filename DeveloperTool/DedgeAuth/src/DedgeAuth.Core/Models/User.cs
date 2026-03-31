using System.ComponentModel.DataAnnotations;
using System.ComponentModel.DataAnnotations.Schema;

namespace DedgeAuth.Core.Models;

/// <summary>
/// User account for DedgeAuth authentication
/// </summary>
[Table("users")]
public class User
{
    [Key]
    [Column("id")]
    public Guid Id { get; set; } = Guid.NewGuid();

    /// <summary>
    /// Associated tenant ID (resolved from email domain)
    /// </summary>
    [Column("tenant_id")]
    public Guid? TenantId { get; set; }

    /// <summary>
    /// Associated tenant
    /// </summary>
    [ForeignKey(nameof(TenantId))]
    public Tenant? Tenant { get; set; }

    /// <summary>
    /// Email address (unique identifier for login)
    /// </summary>
    [Required]
    [Column("email")]
    [MaxLength(255)]
    public string Email { get; set; } = string.Empty;

    /// <summary>
    /// Display name
    /// </summary>
    [Required]
    [Column("display_name")]
    [MaxLength(200)]
    public string DisplayName { get; set; } = string.Empty;

    /// <summary>
    /// Hashed password (bcrypt)
    /// Null if user only uses magic link authentication
    /// </summary>
    [Column("password_hash")]
    [MaxLength(500)]
    public string? PasswordHash { get; set; }

    /// <summary>
    /// Global access level (used when no app-specific role is assigned)
    /// </summary>
    [Required]
    [Column("global_access_level")]
    public AccessLevel GlobalAccessLevel { get; set; } = AccessLevel.User;

    /// <summary>
    /// Whether the user account is active
    /// </summary>
    [Column("is_active")]
    public bool IsActive { get; set; } = true;

    /// <summary>
    /// Whether email has been verified
    /// </summary>
    [Column("email_verified")]
    public bool EmailVerified { get; set; } = false;

    /// <summary>
    /// Account creation timestamp
    /// </summary>
    [Column("created_at")]
    public DateTime CreatedAt { get; set; } = DateTime.UtcNow;

    /// <summary>
    /// Last login timestamp
    /// </summary>
    [Column("last_login_at")]
    public DateTime? LastLoginAt { get; set; }

    /// <summary>
    /// Failed login attempt count (for lockout)
    /// </summary>
    [Column("failed_login_count")]
    public int FailedLoginCount { get; set; } = 0;

    /// <summary>
    /// Account lockout until this time
    /// </summary>
    [Column("lockout_until")]
    public DateTime? LockoutUntil { get; set; }

    /// <summary>
    /// Optional department/team
    /// </summary>
    [Column("department")]
    [MaxLength(100)]
    public string? Department { get; set; }

    /// <summary>
    /// Preferred UI language (ISO 639-1 code, e.g. "nb", "en")
    /// </summary>
    [Column("preferred_language")]
    [MaxLength(10)]
    public string PreferredLanguage { get; set; } = "nb";

    // 20260317 GHS Test Ad/Entra Start -->
    /// <summary>
    /// How the user last authenticated. null or "internal" = password/magic link, "windows" = Windows/Kerberos.
    /// Informational only — does not restrict which login method the user can use.
    /// </summary>
    [Column("auth_method")]
    [MaxLength(50)]
    public string? AuthMethod { get; set; }
    // <--20260317 GHS Test Ad/Entra End

    /// <summary>
    /// App permissions for this user
    /// </summary>
    public ICollection<AppPermission> AppPermissions { get; set; } = new List<AppPermission>();

    /// <summary>
    /// Check if account is currently locked out
    /// </summary>
    public bool IsLockedOut => LockoutUntil.HasValue && DateTime.UtcNow < LockoutUntil.Value;
}
