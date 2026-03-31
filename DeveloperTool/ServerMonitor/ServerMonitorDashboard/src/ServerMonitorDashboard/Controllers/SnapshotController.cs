using DedgeAuth.Client.Authorization;
using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Mvc;
using ServerMonitorDashboard.Services;

namespace ServerMonitorDashboard.Controllers;

/// <summary>
/// API endpoints for fetching snapshots from ServerMonitor agents
/// </summary>
[ApiController]
[Route("api")]
[Produces("application/json")]
[Authorize]
[RequireAppPermission(AppRoles.ReadOnly, AppRoles.User, AppRoles.PowerUser, AppRoles.Admin)]
public class SnapshotController : ControllerBase
{
    private readonly SnapshotProxyService _snapshotService;
    private readonly ILogger<SnapshotController> _logger;

    public SnapshotController(
        SnapshotProxyService snapshotService,
        ILogger<SnapshotController> logger)
    {
        _snapshotService = snapshotService;
        _logger = logger;
    }

    /// <summary>
    /// Gets a live snapshot from a specific server
    /// </summary>
    /// <param name="serverName">Target server name</param>
    [HttpGet("snapshot/{serverName}")]
    public async Task<IActionResult> GetSnapshot(string serverName)
    {
        var snapshot = await _snapshotService.GetSnapshotAsync(serverName);
        
        if (snapshot == null)
        {
            return StatusCode(503, new { 
                message = $"Could not retrieve snapshot from '{serverName}'",
                serverName = serverName
            });
        }

        return Ok(snapshot);
    }

    /// <summary>
    /// Clears the snapshot on a specific server's agent.
    /// Resets in-memory snapshot to initial state and deletes any persisted snapshot file.
    /// Admin-only operation.
    /// </summary>
    /// <param name="serverName">Target server name</param>
    [HttpPost("snapshot/{serverName}/clear")]
    [RequireAppPermission(AppRoles.Admin)]
    public async Task<IActionResult> ClearSnapshot(string serverName)
    {
        _logger.LogWarning("Admin requested snapshot clear for server: {Server}", serverName);

        var (success, message, data) = await _snapshotService.ClearSnapshotAsync(serverName);

        if (!success)
        {
            return StatusCode(503, new
            {
                success = false,
                serverName,
                message = $"Failed to clear snapshot on '{serverName}': {message}"
            });
        }

        return Ok(new
        {
            success = true,
            serverName,
            message,
            agentResponse = data
        });
    }
}
