namespace SqlMmdConverter.Converters;

/// <summary>
/// Defines a converter for transforming SQL DDL to Mermaid ERD diagrams.
/// </summary>
public interface ISqlToMmdConverter
{
    /// <summary>
    /// Converts SQL DDL to Mermaid ERD format synchronously.
    /// </summary>
    /// <param name="sqlDdl">The SQL DDL string containing CREATE TABLE statements</param>
    /// <returns>A Mermaid ERD diagram as a string</returns>
    /// <exception cref="Exceptions.SqlParseException">Thrown when SQL parsing fails</exception>
    /// <exception cref="Exceptions.ConversionException">Thrown when conversion fails</exception>
    string Convert(string sqlDdl);

    /// <summary>
    /// Converts SQL DDL to Mermaid ERD format asynchronously.
    /// </summary>
    /// <param name="sqlDdl">The SQL DDL string containing CREATE TABLE statements</param>
    /// <param name="cancellationToken">Cancellation token for async operation</param>
    /// <returns>A task that resolves to a Mermaid ERD diagram as a string</returns>
    /// <exception cref="Exceptions.SqlParseException">Thrown when SQL parsing fails</exception>
    /// <exception cref="Exceptions.ConversionException">Thrown when conversion fails</exception>
    Task<string> ConvertAsync(string sqlDdl, CancellationToken cancellationToken = default);

    /// <summary>
    /// Converts SQL DDL to Mermaid ERD format wrapped in Markdown.
    /// </summary>
    /// <param name="sqlDdl">The SQL DDL string containing CREATE TABLE statements</param>
    /// <param name="title">Title for the markdown document (typically the filename without extension)</param>
    /// <returns>A Markdown document containing the Mermaid ERD diagram</returns>
    /// <exception cref="Exceptions.SqlParseException">Thrown when SQL parsing fails</exception>
    /// <exception cref="Exceptions.ConversionException">Thrown when conversion fails</exception>
    string ConvertToMarkdown(string sqlDdl, string title);

    /// <summary>
    /// Converts SQL DDL to Mermaid ERD format wrapped in Markdown asynchronously.
    /// </summary>
    /// <param name="sqlDdl">The SQL DDL string containing CREATE TABLE statements</param>
    /// <param name="title">Title for the markdown document (typically the filename without extension)</param>
    /// <param name="cancellationToken">Cancellation token for async operation</param>
    /// <returns>A task that resolves to a Markdown document containing the Mermaid ERD diagram</returns>
    /// <exception cref="Exceptions.SqlParseException">Thrown when SQL parsing fails</exception>
    /// <exception cref="Exceptions.ConversionException">Thrown when conversion fails</exception>
    Task<string> ConvertToMarkdownAsync(string sqlDdl, string title, CancellationToken cancellationToken = default);
}

