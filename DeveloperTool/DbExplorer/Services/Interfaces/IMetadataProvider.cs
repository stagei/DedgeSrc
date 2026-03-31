using System.Collections.Generic;
using System.Data;
using System.Threading.Tasks;

namespace DbExplorer.Services.Interfaces;

/// <summary>
/// Provider-agnostic interface for accessing database metadata queries and UI text.
/// Implementations load data from JSON files in ConfigFiles/ directory.
/// </summary>
public interface IMetadataProvider
{
    /// <summary>
    /// Get SQL statement by name for current provider/version.
    /// </summary>
    /// <param name="statementName">Statement name from JSON (e.g., "GetTableComment")</param>
    /// <returns>SQL query string with ? placeholders</returns>
    string GetStatement(string statementName);
    
    /// <summary>
    /// Get SQL statement for specific provider/version.
    /// </summary>
    string GetStatement(string statementName, string provider, string version);
    
    /// <summary>
    /// Execute a metadata query with parameters.
    /// </summary>
    /// <param name="statementName">Statement name from JSON</param>
    /// <param name="parameters">Dictionary of parameter names to values</param>
    /// <returns>DataTable with results</returns>
    Task<DataTable> ExecuteMetadataQueryAsync(string statementName, Dictionary<string, object> parameters);
    
    /// <summary>
    /// Execute a metadata query that returns a single value.
    /// </summary>
    Task<object?> ExecuteScalarAsync(string statementName, Dictionary<string, object> parameters);
    
    /// <summary>
    /// Get localized UI text by key.
    /// </summary>
    /// <param name="key">Text key from JSON (e.g., "menu_file_new")</param>
    /// <returns>Localized text string</returns>
    string GetText(string key);
    
    /// <summary>
    /// Get current provider code (e.g., "DB2", "POSTGRESQL").
    /// </summary>
    string GetCurrentProvider();
    
    /// <summary>
    /// Get current provider version (e.g., "12.1", "16.0").
    /// </summary>
    string GetCurrentVersion();
    
    /// <summary>
    /// Check if a feature is supported by current provider/version.
    /// </summary>
    bool IsFeatureSupported(string featureName);
    
    /// <summary>
    /// Get list of supported providers.
    /// </summary>
    List<string> GetSupportedProviders();
}

