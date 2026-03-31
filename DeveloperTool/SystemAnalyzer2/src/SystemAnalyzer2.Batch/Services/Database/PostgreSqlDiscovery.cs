using System.Text.Json;
using System.Text.Json.Nodes;
using NLog;
using Npgsql;

namespace SystemAnalyzer2.Batch.Services.Database;

/// <summary>information_schema export for PostgreSQL. Connection string from env <c>SA_POSTGRES_{connectionName}</c> or <paramref name="connectionString"/>.</summary>
public sealed class PostgreSqlDiscovery : IDatabaseDiscovery
{
    private static readonly Logger Logger = LogManager.GetCurrentClassLogger();
    private readonly string _connectionString;
    private readonly string _alias;

    public PostgreSqlDiscovery(string connectionName, string? connectionString = null)
    {
        _alias = connectionName;
        _connectionString = connectionString
            ?? Environment.GetEnvironmentVariable($"SA_POSTGRES_{connectionName}") ?? "";
    }

    public string DatabaseKind => "postgresql";

    public async Task ExportCatalogAsync(string outputDir, CancellationToken ct = default)
    {
        if (string.IsNullOrWhiteSpace(_connectionString))
        {
            Logger.Warn($"PostgreSQL '{_alias}': no connection string (set SA_POSTGRES_{_alias} or pass constructor).");
            return;
        }

        Directory.CreateDirectory(outputDir);
        await using var conn = new NpgsqlConnection(_connectionString);
        await conn.OpenAsync(ct);

        const string q = """
            SELECT table_schema, table_name, table_type
            FROM information_schema.tables
            WHERE table_schema NOT IN ('pg_catalog','information_schema')
            ORDER BY table_schema, table_name
            """;

        var tables = new JsonArray();
        await using (var cmd = new NpgsqlCommand(q, conn))
        await using (var r = await cmd.ExecuteReaderAsync(ct))
        {
            while (await r.ReadAsync(ct))
            {
                tables.Add(new JsonObject
                {
                    ["schema"] = r.GetString(0),
                    ["name"] = r.GetString(1),
                    ["type"] = r.GetString(2)
                });
            }
        }

        var payload = new JsonObject { ["databaseKind"] = "postgresql", ["alias"] = _alias, ["tables"] = tables };
        var path = Path.Combine(outputDir, $"{Sanitize(_alias)}_tables.json");
        await File.WriteAllTextAsync(path, payload.ToJsonString(new JsonSerializerOptions { WriteIndented = true }), ct);
        Logger.Info($"PostgreSQL catalog: {tables.Count} tables -> {path}");

        const string qc = """
            SELECT table_schema, table_name, column_name, data_type, ordinal_position
            FROM information_schema.columns
            WHERE table_schema NOT IN ('pg_catalog','information_schema')
            ORDER BY table_schema, table_name, ordinal_position
            """;
        var columns = new JsonArray();
        await using (var cmd = new NpgsqlCommand(qc, conn))
        await using (var r = await cmd.ExecuteReaderAsync(ct))
        {
            while (await r.ReadAsync(ct))
            {
                columns.Add(new JsonObject
                {
                    ["schema"] = r.GetString(0),
                    ["table"] = r.GetString(1),
                    ["column"] = r.GetString(2),
                    ["dataType"] = r.GetString(3),
                    ["ordinal"] = r.GetInt32(4)
                });
            }
        }

        var colPayload = new JsonObject { ["databaseKind"] = "postgresql", ["alias"] = _alias, ["columns"] = columns };
        var colPath = Path.Combine(outputDir, $"{Sanitize(_alias)}_columns.json");
        await File.WriteAllTextAsync(colPath, colPayload.ToJsonString(new JsonSerializerOptions { WriteIndented = true }), ct);
        Logger.Info($"PostgreSQL columns: {columns.Count} -> {colPath}");
    }

    private static string Sanitize(string s) =>
        string.IsNullOrEmpty(s) ? "pg" : new string(s.Select(c => char.IsLetterOrDigit(c) ? c : '_').ToArray());
}
