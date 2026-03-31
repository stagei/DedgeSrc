using System.Text.Json.Serialization;

namespace CursorDb2McpServer.Models;

/// <summary>
/// Top-level database entry from DatabasesV2.json.
/// </summary>
public sealed class DatabaseEntry
{
    [JsonPropertyName("Database")]
    public string Database { get; set; } = string.Empty;

    [JsonPropertyName("Provider")]
    public string Provider { get; set; } = string.Empty;

    [JsonPropertyName("Application")]
    public string Application { get; set; } = string.Empty;

    [JsonPropertyName("Environment")]
    public string Environment { get; set; } = string.Empty;

    [JsonPropertyName("Version")]
    public string Version { get; set; } = string.Empty;

    [JsonPropertyName("PrimaryCatalogName")]
    public string PrimaryCatalogName { get; set; } = string.Empty;

    [JsonPropertyName("IsActive")]
    public bool IsActive { get; set; }

    [JsonPropertyName("ServerName")]
    public string ServerName { get; set; } = string.Empty;

    [JsonPropertyName("Description")]
    public string Description { get; set; } = string.Empty;

    [JsonPropertyName("NorwegianDescription")]
    public string NorwegianDescription { get; set; } = string.Empty;

    [JsonPropertyName("AccessPoints")]
    public List<AccessPoint> AccessPoints { get; set; } = [];
}

/// <summary>
/// Database access point (PrimaryDb, Alias, or FederatedDb).
/// </summary>
public sealed class AccessPoint
{
    [JsonPropertyName("InstanceName")]
    public string InstanceName { get; set; } = string.Empty;

    [JsonPropertyName("CatalogName")]
    public string CatalogName { get; set; } = string.Empty;

    [JsonPropertyName("AccessPointType")]
    public string AccessPointType { get; set; } = string.Empty;

    [JsonPropertyName("Port")]
    public string Port { get; set; } = string.Empty;

    [JsonPropertyName("ServiceName")]
    public string ServiceName { get; set; } = string.Empty;

    [JsonPropertyName("NodeName")]
    public string NodeName { get; set; } = string.Empty;

    [JsonPropertyName("AuthenticationType")]
    public string AuthenticationType { get; set; } = string.Empty;

    [JsonPropertyName("UID")]
    public string Uid { get; set; } = string.Empty;

    [JsonPropertyName("PWD")]
    public string Pwd { get; set; } = string.Empty;

    [JsonPropertyName("IsActive")]
    public bool IsActive { get; set; }
}
