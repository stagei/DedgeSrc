namespace DedgeAuth.Api.Options;

/// <summary>
/// Configuration options for theming
/// </summary>
public class ThemingOptions
{
    public const string SectionName = "Theming";
    
    /// <summary>
    /// System default CSS that applies when a tenant has no custom CSS configured
    /// </summary>
    public string SystemDefaultCss { get; set; } = string.Empty;
}
