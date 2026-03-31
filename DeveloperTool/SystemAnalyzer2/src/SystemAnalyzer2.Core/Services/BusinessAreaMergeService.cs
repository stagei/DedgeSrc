using System.Text.Json;
using System.Text.Json.Nodes;

namespace SystemAnalyzer2.Core.Services;

public static class BusinessAreaMergeService
{
    private static readonly JsonSerializerOptions WriteOptions = new()
    {
        WriteIndented = true,
        Encoder = System.Text.Encodings.Web.JavaScriptEncoder.UnsafeRelaxedJsonEscaping
    };

    public static JsonObject Merge(string basePath, string overridePath)
    {
        var baseObj = LoadJson(basePath) ?? BuildEmptyBase();
        if (!File.Exists(overridePath)) return baseObj;

        var overrides = LoadJson(overridePath);
        if (overrides == null) return baseObj;

        var areas = baseObj["areas"]?.AsArray() ?? new JsonArray();
        var programMap = baseObj["programAreaMap"]?.AsObject() ?? new JsonObject();
        var existingAreaIds = new HashSet<string>(StringComparer.OrdinalIgnoreCase);
        foreach (var a in areas)
        {
            var id = a?["id"]?.GetValue<string>();
            if (id != null) existingAreaIds.Add(id);
        }

        if (overrides["additionalAreas"] is JsonArray additional)
        {
            foreach (var newArea in additional)
            {
                var id = newArea?["id"]?.GetValue<string>();
                if (id != null && !existingAreaIds.Contains(id))
                {
                    areas.Add(newArea!.DeepClone());
                    existingAreaIds.Add(id);
                }
            }
        }

        if (overrides["programOverrides"] is JsonObject progOverrides)
        {
            foreach (var kv in progOverrides)
            {
                programMap[kv.Key] = kv.Value?.DeepClone();
            }
        }

        baseObj["areas"] = areas;
        baseObj["programAreaMap"] = programMap;
        baseObj["totalAreas"] = existingAreaIds.Count;

        return baseObj;
    }

    public static void MergeAndSave(string basePath, string overridePath, string outputPath)
    {
        var merged = Merge(basePath, overridePath);
        Directory.CreateDirectory(Path.GetDirectoryName(outputPath)!);
        File.WriteAllText(outputPath, merged.ToJsonString(WriteOptions));
    }

    public static JsonObject LoadOverrides(string overridePath)
    {
        if (!File.Exists(overridePath))
        {
            return new JsonObject
            {
                ["analysisAlias"] = "",
                ["lastModified"] = DateTime.UtcNow.ToString("o"),
                ["additionalAreas"] = new JsonArray(),
                ["programOverrides"] = new JsonObject()
            };
        }
        return LoadJson(overridePath) ?? LoadOverrides("");
    }

    public static void SaveOverrides(string overridePath, JsonObject overrides)
    {
        overrides["lastModified"] = DateTime.UtcNow.ToString("o");
        Directory.CreateDirectory(Path.GetDirectoryName(overridePath)!);
        File.WriteAllText(overridePath, overrides.ToJsonString(WriteOptions));
    }

    private static JsonObject? LoadJson(string path)
    {
        if (!File.Exists(path)) return null;
        try
        {
            return JsonNode.Parse(File.ReadAllText(path))?.AsObject();
        }
        catch
        {
            return null;
        }
    }

    private static JsonObject BuildEmptyBase() => new()
    {
        ["title"] = "Business Area Classification",
        ["generated"] = DateTime.UtcNow.ToString("yyyy-MM-dd HH:mm:ss"),
        ["totalAreas"] = 0,
        ["areas"] = new JsonArray(),
        ["programAreaMap"] = new JsonObject(),
        ["version"] = 2
    };
}
