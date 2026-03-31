using Microsoft.EntityFrameworkCore;
using Microsoft.Extensions.Logging;
using GenericLogHandler.Core.Interfaces;
using GenericLogHandler.Core.Models;
using System.Linq.Dynamic.Core;
using System.Text.RegularExpressions;

namespace GenericLogHandler.Data.Repositories;

/// <summary>
/// PostgreSQL implementation of the log repository
/// </summary>
public class LogRepository : ILogRepository
{
    private readonly LoggingDbContext _context;
    private readonly ILogger<LogRepository> _logger;

    public LogRepository(LoggingDbContext context, ILogger<LogRepository> logger)
    {
        _context = context;
        _logger = logger;
    }

    public async Task<LogEntry> AddAsync(LogEntry logEntry, CancellationToken cancellationToken = default)
    {
        try
        {
            logEntry.Message = LogEntry.TrimMultiSpace(logEntry.Message);
            logEntry.GenerateConcatenatedSearchString();
            
            _context.LogEntries.Add(logEntry);
            await _context.SaveChangesAsync(cancellationToken);
            
            _logger.LogDebug("Added log entry {Id} from {ComputerName}", logEntry.Id, logEntry.ComputerName);
            return logEntry;
        }
        catch (Exception ex)
        {
            _logger.LogError(ex, "Error adding log entry from {ComputerName}", logEntry.ComputerName);
            throw;
        }
    }

    public async Task<int> AddBatchAsync(IEnumerable<LogEntry> logEntries, CancellationToken cancellationToken = default)
    {
        try
        {
            var entries = logEntries.ToList();
            
            // Normalize messages (trim multi spaces) and generate concatenated search strings
            foreach (var entry in entries)
            {
                entry.Message = LogEntry.TrimMultiSpace(entry.Message);
                entry.GenerateConcatenatedSearchString();
            }

            _context.LogEntries.AddRange(entries);
            var result = await _context.SaveChangesAsync(cancellationToken);
            
            _logger.LogInformation("Added batch of {Count} log entries", entries.Count);
            return result;
        }
        catch (Exception ex)
        {
            _logger.LogError(ex, "Error adding batch of {Count} log entries", logEntries.Count());
            throw;
        }
    }

    public async Task<LogEntry?> GetByIdAsync(Guid id, CancellationToken cancellationToken = default)
    {
        try
        {
            return await _context.LogEntries
                .FirstOrDefaultAsync(x => x.Id == id, cancellationToken);
        }
        catch (Exception ex)
        {
            _logger.LogError(ex, "Error retrieving log entry {Id}", id);
            throw;
        }
    }

    public async Task<GenericLogHandler.Core.Interfaces.PagedResult<LogEntry>> SearchAsync(LogSearchCriteria criteria, CancellationToken cancellationToken = default)
    {
        try
        {
            var query = BuildSearchQuery(criteria);
            
            var totalCount = await query.CountAsync(cancellationToken);
            
            var sortExpression = BuildSortExpression(criteria.SortBy, criteria.SortDescending);
            var items = await query
                .OrderBy(sortExpression)
                .Skip((criteria.Page - 1) * criteria.PageSize)
                .Take(criteria.PageSize)
                .ToListAsync(cancellationToken);

            _logger.LogDebug("Search returned {Count} of {Total} results", items.Count, totalCount);

            return new GenericLogHandler.Core.Interfaces.PagedResult<LogEntry>
            {
                Items = items,
                TotalCount = totalCount,
                Page = criteria.Page,
                PageSize = criteria.PageSize
            };
        }
        catch (Exception ex)
        {
            _logger.LogError(ex, "Error searching log entries");
            throw;
        }
    }

    public async Task<GenericLogHandler.Core.Models.LogStatistics> GetStatisticsAsync(DateTime fromDate, DateTime toDate, string? sourcePathContains = null, CancellationToken cancellationToken = default)
    {
        try
        {
            var query = _context.LogEntries
                .Where(x => x.Timestamp >= fromDate && x.Timestamp <= toDate);

            if (!string.IsNullOrEmpty(sourcePathContains))
            {
                query = query.Where(x => x.SourceFile != null && x.SourceFile.Contains(sourcePathContains));
            }

            var stats = new GenericLogHandler.Core.Models.LogStatistics
            {
                TotalEntries = await query.CountAsync(cancellationToken),
                ErrorEntries = await query.CountAsync(x => x.Level == Core.Models.LogLevel.ERROR || x.Level == Core.Models.LogLevel.FATAL, cancellationToken),
                WarningEntries = await query.CountAsync(x => x.Level == Core.Models.LogLevel.WARN, cancellationToken),
                InfoEntries = await query.CountAsync(x => x.Level == Core.Models.LogLevel.INFO, cancellationToken),
                UniqueComputers = await query.Select(x => x.ComputerName).Distinct().CountAsync(cancellationToken),
                UniqueUsers = await query.Where(x => !string.IsNullOrEmpty(x.UserName)).Select(x => x.UserName).Distinct().CountAsync(cancellationToken),
                FirstEntry = await query.MinAsync(x => (DateTime?)x.Timestamp, cancellationToken),
                LastEntry = await query.MaxAsync(x => (DateTime?)x.Timestamp, cancellationToken)
            };

            // Get top sources
            stats.TopSources = await query
                .GroupBy(x => x.SourceType)
                .Select(g => new { Source = g.Key, Count = g.LongCount() })
                .OrderByDescending(x => x.Count)
                .Take(10)
                .ToDictionaryAsync(x => x.Source, x => x.Count, cancellationToken);

            // Get top error types
            stats.TopErrorTypes = await query
                .Where(x => !string.IsNullOrEmpty(x.ErrorId))
                .GroupBy(x => x.ErrorId!)
                .Select(g => new { ErrorId = g.Key, Count = g.LongCount() })
                .OrderByDescending(x => x.Count)
                .Take(10)
                .ToDictionaryAsync(x => x.ErrorId, x => x.Count, cancellationToken);

            _logger.LogDebug("Generated statistics for period {FromDate} to {ToDate}", fromDate, toDate);
            return stats;
        }
        catch (Exception ex)
        {
            _logger.LogError(ex, "Error generating statistics");
            throw;
        }
    }

    public async Task<int> DeleteOlderThanAsync(DateTime cutoffDate, CancellationToken cancellationToken = default)
    {
        try
        {
            var deleteQuery = _context.LogEntries.Where(x => x.Timestamp < cutoffDate);
            var count = await deleteQuery.CountAsync(cancellationToken);
            
            // Delete in batches to avoid long-running transactions
            const int batchSize = 10000;
            var totalDeleted = 0;
            
            while (true)
            {
                var batch = await deleteQuery.Take(batchSize).ToListAsync(cancellationToken);
                if (!batch.Any()) break;
                
                _context.LogEntries.RemoveRange(batch);
                await _context.SaveChangesAsync(cancellationToken);
                totalDeleted += batch.Count;
                
                _logger.LogDebug("Deleted batch of {Count} entries (total: {Total})", batch.Count, totalDeleted);
            }

            _logger.LogInformation("Deleted {Count} log entries older than {CutoffDate}", totalDeleted, cutoffDate);
            return totalDeleted;
        }
        catch (Exception ex)
        {
            _logger.LogError(ex, "Error deleting old log entries");
            throw;
        }
    }

    public async Task<int> DeleteOlderThanByLevelAsync(DateTime cutoffDate, Core.Models.LogLevel level, CancellationToken cancellationToken = default)
    {
        try
        {
            // Only delete non-protected entries
            var deleteQuery = _context.LogEntries
                .Where(x => x.Timestamp < cutoffDate && x.Level == level && !x.Protected);
            
            var count = await deleteQuery.CountAsync(cancellationToken);
            if (count == 0)
            {
                _logger.LogDebug("No {Level} entries older than {CutoffDate} to delete", level, cutoffDate);
                return 0;
            }
            
            // Delete in batches to avoid long-running transactions
            const int batchSize = 10000;
            var totalDeleted = 0;
            
            while (true)
            {
                var batch = await deleteQuery.Take(batchSize).ToListAsync(cancellationToken);
                if (!batch.Any()) break;
                
                _context.LogEntries.RemoveRange(batch);
                await _context.SaveChangesAsync(cancellationToken);
                totalDeleted += batch.Count;
                
                _logger.LogDebug("Deleted batch of {Count} {Level} entries (total: {Total})", batch.Count, level, totalDeleted);
            }

            _logger.LogInformation("Deleted {Count} {Level} log entries older than {CutoffDate}", totalDeleted, level, cutoffDate);
            return totalDeleted;
        }
        catch (Exception ex)
        {
            _logger.LogError(ex, "Error deleting old {Level} log entries", level);
            throw;
        }
    }

    public async Task<Dictionary<Core.Models.LogLevel, long>> GetLevelCountsAsync(DateTime fromDate, DateTime toDate, CancellationToken cancellationToken = default)
    {
        try
        {
            var query = _context.LogEntries
                .Where(x => x.Timestamp >= fromDate && x.Timestamp <= toDate);

            var counts = await query
                .GroupBy(x => x.Level)
                .Select(g => new { Level = g.Key, Count = g.LongCount() })
                .ToDictionaryAsync(x => x.Level, x => x.Count, cancellationToken);

            return counts;
        }
        catch (Exception ex)
        {
            _logger.LogError(ex, "Error getting level counts");
            throw;
        }
    }

    public async Task<List<GenericLogHandler.Core.Models.ComputerLogCount>> GetTopComputersAsync(DateTime fromDate, DateTime toDate, int limit = 10, string? sourcePathContains = null, CancellationToken cancellationToken = default)
    {
        try
        {
            var query = _context.LogEntries
                .Where(x => x.Timestamp >= fromDate && x.Timestamp <= toDate);

            if (!string.IsNullOrEmpty(sourcePathContains))
            {
                query = query.Where(x => x.SourceFile != null && x.SourceFile.Contains(sourcePathContains));
            }

            var computers = await query
                .GroupBy(x => x.ComputerName)
                .Select(g => new GenericLogHandler.Core.Models.ComputerLogCount
                {
                    ComputerName = g.Key,
                    TotalLogs = g.LongCount(),
                    ErrorCount = g.LongCount(x => x.Level == Core.Models.LogLevel.ERROR || x.Level == Core.Models.LogLevel.FATAL),
                    WarningCount = g.LongCount(x => x.Level == Core.Models.LogLevel.WARN),
                    UniqueUsers = g.Where(x => !string.IsNullOrEmpty(x.UserName)).Select(x => x.UserName).Distinct().Count(),
                    LastActivity = g.Max(x => (DateTime?)x.Timestamp)
                })
                .OrderByDescending(x => x.TotalLogs)
                .Take(limit)
                .ToListAsync(cancellationToken);

            return computers;
        }
        catch (Exception ex)
        {
            _logger.LogError(ex, "Error getting top computers");
            throw;
        }
    }

    public async Task<List<LogEntry>> GetRecentErrorsAsync(int hours = 24, int limit = 100, CancellationToken cancellationToken = default)
    {
        try
        {
            var cutoffTime = DateTime.UtcNow.AddHours(-hours);
            
            var errors = await _context.LogEntries
                .Where(x => x.Timestamp >= cutoffTime && 
                           (x.Level == Core.Models.LogLevel.ERROR || x.Level == Core.Models.LogLevel.FATAL))
                .OrderByDescending(x => x.Timestamp)
                .Take(limit)
                .ToListAsync(cancellationToken);

            return errors;
        }
        catch (Exception ex)
        {
            _logger.LogError(ex, "Error getting recent errors");
            throw;
        }
    }

    private IQueryable<LogEntry> BuildSearchQuery(LogSearchCriteria criteria)
    {
        var query = _context.LogEntries.AsQueryable();

        if (criteria.FromDate.HasValue)
            query = query.Where(x => x.Timestamp >= criteria.FromDate.Value);

        if (criteria.ToDate.HasValue)
            query = query.Where(x => x.Timestamp <= criteria.ToDate.Value);

        if (criteria.Levels?.Any() == true)
            query = query.Where(x => criteria.Levels.Contains(x.Level));

        if (!string.IsNullOrEmpty(criteria.ComputerName))
            query = query.Where(x => x.ComputerName.Contains(criteria.ComputerName));

        if (!string.IsNullOrEmpty(criteria.UserName))
            query = query.Where(x => x.UserName.Contains(criteria.UserName));

        if (!string.IsNullOrEmpty(criteria.MessageText))
            query = query.Where(x => x.Message.Contains(criteria.MessageText));

        if (!string.IsNullOrEmpty(criteria.ExceptionText))
            query = query.Where(x => x.ExceptionType != null && x.ExceptionType.Contains(criteria.ExceptionText));

        if (!string.IsNullOrEmpty(criteria.FunctionName))
            query = query.Where(x => x.FunctionName.Contains(criteria.FunctionName));

        if (!string.IsNullOrEmpty(criteria.SourceFile))
            query = query.Where(x => x.SourceFile.Contains(criteria.SourceFile));

        if (!string.IsNullOrEmpty(criteria.SourceType))
            query = query.Where(x => x.SourceType == criteria.SourceType);

        // Business identifier filters
        if (!string.IsNullOrEmpty(criteria.AlertId))
            query = query.Where(x => x.AlertId != null && x.AlertId.Contains(criteria.AlertId));

        if (!string.IsNullOrEmpty(criteria.Ordrenr))
            query = query.Where(x => x.Ordrenr != null && x.Ordrenr.Contains(criteria.Ordrenr));

        if (!string.IsNullOrEmpty(criteria.Avdnr))
            query = query.Where(x => x.Avdnr != null && x.Avdnr.Contains(criteria.Avdnr));

        if (!string.IsNullOrEmpty(criteria.JobName))
            query = query.Where(x => x.JobName != null && x.JobName.Contains(criteria.JobName));

        if (!string.IsNullOrEmpty(criteria.JobStatus))
            query = query.Where(x => x.JobStatus != null && x.JobStatus.Contains(criteria.JobStatus));

        // PostgreSQL regex search on concatenated string
        if (!string.IsNullOrEmpty(criteria.RegexPattern))
        {
            try
            {
                // Validate regex pattern
                _ = new Regex(criteria.RegexPattern);
                query = query.Where(x => EF.Functions.Like(x.ConcatenatedSearchString, $"%{criteria.RegexPattern}%"));
            }
            catch (ArgumentException ex)
            {
                _logger.LogWarning("Invalid regex pattern: {Pattern}, Error: {Error}", criteria.RegexPattern, ex.Message);
            }
        }

        return query;
    }

    private static string BuildSortExpression(string sortBy, bool descending)
    {
        var direction = descending ? "desc" : "asc";
        
        return sortBy?.ToLower() switch
        {
            "timestamp" => $"Timestamp {direction}",
            "level" => $"Level {direction}",
            "computername" => $"ComputerName {direction}",
            "username" => $"UserName {direction}",
            "message" => $"Message {direction}",
            "functionname" => $"FunctionName {direction}",
            "sourcetype" => $"SourceType {direction}",
            _ => $"Timestamp {direction}"
        };
    }

    /// <summary>
    /// Gets import status for a source/file combination
    /// </summary>
    public async Task<ImportStatus?> GetImportStatusAsync(string sourceName, string filePath, CancellationToken cancellationToken = default)
    {
        try
        {
            return await _context.ImportStatuses
                .FirstOrDefaultAsync(x => x.SourceName == sourceName && x.FilePath == filePath, cancellationToken);
        }
        catch (Exception ex)
        {
            _logger.LogError(ex, "Error getting import status for {SourceName}/{FilePath}", sourceName, filePath);
            throw;
        }
    }

    /// <summary>
    /// Updates or creates an import status record
    /// </summary>
    public async Task<ImportStatus> UpdateImportStatusAsync(ImportStatus status, CancellationToken cancellationToken = default)
    {
        try
        {
            var existing = await _context.ImportStatuses
                .FirstOrDefaultAsync(x => x.SourceName == status.SourceName && x.FilePath == status.FilePath, cancellationToken);

            if (existing != null)
            {
                // Update existing record
                existing.LastProcessedTimestamp = status.LastProcessedTimestamp;
                existing.LastImportTimestamp = DateTime.UtcNow;
                existing.RecordsProcessed = status.RecordsProcessed;
                existing.RecordsFailed = status.RecordsFailed;
                existing.Status = status.Status;
                existing.ErrorMessage = status.ErrorMessage;
                existing.ProcessingDurationMs = status.ProcessingDurationMs;
                existing.Metadata = status.Metadata;
                existing.LastProcessedByteOffset = status.LastProcessedByteOffset;
                existing.FileHash = status.FileHash;
                existing.LastFileSize = status.LastFileSize;
                existing.FileCreationDate = status.FileCreationDate;
                existing.LastProcessedLine = status.LastProcessedLine;
                
                _context.ImportStatuses.Update(existing);
                await _context.SaveChangesAsync(cancellationToken);
                
                _logger.LogDebug("Updated import status for {SourceName}/{FilePath}", status.SourceName, status.FilePath);
                return existing;
            }
            else
            {
                // Create new record
                status.LastImportTimestamp = DateTime.UtcNow;
                _context.ImportStatuses.Add(status);
                await _context.SaveChangesAsync(cancellationToken);
                
                _logger.LogDebug("Created import status for {SourceName}/{FilePath}", status.SourceName, status.FilePath);
                return status;
            }
        }
        catch (Exception ex)
        {
            _logger.LogError(ex, "Error updating import status for {SourceName}/{FilePath}", status.SourceName, status.FilePath);
            throw;
        }
    }

    /// <summary>
    /// Gets all import status records
    /// </summary>
    public async Task<List<ImportStatus>> GetAllImportStatusAsync(CancellationToken cancellationToken = default)
    {
        try
        {
            return await _context.ImportStatuses
                .OrderByDescending(x => x.LastImportTimestamp)
                .ToListAsync(cancellationToken);
        }
        catch (Exception ex)
        {
            _logger.LogError(ex, "Error getting all import statuses");
            throw;
        }
    }

    public async Task<List<string>> GetDistinctValuesAsync(string fieldName, int limit = 100, CancellationToken cancellationToken = default)
    {
        try
        {
            // Build query dynamically based on field name
            IQueryable<string?> query = fieldName switch
            {
                "ComputerName" => _context.LogEntries
                    .Where(e => e.ComputerName != null && e.ComputerName != "")
                    .Select(e => e.ComputerName)
                    .Distinct()
                    .OrderBy(x => x),
                "UserName" => _context.LogEntries
                    .Where(e => e.UserName != null && e.UserName != "")
                    .Select(e => e.UserName)
                    .Distinct()
                    .OrderBy(x => x),
                "SourceType" => _context.LogEntries
                    .Where(e => e.SourceType != null && e.SourceType != "")
                    .Select(e => e.SourceType)
                    .Distinct()
                    .OrderBy(x => x),
                "JobName" => _context.LogEntries
                    .Where(e => e.JobName != null && e.JobName != "")
                    .Select(e => e.JobName)
                    .Distinct()
                    .OrderBy(x => x),
                "FunctionName" => _context.LogEntries
                    .Where(e => e.FunctionName != null && e.FunctionName != "")
                    .Select(e => e.FunctionName)
                    .Distinct()
                    .OrderBy(x => x),
                "SourceFile" => _context.LogEntries
                    .Where(e => e.SourceFile != null && e.SourceFile != "")
                    .Select(e => e.SourceFile)
                    .Distinct()
                    .OrderBy(x => x),
                _ => throw new ArgumentException($"Unsupported field name: {fieldName}")
            };

            var result = await query
                .Take(limit)
                .ToListAsync(cancellationToken);

            return result.Where(x => x != null).Select(x => x!).ToList();
        }
        catch (Exception ex)
        {
            _logger.LogError(ex, "Error getting distinct values for {FieldName}", fieldName);
            throw;
        }
    }

    /// <inheritdoc/>
    public async Task<List<LogEntry>> GetByIdsAsync(IEnumerable<long> ids, CancellationToken cancellationToken = default)
    {
        var idList = ids.ToList();
        if (idList.Count == 0)
            return new List<LogEntry>();

        // Note: LogEntry uses Guid Id, but we accept long for compatibility
        // The API uses internal numeric IDs; we need to convert
        // For now, we'll assume the long is the hash of the Guid or we need to adjust
        // Actually, let's add an InternalId field or use a different approach
        
        // Since LogEntry uses Guid as primary key, we'll accept Guid strings
        // For bulk operations, let's query by a range or use a workaround
        // For simplicity, we'll convert the log entries to use an auto-increment ID
        
        // Temporary: Use the first N entries matching a LIKE pattern or just return based on order
        // This is a limitation - we need to reconsider the bulk ops design
        
        // Better approach: Query using the Guid Id directly
        return await _context.LogEntries
            .Where(e => idList.Contains(e.InternalId))
            .ToListAsync(cancellationToken);
    }

    /// <inheritdoc/>
    public async Task<int> SetProtectedAsync(IEnumerable<long> ids, bool isProtected, CancellationToken cancellationToken = default)
    {
        var idList = ids.ToList();
        if (idList.Count == 0)
            return 0;

        return await _context.LogEntries
            .Where(e => idList.Contains(e.InternalId))
            .ExecuteUpdateAsync(setters => setters.SetProperty(e => e.Protected, isProtected), cancellationToken);
    }

    /// <inheritdoc/>
    public async Task<int> CountProtectedAsync(IEnumerable<long> ids, CancellationToken cancellationToken = default)
    {
        var idList = ids.ToList();
        if (idList.Count == 0)
            return 0;

        return await _context.LogEntries
            .Where(e => idList.Contains(e.InternalId) && e.Protected)
            .CountAsync(cancellationToken);
    }

    /// <inheritdoc/>
    public async Task<int> DeleteByIdsAsync(IEnumerable<long> ids, bool includeProtected = false, CancellationToken cancellationToken = default)
    {
        var idList = ids.ToList();
        if (idList.Count == 0)
            return 0;

        var query = _context.LogEntries.Where(e => idList.Contains(e.InternalId));
        
        if (!includeProtected)
        {
            query = query.Where(e => !e.Protected);
        }

        return await query.ExecuteDeleteAsync(cancellationToken);
    }

    /// <inheritdoc/>
    public async Task<List<Core.Models.Configuration.ImportLevelFilter>> GetActiveImportLevelFiltersAsync(CancellationToken cancellationToken = default)
    {
        return await _context.ImportLevelFilters
            .Where(f => f.IsEnabled)
            .OrderBy(f => f.Priority)
            .ToListAsync(cancellationToken);
    }
}
