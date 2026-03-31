using System.Text;
using Microsoft.Extensions.Logging;
using ServerMonitor.Core.Models;

namespace ServerMonitor.Core.Services;

/// <summary>
/// Logs DB2 SQL errors to a dedicated file for audit purposes.
/// Used by the LogOnly action in Db2DiagPatternMatcher.
/// Format: timestamp|database|username|sqlcode|message
/// </summary>
public class Db2SqlErrorLogger
{
    private readonly ILogger<Db2SqlErrorLogger> _logger;
    private readonly object _lock = new();
    
    public Db2SqlErrorLogger(ILogger<Db2SqlErrorLogger> logger)
    {
        _logger = logger;
    }

    /// <summary>
    /// Log a SQL error entry to the configured log file.
    /// </summary>
    /// <param name="entry">The DB2 diagnostic entry.</param>
    /// <param name="sqlCode">Extracted SQL code (e.g., SQL0530N).</param>
    /// <param name="logPathTemplate">Path template with {Date}, {Database}, and {ServerName} placeholders.</param>
    public void LogSqlError(Db2DiagEntry entry, string? sqlCode, string logPathTemplate)
    {
        if (string.IsNullOrWhiteSpace(logPathTemplate))
        {
            _logger.LogDebug("SqlErrorLogPath not configured, skipping LogOnly action");
            return;
        }
        
        try
        {
            var database = entry.DatabaseName ?? "UNKNOWN";
            var date = DateTime.Now.ToString("yyyyMMdd");
            var serverName = Environment.MachineName;
            
            // Build file path from template
            var logPath = logPathTemplate
                .Replace("{Date}", date)
                .Replace("{Database}", database)
                .Replace("{ServerName}", serverName);
            
            var line = FormatLogLine(entry, sqlCode);
            
            lock (_lock)
            {
                // Ensure directory exists
                var directory = Path.GetDirectoryName(logPath);
                if (!string.IsNullOrEmpty(directory) && !Directory.Exists(directory))
                {
                    try
                    {
                        Directory.CreateDirectory(directory);
                    }
                    catch (Exception ex)
                    {
                        _logger.LogWarning(ex, "Failed to create directory for SQL error log: {Path}", directory);
                        return;
                    }
                }
                
                // Append to file
                File.AppendAllText(logPath, line + Environment.NewLine, Encoding.UTF8);
            }
            
            _logger.LogDebug("Logged SQL error to {Path}: {SqlCode}", logPath, sqlCode);
        }
        catch (Exception ex)
        {
            // Log warning but don't throw - this is secondary logging
            _logger.LogWarning(ex, "Failed to write to SQL error log");
        }
    }

    /// <summary>
    /// Format a log line: timestamp|database|username|sqlcode|message
    /// </summary>
    private static string FormatLogLine(Db2DiagEntry entry, string? sqlCode)
    {
        var timestamp = entry.TimestampParsed?.ToString("yyyy-MM-dd HH:mm:ss") 
                        ?? DateTime.Now.ToString("yyyy-MM-dd HH:mm:ss");
        var database = entry.DatabaseName ?? "N/A";
        var username = entry.AuthorizationId ?? "N/A";
        var code = sqlCode ?? "N/A";
        var message = ExtractSqlMessage(entry) ?? "No message";
        
        // Escape pipe characters in message to prevent parsing issues
        message = message.Replace("|", "\\|");
        
        return $"{timestamp}|{database}|{username}|{code}|{message}";
    }

    /// <summary>
    /// Extract the SQL error message from data sections.
    /// </summary>
    private static string? ExtractSqlMessage(Db2DiagEntry entry)
    {
        // Look for ODBC error text in data sections
        if (entry.DataSections != null)
        {
            foreach (var section in entry.DataSections)
            {
                // Look for "error txt" or similar
                if (section.Type?.Contains("error", StringComparison.OrdinalIgnoreCase) == true ||
                    section.Value?.Contains("SQL", StringComparison.OrdinalIgnoreCase) == true)
                {
                    var value = section.Value?.Trim();
                    if (!string.IsNullOrWhiteSpace(value) && value.Length > 10)
                    {
                        return CleanMessage(value);
                    }
                }
            }
        }
        
        // Fall back to entry message or function
        return CleanMessage(entry.Message) ?? CleanMessage(entry.Function) ?? "DB2 error";
    }

    /// <summary>
    /// Clean message for log file (remove newlines, truncate).
    /// </summary>
    private static string? CleanMessage(string? msg)
    {
        if (string.IsNullOrWhiteSpace(msg)) return null;
        
        // Remove newlines and excessive whitespace
        var cleaned = msg
            .Replace("\r\n", " ")
            .Replace("\r", " ")
            .Replace("\n", " ")
            .Trim();
        
        // Collapse multiple spaces
        while (cleaned.Contains("  "))
        {
            cleaned = cleaned.Replace("  ", " ");
        }
        
        // Truncate if too long (max 500 chars)
        if (cleaned.Length > 500)
        {
            cleaned = cleaned.Substring(0, 497) + "...";
        }
        
        return cleaned;
    }
}
