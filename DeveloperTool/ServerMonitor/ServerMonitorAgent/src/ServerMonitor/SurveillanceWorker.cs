using Microsoft.Extensions.Hosting;
using Microsoft.Extensions.Logging;
using Microsoft.Extensions.Options;
using ServerMonitor.Core.Configuration;
using ServerMonitor.Core.Services;

namespace ServerMonitor;

/// <summary>
/// Background worker service that runs the surveillance orchestrator
/// </summary>
public class SurveillanceWorker : BackgroundService
{
    private readonly ILogger<SurveillanceWorker> _logger;
    private readonly SurveillanceOrchestrator _orchestrator;
    private readonly IOptionsMonitor<SurveillanceConfiguration> _config;
    private readonly IHostApplicationLifetime _appLifetime;
    private readonly GlobalSnapshotService _snapshotService;
    private readonly DateTime _startTime;

    public SurveillanceWorker(
        ILogger<SurveillanceWorker> logger,
        SurveillanceOrchestrator orchestrator,
        IOptionsMonitor<SurveillanceConfiguration> config,
        IHostApplicationLifetime appLifetime,
        GlobalSnapshotService snapshotService)
    {
        _logger = logger;
        _orchestrator = orchestrator;
        _config = config;
        _appLifetime = appLifetime;
        _snapshotService = snapshotService;
        _startTime = DateTime.Now;
    }

    protected override async Task ExecuteAsync(CancellationToken stoppingToken)
    {
        _logger.LogInformation("Surveillance Worker starting at {StartTime}", _startTime);

        try
        {
            // Try to restore snapshot from previous run
            if (_snapshotService.TryLoadSnapshotFromDisk())
            {
                _logger.LogInformation("✅ Previous snapshot restored - historical data preserved");
            }
            
            // Set up shutdown callback for self-monitoring (memory threshold)
            _orchestrator.SetShutdownCallback(() => InitiateShutdown("Memory threshold exceeded"));
            
            await _orchestrator.StartAsync(stoppingToken);

            // Check for auto-shutdown configuration
            var runtime = _config.CurrentValue.Runtime;
            LogShutdownConfiguration(runtime);

            // Start auto-shutdown monitor if configured
            var shutdownTask = MonitorAutoShutdownAsync(stoppingToken);

            // Keep the worker running until cancelled or shutdown
            await Task.WhenAny(
                Task.Delay(Timeout.Infinite, stoppingToken),
                shutdownTask
            );
        }
        catch (OperationCanceledException)
        {
            _logger.LogInformation("Surveillance Worker stopping");
        }
        catch (Exception ex)
        {
            _logger.LogError(ex, "Unexpected error in Surveillance Worker");
            throw;
        }
    }

    private void LogShutdownConfiguration(RuntimeSettings runtime)
    {
        if (runtime.TestTimeoutSeconds.HasValue && runtime.TestTimeoutSeconds.Value > 0)
        {
            var shutdownTime = _startTime.AddSeconds(runtime.TestTimeoutSeconds.Value);
            _logger.LogWarning("TEST TIMEOUT configured: {Seconds} seconds (shutdown at {ShutdownTime})", 
                runtime.TestTimeoutSeconds.Value, shutdownTime);
        }

        if (!string.IsNullOrWhiteSpace(runtime.AutoShutdownTime))
        {
            _logger.LogInformation("Auto-shutdown configured for time: {ShutdownTime}", runtime.AutoShutdownTime);
        }

        if (runtime.MaxRuntimeHours.HasValue && runtime.MaxRuntimeHours.Value > 0)
        {
            var shutdownTime = _startTime.AddHours(runtime.MaxRuntimeHours.Value);
            _logger.LogInformation("Auto-shutdown configured for max runtime: {Hours} hours (shutdown at {ShutdownTime})", 
                runtime.MaxRuntimeHours.Value, shutdownTime);
        }

        if (!runtime.TestTimeoutSeconds.HasValue &&
            string.IsNullOrWhiteSpace(runtime.AutoShutdownTime) && 
            (!runtime.MaxRuntimeHours.HasValue || runtime.MaxRuntimeHours.Value <= 0))
        {
            _logger.LogInformation("No auto-shutdown configured - running indefinitely");
        }
    }

    private async Task MonitorAutoShutdownAsync(CancellationToken stoppingToken)
    {
        var runtime = _config.CurrentValue.Runtime;

        // Check for test timeout first (highest priority)
        if (runtime.TestTimeoutSeconds.HasValue && runtime.TestTimeoutSeconds.Value > 0)
        {
            _logger.LogWarning("Test timeout active - will exit in {Seconds} seconds", runtime.TestTimeoutSeconds.Value);
            await Task.Delay(TimeSpan.FromSeconds(runtime.TestTimeoutSeconds.Value), stoppingToken);
            _logger.LogWarning("Test timeout reached - initiating shutdown");
            InitiateShutdown("Test timeout reached");
            return;
        }

        // If no shutdown configured, return immediately
        if (string.IsNullOrWhiteSpace(runtime.AutoShutdownTime) && 
            (!runtime.MaxRuntimeHours.HasValue || runtime.MaxRuntimeHours.Value <= 0))
        {
            await Task.Delay(Timeout.Infinite, stoppingToken);
            return;
        }

        while (!stoppingToken.IsCancellationRequested)
        {
            try
            {
                // Reload config in case it changed
                runtime = _config.CurrentValue.Runtime;

                // Check if test timeout was added dynamically
                if (runtime.TestTimeoutSeconds.HasValue && runtime.TestTimeoutSeconds.Value > 0)
                {
                    var elapsed = (DateTime.Now - _startTime).TotalSeconds;
                    var remaining = runtime.TestTimeoutSeconds.Value - elapsed;
                    if (remaining <= 0)
                    {
                        _logger.LogWarning("Test timeout reached - initiating shutdown");
                        InitiateShutdown("Test timeout reached");
                        return;
                    }
                }

                // Check for time-based shutdown
                if (!string.IsNullOrWhiteSpace(runtime.AutoShutdownTime))
                {
                    if (TimeSpan.TryParse(runtime.AutoShutdownTime, out var targetTime))
                    {
                        var now = DateTime.Now;
                        var todayTarget = now.Date.Add(targetTime);

                        // If target time is in the past today, assume it's for tomorrow
                        if (todayTarget < now)
                        {
                            todayTarget = todayTarget.AddDays(1);
                        }

                        // Check if we're within 1 minute of the target time
                        if (Math.Abs((now - todayTarget).TotalMinutes) <= 1)
                        {
                            _logger.LogWarning("Auto-shutdown time reached: {ShutdownTime}", runtime.AutoShutdownTime);
                            InitiateShutdown("Scheduled shutdown time reached");
                            return;
                        }
                    }
                    else
                    {
                        _logger.LogWarning("Invalid AutoShutdownTime format: {Time}. Expected HH:mm format", 
                            runtime.AutoShutdownTime);
                    }
                }

                // Check for duration-based shutdown
                if (runtime.MaxRuntimeHours.HasValue && runtime.MaxRuntimeHours.Value > 0)
                {
                    var runningTime = DateTime.Now - _startTime;
                    var maxDuration = TimeSpan.FromHours(runtime.MaxRuntimeHours.Value);

                    if (runningTime >= maxDuration)
                    {
                        _logger.LogWarning("Maximum runtime reached: {Hours} hours", runtime.MaxRuntimeHours.Value);
                        InitiateShutdown($"Maximum runtime of {runtime.MaxRuntimeHours.Value} hours reached");
                        return;
                    }

                    // Log warning at 90% of max runtime
                    var ninetyPercent = maxDuration * 0.9;
                    if (runningTime >= ninetyPercent && runningTime < maxDuration)
                    {
                        var remaining = maxDuration - runningTime;
                        if (remaining.TotalMinutes > 1) // Only log if more than 1 minute remains
                        {
                            _logger.LogWarning("Approaching maximum runtime. Shutdown in {Minutes:F0} minutes", 
                                remaining.TotalMinutes);
                        }
                    }
                }

                // Check every minute
                await Task.Delay(TimeSpan.FromMinutes(1), stoppingToken);
            }
            catch (OperationCanceledException)
            {
                // Normal cancellation
                break;
            }
            catch (Exception ex)
            {
                _logger.LogError(ex, "Error in auto-shutdown monitor");
                await Task.Delay(TimeSpan.FromMinutes(1), stoppingToken);
            }
        }
    }

    private void InitiateShutdown(string reason)
    {
        _logger.LogWarning("Initiating graceful shutdown: {Reason}", reason);
        _appLifetime.StopApplication();
    }

    public override async Task StopAsync(CancellationToken cancellationToken)
    {
        var runtime = DateTime.Now - _startTime;
        _logger.LogInformation("Surveillance Worker stopping after {Hours:F2} hours of runtime", runtime.TotalHours);
        
        if (_orchestrator.IsMemoryShutdown)
        {
            // Memory suicide: delete any persisted snapshot so the next startup begins fresh
            _logger.LogWarning("⚠️ Memory shutdown - deleting persisted snapshot to prevent reloading bloated data on restart");
            _snapshotService.DeletePersistedSnapshot();
        }
        else
        {
            // Normal shutdown: persist snapshot for next startup
            try
            {
                _snapshotService.SaveSnapshotToDisk();
                _logger.LogInformation("✅ Snapshot persisted for next startup");
            }
            catch (Exception ex)
            {
                _logger.LogError(ex, "Failed to persist snapshot on shutdown");
            }
        }
        
        await _orchestrator.StopAsync(cancellationToken);
        
        await base.StopAsync(cancellationToken);
    }
}
