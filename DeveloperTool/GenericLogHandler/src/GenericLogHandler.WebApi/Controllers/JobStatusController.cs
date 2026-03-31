using Microsoft.AspNetCore.Mvc;
using GenericLogHandler.Core.Interfaces;
using GenericLogHandler.Core.Models;
using GenericLogHandler.WebApi.Models;
using Microsoft.EntityFrameworkCore;
using GenericLogHandler.Data;

namespace GenericLogHandler.WebApi.Controllers;

/// <summary>
/// API controller for job status operations
/// </summary>
[ApiController]
[Route("api/[controller]")]
public class JobStatusController : ControllerBase
{
    private readonly ILogRepository _repository;
    private readonly LoggingDbContext _context;
    private readonly ILogger<JobStatusController> _logger;

    public JobStatusController(ILogRepository repository, LoggingDbContext context, ILogger<JobStatusController> logger)
    {
        _repository = repository;
        _context = context;
        _logger = logger;
    }

    /// <summary>
    /// Get job status summary with counts by status
    /// </summary>
    [HttpGet("summary")]
    public async Task<ActionResult<ApiResponse<JobStatusSummaryDto>>> GetJobStatusSummary(
        [FromQuery] DateTime? fromDate,
        [FromQuery] DateTime? toDate,
        [FromQuery] string? jobName)
    {
        try
        {
            // Filter out boolean-like values that aren't real job statuses
            var query = _context.LogEntries.AsNoTracking()
                .Where(x => x.JobStatus != null && x.JobStatus != "" &&
                    x.JobStatus != "True" && x.JobStatus != "False");

            if (fromDate.HasValue)
                query = query.Where(x => x.Timestamp >= fromDate.Value.ToUniversalTime());
            if (toDate.HasValue)
                query = query.Where(x => x.Timestamp <= toDate.Value.ToUniversalTime());
            if (!string.IsNullOrEmpty(jobName))
                query = query.Where(x => x.JobName != null && x.JobName.Contains(jobName));

            var statusCounts = await query
                .GroupBy(x => x.JobStatus)
                .Select(g => new { Status = g.Key, Count = g.Count() })
                .ToListAsync();

            var summary = new JobStatusSummaryDto
            {
                TotalJobs = statusCounts.Sum(x => x.Count),
                StartedCount = statusCounts.FirstOrDefault(x => x.Status != null && 
                    (x.Status.Equals("Started", StringComparison.OrdinalIgnoreCase) ||
                     x.Status.Equals("Start", StringComparison.OrdinalIgnoreCase) ||
                     x.Status.Equals("Running", StringComparison.OrdinalIgnoreCase)))?.Count ?? 0,
                CompletedCount = statusCounts.FirstOrDefault(x => x.Status != null && 
                    (x.Status.Equals("Completed", StringComparison.OrdinalIgnoreCase) ||
                     x.Status.Equals("Complete", StringComparison.OrdinalIgnoreCase) ||
                     x.Status.Equals("Success", StringComparison.OrdinalIgnoreCase) ||
                     x.Status.Equals("Succeeded", StringComparison.OrdinalIgnoreCase)))?.Count ?? 0,
                FailedCount = statusCounts.FirstOrDefault(x => x.Status != null && 
                    (x.Status.Equals("Failed", StringComparison.OrdinalIgnoreCase) ||
                     x.Status.Equals("Fail", StringComparison.OrdinalIgnoreCase) ||
                     x.Status.Equals("Error", StringComparison.OrdinalIgnoreCase)))?.Count ?? 0,
                StatusBreakdown = statusCounts.ToDictionary(x => x.Status ?? "Unknown", x => x.Count)
            };

            return Ok(ApiResponse<JobStatusSummaryDto>.CreateSuccess(summary));
        }
        catch (Exception ex)
        {
            _logger.LogError(ex, "Error getting job status summary");
            return BadRequest(ApiResponse<JobStatusSummaryDto>.CreateError("Error getting job status summary: " + ex.Message));
        }
    }

    /// <summary>
    /// Get distinct job names with their latest status
    /// </summary>
    [HttpGet("jobs")]
    public async Task<ActionResult<ApiResponse<List<JobInfoDto>>>> GetJobs(
        [FromQuery] DateTime? fromDate,
        [FromQuery] DateTime? toDate,
        [FromQuery] string? status,
        [FromQuery] int limit = 100)
    {
        try
        {
            // Show entries that have JobStatus set (JobName can be empty for legacy data)
            // Filter out boolean-like values that aren't real job statuses
            var query = _context.LogEntries.AsNoTracking()
                .Where(x => x.JobStatus != null && x.JobStatus != "" &&
                    x.JobStatus != "True" && x.JobStatus != "False");

            if (fromDate.HasValue)
                query = query.Where(x => x.Timestamp >= fromDate.Value.ToUniversalTime());
            if (toDate.HasValue)
                query = query.Where(x => x.Timestamp <= toDate.Value.ToUniversalTime());
            if (!string.IsNullOrEmpty(status))
                query = query.Where(x => x.JobStatus != null && x.JobStatus.Contains(status));

            var jobs = await query
                .GroupBy(x => new { x.JobName, x.JobStatus })
                .Select(g => new
                {
                    JobName = g.Key.JobName,
                    JobStatus = g.Key.JobStatus,
                    Count = g.Count(),
                    FirstSeen = g.Min(x => x.Timestamp),
                    LastSeen = g.Max(x => x.Timestamp),
                    Computer = g.Select(x => x.ComputerName).FirstOrDefault()
                })
                .OrderByDescending(x => x.LastSeen)
                .Take(limit)
                .ToListAsync();

            var result = jobs.Select(j => new JobInfoDto
            {
                JobName = j.JobName ?? "",
                JobStatus = j.JobStatus ?? "",
                OccurrenceCount = j.Count,
                FirstSeen = j.FirstSeen,
                LastSeen = j.LastSeen,
                ComputerName = j.Computer ?? ""
            }).ToList();

            return Ok(ApiResponse<List<JobInfoDto>>.CreateSuccess(result));
        }
        catch (Exception ex)
        {
            _logger.LogError(ex, "Error getting jobs");
            return BadRequest(ApiResponse<List<JobInfoDto>>.CreateError("Error getting jobs: " + ex.Message));
        }
    }

    /// <summary>
    /// Get job execution history for a specific job
    /// </summary>
    [HttpGet("history/{jobName}")]
    public async Task<ActionResult<ApiResponse<List<JobExecutionDto>>>> GetJobHistory(
        string jobName,
        [FromQuery] DateTime? fromDate,
        [FromQuery] DateTime? toDate,
        [FromQuery] int limit = 50)
    {
        try
        {
            var query = _context.LogEntries.AsNoTracking()
                .Where(x => x.JobName != null && x.JobName == jobName && x.JobStatus != null && x.JobStatus != "");

            if (fromDate.HasValue)
                query = query.Where(x => x.Timestamp >= fromDate.Value.ToUniversalTime());
            if (toDate.HasValue)
                query = query.Where(x => x.Timestamp <= toDate.Value.ToUniversalTime());

            var executions = await query
                .OrderByDescending(x => x.Timestamp)
                .Take(limit)
                .Select(x => new JobExecutionDto
                {
                    Id = x.Id,
                    Timestamp = x.Timestamp,
                    JobStatus = x.JobStatus ?? "",
                    ComputerName = x.ComputerName,
                    UserName = x.UserName,
                    Message = x.Message,
                    ProcessId = x.ProcessId
                })
                .ToListAsync();

            return Ok(ApiResponse<List<JobExecutionDto>>.CreateSuccess(executions));
        }
        catch (Exception ex)
        {
            _logger.LogError(ex, "Error getting job history for {JobName}", jobName);
            return BadRequest(ApiResponse<List<JobExecutionDto>>.CreateError("Error getting job history: " + ex.Message));
        }
    }

    /// <summary>
    /// Get job executions with correlation (start/complete tracking)
    /// </summary>
    [HttpGet("executions")]
    public async Task<ActionResult<ApiResponse<List<JobExecutionTrackedDto>>>> GetJobExecutions(
        [FromQuery] DateTime? fromDate,
        [FromQuery] DateTime? toDate,
        [FromQuery] string? status,
        [FromQuery] string? jobName,
        [FromQuery] int limit = 100)
    {
        try
        {
            var query = _context.JobExecutions.AsNoTracking();

            if (fromDate.HasValue)
                query = query.Where(x => x.StartedAt >= fromDate.Value.ToUniversalTime());
            if (toDate.HasValue)
                query = query.Where(x => x.StartedAt <= toDate.Value.ToUniversalTime());
            if (!string.IsNullOrEmpty(status))
                query = query.Where(x => x.Status == status);
            if (!string.IsNullOrEmpty(jobName))
                query = query.Where(x => x.JobName.Contains(jobName));

            var executions = await query
                .OrderByDescending(x => x.StartedAt)
                .Take(limit)
                .Select(x => new JobExecutionTrackedDto
                {
                    Id = x.Id,
                    JobName = x.JobName,
                    StartedAt = x.StartedAt,
                    CompletedAt = x.CompletedAt,
                    Status = x.Status,
                    ComputerName = x.ComputerName ?? "",
                    ProcessId = x.ProcessId,
                    DurationSeconds = x.DurationSeconds,
                    ErrorMessage = x.ErrorMessage,
                    SourceFile = x.SourceFile
                })
                .ToListAsync();

            return Ok(ApiResponse<List<JobExecutionTrackedDto>>.CreateSuccess(executions));
        }
        catch (Exception ex)
        {
            _logger.LogError(ex, "Error getting job executions");
            return BadRequest(ApiResponse<List<JobExecutionTrackedDto>>.CreateError("Error getting job executions: " + ex.Message));
        }
    }

    /// <summary>
    /// Get orphaned/timed out jobs
    /// </summary>
    [HttpGet("orphaned")]
    public async Task<ActionResult<ApiResponse<List<JobExecutionTrackedDto>>>> GetOrphanedJobs(
        [FromQuery] int limit = 50)
    {
        try
        {
            var executions = await _context.JobExecutions.AsNoTracking()
                .Where(x => x.Status == "TimedOut" || (x.Status == "Started" && x.CompletedAt == null))
                .OrderByDescending(x => x.StartedAt)
                .Take(limit)
                .Select(x => new JobExecutionTrackedDto
                {
                    Id = x.Id,
                    JobName = x.JobName,
                    StartedAt = x.StartedAt,
                    CompletedAt = x.CompletedAt,
                    Status = x.Status,
                    ComputerName = x.ComputerName ?? "",
                    ProcessId = x.ProcessId,
                    DurationSeconds = x.DurationSeconds,
                    ErrorMessage = x.ErrorMessage,
                    SourceFile = x.SourceFile
                })
                .ToListAsync();

            return Ok(ApiResponse<List<JobExecutionTrackedDto>>.CreateSuccess(executions));
        }
        catch (Exception ex)
        {
            _logger.LogError(ex, "Error getting orphaned jobs");
            return BadRequest(ApiResponse<List<JobExecutionTrackedDto>>.CreateError("Error getting orphaned jobs: " + ex.Message));
        }
    }

    /// <summary>
    /// Manually resolve an orphaned job
    /// </summary>
    [HttpPost("resolve/{id}")]
    public async Task<ActionResult<ApiResponse<JobExecutionTrackedDto>>> ResolveOrphanedJob(
        Guid id,
        [FromBody] ResolveJobRequest request)
    {
        try
        {
            var execution = await _context.JobExecutions.FindAsync(id);
            if (execution == null)
            {
                return NotFound(ApiResponse<JobExecutionTrackedDto>.CreateError("Job execution not found"));
            }

            execution.Status = request.Status ?? "Completed";
            execution.CompletedAt = DateTime.UtcNow;
            execution.ErrorMessage = request.Resolution;
            execution.UpdatedAt = DateTime.UtcNow;

            if (execution.DurationSeconds == null)
            {
                execution.DurationSeconds = (DateTime.UtcNow - execution.StartedAt).TotalSeconds;
            }

            await _context.SaveChangesAsync();

            _logger.LogInformation("Manually resolved job execution {Id} as {Status}", id, execution.Status);

            var dto = new JobExecutionTrackedDto
            {
                Id = execution.Id,
                JobName = execution.JobName,
                StartedAt = execution.StartedAt,
                CompletedAt = execution.CompletedAt,
                Status = execution.Status,
                ComputerName = execution.ComputerName ?? "",
                ProcessId = execution.ProcessId,
                DurationSeconds = execution.DurationSeconds,
                ErrorMessage = execution.ErrorMessage,
                SourceFile = execution.SourceFile
            };

            return Ok(ApiResponse<JobExecutionTrackedDto>.CreateSuccess(dto));
        }
        catch (Exception ex)
        {
            _logger.LogError(ex, "Error resolving job execution {Id}", id);
            return BadRequest(ApiResponse<JobExecutionTrackedDto>.CreateError("Error resolving job: " + ex.Message));
        }
    }

    /// <summary>
    /// Get execution summary stats
    /// </summary>
    [HttpGet("executions/summary")]
    public async Task<ActionResult<ApiResponse<JobExecutionSummaryDto>>> GetExecutionsSummary(
        [FromQuery] DateTime? fromDate,
        [FromQuery] DateTime? toDate)
    {
        try
        {
            var query = _context.JobExecutions.AsNoTracking();

            if (fromDate.HasValue)
                query = query.Where(x => x.StartedAt >= fromDate.Value.ToUniversalTime());
            if (toDate.HasValue)
                query = query.Where(x => x.StartedAt <= toDate.Value.ToUniversalTime());

            var summary = await query
                .GroupBy(x => 1)
                .Select(g => new JobExecutionSummaryDto
                {
                    TotalExecutions = g.Count(),
                    StartedCount = g.Count(x => x.Status == "Started"),
                    CompletedCount = g.Count(x => x.Status == "Completed"),
                    FailedCount = g.Count(x => x.Status == "Failed"),
                    TimedOutCount = g.Count(x => x.Status == "TimedOut"),
                    AverageDurationSeconds = g.Where(x => x.DurationSeconds.HasValue).Average(x => x.DurationSeconds) ?? 0
                })
                .FirstOrDefaultAsync();

            return Ok(ApiResponse<JobExecutionSummaryDto>.CreateSuccess(summary ?? new JobExecutionSummaryDto()));
        }
        catch (Exception ex)
        {
            _logger.LogError(ex, "Error getting execution summary");
            return BadRequest(ApiResponse<JobExecutionSummaryDto>.CreateError("Error getting execution summary: " + ex.Message));
        }
    }
}

/// <summary>
/// Tracked job execution DTO (from JobExecution table)
/// </summary>
public class JobExecutionTrackedDto
{
    public Guid Id { get; set; }
    public string JobName { get; set; } = string.Empty;
    public DateTime StartedAt { get; set; }
    public DateTime? CompletedAt { get; set; }
    public string Status { get; set; } = string.Empty;
    public string ComputerName { get; set; } = string.Empty;
    public int? ProcessId { get; set; }
    public double? DurationSeconds { get; set; }
    public string? ErrorMessage { get; set; }
    public string? SourceFile { get; set; }
    
    public string DurationFormatted => DurationSeconds.HasValue 
        ? TimeSpan.FromSeconds(DurationSeconds.Value).ToString(@"hh\:mm\:ss") 
        : "-";
}

/// <summary>
/// Request to resolve an orphaned job
/// </summary>
public class ResolveJobRequest
{
    public string? Status { get; set; }
    public string? Resolution { get; set; }
}

/// <summary>
/// Job execution summary DTO
/// </summary>
public class JobExecutionSummaryDto
{
    public int TotalExecutions { get; set; }
    public int StartedCount { get; set; }
    public int CompletedCount { get; set; }
    public int FailedCount { get; set; }
    public int TimedOutCount { get; set; }
    public double AverageDurationSeconds { get; set; }
}

/// <summary>
/// Job status summary DTO
/// </summary>
public class JobStatusSummaryDto
{
    public int TotalJobs { get; set; }
    public int StartedCount { get; set; }
    public int CompletedCount { get; set; }
    public int FailedCount { get; set; }
    public Dictionary<string, int> StatusBreakdown { get; set; } = new();
}

/// <summary>
/// Job info DTO
/// </summary>
public class JobInfoDto
{
    public string JobName { get; set; } = string.Empty;
    public string JobStatus { get; set; } = string.Empty;
    public int OccurrenceCount { get; set; }
    public DateTime FirstSeen { get; set; }
    public DateTime LastSeen { get; set; }
    public string ComputerName { get; set; } = string.Empty;
}

/// <summary>
/// Job execution DTO
/// </summary>
public class JobExecutionDto
{
    public Guid Id { get; set; }
    public DateTime Timestamp { get; set; }
    public string JobStatus { get; set; } = string.Empty;
    public string ComputerName { get; set; } = string.Empty;
    public string UserName { get; set; } = string.Empty;
    public string Message { get; set; } = string.Empty;
    public int ProcessId { get; set; }
}
