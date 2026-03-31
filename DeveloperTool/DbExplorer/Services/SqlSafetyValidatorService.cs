using System;
using System.Text.RegularExpressions;
using System.Windows;
using NLog;

namespace DbExplorer.Services;

/// <summary>
/// Validates SQL statements for potentially dangerous operations
/// </summary>
public class SqlSafetyValidatorService
{
    private static readonly Logger Logger = LogManager.GetCurrentClassLogger();
    
    /// <summary>
    /// Validates SQL and warns user about dangerous operations
    /// </summary>
    /// <returns>True if user confirms execution, False if cancelled</returns>
    public bool ValidateAndWarn(string sql)
    {
        Logger.Debug("Validating SQL for safety");
        
        if (string.IsNullOrWhiteSpace(sql))
            return true;
        
        var upperSql = sql.ToUpperInvariant();
        
        // Check for UPDATE without WHERE
        if (IsUpdateWithoutWhere(upperSql))
        {
            Logger.Warn("Detected UPDATE without WHERE clause");
            return ShowDangerousOperationWarning(
                "UPDATE Without WHERE Clause",
                "This UPDATE statement has no WHERE clause!\n\n" +
                "⚠️ This will UPDATE ALL ROWS in the table.\n\n" +
                "Are you absolutely sure you want to continue?");
        }
        
        // Check for DELETE without WHERE
        if (IsDeleteWithoutWhere(upperSql))
        {
            Logger.Warn("Detected DELETE without WHERE clause");
            return ShowDangerousOperationWarning(
                "DELETE Without WHERE Clause",
                "This DELETE statement has no WHERE clause!\n\n" +
                "⚠️ This will DELETE ALL ROWS in the table.\n\n" +
                "Are you absolutely sure you want to continue?");
        }
        
        // Check for DROP TABLE
        if (IsDropTable(upperSql))
        {
            Logger.Warn("Detected DROP TABLE statement");
            return ShowDangerousOperationWarning(
                "DROP TABLE",
                "This will permanently DELETE the entire table!\n\n" +
                "⚠️ All data will be lost and cannot be recovered.\n\n" +
                "Are you absolutely sure you want to continue?");
        }
        
        // Check for DROP DATABASE
        if (IsDropDatabase(upperSql))
        {
            Logger.Warn("Detected DROP DATABASE statement");
            return ShowCriticalOperationWarning(
                "DROP DATABASE - CRITICAL",
                "This will permanently DELETE the entire database!\n\n" +
                "🚨 ALL DATA will be lost and cannot be recovered.\n\n" +
                "This is an EXTREMELY dangerous operation.\n\n" +
                "Are you ABSOLUTELY certain?\n\n" +
                "Click YES only if you understand the consequences.");
        }
        
        // Check for TRUNCATE TABLE
        if (IsTruncateTable(upperSql))
        {
            Logger.Warn("Detected TRUNCATE TABLE statement");
            return ShowDangerousOperationWarning(
                "TRUNCATE TABLE",
                "This will DELETE ALL ROWS from the table!\n\n" +
                "⚠️ This operation is faster than DELETE but cannot be rolled back easily.\n\n" +
                "Continue?");
        }
        
        Logger.Debug("SQL validation passed");
        return true;
    }
    
    private bool IsUpdateWithoutWhere(string sql)
    {
        // Match UPDATE ... SET ... but not WHERE
        // Handle multi-line, comments, etc.
        var cleanSql = RemoveComments(sql);
        
        return Regex.IsMatch(cleanSql, @"\bUPDATE\b.*\bSET\b", RegexOptions.Singleline) &&
               !Regex.IsMatch(cleanSql, @"\bWHERE\b", RegexOptions.Singleline);
    }
    
    private bool IsDeleteWithoutWhere(string sql)
    {
        var cleanSql = RemoveComments(sql);
        
        return Regex.IsMatch(cleanSql, @"\bDELETE\s+FROM\b", RegexOptions.Singleline) &&
               !Regex.IsMatch(cleanSql, @"\bWHERE\b", RegexOptions.Singleline);
    }
    
    private bool IsDropTable(string sql)
    {
        return Regex.IsMatch(sql, @"\bDROP\s+TABLE\b", RegexOptions.Singleline);
    }
    
    private bool IsDropDatabase(string sql)
    {
        return Regex.IsMatch(sql, @"\bDROP\s+(DATABASE|SCHEMA)\b", RegexOptions.Singleline);
    }
    
    private bool IsTruncateTable(string sql)
    {
        return Regex.IsMatch(sql, @"\bTRUNCATE\s+TABLE\b", RegexOptions.Singleline);
    }
    
    private string RemoveComments(string sql)
    {
        // Remove -- comments
        sql = Regex.Replace(sql, @"--[^\n]*", string.Empty);
        
        // Remove /* */ comments
        sql = Regex.Replace(sql, @"/\*.*?\*/", string.Empty, RegexOptions.Singleline);
        
        return sql;
    }
    
    private bool ShowDangerousOperationWarning(string title, string message)
    {
        var result = MessageBox.Show(
            message,
            title,
            MessageBoxButton.YesNo,
            MessageBoxImage.Warning,
            MessageBoxResult.No); // Default to No
        
        return result == MessageBoxResult.Yes;
    }
    
    private bool ShowCriticalOperationWarning(string title, string message)
    {
        // First confirmation
        var firstResult = MessageBox.Show(
            message,
            title,
            MessageBoxButton.YesNo,
            MessageBoxImage.Stop,
            MessageBoxResult.No);
        
        if (firstResult != MessageBoxResult.Yes)
            return false;
        
        // Second confirmation - make user think twice
        var secondResult = MessageBox.Show(
            "FINAL CONFIRMATION\n\n" +
            "This action CANNOT be undone.\n\n" +
            "All data will be permanently destroyed.\n\n" +
            "Execute DROP DATABASE?",
            "FINAL WARNING",
            MessageBoxButton.YesNo,
            MessageBoxImage.Stop,
            MessageBoxResult.No);
        
        return secondResult == MessageBoxResult.Yes;
    }
}

