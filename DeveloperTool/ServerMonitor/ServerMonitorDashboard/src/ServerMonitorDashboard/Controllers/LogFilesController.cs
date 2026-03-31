using DedgeAuth.Client.Authorization;
using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Mvc;
using ServerMonitorDashboard.Services;

namespace ServerMonitorDashboard.Controllers;

/// <summary>
/// API endpoints for fetching log files from ServerMonitor agents
/// </summary>
[ApiController]
[Route("api/logfiles")]
[Produces("application/json")]
[Authorize]
[RequireAppPermission(AppRoles.ReadOnly, AppRoles.User, AppRoles.PowerUser, AppRoles.Admin)]
public class LogFilesController : ControllerBase
{
    private readonly LogFilesProxyService _logFilesService;
    private readonly ILogger<LogFilesController> _logger;

    public LogFilesController(
        LogFilesProxyService logFilesService,
        ILogger<LogFilesController> logger)
    {
        _logFilesService = logFilesService;
        _logger = logger;
    }

    /// <summary>
    /// Gets a list of SQL error log files from a specific server
    /// </summary>
    /// <param name="serverName">Target server name</param>
    [HttpGet("sqlerrors/{serverName}")]
    public async Task<IActionResult> GetSqlErrorLogFiles(string serverName)
    {
        var files = await _logFilesService.GetSqlErrorLogFilesAsync(serverName);
        
        if (files == null)
        {
            return StatusCode(503, new { 
                message = $"Could not retrieve SQL error log files from '{serverName}'",
                serverName = serverName
            });
        }

        return Ok(files);
    }

    /// <summary>
    /// Gets the contents of a specific SQL error log file from a server
    /// </summary>
    /// <param name="serverName">Target server name</param>
    /// <param name="fileName">Log file name</param>
    [HttpGet("sqlerrors/{serverName}/{fileName}")]
    [Produces("text/plain")]
    public async Task<IActionResult> GetSqlErrorLogContent(string serverName, string fileName)
    {
        var content = await _logFilesService.GetSqlErrorLogContentAsync(serverName, fileName);
        
        if (content == null)
        {
            return StatusCode(503, new { 
                message = $"Could not retrieve SQL error log content from '{serverName}'",
                serverName = serverName,
                fileName = fileName
            });
        }

        return Content(content, "text/plain");
    }
}
