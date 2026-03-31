using System.Data;
using System.Text;
using System.Text.RegularExpressions;
using NLog;
using DbExplorer.Data;
using DbExplorer.Services.AI;

namespace DbExplorer.Services;

/// <summary>
/// Builds prompts with DB context (provider + table/column metadata), calls Ollama for SQL modification, and parses the response.
/// </summary>
public class SqlEditAiService
{
    private static readonly Logger Logger = LogManager.GetCurrentClassLogger();
    private readonly MetadataHandler _metadataHandler;
    private readonly SqlScopeParser _scopeParser = new();

    public SqlEditAiService(MetadataHandler metadataHandler)
    {
        _metadataHandler = metadataHandler ?? throw new ArgumentNullException(nameof(metadataHandler));
    }

    /// <summary>
    /// Get provider and version from connection (same pattern as CliCommandHandlerService).
    /// </summary>
    public static (string provider, string version) GetProviderAndVersion(IConnectionManager connectionManager)
    {
        var provider = connectionManager.ConnectionInfo.ProviderType?.ToUpperInvariant() ?? "DB2";
        var version = provider switch { "POSTGRESQL" => "18", "SQLITE" => "3", _ => "12.1" };
        return (provider, version);
    }

    /// <summary>
    /// Replace first ? with first value, second ? with second value, etc.
    /// </summary>
    private static string ReplaceParameters(string sql, params string[] values)
    {
        foreach (var value in values)
        {
            var index = sql.IndexOf('?');
            if (index < 0) break;
            sql = sql.Substring(0, index) + value + sql.Substring(index + 1);
        }
        return sql;
    }

    /// <summary>
    /// Build table/column context string for all tables in the selected SQL (and optionally extra table names).
    /// </summary>
    public async Task<string> BuildTableColumnContextAsync(
        IConnectionManager connectionManager,
        string selectedSql,
        IReadOnlyList<string>? additionalTableNames = null,
        CancellationToken cancellationToken = default)
    {
        var (provider, version) = GetProviderAndVersion(connectionManager);
        var tables = new HashSet<string>(StringComparer.OrdinalIgnoreCase);

        // Parse SQL and collect table references from main scope
        try
        {
            var scopes = _scopeParser.Parse(selectedSql);
            if (scopes.Count > 0)
            {
                foreach (var t in scopes[0].Tables.Where(x => !x.IsDerivedTable && !string.IsNullOrEmpty(x.TableName)))
                {
                    var fullName = string.IsNullOrEmpty(t.Schema) ? t.TableName! : $"{t.Schema}.{t.TableName}";
                    tables.Add(fullName);
                }
            }
        }
        catch (Exception ex)
        {
            Logger.Warn(ex, "SqlScopeParser failed for context; continuing without parsed tables");
        }

        if (additionalTableNames != null)
        {
            foreach (var name in additionalTableNames)
                if (!string.IsNullOrWhiteSpace(name))
                    tables.Add(name.Trim());
        }

        if (tables.Count == 0)
        {
            Logger.Debug("No tables found in SQL for context");
            return "No table metadata available (no tables parsed from SQL).";
        }

        var sb = new StringBuilder();
        string statementKey = "GetTableColumns_Display";

        foreach (var fullName in tables)
        {
            string schema;
            string tableName;
            var dot = fullName.IndexOf('.');
            if (dot > 0)
            {
                schema = fullName.Substring(0, dot).Trim();
                tableName = fullName.Substring(dot + 1).Trim();
            }
            else
            {
                schema = "";
                tableName = fullName.Trim();
            }

            try
            {
                var sql = _metadataHandler.GetQuery(provider, version, statementKey);
                sql = ReplaceParameters(sql, schema, tableName);
                var data = await connectionManager.ExecuteQueryAsync(sql, null, 0, true);
                var columnNames = data.AsEnumerable()
                    .Select(row => (row["ColumnName"]?.ToString()?.Trim()) ?? (row.Table.Columns.Count > 0 ? row[0]?.ToString()?.Trim() : ""))
                    .Where(s => !string.IsNullOrEmpty(s))
                    .ToList();
                if (columnNames.Count > 0)
                    sb.AppendLine($"Table {fullName}: {string.Join(", ", columnNames)}");
                else
                    sb.AppendLine($"Table {fullName}: (no columns retrieved)");
            }
            catch (Exception ex)
            {
                Logger.Debug(ex, "Could not load columns for {Table}", fullName);
                sb.AppendLine($"Table {fullName}: (unable to load columns: {ex.Message})");
            }
        }

        return sb.ToString().TrimEnd();
    }

    /// <summary>
    /// Call Ollama to modify the SQL according to the user instruction. Returns the modified SQL or error message.
    /// </summary>
    public async Task<string> ModifySqlAsync(
        string selectedSql,
        string userInstruction,
        IConnectionManager connectionManager,
        string? modelOverride = null,
        CancellationToken cancellationToken = default)
    {
        var (provider, version) = GetProviderAndVersion(connectionManager);
        var context = await BuildTableColumnContextAsync(connectionManager, selectedSql, null, cancellationToken);

        var systemPrompt = $"You are a SQL expert for {provider} {version}. " +
            "Modify the following SQL according to the user's instruction. " +
            "Return only the modified SQL statement, no explanation and no markdown code fences.";

        var userPrompt = $"Database: {provider} {version}. Schema context:\n{context}\n\n" +
            "Original SQL:\n" + selectedSql + "\n\n" +
            "User instruction: " + userInstruction + "\n\n" +
            "Modified SQL:";

        var fullPrompt = systemPrompt + "\n\n" + userPrompt;
        Logger.Debug("SqlEditAiService prompt length: {Length}", fullPrompt.Length);

        var options = new AiGenerationOptions
        {
            Model = modelOverride ?? App.PreferencesService?.Preferences.SqlEditModel ?? "defog-llama3-sqlcoder-8b",
            Temperature = 0.2,
            MaxTokens = 4096
        };

        var ollama = new OllamaProvider();
        var response = await ollama.GenerateAsync(fullPrompt, options);
        var newSql = ExtractSqlFromResponse(response);
        Logger.Info("SqlEditAiService returned {Length} chars", newSql?.Length ?? 0);
        return newSql ?? response;
    }

    /// <summary>
    /// Extract a single SQL statement from LLM response (strip markdown fences, trim).
    /// </summary>
    public static string? ExtractSqlFromResponse(string response)
    {
        if (string.IsNullOrWhiteSpace(response))
            return null;

        var text = response.Trim();

        // Remove ```sql ... ``` or ``` ... ```
        var fenceMatch = Regex.Match(text, @"^\s*```(?:\w*)\s*\n?(.*?)\n?```", RegexOptions.Singleline);
        if (fenceMatch.Success)
            text = fenceMatch.Groups[1].Value.Trim();

        // Take first contiguous block of lines that look like SQL (stop at empty line or "Error:")
        var lines = text.Split('\n');
        var sb = new StringBuilder();
        foreach (var line in lines)
        {
            if (string.IsNullOrWhiteSpace(line) && sb.Length > 0)
                break;
            if (line.TrimStart().StartsWith("Error:", StringComparison.OrdinalIgnoreCase))
                break;
            sb.AppendLine(line);
        }

        var result = sb.ToString().Trim();
        return string.IsNullOrEmpty(result) ? null : result;
    }
}
