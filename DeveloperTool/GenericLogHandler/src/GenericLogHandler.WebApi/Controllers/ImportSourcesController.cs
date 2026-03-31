using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Mvc;
using Microsoft.EntityFrameworkCore;
using GenericLogHandler.Data;
using GenericLogHandler.Core.Models.Configuration;
using GenericLogHandler.WebApi.Models;
using Newtonsoft.Json;

namespace GenericLogHandler.WebApi.Controllers;

/// <summary>
/// Manages import sources configuration stored in the database
/// </summary>
[ApiController]
[Route("api/[controller]")]
public class ImportSourcesController : ControllerBase
{
    private readonly LoggingDbContext _context;
    private readonly ILogger<ImportSourcesController> _logger;

    public ImportSourcesController(LoggingDbContext context, ILogger<ImportSourcesController> logger)
    {
        _context = context;
        _logger = logger;
    }

    /// <summary>
    /// Get all import sources
    /// </summary>
    [HttpGet]
    public async Task<ActionResult<ApiResponse<List<ImportSourceDto>>>> GetAll()
    {
        var sources = await _context.ImportSources
            .OrderBy(s => s.Priority)
            .ThenBy(s => s.Name)
            .ToListAsync();

        var dtos = sources.Select(MapToDto).ToList();
        return Ok(new ApiResponse<List<ImportSourceDto>> { Success = true, Data = dtos });
    }

    /// <summary>
    /// Get a single import source by ID
    /// </summary>
    [HttpGet("{id}")]
    public async Task<ActionResult<ApiResponse<ImportSourceDto>>> GetById(Guid id)
    {
        var source = await _context.ImportSources.FindAsync(id);
        if (source == null)
        {
            return NotFound(new ApiResponse<ImportSourceDto> { Success = false, Error = "Import source not found" });
        }

        return Ok(new ApiResponse<ImportSourceDto> { Success = true, Data = MapToDto(source) });
    }

    /// <summary>
    /// Create a new import source
    /// </summary>
    [HttpPost]
    [Authorize(Policy = "PowerUserAccess")]
    public async Task<ActionResult<ApiResponse<ImportSourceDto>>> Create([FromBody] CreateImportSourceRequest request)
    {
        var source = new ImportSourceEntity
        {
            Name = request.Name,
            Type = request.Type ?? "file",
            Enabled = request.Enabled,
            Priority = request.Priority,
            Path = request.Path,
            Format = request.Format ?? "json",
            WatchDirectory = request.WatchDirectory,
            Encoding = request.Encoding ?? "utf-8",
            PollInterval = request.PollInterval,
            ProcessExistingFiles = request.ProcessExistingFiles,
            IsAppendOnly = request.IsAppendOnly,
            MaxFileAgeDays = request.MaxFileAgeDays,
            Description = request.Description,
            ConfigJson = request.ConfigJson,
            CreatedAt = DateTime.UtcNow,
            UpdatedAt = DateTime.UtcNow,
            CreatedBy = User.Identity?.Name
        };

        _context.ImportSources.Add(source);
        await _context.SaveChangesAsync();

        _logger.LogInformation("Import source created: {Name} ({Path})", source.Name, source.Path);

        return Ok(new ApiResponse<ImportSourceDto> { Success = true, Data = MapToDto(source) });
    }

    /// <summary>
    /// Update an existing import source
    /// </summary>
    [HttpPut("{id}")]
    [Authorize(Policy = "PowerUserAccess")]
    public async Task<ActionResult<ApiResponse<ImportSourceDto>>> Update(Guid id, [FromBody] UpdateImportSourceRequest request)
    {
        var source = await _context.ImportSources.FindAsync(id);
        if (source == null)
        {
            return NotFound(new ApiResponse<ImportSourceDto> { Success = false, Error = "Import source not found" });
        }

        if (request.Name != null) source.Name = request.Name;
        if (request.Type != null) source.Type = request.Type;
        if (request.Enabled.HasValue) source.Enabled = request.Enabled.Value;
        if (request.Priority.HasValue) source.Priority = request.Priority.Value;
        if (request.Path != null) source.Path = request.Path;
        if (request.Format != null) source.Format = request.Format;
        if (request.WatchDirectory.HasValue) source.WatchDirectory = request.WatchDirectory.Value;
        if (request.Encoding != null) source.Encoding = request.Encoding;
        if (request.PollInterval.HasValue) source.PollInterval = request.PollInterval.Value;
        if (request.ProcessExistingFiles.HasValue) source.ProcessExistingFiles = request.ProcessExistingFiles.Value;
        if (request.IsAppendOnly.HasValue) source.IsAppendOnly = request.IsAppendOnly.Value;
        if (request.MaxFileAgeDays.HasValue) source.MaxFileAgeDays = request.MaxFileAgeDays.Value;
        if (request.Description != null) source.Description = request.Description;
        if (request.ConfigJson != null) source.ConfigJson = request.ConfigJson;
        
        source.UpdatedAt = DateTime.UtcNow;

        await _context.SaveChangesAsync();

        _logger.LogInformation("Import source updated: {Name}", source.Name);

        return Ok(new ApiResponse<ImportSourceDto> { Success = true, Data = MapToDto(source) });
    }

    /// <summary>
    /// Delete an import source
    /// </summary>
    [HttpDelete("{id}")]
    [Authorize(Policy = "PowerUserAccess")]
    public async Task<ActionResult<ApiResponse<object>>> Delete(Guid id)
    {
        var source = await _context.ImportSources.FindAsync(id);
        if (source == null)
        {
            return NotFound(new ApiResponse<object> { Success = false, Error = "Import source not found" });
        }

        _context.ImportSources.Remove(source);
        await _context.SaveChangesAsync();

        _logger.LogInformation("Import source deleted: {Name}", source.Name);

        return Ok(new ApiResponse<object> { Success = true, Data = new { message = "Import source deleted" } });
    }

    /// <summary>
    /// Toggle import source enabled/disabled
    /// </summary>
    [HttpPost("{id}/toggle")]
    [Authorize(Policy = "PowerUserAccess")]
    public async Task<ActionResult<ApiResponse<ImportSourceDto>>> Toggle(Guid id)
    {
        var source = await _context.ImportSources.FindAsync(id);
        if (source == null)
        {
            return NotFound(new ApiResponse<ImportSourceDto> { Success = false, Error = "Import source not found" });
        }

        source.Enabled = !source.Enabled;
        source.UpdatedAt = DateTime.UtcNow;
        await _context.SaveChangesAsync();

        _logger.LogInformation("Import source {Action}: {Name}", 
            source.Enabled ? "enabled" : "disabled", source.Name);

        return Ok(new ApiResponse<ImportSourceDto> { Success = true, Data = MapToDto(source) });
    }

    /// <summary>
    /// Test connection/accessibility of an import source
    /// </summary>
    [HttpPost("{id}/test")]
    public async Task<ActionResult<ApiResponse<TestImportSourceResult>>> Test(Guid id)
    {
        var source = await _context.ImportSources.FindAsync(id);
        if (source == null)
        {
            return NotFound(new ApiResponse<TestImportSourceResult> { Success = false, Error = "Import source not found" });
        }

        var result = new TestImportSourceResult { SourceName = source.Name };

        try
        {
            switch (source.Type.ToLowerInvariant())
            {
                case "file":
                case "json":
                case "xml":
                case "log":
                    result = TestFileSource(source);
                    break;
                default:
                    result.IsAccessible = false;
                    result.Message = $"Testing not implemented for source type: {source.Type}";
                    break;
            }
        }
        catch (Exception ex)
        {
            result.IsAccessible = false;
            result.Message = $"Error testing source: {ex.Message}";
            _logger.LogWarning(ex, "Error testing import source: {Name}", source.Name);
        }

        return Ok(new ApiResponse<TestImportSourceResult> { Success = true, Data = result });
    }

    /// <summary>
    /// Test file-based import source accessibility
    /// </summary>
    private TestImportSourceResult TestFileSource(ImportSourceEntity source)
    {
        var result = new TestImportSourceResult { SourceName = source.Name };

        // Handle wildcards in path
        var path = source.Path;
        var directory = System.IO.Path.GetDirectoryName(path);
        var pattern = System.IO.Path.GetFileName(path);

        // If no wildcards, check if it's a directory
        if (!pattern.Contains('*') && !pattern.Contains('?'))
        {
            if (Directory.Exists(path))
            {
                directory = path;
                pattern = "*";
            }
        }

        if (string.IsNullOrEmpty(directory))
        {
            result.IsAccessible = false;
            result.Message = "Invalid path - could not determine directory";
            return result;
        }

        if (!Directory.Exists(directory))
        {
            result.IsAccessible = false;
            result.Message = $"Directory does not exist: {directory}";
            return result;
        }

        try
        {
            var files = Directory.GetFiles(directory, pattern ?? "*").Take(100).ToList();
            result.IsAccessible = true;
            result.FileCount = files.Count;
            result.Message = $"Found {files.Count} file(s) matching pattern";
            
            if (files.Count > 0)
            {
                var sampleFiles = files.Take(5).Select(System.IO.Path.GetFileName).Where(f => f is not null).ToList()!;
                result.SampleFiles = sampleFiles;
            }
        }
        catch (UnauthorizedAccessException)
        {
            result.IsAccessible = false;
            result.Message = "Access denied to directory";
        }
        catch (Exception ex)
        {
            result.IsAccessible = false;
            result.Message = $"Error accessing directory: {ex.Message}";
        }

        return result;
    }

    private static ImportSourceDto MapToDto(ImportSourceEntity entity)
    {
        return new ImportSourceDto
        {
            Id = entity.Id,
            Name = entity.Name,
            Type = entity.Type,
            Enabled = entity.Enabled,
            Priority = entity.Priority,
            Path = entity.Path,
            Format = entity.Format,
            WatchDirectory = entity.WatchDirectory,
            Encoding = entity.Encoding,
            PollInterval = entity.PollInterval,
            ProcessExistingFiles = entity.ProcessExistingFiles,
            IsAppendOnly = entity.IsAppendOnly,
            MaxFileAgeDays = entity.MaxFileAgeDays,
            Description = entity.Description,
            ConfigJson = entity.ConfigJson,
            CreatedAt = entity.CreatedAt,
            UpdatedAt = entity.UpdatedAt,
            CreatedBy = entity.CreatedBy,
            LastImportAt = entity.LastImportAt,
            LastImportCount = entity.LastImportCount,
            LastError = entity.LastError
        };
    }
}

#region DTOs

public class ImportSourceDto
{
    public Guid Id { get; set; }
    public string Name { get; set; } = string.Empty;
    public string Type { get; set; } = "file";
    public bool Enabled { get; set; }
    public int Priority { get; set; }
    public string Path { get; set; } = string.Empty;
    public string Format { get; set; } = "json";
    public bool WatchDirectory { get; set; }
    public string Encoding { get; set; } = "utf-8";
    public int PollInterval { get; set; }
    public bool ProcessExistingFiles { get; set; }
    public bool IsAppendOnly { get; set; }
    public int MaxFileAgeDays { get; set; }
    public string? Description { get; set; }
    public string? ConfigJson { get; set; }
    public DateTime CreatedAt { get; set; }
    public DateTime UpdatedAt { get; set; }
    public string? CreatedBy { get; set; }
    public DateTime? LastImportAt { get; set; }
    public int LastImportCount { get; set; }
    public string? LastError { get; set; }
}

public class CreateImportSourceRequest
{
    public string Name { get; set; } = string.Empty;
    public string? Type { get; set; }
    public bool Enabled { get; set; } = true;
    public int Priority { get; set; } = 100;
    public string Path { get; set; } = string.Empty;
    public string? Format { get; set; }
    public bool WatchDirectory { get; set; }
    public string? Encoding { get; set; }
    public int PollInterval { get; set; } = 30;
    public bool ProcessExistingFiles { get; set; } = true;
    public bool IsAppendOnly { get; set; }
    public int MaxFileAgeDays { get; set; } = 30;
    public string? Description { get; set; }
    public string? ConfigJson { get; set; }
}

public class UpdateImportSourceRequest
{
    public string? Name { get; set; }
    public string? Type { get; set; }
    public bool? Enabled { get; set; }
    public int? Priority { get; set; }
    public string? Path { get; set; }
    public string? Format { get; set; }
    public bool? WatchDirectory { get; set; }
    public string? Encoding { get; set; }
    public int? PollInterval { get; set; }
    public bool? ProcessExistingFiles { get; set; }
    public bool? IsAppendOnly { get; set; }
    public int? MaxFileAgeDays { get; set; }
    public string? Description { get; set; }
    public string? ConfigJson { get; set; }
}

public class TestImportSourceResult
{
    public string SourceName { get; set; } = string.Empty;
    public bool IsAccessible { get; set; }
    public string Message { get; set; } = string.Empty;
    public int FileCount { get; set; }
    public List<string>? SampleFiles { get; set; }
}

#endregion
