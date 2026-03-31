using System.Diagnostics;
using System.Text.Json;
using Microsoft.Extensions.Options;
using AiDoc.WebNew.Models;
using AiDoc.WebNew.Options;

namespace AiDoc.WebNew.Services;

public class ServiceManagementService
{
    private readonly ILogger<ServiceManagementService> _logger;
    private readonly AiDocOptions _options;
    private readonly IHttpClientFactory _httpClientFactory;

    public ServiceManagementService(
        ILogger<ServiceManagementService> logger,
        IOptions<AiDocOptions> options,
        IHttpClientFactory httpClientFactory)
    {
        _logger = logger;
        _options = options.Value;
        _httpClientFactory = httpClientFactory;
    }

    private string OptPath => Environment.GetEnvironmentVariable("OptPath") ?? @"E:\opt";
    private string PythonRoot => ResolvePath(_options.PythonRoot, "python");

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
        return File.Exists(venvPython) ? venvPython : "python";
    }

    public async Task<List<RagServiceInfo>> ListServicesAsync(List<RagRegistryEntry> rags, string host)
    {
        var results = new List<RagServiceInfo>();
        var client = _httpClientFactory.CreateClient("RagProxy");

        foreach (var rag in rags)
        {
            var info = new RagServiceInfo
            {
                Name = rag.Name,
                Port = rag.Port,
                HealthEndpoint = $"http://{host}:{rag.Port}/health"
            };

            try
            {
                var response = await client.GetAsync($"http://{host}:{rag.Port}/health");
                if (response.IsSuccessStatusCode)
                {
                    info.Status = "running";
                    // Try to find the process by port
                    info.Pid = FindProcessByPort(rag.Port);
                }
                else
                {
                    info.Status = "unhealthy";
                }
            }
            catch
            {
                info.Status = "stopped";
            }

            results.Add(info);
        }

        return results;
    }

    public async Task<RagServiceInfo> StartServiceAsync(string ragName, int port, string host)
    {
        var serverScript = Path.Combine(PythonRoot, "server_http.py");
        if (!File.Exists(serverScript))
            throw new FileNotFoundException($"server_http.py not found at {serverScript}");

        var pythonExe = ResolvePythonExe();

        // Check if already running
        try
        {
            var client = _httpClientFactory.CreateClient("RagProxy");
            var response = await client.GetAsync($"http://{host}:{port}/health");
            if (response.IsSuccessStatusCode)
                throw new InvalidOperationException($"Service for '{ragName}' is already running on port {port}");
        }
        catch (HttpRequestException) { /* not running, good */ }
        catch (InvalidOperationException) { throw; }

        _logger.LogInformation("Starting RAG service {Name} on port {Port}", ragName, port);

        var psi = new ProcessStartInfo
        {
            FileName = pythonExe,
            Arguments = $"\"{serverScript}\" --rag {ragName} --host 0.0.0.0 --port {port}",
            WorkingDirectory = PythonRoot,
            UseShellExecute = false,
            CreateNoWindow = true,
            RedirectStandardOutput = false,
            RedirectStandardError = false
        };

        var process = Process.Start(psi)
            ?? throw new InvalidOperationException("Failed to start Python process");

        _logger.LogInformation("RAG service {Name} started with PID {Pid}", ragName, process.Id);

        // Wait briefly for startup
        await Task.Delay(2000);

        return new RagServiceInfo
        {
            Name = ragName,
            Port = port,
            Status = "starting",
            Pid = process.Id,
            StartedAt = DateTime.UtcNow
        };
    }

    public Task<bool> StopServiceAsync(string ragName, int port)
    {
        var pid = FindProcessByPort(port);
        if (pid is null)
        {
            _logger.LogWarning("No process found for {Name} on port {Port}", ragName, port);
            return Task.FromResult(false);
        }

        try
        {
            var process = Process.GetProcessById(pid.Value);
            process.Kill(entireProcessTree: true);
            _logger.LogInformation("Stopped RAG service {Name} (PID {Pid})", ragName, pid);
            return Task.FromResult(true);
        }
        catch (Exception ex)
        {
            _logger.LogError(ex, "Failed to stop process {Pid} for {Name}", pid, ragName);
            return Task.FromResult(false);
        }
    }

    public async Task<RagServiceInfo> RestartServiceAsync(string ragName, int port, string host)
    {
        await StopServiceAsync(ragName, port);
        await Task.Delay(2000);
        return await StartServiceAsync(ragName, port, host);
    }

    public async Task<bool> CheckHealthAsync(string host, int port)
    {
        try
        {
            var client = _httpClientFactory.CreateClient("RagProxy");
            var response = await client.GetAsync($"http://{host}:{port}/health");
            return response.IsSuccessStatusCode;
        }
        catch { return false; }
    }

    private static int? FindProcessByPort(int port)
    {
        try
        {
            foreach (var proc in Process.GetProcessesByName("python"))
            {
                try
                {
                    if (proc.StartInfo.Arguments?.Contains($"--port {port}") == true)
                        return proc.Id;
                }
                catch { }
            }
        }
        catch { }
        return null;
    }
}
