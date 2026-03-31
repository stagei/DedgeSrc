using System;
using System.Collections.Generic;
using System.IO;
using System.Linq;
using System.Text;
using System.Text.Json;
using System.Text.RegularExpressions;

namespace SystemAnalyzer2.Batch.Services.Shared;

/// <summary>
/// Scans generated JSON files for SQL table references and builds an enriched interaction map.
/// Full-text searches each JSON file for schema.table patterns, then extracts file metadata.
/// </summary>
public static class SqlInteractionsScanner
{
    private static readonly Regex TableRefRegex = new(
        @"(DBM|HST|CRM|LOG|TV)\.([A-Z0-9_]+)",
        RegexOptions.Compiled | RegexOptions.IgnoreCase);

    private static readonly JsonSerializerOptions JsonOpts = new()
    {
        PropertyNameCaseInsensitive = true,
        WriteIndented = true
    };

    /// <summary>
    /// Scan all non-SQL JSON files in outputFolder for SQL table references.
    /// Reads each file as raw text, regex-matches table patterns, then extracts metadata.
    /// Writes enriched _json/_sql_interactions.json.
    /// Filters matches against tables.csv to eliminate false positives.
    /// Returns both the interactions map and an alter_time lookup for skip decisions.
    /// </summary>
    public static (Dictionary<string, List<InteractionEntry>> interactions, Dictionary<string, string> alterTimes)
        Scan(string outputFolder, string cobdokFolder)
    {
        var interactions = new Dictionary<string, List<InteractionEntry>>(StringComparer.OrdinalIgnoreCase);
        var alterTimes = new Dictionary<string, string>(StringComparer.OrdinalIgnoreCase);

        if (!Directory.Exists(outputFolder))
            return (interactions, alterTimes);

        var validTables = LoadValidTables(cobdokFolder, alterTimes);
        int unfilteredCount = 0;

        var jsonFiles = Directory.EnumerateFiles(outputFolder, "*.json", SearchOption.TopDirectoryOnly)
            .Where(f =>
            {
                string name = Path.GetFileName(f);
                return !name.EndsWith(".sql.json", StringComparison.OrdinalIgnoreCase)
                    && !name.Equals("search-index.json", StringComparison.OrdinalIgnoreCase);
            });

        foreach (string jsonFile in jsonFiles)
        {
            try
            {
                string content = File.ReadAllText(jsonFile);
                var matches = TableRefRegex.Matches(content);
                if (matches.Count == 0) continue;

                var seen = new HashSet<string>(StringComparer.OrdinalIgnoreCase);
                var tableRefs = new List<string>();
                foreach (Match match in matches)
                {
                    string tableRef = match.Value.ToLower();
                    unfilteredCount++;
                    if (!seen.Add(tableRef)) continue;
                    if (!validTables.Contains(tableRef)) continue;
                    tableRefs.Add(tableRef);
                }

                if (tableRefs.Count == 0) continue;

                var meta = ExtractMetadata(content, jsonFile);

                foreach (string tableRef in tableRefs)
                {
                    if (!interactions.TryGetValue(tableRef, out var list))
                    {
                        list = new List<InteractionEntry>();
                        interactions[tableRef] = list;
                    }
                    string jsonFileName = Path.GetFileName(jsonFile);
                    string lastChanged = "";
                    try { lastChanged = File.GetLastWriteTimeUtc(jsonFile).ToString("O"); }
                    catch { }

                    list.Add(new InteractionEntry
                    {
                        ProgramName = meta.ProgramName,
                        FileType = meta.FileType,
                        Description = meta.Description,
                        GeneratedAt = meta.GeneratedAt,
                        FilePath = jsonFileName,
                        LastChanged = lastChanged
                    });
                }
            }
            catch (Exception ex)
            {
                AutoDocLogger.LogMessage($"Error scanning {jsonFile}: {ex.Message}", LogLevel.WARN, ex);
            }
        }

        int filteredOut = unfilteredCount - interactions.Values.Sum(l => l.Count);
        if (filteredOut > 0)
            AutoDocLogger.LogMessage($"Filtered out {filteredOut} false-positive table references not in tables.csv", LogLevel.INFO);

        string cachePath = Path.Combine(outputFolder, "_json", "_sql_interactions.json");
        try
        {
            string dir = Path.GetDirectoryName(cachePath)!;
            if (!Directory.Exists(dir)) Directory.CreateDirectory(dir);
            string json = JsonSerializer.Serialize(interactions, JsonOpts);
            File.WriteAllText(cachePath, json);
        }
        catch (Exception ex)
        {
            AutoDocLogger.LogMessage($"Error writing SQL interactions JSON: {ex.Message}", LogLevel.WARN, ex);
        }

        AutoDocLogger.LogMessage($"Found SQL interactions for {interactions.Count} tables from JSON files (validated against tables.csv)", LogLevel.INFO);
        return (interactions, alterTimes);
    }

    /// <summary>
    /// Determine which SQL tables need interaction diagram updates based on
    /// which files were regenerated in the current batch.
    /// Returns only the table refs whose interacting files were regenerated.
    /// </summary>
    public static HashSet<string> FilterTablesWithChangedInteractions(
        Dictionary<string, List<InteractionEntry>> interactions,
        HashSet<string> regeneratedOutputFiles)
    {
        var tablesToUpdate = new HashSet<string>(StringComparer.OrdinalIgnoreCase);

        foreach (var (tableRef, entries) in interactions)
        {
            bool hasChanged = entries.Any(e =>
                regeneratedOutputFiles.Contains(e.FilePath, StringComparer.OrdinalIgnoreCase));

            if (hasChanged)
                tablesToUpdate.Add(tableRef);
        }

        AutoDocLogger.LogMessage(
            $"SQL interaction filter: {tablesToUpdate.Count}/{interactions.Count} tables have changed interacting files",
            LogLevel.INFO);

        return tablesToUpdate;
    }

    /// <summary>
    /// Loads valid table names from tables.csv and populates the alter_time lookup.
    /// </summary>
    private static HashSet<string> LoadValidTables(string cobdokFolder, Dictionary<string, string> alterTimes)
    {
        var valid = new HashSet<string>(StringComparer.OrdinalIgnoreCase);
        string tablesCsv = Path.Combine(cobdokFolder, "tables.csv");
        if (!File.Exists(tablesCsv))
        {
            AutoDocLogger.LogMessage($"tables.csv not found at {tablesCsv}, skipping validation filter", LogLevel.WARN);
            return valid;
        }

        try
        {
            foreach (string line in File.ReadLines(tablesCsv, Encoding.UTF8))
            {
                if (string.IsNullOrWhiteSpace(line)) continue;
                string[] parts = line.Split(';');
                if (parts.Length < 5) continue;
                string schema = parts[0].Trim().Trim('"');
                string table = parts[1].Trim().Trim('"');
                string alterTime = parts[4].Trim().Trim('"');
                if (string.IsNullOrEmpty(schema) || string.IsNullOrEmpty(table)) continue;

                string key = $"{schema}.{table}".ToLower();
                valid.Add(key);
                alterTimes[key] = alterTime;
            }
        }
        catch (Exception ex)
        {
            AutoDocLogger.LogMessage($"Error loading tables.csv: {ex.Message}", LogLevel.WARN, ex);
        }

        AutoDocLogger.LogMessage($"Loaded {valid.Count} valid table names from tables.csv for interaction filtering", LogLevel.INFO);
        return valid;
    }

    private static FileMeta ExtractMetadata(string jsonContent, string filePath)
    {
        var meta = new FileMeta { ProgramName = Path.GetFileName(filePath) };
        try
        {
            using var doc = JsonDocument.Parse(jsonContent);
            var root = doc.RootElement;

            if (root.TryGetProperty("fileName", out var fn))
                meta.ProgramName = fn.GetString() ?? meta.ProgramName;
            if (root.TryGetProperty("type", out var tp))
                meta.FileType = tp.GetString() ?? "";
            if (root.TryGetProperty("description", out var desc))
                meta.Description = desc.GetString() ?? "";
            if (root.TryGetProperty("generatedAt", out var gen))
                meta.GeneratedAt = gen.GetString() ?? "";
        }
        catch { }
        return meta;
    }

    private struct FileMeta
    {
        public string ProgramName;
        public string FileType;
        public string Description;
        public string GeneratedAt;
    }
}

public class InteractionEntry
{
    public string ProgramName { get; set; } = "";
    public string FileType { get; set; } = "";
    public string Description { get; set; } = "";
    public string GeneratedAt { get; set; } = "";
    public string FilePath { get; set; } = "";

    /// <summary>
    /// ISO 8601 UTC timestamp of when the interacting file's JSON was last written.
    /// Used to determine if SQL interaction diagrams need refreshing.
    /// </summary>
    public string LastChanged { get; set; } = "";
}
