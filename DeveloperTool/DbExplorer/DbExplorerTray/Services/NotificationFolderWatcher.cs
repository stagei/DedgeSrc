using System;
using System.IO;
using System.Text.Json;
using System.Threading;
using System.Threading.Tasks;
using NLog;
using DbExplorerTray.Models;

namespace DbExplorerTray.Services;

/// <summary>
/// Watches a folder for JSON notification files and processes them
/// </summary>
public class NotificationFolderWatcher : IDisposable
{
    private static readonly Logger Logger = LogManager.GetCurrentClassLogger();
    private readonly string _watchFolder;
    private readonly TrayIconManager _trayIconManager;
    private FileSystemWatcher? _watcher;
    private bool _disposed = false;

    public NotificationFolderWatcher(string watchFolder, TrayIconManager trayIconManager)
    {
        _watchFolder = watchFolder;
        _trayIconManager = trayIconManager;
    }

    public void Start()
    {
        if (_disposed)
            throw new ObjectDisposedException(nameof(NotificationFolderWatcher));

        try
        {
            Logger.Debug("Starting folder watcher for: {Folder}", _watchFolder);

            // Ensure folder exists
            if (!Directory.Exists(_watchFolder))
            {
                Directory.CreateDirectory(_watchFolder);
                Logger.Debug("Created notifications folder: {Folder}", _watchFolder);
            }

            // Process any existing files first
            ProcessExistingFiles();

            // Create file system watcher
            _watcher = new FileSystemWatcher(_watchFolder)
            {
                Filter = "*.json",
                NotifyFilter = NotifyFilters.FileName | NotifyFilters.LastWrite,
                EnableRaisingEvents = true
            };

            _watcher.Created += OnFileCreated;
            _watcher.Changed += OnFileChanged;
            _watcher.Error += OnError;

            Logger.Info("Folder watcher started successfully");
        }
        catch (Exception ex)
        {
            Logger.Error(ex, "Failed to start folder watcher");
            throw;
        }
    }

    public void Stop()
    {
        if (_watcher != null)
        {
            Logger.Debug("Stopping folder watcher");
            _watcher.EnableRaisingEvents = false;
            _watcher.Created -= OnFileCreated;
            _watcher.Changed -= OnFileChanged;
            _watcher.Error -= OnError;
            _watcher.Dispose();
            _watcher = null;
            Logger.Info("Folder watcher stopped");
        }
    }

    private void ProcessExistingFiles()
    {
        try
        {
            var files = Directory.GetFiles(_watchFolder, "*.json");
            Logger.Debug("Found {Count} existing notification files to process", files.Length);

            foreach (var file in files)
            {
                Task.Run(() => ProcessNotificationFile(file));
            }
        }
        catch (Exception ex)
        {
            Logger.Error(ex, "Error processing existing files");
        }
    }

    private void OnFileCreated(object sender, FileSystemEventArgs e)
    {
        Logger.Debug("New notification file created: {File}", e.FullPath);
        Task.Run(() => ProcessNotificationFile(e.FullPath));
    }

    private void OnFileChanged(object sender, FileSystemEventArgs e)
    {
        Logger.Debug("Notification file changed: {File}", e.FullPath);
        Task.Run(() => ProcessNotificationFile(e.FullPath));
    }

    private void OnError(object sender, ErrorEventArgs e)
    {
        Logger.Error(e.GetException(), "File system watcher error");
    }

    private void ProcessNotificationFile(string filePath)
    {
        const int maxRetries = 5;
        const int retryDelayMs = 500;

        for (int attempt = 1; attempt <= maxRetries; attempt++)
        {
            try
            {
                Logger.Debug("Processing notification file: {File} (attempt {Attempt})", filePath, attempt);

                // Wait a bit for file to be fully written
                if (attempt > 1)
                {
                    Thread.Sleep(retryDelayMs);
                }

                // Read file content
                string jsonContent;
                using (var fileStream = new FileStream(filePath, FileMode.Open, FileAccess.Read, FileShare.ReadWrite))
                using (var reader = new StreamReader(fileStream))
                {
                    jsonContent = reader.ReadToEnd();
                }

                if (string.IsNullOrWhiteSpace(jsonContent))
                {
                    Logger.Warn("Notification file is empty: {File}", filePath);
                    DeleteFile(filePath);
                    return;
                }

                // Parse JSON
                var notification = JsonSerializer.Deserialize<NotificationMessage>(jsonContent);
                if (notification == null)
                {
                    Logger.Warn("Failed to parse notification JSON: {File}", filePath);
                    DeleteFile(filePath);
                    return;
                }

                Logger.Info("Processing notification: {Id} - {Title}", notification.Id, notification.Title);

                // Display notification via tray icon
                _trayIconManager.ShowNotification(
                    notification.Icon,
                    notification.Title,
                    notification.Message,
                    notification.Timeout);

                // Delete processed file
                DeleteFile(filePath);

                Logger.Debug("Notification processed and file deleted: {File}", filePath);
                return;
            }
            catch (IOException ioEx) when (attempt < maxRetries)
            {
                Logger.Debug("File locked, will retry: {File} - {Error}", filePath, ioEx.Message);
                // Continue to retry
            }
            catch (JsonException jsonEx)
            {
                Logger.Warn(jsonEx, "Invalid JSON in notification file: {File}", filePath);
                DeleteFile(filePath);
                return;
            }
            catch (Exception ex)
            {
                Logger.Error(ex, "Error processing notification file: {File}", filePath);
                if (attempt == maxRetries)
                {
                    // On final attempt, try to delete the problematic file
                    try
                    {
                        DeleteFile(filePath);
                    }
                    catch
                    {
                        // Ignore deletion errors on final attempt
                    }
                }
            }
        }
    }

    private void DeleteFile(string filePath)
    {
        try
        {
            if (File.Exists(filePath))
            {
                File.Delete(filePath);
                Logger.Debug("Deleted notification file: {File}", filePath);
            }
        }
        catch (Exception ex)
        {
            Logger.Warn(ex, "Failed to delete notification file: {File}", filePath);
        }
    }

    public void Dispose()
    {
        if (!_disposed)
        {
            Stop();
            _disposed = true;
        }
    }
}
