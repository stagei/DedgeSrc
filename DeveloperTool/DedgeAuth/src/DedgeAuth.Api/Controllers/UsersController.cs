using System.Text.Json;
using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Mvc;
using Microsoft.EntityFrameworkCore;
using Microsoft.Extensions.Options;
using DedgeAuth.Core.Models;
using DedgeAuth.Data;
using DedgeAuth.Services;

namespace DedgeAuth.Api.Controllers;

/// <summary>
/// User management controller
/// </summary>
[ApiController]
[Route("api/[controller]")]
[Authorize]
public class UsersController : ControllerBase
{
    private readonly AuthDbContext _context;
    private readonly AuthService _authService;
    private readonly AuthConfiguration _authConfig;
    private readonly ILogger<UsersController> _logger;

    public UsersController(AuthDbContext context, AuthService authService, IOptions<AuthConfiguration> authConfig, ILogger<UsersController> logger)
    {
        _context = context;
        _authService = authService;
        _authConfig = authConfig.Value;
        _logger = logger;
    }

    private bool IsGlobalAdmin()
    {
        var level = User.FindFirst("globalAccessLevel")?.Value;
        return level == "3";
    }

    private bool IsTenantAdmin()
    {
        var level = User.FindFirst("globalAccessLevel")?.Value;
        return level == "5";
    }

    private string? GetCurrentUserTenantDomain()
    {
        var tenantJson = User.FindFirst("tenant")?.Value;
        if (string.IsNullOrEmpty(tenantJson)) return null;
        try
        {
            using var doc = JsonDocument.Parse(tenantJson);
            return doc.RootElement.GetProperty("domain").GetString();
        }
        catch
        {
            return null;
        }
    }

    /// <summary>
    /// Get the list of protected admin emails (configured in appsettings)
    /// </summary>
    [HttpGet("protected-emails")]
    [Authorize(Policy = "GlobalAdmin")]
    public IActionResult GetProtectedEmails()
    {
        return Ok(_authConfig.AdminEmails ?? new List<string>());
    }

    /// <summary>
    /// Get all users. TenantAdmins see only users in their own tenant.
    /// </summary>
    [HttpGet]
    [Authorize(Policy = "TenantOrGlobalAdmin")]
    public async Task<IActionResult> GetUsers()
    {
        var query = _context.Users.Include(u => u.Tenant).AsQueryable();

        if (IsTenantAdmin())
        {
            var tenantDomain = GetCurrentUserTenantDomain();
            if (!string.IsNullOrEmpty(tenantDomain))
                query = query.Where(u => u.Tenant != null && u.Tenant.Domain == tenantDomain);
        }

        var users = await query
            .Select(u => new
            {
                u.Id,
                u.Email,
                u.DisplayName,
                u.GlobalAccessLevel,
                u.IsActive,
                u.EmailVerified,
                u.CreatedAt,
                u.LastLoginAt,
                TenantDomain = u.Tenant != null ? u.Tenant.Domain : null
            })
            .ToListAsync();

        return Ok(users);
    }

    /// <summary>
    /// Get user by ID
    /// </summary>
    [HttpGet("{userId:guid}")]
    public async Task<IActionResult> GetUser(Guid userId)
    {
        var user = await _context.Users
            .Include(u => u.Tenant)
            .Include(u => u.AppPermissions)
            .ThenInclude(p => p.App)
            .FirstOrDefaultAsync(u => u.Id == userId);

        if (user == null)
        {
            return NotFound(new { message = "User not found" });
        }

        return Ok(new
        {
            user.Id,
            user.Email,
            user.DisplayName,
            user.GlobalAccessLevel,
            user.IsActive,
            user.EmailVerified,
            user.CreatedAt,
            user.LastLoginAt,
            user.Department,
            Tenant = user.Tenant != null ? new { user.Tenant.Domain, user.Tenant.DisplayName } : null,
            Permissions = user.AppPermissions.Select(p => new
            {
                AppId = p.App?.AppId,
                AppName = p.App?.DisplayName,
                p.Role
            })
        });
    }

    /// <summary>
    /// Update user. TenantAdmins can only update users in their own tenant
    /// and cannot assign Admin or TenantAdmin roles.
    /// </summary>
    [HttpPut("{userId:guid}")]
    [Authorize(Policy = "TenantOrGlobalAdmin")]
    public async Task<IActionResult> UpdateUser(Guid userId, [FromBody] UpdateUserRequest request)
    {
        var user = await _context.Users.Include(u => u.Tenant).FirstOrDefaultAsync(u => u.Id == userId);
        if (user == null)
            return NotFound(new { message = "User not found" });

        if (IsTenantAdmin())
        {
            var tenantDomain = GetCurrentUserTenantDomain();
            if (user.Tenant?.Domain != tenantDomain)
                return Forbid();

            if (request.GlobalAccessLevel.HasValue)
            {
                var level = (AccessLevel)request.GlobalAccessLevel.Value;
                if (level == AccessLevel.Admin || level == AccessLevel.TenantAdmin)
                    return BadRequest(new { message = "TenantAdmins cannot assign Admin or TenantAdmin roles" });
            }
        }

        var isProtectedAdmin = (_authConfig.AdminEmails ?? new List<string>())
            .Any(e => string.Equals(e, user.Email, StringComparison.OrdinalIgnoreCase));

        if (isProtectedAdmin && request.GlobalAccessLevel.HasValue && (AccessLevel)request.GlobalAccessLevel.Value != AccessLevel.Admin)
            return BadRequest(new { message = $"Cannot change access level for protected admin user {user.Email}" });

        if (isProtectedAdmin && request.IsActive.HasValue && !request.IsActive.Value)
            return BadRequest(new { message = $"Cannot deactivate protected admin user {user.Email}" });

        if (request.DisplayName != null)
            user.DisplayName = request.DisplayName;
        if (request.GlobalAccessLevel.HasValue)
            user.GlobalAccessLevel = (AccessLevel)request.GlobalAccessLevel.Value;
        if (request.IsActive.HasValue)
            user.IsActive = request.IsActive.Value;
        if (request.EmailVerified.HasValue)
            user.EmailVerified = request.EmailVerified.Value;
        if (request.Department != null)
            user.Department = request.Department;

        await _context.SaveChangesAsync();
        _logger.LogInformation("User updated: {UserId}", userId);

        return Ok(new { message = "User updated" });
    }

    /// <summary>
    /// Delete user
    /// </summary>
    [HttpDelete("{userId:guid}")]
    [Authorize(Policy = "TenantOrGlobalAdmin")]
    public async Task<IActionResult> DeleteUser(Guid userId)
    {
        var user = await _context.Users.Include(u => u.Tenant).FirstOrDefaultAsync(u => u.Id == userId);
        if (user == null)
            return NotFound(new { message = "User not found" });

        if (IsTenantAdmin() && user.Tenant?.Domain != GetCurrentUserTenantDomain())
            return Forbid();

        var isProtectedAdmin = (_authConfig.AdminEmails ?? new List<string>())
            .Any(e => string.Equals(e, user.Email, StringComparison.OrdinalIgnoreCase));

        if (isProtectedAdmin)
            return BadRequest(new { message = $"Cannot deactivate protected admin user {user.Email}" });

        user.IsActive = false;
        await _context.SaveChangesAsync();

        return Ok(new { message = "User deactivated" });
    }

    /// <summary>
    /// Search users
    /// </summary>
    [HttpGet("search")]
    public async Task<IActionResult> SearchUsers([FromQuery] string q)
    {
        var users = await _context.Users
            .Where(u => u.Email.Contains(q) || u.DisplayName.Contains(q))
            .Take(20)
            .Select(u => new
            {
                u.Id,
                u.Email,
                u.DisplayName,
                u.GlobalAccessLevel
            })
            .ToListAsync();

        return Ok(users);
    }

    /// <summary>
    /// Get pending users (not yet verified or not yet approved)
    /// </summary>
    [HttpGet("pending")]
    [Authorize(Policy = "TenantOrGlobalAdmin")]
    public async Task<IActionResult> GetPendingUsers()
    {
        var query = _context.Users.Include(u => u.Tenant).AsQueryable();

        if (IsTenantAdmin())
        {
            var tenantDomain = GetCurrentUserTenantDomain();
            if (!string.IsNullOrEmpty(tenantDomain))
                query = query.Where(u => u.Tenant != null && u.Tenant.Domain == tenantDomain);
        }

        var pendingUsers = await query
            .Where(u => !u.EmailVerified || !u.IsActive)
            .OrderByDescending(u => u.CreatedAt)
            .Select(u => new
            {
                u.Id,
                u.Email,
                u.DisplayName,
                u.GlobalAccessLevel,
                u.IsActive,
                u.EmailVerified,
                u.CreatedAt,
                u.Department,
                TenantDomain = u.Tenant != null ? u.Tenant.Domain : null,
                Status = !u.EmailVerified ? "Pending Verification" : (!u.IsActive ? "Deactivated" : "Active")
            })
            .ToListAsync();

        return Ok(pendingUsers);
    }

    /// <summary>
    /// Approve a pending user (verify email and activate)
    /// </summary>
    [HttpPost("{userId:guid}/approve")]
    [Authorize(Policy = "TenantOrGlobalAdmin")]
    public async Task<IActionResult> ApproveUser(Guid userId, [FromBody] ApproveUserRequest? request = null)
    {
        var user = await _context.Users.FindAsync(userId);
        if (user == null)
        {
            return NotFound(new { message = "User not found" });
        }

        user.EmailVerified = true;
        user.IsActive = true;
        
        if (request?.GlobalAccessLevel.HasValue == true)
        {
            user.GlobalAccessLevel = (AccessLevel)request.GlobalAccessLevel.Value;
        }

        await _context.SaveChangesAsync();
        
        var adminEmail = User.FindFirst("email")?.Value ?? User.FindFirst(System.Security.Claims.ClaimTypes.Email)?.Value;
        _logger.LogInformation("Admin {AdminEmail} approved user {UserEmail} ({UserId}) with access level {AccessLevel}", 
            adminEmail, user.Email, userId, user.GlobalAccessLevel);

        return Ok(new { message = $"User {user.Email} approved", accessLevel = (int)user.GlobalAccessLevel });
    }

    /// <summary>
    /// Reject a pending user (delete account)
    /// </summary>
    [HttpPost("{userId:guid}/reject")]
    [Authorize(Policy = "TenantOrGlobalAdmin")]
    public async Task<IActionResult> RejectUser(Guid userId)
    {
        var user = await _context.Users.FindAsync(userId);
        if (user == null)
        {
            return NotFound(new { message = "User not found" });
        }

        var adminEmail = User.FindFirst("email")?.Value ?? User.FindFirst(System.Security.Claims.ClaimTypes.Email)?.Value;
        _logger.LogInformation("Admin {AdminEmail} rejected user {UserEmail} ({UserId})", 
            adminEmail, user.Email, userId);

        // Remove all permissions, tokens, and pending access requests
        var permissions = await _context.AppPermissions.Where(p => p.UserId == userId).ToListAsync();
        _context.AppPermissions.RemoveRange(permissions);
        
        var tokens = await _context.RefreshTokens.Where(t => t.UserId == userId).ToListAsync();
        _context.RefreshTokens.RemoveRange(tokens);

        var loginTokens = await _context.LoginTokens.Where(t => t.UserId == userId).ToListAsync();
        _context.LoginTokens.RemoveRange(loginTokens);

        var pendingRequests = await _context.AccessRequests
            .Where(r => r.UserId == userId && r.Status == AccessRequest.StatusPending)
            .ToListAsync();
        foreach (var req in pendingRequests)
        {
            req.Status = AccessRequest.StatusRejected;
            req.ReviewedBy = adminEmail;
            req.ReviewNote = "User registration rejected";
            req.ReviewedAt = DateTime.UtcNow;
        }

        _context.Users.Remove(user);
        await _context.SaveChangesAsync();

        return Ok(new { message = $"User {user.Email} rejected and removed" });
    }

    /// <summary>
    /// Get active sessions for a user
    /// </summary>
    [HttpGet("{userId:guid}/sessions")]
    [Authorize(Policy = "GlobalAdmin")]
    public async Task<IActionResult> GetUserSessions(Guid userId)
    {
        var user = await _context.Users.FindAsync(userId);
        if (user == null)
        {
            return NotFound(new { message = "User not found" });
        }

        var sessions = await _authService.GetUserSessionsAsync(userId);
        return Ok(new
        {
            userId,
            email = user.Email,
            activeSessions = sessions.Count,
            sessions
        });
    }

    /// <summary>
    /// Revoke all tokens for a user (force logout from all devices)
    /// </summary>
    [HttpPost("{userId:guid}/revoke-tokens")]
    [Authorize(Policy = "GlobalAdmin")]
    public async Task<IActionResult> RevokeUserTokens(Guid userId)
    {
        var user = await _context.Users.FindAsync(userId);
        if (user == null)
        {
            return NotFound(new { message = "User not found" });
        }

        var adminEmail = User.FindFirst("email")?.Value ?? User.FindFirst(System.Security.Claims.ClaimTypes.Email)?.Value;
        var revokedCount = await _authService.RevokeAllUserTokensAsync(userId, adminEmail);

        _logger.LogInformation("Admin {AdminEmail} revoked {Count} token(s) for user {UserEmail} ({UserId})", 
            adminEmail, revokedCount, user.Email, userId);

        return Ok(new
        {
            message = $"Revoked {revokedCount} active session(s) for {user.Email}",
            revokedCount,
            userId,
            email = user.Email
        });
    }

    /// <summary>
    /// Revoke all tokens for all users (emergency admin action)
    /// </summary>
    [HttpPost("revoke-all-tokens")]
    [Authorize(Policy = "GlobalAdmin")]
    public async Task<IActionResult> RevokeAllTokens()
    {
        var adminEmail = User.FindFirst("email")?.Value ?? User.FindFirst(System.Security.Claims.ClaimTypes.Email)?.Value;
        _logger.LogWarning("Admin {AdminEmail} initiated revocation of ALL tokens", adminEmail);

        var activeTokens = await _context.RefreshTokens
            .Where(t => !t.IsRevoked && t.ExpiresAt > DateTime.UtcNow)
            .ToListAsync();

        foreach (var token in activeTokens)
        {
            token.IsRevoked = true;
            token.RevokedAt = DateTime.UtcNow;
        }

        await _context.SaveChangesAsync();

        _logger.LogWarning("Admin {AdminEmail} revoked {Count} token(s) across all users", adminEmail, activeTokens.Count);

        return Ok(new
        {
            message = $"Revoked {activeTokens.Count} active session(s) across all users",
            revokedCount = activeTokens.Count
        });
    }

    /// <summary>
    /// Admin creates a new user directly (pre-approved, email verified, active)
    /// </summary>
    [HttpPost("create")]
    [Authorize(Policy = "TenantOrGlobalAdmin")]
    public async Task<IActionResult> CreateUser([FromBody] AdminCreateUserRequest request)
    {
        if (string.IsNullOrWhiteSpace(request.Email) || string.IsNullOrWhiteSpace(request.DisplayName))
            return BadRequest(new { message = "Email and displayName are required" });

        var existing = await _context.Users.AnyAsync(u => u.Email == request.Email.Trim().ToLower());
        if (existing)
            return Conflict(new { message = $"User with email {request.Email} already exists" });

        var accessLevel = request.GlobalAccessLevel.HasValue
            ? (AccessLevel)request.GlobalAccessLevel.Value
            : AccessLevel.User;

        if (IsTenantAdmin() && (accessLevel == AccessLevel.Admin || accessLevel == AccessLevel.TenantAdmin))
            return BadRequest(new { message = "TenantAdmins cannot create Admin or TenantAdmin users" });

        var user = new User
        {
            Email = request.Email.Trim().ToLower(),
            DisplayName = request.DisplayName.Trim(),
            GlobalAccessLevel = accessLevel,
            EmailVerified = true,
            IsActive = true
        };

        if (!string.IsNullOrWhiteSpace(request.Password))
        {
            user.PasswordHash = BCrypt.Net.BCrypt.HashPassword(request.Password);
        }

        // Resolve tenant from email domain
        var domain = user.Email.Split('@').LastOrDefault();
        if (!string.IsNullOrEmpty(domain))
        {
            var tenant = await _context.Tenants.FirstOrDefaultAsync(t => t.Domain == domain);
            if (tenant != null)
                user.TenantId = tenant.Id;
        }

        _context.Users.Add(user);

        if (request.AppPermissions != null)
        {
            foreach (var perm in request.AppPermissions)
            {
                var app = await _context.Apps.FirstOrDefaultAsync(a => a.AppId == perm.AppId);
                if (app != null)
                {
                    _context.AppPermissions.Add(new AppPermission
                    {
                        UserId = user.Id,
                        AppId = app.Id,
                        Role = perm.Role,
                        GrantedBy = User.FindFirst(System.Security.Claims.ClaimTypes.Email)?.Value ?? "Admin"
                    });
                }
            }
        }

        await _context.SaveChangesAsync();

        var adminEmail = User.FindFirst(System.Security.Claims.ClaimTypes.Email)?.Value;
        _logger.LogInformation("Admin {AdminEmail} created user {UserEmail} ({UserId}) with access level {AccessLevel}",
            adminEmail, user.Email, user.Id, user.GlobalAccessLevel);

        return Ok(new { message = $"User {user.Email} created", userId = user.Id });
    }
}

public record AdminCreateUserRequest(
    string Email,
    string DisplayName,
    string? Password,
    int? GlobalAccessLevel,
    List<AdminAppPermissionDto>? AppPermissions);

public record AdminAppPermissionDto(string AppId, string Role);

public record UpdateUserRequest(
    string? DisplayName, 
    int? GlobalAccessLevel, 
    bool? IsActive, 
    bool? EmailVerified,
    string? Department);

public record ApproveUserRequest(int? GlobalAccessLevel);
