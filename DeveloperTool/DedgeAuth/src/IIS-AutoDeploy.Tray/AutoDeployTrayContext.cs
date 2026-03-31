using System.Diagnostics;
using System.Drawing;
using System.Runtime.InteropServices;
using System.Text.Json;
using FontAwesome.Sharp;
using System.Reflection;
using Microsoft.Extensions.Configuration;

namespace IIS_AutoDeploy.Tray;

/// <summary>
/// Main application context for the IIS Auto-Deploy tray icon.
/// Monitors DedgeWinApps (staging) and deploy templates for changes, triggers IIS-DeployApp when updates are detected.
/// </summary>
public class AutoDeployTrayContext : ApplicationContext
{
    private const string DeployMutexName = "Global\\IIS-AutoDeploy-DeployMutex";
    private const int MutexTimeoutMs = 5000;

    [DllImport("user32.dll", CharSet = CharSet.Auto)]
    private static extern bool DestroyIcon(IntPtr handle);

    private readonly NotifyIcon _notifyIcon;
    private readonly System.Windows.Forms.Timer _pollTimer;
    private readonly AutoDeploySettings _settings;
    private readonly JsonSerializerOptions _jsonOptions;

    private readonly System.Drawing.Icon _normalIcon;
    private readonly System.Drawing.Icon _deployingIcon;

    private const int StabilitySeconds = 240;

    private readonly Form _hiddenForm;
    private string _stateFolder = "";
    private string _logFolder = "";
    private string _DedgeWinAppsPath = "";
    private string _templatesPath = "";
    private string _deployScriptPath = "";
    private Dictionary<string, string> _installAppNameToSiteName = new();
    private List<string> _allSiteNames = new();
    private ToolStripMenuItem _reinstallMenu = null!;
    private ToolStripMenuItem _updateMenuItem = null!;
    private bool _surveillancePaused;
    private bool _isPolling;
    private DateTime _lastUpdateCheck = DateTime.MinValue;
    private static readonly TimeSpan UpdateCheckInterval = TimeSpan.FromMinutes(5);

    /// <summary>
    /// Tracks each DedgeWinApps subfolder that contains matching DLLs.
    /// Deploy only fires once the folder has been stable (unchanged) for StabilitySeconds.
    /// </summary>
    private readonly Dictionary<string, FolderSnapshot> _folderSnapshots = new(StringComparer.OrdinalIgnoreCase);

    public AutoDeployTrayContext()
    {
        var config = new ConfigurationBuilder()
            .SetBasePath(AppContext.BaseDirectory)
            .AddJsonFile("appsettings.json", optional: false)
            .Build();

        _settings = config.GetSection("IIS-AutoDeploy").Get<AutoDeploySettings>()
            ?? new AutoDeploySettings();

        var optPath = Environment.GetEnvironmentVariable("OptPath") ?? @"C:\opt";

        _stateFolder = !string.IsNullOrWhiteSpace(_settings.StateFolder)
            ? _settings.StateFolder
            : Path.Combine(optPath, "data", "IIS-AutoDeploy");

        var logFolder = !string.IsNullOrWhiteSpace(_settings.LogFolder)
            ? _settings.LogFolder
            : @"data\IIS-AutoDeploy.Tray";
        _logFolder = Path.Combine(optPath, logFolder);

        _DedgeWinAppsPath = !string.IsNullOrWhiteSpace(_settings.DedgeWinAppsPath)
            ? _settings.DedgeWinAppsPath
            : @"C:\opt\src\DedgeSrc\DedgeSystemTools\Folders\DedgeCommon\Software\DedgeWinApps";

        _templatesPath = !string.IsNullOrWhiteSpace(_settings.TemplatesPath)
            ? _settings.TemplatesPath
            : Path.Combine(optPath, "DedgePshApps", "IIS-DeployApp", "templates");

        _deployScriptPath = !string.IsNullOrWhiteSpace(_settings.IISDeployAppScriptPath)
            ? _settings.IISDeployAppScriptPath
            : Path.Combine(optPath, "DedgePshApps", "IIS-DeployApp", "IIS-DeployApp.ps1");

        _jsonOptions = new JsonSerializerOptions { PropertyNameCaseInsensitive = true, WriteIndented = true };

        _normalIcon = CreateIcon(IconChar.Server, Color.FromArgb(0, 137, 66), 32);
        _deployingIcon = CreateIcon(IconChar.Sync, Color.FromArgb(59, 130, 246), 32);

        var contextMenu = new ContextMenuStrip();
        contextMenu.RenderMode = ToolStripRenderMode.System;

        contextMenu.Items.Add("Open IIS-DeployApp Folder", null, (s, e) => OpenIISDeployAppFolder());
        contextMenu.Items.Add("Edit Settings", null, (s, e) => OpenSettings());

        _updateMenuItem = new ToolStripMenuItem("Checking for updates...") { Enabled = false };
        _updateMenuItem.Click += (s, e) => _ = Task.Run(LaunchSelfUpdate);
        contextMenu.Items.Add(_updateMenuItem);
        contextMenu.Items.Add("-");
        _reinstallMenu = new ToolStripMenuItem("Reinstall App...");
        _reinstallMenu.DropDownItems.Add("(loading...)");
        contextMenu.Items.Add(_reinstallMenu);
        contextMenu.Items.Add("-");
        contextMenu.Items.Add("Pause Surveillance", null, (s, e) => TogglePause());
        contextMenu.Items.Add("-");
        contextMenu.Items.Add("Exit", null, (s, e) => ExitApplication());

        _notifyIcon = new NotifyIcon
        {
            Icon = _normalIcon,
            Visible = true,
            Text = $"IIS Auto-Deploy Tray v{GetRunningVersion()}"
        };

        _notifyIcon.ContextMenuStrip = contextMenu;

        _hiddenForm = new Form { ShowInTaskbar = false, WindowState = FormWindowState.Minimized };
        _ = _hiddenForm.Handle; // Create handle for Invoke without showing

        _pollTimer = new System.Windows.Forms.Timer
        {
            Interval = _settings.PollIntervalSeconds * 1000
        };
        _pollTimer.Tick += async (s, e) => await PollAsync();

        Directory.CreateDirectory(_stateFolder);
        Directory.CreateDirectory(_logFolder);

        _ = Task.Run(async () =>
        {
            await Task.Delay(2000);
            ShowStartupDiagnostics();
            await RefreshInstallAppNameMapAsync();
            RefreshUpdateMenuState();
            await PollAsync();
        });

        _pollTimer.Start();
    }

    private void ShowStartupDiagnostics()
    {
        var issues = new List<string>();

        if (!Directory.Exists(_DedgeWinAppsPath))
            issues.Add($"DedgeWinApps not found: {_DedgeWinAppsPath}");
        if (!Directory.Exists(_templatesPath))
            issues.Add($"Templates not found: {_templatesPath}");
        if (!File.Exists(_deployScriptPath))
            issues.Add($"Deploy script not found: {_deployScriptPath}");

        _hiddenForm.Invoke(() =>
        {
            if (issues.Count > 0)
            {
                _notifyIcon.ShowBalloonTip(10000, "IIS Auto-Deploy: Config Error",
                    string.Join("\n", issues), ToolTipIcon.Error);
            }
            else
            {
                var templateCount = 0;
                try { templateCount = Directory.GetFiles(_templatesPath, "*.deploy.json").Length; } catch { }
                _notifyIcon.ShowBalloonTip(5000, "IIS Auto-Deploy Started",
                    $"Monitoring {templateCount} templates\nPoll: {_settings.PollIntervalSeconds}s | Pattern: {_settings.FilePattern}",
                    ToolTipIcon.Info);
            }
        });
    }

    private static System.Drawing.Icon CreateIcon(IconChar iconChar, Color foreColor, int size)
    {
        using var bitmap = iconChar.ToBitmap(foreColor, size);
        IntPtr hIcon = bitmap.GetHicon();
        return System.Drawing.Icon.FromHandle(hIcon);
    }

    private async Task RefreshInstallAppNameMapAsync()
    {
        var map = new Dictionary<string, string>(StringComparer.OrdinalIgnoreCase);
        var siteNames = new List<string>();
        try
        {
            if (!Directory.Exists(_templatesPath)) return;

            foreach (var file in Directory.GetFiles(_templatesPath, "*.deploy.json"))
            {
                try
                {
                    var json = await File.ReadAllTextAsync(file);
                    var doc = JsonDocument.Parse(json);
                    var root = doc.RootElement;

                    if (!root.TryGetProperty("SiteName", out var siteNameEl)) continue;
                    var siteName = siteNameEl.GetString();
                    if (string.IsNullOrEmpty(siteName)) continue;
                    if (siteName.Equals("DefaultWebSite", StringComparison.OrdinalIgnoreCase)) continue;

                    siteNames.Add(siteName);

                    if (root.TryGetProperty("InstallAppName", out var installNameEl))
                    {
                        var installName = installNameEl.GetString();
                        if (!string.IsNullOrEmpty(installName))
                            map[installName] = siteName;
                    }
                }
                catch (Exception ex)
                {
                    WriteLog("WRN", $"Failed to parse template {file}: {ex.Message}");
                }
            }

            _installAppNameToSiteName = map;
            _allSiteNames = siteNames.OrderBy(s => s).ToList();
            _hiddenForm.Invoke(BuildReinstallMenu);
        }
        catch (Exception ex)
        {
            WriteLog("ERR", $"RefreshInstallAppNameMap failed: {ex.Message}");
        }
    }

    private void BuildReinstallMenu()
    {
        _reinstallMenu.DropDownItems.Clear();
        if (_allSiteNames.Count == 0)
        {
            _reinstallMenu.DropDownItems.Add("(no templates found)");
            return;
        }

        foreach (var siteName in _allSiteNames)
        {
            var item = new ToolStripMenuItem(siteName);
            var name = siteName;
            item.Click += (s, e) => _ = Task.Run(() => ManualReinstallApp(name));
            _reinstallMenu.DropDownItems.Add(item);
        }
    }

    private void ManualReinstallApp(string siteName)
    {
        _hiddenForm.Invoke(() =>
        {
            _notifyIcon.Icon = _deployingIcon;
            _notifyIcon.Text = $"Reinstalling {siteName}...";
            _notifyIcon.ShowBalloonTip(3000, "Reinstalling",
                $"Starting IIS-DeployApp for {siteName}...", ToolTipIcon.Info);
        });

        using var mutex = new Mutex(false, DeployMutexName);
        try
        {
            if (!mutex.WaitOne(MutexTimeoutMs))
            {
                _hiddenForm.Invoke(() =>
                    _notifyIcon.ShowBalloonTip(5000, "Reinstall Skipped",
                        $"Another deploy is in progress. Try again later.", ToolTipIcon.Warning));
                return;
            }

            var success = RunIISDeployApp(siteName);

            _hiddenForm.Invoke(() =>
            {
                _notifyIcon.Icon = _normalIcon;
                _notifyIcon.Text = $"IIS Auto-Deploy Tray v{GetRunningVersion()}";
                _notifyIcon.ShowBalloonTip(5000,
                    success ? $"{siteName} reinstalled" : $"{siteName} reinstall failed",
                    success ? "IIS-DeployApp completed successfully." : "Check logs for details.",
                    success ? ToolTipIcon.Info : ToolTipIcon.Error);
            });
        }
        finally
        {
            try { mutex.ReleaseMutex(); } catch { }
        }
    }

    private async Task PollAsync()
    {
        if (_isPolling || _surveillancePaused) return;
        _isPolling = true;

        try
        {
            var sitesToDeploy = new HashSet<string>(StringComparer.OrdinalIgnoreCase);

            sitesToDeploy.UnionWith(await CheckDedgeWinAppsAsync());
            sitesToDeploy.UnionWith(await CheckTemplatesAsync());

            if (sitesToDeploy.Count > 0)
            {
                await Task.Run(() => RunDeploysSequentially(sitesToDeploy));
            }

            if (DateTime.UtcNow - _lastUpdateCheck > UpdateCheckInterval)
                RefreshUpdateMenuState();
        }
        catch (Exception ex)
        {
            WriteLog("ERR", $"Poll error: {ex.Message}");
        }
        finally
        {
            _isPolling = false;
        }
    }

    /// <summary>
    /// Scans DedgeWinApps subfolders for matching DLLs, tracks per-folder max LastWriteTime
    /// and total size. Only returns SiteNames whose folders have been stable (no changes)
    /// for at least <see cref="StabilitySeconds"/> seconds, preventing deploys while
    /// Build-And-Publish is still copying files.
    /// </summary>
    private Task<HashSet<string>> CheckDedgeWinAppsAsync()
    {
        var result = new HashSet<string>(StringComparer.OrdinalIgnoreCase);

        try
        {
            if (!Directory.Exists(_DedgeWinAppsPath)) return Task.FromResult(result);

            var now = DateTime.UtcNow;

            foreach (var subDir in Directory.GetDirectories(_DedgeWinAppsPath))
            {
                var folderName = Path.GetFileName(subDir);
                if (string.IsNullOrEmpty(folderName)) continue;

                var files = Directory.GetFiles(subDir, _settings.FilePattern, SearchOption.AllDirectories);
                if (files.Length == 0) continue;

                var maxWrite = DateTime.MinValue;
                long totalSize = 0;
                foreach (var f in files)
                {
                    var fi = new FileInfo(f);
                    if (fi.LastWriteTimeUtc > maxWrite) maxWrite = fi.LastWriteTimeUtc;
                    totalSize += fi.Length;
                }

                if (_folderSnapshots.TryGetValue(folderName, out var prev))
                {
                    if (prev.MaxWriteUtc == maxWrite && prev.TotalSize == totalSize)
                    {
                        // Nothing changed -- check if stability timeout has elapsed
                        if (!prev.Deployed && now >= prev.DeployAfterUtc &&
                            _installAppNameToSiteName.TryGetValue(folderName, out var siteName))
                        {
                            result.Add(siteName);
                            prev.Deployed = true;
                        }
                    }
                    else
                    {
                        // Files changed -- reset the stability timer
                        prev.MaxWriteUtc = maxWrite;
                        prev.TotalSize = totalSize;
                        prev.DeployAfterUtc = now.AddSeconds(StabilitySeconds);
                        prev.Deployed = false;
                        WriteLog("INF", $"[DedgeWinApps] {folderName}: change detected, deploy after {prev.DeployAfterUtc:HH:mm:ss}");
                    }
                }
                else
                {
                    // First time seeing this folder -- store snapshot, no deploy yet
                    _folderSnapshots[folderName] = new FolderSnapshot
                    {
                        MaxWriteUtc = maxWrite,
                        TotalSize = totalSize,
                        DeployAfterUtc = DateTime.MaxValue,
                        Deployed = true
                    };
                }
            }
        }
        catch (Exception ex)
        {
            WriteLog("ERR", $"CheckDedgeWinApps error: {ex.Message}");
        }

        return Task.FromResult(result);
    }

    private async Task<HashSet<string>> CheckTemplatesAsync()
    {
        var result = new HashSet<string>(StringComparer.OrdinalIgnoreCase);
        var statePath = Path.Combine(_stateFolder, "templates-state.json");

        try
        {
            if (!Directory.Exists(_templatesPath)) return result;

            var state = await LoadStateAsync<Dictionary<string, string>>(statePath)
                ?? new Dictionary<string, string>();

            var newState = new Dictionary<string, string>(StringComparer.OrdinalIgnoreCase);

            bool hasNewTemplates = false;

            foreach (var file in Directory.GetFiles(_templatesPath, "*.deploy.json"))
            {
                var lastWrite = File.GetLastWriteTimeUtc(file).ToString("O");
                var fileName = Path.GetFileName(file);

                newState[fileName] = lastWrite;

                bool isNew = !state.TryGetValue(fileName, out var oldWrite);
                bool isChanged = !isNew && oldWrite != lastWrite;

                if (isNew || isChanged)
                {
                    var siteName = ExtractSiteNameFromTemplate(fileName);
                    if (!string.IsNullOrEmpty(siteName) && !siteName.Equals("DefaultWebSite", StringComparison.OrdinalIgnoreCase))
                    {
                        result.Add(siteName);
                        if (isNew)
                        {
                            hasNewTemplates = true;
                            WriteLog("INF", $"[Templates] New template detected: {fileName} -> {siteName}");
                        }
                    }
                }
            }

            await SaveStateAsync(statePath, newState);

            if (hasNewTemplates)
                await RefreshInstallAppNameMapAsync();
        }
        catch (Exception ex)
        {
            WriteLog("ERR", $"CheckTemplates error: {ex.Message}");
        }

        return result;
    }

    private static string? ExtractSiteNameFromTemplate(string fileName)
    {
        var name = Path.GetFileNameWithoutExtension(fileName);
        var idx = name.IndexOf('_');
        return idx < 0 ? name : name.Substring(0, idx);
    }

    private void RunDeploysSequentially(HashSet<string> siteNames)
    {
        foreach (var siteName in siteNames.OrderBy(s => s))
        {
            using var mutex = new Mutex(false, DeployMutexName);
            try
            {
                if (!mutex.WaitOne(MutexTimeoutMs))
                {
                    _hiddenForm.Invoke(() =>
                        _notifyIcon.ShowBalloonTip(5000, "IIS Deploy Skipped",
                            "Another deploy in progress. Will retry next poll.", ToolTipIcon.Warning));
                    return;
                }

                _hiddenForm.Invoke(() =>
                {
                    _notifyIcon.Icon = _deployingIcon;
                    _notifyIcon.Text = $"IIS Auto-Deploy: deploying {siteName}...";
                });

                var success = RunIISDeployApp(siteName);

                var smsMsg = success
                    ? $"IIS-AutoDeploy: {siteName} deployed OK on {Environment.MachineName}"
                    : $"IIS-AutoDeploy: {siteName} deploy FAILED on {Environment.MachineName}";
                SendSms(smsMsg);

                _hiddenForm.Invoke(() =>
                {
                    _notifyIcon.Icon = _normalIcon;
                    _notifyIcon.Text = $"IIS Auto-Deploy Tray v{GetRunningVersion()}";
                    _notifyIcon.ShowBalloonTip(5000,
                        success ? $"{siteName} deployed" : $"{siteName} deploy failed",
                        success ? "IIS-DeployApp completed successfully." : "Check logs for details.",
                        success ? ToolTipIcon.Info : ToolTipIcon.Error);
                });
            }
            finally
            {
                try { mutex.ReleaseMutex(); } catch { }
            }
        }

        // After all deploys complete, silently reinstall ourselves from the updated MSI.
        // This is a detached process because msiexec will kill this running instance.
        SelfReinstallFromMsi();
    }

    private bool RunIISDeployApp(string siteName)
    {
        if (!File.Exists(_deployScriptPath))
        {
            WriteLog("ERR", $"IIS-DeployApp.ps1 not found at {_deployScriptPath}");
            return false;
        }

        try
        {
            var psi = new ProcessStartInfo("pwsh.exe",
                $"-NoProfile -WindowStyle Hidden -File \"{_deployScriptPath}\" -SiteName \"{siteName}\"")
            {
                UseShellExecute = true,
                WindowStyle = ProcessWindowStyle.Hidden
            };

            using var proc = Process.Start(psi)!;
            proc.WaitForExit(TimeSpan.FromMinutes(10));
            return proc.ExitCode == 0;
        }
        catch (Exception ex)
        {
            WriteLog("ERR", $"RunIISDeployApp failed: {ex.Message}");
            return false;
        }
    }

    private static void SendSms(string message)
    {
        try
        {
            var optPath = Environment.GetEnvironmentVariable("OptPath") ?? @"C:\opt";
            var scriptPath = Path.Combine(optPath, "DedgePshApps", "Send-Sms", "Send-Sms.ps1");

            ProcessStartInfo psi;
            if (File.Exists(scriptPath))
            {
                psi = new ProcessStartInfo("pwsh.exe",
                    $"-NoProfile -File \"{scriptPath}\" \"+4797188358\" \"{message}\"");
            }
            else
            {
                psi = new ProcessStartInfo("Send-Sms.bat",
                    $"\"+4797188358\" \"{message}\"");
            }

            psi.UseShellExecute = false;
            psi.CreateNoWindow = true;
            psi.RedirectStandardOutput = true;
            psi.RedirectStandardError = true;

            using var proc = Process.Start(psi);
            proc?.WaitForExit(TimeSpan.FromSeconds(30));
        }
        catch (Exception ex)
        {
            Debug.WriteLine($"SendSms failed: {ex.Message}");
        }
    }

    /// <summary>
    /// Launches a detached msiexec process to silently reinstall this tray app from the
    /// staging share MSI. Skips if the running version already matches the MSI version.
    /// Must be detached because the MSI's CloseApplication action will terminate this process.
    /// </summary>
    private void SelfReinstallFromMsi()
    {
        var msiPath = Path.Combine(_DedgeWinAppsPath, "IIS-AutoDeploy-Tray", "IIS-AutoDeploy.Tray.Setup.msi");
        if (!File.Exists(msiPath))
        {
            WriteLog("DBG", $"MSI not found at {msiPath}, skipping self-reinstall");
            return;
        }

        var runningVersion = GetRunningVersion();
        var msiVersion = ReadMsiProductVersion(msiPath);
        if (msiVersion != null && AreVersionsEqual(runningVersion, msiVersion))
        {
            WriteLog("DBG", $"Tray already at v{runningVersion}, skipping self-reinstall");
            return;
        }

        try
        {
            WriteLog("INF", $"Launching detached self-reinstall from {msiPath} (v{runningVersion} → v{msiVersion})");

            var psi = new ProcessStartInfo("msiexec.exe", $"/i \"{msiPath}\" /qn")
            {
                UseShellExecute = true
            };

            Process.Start(psi);
        }
        catch (Exception ex)
        {
            WriteLog("ERR", $"SelfReinstallFromMsi failed: {ex.Message}");
        }
    }

    private void RefreshUpdateMenuState()
    {
        _lastUpdateCheck = DateTime.UtcNow;
        var runningVersion = GetRunningVersion();
        var msiPath = Path.Combine(_DedgeWinAppsPath, "IIS-AutoDeploy-Tray", "IIS-AutoDeploy.Tray.Setup.msi");
        var msiVersion = File.Exists(msiPath) ? ReadMsiProductVersion(msiPath) : null;

        _hiddenForm.Invoke(() =>
        {
            if (msiVersion == null)
            {
                _updateMenuItem.Text = $"Update (v{runningVersion})";
                _updateMenuItem.Enabled = false;
                _updateMenuItem.ToolTipText = "MSI not found in staging share";
            }
            else if (AreVersionsEqual(runningVersion, msiVersion))
            {
                _updateMenuItem.Text = $"Update (v{runningVersion} — up to date)";
                _updateMenuItem.Enabled = false;
                _updateMenuItem.ToolTipText = "Running version matches available MSI";
            }
            else
            {
                _updateMenuItem.Text = $"Update Available (v{runningVersion} → v{msiVersion})";
                _updateMenuItem.Enabled = true;
                _updateMenuItem.ToolTipText = "Click to install the updated version";
            }
        });
    }

    private static string GetRunningVersion()
    {
        var version = typeof(AutoDeployTrayContext).Assembly
            .GetCustomAttribute<AssemblyInformationalVersionAttribute>()
            ?.InformationalVersion ?? "0.0.0";

        // Strip SourceLink commit hash suffix (e.g. "1.0.124+abc123" → "1.0.124")
        var plusIndex = version.IndexOf('+');
        return plusIndex >= 0 ? version[..plusIndex] : version;
    }

    /// <summary>
    /// Reads ProductVersion from an MSI file using Windows Installer COM interop.
    /// </summary>
    private static string? ReadMsiProductVersion(string msiPath)
    {
        object? installer = null;
        object? database = null;

        try
        {
            var installerType = Type.GetTypeFromProgID("WindowsInstaller.Installer");
            if (installerType == null) return null;

            installer = Activator.CreateInstance(installerType);
            if (installer == null) return null;

            database = installerType.InvokeMember("OpenDatabase",
                BindingFlags.InvokeMethod, null, installer,
                new object[] { msiPath, 0 });

            if (database == null) return null;

            var dbType = database.GetType();
            var view = dbType.InvokeMember("OpenView",
                BindingFlags.InvokeMethod, null, database,
                new object[] { "SELECT `Value` FROM `Property` WHERE `Property` = 'ProductVersion'" });

            if (view == null) return null;

            var viewType = view.GetType();
            viewType.InvokeMember("Execute",
                BindingFlags.InvokeMethod, null, view, null);

            var record = viewType.InvokeMember("Fetch",
                BindingFlags.InvokeMethod, null, view, null);

            if (record == null) return null;

            try
            {
                var version = record.GetType().InvokeMember("StringData",
                    BindingFlags.GetProperty, null, record,
                    new object[] { 1 }) as string;
                return version;
            }
            finally
            {
                Marshal.ReleaseComObject(record);
                Marshal.ReleaseComObject(view!);
            }
        }
        catch (Exception ex)
        {
            Debug.WriteLine($"ReadMsiProductVersion failed: {ex.Message}");
            return null;
        }
        finally
        {
            if (database != null) try { Marshal.ReleaseComObject(database); } catch { }
            if (installer != null) try { Marshal.ReleaseComObject(installer); } catch { }
        }
    }

    /// <summary>
    /// Compares two version strings, normalizing trailing ".0" segments.
    /// Handles mismatches like "1.0.123.0" vs "1.0.123".
    /// </summary>
    private static bool AreVersionsEqual(string? version1, string? version2)
    {
        if (string.Equals(version1, version2, StringComparison.OrdinalIgnoreCase))
            return true;
        return string.Equals(
            NormalizeVersion(version1),
            NormalizeVersion(version2),
            StringComparison.OrdinalIgnoreCase);
    }

    private static string NormalizeVersion(string? version)
    {
        if (string.IsNullOrEmpty(version)) return "";
        var parts = version.Split('.');
        var minParts = Math.Min(3, parts.Length);
        var lastSignificant = parts.Length - 1;
        while (lastSignificant >= minParts && parts[lastSignificant] == "0")
            lastSignificant--;
        return string.Join(".", parts.Take(lastSignificant + 1));
    }

    private void LaunchSelfUpdate()
    {
        var msiPath = Path.Combine(_DedgeWinAppsPath, "IIS-AutoDeploy-Tray", "IIS-AutoDeploy.Tray.Setup.msi");
        if (!File.Exists(msiPath))
        {
            _hiddenForm.Invoke(() =>
                _notifyIcon.ShowBalloonTip(5000, "Update Failed",
                    "MSI not found in staging share.", ToolTipIcon.Error));
            return;
        }

        _hiddenForm.Invoke(() =>
            _notifyIcon.ShowBalloonTip(3000, "Updating",
                "Launching installer — tray will restart automatically.", ToolTipIcon.Info));

        try
        {
            var psi = new ProcessStartInfo("msiexec.exe", $"/i \"{msiPath}\" /qn")
            {
                UseShellExecute = true
            };
            Process.Start(psi);
        }
        catch (Exception ex)
        {
            _hiddenForm.Invoke(() =>
                _notifyIcon.ShowBalloonTip(5000, "Update Failed",
                    $"Could not launch installer: {ex.Message}", ToolTipIcon.Error));
        }
    }

    private async Task<T?> LoadStateAsync<T>(string path) where T : class
    {
        try
        {
            if (!File.Exists(path)) return null;
            var json = await File.ReadAllTextAsync(path);
            return JsonSerializer.Deserialize<T>(json, _jsonOptions);
        }
        catch
        {
            return null;
        }
    }

    private async Task SaveStateAsync<T>(string path, T state)
    {
        try
        {
            var json = JsonSerializer.Serialize(state, _jsonOptions);
            await File.WriteAllTextAsync(path, json);
        }
        catch (Exception ex)
        {
            WriteLog("ERR", $"SaveState failed: {ex.Message}");
        }
    }

    private void OpenIISDeployAppFolder()
    {
        try
        {
            var dir = Path.GetDirectoryName(_deployScriptPath);
            if (!string.IsNullOrEmpty(dir) && Directory.Exists(dir))
                Process.Start(new ProcessStartInfo { FileName = dir, UseShellExecute = true });
        }
        catch (Exception ex)
        {
            _notifyIcon.ShowBalloonTip(3000, "Error", ex.Message, ToolTipIcon.Error);
        }
    }

    private void OpenSettings()
    {
        try
        {
            var path = Path.Combine(AppContext.BaseDirectory, "appsettings.json");
            if (File.Exists(path))
                Process.Start(new ProcessStartInfo { FileName = "notepad.exe", Arguments = $"\"{path}\"", UseShellExecute = true });
        }
        catch (Exception ex)
        {
            _notifyIcon.ShowBalloonTip(3000, "Error", ex.Message, ToolTipIcon.Error);
        }
    }

    private void TogglePause()
    {
        _surveillancePaused = !_surveillancePaused;
        var item = _notifyIcon.ContextMenuStrip?.Items.Cast<ToolStripItem>()
            .FirstOrDefault(i => i.Text?.Contains("Pause") == true || i.Text?.Contains("Resume") == true);
        if (item != null)
        {
            item.Text = _surveillancePaused ? "Resume Surveillance" : "Pause Surveillance";
        }
        _notifyIcon.ShowBalloonTip(2000, "Surveillance",
            _surveillancePaused ? "Paused" : "Resumed", ToolTipIcon.Info);
    }

    private void ExitApplication()
    {
        _pollTimer.Stop();
        _notifyIcon.Visible = false;
        Application.Exit();
    }

    private void WriteLog(string level, string message)
    {
        Debug.WriteLine($"[{level}] {message}");
        try
        {
            var logFile = Path.Combine(_logFolder, $"IIS-AutoDeploy.Tray-{DateTime.Now:yyyyMMdd}.log");
            var line = $"{DateTime.Now:yyyy-MM-dd HH:mm:ss.fff} [{level}] {message}{Environment.NewLine}";
            File.AppendAllText(logFile, line);
        }
        catch { /* best-effort file logging */ }
    }

    protected override void Dispose(bool disposing)
    {
        if (disposing)
        {
            _pollTimer?.Dispose();
            _notifyIcon?.Dispose();
            _hiddenForm?.Dispose();
            _normalIcon?.Dispose();
            _deployingIcon?.Dispose();
        }
        base.Dispose(disposing);
    }
}

public class AutoDeploySettings
{
    public string DedgeWinAppsPath { get; set; } = "";
    public string TemplatesPath { get; set; } = "";
    public string FilePattern { get; set; } = "DedgeAuth*.dll";
    public int PollIntervalSeconds { get; set; } = 30;
    public string IISDeployAppScriptPath { get; set; } = "";
    public string StateFolder { get; set; } = "";
    public string LogFolder { get; set; } = "";
}

/// <summary>
/// In-memory snapshot of a DedgeWinApps subfolder used to detect stability.
/// Deploy only fires when MaxWriteUtc and TotalSize have not changed for StabilitySeconds.
/// </summary>
internal class FolderSnapshot
{
    public DateTime MaxWriteUtc { get; set; }
    public long TotalSize { get; set; }
    public DateTime DeployAfterUtc { get; set; }
    public bool Deployed { get; set; }
}
