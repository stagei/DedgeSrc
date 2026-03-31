using Microsoft.EntityFrameworkCore;
using Microsoft.Extensions.Logging;
using Microsoft.Extensions.Options;
using GenericLogHandler.Core.Models;
using GenericLogHandler.Core.Models.Configuration;
using GenericLogHandler.Data;

namespace GenericLogHandler.ImportService.Services;

/// <summary>
/// Service for correlating job start and completion events.
/// Creates JobExecution records from log entries with job status information.
/// </summary>
public class JobCorrelationService
{
    private readonly LoggingDbContext _context;
    private readonly ILogger<JobCorrelationService> _logger;
    private readonly JobTrackingConfiguration _config;

    public JobCorrelationService(
        LoggingDbContext context,
        ILogger<JobCorrelationService> logger,
        IOptions<JobTrackingConfiguration> config)
    {
        _context = context;
        _logger = logger;
        _config = config.Value;
    }

    /// <summary>
    /// Process a batch of log entries and correlate job executions
    /// </summary>
    public async Task CorrelateJobsAsync(IEnumerable<LogEntry> entries, CancellationToken cancellationToken = default)
    {
        if (!_config.EnableJobCorrelation)
            return;

        var jobEntries = entries
            .Where(e => !string.IsNullOrEmpty(e.JobStatus) && !string.IsNullOrEmpty(e.JobName))
            .OrderBy(e => e.Timestamp)
            .ToList();

        if (jobEntries.Count == 0)
            return;

        _logger.LogDebug("Processing {Count} job status entries for correlation", jobEntries.Count);

        var startedCount = 0;
        var completedCount = 0;

        foreach (var entry in jobEntries)
        {
            try
            {
                var normalizedStatus = entry.JobStatus?.ToLowerInvariant();
                
                if (normalizedStatus == "started")
                {
                    await CreateJobExecutionAsync(entry, cancellationToken);
                    startedCount++;
                }
                else if (normalizedStatus == "completed" || normalizedStatus == "failed")
                {
                    await CompleteJobExecutionAsync(entry, cancellationToken);
                    completedCount++;
                }
            }
            catch (Exception ex)
            {
                _logger.LogWarning(ex, "Error correlating job: {JobName} with status {Status}", 
                    entry.JobName, entry.JobStatus);
            }
        }

        if (startedCount > 0 || completedCount > 0)
        {
            await _context.SaveChangesAsync(cancellationToken);
            _logger.LogInformation("Job correlation: {Started} started, {Completed} completed/failed", 
                startedCount, completedCount);
        }
    }

    /// <summary>
    /// Create a new job execution record for a "Started" entry
    /// </summary>
    private async Task CreateJobExecutionAsync(LogEntry entry, CancellationToken cancellationToken)
    {
        // Check if we already have an open execution for this job on this computer/process
        var existingOpen = await _context.JobExecutions
            .Where(j => j.JobName == entry.JobName
                && j.Status == "Started"
                && j.ComputerName == entry.ComputerName
                && (entry.ProcessId == 0 || j.ProcessId == entry.ProcessId))
            .OrderByDescending(j => j.StartedAt)
            .FirstOrDefaultAsync(cancellationToken);

        if (existingOpen != null)
        {
            _logger.LogDebug("Job {JobName} already has an open execution, skipping duplicate start", entry.JobName);
            return;
        }

        var execution = new JobExecution
        {
            JobName = entry.JobName!,
            StartedAt = entry.Timestamp,
            Status = "Started",
            ComputerName = entry.ComputerName,
            ProcessId = entry.ProcessId > 0 ? entry.ProcessId : null,
            StartLogEntryId = entry.Id,
            SourceFile = entry.SourceFile,
            CreatedAt = DateTime.UtcNow,
            UpdatedAt = DateTime.UtcNow
        };

        _context.JobExecutions.Add(execution);
        _logger.LogDebug("Created job execution: {JobName} on {Computer}", entry.JobName, entry.ComputerName);
    }

    /// <summary>
    /// Complete a job execution for a "Completed" or "Failed" entry
    /// </summary>
    private async Task CompleteJobExecutionAsync(LogEntry entry, CancellationToken cancellationToken)
    {
        // Find the most recent open execution for this job
        var execution = await _context.JobExecutions
            .Where(j => j.JobName == entry.JobName
                && j.Status == "Started"
                && j.ComputerName == entry.ComputerName
                && (entry.ProcessId == 0 || j.ProcessId == null || j.ProcessId == entry.ProcessId))
            .OrderByDescending(j => j.StartedAt)
            .FirstOrDefaultAsync(cancellationToken);

        if (execution == null)
        {
            // No matching start found - create an execution without a start entry
            _logger.LogDebug("No matching start found for job {JobName}, creating orphaned completion", entry.JobName);
            
            execution = new JobExecution
            {
                JobName = entry.JobName!,
                StartedAt = entry.Timestamp.AddMinutes(-1), // Assume it started just before completion
                CompletedAt = entry.Timestamp,
                Status = entry.JobStatus!,
                ComputerName = entry.ComputerName,
                ProcessId = entry.ProcessId > 0 ? entry.ProcessId : null,
                EndLogEntryId = entry.Id,
                SourceFile = entry.SourceFile,
                DurationSeconds = 0,
                CreatedAt = DateTime.UtcNow,
                UpdatedAt = DateTime.UtcNow
            };

            if (entry.JobStatus?.ToLowerInvariant() == "failed")
            {
                execution.ErrorMessage = entry.Message?.Length > 4000 
                    ? entry.Message.Substring(0, 4000) 
                    : entry.Message;
            }

            _context.JobExecutions.Add(execution);
            return;
        }

        // Update the existing execution
        execution.CompletedAt = entry.Timestamp;
        execution.Status = entry.JobStatus!;
        execution.EndLogEntryId = entry.Id;
        execution.DurationSeconds = (entry.Timestamp - execution.StartedAt).TotalSeconds;
        execution.UpdatedAt = DateTime.UtcNow;

        if (entry.JobStatus?.ToLowerInvariant() == "failed")
        {
            execution.ErrorMessage = entry.Message?.Length > 4000 
                ? entry.Message.Substring(0, 4000) 
                : entry.Message;
        }

        _logger.LogDebug("Completed job execution: {JobName} with status {Status} in {Duration:F1}s", 
            entry.JobName, entry.JobStatus, execution.DurationSeconds);
    }

    /// <summary>
    /// Mark orphaned jobs (started but not completed within timeout) as timed out
    /// </summary>
    public async Task<int> MarkOrphanedJobsAsync(CancellationToken cancellationToken = default)
    {
        if (!_config.AutoMarkOrphanedJobs)
            return 0;

        var cutoff = DateTime.UtcNow.AddHours(-_config.OrphanTimeoutHours);

        var orphanedJobs = await _context.JobExecutions
            .Where(j => j.Status == "Started" && j.StartedAt < cutoff)
            .ToListAsync(cancellationToken);

        if (orphanedJobs.Count == 0)
            return 0;

        foreach (var job in orphanedJobs)
        {
            job.Status = "TimedOut";
            job.CompletedAt = DateTime.UtcNow;
            job.UpdatedAt = DateTime.UtcNow;
            job.ErrorMessage = $"Job timed out after {_config.OrphanTimeoutHours} hours without completion";
        }

        await _context.SaveChangesAsync(cancellationToken);
        _logger.LogInformation("Marked {Count} orphaned jobs as timed out", orphanedJobs.Count);

        return orphanedJobs.Count;
    }

    /// <summary>
    /// Get job execution statistics
    /// </summary>
    public async Task<JobExecutionStats> GetStatsAsync(DateTime? fromDate = null, DateTime? toDate = null, CancellationToken cancellationToken = default)
    {
        var query = _context.JobExecutions.AsQueryable();

        if (fromDate.HasValue)
            query = query.Where(j => j.StartedAt >= fromDate.Value);
        if (toDate.HasValue)
            query = query.Where(j => j.StartedAt <= toDate.Value);

        var stats = await query
            .GroupBy(j => 1)
            .Select(g => new JobExecutionStats
            {
                TotalExecutions = g.Count(),
                StartedCount = g.Count(j => j.Status == "Started"),
                CompletedCount = g.Count(j => j.Status == "Completed"),
                FailedCount = g.Count(j => j.Status == "Failed"),
                TimedOutCount = g.Count(j => j.Status == "TimedOut"),
                AverageDurationSeconds = g.Where(j => j.DurationSeconds.HasValue).Average(j => j.DurationSeconds) ?? 0
            })
            .FirstOrDefaultAsync(cancellationToken);

        return stats ?? new JobExecutionStats();
    }
}

/// <summary>
/// Statistics for job executions
/// </summary>
public class JobExecutionStats
{
    public int TotalExecutions { get; set; }
    public int StartedCount { get; set; }
    public int CompletedCount { get; set; }
    public int FailedCount { get; set; }
    public int TimedOutCount { get; set; }
    public double AverageDurationSeconds { get; set; }
}
