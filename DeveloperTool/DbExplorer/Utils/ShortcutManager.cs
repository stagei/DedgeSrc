using System;
using System.IO;
using System.Runtime.InteropServices;
using System.Runtime.InteropServices.ComTypes;
using System.Text;
using NLog;

namespace DbExplorer.Utils;

/// <summary>
/// Manages creation of desktop and Start Menu shortcuts
/// </summary>
public static class ShortcutManager
{
    private static readonly Logger Logger = LogManager.GetCurrentClassLogger();

    private const string AppName = "DbExplorer";
    private const string StartMenuFolderName = "DbEditor";

    // Shell32 notification constants
    private const int SHCNE_CREATE = 0x00000002;
    private const int SHCNE_UPDATEDIR = 0x00001000;
    private const int SHCNF_PATH = 0x0005;
    private const int SHCNF_FLUSH = 0x1000;

    [DllImport("shell32.dll")]
    private static extern void SHChangeNotify(int wEventId, int uFlags, IntPtr dwItem1, IntPtr dwItem2);

    /// <summary>
    /// Creates shortcuts on desktop and Start Menu if they don't already exist
    /// </summary>
    public static void EnsureShortcutsExist()
    {
        try
        {
            var exePath = GetExecutablePath();
            if (string.IsNullOrEmpty(exePath) || !File.Exists(exePath))
            {
                Logger.Warn("Executable path not found, skipping shortcut creation");
                return;
            }

            // Create desktop shortcut
            CreateDesktopShortcut(exePath);

            // Create Start Menu shortcut
            CreateStartMenuShortcut(exePath);
        }
        catch (Exception ex)
        {
            Logger.Error(ex, "Failed to create shortcuts");
        }
    }

    private static string GetExecutablePath()
    {
        var exePath = System.Diagnostics.Process.GetCurrentProcess().MainModule?.FileName;
        return exePath ?? string.Empty;
    }

    private static void CreateDesktopShortcut(string exePath)
    {
        try
        {
            var desktopPath = Environment.GetFolderPath(Environment.SpecialFolder.Desktop);
            var shortcutPath = Path.Combine(desktopPath, $"{AppName}.lnk");

            if (File.Exists(shortcutPath))
            {
                Logger.Debug("Desktop shortcut already exists: {Path}", shortcutPath);
                return;
            }

            CreateShortcut(shortcutPath, exePath, "DB2 Database Editor");
            Logger.Info("Created desktop shortcut: {Path}", shortcutPath);
        }
        catch (Exception ex)
        {
            Logger.Error(ex, "Failed to create desktop shortcut");
        }
    }

    private static void CreateStartMenuShortcut(string exePath)
    {
        try
        {
            var startMenuPath = Environment.GetFolderPath(Environment.SpecialFolder.StartMenu);
            var folderPath = Path.Combine(startMenuPath, "Programs", StartMenuFolderName);
            var shortcutPath = Path.Combine(folderPath, $"{AppName}.lnk");

            if (File.Exists(shortcutPath))
            {
                Logger.Debug("Start Menu shortcut already exists: {Path}", shortcutPath);
                return;
            }

            // Create folder if it doesn't exist
            if (!Directory.Exists(folderPath))
            {
                Directory.CreateDirectory(folderPath);
                Logger.Debug("Created Start Menu folder: {Path}", folderPath);
            }

            CreateShortcut(shortcutPath, exePath, "DB2 Database Editor");
            Logger.Info("Created Start Menu shortcut: {Path}", shortcutPath);
        }
        catch (Exception ex)
        {
            Logger.Error(ex, "Failed to create Start Menu shortcut");
        }
    }

    private static void CreateShortcut(string shortcutPath, string targetPath, string description)
    {
        var shell = new ShellLink();
        var shellLink = (IShellLinkW)shell;
        
        shellLink.SetPath(targetPath);
        shellLink.SetDescription(description);
        shellLink.SetWorkingDirectory(Path.GetDirectoryName(targetPath) ?? "");
        
        // Set icon to the executable itself
        shellLink.SetIconLocation(targetPath, 0);

        var persistFile = (IPersistFile)shell;
        persistFile.Save(shortcutPath, true);

        Marshal.ReleaseComObject(shell);

        // Notify Windows shell that a new file was created
        NotifyShellOfNewShortcut(shortcutPath);
    }

    private static void NotifyShellOfNewShortcut(string shortcutPath)
    {
        try
        {
            // Notify about the new file
            var pathPtr = Marshal.StringToHGlobalUni(shortcutPath);
            SHChangeNotify(SHCNE_CREATE, SHCNF_PATH | SHCNF_FLUSH, pathPtr, IntPtr.Zero);
            Marshal.FreeHGlobal(pathPtr);

            // Notify about directory update
            var dirPath = Path.GetDirectoryName(shortcutPath);
            if (!string.IsNullOrEmpty(dirPath))
            {
                var dirPtr = Marshal.StringToHGlobalUni(dirPath);
                SHChangeNotify(SHCNE_UPDATEDIR, SHCNF_PATH | SHCNF_FLUSH, dirPtr, IntPtr.Zero);
                Marshal.FreeHGlobal(dirPtr);
            }

            Logger.Debug("Shell notified of new shortcut: {Path}", shortcutPath);
        }
        catch (Exception ex)
        {
            Logger.Warn(ex, "Failed to notify shell of new shortcut");
        }
    }

    #region COM Interop for Shell Links

    [ComImport]
    [Guid("00021401-0000-0000-C000-000000000046")]
    private class ShellLink
    {
    }

    [ComImport]
    [InterfaceType(ComInterfaceType.InterfaceIsIUnknown)]
    [Guid("000214F9-0000-0000-C000-000000000046")]
    private interface IShellLinkW
    {
        void GetPath([Out, MarshalAs(UnmanagedType.LPWStr)] StringBuilder pszFile, int cchMaxPath, IntPtr pfd, uint fFlags);
        void GetIDList(out IntPtr ppidl);
        void SetIDList(IntPtr pidl);
        void GetDescription([Out, MarshalAs(UnmanagedType.LPWStr)] StringBuilder pszName, int cchMaxName);
        void SetDescription([MarshalAs(UnmanagedType.LPWStr)] string pszName);
        void GetWorkingDirectory([Out, MarshalAs(UnmanagedType.LPWStr)] StringBuilder pszDir, int cchMaxPath);
        void SetWorkingDirectory([MarshalAs(UnmanagedType.LPWStr)] string pszDir);
        void GetArguments([Out, MarshalAs(UnmanagedType.LPWStr)] StringBuilder pszArgs, int cchMaxPath);
        void SetArguments([MarshalAs(UnmanagedType.LPWStr)] string pszArgs);
        void GetHotkey(out ushort pwHotkey);
        void SetHotkey(ushort wHotkey);
        void GetShowCmd(out int piShowCmd);
        void SetShowCmd(int iShowCmd);
        void GetIconLocation([Out, MarshalAs(UnmanagedType.LPWStr)] StringBuilder pszIconPath, int cchIconPath, out int piIcon);
        void SetIconLocation([MarshalAs(UnmanagedType.LPWStr)] string pszIconPath, int iIcon);
        void SetRelativePath([MarshalAs(UnmanagedType.LPWStr)] string pszPathRel, uint dwReserved);
        void Resolve(IntPtr hwnd, uint fFlags);
        void SetPath([MarshalAs(UnmanagedType.LPWStr)] string pszFile);
    }

    #endregion
}
