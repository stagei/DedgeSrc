using Microsoft.AspNetCore.Mvc;
using GenericLogHandler.WebApi.Services;

namespace GenericLogHandler.WebApi.Controllers;

/// <summary>
/// API endpoints for editing configuration files (appsettings.json, import-config.json).
/// Mirrors ServerMonitor Dashboard ConfigEditorController pattern.
/// </summary>
[ApiController]
[Route("api/config")]
[Produces("application/json")]
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
    /// Load appsettings.json (Web API service configuration)
    /// </summary>
    [HttpGet("appsettings")]
    [ProducesResponseType(typeof(ConfigFileResult), 200)]
    [ProducesResponseType(typeof(ConfigFileResult), 404)]
    public async Task<IActionResult> GetAppSettings()
    {
        var result = await _configService.LoadConfigAsync(ConfigFileType.AppSettings);

        if (!result.Success)
        {
            return result.Error?.Contains("not found") == true
                ? NotFound(result)
                : StatusCode(500, result);
        }

        return Ok(result);
    }

    /// <summary>
    /// Save appsettings.json
    /// </summary>
    [HttpPost("appsettings")]
    [ProducesResponseType(typeof(ConfigSaveResult), 200)]
    [ProducesResponseType(typeof(ConfigSaveResult), 400)]
    public async Task<IActionResult> SaveAppSettings([FromBody] SaveConfigRequest request)
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
            ConfigFileType.AppSettings,
            request.Content,
            request.EditedBy);

        if (!result.Success)
            return BadRequest(result);

        return Ok(result);
    }

    /// <summary>
    /// Load import-config.json (import sources, retention, parsers)
    /// </summary>
    [HttpGet("import-config")]
    [ProducesResponseType(typeof(ConfigFileResult), 200)]
    [ProducesResponseType(typeof(ConfigFileResult), 404)]
    public async Task<IActionResult> GetImportConfig()
    {
        var result = await _configService.LoadConfigAsync(ConfigFileType.ImportConfig);

        if (!result.Success)
        {
            return result.Error?.Contains("not found") == true
                ? NotFound(result)
                : StatusCode(500, result);
        }

        return Ok(result);
    }

    /// <summary>
    /// Save import-config.json (hot-reload is supported by Import Service)
    /// </summary>
    [HttpPost("import-config")]
    [ProducesResponseType(typeof(ConfigSaveResult), 200)]
    [ProducesResponseType(typeof(ConfigSaveResult), 400)]
    public async Task<IActionResult> SaveImportConfig([FromBody] SaveConfigRequest request)
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
            ConfigFileType.ImportConfig,
            request.Content,
            request.EditedBy);

        if (!result.Success)
            return BadRequest(result);

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
            return BadRequest(result);

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
