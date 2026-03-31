using Microsoft.AspNetCore.Mvc;
using Microsoft.EntityFrameworkCore;
using GenericLogHandler.Core.Models;
using GenericLogHandler.Data;
using GenericLogHandler.WebApi.Models;

namespace GenericLogHandler.WebApi.Controllers;

/// <summary>
/// Controller for audit log operations
/// </summary>
[ApiController]
[Route("api/[controller]")]
public class AuditController : ControllerBase
{
    private readonly LoggingDbContext _context;
    private readonly ILogger<AuditController> _logger;

    public AuditController(LoggingDbContext context, ILogger<AuditController> logger)
    {
        _context = context;
        _logger = logger;
    }

    /// <summary>
    /// Search audit logs with filtering
    /// </summary>
    [HttpGet]
    public async Task<ActionResult<ApiResponse<AuditSearchResult>>> SearchAuditLogs(
        [FromQuery] DateTime? fromDate = null,
        [FromQuery] DateTime? toDate = null,
        [FromQuery] string? userId = null,
        [FromQuery] string? action = null,
        [FromQuery] string? entityType = null,
        [FromQuery] int page = 1,
        [FromQuery] int pageSize = 50)
    {
        try
        {
            fromDate ??= DateTime.UtcNow.AddDays(-7);
            toDate ??= DateTime.UtcNow;

            var query = _context.AuditLogs
                .Where(a => a.Timestamp >= fromDate && a.Timestamp <= toDate);

            if (!string.IsNullOrEmpty(userId))
            {
                query = query.Where(a => a.UserId.Contains(userId));
            }

            if (!string.IsNullOrEmpty(action))
            {
                query = query.Where(a => a.Action == action);
            }

            if (!string.IsNullOrEmpty(entityType))
            {
                query = query.Where(a => a.EntityType == entityType);
            }

            var totalCount = await query.CountAsync();
            var items = await query
                .OrderByDescending(a => a.Timestamp)
                .Skip((page - 1) * pageSize)
                .Take(pageSize)
                .Select(a => new AuditLogDto
                {
                    Id = a.Id,
                    Timestamp = a.Timestamp,
                    UserId = a.UserId,
                    IpAddress = a.IpAddress,
                    Action = a.Action,
                    EntityType = a.EntityType,
                    EntityId = a.EntityId,
                    Details = a.Details,
                    Success = a.Success,
                    ErrorMessage = a.ErrorMessage,
                    HttpMethod = a.HttpMethod,
                    RequestPath = a.RequestPath,
                    DurationMs = a.DurationMs
                })
                .ToListAsync();

            var result = new AuditSearchResult
            {
                Items = items,
                TotalCount = totalCount,
                Page = page,
                PageSize = pageSize
            };

            return Ok(ApiResponse<AuditSearchResult>.CreateSuccess(result));
        }
        catch (Exception ex)
        {
            _logger.LogError(ex, "Error searching audit logs");
            return BadRequest(ApiResponse<AuditSearchResult>.CreateError("Error: " + ex.Message));
        }
    }

    /// <summary>
    /// Get available action types for filtering
    /// </summary>
    [HttpGet("actions")]
    [ResponseCache(Duration = 3600)]
    public ActionResult<ApiResponse<List<string>>> GetActionTypes()
    {
        var actions = new List<string>
        {
            AuditActions.Create,
            AuditActions.Read,
            AuditActions.Update,
            AuditActions.Delete,
            AuditActions.Export,
            AuditActions.Import,
            AuditActions.ConfigChange,
            AuditActions.ServiceControl,
            AuditActions.BulkOperation,
            AuditActions.Maintenance,
            AuditActions.Search
        };
        return Ok(ApiResponse<List<string>>.CreateSuccess(actions));
    }

    /// <summary>
    /// Get available entity types for filtering
    /// </summary>
    [HttpGet("entity-types")]
    [ResponseCache(Duration = 3600)]
    public ActionResult<ApiResponse<List<string>>> GetEntityTypes()
    {
        var entityTypes = new List<string>
        {
            AuditEntityTypes.LogEntry,
            AuditEntityTypes.SavedFilter,
            AuditEntityTypes.ImportStatus,
            AuditEntityTypes.Configuration,
            AuditEntityTypes.Service,
            AuditEntityTypes.Database
        };
        return Ok(ApiResponse<List<string>>.CreateSuccess(entityTypes));
    }

    /// <summary>
    /// Get audit log statistics
    /// </summary>
    [HttpGet("statistics")]
    public async Task<ActionResult<ApiResponse<AuditStatistics>>> GetStatistics(
        [FromQuery] DateTime? fromDate = null,
        [FromQuery] DateTime? toDate = null)
    {
        try
        {
            fromDate ??= DateTime.UtcNow.AddDays(-7);
            toDate ??= DateTime.UtcNow;

            var query = _context.AuditLogs
                .Where(a => a.Timestamp >= fromDate && a.Timestamp <= toDate);

            var stats = new AuditStatistics
            {
                TotalCount = await query.CountAsync(),
                SuccessCount = await query.CountAsync(a => a.Success),
                FailureCount = await query.CountAsync(a => !a.Success),
                UniqueUsers = await query.Select(a => a.UserId).Distinct().CountAsync(),
                ActionCounts = await query
                    .GroupBy(a => a.Action)
                    .Select(g => new { Action = g.Key, Count = g.Count() })
                    .ToDictionaryAsync(x => x.Action, x => x.Count),
                EntityTypeCounts = await query
                    .GroupBy(a => a.EntityType)
                    .Select(g => new { EntityType = g.Key, Count = g.Count() })
                    .ToDictionaryAsync(x => x.EntityType, x => x.Count)
            };

            return Ok(ApiResponse<AuditStatistics>.CreateSuccess(stats));
        }
        catch (Exception ex)
        {
            _logger.LogError(ex, "Error getting audit statistics");
            return BadRequest(ApiResponse<AuditStatistics>.CreateError("Error: " + ex.Message));
        }
    }

    /// <summary>
    /// Log an audit entry (internal use)
    /// </summary>
    internal async Task LogAuditAsync(string userId, string action, string entityType, 
        string? entityId = null, string? details = null, bool success = true, 
        string? errorMessage = null, HttpContext? httpContext = null)
    {
        try
        {
            var entry = new AuditLog
            {
                UserId = userId,
                Action = action,
                EntityType = entityType,
                EntityId = entityId,
                Details = details,
                Success = success,
                ErrorMessage = errorMessage,
                IpAddress = httpContext?.Connection.RemoteIpAddress?.ToString(),
                HttpMethod = httpContext?.Request.Method,
                RequestPath = httpContext?.Request.Path
            };

            _context.AuditLogs.Add(entry);
            await _context.SaveChangesAsync();
        }
        catch (Exception ex)
        {
            _logger.LogError(ex, "Failed to log audit entry");
        }
    }
}

/// <summary>
/// Audit log DTO
/// </summary>
public class AuditLogDto
{
    public long Id { get; set; }
    public DateTime Timestamp { get; set; }
    public string UserId { get; set; } = string.Empty;
    public string? IpAddress { get; set; }
    public string Action { get; set; } = string.Empty;
    public string EntityType { get; set; } = string.Empty;
    public string? EntityId { get; set; }
    public string? Details { get; set; }
    public bool Success { get; set; }
    public string? ErrorMessage { get; set; }
    public string? HttpMethod { get; set; }
    public string? RequestPath { get; set; }
    public long? DurationMs { get; set; }
}

/// <summary>
/// Audit search result
/// </summary>
public class AuditSearchResult
{
    public List<AuditLogDto> Items { get; set; } = new();
    public int TotalCount { get; set; }
    public int Page { get; set; }
    public int PageSize { get; set; }
    public int TotalPages => (int)Math.Ceiling((double)TotalCount / PageSize);
}

/// <summary>
/// Audit statistics
/// </summary>
public class AuditStatistics
{
    public int TotalCount { get; set; }
    public int SuccessCount { get; set; }
    public int FailureCount { get; set; }
    public int UniqueUsers { get; set; }
    public Dictionary<string, int> ActionCounts { get; set; } = new();
    public Dictionary<string, int> EntityTypeCounts { get; set; } = new();
}
