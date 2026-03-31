using System.ComponentModel.DataAnnotations;
using System.ComponentModel.DataAnnotations.Schema;

namespace GenericLogHandler.Core.Models.Auth;

/// <summary>
/// Access levels for user authorization (0-3, higher = more access)
/// </summary>
public enum AccessLevel
{
    /// <summary>
    /// Can only view logs (log-search.html)
    /// </summary>
    ReadOnly = 0,

    /// <summary>
    /// Can view logs + dashboard, analytics, job status
    /// </summary>
    User = 1,

    /// <summary>
    /// User + export, bulk operations, saved filters, maintenance, config, start/stop apps
    /// </summary>
    PowerUser = 2,

    /// <summary>
    /// Full access including user management
    /// </summary>
    Admin = 3
}

/// <summary>
/// User account for custom authentication (independent of Windows AD)
/// </summary>
[Table("users")]
public class User
{
    [Key]
    [Column("id")]
    public Guid Id { get; set; } = Guid.NewGuid();

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
    /// Hashed password (bcrypt or PBKDF2)
    /// Null if user only uses magic link authentication
    /// </summary>
    [Column("password_hash")]
    [MaxLength(500)]
    public string? PasswordHash { get; set; }

    /// <summary>
    /// User access level (0=ReadOnly, 1=User, 2=PowerUser, 3=Admin)
    /// </summary>
    [Required]
    [Column("access_level")]
    public AccessLevel AccessLevel { get; set; } = AccessLevel.User;

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
    /// Optional department/team for filtering
    /// </summary>
    [Column("department")]
    [MaxLength(100)]
    public string? Department { get; set; }

    /// <summary>
    /// Check if user has at least the specified access level
    /// </summary>
    public bool HasAccessLevel(AccessLevel requiredLevel) => AccessLevel >= requiredLevel;

    /// <summary>
    /// Check if user is an admin
    /// </summary>
    public bool IsAdmin => AccessLevel == AccessLevel.Admin;

    /// <summary>
    /// Check if user can access maintenance/configuration
    /// </summary>
    public bool CanAccessMaintenance => AccessLevel >= AccessLevel.PowerUser;

    /// <summary>
    /// Check if user can export data
    /// </summary>
    public bool CanExport => AccessLevel >= AccessLevel.PowerUser;

    /// <summary>
    /// Check if user can manage users
    /// </summary>
    public bool CanManageUsers => AccessLevel == AccessLevel.Admin;
}
