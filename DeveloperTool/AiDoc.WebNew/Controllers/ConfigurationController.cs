using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Mvc;
using DedgeAuth.Client.Authorization;
using AiDoc.WebNew.Models;
using AiDoc.WebNew.Services;

namespace AiDoc.WebNew.Controllers;

[ApiController]
[Route("api/[controller]")]
[Authorize]
public class ConfigurationController : ControllerBase
{
    private readonly ConfigurationService _service;

    public ConfigurationController(ConfigurationService service)
    {
        _service = service;
    }

    [HttpGet("cursor-mcp")]
    [AllowAnonymous]
    public async Task<ActionResult<CursorMcpConfig>> GetCursorMcp()
    {
        var config = await _service.GetCursorMcpConfigAsync();
        return Ok(config);
    }

    [HttpGet("cursor-db2")]
    [AllowAnonymous]
    public async Task<ActionResult<CursorMcpServerEntry>> GetCursorDb2()
    {
        var config = await _service.GetCursorDb2ConfigAsync();
        return Ok(config);
    }

    [HttpGet("ollama-rag")]
    [AllowAnonymous]
    public async Task<ActionResult<OllamaRagConfig>> GetOllamaRag()
    {
        var config = await _service.GetOllamaRagConfigAsync();
        return Ok(config);
    }

    [HttpGet("ollama-db2")]
    [AllowAnonymous]
    public async Task<ActionResult<OllamaDb2Config>> GetOllamaDb2()
    {
        var config = await _service.GetOllamaDb2ConfigAsync();
        return Ok(config);
    }

    [HttpGet("proxy-script")]
    [AllowAnonymous]
    public async Task<ActionResult<ProxyScriptResponse>> GetProxyScript()
    {
        var script = await _service.GetProxyScriptAsync();
        return Ok(script);
    }
}
