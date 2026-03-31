using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Mvc;
using Microsoft.EntityFrameworkCore;
using DedgeAuth.Core.Models;
using DedgeAuth.Data;
using DedgeAuth.Services;

namespace DedgeAuth.Api.Controllers;

/// <summary>
/// App group management (admin) and tree retrieval (user-facing).
/// </summary>
[ApiController]
[Route("api/app-groups")]
[Authorize]
public class AppGroupsController : ControllerBase
{
    private readonly AuthDbContext _context;
    private readonly AppGroupAccessService _treeService;
    private readonly ILogger<AppGroupsController> _logger;

    public AppGroupsController(
        AuthDbContext context,
        AppGroupAccessService treeService,
        ILogger<AppGroupsController> logger)
    {
        _context = context;
        _treeService = treeService;
        _logger = logger;
    }

    /// <summary>
    /// Get all groups for a tenant (flat list, admin view).
    /// </summary>
    [HttpGet]
    [Authorize(Policy = "GlobalAdmin")]
    public async Task<IActionResult> GetGroups([FromQuery] Guid tenantId)
    {
        var groups = await _context.AppGroups
            .Where(g => g.TenantId == tenantId)
            .Include(g => g.Items)
                .ThenInclude(i => i.App)
            .OrderBy(g => g.SortOrder)
            .ThenBy(g => g.Name)
            .Select(g => new
            {
                g.Id,
                g.TenantId,
                g.Name,
                g.Slug,
                g.ParentId,
                g.SortOrder,
                g.IconUrl,
                g.Description,
                g.AclGroupsJson,
                g.CreatedAt,
                Apps = g.Items.OrderBy(i => i.SortOrder).Select(i => new
                {
                    i.Id,
                    i.AppId,
                    i.SortOrder,
                    App = new { i.App.AppId, i.App.DisplayName, i.App.BaseUrl, i.App.IconUrl }
                })
            })
            .ToListAsync();

        return Ok(groups);
    }

    /// <summary>
    /// Get full group tree for a tenant (admin, no ACL pruning).
    /// </summary>
    [HttpGet("tree")]
    [Authorize(Policy = "GlobalAdmin")]
    public async Task<IActionResult> GetTree([FromQuery] Guid tenantId)
    {
        var tree = await _treeService.GetFullTreeAsync(tenantId);
        return Ok(tree);
    }

    /// <summary>
    /// Create a new group.
    /// </summary>
    [HttpPost]
    [Authorize(Policy = "GlobalAdmin")]
    public async Task<IActionResult> CreateGroup([FromBody] CreateGroupRequest request)
    {
        var tenant = await _context.Tenants.FindAsync(request.TenantId);
        if (tenant == null)
            return NotFound(new { message = "Tenant not found." });

        if (request.ParentId.HasValue)
        {
            var parent = await _context.AppGroups.FindAsync(request.ParentId.Value);
            if (parent == null || parent.TenantId != request.TenantId)
                return BadRequest(new { message = "Parent group not found or belongs to different tenant." });
        }

        var existing = await _context.AppGroups
            .AnyAsync(g => g.TenantId == request.TenantId && g.Slug == request.Slug);
        if (existing)
            return Conflict(new { message = $"A group with slug '{request.Slug}' already exists for this tenant." });

        var group = new AppGroup
        {
            TenantId = request.TenantId,
            Name = request.Name,
            Slug = request.Slug,
            ParentId = request.ParentId,
            SortOrder = request.SortOrder,
            IconUrl = request.IconUrl,
            Description = request.Description,
            AclGroupsJson = request.AclGroupsJson
        };

        _context.AppGroups.Add(group);
        await _context.SaveChangesAsync();

        _logger.LogInformation("Created app group '{Name}' (slug: {Slug}) for tenant {TenantId}", group.Name, group.Slug, group.TenantId);
        return CreatedAtAction(nameof(GetGroups), new { tenantId = group.TenantId }, new { group.Id, group.Name, group.Slug });
    }

    /// <summary>
    /// Update an existing group.
    /// </summary>
    [HttpPut("{id:guid}")]
    [Authorize(Policy = "GlobalAdmin")]
    public async Task<IActionResult> UpdateGroup(Guid id, [FromBody] UpdateGroupRequest request)
    {
        var group = await _context.AppGroups.FindAsync(id);
        if (group == null)
            return NotFound(new { message = "Group not found." });

        if (request.ParentId.HasValue && request.ParentId.Value == id)
            return BadRequest(new { message = "A group cannot be its own parent." });

        if (!string.IsNullOrEmpty(request.Slug) && request.Slug != group.Slug)
        {
            var conflict = await _context.AppGroups
                .AnyAsync(g => g.TenantId == group.TenantId && g.Slug == request.Slug && g.Id != id);
            if (conflict)
                return Conflict(new { message = $"A group with slug '{request.Slug}' already exists for this tenant." });
            group.Slug = request.Slug;
        }

        if (!string.IsNullOrEmpty(request.Name)) group.Name = request.Name;
        if (request.ParentId.HasValue) group.ParentId = request.ParentId == Guid.Empty ? null : request.ParentId;
        if (request.SortOrder.HasValue) group.SortOrder = request.SortOrder.Value;
        if (request.IconUrl != null) group.IconUrl = request.IconUrl;
        if (request.Description != null) group.Description = request.Description;
        if (request.AclGroupsJson != null) group.AclGroupsJson = string.IsNullOrWhiteSpace(request.AclGroupsJson) ? null : request.AclGroupsJson;

        await _context.SaveChangesAsync();
        _logger.LogInformation("Updated app group {Id} ('{Name}')", id, group.Name);
        return Ok(new { group.Id, group.Name, group.Slug, group.ParentId, group.SortOrder, group.AclGroupsJson });
    }

    /// <summary>
    /// Delete a group (must have no children or items).
    /// </summary>
    [HttpDelete("{id:guid}")]
    [Authorize(Policy = "GlobalAdmin")]
    public async Task<IActionResult> DeleteGroup(Guid id)
    {
        var group = await _context.AppGroups
            .Include(g => g.Children)
            .Include(g => g.Items)
            .FirstOrDefaultAsync(g => g.Id == id);

        if (group == null)
            return NotFound(new { message = "Group not found." });

        if (group.Children.Count > 0)
            return BadRequest(new { message = "Cannot delete a group that has child groups. Remove children first." });

        if (group.Items.Count > 0)
            return BadRequest(new { message = "Cannot delete a group that has assigned apps. Remove apps first." });

        _context.AppGroups.Remove(group);
        await _context.SaveChangesAsync();

        _logger.LogInformation("Deleted app group {Id} ('{Name}')", id, group.Name);
        return Ok(new { message = "Group deleted." });
    }

    /// <summary>
    /// Add an app to a group.
    /// </summary>
    [HttpPost("{id:guid}/apps")]
    [Authorize(Policy = "GlobalAdmin")]
    public async Task<IActionResult> AddAppToGroup(Guid id, [FromBody] AddAppRequest request)
    {
        var group = await _context.AppGroups.FindAsync(id);
        if (group == null)
            return NotFound(new { message = "Group not found." });

        var app = await _context.Apps.FirstOrDefaultAsync(a => a.AppId == request.AppId);
        if (app == null)
            return NotFound(new { message = $"App '{request.AppId}' not found." });

        var exists = await _context.AppGroupItems
            .AnyAsync(i => i.AppGroupId == id && i.AppId == app.Id);
        if (exists)
            return Conflict(new { message = $"App '{request.AppId}' is already in this group." });

        var item = new AppGroupItem
        {
            AppGroupId = id,
            AppId = app.Id,
            SortOrder = request.SortOrder
        };

        _context.AppGroupItems.Add(item);
        await _context.SaveChangesAsync();

        _logger.LogInformation("Added app '{AppId}' to group {GroupId}", request.AppId, id);
        return Ok(new { item.Id, item.AppGroupId, item.AppId, item.SortOrder });
    }

    /// <summary>
    /// Remove an app from a group.
    /// </summary>
    [HttpDelete("{id:guid}/apps/{appId}")]
    [Authorize(Policy = "GlobalAdmin")]
    public async Task<IActionResult> RemoveAppFromGroup(Guid id, string appId)
    {
        var app = await _context.Apps.FirstOrDefaultAsync(a => a.AppId == appId);
        if (app == null)
            return NotFound(new { message = $"App '{appId}' not found." });

        var item = await _context.AppGroupItems
            .FirstOrDefaultAsync(i => i.AppGroupId == id && i.AppId == app.Id);
        if (item == null)
            return NotFound(new { message = $"App '{appId}' is not in this group." });

        _context.AppGroupItems.Remove(item);
        await _context.SaveChangesAsync();

        _logger.LogInformation("Removed app '{AppId}' from group {GroupId}", appId, id);
        return Ok(new { message = "App removed from group." });
    }

    /// <summary>
    /// Batch reorder groups (sort order + parent reassignment from DnD).
    /// </summary>
    [HttpPut("reorder")]
    [Authorize(Policy = "GlobalAdmin")]
    public async Task<IActionResult> ReorderGroups([FromBody] List<ReorderGroupItem> items)
    {
        if (items == null || items.Count == 0)
            return BadRequest(new { message = "No items to reorder." });

        var ids = items.Select(i => i.Id).ToList();
        var groups = await _context.AppGroups
            .Where(g => ids.Contains(g.Id))
            .ToListAsync();

        foreach (var item in items)
        {
            var group = groups.FirstOrDefault(g => g.Id == item.Id);
            if (group == null) continue;

            group.SortOrder = item.SortOrder;
            group.ParentId = item.ParentId == Guid.Empty ? null : item.ParentId;
        }

        await _context.SaveChangesAsync();
        _logger.LogInformation("Batch reordered {Count} groups", items.Count);
        return Ok(new { message = $"Reordered {items.Count} groups." });
    }

    /// <summary>
    /// Batch reorder apps within a group.
    /// </summary>
    [HttpPut("{id:guid}/apps/reorder")]
    [Authorize(Policy = "GlobalAdmin")]
    public async Task<IActionResult> ReorderApps(Guid id, [FromBody] List<ReorderAppItem> items)
    {
        if (items == null || items.Count == 0)
            return BadRequest(new { message = "No items to reorder." });

        var groupItems = await _context.AppGroupItems
            .Where(i => i.AppGroupId == id)
            .ToListAsync();

        foreach (var item in items)
        {
            var gi = groupItems.FirstOrDefault(g => g.Id == item.Id);
            if (gi == null) continue;
            gi.SortOrder = item.SortOrder;
        }

        await _context.SaveChangesAsync();
        _logger.LogInformation("Batch reordered {Count} apps in group {GroupId}", items.Count, id);
        return Ok(new { message = $"Reordered {items.Count} apps." });
    }
}

public record ReorderGroupItem(Guid Id, int SortOrder, Guid? ParentId = null);
public record ReorderAppItem(Guid Id, int SortOrder);

public record CreateGroupRequest(
    Guid TenantId,
    string Name,
    string Slug,
    Guid? ParentId = null,
    int SortOrder = 0,
    string? IconUrl = null,
    string? Description = null,
    string? AclGroupsJson = null);

public record UpdateGroupRequest(
    string? Name = null,
    string? Slug = null,
    Guid? ParentId = null,
    int? SortOrder = null,
    string? IconUrl = null,
    string? Description = null,
    string? AclGroupsJson = null);

public record AddAppRequest(string AppId, int SortOrder = 0);
