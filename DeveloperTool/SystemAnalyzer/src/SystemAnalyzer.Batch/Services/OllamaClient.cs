using System.Text;
using System.Text.Json;
using NLog;

namespace SystemAnalyzer.Batch.Services;

public sealed class OllamaClient
{
    private static readonly Logger Logger = LogManager.GetCurrentClassLogger();

    private readonly HttpClient _httpClient;
    private readonly string _ollamaUrl;
    private readonly string _ollamaModel;

    public OllamaClient(HttpClient httpClient, string ollamaUrl, string ollamaModel)
    {
        _httpClient = httpClient;
        _ollamaUrl = ollamaUrl.TrimEnd('/');
        _ollamaModel = ollamaModel;
    }

    public async Task<string> InvokeOllamaAsync(string prompt)
    {
        var body = new
        {
            model = _ollamaModel,
            prompt,
            stream = false
        };
        var json = JsonSerializer.Serialize(body);
        var content = new StringContent(json, Encoding.UTF8, "application/json");

        try
        {
            var response = await _httpClient.PostAsync($"{_ollamaUrl}/api/generate", content);
            response.EnsureSuccessStatusCode();
            var responseText = await response.Content.ReadAsStringAsync();
            using var doc = JsonDocument.Parse(responseText);
            if (doc.RootElement.TryGetProperty("response", out var resp))
                return resp.GetString() ?? string.Empty;
            return string.Empty;
        }
        catch (Exception ex)
        {
            Logger.Warn($"Ollama error: {ex.Message}");
            return string.Empty;
        }
    }
}
