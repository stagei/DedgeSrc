using DedgeAuth.Client.Authorization;
using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Mvc;
using ServerMonitorDashboard.Models;
using ServerMonitorDashboard.Services;

namespace ServerMonitorDashboard.Controllers;

/// <summary>
/// API endpoints for active alerts across all monitored servers
/// </summary>
[ApiController]
[Route("api/alerts")]
[Produces("application/json")]
[Authorize]
[RequireAppPermission(AppRoles.ReadOnly, AppRoles.User, AppRoles.PowerUser, AppRoles.Admin)]
public class ActiveAlertsController : ControllerBase
{
    private readonly AlertPollingService _alertPollingService;
    private readonly ILogger<ActiveAlertsController> _logger;

    public ActiveAlertsController(
        AlertPollingService alertPollingService,
        ILogger<ActiveAlertsController> logger)
    {
        _alertPollingService = alertPollingService;
        _logger = logger;
    }

    /// <summary>
    /// Gets all active alerts across monitored servers
    /// </summary>
    /// <returns>List of servers with active alerts and their counts by severity</returns>
    [HttpGet("active")]
    [ProducesResponseType(typeof(ActiveAlertsResponse), 200)]
    public IActionResult GetActiveAlerts()
    {
        var response = _alertPollingService.GetActiveAlerts();
        return Ok(response);
    }

    /// <summary>
    /// Acknowledge alerts for a specific server (removes from active alerts)
    /// </summary>
    /// <param name="serverName">Server name to acknowledge</param>
    /// <returns>Success status</returns>
    [HttpPost("acknowledge/{serverName}")]
    [ProducesResponseType(200)]
    [ProducesResponseType(404)]
    public IActionResult AcknowledgeServer(string serverName)
    {
        _logger.LogInformation("Acknowledging alerts for server: {Server}", serverName);
        
        var removed = _alertPollingService.AcknowledgeServer(serverName);
        
        return Ok(new 
        { 
            success = true, 
            serverName,
            wasActive = removed,
            message = removed 
                ? $"Alerts for {serverName} acknowledged and removed from active list"
                : $"Server {serverName} was not in active alerts list"
        });
    }

    /// <summary>
    /// Gets the current alert polling configuration
    /// </summary>
    /// <returns>Current alert polling settings</returns>
    [HttpGet("config")]
    [ProducesResponseType(typeof(AlertPollingConfig), 200)]
    public IActionResult GetConfig()
    {
        var config = _alertPollingService.GetConfig();
        return Ok(config);
    }
}
