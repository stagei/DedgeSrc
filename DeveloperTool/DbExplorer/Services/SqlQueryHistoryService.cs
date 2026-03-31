using System.Collections.Concurrent;
using NLog;

namespace DbExplorer.Services;

/// <summary>
/// Represents an executed SQL query with metadata
/// </summary>
public class ExecutedQuery
{
    public DateTime ExecutedAt { get; set; }
    public string Sql { get; set; } = string.Empty;
    public string? Source { get; set; }
    public long? DurationMs { get; set; }
    public int? RowsReturned { get; set; }
    public bool Success { get; set; } = true;
    public string? ErrorMessage { get; set; }
    
    public string DisplayTime => ExecutedAt.ToString("HH:mm:ss.fff");
    public string DisplayDuration => DurationMs.HasValue ? $"{DurationMs}ms" : "-";
    public string DisplayRows => RowsReturned?.ToString() ?? "-";
    public string ShortSql => Sql.Length > 100 ? Sql.Substring(0, 100) + "..." : Sql;
}

/// <summary>
/// Service for tracking all executed SQL queries in the application
/// </summary>
public static class SqlQueryHistoryService
{
    private static readonly Logger Logger = LogManager.GetCurrentClassLogger();
    private static readonly ConcurrentQueue<ExecutedQuery> _queryHistory = new();
    private const int MaxHistorySize = 500;
    
    /// <summary>
    /// Get all tracked queries, ordered by execution time (newest first)
    /// </summary>
    public static IReadOnlyList<ExecutedQuery> GetHistory()
    {
        return _queryHistory.Reverse().ToList();
    }
    
    /// <summary>
    /// Track a new query execution
    /// </summary>
    public static void Track(string sql, string? source = null, long? durationMs = null, int? rowsReturned = null, bool success = true, string? errorMessage = null)
    {
        var query = new ExecutedQuery
        {
            ExecutedAt = DateTime.Now,
            Sql = sql,
            Source = source,
            DurationMs = durationMs,
            RowsReturned = rowsReturned,
            Success = success,
            ErrorMessage = errorMessage
        };
        
        _queryHistory.Enqueue(query);
        
        // Trim history if it gets too large
        while (_queryHistory.Count > MaxHistorySize)
        {
            _queryHistory.TryDequeue(out _);
        }
        
        Logger.Debug("Query tracked: {Source} - {Duration}ms", source ?? "Unknown", durationMs);
    }
    
    /// <summary>
    /// Clear all query history
    /// </summary>
    public static void Clear()
    {
        while (_queryHistory.TryDequeue(out _)) { }
        Logger.Info("Query history cleared");
    }
    
    /// <summary>
    /// Get the count of tracked queries
    /// </summary>
    public static int Count => _queryHistory.Count;
}
