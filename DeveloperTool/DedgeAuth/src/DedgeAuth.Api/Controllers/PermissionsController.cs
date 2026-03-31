using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Mvc;
using Microsoft.EntityFrameworkCore;
using DedgeAuth.Core.Models;
using DedgeAuth.Data;

namespace DedgeAuth.Api.Controllers;

/// <summary>
/// App permission management controller
/// </summary>
[ApiController]
[Route("api/[controller]")]
[Authorize]
public class PermissionsController : ControllerBase
{
    private readonly AuthDbContext _context;
    private readonly ILogger<PermissionsController> _logger;

    public PermissionsController(AuthDbContext context, ILogger<PermissionsController> logger)
    {
        _context = context;
        _logger = logger;
    }

    /// <summary>
    /// Get permissions for a user
    /// </summary>
    [HttpGet("user/{userId:guid}")]
    public async Task<IActionResult> GetUserPermissions(Guid userId)
    {
        var permissions = await _context.AppPermissions
            .Include(p => p.App)
            .Where(p => p.UserId == userId)
            .Select(p => new
            {
                p.Id,
                AppId = p.App!.AppId,
                AppName = p.App.DisplayName,
                p.Role,
                p.GrantedAt,
                p.GrantedBy
            })
            .ToListAsync();

        return Ok(permissions);
    }

    /// <summary>
    /// Get permissions for an app
    /// </summary>
    [HttpGet("app/{appId}")]
    public async Task<IActionResult> GetAppPermissions(string appId)
    {
        var permissions = await _context.AppPermissions
            .Include(p => p.App)
            .Include(p => p.User)
            .Where(p => p.App!.AppId == appId)
            .Select(p => new
            {
                p.Id,
                UserId = p.User!.Id,
                UserEmail = p.User.Email,
                UserName = p.User.DisplayName,
                p.Role,
                p.GrantedAt,
                p.GrantedBy
            })
            .ToListAsync();

        return Ok(permissions);
    }

    /// <summary>
    /// Grant permission to user for an app
    /// </summary>
    [HttpPost]
    [Authorize(Policy = "GlobalAdmin")]
    public async Task<IActionResult> GrantPermission([FromBody] GrantPermissionRequest request)
    {
        var user = await _context.Users.FirstOrDefaultAsync(u => u.Id == request.UserId);
        if (user == null)
        {
            return NotFound(new { message = "User not found" });
        }

        var app = await _context.Apps.FirstOrDefaultAsync(a => a.AppId == request.AppId);
        if (app == null)
        {
            return NotFound(new { message = "App not found" });
        }

        // Check if valid role
        var availableRoles = app.GetAvailableRoles();
        if (!availableRoles.Contains(request.Role))
        {
            return BadRequest(new { message = $"Invalid role. Available: {string.Join(", ", availableRoles)}" });
        }

        // Check for existing permission
        var existing = await _context.AppPermissions
            .FirstOrDefaultAsync(p => p.UserId == request.UserId && p.AppId == app.Id);

        if (existing != null)
        {
            existing.Role = request.Role;
            existing.GrantedAt = DateTime.UtcNow;
            existing.GrantedBy = GetCurrentUserEmail();
        }
        else
        {
            var permission = new AppPermission
            {
                UserId = request.UserId,
                AppId = app.Id,
                Role = request.Role,
                GrantedBy = GetCurrentUserEmail()
            };
            _context.AppPermissions.Add(permission);
        }

        await _context.SaveChangesAsync();
        _logger.LogInformation("Permission granted: {UserId} -> {AppId} = {Role}", request.UserId, request.AppId, request.Role);

        return Ok(new { message = "Permission granted" });
    }

    /// <summary>
    /// Revoke permission
    /// </summary>
    [HttpDelete("{permissionId:guid}")]
    [Authorize(Policy = "GlobalAdmin")]
    public async Task<IActionResult> RevokePermission(Guid permissionId)
    {
        var permission = await _context.AppPermissions.FindAsync(permissionId);
        if (permission == null)
        {
            return NotFound(new { message = "Permission not found" });
        }

        _context.AppPermissions.Remove(permission);
        await _context.SaveChangesAsync();

        return Ok(new { message = "Permission revoked" });
    }

    private string GetCurrentUserEmail()
    {
        return User.FindFirst(System.Security.Claims.ClaimTypes.Email)?.Value ?? "System";
    }
}

public record GrantPermissionRequest(Guid UserId, string AppId, string Role);
