using System;
using System.IO;
using System.IO.Compression;

namespace AutoDocNew.Core;

/// <summary>
/// Zip output folder for sync and unzip on test server.
/// Converted from AutoDocBatchRunner.ps1 lines 2386-2399 (unzip) and 3140-3151 (zip).
/// </summary>
public static class ContentZipHelper
{
    /// <summary>
    /// If running on dedge-server and content.zip exists, extract to outputFolder.
    /// Converted from PS lines 2386-2399.
    /// </summary>
    public static void UnzipIfNeeded(string outputFolder, string tmpFolder)
    {
        string machineName = Environment.MachineName.ToLower().Trim();
        if (machineName != "dedge-server") return;

        string zipPath = Path.Combine(tmpFolder, "content.zip");
        if (!File.Exists(zipPath)) return;

        Logger.LogMessage($"Unzipping {zipPath} to {outputFolder}", LogLevel.INFO);
        try
        {
            ZipFile.ExtractToDirectory(zipPath, outputFolder, overwriteFiles: true);
            File.Delete(zipPath);
            Logger.LogMessage("Unzip completed", LogLevel.INFO);
        }
        catch (Exception ex)
        {
            Logger.LogMessage($"Unzip failed: {ex.Message}", LogLevel.WARN, ex);
        }
    }

    /// <summary>
    /// If NOT on dedge-server, zip output to content.zip and copy to sync folder.
    /// Converted from PS lines 3140-3151.
    /// </summary>
    public static void ZipAndCopyIfNeeded(string outputFolder, string tmpFolder)
    {
        string machineName = Environment.MachineName.ToLower().Trim();
        if (machineName == "dedge-server") return;

        string zipPath = Path.Combine(tmpFolder, "content.zip");
        try
        {
            if (File.Exists(zipPath))
                File.Delete(zipPath);

            Logger.LogMessage($"Zipping output folder to {zipPath}", LogLevel.INFO);
            ZipFile.CreateFromDirectory(outputFolder, zipPath);

            string optPath = Environment.GetEnvironmentVariable("OptPath") ?? "C:\\opt";
            string syncFolder = Path.Combine(optPath, "data", "AutoDocJson", "Sync");
            if (Directory.Exists(syncFolder))
            {
                string dest = Path.Combine(syncFolder, "content.zip");
                File.Copy(zipPath, dest, overwrite: true);
                Logger.LogMessage($"Copied zip to {dest}", LogLevel.INFO);
            }
        }
        catch (Exception ex)
        {
            Logger.LogMessage($"Zip/copy failed: {ex.Message}", LogLevel.WARN, ex);
        }
    }
}
