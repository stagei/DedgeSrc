using System.ComponentModel;
using System.Data;
using System.Text.Json;
using System.Text.RegularExpressions;
using CursorDb2McpServer.Services;
using DedgeCommon;
using Microsoft.Extensions.Logging;
using ModelContextProtocol.Server;

namespace CursorDb2McpServer.Tools;

[McpServerToolType]
public sealed class Db2QueryTool
{
    private static readonly string[] ForbiddenKeywords =
    [
        "INSERT", "UPDATE", "DELETE", "DROP", "CREATE", "ALTER", "TRUNCATE", "MERGE", "GRANT", "REVOKE"
    ];

    private const string ConnectionVerifySql =
        "SELECT CURRENT SERVER AS DatabaseName, CURRENT USER AS CurrentUser FROM SYSIBM.SYSDUMMY1";

    private readonly DatabaseConfigService _configService;
    private readonly ILogger<Db2QueryTool> _logger;

    public Db2QueryTool(DatabaseConfigService configService, ILogger<Db2QueryTool> logger)
    {
        _configService = configService;
        _logger = logger;
    }

    [McpServerTool]
    [Description("Execute a read-only SQL query against a DB2 database. Returns results with database name and current user for verification.")]
    public string QueryDb2(
        [Description("Database catalog name (e.g. BASISRAP, FKMTST). Default: BASISRAP when empty.")] string databaseName,
        [Description("SQL query (SELECT, WITH ... SELECT, or VALUES only).")] string query)
    {
        if (string.IsNullOrWhiteSpace(query))
        {
            return JsonSerializer.Serialize(new { error = "Query cannot be empty." });
        }

        var normalizedQuery = query.Trim();
        if (!IsReadOnlyQuery(normalizedQuery))
        {
            return JsonSerializer.Serialize(new
            {
                error = "Only SELECT, WITH ... SELECT, or VALUES statements are allowed. Write operations are not permitted."
            });
        }

        foreach (var kw in ForbiddenKeywords)
        {
            if (ContainsForbiddenKeyword(normalizedQuery, kw))
            {
                return JsonSerializer.Serialize(new
                {
                    error = $"Query contains forbidden keyword: {kw}. Read-only access only."
                });
            }
        }

        try
        {
            var connectionKey = _configService.ResolveConnectionKey(databaseName ?? string.Empty);
            using var dbHandler = DedgeDbHandler.Create(connectionKey);

            var verifyTable = dbHandler.ExecuteQueryAsDataTable(ConnectionVerifySql);
            string database = "";
            string currentUser = "";
            if (verifyTable.Rows.Count > 0)
            {
                var row = verifyTable.Rows[0];
                database = row["DatabaseName"]?.ToString()?.Trim() ?? "";
                currentUser = row["CurrentUser"]?.ToString()?.Trim() ?? "";
            }

            var queryTable = dbHandler.ExecuteQueryAsDataTable(normalizedQuery);
            var rows = new List<Dictionary<string, object?>>();

            foreach (DataRow row in queryTable.Rows)
            {
                var dict = new Dictionary<string, object?>();
                foreach (DataColumn col in queryTable.Columns)
                {
                    var val = row[col];
                    dict[col.ColumnName] = val == DBNull.Value ? null : val;
                }
                rows.Add(dict);
            }

            var result = new
            {
                database,
                currentUser,
                rows
            };

            _logger.LogDebug("Query returned {RowCount} rows from {Database} as {CurrentUser}",
                rows.Count, database, currentUser);

            return JsonSerializer.Serialize(result);
        }
        catch (Exception ex)
        {
            _logger.LogError(ex, "Error during query execution");
            return JsonSerializer.Serialize(new { error = ex.Message });
        }
    }

    private static bool IsReadOnlyQuery(string sql)
    {
        var trimmed = sql.TrimStart();
        if (trimmed.StartsWith("--"))
        {
            var nl = trimmed.IndexOf('\n');
            trimmed = nl >= 0 ? trimmed[(nl + 1)..].TrimStart() : "";
        }

        if (trimmed.StartsWith("/*"))
        {
            var end = trimmed.IndexOf("*/", StringComparison.Ordinal);
            trimmed = end >= 0 ? trimmed[(end + 2)..].TrimStart() : "";
        }

        return trimmed.StartsWith("SELECT", StringComparison.OrdinalIgnoreCase) ||
               trimmed.StartsWith("WITH", StringComparison.OrdinalIgnoreCase) ||
               trimmed.StartsWith("VALUES", StringComparison.OrdinalIgnoreCase);
    }

    private static bool ContainsForbiddenKeyword(string sql, string keyword)
    {
        var pattern = $@"\b{Regex.Escape(keyword)}\b";
        return Regex.IsMatch(sql, pattern, RegexOptions.IgnoreCase);
    }
}
