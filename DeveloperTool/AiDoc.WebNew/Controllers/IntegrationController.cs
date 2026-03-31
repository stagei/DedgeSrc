using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Mvc;
using DedgeAuth.Client.Authorization;
using AiDoc.WebNew.Models;
using AiDoc.WebNew.Services;

namespace AiDoc.WebNew.Controllers;

[ApiController]
[Route("api/[controller]")]
[Authorize]
public class IntegrationController : ControllerBase
{
    private readonly RagManagementService _service;

    public IntegrationController(RagManagementService service)
    {
        _service = service;
    }

    [HttpGet("cursor")]
    [RequireAppPermission(AppRoles.User, AppRoles.Admin, AppRoles.ReadOnly)]
    public async Task<ActionResult<IntegrationConfig>> GetCursorConfig()
    {
        var registry = await _service.GetRegistryAsync();

        var mcpEntries = new Dictionary<string, object>();
        foreach (var rag in registry.Rags)
        {
            mcpEntries[rag.Name] = new
            {
                command = "<python-exe-path>",
                args = new[]
                {
                    "<rag-proxy-dir>/server_mcp_proxy.py",
                    "--rag", rag.Name,
                    "--remote-url", $"http://{registry.Host}:{rag.Port}"
                },
                cwd = "<rag-proxy-dir>"
            };
        }

        return Ok(new IntegrationConfig
        {
            Platform = "cursor",
            Title = "Cursor IDE Integration",
            Description = "Connect Cursor to AiDoc RAG databases via MCP (Model Context Protocol)",
            Steps = new List<IntegrationStep>
            {
                new() { Order = 1, Title = "Install the RAG proxy",
                    Description = "Run the registration script to set up the MCP proxy for Cursor.",
                    Code = "pwsh.exe -File \"C:\\opt\\src\\AiDoc\\src\\AiDoc.Pwsh.Client\\Register-RagNetworkInCursor.ps1\"",
                    Language = "powershell" },
                new() { Order = 2, Title = "Or configure manually",
                    Description = "Edit ~/.cursor/mcp.json and add entries for each RAG. Replace <python-exe-path> with your Python 3.12/3.13 venv path and <rag-proxy-dir> with the proxy directory.",
                    Code = System.Text.Json.JsonSerializer.Serialize(
                        new { mcpServers = mcpEntries },
                        new System.Text.Json.JsonSerializerOptions { WriteIndented = true }),
                    Language = "json" },
                new() { Order = 3, Title = "Restart Cursor",
                    Description = "After editing mcp.json, restart Cursor for the MCP servers to activate. The RAG tools will appear in Cursor's MCP panel." },
                new() { Order = 4, Title = "Test the connection",
                    Description = "Ask Cursor a question that should trigger RAG lookup, e.g. 'What is SQL30082N?' for db2-docs." }
            }
        });
    }

    [HttpGet("ollama")]
    [RequireAppPermission(AppRoles.User, AppRoles.Admin, AppRoles.ReadOnly)]
    public async Task<ActionResult<IntegrationConfig>> GetOllamaConfig()
    {
        var registry = await _service.GetRegistryAsync();

        return Ok(new IntegrationConfig
        {
            Platform = "ollama",
            Title = "Ollama Integration",
            Description = "Use Ollama local LLMs with AiDoc RAG for private, offline AI queries",
            Steps = new List<IntegrationStep>
            {
                new() { Order = 1, Title = "Install Ollama",
                    Description = "Download and install Ollama from https://ollama.ai. Pull a model (e.g. llama3, mistral, or codellama).",
                    Code = "ollama pull llama3.3",
                    Language = "bash" },
                new() { Order = 2, Title = "Run a RAG query via script",
                    Description = "Use the AiDoc Ollama query script to combine RAG context with Ollama's LLM.",
                    Code = $"pwsh.exe -File \"C:\\opt\\src\\AiDoc\\src\\AiDoc.Pwsh.Client\\Invoke-RagOllamaQuery.ps1\" -Query \"What is SQL30082N?\" -Rag db2-docs -RagHost {registry.Host}",
                    Language = "powershell" },
                new() { Order = 3, Title = "Or use the Python script directly",
                    Description = "The Python script queries the RAG HTTP server and sends context + question to Ollama.",
                    Code = $"python AiDoc.Python/scripts/ollama_rag_query.py --rag db2-docs --remote-host {registry.Host} --remote-port 8484 --query \"Explain SQL30082N\"",
                    Language = "bash" },
                new() { Order = 4, Title = "Available RAG endpoints",
                    Description = "These are the RAG HTTP endpoints you can query:",
                    Code = string.Join("\n", registry.Rags.Select(r =>
                        $"http://{registry.Host}:{r.Port}/query?q=<your-question>  # {r.Name}: {r.Description}")),
                    Language = "text" }
            }
        });
    }

    [HttpGet("chatgpt")]
    [RequireAppPermission(AppRoles.User, AppRoles.Admin, AppRoles.ReadOnly)]
    public async Task<ActionResult<IntegrationConfig>> GetChatGptConfig()
    {
        var registry = await _service.GetRegistryAsync();
        var host = registry.Host;

        return Ok(new IntegrationConfig
        {
            Platform = "chatgpt",
            Title = "ChatGPT Integration",
            Description = "Use AiDoc RAG databases with ChatGPT via custom GPTs or the API",
            Steps = new List<IntegrationStep>
            {
                new() { Order = 1, Title = "Option A: Custom GPT with Actions",
                    Description = "Create a Custom GPT in ChatGPT that calls your RAG API as an external action. This requires the RAG HTTP server to be publicly accessible or tunneled via ngrok/Cloudflare." },
                new() { Order = 2, Title = "Create an OpenAPI spec for the RAG",
                    Description = "ChatGPT Custom GPTs use OpenAPI specs to define actions. Use this spec template for each RAG:",
                    Code = GenerateOpenApiSpec(host, registry.Rags.FirstOrDefault()?.Name ?? "db2-docs",
                        registry.Rags.FirstOrDefault()?.Port ?? 8484),
                    Language = "yaml" },
                new() { Order = 3, Title = "Configure the Custom GPT",
                    Description = "In ChatGPT:\n1. Go to 'Explore GPTs' → 'Create'\n2. Name it (e.g. 'DB2 Expert with RAG')\n3. In 'Configure' → 'Actions' → 'Create new action'\n4. Paste the OpenAPI spec\n5. Set the server URL to your public RAG endpoint\n6. Add instructions: 'Always query the RAG database before answering DB2/COBOL questions'" },
                new() { Order = 4, Title = "Option B: Copy-paste workflow",
                    Description = "If public access is not available, use a manual workflow:\n1. Query the RAG via the AiDoc portal or CLI\n2. Copy the relevant excerpts\n3. Paste into ChatGPT with your question\n\nExample CLI query:",
                    Code = $"curl \"http://{host}:8484/query?q=SQL30082N&n=3\"",
                    Language = "bash" },
                new() { Order = 5, Title = "Option C: ChatGPT API with RAG context",
                    Description = "Use the OpenAI API and inject RAG context into the system message. See the full guide in docs/ChatGPT-RAG-Integration.md for Python examples." }
            }
        });
    }

    [HttpGet("copilot")]
    [RequireAppPermission(AppRoles.User, AppRoles.Admin, AppRoles.ReadOnly)]
    public async Task<ActionResult<IntegrationConfig>> GetCopilotConfig()
    {
        var registry = await _service.GetRegistryAsync();

        return Ok(new IntegrationConfig
        {
            Platform = "copilot",
            Title = "Microsoft Copilot Integration",
            Description = "Use AiDoc RAG with Microsoft 365 Copilot, GitHub Copilot, and Copilot Studio",
            Steps = new List<IntegrationStep>
            {
                new() { Order = 1, Title = "GitHub Copilot in VS Code",
                    Description = "GitHub Copilot supports MCP servers (preview). Add the RAG as an MCP tool in VS Code settings.",
                    Code = System.Text.Json.JsonSerializer.Serialize(new
                    {
                        mcp = new
                        {
                            servers = registry.Rags.ToDictionary(r => r.Name, r => new
                            {
                                type = "http",
                                url = $"http://{registry.Host}:{r.Port}"
                            })
                        }
                    }, new System.Text.Json.JsonSerializerOptions { WriteIndented = true }),
                    Language = "json" },
                new() { Order = 2, Title = "Copilot Studio (Power Platform)",
                    Description = "Create a custom Copilot in Copilot Studio that queries the RAG API:\n1. Go to https://copilotstudio.microsoft.com\n2. Create a new Copilot\n3. Add a 'Plugin action' → 'OpenAPI'\n4. Import the OpenAPI spec from the ChatGPT integration section\n5. Configure authentication if needed" },
                new() { Order = 3, Title = "Microsoft 365 Copilot",
                    Description = "M365 Copilot can use Graph connectors and plugins. To integrate:\n1. Register a Copilot plugin via Teams Developer Portal\n2. Use the RAG HTTP API as the plugin backend\n3. Define search capabilities in the plugin manifest\n\nNote: This requires Microsoft 365 E3/E5 with Copilot license." },
                new() { Order = 4, Title = "Manual workflow",
                    Description = "For quick integration without configuration, use the AiDoc portal to query RAGs and paste context into any Copilot conversation." }
            }
        });
    }

    private static string GenerateOpenApiSpec(string host, string ragName, int port) =>
$@"openapi: 3.0.0
info:
  title: AiDoc RAG - {ragName}
  version: '1.0'
  description: Semantic search over {ragName} documentation
servers:
  - url: http://{host}:{port}
paths:
  /query:
    get:
      operationId: queryRag
      summary: Search the {ragName} knowledge base
      parameters:
        - name: q
          in: query
          required: true
          schema:
            type: string
          description: The search query
        - name: 'n'
          in: query
          schema:
            type: integer
            default: 6
          description: Number of results
      responses:
        '200':
          description: Search results
          content:
            application/json:
              schema:
                type: object
  /health:
    get:
      operationId: healthCheck
      summary: Health check
      responses:
        '200':
          description: OK";
}
