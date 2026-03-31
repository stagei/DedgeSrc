using System.Text.Json;
using System.Text.Json.Nodes;
using System.Text.RegularExpressions;
using NLog;
using SystemAnalyzer2.Batch.Services.Shared;

namespace SystemAnalyzer2.Batch.Services;

/// <summary>
/// Ollama-powered naming generation for programs, tables, and columns.
/// Implements V1 Phase 8f logic using AI protocol templates.
/// </summary>
public sealed class NamingService
{
    private static readonly Logger Logger = LogManager.GetCurrentClassLogger();
    private static readonly JsonSerializerOptions JsonWriteOptions = new() { WriteIndented = true };

    private readonly OllamaClient _ollamaClient;
    private readonly RagClient _ragClient;
    private readonly CacheService _cacheService;
    private readonly ClassificationService _classifier;
    private readonly string _ollamaModel;

    public int TableNamingNew { get; private set; }
    public int TableNamingCached { get; private set; }
    public int ColumnNamingNew { get; private set; }
    public int ProgramNamingNew { get; private set; }
    public int ProgramNamingCached { get; private set; }
    public int ColumnConflicts { get; private set; }

    public NamingService(OllamaClient ollamaClient, RagClient ragClient, CacheService cacheService,
        ClassificationService classifier, string ollamaModel)
    {
        _ollamaClient = ollamaClient;
        _ragClient = ragClient;
        _cacheService = cacheService;
        _classifier = classifier;
        _ollamaModel = ollamaModel;
    }

    // ── Table Naming ──────────────────────────────────────────────────────────

    public async Task NameTableAsync(string tableName, JsonObject? sqltableFact)
    {
        var existing = _cacheService.GetCachedNaming(tableName, "TableNames");
        if (existing != null && !string.IsNullOrEmpty(existing["futureName"]?.GetValue<string>()))
        {
            TableNamingCached++;
            return;
        }

        var schemas = "";
        var tableRemarks = "No comment";
        var tableType = "T";
        var colGrid = "No column data available";

        if (sqltableFact != null)
        {
            var db2Meta = sqltableFact["db2Metadata"];
            if (db2Meta != null)
            {
                schemas = string.Join(", ", db2Meta["schemas"]?.AsArray().Select(s => s?.GetValue<string>() ?? "") ?? []);
                tableRemarks = db2Meta["tableRemarks"]?.GetValue<string>() ?? "No comment";
                tableType = db2Meta["type"]?.GetValue<string>() ?? "T";

                var cols = db2Meta["columns"]?.AsArray();
                if (cols != null && cols.Count > 0)
                {
                    var lines = new List<string> { "| # | Name | Type | Length | Nullable | Comment |", "|---|---|---|---|---|---|" };
                    int idx = 0;
                    foreach (var c in cols)
                    {
                        idx++;
                        lines.Add($"| {idx} | {c?["name"]} | {c?["typeName"]} | {c?["length"]} | {(c?["nullable"]?.GetValue<string>() == "Y" ? "Yes" : "No")} | {c?["remarks"]} |");
                    }
                    colGrid = string.Join("\n", lines);
                }
            }
        }

        if (string.IsNullOrEmpty(tableRemarks) || tableRemarks == "No comment")
            tableRemarks = "No comment";

        var prompt = $$"""
            You are analyzing a legacy DB2 table for modernization to C#.
            Your task is to suggest a modern CamelCase class name and logical namespace.

            TABLE: {{tableName}}
            SCHEMAS: {{schemas}}
            TABLE COMMENT (Norwegian): {{tableRemarks}}
            TYPE: {{tableType}}

            COLUMNS:
            {{colGrid}}

            Based on ALL the context above, suggest a CamelCase C# class name and namespace.
            Respond with EXACTLY one JSON object (no markdown, no explanation):
            {"futureName":"OrderHeader","namespace":"Orders"}

            JSON:
            {"futureName":
            """;

        var response = await _ollamaClient.InvokeOllamaAsync(prompt);
        var parsed = ParseJsonResponse(response, "futureName");
        if (parsed == null) return;

        var data = new JsonObject
        {
            ["tableName"] = tableName,
            ["futureName"] = parsed["futureName"]?.GetValue<string>(),
            ["namespace"] = parsed["namespace"]?.GetValue<string>(),
            ["columns"] = new JsonArray(),
            ["model"] = _ollamaModel,
            ["protocol"] = "Naming-TableNames",
            ["analyzedAt"] = DateTime.Now.ToString("yyyy-MM-ddTHH:mm:ss")
        };

        _cacheService.SaveCachedNaming(tableName, "TableNames", data);
        TableNamingNew++;
    }

    // ── Column Naming (per table) ──────────────────────────────────────────────

    public async Task NameColumnsForTableAsync(string tableName, JsonObject? sqltableFact, string analysisAlias)
    {
        var tableNaming = _cacheService.GetCachedNaming(tableName, "TableNames");
        if (tableNaming == null) return;

        var existingCols = tableNaming["columns"]?.AsArray();
        if (existingCols != null && existingCols.Count > 0) return;

        var futureTableName = tableNaming["futureName"]?.GetValue<string>() ?? "unknown";
        var tableRemarks = "No comment";
        var colGrid = "No column data";

        if (sqltableFact?["db2Metadata"] is JsonNode db2Meta)
        {
            tableRemarks = db2Meta["tableRemarks"]?.GetValue<string>() ?? "No comment";
            var cols = db2Meta["columns"]?.AsArray();
            if (cols != null && cols.Count > 0)
            {
                var lines = new List<string> { "| # | Name | Type | Length | Nullable | Comment (Norwegian) |", "|---|---|---|---|---|---|" };
                int idx = 0;
                foreach (var c in cols)
                {
                    idx++;
                    var nullable = c?["nullable"]?.GetValue<string>() == "Y" ? "Yes" : "No";
                    lines.Add($"| {idx} | {c?["name"]} | {c?["typeName"]} | {c?["length"]} | {nullable} | {c?["remarks"]} |");
                }
                colGrid = string.Join("\n", lines);
            }
        }

        var prompt = $$"""
            You are analyzing columns of a legacy DB2 table for modernization to C#.
            Generate a CamelCase property name and English description for EACH column.
            Also identify any foreign key relationships (explicit or inferred).

            TABLE: {{tableName}} (Future C# name: {{futureTableName}})
            TABLE COMMENT (Norwegian): {{tableRemarks}}

            COLUMNS:
            {{colGrid}}

            Norwegian hints: NR=number, DATO=date, BELOP=amount, KODE=code, NAVN=name, ADR=address.

            Respond with EXACTLY one JSON object (no markdown, no explanation):
            {"columns":[{"name":"ORDRNR","futureName":"OrderNumber","description":"Unique order identifier","foreignKey":null}]}

            JSON:
            {"columns":[
            """;

        var response = await _ollamaClient.InvokeOllamaAsync(prompt);
        if (string.IsNullOrEmpty(response)) return;

        response = response.Trim();
        if (!response.StartsWith('{')) response = "{\"columns\":[" + response;

        var match = Regex.Match(response, @"\{[\s\S]*\}", RegexOptions.Singleline);
        if (!match.Success) return;

        try
        {
            var parsed = JsonNode.Parse(match.Value)?.AsObject();
            var columns = parsed?["columns"]?.AsArray();
            if (columns == null || columns.Count == 0) return;

            var updatedTableNaming = _cacheService.GetCachedNaming(tableName, "TableNames")?.AsObject()
                ?? new JsonObject { ["tableName"] = tableName };
            updatedTableNaming["columns"] = columns.DeepClone();
            _cacheService.SaveCachedNaming(tableName, "TableNames", updatedTableNaming);

            foreach (var col in columns)
            {
                var colName = col?["name"]?.GetValue<string>();
                var colFutureName = col?["futureName"]?.GetValue<string>();
                var colDescription = col?["description"]?.GetValue<string>();
                if (string.IsNullOrEmpty(colName)) continue;

                await UpsertColumnRegistryAsync(colName, colFutureName ?? colName, colDescription ?? "", tableName, analysisAlias);
            }

            ColumnNamingNew += columns.Count;
        }
        catch (Exception ex)
        {
            Logger.Warn($"Column naming parse failed for {tableName}: {ex.Message}");
        }
    }

    // ── Column Conflict Resolution ─────────────────────────────────────────────

    private async Task UpsertColumnRegistryAsync(string columnName, string futureName, string description, string tableName, string analysisAlias)
    {
        var colKey = columnName.ToUpperInvariant();
        var existing = _cacheService.GetCachedNaming(colKey, "ColumnNames");

        if (existing == null)
        {
            var newEntry = new JsonObject
            {
                ["originalName"] = colKey,
                ["futureName"] = futureName,
                ["finalContext"] = description,
                ["contexts"] = new JsonArray(new JsonObject
                {
                    ["analysis"] = analysisAlias,
                    ["description"] = description,
                    ["analyzedAt"] = DateTime.Now.ToString("yyyy-MM-ddTHH:mm:ss")
                }),
                ["usedInTables"] = new JsonArray(JsonValue.Create(tableName)),
                ["isTypicalForeignKey"] = false,
                ["typicalTarget"] = (string?)null,
                ["model"] = _ollamaModel,
                ["lastResolvedAt"] = DateTime.Now.ToString("yyyy-MM-ddTHH:mm:ss")
            };
            _cacheService.SaveCachedNaming(colKey, "ColumnNames", newEntry);
            return;
        }

        var usedInTables = existing["usedInTables"]?.AsArray() ?? new JsonArray();
        var tableList = usedInTables.Select(t => t?.GetValue<string>()).ToHashSet(StringComparer.OrdinalIgnoreCase);
        if (!tableList.Contains(tableName))
        {
            usedInTables.Add(JsonValue.Create(tableName));
        }

        var contexts = existing["contexts"]?.AsArray() ?? new JsonArray();
        bool alreadyHasContext = contexts.Any(c => c?["analysis"]?.GetValue<string>()?.Equals(analysisAlias, StringComparison.OrdinalIgnoreCase) == true);
        if (alreadyHasContext)
        {
            existing.AsObject()["usedInTables"] = usedInTables.DeepClone();
            _cacheService.SaveCachedNaming(colKey, "ColumnNames", existing);
            return;
        }

        var existingContext = existing["finalContext"]?.GetValue<string>() ?? "";
        var existingFutureName = existing["futureName"]?.GetValue<string>() ?? colKey;

        if (string.Equals(existingContext, description, StringComparison.OrdinalIgnoreCase)
            || string.IsNullOrEmpty(description))
        {
            contexts.Add(new JsonObject
            {
                ["analysis"] = analysisAlias,
                ["description"] = description,
                ["analyzedAt"] = DateTime.Now.ToString("yyyy-MM-ddTHH:mm:ss")
            });
            existing.AsObject()["contexts"] = contexts.DeepClone();
            existing.AsObject()["usedInTables"] = usedInTables.DeepClone();
            _cacheService.SaveCachedNaming(colKey, "ColumnNames", existing);
            return;
        }

        ColumnConflicts++;
        var contextList = string.Join("\n", contexts.Select(c =>
            $"- [{c?["analysis"]}] {c?["description"]}"));

        var conflictPrompt = $$"""
            You are resolving a naming conflict for a legacy DB2 column used across multiple analysis domains.

            COLUMN: {{colKey}}
            CURRENT FUTURE NAME: {{existingFutureName}}
            CURRENT FINAL CONTEXT: {{existingContext}}

            ALL ANALYSIS CONTEXTS:
            {{contextList}}

            NEW CONTEXT FROM [{{analysisAlias}}]: {{description}}

            Respond with EXACTLY one JSON object:
            {"verdict":"keep-both","futureName":"DepartmentNumber","finalContext":"Unified description covering all valid perspectives"}

            Verdicts: "keep-both" (both valid, merge), "replace-old" (old was wrong), "keep-old" (new is wrong)

            JSON:
            {"verdict":
            """;

        var conflictResp = await _ollamaClient.InvokeOllamaAsync(conflictPrompt);
        var resolved = ParseJsonResponse(conflictResp, "verdict");

        contexts.Add(new JsonObject
        {
            ["analysis"] = analysisAlias,
            ["description"] = description,
            ["analyzedAt"] = DateTime.Now.ToString("yyyy-MM-ddTHH:mm:ss")
        });

        var updated = existing.AsObject();
        updated["contexts"] = contexts.DeepClone();
        updated["usedInTables"] = usedInTables.DeepClone();
        updated["lastResolvedAt"] = DateTime.Now.ToString("yyyy-MM-ddTHH:mm:ss");

        if (resolved != null)
        {
            var verdict = resolved["verdict"]?.GetValue<string>() ?? "keep-both";
            var resolvedName = resolved["futureName"]?.GetValue<string>();
            var resolvedContext = resolved["finalContext"]?.GetValue<string>();

            if (!string.IsNullOrEmpty(resolvedName)) updated["futureName"] = resolvedName;
            if (!string.IsNullOrEmpty(resolvedContext)) updated["finalContext"] = resolvedContext;
        }

        _cacheService.SaveCachedNaming(colKey, "ColumnNames", updated);
    }

    // ── Program Naming ────────────────────────────────────────────────────────

    public async Task NameProgramAsync(
        JsonNode program,
        Dictionary<string, HashSet<string>> calledByMap,
        int ragResults)
    {
        var progName = program["program"]!.GetValue<string>();
        var norm = progName.ToUpperInvariant();

        var existing = _cacheService.GetCachedNaming(norm, "ProgramNames");
        if (existing != null && !string.IsNullOrEmpty(existing["futureProjectName"]?.GetValue<string>()))
        {
            ProgramNamingCached++;
            return;
        }

        var classification = program["classification"]?.GetValue<string>() ?? "unknown";
        var confidence = program["classificationConfidence"]?.GetValue<string>() ?? "unknown";
        var cobdokSystem = program["cobdokSystem"]?.GetValue<string>() ?? "Unknown";
        var cobdokDelsystem = program["cobdokDelsystem"]?.GetValue<string>() ?? "Unknown";
        var cobdokDesc = program["cobdokDescription"]?.GetValue<string>() ?? "No description";
        var isDeprecated = program["isDeprecated"]?.GetValue<bool>() == true ? "true" : "false";

        var sqlOps = program["sqlOperations"]?.AsArray() ?? [];
        var tableListStr = "None";
        if (sqlOps.Count > 0)
        {
            var tblGrouped = new Dictionary<string, HashSet<string>>(StringComparer.OrdinalIgnoreCase);
            foreach (var s in sqlOps)
            {
                var tk = s?["tableName"]?.GetValue<string>() ?? "";
                if (string.IsNullOrEmpty(tk)) continue;
                if (!tblGrouped.ContainsKey(tk)) tblGrouped[tk] = new(StringComparer.OrdinalIgnoreCase);
                var op = s?["operation"]?.GetValue<string>() ?? "";
                if (!string.IsNullOrEmpty(op)) tblGrouped[tk].Add(op);
            }
            var lines = tblGrouped.Take(15).Select(kv =>
            {
                var tn = _cacheService.GetCachedNaming(kv.Key, "TableNames");
                var futName = tn?["futureName"]?.GetValue<string>();
                var suffix = !string.IsNullOrEmpty(futName) ? $" ({futName})" : "";
                return $"{kv.Key}{suffix} [{string.Join(", ", kv.Value)}]";
            });
            tableListStr = string.Join("\n", lines);
        }

        var callTargets = "None";
        var targets = program["callTargets"]?.AsArray();
        if (targets != null && targets.Count > 0)
            callTargets = string.Join(", ", targets.Take(20).Select(t => t?.GetValue<string>() ?? ""));

        var callers = "None";
        if (calledByMap.TryGetValue(norm, out var callerSet) && callerSet.Count > 0)
            callers = string.Join(", ", callerSet.Take(10));

        var ragSnippet = "No source available";
        try
        {
            var rr = await _ragClient.InvokeRagAsync($"{norm} COBOL program purpose", ragResults);
            if (!string.IsNullOrEmpty(rr) && !rr.StartsWith("Error:"))
                ragSnippet = rr.Length > 1500 ? rr[..1500] : rr;
        }
        catch { }

        var sqlOpsCount = sqlOps.Count;
        var prompt = $$"""
            You are analyzing a legacy COBOL program for modernization to C#.
            Suggest a descriptive PascalCase C# project/class name and namespace.

            PROGRAM: {{norm}}
            CLASSIFICATION: {{classification}} (confidence: {{confidence}})
            COBDOK SYSTEM: {{cobdokSystem}}
            COBDOK SUBSYSTEM: {{cobdokDelsystem}}
            COBDOK DESCRIPTION (Norwegian): {{cobdokDesc}}
            IS DEPRECATED: {{isDeprecated}}

            TABLES USED ({{sqlOpsCount}} operations):
            {{tableListStr}}

            CALL TARGETS: {{callTargets}}
            CALLED BY: {{callers}}

            COBOL SOURCE SUMMARY:
            {{ragSnippet}}

            Respond with EXACTLY one JSON object:
            {"futureProjectName":"GrainStockMaintenance","futureNamespace":"Agriculture.Grain","description":"Manages grain stock levels"}

            JSON:
            {"futureProjectName":
            """;

        var response = await _ollamaClient.InvokeOllamaAsync(prompt);
        var parsed = ParseJsonResponse(response, "futureProjectName");
        if (parsed == null) return;

        var data = new JsonObject
        {
            ["program"] = norm,
            ["futureProjectName"] = parsed["futureProjectName"]?.GetValue<string>(),
            ["futureNamespace"] = parsed["futureNamespace"]?.GetValue<string>(),
            ["description"] = parsed["description"]?.GetValue<string>(),
            ["model"] = _ollamaModel,
            ["protocol"] = "Naming-ProgramNames",
            ["analyzedAt"] = DateTime.Now.ToString("yyyy-MM-ddTHH:mm:ss")
        };

        _cacheService.SaveCachedNaming(norm, "ProgramNames", data);
        ProgramNamingNew++;

        if (ProgramNamingNew % 25 == 0)
            Logger.Info($"    Programs named: {ProgramNamingNew} new, {ProgramNamingCached} cached...");
    }

    // ── Business Area Classification ──────────────────────────────────────────

    public async Task<JsonObject?> ClassifyBusinessAreasAsync(JsonArray programs, string alias)
    {
        var cachePath = Path.Combine(_cacheService.AnalysisCommonPath, "BusinessAreas", $"{alias}_business_areas.json");

        var currentProgs = programs.Select(p => p!["program"]!.GetValue<string>()).OrderBy(p => p).ToList();

        if (File.Exists(cachePath))
        {
            try
            {
                var cached = JsonNode.Parse(File.ReadAllText(cachePath))?.AsObject();
                if (cached?["programAreaMap"] is JsonObject pam && cached["version"]?.GetValue<int>() >= 2)
                {
                    var cachedProgs = pam.Select(kv => kv.Key).OrderBy(k => k).ToList();
                    if (cachedProgs.Count == currentProgs.Count && string.Join(",", cachedProgs) == string.Join(",", currentProgs))
                    {
                        Logger.Info("  Business area classification: using cache v2 (program set unchanged)");
                        return cached;
                    }
                }
            }
            catch { }
        }

        JsonObject? result;
        if (programs.Count > 100)
            result = await ClassifyMultiPassAsync(programs, alias);
        else
            result = await ClassifySinglePassAsync(programs, alias);

        if (result == null) return null;

        result["version"] = 2;
        Directory.CreateDirectory(Path.GetDirectoryName(cachePath)!);
        File.WriteAllText(cachePath, result.ToJsonString(JsonWriteOptions));
        Logger.Info($"  Business areas: {result["totalAreas"]} areas for {currentProgs.Count} programs — cached at {cachePath}");

        return result;
    }

    private async Task<JsonObject?> ClassifySinglePassAsync(JsonArray programs, string alias)
    {
        var programBlock = BuildEnrichedProgramBlock(programs.OfType<JsonNode>());
        var areaRange = programs.Count switch
        {
            <= 10 => "3-6",
            <= 50 => "5-12",
            _ => "8-15"
        };

        var prompt = $$"""
            You are a business domain analyst for a legacy COBOL ERP system (Dedge - Norwegian agricultural cooperative).
            Analyze the following programs and classify them into detailed business areas.

            PROGRAMS:
            {{programBlock}}

            RULES:
            1. Create {{areaRange}} business areas based on actual functional domains.
            2. Each area must have: id (kebab-case), name (English), description (1-2 sentences).
            3. Assign every program to exactly one primary area.
            4. Programs in the same system (e.g., IL=Innlan/lending, KD=grain, OA=order/delivery) usually belong to related areas.
            5. Programs calling each other often belong to the same area.
            6. Programs sharing the same tables often belong to the same area.
            7. Common utility programs (GM* prefix) should be in "common-infrastructure".
            8. Use domain-specific names like "interest-calculation", "grain-quality-control", "account-statements" — NOT generic names like "module-1", "batch-processing", or "legacy-modernization".
            9. Norwegian description hints: UTSKRIFT=printing/reports, BEREGNING=calculation, VEDLIKEHOLD=maintenance, REGISTRERING=registration, OVERFOERING=transfer.
            10. The programAreaMap MUST map each PROGRAM NAME (string) to exactly one area id (string). Do NOT invert the map.

            Return ONLY valid JSON (no markdown, no explanation):
            """ + """{"areas":[{"id":"area-id","name":"Area Name","description":"..."}],"programAreaMap":{"PROGRAM1":"area-id","PROGRAM2":"area-id"}}""";

        var response = await _ollamaClient.InvokeOllamaAsync(prompt);
        var parsed = ParseJsonResponse(response, "areas");
        if (parsed == null)
        {
            Logger.Warn("  Business area classification: Ollama returned no valid JSON");
            return null;
        }

        var spProgNames = programs.Select(p => p!["program"]!.GetValue<string>()).ToHashSet(StringComparer.OrdinalIgnoreCase);
        var programAreaMap = NormalizeProgramAreaMap(parsed, spProgNames);

        var mapObj = new JsonObject();
        foreach (var kv in programAreaMap.AsObject())
            mapObj[kv.Key] = kv.Value?.DeepClone();

        return new JsonObject
        {
            ["title"] = "Business Area Classification",
            ["generated"] = DateTime.Now.ToString("yyyy-MM-dd HH:mm:ss"),
            ["analysisAlias"] = alias,
            ["totalAreas"] = parsed["areas"]?.AsArray()?.Count ?? 0,
            ["areas"] = parsed["areas"]?.DeepClone() ?? new JsonArray(),
            ["programAreaMap"] = mapObj
        };
    }

    private async Task<JsonObject?> ClassifyMultiPassAsync(JsonArray programs, string alias)
    {
        Logger.Info($"  Business areas: multi-pass mode for {programs.Count} programs");

        var systemGroups = new Dictionary<string, List<JsonNode>>(StringComparer.OrdinalIgnoreCase);
        foreach (var p in programs)
        {
            var name = p!["program"]!.GetValue<string>();
            var system = GetAutoDocSystem(name);
            if (!systemGroups.ContainsKey(system))
                systemGroups[system] = [];
            systemGroups[system].Add(p!);
        }

        Logger.Info($"  System groups: {string.Join(", ", systemGroups.Select(g => $"{g.Key}({g.Value.Count})"))}");

        var allAreas = new JsonArray();
        var allMap = new Dictionary<string, string>(StringComparer.OrdinalIgnoreCase);
        var areaIdSet = new HashSet<string>(StringComparer.OrdinalIgnoreCase);

        foreach (var (system, groupProgs) in systemGroups.OrderByDescending(g => g.Value.Count))
        {
            var programBlock = BuildEnrichedProgramBlock(groupProgs);
            var areaRange = groupProgs.Count switch
            {
                <= 5 => "1-3",
                <= 20 => "2-6",
                <= 50 => "3-10",
                _ => "5-15"
            };

            var systemPrefix = system == "Unknown" ? "" : $"{system.ToLowerInvariant().Replace(" ", "-")}-";

            var prompt = $$"""
                You are a business domain analyst for a legacy COBOL ERP system (Dedge - Norwegian agricultural cooperative).
                Classify these programs from the "{{system}}" system group into detailed business sub-areas.

                PROGRAMS:
                {{programBlock}}

                RULES:
                1. Create {{areaRange}} business areas for this system group.
                2. Each area id MUST start with "{{systemPrefix}}" prefix (e.g., "{{systemPrefix}}quality-control").
                3. Each area must have: id (kebab-case), name (English), description (1-2 sentences).
                4. Assign every program to exactly one area.
                5. Programs calling each other often belong to the same area.
                6. Programs sharing tables often belong to the same area.
                7. Common utility programs (GM* prefix) should be in "common-infrastructure" (no prefix needed).
                8. Use domain-specific names, NOT generic names like "batch-processing" or "module-1".
                9. Norwegian hints: UTSKRIFT=printing/reports, BEREGNING=calculation, VEDLIKEHOLD=maintenance.
                10. The programAreaMap MUST map PROGRAM NAME (string) to area id (string). Do NOT invert.

                Return ONLY valid JSON:
                """ + """{"areas":[{"id":"area-id","name":"Area Name","description":"..."}],"programAreaMap":{"PROG":"area-id"}}""";

            JsonObject? parsed;
            try
            {
                var response = await _ollamaClient.InvokeOllamaAsync(prompt);
                parsed = ParseJsonResponse(response, "areas");
            }
            catch (Exception ex)
            {
                Logger.Warn($"  Business areas: Exception for system group '{system}': {ex.Message}");
                parsed = null;
            }

            if (parsed == null)
            {
                Logger.Warn($"  Business areas: Ollama failed for system group '{system}' — assigning to unclassified");
                foreach (var p in groupProgs)
                    allMap[p["program"]!.GetValue<string>()] = "unclassified";
                continue;
            }

            var progNames = groupProgs.Select(p => p["program"]!.GetValue<string>()).ToHashSet(StringComparer.OrdinalIgnoreCase);
            var groupMap = NormalizeProgramAreaMap(parsed, progNames);
            foreach (var area in parsed["areas"]?.AsArray() ?? [])
            {
                var id = area?["id"]?.GetValue<string>() ?? "";
                if (!string.IsNullOrEmpty(id) && areaIdSet.Add(id))
                    allAreas.Add(area!.DeepClone());
            }
            foreach (var kv in groupMap.AsObject())
                allMap[kv.Key] = kv.Value?.GetValue<string>() ?? "unclassified";

            Logger.Info($"    {system}: {parsed["areas"]?.AsArray()?.Count ?? 0} areas for {groupProgs.Count} programs");
        }

        if (!areaIdSet.Contains("unclassified") && allMap.Values.Any(v => v == "unclassified"))
        {
            allAreas.Add(new JsonObject
            {
                ["id"] = "unclassified",
                ["name"] = "Unclassified",
                ["description"] = "Programs that could not be classified into a specific area."
            });
        }

        var mapObj = new JsonObject();
        foreach (var kv in allMap)
            mapObj[kv.Key] = kv.Value;

        return new JsonObject
        {
            ["title"] = "Business Area Classification",
            ["generated"] = DateTime.Now.ToString("yyyy-MM-dd HH:mm:ss"),
            ["analysisAlias"] = alias,
            ["totalAreas"] = allAreas.Count,
            ["areas"] = allAreas,
            ["programAreaMap"] = mapObj
        };
    }

    private string BuildEnrichedProgramBlock(IEnumerable<JsonNode> programs)
    {
        var lines = new List<string>();
        foreach (var p in programs)
        {
            var name = p!["program"]!.GetValue<string>();
            var fpn = p["futureProjectName"]?.GetValue<string>() ?? "";
            var cls = p["classification"]?.GetValue<string>() ?? "";
            var desc = p["cobdokDescription"]?.GetValue<string>() ?? "";

            var autoDoc = _classifier.GetAutoDocData(name);
            var system = autoDoc?["metadata"]?["system"]?.GetValue<string>() ?? "";
            var typeLabel = autoDoc?["metadata"]?["typeLabel"]?.GetValue<string>() ?? "";
            var autoDocDesc = autoDoc?["description"]?.GetValue<string>() ?? "";
            if (string.IsNullOrEmpty(desc) && !string.IsNullOrEmpty(autoDocDesc))
                desc = autoDocDesc;

            var rawTables = (p["sqlOperations"]?.AsArray() ?? [])
                .Select(s => s?["tableName"]?.GetValue<string>() ?? "")
                .Where(t => !string.IsNullOrEmpty(t))
                .Distinct()
                .Take(8)
                .ToList();
            var tableEntries = rawTables.Select(t =>
            {
                var tn = _cacheService.GetCachedNaming(t, "TableNames");
                var futName = tn?["futureName"]?.GetValue<string>();
                return !string.IsNullOrEmpty(futName) ? $"{t}({futName})" : t;
            });
            var tables = string.Join(", ", tableEntries);

            var callTargets = string.Join(", ",
                (p["callTargets"]?.AsArray() ?? [])
                    .Select(t => t?.GetValue<string>() ?? "")
                    .Where(t => !string.IsNullOrEmpty(t))
                    .Take(10));

            var parts = new List<string> { $"  {name}" };
            if (!string.IsNullOrEmpty(fpn)) parts[0] += $" ({fpn})";
            parts[0] += $": {cls}";
            if (!string.IsNullOrEmpty(system)) parts.Add($"system: {system}");
            if (!string.IsNullOrEmpty(typeLabel)) parts.Add($"type: {typeLabel}");
            if (!string.IsNullOrEmpty(desc)) parts.Add(desc);
            if (!string.IsNullOrEmpty(tables)) parts.Add($"tables: {tables}");
            if (!string.IsNullOrEmpty(callTargets)) parts.Add($"calls: {callTargets}");

            lines.Add(string.Join(" — ", parts));
        }
        return string.Join("\n", lines);
    }

    private string GetAutoDocSystem(string programName)
    {
        var autoDoc = _classifier.GetAutoDocData(programName);
        var system = autoDoc?["metadata"]?["system"]?.GetValue<string>() ?? "";
        if (!string.IsNullOrEmpty(system))
        {
            var dash = system.IndexOf(" - ", StringComparison.Ordinal);
            return dash > 0 ? system[..dash].Trim() : system.Trim();
        }
        if (programName.StartsWith("GM", StringComparison.OrdinalIgnoreCase)) return "GM";
        if (programName.Length >= 2) return programName[..2].ToUpperInvariant();
        return "Unknown";
    }

    /// <summary>
    /// Detects and fixes inverted programAreaMap (area-id -> program[] instead of program -> area-id).
    /// </summary>
    private static JsonObject NormalizeProgramAreaMap(JsonObject parsed, HashSet<string> progNames)
    {
        var pam = parsed["programAreaMap"]?.AsObject();
        if (pam == null) return new JsonObject();

        var areaIds = (parsed["areas"]?.AsArray() ?? [])
            .Select(a => a?["id"]?.GetValue<string>() ?? "")
            .Where(id => !string.IsNullOrEmpty(id))
            .ToHashSet(StringComparer.OrdinalIgnoreCase);

        bool looksInverted = pam.Count > 0 &&
            pam.All(kv => areaIds.Contains(kv.Key) || kv.Value is JsonArray);

        if (looksInverted)
        {
            Logger.Warn("  Business areas: detected inverted programAreaMap — normalizing");
            var normalized = new JsonObject();
            foreach (var kv in pam)
            {
                var areaId = kv.Key;
                if (kv.Value is JsonArray arr)
                {
                    foreach (var item in arr)
                    {
                        var prog = item?.GetValue<string>();
                        if (!string.IsNullOrEmpty(prog))
                            normalized[prog] = areaId;
                    }
                }
                else
                {
                    var prog = kv.Value?.GetValue<string>();
                    if (!string.IsNullOrEmpty(prog) && progNames.Contains(prog))
                        normalized[prog] = areaId;
                }
            }
            return normalized;
        }

        var safe = new JsonObject();
        foreach (var kv in pam)
            safe[kv.Key] = kv.Value?.DeepClone();
        return safe;
    }

    // ── JSON Parsing Helpers ──────────────────────────────────────────────────

    private static JsonObject? ParseJsonResponse(string? response, string expectedKey)
    {
        if (string.IsNullOrEmpty(response)) return null;

        response = response.Trim();
        response = Regex.Replace(response, @"^```\w*\n?", "", RegexOptions.Multiline);
        response = Regex.Replace(response, @"\n?```$", "", RegexOptions.Multiline);
        response = response.Trim();

        if (!response.StartsWith('{'))
            response = $"{{\"{expectedKey}\":" + response;

        var match = Regex.Match(response, @"\{(?:[^{}]|\{(?:[^{}]|\{[^{}]*\})*\})*\}", RegexOptions.Singleline);
        if (!match.Success) return null;

        return SafeParseJsonWithDuplicates(match.Value);
    }

    /// <summary>
    /// Fallback parser when JsonNode.Parse throws on duplicate keys.
    /// Uses JsonDocument (which tolerates duplicates) and converts to JsonNode,
    /// keeping last-wins semantics for duplicate property names.
    /// </summary>
    private static JsonObject? SafeParseJsonWithDuplicates(string json)
    {
        try
        {
            using var doc = JsonDocument.Parse(json);
            return ConvertElement(doc.RootElement)?.AsObject();
        }
        catch
        {
            return null;
        }
    }

    private static JsonNode? ConvertElement(JsonElement element)
    {
        switch (element.ValueKind)
        {
            case JsonValueKind.Object:
                var obj = new JsonObject();
                foreach (var prop in element.EnumerateObject())
                    obj[prop.Name] = ConvertElement(prop.Value);
                return obj;

            case JsonValueKind.Array:
                var arr = new JsonArray();
                foreach (var item in element.EnumerateArray())
                    arr.Add(ConvertElement(item));
                return arr;

            case JsonValueKind.String:
                return JsonValue.Create(element.GetString());

            case JsonValueKind.Number:
                if (element.TryGetInt64(out var l)) return JsonValue.Create(l);
                return JsonValue.Create(element.GetDouble());

            case JsonValueKind.True:
                return JsonValue.Create(true);

            case JsonValueKind.False:
                return JsonValue.Create(false);

            default:
                return null;
        }
    }
}
