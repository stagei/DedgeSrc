using NLog;
using System;
using System.Collections.Generic;
using System.IO;
using System.Linq;
using System.Text.Json;
using System.Threading.Tasks;
using DbExplorer.Data;
using DbExplorer.Models;
using ICSharpCode.AvalonEdit.CodeCompletion;

namespace DbExplorer.Services;

/// <summary>
/// Manages provider-specific IntelliSense and orchestrates completion providers.
/// </summary>
public class IntelliSenseManager
{
    private static readonly Logger Logger = LogManager.GetCurrentClassLogger();
    
    private readonly Dictionary<string, IIntelliSenseProvider> _providers = new();
    private IIntelliSenseProvider? _activeProvider;
    private string? _currentProviderName;
    private string? _currentVersion;
    
    public IntelliSenseManager()
    {
        Logger.Debug("IntelliSenseManager initialized");
    }
    
    /// <summary>
    /// Registers a provider for a specific database type.
    /// </summary>
    public void RegisterProvider(string providerName, IIntelliSenseProvider provider)
    {
        _providers[providerName] = provider;
        Logger.Info("Registered IntelliSense provider: {Provider}", providerName);
    }
    
    /// <summary>
    /// Sets the active provider based on connection info.
    /// </summary>
    public async Task SetActiveProviderAsync(string providerName, string version, IConnectionManager? connection)
    {
        Logger.Debug("Setting active provider: {Provider} {Version}", providerName, version);
        
        _currentProviderName = providerName;
        _currentVersion = version;
        
        if (!_providers.ContainsKey(providerName))
        {
            Logger.Warn("Provider not registered: {Provider}, creating default DB2 provider", providerName);
            RegisterProvider(providerName, new Db2IntelliSenseProvider());
        }
        
        _activeProvider = _providers[providerName];
        
        // Load metadata for this provider
        try
        {
            var baseDir = AppDomain.CurrentDomain.BaseDirectory;
            var keywordsFile = Path.Combine(baseDir, "ConfigFiles", $"{providerName}_{version}_keywords.json");
            var statementsFile = Path.Combine(baseDir, "ConfigFiles", $"{providerName}_{version}_sql_statements.json");
            var metadataFile = Path.Combine(baseDir, "ConfigFiles", $"{providerName}_{version}_system_metadata.json");
            
            Logger.Debug("Loading IntelliSense metadata from: {KeywordsFile}", keywordsFile);
            
            await _activeProvider.LoadMetadataAsync(keywordsFile, statementsFile, metadataFile);
            
            // Load live schema metadata if connection is available
            if (connection != null)
            {
                await _activeProvider.LoadLiveSchemaMetadataAsync(connection);
            }
            
            Logger.Info("Active provider set and metadata loaded: {Provider} {Version}", providerName, version);
        }
        catch (Exception ex)
        {
            Logger.Error(ex, "Failed to load metadata for provider: {Provider} {Version}", providerName, version);
        }
    }
    
    /// <summary>
    /// Gets completions for the current text and caret position.
    /// </summary>
    public List<ICompletionData> GetCompletions(string text, int caretPosition, IConnectionManager? connection)
    {
        if (_activeProvider == null)
        {
            Logger.Warn("No active IntelliSense provider");
            return new List<ICompletionData>();
        }
        
        Logger.Debug("Getting completions at position {Position}", caretPosition);
        
        var context = new CompletionContext
        {
            Text = text,
            CaretPosition = caretPosition,
            Connection = connection // Provider-agnostic
        };
        
        try
        {
            var completions = _activeProvider.GetCompletions(context);
            Logger.Debug("Generated {Count} completions", completions.Count);
            return completions;
        }
        catch (Exception ex)
        {
            Logger.Error(ex, "Failed to get completions");
            return new List<ICompletionData>();
        }
    }
    
    /// <summary>
    /// Gets function signature hints.
    /// </summary>
    public async Task<FunctionSignature?> GetSignatureHintAsync(string functionName)
    {
        if (_activeProvider == null)
        {
            return null;
        }
        
        return await _activeProvider.GetSignatureHintAsync(functionName);
    }
    
    /// <summary>
    /// Set a callback to trigger after schema/alias completion (to show tables/columns).
    /// </summary>
    public void SetCompletionCallback(Action? callback)
    {
        if (_activeProvider is SqlIntelliSenseProvider sqlProvider)
        {
            sqlProvider.SetCompletionCallback(callback);
            Logger.Debug("Completion callback set on SqlIntelliSenseProvider");
        }
    }
}

/// <summary>
/// Completion context passed to providers.
/// </summary>
public class CompletionContext
{
    public string Text { get; set; } = string.Empty;
    public int CaretPosition { get; set; }
    public IConnectionManager? Connection { get; set; }
}

/// <summary>
/// Interface for IntelliSense providers.
/// </summary>
public interface IIntelliSenseProvider
{
    Task LoadMetadataAsync(string keywordsFile, string statementsFile, string metadataFile);
    Task LoadLiveSchemaMetadataAsync(IConnectionManager connection);
    List<ICompletionData> GetCompletions(CompletionContext context);
    Task<FunctionSignature?> GetSignatureHintAsync(string functionName);
}

/// <summary>
/// Function signature information.
/// </summary>
public class FunctionSignature
{
    public string FunctionName { get; set; } = string.Empty;
    public List<FunctionParameter> Parameters { get; set; } = new();
    public string ReturnType { get; set; } = string.Empty;
    public string Description { get; set; } = string.Empty;
    
    public override string ToString()
    {
        var parameters = string.Join(", ", Parameters.Select(p => $"{p.Name} {p.DataType}"));
        return $"{FunctionName}({parameters}) → {ReturnType}";
    }
}

/// <summary>
/// Function parameter information.
/// </summary>
public class FunctionParameter
{
    public string Name { get; set; } = string.Empty;
    public string DataType { get; set; } = string.Empty;
    public string Mode { get; set; } = string.Empty; // IN, OUT, INOUT
}

