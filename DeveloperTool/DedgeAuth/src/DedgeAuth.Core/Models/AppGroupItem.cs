using System.ComponentModel.DataAnnotations;
using System.ComponentModel.DataAnnotations.Schema;

namespace DedgeAuth.Core.Models;

/// <summary>
/// Join table linking apps to groups (many-to-many).
/// An app can appear in multiple groups across different tenants.
/// </summary>
[Table("app_group_items")]
public class AppGroupItem
{
    [Key]
    [Column("id")]
    public Guid Id { get; set; } = Guid.NewGuid();

    [Required]
    [Column("app_group_id")]
    public Guid AppGroupId { get; set; }

    [ForeignKey("AppGroupId")]
    public AppGroup AppGroup { get; set; } = null!;

    [Required]
    [Column("app_id")]
    public Guid AppId { get; set; }

    [ForeignKey("AppId")]
    public App App { get; set; } = null!;

    [Column("sort_order")]
    public int SortOrder { get; set; } = 0;
}
