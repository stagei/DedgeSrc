using System.Text.Json;
using System.Text.Json.Nodes;
using Microsoft.Data.SqlClient;
using NLog;

namespace SystemAnalyzer2.Batch.Services.Database;

public sealed class SqlServerDiscovery : IDatabaseDiscovery
{
    private static readonly Logger Logger = LogManager.GetCurrentClassLogger();
    private readonly string _connectionString;
    private readonly string _alias;

    public SqlServerDiscovery(string connectionName, string? connectionString = null)
    {
        _alias = connectionName;
        _connectionString = connectionString
            ?? Environment.GetEnvironmentVariable($"SA_MSSQL_{connectionName}") ?? "";
    }

    public string DatabaseKind => "sqlserver";

    public async Task ExportCatalogAsync(string outputDir, CancellationToken ct = default)
    {
        if (string.IsNullOrWhiteSpace(_connectionString))
        {
            Logger.Warn($"SQL Server '{_alias}': no connection string (set SA_MSSQL_{_alias}).");
            return;
        }

        Directory.CreateDirectory(outputDir);
        await using var conn = new SqlConnection(_connectionString);
        await conn.OpenAsync(ct);

        const string q = """
            SELECT TABLE_SCHEMA, TABLE_NAME, TABLE_TYPE
            FROM INFORMATION_SCHEMA.TABLES
            ORDER BY TABLE_SCHEMA, TABLE_NAME
            """;

        var tables = new JsonArray();
        await using (var cmd = new SqlCommand(q, conn))
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

        var payload = new JsonObject { ["databaseKind"] = "sqlserver", ["alias"] = _alias, ["tables"] = tables };
        var path = Path.Combine(outputDir, $"{Sanitize(_alias)}_tables.json");
        await File.WriteAllTextAsync(path, payload.ToJsonString(new JsonSerializerOptions { WriteIndented = true }), ct);
        Logger.Info($"SQL Server catalog: {tables.Count} tables -> {path}");

        const string qc = """
            SELECT TABLE_SCHEMA, TABLE_NAME, COLUMN_NAME, DATA_TYPE, ORDINAL_POSITION
            FROM INFORMATION_SCHEMA.COLUMNS
            ORDER BY TABLE_SCHEMA, TABLE_NAME, ORDINAL_POSITION
            """;
        var columns = new JsonArray();
        await using (var cmd = new SqlCommand(qc, conn))
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

        var colPayload = new JsonObject { ["databaseKind"] = "sqlserver", ["alias"] = _alias, ["columns"] = columns };
        var colPath = Path.Combine(outputDir, $"{Sanitize(_alias)}_columns.json");
        await File.WriteAllTextAsync(colPath, colPayload.ToJsonString(new JsonSerializerOptions { WriteIndented = true }), ct);
        Logger.Info($"SQL Server columns: {columns.Count} -> {colPath}");
    }

    private static string Sanitize(string s) =>
        string.IsNullOrEmpty(s) ? "mssql" : new string(s.Select(c => char.IsLetterOrDigit(c) ? c : '_').ToArray());
}
