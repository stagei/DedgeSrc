using GenericLogHandler.Core.Models;

namespace GenericLogHandler.Core.Interfaces;

/// <summary>
/// Interface for log data repository operations
/// </summary>
public interface ILogRepository
{
    /// <summary>
    /// Adds a single log entry to the repository
    /// </summary>
    Task<LogEntry> AddAsync(LogEntry logEntry, CancellationToken cancellationToken = default);

    /// <summary>
    /// Adds multiple log entries in a batch operation
    /// </summary>
    Task<int> AddBatchAsync(IEnumerable<LogEntry> logEntries, CancellationToken cancellationToken = default);

    /// <summary>
    /// Gets a log entry by its ID
    /// </summary>
    Task<LogEntry?> GetByIdAsync(Guid id, CancellationToken cancellationToken = default);

    /// <summary>
    /// Searches for log entries based on criteria
    /// </summary>
    Task<GenericLogHandler.Core.Interfaces.PagedResult<LogEntry>> SearchAsync(LogSearchCriteria criteria, CancellationToken cancellationToken = default);

    /// <summary>
    /// Gets log statistics for a date range.
    /// </summary>
    /// <param name="sourcePathContains">Optional: only include entries whose SourceFile contains this substring (e.g. "CommonLogging\\Psh" for Psh folder only).</param>
    Task<GenericLogHandler.Core.Models.LogStatistics> GetStatisticsAsync(DateTime fromDate, DateTime toDate, string? sourcePathContains = null, CancellationToken cancellationToken = default);

    /// <summary>
    /// Deletes log entries older than the specified date
    /// </summary>
    Task<int> DeleteOlderThanAsync(DateTime cutoffDate, CancellationToken cancellationToken = default);

    /// <summary>
    /// Deletes log entries older than the specified date for a specific log level.
    /// Only deletes entries where Protected = false.
    /// </summary>
    Task<int> DeleteOlderThanByLevelAsync(DateTime cutoffDate, LogLevel level, CancellationToken cancellationToken = default);

    /// <summary>
    /// Gets the count of log entries for each level in a date range
    /// </summary>
    Task<Dictionary<LogLevel, long>> GetLevelCountsAsync(DateTime fromDate, DateTime toDate, CancellationToken cancellationToken = default);

    /// <summary>
    /// Gets the top computers by log count in a date range.
    /// </summary>
    /// <param name="sourcePathContains">Optional: only include entries whose SourceFile contains this substring.</param>
    Task<List<GenericLogHandler.Core.Models.ComputerLogCount>> GetTopComputersAsync(DateTime fromDate, DateTime toDate, int limit = 10, string? sourcePathContains = null, CancellationToken cancellationToken = default);

    /// <summary>
    /// Gets recent error entries
    /// </summary>
    Task<List<LogEntry>> GetRecentErrorsAsync(int hours = 24, int limit = 100, CancellationToken cancellationToken = default);

    /// <summary>
    /// Gets import status for a source/file combination
    /// </summary>
    Task<ImportStatus?> GetImportStatusAsync(string sourceName, string filePath, CancellationToken cancellationToken = default);

    /// <summary>
    /// Updates or creates an import status record
    /// </summary>
    Task<ImportStatus> UpdateImportStatusAsync(ImportStatus status, CancellationToken cancellationToken = default);

    /// <summary>
    /// Gets all import status records
    /// </summary>
    Task<List<ImportStatus>> GetAllImportStatusAsync(CancellationToken cancellationToken = default);

    /// <summary>
    /// Gets distinct values for a specified field, for use in filter dropdowns
    /// </summary>
    /// <param name="fieldName">Property name on LogEntry (e.g., "ComputerName", "SourceType")</param>
    /// <param name="limit">Maximum number of distinct values to return</param>
    Task<List<string>> GetDistinctValuesAsync(string fieldName, int limit = 100, CancellationToken cancellationToken = default);

    /// <summary>
    /// Gets log entries by their IDs
    /// </summary>
    Task<List<LogEntry>> GetByIdsAsync(IEnumerable<long> ids, CancellationToken cancellationToken = default);

    /// <summary>
    /// Sets the Protected flag for multiple log entries
    /// </summary>
    Task<int> SetProtectedAsync(IEnumerable<long> ids, bool isProtected, CancellationToken cancellationToken = default);

    /// <summary>
    /// Counts how many of the specified IDs are protected
    /// </summary>
    Task<int> CountProtectedAsync(IEnumerable<long> ids, CancellationToken cancellationToken = default);

    /// <summary>
    /// Deletes log entries by their IDs
    /// </summary>
    Task<int> DeleteByIdsAsync(IEnumerable<long> ids, bool includeProtected = false, CancellationToken cancellationToken = default);

    /// <summary>
    /// Gets all active import level filters ordered by priority
    /// </summary>
    Task<List<GenericLogHandler.Core.Models.Configuration.ImportLevelFilter>> GetActiveImportLevelFiltersAsync(CancellationToken cancellationToken = default);
}

/// <summary>
/// Search criteria for log entries
/// </summary>
public class LogSearchCriteria
{
    public DateTime? FromDate { get; set; }
    public DateTime? ToDate { get; set; }
    public List<LogLevel>? Levels { get; set; }
    public string? ComputerName { get; set; }
    public string? UserName { get; set; }
    public string? MessageText { get; set; }
    public string? ExceptionText { get; set; }
    public string? RegexPattern { get; set; }
    public string? FunctionName { get; set; }
    public string? SourceFile { get; set; }
    public string? SourceType { get; set; }
    
    // Business identifier search fields
    public string? AlertId { get; set; }
    public string? Ordrenr { get; set; }
    public string? Avdnr { get; set; }
    public string? JobName { get; set; }
    public string? JobStatus { get; set; }
    
    public int Page { get; set; } = 1;
    public int PageSize { get; set; } = 50;
    public string SortBy { get; set; } = "Timestamp";
    public bool SortDescending { get; set; } = true;
}

/// <summary>
/// Paged result container
/// </summary>
public class PagedResult<T>
{
    public List<T> Items { get; set; } = new();
    public int TotalCount { get; set; }
    public int Page { get; set; }
    public int PageSize { get; set; }
    public int TotalPages => (int)Math.Ceiling((double)TotalCount / PageSize);
    public bool HasNextPage => Page < TotalPages;
    public bool HasPreviousPage => Page > 1;
}

