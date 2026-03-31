using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Mvc;
using DedgeAuth.Client.Authorization;
using AiDoc.WebNew.Models;
using AiDoc.WebNew.Services;

namespace AiDoc.WebNew.Controllers;

[ApiController]
[Route("api/[controller]")]
[Authorize]
public class BackupController : ControllerBase
{
    private readonly BackupService _service;
    private readonly ILogger<BackupController> _logger;

    public BackupController(BackupService service, ILogger<BackupController> logger)
    {
        _service = service;
        _logger = logger;
    }

    [HttpGet("history")]
    [RequireAppPermission(AppRoles.User, AppRoles.Admin, AppRoles.ReadOnly)]
    public async Task<ActionResult<List<BackupInfo>>> History()
    {
        var backups = await _service.GetHistoryAsync();
        return Ok(backups);
    }

    [HttpPost("trigger")]
    [RequireAppPermission(AppRoles.Admin)]
    public async Task<ActionResult<BackupInfo>> Trigger()
    {
        try
        {
            var result = await _service.TriggerBackupAsync();
            return Ok(result);
        }
        catch (DirectoryNotFoundException ex)
        {
            return NotFound(new { error = ex.Message });
        }
    }

    [HttpDelete("{fileName}")]
    [RequireAppPermission(AppRoles.Admin)]
    public async Task<IActionResult> Delete(string fileName)
    {
        try
        {
            var deleted = await _service.DeleteBackupAsync(fileName);
            if (!deleted) return NotFound(new { error = $"Backup '{fileName}' not found" });
            return NoContent();
        }
        catch (ArgumentException ex)
        {
            return BadRequest(new { error = ex.Message });
        }
    }
}
