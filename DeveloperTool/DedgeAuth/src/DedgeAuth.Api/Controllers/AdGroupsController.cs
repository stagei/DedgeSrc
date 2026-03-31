using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Mvc;
using Microsoft.EntityFrameworkCore;
using DedgeAuth.Data;
using DedgeAuth.Services;

namespace DedgeAuth.Api.Controllers;

/// <summary>
/// API for querying cached AD groups and triggering sync.
/// </summary>
[ApiController]
[Route("api/ad-groups")]
[Authorize(Policy = "GlobalAdmin")]
public class AdGroupsController : ControllerBase
{
    private readonly AuthDbContext _context;
    private readonly IServiceProvider _services;
    private readonly ILogger<AdGroupsController> _logger;

    public AdGroupsController(
        AuthDbContext context,
        IServiceProvider services,
        ILogger<AdGroupsController> logger)
    {
        _context = context;
        _services = services;
        _logger = logger;
    }

    /// <summary>
    /// Search cached AD groups by name prefix or substring.
    /// </summary>
    [HttpGet("search")]
    public async Task<IActionResult> Search([FromQuery] Guid tenantId, [FromQuery] string? q, [FromQuery] int limit = 50)
    {
        var query = _context.AdGroupsCache
            .Where(g => g.TenantId == tenantId);

        if (!string.IsNullOrWhiteSpace(q))
        {
            var term = q.Trim().ToLower();
            query = query.Where(g => g.SamAccountName.ToLower().Contains(term)
                                  || (g.Description != null && g.Description.ToLower().Contains(term)));
        }

        var results = await query
            .OrderBy(g => g.SamAccountName)
            .Take(limit)
            .Select(g => new
            {
                g.Id,
                g.SamAccountName,
                g.Description,
                g.GroupCategory,
                g.MemberCount,
                g.LastSyncedAt
            })
            .ToListAsync();

        return Ok(results);
    }

    /// <summary>
    /// Get full list of cached AD groups for a tenant (tree-view / flat list).
    /// </summary>
    [HttpGet]
    public async Task<IActionResult> GetAll([FromQuery] Guid tenantId)
    {
        var groups = await _context.AdGroupsCache
            .Where(g => g.TenantId == tenantId)
            .OrderBy(g => g.SamAccountName)
            .Select(g => new
            {
                g.Id,
                g.SamAccountName,
                g.Description,
                g.GroupCategory,
                g.MemberCount,
                g.LastSyncedAt
            })
            .ToListAsync();

        return Ok(groups);
    }

    /// <summary>
    /// Trigger an immediate AD group sync for a tenant.
    /// </summary>
    [HttpPost("sync")]
    public async Task<IActionResult> TriggerSync([FromQuery] Guid tenantId)
    {
        var tenant = await _context.Tenants.FindAsync(tenantId);
        if (tenant == null)
            return NotFound(new { message = "Tenant not found." });

        if (string.IsNullOrEmpty(tenant.AdDomain))
            return BadRequest(new { message = "Tenant has no AD domain configured." });

        try
        {
            using var scope = _services.CreateScope();
            var syncService = scope.ServiceProvider.GetRequiredService<AdGroupSyncService>();
            var count = await syncService.SyncTenantAsync(tenant);

            _logger.LogInformation("Manual AD group sync triggered for tenant {Domain}: {Count} groups", tenant.Domain, count);
            return Ok(new { message = $"Synced {count} groups from {tenant.AdDomain}.", count });
        }
        catch (Exception ex)
        {
            _logger.LogError(ex, "Manual AD group sync failed for tenant {Domain}", tenant.Domain);
            return StatusCode(500, new { message = $"Sync failed: {ex.Message}" });
        }
    }

    /// <summary>
    /// Get sync status (last sync time, count, status message).
    /// </summary>
    [HttpGet("sync/status")]
    public IActionResult GetSyncStatus()
    {
        return Ok(new
        {
            lastSyncTime = AdGroupSyncService.LastSyncTime,
            lastSyncCount = AdGroupSyncService.LastSyncCount,
            lastSyncStatus = AdGroupSyncService.LastSyncStatus ?? "Not yet synced"
        });
    }
}
