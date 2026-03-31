using Microsoft.Extensions.Options;
using AiDoc.WebNew.Models;
using AiDoc.WebNew.Options;

namespace AiDoc.WebNew.Services;

public class ConfigurationService
{
    private readonly ILogger<ConfigurationService> _logger;
    private readonly AiDocOptions _options;
    private readonly RagManagementService _ragService;

    public ConfigurationService(
        ILogger<ConfigurationService> logger,
        IOptions<AiDocOptions> options,
        RagManagementService ragService)
    {
        _logger = logger;
        _options = options.Value;
        _ragService = ragService;
    }

    public async Task<CursorMcpConfig> GetCursorMcpConfigAsync()
    {
        var registry = await _ragService.GetRegistryAsync();
        var host = string.IsNullOrEmpty(registry.Host) ? _options.RagHost : registry.Host;
        var config = new CursorMcpConfig();

        foreach (var rag in registry.Rags)
        {
            config.McpServers[rag.Name] = new CursorMcpServerEntry
            {
                Command = "<venv-python>",
                Args = new List<string>
                {
                    "<proxy-dir>/server_mcp_proxy.py",
                    "--rag", rag.Name,
                    "--remote-url", $"http://{host}:{rag.Port}"
                },
                Cwd = "<proxy-dir>"
            };
        }

        return config;
    }

    public Task<CursorMcpServerEntry> GetCursorDb2ConfigAsync()
    {
        return Task.FromResult(new CursorMcpServerEntry
        {
            Command = "",
            Args = new List<string>(),
            Cwd = ""
        });
    }

    public async Task<OllamaRagConfig> GetOllamaRagConfigAsync()
    {
        var registry = await _ragService.GetRegistryAsync();
        var host = string.IsNullOrEmpty(registry.Host) ? _options.RagHost : registry.Host;
        var model = _options.OllamaDefaultModel;

        var ragUrls = new Dictionary<string, string>();
        var ragNames = new List<string>();

        foreach (var rag in registry.Rags)
        {
            ragUrls[rag.Name] = $"http://{host}:{rag.Port}";
            ragNames.Add(rag.Name);
        }

        var ragUrlEntries = string.Join("\n",
            ragUrls.Select(kv => $"        '{kv.Key}' = '{kv.Value}'"));
        var ragListStr = string.Join(", ", ragNames);

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

        return new OllamaRagConfig
        {
            ProfileBlock = profileBlock,
            RagUrls = ragUrls,
            DefaultModel = model,
            AvailableRags = ragNames
        };
    }

    public Task<OllamaDb2Config> GetOllamaDb2ConfigAsync()
    {
        var host = _options.RagHost;
        var model = _options.OllamaDefaultModel;

        var profileBlock = "# >>> AiDoc Ask-Db2 >>>\n" +
            "function Start-Db2Bridge {\n" +
            "    $bridgeDir = Join-Path $env:USERPROFILE '.ollama-mcp-bridge'\n" +
            "    $proc = Get-Process -Name 'ollama-mcp-bridge' -ErrorAction SilentlyContinue\n" +
            "    if ($proc) { Write-Host 'Bridge already running.' -ForegroundColor DarkGray; return }\n" +
            "    Start-Process -FilePath (Join-Path $bridgeDir 'ollama-mcp-bridge.exe') -WorkingDirectory $bridgeDir -WindowStyle Hidden\n" +
            "    Write-Host 'Bridge started.' -ForegroundColor Green\n" +
            "}\n\n" +
            "function Ask-Db2 {\n" +
            "    param([Parameter(Mandatory, Position = 0)] [string]$Question, [string]$Model = '" + model + "')\n" +
            "    Start-Db2Bridge\n" +
            "    $prompt = \"Use the db2_query MCP tool to answer: $Question\"\n" +
            "    $prompt | ollama run $Model\n" +
            "}\n" +
            "# <<< AiDoc Ask-Db2 <<<\n";

        return Task.FromResult(new OllamaDb2Config
        {
            ProfileBlock = profileBlock,
            BridgePort = 8000,
            RemoteHost = host,
            Model = model
        });
    }

    public Task<ProxyScriptResponse> GetProxyScriptAsync()
    {
        var content = """
            \"\"\"MCP stdio proxy -> remote RAG HTTP. Cursor starts this; it forwards to the server.\"\"\"
            import argparse, json, sys, urllib.request, urllib.error

            def _parse_args():
                p = argparse.ArgumentParser()
                p.add_argument("--rag", required=True)
                p.add_argument("--remote-url", required=True)
                return p.parse_args()

            def _query_remote(base_url, query, n_results=6):
                url = f"{base_url.rstrip('/')}/query"
                payload = json.dumps({"query": query, "n_results": n_results}).encode("utf-8")
                req = urllib.request.Request(url, data=payload, headers={"Content-Type": "application/json"})
                try:
                    with urllib.request.urlopen(req, timeout=30) as resp:
                        data = json.loads(resp.read().decode("utf-8"))
                        return data.get("result", json.dumps(data))
                except urllib.error.HTTPError as e:
                    return f"Remote RAG error (HTTP {e.code}): {e.read().decode('utf-8', errors='replace')}"
                except Exception as e:
                    return f"Remote RAG unreachable: {e}"

            def main():
                args = _parse_args()
                from mcp.server.fastmcp import FastMCP
                mcp = FastMCP(args.rag, json_response=True)
                @mcp.tool()
                def query_docs(query: str, n_results: int = 6) -> str:
                    \"\"\"Search documentation by meaning (semantic search). Returns relevant excerpts; cite the source file. RAG: \"\"\" + args.rag
                    return _query_remote(args.remote_url, query, n_results)
                mcp.run(transport="stdio")

            if __name__ == "__main__":
                sys.exit(main())
            """;

        return Task.FromResult(new ProxyScriptResponse
        {
            Content = content,
            FileName = "server_mcp_proxy.py"
        });
    }
}
