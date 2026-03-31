using System.Text.Json;
using System.Text.Json.Nodes;
using System.Text.RegularExpressions;
using SystemAnalyzer2.Batch.Parsers;
using SystemAnalyzer2.Core.Models;

namespace SystemAnalyzer2.Batch.Services.Analyzers;

public sealed class CSharpAnalyzer : AnalyzerBase
{
    private static readonly Regex DbCtx = new(@"\bDbContext\b", RegexOptions.Compiled);
    private static readonly Regex DbConn = new(
        @"\b(DB2Connection|NpgsqlConnection|SqlConnection)\b",
        RegexOptions.Compiled);

    public override string TechnologyId => "csharp";
    public override string VendorId => "microsoft";
    public override string ProductId => "dotnet";

    public override bool CanHandle(TechSectionConfig config) => MatchesTechnology(config, "csharp");

    public override Task<TechAnalysisResult> AnalyzeAsync(TechAnalysisRequest request, CancellationToken ct = default)
    {
        var programs = new List<JsonObject>();
        var outRoot = Path.Combine(request.RunDir, "autodoc", "csharp");
        Directory.CreateDirectory(outRoot);
        var repos = LoadRepoMap(request);

        foreach (var entry in request.Entries)
        {
            ct.ThrowIfCancellationRequested();
            var rel = entry["path"]?.GetValue<string>();
            if (string.IsNullOrWhiteSpace(rel) || !rel.EndsWith(".sln", StringComparison.OrdinalIgnoreCase))
                continue;
            var repoId = entry["repoId"]?.GetValue<string>() ?? "";
            if (!repos.TryGetValue(repoId, out var repoRoot) && repos.Count == 1)
                repoRoot = repos.Values.First();
            if (string.IsNullOrEmpty(repoRoot)) continue;

            var sln = Path.GetFullPath(Path.Combine(repoRoot, rel.Replace('/', Path.DirectorySeparatorChar)));
            if (!File.Exists(sln)) continue;

            var sourceFolder = Path.GetDirectoryName(sln) ?? repoRoot;
            _ = CSharpParser.StartCSharpParse(sourceFolder, solutionFile: sln, outputFolder: outRoot, generateHtml: false);

            programs.Add(new JsonObject
            {
                ["program"] = Path.GetFileNameWithoutExtension(sln),
                ["technology"] = "csharp",
                ["solutionPath"] = sln,
                ["scanSummary"] = ScanSolutionTree(sourceFolder)
            });
        }

        return Task.FromResult(new TechAnalysisResult(
            TechnologyId, VendorId, ProductId,
            programs.Count, 0, 0, programs));
    }

    private static JsonObject ScanSolutionTree(string root)
    {
        int dc = 0, cn = 0;
        foreach (var cs in Directory.EnumerateFiles(root, "*.cs", SearchOption.AllDirectories))
        {
            if (cs.Contains($"{Path.DirectorySeparatorChar}obj{Path.DirectorySeparatorChar}", StringComparison.OrdinalIgnoreCase)
                || cs.Contains($"{Path.DirectorySeparatorChar}bin{Path.DirectorySeparatorChar}", StringComparison.OrdinalIgnoreCase))
                continue;
            string t;
            try { t = File.ReadAllText(cs); }
            catch { continue; }
            if (DbCtx.IsMatch(t)) dc++;
            if (DbConn.IsMatch(t)) cn++;
        }

        return new JsonObject
        {
            ["filesWithDbContext"] = dc,
            ["filesWithAdonetConnections"] = cn
        };
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
        catch { }

        return map;
    }
}
