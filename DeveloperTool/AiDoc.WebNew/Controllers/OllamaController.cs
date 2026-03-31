using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Mvc;
using DedgeAuth.Client.Authorization;
using AiDoc.WebNew.Models;
using AiDoc.WebNew.Services;

namespace AiDoc.WebNew.Controllers;

[ApiController]
[Route("api/[controller]")]
[Authorize]
public class OllamaController : ControllerBase
{
    private readonly OllamaQueryService _service;
    private readonly ILogger<OllamaController> _logger;

    public OllamaController(OllamaQueryService service, ILogger<OllamaController> logger)
    {
        _service = service;
        _logger = logger;
    }

    [HttpGet("health")]
    [RequireAppPermission(AppRoles.User, AppRoles.Admin, AppRoles.ReadOnly)]
    public async Task<IActionResult> Health()
    {
        var healthy = await _service.CheckHealthAsync();
        return Ok(new { healthy });
    }

    [HttpGet("models")]
    [RequireAppPermission(AppRoles.User, AppRoles.Admin, AppRoles.ReadOnly)]
    public async Task<ActionResult<List<string>>> Models()
    {
        var models = await _service.ListModelsAsync();
        return Ok(models);
    }

    [HttpPost("query")]
    [RequireAppPermission(AppRoles.Admin)]
    public async Task<ActionResult<OllamaQueryResult>> Query([FromBody] OllamaQueryRequest request)
    {
        if (string.IsNullOrWhiteSpace(request.Query))
            return BadRequest(new { error = "Query is required" });

        try
        {
            var result = await _service.QueryAsync(request);
            return Ok(result);
        }
        catch (InvalidOperationException ex)
        {
            return StatusCode(502, new { error = ex.Message });
        }
    }
}
