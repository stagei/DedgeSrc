using Newtonsoft.Json;

namespace AutoDocNew.Models;

/// <summary>
/// Global settings model - converted from PowerShell GlobalSettings.json structure
/// </summary>
public class GlobalSettings
{
    [JsonProperty("Paths")]
    public PathsSettings? Paths { get; set; }

    [JsonProperty("Organization")]
    public OrganizationSettings? Organization { get; set; }

    [JsonProperty("DatabaseSettings")]
    public object[]? DatabaseSettings { get; set; }
}

public class PathsSettings
{
    [JsonProperty("CommonLog")]
    public string? CommonLog { get; set; }

    [JsonProperty("DevToolsWebUrl")]
    public string? DevToolsWebUrl { get; set; }

    [JsonProperty("Common")]
    public string? Common { get; set; }

    [JsonProperty("TempFk")]
    public string? TempFk { get; set; }

    [JsonProperty("AdInfo")]
    public string? AdInfo { get; set; }
}

public class OrganizationSettings
{
    [JsonProperty("DefaultDomain")]
    public string? DefaultDomain { get; set; }
}
