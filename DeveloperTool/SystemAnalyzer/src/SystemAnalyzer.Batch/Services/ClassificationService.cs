using System.Text.Json;
using System.Text.Json.Nodes;
using NLog;
using SystemAnalyzer.Core.Models;

namespace SystemAnalyzer.Batch.Services;

public sealed class ClassificationService
{
    private static readonly Logger Logger = LogManager.GetCurrentClassLogger();

    private readonly OllamaClient _ollamaClient;
    private readonly RagClient _ragClient;
    private readonly CacheService _cacheService;
    private readonly SystemAnalyzerOptions _options;

    private readonly Dictionary<string, JsonObject> _autoDocCache = new(StringComparer.OrdinalIgnoreCase);
    private bool _autoDocPathVerified;

    public ClassificationService(OllamaClient ollamaClient, RagClient ragClient,
        CacheService cacheService, SystemAnalyzerOptions options)
    {
        _ollamaClient = ollamaClient;
        _ragClient = ragClient;
        _cacheService = cacheService;
        _options = options;
    }

    /// <summary>
    /// Returns the UNC file path for a program's AutoDoc JSON.
    /// </summary>
    public string GetAutoDocFilePath(string programName)
    {
        var basePath = _options.AutoDocJsonPath ?? "";
        return Path.Combine(basePath, $"{programName.ToUpperInvariant()}.CBL.json");
    }

    /// <summary>
    /// Checks if the AutoDoc file exists on disk for the given program.
    /// </summary>
    public bool AutoDocFileExists(string programName)
    {
        if (!EnsureAutoDocPathAccessible()) return false;
        return File.Exists(GetAutoDocFilePath(programName));
    }

    /// <summary>
    /// On-demand: loads and caches a single program's AutoDoc data from UNC.
    /// </summary>
    public JsonObject? GetAutoDocData(string programName)
    {
        var key = programName.ToUpperInvariant();
        if (_autoDocCache.TryGetValue(key, out var cached))
            return cached;

        if (!EnsureAutoDocPathAccessible()) return null;

        var filePath = GetAutoDocFilePath(programName);
        if (!File.Exists(filePath)) return null;

        try
        {
            var text = File.ReadAllText(filePath);
            var obj = JsonNode.Parse(text)?.AsObject();
            if (obj != null)
                _autoDocCache[key] = obj;
            return obj;
        }
        catch (Exception ex)
        {
            Logger.Debug($"AutoDoc: failed to parse {Path.GetFileName(filePath)}: {ex.Message}");
            return null;
        }
    }

    public bool TestProgramInAutoDocIndex(string programName)
    {
        return _autoDocCache.ContainsKey(programName.ToUpperInvariant()) || AutoDocFileExists(programName);
    }

    private bool EnsureAutoDocPathAccessible()
    {
        if (_autoDocPathVerified) return true;
        var basePath = _options.AutoDocJsonPath;
        if (string.IsNullOrEmpty(basePath) || !Directory.Exists(basePath))
        {
            Logger.Warn($"AutoDoc UNC path not accessible: {basePath}");
            return false;
        }
        _autoDocPathVerified = true;
        return true;
    }

    public async Task<bool> TestStandardCobolProgramAsync(string programName, string? sourceText)
    {
        if (string.IsNullOrEmpty(sourceText)) return false;

        var ragResult = await _ragClient.InvokeVisualCobolRagAsync(
            $"{programName} standard COBOL runtime library utility", 4);

        if (!string.IsNullOrEmpty(ragResult) && ragResult.Contains(programName, StringComparison.OrdinalIgnoreCase))
        {
            var prompt = $"Is '{programName}' a standard COBOL runtime library program (like INSPECT, STRING utilities, " +
                         $"date conversion, or Micro Focus/Rocket runtime)? Answer YES or NO only. " +
                         $"Context from documentation: {ragResult[..Math.Min(ragResult.Length, 500)]}";
            var answer = await _ollamaClient.InvokeOllamaAsync(prompt);
            return answer.Contains("YES", StringComparison.OrdinalIgnoreCase);
        }
        return false;
    }

    /// <summary>
    /// V1 Classify-ProgramByRules: uses 3rd character of program name + copybook evidence.
    /// Cross-ref Batch.CSharp lines 1378-1448.
    /// </summary>
    public JsonObject ClassifyProgramByRules(string programName, JsonNode? masterEntry)
    {
        var copies = new HashSet<string>(StringComparer.OrdinalIgnoreCase);
        if (masterEntry?["copyElements"] is JsonArray copyArr)
        {
            foreach (var ce in copyArr)
            {
                var name = ce?["name"]?.GetValue<string>();
                if (!string.IsNullOrEmpty(name))
                    copies.Add(name.ToUpperInvariant());
            }
        }

        var thirdChar = programName.Length >= 3
            ? char.ToUpperInvariant(programName[2])
            : '?';

        bool hasDsrunner  = copies.Contains("DSRUNNER.CPY");
        bool hasDssysinf  = copies.Contains("DSSYSINF.CPY");
        bool hasDsCntrl   = copies.Contains("DS-CNTRL.MF");
        bool hasDsUsrVal  = copies.Contains("DSUSRVAL.CPY");
        bool hasGmadbba   = copies.Contains("GMADBBA.CPY");
        bool hasGmasoal   = copies.Contains("GMASOAL.CPY");
        bool hasDialogSys = hasDsrunner || hasDssysinf || hasDsCntrl;

        string classification, confidence, evidence;

        switch (thirdChar)
        {
            case 'H':
                confidence = hasDialogSys ? "high" : "medium";
                evidence = "3rd-letter=H";
                if (hasDialogSys) evidence += ", has Dialog System copybooks";
                classification = "main-ui";
                break;
            case 'V':
                confidence = hasDsUsrVal ? "high" : "medium";
                evidence = "3rd-letter=V";
                if (hasDsUsrVal) evidence += ", has DSUSRVAL.CPY";
                classification = "validation-ui";
                break;
            case 'F':
                confidence = hasDialogSys ? "high" : "medium";
                evidence = "3rd-letter=F";
                if (hasDialogSys) evidence += ", has Dialog System copybooks";
                classification = "secondary-ui";
                break;
            case 'B':
                confidence = !hasDialogSys ? "high" : "low";
                evidence = "3rd-letter=B";
                if (!hasDialogSys) evidence += ", no Dialog System copybooks";
                classification = "batch-processing";
                break;
            case 'S':
                if (hasGmadbba || hasGmasoal)
                    return MakeClassification(programName, "webservice", "high", "3rd-letter=S, has GMADBBA/GMASOAL");
                if (hasDialogSys)
                    return MakeClassification(programName, "main-ui", "medium", "3rd-letter=S but has Dialog System copybooks");
                return MakeClassification(programName, "webservice", "medium", "3rd-letter=S");
            case 'A':
                confidence = !hasDialogSys ? "high" : "medium";
                evidence = "3rd-letter=A";
                if (!hasDialogSys) evidence += ", no Dialog System copybooks";
                classification = "common-utility";
                break;
            default:
                if (hasDialogSys)
                {
                    var cls = hasDsUsrVal ? "validation-ui" : "main-ui";
                    return MakeClassification(programName, cls, "medium", "copybook-fallback: has Dialog System copybooks");
                }
                if (hasDsUsrVal)
                    return MakeClassification(programName, "validation-ui", "medium", "copybook-fallback: has DSUSRVAL.CPY");
                if (hasGmadbba || hasGmasoal)
                    return MakeClassification(programName, "webservice", "medium", "copybook-fallback: has GMADBBA/GMASOAL");
                return MakeClassification(programName, "unknown", "low", "no matching 3rd-letter rule or copybook pattern");
        }

        return MakeClassification(programName, classification, confidence, evidence);
    }

    private static JsonObject MakeClassification(string program, string cls, string conf, string ev) =>
        new()
        {
            ["program"] = program,
            ["classification"] = cls,
            ["classificationConfidence"] = conf,
            ["classificationEvidence"] = ev
        };

    public async Task UpdateColumnRegistryAsync(string tableName, string schema,
        List<Dictionary<string, string?>> columns)
    {
        var cached = _cacheService.GetCachedNaming(tableName, "ColumnNames");
        if (cached != null) return;

        var columnNames = columns.Select(c => c.GetValueOrDefault("COLNAME") ?? "").ToList();
        if (columnNames.Count == 0) return;

        var prompt = $"For DB2 table {schema}.{tableName}, suggest human-readable CamelCase names for these columns:\n" +
                     string.Join("\n", columnNames.Select(c => $"  {c}")) +
                     "\nReturn JSON object mapping original name to CamelCase name.";

        var response = await _ollamaClient.InvokeOllamaAsync(prompt);
        if (string.IsNullOrEmpty(response)) return;

        try
        {
            var naming = JsonNode.Parse(response);
            if (naming != null)
            {
                _cacheService.SaveCachedNaming(tableName, "ColumnNames", naming);
            }
        }
        catch (Exception ex)
        {
            Logger.Warn($"Column naming parse failed for {tableName}: {ex.Message}");
        }
    }
}
