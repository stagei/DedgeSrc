using SqlMermaidErdTools.Exceptions;
using SqlMermaidErdTools.Models;

namespace SqlMermaidErdTools.Converters;

/// <summary>
/// Converts Mermaid ERD diagrams to SQL DDL using SQLGlot.
/// </summary>
public class MmdToSqlConverter : BaseConverter, IMmdToSqlConverter
{
    /// <summary>
    /// Converts Mermaid ERD to SQL DDL format synchronously.
    /// </summary>
    /// <param name="mermaidErd">The Mermaid ERD diagram string</param>
    /// <param name="dialect">Target SQL dialect (default: AnsiSql)</param>
    /// <returns>SQL DDL statements as a string</returns>
    /// <exception cref="MmdParseException">Thrown when Mermaid parsing fails</exception>
    /// <exception cref="ConversionException">Thrown when conversion fails</exception>
    public string Convert(string mermaidErd, SqlDialect dialect = SqlDialect.AnsiSql)
    {
        ValidateInput(mermaidErd, nameof(mermaidErd));

        try
        {
            var dialectStr = MapDialectToSqlGlot(dialect);
            return ExecutePythonWithTempFile("mmd_to_sql.py", mermaidErd, dialectStr);
        }
        catch (ConversionException)
        {
            throw;
        }
        catch (Exception ex)
        {
            throw new MmdParseException(
                $"Failed to convert Mermaid ERD to SQL: {ex.Message}",
                ex);
        }
    }

    /// <summary>
    /// Converts Mermaid ERD to SQL DDL format asynchronously.
    /// </summary>
    /// <param name="mermaidErd">The Mermaid ERD diagram string</param>
    /// <param name="dialect">Target SQL dialect (default: AnsiSql)</param>
    /// <param name="cancellationToken">Cancellation token for async operation</param>
    /// <returns>A task that resolves to SQL DDL statements as a string</returns>
    /// <exception cref="MmdParseException">Thrown when Mermaid parsing fails</exception>
    /// <exception cref="ConversionException">Thrown when conversion fails</exception>
    public async Task<string> ConvertAsync(
        string mermaidErd,
        SqlDialect dialect = SqlDialect.AnsiSql,
        CancellationToken cancellationToken = default)
    {
        ValidateInput(mermaidErd, nameof(mermaidErd));

        try
        {
            var dialectStr = MapDialectToSqlGlot(dialect);
            var dialectName = string.IsNullOrEmpty(dialectStr) ? "AnsiSql" : dialect.ToString();
            
            return await ExecutePythonWithTempFileAsync(
                "mmd_to_sql.py",
                mermaidErd,
                dialectStr,
                cancellationToken,
                $"MmdToSql_{dialectName}",
                ".mmd",
                ".sql"
            );
        }
        catch (ConversionException)
        {
            throw;
        }
        catch (Exception ex)
        {
            throw new MmdParseException(
                $"Failed to convert Mermaid ERD to SQL: {ex.Message}",
                ex);
        }
    }
}

