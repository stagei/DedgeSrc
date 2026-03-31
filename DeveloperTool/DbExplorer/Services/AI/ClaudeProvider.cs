using NLog;
using System;
using System.Collections.Generic;
using System.Linq;
using System.Net.Http;
using System.Net.Http.Headers;
using System.Text;
using System.Text.Json;
using System.Threading.Tasks;

namespace DbExplorer.Services.AI;

/// <summary>
/// Anthropic Claude provider (Claude 3.5 Sonnet, Claude 3 Opus).
/// Requires API key. Data sent to Anthropic servers.
/// </summary>
public class ClaudeProvider : IAiProvider
{
    private static readonly Logger Logger = LogManager.GetCurrentClassLogger();
    private readonly HttpClient _httpClient;
    private readonly string _apiKey;
    private readonly string _baseUrl = "https://api.anthropic.com/v1";
    
    public string ProviderName => "Claude";
    public string DisplayName => "☁️ Anthropic Claude";
    public bool RequiresApiKey => true;
    public bool IsLocal => false;
    
    public ClaudeProvider(string apiKey)
    {
        _apiKey = apiKey;
        _httpClient = new HttpClient
        {
            Timeout = TimeSpan.FromMinutes(5)
        };
        _httpClient.DefaultRequestHeaders.Add("x-api-key", _apiKey);
        _httpClient.DefaultRequestHeaders.Add("anthropic-version", "2023-06-01");
        
        Logger.Debug("ClaudeProvider initialized");
    }
    
    public async Task<bool> TestConnectionAsync()
    {
        Logger.Debug("Testing Claude connection");
        
        try
        {
            // Claude doesn't have a models endpoint, so test with a simple message
            var requestBody = new
            {
                model = "claude-3-5-sonnet-20241022",
                max_tokens = 10,
                messages = new[]
                {
                    new { role = "user", content = "Hi" }
                }
            };
            
            var json = JsonSerializer.Serialize(requestBody);
            var content = new StringContent(json, Encoding.UTF8, "application/json");
            
            var response = await _httpClient.PostAsync($"{_baseUrl}/messages", content);
            var isAvailable = response.IsSuccessStatusCode;
            
            Logger.Info("Claude connection test: {Status}", isAvailable ? "SUCCESS" : "FAILED");
            return isAvailable;
        }
        catch (Exception ex)
        {
            Logger.Warn(ex, "Claude connection failed");
            return false;
        }
    }
    
    public async Task<string> GenerateAsync(string prompt, AiGenerationOptions options)
    {
        Logger.Info("Generating AI response via Claude (model: {Model})", options.Model ?? "claude-3-5-sonnet-20241022");
        Logger.Debug("Prompt length: {Length} characters", prompt.Length);
        
        try
        {
            var requestBody = new
            {
                model = options.Model ?? "claude-3-5-sonnet-20241022",
                max_tokens = options.MaxTokens,
                temperature = options.Temperature,
                top_p = options.TopP,
                messages = new[]
                {
                    new { role = "user", content = prompt }
                }
            };
            
            var json = JsonSerializer.Serialize(requestBody);
            var content = new StringContent(json, Encoding.UTF8, "application/json");
            
            Logger.Debug("Sending request to Claude: {Url}/messages", _baseUrl);
            var response = await _httpClient.PostAsync($"{_baseUrl}/messages", content);
            response.EnsureSuccessStatusCode();
            
            var responseJson = await response.Content.ReadAsStringAsync();
            var result = JsonSerializer.Deserialize<ClaudeResponse>(responseJson);
            
            var generatedText = result?.content?.FirstOrDefault()?.text ?? string.Empty;
            
            Logger.Info("Claude response received: {Length} characters", generatedText.Length);
            return generatedText;
        }
        catch (HttpRequestException ex) when (ex.Message.Contains("401"))
        {
            Logger.Error("Claude authentication failed - invalid API key");
            return "Error: Invalid API key. Please check your Claude API key in Settings.";
        }
        catch (Exception ex)
        {
            Logger.Error(ex, "Failed to generate AI response via Claude");
            return $"Error: {ex.Message}";
        }
    }
    
    public async Task<List<string>> GetAvailableModelsAsync()
    {
        Logger.Debug("Returning hardcoded Claude models");
        
        // Claude doesn't expose a models endpoint publicly
        return new List<string>
        {
            "claude-3-5-sonnet-20241022",
            "claude-3-opus-20240229",
            "claude-3-sonnet-20240229",
            "claude-3-haiku-20240307"
        };
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
                status.SelectedModel = "claude-3-5-sonnet-20241022";
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
            Logger.Error(ex, "Failed to get Claude status");
            status.IsAvailable = false;
            status.StatusMessage = "❌ Error checking Claude status";
            status.ErrorMessage = ex.Message;
        }
        
        return status;
    }
}

// Claude API response models
internal class ClaudeResponse
{
    public List<ClaudeContent>? content { get; set; }
}

internal class ClaudeContent
{
    public string? type { get; set; }
    public string? text { get; set; }
}

