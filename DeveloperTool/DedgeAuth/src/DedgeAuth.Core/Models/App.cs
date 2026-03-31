using System.ComponentModel.DataAnnotations;
using System.ComponentModel.DataAnnotations.Schema;
using System.Text.Json;

namespace DedgeAuth.Core.Models;

/// <summary>
/// Registered application that uses DedgeAuth for authentication
/// </summary>
[Table("apps")]
public class App
{
    [Key]
    [Column("id")]
    public Guid Id { get; set; } = Guid.NewGuid();

    /// <summary>
    /// Unique application identifier (e.g., "GenericLogHandler", "ServerMonitorDashboard")
    /// </summary>
    [Required]
    [Column("app_id")]
    [MaxLength(100)]
    public string AppId { get; set; } = string.Empty;

    /// <summary>
    /// Display name for the application
    /// </summary>
    [Required]
    [Column("display_name")]
    [MaxLength(200)]
    public string DisplayName { get; set; } = string.Empty;

    /// <summary>
    /// Description of the application
    /// </summary>
    [Column("description")]
    [MaxLength(1000)]
    public string? Description { get; set; }

    /// <summary>
    /// Base URL for this application (e.g., "http://localhost:5000")
    /// </summary>
    [Column("base_url")]
    [MaxLength(500)]
    public string? BaseUrl { get; set; }

    /// <summary>
    /// Icon URL for this application (e.g., "/icons/app-log.svg")
    /// </summary>
    [Column("icon_url")]
    [MaxLength(500)]
    public string? IconUrl { get; set; }

    /// <summary>
    /// Available roles for this app as JSON array (e.g., ["Viewer", "Operator", "Admin"])
    /// </summary>
    [Column("available_roles_json")]
    public string? AvailableRolesJson { get; set; }

    /// <summary>
    /// Whether this application is active
    /// </summary>
    [Column("is_active")]
    public bool IsActive { get; set; } = true;

    /// <summary>
    /// App registration timestamp
    /// </summary>
    [Column("created_at")]
    public DateTime CreatedAt { get; set; } = DateTime.UtcNow;

    /// <summary>
    /// Permissions granted for this app
    /// </summary>
    public ICollection<AppPermission> Permissions { get; set; } = new List<AppPermission>();

    /// <summary>
    /// Get available roles as list
    /// </summary>
    public List<string> GetAvailableRoles()
    {
        if (string.IsNullOrEmpty(AvailableRolesJson))
            return new List<string> { "ReadOnly", "User", "PowerUser", "Admin" };
        
        try
        {
            return JsonSerializer.Deserialize<List<string>>(AvailableRolesJson) 
                   ?? new List<string>();
        }
        catch
        {
            return new List<string>();
        }
    }

    /// <summary>
    /// Set available roles from list
    /// </summary>
    public void SetAvailableRoles(List<string> roles)
    {
        AvailableRolesJson = JsonSerializer.Serialize(roles);
    }
}
