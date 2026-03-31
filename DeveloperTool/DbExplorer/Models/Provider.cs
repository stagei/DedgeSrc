using System.Collections.Generic;
using System.Text.Json.Serialization;

namespace DbExplorer.Models;

/// <summary>
/// Represents a database provider (DB2, PostgreSQL, SQL Server, etc.)
/// </summary>
public class Provider
{
    [JsonPropertyName("provider_code")]
    public string ProviderCode { get; set; } = string.Empty;
    
    [JsonPropertyName("display_name")]
    public string DisplayName { get; set; } = string.Empty;
    
    [JsonPropertyName("icon")]
    public string Icon { get; set; } = string.Empty;
    
    [JsonPropertyName("vendor")]
    public string Vendor { get; set; } = string.Empty;
    
    [JsonPropertyName("description")]
    public string Description { get; set; } = string.Empty;
    
    [JsonPropertyName("supported_versions")]
    public List<string> SupportedVersions { get; set; } = new();
    
    [JsonPropertyName("default_port")]
    public int DefaultPort { get; set; }
    
    [JsonPropertyName("connection_string_template")]
    public string ConnectionStringTemplate { get; set; } = string.Empty;
    
    [JsonPropertyName("requires_schema")]
    public bool RequiresSchema { get; set; }
    
    [JsonPropertyName("system_catalog_schema")]
    public string SystemCatalogSchema { get; set; } = string.Empty;
}

/// <summary>
/// Root object for supported_providers.json
/// </summary>
public class SupportedProvidersFile
{
    [JsonPropertyName("version")]
    public string Version { get; set; } = string.Empty;
    
    [JsonPropertyName("last_updated")]
    public string LastUpdated { get; set; } = string.Empty;
    
    [JsonPropertyName("providers")]
    public List<Provider> Providers { get; set; } = new();
}

