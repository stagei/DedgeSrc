using System.Net.Http.Json;
using System.Text.Json;
using Microsoft.Extensions.Options;
using AiDoc.WebNew.Models;
using AiDoc.WebNew.Options;

namespace AiDoc.WebNew.Services;

public class OllamaQueryService
{
    private readonly ILogger<OllamaQueryService> _logger;
    private readonly AiDocOptions _options;
    private readonly IHttpClientFactory _httpClientFactory;
    private readonly RagManagementService _ragService;

    public OllamaQueryService(
        ILogger<OllamaQueryService> logger,
        IOptions<AiDocOptions> options,
        IHttpClientFactory httpClientFactory,
        RagManagementService ragService)
    {
        _logger = logger;
        _options = options.Value;
        _httpClientFactory = httpClientFactory;
        _ragService = ragService;
    }

    public async Task<OllamaQueryResult> QueryAsync(OllamaQueryRequest request)
    {
        var model = string.IsNullOrEmpty(request.Model) ? _options.OllamaDefaultModel : request.Model;
        var ragName = string.IsNullOrEmpty(request.Rag) ? "db2-docs" : request.Rag;

        _logger.LogInformation("Ollama query: rag={Rag}, model={Model}, q={Query}",
            ragName, model, request.Query);

        // Step 1: Query RAG for context
        string ragContext;
        try
        {
            ragContext = await _ragService.QueryRagAsync(ragName, request.Query, request.Chunks);
        }
        catch (Exception ex)
        {
            throw new InvalidOperationException($"RAG query failed for '{ragName}': {ex.Message}", ex);
        }

        // Parse sources from RAG response
        var sources = new List<string>();
        try
        {
            using var doc = JsonDocument.Parse(ragContext);
            if (doc.RootElement.TryGetProperty("result", out var resultEl))
                ragContext = resultEl.GetString() ?? ragContext;
        }
        catch { /* ragContext is plain text, use as-is */ }

        // Step 2: Build prompt
        var prompt = $"""
            You are a technical assistant. Answer the question using ONLY the documentation excerpts below.
            Cite the source file in your answer.

            --- DOCUMENTATION ---
            {ragContext}
            --- END ---

            Question: {request.Query}
            """;

        // Step 3: Call Ollama API
        var ollamaHost = _options.OllamaHost;
        var ollamaUrl = ollamaHost.StartsWith("http") ? ollamaHost : $"http://{ollamaHost}";

        var client = _httpClientFactory.CreateClient("OllamaClient");
        var ollamaRequest = new
        {
            model,
            prompt,
            stream = false
        };

        string answer;
        try
        {
            var response = await client.PostAsJsonAsync($"{ollamaUrl}/api/generate", ollamaRequest);
            response.EnsureSuccessStatusCode();
            var ollamaResponse = await response.Content.ReadFromJsonAsync<JsonElement>();
            answer = ollamaResponse.TryGetProperty("response", out var resp)
                ? resp.GetString() ?? "No response from Ollama"
                : "Unexpected Ollama response format";
        }
        catch (Exception ex)
        {
            throw new InvalidOperationException($"Ollama query failed: {ex.Message}", ex);
        }

        return new OllamaQueryResult
        {
            Answer = answer,
            RagName = ragName,
            Model = model,
            ChunksUsed = request.Chunks,
            Sources = sources
        };
    }

    public async Task<List<string>> ListModelsAsync()
    {
        try
        {
            var ollamaHost = _options.OllamaHost;
            var ollamaUrl = ollamaHost.StartsWith("http") ? ollamaHost : $"http://{ollamaHost}";
            var client = _httpClientFactory.CreateClient("OllamaClient");
            var response = await client.GetFromJsonAsync<JsonElement>($"{ollamaUrl}/api/tags");

            if (response.TryGetProperty("models", out var models))
            {
                return models.EnumerateArray()
                    .Select(m => m.TryGetProperty("name", out var n) ? n.GetString() ?? "" : "")
                    .Where(n => !string.IsNullOrEmpty(n))
                    .ToList();
            }
        }
        catch (Exception ex)
        {
            _logger.LogWarning(ex, "Failed to list Ollama models");
        }

        return new List<string>();
    }

    public async Task<bool> CheckHealthAsync()
    {
        try
        {
            var ollamaHost = _options.OllamaHost;
            var ollamaUrl = ollamaHost.StartsWith("http") ? ollamaHost : $"http://{ollamaHost}";
            var client = _httpClientFactory.CreateClient("OllamaClient");
            var response = await client.GetAsync(ollamaUrl);
            return response.IsSuccessStatusCode;
        }
        catch { return false; }
    }
}
