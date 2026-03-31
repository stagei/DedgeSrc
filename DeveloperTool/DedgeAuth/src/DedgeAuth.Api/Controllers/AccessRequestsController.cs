using System.Text.Json;
using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Mvc;
using Microsoft.EntityFrameworkCore;
using DedgeAuth.Core.Models;
using DedgeAuth.Data;

namespace DedgeAuth.Api.Controllers;

/// <summary>
/// Access request management — users request app access / role changes,
/// admins approve or reject.
/// </summary>
[ApiController]
[Route("api/access-requests")]
[Authorize]
public class AccessRequestsController : ControllerBase
{
    private readonly AuthDbContext _context;
    private readonly ILogger<AccessRequestsController> _logger;

    public AccessRequestsController(AuthDbContext context, ILogger<AccessRequestsController> logger)
    {
        _context = context;
        _logger = logger;
    }

    /// <summary>
    /// Create a new access request (any authenticated user)
    /// </summary>
    [HttpPost]
    public async Task<IActionResult> CreateRequest([FromBody] CreateAccessRequestDto dto)
    {
        var userId = GetCurrentUserId();
        if (userId == null)
            return Unauthorized();

        if (string.IsNullOrWhiteSpace(dto.RequestType))
            return BadRequest(new { message = "requestType is required" });

        var validTypes = new[] { AccessRequest.TypeAppAccess, AccessRequest.TypeRoleChange, AccessRequest.TypeAccessLevelChange };
        if (!validTypes.Contains(dto.RequestType))
            return BadRequest(new { message = $"Invalid requestType. Valid: {string.Join(", ", validTypes)}" });

        App? app = null;

        if (dto.RequestType is AccessRequest.TypeAppAccess or AccessRequest.TypeRoleChange)
        {
            if (string.IsNullOrWhiteSpace(dto.AppId))
                return BadRequest(new { message = "appId is required for app access or role change requests" });

            app = await _context.Apps.FirstOrDefaultAsync(a => a.AppId == dto.AppId);
            if (app == null)
                return NotFound(new { message = $"App '{dto.AppId}' not found" });

            if (string.IsNullOrWhiteSpace(dto.RequestedRole))
                return BadRequest(new { message = "requestedRole is required for app access or role change requests" });

            var availableRoles = app.GetAvailableRoles();
            if (!availableRoles.Contains(dto.RequestedRole))
                return BadRequest(new { message = $"Invalid role. Available for {app.DisplayName}: {string.Join(", ", availableRoles)}" });

            var hasDuplicate = await _context.AccessRequests.AnyAsync(r =>
                r.UserId == userId.Value &&
                r.AppId == app.Id &&
                r.Status == AccessRequest.StatusPending);

            if (hasDuplicate)
                return Conflict(new { message = "You already have a pending request for this app" });

            if (dto.RequestType == AccessRequest.TypeAppAccess)
            {
                var alreadyHasAccess = await _context.AppPermissions.AnyAsync(p =>
                    p.UserId == userId.Value && p.AppId == app.Id);
                if (alreadyHasAccess)
                    return BadRequest(new { message = "You already have access to this app. Use RoleChange to request a different role." });
            }
        }

        if (dto.RequestType == AccessRequest.TypeAccessLevelChange)
        {
            if (!dto.RequestedAccessLevel.HasValue)
                return BadRequest(new { message = "requestedAccessLevel is required for access level change requests" });

            if (!Enum.IsDefined(typeof(AccessLevel), dto.RequestedAccessLevel.Value))
                return BadRequest(new { message = "Invalid access level value" });

            var hasDuplicate = await _context.AccessRequests.AnyAsync(r =>
                r.UserId == userId.Value &&
                r.AppId == null &&
                r.RequestType == AccessRequest.TypeAccessLevelChange &&
                r.Status == AccessRequest.StatusPending);

            if (hasDuplicate)
                return Conflict(new { message = "You already have a pending access level change request" });
        }

        var request = new AccessRequest
        {
            UserId = userId.Value,
            AppId = app?.Id,
            RequestType = dto.RequestType,
            RequestedRole = dto.RequestedRole,
            RequestedAccessLevel = dto.RequestedAccessLevel,
            Reason = dto.Reason
        };

        _context.AccessRequests.Add(request);
        await _context.SaveChangesAsync();

        _logger.LogInformation("Access request created: {UserId} -> {RequestType} {AppId} {Role}",
            userId, dto.RequestType, dto.AppId ?? "(global)", dto.RequestedRole ?? $"level={dto.RequestedAccessLevel}");

        return Ok(new { message = "Access request submitted", requestId = request.Id });
    }

    /// <summary>
    /// Get current user's access requests
    /// </summary>
    [HttpGet("my")]
    public async Task<IActionResult> GetMyRequests()
    {
        var userId = GetCurrentUserId();
        if (userId == null)
            return Unauthorized();

        var requests = await _context.AccessRequests
            .Include(r => r.App)
            .Where(r => r.UserId == userId.Value)
            .OrderByDescending(r => r.CreatedAt)
            .Select(r => new
            {
                r.Id,
                r.RequestType,
                AppId = r.App != null ? r.App.AppId : null,
                AppName = r.App != null ? r.App.DisplayName : null,
                r.RequestedRole,
                r.RequestedAccessLevel,
                r.Reason,
                r.Status,
                r.ReviewNote,
                r.CreatedAt,
                r.ReviewedAt
            })
            .ToListAsync();

        return Ok(requests);
    }

    /// <summary>
    /// Get all pending access requests (admin view).
    /// Includes a userApproved flag so the frontend knows whether to enable the approve button.
    /// </summary>
    [HttpGet("pending")]
    [Authorize(Policy = "TenantOrGlobalAdmin")]
    public async Task<IActionResult> GetPendingRequests()
    {
        var isTenantAdmin = User.FindFirst("globalAccessLevel")?.Value == "5";
        string? tenantDomain = null;

        if (isTenantAdmin)
        {
            var tenantJson = User.FindFirst("tenant")?.Value;
            if (!string.IsNullOrEmpty(tenantJson))
            {
                try
                {
                    using var doc = JsonDocument.Parse(tenantJson);
                    tenantDomain = doc.RootElement.GetProperty("domain").GetString();
                }
                catch { }
            }
        }

        var query = _context.AccessRequests
            .Include(r => r.User).ThenInclude(u => u!.Tenant)
            .Include(r => r.App)
            .Where(r => r.Status == AccessRequest.StatusPending);

        if (isTenantAdmin && !string.IsNullOrEmpty(tenantDomain))
        {
            query = query.Where(r => r.User != null && r.User.Tenant != null && r.User.Tenant.Domain == tenantDomain);
        }

        var requests = await query
            .OrderByDescending(r => r.CreatedAt)
            .Select(r => new
            {
                r.Id,
                r.UserId,
                UserEmail = r.User != null ? r.User.Email : null,
                UserDisplayName = r.User != null ? r.User.DisplayName : null,
                UserApproved = r.User != null && r.User.EmailVerified && r.User.IsActive,
                r.RequestType,
                AppId = r.App != null ? r.App.AppId : null,
                AppName = r.App != null ? r.App.DisplayName : null,
                AvailableRoles = r.App != null ? r.App.AvailableRolesJson : null,
                r.RequestedRole,
                r.RequestedAccessLevel,
                r.Reason,
                r.Status,
                r.CreatedAt
            })
            .ToListAsync();

        var result = requests.Select(r => new
        {
            r.Id,
            r.UserId,
            r.UserEmail,
            r.UserDisplayName,
            r.UserApproved,
            r.RequestType,
            r.AppId,
            r.AppName,
            AvailableRoles = ParseRoles(r.AvailableRoles),
            r.RequestedRole,
            r.RequestedAccessLevel,
            r.Reason,
            r.Status,
            r.CreatedAt
        });

        return Ok(result);
    }

    /// <summary>
    /// Approve an access request — creates/updates AppPermission or updates AccessLevel
    /// </summary>
    [HttpPost("{id:guid}/approve")]
    [Authorize(Policy = "TenantOrGlobalAdmin")]
    public async Task<IActionResult> ApproveRequest(Guid id, [FromBody] ReviewAccessRequestDto? dto = null)
    {
        var request = await _context.AccessRequests
            .Include(r => r.User)
            .Include(r => r.App)
            .FirstOrDefaultAsync(r => r.Id == id);

        if (request == null)
            return NotFound(new { message = "Access request not found" });

        if (request.Status != AccessRequest.StatusPending)
            return BadRequest(new { message = $"Request is already {request.Status}" });

        if (request.User == null)
            return BadRequest(new { message = "Associated user not found" });

        if (!request.User.EmailVerified || !request.User.IsActive)
            return BadRequest(new { message = "User must be approved first before granting app access" });

        var adminEmail = GetCurrentUserEmail();
        var approvedRole = dto?.Role ?? request.RequestedRole;
        var approvedAccessLevel = dto?.AccessLevel ?? request.RequestedAccessLevel;

        if (request.RequestType is AccessRequest.TypeAppAccess or AccessRequest.TypeRoleChange)
        {
            if (request.App == null)
                return BadRequest(new { message = "Associated app not found" });

            if (string.IsNullOrWhiteSpace(approvedRole))
                return BadRequest(new { message = "Role is required" });

            var existing = await _context.AppPermissions
                .FirstOrDefaultAsync(p => p.UserId == request.UserId && p.AppId == request.AppId!.Value);

            if (existing != null)
            {
                existing.Role = approvedRole;
                existing.GrantedAt = DateTime.UtcNow;
                existing.GrantedBy = adminEmail;
            }
            else
            {
                _context.AppPermissions.Add(new AppPermission
                {
                    UserId = request.UserId,
                    AppId = request.AppId!.Value,
                    Role = approvedRole,
                    GrantedBy = adminEmail
                });
            }
        }
        else if (request.RequestType == AccessRequest.TypeAccessLevelChange)
        {
            if (!approvedAccessLevel.HasValue || !Enum.IsDefined(typeof(AccessLevel), approvedAccessLevel.Value))
                return BadRequest(new { message = "Valid access level is required" });

            request.User.GlobalAccessLevel = (AccessLevel)approvedAccessLevel.Value;
        }

        request.Status = AccessRequest.StatusApproved;
        request.ReviewedBy = adminEmail;
        request.ReviewNote = dto?.Note;
        request.ReviewedAt = DateTime.UtcNow;

        await _context.SaveChangesAsync();

        _logger.LogInformation("Access request {RequestId} approved by {Admin} for user {UserEmail}",
            id, adminEmail, request.User.Email);

        return Ok(new { message = "Request approved" });
    }

    /// <summary>
    /// Reject an access request
    /// </summary>
    [HttpPost("{id:guid}/reject")]
    [Authorize(Policy = "TenantOrGlobalAdmin")]
    public async Task<IActionResult> RejectRequest(Guid id, [FromBody] ReviewAccessRequestDto? dto = null)
    {
        var request = await _context.AccessRequests
            .Include(r => r.User)
            .FirstOrDefaultAsync(r => r.Id == id);

        if (request == null)
            return NotFound(new { message = "Access request not found" });

        if (request.Status != AccessRequest.StatusPending)
            return BadRequest(new { message = $"Request is already {request.Status}" });

        var adminEmail = GetCurrentUserEmail();

        request.Status = AccessRequest.StatusRejected;
        request.ReviewedBy = adminEmail;
        request.ReviewNote = dto?.Note;
        request.ReviewedAt = DateTime.UtcNow;

        await _context.SaveChangesAsync();

        _logger.LogInformation("Access request {RequestId} rejected by {Admin} for user {UserEmail}",
            id, adminEmail, request.User?.Email ?? "unknown");

        return Ok(new { message = "Request rejected" });
    }

    private Guid? GetCurrentUserId()
    {
        var val = User.FindFirst(System.Security.Claims.ClaimTypes.NameIdentifier)?.Value;
        return Guid.TryParse(val, out var id) ? id : null;
    }

    private string GetCurrentUserEmail()
    {
        return User.FindFirst(System.Security.Claims.ClaimTypes.Email)?.Value
            ?? User.FindFirst("email")?.Value
            ?? "System";
    }

    private static List<string>? ParseRoles(string? json)
    {
        if (string.IsNullOrEmpty(json)) return null;
        try { return JsonSerializer.Deserialize<List<string>>(json); }
        catch { return null; }
    }
}

public record CreateAccessRequestDto(
    string RequestType,
    string? AppId,
    string? RequestedRole,
    int? RequestedAccessLevel,
    string? Reason);

public record ReviewAccessRequestDto(
    string? Role,
    int? AccessLevel,
    string? Note);
