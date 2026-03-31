using System.Diagnostics;
using Microsoft.Win32;

namespace ServerMonitorDashboard.Tray;

static class Program
{
    private const string AppName = "ServerMonitorDashboard.Tray";
    private const string RunKeyPath = @"SOFTWARE\Microsoft\Windows\CurrentVersion\Run";

    [STAThread]
    static void Main()
    {
        using var mutex = new Mutex(true, "ServerMonitorDashboard_Tray_SingleInstance", out bool createdNew);

        if (!createdNew)
            return;

        EnsureAutoStart();

        Application.EnableVisualStyles();
        Application.SetCompatibleTextRenderingDefault(false);
        Application.SetHighDpiMode(HighDpiMode.SystemAware);

        try
        {
            Application.Run(new DashboardTrayContext());
        }
        catch (Exception ex)
        {
            Debug.WriteLine($"Fatal error: {ex}");
            MessageBox.Show($"Fatal error: {ex.Message}", "Dashboard Tray Error",
                MessageBoxButtons.OK, MessageBoxIcon.Error);
        }
    }

    /// <summary>
    /// Registers the app in HKCU\...\Run so it launches on user login.
    /// Skips if already registered (by MSI via HKLM or by a previous launch via HKCU).
    /// Updates the path if the exe has moved since last registration.
    /// </summary>
    private static void EnsureAutoStart()
    {
        try
        {
            var exePath = Environment.ProcessPath ?? Application.ExecutablePath;

            // If HKLM already has a valid entry (written by the MSI installer), don't duplicate in HKCU
            using var hklmKey = Registry.LocalMachine.OpenSubKey(RunKeyPath, writable: false);
            var hklmValue = hklmKey?.GetValue(AppName) as string;
            if (!string.IsNullOrEmpty(hklmValue) && File.Exists(hklmValue))
            {
                Debug.WriteLine($"Auto-start: HKLM entry exists ({hklmValue}), skipping HKCU registration");
                return;
            }

            using var hkcuKey = Registry.CurrentUser.OpenSubKey(RunKeyPath, writable: true)
                                ?? Registry.CurrentUser.CreateSubKey(RunKeyPath);

            var currentValue = hkcuKey.GetValue(AppName) as string;

            if (string.Equals(currentValue, exePath, StringComparison.OrdinalIgnoreCase))
                return;

            hkcuKey.SetValue(AppName, exePath);
            Debug.WriteLine($"Auto-start: registered in HKCU Run → {exePath}");
        }
        catch (Exception ex)
        {
            Debug.WriteLine($"Auto-start registration failed (non-fatal): {ex.Message}");
        }
    }

    /// <summary>
    /// Removes the HKCU auto-start entry. Called when the user explicitly disables auto-start.
    /// </summary>
    internal static void RemoveAutoStart()
    {
        try
        {
            using var key = Registry.CurrentUser.OpenSubKey(RunKeyPath, writable: true);
            key?.DeleteValue(AppName, throwOnMissingValue: false);
            Debug.WriteLine("Auto-start: removed HKCU Run entry");
        }
        catch (Exception ex)
        {
            Debug.WriteLine($"Auto-start removal failed: {ex.Message}");
        }
    }

    /// <summary>
    /// Checks whether auto-start is currently enabled (in either HKLM or HKCU).
    /// </summary>
    internal static bool IsAutoStartEnabled()
    {
        try
        {
            using var hklmKey = Registry.LocalMachine.OpenSubKey(RunKeyPath, writable: false);
            if (!string.IsNullOrEmpty(hklmKey?.GetValue(AppName) as string))
                return true;

            using var hkcuKey = Registry.CurrentUser.OpenSubKey(RunKeyPath, writable: false);
            return !string.IsNullOrEmpty(hkcuKey?.GetValue(AppName) as string);
        }
        catch
        {
            return false;
        }
    }
}
