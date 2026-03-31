using System.ComponentModel.DataAnnotations;
using System.ComponentModel.DataAnnotations.Schema;
using System.Text.Json;

namespace DedgeAuth.Core.Models;

/// <summary>
/// Tenant configuration for multi-tenant branding and app routing
/// </summary>
[Table("tenants")]
public class Tenant
{
    [Key]
    [Column("id")]
    public Guid Id { get; set; } = Guid.NewGuid();

    /// <summary>
    /// Email domain for this tenant (e.g., "Dedge.no")
    /// </summary>
    [Required]
    [Column("domain")]
    [MaxLength(255)]
    public string Domain { get; set; } = string.Empty;

    /// <summary>
    /// Display name (e.g., "Dedge")
    /// </summary>
    [Required]
    [Column("display_name")]
    [MaxLength(200)]
    public string DisplayName { get; set; } = string.Empty;

    /// <summary>
    /// Optional external logo URL override. When set, clients use this URL directly
    /// instead of the /tenants/{domain}/logo endpoint. Leave null when logo is stored in database.
    /// </summary>
    [Column("logo_url")]
    [MaxLength(500)]
    public string? LogoUrl { get; set; }

    /// <summary>
    /// Logo image data stored in the database (SVG as UTF-8, or PNG/JPG binary).
    /// Served via GET /tenants/{domain}/logo endpoint.
    /// </summary>
    [Column("logo_data")]
    public byte[]? LogoData { get; set; }

    /// <summary>
    /// MIME type of the stored logo (e.g., "image/svg+xml", "image/png").
    /// </summary>
    [Column("logo_content_type")]
    [MaxLength(100)]
    public string? LogoContentType { get; set; }

    /// <summary>
    /// Favicon/icon image data stored in the database (ICO, PNG, or SVG binary).
    /// Served via GET /tenants/{domain}/icon endpoint.
    /// Used as the browser tab favicon for all DedgeAuth pages and consumer apps.
    /// </summary>
    [Column("icon_data")]
    public byte[]? IconData { get; set; }

    /// <summary>
    /// MIME type of the stored icon (e.g., "image/x-icon", "image/png").
    /// </summary>
    [Column("icon_content_type")]
    [MaxLength(100)]
    public string? IconContentType { get; set; }

    /// <summary>
    /// Primary color (e.g., "#008942")
    /// </summary>
    [Column("primary_color")]
    [MaxLength(20)]
    public string? PrimaryColor { get; set; }

    /// <summary>
    /// CSS overrides stored as full CSS text (injected into consumer apps via tenant theme endpoint)
    /// </summary>
    [Column("css_overrides")]
    public string? CssOverrides { get; set; }

    /// <summary>
    /// App routing configuration as JSON
    /// {"ServerMonitorDashboard": "http://dedge-server/ServerMonitorDashboard", "GenericLogHandler": "http://dedge-server/GenericLogHandler"}
    /// </summary>
    [Column("app_routing_json")]
    public string? AppRoutingJson { get; set; }

    /// <summary>
    /// Supported UI languages as JSON array (e.g. ["nb","en"])
    /// </summary>
    [Column("supported_languages_json")]
    [MaxLength(500)]
    public string? SupportedLanguagesJson { get; set; } = "[\"nb\",\"en\"]";

    /// <summary>
    /// NetBIOS AD domain name (e.g. "DEDGE") used for LDAP lookups and AD group sync.
    /// Combined with LdapSuffix config to form the LDAP path: LDAP://DEDGE.fk.no
    /// </summary>
    [Column("ad_domain")]
    [MaxLength(100)]
    public string? AdDomain { get; set; }

    /// <summary>
    /// Whether Windows/Kerberos SSO auto-registration and implicit app access is enabled for this tenant.
    /// When false, Windows-authenticated users are redirected to standard DedgeAuth registration.
    /// </summary>
    [Column("windows_sso_enabled")]
    public bool WindowsSsoEnabled { get; set; } = false;

    /// <summary>
    /// Whether this tenant is active
    /// </summary>
    [Column("is_active")]
    public bool IsActive { get; set; } = true;

    /// <summary>
    /// Tenant creation timestamp
    /// </summary>
    [Column("created_at")]
    public DateTime CreatedAt { get; set; } = DateTime.UtcNow;

    /// <summary>
    /// Users belonging to this tenant
    /// </summary>
    public ICollection<User> Users { get; set; } = new List<User>();

    /// <summary>
    /// Get app routing as dictionary
    /// </summary>
    public Dictionary<string, string> GetAppRouting()
    {
        if (string.IsNullOrEmpty(AppRoutingJson))
            return new Dictionary<string, string>();
        
        try
        {
            return JsonSerializer.Deserialize<Dictionary<string, string>>(AppRoutingJson) 
                   ?? new Dictionary<string, string>();
        }
        catch
        {
            return new Dictionary<string, string>();
        }
    }

    /// <summary>
    /// Set app routing from dictionary
    /// </summary>
    public void SetAppRouting(Dictionary<string, string> routing)
    {
        AppRoutingJson = JsonSerializer.Serialize(routing);
    }

    /// <summary>
    /// Get supported languages as list
    /// </summary>
    public List<string> GetSupportedLanguages()
    {
        if (string.IsNullOrEmpty(SupportedLanguagesJson))
            return new List<string> { "nb", "en" };

        try
        {
            return JsonSerializer.Deserialize<List<string>>(SupportedLanguagesJson)
                   ?? new List<string> { "nb", "en" };
        }
        catch
        {
            return new List<string> { "nb", "en" };
        }
    }

    /// <summary>
    /// Set supported languages from list
    /// </summary>
    public void SetSupportedLanguages(List<string> languages)
    {
        SupportedLanguagesJson = JsonSerializer.Serialize(languages);
    }
}
