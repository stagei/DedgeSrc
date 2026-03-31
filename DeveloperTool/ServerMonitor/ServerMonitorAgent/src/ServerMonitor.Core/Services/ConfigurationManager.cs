using Microsoft.Extensions.Logging;
using Microsoft.Extensions.Options;
using ServerMonitor.Core.Configuration;
using ServerMonitor.Core.Interfaces;

namespace ServerMonitor.Core.Services;

/// <summary>
/// Manages configuration with hot-reload support
/// </summary>
public class ConfigurationManager : IConfigurationManager
{
    private readonly ILogger<ConfigurationManager> _logger;
    private readonly IOptionsMonitor<SurveillanceConfiguration> _optionsMonitor;
    private SurveillanceConfiguration _configuration;

    public event EventHandler<ConfigurationChangedEventArgs>? ConfigurationChanged;

    public SurveillanceConfiguration Configuration => _configuration;

    public ConfigurationManager(
        ILogger<ConfigurationManager> logger,
        IOptionsMonitor<SurveillanceConfiguration> optionsMonitor)
    {
        _logger = logger;
        _optionsMonitor = optionsMonitor;
        _configuration = optionsMonitor.CurrentValue;

        // Subscribe to configuration changes
        _optionsMonitor.OnChange(OnConfigurationChanged);
    }

    private void OnConfigurationChanged(SurveillanceConfiguration newConfiguration)
    {
        _logger.LogInformation("Configuration change detected");
        
        var validation = ValidateConfiguration(newConfiguration);
        if (!validation.IsValid)
        {
            _logger.LogError("Configuration validation failed: {Errors}", 
                string.Join(", ", validation.Errors));
            return;
        }

        var oldConfiguration = _configuration;
        _configuration = newConfiguration;

        ConfigurationChanged?.Invoke(this, new ConfigurationChangedEventArgs
        {
            NewConfiguration = newConfiguration,
            OldConfiguration = oldConfiguration
        });

        _logger.LogInformation("Configuration reloaded successfully");
    }

    public ConfigurationValidationResult Validate()
    {
        return ValidateConfiguration(_configuration);
    }

    public Task ReloadAsync(CancellationToken cancellationToken = default)
    {
        // With IOptionsMonitor, changes are automatically detected
        // This method is here for explicit reload if needed
        _logger.LogInformation("Configuration reload requested");
        return Task.CompletedTask;
    }

    private ConfigurationValidationResult ValidateConfiguration(SurveillanceConfiguration config)
    {
        var result = new ConfigurationValidationResult { IsValid = true };

        // Validate general settings
        if (config.General.DataRetentionHours < 1)
        {
            result.Errors.Add("DataRetentionHours must be at least 1");
            result.IsValid = false;
        }

        // Validate processor monitoring
        if (config.ProcessorMonitoring.Enabled)
        {
            if (config.ProcessorMonitoring.PollingIntervalSeconds < 1)
            {
                result.Errors.Add("ProcessorMonitoring PollingIntervalSeconds must be at least 1");
                result.IsValid = false;
            }

            if (config.ProcessorMonitoring.Thresholds.WarningPercent < 0 || 
                config.ProcessorMonitoring.Thresholds.WarningPercent > 100)
            {
                result.Errors.Add("ProcessorMonitoring WarningPercent must be between 0 and 100");
                result.IsValid = false;
            }

            if (config.ProcessorMonitoring.Thresholds.CriticalPercent < 0 || 
                config.ProcessorMonitoring.Thresholds.CriticalPercent > 100)
            {
                result.Errors.Add("ProcessorMonitoring CriticalPercent must be between 0 and 100");
                result.IsValid = false;
            }

            if (config.ProcessorMonitoring.Thresholds.CriticalPercent <= 
                config.ProcessorMonitoring.Thresholds.WarningPercent)
            {
                result.Warnings.Add("ProcessorMonitoring CriticalPercent should be greater than WarningPercent");
            }
        }

        // Validate memory monitoring
        if (config.MemoryMonitoring.Enabled)
        {
            if (config.MemoryMonitoring.Thresholds.WarningPercent < 0 || 
                config.MemoryMonitoring.Thresholds.WarningPercent > 100)
            {
                result.Errors.Add("MemoryMonitoring WarningPercent must be between 0 and 100");
                result.IsValid = false;
            }
        }

        // Validate network monitoring
        if (config.NetworkMonitoring.Enabled)
        {
            foreach (var host in config.NetworkMonitoring.BaselineHosts)
            {
                if (string.IsNullOrWhiteSpace(host.Hostname))
                {
                    result.Errors.Add("NetworkMonitoring: All baseline hosts must have a hostname");
                    result.IsValid = false;
                }
            }
        }

        // Validate export settings
        if (config.ExportSettings.Enabled)
        {
            var hasOutputDirectory = !string.IsNullOrWhiteSpace(config.ExportSettings.OutputDirectory);
            var hasOutputDirectories = config.ExportSettings.OutputDirectories != null && 
                                       config.ExportSettings.OutputDirectories.Count > 0 &&
                                       config.ExportSettings.OutputDirectories.Any(d => !string.IsNullOrWhiteSpace(d));
            
            if (!hasOutputDirectory && !hasOutputDirectories)
            {
                result.Errors.Add("ExportSettings: Either OutputDirectory or OutputDirectories must be specified when export is enabled");
                result.IsValid = false;
            }
        }

        // Validate alerting
        if (config.Alerting.Enabled)
        {
            foreach (var channel in config.Alerting.Channels)
            {
                if (string.IsNullOrWhiteSpace(channel.Type))
                {
                    result.Errors.Add("Alerting channel Type cannot be empty");
                    result.IsValid = false;
                }
            }
        }

        return result;
    }
}

