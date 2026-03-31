using SqlMermaidErdTools.Exceptions;
using SqlMermaidErdTools.Models;

namespace SqlMermaidErdTools.Converters;

/// <summary>
/// Translates SQL between different dialects using SQLGlot.
/// </summary>
public class SqlDialectTranslator : BaseConverter, ISqlDialectTranslator
{
    /// <summary>
    /// Translates SQL from one dialect to another synchronously.
    /// </summary>
    /// <param name="sql">The SQL DDL/DML statements to translate</param>
    /// <param name="sourceDialect">The source SQL dialect</param>
    /// <param name="targetDialect">The target SQL dialect</param>
    /// <returns>Translated SQL in the target dialect</returns>
    /// <exception cref="SqlParseException">Thrown when SQL parsing fails</exception>
    /// <exception cref="ConversionException">Thrown when translation fails</exception>
    public string Translate(string sql, SqlDialect sourceDialect, SqlDialect targetDialect)
    {
        ValidateInput(sql, nameof(sql));

        try
        {
            var cleanedSql = CleanSqlBrackets(sql);
            var sourceDialectStr = MapDialectToSqlGlot(sourceDialect);
            var targetDialectStr = MapDialectToSqlGlot(targetDialect);
            
            // Quote the dialect arguments to handle empty strings
            return ExecutePythonWithTempFile(
                "sql_dialect_translate.py",
                cleanedSql,
                $"\"{sourceDialectStr}\" \"{targetDialectStr}\""
            );
        }
        catch (ConversionException)
        {
            throw;
        }
        catch (Exception ex)
        {
            throw new SqlParseException(
                $"Failed to translate SQL from {sourceDialect} to {targetDialect}: {ex.Message}",
                ex);
        }
    }

    /// <summary>
    /// Translates SQL from one dialect to another asynchronously.
    /// </summary>
    /// <param name="sql">The SQL DDL/DML statements to translate</param>
    /// <param name="sourceDialect">The source SQL dialect</param>
    /// <param name="targetDialect">The target SQL dialect</param>
    /// <param name="cancellationToken">Cancellation token for async operation</param>
    /// <returns>A task that resolves to translated SQL in the target dialect</returns>
    /// <exception cref="SqlParseException">Thrown when SQL parsing fails</exception>
    /// <exception cref="ConversionException">Thrown when translation fails</exception>
    public async Task<string> TranslateAsync(
        string sql,
        SqlDialect sourceDialect,
        SqlDialect targetDialect,
        CancellationToken cancellationToken = default)
    {
        ValidateInput(sql, nameof(sql));

        try
        {
            // Export original input
            var sourceName = sourceDialect.ToString();
            var targetName = targetDialect.ToString();
            await ExportToFileAsync(
                sql, 
                $"SqlDialectTranslate_{sourceName}To{targetName}-In_Original.sql", 
                $"Original SQL ({sourceName})",
                cancellationToken
            );
            
            var cleanedSql = CleanSqlBrackets(sql);
            
            // Export cleaned SQL
            await ExportToFileAsync(
                cleanedSql, 
                $"SqlDialectTranslate_{sourceName}To{targetName}-In_Cleaned.sql", 
                "Cleaned SQL (brackets removed)",
                cancellationToken
            );
            
            var sourceDialectStr = MapDialectToSqlGlot(sourceDialect);
            var targetDialectStr = MapDialectToSqlGlot(targetDialect);
            
            // Quote the dialect arguments to handle empty strings
            return await ExecutePythonWithTempFileAsync(
                "sql_dialect_translate.py",
                cleanedSql,
                $"\"{sourceDialectStr}\" \"{targetDialectStr}\"",
                cancellationToken,
                $"SqlDialectTranslate_{sourceName}To{targetName}",
                ".sql",
                ".sql"
            );
        }
        catch (ConversionException)
        {
            throw;
        }
        catch (Exception ex)
        {
            throw new SqlParseException(
                $"Failed to translate SQL from {sourceDialect} to {targetDialect}: {ex.Message}",
                ex);
        }
    }
}

