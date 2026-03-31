using System.Text.Json;
using System.Text.Json.Nodes;
using System.Text.RegularExpressions;
using NLog;
using SystemAnalyzer2.Batch.Services.Analyzers.Cobol;
using SystemAnalyzer2.Batch.Services.Shared;

namespace SystemAnalyzer2.Batch.Services;

public sealed class DependencyExtractor
{
    private static readonly Logger Logger = LogManager.GetCurrentClassLogger();

    private readonly RagClient _ragClient;
    private readonly OllamaClient _ollamaClient;
    private readonly SourceIndexService _sourceIndex;
    private readonly CacheService _cacheService;

    public static Regex CopyPattern => CobolAnalyzerBase.CopyPattern;
    public static Regex CallPattern => CobolAnalyzerBase.CallPattern;
    public static Regex SqlBlockPattern => CobolAnalyzerBase.SqlBlockPattern;
    public static Regex SqlTablePattern => CobolAnalyzerBase.SqlTablePattern;
    public static Regex SelectAssignPattern => CobolAnalyzerBase.SelectAssignPattern;
    public static Regex OpenPattern => CobolAnalyzerBase.OpenPattern;
    public static Regex RagSourcePattern => CobolAnalyzerBase.RagSourcePattern;
    public static HashSet<string> CallExcludeSet => CobolAnalyzerBase.CallExcludeSet;
    public static HashSet<string> SqlNotTables => CobolAnalyzerBase.SqlNotTables;
    public static HashSet<string> SkipLogicalFiles => CobolAnalyzerBase.SkipLogicalFiles;

    public DependencyExtractor(RagClient ragClient, OllamaClient ollamaClient,
        SourceIndexService sourceIndex, CacheService cacheService)
    {
        _ragClient = ragClient;
        _ollamaClient = ollamaClient;
        _sourceIndex = sourceIndex;
        _cacheService = cacheService;
    }

    /// <summary>
    /// Match V1: returns name = full raw uppercased (including extension), type only.
    /// </summary>
    public List<JsonObject> GetCopyElements(string text)
    {
        var found = new HashSet<string>(StringComparer.OrdinalIgnoreCase);
        var results = new List<JsonObject>();
        foreach (Match m in CopyPattern.Matches(text))
        {
            var raw = m.Groups[1].Value.Trim();
            if (string.IsNullOrEmpty(raw) || Regex.IsMatch(raw, "^(SQLCA|SQLENV|SQLSTATE)$")) continue;
            if (!found.Add(raw)) continue;

            var ext = "";
            var extMatch = Regex.Match(raw, @"\.(\w+)$");
            if (extMatch.Success) ext = extMatch.Groups[1].Value.ToUpperInvariant();

            var copyType = ext switch
            {
                "CPY" => "copybook",
                "CPB" => "copybook-binary",
                "DCL" => "sql-declare",
                "" => "copybook",
                _ => ext.ToLowerInvariant()
            };
            results.Add(new JsonObject
            {
                ["name"] = raw.ToUpperInvariant(),
                ["type"] = copyType
            });
        }
        return results;
    }

    /// <summary>
    /// Match V1: schema = (UNQUALIFIED) when not specified, property = tableName, no qualifiedName.
    /// </summary>
    public List<JsonObject> GetSqlOperations(string text)
    {
        var results = new List<JsonObject>();
        var seen = new HashSet<string>(StringComparer.OrdinalIgnoreCase);

        foreach (Match block in SqlBlockPattern.Matches(text))
        {
            var sqlText = block.Groups[1].Value;
            foreach (Match tm in SqlTablePattern.Matches(sqlText))
            {
                var rawOp = tm.Groups[1].Value.Trim();
                var schema = tm.Groups[2].Success ? tm.Groups[2].Value.Trim() : "(unqualified)";
                var table = tm.Groups[3].Value.Trim().ToUpperInvariant();

                if (SqlNotTables.Contains(table)) continue;
                if (table.Length < 2) continue;
                if (char.IsDigit(table[0]) || table[0] == ':') continue;

                var operation = NormalizeSqlOperation(rawOp);
                schema = schema.ToUpperInvariant();

                var key = $"{schema}|{table}|{operation}";
                if (!seen.Add(key)) continue;

                results.Add(new JsonObject
                {
                    ["schema"] = schema,
                    ["tableName"] = table,
                    ["operation"] = operation
                });
            }
        }
        return results;
    }

    /// <summary>
    /// V1 switch-regex mapping (Batch.CSharp FullAnalysisPipeline.cs lines 712-724):
    ///   SELECT  → SELECT
    ///   FROM    → SELECT   (table ref in FROM clause is a SELECT operation)
    ///   JOIN    → SELECT   (table ref in JOIN clause is a SELECT operation)
    ///   INSERT  → INSERT
    ///   INTO    → INSERT   (INTO after INSERT maps to INSERT)
    ///   UPDATE  → UPDATE
    ///   DELETE  → DELETE
    ///   MERGE   → MERGE
    ///   TABLE   → DDL
    ///   INCLUDE → INCLUDE
    /// </summary>
    private static string NormalizeSqlOperation(string rawOp)
    {
        var normalized = Regex.Replace(rawOp.Trim(), @"\s+", " ").ToUpperInvariant();
        if (normalized.StartsWith("INSERT")) return "INSERT";
        if (normalized.StartsWith("DELETE")) return "DELETE";
        if (normalized.StartsWith("MERGE")) return "MERGE";
        if (normalized == "SELECT") return "SELECT";
        if (normalized == "FROM") return "SELECT";
        if (normalized == "JOIN") return "SELECT";
        if (normalized == "UPDATE") return "UPDATE";
        if (normalized == "INTO") return "INSERT";
        if (normalized == "TABLE") return "DDL";
        if (normalized == "INCLUDE") return "INCLUDE";
        return normalized;
    }

    /// <summary>
    /// Match V1: strip .cbl/.obj suffix, exclude names with hyphens, length &lt; 3,
    /// CBL_ prefix, and IEF/DFS/etc prefixes.
    /// </summary>
    public List<string> GetCallTargets(string text)
    {
        var seen = new HashSet<string>(StringComparer.OrdinalIgnoreCase);
        var targets = new List<string>();
        foreach (Match m in CallPattern.Matches(text))
        {
            var target = m.Groups[1].Value.Trim();
            target = CobolAnalyzerBase.CallExtensionStrip.Replace(target, "");
            target = target.ToUpperInvariant();

            if (!TestExcludeCall(target) && seen.Add(target))
                targets.Add(target);
        }
        return targets;
    }

    /// <summary>
    /// Match V1 Test-ExcludeCall: length &lt; 3, contains hyphen, in exclude set,
    /// CBL_ prefix, or IEF/DFS/etc prefix.
    /// </summary>
    public static bool TestExcludeCall(string name)
    {
        if (string.IsNullOrEmpty(name) || name.Length < 3) return true;
        if (name.Contains('-')) return true;
        if (CallExcludeSet.Contains(name)) return true;
        if (CobolAnalyzerBase.CallExcludePrefix.IsMatch(name)) return true;
        return false;
    }

    /// <summary>
    /// Match V1: output fields are logicalName, physicalName, path, fullPath, assignType, operations.
    /// </summary>
    public List<JsonObject> GetFileIO(string text, string? defaultFilePath)
    {
        defaultFilePath ??= @"N:\COBNT";
        var fileMap = new Dictionary<string, JsonObject>(StringComparer.OrdinalIgnoreCase);

        foreach (Match m in SelectAssignPattern.Matches(text))
        {
            var logical = m.Groups[1].Value.Trim().ToUpperInvariant();
            if (SkipLogicalFiles.Contains(logical)) continue;

            string physName;
            string physPath = defaultFilePath;
            string assignType;
            string? fullP = null;

            if (m.Groups[2].Success || m.Groups[3].Success)
            {
                var literal = m.Groups[2].Success ? m.Groups[2].Value : m.Groups[3].Value;
                assignType = "literal";

                if (Regex.IsMatch(literal, @"[\\\/:]"))
                {
                    try
                    {
                        physPath = Path.GetDirectoryName(literal) ?? defaultFilePath;
                        physName = Path.GetFileName(literal);
                    }
                    catch
                    {
                        physPath = defaultFilePath;
                        physName = literal;
                    }
                    if (string.IsNullOrEmpty(physPath)) physPath = defaultFilePath;
                    fullP = literal;
                }
                else
                {
                    physName = literal;
                    try { fullP = Path.Combine(physPath, physName); }
                    catch { fullP = $"{physPath}\\{physName}"; }
                }
            }
            else if (m.Groups[4].Success)
            {
                physName = m.Groups[4].Value;
                assignType = Regex.IsMatch(physName, @"^(DYNAMIC|SELECT)$", RegexOptions.IgnoreCase)
                    ? "dynamic" : "variable";
            }
            else
            {
                continue;
            }

            if (!fileMap.ContainsKey(logical))
            {
                fileMap[logical] = new JsonObject
                {
                    ["logicalName"] = logical,
                    ["physicalName"] = physName,
                    ["path"] = physPath,
                    ["fullPath"] = fullP,
                    ["assignType"] = assignType,
                    ["operations"] = new JsonArray()
                };
            }
        }

        // V1 Pass 2: OPEN statements — only add operations to files ALREADY declared by SELECT...ASSIGN
        foreach (Match m in OpenPattern.Matches(text))
        {
            var rawMode = m.Groups[1].Value.Trim().ToUpperInvariant();
            var mode = rawMode switch
            {
                "INPUT" => "READ",
                "OUTPUT" => "WRITE",
                "EXTEND" => "WRITE",
                "I-O" => "READ-WRITE",
                _ => rawMode
            };

            var files = m.Groups[2].Value.Split([' ', '\t'], StringSplitOptions.RemoveEmptyEntries);
            foreach (var f in files)
            {
                var fn = f.Trim().ToUpperInvariant();
                if (fn.Length < 2) continue;
                if (fileMap.TryGetValue(fn, out var entry))
                {
                    var ops = entry["operations"]!.AsArray();
                    if (!ops.Any(o => o?.GetValue<string>() == mode))
                        ops.Add(mode);
                }
            }
        }

        foreach (var entry in fileMap.Values)
        {
            var ops = entry["operations"]!.AsArray();
            if (ops.Count == 0)
                ops.Add("UNKNOWN");
        }

        return fileMap.Values.ToList();
    }

    public bool TestValidCallTarget(string target)
    {
        if (TestExcludeCall(target)) return false;
        var resolution = _sourceIndex.ResolveProgramSource(target);
        return resolution.Type.StartsWith("local-") || resolution.Type == "rag";
    }

    /// <summary>
    /// Validate call target via source index + RAG lookup (match V1 Test-ValidCallTarget).
    /// </summary>
    public async Task<bool> TestValidCallTargetWithRagAsync(string target, RagClient ragClient, HashSet<string> validProgramNames)
    {
        if (TestExcludeCall(target)) return false;
        var upper = target.ToUpperInvariant();

        if (validProgramNames.Contains(upper)) return true;

        var ragResult = await ragClient.InvokeRagAsync($"COBOL program {target} source file .CBL", 2);
        if (!string.IsNullOrEmpty(ragResult) &&
            Regex.IsMatch(ragResult, $@"(?i)\b{Regex.Escape(target)}\.CBL\b"))
        {
            validProgramNames.Add(upper);
            return true;
        }

        return false;
    }

    public List<JsonObject> FilterSqlByBoundary(List<JsonObject> sqlOps, HashSet<string> catalogQualified)
    {
        if (catalogQualified.Count == 0) return sqlOps;
        return sqlOps.Where(op =>
        {
            var schema = op["schema"]?.GetValue<string>() ?? "";
            var table = op["tableName"]?.GetValue<string>() ?? "";
            var qn = schema.Length > 1 && schema != "(UNQUALIFIED)" ? $"{schema}.{table}" : null;
            return qn != null && catalogQualified.Contains(qn);
        }).ToList();
    }
}
