using Microsoft.EntityFrameworkCore;
using GenericLogHandler.Data;

namespace GenericLogHandler.WebApi.Services;

/// <summary>
/// Background service that periodically deletes old log entries based on retention policy.
/// Protected entries (protected = true) are never deleted by this service.
/// Protected entries can only be deleted manually via SQL.
/// </summary>
public class LogSanitationService : BackgroundService
{
    private readonly IServiceProvider _serviceProvider;
    private readonly ILogger<LogSanitationService> _logger;
    private readonly IConfiguration _configuration;

    private readonly bool _enabled;
    private readonly TimeSpan _runAtTime;
    private readonly int _defaultRetentionDays;
    private readonly int _batchSize;

    public LogSanitationService(
        IServiceProvider serviceProvider,
        ILogger<LogSanitationService> logger,
        IConfiguration configuration)
    {
        _serviceProvider = serviceProvider;
        _logger = logger;
        _configuration = configuration;

        // Read configuration
        _enabled = configuration.GetValue("Sanitation:Enabled", true);
        var timeStr = configuration.GetValue("Sanitation:RunAtTime", "02:00");
        if (!TimeSpan.TryParse(timeStr, out _runAtTime))
        {
            _runAtTime = new TimeSpan(2, 0, 0); // Default 2 AM
        }
        _defaultRetentionDays = configuration.GetValue("Sanitation:RetentionDays", 90);
        _batchSize = configuration.GetValue("Sanitation:BatchSize", 10000);
    }

    protected override async Task ExecuteAsync(CancellationToken stoppingToken)
    {
        if (!_enabled)
        {
            _logger.LogInformation("Log sanitation service is disabled");
            return;
        }

        _logger.LogInformation(
            "Log sanitation service started. Scheduled at {Time} daily, retention: {Days} days",
            _runAtTime, _defaultRetentionDays);

        while (!stoppingToken.IsCancellationRequested)
        {
            try
            {
                // Calculate delay until next run
                var now = DateTime.Now;
                var nextRun = now.Date.Add(_runAtTime);
                if (nextRun <= now)
                {
                    nextRun = nextRun.AddDays(1);
                }

                var delay = nextRun - now;
                _logger.LogDebug("Next sanitation scheduled for {NextRun} (in {Delay})", nextRun, delay);

                await Task.Delay(delay, stoppingToken);

                // Run sanitation
                await RunSanitationAsync(stoppingToken);
            }
            catch (OperationCanceledException)
            {
                break;
            }
            catch (Exception ex)
            {
                _logger.LogError(ex, "Error in log sanitation service");
                // Wait 1 hour before retrying after an error
                await Task.Delay(TimeSpan.FromHours(1), stoppingToken);
            }
        }

        _logger.LogInformation("Log sanitation service stopped");
    }

    /// <summary>
    /// Run sanitation - delete old unprotected log entries
    /// </summary>
    public async Task<SanitationResult> RunSanitationAsync(CancellationToken cancellationToken = default)
    {
        var result = new SanitationResult { StartTime = DateTime.UtcNow };
        var sw = System.Diagnostics.Stopwatch.StartNew();

        _logger.LogInformation("Starting log sanitation (retention: {Days} days)", _defaultRetentionDays);

        using var scope = _serviceProvider.CreateScope();
        var context = scope.ServiceProvider.GetRequiredService<LoggingDbContext>();

        var provider = context.Database.ProviderName ?? string.Empty;
        if (!provider.Contains("Npgsql", StringComparison.OrdinalIgnoreCase))
        {
            _logger.LogWarning("Log sanitation only supported for PostgreSQL, skipping");
            result.Success = false;
            result.Message = "Only PostgreSQL is supported";
            return result;
        }

        try
        {
            var cutoffDate = DateTime.UtcNow.AddDays(-_defaultRetentionDays);
            long totalDeleted = 0;
            int batchCount = 0;

            // Delete in batches to avoid long locks and transaction log bloat
            while (!cancellationToken.IsCancellationRequested)
            {
                // Delete batch of old, unprotected entries
                // Using raw SQL for efficiency with large datasets
                var deleted = await context.Database.ExecuteSqlRawAsync(
                    @"DELETE FROM log_entries 
                      WHERE id IN (
                          SELECT id FROM log_entries 
                          WHERE timestamp < {0} 
                          AND protected = false 
                          LIMIT {1}
                      )",
                    new object[] { cutoffDate, _batchSize },
                    cancellationToken);

                if (deleted == 0)
                    break;

                totalDeleted += deleted;
                batchCount++;
                
                _logger.LogDebug("Sanitation batch {Batch}: deleted {Count} entries", batchCount, deleted);

                // Small delay between batches to reduce database load
                await Task.Delay(100, cancellationToken);
            }

            sw.Stop();
            result.Success = true;
            result.DeletedCount = totalDeleted;
            result.BatchCount = batchCount;
            result.DurationMs = sw.ElapsedMilliseconds;
            result.CutoffDate = cutoffDate;
            result.Message = $"Deleted {totalDeleted} entries older than {_defaultRetentionDays} days";

            _logger.LogInformation(
                "Log sanitation completed: {Deleted} entries deleted in {Duration}ms ({Batches} batches)",
                totalDeleted, sw.ElapsedMilliseconds, batchCount);

            // Run ANALYZE after large deletes to update statistics
            if (totalDeleted > 1000)
            {
                _logger.LogInformation("Running ANALYZE after sanitation...");
                await context.Database.ExecuteSqlRawAsync("ANALYZE log_entries", cancellationToken);
            }

            return result;
        }
        catch (Exception ex)
        {
            sw.Stop();
            result.Success = false;
            result.DurationMs = sw.ElapsedMilliseconds;
            result.Message = ex.Message;
            _logger.LogError(ex, "Error during log sanitation");
            throw;
        }
    }

    /// <summary>
    /// Get count of entries that would be deleted (preview)
    /// </summary>
    public async Task<SanitationPreview> PreviewSanitationAsync(int? retentionDays = null)
    {
        var days = retentionDays ?? _defaultRetentionDays;
        var cutoffDate = DateTime.UtcNow.AddDays(-days);

        using var scope = _serviceProvider.CreateScope();
        var context = scope.ServiceProvider.GetRequiredService<LoggingDbContext>();

        var toDelete = await context.LogEntries
            .Where(e => e.Timestamp < cutoffDate && !e.Protected)
            .CountAsync();

        var protectedCount = await context.LogEntries
            .Where(e => e.Timestamp < cutoffDate && e.Protected)
            .CountAsync();

        var totalOld = await context.LogEntries
            .Where(e => e.Timestamp < cutoffDate)
            .CountAsync();

        return new SanitationPreview
        {
            CutoffDate = cutoffDate,
            RetentionDays = days,
            EntriesToDelete = toDelete,
            ProtectedEntries = protectedCount,
            TotalOldEntries = totalOld
        };
    }
}

/// <summary>
/// Result of a sanitation run
/// </summary>
public class SanitationResult
{
    public bool Success { get; set; }
    public long DeletedCount { get; set; }
    public int BatchCount { get; set; }
    public long DurationMs { get; set; }
    public DateTime StartTime { get; set; }
    public DateTime CutoffDate { get; set; }
    public string Message { get; set; } = string.Empty;
}

/// <summary>
/// Preview of what sanitation would delete
/// </summary>
public class SanitationPreview
{
    public DateTime CutoffDate { get; set; }
    public int RetentionDays { get; set; }
    public int EntriesToDelete { get; set; }
    public int ProtectedEntries { get; set; }
    public int TotalOldEntries { get; set; }
}
