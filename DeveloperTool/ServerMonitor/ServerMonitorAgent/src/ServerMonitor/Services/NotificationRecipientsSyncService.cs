using System.Security.Cryptography;
using System.Text;
using Microsoft.Extensions.Hosting;
using Microsoft.Extensions.Logging;
using Microsoft.Extensions.Options;
using ServerMonitor.Core.Configuration;

namespace ServerMonitor.Services;

/// <summary>
/// Syncs NotificationRecipients.json from UNC path to local file if hash differs
/// Similar to CommonConfigSyncService but for notification recipients
/// </summary>
public class NotificationRecipientsSyncService : BackgroundService
{
    private readonly ILogger<NotificationRecipientsSyncService> _logger;
    private readonly IOptionsMonitor<SurveillanceConfiguration> _configMonitor;
    private readonly ServerMonitor.Core.Services.NotificationRecipientService _recipientService;
    private readonly string _localConfigPath;
    private string? _lastLocalHash;

    public NotificationRecipientsSyncService(
        ILogger<NotificationRecipientsSyncService> logger,
        IOptionsMonitor<SurveillanceConfiguration> configMonitor,
        ServerMonitor.Core.Services.NotificationRecipientService recipientService)
    {
        _logger = logger;
        _configMonitor = configMonitor;
        _recipientService = recipientService;
        _localConfigPath = Path.Combine(AppContext.BaseDirectory, "NotificationRecipients.json");
    }

    protected override async Task ExecuteAsync(CancellationToken stoppingToken)
    {
        // Wait a bit for initial config to be fully loaded
        await Task.Delay(2000, stoppingToken);

        // Check once at startup
        await SyncNotificationRecipientsAsync(stoppingToken);

        // If ConfigReloadIntervalMinutes is set, check periodically
        var intervalMinutes = _configMonitor.CurrentValue.Runtime.ConfigReloadIntervalMinutes;
        
        if (!intervalMinutes.HasValue || intervalMinutes.Value <= 0)
        {
            _logger.LogInformation("⚙️ Notification recipients sync: One-time check completed (periodic sync disabled)");
            return;
        }

        _logger.LogInformation("⚙️ Notification recipients sync: Checking every {Interval} minutes", intervalMinutes.Value);

        while (!stoppingToken.IsCancellationRequested)
        {
            try
            {
                await Task.Delay(TimeSpan.FromMinutes(intervalMinutes.Value), stoppingToken);
                await SyncNotificationRecipientsAsync(stoppingToken);
            }
            catch (OperationCanceledException)
            {
                break;
            }
            catch (Exception ex)
            {
                _logger.LogError(ex, "Error in notification recipients sync service");
            }
        }

        _logger.LogInformation("⚙️ Notification recipients sync service stopped");
    }

    private async Task SyncNotificationRecipientsAsync(CancellationToken cancellationToken)
    {
        // Skip sync if DevMode is enabled
        if (_configMonitor.CurrentValue.Runtime.DevMode)
        {
            _logger.LogInformation("⚙️ DevMode enabled - skipping NotificationRecipients sync");
            return;
        }

        var commonConfigPath = _configMonitor.CurrentValue.Runtime.CommonAppsettingsFile;

        if (string.IsNullOrWhiteSpace(commonConfigPath))
        {
            _logger.LogDebug("⚙️ CommonAppsettingsFile not configured - skipping NotificationRecipients sync");
            return;
        }

        // Build path to Resources subfolder
        var commonConfigDir = Path.GetDirectoryName(commonConfigPath);
        if (string.IsNullOrEmpty(commonConfigDir))
        {
            _logger.LogWarning("⚙️ Could not determine directory from CommonAppsettingsFile path");
            return;
        }

        var resourcesDir = Path.Combine(commonConfigDir, "Resources");
        var remoteRecipientsPath = Path.Combine(resourcesDir, "NotificationRecipients.json");

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
            var remoteHash = await CalculateFileHashAsync(remoteRecipientsPath, cancellationToken);
            
            // Calculate hash of local file
            if (!File.Exists(_localConfigPath))
            {
                _logger.LogInformation("⚙️ Local NotificationRecipients.json does not exist - copying from remote");
                File.Copy(remoteRecipientsPath, _localConfigPath, overwrite: true);
                _lastLocalHash = remoteHash;
                _recipientService.ReloadConfiguration();
                _logger.LogInformation("✅ Notification recipients file copied successfully");
                return;
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
                _logger.LogDebug("⚙️ Notification recipients hash matches local - no sync needed");
                return;
            }

            // If remote hash matches what we last wrote, we're in a loop - skip
            if (remoteHash == _lastLocalHash)
            {
                _logger.LogWarning("⚙️ Notification recipients hash matches last written hash - skipping to prevent loop");
                return;
            }

            _logger.LogInformation("⚙️ Notification recipients hash differs - syncing from {RemotePath} to {LocalPath}", 
                remoteRecipientsPath, _localConfigPath);

            // Create backup of local file
            var backupPath = $"{_localConfigPath}.backup.{DateTime.Now:yyyyMMdd_HHmmss}";
            File.Copy(_localConfigPath, backupPath, overwrite: true);
            _logger.LogInformation("⚙️ Created backup: {BackupPath}", backupPath);

            // Copy remote file to local
            File.Copy(remoteRecipientsPath, _localConfigPath, overwrite: true);
            
            // Update last hash
            _lastLocalHash = remoteHash;

            // Reload configuration
            _recipientService.ReloadConfiguration();

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
        using var md5 = MD5.Create();
        using var stream = File.OpenRead(filePath);
        var hash = await md5.ComputeHashAsync(stream, cancellationToken);
        return Convert.ToBase64String(hash);
    }
}

