using System.IdentityModel.Tokens.Jwt;
using System.Text.Json;
using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Mvc;
using Microsoft.EntityFrameworkCore;
using DedgeAuth.Core.Models;
using DedgeAuth.Data;
using DedgeAuth.Services;

namespace DedgeAuth.Api.Controllers;

/// <summary>
/// Application management controller
/// </summary>
[ApiController]
[Route("api/[controller]")]
[Authorize]
public class AppsController : ControllerBase
{
    private readonly AuthDbContext _context;
    private readonly AppGroupAccessService _treeService;
    private readonly ILogger<AppsController> _logger;

    public AppsController(AuthDbContext context, AppGroupAccessService treeService, ILogger<AppsController> logger)
    {
        _context = context;
        _treeService = treeService;
        _logger = logger;
    }

    /// <summary>
    /// Get all apps (public endpoint for URL fallback)
    /// </summary>
    [HttpGet]
    [AllowAnonymous]
    public async Task<IActionResult> GetApps()
    {
        var apps = await _context.Apps
            .Where(a => a.IsActive)
            .Select(a => new
            {
                a.Id,
                a.AppId,
                a.DisplayName,
                a.Description,
                a.BaseUrl,
                a.IconUrl,
                AvailableRoles = a.GetAvailableRoles()
            })
            .ToListAsync();

        return Ok(apps);
    }

    /// <summary>
    /// Get app by ID
    /// </summary>
    [HttpGet("{appId}")]
    public async Task<IActionResult> GetApp(string appId)
    {
        var app = await _context.Apps
            .FirstOrDefaultAsync(a => a.AppId == appId);

        if (app == null)
        {
            return NotFound(new { message = "App not found" });
        }

        return Ok(new
        {
            app.Id,
            app.AppId,
            app.DisplayName,
            app.Description,
            app.BaseUrl,
            app.IconUrl,
            AvailableRoles = app.GetAvailableRoles()
        });
    }

    /// <summary>
    /// Register a new app
    /// </summary>
    [HttpPost]
    [Authorize(Policy = "GlobalAdmin")]
    public async Task<IActionResult> CreateApp([FromBody] CreateAppRequest request)
    {
        if (await _context.Apps.AnyAsync(a => a.AppId == request.AppId))
        {
            return BadRequest(new { message = "App ID already exists" });
        }

        var app = new App
        {
            AppId = request.AppId,
            DisplayName = request.DisplayName,
            Description = request.Description,
            BaseUrl = request.BaseUrl,
            IconUrl = request.IconUrl
        };
        app.SetAvailableRoles(request.AvailableRoles ?? new List<string> { "ReadOnly", "User", "PowerUser", "Admin" });

        _context.Apps.Add(app);
        await _context.SaveChangesAsync();

        _logger.LogInformation("App created: {AppId}", request.AppId);
        return Ok(new { message = "App created", id = app.Id });
    }

    /// <summary>
    /// Update an app
    /// </summary>
    [HttpPut("{appId}")]
    [Authorize(Policy = "GlobalAdmin")]
    public async Task<IActionResult> UpdateApp(string appId, [FromBody] UpdateAppRequest request)
    {
        var app = await _context.Apps.FirstOrDefaultAsync(a => a.AppId == appId);
        if (app == null)
        {
            return NotFound(new { message = "App not found" });
        }

        app.DisplayName = request.DisplayName ?? app.DisplayName;
        app.Description = request.Description ?? app.Description;
        app.BaseUrl = request.BaseUrl ?? app.BaseUrl;
        app.IconUrl = request.IconUrl ?? app.IconUrl;
        if (request.AvailableRoles != null)
        {
            app.SetAvailableRoles(request.AvailableRoles);
        }

        await _context.SaveChangesAsync();
        return Ok(new { message = "App updated" });
    }

    /// <summary>
    /// Delete an app
    /// </summary>
    [HttpDelete("{appId}")]
    [Authorize(Policy = "GlobalAdmin")]
    public async Task<IActionResult> DeleteApp(string appId)
    {
        var app = await _context.Apps.FirstOrDefaultAsync(a => a.AppId == appId);
        if (app == null)
        {
            return NotFound(new { message = "App not found" });
        }

        app.IsActive = false;
        await _context.SaveChangesAsync();
        return Ok(new { message = "App deactivated" });
    }

    /// <summary>
    /// Bulk-update all app BaseUrls and tenant app routing to use a new server base URL.
    /// Called from the admin UI when it detects a hostname mismatch.
    /// </summary>
    [HttpPost("update-base-urls")]
    [Authorize(Policy = "GlobalAdmin")]
    public async Task<IActionResult> UpdateBaseUrls([FromBody] UpdateBaseUrlsRequest request)
    {
        if (string.IsNullOrWhiteSpace(request.ServerBaseUrl))
        {
            return BadRequest(new { message = "ServerBaseUrl is required" });
        }

        var newBase = request.ServerBaseUrl.TrimEnd('/');
        var changes = new List<string>();

        var apps = await _context.Apps.Where(a => a.IsActive).ToListAsync();
        foreach (var app in apps)
        {
            if (string.IsNullOrEmpty(app.BaseUrl)) continue;
            var newUrl = $"{newBase}/{app.AppId}";
            if (app.BaseUrl != newUrl)
            {
                _logger.LogInformation("Updating app {AppId} BaseUrl: {OldUrl} -> {NewUrl}", app.AppId, app.BaseUrl, newUrl);
                changes.Add($"{app.AppId}: {app.BaseUrl} -> {newUrl}");
                app.BaseUrl = newUrl;
            }
        }

        var tenants = await _context.Tenants.ToListAsync();
        foreach (var tenant in tenants)
        {
            var routing = tenant.GetAppRouting();
            if (routing == null || routing.Count == 0) continue;

            var newRouting = new Dictionary<string, string>();
            var changed = false;
            foreach (var kvp in routing)
            {
                var newUrl = $"{newBase}/{kvp.Key}";
                if (kvp.Value != newUrl)
                {
                    _logger.LogInformation("Updating tenant {Domain} route {AppId}: {OldUrl} -> {NewUrl}",
                        tenant.Domain, kvp.Key, kvp.Value, newUrl);
                    changed = true;
                }
                newRouting[kvp.Key] = newUrl;
            }
            if (changed) tenant.SetAppRouting(newRouting);
        }

        await _context.SaveChangesAsync();

        _logger.LogInformation("Bulk URL update to {NewBase}: {Count} app(s) changed", newBase, changes.Count);
        return Ok(new { updated = changes.Count, changes });
    }

    /// <summary>
    /// Get the user-visible app group tree for the authenticated user's tenant.
    /// Filters by AD group ACLs from the JWT.
    /// </summary>
    [HttpGet("tree")]
    public async Task<IActionResult> GetTree()
    {
        var tenantClaim = User.FindFirst("tenant")?.Value;
        if (string.IsNullOrEmpty(tenantClaim))
            return Ok(new { tree = new List<TreeNode>(), ungrouped = new List<object>() });

        Guid tenantId;
        try
        {
            var tenantObj = JsonSerializer.Deserialize<JsonElement>(tenantClaim);
            tenantId = tenantObj.GetProperty("id").GetGuid();
        }
        catch
        {
            return Ok(new { tree = new List<TreeNode>(), ungrouped = new List<object>() });
        }

        var adGroups = new List<string>();
        var adGroupsClaim = User.FindFirst("adGroups")?.Value;
        if (!string.IsNullOrEmpty(adGroupsClaim))
        {
            try { adGroups = JsonSerializer.Deserialize<List<string>>(adGroupsClaim) ?? new(); }
            catch { /* ignore parse errors */ }
        }

        var appRolesClaim = User.FindFirst("appPermissions")?.Value;
        var appRoles = new Dictionary<string, string>();
        if (!string.IsNullOrEmpty(appRolesClaim))
        {
            try { appRoles = JsonSerializer.Deserialize<Dictionary<string, string>>(appRolesClaim) ?? new(); }
            catch { /* ignore parse errors */ }
        }

        var tree = await _treeService.GetVisibleTreeAsync(tenantId, adGroups, appRoles);
        var ungrouped = await _treeService.GetUngroupedAppsAsync(tenantId);

        return Ok(new
        {
            tree,
            ungrouped = ungrouped.Select(a => new { a.AppId, a.DisplayName, a.BaseUrl, a.IconUrl, a.Description })
        });
    }
}

public record CreateAppRequest(string AppId, string DisplayName, string? Description, string? BaseUrl, string? IconUrl, List<string>? AvailableRoles);
public record UpdateAppRequest(string? DisplayName, string? Description, string? BaseUrl, string? IconUrl, List<string>? AvailableRoles);
public record UpdateBaseUrlsRequest(string ServerBaseUrl);
