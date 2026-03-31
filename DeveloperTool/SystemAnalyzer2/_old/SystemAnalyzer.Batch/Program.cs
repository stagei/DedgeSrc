using Microsoft.Extensions.Configuration;
using SystemAnalyzer.Batch.Services;
using SystemAnalyzer.Core.Models;

var configuration = new ConfigurationBuilder()
    .SetBasePath(AppContext.BaseDirectory)
    .AddJsonFile("appsettings.json", optional: false)
    .AddEnvironmentVariables()
    .Build();

var options = new SystemAnalyzerOptions();
configuration.GetSection("SystemAnalyzer").Bind(options);

var aliasArg = GetArg(args, "--alias");
var allJsonArg = GetArg(args, "--all-json");
var skipClassification = args.Contains("--skip-classification", StringComparer.OrdinalIgnoreCase);
var skipPhasesArg = GetArg(args, "--skip-phases");
var skipPhases = new List<int>();
if (!string.IsNullOrWhiteSpace(skipPhasesArg))
{
    foreach (var part in skipPhasesArg.Split(',', StringSplitOptions.RemoveEmptyEntries | StringSplitOptions.TrimEntries))
    {
        if (int.TryParse(part, out var phase)) skipPhases.Add(phase);
    }
}

if (string.IsNullOrWhiteSpace(allJsonArg))
{
    allJsonArg = Path.Combine(Environment.CurrentDirectory, "all.json");
}

if (!File.Exists(allJsonArg))
{
    Console.Error.WriteLine($"all.json not found: {allJsonArg}");
    return 1;
}

if (string.IsNullOrWhiteSpace(aliasArg))
{
    var suggested = "Analysis";
    try
    {
        var doc = System.Text.Json.JsonDocument.Parse(File.ReadAllText(allJsonArg));
        if (doc.RootElement.TryGetProperty("entries", out var entries) && entries.ValueKind == System.Text.Json.JsonValueKind.Array)
        {
            var areas = entries.EnumerateArray()
                .Select(e => e.TryGetProperty("area", out var a) ? a.GetString() : null)
                .Where(a => !string.IsNullOrWhiteSpace(a))
                .Distinct(StringComparer.OrdinalIgnoreCase)
                .OrderBy(a => a, StringComparer.OrdinalIgnoreCase)
                .ToArray();
            if (areas.Length > 0)
            {
                suggested = string.Join("_", areas);
            }
        }
    }
    catch
    {
    }

    Console.Write($"Analysis alias [{suggested}]: ");
    var input = Console.ReadLine();
    aliasArg = string.IsNullOrWhiteSpace(input) ? suggested : input.Trim();
}

var request = new AnalysisRunRequest
{
    Alias = aliasArg!,
    AllJsonPath = allJsonArg!,
    SkipClassification = skipClassification,
    SkipPhases = skipPhases,
    Options = options
};

var runner = new PowerShellPipelineRunner();
var exitCode = await runner.RunInvokeFullAnalysisAsync(request);
return exitCode;

static string? GetArg(string[] args, string key)
{
    for (var i = 0; i < args.Length - 1; i++)
    {
        if (string.Equals(args[i], key, StringComparison.OrdinalIgnoreCase))
        {
            return args[i + 1];
        }
    }
    return null;
}
