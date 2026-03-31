using System.Text.Json;

namespace ServerMonitorTrayIcon;

/// <summary>
/// Configuration settings for the ServerMonitor Tray application
/// </summary>
public class TrayAppSettings
{
    /// <summary>
    /// ServerMonitor API endpoint
    /// </summary>
    public string ApiBaseUrl { get; set; } = "http://localhost:8999";
    
    /// <summary>
    /// Base path for remote control trigger files
    /// </summary>
    public string ConfigBasePath { get; set; } = @"C:\opt\src\DedgeSrc\DedgeSystemTools\Folders\DedgeCommon\Software\Config\ServerMonitor";
    
    /// <summary>
    /// File name for the reinstall trigger file
    /// </summary>
    public string ReinstallTriggerFileName { get; set; } = "ReinstallServerMonitor.txt";
    
    /// <summary>
    /// File name for the stop tray trigger file
    /// </summary>
    public string StopTrayTriggerFileName { get; set; } = "StopServerMonitorTray.txt";
    
    /// <summary>
    /// Path to the installed ServerMonitor.exe (for version checking)
    /// </summary>
    public string ServerMonitorExePath { get; set; } = @"C:\opt\src\DedgeSrc\DedgeSystemTools\Folders\DedgeCommon\Software\DedgeWinApps\ServerMonitor\ServerMonitor.exe";
    
    /// <summary>
    /// Status check interval in milliseconds
    /// </summary>
    public int StatusCheckIntervalMs { get; set; } = 3000;
    
    // ═══════════════════════════════════════════════════════════════════════════════
    // ALERT NOTIFICATION SETTINGS
    // ═══════════════════════════════════════════════════════════════════════════════
    
    /// <summary>
    /// Enable balloon notifications for new alerts
    /// </summary>
    public bool EnableAlertNotifications { get; set; } = true;
    
    /// <summary>
    /// How often to poll for new alerts (in milliseconds). Uses same timer as status check.
    /// </summary>
    public int AlertPollIntervalMs { get; set; } = 5000;
    
    /// <summary>
    /// Suppress notifications for alerts that exist at startup (prevent notification storm)
    /// </summary>
    public bool SuppressStartupAlerts { get; set; } = true;
    
    /// <summary>
    /// Maximum number of alert IDs to track (memory management)
    /// </summary>
    public int MaxSeenAlertIds { get; set; } = 1000;
    
    /// <summary>
    /// How long to display balloon notification (milliseconds)
    /// </summary>
    public int BalloonDisplayTimeMs { get; set; } = 5000;
    
    /// <summary>
    /// Open HTML report when balloon is clicked (otherwise opens API docs)
    /// </summary>
    public bool OpenHtmlOnBalloonClick { get; set; } = true;
    
    // ═══════════════════════════════════════════════════════════════════════════════
    // COMPUTED PATHS
    // ═══════════════════════════════════════════════════════════════════════════════
    
    /// <summary>
    /// Full path to the reinstall trigger file
    /// </summary>
    public string ReinstallTriggerFilePath => Path.Combine(ConfigBasePath, ReinstallTriggerFileName);
    
    /// <summary>
    /// Full path to the stop tray trigger file
    /// </summary>
    public string StopTrayTriggerFilePath => Path.Combine(ConfigBasePath, StopTrayTriggerFileName);
    
    /// <summary>
    /// Loads settings from appsettings.json
    /// </summary>
    public static TrayAppSettings Load()
    {
        var settings = new TrayAppSettings();
        
        try
        {
            // Look for appsettings.json in the same directory as the executable
            var exeDir = AppContext.BaseDirectory;
            var settingsPath = Path.Combine(exeDir, "appsettings.json");
            
            if (File.Exists(settingsPath))
            {
                var json = File.ReadAllText(settingsPath);
                
                // Remove comments (JSON doesn't officially support comments, but we allow them)
                json = RemoveJsonComments(json);
                
                using var doc = JsonDocument.Parse(json);
                
                if (doc.RootElement.TryGetProperty("TrayAppSettings", out var traySettings))
                {
                    if (traySettings.TryGetProperty("ApiBaseUrl", out var apiUrl))
                        settings.ApiBaseUrl = apiUrl.GetString() ?? settings.ApiBaseUrl;
                    
                    if (traySettings.TryGetProperty("ConfigBasePath", out var configPath))
                        settings.ConfigBasePath = configPath.GetString() ?? settings.ConfigBasePath;
                    
                    if (traySettings.TryGetProperty("ReinstallTriggerFileName", out var reinstallFile))
                        settings.ReinstallTriggerFileName = reinstallFile.GetString() ?? settings.ReinstallTriggerFileName;
                    
                    if (traySettings.TryGetProperty("StopTrayTriggerFileName", out var stopFile))
                        settings.StopTrayTriggerFileName = stopFile.GetString() ?? settings.StopTrayTriggerFileName;
                    
                    if (traySettings.TryGetProperty("ServerMonitorExePath", out var exePath))
                        settings.ServerMonitorExePath = exePath.GetString() ?? settings.ServerMonitorExePath;
                    
                    if (traySettings.TryGetProperty("StatusCheckIntervalMs", out var interval))
                        settings.StatusCheckIntervalMs = interval.GetInt32();
                    
                    // Alert notification settings
                    if (traySettings.TryGetProperty("EnableAlertNotifications", out var enableAlerts))
                        settings.EnableAlertNotifications = enableAlerts.GetBoolean();
                    
                    if (traySettings.TryGetProperty("AlertPollIntervalMs", out var alertInterval))
                        settings.AlertPollIntervalMs = alertInterval.GetInt32();
                    
                    if (traySettings.TryGetProperty("SuppressStartupAlerts", out var suppressStartup))
                        settings.SuppressStartupAlerts = suppressStartup.GetBoolean();
                    
                    if (traySettings.TryGetProperty("MaxSeenAlertIds", out var maxSeen))
                        settings.MaxSeenAlertIds = maxSeen.GetInt32();
                    
                    if (traySettings.TryGetProperty("BalloonDisplayTimeMs", out var balloonTime))
                        settings.BalloonDisplayTimeMs = balloonTime.GetInt32();
                    
                    if (traySettings.TryGetProperty("OpenHtmlOnBalloonClick", out var openHtml))
                        settings.OpenHtmlOnBalloonClick = openHtml.GetBoolean();
                }
            }
        }
        catch (Exception ex)
        {
            System.Diagnostics.Debug.WriteLine($"Error loading settings: {ex.Message}. Using defaults.");
        }
        
        return settings;
    }
    
    /// <summary>
    /// Removes single-line comments from JSON (// style)
    /// </summary>
    private static string RemoveJsonComments(string json)
    {
        var lines = json.Split('\n');
        var result = new System.Text.StringBuilder();
        
        foreach (var line in lines)
        {
            var trimmed = line.TrimStart();
            if (!trimmed.StartsWith("//"))
            {
                // Also handle inline comments (after a value)
                var commentIndex = line.IndexOf("//");
                if (commentIndex > 0)
                {
                    // Check if // is inside a string (simplified check)
                    var beforeComment = line.Substring(0, commentIndex);
                    var quoteCount = beforeComment.Count(c => c == '"');
                    if (quoteCount % 2 == 0) // Even number of quotes = not in string
                    {
                        result.AppendLine(beforeComment);
                        continue;
                    }
                }
                result.AppendLine(line);
            }
        }
        
        return result.ToString();
    }
}
