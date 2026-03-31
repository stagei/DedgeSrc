using System.Collections.Generic;
using System.Threading.Tasks;

namespace DbExplorer.Services.AI;

/// <summary>
/// Interface for AI providers (Ollama, OpenAI, Claude, Gemini, LM Studio).
/// </summary>
public interface IAiProvider
{
    /// <summary>
    /// Provider name (e.g., "Ollama", "OpenAI").
    /// </summary>
    string ProviderName { get; }
    
    /// <summary>
    /// Display name for UI (e.g., "Ollama (Local)", "OpenAI (GPT-4o)").
    /// </summary>
    string DisplayName { get; }
    
    /// <summary>
    /// Does this provider require an API key?
    /// </summary>
    bool RequiresApiKey { get; }
    
    /// <summary>
    /// Is this a local provider (data never leaves PC)?
    /// </summary>
    bool IsLocal { get; }
    
    /// <summary>
    /// Test if provider is available and reachable.
    /// </summary>
    Task<bool> TestConnectionAsync();
    
    /// <summary>
    /// Generate AI response from prompt.
    /// </summary>
    Task<string> GenerateAsync(string prompt, AiGenerationOptions options);
    
    /// <summary>
    /// Get list of available models for this provider.
    /// </summary>
    Task<List<string>> GetAvailableModelsAsync();
    
    /// <summary>
    /// Get provider status information.
    /// </summary>
    Task<ProviderStatus> GetStatusAsync();
}

/// <summary>
/// AI generation options.
/// </summary>
public class AiGenerationOptions
{
    public string? Model { get; set; }
    public double Temperature { get; set; } = 0.7;
    public int MaxTokens { get; set; } = 2000;
    public bool Stream { get; set; } = false;
    public double TopP { get; set; } = 0.9;
    public int TopK { get; set; } = 40;
}

/// <summary>
/// Provider status information.
/// </summary>
public class ProviderStatus
{
    public bool IsAvailable { get; set; }
    public bool IsConnected { get; set; }
    public string StatusMessage { get; set; } = string.Empty;
    public List<string> AvailableModels { get; set; } = new();
    public string? SelectedModel { get; set; }
    public string? ErrorMessage { get; set; }
}

