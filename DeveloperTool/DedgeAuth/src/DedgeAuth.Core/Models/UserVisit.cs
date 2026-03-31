using System.ComponentModel.DataAnnotations;
using System.ComponentModel.DataAnnotations.Schema;

namespace DedgeAuth.Core.Models;

/// <summary>
/// Records a user's visit to a consumer app.
/// Populated by DedgeAuthSessionValidationMiddleware on each cache-miss validation.
/// </summary>
[Table("user_visits")]
public class UserVisit
{
    [Key]
    [Column("id")]
    public Guid Id { get; set; } = Guid.NewGuid();

    [Required]
    [Column("user_id")]
    public Guid UserId { get; set; }

    [ForeignKey(nameof(UserId))]
    public User? User { get; set; }

    /// <summary>
    /// The consumer app's registered AppId (e.g. "DocView", "GenericLogHandler")
    /// </summary>
    [Required]
    [Column("app_id")]
    [MaxLength(100)]
    public string AppId { get; set; } = string.Empty;

    /// <summary>
    /// The request path within the app (e.g. "/documents/123")
    /// </summary>
    [Column("path")]
    [MaxLength(500)]
    public string? Path { get; set; }

    [Column("ip_address")]
    [MaxLength(50)]
    public string? IpAddress { get; set; }

    [Column("user_agent")]
    [MaxLength(500)]
    public string? UserAgent { get; set; }

    [Column("visited_at")]
    public DateTime VisitedAt { get; set; } = DateTime.UtcNow;
}
