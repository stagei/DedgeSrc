using System.ComponentModel.DataAnnotations;
using System.ComponentModel.DataAnnotations.Schema;
using System.Text.Json;

namespace DedgeAuth.Core.Models;

/// <summary>
/// Hierarchical group node for organizing apps within a tenant.
/// Uses adjacency list (self-referential parent_id) for tree structure.
/// ACL groups control visibility per AD/Entra group membership with narrowing inheritance.
/// </summary>
[Table("app_groups")]
public class AppGroup
{
    [Key]
    [Column("id")]
    public Guid Id { get; set; } = Guid.NewGuid();

    [Required]
    [Column("tenant_id")]
    public Guid TenantId { get; set; }

    [ForeignKey("TenantId")]
    public Tenant Tenant { get; set; } = null!;

    [Required]
    [Column("name")]
    [MaxLength(200)]
    public string Name { get; set; } = string.Empty;

    /// <summary>
    /// URL-friendly identifier, unique within tenant.
    /// Used in deploy templates to reference groups by path (e.g. "infrastructure/monitoring").
    /// </summary>
    [Required]
    [Column("slug")]
    [MaxLength(100)]
    public string Slug { get; set; } = string.Empty;

    [Column("parent_id")]
    public Guid? ParentId { get; set; }

    [ForeignKey("ParentId")]
    public AppGroup? Parent { get; set; }

    [Column("sort_order")]
    public int SortOrder { get; set; } = 0;

    [Column("icon_url")]
    [MaxLength(500)]
    public string? IconUrl { get; set; }

    [Column("description")]
    [MaxLength(1000)]
    public string? Description { get; set; }

    /// <summary>
    /// JSON array of AD/Entra group names that can see this node.
    /// null = inherit from parent (or all authenticated users if root).
    /// Example: ["DEDGE\\ACL_ServerOps", "DEDGE\\ACL_DevTeam"]
    /// Narrowing inheritance: a child can only restrict, never broaden parent access.
    /// </summary>
    [Column("acl_groups_json")]
    public string? AclGroupsJson { get; set; }

    [Column("created_at")]
    public DateTime CreatedAt { get; set; } = DateTime.UtcNow;

    public ICollection<AppGroup> Children { get; set; } = new List<AppGroup>();
    public ICollection<AppGroupItem> Items { get; set; } = new List<AppGroupItem>();

    public List<string> GetAclGroups()
    {
        if (string.IsNullOrEmpty(AclGroupsJson))
            return new List<string>();

        try
        {
            return JsonSerializer.Deserialize<List<string>>(AclGroupsJson)
                   ?? new List<string>();
        }
        catch
        {
            return new List<string>();
        }
    }

    public void SetAclGroups(List<string> groups)
    {
        AclGroupsJson = groups.Count > 0 ? JsonSerializer.Serialize(groups) : null;
    }
}
