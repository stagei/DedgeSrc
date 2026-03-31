using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Mvc;

namespace ServerMonitorDashboard.Controllers;

/// <summary>
/// Simple health check endpoint
/// </summary>
[ApiController]
[Route("api")]
[Produces("application/json")]
public class HealthController : ControllerBase
{
    /// <summary>
    /// Simple liveness check - returns true if Dashboard API is running.
    /// AllowAnonymous so install scripts can verify the API is up without auth.
    /// </summary>
    [HttpGet("IsAlive")]
    [AllowAnonymous]
    public IActionResult IsAlive()
    {
        return Ok(true);
    }
}
