using System;
using System.Collections.Generic;
using System.Data;
using System.IO;
using System.Linq;
using System.Text.Json;
using System.Threading.Tasks;
using NLog;
using DbExplorer.Data;
using DbExplorer.Models;
using DbExplorer.Services.Interfaces;

namespace DbExplorer.Services;

/// <summary>
/// Centralized handler for all ConfigFiles-based metadata.
/// Loads SQL statements, UI text, and provider information at startup.
/// Implements IMetadataProvider for provider-agnostic architecture.
/// </summary>
public class MetadataHandler : IMetadataProvider
{
    private static readonly Logger Logger = LogManager.GetCurrentClassLogger();
    private readonly string _configFilesPath;
    
    private SupportedProvidersFile? _providersFile;
    private readonly Dictionary<string, SqlStatementsFile> _sqlStatementsCache = new();
    private readonly Dictionary<string, TextsFile> _textsCache = new();
    
    private string _userLanguagePreference = "en-US"; // Default language
    
    /// <summary>
    /// Initializes the MetadataHandler and loads all ConfigFiles
    /// </summary>
    public MetadataHandler()
    {
        // ConfigFiles are in the same directory as the executable
        _configFilesPath = Path.Combine(AppDomain.CurrentDomain.BaseDirectory, "ConfigFiles");
        Logger.Info("MetadataHandler initialized. ConfigFiles path: {Path}", _configFilesPath);
        
        LoadAllMetadata();
    }
    
    /// <summary>
    /// Load all metadata from ConfigFiles
    /// </summary>
    private void LoadAllMetadata()
    {
        Logger.Info("Loading all metadata from ConfigFiles");
        var stopwatch = System.Diagnostics.Stopwatch.StartNew();
        
        try
        {
            // Step 1: Load supported providers
            _providersFile = LoadSupportedProviders();
            Logger.Info("Loaded {Count} providers", _providersFile?.Providers.Count ?? 0);
            
            if (_providersFile == null || _providersFile.Providers.Count == 0)
            {
                Logger.Error("No providers loaded from supported_providers.json");
                return;
            }
            
            // Step 2: For each provider and version, load metadata
            foreach (var provider in _providersFile.Providers)
            {
                Logger.Debug("Loading metadata for provider: {Provider}", provider.ProviderCode);
                
                foreach (var version in provider.SupportedVersions)
                {
                    LoadProviderVersionMetadata(provider.ProviderCode, version);
                }
            }
            
            stopwatch.Stop();
            Logger.Info("All metadata loaded successfully in {Ms}ms", stopwatch.ElapsedMilliseconds);
        }
        catch (Exception ex)
        {
            Logger.Error(ex, "Failed to load metadata");
            throw;
        }
    }
    
    /// <summary>
    /// Load supported_providers.json
    /// </summary>
    private SupportedProvidersFile? LoadSupportedProviders()
    {
        var filePath = Path.Combine(_configFilesPath, "supported_providers.json");
        Logger.Debug("Loading supported providers from: {Path}", filePath);
        
        if (!File.Exists(filePath))
        {
            Logger.Error("supported_providers.json not found at {Path}", filePath);
            throw new FileNotFoundException("supported_providers.json not found", filePath);
        }
        
        try
        {
            var json = File.ReadAllText(filePath);
            var data = JsonSerializer.Deserialize<SupportedProvidersFile>(json);
            
            if (data == null)
            {
                Logger.Error("Failed to deserialize supported_providers.json");
                return null;
            }
            
            Logger.Debug("Loaded {Count} providers from supported_providers.json", data.Providers.Count);
            return data;
        }
        catch (Exception ex)
        {
            Logger.Error(ex, "Error loading supported_providers.json");
            throw;
        }
    }
    
    /// <summary>
    /// Load all metadata files for a specific provider and version
    /// </summary>
    private void LoadProviderVersionMetadata(string provider, string version)
    {
        Logger.Debug("Loading metadata for {Provider} {Version}", provider, version);
        
        var key = $"{provider}_{version}";
        
        // Load SQL statements
        var sqlStatementsFile = $"{provider.ToLower()}_{version}_sql_statements.json";
        var sqlStatementsPath = Path.Combine(_configFilesPath, sqlStatementsFile);
        if (File.Exists(sqlStatementsPath))
        {
            try
            {
                var json = File.ReadAllText(sqlStatementsPath);
                var data = JsonSerializer.Deserialize<SqlStatementsFile>(json);
                if (data != null)
                {
                    _sqlStatementsCache[key] = data;
                    Logger.Debug("Loaded {Count} SQL statements from: {File}", data.Statements.Count, sqlStatementsFile);
                }
            }
            catch (Exception ex)
            {
                Logger.Error(ex, "Error loading SQL statements file: {File}", sqlStatementsFile);
            }
        }
        else
        {
            Logger.Warn("SQL statements file not found: {File}", sqlStatementsFile);
        }
        
        // Load texts for user's preferred language
        LoadTextsForLanguage(provider, version, _userLanguagePreference);
        
        // Also load English as fallback if user's language is not English
        if (_userLanguagePreference != "en-US")
        {
            LoadTextsForLanguage(provider, version, "en-US");
        }
    }
    
    /// <summary>
    /// Load texts for a specific language
    /// </summary>
    private void LoadTextsForLanguage(string provider, string version, string languageCode)
    {
        var textsFile = $"{provider.ToLower()}_{version}_{languageCode}_texts.json";
        var textsPath = Path.Combine(_configFilesPath, textsFile);
        
        if (File.Exists(textsPath))
        {
            try
            {
                var json = File.ReadAllText(textsPath);
                var data = JsonSerializer.Deserialize<TextsFile>(json);
                if (data != null)
                {
                    var key = $"{provider}_{version}_{languageCode}";
                    _textsCache[key] = data;
                    Logger.Debug("Loaded {Count} texts from: {File}", data.Texts.Count, textsFile);
                }
            }
            catch (Exception ex)
            {
                Logger.Error(ex, "Error loading texts file: {File}", textsFile);
            }
        }
        else
        {
            Logger.Warn("Texts file not found: {File}", textsFile);
        }
    }
    
    /// <summary>
    /// Get SQL query by statement key
    /// </summary>
    /// <param name="provider">Provider code (e.g., "DB2")</param>
    /// <param name="version">Version (e.g., "12.1")</param>
    /// <param name="statementKey">Statement key (e.g., "GetTablesForSchema")</param>
    /// <returns>SQL query string</returns>
    public string GetQuery(string provider, string version, string statementKey)
    {
        var key = $"{provider}_{version}";
        
        Logger.Debug("GetQuery called: {Provider} {Version} {Key}", provider, version, statementKey);
        
        if (_sqlStatementsCache.TryGetValue(key, out var statementsFile))
        {
            if (statementsFile.Statements.TryGetValue(statementKey, out var statement))
            {
                Logger.Debug("Retrieved SQL: {Key} ({Length} chars)", statementKey, statement.Sql.Length);
                return statement.Sql;
            }
        }
        
        Logger.Error("SQL statement not found: {Provider} {Version} {Key}", provider, version, statementKey);
        throw new KeyNotFoundException($"SQL statement '{statementKey}' not found for {provider} {version}");
    }
    
    /// <summary>
    /// Get translated text by text key
    /// Attempts user's preferred language first, falls back to English
    /// </summary>
    /// <param name="provider">Provider code (e.g., "DB2")</param>
    /// <param name="version">Version (e.g., "12.1")</param>
    /// <param name="textKey">Text key (e.g., "ui.menu.file")</param>
    /// <returns>Translated text</returns>
    public string GetText(string provider, string version, string textKey)
    {
        Logger.Debug("GetText called: {Provider} {Version} {Key} [Language: {Lang}]", 
            provider, version, textKey, _userLanguagePreference);
        
        // Try user's preferred language
        var preferredKey = $"{provider}_{version}_{_userLanguagePreference}";
        if (_textsCache.TryGetValue(preferredKey, out var preferredTextsFile))
        {
            if (preferredTextsFile.Texts.TryGetValue(textKey, out var preferredText))
            {
                Logger.Debug("Retrieved text [{Language}]: {Key}", _userLanguagePreference, textKey);
                return preferredText;
            }
        }
        
        // Fallback to English
        var fallbackKey = $"{provider}_{version}_en-US";
        if (_textsCache.TryGetValue(fallbackKey, out var fallbackTextsFile))
        {
            if (fallbackTextsFile.Texts.TryGetValue(textKey, out var fallbackText))
            {
                Logger.Warn("Text not found in {Language}, using English fallback: {Key}", 
                    _userLanguagePreference, textKey);
                return fallbackText;
            }
        }
        
        // Last resort: return key itself
        Logger.Error("Text not found in any language: {Provider} {Version} {Key}", provider, version, textKey);
        return $"[{textKey}]";
    }
    
    /// <summary>
    /// Get translated text with parameter replacement
    /// </summary>
    /// <param name="provider">Provider code</param>
    /// <param name="version">Version</param>
    /// <param name="textKey">Text key</param>
    /// <param name="parameters">Object with properties to replace in placeholders</param>
    /// <returns>Formatted text with parameters replaced</returns>
    public string GetText(string provider, string version, string textKey, object parameters)
    {
        var text = GetText(provider, version, textKey);
        return FormatText(text, parameters);
    }
    
    /// <summary>
    /// Format text by replacing placeholders with values
    /// </summary>
    private string FormatText(string template, object parameters)
    {
        if (parameters == null) return template;
        
        var properties = parameters.GetType().GetProperties();
        foreach (var prop in properties)
        {
            var placeholder = $"{{{prop.Name}}}";
            var value = prop.GetValue(parameters)?.ToString() ?? string.Empty;
            template = template.Replace(placeholder, value);
        }
        
        return template;
    }
    
    /// <summary>
    /// Get list of supported providers
    /// </summary>
    public List<Provider> GetSupportedProviders()
    {
        Logger.Debug("GetSupportedProviders called");
        return _providersFile?.Providers ?? new List<Provider>();
    }
    
    /// <summary>
    /// Get all available languages for a provider/version
    /// </summary>
    public List<string> GetAvailableLanguages(string provider, string version)
    {
        var prefix = $"{provider}_{version}_";
        var languages = _textsCache.Keys
            .Where(k => k.StartsWith(prefix))
            .Select(k => k.Substring(prefix.Length))
            .ToList();
        
        Logger.Debug("GetAvailableLanguages: {Provider} {Version} → {Count} languages", 
            provider, version, languages.Count);
        
        return languages;
    }
    
    /// <summary>
    /// Get all distinct language codes across all providers and versions
    /// </summary>
    public List<string> GetAllDistinctLanguages()
    {
        var languages = new HashSet<string>();
        
        foreach (var key in _textsCache.Keys)
        {
            // Extract language code from key: "DB2_12.1_en-US" → "en-US"
            var parts = key.Split('_');
            if (parts.Length >= 3)
            {
                var languageCode = parts[2]; // Simple case, works for "en-US"
                languages.Add(languageCode);
            }
        }
        
        var result = languages.OrderBy(l => l).ToList();
        Logger.Debug("GetAllDistinctLanguages: Found {Count} languages", result.Count);
        return result;
    }
    
    /// <summary>
    /// Change user's language preference and reload texts
    /// </summary>
    public void ChangeLanguage(string languageCode)
    {
        Logger.Info("Changing language from {Old} to {New}", _userLanguagePreference, languageCode);
        _userLanguagePreference = languageCode;
        
        // Reload texts for all providers and versions with new language
        if (_providersFile != null)
        {
            foreach (var provider in _providersFile.Providers)
            {
                foreach (var version in provider.SupportedVersions)
                {
                    LoadTextsForLanguage(provider.ProviderCode, version, languageCode);
                }
            }
        }
        
        Logger.Info("Language changed successfully");
    }
    
    // ========== IMetadataProvider Implementation ==========
    
    private string _currentProvider = "DB2";
    private string _currentVersion = "12.1";
    private IConnectionManager? _connectionManager;
    
    public void SetConnectionManager(IConnectionManager connectionManager)
    {
        _connectionManager = connectionManager;
        _currentProvider = connectionManager.ConnectionInfo.ProviderType?.ToUpperInvariant() ?? "DB2";
        _currentVersion = _currentProvider switch { "POSTGRESQL" => "18", "SQLITE" => "3", _ => "12.1" }; // TODO: Get version from connection or detect it
    }
    
    public string GetStatement(string statementName)
    {
        return GetQuery(_currentProvider, _currentVersion, statementName);
    }
    
    public string GetStatement(string statementName, string provider, string version)
    {
        return GetQuery(provider, version, statementName);
    }
    
    /// <summary>
    /// Get a required SQL statement. If the statement is missing, shows an error message
    /// and terminates the application.
    /// </summary>
    /// <param name="statementName">The statement key to retrieve</param>
    /// <returns>The SQL statement</returns>
    public string GetRequiredStatement(string statementName)
    {
        try
        {
            return GetStatement(statementName);
        }
        catch (KeyNotFoundException)
        {
            var message = $"Required SQL statement '{statementName}' is missing from configuration file.\n\n" +
                          $"Expected in: ConfigFiles/{_currentProvider.ToLower()}_{_currentVersion}_sql_statements.json\n\n" +
                          $"The application will now exit. Please add the missing statement to the configuration file.";
            
            Logger.Fatal("Missing required SQL statement: {StatementName}", statementName);
            
            System.Windows.MessageBox.Show(
                message,
                "Configuration Error - Missing SQL Statement",
                System.Windows.MessageBoxButton.OK,
                System.Windows.MessageBoxImage.Error);
            
            System.Windows.Application.Current.Shutdown(1);
            throw; // In case shutdown doesn't exit immediately
        }
    }
    
    public async Task<DataTable> ExecuteMetadataQueryAsync(string statementName, Dictionary<string, object> parameters)
    {
        if (_connectionManager == null)
        {
            throw new InvalidOperationException("Connection manager not set");
        }
        
        var sql = GetStatement(statementName);
        
        foreach (var param in parameters)
        {
            // Replace first occurrence of ? with parameter value
            var index = sql.IndexOf('?');
            if (index >= 0)
            {
                sql = sql.Substring(0, index) + $"'{param.Value}'" + sql.Substring(index + 1);
            }
        }
        
        return await _connectionManager.ExecuteQueryAsync(sql);
    }
    
    public async Task<object?> ExecuteScalarAsync(string statementName, Dictionary<string, object> parameters)
    {
        if (_connectionManager == null)
        {
            throw new InvalidOperationException("Connection manager not set");
        }
        
        var sql = GetStatement(statementName);
        
        foreach (var param in parameters)
        {
            // Replace first occurrence of ? with parameter value
            var index = sql.IndexOf('?');
            if (index >= 0)
            {
                sql = sql.Substring(0, index) + $"'{param.Value}'" + sql.Substring(index + 1);
            }
        }
        
        // Provider-agnostic command creation
        using var command = _connectionManager.CreateCommand(sql);
        return await command.ExecuteScalarAsync();
    }
    
    string IMetadataProvider.GetText(string key)
    {
        return GetText(_currentProvider, _currentVersion, key);
    }
    
    public string GetCurrentProvider()
    {
        return _currentProvider;
    }
    
    public string GetCurrentVersion()
    {
        return _currentVersion;
    }
    
    public bool IsFeatureSupported(string featureName)
    {
        return true;
    }
    
    List<string> IMetadataProvider.GetSupportedProviders()
    {
        return GetSupportedProviders().Select(p => p.ProviderCode).ToList();
    }
}

