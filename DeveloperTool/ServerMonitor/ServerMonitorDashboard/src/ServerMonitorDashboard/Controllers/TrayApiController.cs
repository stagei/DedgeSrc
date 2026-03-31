using DedgeAuth.Client.Authorization;
using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Mvc;
using ServerMonitorDashboard.Services;

namespace ServerMonitorDashboard.Controllers;

/// <summary>
/// Controller for interacting with ServerMonitorTrayIcon REST API on remote servers.
/// The Tray API runs on port 8997 on each server and provides direct control
/// of the agent service without using trigger files.
/// </summary>
[ApiController]
[Route("api/[controller]")]
[Authorize]
[RequireAppPermission(AppRoles.ReadOnly, AppRoles.User, AppRoles.PowerUser, AppRoles.Admin)]
public class TrayApiController : ControllerBase
{
    private readonly ITrayApiService _trayApiService;
    private readonly ILogger<TrayApiController> _logger;

    public TrayApiController(ITrayApiService trayApiService, ILogger<TrayApiController> logger)
    {
        _trayApiService = trayApiService;
        _logger = logger;
    }

    /// <summary>
    /// Check if the tray app is running on a specific server.
    /// </summary>
    [HttpGet("{serverName}/isalive")]
    public async Task<IActionResult> IsAlive(string serverName)
    {
        var result = await _trayApiService.IsAliveAsync(serverName);
        return Ok(new
        {
            server = serverName,
            trayAppRunning = result.IsSuccess,
            error = result.Error
        });
    }

    /// <summary>
    /// Get detailed status from the tray app including agent service status.
    /// </summary>
    [HttpGet("{serverName}/status")]
    public async Task<IActionResult> GetStatus(string serverName)
    {
        var result = await _trayApiService.GetStatusAsync(serverName);
        
        if (result.IsSuccess && result.Data != null)
        {
            return Ok(new
            {
                server = serverName,
                success = true,
                trayApp = result.Data.TrayApp,
                agent = result.Data.Agent
            });
        }
        
        return Ok(new
        {
            server = serverName,
            success = false,
            error = result.Error
        });
    }

    /// <summary>
    /// Start the agent service on a specific server via the tray app.
    /// </summary>
    [HttpPost("{serverName}/start")]
    public async Task<IActionResult> StartAgent(string serverName)
    {
        _logger.LogInformation("Dashboard request to START agent on {Server}", serverName);
        
        var result = await _trayApiService.StartAgentAsync(serverName);
        
        return Ok(new
        {
            server = serverName,
            action = "start",
            success = result.IsSuccess && (result.Data?.IsSuccess ?? false),
            message = result.Data?.Message ?? result.Error
        });
    }

    /// <summary>
    /// Stop the agent service on a specific server via the tray app.
    /// </summary>
    [HttpPost("{serverName}/stop")]
    public async Task<IActionResult> StopAgent(string serverName)
    {
        _logger.LogInformation("Dashboard request to STOP agent on {Server}", serverName);
        
        var result = await _trayApiService.StopAgentAsync(serverName);
        
        return Ok(new
        {
            server = serverName,
            action = "stop",
            success = result.IsSuccess && (result.Data?.IsSuccess ?? false),
            message = result.Data?.Message ?? result.Error
        });
    }

    /// <summary>
    /// Restart the agent service on a specific server via the tray app.
    /// </summary>
    [HttpPost("{serverName}/restart")]
    public async Task<IActionResult> RestartAgent(string serverName)
    {
        _logger.LogInformation("Dashboard request to RESTART agent on {Server}", serverName);
        
        var result = await _trayApiService.RestartAgentAsync(serverName);
        
        return Ok(new
        {
            server = serverName,
            action = "restart",
            success = result.IsSuccess && (result.Data?.IsSuccess ?? false),
            message = result.Data?.Message ?? result.Error
        });
    }

    /// <summary>
    /// Trigger agent reinstall on a specific server via the tray app.
    /// This uses the Tray API instead of trigger files for single-server updates.
    /// </summary>
    [HttpPost("{serverName}/reinstall")]
    public async Task<IActionResult> ReinstallAgent(string serverName)
    {
        _logger.LogInformation("Dashboard request to REINSTALL agent on {Server}", serverName);
        
        var result = await _trayApiService.ReinstallAgentAsync(serverName);
        
        return Ok(new
        {
            server = serverName,
            action = "reinstall",
            success = result.IsSuccess && (result.Data?.IsSuccess ?? false),
            message = result.Data?.Message ?? result.Error
        });
    }

    /// <summary>
    /// Batch check if tray apps are running on multiple servers.
    /// </summary>
    [HttpPost("batch/isalive")]
    public async Task<IActionResult> BatchIsAlive([FromBody] string[] serverNames)
    {
        var results = new List<object>();
        
        // Run in parallel for better performance
        var tasks = serverNames.Select(async server =>
        {
            var result = await _trayApiService.IsAliveAsync(server);
            return new
            {
                server,
                trayAppRunning = result.IsSuccess,
                error = result.Error
            };
        });
        
        var responses = await Task.WhenAll(tasks);
        
        return Ok(responses);
    }

    /// <summary>
    /// Get agent health status from the agent API (port 8999).
    /// Proxies the request to avoid CORS issues with direct browser-to-agent calls.
    /// </summary>
    [HttpGet("{serverName}/agent-health")]
    public async Task<IActionResult> GetAgentHealth(string serverName)
    {
        try
        {
            using var httpClient = new HttpClient { Timeout = TimeSpan.FromSeconds(5) };
            var response = await httpClient.GetAsync($"http://{serverName}:8999/api/health");
            
            if (response.IsSuccessStatusCode)
            {
                var content = await response.Content.ReadAsStringAsync();
                return Content(content, "application/json");
            }
            
            return StatusCode((int)response.StatusCode, new { error = $"Agent returned {response.StatusCode}" });
        }
        catch (Exception ex)
        {
            _logger.LogWarning(ex, "Failed to get agent health for {Server}", serverName);
            return StatusCode(503, new { error = $"Unable to connect to agent: {ex.Message}" });
        }
    }

    /// <summary>
    /// Enable or disable alerts on the agent (port 8999).
    /// </summary>
    [HttpPost("{serverName}/agent-alerts/{action}")]
    public async Task<IActionResult> SetAlerts(string serverName, string action)
    {
        if (action != "enable" && action != "disable")
        {
            return BadRequest(new { error = "Action must be 'enable' or 'disable'" });
        }

        try
        {
            using var httpClient = new HttpClient { Timeout = TimeSpan.FromSeconds(5) };
            var response = await httpClient.PostAsync($"http://{serverName}:8999/api/trigger/alerts/{action}", null);
            
            if (response.IsSuccessStatusCode)
            {
                var content = await response.Content.ReadAsStringAsync();
                return Content(content, "application/json");
            }
            
            return StatusCode((int)response.StatusCode, new { error = $"Agent returned {response.StatusCode}" });
        }
        catch (Exception ex)
        {
            _logger.LogWarning(ex, "Failed to {Action} alerts for {Server}", action, serverName);
            return StatusCode(503, new { error = $"Unable to connect to agent: {ex.Message}" });
        }
    }

    /// <summary>
    /// Trigger agent reinstall via agent API (port 8999).
    /// </summary>
    [HttpPost("{serverName}/agent-reinstall")]
    public async Task<IActionResult> TriggerAgentReinstall(string serverName)
    {
        try
        {
            using var httpClient = new HttpClient { Timeout = TimeSpan.FromSeconds(5) };
            var response = await httpClient.PostAsync($"http://{serverName}:8999/api/trigger/reinstall", null);
            
            if (response.IsSuccessStatusCode)
            {
                var content = await response.Content.ReadAsStringAsync();
                return Content(content, "application/json");
            }
            
            return StatusCode((int)response.StatusCode, new { error = $"Agent returned {response.StatusCode}" });
        }
        catch (Exception ex)
        {
            _logger.LogWarning(ex, "Failed to trigger reinstall for {Server}", serverName);
            return StatusCode(503, new { error = $"Unable to connect to agent: {ex.Message}" });
        }
    }

    /// <summary>
    /// Stop the tray icon process via agent API (port 8999).
    /// </summary>
    [HttpPost("{serverName}/agent-stop-tray")]
    public async Task<IActionResult> StopTrayViaAgent(string serverName)
    {
        try
        {
            using var httpClient = new HttpClient { Timeout = TimeSpan.FromSeconds(5) };
            var response = await httpClient.PostAsync($"http://{serverName}:8999/api/trigger/stop-tray", null);
            
            if (response.IsSuccessStatusCode)
            {
                var content = await response.Content.ReadAsStringAsync();
                return Content(content, "application/json");
            }
            
            return StatusCode((int)response.StatusCode, new { error = $"Agent returned {response.StatusCode}" });
        }
        catch (Exception ex)
        {
            _logger.LogWarning(ex, "Failed to stop tray for {Server}", serverName);
            return StatusCode(503, new { error = $"Unable to connect to agent: {ex.Message}" });
        }
    }
}
