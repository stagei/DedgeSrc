using NLog;
using System;
using System.Collections.Generic;
using System.Linq;
using System.Net.Http;
using System.Text;
using System.Text.Json;
using System.Threading.Tasks;

namespace DbExplorer.Services.AI;

/// <summary>
/// Ollama local AI provider (localhost:11434).
/// PRIMARY RECOMMENDED PROVIDER - Free, private, no API key.
/// </summary>
public class OllamaProvider : IAiProvider
{
    private static readonly Logger Logger = LogManager.GetCurrentClassLogger();
    private readonly HttpClient _httpClient;
    private readonly string _baseUrl;
    
    public string ProviderName => "Ollama";
    public string DisplayName => "🏠 Ollama (Local - Recommended)";
    public bool RequiresApiKey => false;
    public bool IsLocal => true;
    
    public OllamaProvider(string baseUrl = "http://localhost:11434")
    {
        _baseUrl = baseUrl;
        _httpClient = new HttpClient
        {
            Timeout = TimeSpan.FromMinutes(5) // AI can take time
        };
        
        Logger.Debug("OllamaProvider initialized with base URL: {Url}", _baseUrl);
    }
    
    public async Task<bool> TestConnectionAsync()
    {
        Logger.Debug("Testing Ollama connection");
        
        try
        {
            var response = await _httpClient.GetAsync($"{_baseUrl}/api/tags");
            var isAvailable = response.IsSuccessStatusCode;
            
            Logger.Info("Ollama connection test: {Status}", isAvailable ? "SUCCESS" : "FAILED");
            return isAvailable;
        }
        catch (Exception ex)
        {
            Logger.Warn(ex, "Ollama not available at {Url}", _baseUrl);
            return false;
        }
    }
    
    public async Task<string> GenerateAsync(string prompt, AiGenerationOptions options)
    {
        Logger.Info("Generating AI response via Ollama (model: {Model})", options.Model ?? "default");
        Logger.Debug("Prompt length: {Length} characters", prompt.Length);
        
        try
        {
            var requestBody = new
            {
                model = options.Model ?? "llama3.2",
                prompt = prompt,
                stream = false,
                options = new
                {
                    temperature = options.Temperature,
                    top_p = options.TopP,
                    top_k = options.TopK
                }
            };
            
            var json = JsonSerializer.Serialize(requestBody);
            var content = new StringContent(json, Encoding.UTF8, "application/json");
            
            Logger.Debug("Sending request to Ollama: {Url}/api/generate", _baseUrl);
            var response = await _httpClient.PostAsync($"{_baseUrl}/api/generate", content);
            response.EnsureSuccessStatusCode();
            
            var responseJson = await response.Content.ReadAsStringAsync();
            var result = JsonSerializer.Deserialize<OllamaResponse>(responseJson);
            
            var generatedText = result?.response ?? string.Empty;
            
            Logger.Info("Ollama response received: {Length} characters", generatedText.Length);
            return generatedText;
        }
        catch (Exception ex)
        {
            Logger.Error(ex, "Failed to generate AI response via Ollama");
            return $"Error: {ex.Message}";
        }
    }
    
    public async Task<List<string>> GetAvailableModelsAsync()
    {
        Logger.Debug("Fetching available Ollama models");
        
        try
        {
            var response = await _httpClient.GetAsync($"{_baseUrl}/api/tags");
            response.EnsureSuccessStatusCode();
            
            var responseJson = await response.Content.ReadAsStringAsync();
            var result = JsonSerializer.Deserialize<OllamaModelsResponse>(responseJson);
            
            var models = result?.models?.Select(m => m.name ?? string.Empty).ToList() ?? new List<string>();
            
            Logger.Info("Found {Count} Ollama models: {Models}", models.Count, string.Join(", ", models));
            return models;
        }
        catch (Exception ex)
        {
            Logger.Error(ex, "Failed to fetch Ollama models");
            return new List<string>();
        }
    }
    
    public async Task<ProviderStatus> GetStatusAsync()
    {
        var status = new ProviderStatus();
        
        try
        {
            status.IsConnected = await TestConnectionAsync();
            status.IsAvailable = status.IsConnected;
            
            if (status.IsAvailable)
            {
                status.AvailableModels = await GetAvailableModelsAsync();
                status.SelectedModel = status.AvailableModels.FirstOrDefault() ?? "llama3.2";
                status.StatusMessage = $"✅ Connected - {status.AvailableModels.Count} model(s) available";
            }
            else
            {
                status.StatusMessage = "⚠️ Ollama not running. Install from https://ollama.com";
                status.ErrorMessage = "Connection failed to localhost:11434";
            }
        }
        catch (Exception ex)
        {
            Logger.Error(ex, "Failed to get Ollama status");
            status.IsAvailable = false;
            status.StatusMessage = "❌ Error checking Ollama status";
            status.ErrorMessage = ex.Message;
        }
        
        return status;
    }
}

// Ollama API response models
internal class OllamaResponse
{
    public string? model { get; set; }
    public string? response { get; set; }
    public bool done { get; set; }
}

internal class OllamaModelsResponse
{
    public List<OllamaModel>? models { get; set; }
}

internal class OllamaModel
{
    public string? name { get; set; }
    public string? modified_at { get; set; }
    public long size { get; set; }
}

