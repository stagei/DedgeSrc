using System.Diagnostics;
using System.Text;
using Microsoft.Extensions.Options;
using SystemAnalyzer2.Core.Models;

public sealed class SystemAnalyzerJobService
{
    private readonly SystemAnalyzerOptions _options;
    private readonly Dictionary<string, JobStatus> _jobs = new(StringComparer.OrdinalIgnoreCase);
    private readonly object _gate = new();

    public SystemAnalyzerJobService(IOptions<SystemAnalyzerOptions> options)
    {
        _options = options.Value;
    }

    public JobStatus Start(
        string alias,
        string allJsonPath,
        List<int>? skipPhases = null,
        bool skipClassification = false,
        bool skipNaming = false,
        bool skipCatalog = false,
        bool refreshCatalogs = false,
        bool generateStats = false,
        bool? generateLocally = null,
        string? autoDocApiUrl = null,
        bool cleanBeforeRun = true)
    {
        var id = Guid.NewGuid().ToString("N");
        var status = new JobStatus
        {
            JobId = id,
            Alias = alias,
            Status = "running",
            StartedAt = DateTimeOffset.UtcNow
        };
        lock (_gate)
        {
            _jobs[id] = status;
        }

        var extraArgs = BuildBatchExtraArguments(
            skipPhases, skipClassification, skipNaming, skipCatalog,
            refreshCatalogs, generateStats, generateLocally, autoDocApiUrl, cleanBeforeRun);
        var coreArgs = $"--alias \"{EscapeForProcessArgument(alias)}\" --all-json \"{EscapeForProcessArgument(allJsonPath)}\"{extraArgs}";

        _ = Task.Run(async () =>
        {
            try
            {
                var batchRoot = ResolveBatchRoot();
                var batchExe = Path.Combine(batchRoot, "SystemAnalyzer2.Batch.exe");
                var batchDll = Path.Combine(batchRoot, "SystemAnalyzer2.Batch.dll");
                ProcessStartInfo psi;

                if (File.Exists(batchExe))
                {
                    psi = new ProcessStartInfo
                    {
                        FileName = batchExe,
                        Arguments = coreArgs,
                        UseShellExecute = false,
                        CreateNoWindow = true
                    };
                }
                else if (File.Exists(batchDll))
                {
                    psi = new ProcessStartInfo
                    {
                        FileName = "dotnet",
                        Arguments = $"\"{batchDll}\" {coreArgs}",
                        UseShellExecute = false,
                        CreateNoWindow = true
                    };
                }
                else
                {
                    var batchProject = Path.GetFullPath(Path.Combine(AppContext.BaseDirectory, "..", "..", "..", "..", "SystemAnalyzer2.Batch", "SystemAnalyzer2.Batch.csproj"));
                    psi = new ProcessStartInfo
                    {
                        FileName = "dotnet",
                        Arguments = $"run --project \"{batchProject}\" -- {coreArgs}",
                        UseShellExecute = false,
                        RedirectStandardOutput = true,
                        RedirectStandardError = true,
                        CreateNoWindow = true
                    };
                }

                using var process = Process.Start(psi);
                if (process is null)
                {
                    throw new InvalidOperationException("Could not start batch process.");
                }

                await process.WaitForExitAsync();
                lock (_gate)
                {
                    status.Status = process.ExitCode == 0 ? "completed" : "failed";
                    status.CompletedAt = DateTimeOffset.UtcNow;
                    status.ExitCode = process.ExitCode;
                }
            }
            catch (Exception ex)
            {
                lock (_gate)
                {
                    status.Status = "failed";
                    status.CompletedAt = DateTimeOffset.UtcNow;
                    status.Error = ex.Message;
                    status.ExitCode = -1;
                }
            }
        });

        return status;
    }

    private static string BuildBatchExtraArguments(
        List<int>? skipPhases,
        bool skipClassification,
        bool skipNaming,
        bool skipCatalog,
        bool refreshCatalogs,
        bool generateStats,
        bool? generateLocally,
        string? autoDocApiUrl,
        bool cleanBeforeRun)
    {
        var sb = new StringBuilder();
        if (skipPhases is { Count: > 0 })
            sb.Append($" --skip-phases \"{string.Join(",", skipPhases)}\"");
        if (skipClassification)
            sb.Append(" --skip-classification");
        if (skipNaming)
            sb.Append(" --skip-naming");
        if (skipCatalog)
            sb.Append(" --skip-catalog");
        if (refreshCatalogs)
            sb.Append(" --refresh-catalogs");
        if (generateStats)
            sb.Append(" --generate-stats");
        if (generateLocally == true)
            sb.Append(" --generate-locally");
        if (generateLocally == false)
            sb.Append(" --no-generate-locally");
        var url = (autoDocApiUrl ?? "").Trim().Replace("\"", "");
        if (url.Length > 0)
            sb.Append($" --autodoc-api-url \"{EscapeForProcessArgument(url)}\"");
        if (!cleanBeforeRun)
            sb.Append(" --no-clean-before-run");
        return sb.ToString();
    }

    /// <summary>Minimal escaping for values embedded in double-quoted process arguments on Windows.</summary>
    private static string EscapeForProcessArgument(string s)
    {
        return s.Replace("\"", "\\\"");
    }

    public JobStatus? Get(string jobId)
    {
        lock (_gate)
        {
            _jobs.TryGetValue(jobId, out var status);
            return status;
        }
    }

    private string ResolveBatchRoot()
    {
        if (!string.IsNullOrWhiteSpace(_options.BatchRoot))
            return _options.BatchRoot;

        var sibling = Path.GetFullPath(Path.Combine(AppContext.BaseDirectory, "..", "SystemAnalyzer-Batch"));
        if (Directory.Exists(sibling))
            return sibling;

        return Path.Combine(AppContext.BaseDirectory, "Batch");
    }
}

public sealed class JobStatus
{
    public string JobId { get; set; } = string.Empty;
    public string Alias { get; set; } = string.Empty;
    public string Status { get; set; } = "running";
    public DateTimeOffset StartedAt { get; set; }
    public DateTimeOffset? CompletedAt { get; set; }
    public int? ExitCode { get; set; }
    public string? Error { get; set; }
}
