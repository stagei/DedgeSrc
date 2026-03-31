using System.Collections.Generic;
using System.Text.Json.Serialization;

namespace DbExplorer.Models;

/// <summary>
/// Represents a SQL statement from ConfigFiles
/// </summary>
public class SqlStatement
{
    [JsonPropertyName("sql")]
    public string Sql { get; set; } = string.Empty;
    
    [JsonPropertyName("description")]
    public string Description { get; set; } = string.Empty;
    
    [JsonPropertyName("parameters")]
    public List<string> Parameters { get; set; } = new();
    
    [JsonPropertyName("returns")]
    public string Returns { get; set; } = string.Empty;
    
    [JsonPropertyName("source")]
    public string Source { get; set; } = string.Empty;
    
    [JsonPropertyName("notes")]
    public List<string> Notes { get; set; } = new();
}

/// <summary>
/// Root object for {provider}_{version}_sql_statements.json
/// </summary>
public class SqlStatementsFile
{
    [JsonPropertyName("provider")]
    public string Provider { get; set; } = string.Empty;
    
    [JsonPropertyName("version")]
    public string Version { get; set; } = string.Empty;
    
    [JsonPropertyName("description")]
    public string Description { get; set; } = string.Empty;
    
    [JsonPropertyName("statements")]
    public Dictionary<string, SqlStatement> Statements { get; set; } = new();
}

