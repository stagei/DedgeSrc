using DedgeAuth.Client.Authorization;
using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Mvc;
using ServerMonitorDashboard.Services;

namespace ServerMonitorDashboard.Controllers;

/// <summary>
/// API endpoints for editing ServerMonitor configuration files
/// Admin-only access required
/// </summary>
[ApiController]
[Route("api/config")]
[Produces("application/json")]
[Authorize]
[RequireAppPermission(AppRoles.Admin)]
public class ConfigEditorController : ControllerBase
{
    private readonly ConfigEditorService _configService;
    private readonly ILogger<ConfigEditorController> _logger;

    public ConfigEditorController(
        ConfigEditorService configService,
        ILogger<ConfigEditorController> logger)
    {
        _configService = configService;
        _logger = logger;
    }

    /// <summary>
    /// Load the agent alert settings (appsettings.ServerMonitorAgent.json)
    /// </summary>
    [HttpGet("agent-settings")]
    [ProducesResponseType(typeof(ConfigFileResult), 200)]
    [ProducesResponseType(typeof(ConfigFileResult), 404)]
    public async Task<IActionResult> GetAgentSettings()
    {
        var result = await _configService.LoadConfigAsync(ConfigFileType.AgentSettings);
        
        if (!result.Success)
        {
            return result.Error?.Contains("not found") == true 
                ? NotFound(result) 
                : StatusCode(500, result);
        }

        return Ok(result);
    }

    /// <summary>
    /// Save the agent alert settings (appsettings.ServerMonitorAgent.json)
    /// </summary>
    [HttpPost("agent-settings")]
    [ProducesResponseType(typeof(ConfigSaveResult), 200)]
    [ProducesResponseType(typeof(ConfigSaveResult), 400)]
    public async Task<IActionResult> SaveAgentSettings([FromBody] SaveConfigRequest request)
    {
        if (string.IsNullOrWhiteSpace(request.Content))
        {
            return BadRequest(new ConfigSaveResult
            {
                Success = false,
                Error = "Content is required"
            });
        }

        var result = await _configService.SaveConfigAsync(
            ConfigFileType.AgentSettings, 
            request.Content,
            request.EditedBy);

        if (!result.Success)
        {
            return BadRequest(result);
        }

        return Ok(result);
    }

    /// <summary>
    /// Load the notification recipients settings (NotificationRecipients.json)
    /// </summary>
    [HttpGet("notification-recipients")]
    [ProducesResponseType(typeof(ConfigFileResult), 200)]
    [ProducesResponseType(typeof(ConfigFileResult), 404)]
    public async Task<IActionResult> GetNotificationRecipients()
    {
        var result = await _configService.LoadConfigAsync(ConfigFileType.NotificationRecipients);
        
        if (!result.Success)
        {
            return result.Error?.Contains("not found") == true 
                ? NotFound(result) 
                : StatusCode(500, result);
        }

        return Ok(result);
    }

    /// <summary>
    /// Save the notification recipients settings (NotificationRecipients.json)
    /// </summary>
    [HttpPost("notification-recipients")]
    [ProducesResponseType(typeof(ConfigSaveResult), 200)]
    [ProducesResponseType(typeof(ConfigSaveResult), 400)]
    public async Task<IActionResult> SaveNotificationRecipients([FromBody] SaveConfigRequest request)
    {
        if (string.IsNullOrWhiteSpace(request.Content))
        {
            return BadRequest(new ConfigSaveResult
            {
                Success = false,
                Error = "Content is required"
            });
        }

        var result = await _configService.SaveConfigAsync(
            ConfigFileType.NotificationRecipients, 
            request.Content,
            request.EditedBy);

        if (!result.Success)
        {
            return BadRequest(result);
        }

        return Ok(result);
    }

    /// <summary>
    /// List all backup files
    /// </summary>
    [HttpGet("backups")]
    [ProducesResponseType(typeof(List<BackupFileInfo>), 200)]
    public IActionResult GetBackups()
    {
        var backups = _configService.GetBackupFiles();
        return Ok(backups);
    }

    /// <summary>
    /// Restore a backup file
    /// </summary>
    [HttpPost("restore")]
    [ProducesResponseType(typeof(ConfigSaveResult), 200)]
    [ProducesResponseType(typeof(ConfigSaveResult), 400)]
    public async Task<IActionResult> RestoreBackup([FromBody] RestoreBackupRequest request)
    {
        if (string.IsNullOrWhiteSpace(request.BackupFileName))
        {
            return BadRequest(new ConfigSaveResult
            {
                Success = false,
                Error = "Backup file name is required"
            });
        }

        var result = await _configService.RestoreBackupAsync(request.BackupFileName, request.FileType);

        if (!result.Success)
        {
            return BadRequest(result);
        }

        return Ok(result);
    }

    /// <summary>
    /// Get the Alert Routing Overview - shows which channels are enabled/disabled per environment
    /// </summary>
    [HttpGet("alert-routing")]
    [ProducesResponseType(typeof(AlertRoutingOverview), 200)]
    public async Task<IActionResult> GetAlertRoutingOverview()
    {
        var result = await _configService.GetAlertRoutingOverviewAsync();
        
        if (!result.Success)
        {
            return StatusCode(500, result);
        }

        return Ok(result);
    }

    /// <summary>
    /// Load the dashboard settings (appsettings.json - local to dashboard service)
    /// </summary>
    [HttpGet("dashboard-settings")]
    [ProducesResponseType(typeof(ConfigFileResult), 200)]
    [ProducesResponseType(typeof(ConfigFileResult), 404)]
    public async Task<IActionResult> GetDashboardSettings()
    {
        var result = await _configService.LoadConfigAsync(ConfigFileType.DashboardSettings);
        
        if (!result.Success)
        {
            return result.Error?.Contains("not found") == true 
                ? NotFound(result) 
                : StatusCode(500, result);
        }

        return Ok(result);
    }

    /// <summary>
    /// Save the dashboard settings (appsettings.json - local to dashboard service)
    /// </summary>
    [HttpPost("dashboard-settings")]
    [ProducesResponseType(typeof(ConfigSaveResult), 200)]
    [ProducesResponseType(typeof(ConfigSaveResult), 400)]
    public async Task<IActionResult> SaveDashboardSettings([FromBody] SaveConfigRequest request)
    {
        if (string.IsNullOrWhiteSpace(request.Content))
        {
            return BadRequest(new ConfigSaveResult
            {
                Success = false,
                Error = "Content is required"
            });
        }

        var result = await _configService.SaveConfigAsync(
            ConfigFileType.DashboardSettings, 
            request.Content,
            request.EditedBy);

        if (!result.Success)
        {
            return BadRequest(result);
        }

        return Ok(result);
    }
}

public class SaveConfigRequest
{
    public string Content { get; set; } = string.Empty;
    public string? EditedBy { get; set; }
}

public class RestoreBackupRequest
{
    public string BackupFileName { get; set; } = string.Empty;
    public ConfigFileType FileType { get; set; }
}
