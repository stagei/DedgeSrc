using System.Text.Json;
using System.Text.Json.Nodes;
using System.Text.Json.Serialization;

namespace SystemAnalyzer2.Core.Models;

public class AllJsonV2
{
    [JsonPropertyName("title")] public string Title { get; set; } = "";
    [JsonPropertyName("generated")] public string Generated { get; set; } = "";
    [JsonPropertyName("analysisNote")] public string AnalysisNote { get; set; } = "";
    [JsonPropertyName("version")] public int Version { get; set; } = 1;
    [JsonPropertyName("repos")] public List<RepoRef> Repos { get; set; } = new();
    [JsonPropertyName("businessDocs")] public BusinessDocsRef? BusinessDocs { get; set; }
    [JsonPropertyName("databases")] public List<DatabaseRef> Databases { get; set; } = new();
    [JsonPropertyName("technologies")] public Dictionary<string, TechnologySection> Technologies { get; set; } = new();

    [JsonPropertyName("entries")] public List<JsonObject>? Entries { get; set; }
    [JsonPropertyName("sourceRoot")] public string? SourceRoot { get; set; }
    [JsonPropertyName("database")] public string? Database { get; set; }
}

public class RepoRef
{
    [JsonPropertyName("id")] public string Id { get; set; } = "";
    [JsonPropertyName("path")] public string Path { get; set; } = "";
    [JsonPropertyName("type")] public string Type { get; set; } = "local";
    [JsonPropertyName("url")] public string? Url { get; set; }
}

public class BusinessDocsRef
{
    [JsonPropertyName("portfolioPath")] public string? PortfolioPath { get; set; }
    [JsonPropertyName("productDoc")] public string? ProductDoc { get; set; }
    [JsonPropertyName("screenshotsDir")] public string? ScreenshotsDir { get; set; }
    [JsonPropertyName("competitorDoc")] public string? CompetitorDoc { get; set; }
}

public class DatabaseRef
{
    [JsonPropertyName("type")] public string Type { get; set; } = "";
    [JsonPropertyName("alias")] public string? Alias { get; set; }
    [JsonPropertyName("dsn")] public string? Dsn { get; set; }
    [JsonPropertyName("connectionName")] public string? ConnectionName { get; set; }
    [JsonPropertyName("database")] public string? Database { get; set; }
}

public class TechnologySection
{
    [JsonPropertyName("vendor")] public string? Vendor { get; set; }
    [JsonPropertyName("product")] public string? Product { get; set; }
    [JsonPropertyName("version")] public string? Version { get; set; }
    [JsonPropertyName("platform")] public string? Platform { get; set; }
    [JsonPropertyName("sourceRoot")] public string? SourceRoot { get; set; }
    [JsonPropertyName("database")] public string? Database { get; set; }
    [JsonPropertyName("entries")] public List<JsonObject> Entries { get; set; } = new();
}

public static class AllJsonReader
{
    private static readonly JsonSerializerOptions DeserializeOptions = new() { PropertyNameCaseInsensitive = true };

    public static AllJsonV2 Load(string path)
    {
        return Parse(File.ReadAllText(path), path);
    }

    /// <summary>Parses all.json content (same normalization as <see cref="Load"/>).</summary>
    public static AllJsonV2 Parse(string json, string? sourceHint = null)
    {
        var doc = JsonSerializer.Deserialize<AllJsonV2>(json, DeserializeOptions)
            ?? throw new InvalidOperationException(
                string.IsNullOrEmpty(sourceHint) ? "Failed to parse all.json" : $"Failed to parse {sourceHint}");

        if (doc.Technologies.Count == 0 && doc.Entries is { Count: > 0 })
        {
            doc.Technologies["cobol"] = new TechnologySection
            {
                Vendor = "rocket",
                Product = "visual-cobol",
                Version = "11.0",
                Platform = "windows-x64",
                SourceRoot = doc.SourceRoot,
                Database = doc.Database,
                Entries = doc.Entries
            };
            doc.Version = 2;
        }

        return doc;
    }

    public static TechSectionConfig ToConfig(string techId, TechnologySection section) =>
        new(techId, section.Vendor ?? "", section.Product ?? "",
            section.Version ?? "", section.Platform ?? "");
}
