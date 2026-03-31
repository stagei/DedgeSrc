using Microsoft.Extensions.Hosting;
using Microsoft.Extensions.Logging;
using Microsoft.Extensions.Options;
using ServerMonitor.Core.Configuration;
using ServerMonitor.Core.Services;

namespace ServerMonitor.Services;

/// <summary>
/// Background service that flushes alert accumulator data based on configured schedules.
/// Supports two flush triggers:
/// - FlushAccumulatorAfterHours: Flush X hours after agent startup
/// - FlushAccumulatorAtTime: Flush at a specific time each day (HH:mm format)
/// Both can be configured simultaneously and will trigger independently.
/// 
/// When flushing, this service clears:
/// - Alert accumulator (occurrence counts, cooldowns, timestamps)
/// - Snapshot alerts
/// - Persisted snapshot file (to prevent stale data on restart)
/// </summary>
public class AccumulatorFlushService : BackgroundService
{
    private readonly ILogger<AccumulatorFlushService> _logger;
    private readonly IOptionsMonitor<SurveillanceConfiguration> _config;
    private readonly IAlertAccumulator _alertAccumulator;
    private readonly GlobalSnapshotService _snapshotService;
    private readonly DateTime _startupTime;
    private bool _hourBasedFlushDone = false;
    private DateTime? _lastDailyFlush = null;

    public AccumulatorFlushService(
        ILogger<AccumulatorFlushService> logger,
        IOptionsMonitor<SurveillanceConfiguration> config,
        IAlertAccumulator alertAccumulator,
        GlobalSnapshotService snapshotService)
    {
        _logger = logger;
        _config = config;
        _alertAccumulator = alertAccumulator;
        _snapshotService = snapshotService;
        _startupTime = DateTime.Now;
    }

    protected override async Task ExecuteAsync(CancellationToken stoppingToken)
    {
        var runtime = _config.CurrentValue.Runtime;
        var afterHours = runtime?.FlushAccumulatorAfterHours;
        var atTime = runtime?.FlushAccumulatorAtTime;

        if (afterHours == null && string.IsNullOrEmpty(atTime))
        {
            _logger.LogInformation("AccumulatorFlushService: No flush schedule configured - service idle");
            return;
        }

        _logger.LogInformation("AccumulatorFlushService started - FlushAfterHours: {AfterHours}, FlushAtTime: {AtTime}",
            afterHours?.ToString() ?? "null", atTime ?? "null");

        // Check every minute for flush conditions
        while (!stoppingToken.IsCancellationRequested)
        {
            try
            {
                await Task.Delay(TimeSpan.FromMinutes(1), stoppingToken);
                
                // Re-read config in case it changed
                runtime = _config.CurrentValue.Runtime;
                afterHours = runtime?.FlushAccumulatorAfterHours;
                atTime = runtime?.FlushAccumulatorAtTime;

                var now = DateTime.Now;
                var flushed = false;

                // Check hour-based flush (only triggers once per agent run)
                if (afterHours.HasValue && !_hourBasedFlushDone)
                {
                    var flushTime = _startupTime.AddHours(afterHours.Value);
                    if (now >= flushTime)
                    {
                        _logger.LogInformation("⏰ Triggering hour-based data flush ({Hours} hours after startup at {StartupTime})",
                            afterHours.Value, _startupTime.ToString("HH:mm:ss"));
                        FlushAllData();
                        _hourBasedFlushDone = true;
                        flushed = true;
                    }
                }

                // Check time-based flush (triggers daily at specified time)
                if (!string.IsNullOrEmpty(atTime) && !flushed)
                {
                    if (TryParseTime(atTime, out var targetTime))
                    {
                        var todayFlushTime = now.Date.Add(targetTime);
                        
                        // Check if we're within 1 minute of the target time
                        // and haven't already flushed today
                        if (now >= todayFlushTime && now < todayFlushTime.AddMinutes(2))
                        {
                            if (_lastDailyFlush == null || _lastDailyFlush.Value.Date < now.Date)
                            {
                                _logger.LogInformation("⏰ Triggering daily data flush at configured time {Time}",
                                    atTime);
                                FlushAllData();
                                _lastDailyFlush = now;
                            }
                        }
                    }
                    else
                    {
                        _logger.LogWarning("Invalid FlushAccumulatorAtTime format: {Time} (expected HH:mm)", atTime);
                    }
                }
            }
            catch (OperationCanceledException)
            {
                break;
            }
            catch (Exception ex)
            {
                _logger.LogError(ex, "Error in AccumulatorFlushService");
            }
        }

        _logger.LogInformation("AccumulatorFlushService stopped");
    }

    /// <summary>
    /// Flushes all accumulated data: accumulator, snapshot alerts, and persisted snapshot file.
    /// </summary>
    private void FlushAllData()
    {
        try
        {
            // 1. Clear the alert accumulator (occurrence tracking, cooldowns, etc.)
            _alertAccumulator.ClearAll();
            
            // 2. Clear alerts from the current snapshot
            var alertCount = _snapshotService.ClearAlerts();
            _logger.LogInformation("🔄 Snapshot alerts cleared: {Count} alerts removed", alertCount);
            
            // 3. Delete persisted snapshot file to prevent stale data on restart
            _snapshotService.DeletePersistedSnapshot();
            
            _logger.LogInformation("✅ Data flush complete - accumulator, alerts, and persisted snapshot cleared");
        }
        catch (Exception ex)
        {
            _logger.LogError(ex, "Error during data flush");
        }
    }

    private static bool TryParseTime(string timeString, out TimeSpan result)
    {
        result = TimeSpan.Zero;
        
        if (string.IsNullOrWhiteSpace(timeString))
            return false;

        // Try parsing HH:mm format
        var parts = timeString.Split(':');
        if (parts.Length != 2)
            return false;

        if (int.TryParse(parts[0], out var hours) && 
            int.TryParse(parts[1], out var minutes) &&
            hours >= 0 && hours <= 23 &&
            minutes >= 0 && minutes <= 59)
        {
            result = new TimeSpan(hours, minutes, 0);
            return true;
        }

        return false;
    }
}
