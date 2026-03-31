using System.Diagnostics;
using System.Drawing;
using System.Runtime.InteropServices;
using System.Text.Json;
using FontAwesome.Sharp;
using Microsoft.Extensions.Configuration;

namespace ServerMonitorDashboard.Tray;

/// <summary>
/// Main application context for the Dashboard Tray icon
/// </summary>
public class DashboardTrayContext : ApplicationContext
{
    // ═══════════════════════════════════════════════════════════════════════════════
    // Hardcoded authorized users for Command feature (security requirement)
    // ═══════════════════════════════════════════════════════════════════════════════
    private static readonly HashSet<string> AuthorizedCommandUsers = new(StringComparer.OrdinalIgnoreCase)
    {
        "FKSVEERI",
        "FKGEISTA"
    };

    private static readonly string UserPrefsPath = Path.Combine(
        Environment.GetFolderPath(Environment.SpecialFolder.ApplicationData),
        "ServerMonitorDashboard.Tray",
        "user-prefs.json");

    // ═══════════════════════════════════════════════════════════════════════════════
    // Native methods for icon cleanup
    // ═══════════════════════════════════════════════════════════════════════════════
    [DllImport("user32.dll", CharSet = CharSet.Auto)]
    private static extern bool DestroyIcon(IntPtr handle);

    // ═══════════════════════════════════════════════════════════════════════════════
    // Fields
    // ═══════════════════════════════════════════════════════════════════════════════
    private readonly NotifyIcon _notifyIcon;
    private readonly System.Windows.Forms.Timer _alertPollTimer;
    private readonly DashboardTraySettings _settings;
    private readonly HttpClient _httpClient;
    private readonly JsonSerializerOptions _jsonOptions;

    private readonly System.Drawing.Icon _normalIcon;
    private readonly System.Drawing.Icon _alertIcon;

    private readonly HashSet<string> _seenAlertIds = new();
    private readonly Dictionary<string, DateTime> _serverLastPollTime = new();
    private List<ServerInfo>? _servers;
    private DateTime _lastServerListRefresh = DateTime.MinValue;

    private AlertInfo? _lastClickedAlert;
    private bool _isPolling;
    private bool _initialPollDone;

    // Current dashboard API server (user-configurable)
    private string _currentDashboardServer;

    // User-configurable filter settings
    private bool _productionOnly = true;
    private SeverityLevel _minimumSeverity = SeverityLevel.Warning;
    private bool _notificationsEnabled = true;

    // Menu items for dynamic updates
    private ToolStripMenuItem? _productionOnlyMenuItem;
    private ToolStripMenuItem? _allEnvironmentsMenuItem;
    private ToolStripMenuItem? _severityCriticalMenuItem;
    private ToolStripMenuItem? _severityErrorMenuItem;
    private ToolStripMenuItem? _severityWarningMenuItem;
    private ToolStripMenuItem? _severityInfoMenuItem;
    private ToolStripMenuItem? _notificationsMenuItem;
    private ToolStripMenuItem? _autoStartMenuItem;
    private ToolStripMenuItem? _serverLabelMenuItem;

    // ═══════════════════════════════════════════════════════════════════════════════
    // Constructor
    // ═══════════════════════════════════════════════════════════════════════════════
    public DashboardTrayContext()
    {
        // Load configuration
        var config = new ConfigurationBuilder()
            .SetBasePath(AppContext.BaseDirectory)
            .AddJsonFile("appsettings.json", optional: false)
            .Build();

        _settings = config.GetSection("DashboardTraySettings").Get<DashboardTraySettings>()
            ?? new DashboardTraySettings();

        // Load user prefs (saved server choice); fall back to appsettings default
        var prefs = LoadUserPrefs();
        _currentDashboardServer = prefs?.DashboardApiServer
            ?? _settings.DefaultDashboardServer;

        _httpClient = new HttpClient { Timeout = TimeSpan.FromSeconds(10) };
        _jsonOptions = new JsonSerializerOptions { PropertyNameCaseInsensitive = true };

        // Create icons
        _normalIcon = CreateIcon(IconChar.ChartLine, Color.FromArgb(0, 137, 66), 32);
        _alertIcon  = CreateIcon(IconChar.ExclamationTriangle, Color.FromArgb(239, 68, 68), 32);

        // ── Build context menu ───────────────────────────────────────────────────
        var contextMenu = new ContextMenuStrip();
        contextMenu.RenderMode = ToolStripRenderMode.System;

        contextMenu.Items.Add("Open Dashboard", null, (s, e) => OpenDashboard());

        if (IsUserAuthorizedForCommand())
            contextMenu.Items.Add("⚡ Script Runner", null, (s, e) => OpenScriptRunner());

        contextMenu.Items.Add("-");

        // Environment filter submenu
        var envMenu = new ToolStripMenuItem("Environment Filter");
        _productionOnlyMenuItem = new ToolStripMenuItem("Production Only", null, (s, e) => SetEnvironmentFilter(true))
        {
            Checked = _productionOnly,
            CheckOnClick = false
        };
        _allEnvironmentsMenuItem = new ToolStripMenuItem("All Environments", null, (s, e) => SetEnvironmentFilter(false))
        {
            Checked = !_productionOnly,
            CheckOnClick = false
        };
        envMenu.DropDownItems.Add(_productionOnlyMenuItem);
        envMenu.DropDownItems.Add(_allEnvironmentsMenuItem);
        contextMenu.Items.Add(envMenu);

        // Minimum severity submenu
        var severityMenu = new ToolStripMenuItem("Minimum Severity");
        _severityCriticalMenuItem = new ToolStripMenuItem("Critical", null, (s, e) => SetMinimumSeverity(SeverityLevel.Critical))
            { Checked = _minimumSeverity == SeverityLevel.Critical, CheckOnClick = false };
        _severityErrorMenuItem = new ToolStripMenuItem("Error", null, (s, e) => SetMinimumSeverity(SeverityLevel.Error))
            { Checked = _minimumSeverity == SeverityLevel.Error, CheckOnClick = false };
        _severityWarningMenuItem = new ToolStripMenuItem("Warning", null, (s, e) => SetMinimumSeverity(SeverityLevel.Warning))
            { Checked = _minimumSeverity == SeverityLevel.Warning, CheckOnClick = false };
        _severityInfoMenuItem = new ToolStripMenuItem("Info (All)", null, (s, e) => SetMinimumSeverity(SeverityLevel.Info))
            { Checked = _minimumSeverity == SeverityLevel.Info, CheckOnClick = false };
        severityMenu.DropDownItems.Add(_severityCriticalMenuItem);
        severityMenu.DropDownItems.Add(_severityErrorMenuItem);
        severityMenu.DropDownItems.Add(_severityWarningMenuItem);
        severityMenu.DropDownItems.Add(_severityInfoMenuItem);
        contextMenu.Items.Add(severityMenu);

        contextMenu.Items.Add("-");

        // Notifications toggle
        _notificationsMenuItem = new ToolStripMenuItem("🔔 Notifications Enabled", null, (s, e) => ToggleNotifications())
        {
            Checked = _notificationsEnabled,
            CheckOnClick = false
        };
        contextMenu.Items.Add(_notificationsMenuItem);

        _autoStartMenuItem = new ToolStripMenuItem("🚀 Start with Windows", null, (s, e) => ToggleAutoStart())
        {
            Checked = Program.IsAutoStartEnabled(),
            CheckOnClick = false
        };
        contextMenu.Items.Add(_autoStartMenuItem);

        contextMenu.Items.Add("-");

        // Dashboard Server submenu
        var serverMenu = BuildServerMenu();
        contextMenu.Items.Add(serverMenu);

        contextMenu.Items.Add("-");

        contextMenu.Items.Add("Refresh Servers", null, async (s, e) => await RefreshServerListAsync());
        contextMenu.Items.Add("⚙️ Edit Dashboard Settings", null, (s, e) => OpenDashboardSettings());
        contextMenu.Items.Add("-");
        contextMenu.Items.Add("⬆️ Update Dashboard Tray", null, (s, e) => UpdateTrayApp());
        contextMenu.Items.Add("-");
        contextMenu.Items.Add("Exit", null, (s, e) => ExitApplication());

        // Create notify icon
        _notifyIcon = new NotifyIcon
        {
            Icon    = _normalIcon,
            Visible = true,
            Text    = $"ServerMonitor Dashboard ({_currentDashboardServer})",
            ContextMenuStrip = contextMenu
        };

        _notifyIcon.DoubleClick         += (s, e) => OpenDashboard();
        _notifyIcon.BalloonTipClicked   += NotifyIcon_BalloonTipClicked;

        // Start alert polling timer
        _alertPollTimer = new System.Windows.Forms.Timer
        {
            Interval = _settings.AlertPollIntervalMs
        };
        _alertPollTimer.Tick += async (s, e) => await PollForAlertsAsync();

        if (_settings.EnableAlertNotifications)
        {
            Task.Run(async () =>
            {
                await Task.Delay(5000);
                await RefreshServerListAsync();
                await PollForAlertsAsync();
            });
            _alertPollTimer.Start();
        }

    }

    // ═══════════════════════════════════════════════════════════════════════════════
    // URL helpers
    // ═══════════════════════════════════════════════════════════════════════════════

    private string GetDashboardUrl()
        => $"http://{_currentDashboardServer}{_settings.DashboardVirtualPath}";

    // ═══════════════════════════════════════════════════════════════════════════════
    // Icon Creation
    // ═══════════════════════════════════════════════════════════════════════════════

    private static System.Drawing.Icon CreateIcon(IconChar iconChar, Color foreColor, int size)
    {
        using var bitmap = iconChar.ToBitmap(foreColor, size);
        IntPtr hIcon = bitmap.GetHicon();
        return System.Drawing.Icon.FromHandle(hIcon);
    }

    // ═══════════════════════════════════════════════════════════════════════════════
    // Tray App Self-Update (via MSI from staging share)
    // ═══════════════════════════════════════════════════════════════════════════════

    /// <summary>
    /// Launches the latest Dashboard Tray MSI from the staging share.
    /// The MSI handles killing the old process (util:CloseApplication),
    /// installing files, and restarting the tray app.
    /// </summary>
    private void UpdateTrayApp()
    {
        try
        {
            var stagingPath = _settings.TrayMsiStagingPath;
            var msiPath     = Path.Combine(stagingPath, "ServerMonitorDashboard.Tray.Setup.msi");

            if (!File.Exists(msiPath))
            {
                _notifyIcon.ShowBalloonTip(5000, "Update Failed",
                    $"MSI not found at:\n{msiPath}", ToolTipIcon.Error);
                return;
            }

            _notifyIcon.ShowBalloonTip(3000, "Updating Dashboard Tray",
                "Installing latest version... The tray app will restart.", ToolTipIcon.Info);

            var psi = new ProcessStartInfo("msiexec.exe",
                $"/i \"{msiPath}\" /qb /l*v \"{Path.GetTempPath()}ServerMonitorDashboard.Tray.Install.log\"")
            {
                UseShellExecute = true,
                CreateNoWindow  = false
            };

            Process.Start(psi);
        }
        catch (Exception ex)
        {
            Debug.WriteLine($"Tray update failed: {ex.Message}");
            _notifyIcon.ShowBalloonTip(5000, "Update Error",
                $"Failed to start update: {ex.Message}", ToolTipIcon.Error);
        }
    }

    // ═══════════════════════════════════════════════════════════════════════════════
    // Dashboard Server Config
    // ═══════════════════════════════════════════════════════════════════════════════

    private ToolStripMenuItem BuildServerMenu()
    {
        var serverMenu = new ToolStripMenuItem($"Dashboard Server: {_currentDashboardServer}");

        _serverLabelMenuItem = new ToolStripMenuItem(_currentDashboardServer)
        {
            Enabled = false
        };

        var changeItem = new ToolStripMenuItem("Change Server...", null, (s, e) => ChangeDashboardServer());

        serverMenu.DropDownItems.Add(_serverLabelMenuItem);
        serverMenu.DropDownItems.Add("-");
        serverMenu.DropDownItems.Add(changeItem);

        return serverMenu;
    }

    private void ChangeDashboardServer()
    {
        using var form    = new Form();
        form.Text         = "Change Dashboard Server";
        form.Size         = new Size(380, 140);
        form.StartPosition = FormStartPosition.CenterScreen;
        form.FormBorderStyle = FormBorderStyle.FixedDialog;
        form.MaximizeBox  = false;
        form.MinimizeBox  = false;

        var label = new Label
        {
            Text     = "Server name or hostname:",
            Location = new Point(12, 14),
            AutoSize = true
        };

        var textBox = new TextBox
        {
            Text     = _currentDashboardServer,
            Location = new Point(12, 34),
            Width    = 340,
            Font     = new Font("Segoe UI", 10)
        };

        var btnOk = new Button
        {
            Text         = "OK",
            DialogResult = DialogResult.OK,
            Location     = new Point(196, 68),
            Width        = 75
        };

        var btnCancel = new Button
        {
            Text         = "Cancel",
            DialogResult = DialogResult.Cancel,
            Location     = new Point(277, 68),
            Width        = 75
        };

        form.Controls.AddRange(new Control[] { label, textBox, btnOk, btnCancel });
        form.AcceptButton = btnOk;
        form.CancelButton = btnCancel;

        if (form.ShowDialog() != DialogResult.OK) return;

        var newServer = textBox.Text.Trim();
        if (string.IsNullOrWhiteSpace(newServer) || newServer == _currentDashboardServer) return;

        _currentDashboardServer = newServer;

        // Persist to user-prefs.json
        SaveUserPrefs(new UserPrefs { DashboardApiServer = newServer });

        // Update tray tooltip and server menu label
        _notifyIcon.Text = $"ServerMonitor Dashboard ({_currentDashboardServer})";

        if (_serverLabelMenuItem != null)
            _serverLabelMenuItem.Text = _currentDashboardServer;

        // Update parent menu text (the ToolStripMenuItem that holds the submenu)
        if (_serverLabelMenuItem?.OwnerItem is ToolStripMenuItem parentItem)
            parentItem.Text = $"Dashboard Server: {_currentDashboardServer}";

        _notifyIcon.ShowBalloonTip(3000, "Server Changed",
            $"Dashboard API server: {_currentDashboardServer}", ToolTipIcon.Info);
    }

    // ═══════════════════════════════════════════════════════════════════════════════
    // User Preferences (persisted)
    // ═══════════════════════════════════════════════════════════════════════════════

    private static UserPrefs? LoadUserPrefs()
    {
        try
        {
            if (!File.Exists(UserPrefsPath)) return null;
            var json = File.ReadAllText(UserPrefsPath);
            return JsonSerializer.Deserialize<UserPrefs>(json);
        }
        catch (Exception ex)
        {
            Debug.WriteLine($"Failed to load user prefs: {ex.Message}");
            return null;
        }
    }

    private static void SaveUserPrefs(UserPrefs prefs)
    {
        try
        {
            Directory.CreateDirectory(Path.GetDirectoryName(UserPrefsPath)!);
            var json = JsonSerializer.Serialize(prefs, new JsonSerializerOptions { WriteIndented = true });
            File.WriteAllText(UserPrefsPath, json);
        }
        catch (Exception ex)
        {
            Debug.WriteLine($"Failed to save user prefs: {ex.Message}");
        }
    }

    // ═══════════════════════════════════════════════════════════════════════════════
    // Dashboard Operations
    // ═══════════════════════════════════════════════════════════════════════════════

    private void OpenDashboard(string? serverName = null, string? alertId = null)
    {
        try
        {
            string url;
            var baseUrl = GetDashboardUrl().TrimEnd('/');

            if (!string.IsNullOrEmpty(serverName) && !string.IsNullOrEmpty(alertId))
            {
                url = $"{baseUrl}/alert-view.html?server={Uri.EscapeDataString(serverName)}&alertId={Uri.EscapeDataString(alertId)}";
            }
            else if (!string.IsNullOrEmpty(serverName))
            {
                url = $"{baseUrl}?server={Uri.EscapeDataString(serverName)}";
            }
            else
            {
                url = baseUrl;
            }

            Process.Start(new ProcessStartInfo { FileName = url, UseShellExecute = true });
        }
        catch (Exception ex)
        {
            Debug.WriteLine($"Error opening dashboard: {ex.Message}");
            _notifyIcon.ShowBalloonTip(3000, "Error",
                $"Failed to open dashboard: {ex.Message}", ToolTipIcon.Error);
        }
    }

    /// <summary>
    /// Opens the Dashboard service's appsettings.json in Notepad.
    /// The Dashboard service uses FileSystemWatcher to auto-reload settings when the file changes.
    /// </summary>
    private void OpenDashboardSettings()
    {
        try
        {
            var optPath      = Environment.GetEnvironmentVariable("OptPath") ?? @"C:\opt";
            var settingsPath = Path.Combine(optPath, "DedgeWinApps", "ServerMonitorDashboard", "appsettings.json");

            if (!File.Exists(settingsPath))
            {
                _notifyIcon.ShowBalloonTip(3000, "File Not Found",
                    $"Settings file not found:\n{settingsPath}", ToolTipIcon.Warning);
                return;
            }

            Process.Start(new ProcessStartInfo
            {
                FileName        = "notepad.exe",
                Arguments       = $"\"{settingsPath}\"",
                UseShellExecute = true
            });

            _notifyIcon.ShowBalloonTip(2000, "Settings Opened",
                "Dashboard will auto-reload settings when you save the file.", ToolTipIcon.Info);
        }
        catch (Exception ex)
        {
            Debug.WriteLine($"Error opening settings: {ex.Message}");
            _notifyIcon.ShowBalloonTip(3000, "Error",
                $"Failed to open settings: {ex.Message}", ToolTipIcon.Error);
        }
    }

    private void OpenScriptRunner()
    {
        try
        {
            var url = $"{GetDashboardUrl().TrimEnd('/')}/script-runner.html?user={Uri.EscapeDataString(Environment.UserName)}";
            Process.Start(new ProcessStartInfo { FileName = url, UseShellExecute = true });
        }
        catch (Exception ex)
        {
            Debug.WriteLine($"Error opening Script Runner: {ex.Message}");
            _notifyIcon.ShowBalloonTip(3000, "Error",
                $"Failed to open Script Runner: {ex.Message}", ToolTipIcon.Error);
        }
    }

    private static bool IsUserAuthorizedForCommand()
        => AuthorizedCommandUsers.Contains(Environment.UserName);

    // ═══════════════════════════════════════════════════════════════════════════════
    // Server List Management
    // ═══════════════════════════════════════════════════════════════════════════════

    private async Task RefreshServerListAsync()
    {
        try
        {
            if (!File.Exists(_settings.ComputerInfoPath))
            {
                Debug.WriteLine($"ComputerInfo.json not found at {_settings.ComputerInfoPath}");
                return;
            }

            var json        = await File.ReadAllTextAsync(_settings.ComputerInfoPath);
            var allComputers = JsonSerializer.Deserialize<List<ComputerInfo>>(json, _jsonOptions)
                               ?? new List<ComputerInfo>();

            _servers = allComputers
                .Where(c => c.Type?.Contains("Server", StringComparison.OrdinalIgnoreCase) == true)
                .Where(c => !string.IsNullOrEmpty(c.Name))
                .Where(c => c.IsActive)
                .Select(c => new ServerInfo { Name = c.Name!, Environment = c.Environment, IsOnline = false })
                .ToList();

            _lastServerListRefresh = DateTime.UtcNow;
            Debug.WriteLine($"Loaded {_servers.Count} servers from ComputerInfo.json");
        }
        catch (Exception ex)
        {
            Debug.WriteLine($"Error loading server list: {ex.Message}");
        }
    }

    // ═══════════════════════════════════════════════════════════════════════════════
    // Alert Polling
    // ═══════════════════════════════════════════════════════════════════════════════

    private async Task PollForAlertsAsync()
    {
        if (_isPolling) return;
        _isPolling = true;

        try
        {
            if ((DateTime.UtcNow - _lastServerListRefresh).TotalMinutes > 5 || _servers == null)
                await RefreshServerListAsync();

            if (_servers == null || _servers.Count == 0) return;

            var isFirstPoll = !_initialPollDone;
            var newAlerts = new List<AlertInfo>();

            foreach (var server in _servers)
            {
                try
                {
                    var alerts = await GetRecentAlertsAsync(server.Name);
                    if (alerts != null && alerts.Count > 0)
                    {
                        foreach (var alert in alerts)
                        {
                            var alertId = $"{server.Name}_{alert.Timestamp:yyyyMMddHHmmss}_{alert.Category}_{alert.Message?.GetHashCode()}";

                            if (!_seenAlertIds.Contains(alertId))
                            {
                                _seenAlertIds.Add(alertId);

                                if (isFirstPoll)
                                    continue;

                                alert.ServerName = server.Name;
                                alert.Id         = alertId;

                                if (ShouldShowAlert(alert, server))
                                    newAlerts.Add(alert);
                            }
                        }
                        server.IsOnline = true;
                    }
                }
                catch
                {
                    server.IsOnline = false;
                }
            }

            _initialPollDone = true;

            while (_seenAlertIds.Count > _settings.MaxSeenAlertIds)
                _seenAlertIds.Remove(_seenAlertIds.First());

            foreach (var alert in newAlerts.OrderByDescending(a => a.Timestamp).Take(3))
            {
                ShowAlertBalloon(alert);
                await Task.Delay(500);
            }

            if (newAlerts.Count > 0)
            {
                _notifyIcon.Icon = _alertIcon;
                _ = Task.Run(async () =>
                {
                    await Task.Delay(30000);
                    _notifyIcon.Icon = _normalIcon;
                });
            }
        }
        catch (Exception ex)
        {
            Debug.WriteLine($"Error polling for alerts: {ex.Message}");
        }
        finally
        {
            _isPolling = false;
        }
    }

    private async Task<List<AlertInfo>?> GetRecentAlertsAsync(string serverName)
    {
        try
        {
            if (!_serverLastPollTime.TryGetValue(serverName, out var lastPoll))
                lastPoll = DateTime.UtcNow.AddMinutes(-5);

            var url = $"http://{serverName}:{_settings.ServerMonitorAgentPort}/api/snapshot/alerts/recent";
            url    += $"?since={lastPoll:o}&count=50";

            var response = await _httpClient.GetAsync(url);
            if (!response.IsSuccessStatusCode)
            {
                Debug.WriteLine($"Alert poll failed for {serverName}: HTTP {(int)response.StatusCode}");
                return null;
            }

            _serverLastPollTime[serverName] = DateTime.UtcNow;

            var json = await response.Content.ReadAsStringAsync();
            var alerts = JsonSerializer.Deserialize<List<AlertInfo>>(json, _jsonOptions);
            Debug.WriteLine($"Alert poll {serverName}: {alerts?.Count ?? 0} alerts returned");
            return alerts;
        }
        catch (Exception ex)
        {
            Debug.WriteLine($"Alert poll exception for {serverName}: {ex.Message}");
            return null;
        }
    }

    private void ShowAlertBalloon(AlertInfo alert)
    {
        if (!_notificationsEnabled)
        {
            Debug.WriteLine($"Notification skipped (disabled): [{alert.ServerName}] {alert.Category}");
            return;
        }

        _lastClickedAlert = alert;

        var icon = alert.Severity?.ToLower() switch
        {
            "critical" or "error" => ToolTipIcon.Error,
            "warning"             => ToolTipIcon.Warning,
            _                     => ToolTipIcon.Info
        };

        var title   = $"[{alert.ServerName}] {alert.Severity ?? "Alert"}";
        var message = $"{alert.Category}: {alert.Message}";

        if (message.Length > 200)
            message = message.Substring(0, 197) + "...";

        _notifyIcon.ShowBalloonTip(_settings.BalloonDisplayTimeMs, title, message, icon);
    }

    private void NotifyIcon_BalloonTipClicked(object? sender, EventArgs e)
    {
        if (_lastClickedAlert != null)
            OpenDashboard(_lastClickedAlert.ServerName, _lastClickedAlert.Id);
        else
            OpenDashboard();
    }

    // ═══════════════════════════════════════════════════════════════════════════════
    // Filter Settings
    // ═══════════════════════════════════════════════════════════════════════════════

    private void SetEnvironmentFilter(bool productionOnly)
    {
        _productionOnly = productionOnly;
        if (_productionOnlyMenuItem  != null) _productionOnlyMenuItem.Checked  = productionOnly;
        if (_allEnvironmentsMenuItem != null) _allEnvironmentsMenuItem.Checked = !productionOnly;

        if (_notificationsEnabled)
            _notifyIcon.ShowBalloonTip(2000, "Filter Updated",
                $"Environment filter: {(productionOnly ? "Production only" : "All environments")}",
                ToolTipIcon.Info);
    }

    private void SetMinimumSeverity(SeverityLevel level)
    {
        _minimumSeverity = level;
        if (_severityCriticalMenuItem != null) _severityCriticalMenuItem.Checked = level == SeverityLevel.Critical;
        if (_severityErrorMenuItem    != null) _severityErrorMenuItem.Checked    = level == SeverityLevel.Error;
        if (_severityWarningMenuItem  != null) _severityWarningMenuItem.Checked  = level == SeverityLevel.Warning;
        if (_severityInfoMenuItem     != null) _severityInfoMenuItem.Checked     = level == SeverityLevel.Info;

        if (_notificationsEnabled)
            _notifyIcon.ShowBalloonTip(2000, "Filter Updated",
                $"Minimum severity: {level}", ToolTipIcon.Info);
    }

    private void ToggleNotifications()
    {
        _notificationsEnabled = !_notificationsEnabled;
        if (_notificationsMenuItem != null)
        {
            _notificationsMenuItem.Checked = _notificationsEnabled;
            _notificationsMenuItem.Text    = _notificationsEnabled
                ? "🔔 Notifications Enabled"
                : "🔕 Notifications Disabled";
        }
        _notifyIcon.ShowBalloonTip(2000, "Notifications",
            $"Balloon notifications are now {(_notificationsEnabled ? "enabled" : "disabled")}",
            ToolTipIcon.Info);
    }

    private void ToggleAutoStart()
    {
        var isEnabled = Program.IsAutoStartEnabled();
        if (isEnabled)
            Program.RemoveAutoStart();
        else
            EnsureAutoStartFromContext();

        var newState = Program.IsAutoStartEnabled();
        if (_autoStartMenuItem != null)
            _autoStartMenuItem.Checked = newState;

        _notifyIcon.ShowBalloonTip(2000, "Start with Windows",
            newState ? "Will start automatically on login" : "Auto-start disabled",
            ToolTipIcon.Info);
    }

    private static void EnsureAutoStartFromContext()
    {
        try
        {
            var exePath = Environment.ProcessPath ?? Application.ExecutablePath;
            using var key = Microsoft.Win32.Registry.CurrentUser.OpenSubKey(
                @"SOFTWARE\Microsoft\Windows\CurrentVersion\Run", writable: true)
                ?? Microsoft.Win32.Registry.CurrentUser.CreateSubKey(
                    @"SOFTWARE\Microsoft\Windows\CurrentVersion\Run");
            key.SetValue("ServerMonitorDashboard.Tray", exePath);
        }
        catch (Exception ex)
        {
            Debug.WriteLine($"Auto-start enable failed: {ex.Message}");
        }
    }

    private bool ShouldShowAlert(AlertInfo alert, ServerInfo server)
    {
        if (_productionOnly && server.Environment != null)
        {
            if (!server.Environment.Contains("prod", StringComparison.OrdinalIgnoreCase) &&
                !server.Environment.Contains("production", StringComparison.OrdinalIgnoreCase))
                return false;
        }

        var alertSeverity = ParseSeverity(alert.Severity);
        return alertSeverity >= _minimumSeverity;
    }

    private static SeverityLevel ParseSeverity(string? severity) =>
        severity?.ToLower() switch
        {
            "critical"    => SeverityLevel.Critical,
            "error"       => SeverityLevel.Error,
            "warning"     => SeverityLevel.Warning,
            "info" or "information" => SeverityLevel.Info,
            _ => SeverityLevel.Info
        };

    // ═══════════════════════════════════════════════════════════════════════════════
    // Cleanup
    // ═══════════════════════════════════════════════════════════════════════════════

    private void ExitApplication()
    {
        _alertPollTimer.Stop();
        _notifyIcon.Visible = false;
        Application.Exit();
    }

    protected override void Dispose(bool disposing)
    {
        if (disposing)
        {
            _alertPollTimer?.Dispose();
            _notifyIcon?.Dispose();
            _httpClient?.Dispose();

            if (_normalIcon != null)
            {
                DestroyIcon(_normalIcon.Handle);
                _normalIcon.Dispose();
            }
            if (_alertIcon != null)
            {
                DestroyIcon(_alertIcon.Handle);
                _alertIcon.Dispose();
            }
        }
        base.Dispose(disposing);
    }
}

// ═══════════════════════════════════════════════════════════════════════════════
// Models
// ═══════════════════════════════════════════════════════════════════════════════

public class DashboardTraySettings
{
    public string DefaultDashboardServer { get; set; } = "dedge-server";
    public string DashboardVirtualPath   { get; set; } = "/ServerMonitorDashboard";
    public string ComputerInfoPath       { get; set; } = @"C:\opt\src\DedgeSrc\DedgeSystemTools\Folders\DedgeCommon\Configfiles\ComputerInfo.json";
    public string TrayMsiStagingPath     { get; set; } = @"C:\opt\src\DedgeSrc\DedgeSystemTools\Folders\DedgeCommon\Software\DedgeWinApps\ServerMonitorDashboard.Tray";
    public int    ServerMonitorAgentPort { get; set; } = 8999;
    public int    AlertPollIntervalMs    { get; set; } = 30000;
    public bool   EnableAlertNotifications { get; set; } = true;
    public int    BalloonDisplayTimeMs   { get; set; } = 5000;
    public int    MaxSeenAlertIds        { get; set; } = 1000;
}

public class UserPrefs
{
    public string DashboardApiServer { get; set; } = "dedge-server";
}

public class ComputerInfo
{
    public string? Name        { get; set; }
    public string? Type        { get; set; }
    public string? Environment { get; set; }
    public bool    IsActive    { get; set; }
}

public class ServerInfo
{
    public string  Name        { get; set; } = "";
    public string? Environment { get; set; }
    public bool    IsOnline    { get; set; }
}

public class AlertInfo
{
    public string?   Id         { get; set; }
    public string?   ServerName { get; set; }
    public string?   Severity   { get; set; }
    public string?   Category   { get; set; }
    public string?   Message    { get; set; }
    public DateTime  Timestamp  { get; set; }
}

/// <summary>
/// Severity levels ordered from lowest to highest priority
/// </summary>
public enum SeverityLevel
{
    Info     = 0,
    Warning  = 1,
    Error    = 2,
    Critical = 3
}
