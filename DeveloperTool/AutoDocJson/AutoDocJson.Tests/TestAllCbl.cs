using System;
using System.Collections.Generic;
using System.IO;
using System.Linq;
using System.Threading.Tasks;
using AutoDocNew.Core;
using AutoDocNew.Parsers;

namespace AutoDocNew.Tests;

/// <summary>
/// Test all 10 CBL files from the plan
/// </summary>
public class TestAllCbl
{
    public static async Task<int> RunAllTests(string[] args)
    {
        try
        {
            string optPath = Environment.GetEnvironmentVariable("OptPath") ?? "C:\\opt";
            string repoBase = Path.Combine(optPath, "data", "AutoDocJson", "tmp", "DedgeRepository");
            string outputFolder = Path.Combine(optPath, "Webs", "AutoDocJson");
            string tmpRootFolder = Path.Combine(optPath, "data", "AutoDocJson", "tmp");
            string srcRootFolder = Path.Combine(optPath, "data", "AutoDocJson", "tmp", "DedgeRepository");

            // Ensure folders exist
            Directory.CreateDirectory(outputFolder);
            Directory.CreateDirectory(Path.Combine(outputFolder, "_templates"));
            Directory.CreateDirectory(Path.Combine(outputFolder, "_css"));
            Directory.CreateDirectory(Path.Combine(outputFolder, "_js"));
            Directory.CreateDirectory(Path.Combine(outputFolder, "_images"));

            // Copy template and CSS if needed
            string templatePath = Path.Combine(outputFolder, "_templates", "cblmmdtemplate.html");
            if (!File.Exists(templatePath))
            {
                string sharedTemplate = Path.Combine(optPath, "src", "DedgePsh", "DevTools", "LegacyCodeTools", "AutoDoc", "_templates", "cblmmdtemplate.html");
                if (File.Exists(sharedTemplate))
                {
                    File.Copy(sharedTemplate, templatePath, true);
                }
            }

            string cssPath = Path.Combine(outputFolder, "_css", "autodoc-shared.css");
            if (!File.Exists(cssPath))
            {
                string sharedCss = Path.Combine(optPath, "src", "DedgePsh", "DevTools", "LegacyCodeTools", "AutoDoc", "_css", "autodoc-shared.css");
                if (File.Exists(sharedCss))
                {
                    File.Copy(sharedCss, cssPath, true);
                }
            }

            // Test files from plan
            var testFiles = new List<string>
            {
                Path.Combine(repoBase, "Dedge", "cbl", "BSAUTOS.CBL"),
                Path.Combine(repoBase, "Dedge", "cbl", "AABELMA.CBL"),
                Path.Combine(repoBase, "Dedge", "cbl", "AAAM005.CBL"),
                Path.Combine(repoBase, "Dedge", "cbl", "AAAKUN2.CBL"),
                Path.Combine(repoBase, "Dedge", "cbl", "AAAKUND.CBL"),
                Path.Combine(repoBase, "Dedge", "cbl", "AAAM024.CBL"),
                Path.Combine(repoBase, "Dedge", "cbl", "AAAM006.CBL"),
                Path.Combine(repoBase, "Dedge", "cbl", "AAAM046.CBL"),
                Path.Combine(repoBase, "Dedge", "cbl", "AAAKCSV.CBL"),
                Path.Combine(repoBase, "Dedge", "cbl", "AAADATO.CBL")
            };

            Logger.LogMessage($"Testing {testFiles.Count} CBL files", LogLevel.INFO);

            int successCount = 0;
            int failCount = 0;
            var results = new List<(string file, bool success, string? error)>();

            foreach (var testFile in testFiles)
            {
                string fileName = Path.GetFileName(testFile);
                Logger.LogMessage($"\n{new string('=', 80)}", LogLevel.INFO);
                Logger.LogMessage($"Testing: {fileName}", LogLevel.INFO);
                Logger.LogMessage($"{new string('=', 80)}", LogLevel.INFO);

                try
                {
                    if (!File.Exists(testFile))
                    {
                        Logger.LogMessage($"File not found: {testFile}", LogLevel.WARN);
                        results.Add((fileName, false, "File not found"));
                        failCount++;
                        continue;
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

                    if (!string.IsNullOrEmpty(htmlPath) && File.Exists(htmlPath))
                    {
                        Logger.LogMessage($"SUCCESS: {fileName} - Generated in {duration.TotalSeconds:F2}s", LogLevel.INFO);
                        results.Add((fileName, true, null));
                        successCount++;
                    }
                    else
                    {
                        Logger.LogMessage($"FAILED: {fileName} - HTML not generated", LogLevel.ERROR);
                        results.Add((fileName, false, "HTML not generated"));
                        failCount++;
                    }
                }
                catch (Exception ex)
                {
                    Logger.LogMessage($"FAILED: {fileName} - {ex.Message}", LogLevel.ERROR, ex);
                    results.Add((fileName, false, ex.Message));
                    failCount++;
                }
            }

            // Summary
            Console.WriteLine($"\n{new string('=', 80)}");
            Console.WriteLine($"CBL Test Summary: {successCount} succeeded, {failCount} failed out of {testFiles.Count}");
            Console.WriteLine($"{new string('=', 80)}");
            
            if (failCount > 0)
            {
                Console.WriteLine("\nFailed files:");
                foreach (var (file, success, error) in results.Where(r => !r.success))
                {
                    Console.WriteLine($"  - {file}: {error}");
                }
            }

            return failCount > 0 ? 1 : 0;
        }
        catch (Exception ex)
        {
            Logger.LogMessage($"Fatal error: {ex.Message}", LogLevel.FATAL, ex);
            Console.WriteLine($"Fatal error: {ex.Message}");
            return 1;
        }
    }
}
