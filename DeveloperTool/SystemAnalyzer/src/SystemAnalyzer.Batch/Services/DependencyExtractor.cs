using System.Text.Json;
using System.Text.Json.Nodes;
using System.Text.RegularExpressions;
using NLog;

namespace SystemAnalyzer.Batch.Services;

public sealed class DependencyExtractor
{
    private static readonly Logger Logger = LogManager.GetCurrentClassLogger();

    private readonly RagClient _ragClient;
    private readonly OllamaClient _ollamaClient;
    private readonly SourceIndexService _sourceIndex;
    private readonly CacheService _cacheService;

    public static readonly Regex CopyPattern = new(
        @"\bCOPY\s+['""]?([A-Z0-9_\-\\.]+)['""]?\s*\.?", RegexOptions.IgnoreCase | RegexOptions.Compiled);

    public static readonly Regex CallPattern = new(
        @"(?<![A-Za-z0-9\-])CALL\s+['""]?([A-Z0-9_\-]+)['""]?(?:\s|$)", RegexOptions.IgnoreCase | RegexOptions.Compiled);

    // Regex to strip trailing COBOL extensions from call targets
    private static readonly Regex CallExtensionStrip = new(
        @"\.(cbl|CBL|obj|OBJ)$", RegexOptions.Compiled);

    public static readonly Regex SqlBlockPattern = new(
        @"EXEC\s+SQL\s+(.+?)END-EXEC", RegexOptions.IgnoreCase | RegexOptions.Singleline | RegexOptions.Compiled);

    public static readonly Regex SqlTablePattern = new(
        @"\b(SELECT|INSERT\s+INTO|UPDATE|DELETE\s+FROM|MERGE\s+INTO|FROM|JOIN|INTO|TABLE|INCLUDE)\s+(?:(\w+)\.)?(\w+)",
        RegexOptions.IgnoreCase | RegexOptions.Compiled);

    public static readonly Regex SelectAssignPattern = new(
        @"\bSELECT\s+(?:OPTIONAL\s+)?(\w[\w-]*)\s+ASSIGN\s+(?:TO\s+)?(?:""([^""]+)""|'([^']+)'|(\w[\w-]*))",
        RegexOptions.IgnoreCase | RegexOptions.Compiled);

    public static readonly Regex OpenPattern = new(
        @"\bOPEN\s+(INPUT|OUTPUT|I-O|EXTEND)\s+([\w][\w-]*(?:[ \t]+[\w][\w-]*)*)",
        RegexOptions.IgnoreCase | RegexOptions.Compiled);

    public static readonly Regex RagSourcePattern = new(
        @"\(source:\s*([A-Z0-9_]+)\.CBL", RegexOptions.IgnoreCase | RegexOptions.Compiled);

    // V1-matching additional call exclusion patterns
    private static readonly Regex CallExcludePrefix = new(
        @"^(IEF|DFS|DFH|CEE|CEEDAY|ILBO|IGZ|__|WIN32|WINAPI|COB32API|CBL_)",
        RegexOptions.IgnoreCase | RegexOptions.Compiled);

    public static readonly HashSet<string> CallExcludeSet = new(StringComparer.OrdinalIgnoreCase)
    {
        "IF","MOVE","ADD","SUBTRACT","MULTIPLY","DIVIDE","COMPUTE","PERFORM","EXIT",
        "EVALUATE","WHEN","OTHER","END","GO","TO","GOBACK","STOP","RUN",
        "ACCEPT","DISPL","DISPL1","DISPL2","INSPECT","EXEC","END-IF","ERROR",
        "STREAM","LINEOUT","PREP_SQL","CALL","DISPLAY","PIC","PAYD","OG","TIL",
        "INS","IS","---","AVSLUTT","SLUTT","SYSFILETREE","SYSLOADFUNCS","SYSSLEEP",
        "RXFUNCADD","START_REXX","DIALOG-SYSTEM","INVOKE-MESSAGE-BOX",
        "ENABLE-OBJECT","DISABLE-OBJECT","REFRESH-OBJECT",
        "REPLACING","COPY","USING","RETURNING","GIVING","ALSO","THRU","THROUGH",
        "VARYING","UNTIL","THE","FROM","UPON","VALUE","SIZE","LENGTH","STRING",
        "UNSTRING","INITIALIZE","RELEASE","RETURN","OPEN","CLOSE","READ","WRITE",
        "REWRITE","DELETE","START","SORT","MERGE","GENERATE","SECTION","PARAGRAPH",
        "CONTINUE",
        "INTO","VALUES","LEFT","RIGHT","INNER","OUTER","CROSS","ORDER","GROUP",
        "HAVING","DISTINCT","WHERE","SELECT","INSERT","UPDATE","DELETE","TABLE",
        "BETWEEN","LIKE","EXISTS","CASE","THEN","ELSE","UNION","EXCEPT",
        "INTERSECT","FETCH","FIRST","ONLY","ROWS","NEXT","PRIOR","CURSOR",
        "DECLARE","END-EXEC","COMMIT","ROLLBACK","CONNECT","DISCONNECT",
        "SET","NULL","NOT","AND","ALL","ANY","ASC","DESC",
        "DB2API","COBAPI","NETAPI","CBLJAPI","CBLAPI","CICS","CICSAPI"
    };

    public static readonly HashSet<string> SqlNotTables = new(StringComparer.OrdinalIgnoreCase)
    {
        "SQLCA","SQLDA","SECTION","SQL","EXEC","END","WHERE","SET","VALUES","INTO","AND",
        "OR","NOT","NULL","IS","AS","ON","BY","ORDER","GROUP","HAVING","DISTINCT",
        "ALL","ANY","BETWEEN","LIKE","IN","EXISTS","CASE","WHEN","THEN","ELSE",
        "BEGIN","COMMIT","ROLLBACK","DECLARE","CURSOR","OPEN","CLOSE","FETCH","NEXT",
        "FOR","READONLY","READ","ONLY","WITH","HOLD","LOCK","ROW","ROWS","FIRST","LAST",
        "CURRENT","OF","TIMESTAMP","DATE","TIME","INTEGER","SMALLINT","CHAR","VARCHAR",
        "DECIMAL","NUMERIC","FLOAT","DOUBLE","BLOB","CLOB","DBCLOB","GRAPHIC",
        "VARGRAPHIC","BIGINT","REAL","BINARY","VARBINARY","BOOLEAN","XML",
        "GLOBAL","TEMPORARY","SEQUENCE","INDEX","VIEW","PROCEDURE","FUNCTION","TRIGGER",
        "INNER","OUTER","LEFT","RIGHT","FULL","CROSS","NATURAL","UNION","EXCEPT","INTERSECT",
        "ASC","DESC","LIMIT","OFFSET","TOP","COUNT","SUM","AVG","MIN","MAX","COALESCE",
        "CAST","TRIM","UPPER","LOWER","SUBSTRING","LENGTH","REPLACE","POSITION",
        "EXTRACT","YEAR","MONTH","DAY","HOUR","MINUTE","SECOND","MICROSECOND",
        "ISOLATION","LEVEL","REPEATABLE","SERIALIZABLE","UNCOMMITTED","COMMITTED",
        "WORK","SAVEPOINT","RELEASE","TO","DATA","EXTERNAL","INPUT","OUTPUT"
    };

    public static readonly HashSet<string> SkipLogicalFiles = new(StringComparer.OrdinalIgnoreCase)
    {
        "PRINTER","PRINT-FILE","SYSOUT","SYSIN","CONSOLE","DISPLAY","KEYBOARD",
        "LINE-SEQUENTIAL","BINARY-SEQUENTIAL","RECORD-SEQUENTIAL",
        "ORGANIZATION","RECORDING","MODE","STATUS","FILE-STATUS",
        "LINAGE","FOOTING","TOP","BOTTOM","LINE-COUNTER","PAGE-COUNTER",
        "SORT-FILE","MERGE-FILE","REPORT-FILE","USE","GIVING","USING"
    };

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
            target = CallExtensionStrip.Replace(target, "");
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
        if (CallExcludePrefix.IsMatch(name)) return true;
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
