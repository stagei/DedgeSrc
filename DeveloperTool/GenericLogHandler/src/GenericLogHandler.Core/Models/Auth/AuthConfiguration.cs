namespace GenericLogHandler.Core.Models.Auth;

/// <summary>
/// Authentication configuration settings
/// </summary>
public class AuthConfiguration
{
    /// <summary>
    /// JWT secret key for signing tokens
    /// </summary>
    public string JwtSecret { get; set; } = string.Empty;

    /// <summary>
    /// JWT issuer
    /// </summary>
    public string JwtIssuer { get; set; } = "GenericLogHandler";

    /// <summary>
    /// JWT audience
    /// </summary>
    public string JwtAudience { get; set; } = "GenericLogHandler";

    /// <summary>
    /// Access token expiration in minutes
    /// </summary>
    public int AccessTokenExpirationMinutes { get; set; } = 60;

    /// <summary>
    /// Refresh token expiration in days
    /// </summary>
    public int RefreshTokenExpirationDays { get; set; } = 7;

    /// <summary>
    /// Magic link token expiration in minutes
    /// </summary>
    public int MagicLinkExpirationMinutes { get; set; } = 15;

    /// <summary>
    /// Password reset token expiration in hours
    /// </summary>
    public int PasswordResetExpirationHours { get; set; } = 24;

    /// <summary>
    /// Maximum failed login attempts before lockout
    /// </summary>
    public int MaxFailedLoginAttempts { get; set; } = 5;

    /// <summary>
    /// Lockout duration in minutes
    /// </summary>
    public int LockoutDurationMinutes { get; set; } = 30;

    /// <summary>
    /// Base URL for email links (e.g., "https://loghandler.intranet.company.com")
    /// </summary>
    public string BaseUrl { get; set; } = string.Empty;

    /// <summary>
    /// Whether to allow password-based login (in addition to magic links)
    /// </summary>
    public bool AllowPasswordLogin { get; set; } = true;

    /// <summary>
    /// Whether to require email verification for new accounts
    /// </summary>
    public bool RequireEmailVerification { get; set; } = true;

    /// <summary>
    /// Minimum password length
    /// </summary>
    public int MinPasswordLength { get; set; } = 8;

    /// <summary>
    /// Require uppercase in password
    /// </summary>
    public bool RequireUppercase { get; set; } = true;

    /// <summary>
    /// Require digit in password
    /// </summary>
    public bool RequireDigit { get; set; } = true;

    /// <summary>
    /// Require special character in password
    /// </summary>
    public bool RequireSpecialChar { get; set; } = false;

    /// <summary>
    /// Allowed email domain for registration (e.g., "Dedge.no")
    /// </summary>
    public string AllowedDomain { get; set; } = string.Empty;

    /// <summary>
    /// List of admin email addresses - these users get Admin access level upon registration
    /// </summary>
    public List<string> AdminEmails { get; set; } = new();
}

/// <summary>
/// SMTP configuration for sending login emails
/// </summary>
public class SmtpConfiguration
{
    public string Host { get; set; } = string.Empty;
    public int Port { get; set; } = 587;
    public bool UseSsl { get; set; } = true;
    public string Username { get; set; } = string.Empty;
    public string Password { get; set; } = string.Empty;
    public string FromEmail { get; set; } = string.Empty;
    public string FromName { get; set; } = "Generic Log Handler";
}
