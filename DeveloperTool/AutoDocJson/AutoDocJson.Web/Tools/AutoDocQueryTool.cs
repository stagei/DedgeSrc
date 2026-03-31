using System.ComponentModel;
using System.Text.Json;
using AutoDocNew.Core;
using AutoDocNew.Models;
using AutoDocNew.Web.Helpers;
using ModelContextProtocol.Server;

namespace AutoDocNew.Web.Tools;

[McpServerToolType]
public sealed class AutoDocQueryTool
{
    private static readonly JsonSerializerOptions ReadOpts = new()
    {
        PropertyNamingPolicy = JsonNamingPolicy.CamelCase,
        PropertyNameCaseInsensitive = true
    };

    private readonly IConfiguration _config;
    private readonly SearchEngine _searchEngine;
    private readonly ILogger<AutoDocQueryTool> _logger;

    public AutoDocQueryTool(IConfiguration config, SearchEngine searchEngine, ILogger<AutoDocQueryTool> logger)
    {
        _config = config;
        _searchEngine = searchEngine;
        _logger = logger;
    }

    private string GetOutputFolder() =>
        _config.GetValue<string>("AutoDocJson:OutputFolder")
        ?? Path.Combine(Environment.GetEnvironmentVariable("OptPath") ?? "C:\\opt", "Webs", "AutoDocJson");

    private int GetMaxNodes() => _config.GetValue<int>("AutoDocJson:MermaidMaxNodes", 500);
    private string GetDefaultRenderer() => _config.GetValue<string>("AutoDocJson:DefaultRenderer") ?? "gojs";

    [McpServerTool]
    [Description("List all available AutoDoc documentation files. Returns file name, type, title, description, git history summary, available diagrams, and recommended renderer.")]
    public string ListDocuments(
        [Description("Optional filter by file type: CBL, BAT, PS1, REX, SQL, CSharp. Leave empty for all types.")] string? fileType = null)
    {
        try
        {
            string outputFolder = GetOutputFolder();
            if (!Directory.Exists(outputFolder))
                return JsonSerializer.Serialize(new { error = "Output folder not found." });

            int maxNodes = GetMaxNodes();
            string defaultRenderer = GetDefaultRenderer();

            var jsonFiles = Directory.EnumerateFiles(outputFolder, "*.json", SearchOption.TopDirectoryOnly)
                .Where(f => !Path.GetFileName(f).StartsWith("_"));

            var documents = new List<object>();

            foreach (var filePath in jsonFiles)
            {
                try
                {
                    string json = File.ReadAllText(filePath);
                    var doc = JsonSerializer.Deserialize<DocFileResult>(json, ReadOpts);
                    if (doc == null) continue;

                    if (!string.IsNullOrWhiteSpace(fileType) &&
                        !string.Equals(doc.Type, fileType, StringComparison.OrdinalIgnoreCase))
                        continue;

                    var diagramNames = GetDiagramNames(json);
                    var recommended = GetRecommendedRenderer(json, maxNodes, defaultRenderer);

                    documents.Add(new
                    {
                        fileName = Path.GetFileName(filePath),
                        type = doc.Type,
                        title = doc.Title,
                        description = doc.Description,
                        generatedAt = doc.GeneratedAt,
                        gitHistory = doc.GitHistory != null ? new
                        {
                            lastChanged = doc.GitHistory.LastChanged,
                            changedBy = doc.GitHistory.ChangedBy,
                            totalChanges = doc.GitHistory.TotalChanges
                        } : null,
                        diagrams = diagramNames,
                        recommendedRenderer = recommended
                    });
                }
                catch
                {
                    // Skip files that can't be parsed
                }
            }

            _logger.LogDebug("ListDocuments returned {Count} documents (filter: {Filter})",
                documents.Count, fileType ?? "all");

            return JsonSerializer.Serialize(new { count = documents.Count, documents });
        }
        catch (Exception ex)
        {
            _logger.LogError(ex, "Error listing documents");
            return JsonSerializer.Serialize(new { error = ex.Message });
        }
    }

    [McpServerTool]
    [Description("Get the full JSON content of a specific AutoDoc documentation file. Returns all parsed data including diagrams, metadata, git history, available diagram names, and recommended renderer.")]
    public string GetDocument(
        [Description("The JSON file name, e.g. 'BSAUTOS.CBL.json' or 'dbm_customer.sql.json'.")] string fileName)
    {
        if (string.IsNullOrWhiteSpace(fileName))
            return JsonSerializer.Serialize(new { error = "fileName cannot be empty." });

        try
        {
            string safeFile = Path.GetFileName(fileName);
            if (!safeFile.EndsWith(".json", StringComparison.OrdinalIgnoreCase))
                return JsonSerializer.Serialize(new { error = "Only .json files are supported." });

            string outputFolder = GetOutputFolder();
            string filePath = Path.Combine(outputFolder, safeFile);

            if (!File.Exists(filePath))
                return JsonSerializer.Serialize(new { error = $"File not found: {safeFile}" });

            string json = File.ReadAllText(filePath);
            int maxNodes = GetMaxNodes();
            string defaultRenderer = GetDefaultRenderer();

            var diagramNames = GetDiagramNames(json);
            var recommended = GetRecommendedRenderer(json, maxNodes, defaultRenderer);

            var result = JsonSerializer.Serialize(new
            {
                document = JsonSerializer.Deserialize<JsonElement>(json),
                availableDiagrams = diagramNames,
                recommendedRenderer = recommended
            });

            _logger.LogDebug("GetDocument returned {FileName} ({Length} chars)", safeFile, result.Length);
            return result;
        }
        catch (Exception ex)
        {
            _logger.LogError(ex, "Error reading document {FileName}", fileName);
            return JsonSerializer.Serialize(new { error = ex.Message });
        }
    }

    [McpServerTool]
    [Description("Search across all AutoDoc documentation files by keyword. Searches titles, descriptions, file names, and content elements.")]
    public string SearchDocuments(
        [Description("Search query string. Multiple terms are supported.")] string query,
        [Description("Optional comma-separated file types to search: CBL,BAT,PS1,REX,SQL,CSharp. Leave empty for all.")] string? types = null,
        [Description("Search logic: AND (all terms must match) or OR (any term matches). Default: AND.")] string? logic = null)
    {
        if (string.IsNullOrWhiteSpace(query))
            return JsonSerializer.Serialize(new { error = "Query cannot be empty." });

        try
        {
            var request = new SearchRequest
            {
                Query = query,
                Logic = logic ?? "AND"
            };

            if (!string.IsNullOrWhiteSpace(types))
                request.Types = types.Split(',', StringSplitOptions.RemoveEmptyEntries);

            var results = _searchEngine.Search(request);

            _logger.LogDebug("SearchDocuments for '{Query}' returned {Count} results", query, results.Count());
            return JsonSerializer.Serialize(new { query, resultCount = results.Count(), results });
        }
        catch (Exception ex)
        {
            _logger.LogError(ex, "Error searching documents");
            return JsonSerializer.Serialize(new { error = ex.Message });
        }
    }

    /// <summary>
    /// Extract non-empty diagram field names from the raw JSON using JsonElement
    /// to avoid needing to know the exact result subtype.
    /// </summary>
    private static List<string> GetDiagramNames(string json)
    {
        var names = new List<string>();
        try
        {
            using var jsonDoc = JsonDocument.Parse(json);
            var root = jsonDoc.RootElement;

            // Standard diagram fields inside "diagrams" object (CBL, BAT, PS1, REX, CSharp)
            if (root.TryGetProperty("diagrams", out var diagrams))
            {
                AddIfNonEmpty(diagrams, "flowMmd", "flow", names);
                AddIfNonEmpty(diagrams, "sequenceMmd", "sequence", names);
                AddIfNonEmpty(diagrams, "processMmd", "process", names);
                AddIfNonEmpty(diagrams, "architectureMmd", "architecture", names);
                AddIfNonEmpty(diagrams, "integrationMmd", "integration", names);
                AddIfNonEmpty(diagrams, "restMmd", "rest", names);
            }

            // SQL-specific top-level diagram fields
            AddIfNonEmpty(root, "erDiagramMmd", "er", names);
            AddIfNonEmpty(root, "interactionDiagramMmd", "interaction", names);
        }
        catch
        {
            // Parsing failed; return empty list
        }
        return names;
    }

    private static void AddIfNonEmpty(JsonElement parent, string propertyName, string diagramName, List<string> names)
    {
        if (parent.TryGetProperty(propertyName, out var prop) &&
            prop.ValueKind == JsonValueKind.String &&
            !string.IsNullOrWhiteSpace(prop.GetString()))
        {
            names.Add(diagramName);
        }
    }

    /// <summary>
    /// Determine recommended renderer by counting nodes in the largest diagram.
    /// </summary>
    private static string GetRecommendedRenderer(string json, int maxNodes, string defaultRenderer)
    {
        try
        {
            using var jsonDoc = JsonDocument.Parse(json);
            var root = jsonDoc.RootElement;
            string? largestMmd = null;
            int largestLen = 0;

            void CheckField(JsonElement parent, string propertyName)
            {
                if (parent.TryGetProperty(propertyName, out var prop) &&
                    prop.ValueKind == JsonValueKind.String)
                {
                    string? val = prop.GetString();
                    if (val != null && val.Length > largestLen)
                    {
                        largestLen = val.Length;
                        largestMmd = val;
                    }
                }
            }

            if (root.TryGetProperty("diagrams", out var diagrams))
            {
                CheckField(diagrams, "flowMmd");
                CheckField(diagrams, "sequenceMmd");
                CheckField(diagrams, "processMmd");
                CheckField(diagrams, "classMmd");
                CheckField(diagrams, "projectMmd");
                CheckField(diagrams, "namespaceMmd");
                CheckField(diagrams, "ecosystemMmd");
                CheckField(diagrams, "executionPathMmd");
                CheckField(diagrams, "restMmd");
            }

            CheckField(root, "erDiagramMmd");
            CheckField(root, "interactionDiagramMmd");

            return MermaidNodeCounter.RecommendRenderer(largestMmd, maxNodes, defaultRenderer);
        }
        catch
        {
            return defaultRenderer;
        }
    }
}
