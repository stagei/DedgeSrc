using System;
using System.Collections.Generic;
using System.Diagnostics;
using System.Drawing;
using System.IO;
using System.Linq;
using System.Runtime.InteropServices;
using System.Text.Json;
using System.Windows.Forms;
using Microsoft.Win32;
using NLog;
using DbExplorerTray.Models;

namespace DbExplorerTray.Services;

/// <summary>
/// Manages the system tray icon, context menu, and notifications
/// </summary>
public class TrayIconManager : IDisposable
{
    [DllImport("user32.dll")]
    private static extern bool SetForegroundWindow(IntPtr hWnd);

    [DllImport("user32.dll")]
    private static extern bool ShowWindow(IntPtr hWnd, int nCmdShow);

    private const int SW_RESTORE = 9;

    private static readonly Logger Logger = LogManager.GetCurrentClassLogger();
    private NotifyIcon? _notifyIcon;
    private bool _disposed = false;
    private bool _isDarkMode = false;

    public void Initialize()
    {
        if (_disposed)
            throw new ObjectDisposedException(nameof(TrayIconManager));

        try
        {
            Logger.Debug("Initializing tray icon manager");

            // Detect system theme
            _isDarkMode = IsSystemDarkMode();
            Logger.Debug("System dark mode detected: {IsDarkMode}", _isDarkMode);

            // Create notify icon
            _notifyIcon = new NotifyIcon
            {
                Icon = GetApplicationIcon(),
                Text = "DbExplorer",
                Visible = true
            };

            // Build context menu
            BuildContextMenu();

            // Handle double-click to show main window
            _notifyIcon.DoubleClick += (s, e) => ShowMainWindow();

            // Listen for theme changes
            SystemEvents.UserPreferenceChanged += SystemEvents_UserPreferenceChanged;

            Logger.Info("Tray icon manager initialized successfully");
        }
        catch (Exception ex)
        {
            Logger.Error(ex, "Failed to initialize tray icon manager");
            throw;
        }
    }

    private void SystemEvents_UserPreferenceChanged(object sender, UserPreferenceChangedEventArgs e)
    {
        if (e.Category == UserPreferenceCategory.General)
        {
            var newDarkMode = IsSystemDarkMode();
            if (newDarkMode != _isDarkMode)
            {
                Logger.Debug("System theme changed, rebuilding context menu");
                _isDarkMode = newDarkMode;
                BuildContextMenu();
            }
        }
    }

    private static bool IsSystemDarkMode()
    {
        try
        {
            using var key = Registry.CurrentUser.OpenSubKey(@"Software\Microsoft\Windows\CurrentVersion\Themes\Personalize");
            if (key != null)
            {
                var value = key.GetValue("AppsUseLightTheme");
                if (value is int intValue)
                {
                    return intValue == 0; // 0 = dark mode, 1 = light mode
                }
            }
        }
        catch (Exception ex)
        {
            Logger.Debug(ex, "Failed to detect system theme, defaulting to light mode");
        }
        return false;
    }

    private Icon GetApplicationIcon()
    {
        try
        {
            // Try multiple possible locations for the icon
            var possiblePaths = new[]
            {
                Path.Combine(AppDomain.CurrentDomain.BaseDirectory, "Resources", "dEdge.ico"),
                Path.Combine(AppDomain.CurrentDomain.BaseDirectory, "..", "Resources", "dEdge.ico"),
                Path.Combine(AppDomain.CurrentDomain.BaseDirectory, "..", "..", "Resources", "dEdge.ico"),
                Path.Combine(AppDomain.CurrentDomain.BaseDirectory, "..", "..", "..", "Resources", "dEdge.ico"),
                Path.Combine(Path.GetDirectoryName(System.Reflection.Assembly.GetExecutingAssembly().Location) ?? "", "Resources", "dEdge.ico")
            };

            foreach (var iconPath in possiblePaths)
            {
                var fullPath = Path.GetFullPath(iconPath);
                if (File.Exists(fullPath))
                {
                    Logger.Debug("Found application icon at: {Path}", fullPath);
                    return new Icon(fullPath);
                }
            }

            // Use default system icon as last resort
            Logger.Warn("Application icon not found in any expected location, using default system icon");
            return SystemIcons.Application;
        }
        catch (Exception ex)
        {
            Logger.Error(ex, "Failed to load application icon, using default");
            return SystemIcons.Application;
        }
    }

    private void BuildContextMenu()
    {
        if (_notifyIcon == null)
            return;

        try
        {
            Logger.Debug("Building context menu");

            var menu = new ContextMenuStrip();
            
            // Apply theme-aware renderer
            menu.Renderer = new ThemeAwareToolStripRenderer(_isDarkMode);

            // Connections submenu
            var connectionsMenu = new ToolStripMenuItem("Connections");
            var profiles = LoadConnectionProfiles();

            if (profiles.Count > 0)
            {
                foreach (var profile in profiles)
                {
                    var profileItem = new ToolStripMenuItem(profile.Name)
                    {
                        Tag = profile
                    };
                    profileItem.Click += (s, e) => LaunchConnection(profile);
                    connectionsMenu.DropDownItems.Add(profileItem);
                }

                connectionsMenu.DropDownItems.Add(new ToolStripSeparator());
            }

            // Manage Connections item
            var manageItem = new ToolStripMenuItem("Manage Connections...");
            manageItem.Click += (s, e) => ShowMainWindow();
            connectionsMenu.DropDownItems.Add(manageItem);

            menu.Items.Add(connectionsMenu);
            menu.Items.Add(new ToolStripSeparator());

            // Show Main Window
            var showWindowItem = new ToolStripMenuItem("Show Main Window");
            showWindowItem.Click += (s, e) => ShowMainWindow();
            menu.Items.Add(showWindowItem);

            // Settings
            var settingsItem = new ToolStripMenuItem("Settings...");
            settingsItem.Click += (s, e) => ShowMainWindowWithSettings();
            menu.Items.Add(settingsItem);

            menu.Items.Add(new ToolStripSeparator());

            // Exit
            var exitItem = new ToolStripMenuItem("Exit");
            exitItem.Click += (s, e) => ExitApplication();
            menu.Items.Add(exitItem);

            _notifyIcon.ContextMenuStrip = menu;

            Logger.Debug("Context menu built with {Count} connections", profiles.Count);
        }
        catch (Exception ex)
        {
            Logger.Error(ex, "Failed to build context menu");
        }
    }

    private List<ConnectionProfile> LoadConnectionProfiles()
    {
        try
        {
            var connectionsFile = GetConnectionsFilePath();

            if (!File.Exists(connectionsFile))
            {
                Logger.Debug("Connections file not found: {File}", connectionsFile);
                return new List<ConnectionProfile>();
            }

            var json = File.ReadAllText(connectionsFile);
            var options = new JsonSerializerOptions
            {
                PropertyNameCaseInsensitive = true
            };
            var connectionsData = JsonSerializer.Deserialize<ConnectionsFile>(json, options);
            var profiles = connectionsData?.Connections ?? new List<ConnectionProfile>();

            // Sort by lastUsed (most recent first)
            profiles = profiles
                .OrderByDescending(p => p.LastUsed ?? "")
                .ToList();

            Logger.Debug("Loaded {Count} connection profiles", profiles.Count);
            return profiles;
        }
        catch (Exception ex)
        {
            Logger.Error(ex, "Failed to load connection profiles");
            return new List<ConnectionProfile>();
        }
    }
    
    /// <summary>
    /// Gets the user data folder (same as main app: Documents\DbExplorer or custom from preferences).
    /// </summary>
    private string GetUserDataFolder()
    {
        var defaultFolder = Path.Combine(
            Environment.GetFolderPath(Environment.SpecialFolder.MyDocuments),
            "DbExplorer");
        var preferencesPath = Path.Combine(defaultFolder, "preferences.json");
        if (!File.Exists(preferencesPath))
            return defaultFolder;
        try
        {
            var prefsJson = File.ReadAllText(preferencesPath);
            var prefs = JsonSerializer.Deserialize<Dictionary<string, object>>(prefsJson);
            if (prefs != null && prefs.TryGetValue("userDataFolder", out var folder) && folder is JsonElement elem)
            {
                var customFolder = elem.GetString();
                if (!string.IsNullOrEmpty(customFolder) && Directory.Exists(customFolder))
                {
                    Logger.Debug("Using custom user data folder from preferences: {Path}", customFolder);
                    return customFolder;
                }
            }
        }
        catch (Exception ex)
        {
            Logger.Debug(ex, "Could not read preferences, using default folder");
        }
        return defaultFolder;
    }

    /// <summary>
    /// Try to find an existing DbExplorer (main app) process and bring its window to foreground.
    /// If profileName is not null, writes it to tray_open_profile.txt so the main app can open that profile when activated.
    /// Returns true if we activated an existing instance; false if main app is not running.
    /// </summary>
    private bool TryActivateExistingMainApp(string? profileName)
    {
        try
        {
            var mainProcesses = Process.GetProcessesByName("DbExplorer");
            foreach (var p in mainProcesses)
            {
                try
                {
                    if (p.MainWindowHandle == IntPtr.Zero)
                        continue;
                    if (profileName != null)
                    {
                        var userDataFolder = GetUserDataFolder();
                        if (!Directory.Exists(userDataFolder))
                            Directory.CreateDirectory(userDataFolder);
                        var filePath = Path.Combine(userDataFolder, "tray_open_profile.txt");
                        File.WriteAllText(filePath, profileName);
                        Logger.Info("Wrote profile request for existing main app: {Profile}", profileName);
                    }
                    ShowWindow(p.MainWindowHandle, SW_RESTORE);
                    SetForegroundWindow(p.MainWindowHandle);
                    Logger.Info("Activated existing DbExplorer window");
                    return true;
                }
                finally
                {
                    p.Dispose();
                }
            }
        }
        catch (Exception ex)
        {
            Logger.Warn(ex, "Could not activate existing main app");
        }
        return false;
    }

    /// <summary>
    /// Gets the path to the connections.json file.
    /// First checks preferences.json for custom user data folder, then falls back to default Documents location.
    /// </summary>
    private string GetConnectionsFilePath()
    {
        var userDataFolder = GetUserDataFolder();
        var oldAppDataFolder = Path.Combine(
            Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData),
            "DbExplorer");
        
        // Check new location first
        var newPath = Path.Combine(userDataFolder, "connections.json");
        if (File.Exists(newPath))
        {
            Logger.Debug("Found connections in new location: {Path}", newPath);
            return newPath;
        }
        
        // Fall back to old AppData location
        var oldPath = Path.Combine(oldAppDataFolder, "connections.json");
        if (File.Exists(oldPath))
        {
            Logger.Debug("Found connections in old AppData location: {Path}", oldPath);
            return oldPath;
        }
        
        // Return new location (will create if needed)
        return newPath;
    }

    private void LaunchConnection(ConnectionProfile profile)
    {
        try
        {
            Logger.Info("Launching connection: {ProfileName}", profile.Name);

            if (TryActivateExistingMainApp(profile.Name))
            {
                Logger.Info("Activated existing main app with profile request: {ProfileName}", profile.Name);
                return;
            }

            var mainAppPath = GetMainApplicationPath();
            if (string.IsNullOrEmpty(mainAppPath) || !File.Exists(mainAppPath))
            {
                Logger.Error("Main application not found: {Path}", mainAppPath);
                ShowNotification("ERROR", "Error", $"Could not find DbExplorer.exe");
                return;
            }

            var startInfo = new ProcessStartInfo
            {
                FileName = mainAppPath,
                Arguments = $"--profile \"{profile.Name}\"",
                UseShellExecute = true,
                WorkingDirectory = Path.GetDirectoryName(mainAppPath) ?? ""
            };

            Process.Start(startInfo);
            Logger.Info("Launched main application with profile: {ProfileName}", profile.Name);
        }
        catch (Exception ex)
        {
            Logger.Error(ex, "Failed to launch connection: {ProfileName}", profile.Name);
            ShowNotification("ERROR", "Error", $"Failed to launch connection: {ex.Message}");
        }
    }

    private string GetMainApplicationPath()
    {
        var currentDir = AppDomain.CurrentDomain.BaseDirectory;
        var possiblePaths = new List<string>
        {
            Path.Combine(currentDir, "DbExplorer.exe"),
            Path.Combine(currentDir, "..", "DbExplorer.exe"),
            Path.Combine(currentDir, "..", "..", "DbExplorer.exe"),
            Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.ProgramFiles), "DbExplorer", "DbExplorer.exe"),
            Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData), "DbExplorer", "DbExplorer.exe")
        };

        // Same directory as this tray exe (when both deployed together)
        try
        {
            var trayPath = Process.GetCurrentProcess().MainModule?.FileName;
            if (!string.IsNullOrEmpty(trayPath))
            {
                var trayDir = Path.GetDirectoryName(trayPath);
                if (!string.IsNullOrEmpty(trayDir))
                    possiblePaths.Insert(0, Path.Combine(trayDir, "DbExplorer.exe"));
            }
        }
        catch (Exception ex)
        {
            Logger.Debug(ex, "Could not get tray exe path for main app lookup");
        }

        // Sibling output when running from solution (tray in DbExplorerTray\bin\Debug\net10.0-windows, main in DbExplorer\bin\Debug\net10.0-windows)
        possiblePaths.Add(Path.GetFullPath(Path.Combine(currentDir, "..", "..", "..", "..", "DbExplorer", "bin", "Debug", "net10.0-windows", "DbExplorer.exe")));

        foreach (var path in possiblePaths)
        {
            var fullPath = Path.GetFullPath(path);
            if (File.Exists(fullPath))
            {
                Logger.Debug("Found main application at: {Path}", fullPath);
                return fullPath;
            }
        }

        Logger.Warn("Main application not found in any expected location");
        return string.Empty;
    }

    private void ShowMainWindow()
    {
        try
        {
            Logger.Debug("Showing main window");
            if (TryActivateExistingMainApp(null))
                return;
            var mainAppPath = GetMainApplicationPath();
            if (!string.IsNullOrEmpty(mainAppPath) && File.Exists(mainAppPath))
            {
                var startInfo = new ProcessStartInfo
                {
                    FileName = mainAppPath,
                    UseShellExecute = true,
                    WorkingDirectory = Path.GetDirectoryName(mainAppPath) ?? ""
                };
                Process.Start(startInfo);
            }
        }
        catch (Exception ex)
        {
            Logger.Error(ex, "Failed to show main window");
        }
    }

    private void ShowMainWindowWithSettings()
    {
        try
        {
            Logger.Debug("Showing main window with settings");
            if (TryActivateExistingMainApp("__SETTINGS__"))
                return;
            var mainAppPath = GetMainApplicationPath();
            if (!string.IsNullOrEmpty(mainAppPath) && File.Exists(mainAppPath))
            {
                var startInfo = new ProcessStartInfo
                {
                    FileName = mainAppPath,
                    Arguments = "--settings",
                    UseShellExecute = true,
                    WorkingDirectory = Path.GetDirectoryName(mainAppPath) ?? ""
                };
                Process.Start(startInfo);
            }
        }
        catch (Exception ex)
        {
            Logger.Error(ex, "Failed to show settings");
        }
    }

    private void ExitApplication()
    {
        Logger.Info("Exit requested from tray icon");
        System.Windows.Forms.Application.Exit();
    }

    public void ShowNotification(string iconType, string title, string message, int timeout = 5000)
    {
        if (_notifyIcon == null || _disposed)
            return;

        try
        {
            var toolTipIcon = iconType.ToUpperInvariant() switch
            {
                "INFO" => ToolTipIcon.Info,
                "WARNING" => ToolTipIcon.Warning,
                "ERROR" => ToolTipIcon.Error,
                "SUCCESS" => ToolTipIcon.Info, // Success uses Info icon
                _ => ToolTipIcon.Info
            };

            _notifyIcon.BalloonTipIcon = toolTipIcon;
            _notifyIcon.BalloonTipTitle = title;
            _notifyIcon.BalloonTipText = message;
            _notifyIcon.ShowBalloonTip(timeout);

            Logger.Debug("Notification shown: {Title} - {Message}", title, message);
        }
        catch (Exception ex)
        {
            Logger.Error(ex, "Failed to show notification: {Title}", title);
        }
    }

    public void RefreshContextMenu()
    {
        if (_notifyIcon == null || _disposed)
            return;

        Logger.Debug("Refreshing context menu");
        BuildContextMenu();
    }

    public void Dispose()
    {
        if (!_disposed)
        {
            SystemEvents.UserPreferenceChanged -= SystemEvents_UserPreferenceChanged;
            
            if (_notifyIcon != null)
            {
                _notifyIcon.Visible = false;
                _notifyIcon.Dispose();
                _notifyIcon = null;
            }
            _disposed = true;
            Logger.Info("Tray icon manager disposed");
        }
    }
}

/// <summary>
/// Custom renderer that applies dark or light theme to ToolStrip menus
/// </summary>
internal class ThemeAwareToolStripRenderer : ToolStripProfessionalRenderer
{
    private readonly bool _isDarkMode;
    private readonly Color _backgroundColor;
    private readonly Color _foregroundColor;
    private readonly Color _highlightColor;
    private readonly Color _borderColor;

    public ThemeAwareToolStripRenderer(bool isDarkMode) : base(new ThemeAwareColorTable(isDarkMode))
    {
        _isDarkMode = isDarkMode;
        
        if (_isDarkMode)
        {
            _backgroundColor = Color.FromArgb(43, 43, 43);
            _foregroundColor = Color.FromArgb(241, 241, 241);
            _highlightColor = Color.FromArgb(62, 62, 64);
            _borderColor = Color.FromArgb(51, 51, 51);
        }
        else
        {
            _backgroundColor = Color.FromArgb(249, 249, 249);
            _foregroundColor = Color.FromArgb(0, 0, 0);
            _highlightColor = Color.FromArgb(229, 243, 255);
            _borderColor = Color.FromArgb(204, 204, 204);
        }
    }

    protected override void OnRenderItemText(ToolStripItemTextRenderEventArgs e)
    {
        e.TextColor = _foregroundColor;
        base.OnRenderItemText(e);
    }

    protected override void OnRenderToolStripBackground(ToolStripRenderEventArgs e)
    {
        using var brush = new SolidBrush(_backgroundColor);
        e.Graphics.FillRectangle(brush, e.AffectedBounds);
    }

    protected override void OnRenderToolStripBorder(ToolStripRenderEventArgs e)
    {
        using var pen = new Pen(_borderColor);
        var rect = new Rectangle(0, 0, e.ToolStrip.Width - 1, e.ToolStrip.Height - 1);
        e.Graphics.DrawRectangle(pen, rect);
    }

    protected override void OnRenderMenuItemBackground(ToolStripItemRenderEventArgs e)
    {
        if (e.Item.Selected || e.Item.Pressed)
        {
            using var brush = new SolidBrush(_highlightColor);
            e.Graphics.FillRectangle(brush, new Rectangle(Point.Empty, e.Item.Size));
        }
        else
        {
            using var brush = new SolidBrush(_backgroundColor);
            e.Graphics.FillRectangle(brush, new Rectangle(Point.Empty, e.Item.Size));
        }
    }

    protected override void OnRenderSeparator(ToolStripSeparatorRenderEventArgs e)
    {
        var bounds = new Rectangle(Point.Empty, e.Item.Size);
        using var pen = new Pen(_borderColor);
        int y = bounds.Height / 2;
        e.Graphics.DrawLine(pen, bounds.Left + 4, y, bounds.Right - 4, y);
    }

    protected override void OnRenderArrow(ToolStripArrowRenderEventArgs e)
    {
        e.ArrowColor = _foregroundColor;
        base.OnRenderArrow(e);
    }
}

/// <summary>
/// Custom color table for theme-aware rendering
/// </summary>
internal class ThemeAwareColorTable : ProfessionalColorTable
{
    private readonly bool _isDarkMode;

    public ThemeAwareColorTable(bool isDarkMode)
    {
        _isDarkMode = isDarkMode;
        UseSystemColors = false;
    }

    public override Color MenuBorder => _isDarkMode ? Color.FromArgb(51, 51, 51) : Color.FromArgb(204, 204, 204);
    public override Color MenuItemBorder => _isDarkMode ? Color.FromArgb(62, 62, 64) : Color.FromArgb(229, 243, 255);
    public override Color MenuItemSelected => _isDarkMode ? Color.FromArgb(62, 62, 64) : Color.FromArgb(229, 243, 255);
    public override Color MenuItemSelectedGradientBegin => _isDarkMode ? Color.FromArgb(62, 62, 64) : Color.FromArgb(229, 243, 255);
    public override Color MenuItemSelectedGradientEnd => _isDarkMode ? Color.FromArgb(62, 62, 64) : Color.FromArgb(229, 243, 255);
    public override Color MenuStripGradientBegin => _isDarkMode ? Color.FromArgb(43, 43, 43) : Color.FromArgb(249, 249, 249);
    public override Color MenuStripGradientEnd => _isDarkMode ? Color.FromArgb(43, 43, 43) : Color.FromArgb(249, 249, 249);
    public override Color ToolStripDropDownBackground => _isDarkMode ? Color.FromArgb(43, 43, 43) : Color.FromArgb(249, 249, 249);
    public override Color ImageMarginGradientBegin => _isDarkMode ? Color.FromArgb(43, 43, 43) : Color.FromArgb(249, 249, 249);
    public override Color ImageMarginGradientMiddle => _isDarkMode ? Color.FromArgb(43, 43, 43) : Color.FromArgb(249, 249, 249);
    public override Color ImageMarginGradientEnd => _isDarkMode ? Color.FromArgb(43, 43, 43) : Color.FromArgb(249, 249, 249);
    public override Color SeparatorDark => _isDarkMode ? Color.FromArgb(51, 51, 51) : Color.FromArgb(204, 204, 204);
    public override Color SeparatorLight => _isDarkMode ? Color.FromArgb(62, 62, 64) : Color.FromArgb(255, 255, 255);
}
