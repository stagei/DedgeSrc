using System.Diagnostics;
using System.Drawing;
using System.Runtime.InteropServices;
using FontAwesome.Sharp;
using DrawingIcon = System.Drawing.Icon;

namespace ServerMonitorTrayIcon;

/// <summary>
/// Application context that manages the system tray icon and context menu
/// </summary>
public class TrayIconApplicationContext : ApplicationContext
{
    // Win32 API to properly destroy icon handles and prevent memory leaks
    [DllImport("user32.dll", CharSet = CharSet.Auto)]
    private static extern bool DestroyIcon(IntPtr handle);
    
    private readonly NotifyIcon _notifyIcon;
    private readonly ServiceManager _serviceManager;
    private readonly ServerMonitorApiClient _apiClient;
    private readonly System.Windows.Forms.Timer _statusTimer;
    private readonly TrayAppSettings _settings;
    
    // REST API server for remote control from Dashboard (port 8997)
    private readonly TrayApiServer _trayApiServer;
    
    private readonly DrawingIcon _runningIcon;
    private readonly DrawingIcon _stoppedIcon;
    private readonly DrawingIcon _installingIcon;
    private readonly DrawingIcon _scriptRunningIcon;
    private bool _hasRunningScripts;
    
    // FileSystemWatcher for real-time trigger file detection (more responsive than polling)
    private FileSystemWatcher? _triggerFileWatcher;
    
    // ═══════════════════════════════════════════════════════════════════════════════
    // REMOTE CONTROL FILES - Drop these files to trigger automatic actions
    // ═══════════════════════════════════════════════════════════════════════════════
    // Configured in appsettings.json:
    //   ReinstallServerMonitor.txt - Triggers reinstall of ServerMonitor service (contains Version=x.y.z)
    //   StopServerMonitorTray.txt  - Closes the tray application
    // ═══════════════════════════════════════════════════════════════════════════════
    
    // Flag to prevent multiple concurrent reinstall operations
    private bool _isReinstallInProgress = false;
    
    // Track processed trigger files to prevent repeated "already up-to-date" balloons
    // Key: trigger file path, Value: signature (LastWriteUtcTicks|Length|Version)
    private readonly Dictionary<string, string> _processedTriggerSignatures = new(StringComparer.OrdinalIgnoreCase);
    
    // Flag to prevent overlapping timer tick executions (Issue 6)
    private bool _isStatusCheckInProgress = false;
    
    // ═══════════════════════════════════════════════════════════════════════════════
    // ALERT NOTIFICATION TRACKING
    // ═══════════════════════════════════════════════════════════════════════════════
    
    // Track alerts we've already shown notifications for (prevents duplicate notifications)
    private readonly HashSet<Guid> _seenAlertIds = new();
    
    // Track the last alert we showed (for balloon click handling)
    private AlertInfo? _lastShownAlert;
    
    // Path to latest snapshot files (for opening when balloon is clicked)
    private string? _lastSnapshotHtmlPath;
    
    // Flag to track if initial alerts have been loaded (suppresses startup storm)
    private bool _initialAlertsLoaded = false;
    
    // Timer for alert polling (separate from status check for different interval)
    private DateTime _lastAlertPollTime = DateTime.MinValue;
    
    // Context menu items (need references to enable/disable them)
    private ToolStripMenuItem _versionInfoItem = null!;
    private ToolStripMenuItem _openSwaggerItem = null!;
    private ToolStripMenuItem _openHtmlItem = null!;
    private ToolStripMenuItem _openJsonItem = null!;
    private ToolStripMenuItem _stopServiceItem = null!;
    private ToolStripMenuItem _startServiceItem = null!;
    private ToolStripMenuItem _restartServiceItem = null!;
    private ToolStripMenuItem _installItem = null!;

    public TrayIconApplicationContext()
    {
        // ═══════════════════════════════════════════════════════════════════════════════
        // TRAY ICON CONFIGURATION
        // ═══════════════════════════════════════════════════════════════════════════════
        // Icons use FontAwesome.Sharp (v6.6.0) - browse all icons at: https://fontawesome.com/search
        //
        // To change an icon:
        //   1. Icon character: Replace IconChar.XXX with any IconChar enum value
        //      Examples: IconChar.Server, IconChar.Heartbeat, IconChar.Shield, IconChar.Gauge
        //   2. Foreground color: Use Color.FromArgb(R, G, B) or named colors like Color.Green
        //   3. Size: Default is 32px (3rd parameter in CreateIcon method)
        //
        // Common icon alternatives:
        //   Running: IconChar.CircleCheck, IconChar.CheckCircle, IconChar.Heartbeat, IconChar.Server
        //   Stopped: IconChar.CircleXmark, IconChar.TimesCircle, IconChar.Ban, IconChar.PowerOff
        //   Installing: IconChar.Spinner, IconChar.Hourglass, IconChar.Gear, IconChar.ArrowsRotate
        //
        // BACKGROUND: Currently transparent. To add a background, use the 4th parameter:
        //   CreateIcon(IconChar.CircleCheck, Color.Green, 32, Color.White)  // white background
        //   CreateIcon(IconChar.CircleCheck, Color.Green, 32, Color.Black)  // black background
        //   - null/omit = transparent (default, works on most taskbars)
        //   - Color.White = useful for dark taskbars if icon color is too dark
        //   - Color.Black = useful for light taskbars if icon color is too bright
        // ═══════════════════════════════════════════════════════════════════════════════
        _runningIcon = CreateIcon(IconChar.CircleCheck, Color.FromArgb(144, 238, 144));    // Light green checkmark
        _stoppedIcon = CreateIcon(IconChar.CircleXmark, Color.FromArgb(255, 128, 128));    // Light red X
        _installingIcon = CreateIcon(IconChar.Spinner, Color.FromArgb(147, 112, 219));     // Purple spinner (installing/waiting)
        _scriptRunningIcon = CreateIcon(IconChar.Terminal, Color.FromArgb(255, 69, 0));    // Red-orange terminal (script executing)
        
        // Load settings from appsettings.json
        _settings = TrayAppSettings.Load();
        Debug.WriteLine($"Settings loaded - API: {_settings.ApiBaseUrl}, ConfigPath: {_settings.ConfigBasePath}");
        
        // Initialize service manager and API client
        _serviceManager = new ServiceManager("ServerMonitor");
        _apiClient = new ServerMonitorApiClient(_settings.ApiBaseUrl);
        
        // Initialize REST API server for remote control from Dashboard (port 8997)
        _trayApiServer = new TrayApiServer(_serviceManager, _settings, () => RunAutomaticReinstallAsync());
        _trayApiServer.SetScriptStateCallback(OnScriptStateChanged);
        _trayApiServer.Start();
        Debug.WriteLine("Tray API server started on port 8997");
        
        // Create the notify icon
        _notifyIcon = new NotifyIcon
        {
            Icon = _stoppedIcon,
            Text = "Server Monitor - Checking status...",
            Visible = true,
            ContextMenuStrip = CreateContextMenu()
        };
        
        // Double-click opens API docs (Scalar)
        _notifyIcon.DoubleClick += (s, e) => OpenApiDocs();
        
        // Handle balloon click to open HTML report
        _notifyIcon.BalloonTipClicked += OnBalloonTipClicked;
        
        // Set up timer to periodically check service status
        _statusTimer = new System.Windows.Forms.Timer
        {
            Interval = _settings.StatusCheckIntervalMs
        };
        _statusTimer.Tick += StatusTimer_Tick;
        _statusTimer.Start();
        
        // Set up FileSystemWatcher for real-time trigger file detection
        InitializeTriggerFileWatcher();
        
        // Initial status check
        UpdateStatus();
        
        // Load initial alerts as "seen" to suppress startup notification storm
        if (_settings.EnableAlertNotifications && _settings.SuppressStartupAlerts)
        {
            _ = LoadInitialAlertsAsync();
        }
    }
    
    /// <summary>
    /// Loads existing alerts at startup and marks them as "seen" to prevent
    /// a storm of notifications when the tray app starts.
    /// </summary>
    private async Task LoadInitialAlertsAsync()
    {
        try
        {
            // Wait a moment for the service to be available
            await Task.Delay(2000);
            
            var alerts = await _apiClient.GetRecentAlertsAsync(50);
            if (alerts != null)
            {
                foreach (var alert in alerts)
                {
                    _seenAlertIds.Add(alert.Id);
                }
                Debug.WriteLine($"Loaded {_seenAlertIds.Count} existing alerts (suppressing startup notifications)");
            }
            
            _initialAlertsLoaded = true;
        }
        catch (Exception ex)
        {
            Debug.WriteLine($"Error loading initial alerts: {ex.Message}");
            _initialAlertsLoaded = true; // Continue anyway
        }
    }
    
    /// <summary>
    /// Initializes FileSystemWatcher to monitor for trigger files in real-time.
    /// This is more responsive than polling and uses fewer resources.
    /// </summary>
    private void InitializeTriggerFileWatcher()
    {
        try
        {
            var configPath = _settings.ConfigBasePath;
            
            // Verify the directory exists (network share)
            if (!Directory.Exists(configPath))
            {
                Debug.WriteLine($"Trigger file directory not accessible: {configPath}");
                Debug.WriteLine("Will fall back to polling on timer tick");
                return;
            }
            
            _triggerFileWatcher = new FileSystemWatcher(configPath)
            {
                // Watch for new file creation and changes to existing files
                NotifyFilter = NotifyFilters.FileName | NotifyFilters.LastWrite | NotifyFilters.CreationTime,
                // Watch all .txt files
                Filter = "*.txt",
                // Include subdirectories if needed (currently no)
                IncludeSubdirectories = false,
                // Enable events
                EnableRaisingEvents = true
            };
            
            // Subscribe to events - use Created for new files, Changed for modifications
            _triggerFileWatcher.Created += OnTriggerFileDetected;
            _triggerFileWatcher.Changed += OnTriggerFileDetected;
            
            // Handle errors (e.g., network disconnection)
            _triggerFileWatcher.Error += OnWatcherError;
            
            Debug.WriteLine($"FileSystemWatcher initialized for: {configPath}");
        }
        catch (Exception ex)
        {
            Debug.WriteLine($"Failed to initialize FileSystemWatcher: {ex.Message}");
            Debug.WriteLine("Will fall back to polling on timer tick");
            _triggerFileWatcher = null;
        }
    }
    
    /// <summary>
    /// Handles FileSystemWatcher events when trigger files are detected
    /// </summary>
    private void OnTriggerFileDetected(object sender, FileSystemEventArgs e)
    {
        try
        {
            Debug.WriteLine($"FileSystemWatcher: {e.ChangeType} - {e.FullPath}");
            
            // Check if this is one of our trigger files
            var fileName = Path.GetFileName(e.FullPath);
            var machineName = Environment.MachineName;
            
            // Machine-specific trigger file names
            var machineSpecificReinstall = $"ReinstallServerMonitor_{machineName}.txt";
            var machineSpecificStart = $"StartServerMonitor_{machineName}.txt";
            
            // Match: reinstall triggers, start triggers, or stop trigger
            if (fileName.Equals(Path.GetFileName(_settings.ReinstallTriggerFilePath), StringComparison.OrdinalIgnoreCase) ||
                fileName.Equals(machineSpecificReinstall, StringComparison.OrdinalIgnoreCase) ||
                fileName.Equals("StartServerMonitor.txt", StringComparison.OrdinalIgnoreCase) ||
                fileName.Equals(machineSpecificStart, StringComparison.OrdinalIgnoreCase) ||
                fileName.Equals(Path.GetFileName(_settings.StopTrayTriggerFilePath), StringComparison.OrdinalIgnoreCase))
            {
                Debug.WriteLine($"Matched trigger file: {fileName}");
                
                // Delay to ensure file is fully written (important for network shares)
                Task.Delay(500).ContinueWith(_ =>
                {
                    // Marshal back to UI thread for processing
                    _notifyIcon.ContextMenuStrip?.Invoke(() => ProcessTriggerFilesAsync());
                });
            }
        }
        catch (Exception ex)
        {
            Debug.WriteLine($"Error handling trigger file event: {ex.Message}");
        }
    }
    
    /// <summary>
    /// Handles FileSystemWatcher errors (e.g., network disconnection)
    /// </summary>
    private void OnWatcherError(object sender, ErrorEventArgs e)
    {
        var ex = e.GetException();
        Debug.WriteLine($"FileSystemWatcher error: {ex.Message}");
        
        // Try to restart the watcher after a delay
        Task.Delay(5000).ContinueWith(_ =>
        {
            try
            {
                _triggerFileWatcher?.Dispose();
                _notifyIcon.ContextMenuStrip?.Invoke(() => InitializeTriggerFileWatcher());
            }
            catch (Exception restartEx)
            {
                Debug.WriteLine($"Failed to restart FileSystemWatcher: {restartEx.Message}");
            }
        });
    }

    /// <summary>
    /// Creates an icon from FontAwesome character
    /// </summary>
    /// <param name="iconChar">FontAwesome icon (e.g., IconChar.CircleCheck)</param>
    /// <param name="color">Foreground/icon color</param>
    /// <param name="size">Icon size in pixels (default: 32)</param>
    /// <param name="backColor">Background color (default: transparent). If specified, draws background before icon.</param>
    private DrawingIcon CreateIcon(IconChar iconChar, Color color, int size = 32, Color? backColor = null)
    {
        try
        {
            // Create the FontAwesome bitmap
            using var iconBitmap = iconChar.ToBitmap(color, size);
            
            Bitmap finalBitmap;
            if (backColor.HasValue)
            {
                // Create a new bitmap with background color
                finalBitmap = new Bitmap(size, size);
                using (var g = Graphics.FromImage(finalBitmap))
                {
                    g.Clear(backColor.Value);
                    g.DrawImage(iconBitmap, 0, 0);
                }
            }
            else
            {
                // Use the icon bitmap directly (transparent background)
                finalBitmap = new Bitmap(iconBitmap);
            }
            
            // GetHicon() creates a native Windows handle that must be destroyed
            // when done. Icon.FromHandle() doesn't take ownership, so we need to:
            // 1. Create the icon from the handle
            // 2. Clone it (so the clone owns its own handle)
            // 3. Destroy the original native handle
            var hIcon = finalBitmap.GetHicon();
            finalBitmap.Dispose();
            
            using var tempIcon = DrawingIcon.FromHandle(hIcon);
            var clonedIcon = (DrawingIcon)tempIcon.Clone(); // Clone creates a new handle that the Icon owns
            DestroyIcon(hIcon); // Destroy the original handle to prevent leak
            
            return clonedIcon;
        }
        catch (Exception ex)
        {
            Debug.WriteLine($"Error creating icon: {ex.Message}");
            // Fallback to system icon
            return SystemIcons.Application;
        }
    }

    private ContextMenuStrip CreateContextMenu()
    {
        var menu = new ContextMenuStrip();
        
        // Use system renderer for proper Windows theme support
        menu.RenderMode = ToolStripRenderMode.System;
        
        // Use SystemColors.MenuText which automatically adapts to Windows theme (dark/light)
        // This is the proper way to handle theme-aware colors in Windows Forms
        
        // Header
        var headerItem = new ToolStripMenuItem("Server Monitor Control")
        {
            Enabled = false,
            Font = new Font(menu.Font, FontStyle.Bold)
        };
        menu.Items.Add(headerItem);
        
        // Version info - shows installed agent version (fetched from API when service is running)
        _versionInfoItem = new ToolStripMenuItem(
            "Agent Version: Checking...", 
            CreateMenuImage(IconChar.InfoCircle, Color.DodgerBlue))
        {
            Enabled = false  // Display only, not clickable
        };
        menu.Items.Add(_versionInfoItem);
        
        menu.Items.Add(new ToolStripSeparator());
        
        // Open API docs (Scalar) - using FontAwesome image
        _openSwaggerItem = new ToolStripMenuItem("Open API Docs", CreateMenuImage(IconChar.Globe, Color.DodgerBlue), (s, e) => OpenApiDocs());
        menu.Items.Add(_openSwaggerItem);
        
        // Open last HTML report - wrapped with exception handling (Issue 3 fix)
        _openHtmlItem = new ToolStripMenuItem("Open Last HTML Report", CreateMenuImage(IconChar.FileCode, Color.OrangeRed), 
            async (s, e) => await SafeExecuteAsync(OpenLastHtmlReportAsync));
        menu.Items.Add(_openHtmlItem);
        
        // Open last JSON snapshot - wrapped with exception handling (Issue 3 fix)
        _openJsonItem = new ToolStripMenuItem("Open Last JSON Snapshot", CreateMenuImage(IconChar.FileLines, Color.MediumSeaGreen), 
            async (s, e) => await SafeExecuteAsync(OpenLastJsonSnapshotAsync));
        menu.Items.Add(_openJsonItem);
        
        menu.Items.Add(new ToolStripSeparator());
        
        // Service control - all wrapped with exception handling (Issue 3 fix)
        _startServiceItem = new ToolStripMenuItem("Start Service", CreateMenuImage(IconChar.Play, Color.Green), 
            async (s, e) => await SafeExecuteAsync(StartServiceAsync));
        menu.Items.Add(_startServiceItem);
        
        _stopServiceItem = new ToolStripMenuItem("Stop Service", CreateMenuImage(IconChar.Stop, Color.Red), 
            async (s, e) => await SafeExecuteAsync(StopServiceAsync));
        menu.Items.Add(_stopServiceItem);
        
        _restartServiceItem = new ToolStripMenuItem("Restart Service", CreateMenuImage(IconChar.RotateRight, Color.DarkOrange), 
            async (s, e) => await SafeExecuteAsync(RestartServiceAsync));
        menu.Items.Add(_restartServiceItem);
        
        menu.Items.Add(new ToolStripSeparator());
        
        // Install latest version - wrapped with exception handling (Issue 3 fix)
        _installItem = new ToolStripMenuItem("Install Latest Version", CreateMenuImage(IconChar.Download, Color.Purple), 
            async (s, e) => await SafeExecuteAsync(InstallLatestVersionAsync));
        menu.Items.Add(_installItem);
        
        menu.Items.Add(new ToolStripSeparator());
        
        // Exit
        var exitItem = new ToolStripMenuItem("Exit", CreateMenuImage(IconChar.RightFromBracket, Color.Gray), (s, e) => ExitApplication());
        menu.Items.Add(exitItem);
        
        // Subscribe to Opening event to refresh colors before menu is shown
        // This ensures colors are updated if user changed Windows theme
        menu.Opening += (s, e) => RefreshMenuColors(menu);
        
        return menu;
    }
    
    /// <summary>
    /// Refreshes menu item colors based on current Windows theme.
    /// Called each time the menu opens to adapt to theme changes.
    /// </summary>
    private void RefreshMenuColors(ContextMenuStrip menu)
    {
        // SystemColors.MenuText automatically reflects the current Windows theme
        var textColor = SystemColors.MenuText;
        
        foreach (ToolStripItem item in menu.Items)
        {
            if (item is ToolStripMenuItem menuItem)
            {
                menuItem.ForeColor = textColor;
            }
        }
    }

    /// <summary>
    /// Creates an image for menu items from FontAwesome character
    /// </summary>
    private Image CreateMenuImage(IconChar iconChar, Color color, int size = 16)
    {
        try
        {
            return iconChar.ToBitmap(color, size);
        }
        catch
        {
            return new Bitmap(size, size);
        }
    }

    /// <summary>
    /// Called when script running state changes in the API server
    /// </summary>
    private void OnScriptStateChanged(bool hasRunningScripts)
    {
        _hasRunningScripts = hasRunningScripts;
        
        // Update UI on main thread
        try
        {
            _notifyIcon.ContextMenuStrip?.Invoke(() => UpdateStatus());
        }
        catch (Exception ex)
        {
            Debug.WriteLine($"Error updating script state: {ex.Message}");
        }
    }

    private void StatusTimer_Tick(object? sender, EventArgs e)
    {
        // Issue 6 fix: Skip if previous tick is still running
        if (_isStatusCheckInProgress)
        {
            Debug.WriteLine("Skipping timer tick - previous check still in progress");
            return;
        }
        
        _isStatusCheckInProgress = true;
        try
        {
            UpdateStatus();
            
            // Always poll for trigger files - FileSystemWatcher doesn't work reliably
            // over network shares (UNC paths), so we use timer polling as primary method
            ProcessTriggerFilesAsync();
            
            // Check for new alerts (if enabled and service is running)
            if (_settings.EnableAlertNotifications && _serviceManager.IsRunning())
            {
                // Throttle alert polling based on configured interval
                var timeSinceLastPoll = DateTime.UtcNow - _lastAlertPollTime;
                if (timeSinceLastPoll.TotalMilliseconds >= _settings.AlertPollIntervalMs)
                {
                    _lastAlertPollTime = DateTime.UtcNow;
                    _ = CheckForNewAlertsAsync(); // Fire and forget, handles its own exceptions
                }
            }
        }
        finally
        {
            _isStatusCheckInProgress = false;
        }
    }
    
    // ═══════════════════════════════════════════════════════════════════════════════
    // ALERT NOTIFICATION METHODS
    // ═══════════════════════════════════════════════════════════════════════════════
    
    /// <summary>
    /// Checks for new alerts and shows balloon notifications for unseen alerts.
    /// Uses severity-based icons: Error (Critical), Warning, Info (Informational).
    /// </summary>
    private async Task CheckForNewAlertsAsync()
    {
        try
        {
            // Don't check if initial alerts haven't been loaded yet
            if (_settings.SuppressStartupAlerts && !_initialAlertsLoaded)
                return;
            
            var alerts = await _apiClient.GetRecentAlertsAsync(10);
            if (alerts == null || alerts.Count == 0)
                return;
            
            // Find alerts we haven't seen yet
            var newAlerts = alerts.Where(a => !_seenAlertIds.Contains(a.Id)).ToList();
            
            if (newAlerts.Count > 0)
            {
                // Mark as seen
                foreach (var alert in newAlerts)
                {
                    _seenAlertIds.Add(alert.Id);
                }
                
                // Limit seen alerts to prevent memory growth
                TrimSeenAlertIds();
                
                // Update snapshot path for balloon click handling
                await UpdateSnapshotPathsAsync();
                
                // Get the most severe alert to show
                var mostSevere = newAlerts
                    .OrderByDescending(a => a.GetSeverityRank())
                    .ThenByDescending(a => a.Timestamp)
                    .First();
                
                // Show balloon notification
                ShowAlertBalloon(mostSevere, newAlerts.Count);
            }
        }
        catch (Exception ex)
        {
            Debug.WriteLine($"Error checking for new alerts: {ex.Message}");
        }
    }
    
    /// <summary>
    /// Shows a balloon notification for an alert with severity-appropriate icon.
    /// </summary>
    /// <param name="alert">The alert to display</param>
    /// <param name="totalNewAlerts">Total count of new alerts (for title)</param>
    private void ShowAlertBalloon(AlertInfo alert, int totalNewAlerts)
    {
        try
        {
            // Store reference for click handling
            _lastShownAlert = alert;
            
            // Set balloon icon based on severity
            // Critical -> Error icon (red X)
            // Warning -> Warning icon (yellow triangle)
            // Informational -> Info icon (blue i)
            var balloonIcon = alert.GetBalloonIcon();
            
            // Build title
            var title = totalNewAlerts > 1
                ? $"ServerMonitor: {totalNewAlerts} New Alerts"
                : $"ServerMonitor: {alert.Severity}";
            
            // Build message - include category and message
            var message = $"[{alert.Category}] {alert.Message}";
            
            // Truncate if too long (Windows limit ~255 chars)
            if (message.Length > 200)
                message = message.Substring(0, 197) + "...";
            
            // Show balloon
            _notifyIcon.BalloonTipIcon = balloonIcon;
            _notifyIcon.BalloonTipTitle = title;
            _notifyIcon.BalloonTipText = message;
            _notifyIcon.ShowBalloonTip(_settings.BalloonDisplayTimeMs);
            
            Debug.WriteLine($"Alert balloon shown: [{alert.Severity}] {alert.Category}: {alert.Message}");
        }
        catch (Exception ex)
        {
            Debug.WriteLine($"Error showing alert balloon: {ex.Message}");
        }
    }
    
    /// <summary>
    /// Handles balloon tip click - opens HTML report or API docs based on settings.
    /// </summary>
    private void OnBalloonTipClicked(object? sender, EventArgs e)
    {
        try
        {
            if (_settings.OpenHtmlOnBalloonClick && !string.IsNullOrEmpty(_lastSnapshotHtmlPath) && File.Exists(_lastSnapshotHtmlPath))
            {
                // Open the HTML report in browser
                Process.Start(new ProcessStartInfo
                {
                    FileName = _lastSnapshotHtmlPath,
                    UseShellExecute = true
                });
                Debug.WriteLine($"Opened HTML report: {_lastSnapshotHtmlPath}");
            }
            else
            {
                // Fallback to API docs
                OpenApiDocs();
            }
        }
        catch (Exception ex)
        {
            Debug.WriteLine($"Error handling balloon click: {ex.Message}");
            // Final fallback - try API docs
            try { OpenApiDocs(); } catch { }
        }
    }
    
    /// <summary>
    /// Updates the cached snapshot file paths for balloon click handling.
    /// </summary>
    private async Task UpdateSnapshotPathsAsync()
    {
        try
        {
            _lastSnapshotHtmlPath = await _apiClient.GetLastExportedHtmlPathAsync();
            Debug.WriteLine($"Updated snapshot path: {_lastSnapshotHtmlPath}");
        }
        catch (Exception ex)
        {
            Debug.WriteLine($"Error updating snapshot paths: {ex.Message}");
        }
    }
    
    /// <summary>
    /// Trims the seen alert IDs set to prevent unbounded memory growth.
    /// Removes oldest entries when count exceeds MaxSeenAlertIds.
    /// </summary>
    private void TrimSeenAlertIds()
    {
        if (_settings.MaxSeenAlertIds > 0 && _seenAlertIds.Count > _settings.MaxSeenAlertIds)
        {
            // HashSet doesn't have order, so we just remove arbitrary entries
            // This is fine since we're just preventing duplicates, and old alerts
            // won't come back from the API anyway
            var excess = _seenAlertIds.Count - _settings.MaxSeenAlertIds;
            var toRemove = _seenAlertIds.Take(excess).ToList();
            
            foreach (var id in toRemove)
            {
                _seenAlertIds.Remove(id);
            }
            
            Debug.WriteLine($"Trimmed {excess} old alert IDs from seen list");
        }
    }
    
    // ═══════════════════════════════════════════════════════════════════════════════
    // TRIGGER FILE PROCESSING
    // ═══════════════════════════════════════════════════════════════════════════════
    
    /// <summary>
    /// Processes trigger files. Safe to call from any thread - handles exceptions internally.
    /// This is called either by FileSystemWatcher (real-time) or timer fallback.
    /// </summary>
    private async void ProcessTriggerFilesAsync()
    {
        try
        {
            // Check for stop tray trigger file
            var stopTrayTriggerFile = _settings.StopTrayTriggerFilePath;
            if (File.Exists(stopTrayTriggerFile))
            {
                Debug.WriteLine($"Stop tray trigger file detected: {stopTrayTriggerFile}");
                
                // Delete the trigger file first
                try
                {
                    File.Delete(stopTrayTriggerFile);
                    Debug.WriteLine("Stop tray trigger file deleted");
                }
                catch (Exception ex)
                {
                    Debug.WriteLine($"Could not delete stop tray trigger file: {ex.Message}");
                }
                
                // Show balloon notification
                _notifyIcon.BalloonTipIcon = ToolTipIcon.Info;
                _notifyIcon.BalloonTipTitle = "ServerMonitor Tray";
                _notifyIcon.BalloonTipText = "Closing due to remote stop command...";
                _notifyIcon.ShowBalloonTip(2000);
                
                // Wait briefly for user to see notification, then exit
                await Task.Delay(2000);
                ExitApplication();
                return;
            }
            
            // Check for start trigger files (to start the service)
            // Priority 1: Machine-specific start file (StartServerMonitor_SERVERNAME.txt)
            // Priority 2: Global start file (StartServerMonitor.txt)
            var machineName = Environment.MachineName;
            var configDir = Path.GetDirectoryName(_settings.ReinstallTriggerFilePath) ?? "";
            
            var machineSpecificStartFile = Path.Combine(configDir, $"StartServerMonitor_{machineName}.txt");
            var globalStartFile = Path.Combine(configDir, "StartServerMonitor.txt");
            
            string? startTriggerFile = null;
            bool isStartMachineSpecific = false;
            
            if (File.Exists(machineSpecificStartFile))
            {
                startTriggerFile = machineSpecificStartFile;
                isStartMachineSpecific = true;
                Debug.WriteLine($"Machine-specific start trigger file detected: {machineSpecificStartFile}");
            }
            else if (File.Exists(globalStartFile))
            {
                startTriggerFile = globalStartFile;
                isStartMachineSpecific = false;
                Debug.WriteLine($"Global start trigger file detected: {globalStartFile}");
            }
            
            if (startTriggerFile != null && !_serviceManager.IsRunning())
            {
                Debug.WriteLine("Service is not running, processing start trigger...");
                
                // Check if agents are disabled via DisableServerMonitor.txt
                var disableFilePath = Path.Combine(configDir, "DisableServerMonitor.txt");
                if (File.Exists(disableFilePath))
                {
                    Debug.WriteLine($"Agents are DISABLED via {disableFilePath} - ignoring start trigger");
                    _notifyIcon.BalloonTipIcon = ToolTipIcon.Warning;
                    _notifyIcon.BalloonTipTitle = "ServerMonitor Disabled";
                    _notifyIcon.BalloonTipText = "Cannot start: Agents are disabled. Remove DisableServerMonitor.txt to enable.";
                    _notifyIcon.ShowBalloonTip(5000);
                    return; // Don't start while disabled
                }
                
                // Delete machine-specific start files, leave global for other machines
                if (isStartMachineSpecific)
                {
                    try
                    {
                        File.Delete(startTriggerFile);
                        Debug.WriteLine($"Deleted machine-specific start trigger: {startTriggerFile}");
                    }
                    catch (Exception ex)
                    {
                        Debug.WriteLine($"Could not delete start trigger file: {ex.Message}");
                    }
                }
                
                // Show balloon notification
                _notifyIcon.BalloonTipIcon = ToolTipIcon.Info;
                _notifyIcon.BalloonTipTitle = "ServerMonitor";
                _notifyIcon.BalloonTipText = "Starting ServerMonitor service...";
                _notifyIcon.ShowBalloonTip(2000);
                
                // Start the service
                var started = _serviceManager.StartService();
                
                if (started)
                {
                    _notifyIcon.BalloonTipIcon = ToolTipIcon.Info;
                    _notifyIcon.BalloonTipTitle = "ServerMonitor Started";
                    _notifyIcon.BalloonTipText = "Service started successfully";
                    _notifyIcon.ShowBalloonTip(3000);
                }
                else
                {
                    _notifyIcon.BalloonTipIcon = ToolTipIcon.Error;
                    _notifyIcon.BalloonTipTitle = "ServerMonitor Start Failed";
                    _notifyIcon.BalloonTipText = "Could not start the service. Check logs for details.";
                    _notifyIcon.ShowBalloonTip(5000);
                }
                
                UpdateStatus();
                return; // Skip reinstall check for this cycle
            }
            
            // Check for reinstall trigger files
            // Priority 1: Machine-specific trigger file (e.g., ReinstallServerMonitor_SERVERNAME.txt)
            // Priority 2: Global trigger file (ReinstallServerMonitor.txt)
            var machineSpecificTrigger = Path.Combine(configDir, $"ReinstallServerMonitor_{machineName}.txt");
            var globalTrigger = _settings.ReinstallTriggerFilePath;
            
            // Find which trigger file exists (machine-specific takes priority)
            string? reinstallTriggerFile = null;
            bool isMachineSpecific = false;
            
            if (File.Exists(machineSpecificTrigger))
            {
                reinstallTriggerFile = machineSpecificTrigger;
                isMachineSpecific = true;
                Debug.WriteLine($"Machine-specific trigger file detected: {machineSpecificTrigger}");
            }
            else if (File.Exists(globalTrigger))
            {
                reinstallTriggerFile = globalTrigger;
                isMachineSpecific = false;
                Debug.WriteLine($"Global trigger file detected: {globalTrigger}");
            }
            
            if (!_isReinstallInProgress && reinstallTriggerFile != null)
            {
                // Build a signature for this trigger file to prevent repeated processing
                var triggerSignature = GetTriggerFileSignature(reinstallTriggerFile);
                
                // Check if we've already processed this exact trigger file (same signature)
                if (!string.IsNullOrEmpty(triggerSignature) &&
                    _processedTriggerSignatures.TryGetValue(reinstallTriggerFile, out var previousSignature) &&
                    string.Equals(previousSignature, triggerSignature, StringComparison.OrdinalIgnoreCase))
                {
                    // Already processed this trigger file - skip silently (no balloon spam!)
                    Debug.WriteLine($"Trigger file already processed (signature: {triggerSignature}) - skipping");
                    return;
                }
                
                // Read the target version from the trigger file (with retries for network latency)
                var targetVersion = ReadVersionFromTriggerFileWithRetry(reinstallTriggerFile);
                Debug.WriteLine($"Target version from trigger file: {targetVersion ?? "unknown"}");
                
                // Get the currently installed version
                var installedVersion = GetInstalledServerMonitorVersion();
                Debug.WriteLine($"Installed ServerMonitor version: {installedVersion ?? "unknown"}");
                
                // Compare versions
                if (string.IsNullOrEmpty(targetVersion))
                {
                    // No version in trigger file - delete it and skip
                    Debug.WriteLine("Trigger file has no version info - skipping reinstall");
                    DeleteTriggerFile(reinstallTriggerFile);
                    
                    // Record as processed to prevent repeated balloons
                    if (!string.IsNullOrEmpty(triggerSignature))
                        _processedTriggerSignatures[reinstallTriggerFile] = triggerSignature;
                    
                    _notifyIcon.BalloonTipIcon = ToolTipIcon.Warning;
                    _notifyIcon.BalloonTipTitle = "ServerMonitor";
                    _notifyIcon.BalloonTipText = "Reinstall trigger file has no version info. Skipping.";
                    _notifyIcon.ShowBalloonTip(3000);
                }
                else if (AreVersionsEqual(targetVersion, installedVersion))
                {
                    // Versions are the same - no need to reinstall
                    Debug.WriteLine($"Version {installedVersion} matches target {targetVersion} - skipping reinstall");
                    
                    // Only delete machine-specific trigger files when versions match
                    // Global trigger file is left for other machines to process
                    if (isMachineSpecific)
                    {
                        DeleteTriggerFile(reinstallTriggerFile);
                        
                        // Show balloon ONLY for machine-specific triggers
                        _notifyIcon.BalloonTipIcon = ToolTipIcon.Info;
                        _notifyIcon.BalloonTipTitle = "ServerMonitor Already Up-to-Date";
                        _notifyIcon.BalloonTipText = $"Version {installedVersion} is already installed. No update needed.";
                        _notifyIcon.ShowBalloonTip(3000);
                    }
                    // For GLOBAL triggers: DO NOT show balloon (prevents spam on every timer tick)
                    // Just record as processed and move on silently
                    
                    // Record as processed to prevent repeated processing
                    if (!string.IsNullOrEmpty(triggerSignature))
                        _processedTriggerSignatures[reinstallTriggerFile] = triggerSignature;
                }
                else
                {
                    // Versions differ - proceed with reinstall
                    Debug.WriteLine($"Version change detected: {installedVersion} → {targetVersion}");
                    
                    // Record as processed immediately to prevent multiple reinstall attempts
                    if (!string.IsNullOrEmpty(triggerSignature))
                        _processedTriggerSignatures[reinstallTriggerFile] = triggerSignature;
                    
                    // Only delete machine-specific trigger files
                    // Global trigger file is left for other machines to process
                    if (isMachineSpecific)
                    {
                        DeleteTriggerFile(reinstallTriggerFile);
                    }
                    
                    // Run the reinstall (don't await - let it run in background)
                    _ = RunAutomaticReinstallAsync(installedVersion, targetVersion);
                }
            }
        }
        catch (Exception ex)
        {
            // Don't let trigger file check errors crash the timer
            Debug.WriteLine($"Error checking trigger files: {ex.Message}");
        }
    }
    
    /// <summary>
    /// Reads the version from the reinstall trigger file with retry logic
    /// to handle race conditions when file is still being written (especially over network shares)
    /// </summary>
    /// <returns>Version string or null if not found</returns>
    private string? ReadVersionFromTriggerFileWithRetry(string filePath, int maxRetries = 3, int delayMs = 500)
    {
        for (int attempt = 0; attempt < maxRetries; attempt++)
        {
            var version = ReadVersionFromTriggerFile(filePath);
            if (!string.IsNullOrEmpty(version))
            {
                return version;
            }
            
            // File exists but no version found - wait and retry (file might still be writing)
            if (attempt < maxRetries - 1 && File.Exists(filePath))
            {
                Debug.WriteLine($"Trigger file has no version (attempt {attempt + 1}/{maxRetries}), retrying in {delayMs}ms...");
                Thread.Sleep(delayMs);
            }
        }
        
        return null;
    }
    
    /// <summary>
    /// Gets a signature for a trigger file based on its metadata.
    /// Used to detect if a trigger file has changed since last processing.
    /// Signature format: "LastWriteUtcTicks|Length|Version"
    /// </summary>
    private string? GetTriggerFileSignature(string filePath)
    {
        try
        {
            if (!File.Exists(filePath))
                return null;
            
            var info = new FileInfo(filePath);
            var version = ReadVersionFromTriggerFile(filePath) ?? "";
            return $"{info.LastWriteTimeUtc.Ticks}|{info.Length}|{version}";
        }
        catch (Exception ex)
        {
            Debug.WriteLine($"Error getting trigger file signature: {ex.Message}");
            return null;
        }
    }
    
    /// <summary>
    /// Compares two version strings, normalizing format differences.
    /// Handles cases like "1.0.62" vs "1.0.62.0" (trailing .0 is ignored).
    /// </summary>
    private static bool AreVersionsEqual(string? version1, string? version2)
    {
        if (string.IsNullOrEmpty(version1) || string.IsNullOrEmpty(version2))
            return false;
        
        // Direct comparison first (fast path)
        if (string.Equals(version1, version2, StringComparison.OrdinalIgnoreCase))
            return true;
        
        // Normalize versions by removing trailing ".0" parts
        // e.g., "1.0.62.0" → "1.0.62", "1.0.0.0" → "1.0.0.0" (keep at least 3 parts)
        var normalized1 = NormalizeVersion(version1);
        var normalized2 = NormalizeVersion(version2);
        
        Debug.WriteLine($"Version comparison: '{version1}' → '{normalized1}' vs '{version2}' → '{normalized2}'");
        
        return string.Equals(normalized1, normalized2, StringComparison.OrdinalIgnoreCase);
    }
    
    /// <summary>
    /// Normalizes a version string by removing trailing ".0" parts while keeping at least 3 parts.
    /// Examples: "1.0.62.0" → "1.0.62", "1.0.0.0" → "1.0.0", "1.0.62" → "1.0.62"
    /// </summary>
    private static string NormalizeVersion(string version)
    {
        if (string.IsNullOrEmpty(version))
            return version;
        
        // Split into parts
        var parts = version.Split('.');
        
        // Keep at least 3 parts (major.minor.patch)
        var minParts = Math.Min(3, parts.Length);
        
        // Find last non-zero part (but keep at least minParts)
        var lastSignificantIndex = parts.Length - 1;
        while (lastSignificantIndex >= minParts && parts[lastSignificantIndex] == "0")
        {
            lastSignificantIndex--;
        }
        
        // Rejoin with the significant parts
        return string.Join(".", parts.Take(lastSignificantIndex + 1));
    }
    
    /// <summary>
    /// Reads the version from the reinstall trigger file
    /// </summary>
    /// <returns>Version string or null if not found</returns>
    private string? ReadVersionFromTriggerFile(string filePath)
    {
        try
        {
            if (!File.Exists(filePath))
                return null;
                
            var lines = File.ReadAllLines(filePath);
            foreach (var line in lines)
            {
                // Look for "Version=x.y.z" pattern
                if (line.StartsWith("Version=", StringComparison.OrdinalIgnoreCase))
                {
                    return line.Substring("Version=".Length).Trim();
                }
            }
        }
        catch (IOException ioEx)
        {
            // File might be locked - this is expected during race conditions
            Debug.WriteLine($"IO error reading trigger file (file may be locked): {ioEx.Message}");
        }
        catch (Exception ex)
        {
            Debug.WriteLine($"Error reading version from trigger file: {ex.Message}");
        }
        
        return null;
    }
    
    /// <summary>
    /// Gets the version of the locally installed ServerMonitor.exe
    /// First tries the local installation path (from service), then falls back to network path
    /// </summary>
    /// <returns>Version string or null if not found</returns>
    private string? GetInstalledServerMonitorVersion()
    {
        try
        {
            // Priority 1: Get path from the actual installed Windows Service
            var localExePath = GetServiceExecutablePath("ServerMonitor");
            
            // Priority 2: Check common local installation paths
            if (string.IsNullOrEmpty(localExePath) || !File.Exists(localExePath))
            {
                var commonPaths = new[]
                {
                    @"C:\opt\DedgeWinApps\ServerMonitor\ServerMonitor.exe",
                    Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.ProgramFiles), "ServerMonitor", "ServerMonitor.exe"),
                    Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData), "ServerMonitor", "ServerMonitor.exe")
                };
                
                localExePath = commonPaths.FirstOrDefault(File.Exists);
            }
            
            // Priority 3: Fall back to network path from settings (shows available version)
            if (string.IsNullOrEmpty(localExePath) || !File.Exists(localExePath))
            {
                localExePath = _settings.ServerMonitorExePath;
            }
            
            if (!File.Exists(localExePath))
            {
                Debug.WriteLine($"ServerMonitor.exe not found at any known location");
                return null;
            }
            
            Debug.WriteLine($"Reading version from: {localExePath}");
            var versionInfo = System.Diagnostics.FileVersionInfo.GetVersionInfo(localExePath);
            
            // Try ProductVersion first (usually contains the semantic version)
            if (!string.IsNullOrEmpty(versionInfo.ProductVersion))
            {
                // ProductVersion might contain additional info like "+commitsha", strip it
                var version = versionInfo.ProductVersion.Split('+')[0].Trim();
                return version;
            }
            
            // Fall back to FileVersion
            if (!string.IsNullOrEmpty(versionInfo.FileVersion))
            {
                return versionInfo.FileVersion;
            }
            
            // Last resort: construct from version parts
            if (versionInfo.FileMajorPart > 0 || versionInfo.FileMinorPart > 0 || versionInfo.FileBuildPart > 0)
            {
                return $"{versionInfo.FileMajorPart}.{versionInfo.FileMinorPart}.{versionInfo.FileBuildPart}";
            }
        }
        catch (Exception ex)
        {
            Debug.WriteLine($"Error getting ServerMonitor version: {ex.Message}");
        }
        
        return null;
    }
    
    /// <summary>
    /// Gets the executable path for a Windows Service from the registry
    /// </summary>
    /// <param name="serviceName">Name of the Windows service</param>
    /// <returns>Path to the executable, or null if not found</returns>
    private string? GetServiceExecutablePath(string serviceName)
    {
        try
        {
            using var key = Microsoft.Win32.Registry.LocalMachine.OpenSubKey(
                $@"SYSTEM\CurrentControlSet\Services\{serviceName}");
            
            if (key == null)
            {
                Debug.WriteLine($"Service '{serviceName}' not found in registry");
                return null;
            }
            
            var imagePath = key.GetValue("ImagePath") as string;
            if (string.IsNullOrEmpty(imagePath))
            {
                return null;
            }
            
            // Remove quotes and any command-line arguments
            imagePath = imagePath.Trim('"');
            
            // Handle paths that might have arguments after the exe
            if (imagePath.Contains(".exe ", StringComparison.OrdinalIgnoreCase))
            {
                var exeIndex = imagePath.IndexOf(".exe ", StringComparison.OrdinalIgnoreCase);
                imagePath = imagePath.Substring(0, exeIndex + 4);
            }
            
            Debug.WriteLine($"Service '{serviceName}' executable path: {imagePath}");
            return imagePath;
        }
        catch (Exception ex)
        {
            Debug.WriteLine($"Error getting service executable path: {ex.Message}");
            return null;
        }
    }
    
    /// <summary>
    /// Safely deletes a trigger file
    /// </summary>
    private void DeleteTriggerFile(string filePath)
    {
        try
        {
            if (File.Exists(filePath))
            {
                File.Delete(filePath);
                Debug.WriteLine($"Trigger file deleted: {filePath}");
            }
        }
        catch (Exception ex)
        {
            Debug.WriteLine($"Could not delete trigger file: {ex.Message}");
        }
    }
    
    /// <summary>
    /// Runs automatic reinstall triggered by the trigger file (no confirmation dialog)
    /// </summary>
    /// <param name="fromVersion">Currently installed version (for display)</param>
    /// <param name="toVersion">Target version to install (for display)</param>
    private async Task RunAutomaticReinstallAsync(string? fromVersion = null, string? toVersion = null)
    {
        if (_isReinstallInProgress)
            return;
            
        _isReinstallInProgress = true;
        
        // Build version info string for notifications
        var versionInfo = "";
        if (!string.IsNullOrEmpty(fromVersion) && !string.IsNullOrEmpty(toVersion))
        {
            versionInfo = $" ({fromVersion} → {toVersion})";
        }
        else if (!string.IsNullOrEmpty(toVersion))
        {
            versionInfo = $" (to v{toVersion})";
        }
        
        try
        {
            SetMenuItemsEnabled(false);
            
            // Show installing icon and status
            _notifyIcon.Icon = _installingIcon;
            _notifyIcon.Text = $"Server Monitor - Updating{versionInfo}...";
            
            // Show balloon notification that update is starting
            _notifyIcon.BalloonTipIcon = ToolTipIcon.Info;
            _notifyIcon.BalloonTipTitle = "ServerMonitor Update";
            _notifyIcon.BalloonTipText = $"Installing update{versionInfo}... Tray app will restart automatically.";
            _notifyIcon.ShowBalloonTip(3000);
            
            // Give user a moment to see the notification
            await Task.Delay(1500);
            
            // Launch installation as a detached process (doesn't wait)
            var success = RunInstallation();
            
            if (success)
            {
                // Installation launched successfully - exit tray app so it can be updated
                // The install script will restart the tray app when done
                Debug.WriteLine($"Auto-update launched{versionInfo}, exiting tray app to allow update...");
                await Task.Delay(500); // Brief delay to ensure process is running
                ExitApplication();
            }
            else
            {
                // Failed to launch installation
                _notifyIcon.BalloonTipIcon = ToolTipIcon.Error;
                _notifyIcon.BalloonTipTitle = "Update Failed";
                _notifyIcon.BalloonTipText = $"Failed to launch update{versionInfo}. Check if PowerShell 7 is installed.";
                _notifyIcon.ShowBalloonTip(5000);
                _isReinstallInProgress = false;
                UpdateStatus();
            }
        }
        catch (Exception ex)
        {
            // Show balloon notification for exception
            _notifyIcon.BalloonTipIcon = ToolTipIcon.Error;
            _notifyIcon.BalloonTipTitle = "Update Error";
            _notifyIcon.BalloonTipText = $"Update failed: {ex.Message}";
            _notifyIcon.ShowBalloonTip(5000);
            _isReinstallInProgress = false;
            UpdateStatus();
        }
    }

    // Cached version from API (to avoid calling API on every status update)
    private string? _cachedAgentVersion;
    private DateTime _lastVersionCheck = DateTime.MinValue;
    private readonly TimeSpan _versionCacheDuration = TimeSpan.FromSeconds(30);
    
    private void UpdateStatus()
    {
        try
        {
            var isRunning = _serviceManager.IsRunning();
            var status = _serviceManager.GetStatus();
            
            // Update icon - script running takes priority over service status
            if (_hasRunningScripts)
            {
                _notifyIcon.Icon = _scriptRunningIcon;
            }
            else
            {
                _notifyIcon.Icon = isRunning ? _runningIcon : _stoppedIcon;
            }
            
            // Get version from API if service is running and cache is stale
            if (isRunning && (DateTime.Now - _lastVersionCheck) > _versionCacheDuration)
            {
                _ = UpdateVersionFromApiAsync();
            }
            
            // Update tooltip with version info
            var scriptIndicator = _hasRunningScripts ? " [Script Running]" : "";
            _notifyIcon.Text = isRunning 
                ? $"Server Monitor v{_cachedAgentVersion ?? "?"} - Running ({status}){scriptIndicator}"
                : $"Server Monitor v{_cachedAgentVersion ?? "?"} - {status}{scriptIndicator}";
            
            // Update version display in menu
            UpdateVersionDisplay(_cachedAgentVersion);
            
            // Update menu item states
            UpdateMenuStates(isRunning);
        }
        catch (Exception ex)
        {
            Debug.WriteLine($"Error updating status: {ex.Message}");
            _notifyIcon.Icon = _stoppedIcon;
            _notifyIcon.Text = "Server Monitor - Status unknown";
            UpdateVersionDisplay(null);
            UpdateMenuStates(false);
        }
    }
    
    /// <summary>
    /// Gets the agent version from the API and caches it
    /// </summary>
    private async Task UpdateVersionFromApiAsync()
    {
        try
        {
            var versionInfo = await _apiClient.GetCurrentVersionAsync();
            if (versionInfo != null)
            {
                _cachedAgentVersion = versionInfo.Version;
                _lastVersionCheck = DateTime.Now;
                
                // Update the UI on the main thread
                _notifyIcon.ContextMenuStrip?.Invoke(() => UpdateVersionDisplay(_cachedAgentVersion));
                
                Debug.WriteLine($"Agent version from API: {_cachedAgentVersion}");
            }
        }
        catch (Exception ex)
        {
            Debug.WriteLine($"Error getting version from API: {ex.Message}");
        }
    }
    
    /// <summary>
    /// Updates the version display in the context menu
    /// </summary>
    private void UpdateVersionDisplay(string? version)
    {
        if (_versionInfoItem != null)
        {
            _versionInfoItem.Text = $"Agent Version: {version ?? "Not available"}";
        }
    }

    private void UpdateMenuStates(bool isRunning)
    {
        // Service must be running for these
        _openSwaggerItem.Enabled = isRunning;
        _openHtmlItem.Enabled = isRunning;
        _openJsonItem.Enabled = isRunning;
        
        // Start only available when stopped
        _startServiceItem.Enabled = !isRunning;
        
        // Stop and restart only available when running
        _stopServiceItem.Enabled = isRunning;
        _restartServiceItem.Enabled = isRunning;
        
        // Update install menu item based on version comparison
        UpdateInstallMenuItemState();
    }

    /// <summary>
    /// Updates the Install menu item based on version comparison with trigger file
    /// </summary>
    private void UpdateInstallMenuItemState()
    {
        try
        {
            var currentVersion = GetCurrentTrayVersion();
            var latestVersion = GetLatestVersionFromTriggerFile();

            if (string.IsNullOrEmpty(latestVersion))
            {
                // Can't read trigger file - enable install button
                _installItem.Enabled = true;
                _installItem.Text = "Install Latest Version";
                return;
            }

            if (AreVersionsEqual(currentVersion, latestVersion))
            {
                // Already on latest version
                _installItem.Enabled = false;
                _installItem.Text = $"✅ Up to date (v{currentVersion})";
            }
            else
            {
                // Update available
                _installItem.Enabled = true;
                _installItem.Text = $"⬆️ Update to v{latestVersion}";
            }
        }
        catch (Exception ex)
        {
            Debug.WriteLine($"Error checking version for install menu: {ex.Message}");
            _installItem.Enabled = true;
            _installItem.Text = "Install Latest Version";
        }
    }

    /// <summary>
    /// Gets the current version of this Tray application
    /// </summary>
    private static string GetCurrentTrayVersion()
    {
        try
        {
            var assembly = System.Reflection.Assembly.GetExecutingAssembly();
            var version = assembly.GetName().Version;
            // Return Major.Minor.Build (skip Revision)
            return version != null ? $"{version.Major}.{version.Minor}.{version.Build}" : "0.0.0";
        }
        catch
        {
            return "0.0.0";
        }
    }

    /// <summary>
    /// Reads the latest version from the reinstall trigger file
    /// </summary>
    private string? GetLatestVersionFromTriggerFile()
    {
        try
        {
            var triggerFilePath = _settings.ReinstallTriggerFilePath;
            if (!File.Exists(triggerFilePath))
            {
                return null;
            }

            var lines = File.ReadAllLines(triggerFilePath);
            foreach (var line in lines)
            {
                if (line.StartsWith("Version=", StringComparison.OrdinalIgnoreCase))
                {
                    return line.Substring("Version=".Length).Trim();
                }
            }
            return null;
        }
        catch
        {
            return null;
        }
    }

    private void OpenApiDocs()
    {
        try
        {
            Process.Start(new ProcessStartInfo
            {
                FileName = "http://localhost:8999/scalar/v1",
                UseShellExecute = true
            });
        }
        catch (Exception ex)
        {
            ShowError($"Failed to open API docs: {ex.Message}");
        }
    }

    private async Task OpenLastHtmlReportAsync()
    {
        try
        {
            var htmlPath = await _apiClient.GetLastExportedHtmlPathAsync();
            
            if (!string.IsNullOrEmpty(htmlPath) && File.Exists(htmlPath))
            {
                Process.Start(new ProcessStartInfo
                {
                    FileName = htmlPath,
                    UseShellExecute = true
                });
            }
            else
            {
                ShowError("No HTML report found. Ensure ServerMonitor has exported at least one snapshot.");
            }
        }
        catch (Exception ex)
        {
            ShowError($"Failed to open HTML report: {ex.Message}");
        }
    }

    private async Task OpenLastJsonSnapshotAsync()
    {
        try
        {
            var jsonPath = await _apiClient.GetLastExportedJsonPathAsync();
            
            if (!string.IsNullOrEmpty(jsonPath) && File.Exists(jsonPath))
            {
                Process.Start(new ProcessStartInfo
                {
                    FileName = jsonPath,
                    UseShellExecute = true
                });
            }
            else
            {
                ShowError("No JSON snapshot found. Ensure ServerMonitor has exported at least one snapshot.");
            }
        }
        catch (Exception ex)
        {
            ShowError($"Failed to open JSON snapshot: {ex.Message}");
        }
    }

    private async Task StartServiceAsync()
    {
        try
        {
            // Check if agents are disabled via DisableServerMonitor.txt
            var configDir = Path.GetDirectoryName(_settings.ReinstallTriggerFilePath) ?? "";
            var disableFilePath = Path.Combine(configDir, "DisableServerMonitor.txt");
            if (File.Exists(disableFilePath))
            {
                ShowError("Cannot start: Agents are DISABLED.\n\nRemove DisableServerMonitor.txt from the config folder to enable agents.");
                return;
            }
            
            SetMenuItemsEnabled(false);
            _notifyIcon.Text = "Server Monitor - Starting...";
            
            var success = await Task.Run(() => _serviceManager.StartService());
            
            if (success)
            {
                ShowInfo("ServerMonitor service started successfully.");
            }
            else
            {
                ShowError("Failed to start ServerMonitor service. Check that the service is installed.");
            }
        }
        catch (Exception ex)
        {
            ShowError($"Failed to start service: {ex.Message}");
        }
        finally
        {
            UpdateStatus();
        }
    }

    private async Task StopServiceAsync()
    {
        try
        {
            SetMenuItemsEnabled(false);
            _notifyIcon.Text = "Server Monitor - Stopping...";
            
            var result = await Task.Run(() => _serviceManager.StopService(forceKillOnTimeout: true));
            
            if (result.Success)
            {
                if (result.ForceKilled)
                {
                    ShowWarning("ServerMonitor service was force-stopped (process killed after timeout).");
                }
                else
                {
                    ShowInfo("ServerMonitor service stopped successfully.");
                }
            }
            else
            {
                var errorMsg = string.IsNullOrEmpty(result.ErrorMessage)
                    ? "Failed to stop ServerMonitor service."
                    : $"Failed to stop service: {result.ErrorMessage}";
                ShowError(errorMsg);
            }
        }
        catch (Exception ex)
        {
            ShowError($"Failed to stop service: {ex.Message}");
        }
        finally
        {
            UpdateStatus();
        }
    }

    private async Task RestartServiceAsync()
    {
        try
        {
            SetMenuItemsEnabled(false);
            _notifyIcon.Text = "Server Monitor - Restarting...";
            
            var success = await Task.Run(() => _serviceManager.RestartService());
            
            if (success)
            {
                ShowInfo("ServerMonitor service restarted successfully.");
            }
            else
            {
                ShowError("Failed to restart ServerMonitor service.");
            }
        }
        catch (Exception ex)
        {
            ShowError($"Failed to restart service: {ex.Message}");
        }
        finally
        {
            UpdateStatus();
        }
    }

    private async Task InstallLatestVersionAsync()
    {
        try
        {
            var result = MessageBox.Show(
                "This will:\n\n" +
                "1. Update the ServerMonitorAgent install script\n" +
                "2. Run the installation script\n" +
                "3. Restart both ServerMonitor service and this tray app\n\n" +
                "The tray app will close and reopen automatically.\n\n" +
                "Continue?",
                "Install Latest Version",
                MessageBoxButtons.YesNo,
                MessageBoxIcon.Question);
            
            if (result != DialogResult.Yes)
                return;
            
            SetMenuItemsEnabled(false);
            
            // Show installing icon and status
            _notifyIcon.Icon = _installingIcon;
            _notifyIcon.Text = "Server Monitor - Launching installation...";
            
            // Show balloon notification that we're starting
            _notifyIcon.BalloonTipIcon = ToolTipIcon.Info;
            _notifyIcon.BalloonTipTitle = "ServerMonitor Installation";
            _notifyIcon.BalloonTipText = "Launching installer... This tray app will close and restart automatically.";
            _notifyIcon.ShowBalloonTip(3000);
            
            // Give user a moment to see the notification
            await Task.Delay(1500);
            
            // Launch the installation as a detached process
            var success = RunInstallation();
            
            if (success)
            {
                // Installation launched successfully - exit tray app so it can be updated
                // The install script will restart the tray app when done
                Debug.WriteLine("Installation launched, exiting tray app to allow update...");
                await Task.Delay(500); // Brief delay to ensure process is running
                ExitApplication();
            }
            else
            {
                // Failed to launch installation
                _notifyIcon.BalloonTipIcon = ToolTipIcon.Error;
                _notifyIcon.BalloonTipTitle = "Installation Failed";
                _notifyIcon.BalloonTipText = "Failed to launch installation process. Check if PowerShell 7 is installed.";
                _notifyIcon.ShowBalloonTip(5000);
                UpdateStatus();
            }
        }
        catch (Exception ex)
        {
            // Show balloon notification for exception
            _notifyIcon.BalloonTipIcon = ToolTipIcon.Error;
            _notifyIcon.BalloonTipTitle = "Installation Error";
            _notifyIcon.BalloonTipText = $"Installation failed: {ex.Message}";
            _notifyIcon.ShowBalloonTip(5000);
            UpdateStatus();
        }
    }

    /// <summary>
    /// Launches the installation process as a completely detached process.
    /// The install script will update both ServerMonitor and ServerMonitorTrayIcon,
    /// so we must NOT wait for it - we launch and exit.
    /// </summary>
    /// <returns>True if the process was launched successfully</returns>
    private bool RunInstallation()
    {
        try
        {
            // Use full path to PowerShell 7
            const string pwsh7Path = @"C:\Program Files\PowerShell\7\pwsh.exe";
            var pwshPath = File.Exists(pwsh7Path) ? pwsh7Path : "pwsh.exe";
            
            // Create a PowerShell script that runs both commands
            // This ensures both steps run even if we exit
            // Explicitly import modules in case PSModulePath is not configured
            var installCommands = @"
                # Ensure modules are available (add DedgeCommon to PSModulePath if needed)
                $fkModulePath = 'C:\opt\src\DedgeSrc\DedgeSystemTools\Folders\DedgeCommon\Software\PowerShellModules'
                if ($env:PSModulePath -notlike ""*$fkModulePath*"") {
                    $env:PSModulePath = ""$fkModulePath;$env:PSModulePath""
                }
                Import-Module GlobalFunctions -Force -ErrorAction Stop
                Import-Module SoftwareUtils -Force -ErrorAction Stop
                
                # Step 1: Update the install script (copies from DedgeCommon to local DedgePshApps)
                Install-OurPshApp -AppName 'ServerMonitorAgent'
                
                # Step 2: Run the install script (this will also restart the tray app)
                Start-OurPshApp -AppName 'ServerMonitorAgent'
            ";
            
            // Escape for command line
            var encodedCommands = Convert.ToBase64String(System.Text.Encoding.Unicode.GetBytes(installCommands));
            
            var startInfo = new ProcessStartInfo
            {
                FileName = pwshPath,
                // Use -EncodedCommand for reliable script execution
                Arguments = $"-NoProfile -ExecutionPolicy Bypass -EncodedCommand {encodedCommands}",
                // UseShellExecute = true makes it a completely independent process
                UseShellExecute = true,
                // Don't redirect anything - process is detached
                RedirectStandardOutput = false,
                RedirectStandardError = false,
                RedirectStandardInput = false,
                // Show window so user can see progress (optional, can set to true for hidden)
                CreateNoWindow = false,
                WindowStyle = ProcessWindowStyle.Normal
            };
            
            Debug.WriteLine($"Launching detached PowerShell process: {pwshPath}");
            Debug.WriteLine("Install script will update both ServerMonitor and ServerMonitorTrayIcon");
            
            var process = Process.Start(startInfo);
            if (process == null)
            {
                Debug.WriteLine("Failed to start PowerShell 7 process");
                return false;
            }
            
            Debug.WriteLine($"Install process launched with PID: {process.Id}");
            Debug.WriteLine("Tray app will now exit to allow update...");
            
            // Don't wait for the process - it's detached
            // The install script will restart the tray app when done
            return true;
        }
        catch (Exception ex)
        {
            Debug.WriteLine($"Installation launch error: {ex.Message}");
            return false;
        }
    }

    private void SetMenuItemsEnabled(bool enabled)
    {
        _startServiceItem.Enabled = enabled;
        _stopServiceItem.Enabled = enabled;
        _restartServiceItem.Enabled = enabled;
        _installItem.Enabled = enabled;
    }

    private void ShowError(string message)
    {
        _notifyIcon.BalloonTipIcon = ToolTipIcon.Error;
        _notifyIcon.BalloonTipTitle = "Server Monitor";
        _notifyIcon.BalloonTipText = message;
        _notifyIcon.ShowBalloonTip(5000);
    }

    private void ShowInfo(string message)
    {
        _notifyIcon.BalloonTipIcon = ToolTipIcon.Info;
        _notifyIcon.BalloonTipTitle = "Server Monitor";
        _notifyIcon.BalloonTipText = message;
        _notifyIcon.ShowBalloonTip(3000);
    }
    
    private void ShowWarning(string message)
    {
        _notifyIcon.BalloonTipIcon = ToolTipIcon.Warning;
        _notifyIcon.BalloonTipTitle = "Server Monitor";
        _notifyIcon.BalloonTipText = message;
        _notifyIcon.ShowBalloonTip(4000);
    }
    
    /// <summary>
    /// Safely executes an async operation with proper exception handling.
    /// This is the fix for Issue 3 (async void Exception Handling).
    /// 
    /// Usage: async (s, e) => await SafeExecuteAsync(SomeAsyncMethod)
    /// 
    /// This ensures any exception thrown by the async method is caught and logged
    /// rather than crashing the application via the SynchronizationContext.
    /// </summary>
    /// <param name="asyncAction">The async method to execute</param>
    private async Task SafeExecuteAsync(Func<Task> asyncAction)
    {
        try
        {
            await asyncAction();
        }
        catch (Exception ex)
        {
            Debug.WriteLine($"Async operation failed: {ex}");
            
            // Show user-friendly error notification
            _notifyIcon.BalloonTipIcon = ToolTipIcon.Error;
            _notifyIcon.BalloonTipTitle = "Server Monitor Error";
            _notifyIcon.BalloonTipText = ex.Message;
            _notifyIcon.ShowBalloonTip(5000);
        }
    }

    private void ExitApplication()
    {
        _statusTimer.Stop();
        _statusTimer.Dispose();
        _triggerFileWatcher?.Dispose();
        _notifyIcon.Visible = false;
        _notifyIcon.Dispose();
        _runningIcon.Dispose();
        _stoppedIcon.Dispose();
        _installingIcon.Dispose();
        _scriptRunningIcon.Dispose();
        _apiClient.Dispose();
        Application.Exit();
    }

    protected override void Dispose(bool disposing)
    {
        if (disposing)
        {
            _statusTimer?.Dispose();
            _triggerFileWatcher?.Dispose();
            _trayApiServer?.Dispose();
            _notifyIcon?.Dispose();
            _runningIcon?.Dispose();
            _stoppedIcon?.Dispose();
            _installingIcon?.Dispose();
            _scriptRunningIcon?.Dispose();
            _apiClient?.Dispose();
        }
        base.Dispose(disposing);
    }
    
    // ═══════════════════════════════════════════════════════════════════════════════
    // ISSUE 3 FIX: async void Exception Handling
    // ═══════════════════════════════════════════════════════════════════════════════
    // 
    // The Problem:
    //   In C#, async void methods have special exception handling behavior:
    //   - Exceptions thrown in async void methods are raised on the SynchronizationContext
    //   - In Windows Forms, this means they go to Application.ThreadException
    //   - If not handled there, they crash the application
    //   
    // Where we use async void:
    //   1. Event handlers (required by delegate signature): async (s, e) => await SomeAsync()
    //   2. Fire-and-forget calls: _ = SomeAsync() (correctly returns Task, no issue)
    //   3. ProcessTriggerFilesAsync() - called from timer and FileSystemWatcher
    //
    // Our Solution:
    //   - All async void methods wrap their body in try-catch
    //   - Exceptions are logged via Debug.WriteLine (visible in debugger output)
    //   - Critical errors show balloon notifications to the user
    //   - Application-level handler catches any escaping exceptions
    //
    // Alternative approaches (not used here):
    //   a) Use IProgress<T> pattern - complex for simple scenarios
    //   b) TaskScheduler.UnobservedTaskException - only for Task-based, not async void
    //   c) Custom event handler wrappers - adds complexity
    //
    // Best Practice:
    //   Avoid async void except for event handlers. When forced to use async void:
    //   1. Wrap entire body in try-catch
    //   2. Log all exceptions
    //   3. Never let exceptions escape
    //
    // Example of proper async void event handler:
    //   async void Button_Click(object? sender, EventArgs e)
    //   {
    //       try
    //       {
    //           await DoWorkAsync();
    //       }
    //       catch (Exception ex)
    //       {
    //           Debug.WriteLine($"Error: {ex.Message}");
    //           ShowError(ex.Message);
    //       }
    //   }
    // ═══════════════════════════════════════════════════════════════════════════════
}
