using System.Diagnostics;
using System.Text.RegularExpressions;
using AutoDocNew.Models;

namespace AutoDocNew.Core;

/// <summary>
/// Gathers git history statistics for a source file.
/// Uses the same git-process pattern as RegenerationDecider.GetGitLastCommitDate.
/// </summary>
public static class GitStatsService
{
    private const int GitTimeoutMs = 15_000;

    /// <summary>
    /// Collect git history for <paramref name="filePath"/>.
    /// <paramref name="workingDirectory"/> must be inside the git work-tree
    /// that contains the file.
    /// Returns null when git is unavailable or the file has no history.
    /// </summary>
    public static GitHistory? GetStats(string filePath, string workingDirectory)
    {
        if (string.IsNullOrWhiteSpace(filePath) || string.IsNullOrWhiteSpace(workingDirectory))
            return null;

        if (!Directory.Exists(workingDirectory))
            return null;

        // When filePath is a directory or a solution/project file, track the whole repo
        // rather than a single file (which would miss most commits)
        bool isDirectory = Directory.Exists(filePath);
        bool isSolutionOrProject = !isDirectory && Path.GetExtension(filePath) is ".sln" or ".csproj";
        string pathFilter = "";

        if (!isDirectory && !isSolutionOrProject)
        {
            string relativePath = GetRelativePath(filePath, workingDirectory);
            pathFilter = $" -- \"{relativePath}\"";
        }

        try
        {
            string? lastChanged = RunGit($"log -n 1 --pretty=format:%cd --date=format:%Y-%m-%d{pathFilter}", workingDirectory);
            if (string.IsNullOrWhiteSpace(lastChanged))
                return null;

            string? changedBy = RunGit($"log -n 1 --pretty=format:%an{pathFilter}", workingDirectory);
            string? totalChangesStr = RunGit($"rev-list --count HEAD{pathFilter}", workingDirectory);

            // --reverse with -n 1 applies the limit first, then reverses — so it
            // still returns the newest commit.  Instead, find the root commit hash
            // and read its date.
            string? firstAdded = null;
            string? rootHash = RunGit($"rev-list --max-parents=0 HEAD{pathFilter}", workingDirectory);
            if (!string.IsNullOrWhiteSpace(rootHash))
            {
                string hash = rootHash.Trim().Split('\n')[0].Trim();
                firstAdded = RunGit($"log {hash} --format=%cd --date=format:%Y-%m-%d -1", workingDirectory);
            }

            // shortlog without a revision range reads stdin; always pass HEAD
            string? shortlog = RunGit($"shortlog -sn --no-merges HEAD{pathFilter}", workingDirectory);

            int totalChanges = 0;
            if (!string.IsNullOrWhiteSpace(totalChangesStr))
                int.TryParse(totalChangesStr.Trim(), out totalChanges);

            var contributors = ParseShortlog(shortlog);

            return new GitHistory
            {
                LastChanged = lastChanged.Trim(),
                ChangedBy = changedBy?.Trim() ?? "",
                TotalChanges = totalChanges,
                FirstAdded = firstAdded?.Trim() ?? "",
                Contributors = contributors.Count,
                ContributorList = contributors
            };
        }
        catch (Exception ex)
        {
            Logger.LogMessage($"GitStatsService: Failed for {filePath}: {ex.Message}", LogLevel.WARN);
            return null;
        }
    }

    /// <summary>
    /// Parse the output of <c>git shortlog -sn</c> into contributor objects.
    /// Each line is "  <count>\t<name>".
    /// </summary>
    private static List<GitContributor> ParseShortlog(string? shortlog)
    {
        var list = new List<GitContributor>();
        if (string.IsNullOrWhiteSpace(shortlog))
            return list;

        // Regex: optional whitespace, one or more digits (count), tab, then the author name
        //   ^\s*       — leading whitespace
        //   (\d+)      — group 1: commit count
        //   \t         — tab separator
        //   (.+)$      — group 2: author name (rest of line)
        var regex = new Regex(@"^\s*(\d+)\t(.+)$", RegexOptions.Multiline);

        foreach (Match m in regex.Matches(shortlog))
        {
            if (int.TryParse(m.Groups[1].Value, out int count))
            {
                list.Add(new GitContributor
                {
                    Name = m.Groups[2].Value.Trim(),
                    Changes = count
                });
            }
        }

        return list;
    }

    /// <summary>
    /// Render a GitHistory object as HTML table rows for the [githistory] template placeholder.
    /// </summary>
    public static string RenderHtmlRows(GitHistory? stats)
    {
        if (stats == null)
            return "<tr><td colspan=\"2\">No git history available</td></tr>";

        var sb = new System.Text.StringBuilder();
        sb.AppendLine($"<tr><td>Last Changed</td><td>{stats.LastChanged}</td></tr>");
        sb.AppendLine($"<tr><td>Changed By</td><td>{stats.ChangedBy}</td></tr>");
        sb.AppendLine($"<tr><td>Total Changes</td><td>{stats.TotalChanges}</td></tr>");
        sb.AppendLine($"<tr><td>First Added</td><td>{stats.FirstAdded}</td></tr>");
        sb.AppendLine($"<tr><td>Contributors</td><td>{stats.Contributors}</td></tr>");

        if (stats.ContributorList.Count > 0)
        {
            sb.AppendLine("<tr><td colspan=\"2\"><table class=\"detail-table\" style=\"margin-top:0.3rem\">");
            sb.AppendLine("<tr><th>Name</th><th>Changes</th></tr>");
            foreach (var c in stats.ContributorList)
                sb.AppendLine($"<tr><td>{c.Name}</td><td>{c.Changes}</td></tr>");
            sb.AppendLine("</table></td></tr>");
        }

        return sb.ToString();
    }

    private static string GetRelativePath(string filePath, string workingDirectory)
    {
        try
        {
            string fullFile = Path.GetFullPath(filePath);
            string fullDir = Path.GetFullPath(workingDirectory).TrimEnd(Path.DirectorySeparatorChar, Path.AltDirectorySeparatorChar);

            if (fullFile.StartsWith(fullDir, StringComparison.OrdinalIgnoreCase))
            {
                string rel = fullFile[(fullDir.Length + 1)..];
                return rel.Replace('\\', '/');
            }
        }
        catch { }

        return Path.GetFileName(filePath);
    }

    private static string? RunGit(string arguments, string workingDirectory)
    {
        try
        {
            var psi = new ProcessStartInfo
            {
                FileName = "git",
                Arguments = arguments,
                WorkingDirectory = workingDirectory,
                RedirectStandardOutput = true,
                RedirectStandardError = true,
                UseShellExecute = false,
                CreateNoWindow = true
            };

            using var process = Process.Start(psi);
            if (process == null) return null;

            string output = process.StandardOutput.ReadToEnd();
            process.WaitForExit(GitTimeoutMs);

            return process.ExitCode == 0 ? output : null;
        }
        catch
        {
            return null;
        }
    }
}
