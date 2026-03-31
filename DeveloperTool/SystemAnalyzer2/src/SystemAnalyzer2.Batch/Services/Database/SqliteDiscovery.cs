using System.Text.Json;
using System.Text.Json.Nodes;
using Microsoft.Data.Sqlite;
using NLog;

namespace SystemAnalyzer2.Batch.Services.Database;

public sealed class SqliteDiscovery : IDatabaseDiscovery
{
    private static readonly Logger Logger = LogManager.GetCurrentClassLogger();
    private readonly string _databasePath;
    private readonly string _alias;

    public SqliteDiscovery(string alias, string databasePath)
    {
        _alias = alias;
        _databasePath = databasePath;
    }

    public string DatabaseKind => "sqlite";

    public async Task ExportCatalogAsync(string outputDir, CancellationToken ct = default)
    {
        if (string.IsNullOrWhiteSpace(_databasePath) || !File.Exists(_databasePath))
        {
            Logger.Warn($"SQLite '{_alias}': file not found: {_databasePath}");
            return;
        }

        Directory.CreateDirectory(outputDir);
        var cs = $"Data Source={_databasePath}";
        await using var conn = new SqliteConnection(cs);
        await conn.OpenAsync(ct);

        const string q = "SELECT name, type FROM sqlite_master WHERE type IN ('table','view') ORDER BY name";
        var tables = new JsonArray();
        await using (var cmd = conn.CreateCommand())
        {
            cmd.CommandText = q;
            await using var r = await cmd.ExecuteReaderAsync(ct);
            while (await r.ReadAsync(ct))
            {
                tables.Add(new JsonObject
                {
                    ["name"] = r.GetString(0),
                    ["type"] = r.GetString(1)
                });
            }
        }

        var payload = new JsonObject { ["databaseKind"] = "sqlite", ["alias"] = _alias, ["tables"] = tables };
        var path = Path.Combine(outputDir, $"{Sanitize(_alias)}_tables.json");
        await File.WriteAllTextAsync(path, payload.ToJsonString(new JsonSerializerOptions { WriteIndented = true }), ct);
        Logger.Info($"SQLite catalog: {tables.Count} objects -> {path}");

        var columns = new JsonArray();
        foreach (var row in tables)
        {
            var tname = row?["name"]?.GetValue<string>();
            if (string.IsNullOrEmpty(tname)) continue;
            await using var cmd = conn.CreateCommand();
            var qName = tname.Replace("\"", "\"\"", StringComparison.Ordinal);
            cmd.CommandText = $"PRAGMA table_info(\"{qName}\")";
            await using var r = await cmd.ExecuteReaderAsync(ct);
            while (await r.ReadAsync(ct))
            {
                columns.Add(new JsonObject
                {
                    ["table"] = tname,
                    ["column"] = r.GetString(1),
                    ["dataType"] = r.GetString(2)
                });
            }
        }

        var colPayload = new JsonObject { ["databaseKind"] = "sqlite", ["alias"] = _alias, ["columns"] = columns };
        var colPath = Path.Combine(outputDir, $"{Sanitize(_alias)}_columns.json");
        await File.WriteAllTextAsync(colPath, colPayload.ToJsonString(new JsonSerializerOptions { WriteIndented = true }), ct);
        Logger.Info($"SQLite columns: {columns.Count} -> {colPath}");
    }

    private static string Sanitize(string s) =>
        string.IsNullOrEmpty(s) ? "sqlite" : new string(s.Select(c => char.IsLetterOrDigit(c) ? c : '_').ToArray());
}
