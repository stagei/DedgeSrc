using DedgeAuth.Client.Authorization;
using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Mvc;
using Microsoft.Extensions.Options;
using ServerMonitorDashboard.Models;
using ServerMonitorDashboard.Services;

namespace ServerMonitorDashboard.Controllers;

/// <summary>
/// API endpoints for creating reinstall and stop trigger files
/// Admin-only access required
/// </summary>
[ApiController]
[Route("api")]
[Produces("application/json")]
[Authorize]
[RequireAppPermission(AppRoles.Admin)]
public class ReinstallController : ControllerBase
{
    private readonly ReinstallService _reinstallService;
    private readonly VersionService _versionService;
    private readonly DashboardConfig _config;
    private readonly ILogger<ReinstallController> _logger;

    public ReinstallController(
        ReinstallService reinstallService,
        VersionService versionService,
        IOptions<DashboardConfig> config,
        ILogger<ReinstallController> logger)
    {
        _reinstallService = reinstallService;
        _versionService = versionService;
        _config = config.Value;
        _logger = logger;
    }

    /// <summary>
    /// Creates a reinstall trigger file for a specific server or all servers
    /// </summary>
    /// <param name="request">Optional: specify server name and/or version to install</param>
    [HttpPost("reinstall")]
    public async Task<IActionResult> CreateReinstallTrigger([FromBody] ReinstallRequest? request = null)
    {
        var result = await _reinstallService.CreateTriggerFileAsync(request?.ServerName, request?.Version);
        
        if (!result.Success)
        {
            return BadRequest(result);
        }

        _logger.LogInformation("Reinstall trigger created for {Server} v{Version}", 
            request?.ServerName ?? "ALL", result.Version);

        return Ok(result);
    }
    
    /// <summary>
    /// Creates a stop trigger file to gracefully shut down agent(s).
    /// - If ServerName is null, empty, "*", or "ALL" → creates global StopServerMonitor.txt (stops ALL agents)
    /// - Otherwise → creates StopServerMonitor_{ServerName}.txt (stops specific server)
    /// </summary>
    /// <param name="request">Stop request with optional ServerName</param>
    [HttpPost("stop")]
    public async Task<IActionResult> CreateStopTrigger([FromBody] StopRequest request)
    {
        try
        {
            // Get the config directory from the reinstall trigger path
            var configDir = Path.GetDirectoryName(_config.ReinstallTriggerPath) ?? "";
            
            // Check if this is a global stop request
            var isGlobal = string.IsNullOrWhiteSpace(request.ServerName) ||
                           request.ServerName.Equals("*", StringComparison.OrdinalIgnoreCase) ||
                           request.ServerName.Equals("ALL", StringComparison.OrdinalIgnoreCase);
            
            // Global: StopServerMonitor.txt | Specific: StopServerMonitor_SERVERNAME.txt
            var stopFilePath = isGlobal
                ? Path.Combine(configDir, "StopServerMonitor.txt")
                : Path.Combine(configDir, $"StopServerMonitor_{request.ServerName}.txt");
            
            // Ensure directory exists
            if (!string.IsNullOrEmpty(configDir) && !Directory.Exists(configDir))
            {
                Directory.CreateDirectory(configDir);
            }
            
            var targetDisplay = isGlobal ? "ALL SERVERS" : request.ServerName;
            
            // Write stop file with metadata
            var content = $"""
                # ServerMonitor Stop Trigger File
                # Target: {targetDisplay}
                # This file will be detected by the agent and trigger a graceful shutdown
                # Machine-specific files are deleted by the agent after processing
                # Global file (StopServerMonitor.txt) is NOT deleted - agents check for it
                
                TargetServer={( isGlobal ? "*" : request.ServerName )}
                Reason={request.Reason ?? "Requested via Dashboard"}
                Created={DateTime.UtcNow:o}
                Source=Dashboard
                """;
            
            // Use synchronous write for network shares reliability
            System.IO.File.WriteAllText(stopFilePath, content);
            
            _logger.LogWarning("🛑 Stop trigger created for {Target} at {Path}", targetDisplay, stopFilePath);
            
            return Ok(new StopResult
            {
                Success = true,
                ServerName = isGlobal ? "*" : request.ServerName,
                TriggerFilePath = stopFilePath,
                Message = isGlobal 
                    ? "Global stop trigger created. All agents will shut down within 10 seconds."
                    : $"Stop trigger created for {request.ServerName}. Agent will shut down within 10 seconds."
            });
        }
        catch (Exception ex)
        {
            _logger.LogError(ex, "Error creating stop trigger for {Server}", request.ServerName ?? "ALL");
            return BadRequest(new StopResult
            {
                Success = false,
                ServerName = request.ServerName,
                Message = $"Error: {ex.Message}"
            });
        }
    }

    /// <summary>
    /// Gets the current ServerMonitor agent version
    /// </summary>
    [HttpGet("version")]
    public IActionResult GetVersion()
    {
        return Ok(new
        {
            version = _versionService.GetCurrentVersion(),
            exePath = _versionService.GetExePath()
        });
    }
    
    /// <summary>
    /// Creates a start trigger file to start agent(s) via tray application.
    /// - If ServerName is null, empty, "*", or "ALL" → creates global StartServerMonitor.txt
    /// - Otherwise → creates StartServerMonitor_{ServerName}.txt
    /// </summary>
    [HttpPost("start")]
    public IActionResult CreateStartTrigger([FromBody] StartRequest request)
    {
        try
        {
            var configDir = Path.GetDirectoryName(_config.ReinstallTriggerPath) ?? "";
            
            var isGlobal = string.IsNullOrWhiteSpace(request.ServerName) ||
                           request.ServerName.Equals("*", StringComparison.OrdinalIgnoreCase) ||
                           request.ServerName.Equals("ALL", StringComparison.OrdinalIgnoreCase);
            
            var startFilePath = isGlobal
                ? Path.Combine(configDir, "StartServerMonitor.txt")
                : Path.Combine(configDir, $"StartServerMonitor_{request.ServerName}.txt");
            
            if (!string.IsNullOrEmpty(configDir) && !Directory.Exists(configDir))
            {
                Directory.CreateDirectory(configDir);
            }
            
            var targetDisplay = isGlobal ? "ALL SERVERS" : request.ServerName;
            
            var content = $"""
                # ServerMonitor Start Trigger File
                # Target: {targetDisplay}
                # This file will be detected by the tray app and trigger service start
                
                TargetServer={( isGlobal ? "*" : request.ServerName )}
                Created={DateTime.UtcNow:o}
                Source=Dashboard
                """;
            
            System.IO.File.WriteAllText(startFilePath, content);
            
            _logger.LogInformation("▶️ Start trigger created for {Target} at {Path}", targetDisplay, startFilePath);
            
            return Ok(new StartResult
            {
                Success = true,
                ServerName = isGlobal ? "*" : request.ServerName,
                TriggerFilePath = startFilePath,
                Message = isGlobal 
                    ? "Global start trigger created. All tray apps will start their agents."
                    : $"Start trigger created for {request.ServerName}."
            });
        }
        catch (Exception ex)
        {
            _logger.LogError(ex, "Error creating start trigger for {Server}", request.ServerName ?? "ALL");
            return BadRequest(new StartResult
            {
                Success = false,
                ServerName = request.ServerName,
                Message = $"Error: {ex.Message}"
            });
        }
    }
    
    /// <summary>
    /// Deletes the global start trigger file
    /// </summary>
    [HttpDelete("start")]
    public IActionResult DeleteStartTrigger()
    {
        try
        {
            var configDir = Path.GetDirectoryName(_config.ReinstallTriggerPath) ?? "";
            var startFilePath = Path.Combine(configDir, "StartServerMonitor.txt");
            
            if (System.IO.File.Exists(startFilePath))
            {
                System.IO.File.Delete(startFilePath);
                _logger.LogInformation("Deleted start trigger file: {Path}", startFilePath);
                return Ok(new { success = true, message = "Start trigger file deleted" });
            }
            
            return Ok(new { success = true, message = "Start trigger file did not exist" });
        }
        catch (Exception ex)
        {
            _logger.LogError(ex, "Error deleting start trigger file");
            return BadRequest(new { success = false, message = ex.Message });
        }
    }
    
    /// <summary>
    /// Checks if stop, start, reinstall, or disable trigger files exist
    /// </summary>
    [HttpGet("trigger-status")]
    public IActionResult GetTriggerStatus()
    {
        try
        {
            var configDir = Path.GetDirectoryName(_config.ReinstallTriggerPath) ?? "";
            
            var stopFilePath = Path.Combine(configDir, "StopServerMonitor.txt");
            var startFilePath = Path.Combine(configDir, "StartServerMonitor.txt");
            var reinstallFilePath = _config.ReinstallTriggerPath;
            var disableFilePath = Path.Combine(configDir, "DisableServerMonitor.txt");
            
            var stopExists = System.IO.File.Exists(stopFilePath);
            var startExists = System.IO.File.Exists(startFilePath);
            var reinstallExists = System.IO.File.Exists(reinstallFilePath);
            var disableExists = System.IO.File.Exists(disableFilePath);
            
            // Get file info if they exist
            DateTime? stopCreated = null;
            DateTime? startCreated = null;
            DateTime? reinstallCreated = null;
            DateTime? disableCreated = null;
            string? reinstallVersion = null;
            string? disableReason = null;
            
            if (stopExists)
            {
                stopCreated = System.IO.File.GetCreationTimeUtc(stopFilePath);
            }
            
            if (startExists)
            {
                startCreated = System.IO.File.GetCreationTimeUtc(startFilePath);
            }
            
            if (reinstallExists)
            {
                reinstallCreated = System.IO.File.GetCreationTimeUtc(reinstallFilePath);
                try
                {
                    var content = System.IO.File.ReadAllText(reinstallFilePath);
                    var versionMatch = System.Text.RegularExpressions.Regex.Match(content, @"Version=(.+)");
                    if (versionMatch.Success)
                    {
                        reinstallVersion = versionMatch.Groups[1].Value.Trim();
                    }
                }
                catch { /* Ignore read errors */ }
            }
            
            if (disableExists)
            {
                disableCreated = System.IO.File.GetCreationTimeUtc(disableFilePath);
                try
                {
                    var content = System.IO.File.ReadAllText(disableFilePath);
                    var reasonMatch = System.Text.RegularExpressions.Regex.Match(content, @"Reason=(.+)");
                    if (reasonMatch.Success)
                    {
                        disableReason = reasonMatch.Groups[1].Value.Trim();
                    }
                }
                catch { /* Ignore read errors */ }
            }
            
            return Ok(new TriggerStatusResult
            {
                StopFileExists = stopExists,
                StopFilePath = stopFilePath,
                StopFileCreated = stopCreated,
                StartFileExists = startExists,
                StartFilePath = startFilePath,
                StartFileCreated = startCreated,
                ReinstallFileExists = reinstallExists,
                ReinstallFilePath = reinstallFilePath,
                ReinstallFileCreated = reinstallCreated,
                ReinstallVersion = reinstallVersion,
                DisableFileExists = disableExists,
                DisableFilePath = disableFilePath,
                DisableFileCreated = disableCreated,
                DisableReason = disableReason
            });
        }
        catch (Exception ex)
        {
            _logger.LogError(ex, "Error checking trigger file status");
            return Ok(new TriggerStatusResult());
        }
    }
    
    /// <summary>
    /// Checks if a specific server's trigger file exists (start or reinstall)
    /// Used by dashboard to poll for file deletion by tray app
    /// </summary>
    [HttpGet("trigger-file-exists/{serverName}")]
    public IActionResult CheckServerTriggerFileExists(string serverName, [FromQuery] string type = "start")
    {
        try
        {
            var configDir = Path.GetDirectoryName(_config.ReinstallTriggerPath) ?? "";
            
            var fileName = type.ToLowerInvariant() switch
            {
                "start" => $"StartServerMonitor_{serverName}.txt",
                "reinstall" => $"ReinstallServerMonitor_{serverName}.txt",
                "stop" => $"StopServerMonitor_{serverName}.txt",
                _ => $"StartServerMonitor_{serverName}.txt"
            };
            
            var filePath = Path.Combine(configDir, fileName);
            var exists = System.IO.File.Exists(filePath);
            
            return Ok(new { 
                exists, 
                serverName, 
                type,
                filePath = exists ? filePath : null
            });
        }
        catch (Exception ex)
        {
            _logger.LogError(ex, "Error checking trigger file for {Server}", serverName);
            return Ok(new { exists = false, serverName, type, error = ex.Message });
        }
    }
    
    /// <summary>
    /// Deletes the global stop trigger file
    /// </summary>
    [HttpDelete("stop")]
    public IActionResult DeleteStopTrigger()
    {
        try
        {
            var configDir = Path.GetDirectoryName(_config.ReinstallTriggerPath) ?? "";
            var stopFilePath = Path.Combine(configDir, "StopServerMonitor.txt");
            
            if (System.IO.File.Exists(stopFilePath))
            {
                System.IO.File.Delete(stopFilePath);
                _logger.LogInformation("Deleted stop trigger file: {Path}", stopFilePath);
                return Ok(new { success = true, message = "Stop trigger file deleted" });
            }
            
            return Ok(new { success = true, message = "Stop trigger file did not exist" });
        }
        catch (Exception ex)
        {
            _logger.LogError(ex, "Error deleting stop trigger file");
            return BadRequest(new { success = false, message = ex.Message });
        }
    }
    
    /// <summary>
    /// Deletes the global reinstall trigger file
    /// </summary>
    [HttpDelete("reinstall")]
    public IActionResult DeleteReinstallTrigger()
    {
        try
        {
            var reinstallFilePath = _config.ReinstallTriggerPath;
            
            if (System.IO.File.Exists(reinstallFilePath))
            {
                System.IO.File.Delete(reinstallFilePath);
                _logger.LogInformation("Deleted reinstall trigger file: {Path}", reinstallFilePath);
                return Ok(new { success = true, message = "Reinstall trigger file deleted" });
            }
            
            return Ok(new { success = true, message = "Reinstall trigger file did not exist" });
        }
        catch (Exception ex)
        {
            _logger.LogError(ex, "Error deleting reinstall trigger file");
            return BadRequest(new { success = false, message = ex.Message });
        }
    }
    
    /// <summary>
    /// Creates a disable trigger file to prevent all agents from starting.
    /// This is a global kill switch that prevents agents from running until removed.
    /// Unlike StopServerMonitor.txt, this file persists and prevents any agent from starting.
    /// </summary>
    [HttpPost("disable")]
    public IActionResult CreateDisableTrigger([FromBody] DisableRequest? request = null)
    {
        try
        {
            var configDir = Path.GetDirectoryName(_config.ReinstallTriggerPath) ?? "";
            var disableFilePath = Path.Combine(configDir, "DisableServerMonitor.txt");
            
            if (!string.IsNullOrEmpty(configDir) && !Directory.Exists(configDir))
            {
                Directory.CreateDirectory(configDir);
            }
            
            var content = $"""
                # ServerMonitor Disable File
                # This file PREVENTS all ServerMonitor agents from starting
                # Agents will not run as long as this file exists
                # Delete this file to allow agents to run again
                
                Reason={request?.Reason ?? "Disabled via Dashboard"}
                Created={DateTime.UtcNow:o}
                CreatedBy={request?.CreatedBy ?? "Dashboard"}
                Source=Dashboard
                """;
            
            System.IO.File.WriteAllText(disableFilePath, content);
            
            _logger.LogWarning("⛔ Disable trigger created - ALL agents are now DISABLED: {Path}", disableFilePath);
            
            return Ok(new DisableResult
            {
                Success = true,
                TriggerFilePath = disableFilePath,
                Message = "Disable file created. All ServerMonitor agents are now prevented from starting."
            });
        }
        catch (Exception ex)
        {
            _logger.LogError(ex, "Error creating disable trigger file");
            return BadRequest(new DisableResult
            {
                Success = false,
                Message = $"Error: {ex.Message}"
            });
        }
    }
    
    /// <summary>
    /// Deletes the disable trigger file to allow agents to start again
    /// </summary>
    [HttpDelete("disable")]
    public IActionResult DeleteDisableTrigger()
    {
        try
        {
            var configDir = Path.GetDirectoryName(_config.ReinstallTriggerPath) ?? "";
            var disableFilePath = Path.Combine(configDir, "DisableServerMonitor.txt");
            
            if (System.IO.File.Exists(disableFilePath))
            {
                System.IO.File.Delete(disableFilePath);
                _logger.LogInformation("✅ Disable trigger file deleted - agents can now start: {Path}", disableFilePath);
                return Ok(new { success = true, message = "Disable file deleted. Agents can now start." });
            }
            
            return Ok(new { success = true, message = "Disable file did not exist" });
        }
        catch (Exception ex)
        {
            _logger.LogError(ex, "Error deleting disable trigger file");
            return BadRequest(new { success = false, message = ex.Message });
        }
    }
    
}

/// <summary>
/// Result model for trigger file status
/// </summary>
public class TriggerStatusResult
{
    public bool StopFileExists { get; set; }
    public string? StopFilePath { get; set; }
    public DateTime? StopFileCreated { get; set; }
    
    public bool StartFileExists { get; set; }
    public string? StartFilePath { get; set; }
    public DateTime? StartFileCreated { get; set; }
    
    public bool ReinstallFileExists { get; set; }
    public string? ReinstallFilePath { get; set; }
    public DateTime? ReinstallFileCreated { get; set; }
    public string? ReinstallVersion { get; set; }
    
    public bool DisableFileExists { get; set; }
    public string? DisableFilePath { get; set; }
    public DateTime? DisableFileCreated { get; set; }
    public string? DisableReason { get; set; }
}

/// <summary>
/// Request model for start endpoint
/// </summary>
public class StartRequest
{
    /// <summary>
    /// Target server name. Use "*" or "ALL" for global start.
    /// </summary>
    public string ServerName { get; set; } = "*";
}

/// <summary>
/// Result of start trigger creation
/// </summary>
public class StartResult
{
    public bool Success { get; set; }
    public string? ServerName { get; set; }
    public string? TriggerFilePath { get; set; }
    public string? Message { get; set; }
}

/// <summary>
/// Request model for reinstall endpoint
/// </summary>
public class ReinstallRequest
{
    /// <summary>
    /// Optional: Target server name. If specified, creates a server-specific trigger file.
    /// If not specified, creates a global trigger that affects all servers.
    /// </summary>
    public string? ServerName { get; set; }
    
    /// <summary>
    /// Optional: Version to install. If not specified, auto-detects from ServerMonitor.exe
    /// </summary>
    public string? Version { get; set; }
}

/// <summary>
/// Request model for stop endpoint
/// </summary>
public class StopRequest
{
    /// <summary>
    /// Required: Target server name to stop
    /// </summary>
    public string ServerName { get; set; } = "";
    
    /// <summary>
    /// Optional: Reason for stopping the agent
    /// </summary>
    public string? Reason { get; set; }
}

/// <summary>
/// Result of stop trigger creation
/// </summary>
public class StopResult
{
    public bool Success { get; set; }
    public string? ServerName { get; set; }
    public string? TriggerFilePath { get; set; }
    public string? Message { get; set; }
}

/// <summary>
/// Request model for disable endpoint
/// </summary>
public class DisableRequest
{
    /// <summary>
    /// Optional: Reason for disabling agents
    /// </summary>
    public string? Reason { get; set; }
    
    /// <summary>
    /// Optional: Who created this disable request
    /// </summary>
    public string? CreatedBy { get; set; }
}

/// <summary>
/// Result of disable trigger creation
/// </summary>
public class DisableResult
{
    public bool Success { get; set; }
    public string? TriggerFilePath { get; set; }
    public string? Message { get; set; }
}
