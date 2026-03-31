using System;
using System.Collections.Generic;
using System.Diagnostics;
using System.IO;
using System.Linq;
using System.Text.RegularExpressions;

namespace AutoDocNew.Core;

/// <summary>
/// Detects changed files across all cloned repos using ONE git command per repo
/// instead of one per file. Replaces the per-file git log calls in RegenerationDecider.
/// </summary>
public static class GitChangeDetector
{
    /// <summary>
    /// Detect all files changed since <paramref name="sinceUtc"/> across all repos in <paramref name="workFolder"/>.
    /// For All/Clean modes, pass a very old date (e.g., 2010-01-01) to capture all tracked files.
    /// </summary>
    /// <param name="workFolder">Root folder containing cloned repos (e.g., .../DedgeRepository)</param>
    /// <param name="sinceUtc">Only files changed after this timestamp</param>
    /// <param name="fileTypes">Enabled file types (Cbl, Rex, Bat, Ps1, CSharp, Gs). SQL is excluded (uses ALTER_TIME).</param>
    /// <param name="maxPerType">Max files per type (0 = unlimited)</param>
    public static List<ChangedFileInfo> DetectChanges(
        string workFolder, DateTime sinceUtc, HashSet<string> fileTypes, int maxPerType)
    {
        var results = new List<ChangedFileInfo>();

        if (!Directory.Exists(workFolder))
        {
            Logger.LogMessage($"GitChangeDetector: Work folder not found: {workFolder}", LogLevel.WARN);
            return results;
        }

        string sinceStr = sinceUtc.ToString("yyyy-MM-ddTHH:mm:ssZ");
        Logger.LogMessage($"GitChangeDetector: Scanning repos for changes since {sinceStr}...", LogLevel.INFO);

        var repoDirectories = Directory.EnumerateDirectories(workFolder)
            .Where(d => Directory.Exists(Path.Combine(d, ".git")))
            .ToList();

        Logger.LogMessage($"GitChangeDetector: Found {repoDirectories.Count} git repositories", LogLevel.INFO);

        foreach (string repoDir in repoDirectories)
        {
            string repoName = Path.GetFileName(repoDir);
            var repoChanges = ScanRepository(repoDir, repoName, sinceStr, fileTypes, maxPerType);
            results.AddRange(repoChanges);
        }

        var byType = results.GroupBy(r => r.ParserType)
            .Select(g => $"{g.Key}={g.Count()}")
            .ToList();
        Logger.LogMessage(
            $"GitChangeDetector: {results.Count} changed files detected ({string.Join(", ", byType)})",
            LogLevel.INFO);

        return results;
    }

    /// <summary>
    /// Detect repos that have ANY changed C# files (.cs, .csproj, .sln) since the given date.
    /// Returns the set of repo names that need CSharp regeneration.
    /// </summary>
    public static HashSet<string> DetectCSharpChangedRepos(
        string workFolder, DateTime sinceUtc)
    {
        var changedRepos = new HashSet<string>(StringComparer.OrdinalIgnoreCase);

        if (!Directory.Exists(workFolder))
            return changedRepos;

        string sinceStr = sinceUtc.ToString("yyyy-MM-ddTHH:mm:ssZ");

        foreach (string repoDir in Directory.EnumerateDirectories(workFolder)
            .Where(d => Directory.Exists(Path.Combine(d, ".git"))))
        {
            string repoName = Path.GetFileName(repoDir);
            var changedFiles = GetChangedFileNames(repoDir, sinceStr);
            bool hasCSharpChanges = changedFiles.Any(f =>
                f.EndsWith(".cs", StringComparison.OrdinalIgnoreCase) ||
                f.EndsWith(".csproj", StringComparison.OrdinalIgnoreCase) ||
                f.EndsWith(".sln", StringComparison.OrdinalIgnoreCase));

            if (hasCSharpChanges)
                changedRepos.Add(repoName);
        }

        return changedRepos;
    }

    private static List<ChangedFileInfo> ScanRepository(
        string repoDir, string repoName, string sinceStr,
        HashSet<string> fileTypes, int maxPerType)
    {
        var results = new List<ChangedFileInfo>();

        string repoUrl = GetRepoUrl(repoDir);

        // git log with COMMIT:<hash> markers so we can associate files with their latest commit
        string gitArgs = $"log --since=\"{sinceStr}\" --pretty=format:\"COMMIT:%H\" --name-only HEAD";
        string output = RunGitOutput(gitArgs, repoDir);

        if (string.IsNullOrWhiteSpace(output))
            return results;

        // Parse blocks: COMMIT:<hash> followed by changed file paths
        // First occurrence of a file = its latest commit
        var fileToCommit = new Dictionary<string, string>(StringComparer.OrdinalIgnoreCase);
        string currentCommit = "";

        foreach (string rawLine in output.Split('\n', StringSplitOptions.None))
        {
            string line = rawLine.Trim().Trim('"');
            if (string.IsNullOrEmpty(line))
                continue;

            if (line.StartsWith("COMMIT:", StringComparison.Ordinal))
            {
                currentCommit = line.Substring(7);
                continue;
            }

            // It's a file path -- first occurrence wins (most recent commit)
            if (!fileToCommit.ContainsKey(line))
                fileToCommit[line] = currentCommit;
        }

        if (fileToCommit.Count == 0)
            return results;

        Logger.LogMessage($"  {repoName}: {fileToCommit.Count} changed files in git log", LogLevel.DEBUG);

        int limit = maxPerType > 0 ? maxPerType : int.MaxValue;
        var typeCounts = new Dictionary<string, int>(StringComparer.OrdinalIgnoreCase);

        foreach (var (relativePath, commitHash) in fileToCommit)
        {
            string fullPath = Path.Combine(repoDir, relativePath.Replace('/', '\\'));
            if (!File.Exists(fullPath))
                continue;

            string fileName = Path.GetFileName(relativePath);
            string? parserType = ClassifyFile(repoName, relativePath, fileName, fileTypes);
            if (parserType == null)
                continue;

            typeCounts.TryGetValue(parserType, out int count);
            if (count >= limit)
                continue;
            typeCounts[parserType] = count + 1;

            results.Add(new ChangedFileInfo
            {
                RepoName = repoName,
                RepoUrl = repoUrl,
                RepoLocalPath = repoDir,
                RelativePath = relativePath.Replace('\\', '/'),
                FullPath = fullPath,
                FileName = fileName,
                CommitId = commitHash,
                ParserType = parserType
            });
        }

        if (results.Count > 0)
            Logger.LogMessage($"  {repoName}: {results.Count} files matched type filters", LogLevel.INFO);

        return results;
    }

    /// <summary>
    /// Classify a file into a parser type based on its repo, path, and filename.
    /// Returns null if the file should be excluded or doesn't match any enabled type.
    /// </summary>
    private static string? ClassifyFile(string repoName, string relativePath, string fileName,
        HashSet<string> fileTypes)
    {
        // Skip _old folders
        if (relativePath.Contains("_old", StringComparison.OrdinalIgnoreCase))
            return null;

        // Skip bin/obj/.vs/.git folders
        if (relativePath.Contains("/bin/") || relativePath.Contains("/obj/") ||
            relativePath.Contains("/.vs/") || relativePath.Contains("/.git/") ||
            relativePath.Contains("\\bin\\") || relativePath.Contains("\\obj\\") ||
            relativePath.Contains("\\.vs\\") || relativePath.Contains("\\.git\\"))
            return null;

        string ext = Path.GetExtension(fileName).ToLowerInvariant();

        // REX: *.rex in Dedge/rexx_prod/
        if (ext == ".rex" && fileTypes.Contains("Rex") &&
            string.Equals(repoName, "Dedge", StringComparison.OrdinalIgnoreCase) &&
            relativePath.StartsWith("rexx_prod/", StringComparison.OrdinalIgnoreCase))
        {
            return "REX";
        }

        // BAT: *.bat in Dedge/bat_prod/, exclude ^[_-] names
        if (ext == ".bat" && fileTypes.Contains("Bat") &&
            string.Equals(repoName, "Dedge", StringComparison.OrdinalIgnoreCase) &&
            relativePath.StartsWith("bat_prod/", StringComparison.OrdinalIgnoreCase))
        {
            if (Regex.IsMatch(fileName, @"^[_-]"))
                return null;
            return "BAT";
        }

        // PS1: *.ps1 in DedgePsh/ (recursive), exclude ^[_-] names
        if (ext == ".ps1" && fileTypes.Contains("Ps1") &&
            string.Equals(repoName, "DedgePsh", StringComparison.OrdinalIgnoreCase))
        {
            if (Regex.IsMatch(fileName, @"^[_-]"))
                return null;
            return "PS1";
        }

        // CBL: *.cbl in Dedge/cbl/, exclude names containing -
        if (ext == ".cbl" && fileTypes.Contains("Cbl") &&
            string.Equals(repoName, "Dedge", StringComparison.OrdinalIgnoreCase) &&
            relativePath.StartsWith("cbl/", StringComparison.OrdinalIgnoreCase))
        {
            if (fileName.Contains('-'))
                return null;
            return "CBL";
        }

        // GS: *.gs in Dedge/gs/, exclude names with -, _, or space
        if (ext == ".gs" && fileTypes.Contains("Gs") &&
            string.Equals(repoName, "Dedge", StringComparison.OrdinalIgnoreCase) &&
            relativePath.StartsWith("gs/", StringComparison.OrdinalIgnoreCase))
        {
            if (fileName.Contains('-') || fileName.Contains('_') || fileName.Contains(' '))
                return null;
            return "GS";
        }

        return null;
    }

    /// <summary>
    /// Get just the list of changed file names (for CSharp detection without full parsing).
    /// </summary>
    private static List<string> GetChangedFileNames(string repoDir, string sinceStr)
    {
        string gitArgs = $"log --since=\"{sinceStr}\" --name-only --pretty=format:\"\" HEAD";
        string output = RunGitOutput(gitArgs, repoDir);
        if (string.IsNullOrWhiteSpace(output))
            return new List<string>();

        return output.Split('\n', StringSplitOptions.RemoveEmptyEntries)
            .Select(l => l.Trim().Trim('"'))
            .Where(l => !string.IsNullOrEmpty(l))
            .Distinct(StringComparer.OrdinalIgnoreCase)
            .ToList();
    }

    /// <summary>
    /// Get the remote origin URL, sanitized to remove any embedded PAT credentials.
    /// </summary>
    private static string GetRepoUrl(string repoDir)
    {
        string url = RunGitOutput("remote get-url origin", repoDir).Trim();
        // Strip embedded credentials: https://user:pat@dev.azure.com/... → https://dev.azure.com/...
        return Regex.Replace(url, @"://[^@]+@", "://");
    }

    private static string RunGitOutput(string arguments, string workingDir)
    {
        try
        {
            var psi = new ProcessStartInfo
            {
                FileName = "git",
                Arguments = arguments,
                WorkingDirectory = workingDir,
                RedirectStandardOutput = true,
                RedirectStandardError = true,
                UseShellExecute = false,
                CreateNoWindow = true
            };
            using var process = Process.Start(psi);
            if (process == null) return "";

            string stdout = process.StandardOutput.ReadToEnd();
            process.WaitForExit(120_000);
            return stdout;
        }
        catch (Exception ex)
        {
            Logger.LogMessage($"GitChangeDetector: git error in {workingDir}: {ex.Message}", LogLevel.WARN);
            return "";
        }
    }
}

/// <summary>
/// Represents a file detected as changed by GitChangeDetector.
/// </summary>
public class ChangedFileInfo
{
    public string RepoName { get; set; } = "";
    public string RepoUrl { get; set; } = "";
    public string RepoLocalPath { get; set; } = "";
    public string RelativePath { get; set; } = "";
    public string FullPath { get; set; } = "";
    public string FileName { get; set; } = "";
    public string CommitId { get; set; } = "";
    public string ParserType { get; set; } = "";
}
