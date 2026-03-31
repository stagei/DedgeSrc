using System.Text.Json;
using System.Text.Json.Nodes;
using NLog;

namespace SystemAnalyzer.Batch.Services;

public sealed class CacheService
{
    private static readonly Logger Logger = LogManager.GetCurrentClassLogger();
    private static readonly JsonSerializerOptions JsonOptions = new() { WriteIndented = true };

    private readonly string _analysisCommonPath;
    private string _objectsDir = string.Empty;
    private string _namingDir = string.Empty;
    private bool _enabled;

    public bool Enabled => _enabled;
    public string AnalysisCommonPath => _analysisCommonPath;
    public int ExtractionCacheHits { get; set; }
    public int ExtractionCacheMisses { get; set; }

    public CacheService(string analysisCommonPath)
    {
        _analysisCommonPath = analysisCommonPath;
    }

    public void InitializeAnalysisCommonCache()
    {
        if (string.IsNullOrEmpty(_analysisCommonPath))
        {
            Logger.Info("AnalysisCommon cache: disabled (path not configured)");
            return;
        }

        Directory.CreateDirectory(_analysisCommonPath);
        _objectsDir = Path.Combine(_analysisCommonPath, "Objects");
        Directory.CreateDirectory(_objectsDir);
        Directory.CreateDirectory(Path.Combine(_analysisCommonPath, "BusinessAreas"));
        Directory.CreateDirectory(Path.Combine(_analysisCommonPath, "Databases"));
        _enabled = true;

        var count = Directory.GetFiles(_objectsDir, "*.json").Length;
        var cblCount = Directory.GetFiles(_objectsDir, "*.cbl.json").Length;
        Logger.Info($"AnalysisCommon cache: enabled ({count} cached, {cblCount} programs) at {_analysisCommonPath}");
    }

    public JsonNode? GetCachedFact(string programName, string factKey, string elementType = "cbl")
    {
        if (!_enabled) return null;
        var path = Path.Combine(_objectsDir, $"{programName.ToUpperInvariant()}.{elementType}.json");
        if (!File.Exists(path)) return null;
        try
        {
            var text = File.ReadAllText(path);
            var obj = JsonNode.Parse(text);
            return obj?[factKey];
        }
        catch { return null; }
    }

    public void SaveCachedFact(string programName, string factKey, JsonNode factValue, string elementType = "cbl")
    {
        if (!_enabled) return;
        var name = programName.ToUpperInvariant();
        var path = Path.Combine(_objectsDir, $"{name}.{elementType}.json");
        try
        {
            JsonObject obj;
            if (File.Exists(path))
            {
                var text = File.ReadAllText(path);
                obj = JsonNode.Parse(text)?.AsObject() ?? new JsonObject();
            }
            else
            {
                obj = new JsonObject
                {
                    ["program"] = name,
                    ["elementType"] = elementType
                };
            }
            obj["lastUpdated"] = DateTime.Now.ToString("yyyy-MM-ddTHH:mm:ss");
            obj[factKey] = factValue?.DeepClone();
            File.WriteAllText(path, obj.ToJsonString(JsonOptions));
        }
        catch (Exception ex)
        {
            Logger.Warn($"Cache write failed for {name}.{elementType}/{factKey}: {ex.Message}");
        }
    }

    public void InitializeNamingCache()
    {
        if (!_enabled) return;
        _namingDir = Path.Combine(_analysisCommonPath, "Naming");
        Directory.CreateDirectory(_namingDir);
        Directory.CreateDirectory(Path.Combine(_namingDir, "ColumnNames"));
        Directory.CreateDirectory(Path.Combine(_namingDir, "TableNames"));
        Directory.CreateDirectory(Path.Combine(_namingDir, "ProgramNames"));
        Logger.Info($"Naming cache initialized at {_namingDir}");
    }

    public JsonNode? GetCachedNaming(string name, string category)
    {
        if (!_enabled || string.IsNullOrEmpty(_namingDir)) return null;
        var path = Path.Combine(_namingDir, category, $"{name.ToUpperInvariant()}.json");
        if (!File.Exists(path)) return null;
        try
        {
            return JsonNode.Parse(File.ReadAllText(path));
        }
        catch { return null; }
    }

    public void SaveCachedNaming(string name, string category, JsonNode data)
    {
        if (!_enabled || string.IsNullOrEmpty(_namingDir)) return;
        var path = Path.Combine(_namingDir, category, $"{name.ToUpperInvariant()}.json");
        try
        {
            File.WriteAllText(path, data.ToJsonString(JsonOptions));
        }
        catch (Exception ex)
        {
            Logger.Warn($"Naming cache write failed for {category}/{name}: {ex.Message}");
        }
    }
}
