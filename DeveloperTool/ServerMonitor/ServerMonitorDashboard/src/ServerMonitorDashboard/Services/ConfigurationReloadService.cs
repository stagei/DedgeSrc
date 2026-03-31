using System.Diagnostics;

namespace ServerMonitorDashboard.Services;

/// <summary>
/// Background service that monitors appsettings.json for changes and logs reload events.
/// ASP.NET Core's IConfiguration automatically reloads when the file changes (reloadOnChange: true).
/// This service provides logging and can trigger additional actions on config reload.
/// </summary>
public class ConfigurationReloadService : BackgroundService
{
    private readonly ILogger<ConfigurationReloadService> _logger;
    private readonly IConfiguration _configuration;
    private FileSystemWatcher? _watcher;
    private readonly string _configPath;
    private DateTime _lastReloadTime = DateTime.MinValue;
    private const int DebounceMilliseconds = 1000; // Debounce rapid file changes

    public ConfigurationReloadService(
        ILogger<ConfigurationReloadService> logger,
        IConfiguration configuration)
    {
        _logger = logger;
        _configuration = configuration;
        
        // Get the path to appsettings.json
        _configPath = Path.Combine(AppContext.BaseDirectory, "appsettings.json");
    }

    protected override Task ExecuteAsync(CancellationToken stoppingToken)
    {
        try
        {
            if (!File.Exists(_configPath))
            {
                _logger.LogWarning("⚙️ Configuration file not found: {Path}", _configPath);
                return Task.CompletedTask;
            }

            var directory = Path.GetDirectoryName(_configPath);
            var fileName = Path.GetFileName(_configPath);
            
            if (string.IsNullOrEmpty(directory))
            {
                _logger.LogWarning("⚙️ Could not determine config directory");
                return Task.CompletedTask;
            }

            _watcher = new FileSystemWatcher(directory, fileName)
            {
                NotifyFilter = NotifyFilters.LastWrite | NotifyFilters.Size,
                EnableRaisingEvents = true
            };

            _watcher.Changed += OnConfigurationChanged;
            _watcher.Error += OnWatcherError;

            _logger.LogInformation("⚙️ Configuration reload watcher started for: {Path}", _configPath);
            _logger.LogInformation("   Settings will auto-reload when the file is modified");
            
            // Register for configuration reload token
            RegisterConfigurationChangeToken();
        }
        catch (Exception ex)
        {
            _logger.LogError(ex, "⚙️ Failed to start configuration watcher");
        }

        return Task.CompletedTask;
    }

    private void RegisterConfigurationChangeToken()
    {
        // This registers a callback that fires when IConfiguration detects a change
        var token = _configuration.GetReloadToken();
        token.RegisterChangeCallback(state =>
        {
            _logger.LogInformation("⚙️ Configuration reloaded by ASP.NET Core");
            LogCurrentAuthSettings();
            
            // Re-register for the next change
            RegisterConfigurationChangeToken();
        }, null);
    }

    private void OnConfigurationChanged(object sender, FileSystemEventArgs e)
    {
        try
        {
            // Debounce - ignore rapid successive changes
            var now = DateTime.Now;
            if ((now - _lastReloadTime).TotalMilliseconds < DebounceMilliseconds)
            {
                return;
            }
            _lastReloadTime = now;

            _logger.LogInformation("═══════════════════════════════════════════════════════");
            _logger.LogInformation("⚙️ CONFIGURATION FILE CHANGED: {Path}", e.FullPath);
            _logger.LogInformation("⚙️ Change type: {ChangeType}", e.ChangeType);
            _logger.LogInformation("═══════════════════════════════════════════════════════");
        }
        catch (Exception ex)
        {
            _logger.LogError(ex, "⚙️ Error handling configuration change");
        }
    }

    private void OnWatcherError(object sender, ErrorEventArgs e)
    {
        _logger.LogError(e.GetException(), "⚙️ Configuration watcher error");
    }

    private void LogCurrentAuthSettings()
    {
        try
        {
            var authEnabled = _configuration.GetValue<bool>("Authentication:Enabled");
            _logger.LogInformation("   Authentication.Enabled: {Enabled}", authEnabled);
            
            var fullAccessGroups = _configuration.GetSection("Authentication:FullAccess:Groups").Get<string[]>() ?? Array.Empty<string>();
            var fullAccessUsers = _configuration.GetSection("Authentication:FullAccess:Users").Get<string[]>() ?? Array.Empty<string>();
            _logger.LogInformation("   FullAccess: {GroupCount} groups, {UserCount} users", 
                fullAccessGroups.Length, fullAccessUsers.Length);
        }
        catch (Exception ex)
        {
            _logger.LogWarning(ex, "   Could not log current auth settings");
        }
    }

    public override void Dispose()
    {
        _watcher?.Dispose();
        base.Dispose();
    }
}
