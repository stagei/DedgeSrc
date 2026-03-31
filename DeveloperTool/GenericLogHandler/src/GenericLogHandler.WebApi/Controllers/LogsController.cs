using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Mvc;
using GenericLogHandler.Core.Interfaces;
using GenericLogHandler.Core.Models;
using GenericLogHandler.Data;
using GenericLogHandler.WebApi.Models;
using System.Text;
using System.Text.Json;
using CsvHelper;
using System.Globalization;
using ClosedXML.Excel;

namespace GenericLogHandler.WebApi.Controllers;

/// <summary>
/// API controller for log operations
/// </summary>
[ApiController]
[Route("api/[controller]")]
public class LogsController : ControllerBase
{
    private readonly ILogRepository _repository;
    private readonly ILogger<LogsController> _logger;
    private readonly LoggingDbContext _context;

    public LogsController(ILogRepository repository, ILogger<LogsController> logger, LoggingDbContext context)
    {
        _repository = repository;
        _logger = logger;
        _context = context;
    }

    /// <summary>
    /// Search for log entries (GET with query parameters)
    /// </summary>
    [HttpGet("search")]
    public async Task<ActionResult<ApiResponse<PagedResult<LogEntryDto>>>> SearchLogsGet(
        [FromQuery] LogSearchRequest request)
    {
        return await SearchLogsInternal(request);
    }

    /// <summary>
    /// Search for log entries (POST with JSON body)
    /// </summary>
    [HttpPost("search")]
    public async Task<ActionResult<ApiResponse<PagedResult<LogEntryDto>>>> SearchLogsPost(
        [FromBody] LogSearchRequest request)
    {
        return await SearchLogsInternal(request);
    }

    /// <summary>
    /// Converts a DateTime to UTC, handling Unspecified kind by treating it as local time
    /// </summary>
    private static DateTime? ToUtc(DateTime? dt)
    {
        if (!dt.HasValue) return null;
        return dt.Value.Kind switch
        {
            DateTimeKind.Utc => dt.Value,
            DateTimeKind.Local => dt.Value.ToUniversalTime(),
            _ => DateTime.SpecifyKind(dt.Value, DateTimeKind.Local).ToUniversalTime()
        };
    }

    private async Task<ActionResult<ApiResponse<PagedResult<LogEntryDto>>>> SearchLogsInternal(
        LogSearchRequest request)
    {
        try
        {
            var criteria = new LogSearchCriteria
            {
                FromDate = ToUtc(request.FromDate),
                ToDate = ToUtc(request.ToDate),
                Levels = request.Levels?.Select(ParseLogLevel).Where(l => l.HasValue).Select(l => l!.Value).ToList(),
                ComputerName = request.ComputerName,
                UserName = request.UserName,
                MessageText = request.MessageText,
                ExceptionText = request.ExceptionText,
                RegexPattern = request.RegexPattern,
                FunctionName = request.FunctionName,
                SourceFile = request.SourceFile,
                SourceType = request.SourceType,
                AlertId = request.AlertId,
                Ordrenr = request.Ordrenr,
                Avdnr = request.Avdnr,
                JobName = request.JobName,
                JobStatus = request.JobStatus,
                Page = request.Page,
                PageSize = Math.Min(request.PageSize, 1000), // Limit max page size
                SortBy = request.SortBy,
                SortDescending = request.SortDescending
            };

            var result = await _repository.SearchAsync(criteria);
            var dtoResult = new PagedResult<LogEntryDto>
            {
                Items = result.Items.Select(LogEntryDto.FromLogEntry).ToList(),
                TotalCount = result.TotalCount,
                Page = result.Page,
                PageSize = result.PageSize
            };

            return Ok(ApiResponse<PagedResult<LogEntryDto>>.CreateSuccess(dtoResult));
        }
        catch (Exception ex)
        {
            _logger.LogError(ex, "Error searching logs");
            return BadRequest(ApiResponse<PagedResult<LogEntryDto>>.CreateError("Error searching logs: " + ex.Message));
        }
    }

    /// <summary>
    /// Get a specific log entry by ID
    /// </summary>
    [HttpGet("{id}")]
    public async Task<ActionResult<ApiResponse<LogEntryDto>>> GetLogEntry(Guid id)
    {
        try
        {
            var logEntry = await _repository.GetByIdAsync(id);
            if (logEntry == null)
            {
                return NotFound(ApiResponse<LogEntryDto>.CreateError("Log entry not found"));
            }

            return Ok(ApiResponse<LogEntryDto>.CreateSuccess(LogEntryDto.FromLogEntry(logEntry)));
        }
        catch (Exception ex)
        {
            _logger.LogError(ex, "Error retrieving log entry {Id}", id);
            return BadRequest(ApiResponse<LogEntryDto>.CreateError("Error retrieving log entry: " + ex.Message));
        }
    }

    /// <summary>
    /// Get log statistics for a date range
    /// </summary>
    [HttpGet("statistics")]
    public async Task<ActionResult<ApiResponse<LogStatisticsDto>>> GetStatistics(
        [FromQuery] DateTime? fromDate = null,
        [FromQuery] DateTime? toDate = null)
    {
        try
        {
            fromDate ??= DateTime.UtcNow.AddDays(-7);
            toDate ??= DateTime.UtcNow;

            var stats = await _repository.GetStatisticsAsync(fromDate.Value, toDate.Value);
            var dto = LogStatisticsDto.FromLogStatistics(stats);

            return Ok(ApiResponse<LogStatisticsDto>.CreateSuccess(dto));
        }
        catch (Exception ex)
        {
            _logger.LogError(ex, "Error retrieving statistics");
            return BadRequest(ApiResponse<LogStatisticsDto>.CreateError("Error retrieving statistics: " + ex.Message));
        }
    }

    /// <summary>
    /// Get log level counts for a date range
    /// </summary>
    [HttpGet("level-counts")]
    public async Task<ActionResult<ApiResponse<Dictionary<string, long>>>> GetLevelCounts(
        [FromQuery] DateTime? fromDate = null,
        [FromQuery] DateTime? toDate = null)
    {
        try
        {
            fromDate ??= DateTime.UtcNow.AddDays(-1);
            toDate ??= DateTime.UtcNow;

            var counts = await _repository.GetLevelCountsAsync(fromDate.Value, toDate.Value);
            var stringCounts = counts.ToDictionary(kvp => kvp.Key.ToString(), kvp => kvp.Value);

            return Ok(ApiResponse<Dictionary<string, long>>.CreateSuccess(stringCounts));
        }
        catch (Exception ex)
        {
            _logger.LogError(ex, "Error retrieving level counts");
            return BadRequest(ApiResponse<Dictionary<string, long>>.CreateError("Error retrieving level counts: " + ex.Message));
        }
    }

    /// <summary>
    /// Get top computers by log count
    /// </summary>
    [HttpGet("top-computers")]
    public async Task<ActionResult<ApiResponse<List<ComputerLogCountDto>>>> GetTopComputers(
        [FromQuery] DateTime? fromDate = null,
        [FromQuery] DateTime? toDate = null,
        [FromQuery] int limit = 10)
    {
        try
        {
            fromDate ??= DateTime.UtcNow.AddDays(-1);
            toDate ??= DateTime.UtcNow;
            limit = Math.Min(limit, 100); // Limit max results

            var computers = await _repository.GetTopComputersAsync(fromDate.Value, toDate.Value, limit);
            var dtos = computers.Select(ComputerLogCountDto.FromComputerLogCount).ToList();

            return Ok(ApiResponse<List<ComputerLogCountDto>>.CreateSuccess(dtos));
        }
        catch (Exception ex)
        {
            _logger.LogError(ex, "Error retrieving top computers");
            return BadRequest(ApiResponse<List<ComputerLogCountDto>>.CreateError("Error retrieving top computers: " + ex.Message));
        }
    }

    /// <summary>
    /// Get recent error entries
    /// </summary>
    [HttpGet("recent-errors")]
    public async Task<ActionResult<ApiResponse<List<LogEntryDto>>>> GetRecentErrors(
        [FromQuery] int hours = 24,
        [FromQuery] int limit = 100)
    {
        try
        {
            hours = Math.Min(hours, 168); // Limit to 1 week
            limit = Math.Min(limit, 1000); // Limit max results

            var errors = await _repository.GetRecentErrorsAsync(hours, limit);
            var dtos = errors.Select(LogEntryDto.FromLogEntry).ToList();

            return Ok(ApiResponse<List<LogEntryDto>>.CreateSuccess(dtos));
        }
        catch (Exception ex)
        {
            _logger.LogError(ex, "Error retrieving recent errors");
            return BadRequest(ApiResponse<List<LogEntryDto>>.CreateError("Error retrieving recent errors: " + ex.Message));
        }
    }

    /// <summary>
    /// Export search results to CSV
    /// </summary>
    [HttpPost("export/csv")]
    public async Task<IActionResult> ExportToCsv([FromBody] LogSearchRequest request)
    {
        try
        {
            var criteria = BuildSearchCriteria(request);
            criteria.PageSize = 50000; // Large page size for export
            criteria.Page = 1;

            var result = await _repository.SearchAsync(criteria);
            
            using var memoryStream = new MemoryStream();
            using var writer = new StreamWriter(memoryStream, Encoding.UTF8);
            using var csv = new CsvWriter(writer, CultureInfo.InvariantCulture);

            await csv.WriteRecordsAsync(result.Items.Select(LogEntryDto.FromLogEntry));
            await writer.FlushAsync();

            var fileName = $"logs_export_{DateTime.UtcNow:yyyyMMdd_HHmmss}.csv";
            return File(memoryStream.ToArray(), "text/csv", fileName);
        }
        catch (Exception ex)
        {
            _logger.LogError(ex, "Error exporting to CSV");
            return BadRequest("Error exporting to CSV: " + ex.Message);
        }
    }

    /// <summary>
    /// Export search results to JSON
    /// </summary>
    [HttpPost("export/json")]
    public async Task<IActionResult> ExportToJson([FromBody] JsonExportRequest request)
    {
        try
        {
            var criteria = BuildSearchCriteria(request);
            criteria.PageSize = Math.Min(request.MaxEntries, 50000);
            criteria.Page = 1;

            var result = await _repository.SearchAsync(criteria);
            
            var entries = result.Items.Select(e => BuildJsonEntry(e, request.IncludeFields, request.ExcludeFields)).ToList();
            
            var jsonOptions = new System.Text.Json.JsonSerializerOptions
            {
                WriteIndented = request.PrettyPrint,
                PropertyNamingPolicy = null // Keep PascalCase
            };
            
            var json = System.Text.Json.JsonSerializer.Serialize(new
            {
                ExportedAt = DateTime.UtcNow,
                TotalCount = result.TotalCount,
                ExportedCount = entries.Count,
                Entries = entries
            }, jsonOptions);

            var fileName = $"logs_export_{DateTime.UtcNow:yyyyMMdd_HHmmss}.json";
            return File(Encoding.UTF8.GetBytes(json), "application/json", fileName);
        }
        catch (Exception ex)
        {
            _logger.LogError(ex, "Error exporting to JSON");
            return BadRequest("Error exporting to JSON: " + ex.Message);
        }
    }

    private static Dictionary<string, object?> BuildJsonEntry(LogEntry entry, List<string>? includeFields, List<string>? excludeFields)
    {
        var allFields = new Dictionary<string, object?>
        {
            ["Id"] = entry.Id,
            ["Timestamp"] = entry.Timestamp,
            ["Level"] = entry.Level.ToString(),
            ["ComputerName"] = entry.ComputerName,
            ["UserName"] = entry.UserName,
            ["FunctionName"] = entry.FunctionName,
            ["Message"] = entry.Message,
            ["ErrorId"] = entry.ErrorId,
            ["ExceptionType"] = entry.ExceptionType,
            ["StackTrace"] = entry.StackTrace,
            ["SourceFile"] = entry.SourceFile,
            ["SourceType"] = entry.SourceType,
            ["JobName"] = entry.JobName,
            ["JobStatus"] = entry.JobStatus,
            ["Ordrenr"] = entry.Ordrenr,
            ["Avdnr"] = entry.Avdnr,
            ["AlertId"] = entry.AlertId,
            ["Protected"] = entry.Protected
        };

        // Filter fields if specified
        if (includeFields != null && includeFields.Count > 0)
        {
            return allFields
                .Where(kvp => includeFields.Contains(kvp.Key, StringComparer.OrdinalIgnoreCase))
                .ToDictionary(kvp => kvp.Key, kvp => kvp.Value);
        }
        
        if (excludeFields != null && excludeFields.Count > 0)
        {
            return allFields
                .Where(kvp => !excludeFields.Contains(kvp.Key, StringComparer.OrdinalIgnoreCase))
                .ToDictionary(kvp => kvp.Key, kvp => kvp.Value);
        }

        return allFields;
    }

    /// <summary>
    /// Export search results to Excel
    /// </summary>
    [HttpPost("export/excel")]
    public async Task<IActionResult> ExportToExcel([FromBody] LogSearchRequest request)
    {
        try
        {
            var criteria = BuildSearchCriteria(request);
            criteria.PageSize = 50000; // Large page size for export
            criteria.Page = 1;

            var result = await _repository.SearchAsync(criteria);
            
            using var workbook = new XLWorkbook();
            var worksheet = workbook.Worksheets.Add("Log Entries");

            // Headers
            var headers = new[] { "Timestamp", "Level", "Computer", "User", "Function", "Message", "Error ID", "Exception Type" };
            for (int i = 0; i < headers.Length; i++)
            {
                worksheet.Cell(1, i + 1).Value = headers[i];
                worksheet.Cell(1, i + 1).Style.Font.Bold = true;
            }

            // Data
            var row = 2;
            foreach (var entry in result.Items)
            {
                worksheet.Cell(row, 1).Value = entry.Timestamp;
                worksheet.Cell(row, 2).Value = entry.Level.ToString();
                worksheet.Cell(row, 3).Value = entry.ComputerName;
                worksheet.Cell(row, 4).Value = entry.UserName;
                worksheet.Cell(row, 5).Value = entry.FunctionName;
                worksheet.Cell(row, 6).Value = entry.Message;
                worksheet.Cell(row, 7).Value = entry.ErrorId;
                worksheet.Cell(row, 8).Value = entry.ExceptionType;
                row++;
            }

            // Auto-fit columns
            worksheet.Columns().AdjustToContents();

            using var stream = new MemoryStream();
            workbook.SaveAs(stream);
            
            var fileName = $"logs_export_{DateTime.UtcNow:yyyyMMdd_HHmmss}.xlsx";
            return File(stream.ToArray(), "application/vnd.openxmlformats-officedocument.spreadsheetml.sheet", fileName);
        }
        catch (Exception ex)
        {
            _logger.LogError(ex, "Error exporting to Excel");
            return BadRequest("Error exporting to Excel: " + ex.Message);
        }
    }

    /// <summary>
    /// Get distinct computer names for filter dropdowns
    /// </summary>
    [HttpGet("computers")]
    [ResponseCache(Duration = 300)] // Cache for 5 minutes
    public async Task<ActionResult<ApiResponse<List<string>>>> GetComputers([FromQuery] int limit = 100)
    {
        try
        {
            var computers = await _repository.GetDistinctValuesAsync("ComputerName", limit);
            return Ok(ApiResponse<List<string>>.CreateSuccess(computers));
        }
        catch (Exception ex)
        {
            _logger.LogError(ex, "Error getting distinct computers");
            return BadRequest(ApiResponse<List<string>>.CreateError("Error getting computers: " + ex.Message));
        }
    }

    /// <summary>
    /// Get distinct source types for filter dropdowns
    /// </summary>
    [HttpGet("source-types")]
    [ResponseCache(Duration = 300)]
    public async Task<ActionResult<ApiResponse<List<string>>>> GetSourceTypes([FromQuery] int limit = 50)
    {
        try
        {
            var sourceTypes = await _repository.GetDistinctValuesAsync("SourceType", limit);
            return Ok(ApiResponse<List<string>>.CreateSuccess(sourceTypes));
        }
        catch (Exception ex)
        {
            _logger.LogError(ex, "Error getting distinct source types");
            return BadRequest(ApiResponse<List<string>>.CreateError("Error getting source types: " + ex.Message));
        }
    }

    /// <summary>
    /// Get distinct user names for filter dropdowns
    /// </summary>
    [HttpGet("users")]
    [ResponseCache(Duration = 300)]
    public async Task<ActionResult<ApiResponse<List<string>>>> GetUsers([FromQuery] int limit = 100)
    {
        try
        {
            var users = await _repository.GetDistinctValuesAsync("UserName", limit);
            return Ok(ApiResponse<List<string>>.CreateSuccess(users));
        }
        catch (Exception ex)
        {
            _logger.LogError(ex, "Error getting distinct users");
            return BadRequest(ApiResponse<List<string>>.CreateError("Error getting users: " + ex.Message));
        }
    }

    /// <summary>
    /// Get distinct job names for filter dropdowns
    /// </summary>
    [HttpGet("job-names")]
    [ResponseCache(Duration = 300)]
    public async Task<ActionResult<ApiResponse<List<string>>>> GetJobNames([FromQuery] int limit = 100)
    {
        try
        {
            var jobNames = await _repository.GetDistinctValuesAsync("JobName", limit);
            return Ok(ApiResponse<List<string>>.CreateSuccess(jobNames));
        }
        catch (Exception ex)
        {
            _logger.LogError(ex, "Error getting distinct job names");
            return BadRequest(ApiResponse<List<string>>.CreateError("Error getting job names: " + ex.Message));
        }
    }

    /// <summary>
    /// Get distinct function names for filter dropdowns
    /// </summary>
    [HttpGet("functions")]
    [ResponseCache(Duration = 300)]
    public async Task<ActionResult<ApiResponse<List<string>>>> GetFunctions([FromQuery] int limit = 100)
    {
        try
        {
            var functions = await _repository.GetDistinctValuesAsync("FunctionName", limit);
            return Ok(ApiResponse<List<string>>.CreateSuccess(functions));
        }
        catch (Exception ex)
        {
            _logger.LogError(ex, "Error getting distinct functions");
            return BadRequest(ApiResponse<List<string>>.CreateError("Error getting functions: " + ex.Message));
        }
    }

    #region Bulk Operations

    /// <summary>
    /// Export specific log entries by IDs
    /// </summary>
    [HttpPost("bulk-export")]
    public async Task<IActionResult> BulkExport([FromBody] BulkExportRequest request)
    {
        try
        {
            if (request.Ids == null || request.Ids.Count == 0)
            {
                return BadRequest(ApiResponse<object>.CreateError("No IDs provided"));
            }

            var entries = await _repository.GetByIdsAsync(request.Ids);
            
            if (request.Format?.ToLower() == "json")
            {
                var json = System.Text.Json.JsonSerializer.Serialize(entries.Select(LogEntryDto.FromLogEntry), 
                    new System.Text.Json.JsonSerializerOptions { WriteIndented = true });
                return File(Encoding.UTF8.GetBytes(json), "application/json", "logs-export.json");
            }
            else // CSV default
            {
                using var memoryStream = new MemoryStream();
                using var writer = new StreamWriter(memoryStream);
                using var csv = new CsvWriter(writer, CultureInfo.InvariantCulture);
                csv.WriteRecords(entries.Select(LogEntryDto.FromLogEntry));
                await writer.FlushAsync();
                return File(memoryStream.ToArray(), "text/csv", "logs-export.csv");
            }
        }
        catch (Exception ex)
        {
            _logger.LogError(ex, "Error during bulk export");
            return BadRequest(ApiResponse<object>.CreateError("Export failed: " + ex.Message));
        }
    }

    /// <summary>
    /// Mark specific log entries as protected
    /// </summary>
    [HttpPost("bulk-protect")]
    public async Task<ActionResult<ApiResponse<int>>> BulkProtect([FromBody] BulkProtectRequest request)
    {
        try
        {
            if (request.Ids == null || request.Ids.Count == 0)
            {
                return BadRequest(ApiResponse<int>.CreateError("No IDs provided"));
            }

            var count = await _repository.SetProtectedAsync(request.Ids, request.Protected);
            _logger.LogInformation("Bulk protect: {Count} entries set to Protected={Protected} by {User}", 
                count, request.Protected, User.Identity?.Name ?? "unknown");
            
            return Ok(ApiResponse<int>.CreateSuccess(count));
        }
        catch (Exception ex)
        {
            _logger.LogError(ex, "Error during bulk protect");
            return BadRequest(ApiResponse<int>.CreateError("Protection update failed: " + ex.Message));
        }
    }

    /// <summary>
    /// Delete specific log entries by IDs (admin only)
    /// </summary>
    [HttpDelete("bulk-delete")]
    public async Task<ActionResult<ApiResponse<int>>> BulkDelete([FromBody] BulkDeleteRequest request)
    {
        try
        {
            if (request.Ids == null || request.Ids.Count == 0)
            {
                return BadRequest(ApiResponse<int>.CreateError("No IDs provided"));
            }

            // Check if any entries are protected
            var protectedCount = await _repository.CountProtectedAsync(request.Ids);
            if (protectedCount > 0 && !request.IncludeProtected)
            {
                return BadRequest(ApiResponse<int>.CreateError(
                    $"{protectedCount} entries are protected. Set IncludeProtected=true to delete them."));
            }

            var count = await _repository.DeleteByIdsAsync(request.Ids, request.IncludeProtected);
            _logger.LogWarning("Bulk delete: {Count} entries deleted by {User}", 
                count, User.Identity?.Name ?? "unknown");
            
            return Ok(ApiResponse<int>.CreateSuccess(count));
        }
        catch (Exception ex)
        {
            _logger.LogError(ex, "Error during bulk delete");
            return BadRequest(ApiResponse<int>.CreateError("Delete failed: " + ex.Message));
        }
    }

    /// <summary>
    /// Get log entries by IDs
    /// </summary>
    [HttpPost("by-ids")]
    public async Task<ActionResult<ApiResponse<List<LogEntryDto>>>> GetByIds([FromBody] List<long> ids)
    {
        try
        {
            if (ids == null || ids.Count == 0)
            {
                return BadRequest(ApiResponse<List<LogEntryDto>>.CreateError("No IDs provided"));
            }

            var entries = await _repository.GetByIdsAsync(ids);
            return Ok(ApiResponse<List<LogEntryDto>>.CreateSuccess(entries.Select(LogEntryDto.FromLogEntry).ToList()));
        }
        catch (Exception ex)
        {
            _logger.LogError(ex, "Error getting entries by IDs");
            return BadRequest(ApiResponse<List<LogEntryDto>>.CreateError("Error: " + ex.Message));
        }
    }

    #endregion

    #region Ingest API

    /// <summary>
    /// Accept a single log entry into the ingest queue (anonymous, fire-and-forget)
    /// </summary>
    [HttpPost("ingest")]
    [AllowAnonymous]
    public async Task<IActionResult> Ingest([FromBody] IngestLogRequest request)
    {
        try
        {
            var entry = new IngestQueueEntry
            {
                CreatedAt = DateTime.UtcNow,
                Payload = JsonSerializer.Serialize(request, _jsonOptions)
            };
            _context.IngestQueue.Add(entry);
            await _context.SaveChangesAsync();

            return StatusCode(202, ApiResponse<object>.CreateSuccess(new { queued = 1 }));
        }
        catch (Exception ex)
        {
            _logger.LogError(ex, "Error queuing ingest entry");
            return StatusCode(500, ApiResponse<object>.CreateError("Failed to queue entry: " + ex.Message));
        }
    }

    /// <summary>
    /// Accept a batch of log entries into the ingest queue (anonymous, fire-and-forget)
    /// </summary>
    [HttpPost("ingest/batch")]
    [AllowAnonymous]
    public async Task<IActionResult> IngestBatch([FromBody] List<IngestLogRequest> requests)
    {
        try
        {
            if (requests == null || requests.Count == 0)
                return BadRequest(ApiResponse<object>.CreateError("Empty batch"));

            var entries = requests.Select(r => new IngestQueueEntry
            {
                CreatedAt = DateTime.UtcNow,
                Payload = JsonSerializer.Serialize(r, _jsonOptions)
            });

            _context.IngestQueue.AddRange(entries);
            await _context.SaveChangesAsync();

            return StatusCode(202, ApiResponse<object>.CreateSuccess(new { queued = requests.Count }));
        }
        catch (Exception ex)
        {
            _logger.LogError(ex, "Error queuing ingest batch");
            return StatusCode(500, ApiResponse<object>.CreateError("Failed to queue batch: " + ex.Message));
        }
    }

    private static readonly JsonSerializerOptions _jsonOptions = new()
    {
        PropertyNamingPolicy = JsonNamingPolicy.CamelCase
    };

    #endregion

    private LogSearchCriteria BuildSearchCriteria(LogSearchRequest request)
    {
        return new LogSearchCriteria
        {
            FromDate = request.FromDate,
            ToDate = request.ToDate,
            Levels = request.Levels?.Select(ParseLogLevel).Where(l => l.HasValue).Select(l => l!.Value).ToList(),
            ComputerName = request.ComputerName,
            UserName = request.UserName,
            MessageText = request.MessageText,
            ExceptionText = request.ExceptionText,
            RegexPattern = request.RegexPattern,
            FunctionName = request.FunctionName,
            SourceFile = request.SourceFile,
            SourceType = request.SourceType,
            AlertId = request.AlertId,
            Ordrenr = request.Ordrenr,
            Avdnr = request.Avdnr,
            JobName = request.JobName,
            JobStatus = request.JobStatus,
            Page = request.Page,
            PageSize = Math.Min(request.PageSize, 1000),
            SortBy = request.SortBy,
            SortDescending = request.SortDescending
        };
    }

    private static GenericLogHandler.Core.Models.LogLevel? ParseLogLevel(string levelString)
    {
        return Enum.TryParse<GenericLogHandler.Core.Models.LogLevel>(levelString, true, out var level) ? level : null;
    }
}
