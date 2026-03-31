using System.Text;
using System.Text.Json;
using DedgeAuth.Client.Authorization;
using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Mvc;
using ServerMonitorDashboard.Services;

namespace ServerMonitorDashboard.Controllers;

/// <summary>
/// Controller for remote script execution.
/// DISABLED in Dashboard - script execution is only available via TrayApp.
/// This API is intentionally NOT documented in Swagger.
/// Only authorized users (FKSVEERI, FKGEISTA) can execute scripts via TrayApp.
/// </summary>
[ApiController]
[Route("api/[controller]")]
[ApiExplorerSettings(IgnoreApi = true)] // Hide from Swagger
[Authorize]
[RequireAppPermission("ScriptRunner")] // Non-existent role - effectively disables this controller
public class ScriptController : ControllerBase
{
    // Hardcoded authorized users - must match Agent Tray list
    private static readonly HashSet<string> AuthorizedUsers = new(StringComparer.OrdinalIgnoreCase)
    {
        "FKSVEERI",
        "FKGEISTA"
    };

    private readonly ComputerInfoService _computerInfoService;
    private readonly IHttpClientFactory _httpClientFactory;
    private readonly ILogger<ScriptController> _logger;
    private const int TrayApiPort = 8997;

    public ScriptController(
        ComputerInfoService computerInfoService,
        IHttpClientFactory httpClientFactory,
        ILogger<ScriptController> logger)
    {
        _computerInfoService = computerInfoService;
        _httpClientFactory = httpClientFactory;
        _logger = logger;
    }

    /// <summary>
    /// Get list of Azure servers with pattern information for filtering.
    /// </summary>
    [HttpGet("servers")]
    public async Task<IActionResult> GetServers()
    {
        try
        {
            var allServers = await _computerInfoService.GetServersAsync();

            // Filter to Azure servers only
            var azureServers = allServers
                .Where(s => s.Platform?.Equals("Azure", StringComparison.OrdinalIgnoreCase) == true)
                .Where(s => !string.IsNullOrEmpty(s.Name))
                .ToList();

            // Build server list with pattern info
            var servers = azureServers.Select(s =>
            {
                var name = s.Name!;
                var lastDash = name.LastIndexOf('-');
                string? typePattern = null;
                string? envPattern = null;

                if (lastDash > 0)
                {
                    typePattern = name.Substring(lastDash); // e.g., "-app"
                    if (lastDash >= 3)
                    {
                        envPattern = name.Substring(lastDash - 3, 3); // e.g., "prd"
                    }
                }

                return new
                {
                    name,
                    typePattern,
                    envPattern,
                    environment = s.Environment
                };
            }).ToList();

            // Extract distinct patterns with counts
            var typePatterns = servers
                .Where(s => s.typePattern != null)
                .GroupBy(s => s.typePattern)
                .Select(g => new { pattern = g.Key, count = g.Count() })
                .OrderBy(p => p.pattern)
                .ToList();

            var envPatterns = servers
                .Where(s => s.envPattern != null)
                .GroupBy(s => s.envPattern)
                .Select(g => new { pattern = g.Key, count = g.Count() })
                .OrderBy(p => p.pattern)
                .ToList();

            return Ok(new
            {
                servers,
                typePatterns,
                envPatterns
            });
        }
        catch (Exception ex)
        {
            _logger.LogError(ex, "Error getting server list for script runner");
            return StatusCode(500, new { error = ex.Message });
        }
    }

    /// <summary>
    /// Execute a script on a remote server via the Agent Tray API.
    /// </summary>
    [HttpPost("execute")]
    public async Task<IActionResult> Execute([FromBody] ScriptExecuteRequest request)
    {
        // Validate request
        if (string.IsNullOrWhiteSpace(request.Server))
        {
            return BadRequest(new { success = false, error = "server is required" });
        }

        if (string.IsNullOrWhiteSpace(request.ScriptName))
        {
            return BadRequest(new { success = false, error = "scriptName is required" });
        }

        if (string.IsNullOrWhiteSpace(request.Mode))
        {
            return BadRequest(new { success = false, error = "mode is required" });
        }

        if (string.IsNullOrWhiteSpace(request.RequestedBy))
        {
            return BadRequest(new { success = false, error = "requestedBy is required" });
        }

        // Validate user authorization (Dashboard-side check)
        if (!AuthorizedUsers.Contains(request.RequestedBy))
        {
            _logger.LogWarning("Unauthorized script execution attempt by {User} on {Server}",
                request.RequestedBy, request.Server);
            return StatusCode(403, new { success = false, error = "Unauthorized user" });
        }

        // Validate mode
        if (request.Mode != "run" && request.Mode != "install")
        {
            return BadRequest(new { success = false, error = "mode must be 'run' or 'install'" });
        }

        var startTime = DateTime.UtcNow;

        try
        {
            _logger.LogInformation("Script execution request: {User} -> {Server} -> {Mode} {Script}",
                request.RequestedBy, request.Server, request.Mode, request.ScriptName);

            // Build request to Agent Tray API
            var trayRequest = new
            {
                mode = request.Mode,
                scriptName = request.ScriptName,
                requestedBy = request.RequestedBy,
                timeoutSeconds = request.TimeoutSeconds ?? 30
            };

            var url = $"http://{request.Server}:{TrayApiPort}/api/script/execute";
            var client = _httpClientFactory.CreateClient("TrayApi");
            client.Timeout = TimeSpan.FromSeconds((request.TimeoutSeconds ?? 30) + 10); // Add buffer

            var jsonContent = new StringContent(
                JsonSerializer.Serialize(trayRequest),
                Encoding.UTF8,
                "application/json");

            var response = await client.PostAsync(url, jsonContent);
            var responseJson = await response.Content.ReadAsStringAsync();

            var duration = (DateTime.UtcNow - startTime).TotalSeconds;

            if (response.IsSuccessStatusCode || response.StatusCode == System.Net.HttpStatusCode.Accepted)
            {
                var result = JsonSerializer.Deserialize<ScriptExecuteResponse>(responseJson, JsonOptions);
                return Ok(new
                {
                    success = result?.Success ?? false,
                    executionId = result?.ExecutionId,
                    output = result?.Output,
                    error = result?.Error,
                    exitCode = result?.ExitCode,
                    message = result?.Message,
                    durationSeconds = Math.Round(duration, 2),
                    server = request.Server
                });
            }
            else
            {
                // Try to parse error response
                try
                {
                    var errorResult = JsonSerializer.Deserialize<ScriptExecuteResponse>(responseJson, JsonOptions);
                    return Ok(new
                    {
                        success = false,
                        error = errorResult?.Error ?? $"Server returned {(int)response.StatusCode}",
                        durationSeconds = Math.Round(duration, 2),
                        server = request.Server
                    });
                }
                catch
                {
                    return Ok(new
                    {
                        success = false,
                        error = $"Server returned {(int)response.StatusCode}: {responseJson}",
                        durationSeconds = Math.Round(duration, 2),
                        server = request.Server
                    });
                }
            }
        }
        catch (HttpRequestException ex)
        {
            var duration = (DateTime.UtcNow - startTime).TotalSeconds;
            _logger.LogWarning("Tray API not reachable on {Server}: {Error}", request.Server, ex.Message);
            return Ok(new
            {
                success = false,
                error = $"Agent tray not reachable: {ex.Message}",
                durationSeconds = Math.Round(duration, 2),
                server = request.Server
            });
        }
        catch (TaskCanceledException)
        {
            var duration = (DateTime.UtcNow - startTime).TotalSeconds;
            return Ok(new
            {
                success = false,
                error = "Request timed out",
                durationSeconds = Math.Round(duration, 2),
                server = request.Server
            });
        }
        catch (Exception ex)
        {
            var duration = (DateTime.UtcNow - startTime).TotalSeconds;
            _logger.LogError(ex, "Error executing script on {Server}", request.Server);
            return Ok(new
            {
                success = false,
                error = ex.Message,
                durationSeconds = Math.Round(duration, 2),
                server = request.Server
            });
        }
    }

    /// <summary>
    /// Poll for script execution status.
    /// </summary>
    [HttpGet("status/{server}/{executionId}")]
    public async Task<IActionResult> GetStatus(string server, string executionId, [FromQuery] string? requestedBy)
    {
        // Validate user authorization
        if (string.IsNullOrWhiteSpace(requestedBy) || !AuthorizedUsers.Contains(requestedBy))
        {
            return StatusCode(403, new { success = false, error = "Unauthorized user" });
        }

        try
        {
            var url = $"http://{server}:{TrayApiPort}/api/script/status/{executionId}";
            var client = _httpClientFactory.CreateClient("TrayApi");
            client.Timeout = TimeSpan.FromSeconds(10);

            var response = await client.GetAsync(url);
            var responseJson = await response.Content.ReadAsStringAsync();

            if (response.IsSuccessStatusCode)
            {
                var result = JsonSerializer.Deserialize<ScriptStatusResponse>(responseJson, JsonOptions);
                return Ok(new
                {
                    executionId = result?.ExecutionId,
                    scriptName = result?.ScriptName,
                    mode = result?.Mode,
                    isRunning = result?.IsRunning ?? false,
                    success = result?.Success,
                    output = result?.Output,
                    exitCode = result?.ExitCode,
                    durationSeconds = result?.DurationSeconds,
                    server
                });
            }
            else if (response.StatusCode == System.Net.HttpStatusCode.NotFound)
            {
                return NotFound(new { success = false, error = "Execution not found" });
            }
            else
            {
                return Ok(new
                {
                    success = false,
                    error = $"Server returned {(int)response.StatusCode}",
                    server
                });
            }
        }
        catch (HttpRequestException ex)
        {
            return Ok(new
            {
                success = false,
                error = $"Agent tray not reachable: {ex.Message}",
                server
            });
        }
        catch (Exception ex)
        {
            _logger.LogError(ex, "Error polling script status on {Server}", server);
            return Ok(new
            {
                success = false,
                error = ex.Message,
                server
            });
        }
    }

    private static readonly JsonSerializerOptions JsonOptions = new()
    {
        PropertyNameCaseInsensitive = true,
        PropertyNamingPolicy = JsonNamingPolicy.CamelCase
    };
}

/// <summary>
/// Response model for script status polling.
/// </summary>
public class ScriptStatusResponse
{
    public string? ExecutionId { get; set; }
    public string? ScriptName { get; set; }
    public string? Mode { get; set; }
    public bool IsRunning { get; set; }
    public bool? Success { get; set; }
    public string? Output { get; set; }
    public int? ExitCode { get; set; }
    public double? DurationSeconds { get; set; }
}

/// <summary>
/// Request model for script execution.
/// </summary>
public class ScriptExecuteRequest
{
    public string? Server { get; set; }
    public string? Mode { get; set; }
    public string? ScriptName { get; set; }
    public string? RequestedBy { get; set; }
    public int? TimeoutSeconds { get; set; }
}

/// <summary>
/// Response model from Agent Tray script execution.
/// </summary>
public class ScriptExecuteResponse
{
    public bool Success { get; set; }
    public string? ExecutionId { get; set; }
    public string? Output { get; set; }
    public string? Error { get; set; }
    public int? ExitCode { get; set; }
    public string? Message { get; set; }
    public bool? IsRunning { get; set; }
    public double DurationSeconds { get; set; }
    public string? Server { get; set; }
}
