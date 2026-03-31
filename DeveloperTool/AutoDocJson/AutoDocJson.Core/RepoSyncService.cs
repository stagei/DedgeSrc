using System;
using System.Collections.Generic;
using System.Diagnostics;
using System.IO;
using System.Linq;
using System.Net.Http;
using System.Text;
using System.Text.Json;

namespace AutoDocNew.Core;

/// <summary>
/// Discovers and clones/pulls Azure DevOps repositories into the work folder.
/// Converted from AzureFunctions.psm1: Get-AzureDevOpsRepositories, Sync-AzureDevOpsRepository,
/// Sync-MultipleAzureDevOpsRepositories, and Get-AzureDevOpsCredentials.
/// Called from BatchRunner lines 2401-2439 in AutoDocBatchRunner.ps1.
/// </summary>
public class RepoSyncService
{
    private const string Organization = "Dedge";
    private const string Project = "Dedge";
    private const string ApiVersion = "7.1";

    /// <summary>Hardcoded fallback repos when API discovery fails.</summary>
    private static readonly string[] FallbackRepos = { "Dedge", "DedgePsh", "ServerMonitor" };

    /// <summary>
    /// Sync (clone or pull) all discovered repos into workFolder.
    /// Each repo ends up at workFolder\{repoName}.
    /// </summary>
    public (int synced, int failed) Sync(string workFolder)
    {
        if (!Directory.Exists(workFolder))
            Directory.CreateDirectory(workFolder);

        var creds = GetCredentials();
        if (creds == null)
        {
            Logger.LogMessage("No Azure DevOps credentials found. Cannot sync repos.", LogLevel.ERROR);
            return (0, 0);
        }

        Logger.LogMessage($"Azure DevOps credentials loaded (email={creds.Value.email})", LogLevel.INFO);

        // Discover repos via REST API
        var repoNames = DiscoverRepositories(creds.Value.pat);
        if (repoNames.Count == 0)
        {
            Logger.LogMessage("Repository discovery returned no results, using hardcoded fallback list.", LogLevel.WARN);
            repoNames = FallbackRepos.ToList();
        }
        else
        {
            Logger.LogMessage($"Discovered {repoNames.Count} repositories in project {Project}.", LogLevel.INFO);
        }

        int synced = 0, failed = 0;
        foreach (string repoName in repoNames)
        {
            string targetFolder = Path.Combine(workFolder, repoName);
            bool ok = SyncRepository(repoName, targetFolder, creds.Value.email, creds.Value.pat);
            if (ok) synced++; else failed++;
        }

        Logger.LogMessage($"Repository sync complete: {synced} succeeded, {failed} failed.", LogLevel.INFO);
        return (synced, failed);
    }

    // ── Credential loading ──────────────────────────────────────────────

    /// <summary>
    /// Search for AzureAccessTokens.json in the same search paths as the PowerShell
    /// Get-AzureDevOpsCredentials function. Returns the PAT and email from the entry
    /// whose Id matches *AzureDevOpsExtPat*.
    /// </summary>
    private static (string pat, string email)? GetCredentials()
    {
        string? optPath = Environment.GetEnvironmentVariable("OptPath") ?? "C:\\opt";
        string? userProfile = Environment.GetFolderPath(Environment.SpecialFolder.UserProfile);
        string? oneDriveCommercial = Environment.GetEnvironmentVariable("OneDriveCommercial");
        string? oneDrive = Environment.GetEnvironmentVariable("OneDrive");

        var searchPaths = new List<string>();

        // Priority 1: Shared location
        if (!string.IsNullOrEmpty(optPath))
            searchPaths.Add(Path.Combine(optPath, "data", "AzureCredentials"));

        // Priority 2: OneDrive
        if (!string.IsNullOrEmpty(oneDriveCommercial))
            searchPaths.Add(oneDriveCommercial);
        if (!string.IsNullOrEmpty(oneDrive))
            searchPaths.Add(oneDrive);

        // Priority 3: User profile sub-folders
        if (!string.IsNullOrEmpty(userProfile))
        {
            searchPaths.Add(Path.Combine(userProfile, "Documents"));
            searchPaths.Add(Path.Combine(userProfile, "AppData", "Roaming"));
            searchPaths.Add(Path.Combine(userProfile, "AppData", "Local"));
        }

        const string fileName = "AzureAccessTokens.json";

        foreach (string dir in searchPaths)
        {
            string candidate = Path.Combine(dir, fileName);
            if (!File.Exists(candidate))
                continue;

            Logger.LogMessage($"Found credentials file: {candidate}", LogLevel.INFO);

            try
            {
                string json = File.ReadAllText(candidate);
                using var doc = JsonDocument.Parse(json);

                // The file is a JSON array of token objects
                if (doc.RootElement.ValueKind != JsonValueKind.Array)
                    continue;

                foreach (var entry in doc.RootElement.EnumerateArray())
                {
                    string? id = GetString(entry, "Id");
                    if (id == null) continue;

                    // Match *AzureDevOpsExtPat*
                    if (id.IndexOf("AzureDevOpsExtPat", StringComparison.OrdinalIgnoreCase) < 0)
                        continue;

                    string? pat = GetString(entry, "Token");
                    string? email = GetString(entry, "Email");

                    if (!string.IsNullOrEmpty(pat) && !string.IsNullOrEmpty(email))
                        return (pat, email);
                }
            }
            catch (Exception ex)
            {
                Logger.LogMessage($"Error reading credentials file {candidate}: {ex.Message}", LogLevel.WARN, ex);
            }
        }

        Logger.LogMessage($"AzureAccessTokens.json not found or missing AzureDevOpsExtPat entry. Search paths: {string.Join("; ", searchPaths)}", LogLevel.WARN);
        return null;
    }

    private static string? GetString(JsonElement el, string name)
    {
        if (el.TryGetProperty(name, out var prop) && prop.ValueKind == JsonValueKind.String)
            return prop.GetString();
        return null;
    }

    // ── Repository discovery ────────────────────────────────────────────

    /// <summary>
    /// Call Azure DevOps REST API to list all repos in the Dedge project.
    /// Returns repo names.
    /// </summary>
    private static List<string> DiscoverRepositories(string pat)
    {
        var repos = new List<string>();
        try
        {
            string url = $"https://dev.azure.com/{Organization}/{Project}/_apis/git/repositories?api-version={ApiVersion}";
            Logger.LogMessage($"Calling Azure DevOps API: {url}", LogLevel.DEBUG);

            using var client = new HttpClient();
            string basicAuth = Convert.ToBase64String(Encoding.ASCII.GetBytes($":{pat}"));
            client.DefaultRequestHeaders.Authorization = new System.Net.Http.Headers.AuthenticationHeaderValue("Basic", basicAuth);

            var response = client.GetAsync(url).GetAwaiter().GetResult();
            if (!response.IsSuccessStatusCode)
            {
                Logger.LogMessage($"Azure DevOps API returned {(int)response.StatusCode} {response.ReasonPhrase}", LogLevel.WARN);
                return repos;
            }

            string body = response.Content.ReadAsStringAsync().GetAwaiter().GetResult();
            using var doc = JsonDocument.Parse(body);
            if (doc.RootElement.TryGetProperty("value", out var arr) && arr.ValueKind == JsonValueKind.Array)
            {
                foreach (var repo in arr.EnumerateArray())
                {
                    string? name = GetString(repo, "name");
                    if (!string.IsNullOrEmpty(name))
                        repos.Add(name);
                }
            }
        }
        catch (Exception ex)
        {
            Logger.LogMessage($"Error discovering repositories: {ex.Message}", LogLevel.WARN, ex);
        }
        return repos;
    }

    // ── Git clone / pull ────────────────────────────────────────────────

    /// <summary>
    /// Clone or pull a single repo. Matches Sync-AzureDevOpsRepository from PS.
    /// Falls back to delete + re-clone when pull fails (stale credentials, corrupt .git, etc.).
    /// </summary>
    private static bool SyncRepository(string repoName, string targetFolder, string email, string pat)
    {
        try
        {
            string emailEncoded = email.Replace("@", "%40");
            string repoUrl = $"https://{emailEncoded}:{pat}@dev.azure.com/{Organization}/{Project}/_git/{repoName}";

            string gitFolder = Path.Combine(targetFolder, ".git");
            bool repoExists = Directory.Exists(gitFolder) && File.Exists(Path.Combine(gitFolder, "config"));

            if (repoExists)
            {
                // Update remote URL with current credentials before pulling (PAT may have changed)
                RunGit($"remote set-url origin \"{repoUrl}\"", targetFolder);

                // Pull latest changes (match PS: git reset --hard HEAD; git clean -fd; git pull)
                Logger.LogMessage($"Pulling latest changes for {repoName}...", LogLevel.INFO);
                RunGit("reset --hard HEAD", targetFolder);
                RunGit("clean -fd", targetFolder);
                int exitCode = RunGit("pull", targetFolder);
                if (exitCode == 0)
                {
                    Logger.LogMessage($"Successfully pulled {repoName}.", LogLevel.INFO);
                    return true;
                }

                // Pull failed - fall back to delete and re-clone
                Logger.LogMessage($"Git pull failed for {repoName} (exit {exitCode}). Deleting and re-cloning...", LogLevel.WARN);
                try { Directory.Delete(targetFolder, recursive: true); }
                catch (Exception delEx)
                {
                    Logger.LogMessage($"Failed to delete {targetFolder}: {delEx.Message}", LogLevel.WARN);
                    return false;
                }
            }

            // Clone (fresh or after failed pull cleanup)
            Logger.LogMessage($"Cloning repository {repoName}...", LogLevel.INFO);
            string? parentDir = Path.GetDirectoryName(targetFolder);
            if (!string.IsNullOrEmpty(parentDir) && !Directory.Exists(parentDir))
                Directory.CreateDirectory(parentDir);

            int cloneExitCode = RunGit($"clone \"{repoUrl}\" \"{targetFolder}\"", workingDir: null);
            if (cloneExitCode == 0)
            {
                Logger.LogMessage($"Successfully cloned {repoName} to {targetFolder}.", LogLevel.INFO);
                return true;
            }
            else
            {
                Logger.LogMessage($"Git clone failed for {repoName} (exit {cloneExitCode}).", LogLevel.WARN);
                return false;
            }
        }
        catch (Exception ex)
        {
            Logger.LogMessage($"Error syncing repository {repoName}: {ex.Message}", LogLevel.ERROR, ex);
            return false;
        }
    }

    /// <summary>Run a git command and return exit code.</summary>
    private static int RunGit(string arguments, string? workingDir)
    {
        var psi = new ProcessStartInfo
        {
            FileName = "git",
            Arguments = arguments,
            WorkingDirectory = workingDir ?? "",
            RedirectStandardOutput = true,
            RedirectStandardError = true,
            UseShellExecute = false,
            CreateNoWindow = true
        };
        using var process = Process.Start(psi);
        if (process == null) return -1;
        process.WaitForExit(300_000); // 5 minute timeout per git operation
        string stderr = process.StandardError.ReadToEnd();
        if (process.ExitCode != 0 && !string.IsNullOrWhiteSpace(stderr))
        {
            // Mask PAT from stderr before logging (avoid leaking credentials)
            string safeStderr = System.Text.RegularExpressions.Regex.Replace(
                stderr.Trim(), @"://[^@]+@", "://***@");
            Logger.LogMessage($"git {arguments.Split(' ')[0]}: {safeStderr}", LogLevel.WARN);
        }
        return process.ExitCode;
    }
}
