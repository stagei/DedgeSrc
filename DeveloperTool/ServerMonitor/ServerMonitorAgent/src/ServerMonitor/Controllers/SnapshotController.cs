using Microsoft.AspNetCore.Mvc;
using ServerMonitor.Core.Interfaces;
using ServerMonitor.Core.Services;
using ServerMonitor.Core.Models;

namespace ServerMonitor.Controllers;

/// <summary>
/// REST API for querying live system snapshot data
/// </summary>
[ApiController]
[Route("api/[controller]")]
[Produces("application/json")]
public class SnapshotController : ControllerBase
{
    private readonly GlobalSnapshotService _globalSnapshot;
    private readonly ISnapshotExporter _snapshotExporter;
    private readonly ILogger<SnapshotController> _logger;

    public SnapshotController(
        GlobalSnapshotService globalSnapshot,
        ISnapshotExporter snapshotExporter,
        ILogger<SnapshotController> logger)
    {
        _globalSnapshot = globalSnapshot;
        _snapshotExporter = snapshotExporter;
        _logger = logger;
    }

    /// <summary>
    /// Gets the complete current system snapshot (live data)
    /// </summary>
    /// <returns>Full system snapshot with all monitoring data and alert history</returns>
    [HttpGet]
    [ProducesResponseType(typeof(SystemSnapshot), 200)]
    public IActionResult GetCurrentSnapshot()
    {
        var snapshot = _globalSnapshot.GetCurrentSnapshot();
        _logger.LogDebug("Snapshot API called: {AlertCount} alerts, Uptime: {Uptime:F1} days",
            snapshot.Alerts.Count, snapshot.Uptime?.CurrentUptimeDays ?? 0);
        
        return Ok(snapshot);
    }

    /// <summary>
    /// Gets all alerts with their distribution history
    /// </summary>
    /// <returns>List of all alerts that have occurred since startup</returns>
    [HttpGet("alerts")]
    [ProducesResponseType(typeof(List<Alert>), 200)]
    public IActionResult GetAlerts()
    {
        var snapshot = _globalSnapshot.GetCurrentSnapshot();
        return Ok(snapshot.Alerts);
    }

    /// <summary>
    /// Gets recent alerts (last N alerts)
    /// </summary>
    /// <param name="count">Number of recent alerts to return (default: 10)</param>
    /// <returns>Recent alerts, most recent first</returns>
    [HttpGet("alerts/recent")]
    [ProducesResponseType(typeof(List<Alert>), 200)]
    public IActionResult GetRecentAlerts([FromQuery] int count = 10, [FromQuery] DateTime? since = null)
    {
        var snapshot = _globalSnapshot.GetCurrentSnapshot();
        IEnumerable<Alert> alerts = snapshot.Alerts.OrderByDescending(a => a.Timestamp);

        if (since.HasValue)
        {
            var sinceUtc = since.Value.Kind == DateTimeKind.Unspecified
                ? DateTime.SpecifyKind(since.Value, DateTimeKind.Utc)
                : since.Value.ToUniversalTime();
            alerts = alerts.Where(a => a.Timestamp > sinceUtc);
        }

        return Ok(alerts.Take(count).ToList());
    }

    /// <summary>
    /// Gets system health summary
    /// </summary>
    /// <returns>Health metrics including CPU, Memory, Disk, Uptime, and Alert counts</returns>
    [HttpGet("health")]
    [ProducesResponseType(200)]
    public IActionResult GetHealth()
    {
        var snapshot = _globalSnapshot.GetCurrentSnapshot();
        
        var health = new
        {
            ServerName = snapshot.Metadata.ServerName,
            Timestamp = snapshot.Metadata.Timestamp,
            UptimeDays = snapshot.Uptime?.CurrentUptimeDays ?? 0,
            LastBootTime = snapshot.Uptime?.LastBootTime,
            Cpu = new
            {
                UsagePercent = snapshot.Processor?.OverallUsagePercent,
                Cores = snapshot.Processor?.PerCoreUsage?.Count
            },
            Memory = new
            {
                TotalGB = snapshot.Memory?.TotalGB,
                UsedPercent = snapshot.Memory?.UsedPercent,
                AvailableGB = snapshot.Memory?.AvailableGB
            },
            Disks = snapshot.Disks?.Space?.Select(d => new
            {
                d.Drive,
                d.TotalGB,
                d.UsedPercent,
                d.AvailableGB
            }),
            Alerts = new
            {
                Total = snapshot.Alerts.Count,
                Critical = snapshot.Alerts.Count(a => a.Severity == AlertSeverity.Critical),
                Warning = snapshot.Alerts.Count(a => a.Severity == AlertSeverity.Warning),
                Informational = snapshot.Alerts.Count(a => a.Severity == AlertSeverity.Informational),
                Last24Hours = snapshot.Alerts.Count(a => a.Timestamp > DateTime.UtcNow.AddHours(-24))
            }
        };

        return Ok(health);
    }

    /// <summary>
    /// Gets processor metrics
    /// </summary>
    /// <returns>CPU usage data including overall and per-core metrics</returns>
    [HttpGet("processor")]
    [ProducesResponseType(typeof(ProcessorData), 200)]
    public IActionResult GetProcessor()
    {
        var snapshot = _globalSnapshot.GetCurrentSnapshot();
        return Ok(snapshot.Processor);
    }

    /// <summary>
    /// Gets memory metrics
    /// </summary>
    /// <returns>Physical memory usage data</returns>
    [HttpGet("memory")]
    [ProducesResponseType(typeof(MemoryData), 200)]
    public IActionResult GetMemory()
    {
        var snapshot = _globalSnapshot.GetCurrentSnapshot();
        return Ok(snapshot.Memory);
    }

    /// <summary>
    /// Gets disk metrics
    /// </summary>
    /// <returns>Disk space and I/O metrics for all monitored drives</returns>
    [HttpGet("disks")]
    [ProducesResponseType(typeof(DiskData), 200)]
    public IActionResult GetDisks()
    {
        var snapshot = _globalSnapshot.GetCurrentSnapshot();
        return Ok(snapshot.Disks);
    }

    /// <summary>
    /// Gets network metrics
    /// </summary>
    /// <returns>Network connectivity data for baseline hosts</returns>
    [HttpGet("network")]
    [ProducesResponseType(typeof(List<NetworkHostData>), 200)]
    public IActionResult GetNetwork()
    {
        var snapshot = _globalSnapshot.GetCurrentSnapshot();
        return Ok(snapshot.Network);
    }

    /// <summary>
    /// Gets Windows Update status
    /// </summary>
    /// <returns>Pending updates and installation history</returns>
    [HttpGet("updates")]
    [ProducesResponseType(typeof(WindowsUpdateData), 200)]
    public IActionResult GetWindowsUpdates()
    {
        var snapshot = _globalSnapshot.GetCurrentSnapshot();
        return Ok(snapshot.WindowsUpdates);
    }

    /// <summary>
    /// Clears the in-memory snapshot and deletes any persisted snapshot file.
    /// Resets the agent to a fresh state — it will re-accumulate data from scratch.
    /// </summary>
    /// <returns>Memory usage before and after the clear</returns>
    [HttpPost("clear")]
    [ProducesResponseType(200)]
    public IActionResult ClearSnapshot()
    {
        var memBeforeMb = System.Diagnostics.Process.GetCurrentProcess().WorkingSet64 / (1024.0 * 1024.0);
        
        _logger.LogWarning("🗑️ Snapshot clear requested via API. Memory before: {MemMB:N0} MB", memBeforeMb);
        
        _globalSnapshot.ClearSnapshot();
        
        var memAfterMb = System.Diagnostics.Process.GetCurrentProcess().WorkingSet64 / (1024.0 * 1024.0);
        
        return Ok(new
        {
            success = true,
            message = "Snapshot cleared and persisted file deleted. Agent will re-accumulate data.",
            memoryBeforeMB = Math.Round(memBeforeMb, 0),
            memoryAfterMB = Math.Round(memAfterMb, 0),
            memoryFreedMB = Math.Round(memBeforeMb - memAfterMb, 0),
            timestamp = DateTime.UtcNow
        });
    }

    /// <summary>
    /// Gets all external events
    /// </summary>
    /// <returns>List of all external events received since startup</returns>
    [HttpGet("external-events")]
    [ProducesResponseType(typeof(List<ExternalEvent>), 200)]
    public IActionResult GetExternalEvents()
    {
        var snapshot = _globalSnapshot.GetCurrentSnapshot();
        return Ok(snapshot.ExternalEvents);
    }

    /// <summary>
    /// Gets recent external events (last N events)
    /// </summary>
    /// <param name="count">Number of recent events to return (default: 10)</param>
    /// <returns>Recent external events, most recent first</returns>
    [HttpGet("external-events/recent")]
    [ProducesResponseType(typeof(List<ExternalEvent>), 200)]
    public IActionResult GetRecentExternalEvents([FromQuery] int count = 10)
    {
        var snapshot = _globalSnapshot.GetCurrentSnapshot();
        var recentEvents = snapshot.ExternalEvents
            .OrderByDescending(e => e.RegisteredTimestamp)
            .Take(count)
            .ToList();
        
        return Ok(recentEvents);
    }
}

