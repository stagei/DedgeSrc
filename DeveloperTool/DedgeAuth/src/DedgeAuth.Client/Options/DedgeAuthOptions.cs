using Microsoft.AspNetCore.Http;

namespace DedgeAuth.Client.Options;

/// <summary>
/// Configuration options for DedgeAuth client
/// </summary>
public class DedgeAuthOptions
{
    /// <summary>
    /// Derives the browser-facing DedgeAuth URL from the incoming HTTP request.
    /// When AuthServerUrl is server-agnostic (localhost, default port), the path
    /// (e.g. /DedgeAuth) is extracted from the config and combined with the request's
    /// scheme + host so the browser always gets a reachable URL.
    /// For non-default ports (e.g. Kestrel dev on :8100), returns AuthServerUrl as-is.
    /// </summary>
    public string GetClientFacingAuthUrl(HttpContext context)
    {
        var authUri = new Uri(AuthServerUrl);
        if ((authUri.Host is "localhost" or "127.0.0.1") && authUri.IsDefaultPort)
        {
            return $"{context.Request.Scheme}://{context.Request.Host}{authUri.AbsolutePath.TrimEnd('/')}";
        }
        return AuthServerUrl.TrimEnd('/');
    }

    /// <summary>
    /// Master switch to enable/disable DedgeAuth authentication.
    /// When false, all DedgeAuth middleware (token extraction, redirect, session validation) is skipped.
    /// </summary>
    public bool Enabled { get; set; } = true;

    /// <summary>
    /// DedgeAuth API base URL (e.g., "http://localhost:8100")
    /// </summary>
    public string AuthServerUrl { get; set; } = "http://localhost:8100";

    /// <summary>
    /// JWT secret key (must match DedgeAuth server)
    /// </summary>
    public string JwtSecret { get; set; } = string.Empty;

    /// <summary>
    /// JWT issuer (must match DedgeAuth server)
    /// </summary>
    public string JwtIssuer { get; set; } = "DedgeAuth";

    /// <summary>
    /// JWT audience (must match DedgeAuth server)
    /// </summary>
    public string JwtAudience { get; set; } = "FKApps";

    /// <summary>
    /// Application ID for this app (e.g., "GenericLogHandler")
    /// </summary>
    public string AppId { get; set; } = string.Empty;

    /// <summary>
    /// Cookie name for storing access token (optional)
    /// </summary>
    public string? AccessTokenCookieName { get; set; }

    /// <summary>
    /// Allow unauthenticated requests to fallback pages
    /// </summary>
    public string LoginPath { get; set; } = "/login";

    /// <summary>
    /// Default role mapping if user has no app-specific role.
    /// Maps global access level (0-3) to app role name.
    /// By default, this is EMPTY (no fallback) - apps must grant explicit permissions.
    /// Configure this only if you want users to get automatic app access based on their global level.
    /// Example: { "0": "ReadOnly", "1": "User", "2": "PowerUser", "3": "Admin" }
    /// </summary>
    public Dictionary<int, string> GlobalLevelToAppRole { get; set; } = new();

    /// <summary>
    /// Cache duration (in seconds) for session validation results.
    /// After a successful validation, the result is cached for this duration before re-checking with DedgeAuth.
    /// Default: 30 seconds.
    /// </summary>
    public int SessionValidationCacheTtlSeconds { get; set; } = 30;

    /// <summary>
    /// Route prefix for the DedgeAuth proxy endpoints (/me and /logout).
    /// Default: "/api/DedgeAuth"
    /// </summary>
    public string ProxyRoutePrefix { get; set; } = "/api/DedgeAuth";

    /// <summary>
    /// Path prefixes that should skip redirect and session validation middleware.
    /// Requests to these paths will not be redirected to login or session-validated.
    /// Default: ["/api/", "/scalar", "/health"]
    /// </summary>
    public string[] SkipPathPrefixes { get; set; } = ["/api/", "/scalar", "/health"];
}
