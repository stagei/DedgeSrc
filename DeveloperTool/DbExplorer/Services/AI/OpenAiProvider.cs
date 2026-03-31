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
/// OpenAI provider (GPT-4o, GPT-4o-mini, GPT-3.5-turbo).
/// Requires API key. Data sent to OpenAI servers.
/// </summary>
public class OpenAiProvider : IAiProvider
{
    private static readonly Logger Logger = LogManager.GetCurrentClassLogger();
    private readonly HttpClient _httpClient;
    private readonly string _apiKey;
    private readonly string _baseUrl = "https://api.openai.com/v1";
    
    public string ProviderName => "OpenAI";
    public string DisplayName => "☁️ OpenAI (GPT-4o)";
    public bool RequiresApiKey => true;
    public bool IsLocal => false;
    
    public OpenAiProvider(string apiKey)
    {
        _apiKey = apiKey;
        _httpClient = new HttpClient
        {
            Timeout = TimeSpan.FromMinutes(5)
        };
        _httpClient.DefaultRequestHeaders.Authorization = 
            new AuthenticationHeaderValue("Bearer", _apiKey);
        
        Logger.Debug("OpenAiProvider initialized");
    }
    
    public async Task<bool> TestConnectionAsync()
    {
        Logger.Debug("Testing OpenAI connection");
        
        try
        {
            var response = await _httpClient.GetAsync($"{_baseUrl}/models");
            var isAvailable = response.IsSuccessStatusCode;
            
            Logger.Info("OpenAI connection test: {Status}", isAvailable ? "SUCCESS" : "FAILED");
            return isAvailable;
        }
        catch (Exception ex)
        {
            Logger.Warn(ex, "OpenAI connection failed");
            return false;
        }
    }
    
    public async Task<string> GenerateAsync(string prompt, AiGenerationOptions options)
    {
        Logger.Info("Generating AI response via OpenAI (model: {Model})", options.Model ?? "gpt-4o-mini");
        Logger.Debug("Prompt length: {Length} characters", prompt.Length);
        
        try
        {
            var requestBody = new
            {
                model = options.Model ?? "gpt-4o-mini",
                messages = new[]
                {
                    new { role = "system", content = "You are an expert database administrator and SQL specialist." },
                    new { role = "user", content = prompt }
                },
                temperature = options.Temperature,
                max_tokens = options.MaxTokens,
                top_p = options.TopP
            };
            
            var json = JsonSerializer.Serialize(requestBody);
            var content = new StringContent(json, Encoding.UTF8, "application/json");
            
            Logger.Debug("Sending request to OpenAI: {Url}/chat/completions", _baseUrl);
            var response = await _httpClient.PostAsync($"{_baseUrl}/chat/completions", content);
            response.EnsureSuccessStatusCode();
            
            var responseJson = await response.Content.ReadAsStringAsync();
            var result = JsonSerializer.Deserialize<OpenAiChatResponse>(responseJson);
            
            var generatedText = result?.choices?.FirstOrDefault()?.message?.content ?? string.Empty;
            
            Logger.Info("OpenAI response received: {Length} characters", generatedText.Length);
            return generatedText;
        }
        catch (HttpRequestException ex) when (ex.Message.Contains("401"))
        {
            Logger.Error("OpenAI authentication failed - invalid API key");
            return "Error: Invalid API key. Please check your OpenAI API key in Settings.";
        }
        catch (Exception ex)
        {
            Logger.Error(ex, "Failed to generate AI response via OpenAI");
            return $"Error: {ex.Message}";
        }
    }
    
    public async Task<List<string>> GetAvailableModelsAsync()
    {
        Logger.Debug("Fetching available OpenAI models");
        
        try
        {
            var response = await _httpClient.GetAsync($"{_baseUrl}/models");
            response.EnsureSuccessStatusCode();
            
            var responseJson = await response.Content.ReadAsStringAsync();
            var result = JsonSerializer.Deserialize<OpenAiModelsResponse>(responseJson);
            
            var models = result?.data?
                .Where(m => m.id != null && (m.id.Contains("gpt") || m.id.Contains("text")))
                .Select(m => m.id!)
                .OrderByDescending(m => m.Contains("gpt-4o"))
                .ToList() ?? new List<string>();
            
            Logger.Info("Found {Count} OpenAI models", models.Count);
            return models;
        }
        catch (Exception ex)
        {
            Logger.Error(ex, "Failed to fetch OpenAI models");
            return new List<string> { "gpt-4o-mini", "gpt-4o", "gpt-3.5-turbo" };
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
                status.SelectedModel = "gpt-4o-mini";
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
            Logger.Error(ex, "Failed to get OpenAI status");
            status.IsAvailable = false;
            status.StatusMessage = "❌ Error checking OpenAI status";
            status.ErrorMessage = ex.Message;
        }
        
        return status;
    }
}

