using System.Globalization;
using System.Text.Json;
using System.Text.Json.Nodes;
using System.Text.RegularExpressions;
using NLog;
using SystemAnalyzer.Batch.Models;
using SystemAnalyzer.Batch.Services;
using SystemAnalyzer.Core.Models;
using SystemAnalyzer.Core.Services;

namespace SystemAnalyzer.Batch;

public sealed class FullAnalysisPipeline
{
    private static readonly Logger Logger = LogManager.GetCurrentClassLogger();
    private static readonly JsonSerializerOptions JsonWriteOptions = new() { WriteIndented = true };
    // V1 uses PowerShell Sort-Object which defaults to CurrentCulture (nb-NO).
    // In Norwegian, 'AA' digraph sorts as 'Å' (after Z), so GMAAKTI sorts after GMFTRAP.
    private static readonly StringComparer NbNoComparer =
        StringComparer.Create(new CultureInfo("nb-NO"), ignoreCase: true);

    private readonly SystemAnalyzerOptions _options;
    private readonly RagClient _ragClient;
    private readonly Db2Client _db2Client;
    private readonly OllamaClient _ollamaClient;
    private readonly SourceIndexService _sourceIndex;
    private readonly CacheService _cacheService;
    private readonly DependencyExtractor _extractor;
    private readonly ClassificationService _classifier;
    private readonly ReportService _reportService;
    private readonly CatalogExportService _catalogExportService;
    private readonly NamingService _namingService;
    private readonly HttpClient _httpClient;

    private readonly HashSet<string> _noisePrograms = new(StringComparer.OrdinalIgnoreCase)
    {
        "---","CALL","PIC","OG","CC1","PAYD","DISPLAY","DISPL1","DISPL2","SLUTT","AVSLUTT","INS","IS",
        "COB32API","DB2API","WIN32","WINAPI","WW-DS","WW-PROG",
        "SYSFILETREE","SYSLOADFUNCS","SYSSLEEP","RXFUNCADD","START_REXX",
        "INVOKE-MESSAGE-BOX","ENABLE-OBJECT","DISABLE-OBJECT","REFRESH-OBJECT","DIALOG-SYSTEM"
    };

    public FullAnalysisPipeline(
        SystemAnalyzerOptions options, RagClient ragClient, Db2Client db2Client,
        OllamaClient ollamaClient, SourceIndexService sourceIndex, CacheService cacheService,
        DependencyExtractor extractor, ClassificationService classifier, ReportService reportService,
        CatalogExportService catalogExportService, NamingService namingService, HttpClient httpClient)
    {
        _options = options;
        _ragClient = ragClient;
        _db2Client = db2Client;
        _ollamaClient = ollamaClient;
        _sourceIndex = sourceIndex;
        _cacheService = cacheService;
        _extractor = extractor;
        _classifier = classifier;
        _reportService = reportService;
        _catalogExportService = catalogExportService;
        _namingService = namingService;
        _httpClient = httpClient;
    }

    private readonly Dictionary<string, string> _programLayers = new(StringComparer.OrdinalIgnoreCase);

    private HashSet<string> _catalogQualified = new(StringComparer.OrdinalIgnoreCase);
    private HashSet<string> _catalogPackages = new(StringComparer.OrdinalIgnoreCase);
    private HashSet<string> _seedSet = new(StringComparer.OrdinalIgnoreCase);
    private string _profileDatabase = "";
    private string _catalogDb2Alias = "";
    private JsonArray? _allJsonEntries;

    // V1 $script:boundaryStripped: programs that had SOME SQL ops stripped (key=program, value=stripped table names)
    private readonly Dictionary<string, string[]> _boundaryStripped = new(StringComparer.OrdinalIgnoreCase);
    // V1 $script:boundaryRejections: programs whose ALL SQL was foreign (removed from master)
    private readonly Dictionary<string, string[]> _sqlBoundaryRejections = new(StringComparer.OrdinalIgnoreCase);
    // V1 $script:packageRejections: programs not in catalogPackages (separate from SQL boundary)
    private readonly Dictionary<string, string> _packageRejections = new(StringComparer.OrdinalIgnoreCase);

    // COBDOK modul.csv enrichment (V1 lines 200-220)
    private readonly Dictionary<string, CobdokEntry> _cobdokIndex = new(StringComparer.OrdinalIgnoreCase);

    public async Task<int> RunAsync(AnalysisRunRequest request)
    {
        var sw = System.Diagnostics.Stopwatch.StartNew();
        var skipPhases = new HashSet<int>(request.SkipPhases);

        var timestamp = DateTime.Now.ToString("yyyyMMdd_HHmmss");
        var alias = SanitizeAlias(request.Alias);
        if (string.IsNullOrEmpty(alias)) alias = "Analysis";

        var dataRoot = _options.DataRoot;
        Directory.CreateDirectory(dataRoot);

        var aliasDir = Path.Combine(dataRoot, alias);
        var historyDir = Path.Combine(aliasDir, "_History");
        var runDir = Path.Combine(historyDir, $"{alias}_{timestamp}");
        Directory.CreateDirectory(runDir);

        Logger.Info($"Run folder: {runDir}");
        Logger.Info($"Alias folder: {aliasDir}");

        var masterJsonPath = Path.Combine(runDir, "dependency_master.json");

        var master = new JsonObject
        {
            ["title"] = "COBOL Dependency Master",
            ["generated"] = DateTime.Now.ToString("yyyy-MM-dd HH:mm:ss"),
            ["programs"] = new JsonArray()
        };

        // Phase 0: Catalog export (if not skipped)
        _cacheService.InitializeAnalysisCommonCache();
        _cacheService.InitializeNamingCache();

        var allJson = JsonNode.Parse(File.ReadAllText(request.AllJsonPath))!;
        _profileDatabase = allJson["database"]?.GetValue<string>() ?? "";

        if (!request.SkipCatalog && !string.IsNullOrEmpty(_profileDatabase))
        {
            WritePhase(0, $"DB2 Catalog Export for {_profileDatabase}");
            var catalogDir = Path.Combine(_options.AnalysisCommonPath ?? "", "Databases", _profileDatabase);
            var exported = await _catalogExportService.ExportCatalogAsync(
                _profileDatabase, catalogDir, request.RefreshCatalogs);
            if (!exported)
                Logger.Warn($"  Catalog export failed for {_profileDatabase} — boundary filtering may be incomplete");
        }

        // Phase 1: Load seeds and build source index
        WritePhase(1, "Load seed programs and index local source tree");
        _sourceIndex.BuildIndex();
        LoadCobdokCsv();

        var seedPrograms = allJson["entries"]!.AsArray()
            .Select(e => e!["program"]!.GetValue<string>())
            .Where(p => !string.IsNullOrEmpty(p) && p.Length >= 2)
            .Distinct(StringComparer.OrdinalIgnoreCase)
            .OrderBy(p => p)
            .ToList();

        Logger.Info($"  Seed programs from all.json: {seedPrograms.Count}");

        _seedSet = new HashSet<string>(seedPrograms.Select(s => s.ToUpperInvariant()), StringComparer.OrdinalIgnoreCase);
        _allJsonEntries = allJson["entries"]?.AsArray();

        // Load database boundary catalogs (matching V1)
        LoadDatabaseBoundary();

        // Store boundary info in master
        if (!string.IsNullOrEmpty(_profileDatabase))
        {
            master["database"] = _profileDatabase;
            master["db2Alias"] = _catalogDb2Alias;
        }

        File.Copy(request.AllJsonPath, Path.Combine(runDir, "all.json"), true);

        // Phase 2: Extract dependencies for seed programs
        if (!skipPhases.Contains(2))
        {
            WritePhase(2, $"Extract seed program dependencies ({seedPrograms.Count} programs)");
            foreach (var prog in seedPrograms)
            {
                _programLayers.TryAdd(prog.ToUpperInvariant(), "original");
                await ExtractProgramAsync(prog, master);
            }

            // Apply SQL boundary filter to seed programs (V1: Filter-SqlByBoundary per seed)
            if (_catalogQualified.Count > 0)
            {
                int seedStripped = 0;
                foreach (var p in master["programs"]!.AsArray())
                {
                    var progName = p!["program"]!.GetValue<string>();
                    var sqlOps = p["sqlOperations"]?.Deserialize<List<JsonObject>>() ?? [];
                    var filtered = FilterSqlByBoundary(sqlOps);
                    if (filtered.Count < sqlOps.Count)
                    {
                        var strippedTables = sqlOps.Except(filtered)
                            .Select(s => s["tableName"]?.GetValue<string>() ?? "").Distinct().ToArray();
                        _boundaryStripped[progName] = strippedTables;
                        seedStripped += sqlOps.Count - filtered.Count;
                        p["sqlOperations"] = JsonSerializer.SerializeToNode(filtered);
                    }
                }
                if (seedStripped > 0)
                    Logger.Info($"  Boundary filter: stripped {seedStripped} non-matching SQL ops from seed programs");
            }

            SaveMaster(master, masterJsonPath);
        }

        // Phase 3: CALL expansion (with V1-matching call target validation + boundary filtering)
        if (!skipPhases.Contains(3))
        {
            WritePhase(3, $"Discover programs via CALL targets (max {_options.MaxCallIterations} iterations)");
            var knownPrograms = new HashSet<string>(seedPrograms.Select(s => s.ToUpperInvariant()), StringComparer.OrdinalIgnoreCase);
            var validProgramNames = new HashSet<string>(_sourceIndex.CblIndex.Keys, StringComparer.OrdinalIgnoreCase);
            foreach (var k in _sourceIndex.FullIndex.Keys) validProgramNames.Add(k);

            var packageRejections = _packageRejections;
            var localSqlBoundaryRejections = _sqlBoundaryRejections;

            for (int iter = 0; iter < _options.MaxCallIterations; iter++)
            {
                var allCalls = new HashSet<string>(StringComparer.OrdinalIgnoreCase);
                foreach (var p in master["programs"]!.AsArray())
                {
                    foreach (var c in p!["callTargets"]?.AsArray() ?? [])
                    {
                        var cn = c!.GetValue<string>();
                        if (!string.IsNullOrEmpty(cn) && !_noisePrograms.Contains(cn) &&
                            await _extractor.TestValidCallTargetWithRagAsync(cn, _ragClient, validProgramNames))
                        {
                            allCalls.Add(cn.ToUpperInvariant());
                        }
                    }
                }

                var newTargets = allCalls.Where(t => !knownPrograms.Contains(t))
                    .OrderBy(t => t).ToList();

                if (newTargets.Count == 0)
                {
                    Logger.Info($"  Iteration {iter + 1}: No new CALL targets found. Stopping.");
                    break;
                }

                Logger.Info($"  Iteration {iter + 1}: {newTargets.Count} new CALL targets");
                int localCount = 0, ragCount = 0, packageFiltered = 0, boundaryRejected = 0;

                foreach (var target in newTargets)
                {
                    knownPrograms.Add(target);

                    // Package boundary: reject programs not in catalog packages (matching V1)
                    if (_catalogPackages.Count > 0 && !_seedSet.Contains(target) && !_catalogPackages.Contains(target))
                    {
                        packageRejections.TryAdd(target, "call-expansion");
                        packageFiltered++;
                        continue;
                    }

                    _programLayers.TryAdd(target, "call-expansion");
                    await ExtractProgramAsync(target, master);

                    // Apply SQL boundary filter
                    var lastProg = master["programs"]!.AsArray().LastOrDefault();
                    if (lastProg != null)
                    {
                        var srcType = lastProg["sourceType"]?.GetValue<string>() ?? "";
                        if (srcType.StartsWith("local-")) localCount++; else ragCount++;

                        if (_catalogQualified.Count > 0)
                        {
                            var sqlOps = lastProg["sqlOperations"]?.Deserialize<List<JsonObject>>() ?? [];
                            var filtered = FilterSqlByBoundary(sqlOps);
                            if (filtered.Count < sqlOps.Count)
                            {
                                var strippedTables = sqlOps.Except(filtered)
                                    .Select(s => s["tableName"]?.GetValue<string>() ?? "").Distinct().ToArray();
                                _boundaryStripped[target] = strippedTables;
                            }
                            if (sqlOps.Count > 0 && filtered.Count == 0)
                            {
                                var tables = sqlOps.Select(s => s["tableName"]?.GetValue<string>() ?? "").Distinct().ToArray();
                                localSqlBoundaryRejections.TryAdd(target, tables);
                                master["programs"]!.AsArray().Remove(lastProg);
                                boundaryRejected++;
                                continue;
                            }
                            if (filtered.Count < sqlOps.Count)
                            {
                                lastProg["sqlOperations"] = JsonSerializer.SerializeToNode(filtered);
                            }
                        }
                    }
                }
                Logger.Info($"  Iteration {iter + 1}: {localCount} local | {ragCount} RAG | {packageFiltered} package-rejected | {boundaryRejected} boundary-rejected");
                SaveMaster(master, masterJsonPath);
            }

            if (packageRejections.Count > 0)
                Logger.Info($"  Package boundary rejections: {packageRejections.Count} programs not bound in {_profileDatabase}");
            if (localSqlBoundaryRejections.Count > 0)
                Logger.Info($"  Database boundary rejections: {localSqlBoundaryRejections.Count} programs (tables outside {_profileDatabase})");
        }

        // Phase 4: DB2 table validation
        if (!skipPhases.Contains(4))
        {
            WritePhase(4, "Validate SQL tables against database catalog");
            var validationResult = ValidateSqlTables(master);
            var validationPath = Path.Combine(runDir, "db2_table_validation.json");
            File.WriteAllText(validationPath, validationResult.ToJsonString(JsonWriteOptions));

            // Phase 4b: Enrich sqltable.json files with DB2 column metadata
            if (!string.IsNullOrEmpty(_profileDatabase))
            {
                await EnrichSqlTablesWithDb2MetadataAsync();
            }
        }

        // Phase 5: Discover programs via shared SQL tables
        if (!skipPhases.Contains(5))
        {
            WritePhase(5, "Discover new programs via shared SQL tables");
            await DiscoverProgramsViaSqlTablesAsync(master);
            SaveMaster(master, masterJsonPath);
        }

        // Phase 6: Extract table-discovered programs (V1 lines 2113-2138)
        if (!skipPhases.Contains(6))
        {
            var tableNewProgs = _programLayers
                .Where(kv => kv.Value == "table-reference")
                .Select(kv => kv.Key)
                .OrderBy(k => k)
                .ToList();

            if (tableNewProgs.Count > 0)
            {
                WritePhase(6, $"Extract {tableNewProgs.Count} table-discovered programs");
                int localCount = 0, ragCount = 0, boundaryRejected = 0;
                foreach (var prog in tableNewProgs)
                {
                    await ExtractProgramAsync(prog, master);
                    var lastProg = master["programs"]!.AsArray()
                        .FirstOrDefault(p => p!["program"]!.GetValue<string>().Equals(prog, StringComparison.OrdinalIgnoreCase));
                    if (lastProg != null)
                    {
                        var srcType = lastProg["sourceType"]?.GetValue<string>() ?? "";
                        if (srcType.StartsWith("local-")) localCount++; else ragCount++;

                        // Apply SQL boundary filter (V1: Filter-SqlByBoundary tracks stripping before rejection)
                        if (_catalogQualified.Count > 0)
                        {
                            var sqlOps = lastProg["sqlOperations"]?.Deserialize<List<JsonObject>>() ?? [];
                            var filtered = FilterSqlByBoundary(sqlOps);
                            if (filtered.Count < sqlOps.Count)
                            {
                                var strippedTables = sqlOps.Except(filtered)
                                    .Select(s => s["tableName"]?.GetValue<string>() ?? "").Distinct().ToArray();
                                _boundaryStripped[prog] = strippedTables;
                            }
                            if (sqlOps.Count > 0 && filtered.Count == 0)
                            {
                                var rejectedTables = sqlOps.Select(s => s["tableName"]?.GetValue<string>() ?? "").Distinct().ToArray();
                                _sqlBoundaryRejections[prog] = rejectedTables;
                                master["programs"]!.AsArray().Remove(lastProg);
                                boundaryRejected++;
                                continue;
                            }
                            if (filtered.Count < sqlOps.Count)
                            {
                                lastProg["sqlOperations"] = JsonSerializer.SerializeToNode(filtered);
                            }
                        }
                    }
                }
                Logger.Info($"  Done: {localCount} local | {ragCount} RAG | {boundaryRejected} boundary-rejected");
                SaveMaster(master, masterJsonPath);
            }
        }

        // Database boundary sweep — prune non-seed programs and clean call targets (matching V1)
        if (_catalogQualified.Count > 0 || _catalogPackages.Count > 0)
        {
            int packageRemoved = 0, boundaryRemoved = 0;

            if (_catalogPackages.Count > 0)
            {
                var keysToRemove = new List<int>();
                var programs = master["programs"]!.AsArray();
                for (int i = programs.Count - 1; i >= 0; i--)
                {
                    var prog = programs[i]!["program"]!.GetValue<string>();
                    if (_seedSet.Contains(prog)) continue;
                    if (!_catalogPackages.Contains(prog))
                    {
                        programs.RemoveAt(i);
                        packageRemoved++;
                    }
                }
                if (packageRemoved > 0)
                {
                    Logger.Info($"  Package boundary sweep: removed {packageRemoved} programs");
                    SaveMaster(master, masterJsonPath);
                }
            }

            if (_catalogQualified.Count > 0)
            {
                var programs = master["programs"]!.AsArray();
                for (int i = programs.Count - 1; i >= 0; i--)
                {
                    var prog = programs[i]!;
                    var progName = prog["program"]!.GetValue<string>();
                    if (_seedSet.Contains(progName)) continue;
                    var sqlOps = prog["sqlOperations"]?.Deserialize<List<JsonObject>>() ?? [];
                    var filtered = FilterSqlByBoundary(sqlOps);
                    if (filtered.Count < sqlOps.Count)
                    {
                        var strippedTables = sqlOps.Except(filtered)
                            .Select(s => s["tableName"]?.GetValue<string>() ?? "").Distinct().ToArray();
                        _boundaryStripped[progName] = strippedTables;
                    }
                    if (sqlOps.Count > 0 && filtered.Count == 0)
                    {
                        var rejectedTables = sqlOps.Select(s => s["tableName"]?.GetValue<string>() ?? "").Distinct().ToArray();
                        _sqlBoundaryRejections[progName] = rejectedTables;
                        programs.RemoveAt(i);
                        boundaryRemoved++;
                        continue;
                    }
                    if (filtered.Count < sqlOps.Count)
                    {
                        prog["sqlOperations"] = JsonSerializer.SerializeToNode(filtered);
                    }
                }
                if (boundaryRemoved > 0)
                {
                    Logger.Info($"  Table boundary sweep: removed {boundaryRemoved} programs");
                    SaveMaster(master, masterJsonPath);
                }
            }

            // Prune call targets: only keep targets that are in master (matching V1)
            var masterProgSet = new HashSet<string>(
                master["programs"]!.AsArray().Select(p => p!["program"]!.GetValue<string>()),
                StringComparer.OrdinalIgnoreCase);

            foreach (var p in master["programs"]!.AsArray())
            {
                var callTargets = p!["callTargets"]?.AsArray();
                if (callTargets == null || callTargets.Count == 0) continue;
                var cleaned = callTargets
                    .Select(c => c!.GetValue<string>())
                    .Where(cn => masterProgSet.Contains(cn))
                    .ToList();
                p["callTargets"] = JsonSerializer.SerializeToNode(cleaned);
            }
            SaveMaster(master, masterJsonPath);

            Logger.Info($"  Programs after boundary filter: {master["programs"]!.AsArray().Count}");
        }

        // Phase 7: Source verification
        if (!skipPhases.Contains(7))
        {
            WritePhase(7, "Source verification and classification");
            var verifyResult = BuildSourceVerification(master);
            File.WriteAllText(Path.Combine(runDir, "source_verification.json"),
                verifyResult.ToJsonString(JsonWriteOptions));

            if (!request.SkipClassification)
            {
                await ClassifyAllProgramsAsync(master, runDir);
            }
        }

        // Phase 8: Cross-reference outputs
        WritePhase(8, "Produce cross-reference output JSONs");
        ProduceCrossReferenceOutputs(master, runDir, alias);

        // Phase 8f: Naming generation via Ollama (table names, column names, program names)
        if (!request.SkipNaming)
        {
            WritePhase(8, "Phase 8f — Naming generation via Ollama");
            await RunNamingPhaseAsync(master, alias);
        }

        // Inject naming cache data (V1 Phase 8f: futureProjectName, futureTableName, tableNaming)
        InjectNamingData(master);

        // Phase 8g: Business area classification via Ollama
        if (!request.SkipNaming)
        {
            WritePhase(8, "Phase 8g — Business area classification via Ollama");
            var businessAreas = await _namingService.ClassifyBusinessAreasAsync(master["programs"]!.AsArray(), alias);
            if (businessAreas != null)
            {
                File.WriteAllText(Path.Combine(runDir, "business_areas.json"),
                    businessAreas.ToJsonString(JsonWriteOptions));
            }
        }

        // Phase 8h: Merge user overrides into business_areas.json
        var overridePath = Path.Combine(_options.AnalysisOverridePath, "BusinessAreas", $"{alias}_overrides.json");
        if (File.Exists(overridePath))
        {
            var baPath = Path.Combine(runDir, "business_areas.json");
            BusinessAreaMergeService.MergeAndSave(baPath, overridePath, baPath);
            Logger.Info($"  Business area overrides merged from {overridePath}");
        }

        // Sort programs alphabetically (V1 line 1633: $Master.Keys | Sort-Object)
        var sortedPrograms = master["programs"]!.AsArray()
            .OrderBy(p => p!["program"]!.GetValue<string>(), NbNoComparer)
            .Select(p => p!.DeepClone())
            .ToList();
        var sortedArr = new JsonArray();
        foreach (var p in sortedPrograms) sortedArr.Add(p);
        master["programs"] = sortedArr;

        // Update master totals and boundary stats (V1 line 1649-1655)
        master["totalPrograms"] = master["programs"]!.AsArray().Count;
        if (!string.IsNullOrEmpty(_profileDatabase))
        {
            master["database"] = _profileDatabase;
            master["db2Alias"] = _catalogDb2Alias;
        }
        if (_catalogQualified.Count > 0)
        {
            master["boundaryStats"] = new JsonObject
            {
                ["database"] = _profileDatabase,
                ["catalogQualified"] = _catalogQualified.Count,
                ["programsRejected"] = _sqlBoundaryRejections.Count,
                ["sqlOpsStripped"] = _boundaryStripped.Count
            };
            Logger.Info($"  Boundary stripped programs ({_boundaryStripped.Count}): {string.Join(", ", _boundaryStripped.Keys.OrderBy(k => k))}");
        }

        // Add tableNaming section (V1 line 3228-3246)
        var tableNaming = BuildTableNamingSection(master);
        if (tableNaming.Count > 0)
            master["tableNaming"] = tableNaming;

        SaveMaster(master, masterJsonPath);

        // Generate summary and per-profile stats before copying to alias folder
        _reportService.WriteRunSummaryMarkdown(runDir);

        sw.Stop();
        var profileStats = StatsService.GenerateProfileStats(master, runDir,
            _cacheService.ExtractionCacheHits, _cacheService.ExtractionCacheMisses, sw.Elapsed);

        // Copy latest to alias folder (includes analysis_stats.json and summary)
        CopyToAliasFolder(runDir, aliasDir);

        // Cross-analysis stats if requested (after copy so individual profile data is in alias folders)
        if (request.GenerateStats)
        {
            var statsDir = Path.Combine(Path.GetDirectoryName(_options.DataRoot.TrimEnd('\\', '/'))!, "AnalysisStats");
            StatsService.GenerateCrossAnalysisStats(
                _options.AnalysisCommonPath ?? "", _options.DataRoot, statsDir);
        }

        Logger.Info($"Pipeline complete in {sw.Elapsed:hh\\:mm\\:ss}");
        Logger.Info($"  Run folder: {runDir}");
        Logger.Info($"  Alias folder: {aliasDir}");
        if (_cacheService.Enabled)
            Logger.Info($"  Extraction cache: {_cacheService.ExtractionCacheHits} hits, {_cacheService.ExtractionCacheMisses} new");
        if (!request.SkipNaming)
            Logger.Info($"  Naming: {_namingService.TableNamingNew} tables, {_namingService.ColumnNamingNew} columns, {_namingService.ProgramNamingNew} programs (new)");

        return 0;
    }

    private async Task ExtractProgramAsync(string program, JsonObject master)
    {
        var norm = program.ToUpperInvariant();
        if (_noisePrograms.Contains(norm)) return;

        var existing = master["programs"]!.AsArray()
            .FirstOrDefault(p => p!["program"]!.GetValue<string>().Equals(norm, StringComparison.OrdinalIgnoreCase));
        if (existing != null) return;

        var resolution = _sourceIndex.ResolveProgramSource(norm);
        bool isLocal = resolution.Type.StartsWith("local-");
        string? text = null;
        string? sourceHash = null;

        if (isLocal && resolution.Path != null)
        {
            try
            {
                text = File.ReadAllText(resolution.Path);
                using var sha = System.Security.Cryptography.SHA256.Create();
                sourceHash = "sha256:" + Convert.ToHexStringLower(sha.ComputeHash(System.Text.Encoding.UTF8.GetBytes(text)));
            }
            catch { }
        }

        // V1 extraction cache: if source hash matches, return cached data without re-extracting
        var cachedExtraction = _cacheService.GetCachedFact(norm, "extraction");
        if (cachedExtraction != null)
        {
            var cachedHash = cachedExtraction["sourceHash"]?.GetValue<string?>();
            bool cacheValid = (sourceHash != null && cachedHash == sourceHash)
                           || (!isLocal && string.IsNullOrEmpty(cachedHash));
            if (cacheValid)
            {
                var entry = new JsonObject
                {
                    ["program"] = cachedExtraction["program"]?.GetValue<string>() ?? norm,
                    ["sourceType"] = cachedExtraction["sourceType"]?.GetValue<string>() ?? resolution.Type,
                    ["sourcePath"] = cachedExtraction["sourcePath"]?.GetValue<string>() ?? resolution.Path,
                    ["actualName"] = cachedExtraction["actualName"]?.GetValue<string>() ?? resolution.ActualName,
                    ["copyElements"] = cachedExtraction["copyElements"]?.DeepClone() ?? new JsonArray(),
                    ["sqlOperations"] = cachedExtraction["sqlOperations"]?.DeepClone() ?? new JsonArray(),
                    ["callTargets"] = cachedExtraction["callTargets"]?.DeepClone() ?? new JsonArray(),
                    ["fileIO"] = cachedExtraction["fileIO"]?.DeepClone() ?? new JsonArray(),
                };
                master["programs"]!.AsArray().Add(entry);
                _cacheService.ExtractionCacheHits++;
                return;
            }
        }

        if (string.IsNullOrEmpty(text))
        {
            var ragQueries = new[]
            {
                $"{norm}.cbl source code",
                $"{norm} COPY EXEC SQL CALL",
                $"{norm} PROCEDURE DIVISION",
                $"{norm} SELECT ASSIGN FILE-CONTROL OPEN"
            };

            var chunks = new List<string>();
            foreach (var query in ragQueries)
            {
                var chunk = await _ragClient.InvokeRagAsync(query, _options.RagResults);
                if (!string.IsNullOrEmpty(chunk) && !chunk.StartsWith("Error:"))
                    chunks.Add(chunk);
            }

            if (chunks.Count > 0)
                text = string.Join("\n\n", chunks);
        }

        var newEntry = new JsonObject
        {
            ["program"] = norm,
            ["sourceType"] = resolution.Type,
            ["sourcePath"] = resolution.Path,
            ["actualName"] = resolution.ActualName,
        };

        if (!string.IsNullOrEmpty(text))
        {
            var copyElements = _extractor.GetCopyElements(text);
            newEntry["copyElements"] = JsonSerializer.SerializeToNode(copyElements);

            var sqlOps = _extractor.GetSqlOperations(text);
            newEntry["sqlOperations"] = JsonSerializer.SerializeToNode(sqlOps);

            var callTargets = _extractor.GetCallTargets(text);
            newEntry["callTargets"] = JsonSerializer.SerializeToNode(callTargets);

            var fileIO = _extractor.GetFileIO(text, _options.DefaultFilePath);
            ResolveVariableFilenamesFromCache(norm, fileIO);
            newEntry["fileIO"] = JsonSerializer.SerializeToNode(fileIO);
        }
        else
        {
            newEntry["copyElements"] = new JsonArray();
            newEntry["sqlOperations"] = new JsonArray();
            newEntry["callTargets"] = new JsonArray();
            newEntry["fileIO"] = new JsonArray();
        }

        master["programs"]!.AsArray().Add(newEntry);

        // V1 Save-CachedFact: persist extraction to AnalysisCommon/Objects/{PROGRAM}.cbl.json
        _cacheService.SaveCachedFact(norm, "extraction", new JsonObject
        {
            ["sourceHash"] = sourceHash,
            ["sourceType"] = resolution.Type,
            ["sourcePath"] = resolution.Path,
            ["actualName"] = resolution.ActualName,
            ["program"] = norm,
            ["copyElements"] = newEntry["copyElements"]?.DeepClone() ?? new JsonArray(),
            ["sqlOperations"] = newEntry["sqlOperations"]?.DeepClone() ?? new JsonArray(),
            ["callTargets"] = newEntry["callTargets"]?.DeepClone() ?? new JsonArray(),
            ["fileIO"] = newEntry["fileIO"]?.DeepClone() ?? new JsonArray(),
            ["extractedAt"] = DateTime.Now.ToString("yyyy-MM-ddTHH:mm:ss")
        });
        _cacheService.ExtractionCacheMisses++;
    }

    private JsonObject ValidateSqlTables(JsonObject master)
    {
        var uniqueTables = new Dictionary<string, JsonObject>(StringComparer.OrdinalIgnoreCase);
        foreach (var p in master["programs"]!.AsArray())
        {
            foreach (var s in p!["sqlOperations"]?.AsArray() ?? [])
            {
                var schema = s!["schema"]?.GetValue<string>() ?? "";
                var tableName = s["tableName"]?.GetValue<string>() ?? "";
                if (string.IsNullOrEmpty(tableName)) continue;
                var isQualified = schema.Length > 1 && schema != "(UNQUALIFIED)";
                var qn = isQualified ? $"{schema}.{tableName}" : tableName;

                if (uniqueTables.ContainsKey(qn)) continue;
                bool? exists = null;
                if (_catalogQualified.Count > 0 && isQualified)
                    exists = _catalogQualified.Contains(qn);

                uniqueTables[qn] = new JsonObject
                {
                    ["schema"] = isQualified ? schema : null,
                    ["tableName"] = tableName,
                    ["qualifiedName"] = isQualified ? qn : null,
                    ["existsInDb2"] = exists
                };
            }
        }

        // V1: save each unique table as *.sqltable.json in AnalysisCommon/Objects/
        // Write flat format (V1-compatible): tableName, schema, db2Metadata all at root level.
        // Do NOT use SaveCachedFact here — its wrapper pattern nests data under a key,
        // but all consumers (naming, enrichment, BuildTableNamingSection) expect flat root access.
        var objectsDir = Path.Combine(_options.AnalysisCommonPath ?? "", "Objects");
        foreach (var (qn, tObj) in uniqueTables)
        {
            var tblName = tObj["tableName"]?.GetValue<string>() ?? "";
            if (string.IsNullOrEmpty(tblName)) continue;

            var sqltablePath = Path.Combine(objectsDir, $"{tblName.ToUpperInvariant()}.sqltable.json");
            if (File.Exists(sqltablePath)) continue;

            var sqltableObj = new JsonObject
            {
                ["tableName"] = tblName,
                ["elementType"] = "sqltable",
                ["lastUpdated"] = DateTime.Now.ToString("yyyy-MM-ddTHH:mm:ss"),
                ["schema"] = tObj["schema"]?.DeepClone(),
                ["qualifiedName"] = tObj["qualifiedName"]?.DeepClone(),
                ["existsInDb2"] = tObj["existsInDb2"]?.DeepClone(),
                ["cachedAt"] = DateTime.Now.ToString("yyyy-MM-ddTHH:mm:ss")
            };
            File.WriteAllText(sqltablePath, sqltableObj.ToJsonString(JsonWriteOptions));
        }

        int validated = uniqueTables.Values.Count(t => t["existsInDb2"]?.GetValue<bool>() == true);
        int notFound = uniqueTables.Values.Count(t => t["existsInDb2"]?.GetValue<bool>() == false);

        return new JsonObject
        {
            ["title"] = "DB2 Table Validation",
            ["generated"] = DateTime.Now.ToString("yyyy-MM-dd HH:mm:ss"),
            ["database"] = _profileDatabase,
            ["db2Alias"] = _catalogDb2Alias,
            ["source"] = _catalogQualified.Count > 0 ? "catalog-file" : "none",
            ["totalQualified"] = uniqueTables.Count,
            ["validated"] = validated,
            ["notFound"] = notFound,
            ["tables"] = new JsonArray(uniqueTables.Values.OrderBy(t => t["qualifiedName"]?.GetValue<string>() ?? t["tableName"]?.GetValue<string>() ?? "").Select(t => (JsonNode)t.DeepClone()).ToArray())
        };
    }

    /// <summary>
    /// V1 Phase 5: Discover programs via seed table RAG queries.
    /// Cross-ref Batch.CSharp lines 2060-2107.
    /// V1 only queries SEED program tables, uses "EXEC SQL SELECT FROM {table}",
    /// validates against validProgramNames, and applies package boundary per program.
    /// </summary>
    private async Task DiscoverProgramsViaSqlTablesAsync(JsonObject master)
    {
        // V1: only seed tables (lines 2048-2058)
        var seedTableSet = new HashSet<string>(StringComparer.OrdinalIgnoreCase);
        foreach (var p in master["programs"]!.AsArray())
        {
            var progName = p!["program"]!.GetValue<string>();
            if (!_seedSet.Contains(progName)) continue;
            foreach (var s in p["sqlOperations"]?.AsArray() ?? [])
            {
                var tbl = s!["tableName"]?.GetValue<string>();
                if (!string.IsNullOrEmpty(tbl)) seedTableSet.Add(tbl);
            }
        }

        var tableList = seedTableSet.OrderBy(t => t).ToList();
        Logger.Info($"  Seed tables: {seedTableSet.Count} (from {_seedSet.Count} seeds)");
        Logger.Info($"  Querying RAG for {tableList.Count} seed tables...");

        var validProgramNames = new HashSet<string>(_sourceIndex.CblIndex.Keys, StringComparer.OrdinalIgnoreCase);
        foreach (var k in _sourceIndex.FullIndex.Keys) validProgramNames.Add(k);

        var knownPrograms = new HashSet<string>(
            master["programs"]!.AsArray().Select(p => p!["program"]!.GetValue<string>()),
            StringComparer.OrdinalIgnoreCase);

        var tableDiscoveries = new Dictionary<string, HashSet<string>>(StringComparer.OrdinalIgnoreCase);

        foreach (var table in tableList)
        {
            // V1 query format (line 2081)
            var ragResult = await _ragClient.InvokeRagAsync($"EXEC SQL SELECT FROM {table}", _options.RagTableResults);
            if (string.IsNullOrEmpty(ragResult)) continue;

            foreach (Match m in DependencyExtractor.RagSourcePattern.Matches(ragResult))
            {
                var pName = m.Groups[1].Value.ToUpperInvariant();
                if (knownPrograms.Contains(pName) || pName.Length < 3) continue;
                if (DependencyExtractor.TestExcludeCall(pName)) continue;
                // V1 line 2088: validate against source index
                if (validProgramNames.Count > 0 && !validProgramNames.Contains(pName)) continue;
                // V1 line 2089: package boundary check
                if (_catalogPackages.Count > 0 && !_seedSet.Contains(pName) && !_catalogPackages.Contains(pName))
                {
                    _packageRejections.TryAdd(pName, "table-reference");
                    continue;
                }
                if (!tableDiscoveries.ContainsKey(pName))
                    tableDiscoveries[pName] = new HashSet<string>(StringComparer.OrdinalIgnoreCase);
                tableDiscoveries[pName].Add(table);
            }
        }

        var tableNewProgs = tableDiscoveries.Keys.OrderBy(k => k).ToList();
        Logger.Info($"  Discovered {tableNewProgs.Count} new programs via seed table references (validated against source index)");

        foreach (var prog in tableNewProgs)
        {
            knownPrograms.Add(prog);
            _programLayers.TryAdd(prog, "table-reference");
        }
    }

    private JsonObject BuildSourceVerification(JsonObject master)
    {
        var cblFound = new JsonArray();
        var uncertainFound = new JsonArray();
        var uvFuzzy = new JsonArray();
        var otherType = new JsonArray();
        var noiseFiltered = new JsonArray();
        var missingList = new List<string>();
        var total = master["programs"]!.AsArray().Count;
        int foundCount = 0;

        foreach (var prog in master["programs"]!.AsArray())
        {
            var progName = prog!["program"]!.GetValue<string>();
            var sourceType = prog["sourceType"]?.GetValue<string>() ?? "";
            var sourcePath = prog["sourcePath"]?.GetValue<string>();

            if (sourceType == "local-cbl")
            {
                cblFound.Add(new JsonObject { ["program"] = progName, ["fileType"] = "CBL", ["path"] = sourcePath });
                foundCount++;
            }
            else if (sourceType == "local-cbl-uv")
            {
                var actualName = prog["actualName"]?.GetValue<string>();
                uvFuzzy.Add(new JsonObject { ["program"] = progName, ["actualName"] = actualName, ["fileType"] = "CBL", ["path"] = sourcePath, ["matchType"] = "U_to_V" });
                foundCount++;
            }
            else if (sourceType == "local-uncertain")
            {
                uncertainFound.Add(new JsonObject { ["program"] = progName, ["fileType"] = "CBL", ["path"] = sourcePath });
                foundCount++;
            }
            else if (sourceType.StartsWith("local-"))
            {
                otherType.Add(new JsonObject { ["program"] = progName, ["fileType"] = sourceType.Replace("local-", "").ToUpperInvariant(), ["path"] = sourcePath });
                foundCount++;
            }
            else
            {
                missingList.Add(progName);
            }
        }

        int totalFound = cblFound.Count + uncertainFound.Count + uvFuzzy.Count + otherType.Count;

        // Copy availability
        var allCopyNames = new HashSet<string>(StringComparer.OrdinalIgnoreCase);
        foreach (var prog in master["programs"]!.AsArray())
        {
            foreach (var c in prog!["copyElements"]?.AsArray() ?? [])
            {
                var name = c!["name"]?.GetValue<string>();
                if (!string.IsNullOrEmpty(name)) allCopyNames.Add(name);
            }
        }
        int copyFound = 0;
        var copyMissing = new List<string>();
        foreach (var cn in allCopyNames.OrderBy(c => c))
        {
            if (_sourceIndex.CopyIndex.ContainsKey(cn) ||
                _sourceIndex.CopyIndex.ContainsKey(Regex.Replace(cn, @"\.\w+$", "")))
                copyFound++;
            else
                copyMissing.Add(cn);
        }

        // On-disk not in master — V1 uses knownSet with program names + UV actual names, no noise filter
        var knownProgs = new HashSet<string>(StringComparer.OrdinalIgnoreCase);
        foreach (var p in master["programs"]!.AsArray())
            knownProgs.Add(p!["program"]!.GetValue<string>().ToUpperInvariant());
        foreach (var uv in uvFuzzy)
        {
            var actual = uv?["actualName"]?.GetValue<string>();
            if (!string.IsNullOrEmpty(actual)) knownProgs.Add(actual);
        }
        var onDiskNotInMaster = _sourceIndex.CblIndex.Keys
            .Where(k => !knownProgs.Contains(k))
            .OrderBy(k => k, NbNoComparer).ToList();

        // V1 sorts programsCblFound by program name (nb-NO culture)
        var sortedCblFound = new JsonArray();
        foreach (var c in cblFound.OrderBy(e => e!["program"]!.GetValue<string>(), NbNoComparer))
            sortedCblFound.Add(c!.DeepClone());

        return new JsonObject
        {
            ["title"] = "Source Availability Verification",
            ["generated"] = DateTime.Now.ToString("yyyy-MM-dd HH:mm:ss"),
            ["sourceRoot"] = _options.SourceRoot,
            ["summary"] = new JsonObject
            {
                ["totalFilesOnDisk"] = _sourceIndex.TotalFileCount,
                ["cblOnDisk"] = _sourceIndex.CblIndex.Count,
                ["programsInMaster"] = total,
                ["programsCblFound"] = sortedCblFound.Count,
                ["programsUncertainFound"] = uncertainFound.Count,
                ["programsUvFuzzyMatch"] = uvFuzzy.Count,
                ["programsOtherType"] = otherType.Count,
                ["programsTotalFound"] = totalFound,
                ["programsNoise"] = noiseFiltered.Count,
                ["programsTrulyMissing"] = missingList.Count,
                ["programFoundPct"] = (total - noiseFiltered.Count) > 0
                    ? Math.Round(100.0 * totalFound / (total - noiseFiltered.Count), 1) : 0,
                ["copyTotal"] = allCopyNames.Count,
                ["copyFound"] = copyFound,
                ["copyMissing"] = copyMissing.Count,
                ["copyFoundPct"] = allCopyNames.Count > 0 ? Math.Round(100.0 * copyFound / allCopyNames.Count, 1) : 0,
                ["onDiskNotInMaster"] = onDiskNotInMaster.Count
            },
            ["programsCblFound"] = sortedCblFound,
            ["programsUncertainFound"] = uncertainFound,
            ["programsUvFuzzyMatch"] = uvFuzzy,
            ["programsOtherType"] = otherType,
            ["programsNoiseFiltered"] = noiseFiltered,
            ["programsTrulyMissing"] = JsonSerializer.SerializeToNode(missingList.OrderBy(m => m, NbNoComparer).ToList()),
            ["copyMissing"] = JsonSerializer.SerializeToNode(copyMissing.OrderBy(c => c, NbNoComparer).ToList()),
            ["onDiskNotInMaster"] = JsonSerializer.SerializeToNode(onDiskNotInMaster)
        };
    }

    private async Task ClassifyAllProgramsAsync(JsonObject master, string runDir)
    {
        var classifiedList = new JsonArray();
        int autoDocFound = 0;

        foreach (var prog in master["programs"]!.AsArray())
        {
            var name = prog!["program"]!.GetValue<string>();

            var classification = _classifier.ClassifyProgramByRules(name, prog);
            prog["classification"] = classification["classification"]?.GetValue<string>();
            prog["classificationConfidence"] = classification["classificationConfidence"]?.GetValue<string>();
            prog["classificationEvidence"] = classification["classificationEvidence"]?.GetValue<string>();

            var autoDocPath = _classifier.GetAutoDocFilePath(name);
            var autoDocExists = _classifier.AutoDocFileExists(name);
            prog["autoDocPath"] = autoDocPath;
            prog["autoDocExists"] = autoDocExists;
            if (autoDocExists) autoDocFound++;

            classifiedList.Add(classification);
        }

        var total = master["programs"]!.AsArray().Count;
        Logger.Info($"  AutoDoc UNC validated: {autoDocFound}/{total} programs have AutoDoc files");
    }

    private void ProduceCrossReferenceOutputs(JsonObject master, string runDir, string alias)
    {
        // V1 iterates programs in nb-NO sorted order for all cross-ref outputs
        // (e.g., line 2620: $sortedKeys = @($master.Keys | Sort-Object))
        // Sort master["programs"] in-place so all downstream iteration is nb-NO ordered.
        var sortedProgs = master["programs"]!.AsArray()
            .Select(p => p!.DeepClone())
            .OrderBy(p => p["program"]!.GetValue<string>(), NbNoComparer)
            .ToList();
        master["programs"] = new JsonArray(sortedProgs.Select(p => (JsonNode?)p).ToArray());
        var programs = master["programs"]!.AsArray();
        var generated = DateTime.Now.ToString("yyyy-MM-dd HH:mm:ss");

        // all_total_programs.json — match V1 structure with metadata from all.json
        var progEntries = new JsonArray();
        int countOrig = 0, countCall = 0, countTable = 0, countLocal = 0, countRag = 0, countInfra = 0, countDeprecated = 0;

        foreach (var p in programs)
        {
            var progName = p!["program"]!.GetValue<string>();
            _programLayers.TryGetValue(progName, out var layer);
            layer ??= "unknown";
            var isInfra = Regex.IsMatch(progName, "^(GMA|GMF|GMD|GMV)");
            var srcType = p["sourceType"]?.GetValue<string>() ?? "";

            var origEntry = _allJsonEntries?.FirstOrDefault(e =>
                e?["program"]?.GetValue<string>()?.Equals(progName, StringComparison.OrdinalIgnoreCase) == true);

            _cobdokIndex.TryGetValue(progName, out var cobdok);

            var pe = new JsonObject
            {
                ["program"] = progName,
                ["filetype"] = "cbl",
                ["source"] = layer,
                ["sourceType"] = srcType,
                ["isSharedInfrastructure"] = isInfra,
                ["type"] = origEntry?["type"]?.GetValue<string>(),
                ["menuChoice"] = origEntry?["menuChoice"]?.GetValue<string>(),
                ["area"] = origEntry?["area"]?.GetValue<string>(),
                ["description"] = origEntry?["description"]?.GetValue<string>(),
                ["descriptionNorwegian"] = origEntry?["descriptionNorwegian"]?.GetValue<string>(),
                ["cobdokSystem"] = cobdok?.CobdokSystem,
                ["cobdokDelsystem"] = cobdok?.Delsystem,
                ["cobdokDescription"] = cobdok?.Description,
                ["isDeprecated"] = cobdok?.IsDeprecated ?? false,
                ["copyCount"] = p["copyElements"]?.AsArray().Count ?? 0,
                ["sqlOpCount"] = p["sqlOperations"]?.AsArray().Count ?? 0,
                ["callCount"] = p["callTargets"]?.AsArray().Count ?? 0,
                ["fileIOCount"] = p["fileIO"]?.AsArray().Count ?? 0,
                ["classification"] = p["classification"]?.DeepClone(),
                ["classificationConfidence"] = p["classificationConfidence"]?.DeepClone(),
                ["classificationEvidence"] = p["classificationEvidence"]?.DeepClone(),
                ["isExclusionCandidate"] = false,
                ["exclusionCandidateReasons"] = ""
            };
            progEntries.Add(pe);

            if (layer == "original") countOrig++;
            else if (layer == "call-expansion") countCall++;
            else if (layer == "table-reference") countTable++;
            if (srcType.StartsWith("local-")) countLocal++; else countRag++;
            if (isInfra) countInfra++;
            if (cobdok?.IsDeprecated == true) countDeprecated++;
        }

        // V1 line 2620: $sortedKeys = @($master.Keys | Sort-Object) — nb-NO culture
        var sortedProgEntries = new JsonArray();
        foreach (var pe2 in progEntries.OrderBy(e => e!["program"]!.GetValue<string>(), NbNoComparer))
            sortedProgEntries.Add(pe2!.DeepClone());

        var totalProgs = new JsonObject
        {
            ["title"] = "All Programs (Total)",
            ["generated"] = generated,
            ["totalPrograms"] = sortedProgEntries.Count,
            ["breakdown"] = new JsonObject
            {
                ["original"] = countOrig,
                ["callExpansion"] = countCall,
                ["tableReference"] = countTable
            },
            ["dataSources"] = new JsonObject { ["localSource"] = countLocal, ["rag"] = countRag },
            ["deprecatedCount"] = countDeprecated,
            ["sharedInfrastructureCount"] = countInfra,
            ["programs"] = sortedProgEntries
        };
        File.WriteAllText(Path.Combine(runDir, "all_total_programs.json"),
            totalProgs.ToJsonString(JsonWriteOptions));

        // all_sql_tables.json — match V1 per-program-per-table format
        var sqlEntries = new JsonArray();
        var sqlUnique = new HashSet<string>(StringComparer.OrdinalIgnoreCase);
        foreach (var p in programs)
        {
            var progName = p!["program"]!.GetValue<string>();
            foreach (var s in p["sqlOperations"]?.AsArray() ?? [])
            {
                var schema = s!["schema"]?.GetValue<string>() ?? "";
                var tableName = s["tableName"]?.GetValue<string>() ?? "";
                var op = s["operation"]?.GetValue<string>() ?? "";
                var key = $"{progName}|{schema}|{tableName}|{op}";
                if (!sqlUnique.Add(key)) continue;

                var qn = schema.Length > 1 && schema != "(UNQUALIFIED)"
                    ? $"{schema}.{tableName}" : (string?)null;
                bool? existsInDb2 = null;
                if (_catalogQualified.Count > 0 && qn != null)
                    existsInDb2 = _catalogQualified.Contains(qn);

                sqlEntries.Add(new JsonObject
                {
                    ["program"] = progName,
                    ["schema"] = schema,
                    ["tableName"] = tableName,
                    ["qualifiedName"] = qn,
                    ["operation"] = op,
                    ["existsInDb2"] = existsInDb2,
                    ["isExclusionCandidate"] = false
                });
            }
        }
        var uTables = new HashSet<string>(StringComparer.OrdinalIgnoreCase);
        foreach (var se in sqlEntries)
        {
            var s = se!["schema"]?.GetValue<string>() ?? "";
            var t = se["tableName"]?.GetValue<string>() ?? "";
            uTables.Add(s == "(UNQUALIFIED)" ? t : $"{s}.{t}");
        }
        // V1 line 2717: Sort-Object { $_['tableName'] }, { $_['program'] } — nb-NO culture
        // PowerShell Sort-Object is stable — preserves insertion order for equal keys.
        // C# OrderBy/ThenBy is also stable, so same tableName+program retains discovery order.
        var sortedSqlEntries = new JsonArray();
        foreach (var se2 in sqlEntries
            .OrderBy(e => e!["tableName"]!.GetValue<string>(), NbNoComparer)
            .ThenBy(e => e!["program"]!.GetValue<string>(), NbNoComparer))
            sortedSqlEntries.Add(se2!.DeepClone());

        File.WriteAllText(Path.Combine(runDir, "all_sql_tables.json"),
            new JsonObject
            {
                ["title"] = "All SQL Table References",
                ["generated"] = generated,
                ["totalReferences"] = sortedSqlEntries.Count,
                ["uniqueTables"] = uTables.Count,
                ["db2Validated"] = _catalogQualified.Count > 0,
                ["tableReferences"] = sortedSqlEntries
            }.ToJsonString(JsonWriteOptions));

        // all_copy_elements.json — match V1 per-element detail (with localPath + usedByCandidateCount)
        var copyMap = new Dictionary<string, JsonObject>(StringComparer.OrdinalIgnoreCase);
        foreach (var p in programs)
        {
            var progName = p!["program"]!.GetValue<string>();
            foreach (var c in p["copyElements"]?.AsArray() ?? [])
            {
                var name = c!["name"]?.GetValue<string>() ?? "";
                if (string.IsNullOrEmpty(name)) continue;
                if (!copyMap.TryGetValue(name, out var entry))
                {
                    string? localPath = null;
                    if (_sourceIndex.CopyIndex.TryGetValue(name, out var cp))
                        localPath = cp;
                    else
                    {
                        var nameNoExt = Regex.Replace(name, @"\.(\w+)$", "");
                        if (_sourceIndex.CopyIndex.TryGetValue(nameNoExt, out var cp2))
                            localPath = cp2;
                    }

                    entry = new JsonObject
                    {
                        ["name"] = name,
                        ["type"] = c["type"]?.GetValue<string>(),
                        ["localPath"] = localPath,
                        ["usedBy"] = new JsonArray(),
                        ["usedByCandidateCount"] = 0
                    };
                    copyMap[name] = entry;
                }
                var usedBy = entry["usedBy"]!.AsArray();
                if (!usedBy.Any(u => u?.GetValue<string>() == progName))
                    usedBy.Add(progName);
            }
        }
        var copyList = new JsonArray();
        foreach (var kv in copyMap.OrderBy(k => k.Key, NbNoComparer))
        {
            var ce = kv.Value;
            var ub = ce["usedBy"]!.AsArray();
            var sorted = ub.Select(u => u!.GetValue<string>()).OrderBy(u => u, NbNoComparer).ToList();
            ce["usedBy"] = JsonSerializer.SerializeToNode(sorted);
            copyList.Add(ce);
        }

        File.WriteAllText(Path.Combine(runDir, "all_copy_elements.json"),
            new JsonObject
            {
                ["title"] = "All COPY Elements",
                ["generated"] = generated,
                ["totalCopyElements"] = copyList.Count,
                ["copyElements"] = copyList
            }.ToJsonString(JsonWriteOptions));

        // all_call_graph.json — match V1 with isExclusionCandidate
        var edges = new JsonArray();
        var callUnique = new HashSet<string>(StringComparer.OrdinalIgnoreCase);
        foreach (var p in programs)
        {
            var caller = p!["program"]!.GetValue<string>();
            foreach (var target in p["callTargets"]?.AsArray() ?? [])
            {
                var callee = target!.GetValue<string>().ToUpperInvariant();
                var key = $"{caller}->{callee}";
                if (!callUnique.Add(key)) continue;
                edges.Add(new JsonObject
                {
                    ["caller"] = caller,
                    ["callee"] = callee,
                    ["isExclusionCandidate"] = false
                });
            }
        }
        // V1 line 2786: Sort-Object { $_['caller'] }, { $_['callee'] } — nb-NO culture
        var sortedEdges = new JsonArray();
        foreach (var e2 in edges
            .OrderBy(e => e!["caller"]!.GetValue<string>(), NbNoComparer)
            .ThenBy(e => e!["callee"]!.GetValue<string>(), NbNoComparer))
            sortedEdges.Add(e2!.DeepClone());

        File.WriteAllText(Path.Combine(runDir, "all_call_graph.json"),
            new JsonObject
            {
                ["title"] = "COBOL Call Graph",
                ["generated"] = generated,
                ["totalEdges"] = sortedEdges.Count,
                ["edges"] = sortedEdges
            }.ToJsonString(JsonWriteOptions));

        // all_file_io.json — match V1 per-program-per-file format
        var fioEntries = new JsonArray();
        var fioUnique = new HashSet<string>(StringComparer.OrdinalIgnoreCase);
        foreach (var p in programs)
        {
            var progName = p!["program"]!.GetValue<string>();
            foreach (var f in p["fileIO"]?.AsArray() ?? [])
            {
                var logName = f!["logicalName"]?.GetValue<string>() ?? "";
                var key = $"{progName}|{logName}";
                if (!fioUnique.Add(key)) continue;
                fioEntries.Add(new JsonObject
                {
                    ["program"] = progName,
                    ["logicalName"] = logName,
                    ["physicalName"] = f["physicalName"]?.DeepClone(),
                    ["path"] = f["path"]?.DeepClone(),
                    ["fullPath"] = f["fullPath"]?.DeepClone(),
                    ["assignType"] = f["assignType"]?.DeepClone(),
                    ["operations"] = f["operations"]?.DeepClone(),
                    ["resolvedPath"] = f["resolvedPath"]?.DeepClone(),
                    ["filenamePattern"] = f["filenamePattern"]?.DeepClone(),
                    ["filenameDescription"] = f["filenameDescription"]?.DeepClone(),
                    ["isExclusionCandidate"] = false
                });
            }
        }
        var fioUniqueFiles = new HashSet<string>(StringComparer.OrdinalIgnoreCase);
        foreach (var f in fioEntries)
        {
            var fn = f!["fullPath"]?.GetValue<string>() ?? f["physicalName"]?.GetValue<string>();
            if (!string.IsNullOrEmpty(fn)) fioUniqueFiles.Add(fn);
        }
        // V1 line 2826: Sort-Object { $_['program'] }, { $_['logicalName'] } — nb-NO culture
        var sortedFioEntries = new JsonArray();
        foreach (var f2 in fioEntries
            .OrderBy(e => e!["program"]!.GetValue<string>(), NbNoComparer)
            .ThenBy(e => e!["logicalName"]!.GetValue<string>(), NbNoComparer))
            sortedFioEntries.Add(f2!.DeepClone());

        File.WriteAllText(Path.Combine(runDir, "all_file_io.json"),
            new JsonObject
            {
                ["title"] = "COBOL File I/O Map",
                ["generated"] = generated,
                ["defaultPath"] = _options.DefaultFilePath,
                ["totalFileReferences"] = sortedFioEntries.Count,
                ["uniqueFiles"] = fioUniqueFiles.Count,
                ["fileReferences"] = sortedFioEntries
            }.ToJsonString(JsonWriteOptions));

        // standard_cobol_filtered.json — V1 checks AutoDocJson index, then cache/Ollama.
        // V2 uses cache only; programs without cache get RAG_UNAVAILABLE (matching V1 when Ollama/RAG is down).
        var nullSourceProgNames = programs
            .Where(p => p!["sourcePath"] == null || p["sourcePath"]!.GetValue<string?>() == null)
            .Select(p => p!["program"]!.GetValue<string>())
            .OrderBy(n => n, NbNoComparer)
            .ToList();
        if (nullSourceProgNames.Count > 0)
        {
            var autoDocIndex = LoadAutoDocIndex();
            var removed = new JsonArray();
            var retained = new JsonArray();

            foreach (var prog in nullSourceProgNames)
            {
                if (autoDocIndex.Contains(prog.ToUpperInvariant()))
                {
                    retained.Add(new JsonObject
                    {
                        ["program"] = prog,
                        ["ragEvidence"] = "AutoDocJson index",
                        ["ollamaVerdict"] = "AUTODOC_KNOWN"
                    });
                    continue;
                }

                var cached = _cacheService.GetCachedFact(prog, "isStandardCobol");
                if (cached != null)
                {
                    var answer = cached["answer"]?.GetValue<string>() ?? "";
                    var evidence = cached["ragEvidence"]?.GetValue<string>() ?? "";
                    if (answer.Equals("YES", StringComparison.OrdinalIgnoreCase))
                        removed.Add(new JsonObject { ["program"] = prog, ["ragEvidence"] = evidence, ["ollamaVerdict"] = answer });
                    else
                        retained.Add(new JsonObject { ["program"] = prog, ["ragEvidence"] = evidence, ["ollamaVerdict"] = answer });
                }
                else
                {
                    retained.Add(new JsonObject
                    {
                        ["program"] = prog,
                        ["ragEvidence"] = "",
                        ["ollamaVerdict"] = "RAG_UNAVAILABLE"
                    });
                }
            }

            if (removed.Count > 0)
            {
                foreach (var re in removed)
                {
                    var rProg = re!["program"]!.GetValue<string>();
                    var masterProgs = master["programs"]!.AsArray();
                    for (int ri = masterProgs.Count - 1; ri >= 0; ri--)
                    {
                        if (string.Equals(masterProgs[ri]!["program"]!.GetValue<string>(), rProg, StringComparison.OrdinalIgnoreCase))
                        {
                            masterProgs.RemoveAt(ri);
                            break;
                        }
                    }
                }
                File.WriteAllText(Path.Combine(runDir, "dependency_master.json"), master.ToJsonString(JsonWriteOptions));
            }

            File.WriteAllText(Path.Combine(runDir, "standard_cobol_filtered.json"),
                new JsonObject
                {
                    ["title"] = "Standard COBOL Program Filter",
                    ["generated"] = generated,
                    ["totalChecked"] = nullSourceProgNames.Count,
                    ["totalRemoved"] = removed.Count,
                    ["totalRetained"] = retained.Count,
                    ["removed"] = removed,
                    ["retained"] = retained
                }.ToJsonString(JsonWriteOptions));
        }

        // business_areas.json — load from cache if available, otherwise stub
        var businessAreasPath = Path.Combine(_options.AnalysisCommonPath ?? "", "BusinessAreas",
            $"{alias}_business_areas.json");
        if (File.Exists(businessAreasPath))
        {
            File.Copy(businessAreasPath, Path.Combine(runDir, "business_areas.json"), true);
        }
        else
        {
            File.WriteAllText(Path.Combine(runDir, "business_areas.json"),
                new JsonObject
                {
                    ["title"] = "Business Area Classification",
                    ["generated"] = generated,
                    ["analysisAlias"] = alias,
                    ["totalAreas"] = 0,
                    ["areas"] = new JsonArray(),
                    ["programAreaMap"] = new JsonObject()
                }.ToJsonString(JsonWriteOptions));
        }
    }

    /// <summary>
    /// V1 Resolve-VariableFilenames: reads cached Ollama results for variable-based file paths.
    /// Cross-ref Batch.CSharp lines 1450-1544.
    /// </summary>
    private void ResolveVariableFilenamesFromCache(string programName, List<JsonObject> fileIOEntries)
    {
        var cachedVf = _cacheService.GetCachedFact(programName, "variableFilenames");
        if (cachedVf == null) return;

        foreach (var ve in fileIOEntries)
        {
            var assignType = ve["assignType"]?.GetValue<string>();
            var physName = ve["physicalName"]?.GetValue<string>();
            if (assignType != "variable" || string.IsNullOrEmpty(physName)) continue;
            if (physName is "DYNAMIC" or "SELECT") continue;

            var logicalKey = ve["logicalName"]?.GetValue<string>() ?? physName;
            var hit = cachedVf[logicalKey];
            if (hit == null) continue;

            var resolvedPath = hit["resolvedPath"]?.GetValue<string>();
            if (!string.IsNullOrEmpty(resolvedPath))
                ve["resolvedPath"] = resolvedPath;

            var pattern = hit["filenamePattern"]?.GetValue<string>();
            if (!string.IsNullOrEmpty(pattern))
                ve["filenamePattern"] = pattern;

            var description = hit["description"]?.GetValue<string>();
            if (!string.IsNullOrEmpty(description))
                ve["filenameDescription"] = description;

            var basePath = hit["basePath"]?.GetValue<string>();
            var currentPath = ve["path"]?.GetValue<string>();
            if (!string.IsNullOrEmpty(basePath) &&
                (string.IsNullOrEmpty(currentPath) || currentPath == _options.DefaultFilePath))
            {
                ve["path"] = basePath;
            }
        }
    }

    /// <summary>
    /// V1 Phase 8f naming injection: adds futureProjectName per program and futureTableName per SQL op.
    /// Cross-ref Batch.CSharp lines 3252-3273.
    /// </summary>
    private void InjectNamingData(JsonObject master)
    {
        int injectedProgs = 0, injectedOps = 0;
        foreach (var p in master["programs"]!.AsArray())
        {
            var progName = p!["program"]!.GetValue<string>();
            var pn = _cacheService.GetCachedNaming(progName, "ProgramNames");
            var fpn = pn?["futureProjectName"]?.GetValue<string>();
            if (!string.IsNullOrEmpty(fpn))
            {
                p["futureProjectName"] = fpn;
                injectedProgs++;
            }

            foreach (var s in p["sqlOperations"]?.AsArray() ?? [])
            {
                var tableName = s!["tableName"]?.GetValue<string>();
                if (string.IsNullOrEmpty(tableName)) continue;
                var tn = _cacheService.GetCachedNaming(tableName, "TableNames");
                var ftn = tn?["futureName"]?.GetValue<string>();
                if (!string.IsNullOrEmpty(ftn))
                {
                    s["futureTableName"] = ftn;
                    injectedOps++;
                }
            }
        }
        if (injectedProgs > 0 || injectedOps > 0)
            Logger.Info($"  Naming injection: {injectedProgs} futureProjectName, {injectedOps} futureTableName");
    }

    /// <summary>
    /// V1 lines 3252-3275: build tableNaming from ALL *.sqltable.json in AnalysisCommon/Objects/.
    /// V1 iterates the shared Objects directory (not just master tables), so tableNaming
    /// includes naming data for tables from ALL previous analyses.
    /// </summary>
    private JsonObject BuildTableNamingSection(JsonObject master)
    {
        var tableNaming = new JsonObject();
        var objectsDir = Path.Combine(_options.AnalysisCommonPath ?? "", "Objects");
        if (!Directory.Exists(objectsDir))
        {
            Logger.Info("  AnalysisCommon/Objects not yet populated — tableNaming will be empty");
            return tableNaming;
        }

        var sqltableFiles = Directory.GetFiles(objectsDir, "*.sqltable.json");
        foreach (var f in sqltableFiles)
        {
            try
            {
                var tData = JsonNode.Parse(File.ReadAllText(f, System.Text.Encoding.UTF8))?.AsObject();
                if (tData == null) continue;
                var tName = tData["tableName"]?.GetValue<string>();
                if (string.IsNullOrEmpty(tName)) continue;

                var tn = _cacheService.GetCachedNaming(tName, "TableNames");
                if (tn == null) continue;

                var entry = new JsonObject
                {
                    ["futureName"] = tn["futureName"]?.GetValue<string>(),
                    ["namespace"] = tn["namespace"]?.GetValue<string>()
                };

                var remarks = tData["db2Metadata"]?["tableRemarks"]?.GetValue<string>();
                if (!string.IsNullOrEmpty(remarks))
                    entry["tableRemarks"] = remarks;

                var cols = tn["columns"]?.AsArray();
                if (cols != null && cols.Count > 0)
                    entry["columns"] = cols.DeepClone();

                tableNaming[tName] = entry;
            }
            catch { }
        }

        Logger.Info($"  tableNaming section: {tableNaming.Count} tables (from {sqltableFiles.Length} sqltable files)");
        return tableNaming;
    }

    private void CopyToAliasFolder(string runDir, string aliasDir)
    {
        Directory.CreateDirectory(aliasDir);
        foreach (var file in Directory.GetFiles(runDir, "*.json"))
        {
            File.Copy(file, Path.Combine(aliasDir, Path.GetFileName(file)), true);
        }
        foreach (var file in Directory.GetFiles(runDir, "*.md"))
        {
            File.Copy(file, Path.Combine(aliasDir, Path.GetFileName(file)), true);
        }
    }

    private static void SaveMaster(JsonObject master, string path)
    {
        master["totalPrograms"] = master["programs"]!.AsArray().Count;
        master["generated"] = DateTime.Now.ToString("yyyy-MM-dd HH:mm:ss");
        var json = master.ToJsonString(JsonWriteOptions);

        for (int attempt = 0; attempt < 6; attempt++)
        {
            try
            {
                File.WriteAllText(path, json);
                return;
            }
            catch when (attempt < 5)
            {
                Thread.Sleep(200 * (attempt + 1));
            }
        }
    }

    /// <summary>
    /// Enrich *.sqltable.json files with DB2 column metadata from SYSCAT.COLUMNS.
    /// Uses per-database ODBC connection (V1 pattern), falling back to MCP.
    /// This data is used by the naming prompts.
    /// </summary>
    private async Task EnrichSqlTablesWithDb2MetadataAsync()
    {
        var objectsDir = Path.Combine(_options.AnalysisCommonPath ?? "", "Objects");
        if (!Directory.Exists(objectsDir)) return;

        var sqltableFiles = Directory.GetFiles(objectsDir, "*.sqltable.json");
        int enriched = 0, skipped = 0, noData = 0;

        Logger.Info($"  Enriching {sqltableFiles.Length} sqltable.json files with DB2 column metadata (DB={_profileDatabase})...");

        foreach (var f in sqltableFiles)
        {
            try
            {
                var tData = JsonNode.Parse(File.ReadAllText(f))?.AsObject();
                if (tData == null) continue;

                if (tData["db2Metadata"] != null) { skipped++; continue; }

                var tableName = tData["tableName"]?.GetValue<string>();
                var schema = tData["schema"]?.GetValue<string>();
                if (string.IsNullOrEmpty(tableName)) continue;

                var colQuery = $"SELECT COLNAME, TYPENAME, LENGTH, SCALE, NULLS, REMARKS FROM SYSCAT.COLUMNS WHERE TABNAME = '{tableName}'";
                if (!string.IsNullOrEmpty(schema) && schema != "(UNQUALIFIED)")
                    colQuery += $" AND TABSCHEMA = '{schema}'";
                colQuery += " ORDER BY COLNO FETCH FIRST 200 ROWS ONLY";

                var colRows = await _db2Client.ExecuteQueryForDatabaseAsync(colQuery, _profileDatabase, _httpClient);

                var tblQuery = $"SELECT REMARKS, TYPE FROM SYSCAT.TABLES WHERE TABNAME = '{tableName}'";
                if (!string.IsNullOrEmpty(schema) && schema != "(UNQUALIFIED)")
                    tblQuery += $" AND TABSCHEMA = '{schema}'";
                tblQuery += " FETCH FIRST 1 ROWS ONLY";

                var tblRows = await _db2Client.ExecuteQueryForDatabaseAsync(tblQuery, _profileDatabase, _httpClient);

                if (colRows.Count == 0 && tblRows.Count == 0)
                {
                    noData++;
                    continue;
                }

                var schemas = colRows
                    .Select(r => r.GetValueOrDefault("TABSCHEMA") ?? schema ?? "")
                    .Where(s => !string.IsNullOrEmpty(s))
                    .Distinct()
                    .ToList();

                var columns = new JsonArray();
                foreach (var r in colRows)
                {
                    columns.Add(new JsonObject
                    {
                        ["name"] = r.GetValueOrDefault("COLNAME"),
                        ["typeName"] = r.GetValueOrDefault("TYPENAME"),
                        ["length"] = int.TryParse(r.GetValueOrDefault("LENGTH"), out var len) ? len : 0,
                        ["scale"] = int.TryParse(r.GetValueOrDefault("SCALE"), out var sc) ? sc : 0,
                        ["nullable"] = r.GetValueOrDefault("NULLS"),
                        ["remarks"] = r.GetValueOrDefault("REMARKS")
                    });
                }

                var db2Metadata = new JsonObject
                {
                    ["schemas"] = new JsonArray(schemas.Select(s => (JsonNode)JsonValue.Create(s)!).ToArray()),
                    ["tableRemarks"] = tblRows.FirstOrDefault()?.GetValueOrDefault("REMARKS"),
                    ["type"] = tblRows.FirstOrDefault()?.GetValueOrDefault("TYPE")?.Trim(),
                    ["columnCount"] = columns.Count,
                    ["columns"] = columns,
                    ["enrichedAt"] = DateTime.Now.ToString("yyyy-MM-ddTHH:mm:ss")
                };

                tData["db2Metadata"] = db2Metadata;
                File.WriteAllText(f, tData.ToJsonString(JsonWriteOptions));
                enriched++;
            }
            catch (Exception ex)
            {
                Logger.Warn($"  Failed to enrich {Path.GetFileName(f)}: {ex.Message}");
            }
        }

        Logger.Info($"  DB2 enrichment: {enriched} enriched, {skipped} already had metadata, {noData} no DB2 data returned");
    }

    /// <summary>
    /// Phase 8f: Run table naming, column naming, and program naming via Ollama.
    /// </summary>
    private async Task RunNamingPhaseAsync(JsonObject master, string alias)
    {
        var objectsDir = Path.Combine(_options.AnalysisCommonPath ?? "", "Objects");
        if (!Directory.Exists(objectsDir))
        {
            Logger.Info("  Skipping naming — AnalysisCommon/Objects not populated");
            return;
        }

        // Step 1: Table naming
        Logger.Info("  Phase 8f Step 1: Table naming via Ollama");
        var sqltableFiles = Directory.GetFiles(objectsDir, "*.sqltable.json");
        foreach (var f in sqltableFiles)
        {
            try
            {
                var tData = JsonNode.Parse(File.ReadAllText(f))?.AsObject();
                if (tData == null) continue;
                var tableName = tData["tableName"]?.GetValue<string>();
                if (string.IsNullOrEmpty(tableName)) continue;
                await _namingService.NameTableAsync(tableName, tData);
            }
            catch (Exception ex)
            {
                Logger.Warn($"  Table naming failed for {Path.GetFileName(f)}: {ex.Message}");
            }
        }
        Logger.Info($"  Table naming: {_namingService.TableNamingNew} new, {_namingService.TableNamingCached} cached");

        // Step 2: Column naming per table
        Logger.Info("  Phase 8f Step 2: Column naming via Ollama");
        foreach (var f in sqltableFiles)
        {
            try
            {
                var tData = JsonNode.Parse(File.ReadAllText(f))?.AsObject();
                if (tData == null) continue;
                var tableName = tData["tableName"]?.GetValue<string>();
                if (string.IsNullOrEmpty(tableName)) continue;
                await _namingService.NameColumnsForTableAsync(tableName, tData, alias);
            }
            catch (Exception ex)
            {
                Logger.Warn($"  Column naming failed for {Path.GetFileName(f)}: {ex.Message}");
            }
        }
        Logger.Info($"  Column naming: {_namingService.ColumnNamingNew} new, {_namingService.ColumnConflicts} conflicts resolved");

        // Step 3: Build calledByMap for program naming context
        var calledByMap = BuildCalledByMap(master);

        // Step 4: Program naming
        Logger.Info("  Phase 8f Step 3: Program naming via Ollama");
        foreach (var p in master["programs"]!.AsArray())
        {
            try
            {
                await _namingService.NameProgramAsync(p!, calledByMap, _options.RagResults);
            }
            catch (Exception ex)
            {
                var pn = p?["program"]?.GetValue<string>() ?? "?";
                Logger.Warn($"  Program naming failed for {pn}: {ex.Message}");
            }
        }
        Logger.Info($"  Program naming: {_namingService.ProgramNamingNew} new, {_namingService.ProgramNamingCached} cached");
    }

    /// <summary>
    /// Build reverse call graph: for each program, which programs call it.
    /// </summary>
    private static Dictionary<string, HashSet<string>> BuildCalledByMap(JsonObject master)
    {
        var map = new Dictionary<string, HashSet<string>>(StringComparer.OrdinalIgnoreCase);
        foreach (var p in master["programs"]!.AsArray())
        {
            var caller = p!["program"]!.GetValue<string>();
            foreach (var target in p["callTargets"]?.AsArray() ?? [])
            {
                var callee = target!.GetValue<string>().ToUpperInvariant();
                if (!map.ContainsKey(callee))
                    map[callee] = new HashSet<string>(StringComparer.OrdinalIgnoreCase);
                map[callee].Add(caller);
            }
        }
        return map;
    }

    private void LoadDatabaseBoundary()
    {
        if (string.IsNullOrEmpty(_profileDatabase)) return;

        var analysisCommon = _options.AnalysisCommonPath ?? "";
        if (string.IsNullOrEmpty(analysisCommon)) return;

        var catalogPath = Path.Combine(analysisCommon, "Databases", _profileDatabase, "syscat_tables.json");
        if (File.Exists(catalogPath))
        {
            try
            {
                var catalog = JsonNode.Parse(File.ReadAllText(catalogPath));
                _catalogDb2Alias = catalog?["db2Alias"]?.GetValue<string>() ?? "";
                foreach (var t in catalog?["tables"]?.AsArray() ?? [])
                {
                    var qn = t?["qualifiedName"]?.GetValue<string>();
                    if (!string.IsNullOrEmpty(qn)) _catalogQualified.Add(qn);
                }
                Logger.Info($"  Database boundary (tables): {_profileDatabase} (alias={_catalogDb2Alias}) — {_catalogQualified.Count} qualifiedNames");
            }
            catch (Exception ex)
            {
                Logger.Warn($"Failed to load table catalog: {ex.Message}");
            }
        }
        else
        {
            Logger.Warn($"Database catalog not found: {catalogPath}");
        }

        var packagePath = Path.Combine(analysisCommon, "Databases", _profileDatabase, "syscat_packages.json");
        if (File.Exists(packagePath))
        {
            try
            {
                var pkgCatalog = JsonNode.Parse(File.ReadAllText(packagePath));
                foreach (var pkg in pkgCatalog?["packages"]?.AsArray() ?? [])
                {
                    var qn = pkg?["qualifiedName"]?.GetValue<string>();
                    if (!string.IsNullOrEmpty(qn)) _catalogPackages.Add(qn.ToUpperInvariant());
                }
                Logger.Info($"  Database boundary (packages): {_catalogPackages.Count} bound programs (strict)");
            }
            catch (Exception ex)
            {
                Logger.Warn($"Failed to load package catalog: {ex.Message}");
            }
        }
        else
        {
            Logger.Warn($"Package catalog not found: {packagePath}");
        }
    }

    private List<JsonObject> FilterSqlByBoundary(List<JsonObject> sqlOps)
    {
        if (_catalogQualified.Count == 0) return sqlOps;

        var valid = new List<JsonObject>();
        foreach (var op in sqlOps)
        {
            var schema = op["schema"]?.GetValue<string>() ?? "";
            var tableName = op["tableName"]?.GetValue<string>() ?? "";
            if (string.IsNullOrEmpty(tableName)) continue;

            var isQualified = schema.Length > 1 && schema != "(UNQUALIFIED)";
            if (!isQualified) continue; // V1 strips unqualified entries
            var qn = $"{schema}.{tableName}";
            if (_catalogQualified.Contains(qn)) valid.Add(op);
        }
        return valid;
    }

    /// <summary>
    /// Split a CSV line respecting quoted fields (e.g. "value;with;semicolons").
    /// PowerShell Import-Csv handles this natively; we replicate the same behavior.
    /// </summary>
    private static List<string> SplitCsvLine(string line, char delimiter)
    {
        var fields = new List<string>();
        var current = new System.Text.StringBuilder();
        bool inQuotes = false;

        for (int i = 0; i < line.Length; i++)
        {
            char c = line[i];
            if (c == '"')
            {
                if (inQuotes && i + 1 < line.Length && line[i + 1] == '"')
                {
                    current.Append('"');
                    i++;
                }
                else
                {
                    inQuotes = !inQuotes;
                }
            }
            else if (c == delimiter && !inQuotes)
            {
                fields.Add(current.ToString());
                current.Clear();
            }
            else
            {
                current.Append(c);
            }
        }
        fields.Add(current.ToString());
        return fields;
    }

    private static void WritePhase(int phase, string title)
    {
        Logger.Info("");
        Logger.Info(new string('=', 72));
        Logger.Info($"  PHASE {phase} — {title}");
        Logger.Info(new string('=', 72));
    }

    /// <summary>
    /// Load AutoDocJson CblParseResult index — programs known to exist in AutoDocJson.
    /// V1 uses this to skip Ollama calls for known application programs.
    /// </summary>
    private HashSet<string> LoadAutoDocIndex()
    {
        var index = new HashSet<string>(StringComparer.OrdinalIgnoreCase);
        var indexPath = Path.Combine(_options.AutoDocJsonPath ?? "", "_json", "CblParseResult.json");
        if (!File.Exists(indexPath)) return index;
        try
        {
            var entries = JsonNode.Parse(File.ReadAllText(indexPath))?.AsArray();
            if (entries == null) return index;
            foreach (var e in entries)
            {
                var name = e?["programName"]?.GetValue<string>();
                if (string.IsNullOrEmpty(name)) continue;
                name = System.Text.RegularExpressions.Regex.Replace(name, @"\.cbl$", "", System.Text.RegularExpressions.RegexOptions.IgnoreCase);
                index.Add(name.ToUpperInvariant());
            }
            Logger.Info($"  AutoDocJson index loaded: {index.Count} COBOL programs");
        }
        catch (Exception ex) { Logger.Warn($"Failed to load AutoDocJson index: {ex.Message}"); }
        return index;
    }

    /// <summary>
    /// V1 lines 200-220: Load COBDOK modul.csv — semicolon-delimited, no header row.
    /// Headers: cobdokSystem;delsystem;modul;tekst;modultype;benytter_sql;benytter_ds;fra_dato;fra_kl;antall_linjer;lengde;filenavn
    /// </summary>
    private void LoadCobdokCsv()
    {
        var path = _options.CobdokCsvPath;
        if (string.IsNullOrEmpty(path) || !File.Exists(path)) return;

        try
        {
            foreach (var line in File.ReadLines(path, System.Text.Encoding.UTF8))
            {
                var parts = SplitCsvLine(line, ';');
                if (parts.Count < 5) continue;
                static string Clean(string s) => s.Trim().Trim('"').Trim();
                var key = Clean(parts[2]).ToUpperInvariant();
                if (string.IsNullOrEmpty(key) || _cobdokIndex.ContainsKey(key)) continue;

                var system = Clean(parts[0]);
                _cobdokIndex[key] = new CobdokEntry
                {
                    CobdokSystem = system,
                    Delsystem = Clean(parts[1]),
                    Description = Clean(parts[3]),
                    Modultype = Clean(parts[4]),
                    IsDeprecated = system.Equals("UTGATT", StringComparison.OrdinalIgnoreCase)
                };
            }
            var deprecatedCount = _cobdokIndex.Values.Count(e => e.IsDeprecated);
            Logger.Info($"  COBDOK enrichment: {_cobdokIndex.Count} modules ({deprecatedCount} deprecated/UTGATT)");
        }
        catch (Exception ex)
        {
            Logger.Warn($"Failed to load COBDOK CSV: {ex.Message}");
        }
    }

    private static string SanitizeAlias(string alias)
    {
        if (string.IsNullOrWhiteSpace(alias)) return string.Empty;
        return new string(alias.Select(ch => char.IsLetterOrDigit(ch) || ch == '_' || ch == '-' ? ch : '_').ToArray()).Trim('_');
    }

    private sealed record CobdokEntry
    {
        public string CobdokSystem { get; init; } = "";
        public string Delsystem { get; init; } = "";
        public string Description { get; init; } = "";
        public string Modultype { get; init; } = "";
        public bool IsDeprecated { get; init; }
    }
}
