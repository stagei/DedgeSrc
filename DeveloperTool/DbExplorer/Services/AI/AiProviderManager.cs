using NLog;
using System;
using System.Collections.Generic;
using System.Linq;
using System.Threading.Tasks;

namespace DbExplorer.Services.AI;

/// <summary>
/// Manager for all AI providers - handles provider registration, selection, and orchestration.
/// Prioritizes local providers (Ollama, LM Studio) over cloud providers.
/// </summary>
public class AiProviderManager
{
    private static readonly Logger Logger = LogManager.GetCurrentClassLogger();
    private readonly Dictionary<string, IAiProvider> _providers = new();
    private IAiProvider? _activeProvider;
    
    public AiProviderManager()
    {
        Logger.Info("AiProviderManager initialized");
    }
    
    /// <summary>
    /// Register all available providers.
    /// </summary>
    public void RegisterProviders(Dictionary<string, string> apiKeys)
    {
        Logger.Debug("Registering AI providers");
        
        // Local providers (NO API keys needed - RECOMMENDED)
        RegisterProvider(new OllamaProvider());
        RegisterProvider(new LmStudioProvider());
        
        // Cloud providers (API keys required)
        if (apiKeys.TryGetValue("OpenAI", out var openAiKey) && !string.IsNullOrWhiteSpace(openAiKey))
        {
            RegisterProvider(new OpenAiProvider(openAiKey));
        }
        
        if (apiKeys.TryGetValue("Claude", out var claudeKey) && !string.IsNullOrWhiteSpace(claudeKey))
        {
            RegisterProvider(new ClaudeProvider(claudeKey));
        }
        
        if (apiKeys.TryGetValue("Gemini", out var geminiKey) && !string.IsNullOrWhiteSpace(geminiKey))
        {
            RegisterProvider(new GeminiProvider(geminiKey));
        }
        
        Logger.Info("Registered {Count} AI provider(s)", _providers.Count);
    }
    
    /// <summary>
    /// Register a single provider.
    /// </summary>
    public void RegisterProvider(IAiProvider provider)
    {
        _providers[provider.ProviderName] = provider;
        Logger.Debug("Registered provider: {Provider}", provider.DisplayName);
    }
    
    /// <summary>
    /// Get all registered providers.
    /// </summary>
    public List<IAiProvider> GetAllProviders()
    {
        return _providers.Values.ToList();
    }
    
    /// <summary>
    /// Get active provider (or auto-select best available).
    /// Priority: Ollama > LM Studio > OpenAI > Claude > Gemini
    /// </summary>
    public async Task<IAiProvider?> GetActiveProviderAsync()
    {
        if (_activeProvider != null)
        {
            Logger.Debug("Using already-active provider: {Provider}", _activeProvider.DisplayName);
            return _activeProvider;
        }
        
        Logger.Info("Auto-selecting best available AI provider");
        
        // Priority 1: Ollama (local, free, private)
        if (_providers.TryGetValue("Ollama", out var ollama))
        {
            if (await ollama.TestConnectionAsync())
            {
                _activeProvider = ollama;
                Logger.Info("✅ Selected Ollama (local, recommended)");
                return _activeProvider;
            }
        }
        
        // Priority 2: LM Studio (local, free, private)
        if (_providers.TryGetValue("LMStudio", out var lmStudio))
        {
            if (await lmStudio.TestConnectionAsync())
            {
                _activeProvider = lmStudio;
                Logger.Info("✅ Selected LM Studio (local)");
                return _activeProvider;
            }
        }
        
        // Priority 3: Cloud providers (require API keys)
        var cloudProviders = new[] { "OpenAI", "Claude", "Gemini" };
        foreach (var providerName in cloudProviders)
        {
            if (_providers.TryGetValue(providerName, out var provider))
            {
                if (await provider.TestConnectionAsync())
                {
                    _activeProvider = provider;
                    Logger.Info("✅ Selected {Provider} (cloud)", providerName);
                    return _activeProvider;
                }
            }
        }
        
        Logger.Warn("❌ No AI providers available - install Ollama from https://ollama.com");
        return null;
    }
    
    /// <summary>
    /// Set active provider by name.
    /// </summary>
    public async Task<bool> SetActiveProviderAsync(string providerName)
    {
        Logger.Info("Attempting to set active provider: {Provider}", providerName);
        
        if (!_providers.TryGetValue(providerName, out var provider))
        {
            Logger.Error("Provider not found: {Provider}", providerName);
            return false;
        }
        
        var isAvailable = await provider.TestConnectionAsync();
        if (isAvailable)
        {
            _activeProvider = provider;
            Logger.Info("✅ Active provider set to: {Provider}", provider.DisplayName);
            return true;
        }
        
        Logger.Warn("Provider unavailable: {Provider}", provider.DisplayName);
        return false;
    }
    
    /// <summary>
    /// Generate AI response using active provider.
    /// </summary>
    public async Task<string> GenerateAsync(string prompt, AiGenerationOptions? options = null)
    {
        var provider = await GetActiveProviderAsync();
        
        if (provider == null)
        {
            Logger.Error("No AI provider available");
            return "Error: No AI provider available. Please install Ollama (https://ollama.com) or configure an API key in Settings.";
        }
        
        options ??= new AiGenerationOptions();
        
        Logger.Info("Generating AI response via {Provider}", provider.DisplayName);
        return await provider.GenerateAsync(prompt, options);
    }
    
    /// <summary>
    /// Get status of all providers.
    /// </summary>
    public async Task<Dictionary<string, ProviderStatus>> GetAllProviderStatusAsync()
    {
        Logger.Debug("Fetching status for all providers");
        
        var statuses = new Dictionary<string, ProviderStatus>();
        
        foreach (var provider in _providers.Values)
        {
            var status = await provider.GetStatusAsync();
            statuses[provider.ProviderName] = status;
            
            Logger.Debug("Provider {Provider} status: {Status}", 
                provider.DisplayName, status.IsAvailable ? "Available" : "Unavailable");
        }
        
        return statuses;
    }
    
    /// <summary>
    /// Check if any provider is available.
    /// </summary>
    public async Task<bool> IsAnyProviderAvailableAsync()
    {
        var provider = await GetActiveProviderAsync();
        return provider != null;
    }
}

