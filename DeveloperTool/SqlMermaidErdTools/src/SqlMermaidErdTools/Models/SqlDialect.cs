namespace SqlMermaidErdTools.Models;

/// <summary>
/// Represents supported SQL database dialects for conversion.
/// </summary>
public enum SqlDialect
{
    /// <summary>
    /// ANSI SQL standard
    /// </summary>
    AnsiSql,

    /// <summary>
    /// Microsoft SQL Server (T-SQL)
    /// </summary>
    SqlServer,

    /// <summary>
    /// PostgreSQL
    /// </summary>
    PostgreSql,

    /// <summary>
    /// MySQL
    /// </summary>
    MySql,

    /// <summary>
    /// SQLite
    /// </summary>
    Sqlite,

    /// <summary>
    /// Oracle Database
    /// </summary>
    Oracle
}

