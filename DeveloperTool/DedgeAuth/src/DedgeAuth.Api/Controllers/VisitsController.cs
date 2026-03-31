using System.Security.Claims;
using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Mvc;
using Microsoft.EntityFrameworkCore;
using DedgeAuth.Core.Models;
using DedgeAuth.Data;

namespace DedgeAuth.Api.Controllers;

[ApiController]
[Route("api/[controller]")]
[Authorize]
public class VisitsController : ControllerBase
{
    private readonly AuthDbContext _context;
    private readonly ILogger<VisitsController> _logger;

    public VisitsController(AuthDbContext context, ILogger<VisitsController> logger)
    {
        _context = context;
        _logger = logger;
    }

    /// <summary>
    /// Record a user visit from a consumer app (called by DedgeAuthSessionValidationMiddleware).
    /// </summary>
    [HttpPost("record")]
    public async Task<IActionResult> RecordVisit([FromBody] RecordVisitRequest request)
    {
        var userIdClaim = User.FindFirst(ClaimTypes.NameIdentifier)?.Value;
        if (string.IsNullOrEmpty(userIdClaim) || !Guid.TryParse(userIdClaim, out var userId))
            return Unauthorized();

        var visit = new UserVisit
        {
            UserId = userId,
            AppId = request.AppId ?? string.Empty,
            Path = Truncate(request.Path, 500),
            IpAddress = Truncate(request.IpAddress, 50),
            UserAgent = Truncate(request.UserAgent, 500),
            VisitedAt = DateTime.UtcNow
        };

        _context.UserVisits.Add(visit);
        await _context.SaveChangesAsync();

        _logger.LogDebug("Recorded visit: user {UserId} -> {AppId}{Path}", userId, visit.AppId, visit.Path);

        return NoContent();
    }

    /// <summary>
    /// Get the latest visits across all users (GlobalAdmin only). Used by admin dashboard.
    /// </summary>
    [HttpGet("latest")]
    [Authorize(Policy = "GlobalAdmin")]
    public async Task<IActionResult> GetLatestVisits([FromQuery] int count = 20)
    {
        count = Math.Clamp(count, 1, 100);

        var visits = await _context.UserVisits
            .Include(v => v.User)
            .OrderByDescending(v => v.VisitedAt)
            .Take(count)
            .Select(v => new
            {
                v.Id,
                v.UserId,
                UserEmail = v.User != null ? v.User.Email : null,
                UserName = v.User != null ? v.User.DisplayName : null,
                v.AppId,
                v.Path,
                v.IpAddress,
                v.VisitedAt
            })
            .ToListAsync();

        return Ok(visits);
    }

    /// <summary>
    /// Get visit history for a specific user (GlobalAdmin only). Used by admin user detail.
    /// </summary>
    [HttpGet("user/{userId:guid}")]
    [Authorize(Policy = "GlobalAdmin")]
    public async Task<IActionResult> GetUserVisits(Guid userId, [FromQuery] int page = 0, [FromQuery] int pageSize = 50)
    {
        pageSize = Math.Clamp(pageSize, 1, 200);

        var totalCount = await _context.UserVisits
            .Where(v => v.UserId == userId)
            .CountAsync();

        var visits = await _context.UserVisits
            .Where(v => v.UserId == userId)
            .OrderByDescending(v => v.VisitedAt)
            .Skip(page * pageSize)
            .Take(pageSize)
            .Select(v => new
            {
                v.Id,
                v.AppId,
                v.Path,
                v.IpAddress,
                v.UserAgent,
                v.VisitedAt
            })
            .ToListAsync();

        return Ok(new
        {
            TotalCount = totalCount,
            Page = page,
            PageSize = pageSize,
            Visits = visits
        });
    }

    /// <summary>
    /// Get visit statistics per app for the last 24h and 7d (GlobalAdmin only).
    /// </summary>
    [HttpGet("stats")]
    [Authorize(Policy = "GlobalAdmin")]
    public async Task<IActionResult> GetVisitStats()
    {
        var now = DateTime.UtcNow;
        var last24h = now.AddHours(-24);
        var last7d = now.AddDays(-7);

        var stats24h = await _context.UserVisits
            .Where(v => v.VisitedAt >= last24h)
            .GroupBy(v => v.AppId)
            .Select(g => new
            {
                AppId = g.Key,
                VisitCount = g.Count(),
                UniqueUsers = g.Select(v => v.UserId).Distinct().Count()
            })
            .ToListAsync();

        var stats7d = await _context.UserVisits
            .Where(v => v.VisitedAt >= last7d)
            .GroupBy(v => v.AppId)
            .Select(g => new
            {
                AppId = g.Key,
                VisitCount = g.Count(),
                UniqueUsers = g.Select(v => v.UserId).Distinct().Count()
            })
            .ToListAsync();

        return Ok(new
        {
            Last24Hours = stats24h,
            Last7Days = stats7d,
            TotalVisits = await _context.UserVisits.CountAsync()
        });
    }

    /// <summary>
    /// Get the current authenticated user's own visit history (any authenticated user).
    /// </summary>
    [HttpGet("my")]
    public async Task<IActionResult> GetMyVisits([FromQuery] int page = 0, [FromQuery] int pageSize = 50)
    {
        var userIdClaim = User.FindFirst(ClaimTypes.NameIdentifier)?.Value;
        if (string.IsNullOrEmpty(userIdClaim) || !Guid.TryParse(userIdClaim, out var userId))
            return Unauthorized();

        pageSize = Math.Clamp(pageSize, 1, 200);

        var totalCount = await _context.UserVisits
            .Where(v => v.UserId == userId)
            .CountAsync();

        var visits = await _context.UserVisits
            .Where(v => v.UserId == userId)
            .OrderByDescending(v => v.VisitedAt)
            .Skip(page * pageSize)
            .Take(pageSize)
            .Select(v => new
            {
                v.Id,
                v.AppId,
                v.Path,
                v.IpAddress,
                v.VisitedAt
            })
            .ToListAsync();

        return Ok(new
        {
            TotalCount = totalCount,
            Page = page,
            PageSize = pageSize,
            Visits = visits
        });
    }

    private static string? Truncate(string? value, int maxLength)
    {
        if (value == null) return null;
        return value.Length <= maxLength ? value : value[..maxLength];
    }
}

public class RecordVisitRequest
{
    public string? AppId { get; set; }
    public string? Path { get; set; }
    public string? IpAddress { get; set; }
    public string? UserAgent { get; set; }
}
