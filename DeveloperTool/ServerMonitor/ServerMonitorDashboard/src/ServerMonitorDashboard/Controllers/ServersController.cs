using System.Text.Json;
using DedgeAuth.Client.Authorization;
using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Mvc;
using ServerMonitorDashboard.Services;

namespace ServerMonitorDashboard.Controllers;

/// <summary>
/// API endpoints for server list and status
/// </summary>
[ApiController]
[Route("api")]
[Produces("application/json")]
[Authorize]
[RequireAppPermission(AppRoles.ReadOnly, AppRoles.User, AppRoles.PowerUser, AppRoles.Admin)]
public class ServersController : ControllerBase
{
    private readonly ServerStatusService _statusService;
    private readonly ILogger<ServersController> _logger;

    public ServersController(ServerStatusService statusService, ILogger<ServersController> logger)
    {
        _statusService = statusService;
        _logger = logger;
    }

    /// <summary>
    /// Gets all servers with their current status
    /// </summary>
    [HttpGet("servers")]
    public IActionResult GetServers()
    {
        var response = _statusService.GetAllServerStatus();
        return Ok(response);
    }

    /// <summary>
    /// Gets status for a specific server
    /// </summary>
    [HttpGet("servers/{serverName}")]
    public IActionResult GetServer(string serverName)
    {
        var status = _statusService.GetServerStatus(serverName);
        if (status == null)
        {
            return NotFound(new { message = $"Server '{serverName}' not found" });
        }
        return Ok(status);
    }

    /// <summary>
    /// Forces a refresh of all server statuses
    /// </summary>
    [HttpPost("servers/refresh")]
    public async Task<IActionResult> RefreshServers()
    {
        await _statusService.RefreshAllServerStatusAsync();
        var response = _statusService.GetAllServerStatus();
        return Ok(response);
    }
    
    /// <summary>
    /// Server-Sent Events (SSE) endpoint for live server status updates.
    /// Clients receive real-time notifications when server status changes.
    /// </summary>
    [HttpGet("servers/stream")]
    public async Task StreamServerStatus(CancellationToken cancellationToken)
    {
        Response.Headers.Append("Content-Type", "text/event-stream");
        Response.Headers.Append("Cache-Control", "no-cache");
        Response.Headers.Append("Connection", "keep-alive");
        
        _logger.LogInformation("SSE client connected");
        
        var tcs = new TaskCompletionSource<bool>();
        Guid subscriptionId = Guid.Empty;
        
        try
        {
            // Subscribe to status updates
            subscriptionId = _statusService.Subscribe(async evt =>
            {
                try
                {
                    var json = JsonSerializer.Serialize(evt, new JsonSerializerOptions
                    {
                        PropertyNamingPolicy = JsonNamingPolicy.CamelCase
                    });
                    
                    await Response.WriteAsync($"data: {json}\n\n", cancellationToken);
                    await Response.Body.FlushAsync(cancellationToken);
                }
                catch (Exception ex)
                {
                    _logger.LogDebug("SSE write error: {Message}", ex.Message);
                }
            });
            
            // Send initial state
            var initialState = _statusService.GetAllServerStatus();
            var initJson = JsonSerializer.Serialize(new { type = "init", servers = initialState.Servers }, 
                new JsonSerializerOptions { PropertyNamingPolicy = JsonNamingPolicy.CamelCase });
            await Response.WriteAsync($"data: {initJson}\n\n", cancellationToken);
            await Response.Body.FlushAsync(cancellationToken);
            
            // Keep connection alive with heartbeat
            while (!cancellationToken.IsCancellationRequested)
            {
                await Task.Delay(30000, cancellationToken); // Heartbeat every 30s
                await Response.WriteAsync($"data: {{\"type\":\"heartbeat\"}}\n\n", cancellationToken);
                await Response.Body.FlushAsync(cancellationToken);
            }
        }
        catch (OperationCanceledException)
        {
            _logger.LogInformation("SSE client disconnected");
        }
        catch (Exception ex)
        {
            _logger.LogWarning(ex, "SSE stream error");
        }
        finally
        {
            if (subscriptionId != Guid.Empty)
            {
                _statusService.Unsubscribe(subscriptionId);
            }
        }
    }
}
