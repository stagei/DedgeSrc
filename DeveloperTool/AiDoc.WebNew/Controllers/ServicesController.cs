using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Mvc;
using DedgeAuth.Client.Authorization;
using AiDoc.WebNew.Models;
using AiDoc.WebNew.Services;

namespace AiDoc.WebNew.Controllers;

[ApiController]
[Route("api/[controller]")]
[Authorize]
public class ServicesController : ControllerBase
{
    private readonly ServiceManagementService _service;
    private readonly RagManagementService _ragService;
    private readonly ILogger<ServicesController> _logger;

    public ServicesController(
        ServiceManagementService service,
        RagManagementService ragService,
        ILogger<ServicesController> logger)
    {
        _service = service;
        _ragService = ragService;
        _logger = logger;
    }

    [HttpGet]
    [RequireAppPermission(AppRoles.User, AppRoles.Admin, AppRoles.ReadOnly)]
    public async Task<ActionResult<List<RagServiceInfo>>> List()
    {
        var registry = await _ragService.GetRegistryAsync();
        var host = string.IsNullOrEmpty(registry.Host) ? "localhost" : registry.Host;
        var services = await _service.ListServicesAsync(registry.Rags, host);
        return Ok(services);
    }

    [HttpGet("{name}/health")]
    [RequireAppPermission(AppRoles.User, AppRoles.Admin, AppRoles.ReadOnly)]
    public async Task<IActionResult> Health(string name)
    {
        var registry = await _ragService.GetRegistryAsync();
        var entry = registry.Rags.FirstOrDefault(r =>
            r.Name.Equals(name, StringComparison.OrdinalIgnoreCase));

        if (entry is null)
            return NotFound(new { error = $"RAG '{name}' not found" });

        var host = string.IsNullOrEmpty(registry.Host) ? "localhost" : registry.Host;
        var healthy = await _service.CheckHealthAsync(host, entry.Port);
        return Ok(new { name, healthy, port = entry.Port });
    }

    [HttpPost("{name}/start")]
    [RequireAppPermission(AppRoles.Admin)]
    public async Task<ActionResult<RagServiceInfo>> Start(string name)
    {
        var registry = await _ragService.GetRegistryAsync();
        var entry = registry.Rags.FirstOrDefault(r =>
            r.Name.Equals(name, StringComparison.OrdinalIgnoreCase));

        if (entry is null)
            return NotFound(new { error = $"RAG '{name}' not found in registry" });

        try
        {
            var host = string.IsNullOrEmpty(registry.Host) ? "localhost" : registry.Host;
            var info = await _service.StartServiceAsync(name, entry.Port, host);
            return Ok(info);
        }
        catch (InvalidOperationException ex)
        {
            return Conflict(new { error = ex.Message });
        }
        catch (FileNotFoundException ex)
        {
            return StatusCode(500, new { error = ex.Message });
        }
    }

    [HttpPost("{name}/stop")]
    [RequireAppPermission(AppRoles.Admin)]
    public async Task<IActionResult> Stop(string name)
    {
        var registry = await _ragService.GetRegistryAsync();
        var entry = registry.Rags.FirstOrDefault(r =>
            r.Name.Equals(name, StringComparison.OrdinalIgnoreCase));

        if (entry is null)
            return NotFound(new { error = $"RAG '{name}' not found in registry" });

        var stopped = await _service.StopServiceAsync(name, entry.Port);
        return Ok(new { name, stopped });
    }

    [HttpPost("{name}/restart")]
    [RequireAppPermission(AppRoles.Admin)]
    public async Task<ActionResult<RagServiceInfo>> Restart(string name)
    {
        var registry = await _ragService.GetRegistryAsync();
        var entry = registry.Rags.FirstOrDefault(r =>
            r.Name.Equals(name, StringComparison.OrdinalIgnoreCase));

        if (entry is null)
            return NotFound(new { error = $"RAG '{name}' not found in registry" });

        try
        {
            var host = string.IsNullOrEmpty(registry.Host) ? "localhost" : registry.Host;
            var info = await _service.RestartServiceAsync(name, entry.Port, host);
            return Ok(info);
        }
        catch (Exception ex)
        {
            return StatusCode(500, new { error = ex.Message });
        }
    }
}
