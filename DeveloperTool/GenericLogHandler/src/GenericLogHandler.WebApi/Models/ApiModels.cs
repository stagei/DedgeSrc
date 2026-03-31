using GenericLogHandler.Core.Models;
using System.ComponentModel.DataAnnotations;

namespace GenericLogHandler.WebApi.Models;

/// <summary>
/// Standard API response wrapper
/// </summary>
public class ApiResponse<T>
{
    public bool Success { get; set; }
    public T? Data { get; set; }
    public string? Error { get; set; }
    public DateTime Timestamp { get; set; } = DateTime.UtcNow;

    public static ApiResponse<T> CreateSuccess(T data) => new() { Success = true, Data = data };
    public static ApiResponse<T> CreateError(string error) => new() { Success = false, Error = error };
}

/// <summary>
/// Log search request model
/// </summary>
public class LogSearchRequest
{
    public DateTime? FromDate { get; set; }
    public DateTime? ToDate { get; set; }
    public List<string>? Levels { get; set; }
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
    
    [Range(1, int.MaxValue)]
    public int Page { get; set; } = 1;
    
    [Range(1, 1000)]
    public int PageSize { get; set; } = 50;
    
    public string SortBy { get; set; } = "Timestamp";
    public bool SortDescending { get; set; } = true;
}

/// <summary>
/// JSON export request with field selection options
/// </summary>
public class JsonExportRequest : LogSearchRequest
{
    /// <summary>
    /// If true, output formatted JSON with indentation
    /// </summary>
    public bool PrettyPrint { get; set; } = true;
    
    /// <summary>
    /// Maximum entries to export (default 10000)
    /// </summary>
    [Range(1, 50000)]
    public int MaxEntries { get; set; } = 10000;
    
    /// <summary>
    /// Only include these fields in output (if specified)
    /// </summary>
    public List<string>? IncludeFields { get; set; }
    
    /// <summary>
    /// Exclude these fields from output (ignored if IncludeFields is set)
    /// </summary>
    public List<string>? ExcludeFields { get; set; }
}

/// <summary>
/// Bulk export request model
/// </summary>
public class BulkExportRequest
{
    /// <summary>
    /// Log entry IDs to export
    /// </summary>
    [Required]
    public List<long> Ids { get; set; } = new();
    
    /// <summary>
    /// Export format: csv (default) or json
    /// </summary>
    public string Format { get; set; } = "csv";
}

/// <summary>
/// Bulk protect request model
/// </summary>
public class BulkProtectRequest
{
    /// <summary>
    /// Log entry IDs to update
    /// </summary>
    [Required]
    public List<long> Ids { get; set; } = new();
    
    /// <summary>
    /// Whether to mark as protected (true) or unprotected (false)
    /// </summary>
    public bool Protected { get; set; } = true;
}

/// <summary>
/// Bulk delete request model
/// </summary>
public class BulkDeleteRequest
{
    /// <summary>
    /// Log entry IDs to delete
    /// </summary>
    [Required]
    public List<long> Ids { get; set; } = new();
    
    /// <summary>
    /// If true, also delete protected entries
    /// </summary>
    public bool IncludeProtected { get; set; } = false;
}

/// <summary>
/// Log entry DTO for API responses
/// </summary>
public class LogEntryDto
{
    public Guid Id { get; set; }
    public long InternalId { get; set; }
    public DateTime Timestamp { get; set; }
    public bool Protected { get; set; }
    public string Level { get; set; } = string.Empty;
    public int ProcessId { get; set; }
    public string Location { get; set; } = string.Empty;
    public string FunctionName { get; set; } = string.Empty;
    public int LineNumber { get; set; }
    public string ComputerName { get; set; } = string.Empty;
    public string UserName { get; set; } = string.Empty;
    public string Message { get; set; } = string.Empty;
    public string? ErrorId { get; set; }
    public string? AlertId { get; set; }
    public string? Ordrenr { get; set; }
    public string? Avdnr { get; set; }
    public string? JobName { get; set; }
    public string? JobStatus { get; set; }
    public string? ExceptionType { get; set; }
    public string? StackTrace { get; set; }
    public string? InnerException { get; set; }
    public string? CommandInvocation { get; set; }
    public int? ScriptLineNumber { get; set; }
    public string? ScriptName { get; set; }
    public int? Position { get; set; }
    public string SourceFile { get; set; } = string.Empty;
    public string SourceType { get; set; } = string.Empty;
    public DateTime ImportTimestamp { get; set; }

    public static LogEntryDto FromLogEntry(LogEntry entry)
    {
        return new LogEntryDto
        {
            Id = entry.Id,
            InternalId = entry.InternalId,
            Timestamp = entry.Timestamp,
            Protected = entry.Protected,
            Level = entry.Level.ToString(),
            ProcessId = entry.ProcessId,
            Location = entry.Location,
            FunctionName = entry.FunctionName,
            LineNumber = entry.LineNumber,
            ComputerName = entry.ComputerName,
            UserName = entry.UserName,
            Message = entry.Message,
            ErrorId = entry.ErrorId,
            AlertId = entry.AlertId,
            Ordrenr = entry.Ordrenr,
            Avdnr = entry.Avdnr,
            JobName = entry.JobName,
            JobStatus = entry.JobStatus,
            ExceptionType = entry.ExceptionType,
            StackTrace = entry.StackTrace,
            InnerException = entry.InnerException,
            CommandInvocation = entry.CommandInvocation,
            ScriptLineNumber = entry.ScriptLineNumber,
            ScriptName = entry.ScriptName,
            Position = entry.Position,
            SourceFile = entry.SourceFile,
            SourceType = entry.SourceType,
            ImportTimestamp = entry.ImportTimestamp
        };
    }
}

/// <summary>
/// Log statistics DTO
/// </summary>
public class LogStatisticsDto
{
    public long TotalEntries { get; set; }
    public long ErrorEntries { get; set; }
    public long WarningEntries { get; set; }
    public long InfoEntries { get; set; }
    public int UniqueComputers { get; set; }
    public int UniqueUsers { get; set; }
    public DateTime? FirstEntry { get; set; }
    public DateTime? LastEntry { get; set; }
    public Dictionary<string, long> TopSources { get; set; } = new();
    public Dictionary<string, long> TopErrorTypes { get; set; } = new();

    public static LogStatisticsDto FromLogStatistics(LogStatistics stats)
    {
        return new LogStatisticsDto
        {
            TotalEntries = stats.TotalEntries,
            ErrorEntries = stats.ErrorEntries,
            WarningEntries = stats.WarningEntries,
            InfoEntries = stats.InfoEntries,
            UniqueComputers = stats.UniqueComputers,
            UniqueUsers = stats.UniqueUsers,
            FirstEntry = stats.FirstEntry,
            LastEntry = stats.LastEntry,
            TopSources = stats.TopSources,
            TopErrorTypes = stats.TopErrorTypes
        };
    }
}

/// <summary>
/// Computer log count DTO
/// </summary>
public class ComputerLogCountDto
{
    public string ComputerName { get; set; } = string.Empty;
    public long TotalLogs { get; set; }
    public long ErrorCount { get; set; }
    public long WarningCount { get; set; }
    public int UniqueUsers { get; set; }
    public DateTime? LastActivity { get; set; }

    public static ComputerLogCountDto FromComputerLogCount(ComputerLogCount count)
    {
        return new ComputerLogCountDto
        {
            ComputerName = count.ComputerName,
            TotalLogs = count.TotalLogs,
            ErrorCount = count.ErrorCount,
            WarningCount = count.WarningCount,
            UniqueUsers = count.UniqueUsers,
            LastActivity = count.LastActivity
        };
    }
}

/// <summary>
/// Dashboard summary DTO
/// </summary>
public class DashboardSummaryDto
{
    public long TotalLogsToday { get; set; }
    public long ErrorsToday { get; set; }
    public long WarningsToday { get; set; }
    public int ActiveComputers { get; set; }
    /// <summary>When set, stats are filtered to entries whose SourceFile contains this path (e.g. "Psh" for \\...\CommonLogging\Psh only).</summary>
    public string? SourceFilter { get; set; }
    public List<HourlyLogCountDto> HourlyTrends { get; set; } = new();
    public List<ComputerLogCountDto> TopComputers { get; set; } = new();
    public List<ErrorSummaryDto> TopErrors { get; set; } = new();
}

/// <summary>
/// Hourly log count for trend charts
/// </summary>
public class HourlyLogCountDto
{
    public DateTime Hour { get; set; }
    public long LogCount { get; set; }
    public long ErrorCount { get; set; }
}

/// <summary>
/// Error summary for dashboard
/// </summary>
public class ErrorSummaryDto
{
    public string ErrorId { get; set; } = string.Empty;
    public string ExceptionType { get; set; } = string.Empty;
    public long Count { get; set; }
    public DateTime LastOccurrence { get; set; }
    public List<string> AffectedComputers { get; set; } = new();
}

/// <summary>
/// Saved filter DTO for API responses
/// </summary>
public class SavedFilterDto
{
    public Guid Id { get; set; }
    public string Name { get; set; } = string.Empty;
    public string? Description { get; set; }
    public string FilterJson { get; set; } = "{}";
    public string CreatedBy { get; set; } = string.Empty;
    public DateTime CreatedAt { get; set; }
    public DateTime? UpdatedAt { get; set; }
    public bool IsAlertEnabled { get; set; }
    public string? AlertConfig { get; set; }
    public DateTime? LastEvaluatedAt { get; set; }
    public DateTime? LastTriggeredAt { get; set; }
    public bool IsShared { get; set; }
    public string? Category { get; set; }

    public static SavedFilterDto FromSavedFilter(SavedFilter filter)
    {
        return new SavedFilterDto
        {
            Id = filter.Id,
            Name = filter.Name,
            Description = filter.Description,
            FilterJson = filter.FilterJson,
            CreatedBy = filter.CreatedBy,
            CreatedAt = filter.CreatedAt,
            UpdatedAt = filter.UpdatedAt,
            IsAlertEnabled = filter.IsAlertEnabled,
            AlertConfig = filter.AlertConfig,
            LastEvaluatedAt = filter.LastEvaluatedAt,
            LastTriggeredAt = filter.LastTriggeredAt,
            IsShared = filter.IsShared,
            Category = filter.Category
        };
    }
}

/// <summary>
/// Request model for creating a saved filter
/// </summary>
public class SavedFilterCreateRequest
{
    [Required]
    [StringLength(200)]
    public string Name { get; set; } = string.Empty;
    
    [StringLength(1000)]
    public string? Description { get; set; }
    
    public string? FilterJson { get; set; }
    
    public bool IsAlertEnabled { get; set; }
    
    public string? AlertConfig { get; set; }
    
    public bool IsShared { get; set; }
    
    [StringLength(100)]
    public string? Category { get; set; }
}

/// <summary>
/// Request model for updating a saved filter
/// </summary>
public class SavedFilterUpdateRequest
{
    [StringLength(200)]
    public string? Name { get; set; }
    
    [StringLength(1000)]
    public string? Description { get; set; }
    
    public string? FilterJson { get; set; }
    
    public bool? IsAlertEnabled { get; set; }
    
    public string? AlertConfig { get; set; }
    
    public bool? IsShared { get; set; }
    
    [StringLength(100)]
    public string? Category { get; set; }
}

/// <summary>
/// Request model for previewing a filter
/// </summary>
public class FilterPreviewRequest
{
    [Required]
    public string FilterJson { get; set; } = "{}";
    
    [Range(1, 100)]
    public int Limit { get; set; } = 10;
}

/// <summary>
/// Result model for filter preview
/// </summary>
public class FilterPreviewResult
{
    public long TotalCount { get; set; }
    public List<LogEntryDto> SampleEntries { get; set; } = new();
}

/// <summary>
/// Alert history DTO for API responses
/// </summary>
public class AlertHistoryDto
{
    public Guid Id { get; set; }
    public Guid FilterId { get; set; }
    public string FilterName { get; set; } = string.Empty;
    public DateTime TriggeredAt { get; set; }
    public int MatchCount { get; set; }
    public string ActionType { get; set; } = string.Empty;
    public string? ActionTaken { get; set; }
    public bool Success { get; set; }
    public string? ErrorMessage { get; set; }
    public long ExecutionDurationMs { get; set; }

    public static AlertHistoryDto FromAlertHistory(AlertHistory history)
    {
        return new AlertHistoryDto
        {
            Id = history.Id,
            FilterId = history.FilterId,
            FilterName = history.FilterName,
            TriggeredAt = history.TriggeredAt,
            MatchCount = history.MatchCount,
            ActionType = history.ActionType,
            ActionTaken = history.ActionTaken,
            Success = history.Success,
            ErrorMessage = history.ErrorMessage,
            ExecutionDurationMs = history.ExecutionDurationMs
        };
    }
}
