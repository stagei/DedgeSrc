using NLog;
using System;
using System.Collections.Generic;
using System.IO;
using System.Linq;
using System.Text.Json;
using System.Text.Json.Serialization;
using System.Threading.Tasks;

namespace DbExplorer.Services;

/// <summary>
/// Loads IntelliSense metadata from provider-specific JSON files.
/// Supports DB2, PostgreSQL, SQL Server, Oracle, MySQL, etc.
/// </summary>
public class IntelliSenseDataLoader
{
    private static readonly Logger Logger = LogManager.GetCurrentClassLogger();
    private static readonly Dictionary<string, IntelliSenseMetadata> _cache = new();
    
    /// <summary>
    /// Load IntelliSense metadata for a specific provider and version.
    /// </summary>
    /// <param name="provider">Database provider (e.g., "DB2", "PostgreSQL")</param>
    /// <param name="version">Provider version (e.g., "12.1", "16")</param>
    /// <returns>IntelliSense metadata or null if not found</returns>
    public async Task<IntelliSenseMetadata?> LoadAsync(string provider, string version)
    {
        var cacheKey = $"{provider}_{version}".ToUpperInvariant();
        
        if (_cache.TryGetValue(cacheKey, out var cached))
        {
            Logger.Debug("Returning cached IntelliSense metadata for {Provider} {Version}", provider, version);
            return cached;
        }
        
        var fileName = $"{provider.ToLowerInvariant()}_{version}_intellisense.json";
        var filePath = Path.Combine(AppDomain.CurrentDomain.BaseDirectory, "ConfigFiles", fileName);
        
        if (!File.Exists(filePath))
        {
            Logger.Warn("IntelliSense file not found: {Path}", filePath);
            return null;
        }
        
        try
        {
            var json = await File.ReadAllTextAsync(filePath);
            var options = new JsonSerializerOptions
            {
                PropertyNameCaseInsensitive = true,
                ReadCommentHandling = JsonCommentHandling.Skip
            };
            
            var metadata = JsonSerializer.Deserialize<IntelliSenseMetadata>(json, options);
            
            if (metadata != null)
            {
                _cache[cacheKey] = metadata;
                Logger.Info("Loaded IntelliSense metadata for {Provider} {Version}: " +
                           "{Keywords} keywords, {DataTypes} data types, {Functions} functions",
                           provider, version,
                           metadata.GetAllKeywords().Count,
                           metadata.GetAllDataTypes().Count,
                           metadata.GetAllFunctions().Count);
            }
            
            return metadata;
        }
        catch (Exception ex)
        {
            Logger.Error(ex, "Failed to load IntelliSense metadata from {Path}", filePath);
            return null;
        }
    }
    
    /// <summary>
    /// Clear the metadata cache.
    /// </summary>
    public void ClearCache()
    {
        _cache.Clear();
        Logger.Debug("IntelliSense metadata cache cleared");
    }
    
    /// <summary>
    /// Get list of available providers.
    /// </summary>
    public List<string> GetAvailableProviders()
    {
        var configPath = Path.Combine(AppDomain.CurrentDomain.BaseDirectory, "ConfigFiles");
        if (!Directory.Exists(configPath))
            return new List<string>();
        
        return Directory.GetFiles(configPath, "*_intellisense.json")
            .Select(f => Path.GetFileNameWithoutExtension(f).Split('_')[0].ToUpperInvariant())
            .Distinct()
            .ToList();
    }
}

#region IntelliSense Metadata Models

/// <summary>
/// Root metadata structure for provider IntelliSense.
/// </summary>
public class IntelliSenseMetadata
{
    public string Provider { get; set; } = string.Empty;
    public string Version { get; set; } = string.Empty;
    public string Description { get; set; } = string.Empty;
    
    public KeywordCategories? Keywords { get; set; }
    public DataTypeCategories? DataTypes { get; set; }
    public FunctionCategories? Functions { get; set; }
    public Dictionary<string, List<string>>? SystemCatalog { get; set; }
    public Dictionary<string, SnippetDefinition>? Snippets { get; set; }
    public List<string>? SystemSchemas { get; set; }
    public List<string>? SpecialValues { get; set; }
    
    /// <summary>
    /// Get all keywords as a flat list.
    /// </summary>
    public List<string> GetAllKeywords()
    {
        var all = new List<string>();
        if (Keywords != null)
        {
            if (Keywords.Statements != null) all.AddRange(Keywords.Statements);
            if (Keywords.Clauses != null) all.AddRange(Keywords.Clauses);
            if (Keywords.Operators != null) all.AddRange(Keywords.Operators);
            if (Keywords.Modifiers != null) all.AddRange(Keywords.Modifiers);
            if (Keywords.Constraints != null) all.AddRange(Keywords.Constraints);
        }
        return all.Distinct().ToList();
    }
    
    /// <summary>
    /// Get all data types as a flat list.
    /// </summary>
    public List<string> GetAllDataTypes()
    {
        var all = new List<string>();
        if (DataTypes != null)
        {
            if (DataTypes.Numeric != null) all.AddRange(DataTypes.Numeric);
            if (DataTypes.String != null) all.AddRange(DataTypes.String);
            if (DataTypes.Binary != null) all.AddRange(DataTypes.Binary);
            if (DataTypes.Datetime != null) all.AddRange(DataTypes.Datetime);
            if (DataTypes.Special != null) all.AddRange(DataTypes.Special);
        }
        return all.Distinct().ToList();
    }
    
    /// <summary>
    /// Get all functions as a flat list.
    /// </summary>
    public List<string> GetAllFunctions()
    {
        var all = new List<string>();
        if (Functions != null)
        {
            if (Functions.Aggregate != null) all.AddRange(Functions.Aggregate);
            if (Functions.String != null) all.AddRange(Functions.String);
            if (Functions.Numeric != null) all.AddRange(Functions.Numeric);
            if (Functions.Datetime != null) all.AddRange(Functions.Datetime);
            if (Functions.Conversion != null) all.AddRange(Functions.Conversion);
            if (Functions.Window != null) all.AddRange(Functions.Window);
            if (Functions.Xml != null) all.AddRange(Functions.Xml);
            if (Functions.Json != null) all.AddRange(Functions.Json);
            if (Functions.System != null) all.AddRange(Functions.System);
        }
        return all.Distinct().ToList();
    }
    
    /// <summary>
    /// Get all system catalog tables as a flat list (with schema prefix).
    /// </summary>
    public List<string> GetAllSystemTables()
    {
        var all = new List<string>();
        if (SystemCatalog != null)
        {
            foreach (var (schema, tables) in SystemCatalog)
            {
                all.AddRange(tables.Select(t => $"{schema}.{t}"));
            }
        }
        return all;
    }
}

/// <summary>
/// Keyword categories.
/// </summary>
public class KeywordCategories
{
    public List<string>? Statements { get; set; }
    public List<string>? Clauses { get; set; }
    public List<string>? Operators { get; set; }
    public List<string>? Modifiers { get; set; }
    public List<string>? Constraints { get; set; }
}

/// <summary>
/// Data type categories.
/// </summary>
public class DataTypeCategories
{
    public List<string>? Numeric { get; set; }
    public List<string>? String { get; set; }
    public List<string>? Binary { get; set; }
    public List<string>? Datetime { get; set; }
    public List<string>? Special { get; set; }
}

/// <summary>
/// Function categories.
/// </summary>
public class FunctionCategories
{
    public List<string>? Aggregate { get; set; }
    public List<string>? String { get; set; }
    public List<string>? Numeric { get; set; }
    public List<string>? Datetime { get; set; }
    public List<string>? Conversion { get; set; }
    public List<string>? Window { get; set; }
    public List<string>? Xml { get; set; }
    public List<string>? Json { get; set; }
    public List<string>? System { get; set; }
}

/// <summary>
/// Snippet definition.
/// </summary>
public class SnippetDefinition
{
    public string Trigger { get; set; } = string.Empty;
    public string Template { get; set; } = string.Empty;
    public string Description { get; set; } = string.Empty;
}

#endregion
