using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Mvc;
using DedgeAuth.Client.Authorization;
using AiDoc.WebNew.Models;
using AiDoc.WebNew.Services;

namespace AiDoc.WebNew.Controllers;

[ApiController]
[Route("api/[controller]")]
[Authorize]
public class EnvironmentController : ControllerBase
{
    private readonly EnvironmentService _service;
    private readonly ILogger<EnvironmentController> _logger;

    public EnvironmentController(EnvironmentService service, ILogger<EnvironmentController> logger)
    {
        _service = service;
        _logger = logger;
    }

    [HttpGet("status")]
    [RequireAppPermission(AppRoles.User, AppRoles.Admin, AppRoles.ReadOnly)]
    public async Task<ActionResult<EnvironmentStatus>> GetStatus()
    {
        var status = await _service.GetStatusAsync();
        return Ok(status);
    }

    [HttpPost("initialize")]
    [RequireAppPermission(AppRoles.Admin)]
    public async Task<ActionResult<EnvironmentStatus>> Initialize()
    {
        try
        {
            var status = await _service.InitializeAsync();
            return Ok(status);
        }
        catch (InvalidOperationException ex)
        {
            return BadRequest(new { error = ex.Message });
        }
    }

    [HttpPost("verify-python")]
    [RequireAppPermission(AppRoles.Admin)]
    public async Task<IActionResult> VerifyPython()
    {
        var version = await _service.VerifyPythonAsync();
        if (version is null)
            return NotFound(new { error = "Python not found" });
        return Ok(new { version });
    }
}
