using Microsoft.AspNetCore.Mvc;
using Microsoft.Extensions.Options;
using ServerMonitor.Core.Configuration;
using ServerMonitor.Core.Models;
using ServerMonitor.Core.Services;

namespace ServerMonitor.Controllers;

/// <summary>
/// REST API for IIS details (used by dashboard pop-out windows)
/// </summary>
[ApiController]
[Route("api/iis")]
[Produces("application/json")]
public class IisDetailController : ControllerBase
{
    private readonly GlobalSnapshotService _globalSnapshot;
    private readonly IOptionsMonitor<SurveillanceConfiguration> _config;
    private readonly ILogger<IisDetailController> _logger;

    public IisDetailController(
        GlobalSnapshotService globalSnapshot,
        IOptionsMonitor<SurveillanceConfiguration> config,
        ILogger<IisDetailController> logger)
    {
        _globalSnapshot = globalSnapshot;
        _config = config;
        _logger = logger;
    }

    /// <summary>
    /// Get IIS dashboard configuration (e.g., whether pop-out is enabled)
    /// </summary>
    [HttpGet("config")]
    [ProducesResponseType(typeof(IisDashboardConfig), 200)]
    public IActionResult GetDashboardConfig()
    {
        var settings = _config.CurrentValue.IisMonitoring;
        return Ok(new IisDashboardConfig
        {
            EnablePopout = settings.EnableDashboardPopout
        });
    }

    /// <summary>
    /// Get full IIS state: sites, app pools, worker processes, and filtered alerts
    /// </summary>
    [HttpGet("state")]
    [ProducesResponseType(typeof(IisStateResponse), 200)]
    public IActionResult GetIisState([FromQuery] int hoursBack = 24)
    {
        var snapshot = _globalSnapshot.GetCurrentSnapshot();
        var iisData = snapshot.Iis;

        if (iisData == null || !iisData.IsActive)
        {
            return Ok(new IisStateResponse
            {
                IsActive = false,
                InactiveReason = iisData?.InactiveReason ?? "IIS monitoring not available"
            });
        }

        var cutoff = DateTime.UtcNow.AddHours(-hoursBack);
        var iisAlerts = (snapshot.Alerts ?? new List<Alert>())
            .Where(a => a.Timestamp >= cutoff && a.Category == "IIS")
            .OrderByDescending(a => a.Timestamp)
            .Take(100)
            .ToList();

        return Ok(new IisStateResponse
        {
            IsActive = true,
            IisVersion = iisData.IisVersion,
            CollectedAt = iisData.CollectedAt,
            Sites = iisData.Sites,
            AppPools = iisData.AppPools,
            TotalSites = iisData.TotalSites,
            RunningSites = iisData.RunningSites,
            StoppedSites = iisData.StoppedSites,
            TotalAppPools = iisData.TotalAppPools,
            RunningAppPools = iisData.RunningAppPools,
            StoppedAppPools = iisData.StoppedAppPools,
            TotalWorkerProcesses = iisData.TotalWorkerProcesses,
            RecentAlerts = iisAlerts,
            Error = iisData.Error
        });
    }
}

/// <summary>
/// Response model for IIS state
/// </summary>
public record IisStateResponse
{
    public bool IsActive { get; init; }
    public string? InactiveReason { get; init; }
    public string? IisVersion { get; init; }
    public DateTime CollectedAt { get; init; }
    public List<IisSiteInfo> Sites { get; init; } = new();
    public List<IisAppPoolInfo> AppPools { get; init; } = new();
    public int TotalSites { get; init; }
    public int RunningSites { get; init; }
    public int StoppedSites { get; init; }
    public int TotalAppPools { get; init; }
    public int RunningAppPools { get; init; }
    public int StoppedAppPools { get; init; }
    public int TotalWorkerProcesses { get; init; }
    public List<Alert> RecentAlerts { get; init; } = new();
    public string? Error { get; init; }
}

/// <summary>
/// Dashboard configuration for IIS features
/// </summary>
public record IisDashboardConfig
{
    public bool EnablePopout { get; init; } = true;
}
