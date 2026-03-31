using NLog;
using PoorMansTSqlFormatterLib;
using PoorMansTSqlFormatterLib.Formatters;

namespace DbExplorer.Services;

/// <summary>
/// Service for formatting SQL code
/// </summary>
public class SqlFormatterService
{
    private static readonly Logger Logger = LogManager.GetCurrentClassLogger();
    private readonly TSqlStandardFormatter _formatter;
    private readonly SqlFormattingManager _formattingManager;

    public SqlFormatterService()
    {
        Logger.Debug("SqlFormatterService initializing");

        // Create formatter with standard options
        // Parameters: indentString, spacesPerTab, maxLineWidth, expandCommaLists, trailingCommas, spaceAfterComma,
        //            expandBooleanExpressions, expandCaseStatements, expandBetweenConditions, breakJoinOnSections,
        //            uppercaseKeywords, htmlColoring, keywordStandardization
        _formatter = new TSqlStandardFormatter("    ", 4, 120, true, false, true, true, true, true, true, true, false, true);
        
        _formattingManager = new SqlFormattingManager
        {
            Formatter = _formatter
        };

        Logger.Info("SqlFormatterService initialized with standard formatting options");
    }

    /// <summary>
    /// Format SQL code
    /// </summary>
    public string FormatSql(string sql)
    {
        if (string.IsNullOrWhiteSpace(sql))
        {
            Logger.Debug("Empty SQL provided for formatting");
            return sql;
        }

        try
        {
            Logger.Debug($"Formatting SQL (length: {sql.Length})");
            var formattedSql = _formattingManager.Format(sql);
            Logger.Debug($"SQL formatted successfully (new length: {formattedSql.Length})");
            return formattedSql;
        }
        catch (Exception ex)
        {
            Logger.Error(ex, "Failed to format SQL");
            throw new FormatException($"SQL formatting failed: {ex.Message}", ex);
        }
    }

    /// <summary>
    /// Check if SQL is valid (can be parsed)
    /// </summary>
    public bool IsValidSql(string sql)
    {
        if (string.IsNullOrWhiteSpace(sql))
        {
            return false;
        }

        try
        {
            Logger.Debug("Validating SQL syntax");
            _formattingManager.Format(sql);
            Logger.Debug("SQL syntax is valid");
            return true;
        }
        catch (Exception ex)
        {
            Logger.Debug($"SQL syntax validation failed: {ex.Message}");
            return false;
        }
    }
}

