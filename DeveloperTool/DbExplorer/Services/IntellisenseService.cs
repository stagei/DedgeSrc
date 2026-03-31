using System;
using System.Collections.Generic;
using System.Linq;
using System.Threading.Tasks;
using NLog;
using DbExplorer.Models;

namespace DbExplorer.Services;

/// <summary>
/// Service for providing SQL intellisense suggestions
/// </summary>
public class IntellisenseService
{
    private static readonly Logger Logger = LogManager.GetCurrentClassLogger();
    private readonly MetadataHandler? _metadataHandler;
    private readonly string _provider;
    private readonly string _version;
    
    private List<string> _allKeywords = new();
    private Dictionary<string, List<string>> _keywordsByCategory = new();
    
    public IntellisenseService(string provider = "DB2", string version = "12.1", MetadataHandler? metadataHandler = null)
    {
        _provider = provider;
        _version = version;
        _metadataHandler = metadataHandler ?? App.MetadataHandler;
        
        Logger.Debug("IntellisenseService initialized - Provider: {Provider}, Version: {Version}", _provider, _version);
        
        LoadKeywords();
    }
    
    private void LoadKeywords()
    {
        try
        {
            // Load keywords from ConfigFiles
            var keywordsFile = System.IO.Path.Combine(
                AppDomain.CurrentDomain.BaseDirectory, 
                "ConfigFiles", 
                $"{_provider.ToLower()}_{_version}_keywords.json");
            
            if (System.IO.File.Exists(keywordsFile))
            {
                Logger.Debug("Loading keywords from: {File}", keywordsFile);
                var json = System.IO.File.ReadAllText(keywordsFile);
                var keywordsData = System.Text.Json.JsonSerializer.Deserialize<KeywordsFile>(json);
                
                if (keywordsData?.Keywords != null)
                {
                    // Flatten all keywords into a single list
                    foreach (var category in keywordsData.Keywords)
                    {
                        var keywords = System.Text.Json.JsonSerializer.Deserialize<List<string>>(category.Value.GetRawText()) 
                                      ?? new List<string>();
                        _keywordsByCategory[category.Key] = keywords;
                        _allKeywords.AddRange(keywords);
                    }
                    
                    Logger.Info("Loaded {Count} keywords across {Categories} categories", 
                               _allKeywords.Count, _keywordsByCategory.Count);
                }
            }
            else
            {
                Logger.Warn("Keywords file not found: {File}", keywordsFile);
                LoadDefaultKeywords();
            }
        }
        catch (Exception ex)
        {
            Logger.Error(ex, "Failed to load keywords, using defaults");
            LoadDefaultKeywords();
        }
    }
    
    private void LoadDefaultKeywords()
    {
        // Fallback default keywords
        _allKeywords = new List<string>
        {
            "SELECT", "FROM", "WHERE", "INSERT", "UPDATE", "DELETE",
            "JOIN", "LEFT JOIN", "RIGHT JOIN", "INNER JOIN",
            "GROUP BY", "ORDER BY", "HAVING",
            "CREATE", "ALTER", "DROP", "TABLE", "VIEW", "INDEX",
            "AND", "OR", "NOT", "IN", "EXISTS", "BETWEEN", "LIKE",
            "COUNT", "SUM", "AVG", "MIN", "MAX", "TRIM",
            "SYSCAT.TABLES", "SYSCAT.COLUMNS", "SYSCAT.VIEWS"
        };
        
        Logger.Info("Loaded {Count} default keywords", _allKeywords.Count);
    }
    
    /// <summary>
    /// Get intellisense suggestions based on partial input
    /// </summary>
    public List<IntellisenseSuggestion> GetSuggestions(string partialText, string? category = null)
    {
        if (string.IsNullOrWhiteSpace(partialText))
        {
            return new List<IntellisenseSuggestion>();
        }
        
        var suggestions = new List<IntellisenseSuggestion>();
        var searchText = partialText.ToUpperInvariant();
        
        // Filter keywords by category if specified
        var keywordsToSearch = string.IsNullOrEmpty(category)
            ? _allKeywords
            : _keywordsByCategory.GetValueOrDefault(category, _allKeywords);
        
        // Find matching keywords
        var matches = keywordsToSearch
            .Where(k => k.ToUpperInvariant().StartsWith(searchText))
            .OrderBy(k => k.Length)
            .Take(20)
            .ToList();
        
        foreach (var match in matches)
        {
            suggestions.Add(new IntellisenseSuggestion
            {
                Text = match,
                DisplayText = match,
                Description = GetKeywordDescription(match),
                Type = GetSuggestionType(match),
                Priority = CalculatePriority(match, searchText)
            });
        }
        
        Logger.Debug("Found {Count} suggestions for '{Text}'", suggestions.Count, partialText);
        return suggestions;
    }
    
    /// <summary>
    /// Get suggestions for table/column names from metadata
    /// </summary>
    public async Task<List<IntellisenseSuggestion>> GetSchemaObjectSuggestionsAsync(
        string partialText, 
        string objectType = "TABLE")
    {
        var suggestions = new List<IntellisenseSuggestion>();
        
        // This would query the database for actual schema objects
        // For now, return common system tables
        if (objectType.ToUpperInvariant() == "TABLE")
        {
            var systemTables = _keywordsByCategory.GetValueOrDefault("system_tables", new List<string>());
            var searchText = partialText.ToUpperInvariant();
            
            var matches = systemTables
                .Where(t => t.ToUpperInvariant().Contains(searchText))
                .Take(10)
                .ToList();
            
            foreach (var match in matches)
            {
                suggestions.Add(new IntellisenseSuggestion
                {
                    Text = match,
                    DisplayText = match,
                    Description = "System catalog table",
                    Type = IntellisenseType.Table,
                    Priority = 5
                });
            }
        }
        
        return suggestions;
    }
    
    private string GetKeywordDescription(string keyword)
    {
        // Find which category this keyword belongs to
        foreach (var category in _keywordsByCategory)
        {
            if (category.Value.Contains(keyword))
            {
                return $"{category.Key.Replace("_", " ").ToUpperInvariant()}";
            }
        }
        return "SQL Keyword";
    }
    
    private IntellisenseType GetSuggestionType(string keyword)
    {
        foreach (var category in _keywordsByCategory)
        {
            if (category.Value.Contains(keyword))
            {
                return category.Key switch
                {
                    "statements" => IntellisenseType.Statement,
                    "clauses" => IntellisenseType.Clause,
                    "datatypes" => IntellisenseType.DataType,
                    "functions" => IntellisenseType.Function,
                    "operators" => IntellisenseType.Operator,
                    "system_tables" => IntellisenseType.Table,
                    _ => IntellisenseType.Keyword
                };
            }
        }
        return IntellisenseType.Keyword;
    }
    
    private int CalculatePriority(string keyword, string searchText)
    {
        // Exact match = highest priority
        if (keyword.ToUpperInvariant() == searchText)
            return 10;
        
        // Starts with = high priority
        if (keyword.ToUpperInvariant().StartsWith(searchText))
            return 8;
        
        // Contains = medium priority
        if (keyword.ToUpperInvariant().Contains(searchText))
            return 5;
        
        return 1;
    }
    
    /// <summary>
    /// Get all keywords for a specific category
    /// </summary>
    public List<string> GetKeywordsByCategory(string category)
    {
        return _keywordsByCategory.GetValueOrDefault(category, new List<string>());
    }
    
    /// <summary>
    /// Check if a word is a SQL keyword
    /// </summary>
    public bool IsKeyword(string word)
    {
        return _allKeywords.Any(k => k.Equals(word, StringComparison.OrdinalIgnoreCase));
    }
}

/// <summary>
/// Intellisense suggestion item
/// </summary>
public class IntellisenseSuggestion
{
    public string Text { get; set; } = string.Empty;
    public string DisplayText { get; set; } = string.Empty;
    public string Description { get; set; } = string.Empty;
    public IntellisenseType Type { get; set; }
    public int Priority { get; set; }
}

/// <summary>
/// Type of intellisense suggestion
/// </summary>
public enum IntellisenseType
{
    Keyword,
    Statement,
    Clause,
    DataType,
    Function,
    Operator,
    Table,
    Column,
    Schema
}

// Helper class for JSON deserialization
internal class KeywordsFile
{
    public string Provider { get; set; } = string.Empty;
    public string Version { get; set; } = string.Empty;
    public Dictionary<string, System.Text.Json.JsonElement> Keywords { get; set; } = new();
}

