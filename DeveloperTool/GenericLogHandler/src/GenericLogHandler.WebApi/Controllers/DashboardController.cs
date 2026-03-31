using Microsoft.AspNetCore.Mvc;
using Microsoft.EntityFrameworkCore;
using GenericLogHandler.Core.Interfaces;
using GenericLogHandler.Data;
using GenericLogHandler.WebApi.Models;

namespace GenericLogHandler.WebApi.Controllers;

/// <summary>
/// API controller for dashboard data
/// </summary>
[ApiController]
[Route("api/[controller]")]
public class DashboardController : ControllerBase
{
    private readonly ILogRepository _repository;
    private readonly LoggingDbContext _context;
    private readonly ILogger<DashboardController> _logger;

    public DashboardController(ILogRepository repository, LoggingDbContext context, ILogger<DashboardController> logger)
    {
        _repository = repository;
        _context = context;
        _logger = logger;
    }

    /// <summary>
    /// Get dashboard summary data.
    /// "Today" uses server local date. Optional sourcePath filters to entries whose SourceFile contains that path (e.g. "CommonLogging\\Psh" for Psh folder only).
    /// </summary>
    [HttpGet("summary")]
    public async Task<ActionResult<ApiResponse<DashboardSummaryDto>>> GetDashboardSummary([FromQuery] string? sourcePath = null)
    {
        try
        {
            // Use local calendar day boundaries converted to UTC for PostgreSQL compatibility
            var localToday = DateTime.Now.Date;
            var today = localToday.ToUniversalTime();
            var tomorrow = localToday.AddDays(1).ToUniversalTime();

            // Get today's statistics (optionally filtered by import source path)
            var todayStats = await _repository.GetStatisticsAsync(today, tomorrow, sourcePath);
            
            // Get hourly trends for last 24 hours
            var hourlyTrends = await GetHourlyTrends();
            
            // Get top computers (same source filter)
            var topComputers = await _repository.GetTopComputersAsync(today, tomorrow, 5, sourcePath);
            
            // Get top errors
            var topErrors = await GetTopErrors();

            var summary = new DashboardSummaryDto
            {
                TotalLogsToday = todayStats.TotalEntries,
                ErrorsToday = todayStats.ErrorEntries,
                WarningsToday = todayStats.WarningEntries,
                ActiveComputers = todayStats.UniqueComputers,
                SourceFilter = sourcePath,
                HourlyTrends = hourlyTrends,
                TopComputers = topComputers.Select(ComputerLogCountDto.FromComputerLogCount).ToList(),
                TopErrors = topErrors
            };

            return Ok(ApiResponse<DashboardSummaryDto>.CreateSuccess(summary));
        }
        catch (Exception ex)
        {
            _logger.LogError(ex, "Error retrieving dashboard summary");
            return BadRequest(ApiResponse<DashboardSummaryDto>.CreateError("Error retrieving dashboard data: " + ex.Message));
        }
    }

    /// <summary>
    /// Get system health status
    /// </summary>
    [HttpGet("health")]
    public async Task<ActionResult<ApiResponse<object>>> GetSystemHealth()
    {
        try
        {
            var now = DateTime.UtcNow;
            var oneHourAgo = now.AddHours(-1);
            
            // Check recent activity
            var recentLogs = await _repository.GetStatisticsAsync(oneHourAgo, now);
            
            // Get recent errors
            var recentErrors = await _repository.GetRecentErrorsAsync(1, 10);
            
            var health = new
            {
                Status = recentLogs.TotalEntries > 0 ? "Healthy" : "Warning",
                LastLogReceived = recentLogs.LastEntry,
                LogsLastHour = recentLogs.TotalEntries,
                ErrorsLastHour = recentLogs.ErrorEntries,
                RecentErrors = recentErrors.Take(5).Select(e => new
                {
                    e.Timestamp,
                    e.ComputerName,
                    e.ErrorId,
                    e.Message
                })
            };

            return Ok(ApiResponse<object>.CreateSuccess(health));
        }
        catch (Exception ex)
        {
            _logger.LogError(ex, "Error retrieving system health");
            return BadRequest(ApiResponse<object>.CreateError("Error retrieving system health: " + ex.Message));
        }
    }

    /// <summary>
    /// Get log volume trends
    /// </summary>
    [HttpGet("trends")]
    public async Task<ActionResult<ApiResponse<List<HourlyLogCountDto>>>> GetLogTrends(
        [FromQuery] int hours = 24)
    {
        try
        {
            hours = Math.Min(hours, 168); // Limit to 1 week
            var trends = await GetHourlyTrends(hours);
            
            return Ok(ApiResponse<List<HourlyLogCountDto>>.CreateSuccess(trends));
        }
        catch (Exception ex)
        {
            _logger.LogError(ex, "Error retrieving log trends");
            return BadRequest(ApiResponse<List<HourlyLogCountDto>>.CreateError("Error retrieving trends: " + ex.Message));
        }
    }

    private async Task<List<HourlyLogCountDto>> GetHourlyTrends(int hours = 24)
    {
        var trends = new List<HourlyLogCountDto>();
        var endTime = DateTime.UtcNow;
        var startTime = endTime.AddHours(-hours);

        // Group by hour and get counts
        for (var hour = startTime; hour <= endTime; hour = hour.AddHours(1))
        {
            var hourEnd = hour.AddHours(1);
            var stats = await _repository.GetStatisticsAsync(hour, hourEnd);
            
            trends.Add(new HourlyLogCountDto
            {
                Hour = hour,
                LogCount = stats.TotalEntries,
                ErrorCount = stats.ErrorEntries
            });
        }

        return trends;
    }

    private async Task<List<ErrorSummaryDto>> GetTopErrors()
    {
        try
        {
            var yesterday = DateTime.UtcNow.AddDays(-1);
            var now = DateTime.UtcNow;
            
            var recentErrors = await _repository.GetRecentErrorsAsync(24, 1000);
            
            var errorGroups = recentErrors
                .Where(e => !string.IsNullOrEmpty(e.ErrorId))
                .GroupBy(e => new { e.ErrorId, e.ExceptionType })
                .Select(g => new ErrorSummaryDto
                {
                    ErrorId = g.Key.ErrorId ?? string.Empty,
                    ExceptionType = g.Key.ExceptionType ?? string.Empty,
                    Count = g.Count(),
                    LastOccurrence = g.Max(e => e.Timestamp),
                    AffectedComputers = g.Select(e => e.ComputerName).Distinct().ToList()
                })
                .OrderByDescending(e => e.Count)
                .Take(10)
                .ToList();

            return errorGroups;
        }
        catch (Exception ex)
        {
            _logger.LogError(ex, "Error getting top errors");
            return new List<ErrorSummaryDto>();
        }
    }

    /// <summary>
    /// Get database statistics including size and total log entry count
    /// </summary>
    [HttpGet("database-stats")]
    public async Task<ActionResult<ApiResponse<DatabaseStatsDto>>> GetDatabaseStats()
    {
        try
        {
            // Get total log entry count
            var totalEntries = await _context.LogEntries.CountAsync();
            
            // Get database size using PostgreSQL-specific query
            decimal databaseSizeBytes = 0;
            try
            {
                var connection = _context.Database.GetDbConnection();
                await connection.OpenAsync();
                using var command = connection.CreateCommand();
                command.CommandText = "SELECT pg_database_size(current_database())";
                var result = await command.ExecuteScalarAsync();
                if (result != null && result != DBNull.Value)
                {
                    databaseSizeBytes = Convert.ToDecimal(result);
                }
            }
            catch (Exception ex)
            {
                _logger.LogWarning(ex, "Could not retrieve database size - may not be PostgreSQL");
            }
            
            // Convert bytes to GB
            var databaseSizeGb = Math.Round(databaseSizeBytes / (1024m * 1024m * 1024m), 2);
            
            // Extract database server hostname from connection string
            var serverName = "unknown";
            try
            {
                var connStr = _context.Database.GetConnectionString() ?? string.Empty;
                var csb = new Npgsql.NpgsqlConnectionStringBuilder(connStr);
                serverName = csb.Host ?? "unknown";
            }
            catch
            {
                // Fall back to unknown if connection string cannot be parsed
            }

            var stats = new DatabaseStatsDto
            {
                TotalLogEntries = totalEntries,
                DatabaseSizeBytes = (long)databaseSizeBytes,
                DatabaseSizeGb = databaseSizeGb,
                ServerName = serverName,
                LastUpdated = DateTime.UtcNow
            };

            return Ok(ApiResponse<DatabaseStatsDto>.CreateSuccess(stats));
        }
        catch (Exception ex)
        {
            _logger.LogError(ex, "Error retrieving database statistics");
            return BadRequest(ApiResponse<DatabaseStatsDto>.CreateError("Error retrieving database statistics: " + ex.Message));
        }
    }
}

/// <summary>
/// Database statistics DTO
/// </summary>
public class DatabaseStatsDto
{
    public long TotalLogEntries { get; set; }
    public long DatabaseSizeBytes { get; set; }
    public decimal DatabaseSizeGb { get; set; }
    public string ServerName { get; set; } = string.Empty;
    public DateTime LastUpdated { get; set; }
}
