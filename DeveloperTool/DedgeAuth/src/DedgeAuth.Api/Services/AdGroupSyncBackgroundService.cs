using Microsoft.Extensions.Options;
using DedgeAuth.Core.Models;
using DedgeAuth.Services;

namespace DedgeAuth.Api.Services;

public class AdGroupSyncBackgroundService : BackgroundService
{
    private readonly IServiceProvider _services;
    private readonly ILogger<AdGroupSyncBackgroundService> _logger;
    private readonly AdGroupSyncOptions _options;

    public AdGroupSyncBackgroundService(
        IServiceProvider services,
        IOptions<AdGroupSyncOptions> options,
        ILogger<AdGroupSyncBackgroundService> logger)
    {
        _services = services;
        _options = options.Value;
        _logger = logger;
    }

    protected override async Task ExecuteAsync(CancellationToken stoppingToken)
    {
        if (!_options.Enabled)
        {
            _logger.LogInformation("AD group sync is disabled via configuration");
            return;
        }

        _logger.LogInformation("AD group sync background service started. Interval: {Minutes} min",
            _options.SyncIntervalMinutes);

        // Initial sync after a short delay (let app start up first)
        await Task.Delay(TimeSpan.FromSeconds(30), stoppingToken);

        while (!stoppingToken.IsCancellationRequested)
        {
            await RunSyncAsync();

            try
            {
                await Task.Delay(TimeSpan.FromMinutes(_options.SyncIntervalMinutes), stoppingToken);
            }
            catch (OperationCanceledException)
            {
                break;
            }
        }
    }

    private async Task RunSyncAsync()
    {
        try
        {
            using var scope = _services.CreateScope();
            var syncService = scope.ServiceProvider.GetRequiredService<AdGroupSyncService>();
            var count = await syncService.SyncAllTenantsAsync();
            _logger.LogInformation("AD group sync completed: {Count} groups", count);
        }
        catch (Exception ex)
        {
            _logger.LogError(ex, "AD group sync failed");
        }
    }
}
