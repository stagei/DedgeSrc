using System.Text.Json;
using System.Text.Json.Nodes;
using NLog;

namespace SystemAnalyzer2.Batch.Services.Shared;

/// <summary>
/// Generates per-profile analysis_stats.json and cross-analysis statistics.
/// Replaces Gather-AnalysisStats.ps1.
/// </summary>
public sealed class StatsService
{
    private static readonly Logger Logger = LogManager.GetCurrentClassLogger();
    private static readonly JsonSerializerOptions JsonWriteOptions = new() { WriteIndented = true };

    public static JsonObject GenerateProfileStats(
        JsonObject master,
        string runDir,
        int cacheHits,
        int cacheMisses,
        TimeSpan elapsed)
    {
        var programs = master["programs"]?.AsArray() ?? [];
        var stats = new JsonObject
        {
            ["generatedAt"] = DateTime.Now.ToString("yyyy-MM-ddTHH:mm:ss"),
            ["elapsedSeconds"] = Math.Round(elapsed.TotalSeconds, 1),
            ["alias"] = master["alias"]?.GetValue<string>() ?? ""
        };

        // Program breakdown
        var totalPrograms = programs.Count;
        int original = 0, callExpanded = 0, tableDiscovered = 0;
        int deprecated = 0, classified = 0;
        var classifications = new Dictionary<string, int>(StringComparer.OrdinalIgnoreCase);

        foreach (var p in programs)
        {
            var layer = p?["layer"]?.GetValue<string>() ?? "";
            if (layer == "original") original++;
            else if (layer == "call-expanded") callExpanded++;
            else if (layer == "table-discovered") tableDiscovered++;

            if (p?["isDeprecated"]?.GetValue<bool>() == true) deprecated++;

            var cls = p?["classification"]?.GetValue<string>() ?? "unclassified";
            if (!string.IsNullOrEmpty(cls) && cls != "unclassified") classified++;
            classifications.TryAdd(cls, 0);
            classifications[cls]++;
        }

        stats["programBreakdown"] = new JsonObject
        {
            ["total"] = totalPrograms,
            ["original"] = original,
            ["callExpanded"] = callExpanded,
            ["tableDiscovered"] = tableDiscovered,
            ["deprecated"] = deprecated,
            ["classified"] = classified,
            ["classifications"] = JsonObject.Create(JsonSerializer.SerializeToElement(
                classifications.OrderByDescending(kv => kv.Value).ToDictionary(kv => kv.Key, kv => kv.Value)))
        };

        // SQL tables — count unique tables from program sqlOperations
        var uniqueTables = new HashSet<string>(StringComparer.OrdinalIgnoreCase);
        var totalSqlOps = 0;
        foreach (var p in programs)
        {
            var ops = p?["sqlOperations"]?.AsArray() ?? [];
            totalSqlOps += ops.Count;
            foreach (var s in ops)
            {
                var tbl = s?["tableName"]?.GetValue<string>();
                if (!string.IsNullOrEmpty(tbl)) uniqueTables.Add(tbl);
            }
        }

        stats["sqlTables"] = new JsonObject
        {
            ["uniqueTables"] = uniqueTables.Count,
            ["totalSqlOperations"] = totalSqlOps
        };

        // Call graph
        var totalCalls = 0;
        var totalCopies = 0;
        var totalFileIO = 0;

        foreach (var p in programs)
        {
            totalCalls += p?["callTargets"]?.AsArray()?.Count ?? 0;
            totalCopies += p?["copyElements"]?.AsArray()?.Count ?? 0;
            totalFileIO += p?["fileIO"]?.AsArray()?.Count ?? 0;
        }

        stats["callGraph"] = new JsonObject
        {
            ["totalCallEdges"] = totalCalls,
            ["totalCopyElements"] = totalCopies,
            ["totalFileIO"] = totalFileIO
        };

        // Source verification summary
        var srcVerif = master["sourceVerification"];
        if (srcVerif != null)
        {
            var summary = srcVerif["summary"];
            stats["sourceVerification"] = new JsonObject
            {
                ["totalPrograms"] = summary?["totalPrograms"]?.GetValue<int>() ?? 0,
                ["programsFound"] = summary?["programsFound"]?.GetValue<int>() ?? 0,
                ["programFoundPct"] = summary?["programFoundPct"]?.GetValue<double>() ?? 0,
                ["totalCopies"] = summary?["totalCopies"]?.GetValue<int>() ?? 0,
                ["copiesFound"] = summary?["copiesFound"]?.GetValue<int>() ?? 0,
                ["copyFoundPct"] = summary?["copyFoundPct"]?.GetValue<double>() ?? 0
            };
        }

        // Boundary stats
        stats["boundaryStats"] = master["boundaryStats"]?.DeepClone() ?? new JsonObject();

        // Cache stats
        stats["cacheStats"] = new JsonObject
        {
            ["extractionCacheHits"] = cacheHits,
            ["extractionCacheMisses"] = cacheMisses
        };

        // Artifacts
        var artifacts = new JsonArray();
        if (Directory.Exists(runDir))
        {
            foreach (var f in Directory.GetFiles(runDir, "*.json"))
            {
                var fi = new FileInfo(f);
                artifacts.Add(new JsonObject
                {
                    ["file"] = fi.Name,
                    ["sizeKb"] = Math.Round(fi.Length / 1024.0, 1)
                });
            }
        }
        stats["artifacts"] = artifacts;

        // Save
        var outputPath = Path.Combine(runDir, "analysis_stats.json");
        File.WriteAllText(outputPath, stats.ToJsonString(JsonWriteOptions));
        Logger.Info($"  Per-profile stats saved to {outputPath}");

        return stats;
    }

    public static void GenerateCrossAnalysisStats(string analysisCommonPath, string analysisResultsRoot, string outputDir)
    {
        Logger.Info("=== Cross-Analysis Statistics ===");
        Directory.CreateDirectory(outputDir);

        var result = new JsonObject
        {
            ["generatedAt"] = DateTime.Now.ToString("yyyy-MM-ddTHH:mm:ss"),
            ["analysisCommonPath"] = analysisCommonPath,
            ["analysisResultsRoot"] = analysisResultsRoot
        };

        // Cache stats
        var objectsDir = Path.Combine(analysisCommonPath, "Objects");
        var objectCount = Directory.Exists(objectsDir) ? Directory.GetFiles(objectsDir, "*.json").Length : 0;
        var cblCount = Directory.Exists(objectsDir) ? Directory.GetFiles(objectsDir, "*.cbl.json").Length : 0;

        var tableNamesDir = Path.Combine(analysisCommonPath, "Naming", "TableNames");
        var tableNamesCount = Directory.Exists(tableNamesDir) ? Directory.GetFiles(tableNamesDir, "*.json").Length : 0;

        var colNamesDir = Path.Combine(analysisCommonPath, "Naming", "ColumnNames");
        var colNamesCount = Directory.Exists(colNamesDir) ? Directory.GetFiles(colNamesDir, "*.json").Length : 0;

        var progNamesDir = Path.Combine(analysisCommonPath, "Naming", "ProgramNames");
        var progNamesCount = Directory.Exists(progNamesDir) ? Directory.GetFiles(progNamesDir, "*.json").Length : 0;

        var businessAreasDir = Path.Combine(analysisCommonPath, "BusinessAreas");
        var businessAreasCount = Directory.Exists(businessAreasDir) ? Directory.GetFiles(businessAreasDir, "*.json").Length : 0;

        result["cacheStats"] = new JsonObject
        {
            ["objects"] = objectCount,
            ["programs"] = cblCount,
            ["tableNames"] = tableNamesCount,
            ["columnNames"] = colNamesCount,
            ["programNames"] = progNamesCount,
            ["businessAreas"] = businessAreasCount
        };
        Logger.Info($"  Cache: {objectCount} objects, {tableNamesCount} tableNames, {colNamesCount} columnNames, {progNamesCount} programNames, {businessAreasCount} businessAreas");

        // Load all profile masters — check alias-level copy first, then latest run dir
        var profiles = new Dictionary<string, JsonObject>();
        if (Directory.Exists(analysisResultsRoot))
        {
            foreach (var profileDir in Directory.GetDirectories(analysisResultsRoot))
            {
                var profileName = Path.GetFileName(profileDir);
                if (profileName.StartsWith("_")) continue;

                var masterPath = Path.Combine(profileDir, "dependency_master.json");
                if (!File.Exists(masterPath))
                {
                    var histDir = Path.Combine(profileDir, "_History");
                    if (Directory.Exists(histDir))
                    {
                        var latestRunDir = Directory.GetDirectories(histDir)
                            .OrderByDescending(d => Path.GetFileName(d))
                            .FirstOrDefault();
                        if (latestRunDir != null)
                            masterPath = Path.Combine(latestRunDir, "dependency_master.json");
                    }
                }
                if (!File.Exists(masterPath)) continue;

                try
                {
                    var masterNode = JsonNode.Parse(File.ReadAllText(masterPath))?.AsObject();
                    if (masterNode != null)
                        profiles[profileName] = masterNode;
                }
                catch { }
            }
        }

        Logger.Info($"  Profiles loaded: {string.Join(", ", profiles.Keys)}");

        // Profile summaries
        var profileSummary = new JsonArray();
        foreach (var (name, master) in profiles)
        {
            var progs = master["programs"]?.AsArray() ?? [];
            profileSummary.Add(new JsonObject
            {
                ["profile"] = name,
                ["programs"] = progs.Count,
                ["sqlTables"] = master["allSqlTables"]?.AsArray()?.Count ?? 0,
                ["database"] = master["database"]?.GetValue<string>() ?? ""
            });
        }
        result["profiles"] = profileSummary;

        // Program overlap
        var programsByProfile = new Dictionary<string, HashSet<string>>();
        foreach (var (name, master) in profiles)
        {
            var progs = master["programs"]?.AsArray() ?? [];
            programsByProfile[name] = progs.Select(p => p?["program"]?.GetValue<string>()?.ToUpperInvariant() ?? "")
                .Where(p => !string.IsNullOrEmpty(p)).ToHashSet();
        }

        var allPrograms = programsByProfile.Values.SelectMany(s => s).ToHashSet();
        var overlap2 = new HashSet<string>();
        var overlap3 = new HashSet<string>();
        var overlapAll = new HashSet<string>();
        var profileNames = programsByProfile.Keys.ToList();

        foreach (var prog in allPrograms)
        {
            int count = profileNames.Count(pn => programsByProfile[pn].Contains(prog));
            if (count >= 2) overlap2.Add(prog);
            if (count >= 3) overlap3.Add(prog);
            if (count == profileNames.Count) overlapAll.Add(prog);
        }

        result["programOverlap"] = new JsonObject
        {
            ["totalUniquePrograms"] = allPrograms.Count,
            ["in2OrMoreProfiles"] = overlap2.Count,
            ["in3OrMoreProfiles"] = overlap3.Count,
            ["inAllProfiles"] = overlapAll.Count,
            ["overlappingPrograms"] = new JsonArray(overlap2.OrderBy(p => p).Take(200).Select(p => (JsonNode)JsonValue.Create(p)!).ToArray())
        };
        Logger.Info($"  Program overlap: {allPrograms.Count} unique, {overlap2.Count} in 2+, {overlapAll.Count} in all");

        // Table overlap
        var tablesByProfile = new Dictionary<string, HashSet<string>>();
        foreach (var (name, master) in profiles)
        {
            var tables = master["allSqlTables"]?.AsArray() ?? [];
            tablesByProfile[name] = tables.Select(t => t?["qualifiedName"]?.GetValue<string>()?.ToUpperInvariant() ?? "")
                .Where(t => !string.IsNullOrEmpty(t)).ToHashSet();
        }

        var allTables = tablesByProfile.Values.SelectMany(s => s).ToHashSet();
        var tableOverlap2 = allTables.Count(t => profileNames.Count(pn => tablesByProfile.GetValueOrDefault(pn)?.Contains(t) == true) >= 2);
        var tableOverlapAll = allTables.Count(t => profileNames.All(pn => tablesByProfile.GetValueOrDefault(pn)?.Contains(t) == true));

        result["tableOverlap"] = new JsonObject
        {
            ["totalUniqueTables"] = allTables.Count,
            ["in2OrMoreProfiles"] = tableOverlap2,
            ["inAllProfiles"] = tableOverlapAll
        };

        // History snapshots
        var historyArr = new JsonArray();
        if (Directory.Exists(analysisResultsRoot))
        {
            foreach (var profileDir in Directory.GetDirectories(analysisResultsRoot))
            {
                var profileName = Path.GetFileName(profileDir);
                if (profileName.StartsWith("_")) continue;

                var histDir = Path.Combine(profileDir, "_History");
                var runs = Directory.Exists(histDir)
                    ? Directory.GetDirectories(histDir).Select(Path.GetFileName).OrderByDescending(d => d).ToList()
                    : [];
                historyArr.Add(new JsonObject
                {
                    ["profile"] = profileName,
                    ["runs"] = runs.Count,
                    ["latest"] = runs.FirstOrDefault() ?? ""
                });
            }
        }
        result["history"] = historyArr;

        // Write summary JSON
        File.WriteAllText(Path.Combine(outputDir, "cross_analysis_stats.json"), result.ToJsonString(JsonWriteOptions));

        // Write markdown tables
        WriteMarkdownTables(outputDir, result, profiles);

        Logger.Info($"  Cross-analysis stats saved to {outputDir}");
    }

    private static void WriteMarkdownTables(string outputDir, JsonObject stats, Dictionary<string, JsonObject> profiles)
    {
        var lines = new List<string>
        {
            "# SystemAnalyzer Cross-Analysis Report",
            "",
            $"Generated: {stats["generatedAt"]}",
            "",
            "## Profile Summary",
            "",
            "| Profile | Programs | SQL Tables | Database |",
            "|---------|----------|------------|----------|"
        };

        foreach (var ps in stats["profiles"]?.AsArray() ?? [])
        {
            lines.Add($"| {ps?["profile"]} | {ps?["programs"]} | {ps?["sqlTables"]} | {ps?["database"]} |");
        }

        lines.AddRange([
            "",
            "## Program Breakdown",
            "",
            "| Profile | Total | Original | Call-Expanded | Table-Discovered | Deprecated |",
            "|---------|-------|----------|---------------|------------------|------------|"
        ]);

        foreach (var (name, master) in profiles)
        {
            var progs = master["programs"]?.AsArray() ?? [];
            int total = progs.Count;
            int orig = progs.Count(p => p?["layer"]?.GetValue<string>() == "original");
            int callExp = progs.Count(p => p?["layer"]?.GetValue<string>() == "call-expanded");
            int tableDis = progs.Count(p => p?["layer"]?.GetValue<string>() == "table-discovered");
            int depr = progs.Count(p => p?["isDeprecated"]?.GetValue<bool>() == true);
            lines.Add($"| {name} | {total} | {orig} | {callExp} | {tableDis} | {depr} |");
        }

        lines.AddRange([
            "",
            "## Source Verification",
            "",
            "| Profile | Programs Found % | Copies Found % |",
            "|---------|-----------------|----------------|"
        ]);

        foreach (var (name, master) in profiles)
        {
            var sv = master["sourceVerification"]?["summary"];
            lines.Add($"| {name} | {sv?["programFoundPct"]}% | {sv?["copyFoundPct"]}% |");
        }

        lines.AddRange([
            "",
            "## DB2 Validation",
            "",
            "| Profile | Tables | In DB2 | Not In DB2 | Validation % |",
            "|---------|--------|--------|------------|--------------|"
        ]);

        foreach (var (name, master) in profiles)
        {
            var tables = master["allSqlTables"]?.AsArray() ?? [];
            var inDb2 = tables.Count(t => t?["existsInDb2"]?.GetValue<bool>() == true);
            var notInDb2 = tables.Count - inDb2;
            var pct = tables.Count > 0 ? Math.Round(100.0 * inDb2 / tables.Count, 1) : 0;
            lines.Add($"| {name} | {tables.Count} | {inDb2} | {notInDb2} | {pct}% |");
        }

        lines.AddRange([
            "",
            "## Cache Stats",
            "",
            "| Category | Count |",
            "|----------|-------|"
        ]);

        var cs = stats["cacheStats"];
        if (cs != null)
        {
            lines.Add($"| Objects (extraction cache) | {cs["objects"]} |");
            lines.Add($"| Programs (COBOL) | {cs["programs"]} |");
            lines.Add($"| Table Names | {cs["tableNames"]} |");
            lines.Add($"| Column Names | {cs["columnNames"]} |");
            lines.Add($"| Program Names | {cs["programNames"]} |");
            lines.Add($"| Business Areas | {cs["businessAreas"]} |");
        }

        var overlap = stats["programOverlap"];
        lines.AddRange([
            "",
            "## Program Overlap",
            "",
            "| Metric | Count |",
            "|--------|-------|",
            $"| Total unique programs | {overlap?["totalUniquePrograms"]} |",
            $"| In 2+ profiles | {overlap?["in2OrMoreProfiles"]} |",
            $"| In 3+ profiles | {overlap?["in3OrMoreProfiles"]} |",
            $"| In all profiles | {overlap?["inAllProfiles"]} |"
        ]);

        File.WriteAllText(Path.Combine(outputDir, "_readme_tables.md"), string.Join("\n", lines));
    }
}
