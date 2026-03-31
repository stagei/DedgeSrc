using System.Text.Json;
using CursorDb2McpServer.Models;
using DedgeCommon;
using Microsoft.Extensions.Logging;

namespace CursorDb2McpServer.Services;

/// <summary>
/// Loads and resolves database connections from DatabasesV2.json.
/// Resolves catalog name to DedgeConnection.ConnectionKey for use with DedgeDbHandler.
/// </summary>
public sealed class DatabaseConfigService
{
    private const string DefaultConfigPath = @"C:\opt\src\DedgeSrc\DedgeSystemTools\Folders\DedgeCommon\Configfiles\DatabasesV2.json";

    private readonly ILogger<DatabaseConfigService> _logger;
    private readonly string _configPath;
    private List<DatabaseEntry>? _cachedEntries;

    public DatabaseConfigService(ILogger<DatabaseConfigService> logger)
    {
        _logger = logger;
        _configPath = Environment.GetEnvironmentVariable("DATABASES_CONFIG_PATH") ?? DefaultConfigPath;
    }

    /// <summary>
    /// Resolves a catalog name (e.g. BASISRAP, FKMTST) to DedgeConnection.ConnectionKey.
    /// Uses Application and Environment from DatabasesV2.json. FederatedDb is ignored.
    /// </summary>
    public DedgeConnection.ConnectionKey ResolveConnectionKey(string databaseName)
    {
        if (string.IsNullOrWhiteSpace(databaseName))
        {
            databaseName = "BASISRAP";
        }

        var entries = LoadConfig();

        var normalizedName = databaseName.Trim();
        foreach (var entry in entries)
        {
            if (!entry.IsActive)
            {
                continue;
            }

            foreach (var ap in entry.AccessPoints)
            {
                if (!ap.IsActive)
                {
                    continue;
                }

                if (string.Equals(ap.AccessPointType, "FederatedDb", StringComparison.OrdinalIgnoreCase))
                {
                    continue;
                }

                if (!string.Equals(ap.AccessPointType, "PrimaryDb", StringComparison.OrdinalIgnoreCase) &&
                    !string.Equals(ap.AccessPointType, "Alias", StringComparison.OrdinalIgnoreCase))
                {
                    continue;
                }

                if (string.Equals(ap.CatalogName, normalizedName, StringComparison.OrdinalIgnoreCase))
                {
                    var app = Enum.TryParse<DedgeConnection.FkApplication>(entry.Application, ignoreCase: true, out var a)
                        ? a : throw new InvalidOperationException($"Unknown Application '{entry.Application}' in DatabasesV2.json");
                    var env = Enum.TryParse<DedgeConnection.FkEnvironment>(entry.Environment, ignoreCase: true, out var e)
                        ? e : throw new InvalidOperationException($"Unknown Environment '{entry.Environment}' in DatabasesV2.json");
                    var connectionKey = new DedgeConnection.ConnectionKey(app, env);
                    _logger.LogDebug("Resolved {CatalogName} to ConnectionKey: {Application}/{Environment}",
                        normalizedName, entry.Application, entry.Environment);
                    return connectionKey;
                }
            }
        }

        var available = string.Join(", ", entries
            .Where(e => e.IsActive)
            .SelectMany(e => e.AccessPoints)
            .Where(ap => ap.IsActive &&
                (string.Equals(ap.AccessPointType, "PrimaryDb", StringComparison.OrdinalIgnoreCase) ||
                 string.Equals(ap.AccessPointType, "Alias", StringComparison.OrdinalIgnoreCase)))
            .Select(ap => ap.CatalogName)
            .Distinct()
            .OrderBy(x => x));

        throw new InvalidOperationException(
            $"Database '{databaseName}' not found in {_configPath}. " +
            $"Available databases: {available}");
    }

    private List<DatabaseEntry> LoadConfig()
    {
        if (_cachedEntries is not null)
        {
            return _cachedEntries;
        }

        if (!File.Exists(_configPath))
        {
            throw new InvalidOperationException(
                $"DatabasesV2.json not found at {_configPath}. Set DATABASES_CONFIG_PATH environment variable.");
        }

        var json = File.ReadAllText(_configPath);
        var entries = JsonSerializer.Deserialize<List<DatabaseEntry>>(json);

        if (entries is null || entries.Count == 0)
        {
            throw new InvalidOperationException(
                $"DatabasesV2.json at {_configPath} is empty or invalid.");
        }

        _cachedEntries = entries;
        _logger.LogInformation("Loaded {Count} database entries from {Path}", entries.Count, _configPath);
        return _cachedEntries;
    }
}
