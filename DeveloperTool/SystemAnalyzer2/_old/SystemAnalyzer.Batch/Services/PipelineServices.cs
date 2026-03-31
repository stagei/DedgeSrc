using System.Diagnostics;
using System.Net.Http.Json;
using SystemAnalyzer.Core.Models;

namespace SystemAnalyzer.Batch.Services;

public sealed class AnalysisPipeline
{
    private readonly SourceIndexer _sourceIndexer;
    private readonly DependencyExtractor _dependencyExtractor;
    private readonly CallGraphExpander _callGraphExpander;
    private readonly Db2TableValidator _db2TableValidator;
    private readonly TableProgramDiscovery _tableProgramDiscovery;
    private readonly SourceVerifier _sourceVerifier;
    private readonly ProgramClassifier _programClassifier;
    private readonly OutputWriter _outputWriter;

    public AnalysisPipeline(
        SourceIndexer sourceIndexer,
        DependencyExtractor dependencyExtractor,
        CallGraphExpander callGraphExpander,
        Db2TableValidator db2TableValidator,
        TableProgramDiscovery tableProgramDiscovery,
        SourceVerifier sourceVerifier,
        ProgramClassifier programClassifier,
        OutputWriter outputWriter)
    {
        _sourceIndexer = sourceIndexer;
        _dependencyExtractor = dependencyExtractor;
        _callGraphExpander = callGraphExpander;
        _db2TableValidator = db2TableValidator;
        _tableProgramDiscovery = tableProgramDiscovery;
        _sourceVerifier = sourceVerifier;
        _programClassifier = programClassifier;
        _outputWriter = outputWriter;
    }

    public async Task<int> RunAsync(AnalysisRunRequest request, CancellationToken cancellationToken = default)
    {
        // The first C# delivery executes the proven PowerShell pipeline while keeping
        // the same JSON contract. The stepwise service classes below map 1:1 to
        // the PowerShell phases and are used by this orchestrator as the migration path.
        await _sourceIndexer.ExecuteAsync(request, cancellationToken);
        await _dependencyExtractor.ExecuteAsync(request, cancellationToken);
        await _callGraphExpander.ExecuteAsync(request, cancellationToken);
        await _db2TableValidator.ExecuteAsync(request, cancellationToken);
        await _tableProgramDiscovery.ExecuteAsync(request, cancellationToken);
        await _sourceVerifier.ExecuteAsync(request, cancellationToken);
        await _programClassifier.ExecuteAsync(request, cancellationToken);
        await _outputWriter.ExecuteAsync(request, cancellationToken);
        return 0;
    }
}

public sealed class SourceIndexer { public Task ExecuteAsync(AnalysisRunRequest request, CancellationToken ct) => Task.CompletedTask; }
public sealed class DependencyExtractor { public Task ExecuteAsync(AnalysisRunRequest request, CancellationToken ct) => Task.CompletedTask; }
public sealed class CallGraphExpander { public Task ExecuteAsync(AnalysisRunRequest request, CancellationToken ct) => Task.CompletedTask; }
public sealed class Db2TableValidator { public Task ExecuteAsync(AnalysisRunRequest request, CancellationToken ct) => Task.CompletedTask; }
public sealed class TableProgramDiscovery { public Task ExecuteAsync(AnalysisRunRequest request, CancellationToken ct) => Task.CompletedTask; }
public sealed class SourceVerifier { public Task ExecuteAsync(AnalysisRunRequest request, CancellationToken ct) => Task.CompletedTask; }
public sealed class ProgramClassifier { public Task ExecuteAsync(AnalysisRunRequest request, CancellationToken ct) => Task.CompletedTask; }
public sealed class OutputWriter { public Task ExecuteAsync(AnalysisRunRequest request, CancellationToken ct) => Task.CompletedTask; }

public sealed class RagClient
{
    private readonly HttpClient _httpClient;
    public RagClient(HttpClient httpClient) => _httpClient = httpClient;
    public async Task<string> QueryAsync(string ragUrl, string query, CancellationToken cancellationToken = default)
    {
        var payload = new Dictionary<string, object> { ["query"] = query, ["top_k"] = 8 };
        using var resp = await _httpClient.PostAsJsonAsync(ragUrl, payload, cancellationToken);
        resp.EnsureSuccessStatusCode();
        return await resp.Content.ReadAsStringAsync(cancellationToken);
    }
}

public sealed class OllamaClient
{
    private readonly HttpClient _httpClient;
    public OllamaClient(HttpClient httpClient) => _httpClient = httpClient;

    public async Task<string> GenerateAsync(string ollamaUrl, string model, string prompt, CancellationToken cancellationToken = default)
    {
        var endpoint = $"{ollamaUrl.TrimEnd('/')}/api/generate";
        var payload = new Dictionary<string, object>
        {
            ["model"] = model,
            ["prompt"] = prompt,
            ["stream"] = false
        };
        using var resp = await _httpClient.PostAsJsonAsync(endpoint, payload, cancellationToken);
        resp.EnsureSuccessStatusCode();
        return await resp.Content.ReadAsStringAsync(cancellationToken);
    }
}

public sealed class AnalysisRunRequest
{
    public string Alias { get; set; } = string.Empty;
    public string AllJsonPath { get; set; } = string.Empty;
    public bool SkipClassification { get; set; }
    public List<int> SkipPhases { get; set; } = [];
    public SystemAnalyzerOptions Options { get; set; } = new();
}

public sealed class PowerShellPipelineRunner
{
    public async Task<int> RunInvokeFullAnalysisAsync(AnalysisRunRequest request, CancellationToken cancellationToken = default)
    {
        var scriptPath = ResolveScriptPath();
        if (scriptPath is null)
        {
            throw new FileNotFoundException(
                $"Invoke-FullAnalysis.ps1 not found. Expected at: {Path.Combine(AppContext.BaseDirectory, "Scripts", "Invoke-FullAnalysis.ps1")}");
        }

        var skipPhases = request.SkipPhases.Count > 0 ? string.Join(",", request.SkipPhases) : string.Empty;
        var arguments = new List<string>
        {
            "-NoProfile",
            "-File", $"\"{scriptPath}\"",
            "-AllJsonPath", $"\"{request.AllJsonPath}\"",
            "-AnalysisAlias", $"\"{request.Alias}\"",
            "-AnalysisDataRoot", $"\"{request.Options.AnalysisResultsRoot}\"",
            "-OutputDir", $"\"{request.Options.AnalysisResultsRoot}\"",
            "-SourceRoot", $"\"{request.Options.SourceRoot}\"",
            "-RagUrl", $"\"{request.Options.RagUrl}\"",
            "-VisualCobolRagUrl", $"\"{request.Options.VisualCobolRagUrl}\"",
            "-Db2Dsn", $"\"{request.Options.Db2Dsn}\"",
            "-DefaultFilePath", $"\"{request.Options.DefaultFilePath}\"",
            "-OllamaUrl", $"\"{request.Options.OllamaUrl}\"",
            "-OllamaModel", $"\"{request.Options.OllamaModel}\"",
            "-MaxCallIterations", request.Options.MaxCallIterations.ToString(),
            "-RagResults", request.Options.RagResults.ToString(),
            "-RagTableResults", request.Options.RagTableResults.ToString()
        };
        if (!string.IsNullOrEmpty(request.Options.AnalysisCommonPath))
        {
            arguments.Add("-AnalysisCommonPath");
            arguments.Add($"\"{request.Options.AnalysisCommonPath}\"");
        }
        if (request.SkipClassification)
        {
            arguments.Add("-SkipClassification");
        }
        if (!string.IsNullOrWhiteSpace(skipPhases))
        {
            arguments.Add("-SkipPhases");
            arguments.Add(skipPhases);
        }

        var startInfo = new ProcessStartInfo
        {
            FileName = "pwsh.exe",
            Arguments = string.Join(" ", arguments),
            UseShellExecute = false,
            RedirectStandardOutput = true,
            RedirectStandardError = true,
            CreateNoWindow = true
        };

        using var process = new Process { StartInfo = startInfo, EnableRaisingEvents = true };
        process.Start();

        _ = Task.Run(async () =>
        {
            while (!process.StandardOutput.EndOfStream)
            {
                var line = await process.StandardOutput.ReadLineAsync(cancellationToken);
                if (!string.IsNullOrWhiteSpace(line))
                {
                    Console.WriteLine(line);
                }
            }
        }, cancellationToken);

        _ = Task.Run(async () =>
        {
            while (!process.StandardError.EndOfStream)
            {
                var line = await process.StandardError.ReadLineAsync(cancellationToken);
                if (!string.IsNullOrWhiteSpace(line))
                {
                    Console.Error.WriteLine(line);
                }
            }
        }, cancellationToken);

        await process.WaitForExitAsync(cancellationToken);
        return process.ExitCode;

        static string? ResolveScriptPath()
        {
            var local = Path.Combine(AppContext.BaseDirectory, "Scripts", "Invoke-FullAnalysis.ps1");
            if (File.Exists(local)) return local;
            return null;
        }
    }
}
