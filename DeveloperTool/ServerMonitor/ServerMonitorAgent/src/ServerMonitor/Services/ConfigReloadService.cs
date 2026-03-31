using Microsoft.Extensions.Configuration;
using Microsoft.Extensions.Hosting;
using Microsoft.Extensions.Logging;
using Microsoft.Extensions.Options;
using ServerMonitor.Core.Configuration;

namespace ServerMonitor.Services;

/// <summary>
/// Periodically reloads configuration from appsettings.json
/// </summary>
public class ConfigReloadService : BackgroundService
{
    private readonly ILogger<ConfigReloadService> _logger;
    private readonly IConfiguration _configuration;
    private readonly IOptionsMonitor<SurveillanceConfiguration> _configMonitor;

    public ConfigReloadService(
        ILogger<ConfigReloadService> logger,
        IConfiguration configuration,
        IOptionsMonitor<SurveillanceConfiguration> configMonitor)
    {
        _logger = logger;
        _configuration = configuration;
        _configMonitor = configMonitor;
    }

    protected override async Task ExecuteAsync(CancellationToken stoppingToken)
    {
        var intervalMinutes = _configMonitor.CurrentValue.Runtime.ConfigReloadIntervalMinutes;

        if (!intervalMinutes.HasValue || intervalMinutes.Value <= 0)
        {
            _logger.LogInformation("⚙️ Config reload service disabled (ConfigReloadIntervalMinutes not set)");
            return;
        }

        _logger.LogInformation("⚙️ Config reload service started: checking every {Interval} minutes", intervalMinutes.Value);

        // Subscribe to config changes
        _configMonitor.OnChange(config =>
        {
            _logger.LogInformation("🔄 Configuration changed - settings reloaded automatically");
            _logger.LogDebug("New config: MonitoringEnabled={Enabled}, ExportEnabled={ExportEnabled}, RestApiEnabled={ApiEnabled}",
                config.General.MonitoringEnabled,
                config.ExportSettings.Enabled,
                config.RestApi?.Enabled ?? false);
        });

        while (!stoppingToken.IsCancellationRequested)
        {
            try
            {
                await Task.Delay(TimeSpan.FromMinutes(intervalMinutes.Value), stoppingToken);

                // IConfiguration with reloadOnChange=true handles file watching automatically
                // Just log that we're monitoring for changes
                _logger.LogDebug("⚙️ Config reload check (IConfiguration monitors file automatically)");
                
                // Force a read to trigger any pending reloads
                var currentConfig = _configMonitor.CurrentValue;
                _logger.LogDebug("Config timestamp check: MonitoringEnabled={Enabled}", currentConfig.General.MonitoringEnabled);
            }
            catch (OperationCanceledException)
            {
                // Normal shutdown
                break;
            }
            catch (Exception ex)
            {
                _logger.LogError(ex, "Error in config reload service");
            }
        }

        _logger.LogInformation("⚙️ Config reload service stopped");
    }
}

