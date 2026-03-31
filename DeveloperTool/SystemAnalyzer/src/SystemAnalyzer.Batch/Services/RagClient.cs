using System.Net.Http.Json;
using System.Text.Json;
using NLog;

namespace SystemAnalyzer.Batch.Services;

public sealed class RagClient
{
    private static readonly Logger Logger = LogManager.GetCurrentClassLogger();

    private readonly HttpClient _httpClient;
    private readonly string _ragUrl;
    private readonly string _visualCobolRagUrl;
    private readonly int _defaultResults;

    public RagClient(HttpClient httpClient, string ragUrl, string visualCobolRagUrl, int defaultResults = 8)
    {
        _httpClient = httpClient;
        _ragUrl = ragUrl;
        _visualCobolRagUrl = visualCobolRagUrl;
        _defaultResults = defaultResults;
    }

    public async Task<string> InvokeRagAsync(string query, int? nResults = null)
    {
        var n = nResults ?? _defaultResults;
        try
        {
            var requestBody = JsonSerializer.Serialize(new Dictionary<string, object>
            {
                ["query"] = query,
                ["n_results"] = n
            });

            var content = new StringContent(requestBody, System.Text.Encoding.UTF8, "application/json");
            var response = await _httpClient.PostAsync(_ragUrl, content);

            if (!response.IsSuccessStatusCode)
            {
                var errorBody = await response.Content.ReadAsStringAsync();
                Logger.Warn($"RAG query failed ({response.StatusCode}): {errorBody}");
                return string.Empty;
            }

            var responseText = await response.Content.ReadAsStringAsync();
            using var doc = JsonDocument.Parse(responseText);
            if (doc.RootElement.TryGetProperty("result", out var resultProp))
                return resultProp.GetString() ?? string.Empty;

            return responseText;
        }
        catch (Exception ex)
        {
            Logger.Warn($"RAG query failed: {ex.Message}");
            return string.Empty;
        }
    }

    public async Task<string> InvokeVisualCobolRagAsync(string query, int nResults = 4)
    {
        var body = new { query, n_results = nResults };
        try
        {
            var response = await _httpClient.PostAsJsonAsync($"{_visualCobolRagUrl}/query", body);
            response.EnsureSuccessStatusCode();
            return await response.Content.ReadAsStringAsync();
        }
        catch (Exception ex)
        {
            Logger.Warn($"Visual COBOL RAG query failed: {ex.Message}");
            return string.Empty;
        }
    }
}
