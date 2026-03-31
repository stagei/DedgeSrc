using System.Diagnostics;
using Microsoft.Extensions.Options;
using AiDoc.WebNew.Models;
using AiDoc.WebNew.Options;

namespace AiDoc.WebNew.Services;

public class EnvironmentService
{
    private readonly ILogger<EnvironmentService> _logger;
    private readonly AiDocOptions _options;

    public EnvironmentService(ILogger<EnvironmentService> logger, IOptions<AiDocOptions> options)
    {
        _logger = logger;
        _options = options.Value;
    }

    private string OptPath => Environment.GetEnvironmentVariable("OptPath") ?? @"E:\opt";

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

    private string PythonRoot => ResolvePath(_options.PythonRoot, "python");

    public async Task<EnvironmentStatus> GetStatusAsync()
    {
        var status = new EnvironmentStatus();
        var issues = new List<string>();

        // Check Python
        var pythonPath = ResolvePythonExe();
        if (pythonPath is not null && File.Exists(pythonPath))
        {
            status.PythonPath = pythonPath;
            status.PythonVersion = await GetPythonVersionAsync(pythonPath);
        }
        else
        {
            issues.Add("Python executable not found");
        }

        // Check venv
        var venvPython = Path.Combine(PythonRoot, ".venv", "Scripts", "python.exe");
        status.VenvExists = File.Exists(venvPython);
        if (!status.VenvExists)
            issues.Add("Python venv not found at " + Path.Combine(PythonRoot, ".venv"));

        // Check library
        status.LibraryExists = Directory.Exists(LibraryRoot);
        if (!status.LibraryExists)
        {
            issues.Add("Library root not found: " + LibraryRoot);
        }
        else
        {
            status.IndexCount = Directory.GetDirectories(LibraryRoot)
                .Count(d => Directory.Exists(Path.Combine(d, ".index")));
        }

        // Check running services
        status.ServicesRunning = Process.GetProcessesByName("python")
            .Count(p =>
            {
                try { return p.MainModule?.FileName?.Contains("AiDoc") == true || GetCommandLine(p)?.Contains("server_http") == true; }
                catch { return false; }
            });

        status.Issues = issues;
        return status;
    }

    public async Task<EnvironmentStatus> InitializeAsync()
    {
        _logger.LogInformation("Initializing AiDoc environment...");

        // Ensure library exists
        if (!Directory.Exists(LibraryRoot))
        {
            Directory.CreateDirectory(LibraryRoot);
            _logger.LogInformation("Created library root: {Path}", LibraryRoot);
        }

        // Find Python
        var pythonExe = ResolvePythonExe();
        if (pythonExe is null || !File.Exists(pythonExe))
            throw new InvalidOperationException("Python 3.11+ not found. Install from https://python.org");

        // Create venv if missing
        var venvDir = Path.Combine(PythonRoot, ".venv");
        var venvPython = Path.Combine(venvDir, "Scripts", "python.exe");
        if (!File.Exists(venvPython))
        {
            _logger.LogInformation("Creating Python venv at {Path}", venvDir);
            await RunProcessAsync(pythonExe, $"-m venv \"{venvDir}\"", PythonRoot);

            // Install requirements
            var reqFile = Path.Combine(PythonRoot, "requirements.txt");
            if (File.Exists(reqFile))
            {
                _logger.LogInformation("Installing pip requirements...");
                await RunProcessAsync(venvPython, $"-m pip install --upgrade pip --quiet", PythonRoot);
                await RunProcessAsync(venvPython, $"-m pip install -r \"{reqFile}\" --quiet", PythonRoot);
            }
        }

        return await GetStatusAsync();
    }

    public async Task<string?> VerifyPythonAsync()
    {
        var exe = ResolvePythonExe();
        if (exe is null || !File.Exists(exe)) return null;
        return await GetPythonVersionAsync(exe);
    }

    private string? ResolvePythonExe()
    {
        if (!string.IsNullOrEmpty(_options.PythonExe) && File.Exists(_options.PythonExe))
            return _options.PythonExe;

        var venvPython = Path.Combine(PythonRoot, ".venv", "Scripts", "python.exe");
        if (File.Exists(venvPython)) return venvPython;

        // Try common install locations
        foreach (var ver in new[] { "314", "313", "312", "311" })
        {
            var path = $@"C:\Program Files\Python{ver}\python.exe";
            if (File.Exists(path)) return path;
        }

        return null;
    }

    private async Task<string?> GetPythonVersionAsync(string pythonExe)
    {
        try
        {
            var psi = new ProcessStartInfo
            {
                FileName = pythonExe,
                Arguments = "--version",
                RedirectStandardOutput = true,
                UseShellExecute = false,
                CreateNoWindow = true
            };
            using var proc = Process.Start(psi);
            if (proc is null) return null;
            var output = await proc.StandardOutput.ReadToEndAsync();
            await proc.WaitForExitAsync();
            return output.Trim();
        }
        catch { return null; }
    }

    private async Task RunProcessAsync(string exe, string args, string workDir)
    {
        var psi = new ProcessStartInfo
        {
            FileName = exe,
            Arguments = args,
            WorkingDirectory = workDir,
            RedirectStandardOutput = true,
            RedirectStandardError = true,
            UseShellExecute = false,
            CreateNoWindow = true
        };
        using var proc = Process.Start(psi) ?? throw new InvalidOperationException($"Failed to start {exe}");
        await proc.WaitForExitAsync();
        if (proc.ExitCode != 0)
        {
            var stderr = await proc.StandardError.ReadToEndAsync();
            throw new InvalidOperationException($"{exe} exited with code {proc.ExitCode}: {stderr}");
        }
    }

    private static string? GetCommandLine(Process p)
    {
        try { return p.StartInfo.Arguments; } catch { return null; }
    }
}
