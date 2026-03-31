using System.Security.Cryptography;
using Microsoft.EntityFrameworkCore;
using Microsoft.Extensions.Logging;
using Microsoft.Extensions.Options;
using DedgeAuth.Core.Models;
using DedgeAuth.Data;

namespace DedgeAuth.Services;

/// <summary>
/// Core authentication service
/// </summary>
public class AuthService
{
    private readonly AuthDbContext _context;
    private readonly AuthConfiguration _config;
    private readonly JwtTokenService _jwtService;
    private readonly EmailService _emailService;
    private readonly ILogger<AuthService> _logger;

    public AuthService(
        AuthDbContext context,
        IOptions<AuthConfiguration> config,
        JwtTokenService jwtService,
        EmailService emailService,
        ILogger<AuthService> logger)
    {
        _context = context;
        _config = config.Value;
        _jwtService = jwtService;
        _emailService = emailService;
        _logger = logger;
    }

    #region User Registration

    public async Task<(bool Success, string Message, User? User)> RegisterAsync(string email, string displayName, string? password = null)
    {
        _logger.LogDebug("Registration attempt for email: {Email}, displayName: {DisplayName}, hasPassword: {HasPassword}", 
            email, displayName, password != null);

        if (!IsAllowedDomain(email))
        {
            _logger.LogWarning("Registration rejected - domain not allowed: {Email}, allowed domain: {AllowedDomain}", 
                email, _config.AllowedDomain);
            return (false, $"Registration is only allowed for @{_config.AllowedDomain} email addresses.", null);
        }

        var existingUser = await _context.Users.FirstOrDefaultAsync(u => u.Email.ToLower() == email.ToLower());
        if (existingUser != null)
        {
            _logger.LogWarning("Registration rejected - email already exists: {Email}", email);
            return (false, "An account with this email already exists.", null);
        }

        var isAdmin = IsAdminEmail(email);
        _logger.LogDebug("User will be created with access level: {AccessLevel} (isAdmin: {IsAdmin})", 
            isAdmin ? "Admin" : "User", isAdmin);

        var user = new User
        {
            Email = email.ToLower(),
            DisplayName = displayName,
            GlobalAccessLevel = isAdmin ? AccessLevel.Admin : AccessLevel.User,
            EmailVerified = !_config.RequireEmailVerification,
            PasswordHash = password != null ? BCrypt.Net.BCrypt.HashPassword(password) : null
        };

        // Resolve tenant from email domain
        var domain = email.Split('@').LastOrDefault()?.ToLower();
        if (!string.IsNullOrEmpty(domain))
        {
            _logger.LogDebug("Looking up tenant for domain: {Domain}", domain);
            var tenant = await _context.Tenants.FirstOrDefaultAsync(t => t.Domain.ToLower() == domain);
            if (tenant != null)
            {
                user.TenantId = tenant.Id;
                _logger.LogDebug("Assigned tenant {TenantId} ({TenantDomain}) to user", tenant.Id, tenant.Domain);
            }
            else
            {
                _logger.LogDebug("No tenant found for domain: {Domain}", domain);
            }
        }

        _context.Users.Add(user);
        await _context.SaveChangesAsync();

        _logger.LogInformation("User registered successfully: {Email} (UserId: {UserId}, AccessLevel: {AccessLevel})", 
            email, user.Id, user.GlobalAccessLevel);
        return (true, "Registration successful.", user);
    }

    #endregion

    // 20260317 GHS Test Ad/Entra Start -->
    #region Windows/AD Authentication

    public async Task<AuthResult> LoginWithWindowsAsync(string windowsName, string? ipAddress = null, string? adEmail = null, string? adDisplayName = null, List<string>? adGroups = null)
    {
        _logger.LogDebug("Windows login for {WindowsName} from IP {IpAddress}, adEmail={AdEmail}", windowsName, ipAddress ?? "unknown", adEmail ?? "(none)");

        var username = windowsName.Contains('\\')
            ? windowsName.Split('\\')[1].ToLower()
            : windowsName.ToLower();

        var email = !string.IsNullOrEmpty(adEmail)
            ? adEmail.ToLower()
            : $"{username}@Dedge.no";

        var displayName = !string.IsNullOrEmpty(adDisplayName)
            ? adDisplayName
            : username.ToUpper();

        // Resolve tenant from email domain and check WindowsSsoEnabled
        var emailDomain = email.Split('@').LastOrDefault()?.ToLower();
        Tenant? tenant = null;
        if (!string.IsNullOrEmpty(emailDomain))
        {
            tenant = await _context.Tenants.FirstOrDefaultAsync(t => t.Domain.ToLower() == emailDomain);
        }

        if (tenant == null || !tenant.WindowsSsoEnabled)
        {
            _logger.LogInformation("Windows SSO not enabled for tenant {Domain} — returning ssoDisabled for {Email}",
                emailDomain ?? "(none)", email);
            return AuthResult.SsoNotEnabled(email, displayName);
        }

        // SSO enabled — find or auto-create user
        bool isNewUser = false;
        var user = await _context.Users.Include(u => u.Tenant)
            .FirstOrDefaultAsync(u => u.Email.ToLower() == email);

        // Cleanup: if AD resolved a real email different from username@domain, merge any orphaned duplicate
        var constructedEmail = $"{username}@Dedge.no";
        if (!string.IsNullOrEmpty(adEmail) && !constructedEmail.Equals(email, StringComparison.OrdinalIgnoreCase))
        {
            var orphan = await _context.Users.FirstOrDefaultAsync(u => u.Email.ToLower() == constructedEmail);
            if (orphan != null)
            {
                _logger.LogInformation("Cleaning up orphaned Windows user {OrphanEmail} (ID: {OrphanId}) — AD resolved to {RealEmail}",
                    constructedEmail, orphan.Id, email);
                _context.AppPermissions.RemoveRange(
                    await _context.AppPermissions.Where(p => p.UserId == orphan.Id).ToListAsync());
                _context.UserVisits.RemoveRange(
                    await _context.UserVisits.Where(v => v.UserId == orphan.Id).ToListAsync());
                _context.LoginTokens.RemoveRange(
                    await _context.LoginTokens.Where(t => t.UserId == orphan.Id).ToListAsync());
                _context.RefreshTokens.RemoveRange(
                    await _context.RefreshTokens.Where(t => t.UserId == orphan.Id).ToListAsync());
                _context.AccessRequests.RemoveRange(
                    await _context.AccessRequests.Where(r => r.UserId == orphan.Id).ToListAsync());
                _context.Users.Remove(orphan);
                await _context.SaveChangesAsync();
            }
        }

        if (user == null)
        {
            _logger.LogInformation("Auto-creating user from Windows identity: {WindowsName} -> {Email} ({DisplayName})", windowsName, email, displayName);

            user = new User
            {
                Email = email,
                DisplayName = displayName,
                IsActive = true,
                EmailVerified = true,
                PasswordHash = null,
                AuthMethod = "windows",
                GlobalAccessLevel = IsAdminEmail(email) ? AccessLevel.Admin : AccessLevel.User,
                TenantId = tenant.Id,
                CreatedAt = DateTime.UtcNow,
                LastLoginAt = DateTime.UtcNow
            };
            _context.Users.Add(user);
            await _context.SaveChangesAsync();

            user = await _context.Users.Include(u => u.Tenant)
                .FirstAsync(u => u.Id == user.Id);
            isNewUser = true;
        }

        if (!user.IsActive)
        {
            _logger.LogWarning("Windows login failed - account inactive: {Email}", email);
            return AuthResult.Failed("Account is inactive.");
        }

        if (!string.IsNullOrEmpty(adDisplayName) && user.DisplayName != adDisplayName)
        {
            _logger.LogInformation("Updating display name for {Email}: {Old} -> {New}", email, user.DisplayName, adDisplayName);
            user.DisplayName = adDisplayName;
        }

        user.AuthMethod = "windows";
        user.LastLoginAt = DateTime.UtcNow;
        await _context.SaveChangesAsync();

        var appRoles = await GetUserAppRolesAsync(user.Id, user.AuthMethod);
        var accessToken = _jwtService.GenerateAccessToken(user, appRoles, user.Tenant, adGroups);
        var refreshToken = await CreateRefreshTokenAsync(user.Id, ipAddress);

        _logger.LogInformation("Windows login successful for {Email} ({UserId}), isNewUser={IsNew}, adGroups={GroupCount}",
            email, user.Id, isNewUser, adGroups?.Count ?? 0);

        return AuthResult.Successful(
            accessToken,
            refreshToken.Token,
            DateTime.UtcNow.AddMinutes(_config.AccessTokenExpirationMinutes),
            CreateUserInfo(user, appRoles),
            isNewUser
        );
    }

    #endregion
    // <--20260317 GHS Test Ad/Entra End

    #region Password Authentication

    public async Task<AuthResult> LoginWithPasswordAsync(string email, string password, string? ipAddress = null, bool rememberMe = false)
    {
        _logger.LogDebug("Password login attempt for {Email} from IP {IpAddress}", email, ipAddress ?? "unknown");

        var user = await _context.Users
            .Include(u => u.Tenant)
            .FirstOrDefaultAsync(u => u.Email.ToLower() == email.ToLower());

        bool isNewUser = false;

        if (user == null)
        {
            // Auto-provision: create user on first login if domain is allowed
            if (!IsAllowedDomain(email))
            {
                _logger.LogWarning("Login failed - user not found and domain not allowed: {Email}", email);
                return AuthResult.Failed("Invalid email or password.");
            }

            var validationResult = ValidatePassword(password);
            if (!validationResult.Success)
            {
                _logger.LogWarning("Auto-provision rejected - password too weak for {Email}: {Msg}", email, validationResult.Message);
                return AuthResult.Failed(validationResult.Message);
            }

            user = await AutoProvisionUserAsync(email, password);
            isNewUser = true;
            _logger.LogInformation("Auto-provisioned new user on password login: {Email} ({UserId})", email, user.Id);
        }

        _logger.LogDebug("User found: {UserId}, IsActive: {IsActive}, IsLockedOut: {IsLockedOut}, HasPassword: {HasPassword}", 
            user.Id, user.IsActive, user.IsLockedOut, !string.IsNullOrEmpty(user.PasswordHash));

        if (!user.IsActive)
        {
            _logger.LogWarning("Login failed - account inactive: {Email} ({UserId})", email, user.Id);
            return AuthResult.Failed("Account is inactive.");
        }

        // Check lockout BEFORE password verification
        if (user.IsLockedOut)
        {
            _logger.LogWarning("Login failed - account locked until {LockoutUntil}: {Email} ({UserId})", 
                user.LockoutUntil, email, user.Id);
            return AuthResult.Failed("Invalid email or password.");
        }

        if (string.IsNullOrEmpty(user.PasswordHash))
        {
            _logger.LogWarning("Login failed - no password set for user: {Email} ({UserId})", email, user.Id);
            return AuthResult.Failed("Password login is not enabled for this account. Use magic link.");
        }

        if (!isNewUser && !BCrypt.Net.BCrypt.Verify(password, user.PasswordHash))
        {
            user.FailedLoginCount++;
            _logger.LogWarning("Login failed - invalid password for {Email}, failed attempts: {FailedCount}/{MaxAttempts}", 
                email, user.FailedLoginCount, _config.MaxFailedLoginAttempts);
            
            if (user.FailedLoginCount >= _config.MaxFailedLoginAttempts)
            {
                user.LockoutUntil = DateTime.UtcNow.AddMinutes(_config.LockoutDurationMinutes);
                _logger.LogWarning("Account locked for {Email} until {LockoutUntil}", email, user.LockoutUntil);

                _ = Task.Run(async () =>
                {
                    try
                    {
                        await _emailService.SendLockoutNotificationAsync(
                            user.Email, user.DisplayName, user.LockoutUntil.Value,
                            user.FailedLoginCount, ipAddress, user.Tenant, _config.ServerBaseUrl);
                    }
                    catch (Exception ex)
                    {
                        _logger.LogDebug("Lockout notification email failed for {Email}: {Error}", user.Email, ex.Message);
                    }
                });
            }
            await _context.SaveChangesAsync();
            return AuthResult.Failed("Invalid email or password.");
        }

        // Reset failed login count and update last login
        user.FailedLoginCount = 0;
        user.LockoutUntil = null;
        user.LastLoginAt = DateTime.UtcNow;
        await _context.SaveChangesAsync();

        _logger.LogDebug("Password verified, generating tokens for {Email}", email);

        // Get app roles (pass authMethod for implicit Windows access if user has used Windows login before)
        var appRoles = await GetUserAppRolesAsync(user.Id, user.AuthMethod);
        _logger.LogDebug("User has {Count} app roles", appRoles.Count);

        // Generate tokens
        var accessToken = _jwtService.GenerateAccessToken(user, appRoles, user.Tenant);
        var refreshToken = await CreateRefreshTokenAsync(user.Id, ipAddress, rememberMe ? 30 : null);

        _logger.LogInformation("Password login successful for {Email} ({UserId}) from IP {IpAddress}, isNewUser={IsNew}, rememberMe={RememberMe}", 
            email, user.Id, ipAddress ?? "unknown", isNewUser, rememberMe);

        return AuthResult.Successful(
            accessToken,
            refreshToken.Token,
            DateTime.UtcNow.AddMinutes(_config.AccessTokenExpirationMinutes),
            CreateUserInfo(user, appRoles),
            isNewUser
        );
    }

    #endregion

    #region Magic Link Authentication

    public async Task<(bool Success, string Message)> RequestMagicLinkAsync(string email, string? ipAddress = null, string? requestBaseUrl = null)
    {
        _logger.LogDebug("Magic link request for {Email} from IP {IpAddress}", email, ipAddress ?? "unknown");

        var user = await _context.Users
            .Include(u => u.Tenant)
            .FirstOrDefaultAsync(u => u.Email.ToLower() == email.ToLower());

        if (user == null)
        {
            // Auto-provision: create user on first magic link request if domain is allowed
            if (!IsAllowedDomain(email))
            {
                _logger.LogDebug("Magic link request - user not found and domain not allowed: {Email}", email);
                return (true, "If this email is registered, you will receive a login link.");
            }

            user = await AutoProvisionUserAsync(email);
            _logger.LogInformation("Auto-provisioned new user on magic link request: {Email} ({UserId})", email, user.Id);
        }

        if (!user.IsActive)
        {
            _logger.LogDebug("Magic link request - user inactive: {Email} ({UserId})", email, user.Id);
            return (true, "If this email is registered, you will receive a login link.");
        }

        if (user.IsLockedOut)
        {
            _logger.LogWarning("Magic link request rejected - account locked: {Email} ({UserId})", email, user.Id);
            return (false, "Account is locked.");
        }

        var token = new LoginToken
        {
            Token = GenerateSecureToken(),
            UserId = user.Id,
            TokenType = TokenTypes.Login,
            ExpiresAt = DateTime.UtcNow.AddMinutes(_config.MagicLinkExpirationMinutes),
            RequestIp = ipAddress
        };

        _context.LoginTokens.Add(token);
        await _context.SaveChangesAsync();

        var baseUrl = !string.IsNullOrEmpty(requestBaseUrl) ? requestBaseUrl.TrimEnd('/') : _config.BaseUrl;
        var loginUrl = $"{baseUrl}/api/auth/verify?token={token.Token}";
        _logger.LogDebug("Magic link token created for {Email}: expires at {ExpiresAt}, URL: {Url}", 
            email, token.ExpiresAt, loginUrl);

        await _emailService.SendMagicLinkEmailAsync(user.Email, user.DisplayName, loginUrl, _config.MagicLinkExpirationMinutes, user.Tenant, baseUrl);

        _logger.LogInformation("Magic link sent to {Email} ({UserId}), expires at {ExpiresAt}", 
            email, user.Id, token.ExpiresAt);
        return (true, "If this email is registered, you will receive a login link.");
    }

    public async Task<AuthResult> VerifyMagicLinkAsync(string token, string? ipAddress = null)
    {
        _logger.LogDebug("Magic link verification attempt, token length: {TokenLength}, IP: {IpAddress}", 
            token?.Length ?? 0, ipAddress ?? "unknown");

        var loginToken = await _context.LoginTokens
            .Include(t => t.User)
            .ThenInclude(u => u!.Tenant)
            .FirstOrDefaultAsync(t => t.Token == token && t.TokenType == TokenTypes.Login);

        if (loginToken == null)
        {
            _logger.LogWarning("Magic link verification failed - token not found");
            return AuthResult.Failed("Invalid or expired login link.");
        }

        var isExpired = DateTime.UtcNow >= loginToken.ExpiresAt;
        _logger.LogDebug("Token found - UserId: {UserId}, ExpiresAt: {ExpiresAt}, IsUsed: {IsUsed}, IsExpired: {IsExpired}", 
            loginToken.UserId, loginToken.ExpiresAt, loginToken.IsUsed, isExpired);

        if (!loginToken.IsValid)
        {
            _logger.LogWarning("Magic link verification failed - token invalid (IsUsed: {IsUsed}, IsExpired: {IsExpired})", 
                loginToken.IsUsed, isExpired);
            return AuthResult.Failed("Invalid or expired login link.");
        }

        if (loginToken.User == null)
        {
            _logger.LogError("Magic link verification failed - user not found for token (UserId: {UserId})", loginToken.UserId);
            return AuthResult.Failed("Invalid or expired login link.");
        }

        _logger.LogDebug("Token valid for user {Email} ({UserId}), marking as used", 
            loginToken.User.Email, loginToken.User.Id);

        // Mark token as used
        loginToken.IsUsed = true;
        loginToken.UsedAt = DateTime.UtcNow;
        loginToken.UsedIp = ipAddress;

        // Update user last login
        loginToken.User.LastLoginAt = DateTime.UtcNow;
        loginToken.User.FailedLoginCount = 0;
        await _context.SaveChangesAsync();

        // Get app roles (pass authMethod for implicit Windows access)
        var appRoles = await GetUserAppRolesAsync(loginToken.User.Id, loginToken.User.AuthMethod);
        _logger.LogDebug("User has {Count} app roles", appRoles.Count);

        // Generate tokens
        _logger.LogDebug("Generating access token for user {Email}", loginToken.User.Email);
        var accessToken = _jwtService.GenerateAccessToken(loginToken.User, appRoles, loginToken.User.Tenant);
        
        _logger.LogDebug("Creating refresh token for user {Email}", loginToken.User.Email);
        var refreshToken = await CreateRefreshTokenAsync(loginToken.User.Id, ipAddress);

        _logger.LogInformation("Magic link login successful for {Email} ({UserId}) from IP {IpAddress}", 
            loginToken.User.Email, loginToken.User.Id, ipAddress ?? "unknown");

        return AuthResult.Successful(
            accessToken,
            refreshToken.Token,
            DateTime.UtcNow.AddMinutes(_config.AccessTokenExpirationMinutes),
            CreateUserInfo(loginToken.User, appRoles)
        );
    }

    #endregion

    #region Token Refresh

    public async Task<AuthResult> RefreshTokenAsync(string refreshTokenValue, string? ipAddress = null)
    {
        _logger.LogDebug("Token refresh attempt, token length: {TokenLength}, IP: {IpAddress}", 
            refreshTokenValue?.Length ?? 0, ipAddress ?? "unknown");

        var refreshToken = await _context.RefreshTokens
            .Include(t => t.User)
            .ThenInclude(u => u!.Tenant)
            .FirstOrDefaultAsync(t => t.Token == refreshTokenValue);

        if (refreshToken == null)
        {
            _logger.LogWarning("Token refresh failed - refresh token not found");
            return AuthResult.Failed("Invalid refresh token.");
        }

        var isExpired = DateTime.UtcNow >= refreshToken.ExpiresAt;
        _logger.LogDebug("Refresh token found - UserId: {UserId}, ExpiresAt: {ExpiresAt}, IsRevoked: {IsRevoked}, IsExpired: {IsExpired}", 
            refreshToken.UserId, refreshToken.ExpiresAt, refreshToken.IsRevoked, isExpired);

        if (!refreshToken.IsActive)
        {
            _logger.LogWarning("Token refresh failed - token not active (IsRevoked: {IsRevoked}, IsExpired: {IsExpired})", 
                refreshToken.IsRevoked, isExpired);
            return AuthResult.Failed("Invalid refresh token.");
        }

        if (refreshToken.User == null)
        {
            _logger.LogError("Token refresh failed - user not found for refresh token (UserId: {UserId})", refreshToken.UserId);
            return AuthResult.Failed("Invalid refresh token.");
        }

        _logger.LogDebug("Revoking old refresh token and creating new one for user {Email}", refreshToken.User.Email);

        // Revoke old token
        refreshToken.IsRevoked = true;
        refreshToken.RevokedAt = DateTime.UtcNow;

        // Create new tokens
        var newRefreshToken = await CreateRefreshTokenAsync(refreshToken.UserId, ipAddress);
        refreshToken.ReplacedByToken = newRefreshToken.Token;

        await _context.SaveChangesAsync();

        // Get app roles (pass authMethod for implicit Windows access)
        var appRoles = await GetUserAppRolesAsync(refreshToken.User.Id, refreshToken.User.AuthMethod);
        _logger.LogDebug("User has {Count} app roles", appRoles.Count);

        var accessToken = _jwtService.GenerateAccessToken(refreshToken.User, appRoles, refreshToken.User.Tenant);

        _logger.LogInformation("Token refresh successful for {Email} ({UserId}) from IP {IpAddress}", 
            refreshToken.User.Email, refreshToken.User.Id, ipAddress ?? "unknown");

        return AuthResult.Successful(
            accessToken,
            newRefreshToken.Token,
            DateTime.UtcNow.AddMinutes(_config.AccessTokenExpirationMinutes),
            CreateUserInfo(refreshToken.User, appRoles)
        );
    }

    /// <summary>
    /// Validate a refresh token and return the associated user ID WITHOUT revoking/rotating it.
    /// Used by the redirect endpoint so that multiple app-link clicks can reuse the same token.
    /// </summary>
    public async Task<Guid?> ValidateRefreshTokenUserAsync(string refreshTokenValue)
    {
        var refreshToken = await _context.RefreshTokens
            .FirstOrDefaultAsync(t => t.Token == refreshTokenValue);

        if (refreshToken == null || !refreshToken.IsActive)
            return null;

        return refreshToken.UserId;
    }

    #endregion

    #region Auth Code Exchange

    /// <summary>
    /// Create a short-lived auth code that can be exchanged for a JWT.
    /// The code is ~43 chars (vs ~800 for a JWT), safe for URL transport.
    /// </summary>
    public async Task<string> CreateAuthCodeAsync(Guid userId, string? ipAddress = null)
    {
        var code = GenerateSecureToken();
        var authCode = new LoginToken
        {
            Token = code,
            UserId = userId,
            TokenType = TokenTypes.AuthCode,
            ExpiresAt = DateTime.UtcNow.AddSeconds(60),
            RequestIp = ipAddress
        };

        _context.LoginTokens.Add(authCode);
        await _context.SaveChangesAsync();

        _logger.LogDebug("Auth code created for user {UserId}, expires in 60s", userId);
        return code;
    }

    /// <summary>
    /// Exchange a one-time auth code for a full JWT + refresh token.
    /// Called server-to-server by consumer apps.
    /// </summary>
    public async Task<AuthResult> ExchangeAuthCodeAsync(string code, string? ipAddress = null)
    {
        _logger.LogDebug("Auth code exchange attempt, code length: {CodeLength}, IP: {IpAddress}",
            code?.Length ?? 0, ipAddress ?? "unknown");

        var authCode = await _context.LoginTokens
            .Include(t => t.User)
            .ThenInclude(u => u!.Tenant)
            .FirstOrDefaultAsync(t => t.Token == code && t.TokenType == TokenTypes.AuthCode);

        if (authCode == null)
        {
            _logger.LogWarning("Auth code exchange failed - code not found");
            return AuthResult.Failed("Invalid or expired auth code.");
        }

        if (!authCode.IsValid)
        {
            _logger.LogWarning("Auth code exchange failed - code expired or used (IsUsed: {IsUsed}, ExpiresAt: {ExpiresAt})",
                authCode.IsUsed, authCode.ExpiresAt);
            return AuthResult.Failed("Invalid or expired auth code.");
        }

        if (authCode.User == null)
        {
            _logger.LogError("Auth code exchange failed - user not found for code (UserId: {UserId})", authCode.UserId);
            return AuthResult.Failed("Invalid or expired auth code.");
        }

        // Mark code as used (one-time)
        authCode.IsUsed = true;
        authCode.UsedAt = DateTime.UtcNow;
        authCode.UsedIp = ipAddress;
        await _context.SaveChangesAsync();

        // Generate fresh JWT and refresh token (pass authMethod for implicit Windows access)
        var appRoles = await GetUserAppRolesAsync(authCode.User.Id, authCode.User.AuthMethod);
        var accessToken = _jwtService.GenerateAccessToken(authCode.User, appRoles, authCode.User.Tenant);
        var refreshToken = await CreateRefreshTokenAsync(authCode.User.Id, ipAddress);

        _logger.LogInformation("Auth code exchange successful for {Email} ({UserId})",
            authCode.User.Email, authCode.User.Id);

        return AuthResult.Successful(
            accessToken,
            refreshToken.Token,
            DateTime.UtcNow.AddMinutes(_config.AccessTokenExpirationMinutes),
            CreateUserInfo(authCode.User, appRoles)
        );
    }

    #endregion

    #region Auto-Provisioning

    /// <summary>
    /// Auto-create a user when they attempt to log in for the first time.
    /// The user is created with EmailVerified=false so they appear in admin pending approvals.
    /// Tenant is resolved from the email domain.
    /// </summary>
    private async Task<User> AutoProvisionUserAsync(string email, string? password = null)
    {
        var normalizedEmail = email.ToLower();
        var displayName = BuildDisplayNameFromEmail(normalizedEmail);
        var domain = normalizedEmail.Split('@').LastOrDefault();

        Tenant? tenant = null;
        if (!string.IsNullOrEmpty(domain))
        {
            tenant = await _context.Tenants.FirstOrDefaultAsync(t => t.Domain.ToLower() == domain);
        }

        var user = new User
        {
            Email = normalizedEmail,
            DisplayName = displayName,
            PasswordHash = password != null ? BCrypt.Net.BCrypt.HashPassword(password) : null,
            GlobalAccessLevel = IsAdminEmail(normalizedEmail) ? AccessLevel.Admin : AccessLevel.User,
            IsActive = true,
            EmailVerified = false,
            TenantId = tenant?.Id,
            CreatedAt = DateTime.UtcNow,
            LastLoginAt = DateTime.UtcNow
        };

        _context.Users.Add(user);
        await _context.SaveChangesAsync();

        // Reload with tenant navigation property
        user = await _context.Users.Include(u => u.Tenant)
            .FirstAsync(u => u.Id == user.Id);

        _logger.LogInformation("Auto-provisioned user {Email} ({UserId}), tenant={Tenant}, pending admin confirmation",
            user.Email, user.Id, tenant?.Domain ?? "(none)");

        return user;
    }

    /// <summary>
    /// Build a display name from email: "geir.helge.starholm@Dedge.no" → "Geir Helge Starholm"
    /// </summary>
    private static string BuildDisplayNameFromEmail(string email)
    {
        var localPart = email.Split('@')[0];
        var parts = localPart.Split(new[] { '.', '_', '-' }, StringSplitOptions.RemoveEmptyEntries);
        if (parts.Length == 0)
            return email;

        return string.Join(" ", parts.Select(p =>
            char.ToUpper(p[0]) + (p.Length > 1 ? p[1..] : "")));
    }

    #endregion

    #region Helper Methods

    public bool IsAllowedDomain(string email)
    {
        if (string.IsNullOrEmpty(_config.AllowedDomain))
            return true;

        var domain = email.Split('@').LastOrDefault()?.ToLower();
        return domain == _config.AllowedDomain.ToLower();
    }

    public bool IsAdminEmail(string email)
    {
        return _config.AdminEmails?.Any(e =>
            e.Equals(email, StringComparison.OrdinalIgnoreCase)) ?? false;
    }

    /// <summary>
    /// Check if user has a password set
    /// </summary>
    public async Task<bool> HasPasswordAsync(Guid userId)
    {
        var user = await _context.Users.FindAsync(userId);
        return user?.PasswordHash != null;
    }

    /// <summary>
    /// Set or update password for a user.
    /// Current password is NOT required — the caller is already authenticated via JWT.
    /// </summary>
    public async Task<(bool Success, string Message)> SetPasswordAsync(Guid userId, string newPassword, string? currentPassword = null)
    {
        var user = await _context.Users.FindAsync(userId);
        if (user == null)
        {
            return (false, "User not found");
        }

        // Validate new password
        var validationResult = ValidatePassword(newPassword);
        if (!validationResult.Success)
        {
            return validationResult;
        }

        // Hash and save new password
        user.PasswordHash = BCrypt.Net.BCrypt.HashPassword(newPassword);
        await _context.SaveChangesAsync();

        _logger.LogInformation("Password set/updated for user {UserId} ({Email})", userId, user.Email);
        return (true, "Password updated successfully");
    }

    /// <summary>
    /// Request a password reset email. Returns generic message for security.
    /// </summary>
    public async Task<(bool Success, string Message)> RequestPasswordResetAsync(string email, string? requestBaseUrl = null)
    {
        _logger.LogDebug("Password reset request for {Email}", email);

        var user = await _context.Users
            .Include(u => u.Tenant)
            .FirstOrDefaultAsync(u => u.Email.ToLower() == email.ToLower());

        if (user == null || !user.IsActive || !user.EmailVerified)
        {
            _logger.LogDebug("Password reset request - user not found/inactive/unverified: {Email}", email);
            return (true, "If this email is registered, you will receive a password reset link.");
        }

        if (user.IsLockedOut)
        {
            _logger.LogWarning("Password reset request rejected - account locked: {Email} ({UserId})", email, user.Id);
            return (false, "Account is locked.");
        }

        var token = new LoginToken
        {
            Token = GenerateSecureToken(),
            UserId = user.Id,
            TokenType = TokenTypes.PasswordReset,
            ExpiresAt = DateTime.UtcNow.AddHours(_config.PasswordResetExpirationHours),
            RequestIp = null
        };

        _context.LoginTokens.Add(token);
        await _context.SaveChangesAsync();

        var baseUrl = !string.IsNullOrEmpty(requestBaseUrl) ? requestBaseUrl.TrimEnd('/') : _config.BaseUrl;
        var resetUrl = $"{baseUrl}/api/auth/verify-reset?token={token.Token}";

        await _emailService.SendPasswordResetEmailAsync(user.Email, user.DisplayName, resetUrl, user.Tenant, baseUrl);

        _logger.LogInformation("Password reset email sent to {Email} ({UserId}), expires at {ExpiresAt}",
            email, user.Id, token.ExpiresAt);
        return (true, "If this email is registered, you will receive a password reset link.");
    }

    /// <summary>
    /// Verify a password reset token (does not consume it — just checks validity).
    /// </summary>
    public async Task<(bool Valid, string Message)> VerifyPasswordResetTokenAsync(string token)
    {
        var loginToken = await _context.LoginTokens
            .FirstOrDefaultAsync(t => t.Token == token && t.TokenType == TokenTypes.PasswordReset);

        if (loginToken == null || !loginToken.IsValid)
        {
            return (false, "Invalid or expired password reset link.");
        }

        return (true, "Token is valid.");
    }

    /// <summary>
    /// Reset password using a valid reset token (no authentication required).
    /// </summary>
    public async Task<(bool Success, string Message)> ResetPasswordAsync(string token, string newPassword)
    {
        var loginToken = await _context.LoginTokens
            .Include(t => t.User)
            .FirstOrDefaultAsync(t => t.Token == token && t.TokenType == TokenTypes.PasswordReset);

        if (loginToken == null || !loginToken.IsValid)
        {
            _logger.LogWarning("Password reset failed - invalid or expired token");
            return (false, "Invalid or expired password reset link.");
        }

        if (loginToken.User == null)
        {
            _logger.LogError("Password reset failed - user not found for token");
            return (false, "Invalid or expired password reset link.");
        }

        // Validate new password
        var validationResult = ValidatePassword(newPassword);
        if (!validationResult.Success)
        {
            return validationResult;
        }

        // Set new password
        loginToken.User.PasswordHash = BCrypt.Net.BCrypt.HashPassword(newPassword);

        // Mark token as used
        loginToken.IsUsed = true;
        loginToken.UsedAt = DateTime.UtcNow;

        // Reset any lockout
        loginToken.User.FailedLoginCount = 0;
        loginToken.User.LockoutUntil = null;

        await _context.SaveChangesAsync();

        _logger.LogInformation("Password reset successful for user {Email} ({UserId})",
            loginToken.User.Email, loginToken.User.Id);
        return (true, "Password has been reset successfully. You can now log in with your new password.");
    }

    /// <summary>
    /// Validate password against configured rules.
    /// </summary>
    private (bool Success, string Message) ValidatePassword(string password)
    {
        if (password.Length < _config.MinPasswordLength)
        {
            return (false, $"Password must be at least {_config.MinPasswordLength} characters");
        }

        if (_config.RequireUppercase && !password.Any(char.IsUpper))
        {
            return (false, "Password must contain at least one uppercase letter");
        }

        if (_config.RequireDigit && !password.Any(char.IsDigit))
        {
            return (false, "Password must contain at least one digit");
        }

        if (_config.RequireSpecialChar && !password.Any(c => !char.IsLetterOrDigit(c)))
        {
            return (false, "Password must contain at least one special character");
        }

        return (true, "Password is valid");
    }

    public async Task<Dictionary<string, string>> GetUserAppRolesAsync(Guid userId, string? authMethod = null)
    {
        _logger.LogDebug("Fetching app roles for user {UserId}, authMethod={AuthMethod}", userId, authMethod ?? "(none)");

        var permissions = await _context.AppPermissions
            .Include(p => p.App)
            .Where(p => p.UserId == userId && p.App!.IsActive)
            .ToListAsync();

        var roles = permissions.ToDictionary(
            p => p.App!.AppId,
            p => p.Role
        );

        // 20260317 GHS Test Ad/Entra Start -->
        // For Windows/Kerberos users: add implicit minimum access to apps where they have no explicit permission
        if (string.Equals(authMethod, "windows", StringComparison.OrdinalIgnoreCase))
        {
            var safeRoles = new HashSet<string>(StringComparer.OrdinalIgnoreCase) { "ReadOnly", "Viewer", "User" };
            var roleHierarchy = new List<string> { "ReadOnly", "Viewer", "User", "Operator", "PowerUser", "Admin" };

            var allActiveApps = await _context.Apps.Where(a => a.IsActive).ToListAsync();

            foreach (var app in allActiveApps)
            {
                if (roles.ContainsKey(app.AppId))
                    continue;

                var availableRoles = app.GetAvailableRoles();
                if (availableRoles.Count == 0)
                    continue;

                // Find the lowest role in the hierarchy
                string? lowestRole = null;
                foreach (var hierarchyRole in roleHierarchy)
                {
                    if (availableRoles.Any(r => r.Equals(hierarchyRole, StringComparison.OrdinalIgnoreCase)))
                    {
                        lowestRole = availableRoles.First(r => r.Equals(hierarchyRole, StringComparison.OrdinalIgnoreCase));
                        break;
                    }
                }

                if (lowestRole != null && safeRoles.Contains(lowestRole))
                {
                    roles[app.AppId] = lowestRole;
                    _logger.LogDebug("Implicit minimum role for Windows user on app {AppId}: {Role}", app.AppId, lowestRole);
                }
            }
        }
        // <--20260317 GHS Test Ad/Entra End

        if (roles.Count > 0)
        {
            _logger.LogDebug("Found {Count} app roles for user {UserId}: {Roles}", 
                roles.Count, userId, string.Join(", ", roles.Select(r => $"{r.Key}={r.Value}")));
        }
        else
        {
            _logger.LogDebug("No app roles found for user {UserId}", userId);
        }

        return roles;
    }

    /// <summary>
    /// Revoke all refresh tokens for a user (admin action)
    /// </summary>
    public async Task<int> RevokeAllUserTokensAsync(Guid userId, string? revokedByEmail = null)
    {
        _logger.LogInformation("Revoking all tokens for user {UserId}, initiated by: {RevokedBy}", 
            userId, revokedByEmail ?? "system");

        var activeTokens = await _context.RefreshTokens
            .Where(t => t.UserId == userId && !t.IsRevoked && t.ExpiresAt > DateTime.UtcNow)
            .ToListAsync();

        if (activeTokens.Count == 0)
        {
            _logger.LogDebug("No active tokens found for user {UserId}", userId);
            return 0;
        }

        foreach (var token in activeTokens)
        {
            token.IsRevoked = true;
            token.RevokedAt = DateTime.UtcNow;
        }

        await _context.SaveChangesAsync();

        _logger.LogInformation("Revoked {Count} token(s) for user {UserId}", activeTokens.Count, userId);
        return activeTokens.Count;
    }

    /// <summary>
    /// Get active sessions (tokens) for a user
    /// </summary>
    public async Task<List<UserSession>> GetUserSessionsAsync(Guid userId)
    {
        var tokens = await _context.RefreshTokens
            .Where(t => t.UserId == userId && !t.IsRevoked && t.ExpiresAt > DateTime.UtcNow)
            .OrderByDescending(t => t.CreatedAt)
            .Select(t => new UserSession
            {
                TokenId = t.Id,
                CreatedAt = t.CreatedAt,
                ExpiresAt = t.ExpiresAt,
                IpAddress = t.IpAddress,
                UserAgent = t.UserAgent
            })
            .ToListAsync();

        return tokens;
    }

    private async Task<RefreshToken> CreateRefreshTokenAsync(Guid userId, string? ipAddress, int? overrideDays = null)
    {
        var expiresAt = DateTime.UtcNow.AddDays(overrideDays ?? _config.RefreshTokenExpirationDays);
        _logger.LogDebug("Creating refresh token for user {UserId}, expires at {ExpiresAt}", userId, expiresAt);

        var refreshToken = new RefreshToken
        {
            Token = GenerateSecureToken(),
            UserId = userId,
            ExpiresAt = expiresAt,
            IpAddress = ipAddress
        };

        _context.RefreshTokens.Add(refreshToken);
        await _context.SaveChangesAsync();

        _logger.LogDebug("Refresh token created for user {UserId}, token ID: {TokenId}", userId, refreshToken.Id);

        return refreshToken;
    }

    private static string GenerateSecureToken()
    {
        var bytes = new byte[32];
        using var rng = RandomNumberGenerator.Create();
        rng.GetBytes(bytes);
        return Convert.ToBase64String(bytes).Replace("+", "-").Replace("/", "_").TrimEnd('=');
    }

    private UserInfo CreateUserInfo(User user, Dictionary<string, string> appRoles)
    {
        return new UserInfo
        {
            Id = user.Id,
            Email = user.Email,
            DisplayName = user.DisplayName,
            GlobalAccessLevel = (int)user.GlobalAccessLevel,
            Department = user.Department,
            // 20260317 GHS Test Ad/Entra Start -->
            AuthMethod = user.AuthMethod,
            // <--20260317 GHS Test Ad/Entra End
            AppRoles = appRoles,
            Tenant = user.Tenant != null ? new TenantInfo
            {
                Id = user.Tenant.Id,
                Domain = user.Tenant.Domain,
                DisplayName = user.Tenant.DisplayName,
                PrimaryColor = user.Tenant.PrimaryColor,
                LogoUrl = user.Tenant.LogoUrl,
                HasLogoData = user.Tenant.LogoData != null && user.Tenant.LogoData.Length > 0,
                AppRouting = user.Tenant.GetAppRouting()
            } : null
        };
    }

    #endregion
}
