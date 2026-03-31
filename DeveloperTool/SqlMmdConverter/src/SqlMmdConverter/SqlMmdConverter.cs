using SqlMmdConverter.Converters;

namespace SqlMmdConverter;

/// <summary>
/// Provides static convenience methods for converting SQL DDL to Mermaid ERD diagrams.
/// </summary>
/// <remarks>
/// Version 1.0 supports SQL → Mermaid ERD conversion only.
/// Mermaid → SQL conversion will be added in a future version.
/// </remarks>
public static class SqlMmdConverter
{
    private static readonly Lazy<ISqlToMmdConverter> _sqlToMmdConverter =
        new(() => new SqlToMmdConverter());

    /// <summary>
    /// Converts SQL DDL to Mermaid ERD diagram.
    /// </summary>
    /// <param name="sql">The SQL DDL string containing CREATE TABLE statements</param>
    /// <returns>A Mermaid ERD diagram as a string</returns>
    /// <exception cref="Exceptions.SqlParseException">Thrown when SQL parsing fails</exception>
    /// <exception cref="Exceptions.ConversionException">Thrown when conversion fails</exception>
    /// <example>
    /// <code>
    /// var mermaid = SqlMmdConverter.ToMermaid(sqlDdl);
    /// Console.WriteLine(mermaid);
    /// </code>
    /// </example>
    public static string ToMermaid(string sql)
    {
        return _sqlToMmdConverter.Value.Convert(sql);
    }

    /// <summary>
    /// Converts SQL DDL to Mermaid ERD diagram asynchronously.
    /// </summary>
    /// <param name="sql">The SQL DDL string containing CREATE TABLE statements</param>
    /// <param name="cancellationToken">Cancellation token for async operation</param>
    /// <returns>A task that resolves to a Mermaid ERD diagram as a string</returns>
    /// <exception cref="Exceptions.SqlParseException">Thrown when SQL parsing fails</exception>
    /// <exception cref="Exceptions.ConversionException">Thrown when conversion fails</exception>
    public static Task<string> ToMermaidAsync(string sql, CancellationToken cancellationToken = default)
    {
        return _sqlToMmdConverter.Value.ConvertAsync(sql, cancellationToken);
    }
}

