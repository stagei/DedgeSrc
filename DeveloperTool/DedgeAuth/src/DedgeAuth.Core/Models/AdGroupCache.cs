using System.ComponentModel.DataAnnotations;
using System.ComponentModel.DataAnnotations.Schema;

namespace DedgeAuth.Core.Models;

/// <summary>
/// Cached Active Directory group entry, synced periodically from LDAP.
/// Used by admin UI to pick ACL groups without live LDAP queries per request.
/// </summary>
[Table("ad_groups_cache")]
public class AdGroupCache
{
    [Key]
    [Column("id")]
    public Guid Id { get; set; } = Guid.NewGuid();

    [Required]
    [Column("tenant_id")]
    public Guid TenantId { get; set; }

    [ForeignKey("TenantId")]
    public Tenant Tenant { get; set; } = null!;

    /// <summary>
    /// Full sAMAccountName (e.g. "ACL_Dedge_Servere_Utviklere")
    /// </summary>
    [Required]
    [Column("sam_account_name")]
    [MaxLength(256)]
    public string SamAccountName { get; set; } = string.Empty;

    /// <summary>
    /// Distinguished name for LDAP reference
    /// </summary>
    [Column("distinguished_name")]
    [MaxLength(1000)]
    public string? DistinguishedName { get; set; }

    /// <summary>
    /// Human-readable description from AD, if available
    /// </summary>
    [Column("description")]
    [MaxLength(500)]
    public string? Description { get; set; }

    /// <summary>
    /// AD group category (Security / Distribution)
    /// </summary>
    [Column("group_category")]
    [MaxLength(50)]
    public string? GroupCategory { get; set; }

    /// <summary>
    /// Number of direct members at last sync
    /// </summary>
    [Column("member_count")]
    public int MemberCount { get; set; }

    [Column("last_synced_at")]
    public DateTime LastSyncedAt { get; set; } = DateTime.UtcNow;
}
