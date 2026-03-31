using System.Security.Cryptography;
using System.Text;
using Microsoft.Extensions.Configuration;
using Microsoft.Extensions.Hosting;
using Microsoft.Extensions.Logging;
using Microsoft.Extensions.Options;
using ServerMonitor.Core.Configuration;

namespace ServerMonitor.Services;

/// <summary>
/// Syncs common appsettings.json and NotificationRecipients.json from UNC path to local files if hash differs
/// Both files are synced and reloaded together
/// </summary>
public class CommonConfigSyncService : BackgroundService
{
    private readonly ILogger<CommonConfigSyncService> _logger;
    private readonly IConfiguration _configuration;
    private readonly IOptionsMonitor<SurveillanceConfiguration> _configMonitor;
    private readonly ServerMonitor.Core.Services.NotificationRecipientService? _recipientService;
    private readonly string _localConfigPath;
    private readonly string _localRecipientsPath;
    private string? _lastLocalHash;
    private string? _lastRecipientsHash;

    public CommonConfigSyncService(
        ILogger<CommonConfigSyncService> logger,
        IConfiguration configuration,
        IOptionsMonitor<SurveillanceConfiguration> configMonitor,
        ServerMonitor.Core.Services.NotificationRecipientService? recipientService = null)
    {
        _logger = logger;
        _configuration = configuration;
        _configMonitor = configMonitor;
        _recipientService = recipientService;
        _localConfigPath = Path.Combine(AppContext.BaseDirectory, "appsettings.json");
        _localRecipientsPath = Path.Combine(AppContext.BaseDirectory, "NotificationRecipients.json");
        
        // Subscribe to config changes to reload NotificationRecipients when appsettings.json changes
        _configMonitor.OnChange(_ => ReloadNotificationRecipients());
    }

    protected override async Task ExecuteAsync(CancellationToken stoppingToken)
    {
        // Wait a bit for initial config to be fully loaded
        await Task.Delay(2000, stoppingToken);

        // Check once at startup - sync both files together
        await SyncConfigFilesAsync(stoppingToken);

        // If ConfigReloadIntervalMinutes is set, check periodically
        var intervalMinutes = _configMonitor.CurrentValue.Runtime.ConfigReloadIntervalMinutes;
        
        if (!intervalMinutes.HasValue || intervalMinutes.Value <= 0)
        {
            _logger.LogInformation("⚙️ Common config sync: One-time check completed (periodic sync disabled)");
            return;
        }

        _logger.LogInformation("⚙️ Common config sync: Checking every {Interval} minutes", intervalMinutes.Value);

        while (!stoppingToken.IsCancellationRequested)
        {
            try
            {
                await Task.Delay(TimeSpan.FromMinutes(intervalMinutes.Value), stoppingToken);
                await SyncConfigFilesAsync(stoppingToken);
            }
            catch (OperationCanceledException)
            {
                break;
            }
            catch (Exception ex)
            {
                _logger.LogError(ex, "Error in common config sync service");
            }
        }

        _logger.LogInformation("⚙️ Common config sync service stopped");
    }

    /// <summary>
    /// Syncs both appsettings.json and NotificationRecipients.json together
    /// </summary>
    private async Task SyncConfigFilesAsync(CancellationToken cancellationToken)
    {
        // Sync appsettings.json first
        var appsettingsSynced = await SyncCommonConfigAsync(cancellationToken);
        
        // Sync NotificationRecipients.json right after (if appsettings sync succeeded or was skipped)
        if (appsettingsSynced || !string.IsNullOrWhiteSpace(_configMonitor.CurrentValue.Runtime.CommonAppsettingsFile))
        {
            await SyncNotificationRecipientsAsync(cancellationToken);
        }
    }
    
    /// <summary>
    /// Reloads NotificationRecipients.json when appsettings.json changes
    /// </summary>
    private void ReloadNotificationRecipients()
    {
        if (_recipientService != null)
        {
            _logger.LogDebug("🔄 Appsettings.json changed - reloading NotificationRecipients.json");
            _recipientService.ReloadConfiguration();
        }
    }
    
    private async Task<bool> SyncCommonConfigAsync(CancellationToken cancellationToken)
    {
        // Skip sync if DevMode is enabled
        if (_configMonitor.CurrentValue.Runtime.DevMode)
        {
            _logger.LogInformation("⚙️ DevMode enabled - skipping CommonAppsettingsFile sync");
            return false;
        }

        var commonConfigPath = _configMonitor.CurrentValue.Runtime.CommonAppsettingsFile;

        if (string.IsNullOrWhiteSpace(commonConfigPath))
        {
            _logger.LogDebug("⚙️ CommonAppsettingsFile not configured - using local appsettings.json");
            return false;
        }

        try
        {
            _logger.LogInformation("⚙️ Checking common config file: {Path}", commonConfigPath);

            // Check if UNC path is accessible
            if (!IsPathAccessible(commonConfigPath))
            {
                _logger.LogWarning("⚙️ Common config path not accessible: {Path} - using local appsettings.json", commonConfigPath);
                return false;
            }

            // Check if remote file exists
            if (!File.Exists(commonConfigPath))
            {
                _logger.LogWarning("⚙️ Common config file does not exist: {Path} - using local appsettings.json", commonConfigPath);
                return false;
            }

            // Calculate hash of remote file
            var remoteHash = await CalculateFileHashAsync(commonConfigPath, cancellationToken);
            
            // Calculate hash of local file
            if (!File.Exists(_localConfigPath))
            {
                _logger.LogWarning("⚙️ Local appsettings.json does not exist: {Path}", _localConfigPath);
                return false;
            }

            var localHash = await CalculateFileHashAsync(_localConfigPath, cancellationToken);

            // Store initial hash to prevent infinite loop
            if (_lastLocalHash == null)
            {
                _lastLocalHash = localHash;
            }

            // If hashes are the same, no sync needed
            if (remoteHash == localHash)
            {
                _logger.LogDebug("⚙️ Common config hash matches local - no sync needed");
                return true; // File exists and is in sync
            }

            // If remote hash matches what we last wrote, we're in a loop - skip
            if (remoteHash == _lastLocalHash)
            {
                _logger.LogWarning("⚙️ Common config hash matches last written hash - skipping to prevent loop");
                return true; // Already synced
            }

            _logger.LogInformation("⚙️ Common config hash differs - syncing from {RemotePath} to {LocalPath}", 
                commonConfigPath, _localConfigPath);

            // Create backup of local file
            var backupPath = $"{_localConfigPath}.backup.{DateTime.Now:yyyyMMdd_HHmmss}";
            File.Copy(_localConfigPath, backupPath, overwrite: true);
            _logger.LogInformation("⚙️ Created backup: {BackupPath}", backupPath);

            // Copy remote file to local
            File.Copy(commonConfigPath, _localConfigPath, overwrite: true);
            
            // Update last hash
            _lastLocalHash = remoteHash;

            _logger.LogInformation("✅ Common config synced successfully - configuration will reload automatically");

            // The configuration system with reloadOnChange=true will automatically detect the file change
            // and trigger IOptionsMonitor.OnChange events, which services are already subscribed to
            // This will also trigger ReloadNotificationRecipients() via the OnChange subscription
            
            return true;
        }
        catch (UnauthorizedAccessException ex)
        {
            _logger.LogWarning(ex, "⚙️ Access denied to common config path: {Path} - using local appsettings.json", commonConfigPath);
            return false;
        }
        catch (IOException ex)
        {
            _logger.LogWarning(ex, "⚙️ IO error accessing common config path: {Path} - using local appsettings.json", commonConfigPath);
            return false;
        }
        catch (Exception ex)
        {
            _logger.LogError(ex, "⚙️ Error syncing common config from {Path} - using local appsettings.json", commonConfigPath);
            return false;
        }
    }
    
    private async Task SyncNotificationRecipientsAsync(CancellationToken cancellationToken)
    {
        // Skip sync if DevMode is enabled
        if (_configMonitor.CurrentValue.Runtime.DevMode)
        {
            _logger.LogDebug("⚙️ DevMode enabled - skipping NotificationRecipients sync");
            return;
        }

        var commonConfigPath = _configMonitor.CurrentValue.Runtime.CommonAppsettingsFile;

        if (string.IsNullOrWhiteSpace(commonConfigPath))
        {
            _logger.LogDebug("⚙️ CommonAppsettingsFile not configured - skipping NotificationRecipients sync");
            return;
        }

        // Build path to NotificationRecipients.json in same folder as CommonAppsettingsFile
        var commonConfigDir = Path.GetDirectoryName(commonConfigPath);
        if (string.IsNullOrEmpty(commonConfigDir))
        {
            _logger.LogWarning("⚙️ Could not determine directory from CommonAppsettingsFile path");
            return;
        }

        var remoteRecipientsPath = Path.Combine(commonConfigDir, "NotificationRecipients.json");

        try
        {
            _logger.LogInformation("⚙️ Checking notification recipients file: {Path}", remoteRecipientsPath);

            // Check if UNC path is accessible
            if (!IsPathAccessible(remoteRecipientsPath))
            {
                _logger.LogWarning("⚙️ Notification recipients path not accessible: {Path} - using local file if exists", remoteRecipientsPath);
                return;
            }

            // Check if remote file exists
            if (!File.Exists(remoteRecipientsPath))
            {
                _logger.LogWarning("⚙️ Notification recipients file does not exist: {Path} - using local file if exists", remoteRecipientsPath);
                return;
            }

            // Calculate hash of remote file
            var remoteHash = await CalculateFileHashBase64Async(remoteRecipientsPath, cancellationToken);
            
            // Calculate hash of local file
            if (!File.Exists(_localRecipientsPath))
            {
                _logger.LogInformation("⚙️ Local NotificationRecipients.json does not exist - copying from remote");
                File.Copy(remoteRecipientsPath, _localRecipientsPath, overwrite: true);
                _lastRecipientsHash = remoteHash;
                _recipientService?.ReloadConfiguration();
                _logger.LogInformation("✅ Notification recipients file copied successfully");
                return;
            }

            var localHash = await CalculateFileHashBase64Async(_localRecipientsPath, cancellationToken);

            // Store initial hash to prevent infinite loop
            if (_lastRecipientsHash == null)
            {
                _lastRecipientsHash = localHash;
            }

            // If hashes are the same, no sync needed
            if (remoteHash == localHash)
            {
                _logger.LogDebug("⚙️ Notification recipients hash matches local - no sync needed");
                return;
            }

            // If remote hash matches what we last wrote, we're in a loop - skip
            if (remoteHash == _lastRecipientsHash)
            {
                _logger.LogWarning("⚙️ Notification recipients hash matches last written hash - skipping to prevent loop");
                return;
            }

            _logger.LogInformation("⚙️ Notification recipients hash differs - syncing from {RemotePath} to {LocalPath}", 
                remoteRecipientsPath, _localRecipientsPath);

            // Create backup of local file
            var backupPath = $"{_localRecipientsPath}.backup.{DateTime.Now:yyyyMMdd_HHmmss}";
            File.Copy(_localRecipientsPath, backupPath, overwrite: true);
            _logger.LogInformation("⚙️ Created backup: {BackupPath}", backupPath);

            // Copy remote file to local
            File.Copy(remoteRecipientsPath, _localRecipientsPath, overwrite: true);
            
            // Update last hash
            _lastRecipientsHash = remoteHash;

            // Reload configuration
            _recipientService?.ReloadConfiguration();

            _logger.LogInformation("✅ Notification recipients synced successfully");
        }
        catch (UnauthorizedAccessException ex)
        {
            _logger.LogWarning(ex, "⚙️ Access denied to notification recipients path: {Path} - using local file", remoteRecipientsPath);
        }
        catch (IOException ex)
        {
            _logger.LogWarning(ex, "⚙️ IO error accessing notification recipients path: {Path} - using local file", remoteRecipientsPath);
        }
        catch (Exception ex)
        {
            _logger.LogError(ex, "⚙️ Error syncing notification recipients from {Path} - using local file", remoteRecipientsPath);
        }
    }

    private bool IsPathAccessible(string path)
    {
        try
        {
            // For UNC paths, try to get directory info
            var directory = Path.GetDirectoryName(path);
            if (string.IsNullOrEmpty(directory))
                return false;

            // Check if directory exists and is accessible
            if (!Directory.Exists(directory))
                return false;

            // Try to enumerate files (quick accessibility check)
            _ = Directory.GetFiles(directory).Take(1).ToList();
            return true;
        }
        catch
        {
            return false;
        }
    }

    private async Task<string> CalculateFileHashAsync(string filePath, CancellationToken cancellationToken)
    {
        return await Task.Run(() =>
        {
            using var md5 = MD5.Create();
            using var stream = File.OpenRead(filePath);
            var hashBytes = md5.ComputeHash(stream);
            return Convert.ToHexString(hashBytes);
        }, cancellationToken);
    }
    
    private async Task<string> CalculateFileHashBase64Async(string filePath, CancellationToken cancellationToken)
    {
        using var md5 = MD5.Create();
        using var stream = File.OpenRead(filePath);
        var hash = await md5.ComputeHashAsync(stream, cancellationToken);
        return Convert.ToBase64String(hash);
    }
}

