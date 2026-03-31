using Microsoft.EntityFrameworkCore;
using GenericLogHandler.Data;

namespace GenericLogHandler.WebApi.Services;

/// <summary>
/// Background service that runs periodic database maintenance tasks.
/// Runs ANALYZE on tables daily to keep query planner statistics up-to-date.
/// PostgreSQL autovacuum handles most maintenance, but this ensures statistics 
/// are fresh for high-insert workloads like log aggregation.
/// </summary>
public class DatabaseMaintenanceService : BackgroundService
{
    private readonly IServiceProvider _serviceProvider;
    private readonly ILogger<DatabaseMaintenanceService> _logger;
    private readonly IConfiguration _configuration;

    // Default: Run maintenance at 3 AM daily
    private readonly TimeSpan _maintenanceTime;
    private readonly bool _enabled;

    public DatabaseMaintenanceService(
        IServiceProvider serviceProvider,
        ILogger<DatabaseMaintenanceService> logger,
        IConfiguration configuration)
    {
        _serviceProvider = serviceProvider;
        _logger = logger;
        _configuration = configuration;

        // Read configuration
        _enabled = configuration.GetValue("DatabaseMaintenance:Enabled", true);
        var timeStr = configuration.GetValue("DatabaseMaintenance:RunAtTime", "03:00");
        if (!TimeSpan.TryParse(timeStr, out _maintenanceTime))
        {
            _maintenanceTime = new TimeSpan(3, 0, 0); // Default 3 AM
        }
    }

    protected override async Task ExecuteAsync(CancellationToken stoppingToken)
    {
        if (!_enabled)
        {
            _logger.LogInformation("Database maintenance service is disabled");
            return;
        }

        _logger.LogInformation("Database maintenance service started. Scheduled at {Time} daily", _maintenanceTime);

        while (!stoppingToken.IsCancellationRequested)
        {
            try
            {
                // Calculate delay until next maintenance window
                var now = DateTime.Now;
                var nextRun = now.Date.Add(_maintenanceTime);
                if (nextRun <= now)
                {
                    nextRun = nextRun.AddDays(1);
                }

                var delay = nextRun - now;
                _logger.LogDebug("Next database maintenance scheduled for {NextRun} (in {Delay})", nextRun, delay);

                await Task.Delay(delay, stoppingToken);

                // Run maintenance
                await RunMaintenanceAsync(stoppingToken);
            }
            catch (OperationCanceledException)
            {
                // Service is stopping
                break;
            }
            catch (Exception ex)
            {
                _logger.LogError(ex, "Error in database maintenance service");
                // Wait 1 hour before retrying after an error
                await Task.Delay(TimeSpan.FromHours(1), stoppingToken);
            }
        }

        _logger.LogInformation("Database maintenance service stopped");
    }

    private async Task RunMaintenanceAsync(CancellationToken cancellationToken)
    {
        _logger.LogInformation("Starting scheduled database maintenance");
        var sw = System.Diagnostics.Stopwatch.StartNew();

        using var scope = _serviceProvider.CreateScope();
        var context = scope.ServiceProvider.GetRequiredService<LoggingDbContext>();

        var provider = context.Database.ProviderName ?? string.Empty;
        if (!provider.Contains("Npgsql", StringComparison.OrdinalIgnoreCase))
        {
            _logger.LogWarning("Database maintenance only supported for PostgreSQL, skipping");
            return;
        }

        try
        {
            var connection = context.Database.GetDbConnection();
            await connection.OpenAsync(cancellationToken);

            // 1. Run ANALYZE to update statistics
            _logger.LogInformation("Running ANALYZE on log_entries...");
            await context.Database.ExecuteSqlRawAsync("ANALYZE log_entries", cancellationToken);
            
            _logger.LogInformation("Running ANALYZE on import_status...");
            await context.Database.ExecuteSqlRawAsync("ANALYZE import_status", cancellationToken);

            // 2. Check dead tuple ratio and run VACUUM if needed
            long deadTuples = 0;
            long liveTuples = 0;
            using (var command = connection.CreateCommand())
            {
                command.CommandText = @"
                    SELECT n_live_tup, n_dead_tup 
                    FROM pg_stat_user_tables 
                    WHERE relname = 'log_entries'";
                using var reader = await command.ExecuteReaderAsync(cancellationToken);
                if (await reader.ReadAsync(cancellationToken))
                {
                    liveTuples = reader.IsDBNull(0) ? 0 : reader.GetInt64(0);
                    deadTuples = reader.IsDBNull(1) ? 0 : reader.GetInt64(1);
                }
            }

            // If dead tuples exceed 10% of live tuples, run VACUUM
            var deadRatio = liveTuples > 0 ? (double)deadTuples / liveTuples * 100 : 0;
            if (deadRatio > 10)
            {
                _logger.LogInformation("Dead tuple ratio is {Ratio:F1}%, running VACUUM on log_entries...", deadRatio);
                using var vacuumCommand = connection.CreateCommand();
                vacuumCommand.CommandText = "VACUUM log_entries";
                vacuumCommand.CommandTimeout = 600;
                await vacuumCommand.ExecuteNonQueryAsync(cancellationToken);
            }
            else
            {
                _logger.LogDebug("Dead tuple ratio is {Ratio:F1}%, VACUUM not needed", deadRatio);
            }

            // 3. Check if any indexes need attention (unused indexes logged as warning)
            using (var command = connection.CreateCommand())
            {
                command.CommandText = @"
                    SELECT indexrelname, idx_scan
                    FROM pg_stat_user_indexes
                    WHERE relname = 'log_entries' AND idx_scan = 0";
                using var reader = await command.ExecuteReaderAsync(cancellationToken);
                while (await reader.ReadAsync(cancellationToken))
                {
                    var indexName = reader.GetString(0);
                    _logger.LogWarning("Index {IndexName} has never been used - consider removing", indexName);
                }
            }

            sw.Stop();
            _logger.LogInformation("Database maintenance completed in {Duration}ms", sw.ElapsedMilliseconds);
        }
        catch (Exception ex)
        {
            _logger.LogError(ex, "Error during database maintenance");
            throw;
        }
    }
}
