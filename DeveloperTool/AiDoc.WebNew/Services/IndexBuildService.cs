using System.Diagnostics;
using System.Text.Json;
using Microsoft.Extensions.Options;
using AiDoc.WebNew.Options;

namespace AiDoc.WebNew.Services;

public class IndexBuildService
{
    private readonly ILogger<IndexBuildService> _logger;
    private readonly AiDocOptions _options;

    private static readonly JsonSerializerOptions JsonOpts = new()
    {
        PropertyNameCaseInsensitive = true,
        WriteIndented = true
    };

    public IndexBuildService(ILogger<IndexBuildService> logger, IOptions<AiDocOptions> options)
    {
        _logger = logger;
        _options = options.Value;
    }

    private string OptPath => Environment.GetEnvironmentVariable("OptPath") ?? @"E:\opt";
    private string PythonRoot => ResolvePath(_options.PythonRoot, "python");
    private string LibraryRoot
    {
        get
        {
            if (!string.IsNullOrEmpty(_options.LibraryRoot))
            {
                if (Path.IsPathRooted(_options.LibraryRoot)) return _options.LibraryRoot;
                var joined = Path.Combine(OptPath, _options.LibraryRoot);
                if (Directory.Exists(joined)) return joined;
            }
            return Path.Combine(OptPath, "data", "AiDoc.Library");
        }
    }
    private string RebuildStatusDir => Path.Combine(OptPath, "data", "Rebuild-RagIndex");

    private string ResolvePath(string configValue, string appRelativeFallback)
    {
        if (!string.IsNullOrEmpty(configValue))
        {
            if (Path.IsPathRooted(configValue)) return configValue;
            var joined = Path.Combine(OptPath, configValue);
            if (Directory.Exists(joined)) return joined;
        }
        return Path.Combine(AppContext.BaseDirectory, appRelativeFallback);
    }

    private string ResolvePythonExe()
    {
        if (!string.IsNullOrEmpty(_options.PythonExe) && File.Exists(_options.PythonExe))
            return _options.PythonExe;

        var venvPython = Path.Combine(PythonRoot, ".venv", "Scripts", "python.exe");
        if (File.Exists(venvPython)) return venvPython;

        return "python";
    }

    public Task<bool> RebuildAsync(string ragName)
    {
        var ragDir = Path.Combine(LibraryRoot, ragName);
        if (!Directory.Exists(ragDir))
            throw new DirectoryNotFoundException($"RAG directory not found: {ragDir}");

        Directory.CreateDirectory(RebuildStatusDir);

        var runningFile = Path.Combine(RebuildStatusDir, $"{ragName}.running");
        if (File.Exists(runningFile))
            throw new InvalidOperationException($"Rebuild already in progress for '{ragName}'");

        var buildScript = Path.Combine(PythonRoot, "build_index.py");
        if (!File.Exists(buildScript))
            throw new FileNotFoundException($"build_index.py not found at {buildScript}");

        var pythonExe = ResolvePythonExe();

        // Write running status
        var status = new
        {
            ragName,
            startedAt = DateTime.UtcNow.ToString("O"),
            startedBy = Environment.UserName,
            server = Environment.MachineName,
            pid = 0
        };
        File.WriteAllText(runningFile, JsonSerializer.Serialize(status, JsonOpts));

        _logger.LogInformation("Starting index rebuild for {Rag} using {Python}", ragName, pythonExe);

        var psi = new ProcessStartInfo
        {
            FileName = pythonExe,
            Arguments = $"\"{buildScript}\" --rag {ragName}",
            WorkingDirectory = PythonRoot,
            UseShellExecute = false,
            CreateNoWindow = true,
            RedirectStandardOutput = false,
            RedirectStandardError = false
        };

        // Set library dir env var so build_index.py finds the library
        psi.Environment["AIDOC_LIBRARY_DIR"] = LibraryRoot;

        var process = Process.Start(psi);
        if (process is null)
        {
            File.Delete(runningFile);
            throw new InvalidOperationException("Failed to start Python process");
        }

        // Update status with actual PID
        var updatedStatus = new
        {
            ragName,
            startedAt = DateTime.UtcNow.ToString("O"),
            startedBy = Environment.UserName,
            server = Environment.MachineName,
            pid = process.Id
        };
        File.WriteAllText(runningFile, JsonSerializer.Serialize(updatedStatus, JsonOpts));

        // Fire-and-forget: clean up running file when process exits
        _ = Task.Run(async () =>
        {
            await process.WaitForExitAsync();
            if (File.Exists(runningFile))
                File.Delete(runningFile);
            _logger.LogInformation("Rebuild for {Rag} finished with exit code {Code}", ragName, process.ExitCode);
        });

        return Task.FromResult(true);
    }

    public Task<object?> GetStatusAsync(string ragName)
    {
        var runningFile = Path.Combine(RebuildStatusDir, $"{ragName}.running");
        if (!File.Exists(runningFile))
            return Task.FromResult<object?>(new { building = false });

        try
        {
            var json = File.ReadAllText(runningFile);
            var doc = JsonDocument.Parse(json);
            return Task.FromResult<object?>(new
            {
                building = true,
                ragName = doc.RootElement.TryGetProperty("ragName", out var rn) ? rn.GetString() : ragName,
                startedAt = doc.RootElement.TryGetProperty("startedAt", out var sa) ? sa.GetString() : null,
                pid = doc.RootElement.TryGetProperty("pid", out var p) ? p.GetInt32() : (int?)null
            });
        }
        catch
        {
            return Task.FromResult<object?>(new { building = true, ragName });
        }
    }
}
