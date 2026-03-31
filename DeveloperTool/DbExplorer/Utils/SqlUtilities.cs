using System.Text;
using System.Text.RegularExpressions;
using NLog;

namespace DbExplorer.Utils;

/// <summary>
/// Utility class for SQL statement manipulation and parsing
/// </summary>
public static class SqlUtilities
{
    private static readonly Logger Logger = LogManager.GetCurrentClassLogger();

    /// <summary>
    /// Split SQL script into individual statements separated by semicolons
    /// </summary>
    public static List<string> SplitStatements(string sql)
    {
        Logger.Debug("Splitting SQL statements");

        if (string.IsNullOrWhiteSpace(sql))
        {
            return new List<string>();
        }

        var statements = new List<string>();
        var currentStatement = new StringBuilder();
        bool inString = false;
        bool inComment = false;
        bool inMultiLineComment = false;
        char stringDelimiter = '\0';

        for (int i = 0; i < sql.Length; i++)
        {
            char c = sql[i];
            char nextChar = i + 1 < sql.Length ? sql[i + 1] : '\0';

            // Check for multi-line comment start
            if (!inString && !inComment && c == '/' && nextChar == '*')
            {
                inMultiLineComment = true;
                currentStatement.Append(c);
                continue;
            }

            // Check for multi-line comment end
            if (inMultiLineComment && c == '*' && nextChar == '/')
            {
                inMultiLineComment = false;
                currentStatement.Append(c);
                if (i + 1 < sql.Length)
                {
                    i++;
                    currentStatement.Append(sql[i]);
                }
                continue;
            }

            // Skip processing if in multi-line comment
            if (inMultiLineComment)
            {
                currentStatement.Append(c);
                continue;
            }

            // Check for single-line comment start
            if (!inString && !inComment && c == '-' && nextChar == '-')
            {
                inComment = true;
                currentStatement.Append(c);
                continue;
            }

            // Check for single-line comment end
            if (inComment && c == '\n')
            {
                inComment = false;
                currentStatement.Append(c);
                continue;
            }

            // Skip processing if in comment
            if (inComment)
            {
                currentStatement.Append(c);
                continue;
            }

            // Check for string delimiters
            if (!inString && (c == '\'' || c == '"'))
            {
                inString = true;
                stringDelimiter = c;
                currentStatement.Append(c);
                continue;
            }

            // Check for string end (handle escaped quotes)
            if (inString && c == stringDelimiter)
            {
                if (nextChar == stringDelimiter)
                {
                    // Escaped quote, skip next char
                    currentStatement.Append(c);
                    i++;
                    currentStatement.Append(sql[i]);
                    continue;
                }
                else
                {
                    inString = false;
                    stringDelimiter = '\0';
                    currentStatement.Append(c);
                    continue;
                }
            }

            // Check for statement terminator
            if (!inString && !inComment && !inMultiLineComment && c == ';')
            {
                var statement = currentStatement.ToString().Trim();
                if (!string.IsNullOrWhiteSpace(statement))
                {
                    statements.Add(statement);
                    Logger.Debug($"Found statement: {statement.Substring(0, Math.Min(50, statement.Length))}...");
                }
                currentStatement.Clear();
                continue;
            }

            currentStatement.Append(c);
        }

        // Add final statement if exists
        var finalStatement = currentStatement.ToString().Trim();
        if (!string.IsNullOrWhiteSpace(finalStatement))
        {
            statements.Add(finalStatement);
            Logger.Debug($"Found final statement: {finalStatement.Substring(0, Math.Min(50, finalStatement.Length))}...");
        }

        Logger.Info($"Split SQL into {statements.Count} statement(s)");
        return statements;
    }

    /// <summary>
    /// Extract SQL keywords from a statement
    /// </summary>
    public static List<string> ExtractKeywords(string sql)
    {
        Logger.Debug("Extracting SQL keywords");

        if (string.IsNullOrWhiteSpace(sql))
        {
            return new List<string>();
        }

        var keywords = new HashSet<string>(StringComparer.OrdinalIgnoreCase)
        {
            "SELECT", "FROM", "WHERE", "INSERT", "UPDATE", "DELETE", "CREATE", "ALTER", "DROP",
            "TABLE", "INDEX", "VIEW", "PROCEDURE", "FUNCTION", "TRIGGER", "SCHEMA",
            "JOIN", "INNER", "LEFT", "RIGHT", "OUTER", "FULL", "CROSS",
            "ON", "AND", "OR", "NOT", "IN", "EXISTS", "BETWEEN", "LIKE",
            "ORDER", "BY", "GROUP", "HAVING", "DISTINCT", "AS", "ASC", "DESC",
            "UNION", "INTERSECT", "EXCEPT", "WITH", "CASE", "WHEN", "THEN", "ELSE", "END"
        };

        var foundKeywords = new List<string>();
        var words = Regex.Split(sql, @"\W+");

        foreach (var word in words)
        {
            if (keywords.Contains(word))
            {
                foundKeywords.Add(word.ToUpperInvariant());
            }
        }

        Logger.Debug($"Found {foundKeywords.Count} keywords");
        return foundKeywords.Distinct().ToList();
    }

    /// <summary>
    /// Check if SQL contains a specific statement type
    /// </summary>
    public static bool IsStatementType(string sql, string statementType)
    {
        if (string.IsNullOrWhiteSpace(sql))
        {
            return false;
        }

        var trimmed = RemoveComments(sql).Trim();
        return trimmed.StartsWith(statementType, StringComparison.OrdinalIgnoreCase);
    }

    /// <summary>
    /// Determine if SQL is a SELECT query
    /// </summary>
    public static bool IsSelectStatement(string sql)
    {
        return IsStatementType(sql, "SELECT");
    }

    /// <summary>
    /// Determine if SQL is a DML statement (INSERT, UPDATE, DELETE)
    /// </summary>
    public static bool IsDmlStatement(string sql)
    {
        if (string.IsNullOrWhiteSpace(sql))
        {
            return false;
        }

        var trimmed = RemoveComments(sql).Trim();
        return trimmed.StartsWith("INSERT", StringComparison.OrdinalIgnoreCase) ||
               trimmed.StartsWith("UPDATE", StringComparison.OrdinalIgnoreCase) ||
               trimmed.StartsWith("DELETE", StringComparison.OrdinalIgnoreCase);
    }

    /// <summary>
    /// Determine if SQL is a DDL statement (CREATE, ALTER, DROP)
    /// </summary>
    public static bool IsDdlStatement(string sql)
    {
        if (string.IsNullOrWhiteSpace(sql))
        {
            return false;
        }

        var trimmed = RemoveComments(sql).Trim();
        return trimmed.StartsWith("CREATE", StringComparison.OrdinalIgnoreCase) ||
               trimmed.StartsWith("ALTER", StringComparison.OrdinalIgnoreCase) ||
               trimmed.StartsWith("DROP", StringComparison.OrdinalIgnoreCase);
    }

    /// <summary>
    /// Remove SQL comments from a statement
    /// </summary>
    public static string RemoveComments(string sql)
    {
        if (string.IsNullOrWhiteSpace(sql))
        {
            return string.Empty;
        }

        // Remove single-line comments (-- ...)
        var result = Regex.Replace(sql, @"--[^\r\n]*", "");

        // Remove multi-line comments (/* ... */)
        result = Regex.Replace(result, @"/\*.*?\*/", "", RegexOptions.Singleline);

        return result;
    }

    /// <summary>
    /// Extract table names from a SQL statement
    /// </summary>
    public static List<string> ExtractTableNames(string sql)
    {
        Logger.Debug("Extracting table names");

        if (string.IsNullOrWhiteSpace(sql))
        {
            return new List<string>();
        }

        var tables = new HashSet<string>();
        var cleanSql = RemoveComments(sql);

        // Pattern for FROM clause
        var fromPattern = @"\bFROM\s+([a-zA-Z_][a-zA-Z0-9_]*\.)?([a-zA-Z_][a-zA-Z0-9_]*)";
        var fromMatches = Regex.Matches(cleanSql, fromPattern, RegexOptions.IgnoreCase);
        foreach (Match match in fromMatches)
        {
            var tableName = match.Groups[2].Value;
            if (!string.IsNullOrEmpty(tableName))
            {
                tables.Add(tableName);
            }
        }

        // Pattern for JOIN clause
        var joinPattern = @"\bJOIN\s+([a-zA-Z_][a-zA-Z0-9_]*\.)?([a-zA-Z_][a-zA-Z0-9_]*)";
        var joinMatches = Regex.Matches(cleanSql, joinPattern, RegexOptions.IgnoreCase);
        foreach (Match match in joinMatches)
        {
            var tableName = match.Groups[2].Value;
            if (!string.IsNullOrEmpty(tableName))
            {
                tables.Add(tableName);
            }
        }

        // Pattern for INTO clause (INSERT)
        var intoPattern = @"\bINTO\s+([a-zA-Z_][a-zA-Z0-9_]*\.)?([a-zA-Z_][a-zA-Z0-9_]*)";
        var intoMatches = Regex.Matches(cleanSql, intoPattern, RegexOptions.IgnoreCase);
        foreach (Match match in intoMatches)
        {
            var tableName = match.Groups[2].Value;
            if (!string.IsNullOrEmpty(tableName))
            {
                tables.Add(tableName);
            }
        }

        // Pattern for UPDATE clause
        var updatePattern = @"\bUPDATE\s+([a-zA-Z_][a-zA-Z0-9_]*\.)?([a-zA-Z_][a-zA-Z0-9_]*)";
        var updateMatches = Regex.Matches(cleanSql, updatePattern, RegexOptions.IgnoreCase);
        foreach (Match match in updateMatches)
        {
            var tableName = match.Groups[2].Value;
            if (!string.IsNullOrEmpty(tableName))
            {
                tables.Add(tableName);
            }
        }

        Logger.Debug($"Found {tables.Count} table(s)");
        return tables.ToList();
    }

    /// <summary>
    /// Validate basic SQL syntax
    /// </summary>
    public static bool IsValidSqlSyntax(string sql)
    {
        if (string.IsNullOrWhiteSpace(sql))
        {
            return false;
        }

        var cleanSql = RemoveComments(sql).Trim();

        // Check for basic statement keywords
        if (!IsSelectStatement(cleanSql) && !IsDmlStatement(cleanSql) && !IsDdlStatement(cleanSql))
        {
            return false;
        }

        // Check for balanced parentheses
        int openParens = 0;
        foreach (char c in cleanSql)
        {
            if (c == '(') openParens++;
            if (c == ')') openParens--;
            if (openParens < 0) return false;
        }

        if (openParens != 0)
        {
            return false;
        }

        return true;
    }

    /// <summary>
    /// Get the first line of SQL (useful for display/logging)
    /// </summary>
    public static string GetFirstLine(string sql)
    {
        if (string.IsNullOrWhiteSpace(sql))
        {
            return string.Empty;
        }

        var lines = sql.Split(new[] { '\r', '\n' }, StringSplitOptions.RemoveEmptyEntries);
        return lines.FirstOrDefault()?.Trim() ?? string.Empty;
    }

    /// <summary>
    /// Truncate SQL for display purposes
    /// </summary>
    public static string Truncate(string sql, int maxLength = 100)
    {
        if (string.IsNullOrWhiteSpace(sql))
        {
            return string.Empty;
        }

        var singleLine = sql.Replace("\r", " ").Replace("\n", " ").Trim();
        singleLine = Regex.Replace(singleLine, @"\s+", " ");

        if (singleLine.Length <= maxLength)
        {
            return singleLine;
        }

        return singleLine.Substring(0, maxLength - 3) + "...";
    }
}

