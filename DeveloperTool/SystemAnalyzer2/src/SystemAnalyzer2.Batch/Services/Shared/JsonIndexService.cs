using System;
using System.Collections.Generic;
using System.IO;
using System.Linq;
using System.Text;
using System.Text.Json;

namespace SystemAnalyzer2.Batch.Services.Shared;

/// <summary>
/// Creates/updates _json index files from generated HTML and cobdok CSVs.
/// Converted from CreateAllJsonIndexFiles in AutoDocBatchRunner.ps1 (lines 570-860).
/// </summary>
public static class JsonIndexService
{
    /// <summary>Update all JSON index files in outputFolder\_json.</summary>
    public static void UpdateAll(string outputFolder, string cobdokFolder, string serverMonitorFolder)
    {
        string jsonFolder = Path.Combine(outputFolder, "_json");
        if (!Directory.Exists(jsonFolder))
            Directory.CreateDirectory(jsonFolder);

        AutoDocLogger.LogMessage(new string('-', 75), LogLevel.INFO);
        AutoDocLogger.LogMessage("Generating JSON index files from output folder", LogLevel.INFO);
        AutoDocLogger.LogMessage($"Output folder: {outputFolder}", LogLevel.INFO);
        AutoDocLogger.LogMessage(new string('-', 75), LogLevel.INFO);

        UpdateCbl(outputFolder, cobdokFolder, Path.Combine(jsonFolder, "CblParseResult.json"));
        UpdateScriptType(outputFolder, Path.Combine(jsonFolder, "BatParseResult.json"), "bat", "Windows Batch Script");
        UpdateScriptType(outputFolder, Path.Combine(jsonFolder, "Ps1ParseResult.json"), "ps1", "Powershell Script");
        UpdateScriptType(outputFolder, Path.Combine(jsonFolder, "Psm1ParseResult.json"), "psm1", "Powershell Module");
        UpdateScriptType(outputFolder, Path.Combine(jsonFolder, "RexParseResult.json"), "rex", "Object Rexx Script");
        UpdateSql(outputFolder, cobdokFolder, Path.Combine(jsonFolder, "SqlParseResult.json"));
        UpdateCSharp(outputFolder, Path.Combine(jsonFolder, "CSharpParseResult.json"), serverMonitorFolder);

        SearchIndexBuilder.Build(outputFolder);

        int totalFiles = Directory.EnumerateFiles(jsonFolder, "*.json").Count();
        AutoDocLogger.LogMessage(new string('-', 75), LogLevel.INFO);
        AutoDocLogger.LogMessage($"JSON index generation complete - {totalFiles} JSON files in {jsonFolder}", LogLevel.INFO);
        AutoDocLogger.LogMessage(new string('-', 75), LogLevel.INFO);
    }

    // ── CBL ──────────────────────────────────────────────────────────────────
    private static void UpdateCbl(string outputFolder, string cobdokFolder, string jsonPath)
    {
        var entries = new List<object>();
        if (!Directory.Exists(outputFolder)) { WriteJson(jsonPath, entries); return; }

        // Load modul.csv for enrichment
        var modulLookup = LoadModulCsv(Path.Combine(cobdokFolder, "modul.csv"));

        foreach (string htmlFile in Directory.EnumerateFiles(outputFolder, "*.cbl.html").OrderBy(f => f))
        {
            string fileName = Path.GetFileName(htmlFile).ToLowerInvariant();
            string baseName = fileName.Replace(".cbl.html", "").ToUpper();
            string errPath = Path.Combine(outputFolder, baseName.ToLower() + ".cbl.err");
            if (File.Exists(errPath)) continue;

            string link = $"<a href=\"./{fileName.Trim()}\" target=\"_blank\">{baseName}.cbl</a><br>";
            string system = "", desc = "", type = "";
            if (modulLookup.TryGetValue(baseName, out var m))
            {
                system = m.system; desc = m.description; type = m.type;
            }
            entries.Add(new { programName = baseName.ToLower() + ".cbl", programNameLink = link, description = desc, system, type });
        }
        WriteJson(jsonPath, entries);
        AutoDocLogger.LogMessage($"CblParseResult.json: {entries.Count} entries", LogLevel.INFO);
    }

    // ── Script types (BAT, PS1, PSM1, REX) ──────────────────────────────────
    private static void UpdateScriptType(string outputFolder, string jsonPath, string extension, string typeName)
    {
        var entries = new List<object>();
        if (!Directory.Exists(outputFolder)) { WriteJson(jsonPath, entries); return; }

        string pattern = $"*.{extension}.html";
        foreach (string htmlFile in Directory.EnumerateFiles(outputFolder, pattern).OrderBy(f => f))
        {
            string fileName = Path.GetFileName(htmlFile);
            string errPath = Path.Combine(outputFolder, fileName.Replace(".html", ".err"));
            if (File.Exists(errPath)) continue;

            string baseName = fileName.Replace(".html", "").ToUpper();
            string link = $"<a href=\"./{fileName.ToLower().Trim()}\" target=\"_blank\">{baseName}</a><br>";
            entries.Add(new { scriptNameLink = link, type = typeName });
        }
        WriteJson(jsonPath, entries);
        AutoDocLogger.LogMessage($"{Path.GetFileName(jsonPath)}: {entries.Count} entries", LogLevel.INFO);
    }

    // ── SQL ──────────────────────────────────────────────────────────────────
    private static void UpdateSql(string outputFolder, string cobdokFolder, string jsonPath)
    {
        var entries = new List<object>();
        if (!Directory.Exists(outputFolder)) { WriteJson(jsonPath, entries); return; }

        // Load tables.csv lookup
        var tableLookup = LoadTablesCsv(Path.Combine(cobdokFolder, "tables.csv"));

        foreach (string htmlFile in Directory.EnumerateFiles(outputFolder, "*.sql.html").OrderBy(f => f))
        {
            string fileName = Path.GetFileName(htmlFile);
            string baseName = fileName.Replace(".sql.html", "").ToUpper();

            string tableDisplayName = "";
            string desc = "";
            string sqlType = "Sql table";

            // Try to match cobdok entry
            bool matched = false;
            foreach (var kvp in tableLookup)
            {
                string expected = kvp.Key.Replace(".", "_").ToUpper()
                    .Replace("\u00C6", "AE").Replace("\u00D8", "OE").Replace("\u00C5", "AA");
                if (expected == baseName)
                {
                    tableDisplayName = kvp.Key;
                    desc = kvp.Value.comment;
                    if (kvp.Value.tableType.Contains("V")) sqlType = "Sql view";
                    matched = true;
                    break;
                }
            }
            if (!matched)
            {
                int underscorePos = baseName.IndexOf('_');
                tableDisplayName = underscorePos > 0
                    ? baseName.Substring(0, underscorePos) + "." + baseName.Substring(underscorePos + 1)
                    : baseName;
            }

            string link = $"<a href=\"./{fileName.ToLower().Trim()}\" target=\"_blank\">{tableDisplayName}</a>";
            entries.Add(new { tableNameLink = link, description = desc, type = sqlType });
        }
        WriteJson(jsonPath, entries);
        AutoDocLogger.LogMessage($"SqlParseResult.json: {entries.Count} entries", LogLevel.INFO);
    }

    // ── CSharp ──────────────────────────────────────────────────────────────
    private static void UpdateCSharp(string outputFolder, string jsonPath, string serverMonitorFolder)
    {
        var entries = new List<object>();
        if (!Directory.Exists(outputFolder)) { WriteJson(jsonPath, entries); return; }

        foreach (string htmlFile in Directory.EnumerateFiles(outputFolder, "*.csharp.html").OrderBy(f => f))
        {
            string fileName = Path.GetFileName(htmlFile);
            string baseName = fileName.Replace(".csharp.html", "");
            string link = $"<a href=\"./{fileName.ToLower().Trim()}\" target=\"_blank\">{baseName}</a><br>";
            string projectType = baseName.ToLower().EndsWith(".ecosystem") ? "C# Ecosystem" : "C# Solution";
            string description = baseName.ToLower().EndsWith(".ecosystem") ? "Multi-project ecosystem diagram" : "";

            entries.Add(new { projectName = baseName, projectNameLink = link, description, type = projectType });
        }
        WriteJson(jsonPath, entries);
        AutoDocLogger.LogMessage($"CSharpParseResult.json: {entries.Count} entries", LogLevel.INFO);
    }

    // ── Helpers ──────────────────────────────────────────────────────────────
    private static void WriteJson(string path, List<object> entries)
    {
        string json = JsonSerializer.Serialize(entries, new JsonSerializerOptions { WriteIndented = true });
        File.WriteAllText(path, json, Encoding.UTF8);
    }

    private static Dictionary<string, (string system, string description, string type)> LoadModulCsv(string path)
    {
        var dict = new Dictionary<string, (string, string, string)>(StringComparer.OrdinalIgnoreCase);
        if (!File.Exists(path)) return dict;
        try
        {
            foreach (string line in File.ReadLines(path))
            {
                string[] p = line.Split(';');
                if (p.Length >= 5)
                {
                    string modul = p[2].Trim().ToUpper();
                    if (!string.IsNullOrEmpty(modul))
                        dict[modul] = (p[1].Trim(), p[3].Trim(), p[4].Trim());
                }
            }
            AutoDocLogger.LogMessage($"Loaded modul.csv with {dict.Count} entries for CBL enrichment", LogLevel.INFO);
        }
        catch (Exception ex)
        {
            AutoDocLogger.LogMessage($"Warning: Could not load modul.csv - {ex.Message}", LogLevel.WARN);
        }
        return dict;
    }

    private static Dictionary<string, (string comment, string tableType)> LoadTablesCsv(string path)
    {
        var dict = new Dictionary<string, (string, string)>(StringComparer.OrdinalIgnoreCase);
        if (!File.Exists(path)) return dict;
        try
        {
            foreach (string line in File.ReadLines(path))
            {
                string[] p = line.Split(';');
                if (p.Length >= 4)
                {
                    string key = p[0].Trim().ToUpper() + "." + p[1].Trim().ToUpper();
                    dict[key] = (p[2].Trim(), p[3].Trim());
                }
            }
            AutoDocLogger.LogMessage($"Loaded tables.csv with {dict.Count} entries for SQL enrichment", LogLevel.INFO);
        }
        catch (Exception ex)
        {
            AutoDocLogger.LogMessage($"Warning: Could not load tables.csv - {ex.Message}", LogLevel.WARN);
        }
        return dict;
    }
}
