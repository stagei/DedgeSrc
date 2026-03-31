using System.Collections.Generic;
using System.Text.Json.Serialization;

namespace DbExplorer.Models;

/// <summary>
/// Root object for {provider}_{version}_{language}_texts.json
/// </summary>
public class TextsFile
{
    [JsonPropertyName("provider")]
    public string Provider { get; set; } = string.Empty;
    
    [JsonPropertyName("version")]
    public string Version { get; set; } = string.Empty;
    
    [JsonPropertyName("language")]
    public string Language { get; set; } = string.Empty;
    
    [JsonPropertyName("language_name")]
    public string LanguageName { get; set; } = string.Empty;
    
    [JsonPropertyName("translator")]
    public string Translator { get; set; } = string.Empty;
    
    [JsonPropertyName("last_updated")]
    public string LastUpdated { get; set; } = string.Empty;
    
    [JsonPropertyName("completion_percentage")]
    public int CompletionPercentage { get; set; }
    
    [JsonPropertyName("texts")]
    public Dictionary<string, string> Texts { get; set; } = new();
}

