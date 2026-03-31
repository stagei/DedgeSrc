using System.Collections.Generic;
using System.Text.Json.Serialization;

namespace DbExplorerTray.Models;

/// <summary>
/// Wrapper for connections.json file structure
/// </summary>
public class ConnectionsFile
{
    [JsonPropertyName("connections")]
    public List<ConnectionProfile> Connections { get; set; } = new();
}

/// <summary>
/// Connection profile model matching the main app's connections.json format
/// </summary>
public class ConnectionProfile
{
    [JsonPropertyName("name")]
    public string Name { get; set; } = string.Empty;

    [JsonPropertyName("server")]
    public string Server { get; set; } = string.Empty;

    [JsonPropertyName("port")]
    public int Port { get; set; } = 50000;

    [JsonPropertyName("database")]
    public string Database { get; set; } = string.Empty;

    [JsonPropertyName("provider")]
    public string Provider { get; set; } = "DB2";

    [JsonPropertyName("lastUsed")]
    public string? LastUsed { get; set; }
}
