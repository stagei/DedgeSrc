using System.Text.Json;
using SystemAnalyzer2.Core.Models;

namespace SystemAnalyzer2.Core.Services;

public sealed class AnalysisIndexService
{
    private static readonly JsonSerializerOptions JsonOptions = new()
    {
        PropertyNameCaseInsensitive = true,
        WriteIndented = true
    };

    public AnalysisIndex Load(string dataRoot)
    {
        var path = Path.Combine(dataRoot, "analyses.json");
        if (File.Exists(path))
        {
            var raw = File.ReadAllText(path);
            var idx = JsonSerializer.Deserialize<AnalysisIndex>(raw, JsonOptions);
            if (idx is { Analyses.Count: > 0 }) return idx;
        }

        return DiscoverFromFolders(dataRoot);
    }

    private static AnalysisIndex DiscoverFromFolders(string dataRoot)
    {
        var index = new AnalysisIndex();
        if (!Directory.Exists(dataRoot)) return index;

        foreach (var dir in Directory.GetDirectories(dataRoot))
        {
            var masterPath = Path.Combine(dir, "dependency_master.json");
            if (!File.Exists(masterPath)) continue;

            var alias = Path.GetFileName(dir);
            var lastWrite = File.GetLastWriteTime(masterPath);
            index.Analyses.Add(new AnalysisMetadata
            {
                Alias = alias,
                LatestFolder = alias,
                LastRun = lastWrite.ToString("yyyy-MM-dd HH:mm:ss")
            });
        }

        return index;
    }

    public void Save(string dataRoot, AnalysisIndex index)
    {
        Directory.CreateDirectory(dataRoot);
        var path = Path.Combine(dataRoot, "analyses.json");
        var json = JsonSerializer.Serialize(index, JsonOptions);
        File.WriteAllText(path, json);
    }
}
