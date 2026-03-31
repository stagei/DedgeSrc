using System.Text.Json;
using Microsoft.Extensions.Logging;
using GenericLogHandler.Core.Models;

namespace GenericLogHandler.ImportService.Services;

/// <summary>
/// Loads and caches program metadata from AutoDocJson files (*.CBL.json, *.REX.json)
/// to enrich WKMONIT log entries with program type, system, and documentation links.
/// Thread-safe singleton; scans the folder once on first access.
/// </summary>
public class WkmonitMetadataService
{
    private readonly ILogger<WkmonitMetadataService> _logger;
    private readonly string _autoDocJsonPath;
    private Dictionary<string, WkmonitProgramInfo>? _cache;
    private readonly object _loadLock = new();

    public WkmonitMetadataService(ILogger<WkmonitMetadataService> logger)
    {
        _logger = logger;
        var optPath = Environment.GetEnvironmentVariable("OptPath") ?? @"C:\opt";
        _autoDocJsonPath = Path.Combine(optPath, "Webs", "AutoDocJson");
    }

    public bool TryGetProgramInfo(string programName, out WkmonitProgramInfo? info)
    {
        EnsureLoaded();
        return _cache!.TryGetValue(programName.ToUpperInvariant(), out info);
    }

    private void EnsureLoaded()
    {
        if (_cache != null) return;
        lock (_loadLock)
        {
            if (_cache != null) return;
            _cache = LoadMetadata();
        }
    }

    private Dictionary<string, WkmonitProgramInfo> LoadMetadata()
    {
        var dict = new Dictionary<string, WkmonitProgramInfo>(StringComparer.OrdinalIgnoreCase);

        if (!Directory.Exists(_autoDocJsonPath))
        {
            _logger.LogWarning("AutoDocJson folder not found at {Path}, WKMONIT metadata enrichment disabled", _autoDocJsonPath);
            return dict;
        }

        var extensions = new[] { ".CBL.json", ".REX.json" };
        int loaded = 0;

        foreach (var ext in extensions)
        {
            var sourceType = ext.StartsWith(".CBL") ? "CBL" : "REX";

            foreach (var file in Directory.EnumerateFiles(_autoDocJsonPath, $"*{ext}"))
            {
                try
                {
                    var fileName = Path.GetFileName(file);
                    var programName = fileName[..^ext.Length].ToUpperInvariant();

                    if (dict.ContainsKey(programName))
                        continue;

                    using var stream = File.OpenRead(file);
                    using var doc = JsonDocument.Parse(stream);
                    var root = doc.RootElement;

                    string typeLabel = "", system = "";
                    bool usesSql = false;

                    if (root.TryGetProperty("metadata", out var meta))
                    {
                        if (meta.TryGetProperty("typeLabel", out var tl))
                            typeLabel = tl.GetString() ?? "";
                        else if (meta.TryGetProperty("typeCode", out var tc))
                            typeLabel = tc.GetString() ?? "";

                        if (meta.TryGetProperty("system", out var sys))
                            system = sys.GetString() ?? "";

                        if (meta.TryGetProperty("usesSql", out var sql))
                            usesSql = sql.ValueKind == JsonValueKind.True;
                    }

                    dict[programName] = new WkmonitProgramInfo
                    {
                        ProgramName = programName,
                        TypeLabel = typeLabel,
                        System = system,
                        UsesSql = usesSql,
                        SourceType = sourceType,
                        AutoDocUrl = $"{programName}.{sourceType}.html"
                    };
                    loaded++;
                }
                catch (Exception ex)
                {
                    _logger.LogDebug(ex, "Failed to parse AutoDocJson file {File}", file);
                }
            }
        }

        _logger.LogInformation("Loaded {Count} WKMONIT program metadata entries from {Path}", loaded, _autoDocJsonPath);
        return dict;
    }
}
