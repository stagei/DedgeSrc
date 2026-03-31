using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Mvc;
using Microsoft.AspNetCore.RateLimiting;
using Microsoft.EntityFrameworkCore;

using System.DirectoryServices;
using System.Security.Claims;
using Microsoft.Extensions.Options;
using DedgeAuth.Core.Models;
using DedgeAuth.Data;
using DedgeAuth.Services;

namespace DedgeAuth.Api.Controllers;

/// <summary>
/// Authentication controller
/// </summary>
[ApiController]
[Route("api/[controller]")]
public class AuthController : ControllerBase
{
    private readonly AuthService _authService;
    private readonly AuthDbContext _context;
    private readonly ILogger<AuthController> _logger;
    private readonly AuthConfiguration _config;
    // 20260317 GHS Test Ad/Entra Start -->
    private readonly EmailService _emailService;
    // <--20260317 GHS Test Ad/Entra End

    public AuthController(AuthService authService, AuthDbContext context, ILogger<AuthController> logger, EmailService emailService, IOptions<AuthConfiguration> config)
    {
        _authService = authService;
        _context = context;
        _logger = logger;
        _config = config.Value;
        // 20260317 GHS Test Ad/Entra Start -->
        _emailService = emailService;
        // <--20260317 GHS Test Ad/Entra End
    }

    /// <summary>
    /// Register a new user
    /// </summary>
    [HttpPost("register")]
    [AllowAnonymous]
    public async Task<IActionResult> Register([FromBody] RegisterRequest request)
    {
        _logger.LogDebug("POST /api/auth/register - Email: {Email}, DisplayName: {DisplayName}", 
            request.Email, request.DisplayName);

        var (success, message, user) = await _authService.RegisterAsync(
            request.Email, 
            request.DisplayName, 
            request.Password);

        if (!success)
        {
            _logger.LogWarning("Registration failed for {Email}: {Message}", request.Email, message);
            return BadRequest(new { success = false, message });
        }

        // Create access requests for any requested apps
        if (user != null && request.AppRequests?.Count > 0)
        {
            foreach (var appReq in request.AppRequests)
            {
                var app = await _context.Apps.FirstOrDefaultAsync(a => a.AppId == appReq.AppId);
                if (app != null)
                {
                    _context.AccessRequests.Add(new DedgeAuth.Core.Models.AccessRequest
                    {
                        UserId = user.Id,
                        AppId = app.Id,
                        RequestType = DedgeAuth.Core.Models.AccessRequest.TypeAppAccess,
                        RequestedRole = appReq.Role,
                        Reason = appReq.Reason
                    });
                }
            }
            await _context.SaveChangesAsync();
            _logger.LogInformation("Created {Count} access request(s) for new user {Email}",
                request.AppRequests.Count, request.Email);
        }

        _logger.LogInformation("Registration successful for {Email}, UserId: {UserId}", request.Email, user?.Id);
        return Ok(new { success = true, message, userId = user?.Id });
    }

    /// <summary>
    /// Login with password
    /// </summary>
    [HttpPost("login")]
    [AllowAnonymous]
    [EnableRateLimiting("login")] // Apply stricter rate limiting to login
    public async Task<IActionResult> Login([FromBody] LoginRequest request)
    {
        var ipAddress = GetIpAddress();
        _logger.LogDebug("POST /api/auth/login - Email: {Email}, IP: {IpAddress}", request.Email, ipAddress);

        var result = await _authService.LoginWithPasswordAsync(request.Email, request.Password, ipAddress, rememberMe: request.RememberMe);

        if (!result.Success)
        {
            _logger.LogWarning("Login failed for {Email}: {Message}", request.Email, result.Message);
            return Unauthorized(new { success = false, message = result.Message });
        }

        // Set refresh token as HTTP-only cookie
        SetRefreshTokenCookie(result.RefreshToken!, request.RememberMe);
        _logger.LogDebug("Refresh token cookie set for {Email} (rememberMe={RememberMe})", request.Email, request.RememberMe);

        // Create a short auth code for redirect-based SSO (consumer apps exchange this for a JWT)
        var authCode = await _authService.CreateAuthCodeAsync(result.User!.Id, ipAddress);

        if (result.IsNewUser)
        {
            _logger.LogInformation("New user auto-provisioned via password login: {Email} ({UserId}), pending admin confirmation",
                request.Email, result.User.Id);
        }

        _logger.LogInformation("Login successful for {Email} (isNewUser={IsNew})", request.Email, result.IsNewUser);
        return Ok(new LoginResponse(
            Success: true,
            AccessToken: result.AccessToken!,
            AuthCode: authCode,
            ExpiresAt: result.ExpiresAt,
            User: result.User,
            IsNewUser: result.IsNewUser));
    }

    // 20260317 GHS Test Ad/Entra Start -->
    /// <summary>
    /// Silent probe for Windows/Kerberos credentials. AllowAnonymous so no 401 challenge
    /// is sent — if the browser has a Kerberos ticket configured, it will be passed through
    /// automatically; otherwise the request arrives as anonymous and we return success=false.
    /// Used by the auto-login attempt on page load to avoid triggering a Windows Security prompt.
    /// </summary>
    [HttpGet("windows-probe")]
    [AllowAnonymous]
    public async Task<IActionResult> WindowsProbe()
    {
        var windowsIdentity = HttpContext.User.Identity;
        if (windowsIdentity == null || !windowsIdentity.IsAuthenticated)
        {
            return Ok(new { success = false, windowsAuthAvailable = false });
        }

        return await HandleWindowsLoginCoreAsync();
    }

    /// <summary>
    /// Create a fresh short-lived auth code for an already-authenticated user.
    /// Used by the login page to generate per-app-click codes so each consumer
    /// app receives its own unused code for the auth-code exchange flow.
    /// </summary>
    [HttpPost("create-code")]
    [Authorize]
    public async Task<IActionResult> CreateCode()
    {
        var userId = User.FindFirstValue(ClaimTypes.NameIdentifier);
        if (userId == null || !Guid.TryParse(userId, out var uid))
            return Unauthorized(new { success = false, message = "Not authenticated." });

        var ipAddress = GetIpAddress();
        var code = await _authService.CreateAuthCodeAsync(uid, ipAddress);
        return Ok(new { code });
    }

    /// <summary>
    /// Server-side redirect: generates a fresh auth code and 302-redirects the browser
    /// to the consumer app with ?code=. Works even if the client-side JWT has expired
    /// because it falls back to the refresh token cookie.
    /// </summary>
    [HttpGet("redirect")]
    [AllowAnonymous]
    public async Task<IActionResult> RedirectWithCode([FromQuery] string returnUrl)
    {
        if (string.IsNullOrEmpty(returnUrl))
            return BadRequest(new { message = "returnUrl is required." });

        var ipAddress = GetIpAddress();
        var pathBase = Request.PathBase.HasValue ? Request.PathBase.Value : "";

        // Try multiple auth sources in order of preference
        Guid uid;
        var authenticated = false;

        // 1. Try ASP.NET Core identity (JWT from Authorization header)
        var userId = User.FindFirstValue(ClaimTypes.NameIdentifier);
        if (userId != null && Guid.TryParse(userId, out uid))
        {
            _logger.LogDebug("Redirect: using JWT identity for {UserId}", uid);
            authenticated = true;
        }
        // 2. Try the DedgeAuth_jwt cookie set by login.html JavaScript
        else if (!string.IsNullOrEmpty(Request.Cookies["DedgeAuth_jwt"]))
        {
            uid = default;
            var jwtCookie = Request.Cookies["DedgeAuth_jwt"]!;
            try
            {
                var parts = jwtCookie.Split('.');
                if (parts.Length == 3)
                {
                    var payload = parts[1];
                    payload = payload.Replace('-', '+').Replace('_', '/');
                    switch (payload.Length % 4) { case 2: payload += "=="; break; case 3: payload += "="; break; }
                    var json = System.Text.Encoding.UTF8.GetString(Convert.FromBase64String(payload));
                    var claims = System.Text.Json.JsonDocument.Parse(json);
                    var sub = claims.RootElement.TryGetProperty("http://schemas.xmlsoap.org/ws/2005/05/identity/claims/nameidentifier", out var subProp)
                        ? subProp.GetString()
                        : (claims.RootElement.TryGetProperty("sub", out var subAlt) ? subAlt.GetString() : null);
                    var exp = claims.RootElement.TryGetProperty("exp", out var expProp) ? expProp.GetInt64() : 0;
                    var expTime = DateTimeOffset.FromUnixTimeSeconds(exp).UtcDateTime;

                    if (sub != null && Guid.TryParse(sub, out uid) && expTime > DateTime.UtcNow)
                    {
                        _logger.LogDebug("Redirect: using DedgeAuth_jwt cookie for {UserId}", uid);
                        authenticated = true;
                    }
                }
            }
            catch (Exception ex)
            {
                _logger.LogWarning(ex, "Redirect: failed to parse DedgeAuth_jwt cookie");
            }
        }
        // 3. Fall back to refresh token cookie
        else
        {
            uid = default;
            var refreshToken = Request.Cookies["refreshToken"];
            if (!string.IsNullOrEmpty(refreshToken))
            {
                var validatedUserId = await _authService.ValidateRefreshTokenUserAsync(refreshToken);
                if (validatedUserId != null)
                {
                    uid = validatedUserId.Value;
                    _logger.LogDebug("Redirect: validated refresh token for {UserId}", uid);
                    authenticated = true;
                }
            }
        }

        if (!authenticated)
        {
            _logger.LogDebug("Redirect: no valid auth found, redirecting to login");
            return Redirect($"{pathBase}/login.html?returnUrl={Uri.EscapeDataString(returnUrl)}");
        }

        var code = await _authService.CreateAuthCodeAsync(uid, ipAddress);
        var separator = returnUrl.Contains('?') ? '&' : '?';
        var targetUrl = $"{returnUrl}{separator}code={code}";
        _logger.LogInformation("Redirect: sending user {UserId} to {TargetUrl}", uid, returnUrl);
        return Redirect(targetUrl);
    }

    /// <summary>
    /// Login with Windows/AD credentials (Negotiate/Kerberos).
    /// Any authenticated DEDGE domain user is allowed; app-level visibility
    /// is controlled by app_groups.acl_groups_json per tenant.
    /// Uses [Authorize] to force a 401 Negotiate challenge.
    /// </summary>
    [HttpGet("windows-login")]
    [Authorize(Policy = "WindowsAuth")]
    public async Task<IActionResult> WindowsLogin()
    {
        return await HandleWindowsLoginCoreAsync();
    }

    private async Task<IActionResult> HandleWindowsLoginCoreAsync()
    {
        var windowsIdentity = HttpContext.User.Identity;
        if (windowsIdentity == null || !windowsIdentity.IsAuthenticated)
        {
            _logger.LogWarning("Windows login failed - no authenticated identity");
            return Unauthorized(new { success = false, message = "Windows authentication failed." });
        }

        var windowsName = windowsIdentity.Name ?? "unknown";
        _logger.LogInformation("Windows login attempt for {WindowsName}", windowsName);

        // Collect AD group memberships from Kerberos claims for ACL-based app group visibility
        var adGroups = HttpContext.User.Claims
            .Where(c => c.Type == ClaimTypes.Role || c.Type == ClaimTypes.GroupSid ||
                        c.Type == "http://schemas.microsoft.com/ws/2008/06/identity/claims/role")
            .Select(c => c.Value)
            .Distinct()
            .ToList();
        _logger.LogDebug("Windows identity has {GroupCount} AD group claims", adGroups.Count);

        // Look up real email and display name from Active Directory via LDAP DirectorySearcher
        string? adEmail = null;
        string? adDisplayName = null;
        var samAccountName = windowsName.Contains('\\')
            ? windowsName.Split('\\')[1]
            : windowsName;
        try
        {
#pragma warning disable CA1416 // Windows-only API; this app exclusively runs on Windows Server / IIS
            using var entry = new DirectoryEntry("LDAP://DEDGE.fk.no");
            using var searcher = new DirectorySearcher(entry)
            {
                Filter = $"(&(objectCategory=person)(objectClass=user)(sAMAccountName={samAccountName}))"
            };
            searcher.PropertiesToLoad.AddRange(["mail", "displayName", "userPrincipalName", "memberOf"]);
            var adResult = searcher.FindOne();
            if (adResult != null)
            {
                adEmail = adResult.Properties["mail"]?.Count > 0
                    ? adResult.Properties["mail"][0]?.ToString()
                    : null;
                adEmail ??= adResult.Properties["userPrincipalName"]?.Count > 0
                    ? adResult.Properties["userPrincipalName"][0]?.ToString()
                    : null;
                adDisplayName = adResult.Properties["displayName"]?.Count > 0
                    ? adResult.Properties["displayName"][0]?.ToString()
                    : null;

                // Supplement group list with LDAP memberOf (contains friendly CN names)
                if (adResult.Properties["memberOf"]?.Count > 0)
                {
                    foreach (var dn in adResult.Properties["memberOf"])
                    {
                        var dnStr = dn?.ToString();
                        if (dnStr != null && dnStr.StartsWith("CN=", StringComparison.OrdinalIgnoreCase))
                        {
                            var cn = dnStr.Split(',')[0][3..];
                            var fqGroup = $@"DEDGE\{cn}";
                            if (!adGroups.Contains(fqGroup, StringComparer.OrdinalIgnoreCase))
                                adGroups.Add(fqGroup);
                        }
                    }
                }
#pragma warning restore CA1416
                _logger.LogInformation("AD lookup for {SamAccountName}: email={Email}, displayName={DisplayName}, groups={GroupCount}",
                    samAccountName, adEmail ?? "(none)", adDisplayName ?? "(none)", adGroups.Count);
            }
            else
            {
                _logger.LogWarning("AD user not found for {SamAccountName}, falling back to constructed email", samAccountName);
            }
        }
        catch (Exception ex)
        {
            _logger.LogWarning(ex, "AD lookup failed for {SamAccountName}, falling back to constructed email",
                samAccountName);
        }

        var ipAddress = GetIpAddress();
        var result = await _authService.LoginWithWindowsAsync(windowsName, ipAddress, adEmail, adDisplayName, adGroups);

        if (result.SsoDisabled)
        {
            _logger.LogInformation("Windows SSO disabled for tenant — returning ssoDisabled for {Email}", result.SsoEmail);
            return Ok(new { success = false, ssoDisabled = true, email = result.SsoEmail, displayName = result.SsoDisplayName, message = result.Message });
        }

        if (!result.Success)
        {
            _logger.LogWarning("Windows login failed for {WindowsName}: {Message}", windowsName, result.Message);
            return Unauthorized(new { success = false, message = result.Message });
        }

        SetRefreshTokenCookie(result.RefreshToken!);
        var authCode = await _authService.CreateAuthCodeAsync(result.User!.Id, ipAddress);

        // Fire-and-forget welcome email for newly auto-registered Windows users
        if (result.IsNewUser)
        {
            var baseUrl = $"{Request.Scheme}://{Request.Host}{Request.PathBase}";
            var profileUrl = $"{baseUrl}/profile.html";
            var tenant = result.User.Tenant != null
                ? await _context.Tenants.FindAsync(Guid.Parse(result.User.Tenant.Id.ToString()))
                : null;
            _ = Task.Run(async () =>
            {
                try { await _emailService.SendWindowsWelcomeEmailAsync(result.User.Email, result.User.DisplayName, profileUrl, tenant, baseUrl); }
                catch (Exception ex) { _logger.LogWarning(ex, "Failed to send Windows welcome email to {Email}", result.User.Email); }
            });
        }

        _logger.LogInformation("Windows login successful for {WindowsName} -> {Email} (isNewUser={IsNew})", windowsName, result.User.Email, result.IsNewUser);
        return Ok(new LoginResponse(
            Success: true,
            AccessToken: result.AccessToken!,
            AuthCode: authCode,
            ExpiresAt: result.ExpiresAt,
            User: result.User,
            IsNewUser: result.IsNewUser));
    }
    // <--20260317 GHS Test Ad/Entra End

    /// <summary>
    /// Request a magic link
    /// </summary>
    [HttpPost("request-login")]
    [AllowAnonymous]
    public async Task<IActionResult> RequestMagicLink([FromBody] MagicLinkRequest request)
    {
        var ipAddress = GetIpAddress();
        _logger.LogDebug("POST /api/auth/request-login - Email: {Email}, IP: {IpAddress}", request.Email, ipAddress);

        var requestBaseUrl = GetRequestBaseUrl();
        var (success, message) = await _authService.RequestMagicLinkAsync(request.Email, ipAddress, requestBaseUrl);

        _logger.LogDebug("Magic link request completed for {Email}, success: {Success}", request.Email, success);
        return Ok(new { success, message });
    }

    /// <summary>
    /// Verify magic link and login
    /// </summary>
    [HttpGet("verify")]
    [AllowAnonymous]
    public async Task<IActionResult> VerifyMagicLink([FromQuery] string? token, [FromQuery] string? returnUrl = null)
    {
        var ipAddress = GetIpAddress();
        _logger.LogDebug("GET /api/auth/verify - Token length: {TokenLength}, ReturnUrl: {ReturnUrl}, IP: {IpAddress}", 
            token?.Length ?? 0, returnUrl ?? "(none)", ipAddress);

        var pathBase = Request.PathBase.Value?.TrimEnd('/') ?? "";

        if (string.IsNullOrEmpty(token))
        {
            _logger.LogWarning("Magic link verification failed - no token provided");
            var errorUrl = $"{pathBase}/login.html?error={Uri.EscapeDataString("Invalid or missing token")}";
            return Redirect(errorUrl);
        }

        var result = await _authService.VerifyMagicLinkAsync(token, ipAddress);

        if (!result.Success)
        {
            _logger.LogWarning("Magic link verification failed: {Message}", result.Message);
            var errorUrl = $"{pathBase}/login.html?error={Uri.EscapeDataString(result.Message ?? "Invalid token")}";
            _logger.LogDebug("Redirecting to error page: {Url}", errorUrl);
            return Redirect(errorUrl);
        }

        // Set refresh token as HTTP-only cookie
        SetRefreshTokenCookie(result.RefreshToken!);
        _logger.LogDebug("Refresh token cookie set");

        // Create a short auth code instead of passing the full JWT in the URL.
        // Consumer apps exchange this code server-to-server for the actual JWT.
        var userId = result.User!.Id;
        var authCode = await _authService.CreateAuthCodeAsync(userId, ipAddress);

        // Redirect to return URL with short code, or to login page with success indicator
        if (!string.IsNullOrEmpty(returnUrl) && returnUrl != "/")
        {
            var separator = returnUrl.Contains('?') ? "&" : "?";
            var finalUrl = $"{returnUrl}{separator}code={authCode}";
            _logger.LogInformation("Magic link verification successful, redirecting to: {Url} with auth code", returnUrl);
            return Redirect(finalUrl);
        }
        else
        {
            // No return URL - redirect to login page with success and token (direct JWT is fine here, same origin)
            var successUrl = $"{pathBase}/login.html?success=true&token={result.AccessToken}";
            _logger.LogInformation("Magic link verification successful, redirecting to login page with token");
            return Redirect(successUrl);
        }
    }

    /// <summary>
    /// Exchange a short-lived auth code for a JWT.
    /// Called server-to-server by consumer apps after redirect.
    /// </summary>
    [HttpPost("exchange")]
    [AllowAnonymous]
    public async Task<IActionResult> ExchangeAuthCode([FromBody] AuthCodeExchangeRequest request)
    {
        var ipAddress = GetIpAddress();
        _logger.LogDebug("POST /api/auth/exchange - Code length: {CodeLength}, IP: {IpAddress}",
            request.Code?.Length ?? 0, ipAddress);

        if (string.IsNullOrEmpty(request.Code))
        {
            return BadRequest(new { success = false, message = "Auth code is required" });
        }

        var result = await _authService.ExchangeAuthCodeAsync(request.Code, ipAddress);

        if (!result.Success)
        {
            _logger.LogWarning("Auth code exchange failed: {Message}", result.Message);
            return Unauthorized(new { success = false, message = result.Message });
        }

        _logger.LogInformation("Auth code exchange successful");
        return Ok(new
        {
            success = true,
            accessToken = result.AccessToken,
            expiresAt = result.ExpiresAt,
            user = result.User
        });
    }

    /// <summary>
    /// Refresh access token
    /// </summary>
    [HttpPost("refresh")]
    [AllowAnonymous]
    public async Task<IActionResult> RefreshToken()
    {
        var ipAddress = GetIpAddress();
        _logger.LogDebug("POST /api/auth/refresh - IP: {IpAddress}", ipAddress);

        var refreshToken = Request.Cookies["refreshToken"];
        if (string.IsNullOrEmpty(refreshToken))
        {
            _logger.LogWarning("Token refresh failed - no refresh token cookie present");
            return Unauthorized(new { success = false, message = "No refresh token" });
        }

        _logger.LogDebug("Refresh token cookie found, length: {Length}", refreshToken.Length);

        var result = await _authService.RefreshTokenAsync(refreshToken, ipAddress);

        if (!result.Success)
        {
            _logger.LogWarning("Token refresh failed: {Message}", result.Message);
            return Unauthorized(new { success = false, message = result.Message });
        }

        SetRefreshTokenCookie(result.RefreshToken!);
        _logger.LogDebug("New refresh token cookie set");

        // Create auth code for redirect-based SSO
        var authCode = await _authService.CreateAuthCodeAsync(result.User!.Id, ipAddress);

        _logger.LogInformation("Token refresh successful");
        return Ok(new
        {
            success = true,
            accessToken = result.AccessToken,
            authCode,
            expiresAt = result.ExpiresAt,
            user = result.User
        });
    }

    /// <summary>
    /// Logout - revokes all user tokens
    /// </summary>
    [HttpPost("logout")]
    [Authorize]
    public async Task<IActionResult> Logout()
    {
        if (!User.Identity?.IsAuthenticated ?? true)
        {
            return Unauthorized(new { success = false, message = "Authentication required" });
        }
        
        var userId = User.FindFirst(System.Security.Claims.ClaimTypes.NameIdentifier)?.Value;
        _logger.LogDebug("POST /api/auth/logout - UserId: {UserId}", userId ?? "unknown");

        Response.Cookies.Delete("refreshToken", new CookieOptions
        {
            Path = Request.PathBase.HasValue ? Request.PathBase.Value : "/"
        });
        
        // Revoke all refresh tokens for this user
        if (Guid.TryParse(userId, out var userGuid))
        {
            var revokedCount = await _authService.RevokeAllUserTokensAsync(userGuid, "self-logout");
            _logger.LogInformation("User logged out: {UserId}, revoked {Count} token(s)", userId, revokedCount);
        }
        else
        {
            _logger.LogInformation("User logged out: {UserId}", userId ?? "unknown");
        }

        return Ok(new { success = true });
    }

    /// <summary>
    /// Validate current session - checks if user still has an active session
    /// Client apps should call this to verify the token is still valid
    /// </summary>
    [HttpGet("validate")]
    [Authorize]
    public async Task<IActionResult> ValidateSession()
    {
        var userId = User.FindFirst(System.Security.Claims.ClaimTypes.NameIdentifier)?.Value;
        
        if (!Guid.TryParse(userId, out var userGuid))
        {
            return Unauthorized(new { valid = false, reason = "invalid_token" });
        }

        // Check if user has any active refresh tokens (session still valid)
        var sessions = await _authService.GetUserSessionsAsync(userGuid);
        
        if (sessions.Count == 0)
        {
            _logger.LogDebug("Session validation failed for user {UserId} - no active sessions", userId);
            return Unauthorized(new { valid = false, reason = "session_revoked" });
        }

        return Ok(new { valid = true, activeSessions = sessions.Count });
    }

    /// <summary>
    /// Get current user info
    /// </summary>
    [HttpGet("me")]
    [Authorize]
    public async Task<IActionResult> GetCurrentUser()
    {
        var userId = User.FindFirst(System.Security.Claims.ClaimTypes.NameIdentifier)?.Value;
        var email = User.FindFirst(System.Security.Claims.ClaimTypes.Email)?.Value;
        var name = User.FindFirst(System.Security.Claims.ClaimTypes.Name)?.Value;
        var accessLevel = User.FindFirst("globalAccessLevel")?.Value;

        _logger.LogDebug("GET /api/auth/me - UserId: {UserId}, Email: {Email}", userId, email);

        // Check if user has password set
        var hasPassword = false;
        // 20260317 GHS Test Ad/Entra Start -->
        string? authMethod = null;
        // <--20260317 GHS Test Ad/Entra End
        if (Guid.TryParse(userId, out var userGuid))
        {
            hasPassword = await _authService.HasPasswordAsync(userGuid);
            // 20260317 GHS Test Ad/Entra Start -->
            var dbUser = await _context.Users.FindAsync(userGuid);
            authMethod = dbUser?.AuthMethod;
            // <--20260317 GHS Test Ad/Entra End
        }

        var accessLevelName = User.FindFirst("globalAccessLevelName")?.Value;

        return Ok(new
        {
            hasPassword,
            userId,
            email,
            displayName = name,
            globalAccessLevel = accessLevel,
            globalAccessLevelName = accessLevelName,
            // 20260317 GHS Test Ad/Entra Start -->
            authMethod
            // <--20260317 GHS Test Ad/Entra End
        });
    }

    /// <summary>
    /// Set or change password for the current user
    /// </summary>
    [HttpPost("set-password")]
    [Authorize]
    public async Task<IActionResult> SetPassword([FromBody] SetPasswordRequest request)
    {
        var userId = User.FindFirst(System.Security.Claims.ClaimTypes.NameIdentifier)?.Value;
        
        if (!Guid.TryParse(userId, out var userGuid))
        {
            return Unauthorized(new { success = false, message = "Invalid token" });
        }

        _logger.LogDebug("POST /api/auth/set-password - UserId: {UserId}", userId);

        var (success, message) = await _authService.SetPasswordAsync(userGuid, request.NewPassword, request.CurrentPassword);

        if (!success)
        {
            _logger.LogWarning("Password set failed for user {UserId}: {Message}", userId, message);
            return BadRequest(new { success = false, message });
        }

        _logger.LogInformation("Password set successfully for user {UserId}", userId);
        return Ok(new { success = true, message });
    }

    /// <summary>
    /// Check if current user has a password set
    /// </summary>
    [HttpGet("has-password")]
    [Authorize]
    public async Task<IActionResult> HasPassword()
    {
        var userId = User.FindFirst(System.Security.Claims.ClaimTypes.NameIdentifier)?.Value;
        
        if (!Guid.TryParse(userId, out var userGuid))
        {
            return Unauthorized(new { success = false, message = "Invalid token" });
        }

        var hasPassword = await _authService.HasPasswordAsync(userGuid);
        return Ok(new { hasPassword });
    }

    /// <summary>
    /// Request a password reset email (anonymous - does not reveal whether user exists)
    /// </summary>
    [HttpPost("request-password-reset")]
    [AllowAnonymous]
    public async Task<IActionResult> RequestPasswordReset([FromBody] PasswordResetRequest request)
    {
        _logger.LogDebug("POST /api/auth/request-password-reset - Email: {Email}", request.Email);

        var requestBaseUrl = GetRequestBaseUrl();
        var (success, message) = await _authService.RequestPasswordResetAsync(request.Email, requestBaseUrl);

        return Ok(new { success, message });
    }

    /// <summary>
    /// Verify a password reset token and redirect to login page with resetToken parameter
    /// </summary>
    [HttpGet("verify-reset")]
    [AllowAnonymous]
    public async Task<IActionResult> VerifyResetToken([FromQuery] string? token)
    {
        var pathBase = Request.PathBase.Value?.TrimEnd('/') ?? "";

        if (string.IsNullOrEmpty(token))
        {
            _logger.LogWarning("Password reset verification failed - no token provided");
            var errorUrl = $"{pathBase}/login.html?error={Uri.EscapeDataString("Invalid or missing reset token")}";
            return Redirect(errorUrl);
        }

        var (valid, message) = await _authService.VerifyPasswordResetTokenAsync(token);

        if (!valid)
        {
            _logger.LogWarning("Password reset token invalid: {Message}", message);
            var errorUrl = $"{pathBase}/login.html?error={Uri.EscapeDataString(message)}";
            return Redirect(errorUrl);
        }

        // Redirect to login page with the reset token so the UI can show the "set new password" form
        var resetUrl = $"{pathBase}/login.html?resetToken={Uri.EscapeDataString(token)}";
        _logger.LogInformation("Password reset token verified, redirecting to reset form");
        return Redirect(resetUrl);
    }

    /// <summary>
    /// Reset password using a valid reset token (anonymous - no auth required)
    /// </summary>
    [HttpPost("reset-password")]
    [AllowAnonymous]
    public async Task<IActionResult> ResetPassword([FromBody] ResetPasswordRequest request)
    {
        _logger.LogDebug("POST /api/auth/reset-password - token length: {TokenLength}", request.Token?.Length ?? 0);

        if (string.IsNullOrEmpty(request.Token))
        {
            return BadRequest(new { success = false, message = "Reset token is required" });
        }

        var (success, message) = await _authService.ResetPasswordAsync(request.Token, request.NewPassword);

        if (!success)
        {
            _logger.LogWarning("Password reset failed: {Message}", message);
            return BadRequest(new { success = false, message });
        }

        _logger.LogInformation("Password reset completed successfully");
        return Ok(new { success = true, message });
    }

    /// <summary>
    /// Build the base URL for email links (magic link, password reset) from the incoming request.
    /// Prefers the browser's Origin header (always correct), falls back to Request.Host.
    /// </summary>
    private string GetRequestBaseUrl()
    {
        var origin = Request.Headers.Origin.FirstOrDefault();
        var pathBase = Request.PathBase.Value?.TrimEnd('/') ?? "";

        if (!string.IsNullOrEmpty(origin))
        {
            var baseUrl = $"{origin.TrimEnd('/')}{pathBase}";
            _logger.LogDebug("Base URL from Origin header: {BaseUrl} (Origin: {Origin}, PathBase: {PathBase})",
                baseUrl, origin, pathBase);
            return baseUrl;
        }

        var hostBaseUrl = $"{Request.Scheme}://{Request.Host}{pathBase}";
        _logger.LogDebug("Base URL from Request.Host: {BaseUrl} (Host: {Host}, Scheme: {Scheme}, PathBase: {PathBase})",
            hostBaseUrl, Request.Host, Request.Scheme, pathBase);
        return hostBaseUrl;
    }

    private string? GetIpAddress()
    {
        return HttpContext.Connection.RemoteIpAddress?.ToString();
    }

    private void SetRefreshTokenCookie(string token, bool rememberMe = false)
    {
        var days = rememberMe ? 30 : _config.RefreshTokenExpirationDays;
        var cookieOptions = new CookieOptions
        {
            HttpOnly = true,
            Expires = DateTime.UtcNow.AddDays(days),
            SameSite = SameSiteMode.Lax,
            Secure = Request.IsHttps,
            Path = Request.PathBase.HasValue ? Request.PathBase.Value : "/"
        };
        Response.Cookies.Append("refreshToken", token, cookieOptions);
    }

    /// <summary>
    /// Update current user's preferred language
    /// </summary>
    [HttpPut("language")]
    [Authorize]
    public async Task<IActionResult> UpdateLanguage([FromBody] UpdateLanguageRequest request)
    {
        var userId = User.FindFirst(System.Security.Claims.ClaimTypes.NameIdentifier)?.Value;

        if (!Guid.TryParse(userId, out var userGuid))
        {
            return Unauthorized(new { success = false, message = "Invalid token" });
        }

        var user = await _context.Users.Include(u => u.Tenant).FirstOrDefaultAsync(u => u.Id == userGuid);
        if (user == null)
        {
            return NotFound(new { success = false, message = "User not found" });
        }

        var supportedLanguages = user.Tenant?.GetSupportedLanguages() ?? new List<string> { "nb", "en" };
        if (!supportedLanguages.Contains(request.Language, StringComparer.OrdinalIgnoreCase))
        {
            return BadRequest(new { success = false, message = $"Language '{request.Language}' is not supported. Supported: {string.Join(", ", supportedLanguages)}" });
        }

        user.PreferredLanguage = request.Language.ToLowerInvariant();
        await _context.SaveChangesAsync();

        _logger.LogInformation("User {UserId} changed preferred language to {Language}", userId, request.Language);
        return Ok(new { success = true, language = user.PreferredLanguage });
    }
}

// Request DTOs
public record RegisterRequest(string Email, string DisplayName, string? Password, List<AppAccessRequestDto>? AppRequests);
public record AppAccessRequestDto(string AppId, string Role, string? Reason);
public record LoginRequest(string Email, string Password, bool RememberMe = false);
public record MagicLinkRequest(string Email);
public record SetPasswordRequest(string NewPassword, string? CurrentPassword);
public record PasswordResetRequest(string Email);
public record ResetPasswordRequest(string Token, string NewPassword);
public record AuthCodeExchangeRequest(string Code);
public record UpdateLanguageRequest(string Language);

/// <summary>
/// Response DTO for the login endpoint. Named type to avoid IIS InProcess anonymous type issues.
/// </summary>
public record LoginResponse(
    bool Success,
    string AccessToken,
    string? AuthCode,
    DateTime? ExpiresAt,
    DedgeAuth.Services.UserInfo? User,
    bool IsNewUser = false);
