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
/// Google Gemini provider (Gemini 2.0 Flash, Gemini 1.5 Pro).
/// Requires API key. Data sent to Google servers.
/// </summary>
public class GeminiProvider : IAiProvider
{
    private static readonly Logger Logger = LogManager.GetCurrentClassLogger();
    private readonly HttpClient _httpClient;
    private readonly string _apiKey;
    private readonly string _baseUrl = "https://generativelanguage.googleapis.com/v1";
    
    public string ProviderName => "Gemini";
    public string DisplayName => "☁️ Google Gemini";
    public bool RequiresApiKey => true;
    public bool IsLocal => false;
    
    public GeminiProvider(string apiKey)
    {
        _apiKey = apiKey;
        _httpClient = new HttpClient
        {
            Timeout = TimeSpan.FromMinutes(5)
        };
        
        Logger.Debug("GeminiProvider initialized");
    }
    
    public async Task<bool> TestConnectionAsync()
    {
        Logger.Debug("Testing Gemini connection");
        
        try
        {
            var response = await _httpClient.GetAsync($"{_baseUrl}/models?key={_apiKey}");
            var isAvailable = response.IsSuccessStatusCode;
            
            Logger.Info("Gemini connection test: {Status}", isAvailable ? "SUCCESS" : "FAILED");
            return isAvailable;
        }
        catch (Exception ex)
        {
            Logger.Warn(ex, "Gemini connection failed");
            return false;
        }
    }
    
    public async Task<string> GenerateAsync(string prompt, AiGenerationOptions options)
    {
        Logger.Info("Generating AI response via Gemini (model: {Model})", options.Model ?? "gemini-2.0-flash-exp");
        Logger.Debug("Prompt length: {Length} characters", prompt.Length);
        
        try
        {
            var modelName = options.Model ?? "gemini-2.0-flash-exp";
            
            var requestBody = new
            {
                contents = new[]
                {
                    new
                    {
                        parts = new[]
                        {
                            new { text = prompt }
                        }
                    }
                },
                generationConfig = new
                {
                    temperature = options.Temperature,
                    topP = options.TopP,
                    topK = options.TopK,
                    maxOutputTokens = options.MaxTokens
                }
            };
            
            var json = JsonSerializer.Serialize(requestBody);
            var content = new StringContent(json, Encoding.UTF8, "application/json");
            
            var url = $"{_baseUrl}/models/{modelName}:generateContent?key={_apiKey}";
            Logger.Debug("Sending request to Gemini: {Url}", url);
            
            var response = await _httpClient.PostAsync(url, content);
            response.EnsureSuccessStatusCode();
            
            var responseJson = await response.Content.ReadAsStringAsync();
            var result = JsonSerializer.Deserialize<GeminiResponse>(responseJson);
            
            var generatedText = result?.candidates?.FirstOrDefault()?.content?.parts?.FirstOrDefault()?.text ?? string.Empty;
            
            Logger.Info("Gemini response received: {Length} characters", generatedText.Length);
            return generatedText;
        }
        catch (HttpRequestException ex) when (ex.Message.Contains("400") || ex.Message.Contains("401"))
        {
            Logger.Error("Gemini authentication failed - invalid API key");
            return "Error: Invalid API key. Please check your Gemini API key in Settings.";
        }
        catch (Exception ex)
        {
            Logger.Error(ex, "Failed to generate AI response via Gemini");
            return $"Error: {ex.Message}";
        }
    }
    
    public async Task<List<string>> GetAvailableModelsAsync()
    {
        Logger.Debug("Fetching available Gemini models");
        
        try
        {
            var response = await _httpClient.GetAsync($"{_baseUrl}/models?key={_apiKey}");
            response.EnsureSuccessStatusCode();
            
            var responseJson = await response.Content.ReadAsStringAsync();
            var result = JsonSerializer.Deserialize<GeminiModelsResponse>(responseJson);
            
            var models = result?.models?
                .Where(m => m.name != null && m.name.Contains("gemini") && !m.name.Contains("vision"))
                .Select(m => m.name!.Replace("models/", ""))
                .ToList() ?? new List<string>();
            
            Logger.Info("Found {Count} Gemini models: {Models}", models.Count, string.Join(", ", models));
            return models;
        }
        catch (Exception ex)
        {
            Logger.Error(ex, "Failed to fetch Gemini models");
            return new List<string> { "gemini-2.0-flash-exp", "gemini-1.5-pro", "gemini-1.5-flash" };
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
                status.SelectedModel = "gemini-2.0-flash-exp";
                status.StatusMessage = $"✅ Connected - {status.AvailableModels.Count} model(s) available";
            }
            else
            {
                status.StatusMessage = "❌ Authentication failed. Check API key.";
                status.ErrorMessage = "Invalid or missing API key";
            }
        }
        catch (Exception ex)
        {
            Logger.Error(ex, "Failed to get Gemini status");
            status.IsAvailable = false;
            status.StatusMessage = "❌ Error checking Gemini status";
            status.ErrorMessage = ex.Message;
        }
        
        return status;
    }
}

// Gemini API response models
internal class GeminiResponse
{
    public List<GeminiCandidate>? candidates { get; set; }
}

internal class GeminiCandidate
{
    public GeminiContent? content { get; set; }
}

internal class GeminiContent
{
    public List<GeminiPart>? parts { get; set; }
}

internal class GeminiPart
{
    public string? text { get; set; }
}

internal class GeminiModelsResponse
{
    public List<GeminiModelInfo>? models { get; set; }
}

internal class GeminiModelInfo
{
    public string? name { get; set; }
    public string? displayName { get; set; }
}

