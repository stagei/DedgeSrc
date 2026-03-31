using System.Text.Json;
using System.Text.Json.Nodes;
using System.Text.RegularExpressions;
using SystemAnalyzer2.Batch.Parsers;
using SystemAnalyzer2.Core.Models;

namespace SystemAnalyzer2.Batch.Services.Analyzers;

/// <summary>PowerShell analysis using embedded <see cref="Ps1Parser"/> patterns plus REST/SQL discovery.</summary>
public sealed class PowerShellAnalyzer : AnalyzerBase
{
    private static readonly Regex RestRx = new(
        @"\b(Invoke-RestMethod|Invoke-WebRequest)\s+[^\n#]*?(?:-Uri\s+)?['""]([^'""]+)['""]",
        RegexOptions.IgnoreCase | RegexOptions.Compiled);

    private static readonly Regex DbRx = new(
        @"\b(Invoke-Db2Query|Invoke-McpDb2Query|Invoke-SqlCmd)\b",
        RegexOptions.IgnoreCase | RegexOptions.Compiled);

    public override string TechnologyId => "powershell";
    public override string VendorId => "microsoft";
    public override string ProductId => "pwsh7";

    public override bool CanHandle(TechSectionConfig config) => MatchesTechnology(config, "powershell");

    public override Task<TechAnalysisResult> AnalyzeAsync(TechAnalysisRequest request, CancellationToken ct = default)
    {
        var programs = new List<JsonObject>();
        var autodocRoot = Path.Combine(request.RunDir, "autodoc", "powershell");
        Directory.CreateDirectory(autodocRoot);

        var repos = LoadRepoMap(request);
        Dictionary<string, (string FilePath, List<string> Functions)>? moduleIndex = null;
        foreach (var repo in repos.Values)
        {
            var modulesDir = Path.Combine(repo, "Modules");
            if (Directory.Exists(modulesDir))
            {
                moduleIndex = Ps1Parser.BuildModuleIndex(modulesDir);
                break;
            }
        }

        foreach (var entry in request.Entries)
        {
            ct.ThrowIfCancellationRequested();
            var rel = entry["path"]?.GetValue<string>();
            if (string.IsNullOrWhiteSpace(rel)) continue;
            var repoId = entry["repoId"]?.GetValue<string>() ?? "";
            if (!repos.TryGetValue(repoId, out var repoRoot) && repos.Count == 1)
                repoRoot = repos.Values.First();
            if (string.IsNullOrEmpty(repoRoot)) continue;

            var fullPath = Path.GetFullPath(Path.Combine(repoRoot, rel.Replace('/', Path.DirectorySeparatorChar)));
            if (!File.Exists(fullPath)) continue;

            _ = Ps1Parser.StartPs1Parse(fullPath, show: false, outputFolder: autodocRoot, cleanUp: false,
                generateHtml: false, saveMmdFiles: false, moduleIndex: moduleIndex);

            var text = File.ReadAllText(fullPath);
            var jo = new JsonObject
            {
                ["program"] = Path.GetFileNameWithoutExtension(fullPath),
                ["technology"] = "powershell",
                ["sourcePath"] = fullPath,
                ["restCalls"] = CollectRestCalls(text),
                ["sqlToolHints"] = CollectSqlHints(text)
            };
            programs.Add(jo);
        }

        return Task.FromResult(new TechAnalysisResult(
            TechnologyId, VendorId, ProductId,
            programs.Count, 0, 0, programs));
    }

    private static JsonArray CollectRestCalls(string text)
    {
        var a = new JsonArray();
        foreach (Match m in RestRx.Matches(text))
            a.Add(new JsonObject { ["verb"] = m.Groups[1].Value, ["uri"] = m.Groups[2].Value });
        return a;
    }

    private static JsonArray CollectSqlHints(string text)
    {
        var a = new JsonArray();
        foreach (Match m in DbRx.Matches(text))
            a.Add(m.Groups[1].Value);
        return a;
    }

    private static Dictionary<string, string> LoadRepoMap(TechAnalysisRequest request)
    {
        var map = new Dictionary<string, string>(StringComparer.OrdinalIgnoreCase);
        try
        {
            var doc = JsonSerializer.Deserialize<AllJsonV2>(request.AllJson.ToJsonString(),
                new JsonSerializerOptions { PropertyNameCaseInsensitive = true });
            if (doc?.Repos == null) return map;
            foreach (var r in doc.Repos)
            {
                if (!string.IsNullOrEmpty(r.Id) && !string.IsNullOrEmpty(r.Path))
                    map[r.Id] = r.Path;
            }
        }
        catch { /* ignore */ }

        return map;
    }
}
