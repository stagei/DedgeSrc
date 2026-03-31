using System;
using System.IO;
using Microsoft.Win32;
using NLog;

namespace DbExplorer.Services;

/// <summary>
/// Service for managing Windows startup registry entries
/// </summary>
public class StartupManagerService
{
    private static readonly Logger Logger = LogManager.GetCurrentClassLogger();
    private const string RegistryKeyPath = @"Software\Microsoft\Windows\CurrentVersion\Run";
    private const string RegistryValueName = "DbExplorer";

    /// <summary>
    /// Check if startup is currently enabled
    /// </summary>
    public bool IsStartupEnabled()
    {
        try
        {
            using var key = Registry.CurrentUser.OpenSubKey(RegistryKeyPath, false);
            if (key == null)
            {
                Logger.Debug("Startup registry key not found");
                return false;
            }

            var value = key.GetValue(RegistryValueName);
            var isEnabled = value != null && !string.IsNullOrEmpty(value.ToString());
            
            Logger.Debug("Startup enabled check: {Enabled}", isEnabled);
            return isEnabled;
        }
        catch (Exception ex)
        {
            Logger.Error(ex, "Failed to check startup status");
            return false;
        }
    }

    /// <summary>
    /// Enable startup by adding registry entry
    /// </summary>
    public bool EnableStartup()
    {
        try
        {
            var exePath = GetExecutablePath();
            if (string.IsNullOrEmpty(exePath) || !File.Exists(exePath))
            {
                Logger.Error("Executable path not found: {Path}", exePath);
                return false;
            }

            using var key = Registry.CurrentUser.OpenSubKey(RegistryKeyPath, true);
            if (key == null)
            {
                Logger.Error("Failed to open registry key for writing");
                return false;
            }

            key.SetValue(RegistryValueName, exePath);
            Logger.Info("Startup enabled - Registry entry added: {Path}", exePath);
            return true;
        }
        catch (Exception ex)
        {
            Logger.Error(ex, "Failed to enable startup");
            return false;
        }
    }

    /// <summary>
    /// Disable startup by removing registry entry
    /// </summary>
    public bool DisableStartup()
    {
        try
        {
            using var key = Registry.CurrentUser.OpenSubKey(RegistryKeyPath, true);
            if (key == null)
            {
                Logger.Debug("Startup registry key not found - already disabled");
                return true; // Already disabled
            }

            var value = key.GetValue(RegistryValueName);
            if (value == null)
            {
                Logger.Debug("Startup registry value not found - already disabled");
                return true; // Already disabled
            }

            key.DeleteValue(RegistryValueName, false);
            Logger.Info("Startup disabled - Registry entry removed");
            return true;
        }
        catch (Exception ex)
        {
            Logger.Error(ex, "Failed to disable startup");
            return false;
        }
    }

    /// <summary>
    /// Get the full path to the current executable
    /// </summary>
    public string GetExecutablePath()
    {
        try
        {
            var exePath = System.Reflection.Assembly.GetExecutingAssembly().Location;
            if (string.IsNullOrEmpty(exePath))
            {
                // Fallback to entry assembly location
                exePath = System.Reflection.Assembly.GetEntryAssembly()?.Location;
            }

            if (string.IsNullOrEmpty(exePath))
            {
                // Last resort: use Process.GetCurrentProcess().MainModule
                exePath = System.Diagnostics.Process.GetCurrentProcess().MainModule?.FileName;
            }

            if (!string.IsNullOrEmpty(exePath))
            {
                // Convert to full path
                exePath = Path.GetFullPath(exePath);
                Logger.Debug("Executable path: {Path}", exePath);
            }
            else
            {
                Logger.Warn("Could not determine executable path");
            }

            return exePath ?? string.Empty;
        }
        catch (Exception ex)
        {
            Logger.Error(ex, "Failed to get executable path");
            return string.Empty;
        }
    }
}
