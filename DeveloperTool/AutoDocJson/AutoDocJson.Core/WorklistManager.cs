using System;
using System.Collections.Generic;
using System.IO;
using System.Linq;
using System.Text.Encodings.Web;
using System.Text.Json;
using System.Text.Json.Serialization;
using System.Text.RegularExpressions;

namespace AutoDocNew.Core;

/// <summary>
/// Manages the _regenerate_worklist folder: creates worklist files from detected changes,
/// reads them with exclusive locking, and deletes after claiming.
/// Supports distributed processing via UNC paths.
/// </summary>
public static class WorklistManager
{
    public const string WorklistFolderName = "_regenerate_worklist";
    private const string WorkFileExtension = ".work";

    private static readonly JsonSerializerOptions JsonOpts = new()
    {
        WriteIndented = true,
        PropertyNamingPolicy = JsonNamingPolicy.CamelCase,
        Encoder = JavaScriptEncoder.UnsafeRelaxedJsonEscaping,
        DefaultIgnoreCondition = JsonIgnoreCondition.WhenWritingNull
    };

    /// <summary>
    /// Create the worklist folder and populate it with one .work file per changed file.
    /// Clears any existing worklist files first.
    /// </summary>
    /// <param name="autoDocDataFolder">Base data folder (e.g., %OptPath%\data\AutoDocJson)</param>
    /// <param name="changedFiles">Files detected by GitChangeDetector</param>
    /// <param name="sqlItems">SQL tables to regenerate (from tables.csv filtering)</param>
    /// <returns>Path to the worklist folder</returns>
    public static string CreateWorklist(
        string autoDocDataFolder,
        List<ChangedFileInfo> changedFiles,
        List<SqlWorklistItem>? sqlItems = null)
    {
        string worklistFolder = Path.Combine(autoDocDataFolder, WorklistFolderName);

        if (Directory.Exists(worklistFolder))
        {
            foreach (var f in Directory.EnumerateFiles(worklistFolder, $"*{WorkFileExtension}"))
            {
                try { File.Delete(f); } catch { }
            }
        }
        else
        {
            Directory.CreateDirectory(worklistFolder);
        }

        string optPath = Environment.GetEnvironmentVariable("OptPath") ?? "C:\\opt";
        string optPathUnc = Environment.GetEnvironmentVariable("OptPathUnc")
            ?? $"\\\\{Environment.MachineName}\\opt";

        int written = 0;

        foreach (var file in changedFiles)
        {
            string localPath = file.FullPath;
            string uncPath = localPath.StartsWith(optPath, StringComparison.OrdinalIgnoreCase)
                ? optPathUnc + localPath.Substring(optPath.Length)
                : localPath;

            var item = new WorklistItem
            {
                LocalPath = localPath,
                UncPath = uncPath,
                RepoName = file.RepoName,
                RepoUrl = file.RepoUrl,
                RepoLocalPath = file.RepoLocalPath,
                RelativePath = file.RelativePath,
                CommitId = file.CommitId,
                ParserType = file.ParserType,
                FileName = file.FileName
            };

            string safeName = BuildSafeFileName(file.RepoName, file.RelativePath, file.ParserType);
            string workFilePath = Path.Combine(worklistFolder, safeName + WorkFileExtension);

            try
            {
                string json = JsonSerializer.Serialize(item, JsonOpts);
                File.WriteAllText(workFilePath, json);
                written++;
            }
            catch (Exception ex)
            {
                Logger.LogMessage($"WorklistManager: Failed to write {safeName}: {ex.Message}", LogLevel.WARN);
            }
        }

        if (sqlItems != null)
        {
            foreach (var sql in sqlItems)
            {
                var item = new WorklistItem
                {
                    ParserType = "SQL",
                    TableName = sql.TableName,
                    AlterTime = sql.AlterTime,
                    FileName = sql.TableName
                };

                string safeName = $"SQL_{sql.TableName.Replace(".", "_")}";
                string workFilePath = Path.Combine(worklistFolder, safeName + WorkFileExtension);

                try
                {
                    string json = JsonSerializer.Serialize(item, JsonOpts);
                    File.WriteAllText(workFilePath, json);
                    written++;
                }
                catch (Exception ex)
                {
                    Logger.LogMessage($"WorklistManager: Failed to write SQL {sql.TableName}: {ex.Message}", LogLevel.WARN);
                }
            }
        }

        Logger.LogMessage($"WorklistManager: Created {written} worklist files in {worklistFolder}", LogLevel.INFO);
        return worklistFolder;
    }

    /// <summary>
    /// Read all worklist files from the folder. Each file is opened with exclusive lock,
    /// read, then deleted to prevent other processes from claiming it.
    /// Files that are locked by another process are skipped.
    /// </summary>
    public static List<WorklistItem> ClaimWorklistItems(string worklistFolder)
    {
        var items = new List<WorklistItem>();

        if (!Directory.Exists(worklistFolder))
            return items;

        var workFiles = Directory.EnumerateFiles(worklistFolder, $"*{WorkFileExtension}")
            .OrderBy(f => f) // deterministic order
            .ToList();

        int claimed = 0, skipped = 0;

        foreach (string workFile in workFiles)
        {
            try
            {
                string json;
                using (var fs = new FileStream(workFile, FileMode.Open, FileAccess.Read, FileShare.None))
                using (var reader = new StreamReader(fs))
                {
                    json = reader.ReadToEnd();
                }
                File.Delete(workFile);

                var item = JsonSerializer.Deserialize<WorklistItem>(json, JsonOpts);
                if (item != null)
                {
                    items.Add(item);
                    claimed++;
                }
            }
            catch (IOException)
            {
                skipped++;
            }
            catch (Exception ex)
            {
                Logger.LogMessage($"WorklistManager: Error reading {Path.GetFileName(workFile)}: {ex.Message}", LogLevel.WARN);
                skipped++;
            }
        }

        if (skipped > 0)
            Logger.LogMessage($"WorklistManager: Claimed {claimed}, skipped {skipped} (locked by other process)", LogLevel.INFO);

        return items;
    }

    /// <summary>
    /// Pre-generation check: returns true if the output file was already regenerated
    /// after the current batch started (another process beat us to it).
    /// </summary>
    public static bool IsAlreadyRegenerated(string outputFolder, string fileName, DateTime batchStartedAtUtc)
    {
        string outputJson = Path.Combine(outputFolder, fileName + ".json");
        if (!File.Exists(outputJson))
            return false;

        return File.GetLastWriteTimeUtc(outputJson) > batchStartedAtUtc;
    }

    /// <summary>
    /// Build a filesystem-safe filename from repo name, relative path, and parser type.
    /// Example: Dedge_rexx_prod_BSAUTOS_REX
    /// </summary>
    private static string BuildSafeFileName(string repoName, string relativePath, string parserType)
    {
        // Replace path separators and dots with underscores, strip extension
        string pathPart = Path.ChangeExtension(relativePath, null) ?? relativePath;
        string combined = $"{repoName}_{pathPart}_{parserType}";

        // Sanitize: only allow alphanumeric, underscore, hyphen
        // Replace path separators and other unsafe chars with underscore
        combined = Regex.Replace(combined, @"[/\\. ]+", "_");
        combined = Regex.Replace(combined, @"[^a-zA-Z0-9_-]", "_");
        combined = Regex.Replace(combined, @"_+", "_").Trim('_');

        return combined;
    }
}

/// <summary>
/// Represents one item in the worklist folder. Serialized as JSON in .work files.
/// </summary>
public class WorklistItem
{
    public string? LocalPath { get; set; }
    public string? UncPath { get; set; }
    public string? RepoName { get; set; }
    public string? RepoUrl { get; set; }
    public string? RepoLocalPath { get; set; }
    public string? RelativePath { get; set; }
    public string? CommitId { get; set; }
    public string? ParserType { get; set; }
    public string? FileName { get; set; }
    public string? TableName { get; set; }
    public string? AlterTime { get; set; }
}

/// <summary>
/// SQL table entry for worklist creation.
/// </summary>
public class SqlWorklistItem
{
    public string TableName { get; set; } = "";
    public string AlterTime { get; set; } = "";
}
