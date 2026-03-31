using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Mvc;
using Microsoft.EntityFrameworkCore;
using GenericLogHandler.Data;
using GenericLogHandler.Core.Models.Configuration;
using GenericLogHandler.WebApi.Models;
using System.Text.RegularExpressions;

namespace GenericLogHandler.WebApi.Controllers;

/// <summary>
/// Manages import level filters that control which log levels are imported per file pattern
/// </summary>
[ApiController]
[Route("api/[controller]")]
public class ImportLevelFiltersController : ControllerBase
{
    private readonly LoggingDbContext _context;
    private readonly ILogger<ImportLevelFiltersController> _logger;

    public ImportLevelFiltersController(LoggingDbContext context, ILogger<ImportLevelFiltersController> logger)
    {
        _context = context;
        _logger = logger;
    }

    /// <summary>
    /// Get all import level filters
    /// </summary>
    [HttpGet]
    public async Task<ActionResult<ApiResponse<List<ImportLevelFilterDto>>>> GetAll()
    {
        var filters = await _context.ImportLevelFilters
            .OrderBy(f => f.Priority)
            .ThenBy(f => f.Name)
            .ToListAsync();

        var dtos = filters.Select(f => new ImportLevelFilterDto
        {
            Id = f.Id,
            Name = f.Name,
            FilePattern = f.FilePattern,
            MinLevel = f.MinLevel,
            MinLevelName = f.MinLevelName,
            IsEnabled = f.IsEnabled,
            Priority = f.Priority,
            Description = f.Description,
            CreatedAt = f.CreatedAt,
            UpdatedAt = f.UpdatedAt,
            CreatedBy = f.CreatedBy
        }).ToList();

        return Ok(new ApiResponse<List<ImportLevelFilterDto>> { Success = true, Data = dtos });
    }

    /// <summary>
    /// Get a single filter by ID
    /// </summary>
    [HttpGet("{id}")]
    public async Task<ActionResult<ApiResponse<ImportLevelFilterDto>>> GetById(Guid id)
    {
        var filter = await _context.ImportLevelFilters.FindAsync(id);
        if (filter == null)
        {
            return NotFound(new ApiResponse<ImportLevelFilterDto> { Success = false, Error = "Filter not found" });
        }

        var dto = new ImportLevelFilterDto
        {
            Id = filter.Id,
            Name = filter.Name,
            FilePattern = filter.FilePattern,
            MinLevel = filter.MinLevel,
            MinLevelName = filter.MinLevelName,
            IsEnabled = filter.IsEnabled,
            Priority = filter.Priority,
            Description = filter.Description,
            CreatedAt = filter.CreatedAt,
            UpdatedAt = filter.UpdatedAt,
            CreatedBy = filter.CreatedBy
        };

        return Ok(new ApiResponse<ImportLevelFilterDto> { Success = true, Data = dto });
    }

    /// <summary>
    /// Create a new import level filter
    /// </summary>
    [HttpPost]
    [Authorize(Policy = "PowerUserAccess")]
    public async Task<ActionResult<ApiResponse<ImportLevelFilterDto>>> Create([FromBody] CreateImportLevelFilterRequest request)
    {
        // Validate regex pattern
        if (!IsValidRegex(request.FilePattern))
        {
            return BadRequest(new ApiResponse<ImportLevelFilterDto> 
            { 
                Success = false, 
                Error = "Invalid regex pattern" 
            });
        }

        var filter = new ImportLevelFilter
        {
            Name = request.Name,
            FilePattern = request.FilePattern,
            MinLevel = request.MinLevel,
            IsEnabled = request.IsEnabled,
            Priority = request.Priority,
            Description = request.Description,
            CreatedAt = DateTime.UtcNow,
            UpdatedAt = DateTime.UtcNow,
            CreatedBy = User.Identity?.Name
        };

        _context.ImportLevelFilters.Add(filter);
        await _context.SaveChangesAsync();

        _logger.LogInformation("Import level filter created: {Name} (min level: {MinLevel})", 
            filter.Name, filter.MinLevelName);

        var dto = new ImportLevelFilterDto
        {
            Id = filter.Id,
            Name = filter.Name,
            FilePattern = filter.FilePattern,
            MinLevel = filter.MinLevel,
            MinLevelName = filter.MinLevelName,
            IsEnabled = filter.IsEnabled,
            Priority = filter.Priority,
            Description = filter.Description,
            CreatedAt = filter.CreatedAt,
            UpdatedAt = filter.UpdatedAt,
            CreatedBy = filter.CreatedBy
        };

        return Ok(new ApiResponse<ImportLevelFilterDto> { Success = true, Data = dto });
    }

    /// <summary>
    /// Update an existing import level filter
    /// </summary>
    [HttpPut("{id}")]
    [Authorize(Policy = "PowerUserAccess")]
    public async Task<ActionResult<ApiResponse<ImportLevelFilterDto>>> Update(Guid id, [FromBody] UpdateImportLevelFilterRequest request)
    {
        var filter = await _context.ImportLevelFilters.FindAsync(id);
        if (filter == null)
        {
            return NotFound(new ApiResponse<ImportLevelFilterDto> { Success = false, Error = "Filter not found" });
        }

        // Validate regex pattern if provided
        if (!string.IsNullOrEmpty(request.FilePattern) && !IsValidRegex(request.FilePattern))
        {
            return BadRequest(new ApiResponse<ImportLevelFilterDto> 
            { 
                Success = false, 
                Error = "Invalid regex pattern" 
            });
        }

        if (request.Name != null) filter.Name = request.Name;
        if (request.FilePattern != null) filter.FilePattern = request.FilePattern;
        if (request.MinLevel.HasValue) filter.MinLevel = request.MinLevel.Value;
        if (request.IsEnabled.HasValue) filter.IsEnabled = request.IsEnabled.Value;
        if (request.Priority.HasValue) filter.Priority = request.Priority.Value;
        if (request.Description != null) filter.Description = request.Description;
        filter.UpdatedAt = DateTime.UtcNow;

        await _context.SaveChangesAsync();

        _logger.LogInformation("Import level filter updated: {Name}", filter.Name);

        var dto = new ImportLevelFilterDto
        {
            Id = filter.Id,
            Name = filter.Name,
            FilePattern = filter.FilePattern,
            MinLevel = filter.MinLevel,
            MinLevelName = filter.MinLevelName,
            IsEnabled = filter.IsEnabled,
            Priority = filter.Priority,
            Description = filter.Description,
            CreatedAt = filter.CreatedAt,
            UpdatedAt = filter.UpdatedAt,
            CreatedBy = filter.CreatedBy
        };

        return Ok(new ApiResponse<ImportLevelFilterDto> { Success = true, Data = dto });
    }

    /// <summary>
    /// Delete an import level filter
    /// </summary>
    [HttpDelete("{id}")]
    [Authorize(Policy = "PowerUserAccess")]
    public async Task<ActionResult<ApiResponse<object>>> Delete(Guid id)
    {
        var filter = await _context.ImportLevelFilters.FindAsync(id);
        if (filter == null)
        {
            return NotFound(new ApiResponse<object> { Success = false, Error = "Filter not found" });
        }

        _context.ImportLevelFilters.Remove(filter);
        await _context.SaveChangesAsync();

        _logger.LogInformation("Import level filter deleted: {Name}", filter.Name);

        return Ok(new ApiResponse<object> { Success = true, Data = new { message = "Filter deleted" } });
    }

    /// <summary>
    /// Test a file path against all filters to see which would apply
    /// </summary>
    [HttpPost("test")]
    public async Task<ActionResult<ApiResponse<TestFilterResult>>> TestFilePath([FromBody] TestFilterRequest request)
    {
        var filters = await _context.ImportLevelFilters
            .Where(f => f.IsEnabled)
            .OrderBy(f => f.Priority)
            .ToListAsync();

        ImportLevelFilter? matchingFilter = null;
        foreach (var filter in filters)
        {
            try
            {
                if (Regex.IsMatch(request.FilePath, filter.FilePattern, RegexOptions.IgnoreCase))
                {
                    matchingFilter = filter;
                    break;
                }
            }
            catch
            {
                // Skip invalid regex patterns
            }
        }

        var result = new TestFilterResult
        {
            FilePath = request.FilePath,
            MatchingFilter = matchingFilter != null ? new ImportLevelFilterDto
            {
                Id = matchingFilter.Id,
                Name = matchingFilter.Name,
                FilePattern = matchingFilter.FilePattern,
                MinLevel = matchingFilter.MinLevel,
                MinLevelName = matchingFilter.MinLevelName,
                IsEnabled = matchingFilter.IsEnabled,
                Priority = matchingFilter.Priority,
                Description = matchingFilter.Description
            } : null,
            WouldImportTrace = matchingFilter?.ShouldImport("TRACE") ?? true,
            WouldImportDebug = matchingFilter?.ShouldImport("DEBUG") ?? true,
            WouldImportInfo = matchingFilter?.ShouldImport("INFO") ?? true,
            WouldImportWarn = matchingFilter?.ShouldImport("WARN") ?? true,
            WouldImportError = matchingFilter?.ShouldImport("ERROR") ?? true,
            WouldImportFatal = matchingFilter?.ShouldImport("FATAL") ?? true
        };

        return Ok(new ApiResponse<TestFilterResult> { Success = true, Data = result });
    }

    /// <summary>
    /// Toggle filter enabled/disabled status
    /// </summary>
    [HttpPost("{id}/toggle")]
    [Authorize(Policy = "PowerUserAccess")]
    public async Task<ActionResult<ApiResponse<ImportLevelFilterDto>>> Toggle(Guid id)
    {
        var filter = await _context.ImportLevelFilters.FindAsync(id);
        if (filter == null)
        {
            return NotFound(new ApiResponse<ImportLevelFilterDto> { Success = false, Error = "Filter not found" });
        }

        filter.IsEnabled = !filter.IsEnabled;
        filter.UpdatedAt = DateTime.UtcNow;
        await _context.SaveChangesAsync();

        _logger.LogInformation("Import level filter {Action}: {Name}", 
            filter.IsEnabled ? "enabled" : "disabled", filter.Name);

        var dto = new ImportLevelFilterDto
        {
            Id = filter.Id,
            Name = filter.Name,
            FilePattern = filter.FilePattern,
            MinLevel = filter.MinLevel,
            MinLevelName = filter.MinLevelName,
            IsEnabled = filter.IsEnabled,
            Priority = filter.Priority,
            Description = filter.Description,
            CreatedAt = filter.CreatedAt,
            UpdatedAt = filter.UpdatedAt,
            CreatedBy = filter.CreatedBy
        };

        return Ok(new ApiResponse<ImportLevelFilterDto> { Success = true, Data = dto });
    }

    private static bool IsValidRegex(string pattern)
    {
        if (string.IsNullOrEmpty(pattern)) return false;
        try
        {
            _ = new Regex(pattern);
            return true;
        }
        catch
        {
            return false;
        }
    }
}

#region DTOs

public class ImportLevelFilterDto
{
    public Guid Id { get; set; }
    public string Name { get; set; } = string.Empty;
    public string FilePattern { get; set; } = string.Empty;
    public int MinLevel { get; set; }
    public string MinLevelName { get; set; } = string.Empty;
    public bool IsEnabled { get; set; }
    public int Priority { get; set; }
    public string? Description { get; set; }
    public DateTime CreatedAt { get; set; }
    public DateTime UpdatedAt { get; set; }
    public string? CreatedBy { get; set; }
}

public class CreateImportLevelFilterRequest
{
    public string Name { get; set; } = string.Empty;
    public string FilePattern { get; set; } = string.Empty;
    public int MinLevel { get; set; } = 0;
    public bool IsEnabled { get; set; } = true;
    public int Priority { get; set; } = 100;
    public string? Description { get; set; }
}

public class UpdateImportLevelFilterRequest
{
    public string? Name { get; set; }
    public string? FilePattern { get; set; }
    public int? MinLevel { get; set; }
    public bool? IsEnabled { get; set; }
    public int? Priority { get; set; }
    public string? Description { get; set; }
}

public class TestFilterRequest
{
    public string FilePath { get; set; } = string.Empty;
}

public class TestFilterResult
{
    public string FilePath { get; set; } = string.Empty;
    public ImportLevelFilterDto? MatchingFilter { get; set; }
    public bool WouldImportTrace { get; set; }
    public bool WouldImportDebug { get; set; }
    public bool WouldImportInfo { get; set; }
    public bool WouldImportWarn { get; set; }
    public bool WouldImportError { get; set; }
    public bool WouldImportFatal { get; set; }
}

#endregion
