using Microsoft.AspNetCore.Mvc;
using Microsoft.EntityFrameworkCore;
using GenericLogHandler.Core.Interfaces;
using GenericLogHandler.Core.Models;
using GenericLogHandler.Data;
using GenericLogHandler.WebApi.Models;
using System.Text.Json;

namespace GenericLogHandler.WebApi.Controllers;

/// <summary>
/// API controller for saved filter operations
/// </summary>
[ApiController]
[Route("api/filters")]
public class SavedFiltersController : ControllerBase
{
    private readonly LoggingDbContext _context;
    private readonly ILogRepository _repository;
    private readonly ILogger<SavedFiltersController> _logger;

    public SavedFiltersController(
        LoggingDbContext context,
        ILogRepository repository,
        ILogger<SavedFiltersController> logger)
    {
        _context = context;
        _repository = repository;
        _logger = logger;
    }

    /// <summary>
    /// Get all saved filters
    /// </summary>
    [HttpGet]
    public async Task<ActionResult<ApiResponse<List<SavedFilterDto>>>> GetFilters(
        [FromQuery] bool? alertsOnly = null,
        [FromQuery] string? category = null)
    {
        try
        {
            var query = _context.SavedFilters.AsQueryable();

            if (alertsOnly == true)
            {
                query = query.Where(f => f.IsAlertEnabled);
            }

            if (!string.IsNullOrEmpty(category))
            {
                query = query.Where(f => f.Category == category);
            }

            var filters = await query
                .OrderByDescending(f => f.CreatedAt)
                .ToListAsync();

            var dtos = filters.Select(SavedFilterDto.FromSavedFilter).ToList();
            return Ok(ApiResponse<List<SavedFilterDto>>.CreateSuccess(dtos));
        }
        catch (Exception ex)
        {
            _logger.LogError(ex, "Error retrieving saved filters");
            return BadRequest(ApiResponse<List<SavedFilterDto>>.CreateError("Error retrieving filters: " + ex.Message));
        }
    }

    /// <summary>
    /// Get a specific saved filter by ID
    /// </summary>
    [HttpGet("{id}")]
    public async Task<ActionResult<ApiResponse<SavedFilterDto>>> GetFilter(Guid id)
    {
        try
        {
            var filter = await _context.SavedFilters.FindAsync(id);
            if (filter == null)
            {
                return NotFound(ApiResponse<SavedFilterDto>.CreateError("Filter not found"));
            }

            return Ok(ApiResponse<SavedFilterDto>.CreateSuccess(SavedFilterDto.FromSavedFilter(filter)));
        }
        catch (Exception ex)
        {
            _logger.LogError(ex, "Error retrieving filter {Id}", id);
            return BadRequest(ApiResponse<SavedFilterDto>.CreateError("Error retrieving filter: " + ex.Message));
        }
    }

    /// <summary>
    /// Create a new saved filter
    /// </summary>
    [HttpPost]
    public async Task<ActionResult<ApiResponse<SavedFilterDto>>> CreateFilter([FromBody] SavedFilterCreateRequest request)
    {
        try
        {
            if (string.IsNullOrWhiteSpace(request.Name))
            {
                return BadRequest(ApiResponse<SavedFilterDto>.CreateError("Filter name is required"));
            }

            var filter = new SavedFilter
            {
                Name = request.Name,
                Description = request.Description,
                FilterJson = request.FilterJson ?? "{}",
                CreatedBy = User.Identity?.Name ?? "anonymous",
                CreatedAt = DateTime.UtcNow,
                IsAlertEnabled = request.IsAlertEnabled,
                AlertConfig = request.AlertConfig,
                IsShared = request.IsShared,
                Category = request.Category
            };

            _context.SavedFilters.Add(filter);
            await _context.SaveChangesAsync();

            _logger.LogInformation("Created saved filter: {FilterName} (ID: {FilterId})", filter.Name, filter.Id);
            return CreatedAtAction(nameof(GetFilter), new { id = filter.Id }, 
                ApiResponse<SavedFilterDto>.CreateSuccess(SavedFilterDto.FromSavedFilter(filter)));
        }
        catch (Exception ex)
        {
            _logger.LogError(ex, "Error creating filter");
            return BadRequest(ApiResponse<SavedFilterDto>.CreateError("Error creating filter: " + ex.Message));
        }
    }

    /// <summary>
    /// Update an existing saved filter
    /// </summary>
    [HttpPut("{id}")]
    public async Task<ActionResult<ApiResponse<SavedFilterDto>>> UpdateFilter(Guid id, [FromBody] SavedFilterUpdateRequest request)
    {
        try
        {
            var filter = await _context.SavedFilters.FindAsync(id);
            if (filter == null)
            {
                return NotFound(ApiResponse<SavedFilterDto>.CreateError("Filter not found"));
            }

            if (!string.IsNullOrWhiteSpace(request.Name))
                filter.Name = request.Name;
            
            if (request.Description != null)
                filter.Description = request.Description;
            
            if (!string.IsNullOrWhiteSpace(request.FilterJson))
                filter.FilterJson = request.FilterJson;
            
            if (request.IsAlertEnabled.HasValue)
                filter.IsAlertEnabled = request.IsAlertEnabled.Value;
            
            if (request.AlertConfig != null)
                filter.AlertConfig = request.AlertConfig;
            
            if (request.IsShared.HasValue)
                filter.IsShared = request.IsShared.Value;
            
            if (request.Category != null)
                filter.Category = request.Category;

            filter.UpdatedAt = DateTime.UtcNow;

            await _context.SaveChangesAsync();

            _logger.LogInformation("Updated saved filter: {FilterName} (ID: {FilterId})", filter.Name, filter.Id);
            return Ok(ApiResponse<SavedFilterDto>.CreateSuccess(SavedFilterDto.FromSavedFilter(filter)));
        }
        catch (Exception ex)
        {
            _logger.LogError(ex, "Error updating filter {Id}", id);
            return BadRequest(ApiResponse<SavedFilterDto>.CreateError("Error updating filter: " + ex.Message));
        }
    }

    /// <summary>
    /// Delete a saved filter
    /// </summary>
    [HttpDelete("{id}")]
    public async Task<ActionResult<ApiResponse<bool>>> DeleteFilter(Guid id)
    {
        try
        {
            var filter = await _context.SavedFilters.FindAsync(id);
            if (filter == null)
            {
                return NotFound(ApiResponse<bool>.CreateError("Filter not found"));
            }

            _context.SavedFilters.Remove(filter);
            await _context.SaveChangesAsync();

            _logger.LogInformation("Deleted saved filter: {FilterName} (ID: {FilterId})", filter.Name, filter.Id);
            return Ok(ApiResponse<bool>.CreateSuccess(true));
        }
        catch (Exception ex)
        {
            _logger.LogError(ex, "Error deleting filter {Id}", id);
            return BadRequest(ApiResponse<bool>.CreateError("Error deleting filter: " + ex.Message));
        }
    }

    /// <summary>
    /// Preview filter results (execute the filter and return matching count + sample entries)
    /// </summary>
    [HttpPost("{id}/preview")]
    public async Task<ActionResult<ApiResponse<FilterPreviewResult>>> PreviewFilter(Guid id, [FromQuery] int limit = 10)
    {
        try
        {
            var filter = await _context.SavedFilters.FindAsync(id);
            if (filter == null)
            {
                return NotFound(ApiResponse<FilterPreviewResult>.CreateError("Filter not found"));
            }

            return await ExecuteFilterPreview(filter.FilterJson, limit);
        }
        catch (Exception ex)
        {
            _logger.LogError(ex, "Error previewing filter {Id}", id);
            return BadRequest(ApiResponse<FilterPreviewResult>.CreateError("Error previewing filter: " + ex.Message));
        }
    }

    /// <summary>
    /// Preview filter results without saving (test a filter JSON)
    /// </summary>
    [HttpPost("preview")]
    public async Task<ActionResult<ApiResponse<FilterPreviewResult>>> PreviewFilterJson(
        [FromBody] FilterPreviewRequest request)
    {
        try
        {
            return await ExecuteFilterPreview(request.FilterJson, request.Limit);
        }
        catch (Exception ex)
        {
            _logger.LogError(ex, "Error previewing filter JSON");
            return BadRequest(ApiResponse<FilterPreviewResult>.CreateError("Error previewing filter: " + ex.Message));
        }
    }

    /// <summary>
    /// Get alert history for a filter
    /// </summary>
    [HttpGet("{id}/history")]
    public async Task<ActionResult<ApiResponse<List<AlertHistoryDto>>>> GetFilterHistory(
        Guid id, 
        [FromQuery] int limit = 50)
    {
        try
        {
            var filter = await _context.SavedFilters.FindAsync(id);
            if (filter == null)
            {
                return NotFound(ApiResponse<List<AlertHistoryDto>>.CreateError("Filter not found"));
            }

            var history = await _context.AlertHistories
                .Where(h => h.FilterId == id)
                .OrderByDescending(h => h.TriggeredAt)
                .Take(limit)
                .ToListAsync();

            var dtos = history.Select(AlertHistoryDto.FromAlertHistory).ToList();
            return Ok(ApiResponse<List<AlertHistoryDto>>.CreateSuccess(dtos));
        }
        catch (Exception ex)
        {
            _logger.LogError(ex, "Error retrieving alert history for filter {Id}", id);
            return BadRequest(ApiResponse<List<AlertHistoryDto>>.CreateError("Error retrieving history: " + ex.Message));
        }
    }

    /// <summary>
    /// Get all categories used by saved filters
    /// </summary>
    [HttpGet("categories")]
    public async Task<ActionResult<ApiResponse<List<string>>>> GetCategories()
    {
        try
        {
            var categories = await _context.SavedFilters
                .Where(f => f.Category != null)
                .Select(f => f.Category!)
                .Distinct()
                .OrderBy(c => c)
                .ToListAsync();

            return Ok(ApiResponse<List<string>>.CreateSuccess(categories));
        }
        catch (Exception ex)
        {
            _logger.LogError(ex, "Error retrieving categories");
            return BadRequest(ApiResponse<List<string>>.CreateError("Error retrieving categories: " + ex.Message));
        }
    }

    private async Task<ActionResult<ApiResponse<FilterPreviewResult>>> ExecuteFilterPreview(string filterJson, int limit)
    {
        var options = new JsonSerializerOptions { PropertyNameCaseInsensitive = true };
        LogSearchRequest? searchRequest;
        
        try
        {
            searchRequest = JsonSerializer.Deserialize<LogSearchRequest>(filterJson, options);
        }
        catch (JsonException)
        {
            return BadRequest(ApiResponse<FilterPreviewResult>.CreateError("Invalid filter JSON format"));
        }

        if (searchRequest == null)
        {
            return BadRequest(ApiResponse<FilterPreviewResult>.CreateError("Filter JSON is empty"));
        }

        var criteria = new LogSearchCriteria
        {
            FromDate = searchRequest.FromDate,
            ToDate = searchRequest.ToDate,
            Levels = searchRequest.Levels?.Select(l => Enum.TryParse<Core.Models.LogLevel>(l, true, out var lvl) ? lvl : (Core.Models.LogLevel?)null)
                .Where(l => l.HasValue).Select(l => l!.Value).ToList(),
            ComputerName = searchRequest.ComputerName,
            UserName = searchRequest.UserName,
            MessageText = searchRequest.MessageText,
            ExceptionText = searchRequest.ExceptionText,
            RegexPattern = searchRequest.RegexPattern,
            FunctionName = searchRequest.FunctionName,
            SourceFile = searchRequest.SourceFile,
            SourceType = searchRequest.SourceType,
            AlertId = searchRequest.AlertId,
            Ordrenr = searchRequest.Ordrenr,
            Avdnr = searchRequest.Avdnr,
            JobName = searchRequest.JobName,
            Page = 1,
            PageSize = Math.Min(limit, 100),
            SortBy = searchRequest.SortBy ?? "Timestamp",
            SortDescending = searchRequest.SortDescending
        };

        var result = await _repository.SearchAsync(criteria);
        
        var preview = new FilterPreviewResult
        {
            TotalCount = result.TotalCount,
            SampleEntries = result.Items.Select(LogEntryDto.FromLogEntry).ToList()
        };

        return Ok(ApiResponse<FilterPreviewResult>.CreateSuccess(preview));
    }
}
