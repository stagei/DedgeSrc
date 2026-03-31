using System.ComponentModel.DataAnnotations;
using System.ComponentModel.DataAnnotations.Schema;

namespace GenericLogHandler.Core.Models.Auth;

/// <summary>
/// Magic link login token sent via email
/// </summary>
[Table("login_tokens")]
public class LoginToken
{
    [Key]
    [Column("id")]
    public Guid Id { get; set; } = Guid.NewGuid();

    /// <summary>
    /// The unique token sent in the email link
    /// </summary>
    [Required]
    [Column("token")]
    [MaxLength(100)]
    public string Token { get; set; } = string.Empty;

    /// <summary>
    /// Associated user ID
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
    /// Token type (Login, PasswordReset, EmailVerification)
    /// </summary>
    [Required]
    [Column("token_type")]
    [MaxLength(50)]
    public string TokenType { get; set; } = TokenTypes.Login;

    /// <summary>
    /// Token creation timestamp
    /// </summary>
    [Column("created_at")]
    public DateTime CreatedAt { get; set; } = DateTime.UtcNow;

    /// <summary>
    /// Token expiration timestamp
    /// </summary>
    [Required]
    [Column("expires_at")]
    public DateTime ExpiresAt { get; set; }

    /// <summary>
    /// Whether this token has been used
    /// </summary>
    [Column("is_used")]
    public bool IsUsed { get; set; } = false;

    /// <summary>
    /// When the token was used
    /// </summary>
    [Column("used_at")]
    public DateTime? UsedAt { get; set; }

    /// <summary>
    /// IP address that requested this token
    /// </summary>
    [Column("request_ip")]
    [MaxLength(50)]
    public string? RequestIp { get; set; }

    /// <summary>
    /// IP address that used this token
    /// </summary>
    [Column("used_ip")]
    [MaxLength(50)]
    public string? UsedIp { get; set; }

    /// <summary>
    /// Check if token is still valid
    /// </summary>
    public bool IsValid => !IsUsed && DateTime.UtcNow < ExpiresAt;
}

/// <summary>
/// Token type constants
/// </summary>
public static class TokenTypes
{
    public const string Login = "Login";
    public const string PasswordReset = "PasswordReset";
    public const string EmailVerification = "EmailVerification";
}
