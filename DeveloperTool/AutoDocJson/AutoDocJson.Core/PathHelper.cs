using System;
using System.IO;

namespace AutoDocNew.Core;

/// <summary>
/// Path helper utilities - converted from PowerShell path functions
/// Equivalent to Join-Path, Test-Path, Get-AutodocSharedFolder, etc.
/// </summary>
public static class PathHelper
{
    private static string? _autodocSharedFolder;

    /// <summary>
    /// Get AutoDoc shared folder (templates, _css, _js, _images).
    /// Converted from Get-AutodocSharedFolder in AutoDocFunctions.psm1.
    /// </summary>
    public static string GetAutodocSharedFolder()
    {
        if (_autodocSharedFolder != null)
            return _autodocSharedFolder;

        string optPath = Environment.GetEnvironmentVariable("OptPath") ?? "C:\\opt";
        // Prioritize bundled assets in the application directory (shipped with this project),
        // then fall back to the PowerShell source tree or deployed app folder.
        string[] sharedLocations =
        {
            AppDomain.CurrentDomain.BaseDirectory ?? "",
            Path.Combine(optPath, "src", "DedgePsh", "DevTools", "LegacyCodeTools", "AutoDoc"),
            Path.Combine(optPath, "DedgePshApps", "AutoDoc")
        };

        foreach (string sharedPath in sharedLocations)
        {
            string cssFolder = Path.Combine(sharedPath, "_css");
            if (Directory.Exists(cssFolder))
            {
                _autodocSharedFolder = Path.GetFullPath(sharedPath);
                return _autodocSharedFolder;
            }
        }

        foreach (string sharedPath in sharedLocations)
        {
            if (Directory.Exists(sharedPath))
            {
                _autodocSharedFolder = Path.GetFullPath(sharedPath);
                return _autodocSharedFolder;
            }
        }

        _autodocSharedFolder = "";
        return _autodocSharedFolder;
    }
    /// <summary>
    /// Join paths - equivalent to Join-Path
    /// </summary>
    public static string JoinPath(params string[] paths)
    {
        return Path.Combine(paths);
    }

    /// <summary>
    /// Test if path exists (file) - equivalent to Test-Path for files
    /// </summary>
    public static bool TestPathFile(string path)
    {
        return File.Exists(path);
    }

    /// <summary>
    /// Test if path exists (directory) - equivalent to Test-Path for directories
    /// </summary>
    public static bool TestPathDirectory(string path)
    {
        return Directory.Exists(path);
    }

    /// <summary>
    /// Get DevTools web path
    /// Converted from Agent-Handler module Get-DevToolsWebPath function
    /// </summary>
    public static string GetDevToolsWebPath()
    {
        // Simplified version - will need to read actual implementation
        string optPath = Environment.GetEnvironmentVariable("OptPath") ?? "C:\\opt";
        return Path.Combine(optPath, "Webs", "DevTools");
    }
}
