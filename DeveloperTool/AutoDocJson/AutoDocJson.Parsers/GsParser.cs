using System;
using System.Diagnostics;
using System.IO;
using System.Text;
using System.Threading;
using System.Threading.Tasks;
using AutoDocNew.Core;

namespace AutoDocNew.Parsers;

/// <summary>
/// Processes Dialog System screenset files (.gs).
/// Converted from HandleGsFiles (lines 1328-1481) and Start-GsParse (AutoDocFunctions 11964-12193).
/// Step 1: Export .gs to .imp using dswin.exe (with 30s timeout, own thread)
/// Step 2: Parse .imp file and generate .screen.html
/// </summary>
public static class GsParser
{
    private const string DswinPath = @"C:\Program Files (x86)\Micro Focus\Net Express 5.1\DIALOGSYSTEM\Bin\dswin.exe";

    /// <summary>
    /// Timeout for dswin.exe process in seconds.
    /// Matches PowerShell: $timeoutSeconds = 30
    /// </summary>
    private const int TimeoutSeconds = 30;

    /// <summary>
    /// Process a single .gs file: export to .imp, then parse to .screen.html.
    /// Returns the HTML output path or null on failure.
    /// Converted line-by-line from HandleGsFiles (PS lines 1416-1477).
    /// </summary>
    public static string? StartGsParse(string gsFilePath, string impFolder, string outputFolder)
    {
        string baseName = Path.GetFileNameWithoutExtension(gsFilePath).ToUpper();
        string impFile = Path.Combine(impFolder, baseName + ".IMP");
        string htmlFile = Path.Combine(outputFolder, baseName + ".screen.html");
        string errFile = Path.Combine(outputFolder, baseName + ".screen.err");

        // Remove previous error file (PS line 1412-1413)
        if (File.Exists(errFile))
            try { File.Delete(errFile); } catch { }

        // Check if dswin.exe exists (PS lines 1349-1353)
        if (!File.Exists(DswinPath))
        {
            Logger.LogMessage($"dswin.exe not found at: {DswinPath} - skipping GS file {baseName}", LogLevel.WARN);
            File.WriteAllText(errFile, "dswin.exe not found");
            return null;
        }

        if (!Directory.Exists(impFolder))
            Directory.CreateDirectory(impFolder);

        // Step 1: Export .gs to .imp using dswin.exe with timeout (PS lines 1417-1448)
        // dswin.exe runs on its own thread and is killed after TimeoutSeconds if it
        // has not produced the .imp file.
        Logger.LogMessage($"Exporting GS: {Path.GetFileName(gsFilePath)} -> {baseName}.IMP", LogLevel.DEBUG);

        bool exportSuccess = RunDswinWithTimeout(gsFilePath, impFile, baseName, errFile);
        if (!exportSuccess)
            return null;

        // Verify .imp file was created (PS lines 1450-1456)
        if (!File.Exists(impFile))
        {
            Logger.LogMessage($"Failed to export {Path.GetFileName(gsFilePath)} - no IMP file created", LogLevel.WARN);
            File.WriteAllText(errFile, "Export failed: No IMP file created by dswin.exe");
            return null;
        }

        // Step 2: Parse .imp file and generate HTML (PS lines 1458-1477)
        Logger.LogMessage($"Parsing IMP: {baseName}.IMP", LogLevel.DEBUG);
        try
        {
            ParseImpToHtml(impFile, htmlFile, baseName);
            if (File.Exists(htmlFile))
            {
                Logger.LogMessage($"Generated: {baseName}.screen.html", LogLevel.INFO);
                return htmlFile;
            }
            Logger.LogMessage($"Failed to generate HTML for {baseName}", LogLevel.WARN);
            File.WriteAllText(errFile, "Parse failed: HTML file not generated");
            return null;
        }
        catch (Exception ex)
        {
            Logger.LogMessage($"Error processing {Path.GetFileName(gsFilePath)}: {ex.Message}", LogLevel.ERROR);
            File.WriteAllText(errFile, ex.Message);
            return null;
        }
    }

    /// <summary>
    /// Runs dswin.exe on a separate thread with a timeout.
    /// Matches PowerShell lines 1420-1448:
    ///   $process = Start-Process -FilePath $dswinPath -ArgumentList "/e ..." -PassThru -NoNewWindow
    ///   $completed = $process.WaitForExit($timeoutSeconds * 1000)
    ///   if (-not $completed) { kill specific + kill all lingering dswin }
    /// </summary>
    private static bool RunDswinWithTimeout(string gsFilePath, string impFile, string baseName, string errFile)
    {
        Process? process = null;
        try
        {
            // PS line 1420-1422: Start-Process -FilePath $dswinPath -ArgumentList "/e ..." -PassThru -NoNewWindow
            var psi = new ProcessStartInfo
            {
                FileName = DswinPath,
                Arguments = $"/e \"{gsFilePath}\" \"{impFile}\"",
                UseShellExecute = false,
                CreateNoWindow = true
            };

            process = Process.Start(psi);
            if (process == null)
            {
                File.WriteAllText(errFile, "Failed to start dswin.exe");
                return false;
            }

            // PS line 1426: $completed = $process.WaitForExit($timeoutSeconds * 1000)
            // Run WaitForExit on a Task so the process runs on its own thread
            bool completed;
            try
            {
                var waitTask = Task.Run(() => process.WaitForExit(TimeoutSeconds * 1000));
                completed = waitTask.GetAwaiter().GetResult();
            }
            catch
            {
                completed = false;
            }

            if (!completed)
            {
                // PS lines 1432-1447: Process exceeded timeout - kill it
                Logger.LogMessage($"dswin.exe timeout for {baseName} - killing process", LogLevel.WARN);

                // PS line 1436-1438: Kill specific process
                if (!process.HasExited)
                {
                    try { process.Kill(entireProcessTree: true); } catch { }
                }

                // PS lines 1440-1443: Kill any lingering dswin.exe processes by name
                KillAllDswinProcesses();

                // PS line 1445: Write error file
                File.WriteAllText(errFile, $"Timeout: dswin.exe exceeded {TimeoutSeconds} seconds");
                return false;
            }

            return true;
        }
        catch (Exception ex)
        {
            Logger.LogMessage($"dswin.exe error for {baseName}: {ex.Message}", LogLevel.ERROR);
            File.WriteAllText(errFile, $"dswin.exe error: {ex.Message}");

            // Kill any lingering dswin.exe on exception too
            KillAllDswinProcesses();
            return false;
        }
        finally
        {
            process?.Dispose();
        }
    }

    /// <summary>
    /// Kill any lingering dswin.exe processes.
    /// Matches PowerShell lines 1440-1443:
    ///   Get-Process -Name "dswin" -ErrorAction SilentlyContinue | ForEach-Object {
    ///       $_ | Stop-Process -Force -ErrorAction SilentlyContinue
    ///   }
    /// </summary>
    private static void KillAllDswinProcesses()
    {
        try
        {
            var dswinProcesses = Process.GetProcessesByName("dswin");
            foreach (var p in dswinProcesses)
            {
                try
                {
                    if (!p.HasExited)
                        p.Kill();
                }
                catch { /* SilentlyContinue equivalent */ }
                finally
                {
                    p.Dispose();
                }
            }
        }
        catch { /* SilentlyContinue equivalent */ }
    }

    /// <summary>Parse a .imp file and generate a simple screen HTML document.</summary>
    private static void ParseImpToHtml(string impFile, string htmlFile, string baseName)
    {
        string[] lines = File.ReadAllLines(impFile);
        var sb = new StringBuilder();

        string templateFolder = Path.Combine(PathHelper.GetAutodocSharedFolder(), "_templates");
        string templatePath = Path.Combine(templateFolder, "gsmmdtemplate.html");
        string template = File.Exists(templatePath) ? File.ReadAllText(templatePath) : GetDefaultTemplate();

        // Parse screens from .imp content
        var screens = new System.Collections.Generic.List<(string name, string content)>();
        string currentScreen = "";
        var currentContent = new StringBuilder();

        foreach (string line in lines)
        {
            if (line.StartsWith("WINDOW", StringComparison.OrdinalIgnoreCase) ||
                line.StartsWith("SCREENSET", StringComparison.OrdinalIgnoreCase))
            {
                if (!string.IsNullOrEmpty(currentScreen))
                    screens.Add((currentScreen, currentContent.ToString()));
                currentScreen = line.Trim();
                currentContent.Clear();
            }
            else
            {
                currentContent.AppendLine(System.Net.WebUtility.HtmlEncode(line));
            }
        }
        if (!string.IsNullOrEmpty(currentScreen))
            screens.Add((currentScreen, currentContent.ToString()));

        // Build HTML tabs for each screen
        sb.AppendLine("<div class=\"screen-tabs\">");
        foreach (var (name, _) in screens)
        {
            sb.AppendLine($"  <button class=\"screen-tab\" onclick=\"openScreen('{name}')\">{name}</button>");
        }
        sb.AppendLine("</div>");
        foreach (var (name, content) in screens)
        {
            sb.AppendLine($"<div id=\"{name}\" class=\"screen-content\"><pre>{content}</pre></div>");
        }

        string html = template
            .Replace("[title]", baseName)
            .Replace("[content]", sb.ToString())
            .Replace("[filename]", baseName + ".gs")
            .Replace("[generated]", DateTime.Now.ToString("yyyy-MM-dd HH:mm:ss"));

        File.WriteAllText(htmlFile, html, Encoding.UTF8);
    }

    private static string GetDefaultTemplate()
    {
        return @"<!DOCTYPE html><html><head><title>[title]</title></head>
<body><h1>[filename]</h1><p>Generated: [generated]</p>[content]</body></html>";
    }
}
