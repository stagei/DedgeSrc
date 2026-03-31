namespace DedgeAuth.Services;

/// <summary>
/// Result of an authentication operation
/// </summary>
public class AuthResult
{
    public bool Success { get; set; }
    public string? Message { get; set; }
    public string? AccessToken { get; set; }
    public string? RefreshToken { get; set; }
    public DateTime? ExpiresAt { get; set; }
    public UserInfo? User { get; set; }
    public string? RedirectUrl { get; set; }

    // 20260317 GHS Test Ad/Entra Start -->
    /// <summary>True when Windows auth succeeded but the tenant has WindowsSsoEnabled = false.</summary>
    public bool SsoDisabled { get; set; }
    /// <summary>AD email resolved from Windows identity (returned in ssoDisabled responses).</summary>
    public string? SsoEmail { get; set; }
    /// <summary>AD display name resolved from Windows identity (returned in ssoDisabled responses).</summary>
    public string? SsoDisplayName { get; set; }
    /// <summary>True when the user was auto-created during this login (for welcome email trigger).</summary>
    public bool IsNewUser { get; set; }
    // <--20260317 GHS Test Ad/Entra End

    public static AuthResult Successful(string accessToken, string? refreshToken = null, DateTime? expiresAt = null, UserInfo? user = null, bool isNewUser = false)
    {
        return new AuthResult
        {
            Success = true,
            AccessToken = accessToken,
            RefreshToken = refreshToken,
            ExpiresAt = expiresAt,
            User = user,
            IsNewUser = isNewUser
        };
    }

    public static AuthResult Failed(string message)
    {
        return new AuthResult
        {
            Success = false,
            Message = message
        };
    }

    // 20260317 GHS Test Ad/Entra Start -->
    public static AuthResult SsoNotEnabled(string email, string displayName)
    {
        return new AuthResult
        {
            Success = false,
            SsoDisabled = true,
            SsoEmail = email,
            SsoDisplayName = displayName,
            Message = "Windows SSO is not enabled for your tenant. Please register with a password."
        };
    }
    // <--20260317 GHS Test Ad/Entra End
}

/// <summary>
/// User information returned in auth result
/// </summary>
public class UserInfo
{
    public Guid Id { get; set; }
    public string Email { get; set; } = string.Empty;
    public string DisplayName { get; set; } = string.Empty;
    public int GlobalAccessLevel { get; set; }
    public string? Department { get; set; }
    // 20260317 GHS Test Ad/Entra Start -->
    public string? AuthMethod { get; set; }
    // <--20260317 GHS Test Ad/Entra End
    public Dictionary<string, string> AppRoles { get; set; } = new();
    public TenantInfo? Tenant { get; set; }
}

/// <summary>
/// Tenant information returned in auth result
/// </summary>
public class TenantInfo
{
    public Guid Id { get; set; }
    public string Domain { get; set; } = string.Empty;
    public string DisplayName { get; set; } = string.Empty;
    public string? PrimaryColor { get; set; }
    /// <summary>
    /// External logo URL override (null when logo is stored in database).
    /// Consumers should use /tenants/{domain}/logo endpoint when this is null and HasLogoData is true.
    /// </summary>
    public string? LogoUrl { get; set; }
    /// <summary>
    /// Whether this tenant has logo data stored in the database.
    /// </summary>
    public bool HasLogoData { get; set; }
    public Dictionary<string, string> AppRouting { get; set; } = new();
}

/// <summary>
/// User session (active token) information
/// </summary>
public class UserSession
{
    public Guid TokenId { get; set; }
    public DateTime CreatedAt { get; set; }
    public DateTime ExpiresAt { get; set; }
    public string? IpAddress { get; set; }
    public string? UserAgent { get; set; }
}
