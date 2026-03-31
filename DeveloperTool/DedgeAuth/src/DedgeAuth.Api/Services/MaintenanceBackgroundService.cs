using Microsoft.Extensions.Options;
using DedgeAuth.Core.Models;
using DedgeAuth.Services;

namespace DedgeAuth.Api.Services;
// test
public class MaintenanceBackgroundService : BackgroundService
{
    private readonly IServiceProvider _services;
    private readonly ILogger<MaintenanceBackgroundService> _logger;
    private readonly MaintenanceOptions _options;

    public MaintenanceBackgroundService(
        IServiceProvider services,
        IOptions<MaintenanceOptions> options,
        ILogger<MaintenanceBackgroundService> logger)
    {
        _services = services;
        _options = options.Value;
        _logger = logger;
    }

    protected override async Task ExecuteAsync(CancellationToken stoppingToken)
    {
        _logger.LogInformation("Maintenance background service started. Interval: {Hours}h, Visit retention: {Days} days",
            _options.CleanupIntervalHours, _options.VisitRetentionDays);

        while (!stoppingToken.IsCancellationRequested)
        {
            try
            {
                await Task.Delay(TimeSpan.FromHours(_options.CleanupIntervalHours), stoppingToken);
            }
            catch (OperationCanceledException)
            {
                break;
            }

            await RunCleanupAsync();
        }
    }

    private async Task RunCleanupAsync()
    {
        _logger.LogInformation("Scheduled maintenance cleanup starting");
        try
        {
            using var scope = _services.CreateScope();
            var maintenance = scope.ServiceProvider.GetRequiredService<MaintenanceService>();

            var tokenResult = await maintenance.CleanupExpiredTokensAsync();
            var visitCount = await maintenance.CleanupOldVisitsAsync();

            _logger.LogInformation(
                "Scheduled maintenance complete: {LoginTokens} login tokens, {RefreshTokens} refresh tokens, {Visits} visits removed",
                tokenResult.LoginTokensRemoved, tokenResult.RefreshTokensRemoved, visitCount);
        }
        catch (Exception ex)
        {
            _logger.LogError(ex, "Scheduled maintenance cleanup failed");
        }
    }
}
