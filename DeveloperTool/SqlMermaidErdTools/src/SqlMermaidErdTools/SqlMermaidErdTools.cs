using SqlMermaidErdTools.Converters;
using SqlMermaidErdTools.Models;

namespace SqlMermaidErdTools;

/// <summary>
/// Provides static convenience methods for bidirectional conversion between SQL DDL and Mermaid ERD diagrams,
/// SQL dialect translation, and schema diff management.
/// </summary>
/// <remarks>
/// Version 0.1.0 supports:
/// - SQL → Mermaid ERD conversion
/// - Mermaid ERD → SQL conversion
/// - SQL dialect translation (between different SQL dialects)
/// - Mermaid ERD diff → SQL ALTER statements
/// </remarks>
public static class SqlMermaidErdTools
{
    private static readonly Lazy<ISqlToMmdConverter> _sqlToMmdConverter =
        new(() => new SqlToMmdConverter());
    
    private static readonly Lazy<IMmdToSqlConverter> _mmdToSqlConverter =
        new(() => new MmdToSqlConverter());
    
    private static readonly Lazy<ISqlDialectTranslator> _sqlDialectTranslator =
        new(() => new SqlDialectTranslator());
    
    private static readonly Lazy<IMmdDiffToSqlGenerator> _mmdDiffToSqlGenerator =
        new(() => new MmdDiffToSqlGenerator());

    #region SQL to Mermaid

    /// <summary>
    /// Converts SQL DDL to Mermaid ERD diagram.
    /// </summary>
    /// <param name="sql">The SQL DDL string containing CREATE TABLE statements</param>
    /// <returns>A Mermaid ERD diagram as a string</returns>
    /// <exception cref="Exceptions.SqlParseException">Thrown when SQL parsing fails</exception>
    /// <exception cref="Exceptions.ConversionException">Thrown when conversion fails</exception>
    /// <example>
    /// <code>
    /// var mermaid = SqlMermaidErdTools.ToMermaid(sqlDdl);
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

    #endregion

    #region Mermaid to SQL

    /// <summary>
    /// Converts Mermaid ERD diagram to SQL DDL.
    /// </summary>
    /// <param name="mermaid">The Mermaid ERD diagram string</param>
    /// <param name="dialect">Target SQL dialect (default: AnsiSql)</param>
    /// <returns>SQL DDL statements as a string</returns>
    /// <exception cref="Exceptions.MmdParseException">Thrown when Mermaid parsing fails</exception>
    /// <exception cref="Exceptions.ConversionException">Thrown when conversion fails</exception>
    /// <example>
    /// <code>
    /// var sql = SqlMermaidErdTools.ToSql(mermaidDiagram, SqlDialect.PostgreSql);
    /// Console.WriteLine(sql);
    /// </code>
    /// </example>
    public static string ToSql(string mermaid, SqlDialect dialect = SqlDialect.AnsiSql)
    {
        return _mmdToSqlConverter.Value.Convert(mermaid, dialect);
    }

    /// <summary>
    /// Converts Mermaid ERD diagram to SQL DDL asynchronously.
    /// </summary>
    /// <param name="mermaid">The Mermaid ERD diagram string</param>
    /// <param name="dialect">Target SQL dialect (default: AnsiSql)</param>
    /// <param name="cancellationToken">Cancellation token for async operation</param>
    /// <returns>A task that resolves to SQL DDL statements as a string</returns>
    /// <exception cref="Exceptions.MmdParseException">Thrown when Mermaid parsing fails</exception>
    /// <exception cref="Exceptions.ConversionException">Thrown when conversion fails</exception>
    public static Task<string> ToSqlAsync(
        string mermaid,
        SqlDialect dialect = SqlDialect.AnsiSql,
        CancellationToken cancellationToken = default)
    {
        return _mmdToSqlConverter.Value.ConvertAsync(mermaid, dialect, cancellationToken);
    }

    #endregion

    #region SQL Dialect Translation

    /// <summary>
    /// Translates SQL from one dialect to another.
    /// </summary>
    /// <param name="sql">The SQL DDL/DML statements to translate</param>
    /// <param name="sourceDialect">The source SQL dialect</param>
    /// <param name="targetDialect">The target SQL dialect</param>
    /// <returns>Translated SQL in the target dialect</returns>
    /// <exception cref="Exceptions.SqlParseException">Thrown when SQL parsing fails</exception>
    /// <exception cref="Exceptions.ConversionException">Thrown when translation fails</exception>
    /// <example>
    /// <code>
    /// var postgresSQL = SqlMermaidErdTools.TranslateDialect(
    ///     sqlServerSql, 
    ///     SqlDialect.SqlServer, 
    ///     SqlDialect.PostgreSql);
    /// </code>
    /// </example>
    public static string TranslateDialect(
        string sql,
        SqlDialect sourceDialect,
        SqlDialect targetDialect)
    {
        return _sqlDialectTranslator.Value.Translate(sql, sourceDialect, targetDialect);
    }

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
    public static Task<string> TranslateDialectAsync(
        string sql,
        SqlDialect sourceDialect,
        SqlDialect targetDialect,
        CancellationToken cancellationToken = default)
    {
        return _sqlDialectTranslator.Value.TranslateAsync(
            sql,
            sourceDialect,
            targetDialect,
            cancellationToken);
    }

    #endregion

    #region Mermaid Diff to SQL ALTER

    /// <summary>
    /// Generates SQL ALTER statements from differences between two Mermaid ERD diagrams.
    /// </summary>
    /// <param name="beforeMermaid">The original/before Mermaid ERD diagram</param>
    /// <param name="afterMermaid">The modified/after Mermaid ERD diagram</param>
    /// <param name="dialect">Target SQL dialect (default: AnsiSql)</param>
    /// <returns>SQL ALTER statements representing the differences</returns>
    /// <exception cref="Exceptions.MmdParseException">Thrown when Mermaid parsing fails</exception>
    /// <exception cref="Exceptions.ConversionException">Thrown when conversion fails</exception>
    /// <example>
    /// <code>
    /// var alterStatements = SqlMermaidErdTools.GenerateDiffAlterStatements(
    ///     originalDiagram,
    ///     modifiedDiagram,
    ///     SqlDialect.PostgreSql);
    /// </code>
    /// </example>
    public static string GenerateDiffAlterStatements(
        string beforeMermaid,
        string afterMermaid,
        SqlDialect dialect = SqlDialect.AnsiSql)
    {
        return _mmdDiffToSqlGenerator.Value.GenerateAlterStatements(
            beforeMermaid,
            afterMermaid,
            dialect);
    }

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
    public static Task<string> GenerateDiffAlterStatementsAsync(
        string beforeMermaid,
        string afterMermaid,
        SqlDialect dialect = SqlDialect.AnsiSql,
        CancellationToken cancellationToken = default)
    {
        return _mmdDiffToSqlGenerator.Value.GenerateAlterStatementsAsync(
            beforeMermaid,
            afterMermaid,
            dialect,
            cancellationToken);
    }

    #endregion
}

