using SqlMermaidErdTools.Models;

namespace SqlMermaidErdTools.Converters;

/// <summary>
/// Defines a generator for creating SQL ALTER statements from Mermaid ERD differences.
/// </summary>
public interface IMmdDiffToSqlGenerator
{
    /// <summary>
    /// Generates SQL ALTER statements from differences between two Mermaid ERD diagrams synchronously.
    /// </summary>
    /// <param name="beforeMermaid">The original/before Mermaid ERD diagram</param>
    /// <param name="afterMermaid">The modified/after Mermaid ERD diagram</param>
    /// <param name="dialect">Target SQL dialect (default: AnsiSql)</param>
    /// <returns>SQL ALTER statements representing the differences</returns>
    /// <exception cref="Exceptions.MmdParseException">Thrown when Mermaid parsing fails</exception>
    /// <exception cref="Exceptions.ConversionException">Thrown when conversion fails</exception>
    string GenerateAlterStatements(
        string beforeMermaid,
        string afterMermaid,
        SqlDialect dialect = SqlDialect.AnsiSql);

    /// <summary>
    /// Generates SQL ALTER statements from differences between two Mermaid ERD diagrams asynchronously.
    /// </summary>
    /// <param name="beforeMermaid">The original/before Mermaid ERD diagram</param>
    /// <param name="afterMermaid">The modified/after Mermaid ERD diagram</param>
    /// <param name="dialect">Target SQL dialect (default: AnsiSql)</param>
    /// <param name="cancellationToken">Cancellation token for async operation</param>
    /// <returns>A task that resolves to SQL ALTER statements representing the differences</returns>
    /// <exception cref="Exceptions.MmdParseException">Thrown when Mermaid parsing fails</exception>
    /// <exception cref="Exceptions.ConversionException">Thrown when conversion fails</exception>
    Task<string> GenerateAlterStatementsAsync(
        string beforeMermaid,
        string afterMermaid,
        SqlDialect dialect = SqlDialect.AnsiSql,
        CancellationToken cancellationToken = default);
}

