using System;
using System.Collections.Generic;
using System.IO;
using System.Linq;
using System.Text.Json;
using System.Text.RegularExpressions;

namespace SystemAnalyzer2.Batch.Services.Shared;

/// <summary>
/// Builds a lightweight search index (_json/search-index.json) from all per-file JSON results.
/// The index extracts searchable field values so the SearchEngine can query without
/// opening every individual JSON file at runtime.
/// </summary>
public static class SearchIndexBuilder
{
    private static readonly JsonSerializerOptions JsonOpts = new()
    {
        PropertyNameCaseInsensitive = true,
        PropertyNamingPolicy = JsonNamingPolicy.CamelCase,
        WriteIndented = false
    };

    public static void Build(string outputFolder)
    {
        string jsonFolder = Path.Combine(outputFolder, "_json");
        if (!Directory.Exists(jsonFolder))
            Directory.CreateDirectory(jsonFolder);

        string indexPath = Path.Combine(jsonFolder, "search-index.json");
        var entries = new List<Dictionary<string, object>>();

        foreach (string jsonFile in Directory.EnumerateFiles(outputFolder, "*.json")
            .Where(f => !Path.GetFileName(f).StartsWith("_"))
            .OrderBy(f => f))
        {
            try
            {
                string raw = File.ReadAllText(jsonFile);
                using var doc = JsonDocument.Parse(raw);
                var root = doc.RootElement;

                string type = GetString(root, "type");
                if (string.IsNullOrEmpty(type)) continue;

                var fields = new Dictionary<string, string>();
                ExtractCommonFields(root, fields);

                switch (type.ToUpperInvariant())
                {
                    case "CBL": ExtractCblFields(root, fields); break;
                    case "SQL": ExtractSqlFields(root, fields); break;
                    case "BAT": ExtractBatFields(root, fields); break;
                    case "PS1": ExtractPs1Fields(root, fields); break;
                    case "REX": ExtractRexFields(root, fields); break;
                    case "CSHARP": ExtractCSharpFields(root, fields); break;
                }

                // Remove empty fields
                var cleanFields = fields
                    .Where(kv => !string.IsNullOrWhiteSpace(kv.Value))
                    .ToDictionary(kv => kv.Key, kv => kv.Value);

                entries.Add(new Dictionary<string, object>
                {
                    ["f"] = Path.GetFileName(jsonFile),
                    ["t"] = type,
                    ["n"] = GetString(root, "fileName"),
                    ["d"] = GetString(root, "description"),
                    ["g"] = GetString(root, "generatedAt"),
                    ["fields"] = cleanFields
                });
            }
            catch (Exception ex)
            {
                AutoDocLogger.LogMessage($"SearchIndex: skipping {Path.GetFileName(jsonFile)}: {ex.Message}", LogLevel.WARN);
            }
        }

        string json = JsonSerializer.Serialize(entries, new JsonSerializerOptions
        {
            WriteIndented = false,
            PropertyNamingPolicy = JsonNamingPolicy.CamelCase
        });
        File.WriteAllText(indexPath, json, System.Text.Encoding.UTF8);
        AutoDocLogger.LogMessage($"SearchIndex: Built search-index.json with {entries.Count} entries", LogLevel.INFO);
    }

    private static void ExtractCommonFields(JsonElement root, Dictionary<string, string> fields)
    {
        if (root.TryGetProperty("metadata", out var meta))
        {
            foreach (var prop in meta.EnumerateObject())
            {
                if (prop.Value.ValueKind == JsonValueKind.String)
                {
                    string val = prop.Value.GetString() ?? "";
                    if (!string.IsNullOrWhiteSpace(val))
                        fields[$"metadata.{prop.Name}"] = val;
                }
            }
        }

        if (root.TryGetProperty("diagrams", out var diagrams) && diagrams.ValueKind == JsonValueKind.Object)
        {
            var mmdTexts = new List<string>();
            foreach (var prop in diagrams.EnumerateObject())
            {
                if (prop.Value.ValueKind == JsonValueKind.String)
                {
                    string mmd = prop.Value.GetString() ?? "";
                    if (!string.IsNullOrWhiteSpace(mmd))
                    {
                        string extracted = ExtractMermaidText(mmd);
                        if (!string.IsNullOrWhiteSpace(extracted))
                            mmdTexts.Add(extracted);
                    }
                }
            }
            if (mmdTexts.Count > 0)
                fields["diagrams"] = string.Join(" ", mmdTexts);
        }
    }

    private static void ExtractCblFields(JsonElement root, Dictionary<string, string> fields)
    {
        fields["sqlTables"] = JoinArrayProp(root, "sqlTables", "table");
        fields["calledSubprograms"] = JoinArrayProp(root, "calledSubprograms", "module");
        fields["copyElements"] = JoinArrayProp(root, "copyElements", "name");
        fields["changeLog"] = JoinArrayProp(root, "changeLog", "comment");
    }

    private static void ExtractSqlFields(JsonElement root, Dictionary<string, string> fields)
    {
        fields["columns"] = JoinArrayProp(root, "columns", "name");
        fields["indexes"] = JoinArrayProp(root, "indexes", "indexName");
        fields["triggers"] = JoinArrayProp(root, "triggers", "triggerName");

        var fkNames = new List<string>();
        foreach (string prop in new[] { "foreignKeysOutgoing", "foreignKeysIncoming" })
        {
            if (root.TryGetProperty(prop, out var arr) && arr.ValueKind == JsonValueKind.Array)
            {
                foreach (var item in arr.EnumerateArray())
                {
                    string refTable = GetString(item, "refTabName");
                    string tabName = GetString(item, "tabName");
                    if (!string.IsNullOrWhiteSpace(refTable)) fkNames.Add(refTable);
                    if (!string.IsNullOrWhiteSpace(tabName)) fkNames.Add(tabName);
                }
            }
        }
        if (fkNames.Count > 0)
            fields["foreignKeys"] = string.Join(" ", fkNames.Distinct());
    }

    private static void ExtractBatFields(JsonElement root, Dictionary<string, string> fields)
    {
        fields["calledScripts"] = JoinArrayProp(root, "calledScripts", "name");
        fields["calledPrograms"] = JoinArrayProp(root, "calledPrograms", "module");
        fields["changeLog"] = JoinArrayProp(root, "changeLog", "comment");
    }

    private static void ExtractPs1Fields(JsonElement root, Dictionary<string, string> fields)
    {
        fields["calledScripts"] = JoinArrayProp(root, "calledScripts", "name");
        fields["calledPrograms"] = JoinArrayProp(root, "calledPrograms", "module");
        fields["changeLog"] = JoinArrayProp(root, "changeLog", "comment");

        if (root.TryGetProperty("functions", out var funcs) && funcs.ValueKind == JsonValueKind.Array)
        {
            var names = new List<string>();
            foreach (var item in funcs.EnumerateArray())
            {
                if (item.ValueKind == JsonValueKind.String)
                    names.Add(item.GetString() ?? "");
            }
            fields["functions"] = string.Join(" ", names.Where(n => !string.IsNullOrWhiteSpace(n)));
        }
    }

    private static void ExtractRexFields(JsonElement root, Dictionary<string, string> fields)
    {
        fields["calledScripts"] = JoinArrayProp(root, "calledScripts", "name");
        fields["calledPrograms"] = JoinArrayProp(root, "calledPrograms", "module");
        fields["changeLog"] = JoinArrayProp(root, "changeLog", "comment");
    }

    private static void ExtractCSharpFields(JsonElement root, Dictionary<string, string> fields)
    {
        fields["sqlTables"] = JoinArrayProp(root, "sqlTables", "table");
        fields["projects"] = JoinArrayProp(root, "projects", "name");
        fields["namespaces"] = JoinArrayProp(root, "namespaces", "name");
        fields["classes"] = JoinArrayProp(root, "classes", "name");
        fields["restEndpoints"] = JoinArrayProp(root, "restEndpoints", "route");
    }

    private static string JoinArrayProp(JsonElement root, string arrayName, string propName)
    {
        if (!root.TryGetProperty(arrayName, out var arr) || arr.ValueKind != JsonValueKind.Array)
            return "";

        var values = new List<string>();
        foreach (var item in arr.EnumerateArray())
        {
            string val = GetString(item, propName);
            if (!string.IsNullOrWhiteSpace(val))
                values.Add(val);
        }
        return string.Join(" ", values.Distinct());
    }

    private static string GetString(JsonElement el, string propName)
    {
        if (el.TryGetProperty(propName, out var val) && val.ValueKind == JsonValueKind.String)
            return val.GetString() ?? "";
        return "";
    }

    /// <summary>
    /// Extracts human-readable node labels from Mermaid diagram source,
    /// stripping syntax, style directives, click handlers, and URLs.
    /// </summary>
    private static string ExtractMermaidText(string mmd)
    {
        var words = new HashSet<string>(StringComparer.OrdinalIgnoreCase);

        foreach (string rawLine in mmd.Split('\n'))
        {
            string line = rawLine.Trim();
            if (string.IsNullOrWhiteSpace(line)) continue;
            if (line.StartsWith("%%{") || line.StartsWith("%%")) continue;
            if (line.StartsWith("flowchart ") || line.StartsWith("sequenceDiagram") ||
                line.StartsWith("erDiagram") || line.StartsWith("graph ")) continue;
            if (line.StartsWith("style ") || line.StartsWith("click ") ||
                line.StartsWith("classDef ")) continue;

            // Extract text inside brackets: [[...]], ["..."], [...], ((...)), {...}, etc.
            // Regex: match text inside node label delimiters
            //   \[\["?  – opening [[ or [["
            //   ([^"\]\}]+) – capture group: content (non-bracket/brace chars)
            //   "?\]\]     – closing "]] or ]]
            //   Also matches [...], (...), {...}
            foreach (Match m in Regex.Matches(line, @"\[\[""?([^""\]\}]+)""?\]\]|\[""?([^""\]]+)""?\]|\(\(""?([^""\)]+)""?\)\)|\{""?([^""\}]+)""?\}"))
            {
                for (int g = 1; g <= 4; g++)
                {
                    if (m.Groups[g].Success)
                    {
                        string text = m.Groups[g].Value
                            .Replace("<br/>", " ")
                            .Replace("<br>", " ")
                            .Replace("\\n", " ");
                        text = Regex.Replace(text, @"<[^>]+>", " ");
                        foreach (string word in text.Split(new[] { ' ', '\t' }, StringSplitOptions.RemoveEmptyEntries))
                        {
                            string clean = word.Trim('|', '"', '\'');
                            if (clean.Length > 1 && !clean.StartsWith("http"))
                                words.Add(clean);
                        }
                    }
                }
            }

            // Also extract link labels: --"text"--> or --|text|--> or --text-->
            foreach (Match m in Regex.Matches(line, @"--""?([^"">|]+)""?-->|--\|([^|]+)\|"))
            {
                for (int g = 1; g <= 2; g++)
                {
                    if (m.Groups[g].Success)
                    {
                        string label = m.Groups[g].Value.Trim();
                        if (label.Length > 1)
                            words.Add(label);
                    }
                }
            }
        }

        return string.Join(" ", words.OrderBy(w => w));
    }
}
