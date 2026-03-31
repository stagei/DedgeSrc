using SqlMermaidErdTools.Converters;
using SqlMermaidErdTools.Models;
using SqlMermaidApi.Models;

namespace SqlMermaidApi.Services;

public interface IConversionService
{
    Task<ConversionResponse> ConvertSqlToMermaidAsync(string sql, bool includeAst, int tableLimit);
    Task<ConversionResponse> ConvertMermaidToSqlAsync(string mermaid, string dialect, bool includeAst, int tableLimit);
    Task<ConversionResponse> GenerateMigrationAsync(string beforeMermaid, string afterMermaid, string dialect, int tableLimit);
}

public class ConversionService : IConversionService
{
    private readonly ILogger<ConversionService> _logger;

    public ConversionService(ILogger<ConversionService> logger)
    {
        _logger = logger;
    }

    public async Task<ConversionResponse> ConvertSqlToMermaidAsync(string sql, bool includeAst, int tableLimit)
    {
        try
        {
            var converter = new SqlToMmdConverter();
            var result = await Task.Run(() => converter.Convert(sql));

            // Count tables
            var tableCount = CountTables(result);
            if (tableCount > tableLimit)
            {
                return new ConversionResponse
                {
                    Success = false,
                    Error = $"Table limit exceeded. Your license allows {tableLimit} tables, but this schema has {tableCount} tables. Upgrade to Pro or Enterprise for unlimited tables."
                };
            }

            string? ast = null;
            if (includeAst)
            {
                // AST would be in the export directory - for API we'd need to capture it differently
                ast = "AST export not yet implemented for API";
            }

            return new ConversionResponse
            {
                Success = true,
                Result = result,
                Ast = ast,
                Metadata = new ConversionMetadata
                {
                    TableCount = tableCount,
                    ColumnCount = CountColumns(result),
                    RelationshipCount = CountRelationships(result),
                    Dialect = "Input SQL"
                }
            };
        }
        catch (Exception ex)
        {
            _logger.LogError(ex, "SQL to Mermaid conversion failed");
            return new ConversionResponse
            {
                Success = false,
                Error = $"Conversion failed: {ex.Message}"
            };
        }
    }

    public async Task<ConversionResponse> ConvertMermaidToSqlAsync(string mermaid, string dialect, bool includeAst, int tableLimit)
    {
        try
        {
            // Count tables in input Mermaid
            var tableCount = CountTables(mermaid);
            if (tableCount > tableLimit)
            {
                return new ConversionResponse
                {
                    Success = false,
                    Error = $"Table limit exceeded. Your license allows {tableLimit} tables, but this schema has {tableCount} tables. Upgrade to Pro or Enterprise for unlimited tables."
                };
            }

            var sqlDialect = ParseDialect(dialect);
            var converter = new MmdToSqlConverter();
            var result = await Task.Run(() => converter.Convert(mermaid, sqlDialect));

            string? ast = null;
            if (includeAst)
            {
                ast = "AST export not yet implemented for API";
            }

            return new ConversionResponse
            {
                Success = true,
                Result = result,
                Ast = ast,
                Metadata = new ConversionMetadata
                {
                    TableCount = tableCount,
                    ColumnCount = 0,
                    RelationshipCount = 0,
                    Dialect = dialect
                }
            };
        }
        catch (Exception ex)
        {
            _logger.LogError(ex, "Mermaid to SQL conversion failed");
            return new ConversionResponse
            {
                Success = false,
                Error = $"Conversion failed: {ex.Message}"
            };
        }
    }

    public async Task<ConversionResponse> GenerateMigrationAsync(string beforeMermaid, string afterMermaid, string dialect, int tableLimit)
    {
        try
        {
            // Count tables
            var tableCount = Math.Max(CountTables(beforeMermaid), CountTables(afterMermaid));
            if (tableCount > tableLimit)
            {
                return new ConversionResponse
                {
                    Success = false,
                    Error = $"Table limit exceeded. Your license allows {tableLimit} tables, but this schema has {tableCount} tables."
                };
            }

            var sqlDialect = ParseDialect(dialect);
            var generator = new MmdDiffToSqlGenerator();
            var result = await Task.Run(() => generator.GenerateAlterStatements(beforeMermaid, afterMermaid, sqlDialect));

            return new ConversionResponse
            {
                Success = true,
                Result = result,
                Metadata = new ConversionMetadata
                {
                    TableCount = tableCount,
                    ColumnCount = 0,
                    RelationshipCount = 0,
                    Dialect = dialect
                }
            };
        }
        catch (Exception ex)
        {
            _logger.LogError(ex, "Migration generation failed");
            return new ConversionResponse
            {
                Success = false,
                Error = $"Migration generation failed: {ex.Message}"
            };
        }
    }

    private static int CountTables(string content)
    {
        if (string.IsNullOrWhiteSpace(content)) return 0;
        
        // Simple heuristic: count CREATE TABLE or entity names in Mermaid
        var createTableCount = System.Text.RegularExpressions.Regex.Matches(
            content, 
            @"CREATE\s+TABLE", 
            System.Text.RegularExpressions.RegexOptions.IgnoreCase).Count;
        
        var mermaidEntityCount = System.Text.RegularExpressions.Regex.Matches(
            content, 
            @"^\s*\w+\s*\{", 
            System.Text.RegularExpressions.RegexOptions.Multiline).Count;
        
        return Math.Max(createTableCount, mermaidEntityCount);
    }

    private static int CountColumns(string content)
    {
        if (string.IsNullOrWhiteSpace(content)) return 0;
        return System.Text.RegularExpressions.Regex.Matches(content, @"\w+\s+\w+").Count;
    }

    private static int CountRelationships(string content)
    {
        if (string.IsNullOrWhiteSpace(content)) return 0;
        return System.Text.RegularExpressions.Regex.Matches(content, @"\|\|--[o\{]").Count;
    }

    private static SqlDialect ParseDialect(string dialect)
    {
        return dialect.ToLowerInvariant() switch
        {
            "ansi" or "ansisql" => SqlDialect.AnsiSql,
            "sqlserver" or "mssql" or "tsql" => SqlDialect.SqlServer,
            "postgresql" or "postgres" or "psql" => SqlDialect.PostgreSql,
            "mysql" => SqlDialect.MySql,
            _ => SqlDialect.AnsiSql
        };
    }
}

