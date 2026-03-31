using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Mvc;
using DedgeAuth.Client.Authorization;
using AiDoc.WebNew.Models;
using AiDoc.WebNew.Services;

namespace AiDoc.WebNew.Controllers;

[ApiController]
[Route("api/[controller]")]
[Authorize]
public class RagsController : ControllerBase
{
    private readonly RagManagementService _service;
    private readonly ILogger<RagsController> _logger;

    public RagsController(RagManagementService service, ILogger<RagsController> logger)
    {
        _service = service;
        _logger = logger;
    }

    [HttpGet]
    [RequireAppPermission(AppRoles.User, AppRoles.Admin, AppRoles.ReadOnly)]
    public async Task<ActionResult<List<RagIndexInfo>>> List()
    {
        var rags = await _service.ListRagsAsync();
        return Ok(rags);
    }

    [HttpGet("{name}")]
    [RequireAppPermission(AppRoles.User, AppRoles.Admin, AppRoles.ReadOnly)]
    public async Task<ActionResult<RagIndexInfo>> Get(string name)
    {
        var rag = await _service.GetRagAsync(name);
        if (rag is null) return NotFound(new { error = $"RAG '{name}' not found" });
        return Ok(rag);
    }

    [HttpPost]
    [RequireAppPermission(AppRoles.Admin)]
    public async Task<ActionResult<RagIndexInfo>> Create([FromBody] CreateRagRequest request)
    {
        try
        {
            var rag = await _service.CreateRagAsync(request);
            return CreatedAtAction(nameof(Get), new { name = rag.Name }, rag);
        }
        catch (ArgumentException ex)
        {
            return BadRequest(new { error = ex.Message });
        }
        catch (InvalidOperationException ex)
        {
            return Conflict(new { error = ex.Message });
        }
    }

    [HttpPost("{name}/rebuild")]
    [RequireAppPermission(AppRoles.Admin)]
    public async Task<ActionResult<RebuildResult>> Rebuild(string name)
    {
        try
        {
            var result = await _service.RebuildRagAsync(name);
            return Accepted(result);
        }
        catch (KeyNotFoundException ex)
        {
            return NotFound(new { error = ex.Message });
        }
        catch (DirectoryNotFoundException ex)
        {
            return NotFound(new { error = ex.Message });
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

    [HttpGet("{name}/rebuild-status")]
    [RequireAppPermission(AppRoles.User, AppRoles.Admin, AppRoles.ReadOnly)]
    public async Task<ActionResult<RebuildStatus>> GetRebuildStatus(string name)
    {
        var status = await _service.GetRebuildStatusAsync(name);
        return Ok(status);
    }

    [HttpPost("{name}/rebuild-cancel")]
    [RequireAppPermission(AppRoles.Admin)]
    public async Task<IActionResult> CancelRebuild(string name)
    {
        var cancelled = await _service.CancelRebuildAsync(name);
        if (!cancelled)
            return NotFound(new { error = $"No active rebuild found for '{name}'" });

        return Ok(new { cancelled = true, name });
    }

    [HttpDelete("{name}")]
    [RequireAppPermission(AppRoles.Admin)]
    public async Task<IActionResult> Delete(string name, [FromQuery] bool deleteFiles = false)
    {
        try
        {
            await _service.DeleteRagAsync(name, deleteFiles);
            return NoContent();
        }
        catch (KeyNotFoundException ex)
        {
            return NotFound(new { error = ex.Message });
        }
    }

    [HttpPost("{name}/upload")]
    [RequireAppPermission(AppRoles.Admin)]
    [RequestSizeLimit(200_000_000)]
    public async Task<ActionResult<UploadResult>> Upload(string name, [FromForm] List<IFormFile> files)
    {
        if (files is null || files.Count == 0)
            return BadRequest(new { error = "No files provided" });

        try
        {
            var result = await _service.UploadFilesAsync(name, files);
            return Ok(result);
        }
        catch (KeyNotFoundException ex)
        {
            return NotFound(new { error = ex.Message });
        }
        catch (DirectoryNotFoundException ex)
        {
            return NotFound(new { error = ex.Message });
        }
    }

    [HttpGet("{name}/sources")]
    [RequireAppPermission(AppRoles.User, AppRoles.Admin, AppRoles.ReadOnly)]
    public async Task<ActionResult<List<RagSourceInfo>>> ListSources(string name)
    {
        try
        {
            var sources = await _service.ListSourcesAsync(name);
            return Ok(sources);
        }
        catch (DirectoryNotFoundException ex)
        {
            return NotFound(new { error = ex.Message });
        }
    }

    [HttpDelete("{name}/sources/{*path}")]
    [RequireAppPermission(AppRoles.Admin)]
    public async Task<IActionResult> DeleteSource(string name, string path)
    {
        try
        {
            await _service.DeleteSourceAsync(name, path);
            return NoContent();
        }
        catch (FileNotFoundException ex)
        {
            return NotFound(new { error = ex.Message });
        }
        catch (ArgumentException ex)
        {
            return BadRequest(new { error = ex.Message });
        }
    }

    [HttpGet("{name}/query")]
    [RequireAppPermission(AppRoles.User, AppRoles.Admin, AppRoles.ReadOnly)]
    public async Task<IActionResult> Query(string name, [FromQuery] string q, [FromQuery] int n = 6)
    {
        if (string.IsNullOrWhiteSpace(q))
            return BadRequest(new { error = "Query parameter 'q' is required" });

        try
        {
            var result = await _service.QueryRagAsync(name, q, n);
            return Content(result, "application/json");
        }
        catch (KeyNotFoundException ex)
        {
            return NotFound(new { error = ex.Message });
        }
        catch (HttpRequestException ex)
        {
            return StatusCode(502, new { error = $"RAG server unreachable: {ex.Message}" });
        }
    }

    [HttpGet("registry")]
    [RequireAppPermission(AppRoles.User, AppRoles.Admin, AppRoles.ReadOnly)]
    public async Task<ActionResult<RagRegistry>> GetRegistry()
    {
        var registry = await _service.GetRegistryAsync();
        return Ok(registry);
    }

    // ═══════════════════════════════════════════════════════════════════════════
    // Anonymous endpoints for setup scripts (Setup-CursorRagNew, Setup-OllamaRagNew)
    // ═══════════════════════════════════════════════════════════════════════════

    [HttpGet("setup/cursor-mcp")]
    [AllowAnonymous]
    public async Task<IActionResult> GetCursorMcpConfig()
    {
        var registry = await _service.GetRegistryAsync();
        var mcpServers = new Dictionary<string, object>();

        foreach (var rag in registry.Rags)
        {
            mcpServers[rag.Name] = new
            {
                command = "<venv-python>",
                args = new[]
                {
                    "<proxy-dir>/server_mcp_proxy.py",
                    "--rag", rag.Name,
                    "--remote-url", $"http://{registry.Host}:{rag.Port}"
                },
                cwd = "<proxy-dir>"
            };
        }

        return Ok(new { mcpServers });
    }

    [HttpGet("setup/ollama-rag")]
    [AllowAnonymous]
    public async Task<IActionResult> GetOllamaRagConfig()
    {
        var registry = await _service.GetRegistryAsync();
        var ragUrls = registry.Rags.ToDictionary(r => r.Name, r => $"http://{registry.Host}:{r.Port}");
        var ragList = registry.Rags.Select(r => r.Name).ToList();
        var ragUrlEntries = string.Join("\n", ragUrls.Select(kv => $"        '{kv.Key}' = '{kv.Value}'"));
        var ragListStr = string.Join(", ", ragList);

        var model = "llama3.2";
        var profileBlock =
            "# >>> AiDoc Ask-Rag >>>\n" +
            "function Ask-Rag {\n" +
            "    param(\n" +
            "        [Parameter(Mandatory, Position = 0)]\n" +
            "        [string]$Question,\n" +
            "        [string]$Rag     = 'db2-docs',\n" +
            "        [string]$Model   = '" + model + "',\n" +
            "        [int]$Chunks     = 6\n" +
            "    )\n\n" +
            "    $ragUrls = @{\n" +
            ragUrlEntries + "\n" +
            "    }\n" +
            "    $baseUrl = $ragUrls[$Rag]\n" +
            "    if (-not $baseUrl) { Write-Host \"Unknown RAG: $Rag. Available: " + ragListStr + "\" -ForegroundColor Red; return }\n\n" +
            "    Write-Host \"Searching $Rag...\" -ForegroundColor DarkGray\n" +
            "    try {\n" +
            "        $body = @{ query = $Question; n_results = $Chunks } | ConvertTo-Json\n" +
            "        $resp = Invoke-RestMethod -Uri \"$baseUrl/query\" -Method Post -Body $body -ContentType 'application/json' -TimeoutSec 30\n" +
            "        $context = $resp.result\n" +
            "    } catch {\n" +
            "        Write-Host \"RAG query failed: $($_.Exception.Message)\" -ForegroundColor Red; return\n" +
            "    }\n" +
            "    if (-not $context) { Write-Host 'No results from RAG.' -ForegroundColor Yellow; return }\n\n" +
            "    $prompt = \"You are a technical assistant. Answer the question using ONLY the documentation excerpts below. Cite the source file.`n`n--- DOCUMENTATION ---`n$context`n--- END ---`n`nQuestion: $Question\"\n\n" +
            "    Write-Host \"Asking Ollama ($Model)...\" -ForegroundColor DarkGray\n" +
            "    $prompt | ollama run $Model\n" +
            "}\n" +
            "# <<< AiDoc Ask-Rag <<<\n";

        return Ok(new
        {
            profileBlock,
            ragUrls,
            defaultModel = model,
            availableRags = ragList
        });
    }

    [HttpGet("setup/proxy-script")]
    [AllowAnonymous]
    public IActionResult GetProxyScript()
    {
        var tq = "\"\"\"";
        var content =
            $"{tq}MCP stdio proxy -> remote RAG HTTP. Cursor starts this; it forwards to the server.{tq}\n" +
            "import argparse, json, sys, urllib.request, urllib.error\n" +
            "\n" +
            "def _parse_args():\n" +
            "    p = argparse.ArgumentParser()\n" +
            "    p.add_argument(\"--rag\", required=True)\n" +
            "    p.add_argument(\"--remote-url\", required=True)\n" +
            "    return p.parse_args()\n" +
            "\n" +
            "def _query_remote(base_url, query, n_results=6):\n" +
            "    url = f\"{base_url.rstrip('/')}/query\"\n" +
            "    payload = json.dumps({\"query\": query, \"n_results\": n_results}).encode(\"utf-8\")\n" +
            "    req = urllib.request.Request(url, data=payload, headers={\"Content-Type\": \"application/json\"})\n" +
            "    try:\n" +
            "        with urllib.request.urlopen(req, timeout=30) as resp:\n" +
            "            data = json.loads(resp.read().decode(\"utf-8\"))\n" +
            "            return data.get(\"result\", json.dumps(data))\n" +
            "    except urllib.error.HTTPError as e:\n" +
            "        return f\"Remote RAG error (HTTP {e.code}): {e.read().decode('utf-8', errors='replace')}\"\n" +
            "    except Exception as e:\n" +
            "        return f\"Remote RAG unreachable: {e}\"\n" +
            "\n" +
            "def main():\n" +
            "    args = _parse_args()\n" +
            "    from mcp.server.fastmcp import FastMCP\n" +
            "    mcp = FastMCP(args.rag, json_response=True)\n" +
            "    @mcp.tool()\n" +
            "    def query_docs(query: str, n_results: int = 6) -> str:\n" +
            $"        {tq}Search documentation by meaning (semantic search). Returns relevant excerpts; cite the source file.{tq}\n" +
            "        return _query_remote(args.remote_url, query, n_results)\n" +
            "    mcp.run(transport=\"stdio\")\n" +
            "\n" +
            "if __name__ == \"__main__\":\n" +
            "    sys.exit(main())\n";

        return Ok(new { content, fileName = "server_mcp_proxy.py" });
    }

    [HttpGet("setup/services")]
    [AllowAnonymous]
    public async Task<IActionResult> GetServicesStatus()
    {
        var registry = await _service.GetRegistryAsync();
        var httpFactory = HttpContext.RequestServices.GetRequiredService<IHttpClientFactory>();
        var client = httpFactory.CreateClient("RagProxy");

        var tasks = registry.Rags.Select(async r =>
        {
            string status;
            try
            {
                var resp = await client.GetAsync($"http://{registry.Host}:{r.Port}/health");
                status = resp.IsSuccessStatusCode ? "running" : "stopped";
            }
            catch
            {
                status = "stopped";
            }
            return new { name = r.Name, port = r.Port, status };
        });

        var services = await Task.WhenAll(tasks);
        return Ok(services);
    }
}
