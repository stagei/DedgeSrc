using Microsoft.Extensions.Options;
using System.Diagnostics;
using SystemAnalyzer.Core.Models;

public sealed class SystemAnalyzerJobService
{
    private readonly SystemAnalyzerOptions _options;
    private readonly Dictionary<string, JobStatus> _jobs = new(StringComparer.OrdinalIgnoreCase);
    private readonly object _gate = new();

    public SystemAnalyzerJobService(IOptions<SystemAnalyzerOptions> options)
    {
        _options = options.Value;
    }

    public JobStatus Start(string alias, string allJsonPath, List<int>? skipPhases = null, bool skipClassification = false)
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

        var extraArgs = "";
        if (skipPhases is { Count: > 0 })
        {
            extraArgs += $" --skip-phases \"{string.Join(",", skipPhases)}\"";
        }
        if (skipClassification)
        {
            extraArgs += " --skip-classification";
        }

        _ = Task.Run(async () =>
        {
            try
            {
                var batchRoot = ResolveBatchRoot();
                var batchExe = Path.Combine(batchRoot, "SystemAnalyzer.Batch.exe");
                var batchDll = Path.Combine(batchRoot, "SystemAnalyzer.Batch.dll");
                ProcessStartInfo psi;

                if (File.Exists(batchExe))
                {
                    psi = new ProcessStartInfo
                    {
                        FileName = batchExe,
                        Arguments = $"--alias \"{alias}\" --all-json \"{allJsonPath}\"{extraArgs}",
                        UseShellExecute = false,
                        CreateNoWindow = true
                    };
                }
                else if (File.Exists(batchDll))
                {
                    psi = new ProcessStartInfo
                    {
                        FileName = "dotnet",
                        Arguments = $"\"{batchDll}\" --alias \"{alias}\" --all-json \"{allJsonPath}\"{extraArgs}",
                        UseShellExecute = false,
                        CreateNoWindow = true
                    };
                }
                else
                {
                    var batchProject = Path.GetFullPath(Path.Combine(AppContext.BaseDirectory, "..", "..", "..", "..", "SystemAnalyzer.Batch", "SystemAnalyzer.Batch.csproj"));
                    psi = new ProcessStartInfo
                    {
                        FileName = "dotnet",
                        Arguments = $"run --project \"{batchProject}\" -- --alias \"{alias}\" --all-json \"{allJsonPath}\"{extraArgs}",
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
