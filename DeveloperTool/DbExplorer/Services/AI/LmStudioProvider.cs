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
/// LM Studio local AI provider (localhost:1234) - OpenAI-compatible API.
/// </summary>
public class LmStudioProvider : IAiProvider
{
    private static readonly Logger Logger = LogManager.GetCurrentClassLogger();
    private readonly HttpClient _httpClient;
    private readonly string _baseUrl;
    
    public string ProviderName => "LMStudio";
    public string DisplayName => "🖥️ LM Studio (Local)";
    public bool RequiresApiKey => false;
    public bool IsLocal => true;
    
    public LmStudioProvider(string baseUrl = "http://localhost:1234/v1")
    {
        _baseUrl = baseUrl;
        _httpClient = new HttpClient
        {
            Timeout = TimeSpan.FromMinutes(5)
        };
        
        Logger.Debug("LmStudioProvider initialized with base URL: {Url}", _baseUrl);
    }
    
    public async Task<bool> TestConnectionAsync()
    {
        Logger.Debug("Testing LM Studio connection");
        
        try
        {
            var response = await _httpClient.GetAsync($"{_baseUrl}/models");
            var isAvailable = response.IsSuccessStatusCode;
            
            Logger.Info("LM Studio connection test: {Status}", isAvailable ? "SUCCESS" : "FAILED");
            return isAvailable;
        }
        catch (Exception ex)
        {
            Logger.Warn(ex, "LM Studio not available at {Url}", _baseUrl);
            return false;
        }
    }
    
    public async Task<string> GenerateAsync(string prompt, AiGenerationOptions options)
    {
        Logger.Info("Generating AI response via LM Studio (model: {Model})", options.Model ?? "default");
        
        try
        {
            // LM Studio uses OpenAI-compatible chat completion format
            var requestBody = new
            {
                model = options.Model ?? "local-model",
                messages = new[]
                {
                    new { role = "system", content = "You are a helpful database expert assistant." },
                    new { role = "user", content = prompt }
                },
                temperature = options.Temperature,
                max_tokens = options.MaxTokens,
                top_p = options.TopP,
                stream = false
            };
            
            var json = JsonSerializer.Serialize(requestBody);
            var content = new StringContent(json, Encoding.UTF8, "application/json");
            
            Logger.Debug("Sending request to LM Studio: {Url}/chat/completions", _baseUrl);
            var response = await _httpClient.PostAsync($"{_baseUrl}/chat/completions", content);
            response.EnsureSuccessStatusCode();
            
            var responseJson = await response.Content.ReadAsStringAsync();
            var result = JsonSerializer.Deserialize<OpenAiChatResponse>(responseJson);
            
            var generatedText = result?.choices?.FirstOrDefault()?.message?.content ?? string.Empty;
            
            Logger.Info("LM Studio response received: {Length} characters", generatedText.Length);
            return generatedText;
        }
        catch (Exception ex)
        {
            Logger.Error(ex, "Failed to generate AI response via LM Studio");
            return $"Error: {ex.Message}";
        }
    }
    
    public async Task<List<string>> GetAvailableModelsAsync()
    {
        Logger.Debug("Fetching available LM Studio models");
        
        try
        {
            var response = await _httpClient.GetAsync($"{_baseUrl}/models");
            response.EnsureSuccessStatusCode();
            
            var responseJson = await response.Content.ReadAsStringAsync();
            var result = JsonSerializer.Deserialize<OpenAiModelsResponse>(responseJson);
            
            var models = result?.data?.Select(m => m.id ?? string.Empty).ToList() ?? new List<string>();
            
            Logger.Info("Found {Count} LM Studio models: {Models}", models.Count, string.Join(", ", models));
            return models;
        }
        catch (Exception ex)
        {
            Logger.Error(ex, "Failed to fetch LM Studio models");
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
                status.SelectedModel = status.AvailableModels.FirstOrDefault() ?? "local-model";
                status.StatusMessage = $"✅ Connected - {status.AvailableModels.Count} model(s) available";
            }
            else
            {
                status.StatusMessage = "⚠️ LM Studio not running. Start LM Studio server.";
                status.ErrorMessage = "Connection failed to localhost:1234";
            }
        }
        catch (Exception ex)
        {
            Logger.Error(ex, "Failed to get LM Studio status");
            status.IsAvailable = false;
            status.StatusMessage = "❌ Error checking LM Studio status";
            status.ErrorMessage = ex.Message;
        }
        
        return status;
    }
}

// OpenAI-compatible API response models (shared with OpenAI provider)
internal class OpenAiChatResponse
{
    public List<OpenAiChoice>? choices { get; set; }
}

internal class OpenAiChoice
{
    public OpenAiMessage? message { get; set; }
}

internal class OpenAiMessage
{
    public string? role { get; set; }
    public string? content { get; set; }
}

internal class OpenAiModelsResponse
{
    public List<OpenAiModelInfo>? data { get; set; }
}

internal class OpenAiModelInfo
{
    public string? id { get; set; }
    public string? owned_by { get; set; }
}

