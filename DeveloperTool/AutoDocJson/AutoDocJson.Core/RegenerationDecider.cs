using System;
using System.IO;

namespace AutoDocNew.Core;

/// <summary>
/// Determines whether a source file or SQL table should be regenerated.
/// Simplified from the original per-file git log approach: git change detection
/// is now batch-level via GitChangeDetector. This class handles template checks,
/// output existence, and pre-generation verification for distributed safety.
/// </summary>
public static class RegenerationDecider
{
    /// <summary>
    /// Check if any template file has been modified since <paramref name="sinceUtc"/>.
    /// If so, all files of that type should be regenerated.
    /// </summary>
    public static bool HasTemplateChanged(string templateName, DateTime sinceUtc)
    {
        string templateDir = Path.Combine(PathHelper.GetAutodocSharedFolder(), "_templates");
        if (!Directory.Exists(templateDir))
            return false;

        string templatePath = Path.Combine(templateDir, templateName);
        if (!File.Exists(templatePath))
            return false;

        return File.GetLastWriteTimeUtc(templatePath) > sinceUtc;
    }

    /// <summary>
    /// Should the given SQL table be regenerated based on ALTER_TIME comparison?
    /// Used for Incremental mode. All/Clean always return true.
    /// </summary>
    public static bool ShouldRegenerateSqlTable(string schemaName, string tableName, string alterTime,
        DateTime previousStartedAtUtc, string regenerate, string outputFolder)
    {
        string tableNameFile = (schemaName.Trim().ToUpper() + "_" + tableName.Trim().ToUpper())
            .Replace("\u00C6", "AE").Replace("\u00D8", "OE").Replace("\u00C5", "AA").ToLower();

        // Template check
        if (HasTemplateChanged("sqlmmdtemplate.html", previousStartedAtUtc))
            return true;

        // Missing output → regenerate
        string jsonPath = Path.Combine(outputFolder, tableNameFile + ".sql.json");
        if (!File.Exists(jsonPath))
            return true;

        // All/Clean always regenerate
        if (regenerate is "All" or "Clean")
            return true;

        // Errors mode
        if (string.Equals(regenerate, "Errors", StringComparison.OrdinalIgnoreCase))
        {
            string errPath = Path.Combine(outputFolder, tableNameFile + ".sql.err");
            return File.Exists(errPath);
        }

        // Incremental: compare ALTER_TIME with JSON file date
        try
        {
            int alterTimeInt = int.Parse(alterTime.Substring(0, 10).Replace("-", ""));
            int jsonDate = int.Parse(File.GetLastWriteTime(jsonPath).ToString("yyyyMMdd"));
            return jsonDate < alterTimeInt;
        }
        catch
        {
            return true;
        }
    }

    /// <summary>
    /// Pre-generation verification for distributed safety.
    /// Returns true if the output has already been regenerated after the current batch started
    /// (another process already handled it).
    /// </summary>
    public static bool IsOutputAlreadyFresh(string outputFolder, string outputFileName, DateTime batchStartedAtUtc)
    {
        string outputJson = Path.Combine(outputFolder, outputFileName + ".json");
        if (!File.Exists(outputJson))
            return false;

        return File.GetLastWriteTimeUtc(outputJson) > batchStartedAtUtc;
    }

    /// <summary>
    /// Check if the output file for a source file is missing (needs generation regardless of mode).
    /// </summary>
    public static bool IsOutputMissing(string outputFolder, string sourceFileName)
    {
        string jsonPath = Path.Combine(outputFolder, sourceFileName + ".json");
        return !File.Exists(jsonPath);
    }

    /// <summary>Map file extension to template name. Returns null if no template.</summary>
    public static string? GetTemplateName(string fileName)
    {
        string lower = fileName.ToLowerInvariant();
        if (lower.EndsWith(".cbl")) return "cblmmdtemplate.html";
        if (lower.EndsWith(".ps1")) return "ps1mmdtemplate.html";
        if (lower.EndsWith(".rex")) return "rexmmdtemplate.html";
        if (lower.EndsWith(".bat")) return "batmmdtemplate.html";
        return null;
    }
}
