using System;
using System.IO;
using AutoDocNew.Core;
using AutoDocNew.Parsers;

namespace AutoDocNew.Tests;

/// <summary>
/// Quick test for CBL parser - direct call without compilation step
/// </summary>
public class QuickTestCbl
{
    public static int RunTest(string[] args)
    {
        try
        {
            string optPath = Environment.GetEnvironmentVariable("OptPath") ?? "C:\\opt";
            string testFile = args.Length > 0 ? args[0] : Path.Combine(optPath, "data", "AutoDocJson", "tmp", "DedgeRepository", "Dedge", "cbl", "BSAUTOS.CBL");
            string outputFolder = Path.Combine(optPath, "Webs", "AutoDocJson");
            string tmpRootFolder = Path.Combine(optPath, "data", "AutoDocJson", "tmp");
            string srcRootFolder = Path.Combine(optPath, "data", "AutoDocJson", "tmp", "DedgeRepository");

            Logger.LogMessage($"Testing CBL file: {testFile}", LogLevel.INFO);
            Logger.LogMessage($"Output folder: {outputFolder}", LogLevel.INFO);

            // Ensure output folder exists
            Directory.CreateDirectory(outputFolder);
            Directory.CreateDirectory(Path.Combine(outputFolder, "_templates"));
            Directory.CreateDirectory(Path.Combine(outputFolder, "_css"));
            Directory.CreateDirectory(Path.Combine(outputFolder, "_js"));
            Directory.CreateDirectory(Path.Combine(outputFolder, "_images"));

            // Copy template if it doesn't exist
            string templatePath = Path.Combine(outputFolder, "_templates", "cblmmdtemplate.html");
            if (!File.Exists(templatePath))
            {
                string sharedTemplate = Path.Combine(optPath, "src", "DedgePsh", "DevTools", "LegacyCodeTools", "AutoDoc", "_templates", "cblmmdtemplate.html");
                if (File.Exists(sharedTemplate))
                {
                    Directory.CreateDirectory(Path.GetDirectoryName(templatePath)!);
                    File.Copy(sharedTemplate, templatePath, true);
                    Logger.LogMessage($"Copied template to: {templatePath}", LogLevel.INFO);
                }
            }

            // Copy CSS if it doesn't exist
            string cssPath = Path.Combine(outputFolder, "_css", "autodoc-shared.css");
            if (!File.Exists(cssPath))
            {
                string sharedCss = Path.Combine(optPath, "src", "DedgePsh", "DevTools", "LegacyCodeTools", "AutoDoc", "_css", "autodoc-shared.css");
                if (File.Exists(sharedCss))
                {
                    Directory.CreateDirectory(Path.GetDirectoryName(cssPath)!);
                    File.Copy(sharedCss, cssPath, true);
                    Logger.LogMessage($"Copied CSS to: {cssPath}", LogLevel.INFO);
                }
            }

            if (!File.Exists(testFile))
            {
                Logger.LogMessage($"Test file not found: {testFile}", LogLevel.ERROR);
                return 1;
            }

            var startTime = DateTime.Now;
            string? htmlPath = CblParser.StartCblParse(
                testFile,
                show: false,
                outputFolder: outputFolder,
                tmpRootFolder: tmpRootFolder,
                srcRootFolder: srcRootFolder,
                clientSideRender: true,
                saveMmdFiles: true
            );
            var duration = DateTime.Now - startTime;

            Console.WriteLine($"\n{new string('=', 80)}");
            if (!string.IsNullOrEmpty(htmlPath) && File.Exists(htmlPath))
            {
                Console.WriteLine($"SUCCESS: HTML generated in {duration.TotalSeconds:F2}s");
                Console.WriteLine($"HTML Path: {htmlPath}");
                Console.WriteLine($"{new string('=', 80)}\n");
                return 0;
            }
            else
            {
                Console.WriteLine($"FAILED: HTML not generated");
                Console.WriteLine($"Duration: {duration.TotalSeconds:F2}s");
                Console.WriteLine($"{new string('=', 80)}\n");
                return 1;
            }
        }
        catch (Exception ex)
        {
            Logger.LogMessage($"Fatal error: {ex.Message}", LogLevel.FATAL, ex);
            Console.WriteLine($"Fatal error: {ex.Message}");
            Console.WriteLine(ex.ToString());
            return 1;
        }
    }
}
