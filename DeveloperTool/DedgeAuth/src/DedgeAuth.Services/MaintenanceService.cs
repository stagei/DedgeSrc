using Microsoft.EntityFrameworkCore;
using Microsoft.Extensions.Logging;
using Microsoft.Extensions.Options;
using DedgeAuth.Core.Models;
using DedgeAuth.Data;

namespace DedgeAuth.Services;

public class MaintenanceService
{
    private readonly AuthDbContext _context;
    private readonly MaintenanceOptions _options;
    private readonly ILogger<MaintenanceService> _logger;

    public MaintenanceService(AuthDbContext context, IOptions<MaintenanceOptions> options, ILogger<MaintenanceService> logger)
    {
        _context = context;
        _options = options.Value;
        _logger = logger;
    }

    public async Task<CleanupResult> CleanupExpiredTokensAsync()
    {
        var now = DateTime.UtcNow;

        var expiredLoginTokens = await _context.LoginTokens
            .Where(t => t.ExpiresAt < now || (t.IsUsed && t.UsedAt.HasValue && t.UsedAt.Value < now.AddDays(-7)))
            .CountAsync();

        if (expiredLoginTokens > 0)
        {
            await _context.LoginTokens
                .Where(t => t.ExpiresAt < now || (t.IsUsed && t.UsedAt.HasValue && t.UsedAt.Value < now.AddDays(-7)))
                .ExecuteDeleteAsync();
        }

        var expiredRefreshTokens = await _context.RefreshTokens
            .Where(t => t.ExpiresAt < now || t.IsRevoked)
            .CountAsync();

        if (expiredRefreshTokens > 0)
        {
            await _context.RefreshTokens
                .Where(t => t.ExpiresAt < now || t.IsRevoked)
                .ExecuteDeleteAsync();
        }

        _logger.LogInformation("Token cleanup: removed {LoginTokens} login tokens, {RefreshTokens} refresh tokens",
            expiredLoginTokens, expiredRefreshTokens);

        return new CleanupResult
        {
            LoginTokensRemoved = expiredLoginTokens,
            RefreshTokensRemoved = expiredRefreshTokens
        };
    }

    public async Task<int> CleanupOldVisitsAsync(int? retentionDays = null)
    {
        var days = retentionDays ?? _options.VisitRetentionDays;
        var cutoff = DateTime.UtcNow.AddDays(-days);

        var count = await _context.UserVisits
            .Where(v => v.VisitedAt < cutoff)
            .CountAsync();

        if (count > 0)
        {
            await _context.UserVisits
                .Where(v => v.VisitedAt < cutoff)
                .ExecuteDeleteAsync();
        }

        _logger.LogInformation("Visit cleanup: removed {Count} visits older than {Days} days", count, days);
        return count;
    }

    public async Task<MaintenanceStats> GetStatsAsync()
    {
        var now = DateTime.UtcNow;
        return new MaintenanceStats
        {
            ExpiredLoginTokens = await _context.LoginTokens.CountAsync(t => t.ExpiresAt < now),
            UsedLoginTokens = await _context.LoginTokens.CountAsync(t => t.IsUsed),
            TotalLoginTokens = await _context.LoginTokens.CountAsync(),
            ExpiredRefreshTokens = await _context.RefreshTokens.CountAsync(t => t.ExpiresAt < now),
            RevokedRefreshTokens = await _context.RefreshTokens.CountAsync(t => t.IsRevoked),
            TotalRefreshTokens = await _context.RefreshTokens.CountAsync(),
            TotalVisits = await _context.UserVisits.CountAsync(),
            VisitRetentionDays = _options.VisitRetentionDays,
            VisitsOlderThanRetention = await _context.UserVisits.CountAsync(v => v.VisitedAt < now.AddDays(-_options.VisitRetentionDays))
        };
    }
}

public class CleanupResult
{
    public int LoginTokensRemoved { get; set; }
    public int RefreshTokensRemoved { get; set; }
}

public class MaintenanceStats
{
    public int ExpiredLoginTokens { get; set; }
    public int UsedLoginTokens { get; set; }
    public int TotalLoginTokens { get; set; }
    public int ExpiredRefreshTokens { get; set; }
    public int RevokedRefreshTokens { get; set; }
    public int TotalRefreshTokens { get; set; }
    public int TotalVisits { get; set; }
    public int VisitRetentionDays { get; set; }
    public int VisitsOlderThanRetention { get; set; }
}
