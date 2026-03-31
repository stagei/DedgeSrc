using SqlMermaidErdTools.Models;

namespace SqlMermaidErdTools.Converters;

/// <summary>
/// Defines a translator for converting SQL between different dialects.
/// </summary>
public interface ISqlDialectTranslator
{
    /// <summary>
    /// Translates SQL from one dialect to another synchronously.
    /// </summary>
    /// <param name="sql">The SQL DDL/DML statements to translate</param>
    /// <param name="sourceDialect">The source SQL dialect</param>
    /// <param name="targetDialect">The target SQL dialect</param>
    /// <returns>Translated SQL in the target dialect</returns>
    /// <exception cref="Exceptions.SqlParseException">Thrown when SQL parsing fails</exception>
    /// <exception cref="Exceptions.ConversionException">Thrown when translation fails</exception>
    string Translate(string sql, SqlDialect sourceDialect, SqlDialect targetDialect);

    /// <summary>
    /// Translates SQL from one dialect to another asynchronously.
    /// </summary>
    /// <param name="sql">The SQL DDL/DML statements to translate</param>
    /// <param name="sourceDialect">The source SQL dialect</param>
    /// <param name="targetDialect">The target SQL dialect</param>
    /// <param name="cancellationToken">Cancellation token for async operation</param>
    /// <returns>A task that resolves to translated SQL in the target dialect</returns>
    /// <exception cref="Exceptions.SqlParseException">Thrown when SQL parsing fails</exception>
    /// <exception cref="Exceptions.ConversionException">Thrown when translation fails</exception>
    Task<string> TranslateAsync(
        string sql,
        SqlDialect sourceDialect,
        SqlDialect targetDialect,
        CancellationToken cancellationToken = default);
}

