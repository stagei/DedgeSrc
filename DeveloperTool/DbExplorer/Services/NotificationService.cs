using System;
using System.IO;
using System.Text.Json;
using NLog;

namespace DbExplorer.Services;

/// <summary>
/// Service for creating notification files that the tray icon app will display
/// </summary>
public class NotificationService
{
    private static readonly Logger Logger = LogManager.GetCurrentClassLogger();
    private readonly string _notificationsFolder;

    public NotificationService()
    {
        _notificationsFolder = UserDataFolderHelper.EnsureSubFolder("Notifications");
        Logger.Debug("Notifications folder: {Folder}", _notificationsFolder);
    }

    /// <summary>
    /// Show an info notification
    /// </summary>
    public void ShowInfo(string title, string message)
    {
        CreateNotificationFile("Info", title, message);
    }

    /// <summary>
    /// Show a warning notification
    /// </summary>
    public void ShowWarning(string title, string message)
    {
        CreateNotificationFile("Warning", title, message);
    }

    /// <summary>
    /// Show an error notification
    /// </summary>
    public void ShowError(string title, string message)
    {
        CreateNotificationFile("Error", title, message);
    }

    /// <summary>
    /// Show a success notification
    /// </summary>
    public void ShowSuccess(string title, string message)
    {
        CreateNotificationFile("Success", title, message);
    }

    /// <summary>
    /// Show a job completion notification
    /// </summary>
    public void ShowJobCompletion(string jobName, bool success, string details)
    {
        var icon = success ? "Success" : "Error";
        var title = success ? "Job Completed" : "Job Failed";
        var message = $"{jobName}\n\n{details}";
        
        CreateNotificationFile(icon, title, message);
    }

    private void CreateNotificationFile(string icon, string title, string message)
    {
        try
        {
            var notification = new
            {
                id = Guid.NewGuid().ToString(),
                icon = icon,
                title = title,
                message = message,
                timeout = 5000
            };

            var json = JsonSerializer.Serialize(notification, new JsonSerializerOptions
            {
                WriteIndented = false
            });

            var fileName = $"notification_{notification.id}.json";
            var filePath = Path.Combine(_notificationsFolder, fileName);

            // Write file atomically
            var tempPath = filePath + ".tmp";
            File.WriteAllText(tempPath, json);
            File.Move(tempPath, filePath, overwrite: true);

            Logger.Debug("Created notification file: {File} - {Title}", fileName, title);
        }
        catch (Exception ex)
        {
            Logger.Error(ex, "Failed to create notification file: {Title}", title);
        }
    }
}
