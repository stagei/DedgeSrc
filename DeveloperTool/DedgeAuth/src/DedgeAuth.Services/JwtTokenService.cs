using System.IdentityModel.Tokens.Jwt;
using System.Security.Claims;
using System.Text;
using System.Text.Json;
using Microsoft.Extensions.Logging;
using Microsoft.Extensions.Options;
using Microsoft.IdentityModel.Tokens;
using DedgeAuth.Core.Models;

namespace DedgeAuth.Services;

/// <summary>
/// Service for generating and validating JWT tokens
/// </summary>
public class JwtTokenService
{
    private readonly AuthConfiguration _config;
    private readonly ILogger<JwtTokenService> _logger;

    public JwtTokenService(IOptions<AuthConfiguration> config, ILogger<JwtTokenService> logger)
    {
        _config = config.Value;
        _logger = logger;
    }

    /// <summary>
    /// Generate an access token for a user
    /// </summary>
    public string GenerateAccessToken(User user, Dictionary<string, string>? appRoles = null, Tenant? tenant = null, List<string>? adGroups = null)
    {
        _logger.LogDebug("Generating access token for user {UserId} ({Email})", user.Id, user.Email);

        if (string.IsNullOrEmpty(_config.JwtSecret))
        {
            _logger.LogError("JwtSecret is not configured - cannot generate token");
            throw new InvalidOperationException("JwtSecret is not configured");
        }

        _logger.LogDebug("JwtSecret length: {Length} chars, Issuer: {Issuer}, Audience: {Audience}", 
            _config.JwtSecret.Length, _config.JwtIssuer, _config.JwtAudience);

        var key = new SymmetricSecurityKey(Encoding.UTF8.GetBytes(_config.JwtSecret));
        var credentials = new SigningCredentials(key, SecurityAlgorithms.HmacSha256);

        var claims = new List<Claim>
        {
            new(JwtRegisteredClaimNames.Sub, user.Id.ToString()),
            new(JwtRegisteredClaimNames.Email, user.Email),
            new(JwtRegisteredClaimNames.Name, user.DisplayName),
            new("globalAccessLevel", ((int)user.GlobalAccessLevel).ToString()),
            new("globalAccessLevelName", user.GlobalAccessLevel.ToString())
        };

        claims.Add(new Claim("language", user.PreferredLanguage ?? "nb"));

        if (!string.IsNullOrEmpty(user.Department))
        {
            claims.Add(new Claim("department", user.Department));
            _logger.LogDebug("Added department claim: {Department}", user.Department);
        }

        // Add app permissions
        if (appRoles != null && appRoles.Count > 0)
        {
            claims.Add(new Claim("appPermissions", JsonSerializer.Serialize(appRoles)));
            _logger.LogDebug("Added {Count} app role claims: {Roles}", appRoles.Count, string.Join(", ", appRoles.Keys));
        }

        // Add AD group memberships for ACL-based app group visibility
        if (adGroups != null && adGroups.Count > 0)
        {
            claims.Add(new Claim("adGroups", JsonSerializer.Serialize(adGroups)));
            _logger.LogDebug("Added {Count} AD group claims to token", adGroups.Count);
        }

        // Add tenant info including app routing.
        // With auth code flow, JWT travels in cookies (not URLs), so size is not a URL concern.
        if (tenant != null)
        {
            var tenantInfo = new
            {
                id = tenant.Id,
                domain = tenant.Domain,
                displayName = tenant.DisplayName,
                primaryColor = tenant.PrimaryColor,
                appRouting = tenant.GetAppRouting(),
                supportedLanguages = tenant.GetSupportedLanguages()
            };
            claims.Add(new Claim("tenant", JsonSerializer.Serialize(tenantInfo)));
            _logger.LogDebug("Added tenant claim: {TenantDomain} with {RouteCount} app routes", 
                tenant.Domain, tenant.GetAppRouting().Count);
        }

        var expiresAt = DateTime.UtcNow.AddMinutes(_config.AccessTokenExpirationMinutes);
        _logger.LogDebug("Token will expire at {ExpiresAt} ({Minutes} minutes from now)", 
            expiresAt, _config.AccessTokenExpirationMinutes);

        var token = new JwtSecurityToken(
            issuer: _config.JwtIssuer,
            audience: _config.JwtAudience,
            claims: claims,
            expires: expiresAt,
            signingCredentials: credentials
        );

        var tokenString = new JwtSecurityTokenHandler().WriteToken(token);
        _logger.LogInformation("Access token generated for user {UserId} ({Email}), expires at {ExpiresAt}", 
            user.Id, user.Email, expiresAt);

        return tokenString;
    }

    /// <summary>
    /// Validate a token and return the claims principal
    /// </summary>
    public ClaimsPrincipal? ValidateToken(string token)
    {
        _logger.LogDebug("Validating JWT token (length: {Length})", token?.Length ?? 0);

        var tokenHandler = new JwtSecurityTokenHandler();
        var key = Encoding.UTF8.GetBytes(_config.JwtSecret);

        try
        {
            var principal = tokenHandler.ValidateToken(token, new TokenValidationParameters
            {
                ValidateIssuerSigningKey = true,
                IssuerSigningKey = new SymmetricSecurityKey(key),
                ValidateIssuer = true,
                ValidIssuer = _config.JwtIssuer,
                ValidateAudience = true,
                ValidAudience = _config.JwtAudience,
                ValidateLifetime = true,
                ClockSkew = TimeSpan.FromMinutes(5)
            }, out var validatedToken);

            var userId = principal.FindFirst(JwtRegisteredClaimNames.Sub)?.Value;
            var email = principal.FindFirst(JwtRegisteredClaimNames.Email)?.Value;
            _logger.LogDebug("Token validated successfully for user {UserId} ({Email})", userId, email);

            return principal;
        }
        catch (SecurityTokenExpiredException ex)
        {
            _logger.LogWarning("Token validation failed: token expired at {Expired}", ex.Expires);
            return null;
        }
        catch (SecurityTokenException ex)
        {
            _logger.LogWarning("Token validation failed: {Message}", ex.Message);
            return null;
        }
        catch (Exception ex)
        {
            _logger.LogError(ex, "Token validation failed with unexpected error");
            return null;
        }
    }
}
