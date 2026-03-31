namespace SystemAnalyzer.Core.Services;

public sealed class JsonDataService
{
    private static readonly HashSet<string> AllowedFiles = new(StringComparer.OrdinalIgnoreCase)
    {
        "all.json",
        "dependency_master.json",
        "all_total_programs.json",
        "all_call_graph.json",
        "all_sql_tables.json",
        "all_file_io.json",
        "all_copy_elements.json",
        "source_verification.json",
        "db2_table_validation.json",
        "applied_exclusions.json",
        "standard_cobol_filtered.json",
        "business_areas.json",
        "run_summary.md"
    };

    public string ReadAnalysisFile(string dataRoot, string alias, string fileName)
    {
        if (!AllowedFiles.Contains(fileName))
        {
            throw new InvalidOperationException($"File is not exposed by API: {fileName}");
        }

        var aliasSafe = SanitizeAlias(alias);
        var fullPath = Path.Combine(dataRoot, aliasSafe, fileName);
        if (File.Exists(fullPath))
        {
            return File.ReadAllText(fullPath);
        }

        var runFolder = FindLatestRunFolder(dataRoot, aliasSafe);
        if (runFolder != null)
        {
            var runPath = Path.Combine(runFolder, fileName);
            if (File.Exists(runPath))
            {
                return File.ReadAllText(runPath);
            }
        }

        throw new FileNotFoundException("Data file not found", fullPath);
    }

    private static string? FindLatestRunFolder(string dataRoot, string alias)
    {
        var historyDir = Path.Combine(dataRoot, alias, "_History");
        if (!Directory.Exists(historyDir)) return null;

        return Directory.GetDirectories(historyDir, $"{alias}_*")
            .OrderByDescending(d => d)
            .FirstOrDefault();
    }

    public string ResolveAliasPath(string dataRoot, string alias)
    {
        var aliasSafe = SanitizeAlias(alias);
        return Path.Combine(dataRoot, aliasSafe);
    }

    public static string SanitizeAlias(string alias)
    {
        if (string.IsNullOrWhiteSpace(alias))
        {
            return string.Empty;
        }

        var filtered = alias
            .Select(ch => char.IsLetterOrDigit(ch) || ch == '_' || ch == '-' ? ch : '_')
            .ToArray();
        return new string(filtered).Trim('_');
    }
}
