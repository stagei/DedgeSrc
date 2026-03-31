using SqlMermaidErdTools.Models;

namespace SqlMermaidErdTools.Converters;

/// <summary>
/// Defines a converter for transforming Mermaid ERD diagrams to SQL DDL.
/// </summary>
public interface IMmdToSqlConverter
{
    /// <summary>
    /// Converts Mermaid ERD to SQL DDL format synchronously.
    /// </summary>
    /// <param name="mermaidErd">The Mermaid ERD diagram string</param>
    /// <param name="dialect">Target SQL dialect (default: AnsiSql)</param>
    /// <returns>SQL DDL statements as a string</returns>
    /// <exception cref="Exceptions.MmdParseException">Thrown when Mermaid parsing fails</exception>
    /// <exception cref="Exceptions.ConversionException">Thrown when conversion fails</exception>
    string Convert(string mermaidErd, SqlDialect dialect = SqlDialect.AnsiSql);

    /// <summary>
    /// Converts Mermaid ERD to SQL DDL format asynchronously.
    /// </summary>
    /// <param name="mermaidErd">The Mermaid ERD diagram string</param>
    /// <param name="dialect">Target SQL dialect (default: AnsiSql)</param>
    /// <param name="cancellationToken">Cancellation token for async operation</param>
    /// <returns>A task that resolves to SQL DDL statements as a string</returns>
    /// <exception cref="Exceptions.MmdParseException">Thrown when Mermaid parsing fails</exception>
    /// <exception cref="Exceptions.ConversionException">Thrown when conversion fails</exception>
    Task<string> ConvertAsync(
        string mermaidErd,
        SqlDialect dialect = SqlDialect.AnsiSql,
        CancellationToken cancellationToken = default);
}

