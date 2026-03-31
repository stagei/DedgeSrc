using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Mvc;
using DedgeAuth.Services;

namespace DedgeAuth.Api.Controllers;

[ApiController]
[Route("api/[controller]")]
[Authorize(Policy = "GlobalAdmin")]
public class MaintenanceController : ControllerBase
{
    private readonly MaintenanceService _maintenance;
    private readonly ILogger<MaintenanceController> _logger;

    public MaintenanceController(MaintenanceService maintenance, ILogger<MaintenanceController> logger)
    {
        _maintenance = maintenance;
        _logger = logger;
    }

    [HttpGet("stats")]
    public async Task<IActionResult> GetStats()
    {
        var stats = await _maintenance.GetStatsAsync();
        return Ok(stats);
    }

    [HttpPost("cleanup-tokens")]
    public async Task<IActionResult> CleanupTokens()
    {
        _logger.LogInformation("Manual token cleanup triggered by admin");
        var result = await _maintenance.CleanupExpiredTokensAsync();
        return Ok(result);
    }

    [HttpPost("cleanup-visits")]
    public async Task<IActionResult> CleanupVisits([FromQuery] int? retentionDays = null)
    {
        if (retentionDays.HasValue && retentionDays.Value < 1)
            return BadRequest(new { error = "retentionDays must be at least 1" });

        _logger.LogInformation("Manual visit cleanup triggered by admin, retentionDays={Days}", retentionDays ?? -1);
        var removed = await _maintenance.CleanupOldVisitsAsync(retentionDays);
        return Ok(new { visitsRemoved = removed, retentionDays = retentionDays });
    }

    [HttpPost("run-all")]
    public async Task<IActionResult> RunAll([FromQuery] int? visitRetentionDays = null)
    {
        _logger.LogInformation("Full maintenance run triggered by admin");
        var tokenResult = await _maintenance.CleanupExpiredTokensAsync();
        var visitCount = await _maintenance.CleanupOldVisitsAsync(visitRetentionDays);

        return Ok(new
        {
            tokenResult.LoginTokensRemoved,
            tokenResult.RefreshTokensRemoved,
            VisitsRemoved = visitCount
        });
    }
}
