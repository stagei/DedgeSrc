using System.Net.Http.Json;
using System.Text;
using System.Text.Json;
using IBM.Data.Db2;
using NLog;

namespace SystemAnalyzer.Batch.Services;

public sealed class Db2Client : IDisposable
{
    private static readonly Logger Logger = LogManager.GetCurrentClassLogger();

    private readonly string _dsn;
    private DB2Connection? _connection;

    public Db2Client(string dsn)
    {
        _dsn = dsn;
    }

    public bool TryConnect()
    {
        if (string.IsNullOrEmpty(_dsn)) return false;
        try
        {
            _connection = new DB2Connection($"Database={_dsn};");
            _connection.Open();
            Logger.Info($"DB2 connected to {_dsn}");
            return true;
        }
        catch (Exception ex)
        {
            Logger.Warn($"DB2 connection failed ({_dsn}): {ex.Message}");
            _connection = null;
            return false;
        }
    }

    public bool IsConnected => _connection?.State == System.Data.ConnectionState.Open;

    public List<Dictionary<string, string?>> ExecuteQuery(string sql)
    {
        if (_connection == null || _connection.State != System.Data.ConnectionState.Open)
            return [];

        using var cmd = _connection.CreateCommand();
        cmd.CommandText = sql;
        cmd.CommandTimeout = 60;

        try
        {
            using var reader = cmd.ExecuteReader();
            var results = new List<Dictionary<string, string?>>();
            while (reader.Read())
            {
                var row = new Dictionary<string, string?>(StringComparer.OrdinalIgnoreCase);
                for (int i = 0; i < reader.FieldCount; i++)
                {
                    row[reader.GetName(i)] = reader.IsDBNull(i) ? null : reader.GetValue(i).ToString()?.Trim();
                }
                results.Add(row);
            }
            return results;
        }
        catch (Exception ex)
        {
            Logger.Warn($"DB2 query failed: {ex.Message}");
            return [];
        }
    }

    public async Task<List<Dictionary<string, string?>>> ExecuteQueryViaMcpAsync(
        string sql, string databaseName, HttpClient httpClient)
    {
        const string mcpUrl = "http://dedge-server/CursorDb2McpServer/";
        try
        {
            // Step 1: Initialize MCP session
            var initBody = new
            {
                jsonrpc = "2.0", id = 1, method = "initialize",
                @params = new
                {
                    protocolVersion = "2024-11-05",
                    capabilities = new { },
                    clientInfo = new { name = "SystemAnalyzer-Batch", version = "2.0" }
                }
            };
            var initRequest = new HttpRequestMessage(HttpMethod.Post, mcpUrl)
            {
                Content = new StringContent(JsonSerializer.Serialize(initBody), Encoding.UTF8, "application/json")
            };
            initRequest.Headers.Accept.ParseAdd("application/json");
            initRequest.Headers.Accept.ParseAdd("text/event-stream");

            var initResponse = await httpClient.SendAsync(initRequest);
            if (!initResponse.IsSuccessStatusCode)
            {
                var initText = await initResponse.Content.ReadAsStringAsync();
                Logger.Warn($"MCP init failed: HTTP {(int)initResponse.StatusCode} — {initText[..Math.Min(200, initText.Length)]}");
                return [];
            }

            string? sessionId = null;
            if (initResponse.Headers.TryGetValues("Mcp-Session-Id", out var sessionValues))
                sessionId = sessionValues.FirstOrDefault();

            // Step 2: Call query_db2 tool
            var queryBody = new
            {
                jsonrpc = "2.0", id = 2, method = "tools/call",
                @params = new
                {
                    name = "query_db2",
                    arguments = new { databaseName, query = sql }
                }
            };
            var queryRequest = new HttpRequestMessage(HttpMethod.Post, mcpUrl)
            {
                Content = new StringContent(JsonSerializer.Serialize(queryBody), Encoding.UTF8, "application/json")
            };
            queryRequest.Headers.Accept.ParseAdd("application/json");
            queryRequest.Headers.Accept.ParseAdd("text/event-stream");
            if (sessionId != null)
                queryRequest.Headers.Add("Mcp-Session-Id", sessionId);

            var queryResponse = await httpClient.SendAsync(queryRequest);
            var responseText = await queryResponse.Content.ReadAsStringAsync();

            if (!queryResponse.IsSuccessStatusCode)
            {
                Logger.Warn($"MCP query failed: HTTP {(int)queryResponse.StatusCode} — {responseText[..Math.Min(200, responseText.Length)]}");
                return [];
            }

            // The server may return SSE (text/event-stream) or plain JSON depending
            // on the Accept header. Extract JSON from SSE data: lines if needed.
            var jsonText = ExtractJsonFromResponse(responseText);
            if (string.IsNullOrEmpty(jsonText))
            {
                Logger.Warn($"MCP returned empty/unparseable response for {databaseName}");
                return [];
            }

            using var doc = JsonDocument.Parse(jsonText);
            var root = doc.RootElement;

            if (root.TryGetProperty("error", out var rpcError))
            {
                Logger.Warn($"MCP JSON-RPC error: {rpcError}");
                return [];
            }

            if (!root.TryGetProperty("result", out var result)) return [];
            if (!result.TryGetProperty("content", out var contentArr)) return [];

            foreach (var item in contentArr.EnumerateArray())
            {
                if (!item.TryGetProperty("type", out var typeEl) || typeEl.GetString() != "text") continue;
                if (!item.TryGetProperty("text", out var textEl)) continue;
                var textPayload = textEl.GetString();
                if (textPayload == null) continue;

                using var payload = JsonDocument.Parse(textPayload);
                if (payload.RootElement.TryGetProperty("error", out var err))
                {
                    Logger.Warn($"MCP DB2 error: {err}");
                    return [];
                }
                if (payload.RootElement.TryGetProperty("rows", out var rows))
                    return DeserializeRows(rows);
            }
            return [];
        }
        catch (Exception ex)
        {
            Logger.Warn($"MCP DB2 query failed ({databaseName}): {ex.Message}");
            return [];
        }
    }

    /// <summary>
    /// If the response is SSE (text/event-stream), extract JSON from "data:" lines.
    /// If it's already plain JSON (starts with '{'), return as-is.
    /// </summary>
    private static string? ExtractJsonFromResponse(string responseText)
    {
        if (string.IsNullOrWhiteSpace(responseText))
            return null;

        var trimmed = responseText.TrimStart();
        if (trimmed.StartsWith('{') || trimmed.StartsWith('['))
            return trimmed;

        // SSE format: lines like "event: message\ndata: {json}\n\n"
        foreach (var line in responseText.Split('\n'))
        {
            var l = line.Trim();
            if (l.StartsWith("data:", StringComparison.OrdinalIgnoreCase))
            {
                var json = l["data:".Length..].Trim();
                if (json.StartsWith('{') || json.StartsWith('['))
                    return json;
            }
        }

        return null;
    }

    public async Task<List<Dictionary<string, string?>>> ExecuteQueryAnyAsync(
        string sql, string databaseName, HttpClient httpClient)
    {
        if (IsConnected)
            return ExecuteQuery(sql);
        return await ExecuteQueryViaMcpAsync(sql, databaseName, httpClient);
    }

    /// <summary>
    /// Execute a query against a specific database, matching V1's per-database ODBC pattern.
    /// Tries: 1) shared connection (if connected to this DB), 2) dedicated ODBC DSN={database},
    /// 3) MCP fallback.
    /// </summary>
    public async Task<List<Dictionary<string, string?>>> ExecuteQueryForDatabaseAsync(
        string sql, string database, HttpClient httpClient)
    {
        if (IsConnected && _dsn.Equals(database, StringComparison.OrdinalIgnoreCase))
            return ExecuteQuery(sql);

        var rows = TryExecuteWithDedicatedOdbc(sql, database);
        if (rows.Count > 0)
            return rows;

        return await ExecuteQueryViaMcpAsync(sql, database, httpClient);
    }

    private static List<Dictionary<string, string?>> TryExecuteWithDedicatedOdbc(string sql, string database)
    {
        DB2Connection? conn = null;
        try
        {
            conn = new DB2Connection($"Database={database};");
            conn.Open();
            Logger.Info($"  Per-database ODBC connected: DSN={database}");

            using var cmd = conn.CreateCommand();
            cmd.CommandText = sql;
            cmd.CommandTimeout = 120;

            using var reader = cmd.ExecuteReader();
            var results = new List<Dictionary<string, string?>>();
            while (reader.Read())
            {
                var row = new Dictionary<string, string?>(StringComparer.OrdinalIgnoreCase);
                for (int i = 0; i < reader.FieldCount; i++)
                    row[reader.GetName(i)] = reader.IsDBNull(i) ? null : reader.GetValue(i).ToString()?.Trim();
                results.Add(row);
            }
            Logger.Info($"  Per-database ODBC query returned {results.Count} rows from {database}");
            return results;
        }
        catch (Exception ex)
        {
            Logger.Warn($"  Per-database ODBC failed (DSN={database}): {ex.Message}");
            return [];
        }
        finally
        {
            if (conn?.State == System.Data.ConnectionState.Open) conn.Close();
            conn?.Dispose();
        }
    }

    private static List<Dictionary<string, string?>> DeserializeRows(JsonElement rows)
    {
        var result = new List<Dictionary<string, string?>>();
        foreach (var row in rows.EnumerateArray())
        {
            var dict = new Dictionary<string, string?>(StringComparer.OrdinalIgnoreCase);
            foreach (var prop in row.EnumerateObject())
            {
                dict[prop.Name] = prop.Value.ValueKind == JsonValueKind.Null
                    ? null
                    : prop.Value.ToString().Trim();
            }
            result.Add(dict);
        }
        return result;
    }

    public void Dispose()
    {
        _connection?.Close();
        _connection?.Dispose();
    }
}
