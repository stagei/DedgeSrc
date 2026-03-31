using System.Text.Json;
using AutoDocNew.Models;
using Microsoft.AspNetCore.Mvc;
using Microsoft.AspNetCore.Mvc.RazorPages;

namespace AutoDocNew.Web.Pages;

public class DocModel : PageModel
{
    private readonly IConfiguration _config;
    private static readonly JsonSerializerOptions JsonOpts = new()
    {
        PropertyNamingPolicy = JsonNamingPolicy.CamelCase,
        PropertyNameCaseInsensitive = true
    };

    public DocModel(IConfiguration config) => _config = config;

    public string FileType { get; set; } = "";
    public string DocTitle { get; set; } = "";
    public DocFileResult? DocBase { get; set; }
    public CblResult? Cbl { get; set; }
    public BatResult? Bat { get; set; }
    public Ps1Result? Ps1 { get; set; }
    public RexResult? Rex { get; set; }
    public SqlResult? Sql { get; set; }
    public CSharpResult? CSharp { get; set; }
    public string ErrorMessage { get; set; } = "";

    public IActionResult OnGet(string? file)
    {
        if (string.IsNullOrEmpty(file))
        {
            ErrorMessage = "No file specified.";
            return Page();
        }

        // Sanitize: only allow filename chars
        string safeFile = Path.GetFileName(file);
        if (!safeFile.EndsWith(".json", StringComparison.OrdinalIgnoreCase))
        {
            ErrorMessage = "Invalid file type.";
            return Page();
        }

        string outputFolder = _config.GetValue<string>("AutoDocJson:OutputFolder")
            ?? Path.Combine(Environment.GetEnvironmentVariable("OptPath") ?? "C:\\opt", "Webs", "AutoDocJson");
        string jsonPath = Path.Combine(outputFolder, safeFile);

        if (!System.IO.File.Exists(jsonPath))
        {
            ErrorMessage = $"File not found: {safeFile}";
            return Page();
        }

        try
        {
            string json = System.IO.File.ReadAllText(jsonPath);
            DocBase = JsonSerializer.Deserialize<DocFileResult>(json, JsonOpts);
            if (DocBase == null)
            {
                ErrorMessage = "Failed to parse JSON.";
                return Page();
            }

            FileType = DocBase.Type;
            DocTitle = DocBase.Title;

            switch (DocBase.Type)
            {
                case "CBL":
                    Cbl = JsonSerializer.Deserialize<CblResult>(json, JsonOpts);
                    break;
                case "BAT":
                    Bat = JsonSerializer.Deserialize<BatResult>(json, JsonOpts);
                    break;
                case "PS1":
                    Ps1 = JsonSerializer.Deserialize<Ps1Result>(json, JsonOpts);
                    break;
                case "REX":
                    Rex = JsonSerializer.Deserialize<RexResult>(json, JsonOpts);
                    break;
                case "SQL":
                    Sql = JsonSerializer.Deserialize<SqlResult>(json, JsonOpts);
                    if (Sql != null)
                    {
                        PopulateSqlUsageFromCache(Sql, outputFolder);
                        Sql.ErDiagramMmd = SanitizeErDiagram(Sql.ErDiagramMmd);
                    }
                    break;
                case "CSharp":
                    CSharp = JsonSerializer.Deserialize<CSharpResult>(json, JsonOpts);
                    break;
                default:
                    ErrorMessage = $"Unknown file type: {DocBase.Type}";
                    break;
            }
        }
        catch (Exception ex)
        {
            ErrorMessage = $"Error loading file: {ex.Message}";
        }

        return Page();
    }

    private static void PopulateSqlUsageFromCache(SqlResult sql, string outputFolder)
    {
        if (sql.UsedBy?.Count > 0) return;

        string interactionsPath = Path.Combine(outputFolder, "_json", "_sql_interactions.json");
        if (!System.IO.File.Exists(interactionsPath)) return;

        try
        {
            string interactionsJson = System.IO.File.ReadAllText(interactionsPath);
            var tableKeys = new List<string>();
            if (!string.IsNullOrWhiteSpace(sql.Metadata?.FullName))
                tableKeys.Add(sql.Metadata.FullName.ToLowerInvariant());
            if (!string.IsNullOrWhiteSpace(sql.Metadata?.Schema) && !string.IsNullOrWhiteSpace(sql.Metadata?.TableName))
                tableKeys.Add($"{sql.Metadata.Schema}.{sql.Metadata.TableName}".ToLowerInvariant());
            if (!string.IsNullOrWhiteSpace(sql.FileName))
                tableKeys.Add(sql.FileName.ToLowerInvariant());

            List<SqlUsageDef>? usedByList = null;

            using var doc = JsonDocument.Parse(interactionsJson);
            foreach (var key in tableKeys.Distinct())
            {
                if (!doc.RootElement.TryGetProperty(key, out var tableElement)) continue;
                if (tableElement.ValueKind != JsonValueKind.Array || tableElement.GetArrayLength() == 0) continue;

                var first = tableElement[0];
                if (first.ValueKind == JsonValueKind.Object)
                {
                    usedByList = tableElement.EnumerateArray().Select(e => new SqlUsageDef
                    {
                        ProgramName = e.TryGetProperty("programName", out var pn) ? pn.GetString() ?? "" :
                                      e.TryGetProperty("ProgramName", out var pn2) ? pn2.GetString() ?? "" : "",
                        FileType = e.TryGetProperty("fileType", out var ft) ? ft.GetString() ?? "" :
                                   e.TryGetProperty("FileType", out var ft2) ? ft2.GetString() ?? "" : "",
                        FilePath = e.TryGetProperty("filePath", out var fp) ? fp.GetString() ?? "" :
                                   e.TryGetProperty("FilePath", out var fp2) ? fp2.GetString() ?? "" : "",
                        Description = e.TryGetProperty("description", out var d) ? d.GetString() ?? "" :
                                      e.TryGetProperty("Description", out var d2) ? d2.GetString() ?? "" : "",
                        GeneratedAt = e.TryGetProperty("generatedAt", out var g) ? g.GetString() ?? "" :
                                      e.TryGetProperty("GeneratedAt", out var g2) ? g2.GetString() ?? "" : ""
                    }).ToList();
                    break;
                }
                else if (first.ValueKind == JsonValueKind.String)
                {
                    usedByList = tableElement.EnumerateArray()
                        .Select(e => e.GetString() ?? "")
                        .Where(s => !string.IsNullOrEmpty(s))
                        .Distinct(StringComparer.OrdinalIgnoreCase)
                        .Select(p => new SqlUsageDef
                        {
                            ProgramName = TrimProgramName(p),
                            FileType = InferFileType(p),
                            FilePath = p.EndsWith(".json", StringComparison.OrdinalIgnoreCase) ? p : p + ".json"
                        }).ToList();
                    break;
                }
            }

            if (usedByList == null || usedByList.Count == 0)
            {
                var programs = FindProgramsUsingTableFromHtml(outputFolder, tableKeys);
                if (programs.Count == 0) return;
                usedByList = programs.Distinct(StringComparer.OrdinalIgnoreCase)
                    .Select(p => new SqlUsageDef
                    {
                        ProgramName = TrimProgramName(p),
                        FileType = InferFileType(p),
                        FilePath = p.EndsWith(".json", StringComparison.OrdinalIgnoreCase) ? p : p + ".json"
                    }).ToList();
            }

            sql.UsedBy = usedByList.OrderBy(x => x.ProgramName).ToList();

            if (string.IsNullOrWhiteSpace(sql.InteractionDiagramMmd) && sql.UsedBy.Count > 0)
            {
                string nodeId = (sql.Metadata?.FullName ?? "sql_table").Replace(".", "_").ToLowerInvariant();
                var lines = new List<string> { "flowchart TD", $"    sql_{nodeId}[({(sql.Metadata?.FullName ?? "SQL_TABLE").ToUpperInvariant()})]" };
                foreach (var usage in sql.UsedBy.Take(100))
                {
                    string safe = new string(usage.ProgramName.Select(ch => char.IsLetterOrDigit(ch) ? ch : '_').ToArray());
                    lines.Add($"    p_{safe}[\"{usage.ProgramName}\"]");
                    lines.Add($"    p_{safe} -->|\"REFERENCES\"| sql_{nodeId}");
                }
                sql.InteractionDiagramMmd = string.Join("\n", lines);
            }
        }
        catch
        {
            // Keep page rendering resilient; fallback should never break document view.
        }
    }

    private static List<string> FindProgramsUsingTableFromHtml(string outputFolder, IEnumerable<string> tableKeys)
    {
        if (!Directory.Exists(outputFolder)) return new List<string>();

        var normalizedKeys = tableKeys
            .Where(k => !string.IsNullOrWhiteSpace(k))
            .Select(k => k.ToUpperInvariant())
            .Distinct()
            .ToList();
        if (normalizedKeys.Count == 0) return new List<string>();

        var programs = new HashSet<string>(StringComparer.OrdinalIgnoreCase);
        foreach (var htmlFile in Directory.EnumerateFiles(outputFolder, "*.html", SearchOption.TopDirectoryOnly)
                     .Where(f => !f.EndsWith(".sql.html", StringComparison.OrdinalIgnoreCase)))
        {
            try
            {
                string content = System.IO.File.ReadAllText(htmlFile).ToUpperInvariant();
                if (normalizedKeys.Any(k => content.Contains(k)))
                    programs.Add(Path.GetFileName(htmlFile));
            }
            catch
            {
                // Ignore malformed/unreadable files in fallback scan.
            }
        }

        return programs.OrderBy(x => x).ToList();
    }

    private static string TrimProgramName(string value)
    {
        foreach (var ext in new[] { ".cbl.html", ".bat.html", ".ps1.html", ".psm1.html", ".rex.html", ".csharp.html", ".sql.html", ".screen.html", ".gs.html", ".html" })
        {
            if (value.EndsWith(ext, StringComparison.OrdinalIgnoreCase))
                return value[..^ext.Length];
        }
        return value;
    }

    private static string InferFileType(string value)
    {
        if (value.EndsWith(".cbl.html", StringComparison.OrdinalIgnoreCase) || value.EndsWith(".cbl", StringComparison.OrdinalIgnoreCase)) return "COBOL";
        if (value.EndsWith(".bat.html", StringComparison.OrdinalIgnoreCase) || value.EndsWith(".bat", StringComparison.OrdinalIgnoreCase)) return "Batch";
        if (value.EndsWith(".ps1.html", StringComparison.OrdinalIgnoreCase) || value.EndsWith(".ps1", StringComparison.OrdinalIgnoreCase) || value.EndsWith(".psm1.html", StringComparison.OrdinalIgnoreCase)) return "PowerShell";
        if (value.EndsWith(".rex.html", StringComparison.OrdinalIgnoreCase) || value.EndsWith(".rex", StringComparison.OrdinalIgnoreCase)) return "REXX";
        if (value.EndsWith(".csharp.html", StringComparison.OrdinalIgnoreCase)) return "CSharp";
        if (value.EndsWith(".sql.html", StringComparison.OrdinalIgnoreCase)) return "SQL";
        return "";
    }

    /// <summary>
    /// Mermaid ER diagrams fail hard on some identifier characters (for example Ø in column names).
    /// Sanitize attribute identifiers at render-time so older JSON files still render without regeneration.
    /// </summary>
    private static string SanitizeErDiagram(string? mmd)
    {
        if (string.IsNullOrWhiteSpace(mmd)) return mmd ?? "";

        var lines = mmd.Split('\n');
        var output = new List<string>(lines.Length);
        bool insideEntity = false;

        foreach (var rawLine in lines)
        {
            var line = rawLine;
            var trimmed = line.Trim();

            if (trimmed.EndsWith("{", StringComparison.Ordinal))
            {
                insideEntity = true;
                output.Add(line);
                continue;
            }
            if (trimmed == "}")
            {
                insideEntity = false;
                output.Add(line);
                continue;
            }
            if (!insideEntity || trimmed.Length == 0 || trimmed.Contains("}o--", StringComparison.Ordinal))
            {
                output.Add(line);
                continue;
            }

            // Attribute lines: "<indent><type> <name> [\"PK,FK\"]"
            var match = System.Text.RegularExpressions.Regex.Match(
                line,
                @"^(\s*)([A-Za-z0-9_]+)\s+([^\s""]+)(\s+"".*"")?\s*$");
            if (!match.Success)
            {
                output.Add(line);
                continue;
            }

            string indent = match.Groups[1].Value;
            string type = match.Groups[2].Value;
            string name = match.Groups[3].Value;
            string marker = match.Groups[4].Value;

            var safeName = name
                .Replace("Æ", "AE", StringComparison.OrdinalIgnoreCase)
                .Replace("Ø", "OE", StringComparison.OrdinalIgnoreCase)
                .Replace("Å", "AA", StringComparison.OrdinalIgnoreCase);
            safeName = System.Text.RegularExpressions.Regex.Replace(safeName, @"[^A-Za-z0-9_]", "_");
            if (safeName.Length == 0) safeName = "COL";
            if (char.IsDigit(safeName[0])) safeName = "C_" + safeName;

            output.Add($"{indent}{type} {safeName}{marker}");
        }

        return string.Join("\n", output);
    }
}
